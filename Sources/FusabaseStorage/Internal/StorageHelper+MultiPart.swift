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


enum MultiPartOp {
    case putData
    case commit
    case abort
}

extension StorageHelper {
    
    /// Builds a URLRequest for multipart operations (PUT chunk, POST commit, DELETE abort).
    /// - Parameters:
    ///   - url: Pre-auth base URL.
    ///   - op: Operation to perform (putData/commit/abort).
    ///   - storageRef: Associated reference for headers.
    ///   - data: Chunk payload for putData.
    ///   - mimeType: MIME type for chunk uploads.
    /// - Returns: Configured URLRequest with Authorization, apiKey and x-object-path.
    internal func setHttpRequestForMultiPart(url: URL, op: MultiPartOp, storageRef: StorageReference,
                                             data: Data? = nil, mimeType: String? = nil) -> URLRequest
    {
        if (op == .putData) {
            assert(data != nil)
            assert(mimeType != nil)
        } else if (op == .commit) {
            assert(data == nil)
            assert(mimeType == nil)
        }
        
        // Append apiKey query parameter as Java helper does for multipart operations
        var finalURL = url
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var q = comps.queryItems ?? []
            q.append(URLQueryItem(name: "apiKey", value: self.appId))
            comps.queryItems = q
            if let newURL = comps.url {
                finalURL = newURL
            }
        }
        var req = URLRequest(url: finalURL)
        
        // setup http method
        switch op {
        case .putData:
            req.httpMethod = "PUT"
        case .commit:
            req.httpMethod = "POST"
        case .abort:
            req.httpMethod = "DELETE"
        }
        
        // Authorization header - securely add using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        // x-object-path header similar to Java implementation
        let pathAttr: [String: Any] = ["path": storageRef.fullPath, "bucket": self.bucket]
        if let jsonPathAttr = try? JSONSerialization.data(withJSONObject: pathAttr),
           let jsonPathAttrStr = String(data: jsonPathAttr, encoding: .utf8) {
            req.setValue(jsonPathAttrStr, forHTTPHeaderField: "x-object-path")
        }
        
        if op == .putData {
            // set Content-Type in header
            req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            // set http body
            req.httpBody = data
        }
        
        StorageLogger.debug("Multipart request prepared: \(req.httpMethod ?? "-") \(finalURL.absoluteString)")
        return req
    }
    
    
}
