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
    
    
    private var _config: FusabaseOptions
    private var _encodedSecret: Any?
    private var clientid: String
    private var clientsecret: String
    private var ordsConfig: IDCSConfigHelper
    private var logger = Logger(subsystem: "com.oracle.database.fusabase", category: "auth")

    private var ordsBaseURL: String {
        "\(_config.ordsHost):\(_config.ordsPort)/ords/\(_config.schema)/_/baas-services/idm/idcs/\(_config.projectId)/"
    }

    init(_config: FusabaseOptions) {
        self._config = _config
        self.clientid = _config.clientID!
        self.clientsecret = _config.clientSecret!
        self._encodedSecret = AuthUtils.btoa("\(self.clientid):\(self.clientsecret)")

        ordsConfig = IDCSConfigHelper(
            _domainURL: _config.domainURL!,
            _appID: _config.appId,
            _clientID: _config.clientID!,
            _clientSecret: _config.clientSecret!
        )
    }
    
    /**
      # func getBearerToken()
        Fetches the necessary bearer token from IDCS
        - Returns : bearerToken: AuthTokenResult

     */
    func getBearerToken() async throws -> AuthTokenResult {
        let url = URL(string: _config.domainURL! + ordsConfig.OAUTH_TOKEN_REST_EP)

        // 2. Create the JSON body
        let requestBody: String = "grant_type=client_credentials&scope=urn:opc:idm:__myscopes__"

        // Create the URLRequest
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = requestBody.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(_encodedSecret ?? "-")", forHTTPHeaderField: "Authorization")


        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Bearer token retrieval.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Unable to get response from the server.")
        }

        let decoder = JSONDecoder()
        guard let bearerTokenDetails = try? decoder.decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Unable to decode bearer token from the server.")
        }

        let bearerToken = try AuthTokenResult(token: bearerTokenDetails.access_token, "idcsbtoken", tokenKey: .idcsBearer)

        // Store token securely in keychain
        KeychainTokenStore.shared.write(bearerToken.token, for: .idcsBearer)

        // we just formed the bearer token. if any errors do appear, they will
        return bearerToken
    }

    /**
     * Checks if a bearer token is expired by decoding the JWT and checking the 'exp' claim
     * - Parameter token: The JWT token to check
     * - Returns: true if the token is expired or invalid, false if valid
     */
    private func isBearerTokenExpired(_ token: String) -> Bool {
        do {
            let decoded = try AuthUtils.decode(jwtToken: token, "idcsbtoken")
            return decoded.exp <= Date().timeIntervalSince1970
        } catch {
            // If we can't decode the token, consider it expired
            return true
        }
    }

    /**
     * Gets a valid bearer token, either from cache if still valid, or fetches a new one
     * - Returns: A valid AuthTokenResult containing the bearer token
     */
    func getValidBearerToken() async throws -> AuthTokenResult {
        // Check if we have a cached bearer token
        var existingToken: String? = nil
        KeychainTokenStore.shared.withSecureToken(.idcsBearer) { token in
            existingToken = token
        }

        // If we have a token and it's not expired, return it
        if let token = existingToken, !token.isEmpty, !isBearerTokenExpired(token) {
            return try AuthTokenResult(token: token, "idcsbtoken", tokenKey: .idcsBearer)
        }

        // Otherwise, fetch a new one
        return try await getBearerToken()
    }
    
    /**
        # func getAuthForm(bearerToken: String)
        Method that fetches the authentication form for the authentication process
        - Parameter bearerToken: String
        - Returns : Authentication form.  AuthForm struct is pending.
     */
    func getAuthForm(bearerToken: AuthTokenResult) async throws -> AuthForm {
        let url = URL(string: _config.domainURL! + ordsConfig.AUTHENTICATE_REST_EP )
                
        var request = URLRequest(url: url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken.token)", forHTTPHeaderField: "Authorization")
        
        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
     
        // 6. Check the response (similar to Utils.checkResponse in JavaScript)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Auth form retrieval.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response from server")
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Coulldn't form JSON object from response.")
        }
        
        if let jsonDictionary = jsonObject as? [String: Any] {
            let newAuthForm = AuthForm(USERNAME_PWD: jsonDictionary["USERNAME_PASSWORD"] as! [String : Any], applicationName: jsonDictionary["applicationName"] as! String, ecId: jsonDictionary["ecId"] as! String, keepMeSignedInEnabled: jsonDictionary["keepMeSignedInEnabled"] as! Int, nextAuthFactors: jsonDictionary["nextAuthFactors"] as! [String], nextOp: jsonDictionary["nextOp"] as! [String], requestState: jsonDictionary["requestState"] as! String, status: jsonDictionary["status"] as! String)
            return newAuthForm
        }
        
        throw AuthErrorUtilities.internalError(message: "Couldn't get authentication form.")
        
    }
    
    /**
        Helper method for getUserDetails that returns the APIUser object for the access token. The result of this will be modified with the result from the GET to /admin/v1/ME
     */
    func _getUserDetailsHelper(accessToken: AuthTokenResult) throws -> AuthUserInterface {
        let data = try AuthUtils.decodeOnly(jwtToken: accessToken.token)
        
        let newEmails = [["value": data["sub"] as? String ?? "-"]]
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

        
        let userData = AuthUserInterface(displayName: data["user_displayname"] as! String, emails: newEmails, phoneNumbers: phoneNumbers, metadata: meta, photos: photos, emailVerified: emailverified, idp_name: data["idp_name"] as! String, idp_type: data["idp_type"] as! String, id: data["user_id"] as! String)
        self.logger.info("Successfully created initial user from token.")
        return userData
    }
    
    /**
     Method that returns the details of an IDCS authenticated user
     - Parameter accessToken : IDToken
     - Returns : AuthUserInterface object
     */
    func _getUserDetailsIDCS(accessToken _: AuthTokenResult) async throws -> AuthUserInterface {
        
        // Read IDCS access token from Keychain; ignore passed parameter.
        guard let idcsAccessToken = KeychainTokenStore.shared.read(.idcsAccess), !idcsAccessToken.isEmpty else {
            throw AuthErrorUtilities.internalError(message: "No IDCS access token available for user details retrieval")
        }

        // Build a short-lived AuthTokenResult for initial user fields
        let effectiveAccessToken = try AuthTokenResult(token: idcsAccessToken, "idcsuser", tokenKey: .idcsAccess)

        // obtain token data
        var initialUser = try _getUserDetailsHelper(accessToken: effectiveAccessToken)
        
        let url = URL(string: _config.domainURL! + ordsConfig.SELF_ME_REST_EP)

        var request = URLRequest(url: url!)
        request.httpMethod = "GET"
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")

        // Securely add authorization header using token read from Keychain
        KeychainTokenStore.shared.withSecureToken(.idcsAccess) { token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
     
        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response from server")
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't form JSON object from response.")
        }
        
        if let jsonDictionary = jsonObject as? [String: Any] {
            initialUser.displayName = jsonDictionary["displayName"] as! String
            initialUser.ocid = jsonDictionary["ocid"] as! String
            
            
            // we access the emails and save the primary
            if let emailsArray = jsonDictionary["emails"] as? [[String: Any]] {
                for emailDict in emailsArray {
                    if emailDict["primary"] as! Int == 1 {
                        initialUser.emails = [["value": emailDict["value"] as! String]]
                    }
                    
                }
            }
            self.logger.info("Succesfully retrieved important information from server for user")
            return initialUser
        }
        
        throw AuthErrorUtilities.internalError(message: "Couldn't get user details for the IDCS user.")
    }
    
    
    /**
        Abstracted method that authenticates an IDCS user with a given email & password, retrieves their access token and creates a AuthUserCompleteDetails object
        - Parameter email : String
        - Parameter password : String
     */
    func authenticateAndGetDetails(email: String, password: String) async throws -> AuthUserCompleteDetails {

        // we call authenticateUser
        let authToken = try await authenticateIDCSUser(email: email, password: password)
        AuthLogger.info("authenticated user!")
        let profileTokens = try await self.getAccessToken(authnToken: authToken)
        AuthLogger.info("getting at ..")
        let fusabaseTokens = try await self.getFusabaseToken(authCredential: authToken, profileCredential: profileTokens)
        AuthLogger.info("getting ot ..")

        // Store the final FUSABASE tokens securely in keychain
        KeychainTokenStore.shared.write(fusabaseTokens.access_token, for: .access)
        if let refreshToken = fusabaseTokens.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }
        // Store IDCS tokens separately for IDCS operations
        if let idcsAccessToken = fusabaseTokens.idcs_access_token, !idcsAccessToken.isEmpty {
            KeychainTokenStore.shared.write(idcsAccessToken, for: .idcsAccess)
        }
        if let idcsRefreshToken = fusabaseTokens.idcs_refresh_token, !idcsRefreshToken.isEmpty {
            KeychainTokenStore.shared.write(idcsRefreshToken, for: .idcsRefresh)
        }

        guard let idcsAccessToken = fusabaseTokens.idcs_access_token else {
            throw AuthErrorUtilities.internalError(message: "IDCS access token not available for user details retrieval")
        }
        let userDetails = try await self._getUserDetailsIDCS(accessToken: try AuthTokenResult(token: fusabaseTokens.idcs_access_token!, "idcsuser", tokenKey: .idcsAccess))

        return AuthUserCompleteDetails(accessToken: try AuthTokenResult(token: fusabaseTokens.access_token, "idcsuser", tokenKey: .access), refreshToken: fusabaseTokens.refresh_token ?? "", authnToken: authToken, userInfo: userDetails)

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
            buildLoginURL: { codeChallenge, linkFlag in
                guard var components = URLComponents(string: ordsBaseURL + "social") else {
                    throw AuthErrorUtilities.internalError(message: "Unable to construct social login endpoint for IDCS.")
                }

                var queryItems = [
                    URLQueryItem(name: "device", value: "mobile"),
                    URLQueryItem(name: "apiKey", value: _config.appId),
                    URLQueryItem(name: "code_challenge", value: codeChallenge),
                    URLQueryItem(name: "code_challenge_method", value: "S256")
                ]

                if providerID != "idcs" {
                    queryItems.append(URLQueryItem(name: "link", value: linkFlag ? "1" : "0"))
                }

                components.queryItems = queryItems

                guard let url = components.url else {
                    throw AuthErrorUtilities.internalError(message: "Unable to construct social login URL for IDCS.")
                }

                return url
            },
            fetchTokens: { code in
                try await self.redirectResult(code: code)
            },
            mapTokensToDetails: { tokens in
                try await self.mapTokensToDetails(tokens: tokens)
            }
        )
    }

    private func mapTokensToDetails(tokens: BearerTokenResponse) async throws -> AuthUserCompleteDetails {
        // Exchange IDCS tokens for FUSABASE tokens
        let fusabaseTokens = try await self.getFusabaseToken(authCredential: AuthTokenResult(rawToken: "", tokenKey: .authn, persist: false), profileCredential: tokens)

        // Store the final FUSABASE tokens securely in keychain
        KeychainTokenStore.shared.write(fusabaseTokens.access_token, for: .access)
        if let refreshToken = fusabaseTokens.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }
        // Store IDCS tokens separately for IDCS operations
        if let idcsAccessToken = fusabaseTokens.idcs_access_token, !idcsAccessToken.isEmpty {
            KeychainTokenStore.shared.write(idcsAccessToken, for: .idcsAccess)
        }
        if let idcsRefreshToken = fusabaseTokens.idcs_refresh_token, !idcsRefreshToken.isEmpty {
            KeychainTokenStore.shared.write(idcsRefreshToken, for: .idcsRefresh)
        }

        guard let idcsAccessToken = fusabaseTokens.idcs_access_token else {
            throw AuthErrorUtilities.internalError(message: "IDCS access token not available for user details retrieval")
        }
        let userDetails = try await self._getUserDetailsIDCS(accessToken: try AuthTokenResult(token: idcsAccessToken, "idcsuser", tokenKey: .idcsAccess))

        return AuthUserCompleteDetails(accessToken: try AuthTokenResult(token: fusabaseTokens.access_token, "idcsuser", tokenKey: .access), refreshToken: fusabaseTokens.refresh_token ?? "", authnToken: nil, userInfo: userDetails)
    }
    
    /**
        Internal method to authenticate the user through IDCS.
        - Parameter email: String
        - Parameter password: String
        - Returns : AuthTokenResult object containing the authenticated user's information (should be changed into idtoken)
     
        ## This method shouldn't be exposed, it should be accessed through authenticateAndGetDetails to avoid ambiguous return types
     */
    func authenticateIDCSUser(email: String, password: String) async throws -> AuthTokenResult {

        // Fetch bearer token inline for authentication form
        let bearerToken = try await self.getValidBearerToken()
        let formResult = try await self.getAuthForm(bearerToken: bearerToken)
        let url = URL(string: _config.domainURL! + ordsConfig.AUTHENTICATE_REST_EP)
        AuthLogger.info("url: \(url!.absoluteString)")

        let body: [String: Any] = [
            "op": "credSubmit",
            "credentials": [
                "username": email,
                "password": password
            ],
            "requestState": formResult.requestState
        ]

        // 3. Serialize the body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            fatalError("Error serializing JSON")
        }

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsBearer) { token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = jsonData

        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. We check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response from server")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw NSError(domain: "Invalid JSON format", code: 1, userInfo: nil)
        }

        if let jsonDictionary = jsonObject as? [String: Any] {
            let authnToken = jsonDictionary["authnToken"] as? String ?? ""
            if authnToken.isEmpty {
                throw AuthErrorUtilities.internalError(message: "Couldn't form token for the authenticated user.")
            }
            let newtoken = try AuthTokenResult(token: authnToken, "idcsuser", tokenKey: .authn)
            return newtoken
        }

        throw AuthErrorUtilities.internalError(message: "Couldn't perform authentication. Please try again.")

    }
    
    /**
        Fetches access and refresh token for the authenticated user
        - Parameter authnToken: IdToken
        - Returns : access token and refresh tokens
     */

    func getAccessToken(authnToken: AuthTokenResult) async throws -> BearerTokenResponse {
        // url is not correct at the moment
        let url = URL(string: _config.domainURL! + ordsConfig.OAUTH_TOKEN_REST_EP)

        let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&scope=urn:opc:idm:__myscopes__+offline_access&assertion=\(authnToken.token)"


        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(_encodedSecret!)", forHTTPHeaderField: "Authorization")
        request.httpBody = body.data(using: .utf8)


        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response (similar to Utils.checkResponse in JavaScript)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Retrieve access token.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Received invalid HTTP response from server.")
        }

        if let tokens = try? JSONDecoder().decode(BearerTokenResponse.self, from: data) {
            return tokens
        }

        throw AuthErrorUtilities.internalError(message: "Couldn't fetch access token for the user")
    }

    /**
        Exchanges IDCS tokens for FUSABASE tokens
        - Parameter authCredential: AuthCredential containing authnToken and refresh_token
        - Parameter profileCredential: BearerTokenResponse containing access_token and refresh_token
        - Returns: BearerTokenResponse with FUSABASE tokens
     */
    func getFusabaseToken(authCredential: AuthTokenResult, profileCredential: BearerTokenResponse) async throws -> BearerTokenResponse {
        let url = URL(string: "\(_config.ordsHost):\(_config.ordsPort)/ords/\(_config.schema)/_/baas-services/idm/idcs/\(_config.projectId)/\(ordsConfig.TOKEN_EXCHANGE_PATH)")
        
        AuthLogger.info("url: \(url!.absoluteString)")

        let body: [String: Any] = [
            "token": profileCredential.access_token
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for token exchange.")
        }

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Exchange IDCS tokens for FUSABASE tokens.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Received invalid HTTP response from server.")
        }

        // Parse the response as a dictionary since it may not have all BearerTokenResponse fields
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse token exchange response.")
        }

        let fusabaseAccessToken = jsonObject["access_token"] as? String ?? ""
        let fusabaseRefreshToken = jsonObject["refresh_token"] as? String ?? ""

        // Return FUSABASE tokens with IDCS tokens embedded
        return BearerTokenResponse(
            access_token: fusabaseAccessToken,
            token_type: "Bearer",
            expires_in: 3600,  // Default expiration
            refresh_token: fusabaseRefreshToken,
            authn_token: authCredential.token,
            authn_refresh_token: "",  // TODO: Get from authCredential if available
            idcs_access_token: profileCredential.access_token,
            idcs_refresh_token: profileCredential.refresh_token
        )
    }
    
    /**
        Method that registers a user into IDCS (proxied via ORDS)
        - Parameter email: String
        - Parameter password: String
     */
    func registerUser(email: String, password: String) async throws {

        // Registration is proxied via ORDS to avoid exposing IDCS-sensitive parameters.
        guard let url = URL(string: ordsBaseURL + ordsConfig.SELF_REGISTER_EP) else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct ORDS user registration endpoint.")
        }

        let requestBody: [String: Any] = [
            "first_name": "-",
            "last_name": "-",
            "email": email,
            "password": password
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't serialize request body for user registration.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "User registration (IDCS via ORDS).")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

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
        // Use the existing IDCS access token for user details reload
        guard let idcsAccessToken = KeychainTokenStore.shared.read(.idcsAccess), !idcsAccessToken.isEmpty else {
            throw AuthErrorUtilities.internalError(message: "No IDCS access token available for user reload")
        }

        return try await self._getUserDetailsIDCS(accessToken: AuthTokenResult(token: idcsAccessToken, "idcsuser", tokenKey: .idcsAccess))
    }
    
    /**
        Method that sends the password reset emali
        - Parameter user: AuthUser
        - Parameter withEmail: String that contains the user's email
     */
    func sendPasswordResetHelper(withEmail: String) async throws {
        // Ensure we have a valid bearer token before making the request
        _ = try await getValidBearerToken()

        let url = URL(string: self._config.domainURL! + ordsConfig.SEND_PASSWORD_RESET_EMAIL)
        let copy = withEmail
        let emailDomain = copy.split(separator: "@")[1]

        let body: [String: Any] = [
            "userName": withEmail,
            "notificationType": "email",
            "notificationEmailAddress": "****@\(emailDomain)",
            "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:MePasswordResetRequestor"]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse JSON body for password reset request.")
        }

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsBearer) { token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Send password reset email.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

    }
    
    /**
        Method that verifies the password reset code
        - Parameter token: String containing the verification token
        - Returns: Dictionary with the verification result
     */
    func verifyPasswordResetCodeHelper(code: String) async throws -> [String: Any] {
        // Ensure we have a valid bearer token before making the request
        _ = try await getValidBearerToken()

        let url = URL(string: self._config.domainURL! + ordsConfig.VERIFY_PASSWORD_RESET_CODE)

        let body: [String: Any] = [
            "token": code,
            "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:UserTokenValidator"]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse JSON body for verifying password reset code.")
        }

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsBearer) { token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Verify password reset code (IDCS).")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse verify password reset response.")
        }
        return jsonObject
    }
    
    /**
        Method that confirms the password reset with new password (IDCS)
        - Parameters:
            - token: String containing the verification token
            - newPassword: New password to set
        - Returns: Dictionary with the confirmation result
     */
    func confirmPasswordResetHelper(code: String, newPassword: String) async throws -> [String: Any] {
        // Ensure we have a valid bearer token before making the request
        _ = try await getValidBearerToken()

        let url = URL(string: self._config.domainURL! + ordsConfig.CONFIRM_PASSWORD_RESET)

        let body: [String: Any] = [
            "token": code,
            "password": newPassword,
            "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:MePasswordResetter"]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse JSON body for confirming password reset.")
        }

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = jsonData

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsBearer) { token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Confirm password reset (IDCS).")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse confirm password reset response.")
        }
        return jsonObject
    }
    
    /**
        Abstracted method that performs the sign out for authenticated users
        - Parameter refreshToken: String
     */
    func performSignOut(refreshToken: String) async throws {
        // perform signout
        try await self.performSignOutIDCS()
        // revoke refreshtoken
        try await self.revokeRefreshToken(refreshToken: refreshToken)
    }
    
    /**
        Internal method that performs the signout from ORDS for an authenticated user
     */
    func performSignOutIDCS() async throws {
        let url = URL(string: self._config.domainURL! + ordsConfig.LOGOUT_REST_EP)
        
        var request = URLRequest(url: url!)
        request.httpMethod = "GET"
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")
        
        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
     
        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Perform signout for authenticated user through IDCS.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Received invalid HTTP response from server.")
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

        let url = URL(string: self._config.domainURL! + ordsConfig.REVOKE_REFRESH_TOKEN_REST_EP)

        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(self._encodedSecret!)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.httpBody = "token=\(refreshToken)".data(using: .utf8)

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Revoke a refresh token for an authenticated user through IDCS.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Received invalid HTTP response from server.")
        }
    }

    func signInWithCredential(with credential: AuthCredential) async throws -> AuthUserCompleteDetails {
        let tokens = try await self.signInWithCredentialHelper(credential: credential, link: false)

        KeychainTokenStore.shared.write(tokens.access_token, for: .access)
        if let refreshToken = tokens.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }
        // Store IDCS tokens
        if let idcsAccessToken = tokens.idcs_access_token, !idcsAccessToken.isEmpty {
            KeychainTokenStore.shared.write(idcsAccessToken, for: .idcsAccess)
        }
        if let idcsRefreshToken = tokens.idcs_refresh_token, !idcsRefreshToken.isEmpty {
            KeychainTokenStore.shared.write(idcsRefreshToken, for: .idcsRefresh)
        }

        guard let idcsAccessToken = tokens.idcs_access_token else {
            throw AuthErrorUtilities.internalError(message: "No IDCS access token available for user details retrieval")
        }
        let userDetails = try await self._getUserDetailsIDCS(accessToken: AuthTokenResult(token: idcsAccessToken, "idcsuser", tokenKey: .idcsAccess))

        let accessToken = try AuthTokenResult(token: tokens.access_token, "idcsuser", tokenKey: .access)
        return AuthUserCompleteDetails(accessToken: accessToken,
                                       refreshToken: tokens.refresh_token ?? "",
                                       authnToken: nil,
                                       userInfo: userDetails)
    }

    func signInWithCredentialLinking(credential: AuthCredential, link: Bool) async throws -> AuthUserCompleteDetails {
        let tokens = try await self.signInWithCredentialHelper(credential: credential, link: link)

        KeychainTokenStore.shared.write(tokens.access_token, for: .access)
        if let refreshToken = tokens.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }
        // Store IDCS tokens
        if let idcsAccessToken = tokens.idcs_access_token, !idcsAccessToken.isEmpty {
            KeychainTokenStore.shared.write(idcsAccessToken, for: .idcsAccess)
        }
        if let idcsRefreshToken = tokens.idcs_refresh_token, !idcsRefreshToken.isEmpty {
            KeychainTokenStore.shared.write(idcsRefreshToken, for: .idcsRefresh)
        }

        guard let idcsAccessToken = tokens.idcs_access_token else {
            throw AuthErrorUtilities.internalError(message: "No IDCS access token available for user details retrieval")
        }
        let userDetails = try await self._getUserDetailsIDCS(accessToken: AuthTokenResult(token: idcsAccessToken, "idcsuser", tokenKey: .idcsAccess))

        let accessToken = try AuthTokenResult(token: tokens.access_token, "idcsuser", tokenKey: .access)
        return AuthUserCompleteDetails(accessToken: accessToken,
                                       refreshToken: tokens.refresh_token ?? "",
                                       authnToken: nil,
                                       userInfo: userDetails)
    }

    private func signInWithCredentialHelper(credential: AuthCredential, link: Bool) async throws -> BearerTokenResponse {
        guard var components = URLComponents(string: ordsBaseURL + "getcredential") else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct credential exchange endpoint for IDCS.")
        }

        var queryItems = [
            URLQueryItem(name: "apiKey", value: _config.appId),
            URLQueryItem(name: "smethod", value: credential.provider)
        ]

        if link {
            queryItems.append(URLQueryItem(name: "link", value: "true"))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw AuthErrorUtilities.internalError(message: "Unable to build credential URL for IDCS.")
        }

        let password = link ? (KeychainTokenStore.shared.read(.userPassword) ?? "") : ""
        let requestBody: [String: Any] = [
            "token": try credential.getIdToken(),
            "password": password
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for IDCS credential sign-in.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response from IDCS credential exchange.")
        }

        guard let tokens = try? JSONDecoder().decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't decode token response from IDCS credential exchange.")
        }

        return tokens
    }

    func socialUnlinkHelper(provider: String) async throws -> AuthUserCompleteDetails {
        let tokens = try await self.socialUnlinkHelperInternal(provider: provider)

        KeychainTokenStore.shared.write(tokens.access_token, for: .access)
        if let refreshToken = tokens.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }
        // Store IDCS tokens
        if let idcsAccessToken = tokens.idcs_access_token, !idcsAccessToken.isEmpty {
            KeychainTokenStore.shared.write(idcsAccessToken, for: .idcsAccess)
        }
        if let idcsRefreshToken = tokens.idcs_refresh_token, !idcsRefreshToken.isEmpty {
            KeychainTokenStore.shared.write(idcsRefreshToken, for: .idcsRefresh)
        }

        guard let idcsAccessToken = tokens.idcs_access_token else {
            throw AuthErrorUtilities.internalError(message: "No IDCS access token available for user details retrieval")
        }
        let userDetails = try await self._getUserDetailsIDCS(accessToken: AuthTokenResult(token: idcsAccessToken, "idcsuser", tokenKey: .idcsAccess))

        let accessToken = try AuthTokenResult(token: tokens.access_token, "idcsuser", tokenKey: .access)
        return AuthUserCompleteDetails(accessToken: accessToken,
                                       refreshToken: tokens.refresh_token ?? "",
                                       authnToken: nil,
                                       userInfo: userDetails)
    }

    private func socialUnlinkHelperInternal(provider: String) async throws -> BearerTokenResponse {
        guard var components = URLComponents(string: ordsBaseURL + "socialunlink") else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct social unlink endpoint for IDCS.")
        }

        components.queryItems = [
            URLQueryItem(name: "apiKey", value: _config.appId),
            URLQueryItem(name: "provider", value: provider)
        ]

        guard let url = components.url else {
            throw AuthErrorUtilities.internalError(message: "Unable to build social unlink URL for IDCS.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data()

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response from IDCS social unlink.")
        }

        guard let tokens = try? JSONDecoder().decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't decode token response from IDCS social unlink.")
        }

        return tokens
    }

    private func redirectResult(code: String) async throws -> BearerTokenResponse {
        guard var components = URLComponents(string: ordsBaseURL + "redirectResult") else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct redirect result endpoint for IDCS.")
        }

        components.queryItems = [
            URLQueryItem(name: "apiKey", value: _config.appId)
        ]

        guard let url = components.url else {
            throw AuthErrorUtilities.internalError(message: "Unable to build redirect result URL for IDCS.")
        }

        let verifier = KeychainTokenStore.shared.read(.codeVerifier) ?? ""

        let requestBody: [String: Any] = [
            "code": code,
            "code_verifier": verifier
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for IDCS redirect result.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response from IDCS redirect result.")
        }

        guard let tokens = try? JSONDecoder().decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't decode token response from IDCS redirect result.")
        }

        return tokens
    }
}
