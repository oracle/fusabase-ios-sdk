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
/**
 A credential for OAuth-based authentication, including access token and secret.
 */
open class OAuthCredential: AuthCredential {
    /// The OAuth access token (securely stored).
    private var accessTokenChars: [Character]?
    /// The OAuth secret (securely stored).
    private var secretChars: [Character]?

    /// The OAuth access token.
    public var accessToken: String? {
        return accessTokenChars.map { String($0) }
    }

    /// The OAuth secret, if applicable.
    public var secret: String? {
        return secretChars.map { String($0) }
    }

    /// Initializes an `OAuthCredential`.
    ///
    /// - Parameters:
    ///   - idToken: The ID token.
    ///   - accessToken: The access token.
    ///   - secret: The secret.
    ///   - provider: The provider ID.
    init(idToken: String? = nil, accessToken: String?, secret: String? = nil, provider: String) {
        self.accessTokenChars = accessToken.map { Array($0) }
        self.secretChars = secret.map { Array($0) }
        super.init(provider: provider, idToken: idToken)
    }

    /// Automatically clears sensitive data when the credential goes out of scope.
    deinit {
        clearSensitiveData()
    }

    /// Clears sensitive data from memory to prevent heap dump attacks.
    private func clearSensitiveData() {
        clearAccessToken()
        clearSecret()
    }

    private func clearAccessToken() {
        if let chars = accessTokenChars {
            // Zero out each character to securely erase from memory
            for i in 0..<chars.count {
                accessTokenChars![i] = "\0"
            }
            accessTokenChars = nil
        }
    }

    private func clearSecret() {
        if let chars = secretChars {
            // Zero out each character to securely erase from memory
            for i in 0..<chars.count {
                secretChars![i] = "\0"
            }
            secretChars = nil
        }
    }
}
