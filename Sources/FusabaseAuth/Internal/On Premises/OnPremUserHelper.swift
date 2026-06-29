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
import FusabaseCore

// Internal class for the OnPrem/Basic auth type User
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
class OnPremUserHelper: UserHelperProtocol {

    private var _config: FusabaseOptions
    private var _user: FusabaseUser?
    private var ordsConfig: OnPremConfigHelper


    init(config: FusabaseOptions, accessToken: AuthTokenResult?, authToken: Any? = nil) {
        self._config = config
        self._user = nil

        let domainurl = _config.ordsHost + ":" + _config.ordsPort + "/ords/" + _config.schema + "/_/baas-services/idm/onprem/" + _config.projectId + "/"
        self.ordsConfig = OnPremConfigHelper(_domainURL: domainurl, _appID: _config.appId)
    }
    
    /**
        # func _checkForUser
        Internal method to check if the user is nil
     */
    func _checkForUser() throws {
        if _user == nil {
            fatalError("No active user")
        }
    }
    
    /**
        Internal method that returns the operations in the specified format
        - Parameter currentUserProfile: User
        - Parameter newUserProfile: UserProfile
        - Returns [[String: Any]]
     */
    func _getOperations(_ currentUserProfile: FusabaseUser, newUserProfile: UserProfile) -> [[String: Any]] {
        
        var operations: [[String: Any]] = []
        
        // If we need to modify the display name
        if newUserProfile.displayName != nil {
            
            var operation: [String: Any] = [
                "op": "replace",
                "path": "displayName",
                "value": newUserProfile.displayName!
            ]
            
            if currentUserProfile.displayName.isEmpty {
                operation.updateValue("add", forKey: "op")
            }
            
            operations.append(operation)
        }
        
        // If we need to modify the phone number
        if newUserProfile.phoneNumber != nil {
            
            var operation: [String: Any] = [
                "op": "replace",
                "path": "phoneNumber",
                "value": newUserProfile.phoneNumber!
            ]
            
            if currentUserProfile.phoneNumber.isEmpty {
                operation.updateValue("add", forKey: "op")
            }
            
            operations.append(operation)
        }
        
        return operations
    }
    
    /**
        # func refreshAccessToken(refreshToken: String) async -> String?
        - Parameter refreshToken: string containing the refresh token to fetch a new access token
        - Returns : dictionary object containing accessToken and refreshToken
     */
    
    func refreshAccessToken(refreshToken: String) async throws -> BearerTokenResponse {
        
        // 1. request url
        let url = URL(string: ordsConfig.domainURL + ordsConfig.AUTHENTICATE_REST_EP )
        
        let requestBody: [String: Any] = [
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't serialize body for refreshAccessToken.")
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
        
        // 7. parsing
        let decoder = JSONDecoder()
        guard let userDetails = try? decoder.decode(BearerTokenResponse.self, from: data) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse the user's details.")
        }

        // Store the refreshed tokens securely in keychain
        KeychainTokenStore.shared.write(userDetails.access_token, for: .access)
        if let refreshToken = userDetails.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        }

