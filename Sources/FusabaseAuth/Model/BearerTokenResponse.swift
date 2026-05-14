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
    Internal struct BearerTokenResponse that contains bearer token metadata and
    persists sensitive fields directly to the Keychain via PersistenceUtils.
    This minimizes keeping tokens in memory by-value or by-reference.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
struct BearerTokenResponse: Codable {
    // MARK: - Centralized token store
    private static let tokenStore: TokenStore = KeychainTokenStore.shared

    // MARK: - Public metadata (non-sensitive)
    var token_type: String
    var expires_in: Int

    // MARK: - Stored tokens for non-persistent instances
    private var stored_access_token: String?
    private var stored_refresh_token: String?
    private var stored_authn_token: String?
    private var stored_authn_refresh_token: String?
    private var stored_idcs_access_token: String?
    private var stored_idcs_refresh_token: String?

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
            if stored_access_token != nil {
                stored_access_token = newValue
            } else {
                Self.tokenStore.write(newValue, for: .access)
            }
        }
    }

    var refresh_token: String? {
        get {
            if let stored = stored_refresh_token {
                return stored
            }
            return Self.tokenStore.read(.refresh)
        }
        set {
            if stored_refresh_token != nil {
                stored_refresh_token = newValue
            } else {
                Self.tokenStore.write(newValue, for: .refresh)
            }
        }
    }

    // IDCS-specific fields
    var authn_token: String? {
        get {
            if let stored = stored_authn_token {
                return stored
            }
            return Self.tokenStore.read(.authn)
        }
        set {
            if stored_authn_token != nil {
                stored_authn_token = newValue
            } else {
                Self.tokenStore.write(newValue, for: .authn)
            }
        }
    }

    var authn_refresh_token: String? {
        get {
            if let stored = stored_authn_refresh_token {
                return stored
            }
            return Self.tokenStore.read(.authnRefresh)
        }
        set {
            if stored_authn_refresh_token != nil {
                stored_authn_refresh_token = newValue
            } else {
                Self.tokenStore.write(newValue, for: .authnRefresh)
            }
        }
    }

    var idcs_access_token: String? {
        get {
            if let stored = stored_idcs_access_token {
                return stored
            }
            return Self.tokenStore.read(.idcsAccess)
        }
        set {
            if stored_idcs_access_token != nil {
                stored_idcs_access_token = newValue
            } else {
                Self.tokenStore.write(newValue, for: .idcsAccess)
            }
        }
    }

    var idcs_refresh_token: String? {
        get {
            if let stored = stored_idcs_refresh_token {
                return stored
            }
            return Self.tokenStore.read(.idcsRefresh)
        }
        set {
            if stored_idcs_refresh_token != nil {
                stored_idcs_refresh_token = newValue
            } else {
                Self.tokenStore.write(newValue, for: .idcsRefresh)
            }
        }
    }

    // MARK: - Custom initializer for programmatic creation (used by IDCSAuthHelper)
    // Persists tokens directly to the Keychain or stores in memory.
    init(
        access_token: String,
        token_type: String,
        expires_in: Int,
        refresh_token: String?,
        authn_token: String?,
        authn_refresh_token: String?,
        idcs_access_token: String?,
        idcs_refresh_token: String?,
        persistToKeychain: Bool = true
    ) {
        self.token_type = token_type
        self.expires_in = expires_in

        // Persist sensitive values to Keychain immediately (if requested)
        if persistToKeychain {
            if !access_token.isEmpty { Self.tokenStore.write(access_token, for: .access) }
            Self.tokenStore.write(refresh_token, for: .refresh)
            Self.tokenStore.write(authn_token, for: .authn)
            Self.tokenStore.write(authn_refresh_token, for: .authnRefresh)
            Self.tokenStore.write(idcs_access_token, for: .idcsAccess)
            Self.tokenStore.write(idcs_refresh_token, for: .idcsRefresh)
        } else {
            // Store tokens in memory for non-persistent instances
            self.stored_access_token = access_token.isEmpty ? nil : access_token
            self.stored_refresh_token = refresh_token
            self.stored_authn_token = authn_token
            self.stored_authn_refresh_token = authn_refresh_token
            self.stored_idcs_access_token = idcs_access_token
            self.stored_idcs_refresh_token = idcs_refresh_token
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case access_token
        case token_type
        case expires_in
        case refresh_token
        case authn_token
        case authn_refresh_token
        case idcs_access_token
        case idcs_refresh_token
    }

    // Custom decoding to persist sensitive values to Keychain
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        token_type = try container.decode(String.self, forKey: .token_type)
        expires_in = try container.decode(Int.self, forKey: .expires_in)

        if let v = try container.decodeIfPresent(String.self, forKey: .access_token) {
            Self.tokenStore.write(v, for: .access)
        }
        if let v = try container.decodeIfPresent(String.self, forKey: .refresh_token) {
            Self.tokenStore.write(v, for: .refresh)
        }
        if let v = try container.decodeIfPresent(String.self, forKey: .authn_token) {
            Self.tokenStore.write(v, for: .authn)
        }
        if let v = try container.decodeIfPresent(String.self, forKey: .authn_refresh_token) {
            Self.tokenStore.write(v, for: .authnRefresh)
        }
        if let v = try container.decodeIfPresent(String.self, forKey: .idcs_access_token) {
            Self.tokenStore.write(v, for: .idcsAccess)
        }
        if let v = try container.decodeIfPresent(String.self, forKey: .idcs_refresh_token) {
            Self.tokenStore.write(v, for: .idcsRefresh)
        }
    }

    // Custom encoding to output original JSON structure
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(token_type, forKey: .token_type)
        try container.encode(expires_in, forKey: .expires_in)

        // Rehydrate from Keychain when encoding
        if let at = Self.tokenStore.read(.access) {
            try container.encode(at, forKey: .access_token)
        }

        if let rt = Self.tokenStore.read(.refresh) {
            try container.encode(rt, forKey: .refresh_token)
        }

        if let an = Self.tokenStore.read(.authn) {
            try container.encode(an, forKey: .authn_token)
        }

        if let anr = Self.tokenStore.read(.authnRefresh) {
            try container.encode(anr, forKey: .authn_refresh_token)
        }

        if let ia = Self.tokenStore.read(.idcsAccess) {
            try container.encode(ia, forKey: .idcs_access_token)
        }

        if let ir = Self.tokenStore.read(.idcsRefresh) {
            try container.encode(ir, forKey: .idcs_refresh_token)
        }
    }

    /// Clears all sensitive data from persistent storage (Keychain).
    /// Call this method when the BearerTokenResponse is no longer needed.
    mutating func clearSensitiveData() {
        Self.tokenStore.delete(.access)
        Self.tokenStore.delete(.refresh)
        Self.tokenStore.delete(.authn)
        Self.tokenStore.delete(.authnRefresh)
        Self.tokenStore.delete(.idcsAccess)
        Self.tokenStore.delete(.idcsRefresh)
    }
}
