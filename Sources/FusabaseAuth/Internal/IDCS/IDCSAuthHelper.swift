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
import os
import FusabaseCore
import AuthenticationServices
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
class IDCSAuthHelper: AuthHelperProtocol {
    
    
    private let middleware: IDCSMiddlewareClient
    private var logger = Logger(subsystem: "com.oracle.database.fusabase", category: "auth")

    private var idcsDomainURL: String {
        middleware.idcsDomainURL
    }

    init(_config: FusabaseOptions) {
        self.middleware = IDCSMiddlewareClient(config: _config)
    }

    func mapNormalizedTokensToDetails(tokens: BearerTokenResponse, link: Bool = false) async throws -> AuthUserCompleteDetails {
        if link {
            return AuthUserCompleteDetails(
                accessToken: AuthTokenResult(rawToken: tokens.access_token, persist: false),
                refreshToken: "",
                userInfo: nil
            )
        }
        let refreshToken = try tokens.requireRefreshTokenForSignIn()
        let accessToken = try AuthTokenResult(token: tokens.access_token, "idcsuser", tokenKey: .access, persist: false)
        let userDetails = try await self._getUserDetailsIDCS(accessToken: accessToken)
        IDCSMiddlewareClient.persistNormalizedTokens(tokens, replacingAuthTokens: true)
        return AuthUserCompleteDetails(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userInfo: userDetails
        )
    }
    
    /**
        Helper method for getUserDetails that returns the APIUser object for the access token. The result of this will be modified with the result from the GET to /admin/v1/ME
     */
    func _getUserDetailsHelper(accessToken: AuthTokenResult) throws -> AuthUserInterface {
        let data = try AuthUtils.decodeOnly(jwtToken: accessToken.token)
        
        let email = data["sub"] as? String ?? data["email"] as? String ?? "-"
        let displayName = data["user_displayname"] as? String ?? email
        let userId = data["user_id"] as? String ?? email
        let newEmails = [["value": email]]
        let phoneNumbers = [["value": "-"]] // idcs user don't seem to contain phoneNumber attribute
        let meta = [
            "created": data["creation_time"] ?? "-",
            "lastSignIn": data["iat"] ?? "-"
        ] as [String : Any]
        let photos = [["url": "none"]] // idcs users don't seem to contain a photoUrls atrribute
        
        // temporary solution to email verified being 0
        let emailverified: String = {
            if let intVal = data["email_verified"] as? Int {
                return String(intVal)
            } else {
                return "false"
            }
        }()

        let userData = AuthUserInterface(displayName: displayName, emails: newEmails, phoneNumbers: phoneNumbers, metadata: meta, photos: photos, emailVerified: emailverified, idp_name: data["idp_name"] as? String ?? "idcs", idp_type: data["idp_type"] as? String ?? "idcs", id: userId)
        self.logger.info("Successfully created initial user from token.")
        return userData
    }
    
    /**
     Method that returns the details of an IDCS authenticated user
     - Parameter accessToken : IDToken
     - Returns : AuthUserInterface object
     */
    func _getUserDetailsIDCS(accessToken: AuthTokenResult) async throws -> AuthUserInterface {
        self.logger.info("Creating IDCS user details from ORDS access token.")
        return try _getUserDetailsHelper(accessToken: accessToken)
    }
    
    
    /**
        Abstracted method that authenticates an IDCS user with a given email & password, retrieves their access token and creates a AuthUserCompleteDetails object
        - Parameter email : String
        - Parameter password : String
     */
    func authenticateAndGetDetails(email: String, password: String) async throws -> AuthUserCompleteDetails {
        let tokens = try await authenticateWithOrds(email: email, password: password)
        return try await mapNormalizedTokensToDetails(tokens: tokens)

    }
    
    /**
        Abstracted method that calls the internal registerUser method and then authenticates.
        - Parameter email : String
        - Parameter password : String
     */
    func createUserWithEmailAndPassword(email: String, password: String) async throws -> AuthUserCompleteDetails? {
        try await registerUser(email: email, password: password)
        return try await authenticateAndGetDetails(email: email, password: password)

    }

