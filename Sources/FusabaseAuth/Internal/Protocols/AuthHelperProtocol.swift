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
import AuthenticationServices


/**
    # protocol AuthHelperProtocol
    This internal protocol defines a common interface for the authentication types (OnPrem & IDCS).
    Additionally, it provides default implementations for functions that are exclusive to certain authentication types.
 
    ## Relevant Methods
    - `authenticateAndGetDetails() async throws`: Authenticates the user and provides AuthUserCompleteDetails object.
    - `createUserWithEmailAndPassword(email: String, password: String) async throws`: Creates a user within the project provided, utilizing the passed credentials.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
protocol AuthHelperProtocol {
    // internal helper utility methods
    func _getUserDetails(accessToken: String) throws -> AuthUserInterface
    func _getUserDetailsIDCS(accessToken: AuthTokenResult) async throws -> AuthUserInterface // requires async
    func reloadUser(_ user: FusabaseUser) async throws -> AuthUserInterface
    
    // sign-in with credentials helpers
    func signInWithRedirectHelper(providerID: String, callbackScheme: String) async throws -> AuthUserCompleteDetails
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, link: Bool) async throws -> AuthUserCompleteDetails
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> AuthUserCompleteDetails
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding, link: Bool) async throws -> AuthUserCompleteDetails
    func signInWithCredential(with credential: AuthCredential) async throws -> AuthUserCompleteDetails
    func signInWithCredentialLinking(credential: AuthCredential, link: Bool) async throws -> AuthUserCompleteDetails
    func socialUnlinkHelper(provider: String) async throws -> AuthUserCompleteDetails

    // sign-in helpers
    func authenticateAndGetDetails(email: String, password: String) async throws -> AuthUserCompleteDetails
    func authenticateUser(email: String, password: String) async throws -> AuthenticationDetails
    func authenticateUser(email: String, password: String) async throws -> AuthTokenResult
    
    // register helpers
    func createUserWithEmailAndPassword(email: String, password: String) async throws -> AuthUserCompleteDetails?
    
    // send password reset helper
    func sendPasswordResetHelper(withEmail: String) async throws
    
    // verify/confirm password reset - OnPrem (code) and IDCS (token)
    func verifyPasswordResetCodeHelper(code: String) async throws -> [String: Any]
    func confirmPasswordResetHelper(code: String, newPassword: String) async throws -> [String: Any]
    
    // sign out helper
    func performSignOut(refreshToken: String) async throws
}

/**
    # extension AuthHelperProtocol
    Provides default implementations for functions that are exclusive to certain classes.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
extension AuthHelperProtocol {
    func authenticateUser(email: String, password: String) async throws -> AuthenticationDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for your authentication type.")
    }
    
    func authenticateUser(email: String, password: String) async throws -> AuthTokenResult {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for your authentication type.")
    }
    
    func _getUserDetails(accessToken: String) throws -> AuthUserInterface {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for your authentication type.")
    }
    
    func _getUserDetailsIDCS(accessToken: AuthTokenResult) async throws -> AuthUserInterface {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for your authentication type.")
    }
    
    func signInWithCredential(with credential: AuthCredential) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for IDCS.")
    }
    
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for IDCS.")
    }
    
    func signInWithRedirectHelper(providerID: String, callbackScheme: String) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for IDCS.")
    }

    // Default implementations for the link-aware overloads added to the protocol.
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, link: Bool) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for IDCS.")
    }

    func signInWithRedirectHelper(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding, link: Bool) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for IDCS.")
    }

    func signInWithCredentialLinking(credential: AuthCredential, link: Bool) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for your authentication type.")
    }

    func socialUnlinkHelper(provider: String) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "Method not supported for your authentication type.")
    }
    
    // Default implementations for password reset verification/confirmation.
    // Conforming helpers (OnPrem/IDCS) override the variant that applies to them.
    func verifyPasswordResetCodeHelper(code: String) async throws -> [String: Any] {
        throw AuthErrorUtilities.operationNotAllowed(message: "Password reset verification not supported for your authentication type.")
    }
    
    func verifyPasswordResetCodeHelper(token: String) async throws -> [String: Any] {
        throw AuthErrorUtilities.operationNotAllowed(message: "Password reset verification not supported for your authentication type.")
    }
    
    func confirmPasswordResetHelper(code: String, newPassword: String) async throws -> [String: Any] {
        throw AuthErrorUtilities.operationNotAllowed(message: "Password reset confirmation not supported for your authentication type.")
    }
    
    func confirmPasswordResetHelper(token: String, newPassword: String) async throws -> [String: Any] {
        throw AuthErrorUtilities.operationNotAllowed(message: "Password reset confirmation not supported for your authentication type.")
    }

}
