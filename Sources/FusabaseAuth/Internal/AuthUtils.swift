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
import CryptoKit
import FusabaseCore

enum DecodeErrors: Error {
    case badToken
    case other
}

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
class AuthUtils {

    static let fusabaseLogger = FusabaseLogger(category: "AuthUtils")
    private static let sensitiveHeaderKeys: Set<String> = ["authorization", "cookie", "set-cookie"]
    private static let sensitiveBodyKeys: Set<String> = [
        "password", "token", "access_token", "refresh_token", "id_token", "id_token_hint", "authtoken", "clientsecret", "code_verifier"
    ]
    private static let redactedValue = "<redacted>"
    private static let maxLoggedBodyLength = 256

    static func redactHeaders(_ headers: [String: String]) -> [String: String] {
        var redacted: [String: String] = [:]
        for (key, value) in headers {
            if sensitiveHeaderKeys.contains(key.lowercased()) {
                redacted[key] = redactedValue
            } else {
                redacted[key] = value
            }
        }
        return redacted
    }

    static func redactBodyPreview(_ bodyData: Data?) -> String? {
        guard let bodyData, let bodyString = String(data: bodyData, encoding: .utf8), !bodyString.isEmpty else {
            return nil
        }

        // JSON body redaction
        if let object = try? JSONSerialization.jsonObject(with: bodyData),
           var dict = object as? [String: Any] {
            redactSensitiveKeys(in: &dict)
            if let redactedData = try? JSONSerialization.data(withJSONObject: dict, options: []),
               let redactedString = String(data: redactedData, encoding: .utf8) {
                return truncateForLogging(redactedString)
            }
        }

        // Form-urlencoded body redaction
        if bodyString.contains("=") {
            let items = bodyString.split(separator: "&").map { pair -> String in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let keyPart = parts.first else { return String(pair) }
                let key = String(keyPart)
                if sensitiveBodyKeys.contains(key.lowercased()) {
                    return "\(key)=\(redactedValue)"
                }
                return String(pair)
            }
            return truncateForLogging(items.joined(separator: "&"))
        }

        return "<body omitted>"
    }

    private static func redactSensitiveKeys(in dict: inout [String: Any]) {
        for (key, value) in dict {
            if sensitiveBodyKeys.contains(key.lowercased()) {
                dict[key] = redactedValue
            } else if var nested = value as? [String: Any] {
                redactSensitiveKeys(in: &nested)
                dict[key] = nested
            } else if var array = value as? [[String: Any]] {
                for idx in array.indices {
                    redactSensitiveKeys(in: &array[idx])
                }
                dict[key] = array
            }
        }
    }

    private static func truncateForLogging(_ value: String) -> String {
        if value.count <= maxLoggedBodyLength { return value }
        return String(value.prefix(maxLoggedBodyLength)) + "...<truncated>"
    }
    
    /**
        Method to replicate Javascript's btoa() method and return a encoded string in bas64 using utf-8
        - Parameter string:String
        - Returns: Encoded string
     */
    static func btoa(_ string: String) -> String? {
        let data = string.data(using: .utf8)
        return data?.base64EncodedString()
    }
    
    /**
        Method that decodes a base64 string
     */
    static func base64Decode(_ base64: String) -> Data? {
        let base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
        guard let decoded = Data(base64Encoded: padded) else {
            Self.fusabaseLogger.error("Couldn't decode base64 string")
            return nil
        }
        return decoded
    }
    