    func signInWithRedirectHelper(providerID: String, callbackScheme: String, link: Bool) async throws -> AuthUserCompleteDetails {
        #if canImport(UIKit)
        return try await signInWithRedirectHelper(providerID: providerID,
                                                  callbackScheme: callbackScheme,
                                                  presentationContext: DefaultWebAuthProvider.shared,
                                                  link: link)
        #else
        throw AuthErrorUtilities.operationNotAllowed(message: "signInWithRedirect is not supported on this platform.")
        #endif
    }

    func signInWithRedirectHelper(providerID: String, callbackScheme: String) async throws -> AuthUserCompleteDetails {
        return try await signInWithRedirectHelper(providerID: providerID,
                                                  callbackScheme: callbackScheme,
                                                  link: false)
    }

    func signInWithRedirectHelper(providerID: String,
                                   callbackScheme: String,
                                   presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> AuthUserCompleteDetails {
        return try await signInWithRedirectHelper(providerID: providerID,
                                                  callbackScheme: callbackScheme,
                                                  presentationContext: presentationContext,
                                                  link: false)
    }

    func signInWithRedirectHelper(providerID: String,
                                   callbackScheme: String,
                                   presentationContext: ASWebAuthenticationPresentationContextProviding,
                                   link: Bool) async throws -> AuthUserCompleteDetails {

        return try await SocialLoginFlowHelper.perform(
            callbackScheme: callbackScheme,
            presentationContext: presentationContext,
            link: link,
            buildLoginURL: { codeChallenge, _ in
                try self.middleware.url(
                    "social",
                    queryItems: [
                        URLQueryItem(name: "device", value: "mobile"),
                        URLQueryItem(name: "apiKey", value: self.middleware.config.appId),
                        URLQueryItem(name: "code_challenge", value: codeChallenge),
                        URLQueryItem(name: "code_challenge_method", value: "S256")
                    ]
                )
            },
            fetchTokens: { code in
                try await self.redirectResult(code: code)
            },
            mapTokensToDetails: { tokens in
                try await self.mapNormalizedTokensToDetails(tokens: tokens, link: link)
            }
        )
    }
    
    private func authenticateWithOrds(email: String, password: String) async throws -> BearerTokenResponse {
        try await middleware.sendDecodable(
            endpoint: middleware.endpoints.AUTHENTICATE_PATH,
            method: "POST",
            body: [
                "grant_type": "user_credentials",
                "username": email,
                "password": password
            ],
            methodDescription: "Authenticate IDCS user through ORDS."
        )
    }

    /**
        Method that registers a user into IDCS (proxied via ORDS)
        - Parameter email: String
        - Parameter password: String
     */
    func registerUser(email: String, password: String) async throws {

        // Registration is proxied via ORDS to avoid exposing IDCS-sensitive parameters.
        let data = try await middleware.send(
            endpoint: middleware.endpoints.SELF_REGISTER_EP,
            method: "POST",
            body: [
                "first_name": "-",
                "last_name": "-",
                "email": email,
                "password": password
            ],
            methodDescription: "User registration (IDCS via ORDS)."
        )

        // Contract: 200 OK + {"message":"User Registered"}
        if let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = json as? [String: Any],
           let message = dict["message"] as? String {
            AuthLogger.info("Registration response: \(message)")
        }
    }
    
    /**
        Method to reload the user through getIdTokenResult.
     */
    func reloadUser(_ user: FusabaseUser) async throws -> AuthUserInterface {
        let accessToken = KeychainTokenStore.shared.read(.access) ?? ""
        if accessToken.isEmpty {
            throw AuthErrorUtilities.invalidCredential(message: "Missing access token for user reload.")
        }
        return try await self._getUserDetailsIDCS(
            accessToken: AuthTokenResult(token: accessToken, "idcsuser", tokenKey: .access)
        )
    }
    
    /**
        Method that sends the password reset emali
        - Parameter user: AuthUser
        - Parameter withEmail: String that contains the user's email
     */
    func sendPasswordResetHelper(withEmail: String) async throws {
        _ = try await middleware.send(
            endpoint: middleware.endpoints.SEND_EMAIL_PATH,
            method: "GET",
            headers: ["Accept": "application/json"],
            queryItems: [
                URLQueryItem(name: "email", value: withEmail),
                URLQueryItem(name: "requesttype", value: "resetpwd")
            ],
            methodDescription: "Send password reset email."
        )

        UserDefaults.standard.set(withEmail, forKey: "password_reset_email")
    }
    
    /**
        Method that verifies the password reset code
        - Parameter token: String containing the verification token
        - Returns: Dictionary with the verification result
     */
    func verifyPasswordResetCodeHelper(code: String) async throws -> [String: Any] {
        try await middleware.sendJSON(
            endpoint: middleware.endpoints.VERIFY_CODE_PATH,
            method: "GET",
            headers: ["Accept": "application/json"],
            queryItems: [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "requesttype", value: "resetpwd")
            ],
            methodDescription: "Verify password reset code (IDCS)."
        )
    }
    
