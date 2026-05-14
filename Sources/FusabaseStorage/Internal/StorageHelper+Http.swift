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


extension StorageHelper {
    
    /// Builds an authenticated URLRequest for Storage operations.
    /// - Parameters:
    ///   - storageHelperFunc: Operation type (put/get/delete/list/metadata/genPreAuth).
    ///   - storageRef: Target storage reference.
    ///   - data: Request body for put operations.
    ///   - mimeType: Content-Type for uploads.
    ///   - maxResults: Max results for list.
    ///   - pageToken: Next page token (optional; defaults to "0").
    ///   - accessType: "ObjectRead" or "ObjectWrite" for pre-auth calls.
    /// - Returns: A configured URLRequest with apiKey and Authorization headers set.
    internal func setHttpRequest(storageHelperFunc: StorageHelperFunc, storageRef: StorageReference,
                                data: Data? = nil, mimeType: String? = nil,
                                maxResults: Int? = nil, pageToken: String? = nil,
                                accessType: String? = nil, recurse: Bool = false,
                                metadata: StorageMetadata? = nil) -> URLRequest {
        
        if storageHelperFunc == .putObj {
            assert (mimeType != nil && !mimeType!.isEmpty)
            assert (maxResults == nil)
            assert (pageToken == nil)
        } else if storageHelperFunc == .getObj {
            assert (data == nil)
            assert (mimeType == nil)
            assert (maxResults == nil)
            assert (pageToken == nil)
        } else if storageHelperFunc == .delObj {
            assert (data == nil)
            assert (mimeType == nil)
            assert (maxResults == nil)
            assert (pageToken == nil)
        } else if storageHelperFunc == .lstObjs {
            assert (data == nil)
            assert (mimeType == nil)
            assert (maxResults != nil)
            // pageToken can be nil; will default to "0" if missing
        } else if storageHelperFunc == .getMetadata {
            assert (data == nil)
            assert (mimeType == nil)
            assert (maxResults == nil)
            assert (pageToken == nil)
        } else if storageHelperFunc == .genPreAuth {
            assert (data == nil)
//            assert (mimeType == nil)
            
            if accessType == "ObjectWrite" {
                assert (mimeType != nil)
            }
            
            assert (maxResults == nil)
            assert (pageToken == nil)
        }   
        let bgnWithApiKey = "apiKey=" + self.appId
        
        
        // 1. get mutableStr
        var mutableStr = ""
        switch storageHelperFunc {
            case .putObj, .getObj, .delObj:
                mutableStr = "o/operation"
            case .lstObjs:
                mutableStr = "listallobj/b/" + self.bucket
            case .getMetadata:
                mutableStr = "getmetadata/b/" + self.bucket
            case .genPreAuth:
                mutableStr = "genpreauth"
        }
            
        let urlStr = self.endWithProjectId + "/" + mutableStr + "?" + bgnWithApiKey
        StorageLogger.debug("Request URL: \(urlStr)")
        
        guard let url = URL(string: urlStr)
        else {
            fatalError("Invalid URL")
        }
        var req = URLRequest(url: url)
        
        // 3. setup http method
        switch storageHelperFunc {
            case .putObj:
                req.httpMethod = "POST"
            case .getObj:
                req.httpMethod = "GET"
            case .delObj:
                req.httpMethod = "DELETE"
            case .lstObjs:
                req.httpMethod = "GET"
            case .getMetadata:
                req.httpMethod = "GET"
            case .genPreAuth:
                req.httpMethod = "POST"
        }
        
        var pathAttr: [String: Any] = [:]
        switch storageHelperFunc {
            case .putObj, .getObj, .delObj, .getMetadata:
                pathAttr = ["path": storageRef.fullPath, "bucket": self.bucket]
            case .lstObjs:
                let tokenVal = pageToken ?? "0"
                pathAttr = ["path": storageRef.fullPath, "recurse": recurse, "pageToken": tokenVal, "maxResults": maxResults!]
            case .genPreAuth:
                break
        }
        // convert pathAttr to jsonPathAttrStr
        guard let jsonPathAttr = try? JSONSerialization.data(withJSONObject: pathAttr),
            let jsonPathAttrStr = String(data: jsonPathAttr, encoding: .utf8) else {
                fatalError("Error serializing x-transaction header")
        }
        // set
        switch storageHelperFunc {
            case .putObj, .getObj, .delObj, .getMetadata:
                req.setValue(jsonPathAttrStr, forHTTPHeaderField: "x-object-path")
            case .lstObjs:
                req.setValue(jsonPathAttrStr, forHTTPHeaderField: "x-dbfs-list-opts")
            case .genPreAuth:
                break
        }
        
        // Authorization - securely add header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        
        // set Content-Type in header
        if storageHelperFunc == .putObj {
            // Set content type from metadata if provided, otherwise use mimeType
            if let metadata = metadata, let contentType = metadata.contentType {
                req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            } else {
                req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            }

            // Set other metadata headers
            if let metadata = metadata {
                if let cacheControl = metadata.cacheControl {
                    req.setValue(cacheControl, forHTTPHeaderField: "Cache-Control")
                }
                if let contentDisposition = metadata.contentDisposition {
                    req.setValue(contentDisposition, forHTTPHeaderField: "Content-Disposition")
                }
                if let contentEncoding = metadata.contentEncoding {
                    req.setValue(contentEncoding, forHTTPHeaderField: "Content-Encoding")
                }
                if let contentLanguage = metadata.contentLanguage {
                    req.setValue(contentLanguage, forHTTPHeaderField: "Content-Language")
                }
                // Set custom metadata as headers with x-metadata- prefix
                if let customMetadata = metadata.customMetadata {
                    for (key, value) in customMetadata {
                        req.setValue(value, forHTTPHeaderField: "x-metadata-\(key)")
                    }
                }
            }
        } else if storageHelperFunc == .genPreAuth {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // 5. set http body
        if storageHelperFunc == .putObj, let data {
            req.httpBody = data
        } else if storageHelperFunc == .genPreAuth {

            // Use provided metadata or create default with contentType
            var metadataVal: [String: Any] = [:]
            if let providedMetadata = metadata {
                // Convert StorageMetadata to dictionary
                metadataVal = providedMetadata.dictionaryRepresentation()
            } else if accessType == "ObjectWrite" {
                // Fallback: create minimal metadata with contentType
                metadataVal = ["contentType": mimeType!]
            }

            let bodyDict: [String: Any] = [
                "path": storageRef.fullPath,
                "bucket": bucket,
                "access_type": accessType!,
                "metadata": metadataVal
            ]
            do {
                let jsonBody = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
                req.httpBody = jsonBody
            } catch {
                StorageLogger.error("Failed to serialize JSON body: \(error)")
            }
        }

        StorageLogger.debug("Request prepared: \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "Unknown URL")")
        StorageLogger.debug("Request body length: \(req.httpBody?.count ?? 0) bytes")
        
        return req
    }
    
    /// Validates an HTTPURLResponse and maps errors to StorageErrorUtilities.
    /// - Parameters:
    ///   - data: Raw response body.
    ///   - response: URLResponse expected to be HTTPURLResponse.
    /// - Returns: Parsed JSON dictionary (or wrapper for non-JSON success).
    /// - Throws: Mapped Storage errors for non-2xx responses, malformed JSON, or unknown failures.
    internal func handleHttpResponse(data: Data, response: URLResponse) throws -> [String: Any] {
        let httpResp = response as? HTTPURLResponse
        let status = httpResp?.statusCode ?? -1
        let contentType = httpResp?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        
        StorageLogger.debug("Response status: \(status)")
        StorageLogger.debug("Response content-type: \(contentType)")
        StorageLogger.debug("Response data length: \(data.count) bytes")
        
        func parseJSONDict(_ data: Data) -> [String: Any]? {
            if data.isEmpty { return [:] }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            return nil
        }
        
        func mappedError(_ status: Int, defaultMessage: String) -> Error {
            var message = defaultMessage
            if let json = parseJSONDict(data) {
                if let m = json["message"] as? String {
                    message = m
                } else if let e = json["error"] as? String {
                    message = e
                }
            } else if !bodyString.isEmpty {
                message = bodyString
            }
            var userInfo: [String: Any] = [
                "httpStatus": status,
                "responseBody": bodyString,
                NSLocalizedDescriptionKey: message
            ]
            // Use the userInfo-based creator so we keep HTTP context
            switch status {
            case 400: return StorageErrorUtilities.error(code: .invalidArgument, userInfo: userInfo)
            case 401: return StorageErrorUtilities.error(code: .unauthenticated, userInfo: userInfo)
            case 403: return StorageErrorUtilities.error(code: .unauthorized, userInfo: userInfo)
            case 404: return StorageErrorUtilities.error(code: .objectNotFound, userInfo: userInfo)
            case 409: return StorageErrorUtilities.error(code: .bucketMismatch, userInfo: userInfo)
            case 413: return StorageErrorUtilities.error(code: .quotaExceeded, userInfo: userInfo)
            case 429: return StorageErrorUtilities.error(code: .retryLimitExceeded, userInfo: userInfo)
            case 500...599: return StorageErrorUtilities.error(code: .internalError, userInfo: userInfo)
            default: return StorageErrorUtilities.error(code: .unknown, userInfo: userInfo)
            }
        }
        
        // Success path
        if (200...299).contains(status) {
            // 204 or empty body -> return empty dictionary
            if status == 204 || data.isEmpty {
                return [:]
            }
            if let json = parseJSONDict(data) {
                return json
            }
            // If server claims JSON but we cannot parse, treat as error
            if contentType.lowercased().contains("application/json") {
                throw mappedError(status, defaultMessage: "Invalid JSON format")
            }
            // Non-JSON success: return a minimal wrapper
            return ["data": bodyString, "httpStatus": status]
        }
        
        // Error path
        throw mappedError(status, defaultMessage: "HTTP error \(status)")
    }
}