    /**
        Method that decodes a jwt token into an AuthUserAPI object
     */
    static func decode(jwtToken jwt: String, _ authType: String? = "basic") throws -> AuthUserFromJWT {

        func decodeJWTPart(_ value: String) throws -> AuthUserFromJWT {
            guard let bodyData = base64Decode(value) else {
                throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
            }
            
            // if the authentication type is basic, we simply decode it with AuthUserAPI
            if authType == "basic" {
                do {
                    let newPayload = try JSONDecoder().decode(AuthUserFromJWT.self, from: bodyData)
                    return newPayload
                } catch {
                    throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
                }
            }
            
            // if it's a bearer token, we unpack it with this items
            else if authType == "idcsbtoken" {
                do {
                    guard let jsonObject = try? JSONSerialization.jsonObject(with: bodyData, options: []) else {
                        throw AuthErrorUtilities.internalError(message: "Couldn't serialize JSON object from server.")
                    }
                    
                    if let jsonDict = jsonObject as? [String: Any] {
                        let newUser = AuthUserFromJWT(user_displayname: "-", user_id: "-", iss: jsonDict["iss"] as! String, idp_name: "-", creation_time: "-", sub: jsonDict["sub"] as! String, iat: jsonDict["iat"] as! Double, idp_type: "-", aud: "-", email_verified: "-", scope: jsonDict["scope"] as! String, exp: jsonDict["exp"] as! Double)
                        return newUser
                    }
                    
                    
                } catch {
                    throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
                }
            }
            
            // if it's an idcs user token, we unpack it with this
            else if authType == "idcsuser" {
                do {
                    guard let jsonObject = try? JSONSerialization.jsonObject(with: bodyData, options: []) else {
                        throw AuthErrorUtilities.internalError(message: "Couldn't serialize JSON object from server.")
                    }
                    
                    if let jsonDict = jsonObject as? [String: Any] {
                        // this access token could be either from the locally saved user or the recently authenticated
                        // in the first case, email_verified will be a boolean
                        // and in the latter it will be either 1 or 0 as Int.
                        // it needs to be saved as a string "1" or "0" for User to properly read it
                        
                        let emailVerified: String
                        
                        if let emailVerifiedAsBool = jsonDict["email_verified"] as? Bool {
                            emailVerified = emailVerifiedAsBool ? "1" : "0"
                        } else if let emailVerifiedAsInt = jsonDict["email_verified"] as? Int {
                            emailVerified = emailVerifiedAsInt == 1 ? "1" : "0"
                        } else {
                            emailVerified = "0"
                        }
                        
                        guard let displayName = jsonDict["user_displayname"] as? String,
                              let userId = jsonDict["user_id"] as? String,
                              let issuer = jsonDict["iss"] as? String,
                              let provider = jsonDict["idp_name"] as? String,
                              let subject = jsonDict["sub"] as? String,
                              let issuedAt = jsonDict["iat"] as? Double,
                              let idpType = jsonDict["idp_type"] as? String,
                              let expiresAt = jsonDict["exp"] as? Double else {
                            throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
                        }
                        let newUser = AuthUserFromJWT(user_displayname: displayName, user_id: userId, iss: issuer, idp_name: provider, creation_time: "-", sub: subject, iat: issuedAt, idp_type: idpType, aud: "-", email_verified: emailVerified, scope: "-", exp: expiresAt)
                        return newUser
                    }
                    
                } catch {
                    
                    throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
                }
            }
            
            // if unknown, return nil
            throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
            
            
        }
        let segments = jwt.components(separatedBy: ".")
        guard segments.count == 3 else {
            throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
        }
        return try decodeJWTPart(segments[1])
    }
    
    /**
        Method that decodes a jwt token into a dictionary without a given format
        Important: This should only be used when the format of the returned dictionary is known as it will be force unwrapped
     */
    static func decodeOnly(jwtToken jwt: String) throws -> [String: Any] {

        func decodeJWTPart(_ value: String) throws -> [String: Any] {
            guard let bodyData = base64Decode(value) else {
                throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
            }
            
           if let jsonDictionary = try JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any] {
                return jsonDictionary
            } else {
                throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
            }
            
        }
        
