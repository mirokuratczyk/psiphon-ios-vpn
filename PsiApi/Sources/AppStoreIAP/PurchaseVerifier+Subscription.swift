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
import Promises
import ReactiveSwift
import PsiApi

extension PurchaseVerifierServer {

    fileprivate static func subscriptionUrl() -> URL {
        if Debugging.devServers {
            return PurchaseVerifierURLs.devSubscriptionVerify
        } else {
            return PurchaseVerifierURLs.subscriptionVerify
        }
    }
    
    static func subscription (
        requestBody: SubscriptionValidationRequest,
        clientMetaData: ClientMetaData
    ) -> (error: NestedScopedError<ErrorRepr>?,
        request: HTTPRequest<SubscriptionValidationResponse>) {
            do {
                let encoder = JSONEncoder.makeRfc3339Encoder()
                let jsonData = try encoder.encode(requestBody)
                return PurchaseVerifierServer.req(url: PurchaseVerifierServer.subscriptionUrl(),
                                                  jsonData: jsonData,
                                                  clientMetaData: clientMetaData)
            } catch {
                fatalError("failed to create request '\(error)'")
            }
    }
}
