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

/**
 Represents a credential used for authentication, containing provider information and optionally an ID token.
 */
open class AuthCredential {
    /// The ID of the authentication provider.
    public let provider: String
    /// The ID token associated with the credential, stored as a clearable character array.
    private var idTokenChars: [Character]?

    /// Initializes an `AuthCredential` with the specified provider and optional ID token.
    ///
    /// - Parameters:
    ///   - provider: The provider ID.
    ///   - idToken: The ID token, if any.
    init(provider: String, idToken: String? = nil) {
        self.provider = provider
        if let token = idToken {
            // Store as character array for secure clearing capability
            self.idTokenChars = Array(token)
        }
    }

    /// Retrieves the ID token for the credential.
    ///
    /// This is an Fusabase exclusive method.
    ///
    /// - Returns: The ID token.
    /// - Throws: An error if no ID token is available.
    func getIdToken() throws -> String {
        guard let chars = idTokenChars else {
            throw AuthErrorUtilities.invalidCredential(message: "No ID token for the provided credential.")
        }
        return String(chars)
    }

    /// Automatically clears sensitive data when the credential goes out of scope.
    deinit {
        clearSensitiveData()
    }

    /// Clears sensitive data from memory to prevent heap dump attacks.
    private func clearSensitiveData() {
        if let chars = idTokenChars {
            // Zero out each character to securely erase from memory
            for i in 0..<chars.count {
                idTokenChars![i] = "\0"
            }
            idTokenChars = nil
        }
    }
}
