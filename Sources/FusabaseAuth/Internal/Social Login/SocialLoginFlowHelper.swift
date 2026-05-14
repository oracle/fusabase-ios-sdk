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
import FusabaseCore

/// Helper responsible for running the common redirect-based social login flow
/// shared by the On-Premises and IDCS helpers. This centralises the PKCE
/// challenge creation, invocation of the `SocialLoginManager`, and leaves it to
/// the caller to build endpoint-specific URLs and map the resulting tokens into
/// `AuthUserCompleteDetails`.
enum SocialLoginFlowHelper {

    static func perform(
        callbackScheme: String,
        presentationContext: ASWebAuthenticationPresentationContextProviding,
        link: Bool,
        buildLoginURL: (_ codeChallenge: String, _ link: Bool) throws -> URL,
        fetchTokens: (_ code: String) async throws -> BearerTokenResponse,
        mapTokensToDetails: (_ tokens: BearerTokenResponse) async throws -> AuthUserCompleteDetails
    ) async throws -> AuthUserCompleteDetails {

        // Generate PKCE verifier & challenge, persisting the verifier for the
        // redirect result exchange.
        let verifier = AuthUtils.generateCodeVerifier()
        KeychainTokenStore.shared.write(verifier, for: .codeVerifier)
        let challenge = AuthUtils.generateCodeChallenge(from: verifier)

        do {
            let loginURL = try buildLoginURL(challenge, link)

            let code = try await SocialLoginManager.loginWithIDP(
                callbackScheme: callbackScheme,
                loginURL: loginURL,
                presentationProvider: presentationContext
            )

            let tokens = try await fetchTokens(code)
            return try await mapTokensToDetails(tokens)
        } catch {
            // Clear the stored code verifier on failure
            KeychainTokenStore.shared.delete(.codeVerifier)
            throw error
        }
    }
}