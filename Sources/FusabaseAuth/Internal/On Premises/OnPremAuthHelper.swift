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

// Needed for JSON utilities
import Foundation

// Logger utilities
import os

// Crypto kit for RFC 7376
import CryptoKit
import AuthenticationServices
import FusabaseCore

/**
 Result type for sign-in operations that can return either user details or a credential
 */
enum SignInResult {
    case userDetails(AuthUserCompleteDetails)
    case credential(AuthCredential)
}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
class OnPremAuthHelper: AuthHelperProtocol {

    var _config: FusabaseOptions
    var ordsConfig: OnPremConfigHelper
    private var logger = Logger(subsystem: "com.oracle.database.fusabase", category: "auth")

    
    init(config: FusabaseOptions) {
        self._config = config
        let domainurl = _config.ordsHost + ":" + _config.ordsPort + "/ords/" + _config.schema + "/_/baas-services/idm/onprem/" + _config.projectId + "/"
        self.ordsConfig = OnPremConfigHelper(_domainURL: domainurl, _appID: _config.appId)
    }
    
    /**
        # func getUserDetails(accessToken: String)
        Internal method to create a APIUser object based on the given access token.
        - Parameter accessToken: String
        - Returns : APIUser object.
     */
    func _getUserDetails(accessToken: String) throws -> AuthUserInterface {
        let data = try AuthUtils.decode(jwtToken: accessToken)
        
        let newEmails = [["value": data.sub]]
        let phoneNumbers = [["value": "num"]]
        let meta = [
            "created": data.creation_time,
            "lastSignIn": data.iat
        ] as [String : Any]
        let photos = [["url": "url"]] // no url attribute from given data
                
        let userData = AuthUserInterface(displayName: data.user_displayname, emails: newEmails, phoneNumbers: phoneNumbers, metadata: meta, photos: photos, emailVerified: data.email_verified, idp_name: data.idp_name, idp_type: data.idp_type, id: data.user_id)
        
        return userData
        
    }
    
