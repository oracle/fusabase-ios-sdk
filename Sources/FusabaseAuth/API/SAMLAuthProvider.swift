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
    Utility class for constructing OAuth SAML credentials
 */

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class SAMLAuthProvider : FederatedAuthProvider, AuthProvider {
    
    open var scopes: [String]?
    open var customParameters: [String: String]?
    public var providerID: String
    private let auth: FusabaseAuth
    public let callbackScheme: String
    private let usingClientIDScheme: String
    
    /**
        Method that returns an instance of OAuthProvider with the given providerID
        - Parameter providerID: String
        - Returns: An instance of OAuthProvider corresponding to the specified provider ID.
     */
    open class func provider(providerID: String) -> SAMLAuthProvider {
        return SAMLAuthProvider(providerID: providerID)
    }
    
    /// Initializes a OAuthProvider object.
    /// - Parameter providerID: Provider ID for which this instance will be configured.
    /// - Parameter auth: Auth instance associated with the object
    public init(providerID: String, auth: FusabaseAuth? = nil) {
        
        // fusabase ios sdk doesn't allow facebook or apple, check if it will be allowed here
        
        if auth == nil {
            self.auth = FusabaseAuth.auth()
        } else {
            self.auth = auth!
        }
        
        self.providerID = providerID
        scopes = [""]
        customParameters = [:]
        
        self.callbackScheme = "baasmobile" + FusabaseAuth.auth().config!.appId.lowercased()
        self.usingClientIDScheme = ""
    }
    
    /// Creates AuthCredential object for the OAuth2 provider with providerID, IDToken and access token
    /// - Parameter providerID: The provider ID associated with the auth credential
    /// - Parameter IDToken: IDToken associated with the auth credential
    /// - Parameter accessToken: The access token associated with the auth credential
    /// - Returns : An AuthCredential for the specified provider ID
    public static func credential(providerID: String, idToken: String, accessToken: String? = nil) -> SAMLAuthCredential {
        return SAMLAuthCredential(idToken: idToken, accessToken: accessToken, provider: providerID)
    }
    
    public func credential() async throws -> AuthCredential {
        #if canImport(UIKit)
        let userCredential = try await getCredentialWith()
        return userCredential.credential
        #else
        throw AuthErrorUtilities.operationNotAllowed(message: "SAML sign-in requires a presentation context which is not available on this platform.")
        #endif
    }
    
    /// Performs a SAML/OIDC redirect flow and returns a fully populated UserCredential.
    ///
    /// This method:
    /// - Starts the SAML/OIDC redirect flow for this provider instance
    /// - Exchanges tokens for user details
    /// - Creates and sets the current user in FusabaseAuth (tokens are persisted)
    /// - Builds an AuthCredential and returns UserCredential
    ///
    /// Important:
    /// - After calling this method, you do NOT need to call FusabaseAuth.signIn(with: AuthCredential).
    ///   The user is already signed in and tokens are stored.
    ///
    /// - Parameter presentationContext: ASWebAuthentication presentation context for UI control.
    /// - Returns: UserCredential for the signed-in user.
    /// - Throws: Error if the flow fails.
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
