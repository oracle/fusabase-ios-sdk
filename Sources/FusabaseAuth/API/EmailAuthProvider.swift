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
 Provides authentication using email and password, conforming to `AuthProvider`.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class EmailAuthProvider: NSObject, AuthProvider {
    
    /// ID Constant for compliance.
    let EmailAuthProviderID: String = "EPW"
    /// ID Constant for compliance.
    let EmailLinkAuthSignInMethod: String = "EPWL"
    /// ID Constant for compliance.
    let EmailPasswordAuthSignInMethod: String = "EPW"
    /// The ID of this provider.
    public var providerID: String = "email"
    /// Constant for email link sign-in method.
    let EMAIL_LINK_SIGN_IN_METHOD: String = "email/link"
    /// Constant for email/password sign-in method.
    let EMAIL_PASSWORD_SIGN_IN_METHOD: String = "email/password"
    
    /// The ID string for email/password authentication.
    ///
    /// Note: Must match backend/Android method identifier (epw).
    public static let id: String = "epw"
    
    /// Initializes the EmailAuthProvider.
    public override init() {
        super.init()
    }
    
    /// Creates an `AuthCredential` for email and password authentication.
    ///
    /// - Parameters:
    ///   - email: The user's email address.
    ///   - password: The user's password.
    /// - Returns: An `AuthCredential` object.
    ///
    /// Note: Password might not be needed in some implementations.
    open class func credential(email: String, password: String) -> AuthCredential {
        return EmailAuthCredential(withEmail: email, password: password)
    }
    
}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/// A credential for email-based authentication, either with password or link.
class EmailAuthCredential: AuthCredential {

    /// The email address associated with the credential.
    let email: String

    // enum to classify based on either password or link
    /// Enum representing the type of email authentication (password or link).
    enum EmailType {
        /// Case for password-based authentication (securely stored).
        case password([Character])
        /// Case for link-based authentication.
        case link(String)

        /// Returns the password as a String if this is a password case.
        var passwordValue: String? {
            switch self {
            case .password(let chars): return String(chars)
            case .link: return nil
            }
        }

        /// Returns the link as a String if this is a link case.
        var linkValue: String? {
            switch self {
            case .password: return nil
            case .link(let link): return link
            }
        }

        /// Clears sensitive data from the enum.
        mutating func clearSensitiveData() {
            switch self {
            case .password(var chars):
                // Zero out each character to securely erase from memory
                for i in 0..<chars.count {
                    chars[i] = "\0"
                }
                self = .password([])
            case .link:
                // Links are not considered sensitive data
                break
            }
        }
    }

    /// The type of email authentication.
    let emailType: EmailType

    /// Initializes with email and password.
    ///
    /// - Parameters:
    ///   - email: The email address.
    ///   - password: The password.
    init(withEmail email: String, password: String) {
        self.email = email
        emailType = .password(Array(password))
        super.init(provider: EmailAuthProvider.id)
    }

    /// Initializes with email and link.
    ///
    /// - Parameters:
    ///   - email: The email address.
    ///   - link: The authentication link.
    init(withEmail email: String, link: String) {
        self.email = email
        emailType = .link(link)
        super.init(provider: EmailAuthProvider.id)
    }

    /// Automatically clears sensitive data when the credential goes out of scope.
    deinit {
        // Create a mutable copy to clear sensitive data
        var mutableType = emailType
        mutableType.clearSensitiveData()
    }
}