        return userDetails
    }
    
    /**
        # func updatePasswordHelper
        Internal helper function that makes the API call for /changePassword
        - Parameter oldPassword: string containing the old password
        - Parameter newPassword: string containing the new password for the user
     */

    func updatePasswordHelper(_ user: FusabaseUser, oldPassword: String, newPassword: String) async throws {
        
        let access_token = try await user.getIDToken()
        
        let url = URL(string: ordsConfig.domainURL + ordsConfig.UPDATE_PASSWORD_HELPER)
    
        // 2. Create the JSON body
        let requestBody: [String: Any] = [
            "oldPassword": oldPassword,
            "password": newPassword
        ]
        
        
        // 3. Serialize the body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            fatalError("Error serializing JSON")
        }
        
        // 4. Create the URLRequest
        var request = URLRequest(url: url!)
        request.httpMethod = "PUT"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(access_token, forHTTPHeaderField: "X-AUTHZ" )
        

        // 5. Perform the request and await the response
        let (data, response) = try await SecureNetworking.secureSession.data(for: request)

        // 6. Check the response (similar to Utils.checkResponse in JavaScript)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
    }
    
    /**
        # func updateProfileHelper(newUserProfile: UserProfile)
        - Parameter newUserProfile: the object containing the updates needed for the user
        - Returns: void function
     
     */
    func updateProfileHelper(_ user: FusabaseUser, newUserProfile: UserProfile) async throws {
        
        let url = URL(string: ordsConfig.domainURL + ordsConfig.UPDATE_PROFILE_HELPER )
        
        // 2. Create the JSON body
        let requestBody = [
            "Operations": _getOperations(user, newUserProfile: newUserProfile)
        ]
        
        
        // 3. Serialize the body to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse request body for update profile operations.")
        }
        
        let access_token = try await user.getIDToken(forcingRefresh: true)
        
        // 4. Create the URLRequest
        var request = URLRequest(url: url!)
        request.httpMethod = "PUT"
        request.httpBody = jsonData
        request.setValue(access_token, forHTTPHeaderField: "X-AUTHZ" )
        request.setValue("application/json", forHTTPHeaderField: "Content-type")
        
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // Check response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
    }
    
    
    /**
        Method that allows a user to verify their email through email verification.
        - Parameter user: AuthUser
     */
    func sendEmailVerificationHelper(_ user: FusabaseUser, withEmail: String, uid: Any) async throws {
        
        let email: String
        
        if let encodedEmail = withEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            email = encodedEmail
        } else {
            throw AuthErrorUtilities.invalidEmailError(message: "Invalid email given for verification.")
        }

        
        let url = URL(string: ordsConfig.domainURL + ordsConfig.SEND_EMAIL_VERIFICATION + "&email=" + email + "&requesttype=verifyemail")
        
        
        let access_token = try await user.getIDToken()
        
        var req = URLRequest(url: url!)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access_token)", forHTTPHeaderField: "Authorization")

        
        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: req)

        // 6. Check the response (similar to Utils.checkResponse in JavaScript)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Obtained a non-valid HTTP response.")
        }
        
    }
    
    func linkWithCredential(_ user: FusabaseUser, credential: AuthCredential) async throws {
        if let emailCredential = credential as? EmailAuthCredential {
            try Self.validateEmailCredentialForLinking(emailCredential, currentUserEmail: user.email)
        }
        
        let authHelper = OnPremAuthHelper(config: _config)
        _ = try await authHelper.signInWithCredentialLinking(credential: credential, link: true)
       
    }

    static func validateEmailCredentialForLinking(_ credential: EmailAuthCredential, currentUserEmail: String) throws {
        let credentialEmail = credential.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrentUserEmail = currentUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !credentialEmail.isEmpty,
              !normalizedCurrentUserEmail.isEmpty,
              credentialEmail.caseInsensitiveCompare(normalizedCurrentUserEmail) == .orderedSame else {
            throw AuthErrorUtilities.invalidCredential(message: "Email credential must match the currently signed-in user's email.")
        }
    }

    static func withProviderLinkingState<T>(_ operation: () async throws -> T) async throws -> T {
        KeychainTokenStore.shared.write("true", for: .linking)

        do {
            return try await operation()
        } catch {
            KeychainTokenStore.shared.delete(.linking)
            throw error
        }
    }

    func linkWithCredential(_ user: FusabaseUser, provider: AuthProvider) async throws {
        _ = user // Link flow triggers UI, updated user fetched via reload afterward.
        let callbackScheme = "baasmobile" + _config.appId.lowercased()

        #if canImport(UIKit)
        guard #available(iOS 15.0, tvOS 15.0, *) else {
            throw AuthErrorUtilities.operationNotAllowed(message: "Linking with redirect-based flows requires iOS/tvOS 15 or newer.")
        }

        let authHelper = OnPremAuthHelper(config: _config)

        try await Self.withProviderLinkingState {
            // Perform OAuth redirect flow - the linking flag will be checked in mapTokensToDetails
            let redirectResult = try await authHelper.signInWithRedirectHelper(providerID: provider.providerID,
                                                                              callbackScheme: callbackScheme,
                                                                              presentationContext: DefaultWebAuthProvider.shared,
                                                                              link: true)

            // Extract the access token from the result to create credential
            let credential = AuthCredential(provider: provider.providerID, idToken: redirectResult.accessToken.token)

            // Use the credential for linking
            _ = try await authHelper.signInWithCredentialLinking(credential: credential, link: true)
        }

        #else
        throw AuthErrorUtilities.operationNotAllowed(message: "Linking with redirect-based flows is not supported on this platform.")
        #endif
    }
    
}
