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

import ObjectiveC
import AuthenticationServices
import Foundation
import FusabaseCore

/**
    Class that contains the ASWebAuthenticationService object that triggers a UI Window for the user to show their credentials.
    This class is internal and shouldn't be accesible to the user directly.
 */
@MainActor
@available(macOS 10.15, iOS 15.0, *)
class SocialLoginManager: NSObject {

    private var session: ASWebAuthenticationSession?
    
    /// Struct to return the token information
    /// Persist tokens to Keychain and expose them via computed properties.
    public struct AuthTokens {
        public var accessToken: String { KeychainTokenStore.shared.read(.access) ?? "" }
        public var refreshToken: String? { KeychainTokenStore.shared.read(.refresh) }
        public let rawCallbackURL: URL

        public init(accessToken: String, refreshToken: String?, rawCallbackURL: URL) {
            // Persist immediately; avoid retaining raw strings on the struct
            KeychainTokenStore.shared.write(accessToken, for: .access)
            if let rt = refreshToken, !rt.isEmpty {
                KeychainTokenStore.shared.write(rt, for: .refresh)
            }
            self.rawCallbackURL = rawCallbackURL
        }
    }

    /**
        Method that triggers social authentication through the given URL.
        ## This shouldn't be accessed directly, but through the Auth() class
        - Parameter callbackScheme: tells ORDS where to redirect the user after successful authentication
        - Parameter loginURL: URL object
        - Parameter presentationProvider:An interface the session uses to ask a delegate for a presentation context to show the web view.
     */
    static func login(
        callbackScheme: String,
        loginURL: URL,
        presentationProvider: ASWebAuthenticationPresentationContextProviding
    ) async throws -> AuthTokens {
        
        /// withCheckedThrowingContinuation allows this be handled in an async/await fashion
        return try await withCheckedThrowingContinuation { continuation in
            let manager = SocialLoginManager()

            
            // we initialize the authentication web session
            let session = ASWebAuthenticationSession(
                url: loginURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in

                // in case we find an error, we return it through the continuation
                if let error = error {
                    AuthLogger.info("crashed after session. throwing error before parse.")
                    continuation.resume(throwing: error)
                    return
                }

                // we check if can obtain the json data from the callbackurl
                guard
                    let callbackURL = callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let respItem = components.queryItems?.first(where: { $0.name == "resp" })?.value,
                    let decodedString = respItem.removingPercentEncoding,
                    let jsonData = decodedString.data(using: .utf8)
                else {
                    continuation.resume(throwing: NSError(
                        domain: "sociallogin",
                        code: 99,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL or missing token data"]
                    ))
                    return
                }
                
                AuthLogger.info("json data object found: \(jsonData)")

                do {
                    if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let accessToken = json["access_token"] as? String,
                       let refreshToken = json["refresh_token"] as? String {
                        
                        let tokens = AuthTokens(
                            accessToken: accessToken,
                            refreshToken: refreshToken,
                            rawCallbackURL: callbackURL
                        )

                        continuation.resume(returning: tokens)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "sociallogin",
                            code: 100,
                            userInfo: [NSLocalizedDescriptionKey: "Malformed JSON structure"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = true

            manager.session = session
            session.start()
        }
    }
    
    /**
        Method that triggers social authentication through the given URL and returns an AuthCredential based on the given provider.
        ## This shouldn't be accessed directly, but through the Auth() class
        - Parameter callbackScheme: tells ORDS where to redirect the user after successful authentication
        - Parameter loginURL: URL object
        - Parameter presentationProvider:An interface the session uses to ask a delegate for a presentation context to show the web view.
        - Returns : String containing the code from the login operation
     */
    static func loginWithIDP(
        callbackScheme: String,
        loginURL: URL,
        presentationProvider: ASWebAuthenticationPresentationContextProviding
    ) async throws -> String {
        /// withCheckedThrowingContinuation allows this be handled in an async/await fashion
        return try await withCheckedThrowingContinuation { continuation in
            let manager = SocialLoginManager()

            let session = ASWebAuthenticationSession(
                url: loginURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                

                // If there's an error generating the web view with the given browser, return the error
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                // We separate the components from the returned callbackURL
                guard
                    let callbackURL = callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let queryItems = components.queryItems,
                    let respValue = queryItems.first(where: {$0.name == "resp"})?.value
                else {
                    continuation.resume(throwing: NSError(
                        domain: "sociallogin",
                        code: 99,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL or missing token data"]
                    ))
                    return
                }
                
                // From the parsed callback url we obtain the code 
                let pairs = respValue.components(separatedBy: "&")
                for pair in pairs {
                    let keyValue = pair.components(separatedBy: "=")
                    if keyValue.count == 2, keyValue[0] == "code" {
                        continuation.resume(returning: keyValue[1])
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "sociallogin",
                            code: 99,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL or missing token data"]
                        ))
                        return
                    }
                }
            }

            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = true

            manager.session = session
            session.start()
        }
    }
    
    // MARK: - These implementations implement the presentation context automatically. Only IF the device supports it.
    #if canImport(UIKit)
    /**
        Method that triggers social authentication through the given URL.
        ## This shouldn't be accessed directly, but through the Auth() class
        - Parameter callbackScheme: tells ORDS where to redirect the user after successful authentication
        - Parameter loginURL: URL object
     */
    @MainActor
    static func login(
        callbackScheme: String,
        loginURL: URL
    ) async throws -> AuthTokens {
        
        /// withCheckedThrowingContinuation allows this be handled in an async/await fashion
        return try await withCheckedThrowingContinuation { continuation in
            let manager = SocialLoginManager()

            
            // we initialize the authentication web session
            let session = ASWebAuthenticationSession(
                url: loginURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in

                // in case we find an error, we return it through the continuation
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                // we check if can obtain the json data from the callbackurl
                guard
                    let callbackURL = callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let respItem = components.queryItems?.first(where: { $0.name == "resp" })?.value,
                    let decodedString = respItem.removingPercentEncoding,
                    let jsonData = decodedString.data(using: .utf8)
                else {
                    continuation.resume(throwing: NSError(
                        domain: "sociallogin",
                        code: 99,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL or missing token data"]
                    ))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let accessToken = json["access_token"] as? String,
                       let refreshToken = json["refresh_token"] as? String {
                        
                        let tokens = AuthTokens(
                            accessToken: accessToken,
                            refreshToken: refreshToken,
                            rawCallbackURL: callbackURL
                        )

                        continuation.resume(returning: tokens)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "sociallogin",
                            code: 100,
                            userInfo: [NSLocalizedDescriptionKey: "Malformed JSON structure"]
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            session.presentationContextProvider = DefaultWebAuthProvider.shared
            session.prefersEphemeralWebBrowserSession = true

            manager.session = session
            session.start()
        }
    }
    
    /**
        Method that triggers social authentication through the given URL and returns an AuthCredential based on the given provider.
        ## This shouldn't be accessed directly, but through the Auth() class
        - Parameter callbackScheme: tells ORDS where to redirect the user after successful authentication
        - Parameter loginURL: URL object
        - Returns : String containing the code from the login operation
     */
    static func loginWithIDP(
        callbackScheme: String,
        loginURL: URL
    ) async throws -> String {
        /// withCheckedThrowingContinuation allows this be handled in an async/await fashion
        return try await withCheckedThrowingContinuation { continuation in
            let manager = SocialLoginManager()

            let session = ASWebAuthenticationSession(
                url: loginURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                

                // If there's an error generating the web view with the given browser, return the error
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                AuthLogger.debug("Starting social login flow for URL: \(loginURL.absoluteString)")

                // We separate the components from the returned callbackURL
                guard
                    let callbackURL = callbackURL,
                    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                    let queryItems = components.queryItems,
                    let respValue = queryItems.first(where: {$0.name == "resp"})?.value
                else {
                    continuation.resume(throwing: NSError(
                        domain: "AuthDomain",
                        code: 99,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL or missing token data"]
                    ))
                    return
                }
                
                // From the parsed callback url we obtain the code
                let pairs = respValue.components(separatedBy: "&")
                for pair in pairs {
                    let keyValue = pair.components(separatedBy: "=")
                    if keyValue.count == 2, keyValue[0] == "code" {
                        continuation.resume(returning: keyValue[1])
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "sociallogin",
                            code: 99,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL or missing token data"]
                        ))
                        return
                    }
                }
            }

            session.presentationContextProvider = DefaultWebAuthProvider.shared
            session.prefersEphemeralWebBrowserSession = true

            manager.session = session
            session.start()
        }
    }
    
    #endif
}
