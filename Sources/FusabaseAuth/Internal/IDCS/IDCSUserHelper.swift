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
class IDCSUserHelper: UserHelperProtocol {
    private var _encodedSecret: String?
    private var _config: FusabaseOptions
    private var _user: FusabaseUser?
    private var ordsConfig: IDCSConfigHelper
    private var logger = Logger(subsystem: "com.oracle.database.fusabase", category: "IDCSUserHelper")
    
    private var ordsBaseURL: String {
        "\(_config.ordsHost):\(_config.ordsPort)/ords/\(_config.schema)/_/baas-services/idm/idcs/\(_config.projectId)/"
    }

    init(_ config: FusabaseOptions, _accessToken: AuthTokenResult?, authnToken: Any? = nil) {
        self._encodedSecret = AuthUtils.btoa("\(config.clientID!):\(config.clientSecret!)")
        self._config = config
        self._user = nil

        ordsConfig = IDCSConfigHelper(_domainURL: _config.domainURL!, _appID: _config.appId, _clientID: _config.clientID!, _clientSecret: _config.clientSecret!)
    }
    
    /**
        Private method that returns the operations in the needed format for the server
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
        Method that refreshes the user's access token utilizing the refresh token
        - Parameter refreshToken: String
        - Returns tokens: Object containing access token and refresh token
     */
    func refreshAccessToken(refreshToken: String) async throws -> BearerTokenResponse {
        let url = URL(string: _config.domainURL! + ordsConfig.OAUTH_TOKEN_REST_EP)
        
        // 2. Create the JSON body
        let requestBody: String = "grant_type=refresh_token&refresh_token=\(refreshToken)&scope=offline_access"
        
        // Create the URLRequest
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.httpBody = requestBody.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(_encodedSecret!)", forHTTPHeaderField: "Authorization")

        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response (similar to Utils.checkResponse in JavaScript)
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "refreshAccessToken")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

        let e = try JSONDecoder().decode(BearerTokenResponse.self, from: data)

        // Store the refreshed IDCS tokens securely in keychain
        KeychainTokenStore.shared.write(e.access_token, for: .idcsAccess)
        if let refreshToken = e.refresh_token, !refreshToken.isEmpty {
            KeychainTokenStore.shared.write(refreshToken, for: .idcsRefresh)
        }

        return e
    }
    
    func updatePasswordHelper(_ user: FusabaseUser, oldPassword: String, newPassword: String) async throws {
        let url = URL(string: _config.domainURL! + ordsConfig.UPDATE_PASSWORD_HELPER)
        
        let body: [String: Any] = [
            "oldPassword": oldPassword,
            "password": newPassword,
            "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:MePasswordChanger"]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse body for updatePasswordHelper")
        }
        
        var request = URLRequest(url: url!)
        request.httpMethod = "PUT"

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsAccess) { token in
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/scim+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

        self.logger.info("Successfully updated the authenticated user's password.")
    }
    
    func updateProfileHelper(_ user: FusabaseUser, newUserProfile: UserProfile) async throws {
        
        let url = URL(string: _config.domainURL! + ordsConfig.SELF_ME_REST_EP)
        
        let body: [String: Any] = [
            "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
            "Operations": self._getOperations(user, newUserProfile: newUserProfile)
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse body for updateProfileHelper method.")
        }
        
        var request = URLRequest(url: url!)
        request.httpMethod = "PATCH"
        request.httpBody = jsonData
        request.setValue("application/scim+json", forHTTPHeaderField: "Content-Type")

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsAccess) { token in
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }


        // 5. Perform the request and await the response
        let (data, response) = try await AuthUtils.fusabaseCall(for: request)

        // 6. Check the response
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data)
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }

        self.logger.info("Successfully updated the authenticated user's profile.")
    }
    
    
    /**
        Method that allows a user to verify their email through email verification.
        - Parameter user: AuthUser
     */
    func sendEmailVerificationHelper(_ user: FusabaseUser, withEmail: String, uid: Any) async throws {
        let url = URL(string: self._config.domainURL! + ordsConfig.SEND_EMAIL_VERIFICATION)
        
        let body: [String: Any] = [
            "id": uid,
            "email": withEmail,
            "schemas": ["urn:ietf:params:scim:schemas:oracle:idcs:MeEmailVerifier"],
            "meta": [
                "resourceType": "MeEmailVerifier"
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse the body to create a JSON body.")
        }
        
        var request = URLRequest(url: url!)
        request.httpMethod = "PUT"

        // Securely add authorization header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.idcsAccess) { token in
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, response) = try await SecureNetworking.secureSession.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            try AuthUtils.checkResponse(response: httpResponse, data: data, method: "Send Email Verification.")
        } else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }
        
    }
    
    func linkWithCredential(_ user: FusabaseUser, credential: AuthCredential) async throws {
        throw AuthErrorUtilities.operationNotAllowed(message: "Linking is not supported for IDCS authentication.")
    }

    func linkWithCredential(_ user: FusabaseUser, provider: AuthProvider) async throws {
        throw AuthErrorUtilities.operationNotAllowed(message: "Linking is not supported for IDCS authentication.")
    }
}
