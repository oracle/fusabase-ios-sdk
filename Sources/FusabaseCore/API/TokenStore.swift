// Copyright (c) 2015, 2025, Oracle and/or its affiliates.

//-----------------------------------------------------------------------------
//
// This software is dual-licensed to you under the Universal Permissive License
// (UPL) 1.0 as shown at https://oss.oracle.com/licenses/upl and Apache License
// 2.0 as shown at http://www.apache.org/licenses/LICENSE-2.0. You may choose
// either license.
//
// If you elect to accept the software under the Apache License, Version 2.0,
// the following applies:
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-----------------------------------------------------------------------------

import Foundation

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
package enum TokenKey: String, CaseIterable {
    // Core auth tokens
    case access = "ACCESS_TOKEN"
    case refresh = "REFRESH_TOKEN"

    // IDCS-specific tokens
    case authn = "AUTHN_TOKEN"
    case authnRefresh = "AUTHN_REFRESH_TOKEN"
    case idcsAccess = "IDCS_ACCESS_TOKEN"
    case idcsRefresh = "IDCS_REFRESH_TOKEN"
    case idcsBearer = "IDCS_BEARER_TOKEN"

    // Other persisted values used across the SDK
    case codeVerifier = "CODE_VERIFIER"
    case userEmail = "USER_EMAIL"
    case userPassword = "USER_PASSWORD"
    case linking = "LINKING_STATE"
}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
package protocol TokenStore {
    /// Write a value to secure storage; nil or empty will delete the entry
    func write(_ value: String?, for key: TokenKey)

    /// Read a value from secure storage; returns nil when not present
    func read(_ key: TokenKey) -> String?

    /// Delete an entry from secure storage
    func delete(_ key: TokenKey)
}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
package struct KeychainTokenStore: TokenStore {
    public static let shared = KeychainTokenStore()

    private init() {}

    public func write(_ value: String?, for key: TokenKey) {
        guard let v = value, !v.isEmpty else {
            PersistenceUtils.deleteItem(forKey: key.rawValue)
            return
        }
        PersistenceUtils.saveItem(v, forKey: key.rawValue)
    }

    /// Replace the current authentication token pair without retaining a token
    /// from a previous sign-in when the new response omits a refresh token.
    public func replaceAuthTokens(accessToken: String, refreshToken: String?) {
        delete(.access)
        delete(.refresh)
        write(accessToken, for: .access)
        write(refreshToken, for: .refresh)
    }

    public func read(_ key: TokenKey) -> String? {
        let v = PersistenceUtils.loadItem(forKey: key.rawValue)
        return v.isEmpty ? nil : v
    }

    public func delete(_ key: TokenKey) {
        PersistenceUtils.deleteItem(forKey: key.rawValue)
    }

    /// Securely execute an operation with a token, clearing memory immediately after use
    public func withSecureToken<T>(_ key: TokenKey, _ operation: (String) -> T) -> T? {
        guard let token = read(key) else { return nil }

        // Execute operation with token
        let result = operation(token)

        // Immediately clear token from memory
        secureClearString(token)

        return result
    }

    /// Securely execute an operation with a token (no return value), clearing memory immediately after use
    public func withSecureToken(_ key: TokenKey, _ operation: (String) -> Void) {
        guard let token = read(key) else { return }

        // Execute operation with token
        operation(token)

        // Immediately clear token from memory
        secureClearString(token)
    }
}

package func secureClearString(_ string: String) {
    
    _ = string // Mark as used to avoid warnings
}
