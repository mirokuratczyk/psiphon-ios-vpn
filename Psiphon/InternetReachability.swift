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

@objc enum ReachabilityStatus: Int {
    case notReachable
    case viaWiFi
    case viaWWAN
}

/// Represents reachability status flags coded into a string.
struct ReachabilityCodedStatus: ExpressibleByStringLiteral, Hashable, Codable,
CustomStringConvertible {
    typealias StringLiteralType = String
    
    private let value: String
    
    init(stringLiteral value: String) {
        self.value = value
    }
    
    var description: String {
        self.value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.value)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(stringLiteral: try container.decode(String.self))
    }
}

enum ReachabilityAction {
    case reachabilityStatus(ReachabilityStatus, ReachabilityCodedStatus)
}

struct ReachabilityState: Equatable {
    var networkStatus: ReachabilityStatus = .notReachable
    var codedStatus: ReachabilityCodedStatus = ""
}

func internetReachabilityReducer(
    state: inout ReachabilityState, action: ReachabilityAction, environment: ()
) -> [Effect<ReachabilityAction>] {
    switch action {
    case let .reachabilityStatus(updatedStatus, updatedCodedStatus):
        state.networkStatus = updatedStatus
        state.codedStatus = updatedCodedStatus
        return []
    }
}

protocol InternetReachability {
    
    func currentStatus() -> ReachabilityStatus
    
    func currentReachabilityFlags() -> ReachabilityCodedStatus
    
}

extension InternetReachability {
    
    var isCurrentlyReachable: Bool {
        let status = self.currentStatus()
        switch status {
        case .notReachable: return false
        case .viaWiFi: return true
        case .viaWWAN: return true
        }
    }
    
}
