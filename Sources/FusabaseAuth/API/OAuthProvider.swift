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
 A utility class for constructing OAuth credentials, conforming to `FederatedAuthProvider` and `AuthProvider`.
 */

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class OAuthProvider: FederatedAuthProvider, AuthProvider {

    /// The ID of the OAuth provider.
    public var providerID: String
    /// The associated authentication instance.
    private let auth: FusabaseAuth
    /// The callback scheme for handling authentication responses.
    private let callbackScheme: String
    /// A string indicating if client ID scheme is used (empty in this implementation).
    private let usingClientIDScheme: String
    
    /// Creates an instance of `OAuthProvider` for the specified provider ID.
    ///
    /// - Parameter providerID: The provider ID.
    /// - Returns: An `OAuthProvider` instance.
    open class func provider(providerID: String) async -> OAuthProvider {
        return OAuthProvider(providerID: providerID)
    }
    
    /// Initializes an `OAuthProvider` object.
    ///
    /// - Parameters:
    ///   - providerID: Provider ID for which this instance will be configured.
    ///   - auth: Auth instance associated with the object (defaults to default auth if nil).
    public init(providerID: String, auth: FusabaseAuth? = nil) {
        
        // fusabase ios sdk doesn't allow facebook or apple, check if it will be allowed here
        
        if auth == nil {
            self.auth = FusabaseAuth.auth()
        } else {
            self.auth = auth!
        }
        
        self.providerID = providerID
        
        self.callbackScheme = "baasmobile" + FusabaseAuth.auth().config!.appId.lowercased()
        self.usingClientIDScheme = ""
    }
    
    /// Creates an `OAuthCredential` for the specified provider.
    ///
    /// - Parameters:
    ///   - providerID: The provider ID.
    ///   - idToken: The ID token.
    ///   - accessToken: The access token (optional).
    /// - Returns: An `OAuthCredential`.
    public static func credential(providerID: String, idToken: String, accessToken: String? = nil) -> OAuthCredential {
        return OAuthCredential(idToken: idToken, accessToken: accessToken, provider: providerID)
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

    /// Performs the OAuth sign-in flow for this provider and returns a fully populated UserCredential.
    ///
    /// This method:
    /// - Launches a system web authentication session for the configured OAuth provider
    /// - Exchanges the resulting tokens for user details
    /// - Creates and sets the current user in FusabaseAuth (tokens are persisted)
    /// - Builds an AuthCredential associated with the provider and returns UserCredential
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
        let access = details.accessToken.token
        let refresh = details.refreshToken

        // Retrieve user details and construct FusabaseUser
        let userDetails = try self.auth._authHelper._getUserDetails(accessToken: access)
        let newUser = FusabaseUser(user: userDetails,
                                userRefreshToken: refresh,
                                accessToken: details.accessToken,
                                auth: self.auth)

        try await self.auth.updateCurrentUser(newUser)

        // Construct a generic or provider-specific AuthCredential
        let idToken = try await newUser.getIDToken()
        let credential: AuthCredential
        if self.providerID == "google" {
            credential = GoogleAuthCredential(withIDToken: idToken, accessToken: idToken)
        } else if self.providerID == "facebook" {
            credential = FacebookAuthCredential(withAccessToken: idToken)
        } else if self.providerID == "github" {
            credential = GithubAuthCredential(withToken: idToken)
        } else {
            credential = AuthCredential(provider: self.providerID)
        }

        return UserCredential(user: newUser, credential: credential)
    }

    #if canImport(UIKit)
    /// Convenience overload that uses a default presentation context on UIKit platforms.
    open func getCredentialWith() async throws -> UserCredential {
        return try await getCredentialWith(presentationContext: DefaultWebAuthProvider.shared)
    }
    #endif
}
