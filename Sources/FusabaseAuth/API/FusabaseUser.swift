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

/**
 A user account and profile associated with the current authentication context.
 
 Use this type to access profile information and to perform user-related operations such as:
 - Retrieving ID tokens
 - Refreshing the user
 - Updating the password and profile
 - Sending email verification
 - Linking and unlinking authentication providers
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class FusabaseUser: NSObject {
    // MARK: - Public properties

    /// The user's display name.
    open var displayName: String
    /// The user's primary email address.
    open var email: String
    /// The user's primary phone number.
    var phoneNumber: String

    /// The unique user identifier.
    open var uid: String
    
    var userProfile: UserProfileChangeRequest?
    
    /// Identifier for the primary authentication provider.
    open var providerID: String
    /// Information about the user from linked identity providers.
    open var providerData: [UserInfo]
    /// Refresh token is never stored in memory; read/write through Keychain only.
    var refreshToken: String? {
        get { KeychainTokenStore.shared.read(.refresh) }
        set { KeychainTokenStore.shared.write(newValue, for: .refresh) }
    }
    /// Indicates whether this user is anonymous.
    public internal(set) var isAnonymous: Bool
    /// Indicates whether the user's email address has been verified.
    public private(set) var isEmailVerified: Bool
    /// Metadata associated with the user (creation date, last sign-in date).
    public private(set) var metadata: FusabaseUserMetadata
    
    // MARK: - Internal state

    private var _config: FusabaseOptions
    private var _auth: FusabaseAuth
    /// Identity provider type name.
    open var idp_type: String

    
    // Helpers
    private var _authHelper: AuthHelperProtocol
    private var _userHelper: UserHelperProtocol
    
    private var logger = Logger(subsystem: "com.oracle.database.fusabase", category: "user")

    // MARK: - Initialization
    
    /// Internal initializer used by the authentication system to construct a user instance.
    /// - Parameters:
    ///   - user: Parsed user information.
    ///   - userRefreshToken: The refresh token for the user.
    ///   - accessToken: The access token result in use for this user.
    ///   - auth: The authentication instance associated with this user.
    ///   - authToken: Reserved for future use.
    init (user: AuthUserInterface, userRefreshToken: String, accessToken: AuthTokenResult, auth: FusabaseAuth, authToken: Any? = nil) {
        self.displayName = user.displayName
        self.email = user.emails[0]["value"] ?? "-"
        self.isEmailVerified = (user.emailVerified == "true" || user.emailVerified == "1")
        self.uid = user.id
        self._config = auth.config!
        if !userRefreshToken.isEmpty { KeychainTokenStore.shared.write(userRefreshToken, for: .refresh) }
        self.phoneNumber = user.phoneNumbers[0]["num"] ?? "-"
        self._auth = auth
        self.idp_type = user.idp_type
        self.isAnonymous = false
        self.providerID = user.idp_name
        self.providerData = [FusabaseUserInfoImpl(providerID: user.idp_name, uid: user.id, displayName: user.displayName, email: self.email, phoneNumber: self.phoneNumber)]
        self.metadata = FusabaseUserMetadata(lastSignInDate: Date(), creationDate: Date())
        
        if _config.authType == "idcs" {
            self._userHelper = IDCSUserHelper(_config, _accessToken: accessToken)
            self._authHelper = IDCSAuthHelper(_config: auth.config!)
        } else {
            self._userHelper = OnPremUserHelper(config: _config, accessToken: accessToken)
            self._authHelper = OnPremAuthHelper(config: auth.config!)
        }
        
        super.init()
    }
    
    /// Refreshes this instance with updated values.
    private func refreshUser(user: AuthUserInterface, userRefreshToken: String, accessToken: AuthTokenResult, auth: FusabaseAuth, authToken: Any? = nil) {
        self.displayName = user.displayName
        self.email = user.emails[0]["value"] ?? "-"
        self.isEmailVerified = (user.emailVerified == "true" || user.emailVerified == "1")
        self.uid = user.id
        self._config = auth.config!
        if !userRefreshToken.isEmpty { KeychainTokenStore.shared.write(userRefreshToken, for: .refresh) }
        self.phoneNumber = user.phoneNumbers[0]["num"] ?? "-"
        self._auth = auth
        self.isAnonymous = false
        self.providerID = user.idp_name
        self.idp_type = user.idp_type
        self.providerData = [FusabaseUserInfoImpl(providerID: user.idp_name, uid: user.id, displayName: user.displayName, email: self.email, phoneNumber: self.phoneNumber)]
        
        if _config.authType == "idcs" {
            self._userHelper = IDCSUserHelper(_config, _accessToken: accessToken)
            self._authHelper = IDCSAuthHelper(_config: auth.config!)
        } else {
            self._userHelper = OnPremUserHelper(config: _config, accessToken: accessToken)
            self._authHelper = OnPremAuthHelper(config: auth.config!)
        }
        
        // Persist latest tokens
        KeychainTokenStore.shared.write(accessToken.token, for: .access)
        if !userRefreshToken.isEmpty { KeychainTokenStore.shared.write(userRefreshToken, for: .refresh) }
    }
    
    // MARK: - Public API
    
    /// Returns whether the user's email is verified.
    open func emailVerified() -> Bool {
        return self.isEmailVerified
    }
    
    /// Creates a new profile change request for this user.
    open func createProfileChangeRequest() -> UserProfileChangeRequest {
        return UserProfileChangeRequest(_user: self)
    }
    
    /// Temporary internal setter for access and refresh tokens.
    /// This does not keep tokens in memory; it persists them to Keychain.
    func updateTokens(accessToken: String, refreshToken: String) {
        KeychainTokenStore.shared.write(accessToken, for: .access)
        if !refreshToken.isEmpty { KeychainTokenStore.shared.write(refreshToken, for: .refresh) }
    }
    
    /// Returns whether the user is anonymous.
    open func anonymous() -> Bool {
        return isAnonymous
    }
    
    /// Returns the current access token without forcing a refresh.
    open func getIDToken() -> String {
        return KeychainTokenStore.shared.read(.access) ?? ""
    }
    
    /// Returns an access token, optionally forcing a refresh if requested or if the token is invalid.
    /// - Parameter forceRefresh: If true, forces retrieval of a new access token.
    open func getIDToken(forcingRefresh forceRefresh: Bool = false) async throws -> String {
        let userType = self._config.authType == "idcs" ? "idcsuser" : "basic"

        // Read current access token from Keychain
        var currentAccess = KeychainTokenStore.shared.read(.access) ?? ""

        // Decide if we must refresh
        var needsRefresh = forceRefresh || currentAccess.isEmpty
        if !needsRefresh {
            do {
                let parsed = try AuthTokenResult(token: currentAccess, userType, tokenKey: .access)
                needsRefresh = !parsed._validateAccessToken()
            } catch {
                needsRefresh = true
            }
        }

        if needsRefresh {
            do {
                if self._config.authType == "idcs" {
                    // Use IDCS refresh token to obtain a new IDCS access token, then exchange to FUSABASE access
                    guard let idcsRT = KeychainTokenStore.shared.read(.idcsRefresh), !idcsRT.isEmpty else {
                        throw AuthErrorUtilities.invalidCredential(message: "Missing IDCS refresh token to refresh access token.")
                    }
                    guard let idcsUserHelper = self._userHelper as? IDCSUserHelper else {
                        throw AuthErrorUtilities.internalError(message: "IDCS refresh not available in current context")
                    }
                    let idcsResp = try await idcsUserHelper.refreshAccessToken(refreshToken: idcsRT)
                    // Exchange to FUSABASE tokens using the refreshed IDCS access token
                    guard let idcsAuthHelper = self._authHelper as? IDCSAuthHelper else {
                        throw AuthErrorUtilities.internalError(message: "IDCS token exchange not available in current context")
                    }
                    let fusabaseTokens = try await idcsAuthHelper.getFusabaseToken(authCredential: AuthTokenResult(rawToken: "", tokenKey: .authn, persist: false), profileCredential: idcsResp)
                    // Persist FUSABASE tokens
                    KeychainTokenStore.shared.write(fusabaseTokens.access_token, for: .access)
                    currentAccess = fusabaseTokens.access_token
                    if let newRefresh = fusabaseTokens.refresh_token, !newRefresh.isEmpty {
                        KeychainTokenStore.shared.write(newRefresh, for: .refresh)
                    }
                    // Persist IDCS tokens if provided
                    if let ia = fusabaseTokens.idcs_access_token, !ia.isEmpty {
                        KeychainTokenStore.shared.write(ia, for: .idcsAccess)
                    }
                    if let ir = fusabaseTokens.idcs_refresh_token, !ir.isEmpty {
                        KeychainTokenStore.shared.write(ir, for: .idcsRefresh)
                    }
                } else {
                    // On-prem: use local refresh token flow
                    guard let rt = self.refreshToken, !rt.isEmpty else {
                        throw AuthErrorUtilities.invalidCredential(message: "Missing refresh token to refresh access token.")
                    }
                    let resp = try await self._userHelper.refreshAccessToken(refreshToken: rt)
                    KeychainTokenStore.shared.write(resp.access_token, for: .access)
                    currentAccess = resp.access_token
                    if let newRefresh = resp.refresh_token, !newRefresh.isEmpty {
                        KeychainTokenStore.shared.write(newRefresh, for: .refresh)
                    }
                }
            } catch let error as NSError {
                self.logger.error("Couldn't refresh access token: \(error.localizedDescription)")
                throw error
            } catch {
                throw AuthErrorUtilities.invalidCredential(message: "Couldn't refresh access token. Will now sign out current user.")
            }
        }

        return currentAccess
    }
    
    /// Returns the parsed token result for the current access token.
    /// - Parameter forceRefresh: If true, forces retrieval of a new access token before parsing.
    open func getIDTokenResult(_ forceRefresh: Bool) async throws -> AuthTokenResult {
        let userType = self._config.authType == "idcs" ? "idcsuser" : "basic"
        let token = try await getIDToken(forcingRefresh: forceRefresh)
        return try AuthTokenResult(token: token, userType, tokenKey: .access)
    }
    
    /// Reloads the user's profile and refreshes local state.
    open func reload() async throws {
        // Ensure the underlying access token is refreshed.
        // For IDCS this will refresh IDCS tokens and perform tokenExchange to obtain
        // a fresh FUSABASE/ORDS ACCESS_TOKEN.
        _ = try await self.getIDToken(forcingRefresh: true)

        let userDetails = try await self._authHelper.reloadUser(self)
        let userType = self._config.authType == "idcs" ? "idcsuser" : "basic"
        let accessString = KeychainTokenStore.shared.read(.access) ?? ""
        let accessToken = try AuthTokenResult(token: accessString, userType, tokenKey: .access)
        self.refreshUser(user: userDetails, userRefreshToken: self.refreshToken ?? "", accessToken: accessToken, auth: self._auth)
    }
    
    /// Updates the user's password.
    /// - Parameter password: The new password to set.
    open func updatePassword(to password: String) async throws {
        let oldPassword = KeychainTokenStore.shared.read(.userPassword) ?? ""
        
        if oldPassword.isEmpty {
            self.logger.error("Couldn't find any saved password to perform the operation. Please sign-in and try again.")
            throw AuthErrorUtilities.internalError(message: "Couldn't find any saved password to perform the operation. Please sign-in and try again.")
        }
        
        if oldPassword == password {
            self.logger.error("New password can't be the same as the old one.")
            throw AuthErrorUtilities.weakPasswordError(message: "The new password can't be the same as the old password.")
        }
            
        try await _userHelper.updatePasswordHelper(self, oldPassword: oldPassword, newPassword: password)
    }
    
    /// Updates the user's password using a completion handler.
    /// - Parameters:
    ///   - oldPassword: The current password.
    ///   - newPassword: The new password.
    ///   - completion: Invoked with an error if the operation fails.
    @objc open func updatePassword(oldPassword: String, newPassword: String, completion: @escaping (Error?) -> Void) {
        if oldPassword == newPassword {
            self.logger.error("Couldn't find any saved password to perform the operation. Please sign-in and try again.")
            completion(AuthErrorUtilities.invalidEmailError(message: "The new password can't be the same as the old password."))
            return
        }

        Task {
            do {
                try await _userHelper.updatePasswordHelper(self, oldPassword: oldPassword, newPassword: newPassword)
                completion(nil)
            } catch let error as NSError {
                completion(error)
            } catch {
                completion(AuthErrorUtilities.internalError(message: "Couldn't update password."))
            }
        }
    }
    
    /// Applies profile updates described by the given profile object, then reloads the user.
    /// - Parameter newProfile: The profile updates to apply.
    func updateProfile(newProfile: UserProfile) async throws {
        try await self._userHelper.updateProfileHelper(self, newUserProfile: newProfile)
        try await self.reload()
    }
    
    /// Sends a verification email to the user's email address.
    open func sendEmailVerification() async throws {
        let email = KeychainTokenStore.shared.read(.userEmail) ?? ""
        
        if email.isEmpty {
            throw AuthErrorUtilities.nullUser()
        }
        
        let _ = try await self.getIDToken()
        try await self._userHelper.sendEmailVerificationHelper(self, withEmail: email, uid: self.uid)
    }
    
    /// Sends a verification email to the specified email address.
    /// - Parameters:
    ///   - withEmail: The target email address.
    ///   - completion: Invoked with an error if the operation fails.
    @objc open func sendEmailVerification(withEmail: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await self._userHelper.sendEmailVerificationHelper(self, withEmail: withEmail, uid: self.uid)
                completion(nil)
            } catch let error as NSError {
                self.logger.error("Couldn't send email verification.")
                completion(error)
            } catch {
                completion(AuthErrorUtilities.internalError(message: "Couldn't send email verification."))
            }
        }
    }

    /// Links the user with the given credential.
    /// - Parameter credential: The credential to link.
    /// - Returns: An authentication result containing the updated user.
    open func link(with credential: AuthCredential) async throws -> AuthDataResult {
        try await self._userHelper.linkWithCredential(self, credential: credential)
        
        // if it goes through, reload the user
        try await self.reload()
        
        // return the AuthDataResult object
        return AuthDataResult(user: self, credential: credential)
    }

    /// Links the user with the given credential.
    /// - Parameter credential: The credential to link.
    /// - Returns: An authentication result containing the updated user.
    open func link(with provider: AuthProvider) async throws -> AuthDataResult {
        try await self._userHelper.linkWithCredential(self, provider: provider)

        // if it goes through, reload the user
        try await self.reload()

        // return the AuthDataResult object
        return AuthDataResult(user: self, credential: nil)
    }

    /// Unlinks the specified provider from the user and updates the current user in the auth context.
    /// - Parameter provider: The provider identifier to unlink.
    /// - Returns: An authentication result containing the updated user.
    open func unlink(fromProvider provider: String) async throws -> AuthDataResult {
        let userDetails = try await self._authHelper.socialUnlinkHelper(provider: provider)
        guard let userInfo = userDetails.userInfo else {
            throw AuthErrorUtilities.internalError(message: "User info is required for unlink operation")
        }
        let newUser = FusabaseUser(user: userInfo, userRefreshToken: userDetails.refreshToken, accessToken: userDetails.accessToken, auth: self._auth)

        try await self._auth.updateCurrentUser(newUser)
        return AuthDataResult(user: newUser, credential: nil)
    }

    /// Unlinks the specified provider using a completion handler.
    /// - Parameters:
    ///   - provider: The provider identifier to unlink.
    ///   - completion: Invoked with the updated user or an error when the operation completes.
    open func unlink(fromProvider provider: String, completion: ((FusabaseUser?, Error?) -> Void)? = nil) {
        Task {
            do {
                let result = try await self.unlink(fromProvider: provider)
                completion?(result.user, nil)
            } catch let error as NSError {
                completion?(nil, error)
            } catch {
                completion?(nil, error)
            }
        }
    }
}