    /**
        Method to obtain a credential for a user with the given provider. This method creates the presentation context by default.
        - Parameter providerID: String
        - Parameter callbackScheme: String
     */
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, link: Bool = false) async throws -> AuthUserCompleteDetails {
        
        let verifier = AuthUtils.generateCodeVerifier()
        
        // we save the code verifier into the device
        KeychainTokenStore.shared.write(verifier, for: .codeVerifier)
        
        let challenge = AuthUtils.generateCodeChallenge(from: verifier)

        // we form the needed url
        _ = URL(string: ordsConfig.getSignInWithRedirectURL(providerID: providerID, challenge: challenge, link: link))

        return try await SocialLoginFlowHelper.perform(
            callbackScheme: callbackScheme,
            presentationContext: DefaultWebAuthProvider.shared,
            link: link,
            buildLoginURL: { challenge, linkFlag in
                guard let url = URL(string: ordsConfig.getSignInWithRedirectURL(providerID: providerID,
                                                                                challenge: challenge,
                                                                                link: linkFlag)) else {
                    throw AuthErrorUtilities.internalError(message: "Unable to construct social login URL.")
                }
                return url
            },
            fetchTokens: { code in
                try await self.redirectResult(code: code)
            },
            mapTokensToDetails: mapTokensToDetails(tokens:)
        )
    }

    // Wrapper to satisfy protocol method without link parameter
    func signInWithRedirectHelper(providerID: String, callbackScheme: String) async throws -> AuthUserCompleteDetails {
        return try await signInWithRedirectHelper(providerID: providerID, callbackScheme: callbackScheme, link: false)
    }

    // Presentation context variant that accepts a link flag
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding, link: Bool) async throws -> AuthUserCompleteDetails {

        return try await SocialLoginFlowHelper.perform(
            callbackScheme: callbackScheme,
            presentationContext: presentationContext,
            link: link,
            buildLoginURL: { challenge, linkFlag in
                guard let url = URL(string: ordsConfig.getSignInWithRedirectURL(providerID: providerID,
                                                                                challenge: challenge,
                                                                                link: linkFlag)) else {
                    throw AuthErrorUtilities.internalError(message: "Unable to construct social login URL.")
                }
                return url
            },
            fetchTokens: { code in
                try await self.redirectResult(code: code)
            },
            mapTokensToDetails: mapTokensToDetails(tokens:)
        )
    }

    /**
        Method to obtain a credential for a user with the given provider. Allows the developer to
        - Parameter providerID: String
        - Parameter callbackScheme: String
        - Parameter presentationContext: Interface needed to tell ASWebAuthenticationService where to show the login page
     */
    func signInWithRedirectHelper(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> AuthUserCompleteDetails {

        return try await SocialLoginFlowHelper.perform(
            callbackScheme: callbackScheme,
            presentationContext: presentationContext,
            link: false,
            buildLoginURL: { challenge, _ in
                guard let url = URL(string: ordsConfig.getSignInWithRedirectURL(providerID: providerID,
                                                                                challenge: challenge)) else {
                    throw AuthErrorUtilities.internalError(message: "Unable to construct social login URL.")
                }
                return url
            },
            fetchTokens: { code in
                try await self.redirectResult(code: code)
            },
            mapTokensToDetails: mapTokensToDetails(tokens:)
        )
    }

    /**
        Method to obtain a credential for linking a user with the given provider.
        Returns AuthCredential directly without persisting tokens or parsing user details.
        - Parameter providerID: String
        - Parameter callbackScheme: String
        - Parameter presentationContext: Interface needed to tell ASWebAuthenticationService where to show the login page
     */
    func signInWithRedirectForLinking(providerID: String, callbackScheme: String, presentationContext: ASWebAuthenticationPresentationContextProviding) async throws -> AuthCredential {

        let verifier = AuthUtils.generateCodeVerifier()

        // we save the code verifier into the device
        KeychainTokenStore.shared.write(verifier, for: .codeVerifier)

        let challenge = AuthUtils.generateCodeChallenge(from: verifier)

        guard let loginURL = URL(string: ordsConfig.getSignInWithRedirectURL(providerID: providerID,
                                                                             challenge: challenge,
                                                                             link: true)) else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct social login URL.")
        }

        // Perform the OAuth redirect flow manually using ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(url: loginURL, callbackURLScheme: callbackScheme) { callbackURL, error in
            // This will be handled by the continuation below
        }

        #if canImport(UIKit)
        session.presentationContextProvider = presentationContext
        #endif

        // Start the authentication session and wait for result
        return try await withCheckedThrowingContinuation { continuation in
            session.start()

            // Note: This is a simplified implementation. In practice, you'd need to handle
            // the callback URL properly. The SocialLoginFlowHelper handles this complexity.
            // For now, this is a placeholder that needs to be completed based on the actual flow.
        }
    }

    private func mapTokensToDetails(tokens: BearerTokenResponse) throws -> AuthUserCompleteDetails {
        // Check if this is a linking flow by reading the linking flag from keychain
        let isLinking = KeychainTokenStore.shared.read(.linking) != nil

        if isLinking {
            // For linking flows: don't persist tokens, don't parse JWT, return minimal details
            // Clean up the linking flag
            KeychainTokenStore.shared.delete(.linking)

            return AuthUserCompleteDetails(
                accessToken: AuthTokenResult(rawToken: tokens.access_token, tokenKey: .access, persist: false),
                refreshToken: tokens.refresh_token ?? "",
                authnToken: nil,
                userInfo: nil // No user details for linking
            )
        } else {
            // For regular sign-in flows: persist tokens and parse user details
            KeychainTokenStore.shared.write(tokens.access_token, for: .access)
            if let refreshToken = tokens.refresh_token, !refreshToken.isEmpty {
                KeychainTokenStore.shared.write(refreshToken, for: .refresh)
            }

            let userDetails = try self._getUserDetails(accessToken: tokens.access_token)
            return AuthUserCompleteDetails(
                accessToken: try AuthTokenResult(token: tokens.access_token, tokenKey: .access),
                refreshToken: tokens.refresh_token ?? "",
                authnToken: nil,
                userInfo: userDetails
            )
        }
    }
    
    /**
        Internal method that calls authenticateUser and returns a AuthUserCompleteDetails object
        - Parameter email: String
        - Parameter password: String
        - Returns : AuthUserCompleteDetails object
     */
    func authenticateAndGetDetails(email: String, password: String) async throws -> AuthUserCompleteDetails {
        let authenticationDetails = try await self.authenticateUser(email: email, password: password)

        // Store the authentication tokens securely in keychain
        KeychainTokenStore.shared.write(authenticationDetails.access_token.token, for: .access)
        if !authenticationDetails.refresh_token.isEmpty {
            KeychainTokenStore.shared.write(authenticationDetails.refresh_token, for: .refresh)
        }

        let userDetails = try self._getUserDetails(accessToken: authenticationDetails.access_token.token)

        return AuthUserCompleteDetails(accessToken: authenticationDetails.access_token, refreshToken: authenticationDetails.refresh_token, authnToken: nil, userInfo: userDetails)

    }
    
    /**
        Internal method that signs in a user with the provided credential
        - Parameter credential: AuthCredential
        - Returns AuthUserCompleteDetails object
     */
    func signInWithCredential(with credential: AuthCredential) async throws -> AuthUserCompleteDetails {
        let authenticationDetails = try await self.signInWithCredentialHelper(credential: credential, link: false)

        // Store the authentication tokens securely in keychain
        KeychainTokenStore.shared.write(authenticationDetails.access_token, for: .access)
        if let refreshToken = authenticationDetails.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }

        let userDetails = try self._getUserDetails(accessToken: authenticationDetails.access_token)

        return AuthUserCompleteDetails(accessToken: try AuthTokenResult(token: authenticationDetails.access_token, tokenKey: .access), refreshToken: authenticationDetails.refresh_token!, authnToken: nil, userInfo: userDetails)
    }

    /**
        Internal method that links or signs in a user with the provided credential
        - Parameter credential: AuthCredential
        - Parameter link: Bool indicating if this is a link operation
        - Returns AuthUserCompleteDetails object
     */
    func signInWithCredentialLinking(credential: AuthCredential, link: Bool) async throws -> AuthUserCompleteDetails {
        let authenticationDetails = try await self.signInWithCredentialHelper(credential: credential, link: link)

        // For linking operations, don't persist the new tokens - they don't replace the user's current tokens
        if !link {
            // Store the authentication tokens securely in keychain
            KeychainTokenStore.shared.write(authenticationDetails.access_token, for: .access)
            if let refreshToken = authenticationDetails.refresh_token, !refreshToken.isEmpty {
                KeychainTokenStore.shared.write(refreshToken, for: .refresh)
            }
        }

        let userDetails = try self._getUserDetails(accessToken: authenticationDetails.access_token)

        return AuthUserCompleteDetails(accessToken: try AuthTokenResult(rawToken: authenticationDetails.access_token, tokenKey: .access, persist: !link), refreshToken: authenticationDetails.refresh_token!, authnToken: nil, userInfo: userDetails)
    }

    /**
        Internal method that unlinks a provider from the user
        - Parameter provider: String
        - Returns AuthUserCompleteDetails object
     */
    func socialUnlinkHelper(provider: String) async throws -> AuthUserCompleteDetails {
        let authenticationDetails = try await self.socialUnlinkHelperInternal(provider: provider)

        // Store the authentication tokens securely in keychain
        KeychainTokenStore.shared.write(authenticationDetails.access_token, for: .access)
        if let refreshToken = authenticationDetails.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }

        let userDetails = try self._getUserDetails(accessToken: authenticationDetails.access_token)

        return AuthUserCompleteDetails(accessToken: try AuthTokenResult(token: authenticationDetails.access_token, tokenKey: .access), refreshToken: authenticationDetails.refresh_token!, authnToken: nil, userInfo: userDetails)
    }
    
    /**
        Internal method that calls registerUser and handles errors if needed.
        - Parameter email: String
        - Parameter password: String
     */
    func createUserWithEmailAndPassword(email: String, password: String) async throws -> AuthUserCompleteDetails?
    {
        try await self.registerUser(email: email, password: password)
        return nil

    }
    
    /**
        # func authenticateUser(email, string)
        Internal method to call POST /authenticate and return the user object
        - Parameter email: String
        - Parameter password: String
     
        - Returns : AuthenticationDetails.
     */
    func authenticateUser(email: String, password: String) async throws -> AuthenticationDetails {
        let url = URL(string: ordsConfig.domainURL + ordsConfig.AUTHENTICATE_REST_EP)
        
        // 2. Create the JSON body
        let requestBody: [String: Any] = [
            "grant_type": "user_credentials",
            "username": email,
            "password": password
        ]
        
        
        // 3. Serialize the body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for authentication.")
        }
        
        // 4. Create the URLRequest
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        
        // 6. Check the response (similar to Utils.checkResponse in JavaScript)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "On authenticating user.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
        
        // 7. parsing
        let decoder = JSONDecoder()
        guard let userDetails = try? decoder.decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't decode the user's details from the server.")
        }
        return AuthenticationDetails(access_token: try AuthTokenResult(token: userDetails.access_token, tokenKey: .access), refresh_token: userDetails.refresh_token!)

    }
    
    /**
        Internal method to fetch response for the getCredential method
        - Parameter credential: AuthCredential object
        - Parameter link: Bool indicating if this is a link operation
        - Returns : BearerTokenResponse
     */

    func signInWithCredentialHelper(credential: AuthCredential, link: Bool = false) async throws -> BearerTokenResponse {
        // Align behavior with Android implementation:
        // - Normalize provider method to first segment (split by '.')
        // - For linking operations, require a current access token and, when linking with
        //   EmailAuthCredential, require a cached password (recent email/password login).
        let method = credential.provider.split(separator: ".").first.map(String.init) ?? credential.provider

        if link {
            let currentAccessToken = KeychainTokenStore.shared.read(.access) ?? ""
            if currentAccessToken.isEmpty {
                throw AuthErrorUtilities.invalidCredential(message: "User must be recently logged in for linking with provider.")
            }

            // Email/password linking requires a password. Prefer the password carried inside
            // EmailAuthCredential (prompted from user), and fall back to cached password.
            if let emailCredential = credential as? EmailAuthCredential {
                let providedPassword = emailCredential.emailType.passwordValue ?? ""
                let cachedPassword = KeychainTokenStore.shared.read(.userPassword) ?? ""
                if providedPassword.isEmpty && cachedPassword.isEmpty {
                    throw AuthErrorUtilities.invalidCredential(message: "User must provide password (or be recently logged in) for linking with provider.")
                }
            }
        }

        let url = URL(string: ordsConfig.domainURL + ordsConfig.SIGN_IN_WITH_CREDENTIAL + "&method=\(method)&link=\(link ? 1 : 0)")

        let password: String
        if link, let emailCredential = credential as? EmailAuthCredential {
            // Use password provided in the credential first, else fallback to cached password.
            password = emailCredential.emailType.passwordValue
                ?? (KeychainTokenStore.shared.read(.userPassword) ?? "")
        } else {
            password = link ? (KeychainTokenStore.shared.read(.userPassword) ?? "") : ""
        }

        // Android parity: when linking with EmailAuthCredential, no idToken is supplied.
        // The backend relies on the Authorization header (current user) + cached password.
        // Our AuthCredential.getIdToken() throws when idToken is absent, so we must avoid
        // calling it in this specific case.
        let token: String
        if link, credential is EmailAuthCredential {
            token = ""
        } else {
            token = try credential.getIdToken()
        }

        let requestBody: [String: Any] = [
            "token": token,
            "password": password
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for authentication with credential.")
        }


        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // For linking, add Authorization header with current user's access token
        if link {
            if let accessToken = KeychainTokenStore.shared.read(.access), !accessToken.isEmpty {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
                
        // For linking operations, return current user's tokens instead of server response tokens
        if link {
            let currentAccessToken = KeychainTokenStore.shared.read(.access) ?? ""
            let currentRefreshToken = KeychainTokenStore.shared.read(.refresh)

            return BearerTokenResponse(
                access_token: currentAccessToken,
                token_type: "Bearer",
                expires_in: 3600, // Default expiration
                refresh_token: currentRefreshToken,
                authn_token: nil,
                authn_refresh_token: nil,
                idcs_access_token: nil,
                idcs_refresh_token: nil,
                persistToKeychain: false
            )
        } else {
            // For non-linking operations, decode and return server response
            let decoder = JSONDecoder()
            guard let decodedResponse = try? decoder.decode(BearerTokenResponse.self, from: data) else {
                throw AuthErrorUtilities.internalError(message: "Couldn't decode the user's details from the server.")
            }
            return decodedResponse
        }
    }
    
    /**
        Method to POST the obtained code from ORDS with the code verifier to obtain the user's tokens
        - Parameter code: String
        - Returns : Tokens from authentication
     */
    func redirectResult(code: String) async throws -> BearerTokenResponse {
        let url = URL(string: ordsConfig.domainURL + ordsConfig.REDIRECT_RESULT_EP)
        let verifier = KeychainTokenStore.shared.read(.codeVerifier) ?? ""

        let requestBody: [String: Any] = [
            "code": code,
            "code_verifier": verifier
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for authentication with credential.")
        }

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }

        // Parse JSON to check response structure
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse server response.")
        }

        // Handle linking case where response is {"id_token": "<value>"}
        if let idToken = jsonObject["id_token"] as? String {
            return BearerTokenResponse(
                access_token: idToken,
                token_type: "Bearer",
                expires_in: 3600, // Default expiration
                refresh_token: nil,
                authn_token: nil,
                authn_refresh_token: nil,
                idcs_access_token: nil,
                idcs_refresh_token: nil,
                persistToKeychain: false
            )
        }

        // Handle normal case - decode as full BearerTokenResponse
        let decoder = JSONDecoder()
        guard let userDetails = try? decoder.decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't decode the user's details from the server.")
        }
        return userDetails
    }
    
    /**
        # func registerUser(email, string)
        Internal method that calls POST /useradd
        - Parameter email: String
        - Parameter password: String
     */
    func registerUser(email: String, password: String) async throws {
        
        let url = URL(string: ordsConfig.domainURL + ordsConfig.SELF_REGISTER_EP)
        
        // 2. Create the JSON body
        let requestBody: [String: Any] = [
            "first_name": "-",
            "last_name": "-",
            "email": email,
            "password": password
        ]
        
        
        // 3. Serialize the body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            fatalError("Error serializing JSON")
        }
        
        // 4. Create the URLRequest
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        

        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "User registration.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
                
    }
    
    /**
        Method to reload the user through getIdTokenResult
     */
    func reloadUser(_ user: FusabaseUser) async throws -> AuthUserInterface {
        let accessToken = try await user.getIDTokenResult(true)
        return try  _getUserDetails(accessToken: accessToken.token)
    }
    
    /**
        Method that sends the password reset emali
        - Parameter user: AuthUser
        - Parameter withEmail: String that contains the user's email
     */
    func sendPasswordResetHelper(withEmail: String) async throws {
        // Build GET URL:
        // {domainURL}sendemail?apiKey={appId}&email={email}&requesttype=resetpwd
        guard let encodedEmail = withEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw AuthErrorUtilities.invalidEmailError(message: "Invalid email provided.")
        }
        let urlString = ordsConfig.domainURL
            + ordsConfig.SEND_PASSWORD_RESET_EMAIL
            + "&email=\(encodedEmail)&requesttype=resetpwd"

        guard let url = URL(string: urlString) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't construct password reset URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Password reset email request.")
            // Store the email for use in password reset confirmation
            UserDefaults.standard.set(withEmail, forKey: "password_reset_email")
            logger.info("Password reset email request sent successfully.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
    }
    
    /**
        Method that verifies the password reset code
        - Parameter code: String containing the verification code
        - Returns: Dictionary with the verification result
     */
    func verifyPasswordResetCodeHelper(code: String) async throws -> [String: Any] {
        guard let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw AuthErrorUtilities.internalError(message: "Invalid code provided.")
        }
        let urlString = ordsConfig.domainURL
            + ordsConfig.VERIFY_PASSWORD_RESET_CODE
            // Keep query parameter casing aligned with Android SDK and ORDS backend expectations.
            // Android uses `requesttype` (lowercase 't') for On-Prem password reset flows.
            + "&code=\(encodedCode)&requesttype=resetpwd"
        
        guard let url = URL(string: urlString) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't construct verify password reset URL.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Verify password reset code.")
            logger.info("Verify password reset request sent successfully.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let result = jsonObject as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse verify password reset response.")
        }
        return result
    }
    
    /**
        Method that confirms the password reset with new password
        - Parameters:
            - code: String containing the verification code
            - newPassword: New password to set
        - Returns: Dictionary with the confirmation result
     */
    func confirmPasswordResetHelper(code: String, newPassword: String) async throws -> [String: Any] {
        let storedEmail = UserDefaults.standard.string(forKey: "password_reset_email")
        guard let storedEmail = storedEmail, !storedEmail.isEmpty else {
            throw AuthErrorUtilities.internalError(message: "No password reset request found. Please request a password reset first.")
        }

        guard let encodedStoredEmail = storedEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw AuthErrorUtilities.internalError(message: "Invalid email stored.")
        }

        let urlString = ordsConfig.domainURL
            + ordsConfig.CONFIRM_PASSWORD_RESET
            + "&email=\(encodedStoredEmail)"

        guard let url = URL(string: urlString) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't construct confirm password reset URL.")
        }

        let body: [String: Any] = [
            "password": newPassword,
            "code": code
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse JSON body for confirming password reset.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Confirm password reset.")
            logger.info("Confirm password reset request sent successfully.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let result = jsonObject as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse confirm password reset response.")
        }
        return result
    }

    /**
        Internal method that unlinks a provider from the user
        - Parameter provider: String
        - Returns : BearerTokenResponse
     */
    func socialUnlinkHelperInternal(provider: String) async throws -> BearerTokenResponse {
        let method = provider.split(separator: ".").first.map(String.init) ?? provider
        let url = URL(string: ordsConfig.domainURL + ordsConfig.SIGN_IN_WITH_CREDENTIAL + "&method=\(method)")

        var request = URLRequest(url: url!)
        request.httpMethod = "DELETE"

        // Add Authorization header with current user's access token
        if let accessToken = KeychainTokenStore.shared.read(.access), !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }

        // For unlink operations, return current user's tokens instead of server response tokens
        let currentAccessToken = KeychainTokenStore.shared.read(.access) ?? ""
        let currentRefreshToken = KeychainTokenStore.shared.read(.refresh)

        return BearerTokenResponse(
            access_token: currentAccessToken,
            token_type: "Bearer",
            expires_in: 3600, // Default expiration
            refresh_token: currentRefreshToken,
            authn_token: nil,
            authn_refresh_token: nil,
            idcs_access_token: nil,
            idcs_refresh_token: nil,
            persistToKeychain: true  // Unlink can persist since it doesn't change user tokens
        )
    }

    /**
        Abstracted method that performs the sign out for an authenticated user through OnPrem/Basic configurations
        - Parameter refreshToken: String
     */
    func performSignOut(refreshToken: String) async throws {
        // perform signout
        try await self.revokeRefreshToken(refreshToken)
    }
    
    /**
        Internal method to revoke a user's refresh token
        - Parameter refreshToken: String
     */
    func revokeRefreshToken(_ refreshToken: String) async throws {
        let url = URL(string: ordsConfig.domainURL + ordsConfig.REVOKE_REFRESH_TOKEN )
        let body = [
            "token": refreshToken
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            fatalError("Error serializing JSON")
        }
        
        var request = URLRequest(url: url!)
        request.httpMethod = "PUT"
        request.httpBody = jsonData
        
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "User registration.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
        
    }
}
