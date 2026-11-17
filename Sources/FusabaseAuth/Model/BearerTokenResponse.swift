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
    Internal struct BearerTokenResponse containing bearer token metadata and
    response-scoped token values. Callers persist tokens after applying the
    rules for the authentication flow that produced them.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
struct BearerTokenResponse: Codable {
    // MARK: - Centralized token store
    private static let tokenStore: TokenStore = KeychainTokenStore.shared

    // MARK: - Public metadata (non-sensitive)
    var token_type: String?
    var expires_in: Int?

    // MARK: - Response-scoped token values
    private var stored_access_token: String?
    private var stored_refresh_token: String?
    private var refresh_token_is_response_scoped = false
    private var persistTokenMutations = false

    // MARK: - Computed properties backed by Keychain or stored values
    // Note: Accessors materialize short-lived Strings only when needed.

    var access_token: String {
        get {
            if let stored = stored_access_token {
                return stored
            }
            return Self.tokenStore.read(.access) ?? ""
        }
        set {
            stored_access_token = newValue
            if persistTokenMutations {
                Self.tokenStore.write(newValue, for: .access)
            }
        }
    }

    var refresh_token: String? {
        get {
            if refresh_token_is_response_scoped {
                return stored_refresh_token
            }
            if let stored = stored_refresh_token { return stored }
            return Self.tokenStore.read(.refresh)
        }
        set {
            stored_refresh_token = newValue
            if persistTokenMutations {
                Self.tokenStore.write(newValue, for: .refresh)
            }
        }
    }

    // MARK: - Custom initializer for programmatic creation (used by IDCSAuthHelper)
    // Persists tokens directly to the Keychain or stores in memory.
    init(
        access_token: String,
        token_type: String? = nil,
        expires_in: Int? = nil,
        refresh_token: String?,
        persistToKeychain: Bool = true
    ) {
        self.token_type = token_type
        self.expires_in = expires_in
        self.stored_access_token = access_token.isEmpty ? nil : access_token
        self.stored_refresh_token = refresh_token
        self.refresh_token_is_response_scoped = true
        self.persistTokenMutations = persistToKeychain

        // Persist sensitive values to Keychain immediately (if requested)
        if persistToKeychain {
            if !access_token.isEmpty { Self.tokenStore.write(access_token, for: .access) }
            Self.tokenStore.write(refresh_token, for: .refresh)
        } else {
            // Store tokens in memory for non-persistent instances
            self.stored_access_token = access_token.isEmpty ? nil : access_token
            self.stored_refresh_token = refresh_token
        }
    }

    /// Fresh authentication must never inherit a refresh token from another session.
    func requireRefreshTokenForSignIn() throws -> String {
        guard let refreshToken = refresh_token, !refreshToken.isEmpty else {
            throw AuthErrorUtilities.invalidCredential(message: "Authentication response is missing a refresh token.")
        }
        return refreshToken
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case access_token
        case token_type
        case expires_in
        case refresh_token
    }

    // Decode response-scoped token values without falling back to shared Keychain slots.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let accessToken = try container.decode(String.self, forKey: .access_token)
        guard !accessToken.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .access_token,
                in: container,
                debugDescription: "access_token must not be empty."
            )
        }

        token_type = try container.decodeIfPresent(String.self, forKey: .token_type)
        expires_in = try container.decodeIfPresent(Int.self, forKey: .expires_in)
        stored_access_token = accessToken
        stored_refresh_token = try container.decodeIfPresent(String.self, forKey: .refresh_token)
        refresh_token_is_response_scoped = true
        persistTokenMutations = false

    }

    // Custom encoding to output this response's token values.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(token_type, forKey: .token_type)
        try container.encodeIfPresent(expires_in, forKey: .expires_in)

        if !access_token.isEmpty {
            try container.encode(access_token, forKey: .access_token)
        }

        if let rt = refresh_token {
            try container.encode(rt, forKey: .refresh_token)
        }


    }

    /// Clears all sensitive data from persistent storage (Keychain).
    /// Call this method when the BearerTokenResponse is no longer needed.
    mutating func clearSensitiveData() {
        Self.tokenStore.delete(.access)
        Self.tokenStore.delete(.refresh)
    }
}
