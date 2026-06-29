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
 IDCS authentication provider for the iOS SDK.

 This provider mirrors the behavior of OAuthProvider / SAMLAuthProvider and
 performs a redirect-based sign-in flow using the library's internal
 AuthHelper. When signed in this way the returned UserCredential will contain
 a signed-in FusabaseUser and an AuthCredential appropriate for the provider.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class IDCSAuthProvider: FederatedAuthProvider, AuthProvider {

    /// The ID for the IDCS provider
    public static let PROVIDER_ID = "idcs"
    public static let IDCS_SIGN_IN_METHOD = "idcs"

    public var providerID: String
    private let auth: FusabaseAuth
    public let callbackScheme: String
    private let usingClientIDScheme: String

    /// Return an instance for a providerID
    open class func provider(providerID: String) -> IDCSAuthProvider {
        return IDCSAuthProvider(providerID: providerID)
    }

    public init(providerID: String, auth: FusabaseAuth? = nil) {
        if auth == nil {
            self.auth = FusabaseAuth.auth()
        } else {
            self.auth = auth!
        }

        self.providerID = providerID
        self.callbackScheme = "baasmobile" + FusabaseAuth.auth().config!.appId.lowercased()
        self.usingClientIDScheme = ""
    }

    /// Create an AuthCredential for IDCS (ID token + optional access token)
    public static func credential(providerID: String, idToken: String, accessToken: String? = nil) -> AuthCredential {
        return AuthCredential(provider: providerID)
    }

    public func credential() async throws -> AuthCredential {
        #if canImport(UIKit)
        let userCredential = try await getCredentialWith()
        return userCredential.credential
        #else
        throw AuthErrorUtilities.operationNotAllowed(message: "IDCS sign-in requires a presentation context which is not available on this platform.")
        #endif
    }

    /**
     Performs the IDCS redirect flow and returns a populated UserCredential.
     This mirrors the logic in OAuthProvider/SAMLAuthProvider but is provided
     as a dedicated provider to be used by IDCS-specific flows if needed.
    */
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
