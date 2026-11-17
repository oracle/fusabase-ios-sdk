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
import AuthenticationServices

/**
 The main class for managing authentication in Oracle FUSABASE applications.
 
 Access all authentication methods through this class. User-related methods are available via the `currentUser` property.
 
 This class follows the singleton pattern. Access the shared instance using `auth()`.
 
 To associate with a specific app, use `auth(app: FusabaseApp)`.
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
open class FusabaseAuth: NSObject {

    /// The associated FusabaseApp instance.
    public var app: FusabaseApp 
    
    /// The currently signed-in user, or nil if no user is signed in.
    public var currentUser: FusabaseUser?
    
    // internal variables
    /// The shared singleton instance of FusabaseAuth.
    private static var sharedAuthInstance: FusabaseAuth? // singleton pattern
    /// The configuration options for the auth instance. // TODO: this shouldn't be public. provide access methods to change the options
    var _config: FusabaseOptions
    /// The helper protocol for authentication operations.
    var _authHelper: AuthHelperProtocol
    /// The helper protocol for user operations (optional).
    var _userHelper: UserHelperProtocol?
    /// Dictionary of registered auth state change listeners.
    private var listeners: [AuthStateDidChangeListenerHandle: (FusabaseAuth?, FusabaseUser?) -> Void] = [:]
    /// Dictionary of registered ID token change listeners.
    private var idTokenListeners: [IDTokenDidChangeListenerHandle: (FusabaseAuth, FusabaseUser?) -> Void] = [:]
    /// Counter for generating unique listener IDs.
    private var listenerIDCounter = 0
    /// Counter for generating unique ID token listener IDs.
    private var idTokenListenerIDCounter = 0
    /// The current user credential (internal).
    private var _userCredential: UserCredential?
    
    /// Provides read-only access to the configuration options.
    var config: FusabaseOptions? {
        get {
            return _config
        }
        
    }

    /// Private initializer that sets up the auth instance with the given app.
    private init(app: FusabaseApp) {
        
        self.app = app
        self.currentUser = nil
        self._config = app.options
        
        if _config.authType == "idcs" {
            self._authHelper = IDCSAuthHelper(_config: app.options)
        }
        else {
            self._authHelper = OnPremAuthHelper(config: app.options)
        }
        
        // initializer for NSObject super class
        super.init()
        
        // running task to asynchrounsly perform initial sign-in
        // warning: finishing initialization doesn't mean that the initial sign-in will be over
        Task {
            do {
                try await self._performInitialSignIn(config: app.options)
            } catch {
                AuthLogger.info("Didn't find any local user. Please sign-in.")
            }
        }
        
    }
    
    /// Returns the shared singleton instance of FusabaseAuth.
    ///
    /// This method follows the singleton pattern and returns the shared instance of FusabaseAuth.
    /// If no shared instance exists, it creates one using the default FusabaseApp instance.
    ///
    /// - Returns: The shared FusabaseAuth instance.
    open class func auth() -> FusabaseAuth {
        if sharedAuthInstance == nil {
            sharedAuthInstance = FusabaseAuth(app: FusabaseApp.app()!)
        }
        return sharedAuthInstance!
    }
    
    /// Returns an instance of FusabaseAuth associated with the given app, replacing the shared instance.
    ///
    /// This method creates a new FusabaseAuth instance with the specified FusabaseApp and sets it as the shared singleton instance.
    /// Any previous shared instance is replaced.
    ///
    /// - Parameter app: The FusabaseApp instance to associate with the auth instance.
    /// - Returns: The newly created FusabaseAuth instance, now set as the shared instance.
    open class func auth(app: FusabaseApp) -> FusabaseAuth {
        FusabaseAuth.sharedAuthInstance = FusabaseAuth(app: app)
        return FusabaseAuth.sharedAuthInstance!
    }
    
    // MARK: - Logging
    
    
    /// Internal method to create credentials and update the user.
    ///
    /// - Parameters:
    ///   - userData: Optional complete user details.
    ///   - completeUser: Optional complete user object.
    ///   - provider: The authentication provider (default is EmailAuthProvider).
    /// - Returns: The user credential.
    /// - Throws: An error if credentials cannot be created.
    private func _createCredentials(userData: AuthUserCompleteDetails? = nil, completeUser: FusabaseUser? = nil, provider: AuthProvider = EmailAuthProvider()) async throws -> UserCredential {
        // if userData and completeUser are empty, throw an error
        if userData == nil && completeUser == nil {
            throw AuthErrorUtilities.internalError(message: "Couldn't create the credentials for the given user.")
        }

        let user: FusabaseUser

        if userData != nil {
            // For linking flows, userInfo may be nil - use existing currentUser
            if let userInfo = userData!.userInfo {
                user = FusabaseUser(user: userInfo, userRefreshToken: userData!.refreshToken, accessToken: userData!.accessToken, auth: self)
            } else {
                guard let currentUser = completeUser ?? self.currentUser else {
                    throw AuthErrorUtilities.internalError(message: "User info is required for social sign-in.")
                }
                // Linking returns a provider credential without replacing the current session.
                user = currentUser
            }
        } else {
            user = completeUser!
        }

        // Authentication helpers have already validated and accepted the token pair.
        // Publishing this result must not start another asynchronous refresh.
        let accessToken = KeychainTokenStore.shared.read(.access) ?? ""
        try self._updateCurrentUserInternally(user: user, accessToken: accessToken)

        // we return the credential based on the given provider
        var credential: AuthCredential

        if provider.providerID == "google" {
            credential = GoogleAuthCredential(withIDToken: accessToken, accessToken: accessToken)
        } else if provider.providerID == "facebook" {
            credential = FacebookAuthCredential(withAccessToken: accessToken)
        } else if provider.providerID == "github" {
            credential = GithubAuthCredential(withToken: accessToken)
        } else {
            credential = AuthCredential(provider: provider.providerID)
        }

        let userCred = UserCredential(user: user, credential: credential)

        self._userCredential = userCred
        return userCred
    }

    internal func _createCredentialsFromRedirectResult(_ details: AuthUserCompleteDetails,
                                                       provider: AuthProvider) async throws -> UserCredential {
        if self._config.authType == "idcs", !(provider is IDCSAuthProvider) {
            throw AuthErrorUtilities.operationNotAllowed(message: "IDCS auth type supports only IDCSAuthProvider.")
        }

        return try await self._createCredentials(userData: details, provider: provider)
    }
    
    /// Internal method that updates the currentUser variable inside of Auth and saves it into the device.
    ///
    /// - Parameters:
    ///   - user: User object containing the new user.
    ///   - accessToken: String containing the access token to be saved.
    /// - Throws: Error if the update fails.
    private func _updateCurrentUserInternally(user: FusabaseUser, accessToken: String) throws {

        // temporary solution for email
        KeychainTokenStore.shared.write(user.email, for: .userEmail)

        // We save the current user's tokens into the device if the idp_type is local
        // If there's already existing data, it will be overwritten
        KeychainTokenStore.shared.write(user.refreshToken, for: .refresh)
        KeychainTokenStore.shared.write(accessToken, for: .access)

        self.currentUser = user
        // We notify listeners
        notifyListeners(auth: self, user: self.currentUser)
        // We notify ID token listeners
        notifyIDTokenListeners(auth: self, user: self.currentUser)

        AuthLogger.info("Successfully updated current user and saved tokens to the device.")

    }
    
    /// Internal method to perform an initial sign-in if we find valid tokens.
    ///
    /// - Parameter config: The configuration options.
    /// - Throws: Error if sign-in fails.
    ///
    /// todo: might remove throws from here and just return empty if there's no AuthTokenResult possible
    private func _performInitialSignIn(config: FusabaseOptions) async throws {

        var accessToken: AuthTokenResult
        var stringAccessToken: String
        var refreshToken: String
        
        let userType = config.authType == "idcs" ? "idcsuser" : "basic"
        
        // we try to to retrieve data
        do {
            stringAccessToken = KeychainTokenStore.shared.read(.access) ?? ""
            refreshToken = KeychainTokenStore.shared.read(.refresh) ?? ""
            
            if stringAccessToken.isEmpty || refreshToken.isEmpty {
                AuthLogger.warning("No saved tokens in the device. Try signing in again.")
                throw AuthErrorUtilities.invalidCredential(message: "No saved tokens in the device.")
            }
            
            accessToken = try AuthTokenResult(token: stringAccessToken, userType, tokenKey: .access)
        } catch {
            return
        }
        
        AuthLogger.info("Found user credentials saved in the device. Will attempt to sign in automatically...")
        
        // if we find both, we create the user helper
        if config.authType == "idcs" {
            self._userHelper = IDCSUserHelper(config, _accessToken: accessToken)
        } else {
            self._userHelper = OnPremUserHelper(config: config, accessToken: accessToken)
        }
        

        if !accessToken._validateAccessToken() {
            // if the access token is invalid, attempt to refresh
            // IDCS: use IDCS refresh token and exchange for FUSABASE access
            // On-Prem: use local refresh token directly
            do {
                if config.authType == "idcs" {
                    guard let idcsUserHelper = self._userHelper as? IDCSUserHelper else {
                        throw AuthErrorUtilities.internalError(message: "IDCS refresh helper not available")
                    }
                    let tokenResp = try await idcsUserHelper.refreshAccessToken(refreshToken: refreshToken)
                    accessToken = try AuthTokenResult(token: tokenResp.access_token, userType, tokenKey: .access)
                    if let newRefresh = tokenResp.refresh_token, !newRefresh.isEmpty {
                        refreshToken = newRefresh
                    }
                    KeychainTokenStore.shared.write(tokenResp.access_token, for: .access)
                    if let newRefresh = tokenResp.refresh_token, !newRefresh.isEmpty {
                        KeychainTokenStore.shared.write(newRefresh, for: .refresh)
                    }
                } else {
                    // On-Prem refresh using local refresh token
                    let tokenResp = try await self._userHelper!.refreshAccessToken(refreshToken: refreshToken)
                    accessToken = try AuthTokenResult(token: tokenResp.access_token, userType, tokenKey: .access)
                    if let newRefresh = tokenResp.refresh_token, !newRefresh.isEmpty {
                        refreshToken = newRefresh
                    }
                    KeychainTokenStore.shared.write(tokenResp.access_token, for: .access)
                    if let newRefresh = tokenResp.refresh_token, !newRefresh.isEmpty {
                        KeychainTokenStore.shared.write(newRefresh, for: .refresh)
                    }
                }
            } catch {
                // we sign-out remove previous credentials
                KeychainTokenStore.shared.delete(.access)
                KeychainTokenStore.shared.delete(.refresh)
                KeychainTokenStore.shared.delete(.userEmail)
                self.currentUser = nil
                return
            }
        }

        let userDetails: AuthUserInterface
        
        // we obtain the user details
        if config.authType == "idcs" {
            userDetails = try await self._authHelper._getUserDetailsIDCS(accessToken: accessToken)
        }
        
        else {
            userDetails = try self._authHelper._getUserDetails(accessToken: accessToken.token)
        }
        
        let newUser = FusabaseUser(user: userDetails, userRefreshToken: refreshToken, accessToken: accessToken, auth: self)
        AuthLogger.info("Successfully retrieved user from the device.")
        
        let _ = try await self._createCredentials(completeUser: newUser)
    }
    
    /// Adds a listener for authentication state changes.
    ///
    /// - Parameter callback: The callback to be called when the state changes.
    /// - Returns: A handle to remove the listener.
    ///
    /// Not compatible with Obj-C.
    open func addStateDidChangeListener(callback: @escaping (FusabaseAuth?, FusabaseUser?) -> Void) -> AuthStateDidChangeListenerHandle {
        listenerIDCounter += 1
        let handle = AuthStateDidChangeListenerHandle(id: listenerIDCounter)
        
        listeners[handle] = callback
        
        return handle
    }
    
    /// Removes a listener for authentication state changes.
    ///
    /// - Parameter handle: The handle of the listener to remove.
    open func removeStateDidChangeListener(_ handle: AuthStateDidChangeListenerHandle) {
        listeners.removeValue(forKey: handle)
    }
    
    /// Notifies all listeners of changes in auth or user.
    ///
    /// - Parameters:
    ///   - auth: The auth instance.
    ///   - user: The current user.
    func notifyListeners(auth: FusabaseAuth, user: FusabaseUser?) {
        for listener in listeners.values {
            listener(auth, user)
        }
    }

    /// Registers a block as an "ID token did change" listener.
    ///
    /// To be invoked when:
    ///
    ///     The block is registered as a listener,
    ///     A user with a different UID from the current user has signed in, or
    ///     The ID token of the current user has been refreshed, or
    ///     The current user has signed out.
    ///
    /// The block is invoked immediately after adding it according to its standard invocation semantics, asynchronously on the main thread.
    ///
    /// - Parameter listener: The block to be invoked. The block is always invoked asynchronously on the main thread, even for its initial invocation after having been added as a listener.
    /// - Returns: A handle useful for manually unregistering the block as a listener.
    @objc
    open func addIDTokenDidChangeListener(_ listener: @escaping (FusabaseAuth, FusabaseUser?) -> Void) -> NSObjectProtocol {
        idTokenListenerIDCounter += 1
        let handle = IDTokenDidChangeListenerHandle(id: idTokenListenerIDCounter)

        idTokenListeners[handle] = listener

        // Invoke the listener immediately after adding it
        DispatchQueue.main.async {
            listener(self, self.currentUser)
        }

        return handle as NSObjectProtocol
    }

    /// Unregisters a block as an "ID token did change" listener.
    ///
    /// - Parameter listenerHandle: The handle for the listener.
    @objc
    open func removeIDTokenDidChangeListener(_ listenerHandle: NSObjectProtocol) {
        if let handle = listenerHandle as? IDTokenDidChangeListenerHandle {
            idTokenListeners.removeValue(forKey: handle)
        }
    }

    /// Notifies all ID token listeners of changes.
    ///
    /// - Parameters:
    ///   - auth: The auth instance.
    ///   - user: The current user.
    func notifyIDTokenListeners(auth: FusabaseAuth, user: FusabaseUser?) {
        for listener in idTokenListeners.values {
            DispatchQueue.main.async {
                listener(auth, user)
            }
        }
    }
    
    /// Updates the current user in Auth.
    ///
    /// - Parameter user: The new user.
    /// - Throws: Error if update fails.
    open func updateCurrentUser(_ user: FusabaseUser) async throws {
        try self._updateCurrentUserInternally(user: user, accessToken: try await user.getIDToken(forcingRefresh: true))
    }
    
    /// Signs out the current user from ORDS.
    ///
    /// - Throws: Error if sign out fails.
    open func signOut() async throws {
        try await signOutInternal()
    }

    private func signOutInternal() async throws {
        // Notify listeners and end the local session even when remote logout fails.
        // The remote error still propagates to the caller after cleanup.
        defer { clearLocalAuthState() }

        let refreshToken = KeychainTokenStore.shared.read(.refresh) ?? ""
        guard currentUser != nil else { return }
        try await _authHelper.performSignOut(refreshToken: refreshToken)
        AuthLogger.info("Logged user out of the application.")
    }

    private func clearLocalAuthState() {
        KeychainTokenStore.shared.delete(.access)
        KeychainTokenStore.shared.delete(.refresh)
        KeychainTokenStore.shared.delete(.userEmail)
        KeychainTokenStore.shared.delete(.userPassword)
        currentUser = nil
        notifyListeners(auth: self, user: nil)
        notifyIDTokenListeners(auth: self, user: nil)
    }

    /// Signs out a user from ORDS with a completion handler.
    ///
    /// - Parameter completion: Completion handler for Obj-C compatibility.
    @objc open func signOut(completion: @escaping (Error?) -> Void) {

        // we check if we do have a user signed in
        if currentUser == nil {
            completion(AuthErrorUtilities.invalidCredential(message: "No user signed in to perform sign out operation."))
            return
        }

        Task {
            do {
                try await self.signOutInternal()
                completion(nil)
            } catch let error as NSError {
                AuthLogger.error("Couldn't sign out user: \(error)")
                completion(error)
            } catch {
                completion(AuthErrorUtilities.invalidCredential(message: "Couldn't sign out."))
            }
        }
    }
    
    
    /// Signs in a user with an email and password.
    ///
    /// - Parameters:
    ///   - email: The user's email.
    ///   - password: The user's password.
    /// - Returns: AuthDataResult containing the signed-in user information.
    /// - Throws: Error if sign-in fails.
    open func signIn(withEmail email: String, password: String) async throws -> AuthDataResult {
        if email.isEmpty || password.isEmpty {
            throw AuthErrorUtilities.invalidEmailError(message: "Provide both email and password for sign-in.")
        }

        let userDetails = try await self._authHelper.authenticateAndGetDetails(email: email, password: password)
        let userCredential = try await self._createCredentials(userData: userDetails)

        // if both operations are successfull, we remember the password
        KeychainTokenStore.shared.write(password, for: .userPassword)
        return AuthDataResult(user: self.currentUser!, credential: userCredential.credential)
    }
    
    /// Signs in a user with an email and password, with completion handler.
    ///
    /// - Parameters:
    ///   - withEmail: The user's email.
    ///   - password: The user's password.
    ///   - completion: Completion handler with result or error.
    open func signIn(withEmail: String, password: String, completion: @escaping (AuthDataResult?, Error?) -> Void) {
        Task{
            do {
                let authDataResult = try await signIn(withEmail: withEmail, password: password)
                completion(authDataResult, nil)
            } catch let error as NSError {
                completion(nil, error)
            } catch {
                completion(nil, error)
            }
        }
        
    }
    
    /// Signs in a user with the given credential.
    ///
    /// - Parameter credential: The AuthCredential for sign-in.
    /// - Returns: AuthDataResult containing the signed-in user information.
    /// - Throws: Error if sign-in fails.
    open func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
        // we first make the needed user details for our internal User object
        let userDetails = try await self._authHelper.signInWithCredential(with: credential)

        let userCredential = try await self._createCredentials(userData: userDetails)

        // if we're not saving the password, updatePassword won't work !!!
        // PersistenceUtils.saveItem(password, forKey: "USER_PASSWORD")

        return AuthDataResult(user: self.currentUser!, credential: userCredential.credential)
    }
    
    /// Creates a new user in the backend and signs them in.
    ///
    /// - Parameters:
    ///   - email: The email for the new user.
    ///   - password: The password for the new user.
    /// - Returns: AuthDataResult for the new user.
    /// - Throws: Error if creation or sign-in fails.
    open func createUser(withEmail email: String, password: String) async throws -> AuthDataResult {
        if let userDetails = try await self._authHelper.createUserWithEmailAndPassword(email: email, password: password) {
            AuthLogger.info("created and authenticated user!")
            let userCredential = try await self._createCredentials(userData: userDetails)
            AuthLogger.info("created credentials !!!")

            // if both operations are successfull, we remember the password
            KeychainTokenStore.shared.write(password, for: .userPassword)

            return AuthDataResult(user: self.currentUser!, credential: userCredential.credential, isNewUser: true)
        } else {
            let userDetails = try await self._authHelper.authenticateAndGetDetails(email: email, password: password)
            AuthLogger.info("created and authenticated user!")
            let userCredential = try await self._createCredentials(userData: userDetails)
            AuthLogger.info("created credentials !!!")

            // if both operations are successfull, we remember the password
            KeychainTokenStore.shared.write(password, for: .userPassword)

            return AuthDataResult(user: self.currentUser!, credential: userCredential.credential, isNewUser: true)
        }
    }

    /// Creates a new user in the backend with completion handler.
    ///
    /// - Parameters:
    ///   - withEmail: The email for the new user.
    ///   - password: The password for the new user.
    ///   - completion: Completion handler with result or error.
    @objc open func createUser(withEmail: String, password: String, completion: @escaping (AuthDataResult?, Error?) -> Void) {
        Task {
            do {
                let res = try await createUser(withEmail: withEmail, password: password)
                completion(res, nil)
                
            } catch let error as NSError {
                completion(nil, error)
            } catch {
                completion(nil, error)
            }
        }
    }
    
    /// Sends a password reset email.
    ///
    /// - Throws: Error if sending fails.
    open func sendPasswordReset() async throws {
        let email = KeychainTokenStore.shared.read(.userEmail) ?? ""

        if email.isEmpty {
            throw AuthErrorUtilities.invalidCredential(message: "Couldn't find any saved email to perform the operation. Please sign-in and try again.")
        }

        try await self._authHelper.sendPasswordResetHelper(withEmail: email)
    }
    
    /// Sends a password reset email with completion handler.
    ///
    /// - Parameters:
    ///   - withEmail: The user's email.
    ///   - completion: Completion handler with error if any.
    @objc open func sendPasswordReset(withEmail: String, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await self._authHelper.sendPasswordResetHelper(withEmail: withEmail)
                completion(nil)
            } catch let error as NSError {
                completion(error)
            } catch {
                completion(AuthErrorUtilities.internalError(message: "Couldn't send password reset email."))
            }
        }
    }
    
    /// Verifies a password reset using a code.
    ///
    /// - Parameter code: The verification code received by email.
    /// - Returns: A JSON dictionary with the verification result.
    /// - Throws: Errors bubbled from the underlying helper.
    open func verifyPasswordReset(_ code: String) async throws -> [String: Any] {
        try await self._authHelper.verifyPasswordResetCodeHelper(code: code)
    }
    
    /// Confirms a password reset using a code.
    ///
    /// - Parameters:
    ///   - code: The verification code received by email.
    ///   - newPassword: The new password to set.
    /// - Returns: A JSON dictionary with the confirmation result.
    /// - Throws: Errors bubbled from the underlying helper.
    open func confirmPasswordReset(withCode code : String, newPassword: String) async throws -> [String: Any] {
        try await self._authHelper.confirmPasswordResetHelper(code: code, newPassword: newPassword)
    }

    /// Signs in with the given credential for linking to the current user.
    ///
    /// - Parameter credential: The AuthCredential for linking.
    /// - Returns: AuthDataResult containing the linked user information.
    /// - Throws: Error if linking fails.
    func signInWithCredentialLinking(credential: AuthCredential) async throws -> AuthDataResult {
        let userDetails = try await self._authHelper.signInWithCredentialLinking(credential: credential, link: true)
        let userCredential = try await self._createCredentials(userData: userDetails)

        return AuthDataResult(user: self.currentUser!, credential: userCredential.credential)
    }

    /// Signs in using the provided auth provider instance.
    ///
    /// - Parameter provider: An instance of an auth provider used to initiate the sign-in flow.
    /// - Returns: The AuthDataResult after the successful sign-in.
    /// - Throws: Error if the sign-in fails.
    @available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
    @discardableResult
    open func signIn(with provider: FederatedAuthProvider) async throws -> AuthDataResult {
        let credential = try await provider.credential()
        return AuthDataResult(user: self.currentUser!, credential: credential)
    }

}