        let segments = jwt.components(separatedBy: ".")
        guard segments.count == 3 else {
            throw AuthErrorUtilities.malformedJWT(message: "Couldn't decode JWT token received from backend.")
        }
        return try decodeJWTPart(segments[1])
    }
    
    /**
        Internal method that parses a response where the content is in HTML. It will try to abtract the code + reason by id = "reason"
        - Parameter html: data
        - Returns : String containing the reason and HTTP status code: "{HTTP Status}: Message"
     */
    static func extractErrorMessage(from html: String, tag: String) -> String? {
        let id = "reason"
        
        let pattern = "<\(tag)[^>]*id\\s*=\\s*[\"']\(id)[\"'][^>]*>([\\s\\S]*?)</\(tag)>"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            
            if let match = regex.firstMatch(in: html, options: [], range: nsRange),
               let range = Range(match.range(at: 1), in: html) {
                return html[range]
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) // Clean inner HTML
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            
        }
        
        return nil
    }
    
    /**
        Check the http response and return an error with the given body if needed
        - Parameter response.statusCode: Int
        - Parameter data: Data
        - Parameter method: String
     */
    static func checkResponse(response: HTTPURLResponse, data: Data?, method: String? = nil) throws {
        
        if (200...299).contains(response.statusCode) {
            return
        }
        else if (400...402).contains(response.statusCode) {
            if data == nil {
                throw AuthErrorUtilities.operationNotAllowed(message: "No data returned.")
            } else {
                // todo: parse the ora codes and return specific cases eg. .weakPassword, etc.
                throw AuthErrorUtilities.operationNotAllowed(message: "\(String(data: data!, encoding: .utf8) ?? "Unknown error message.")")
            }
        }
        else if response.statusCode == 403 {
            if data == nil {
                throw AuthErrorUtilities.wrongPasswordError(message: "No data returned from server.")
            } else {
                // we check if the response is in html format
                let contentType = response.allHeaderFields["Content-Type"] as? String ?? ""
                
                // if it is, we parse it and try to obtain the message
                if contentType.lowercased().contains("text/html"),
                  let htmlString = String(data: data!, encoding: .utf8) {
                   
                   if let errorMessage = extractErrorMessage(from: htmlString, tag: "p") {
                       throw AuthErrorUtilities.wrongPasswordError(message: "403 Not authorized. Reason: " + errorMessage)
                   } else {
                       throw AuthErrorUtilities.wrongPasswordError(message: "403 Not authorized. Reason not provided from server.")
                   }
                
                }
                
                // if it's a json, we simply append the error message
                throw AuthErrorUtilities.wrongPasswordError(message: "\(String(data: data!, encoding: .utf8) ?? "Unknown error message.")")
            }
        }
        else if response.statusCode == 404 {
            if data == nil {
                throw AuthErrorUtilities.resourceNotFound(message: "No data returned from server.")
            } else {
                // we check if the response is in html format
                let contentType = response.allHeaderFields["Content-Type"] as? String ?? ""
                
                // if it is, we parse it and try to obtain the message
                if contentType.lowercased().contains("text/html"),
                  let htmlString = String(data: data!, encoding: .utf8) {
                   
                   if let errorMessage = extractErrorMessage(from: htmlString, tag: "p") {
                       throw AuthErrorUtilities.resourceNotFound(message: "404 Not Found. Reason: " + errorMessage)
                   } else {
                       throw AuthErrorUtilities.resourceNotFound(message: "404 Not Found. Reason not provided from server.")
                   }
                
                }
                
                // if it's a json, we simply append the error message
                throw AuthErrorUtilities.resourceNotFound(message: "\(String(data: data!, encoding: .utf8) ?? "Unknown error message.")")
            }
        }
        else if response.statusCode == 409 {
            if data == nil {
                throw AuthErrorUtilities.emailAlreadyInUse(message: "No data returned from server.")
            } else {
                let contentType = response.allHeaderFields["Content-Type"] as? String ?? ""
                if let bodyString = String(data: data!, encoding: .utf8) {
                    var message = bodyString
                    if contentType.lowercased().contains("application/json") {
                        if let json = try? JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] {
                            if let detail = json["detail"] as? String {
                                message = detail
                            } else if let description = json["description"] as? String {
                                message = description
                            }
                        }
                    } else if contentType.lowercased().contains("text/html") {
                        if let htmlMessage = extractErrorMessage(from: bodyString, tag: "div") ?? extractErrorMessage(from: bodyString, tag: "p") {
                            message = htmlMessage
                        }
                    }
                    throw AuthErrorUtilities.emailAlreadyInUse(message: message)
                }
                throw AuthErrorUtilities.emailAlreadyInUse(message: nil)
            }
        }
        else if (405...599).contains(response.statusCode) {
            if data == nil {
                throw AuthErrorUtilities.internalError(message: "No data returned.")
            } else {
                // we check if the response is in html format
                let contentType = response.allHeaderFields["Content-Type"] as? String ?? ""
                
                // if it is, we parse it and try to obtain the message
                if contentType.lowercased().contains("text/html"),
                   let htmlString = String(data: data!, encoding: .utf8) {
                    
                    if let errorMessage = extractErrorMessage(from: htmlString, tag: "div") {
                        throw AuthErrorUtilities.internalError(message: "HTTP Code: \(response.statusCode). Reason: " + errorMessage)
                    } else {
                        throw AuthErrorUtilities.internalError(message: "HTTP Code: \(response.statusCode). Reason not provided from server.")
                    }
                }
            }
            
            // if it's a json, we simply append the error message
            throw AuthErrorUtilities.internalError(message: "\(String(data: data!, encoding: .utf8) ?? "Unknown error message.")")
        }
        
    }
    
    /**
      Internal method to make an API request to the backend. This will gracefully handle any URLErrors that occur in the process and return an NSError object in said case.
        - Parameter URLRequest: already formed URLRequest object ready to be used
        - Returns : Data, URLResponse tuple
     */
    static func fusabaseCall(for URLRequest: URLRequest) async throws -> (Data, URLResponse) {
        // Log outgoing request details
        Self.fusabaseLogger.debug("🔍 HTTP Request: \(URLRequest.httpMethod ?? "GET") \(URLRequest.url?.absoluteString ?? "Unknown URL")")
        if let headers = URLRequest.allHTTPHeaderFields {
            Self.fusabaseLogger.debug("🔍 Request headers (redacted): \(Self.redactHeaders(headers))")
        }
        if let bodyPreview = Self.redactBodyPreview(URLRequest.httpBody) {
            Self.fusabaseLogger.debug("🔍 Request body preview (redacted): \(bodyPreview)")
        }

        do {
            let (data, response) = try await SecureNetworking.secureSession.data(for: URLRequest)

            // Log incoming response details
            if let httpResponse = response as? HTTPURLResponse {
                Self.fusabaseLogger.debug("📨 HTTP Response: \(httpResponse.statusCode) \(URLRequest.url?.absoluteString ?? "Unknown URL")")
                if let responseHeaders = httpResponse.allHeaderFields as? [String: String] {
                    Self.fusabaseLogger.debug("📨 Response headers (redacted): \(Self.redactHeaders(responseHeaders))")
                }
            }
            if let responsePreview = Self.redactBodyPreview(data) {
                Self.fusabaseLogger.debug("📨 Response body preview (redacted): \(responsePreview)")
            }

            return (data, response)
        } catch let urlError as URLError {
            let message = AuthErrorUtilities.handleURLError(urlError)
            throw AuthErrorUtilities.networkError(message: message)
        } catch {
            throw AuthErrorUtilities.networkError(message: nil)
        }
    }
    
    /**
        Internal method to calculate a custom mod
        - Parameter value: Int
        - Parameter modulus: Int
     */
    static func customMod(value: Int, modulus: Int) -> Int {
        var res = value % modulus
        if res < 0 {
            res += modulus
        }
        return res
    }
    
    /// RFC 7636 compliant
    
   // MARK: - Base64 URL Encoding (no padding, URL-safe)
        static func base64UrlEncode(_ data: Data) -> String {
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

    // MARK: - Generate Code Verifier
    static func generateCodeVerifier(length: Int = 128) -> String {
        precondition((43...128).contains(length), "Verifier length must be between 43 and 128 characters.")

        // Calculate the number of bytes needed to produce a base64 string of the desired length
        // Since base64 encodes 3 bytes to 4 characters, we need ceil(length * 3 / 4) bytes
        let byteLength = Int(ceil(Double(length) * 3.0 / 4.0))

        var bytes = [UInt8](repeating: 0, count: byteLength)
        let result = SecRandomCopyBytes(kSecRandomDefault, byteLength, &bytes)
        if result != errSecSuccess {
            fatalError("Unable to generate secure random bytes")
        }

        let encoded = base64UrlEncode(Data(bytes))
        // Ensure the result doesn't exceed the requested length
        return String(encoded.prefix(length))
    }

    // MARK: - Generate Code Challenge from Verifier
    static func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else {
            fatalError("Unable to convert verifier to data")
        }
        let hash = SHA256.hash(data: data)
        return base64UrlEncode(Data(hash))
    }
    
    // utility method to print network call details
    static func printNetworkResponseDetails(data: Data?, response: URLResponse?) {
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.fusabaseLogger.debug("No valid HTTP response.")
            return
        }
        
        Self.fusabaseLogger.debug("URL: \(httpResponse.url?.absoluteString ?? "Unknown URL")")
        Self.fusabaseLogger.debug("Status Code: \(httpResponse.statusCode)")
        if let data, let preview = Self.redactBodyPreview(data) {
            Self.fusabaseLogger.debug("Response body preview (redacted): \(preview)")
        } else {
            Self.fusabaseLogger.debug("No response data or unable to decode data to string.")
        }
    }
    
}
