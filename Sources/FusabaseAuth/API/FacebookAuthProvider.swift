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


import AuthenticationServices
import FusabaseCore

/**
 Provides authentication using Facebook, conforming to `AuthProvider` and `FederatedAuthProvider`.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class FacebookAuthProvider: NSObject, AuthProvider, FederatedAuthProvider {

    /// ID Constant for compliance.
    let FacebookAuthProviderID: String = "facebook"
    /// ID Constant for compliance.
    let FacebookAuthSignInMethod: String = "facebook"
    /// The ID string for Facebook authentication.
    public static let id: String = "facebook"
    /// The provider ID.
    public var providerID: String = "facebook"
    /// The associated authentication instance.
    private let auth: FusabaseAuth
    /// The callback scheme for handling authentication responses.
    private let callbackScheme: String

    /// Initializes the FacebookAuthProvider.
    ///
    /// - Parameter auth: Auth instance associated with the object (defaults to default auth if nil).
    public init(auth: FusabaseAuth? = nil) {
        if auth == nil {
            self.auth = FusabaseAuth.auth()
        } else {
            self.auth = auth!
        }
        self.callbackScheme = "baasmobile" + FusabaseAuth.auth().config!.appId.lowercased()
        super.init()
    }


    /// Creates an `AuthCredential` for Facebook authentication using an access token.
    ///
    /// - Parameter accessToken: The Facebook access token.
    /// - Returns: An `AuthCredential` object.
    open class func credential(withAccessToken accessToken: String) -> AuthCredential {
        return FacebookAuthCredential(withAccessToken: accessToken)
    }

    /// Retrieves a credential by performing the OAuth sign-in flow.
    ///
    /// This method performs the complete OAuth authentication flow and returns the resulting credential.
    /// The user will be signed in as part of this process.
    ///
    /// - Returns: An `AuthCredential` from the completed OAuth flow.
    /// - Throws: An error if the OAuth flow fails.
    public func credential() async throws -> AuthCredential {
        #if canImport(UIKit)
        let userCredential = try await getCredentialWith()
        return userCredential.credential
        #else
        throw AuthErrorUtilities.operationNotAllowed(message: "OAuth sign-in requires a presentation context which is not available on this platform.")
        #endif
    }

    /// Performs the OAuth sign-in flow for Facebook and returns a fully populated UserCredential.
    ///
    /// This method:
    /// - Launches a system web authentication session for Facebook
    /// - Exchanges the resulting tokens for user details
    /// - Creates and sets the current user in FusabaseAuth (tokens are persisted)
    /// - Builds a FacebookAuthCredential and returns UserCredential
    ///
    /// Important:
    /// - After calling this method, you do NOT need to call FusabaseAuth.signIn(with: AuthCredential).
    ///   The user is already signed in and tokens are stored.
    ///
    /// - Parameter presentationContext: Optional ASWebAuthentication presentation context for UI control.
    /// - Returns: UserCredential for the signed-in user.
    /// - Throws: Error if the flow fails at any step.
    open func getCredentialWith(presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> UserCredential {
        // Acquire user details via redirect (tokens persisted to Keychain)
        let details = try await self.auth._authHelper.signInWithRedirectHelper(providerID: self.providerID,
                                                                               callbackScheme: self.callbackScheme,
                                                                               presentationContext: presentationContext)
        return try await self.auth._createCredentialsFromRedirectResult(details, provider: self)
    }

    #if canImport(UIKit)
    /// Convenience overload that uses a default presentation context on UIKit platforms.
    open func getCredentialWith() async throws -> UserCredential {
        return try await getCredentialWith(presentationContext: DefaultWebAuthProvider.shared)
    }
    #endif

}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
/// A credential for Facebook authentication.
class FacebookAuthCredential: AuthCredential {
    /// The Facebook access token (securely stored).
    private var accessTokenChars: [Character]?

    /// The Facebook access token.
    var accessToken: String? {
        return accessTokenChars.map { String($0) }
    }

    /// Initializes with a Facebook access token.
    ///
    /// - Parameter accessToken: The access token.
    init(withAccessToken accessToken: String) {
        self.accessTokenChars = Array(accessToken)
        super.init(provider: FacebookAuthProvider.id, idToken: accessToken)
    }

    /// Automatically clears sensitive data when the credential goes out of scope.
    deinit {
        clearSensitiveData()
    }

    /// Clears sensitive data from memory to prevent heap dump attacks.
    private func clearSensitiveData() {
        if let chars = accessTokenChars {
            // Zero out each character to securely erase from memory
            for i in 0..<chars.count {
                accessTokenChars![i] = "\0"
            }
            accessTokenChars = nil
        }
    }
}
