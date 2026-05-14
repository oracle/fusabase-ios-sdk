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
import FusabaseCore

/**
 A data class representing the result of an authentication token, including the JWT string and related properties like expiration and claims.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class AuthTokenResult {
    /// The parsed JWT from the token.
    private var parsedJwt: AuthUserFromJWT
    /// Keychain slot this token should be read from.
    private let tokenKey: TokenKey
    /// Stored token for non-persistent instances.
    private var storedToken: String?
    
    /// The date when the token expires.
    open var expirationDate: Date
    /// The date when the authentication occurred.
    open var authDate: Date
    /// The date when the token was issued.
    open var issuedAtDate: Date
    /// The provider used for sign-in.
    open var signInProvider: String
    /// A dictionary of claims from the JWT.
    open var claims: [String: Any]
    /// The raw token string (read on-demand from Keychain or stored value).
    open var token: String {
        if let stored = storedToken {
            return stored
        }
        return KeychainTokenStore.shared.read(self.tokenKey) ?? ""
    }
    
    /// Initializes an `AuthTokenResult` by parsing the given token.
    ///
    /// - Parameters:
    ///   - token: The JWT token string.
    ///   - provider: The sign-in provider (default is "password").
    ///   - authType: The authentication type (default is "basic").
    /// - Throws: An error if the token cannot be decoded.
    init(token: String, provider: String = "password", _ authType: String? = "basic", tokenKey: TokenKey = .access) throws {

        self.parsedJwt = try AuthUtils.decode(jwtToken: token, authType)
        self.tokenKey = tokenKey
        KeychainTokenStore.shared.write(token, for: tokenKey)

        self.expirationDate = Date(timeIntervalSince1970: self.parsedJwt.exp)
        self.issuedAtDate = Date(timeIntervalSince1970: self.parsedJwt.iat)
        self.authDate = Date(timeIntervalSince1970: self.parsedJwt.iat)

        self.signInProvider = provider
        self.claims = ["-": "-"] // Stores the entire payload of claims found on the ID token.

    }

    /// Initializes an `AuthTokenResult` with a raw token string without parsing.
    /// This is used for linking flows where JWT parsing is not needed.
    ///
    /// - Parameters:
    ///   - rawToken: The raw JWT token string.
    ///   - tokenKey: The keychain slot for this token.
    ///   - persist: Whether to persist the token to keychain (default true).
    init(rawToken: String, tokenKey: TokenKey = .access, persist: Bool = true) {
        // Create a dummy parsed JWT since the struct requires it
        self.parsedJwt = AuthUserFromJWT(
            user_displayname: "",
            user_id: "",
            iss: "",
            idp_name: "",
            creation_time: "",
            sub: "",
            iat: 0.0,
            idp_type: "",
            aud: "",
            email_verified: "",
            scope: "",
            exp: 0.0
        )
        self.tokenKey = tokenKey
        if persist {
            KeychainTokenStore.shared.write(rawToken, for: tokenKey)
        } else {
            // Store the token internally for non-persistent instances
            self.storedToken = rawToken
        }

        // Set default/placeholder values for parsed properties
        self.expirationDate = Date.distantFuture
        self.issuedAtDate = Date()
        self.authDate = Date()

        self.signInProvider = "password"
        self.claims = ["-": "-"]
    }
    
    /// Validates if the access token is still valid (not expired).
    ///
    /// - Returns: `true` if the token is valid, `false` otherwise.
    func _validateAccessToken() -> Bool {
        return expirationDate > Date()
    }
}
