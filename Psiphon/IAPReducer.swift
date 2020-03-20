/*
 * Copyright (c) 2020, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import ReactiveSwift
import Promises

enum IAPAction {
    case purchase(IAPPurchasableProduct)
    case purchaseAdded(PurchaseAddedResult)
    case verifiedPsiCashConsumable(VerifiedPsiCashConsumableTransaction)
    case transactionUpdate(TransactionUpdate)
    case receiptUpdated
}

/// StoreKit transaction obersver
enum TransactionUpdate {
    case updatedTransactions([SKPaymentTransaction])
    case restoredCompletedTransactions(error: Error?)
}

struct IAPReducerState {
    var iap: IAPState
    var psiCashBalance: PsiCashBalance
    let psiCashAuth: PsiCashAuthPackage
    let receiptData: ReceiptData?
}

func iapReducer(state: inout IAPReducerState, action: IAPAction) -> [Effect<IAPAction>] {
    switch action {
    case .purchase(let product):
        guard state.iap.purchasing.completed else {
            return []
        }
        
        if case .psiCash = product {
            // No action is taken if there is already an unverified PsiCash transaction.
            guard state.iap.unverifiedPsiCashTx == nil else {
                return []
            }
            
            // PsiCash IAP requires presence of PsiCash spender token.
            guard state.psiCashAuth.hasMinimalTokens else {
                state.iap.purchasing = .error(ErrorEvent(
                    .failedToCreatePurchase(reason: "PsiCash data not present.")
                ))
                return []
            }
        }
    
        state.iap.purchasing = .pending(product)

        return [
            Current.paymentQueue.addPurchase(product)
                .map(IAPAction.purchaseAdded)
        ]
        
    case .purchaseAdded(let result):
        switch result {
        case .success(_):
            return []
            
        case .failure(let errorEvent):
            state.iap.purchasing = .error(errorEvent)
            return []
        }
        
    case .receiptUpdated:
        guard let receiptData = state.receiptData else {
            return []
        }
        guard case let .pendingVerification(unverifiedTx) = state.iap.unverifiedPsiCashTx else {
            return []
        }
        return [
            verifyConsumable(transaction: unverifiedTx, receipt: receiptData)
                .map(IAPAction.verifiedPsiCashConsumable)
        ]
        
    case .verifiedPsiCashConsumable(let verifiedTx):
        guard case let .pendingVerificationResult(pendingTx) = state.iap.unverifiedPsiCashTx else {
            fatalError("there is no unverified IAP transaction '\(verifiedTx)'")
        }
        guard verifiedTx.value == pendingTx.value else {
            fatalError("""
                transactions are not equal '\(verifiedTx)' != '\(pendingTx)'
                """)
        }
        state.iap.unverifiedPsiCashTx = .none
        return [
            Current.paymentQueue.finishTransaction(verifiedTx.value).mapNever(),
            .fireAndForget {
                Current.app.store.send(.psiCash(.refreshPsiCashState))
            },
            .fireAndForget {
                PsiFeedbackLogger.info(withType: "IAP",
                                       json: ["event": "verified psicash consumable"])
            }
        ]
        
    case .transactionUpdate(let value):
        switch value {
        case .restoredCompletedTransactions:
            return [
                .fireAndForget {
                    Current.app.store.send(.appReceipt(.receiptRefreshed(.success(()))))
                }
            ]
            
        case .updatedTransactions(let transactions):
            var effects = [Effect<IAPAction>]()
            
            for transaction in transactions {
                switch transaction.typedTransactionState {
                case .pending(_):
                    return []
                    
                case .completed(let completedState):
                    let finishTransaction: Bool
                    let purchasingState: IAPPurchasingState
                    
                    switch completedState {
                    case let .failure(skError):
                        purchasingState = .error(ErrorEvent(.storeKitError(skError)))
                        finishTransaction = true
                        
                    case let .success(success):
                        purchasingState = .none
                        switch success {
                        case .purchased:
                            switch try? AppStoreProductType.from(transaction: transaction) {
                            case .none:
                                fatalError("unknown product \(String(describing: transaction))")
                                
                            case .psiCash:
                                switch state.iap.unverifiedPsiCashTx?.transaction
                                    .isEqualTransactionId(to: transaction) {
                                case .none:
                                    // There is no unverified psicash IAP transaction.
                                    
                                    // Updates balance state to reflect expected increase
                                    // in PsiCash balance.
                                    state.psiCashBalance.waitingForExpectedIncrease(
                                        withAddedReward: .zero()
                                    )
                                    let unverifiedTx =
                                        UnverifiedPsiCashConsumableTransaction(value: transaction)
                                    finishTransaction = false
                                    
                                    if let receiptData = state.receiptData {
                                        state.iap.unverifiedPsiCashTx =
                                            .pendingVerificationResult(unverifiedTx)
                                        
                                        effects.append(
                                            verifyConsumable(transaction: unverifiedTx,
                                                             receipt: receiptData)
                                                .map(IAPAction.verifiedPsiCashConsumable)
                                        )
                                    } else {
                                        // Does a receipt refresh if there is no valid
                                        // App Store receipt.
                                        
                                        state.iap.unverifiedPsiCashTx =
                                            .pendingVerification(unverifiedTx)
                                        
                                        effects.append(
                                            .fireAndForget {
                                                Current.app.store.send(
                                                    .appReceipt(
                                                        .refreshReceipt(optinalPromise: nil))
                                                )
                                            }
                                        )
                                    }
                                    
                                case .some(true):
                                    // Tranaction has the same identifier as the current
                                    // unverified psicash IAP transaction.
                                    finishTransaction = true
                                    
                                case .some(false):
                                    // Unexpected presence of two consumable transactions
                                    // with different transaction ids.
                                    let unverifiedTxId = state.iap.unverifiedPsiCashTx!
                                    .transaction.value.transactionIdentifier ?? "(none)"
                                    let newTxId = transaction.transactionIdentifier ?? "(none)"
                                    fatalError("""
                                    cannot have two completed but unverified consumable purchases: \
                                        unverified transaction: '\(unverifiedTxId)', \
                                        new transaction: '\(newTxId)'
                                    """)
                                }

                                
                            case .subscription:
                                finishTransaction = true
                            }
                            
                        case .restored :
                            finishTransaction = true
                        }
                    }
                    
                    // Updates purchasing state
                    state.iap.purchasing = purchasingState
                    
                    if finishTransaction {
                        effects.append(
                            Current.paymentQueue.finishTransaction(transaction).mapNever()
                        )
                    }
                    
                    if transactions.appReceiptUpdated {
                        effects.append(
                            .fireAndForget {
                                Current.app.store.send(.appReceipt(.receiptRefreshed(.success(()))))
                            }
                        )
                    }
                }
            }
            
            return effects
        }
    }
}

/// Delegate for StoreKit transactions.
/// - Note: There is no callback from StoreKit if purchasing a product that is already
/// purchased.
class PaymentTransactionDelegate: StoreDelegate<TransactionUpdate>,
SKPaymentTransactionObserver {
    
    // Sent when transactions are removed from the queue (via finishTransaction:).
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions
        transactions: [SKPaymentTransaction]) {
        // Ignore.
    }
    
    // Sent when an error is encountered while adding transactions
    // from the user's purchase history back to the queue.
    func paymentQueue(_ queue: SKPaymentQueue,
                      restoreCompletedTransactionsFailedWithError error: Error) {
        sendOnMain(.restoredCompletedTransactions(error: error))
    }
    
    // Sent when all transactions from the user's purchase history have
    // successfully been added back to the queue.
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        sendOnMain(.restoredCompletedTransactions(error: .none))
    }
    
    // Sent when a user initiates an IAP buy from the App Store
    @available(iOS 11.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment,
                      for product: SKProduct) -> Bool {
        return false
    }
    
    // Sent when the transaction array has changed (additions or state changes).
    // Client should check state of transactions and finish as appropriate.
    func paymentQueue(_ queue: SKPaymentQueue,
                      updatedTransactions transactions: [SKPaymentTransaction]) {
        sendOnMain(.updatedTransactions(transactions))
    }
    
    @available(iOS 13.0, *)
    func paymentQueueDidChangeStorefront(_ queue: SKPaymentQueue) {
        // Do nothing.
    }
    
}