    /**
        Method that confirms the password reset with new password (IDCS)
        - Parameters:
            - token: String containing the verification token
            - newPassword: New password to set
        - Returns: Dictionary with the confirmation result
     */
    func confirmPasswordResetHelper(code: String, newPassword: String) async throws -> [String: Any] {
        guard let storedEmail = UserDefaults.standard.string(forKey: "password_reset_email"), !storedEmail.isEmpty else {
            throw AuthErrorUtilities.internalError(message: "No password reset request found. Please request a password reset first.")
        }

        return try await middleware.sendJSON(
            endpoint: middleware.endpoints.RESET_PASSWORD_PATH,
            method: "POST",
            body: [
                "code": code,
                "password": newPassword
            ],
            headers: ["Accept": "application/json"],
            queryItems: [URLQueryItem(name: "email", value: storedEmail)],
            methodDescription: "Confirm password reset (IDCS)."
        )
    }
    
    /**
        Abstracted method that performs the sign out for authenticated users
        - Parameter refreshToken: String
     */
    func performSignOut(refreshToken: String) async throws {
        var revokeFailure: Error?

        do {
            try await self.revokeRefreshToken(refreshToken: refreshToken)
        } catch {
            revokeFailure = error
            AuthLogger.warning("Unable to revoke Fusabase refresh token during IDCS sign out: \(error.localizedDescription)")
        }

        do {
            try await self.signOutFromIDCS()
        } catch {
            AuthLogger.warning("Unable to complete IDCS browser-session logout: \(error.localizedDescription)")
        }

        if let revokeFailure {
            throw revokeFailure
        }
    }

    private func signOutFromIDCS() async throws {
        let domain = idcsDomainURL
        guard !domain.isEmpty else { return }
        guard let url = URL(string: "\(domain)/oauth2/v1/userlogout") else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct IDCS user logout endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Signing out from IDCS domain session.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Received invalid HTTP response from IDCS logout.")
        }
    }
    
    /**
        Internal method to revoke a refresh token for an authenticated user
        - Parameter refreshToken: String
     */
    func revokeRefreshToken(refreshToken: String) async throws {
        // Skip revocation if refresh token is empty or nil
        guard !refreshToken.isEmpty else {
            AuthLogger.info("Skipping refresh token revocation - no token available")
            return
        }

        _ = try await middleware.send(
            endpoint: middleware.endpoints.REVOKE_REFRESH_TOKEN_PATH,
            method: "PUT",
            body: ["token": refreshToken],
            headers: [
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Accept": "*/*"
            ],
            methodDescription: "Revoke a refresh token for an authenticated user through IDCS."
        )
    }

    func signInWithCredential(with credential: AuthCredential) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "IDCS sign-in with credential is not supported.")
    }

    func signInWithCredentialLinking(credential: AuthCredential, link: Bool) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "IDCS sign-in with credential is not supported.")
    }

    func socialUnlinkHelper(provider: String) async throws -> AuthUserCompleteDetails {
        throw AuthErrorUtilities.operationNotAllowed(message: "IDCS social unlink is not supported.")
    }

    private func redirectResult(code: String) async throws -> BearerTokenResponse {
        let verifier = KeychainTokenStore.shared.read(.codeVerifier) ?? ""

        return try await middleware.sendDecodable(
            endpoint: middleware.endpoints.REDIRECT_RESULT_PATH,
            method: "POST",
            body: [
                "code": code,
                "code_verifier": verifier
            ],
            methodDescription: "IDCS redirect result."
        )
    }
}
