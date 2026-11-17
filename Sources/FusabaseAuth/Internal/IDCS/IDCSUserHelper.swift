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

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
class IDCSUserHelper: UserHelperProtocol {
    private let middleware: IDCSMiddlewareClient
    private var logger = Logger(subsystem: "com.oracle.database.fusabase", category: "IDCSUserHelper")

    init(_ config: FusabaseOptions, _accessToken: AuthTokenResult?) {
        self.middleware = IDCSMiddlewareClient(config: config)
    }
    
    /**
        Method that refreshes the user's access token utilizing the refresh token
        - Parameter refreshToken: String
        - Returns tokens: Object containing access token and refresh token
     */
    func refreshAccessToken(refreshToken: String) async throws -> BearerTokenResponse {
        let e: BearerTokenResponse = try await middleware.sendDecodable(
            endpoint: middleware.endpoints.AUTHENTICATE_PATH,
            method: "POST",
            body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ],
            methodDescription: "refreshAccessToken"
        )

        IDCSMiddlewareClient.persistNormalizedTokens(e)
        return e
    }

    func updatePasswordHelper(_ user: FusabaseUser, oldPassword: String, newPassword: String) async throws {
        let accessToken = try await user.getIDToken()
        _ = try await middleware.send(
            endpoint: middleware.endpoints.CHANGE_PASSWORD_PATH,
            method: "PUT",
            body: [
                "oldPassword": oldPassword,
                "password": newPassword
            ],
            headers: ["Authorization": "Bearer \(accessToken)"],
            methodDescription: "Update IDCS user password through ORDS."
        )

        self.logger.info("Successfully updated the authenticated user's password.")
    }

    func updateProfileHelper(_ user: FusabaseUser, newUserProfile: UserProfile) async throws {
        var body: [String: Any] = [:]
        if let displayName = newUserProfile.displayName {
            body["displayName"] = displayName
        }
        if let phoneNumber = newUserProfile.phoneNumber {
            body["phoneNumbers"] = [[
                "value": phoneNumber,
                "type": "mobile",
                "primary": true
            ]]
        }
        if let photoURL = newUserProfile.photoURL {
            body["photos"] = [[
                "value": photoURL,
                "type": "photo",
                "primary": true
            ]]
        }

        if body.isEmpty {
            return
        }

        let accessToken = try await user.getIDToken()
        _ = try await middleware.send(
            endpoint: middleware.endpoints.PROFILE_PATH,
            method: "PUT",
            body: body,
            headers: ["Authorization": "Bearer \(accessToken)"],
            methodDescription: "Update IDCS user profile through ORDS."
        )

        self.logger.info("Successfully updated the authenticated user's profile.")
    }

    /**
        Method that allows a user to verify their email through email verification.
        - Parameter user: AuthUser
     */
    func sendEmailVerificationHelper(_ user: FusabaseUser, withEmail: String, uid: Any) async throws {
        throw AuthErrorUtilities.operationNotAllowed(message: "IDCS email verification is not supported by ORDS.")
    }
    
    func linkWithCredential(_ user: FusabaseUser, credential: AuthCredential) async throws {
        throw AuthErrorUtilities.operationNotAllowed(message: "Linking is not supported for IDCS authentication.")
    }

    func linkWithCredential(_ user: FusabaseUser, provider: AuthProvider) async throws {
        throw AuthErrorUtilities.operationNotAllowed(message: "Linking is not supported for IDCS authentication.")
    }
}
