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
import FusabaseAuth

    /// Internal discriminator for backend operation types used by QueryHelper request builders.
    /// - addDoc: Create a document
    /// - delDoc: Delete a document
    /// - setDoc: Set/overwrite a document (with optional merge semantics)
    /// - updDoc: Partially update specific fields of a document
    /// - qryDoc: Execute a query and return result documents
enum QueryHelperFunc {
    case addDoc
    case delDoc
    case setDoc
    case updDoc
    case qryDoc
}

/**
 Helper for constructing and executing HTTP/WebSocket requests to Oracledb backends.

 QueryHelper is an internal service used by higher-level APIs such as
 DocumentReference, CollectionReference/Query, Transaction, and WriteBatch to
 perform CRUD, query, aggregation, and listener operations.
 
 This type is not intended to be used directly by SDK consumers.
 */
class QueryHelper {


    // Base API service path.
    static let BAAS_SERVICE = "/_/baas-services"

    // Database service path.
    static let DATABASE = "/database"

    // IDM service path.
    static let IDM = "/idm"

    // ONPREM service path.
    static let ONPREM = "/onprem"

    // Authorize snapshot path.
    static let AUTHORIZE_SNAPSHOT = "/authorizeSnapshot"

    // API version 1 path.
    static let V1 = "v1"

    // API version 2 path.
    static let V2 = "v2"

    // Run query endpoint.
    static let RUN_QUERY = "/runQuery"

    // Delete document endpoint.
    static let DELETE_DOCUMENT = "deleteDocument"

    // Set document endpoint.
    static let SET_DOCUMENT = "setDocument"

    // Update document endpoint.
    static let UPDATE_DOCUMENT = "updateDocument"

    // API version string.
    let API_VERSION: String

    // Options instance.
    let options: FusabaseOptions

    // Oracledb instance.
    let oradb: FusabaseOracledb

    // Flag indicating if OID is created.
    var oidCreated: Bool

    init(options: FusabaseOptions, oradb: FusabaseOracledb) {
        self.options = options
        self.oradb = oradb
        self.oidCreated = false
        self.API_VERSION = options.useOracledbVersion == 1 ? "1.0" : "2.0"
    }

    /**
     * Creates a path JSON object for standard paths.
     */
    private func getPathObject(path: [String]) -> [String: Any] {
        return ["path": path]
    }

    /**
     * Creates a path JSON object for duality views.
     */
    func getDualityViewPathObject(path: [String]) -> [String: Any] {
        var payload: [String: Any] = [:]
        payload["dv_name"] = path[0]
        if path.count > 1 {
            payload["oid"] = path[1]
        }
        return payload
    }
    
    /**
      Deletes the specified document from Oracledb.
      - Note: This is an asynchronous function.

      - Parameter docRef: The `DocumentReference` of the document to be deleted.
      - Parameter completion: An optional completion handler that returns an `Error?` if the operation fails.

      - Throws: An error if the document deletion fails.
      - Returns: A dictionary containing the response data.
    */
    @available(macOS 10.15.0, *)
    func deleteDocument(docRef: DocumentReference, completion: ((Error?) -> Void)? = nil) async throws -> [String: Any] {

        let urlStr = options.ordsHost + ":" + options.ordsPort + "/ords/" + options.schema + QueryHelper.BAAS_SERVICE + QueryHelper.DATABASE + "/" + options.projectId + "/" + QueryHelper.DELETE_DOCUMENT

        guard let url = URL(string: urlStr) else {
            throw OracledbErrorUtilities.invalidURLError(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Transaction header
        let tranAttr: [String: Any] = [
            "begin_trans": 0,
            "end_trans": 0,
            "trans_name": ""
        ]
        if let tranData = try? JSONSerialization.data(withJSONObject: tranAttr),
           let tranStr = String(data: tranData, encoding: .utf8) {
            request.setValue(tranStr, forHTTPHeaderField: "x-transaction")
        }

        // Authorization - securely add header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }

        // Query params
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "apiKey", value: options.appId)
        ]
        if let finalURL = urlComponents?.url {
            request.url = finalURL
        }

        // Payload
        var payload: [String: Any] = [:]
        payload["path"] = docRef.path.components(separatedBy: "/")

        if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = bodyData
        }

        let (data, resp) = try await SecureNetworking.secureSession.data(for: request)
        return try handleHttpResponse(data: data, response: resp)
    }

    /**
      Sets the given document to the specified data. If the document exists, it can be merged with the existing data.
      - Note: This is an asynchronous function.

      - Parameter docRef: The `DocumentReference` of the document to be set.
      - Parameter docData: A dictionary containing the document data.
      - Parameter merge: A Boolean indicating whether to merge the new data with existing data (`true`) or replace it entirely (`false`).
      - Parameter completion: An optional completion handler that returns an `Error?` if the operation fails.

      - Throws: An error if the document setting operation fails.
      - Returns: A dictionary containing the updated document's data, or `nil` if the operation was unsuccessful.
    */
    @available(macOS 10.15.0, *)
    func setDocument(docRef: DocumentReference, docData: [String : Any], merge: Bool = false, mergeFields: [String]? = nil, completion: ((Error?) -> Void)? = nil) async throws -> [String: Any] {

        // For the current ORDS version, mergeFields isn't passed directly to the API call.
        // Instead, the API only recollects the fields that need to be updated and performs said operation.
        // For compatibility with the setData(mergeFields:) method, this transformation is done internally.

        // For convenience, we define a new document where we will save the document to be sent
        var new_data: [String: Any] = [:]

        if mergeFields != nil {
            for i in mergeFields! {
                new_data[i] = docData[i]
            }
        } else {
            // If there's no mergeFields passed, we simply update our new document with the one passed
            // as a parameter
            new_data = docData
        }

        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.setDoc, ref: docRef, docData: new_data, merge: merge, mergeFields: nil)

        let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
        return try handleHttpResponse(data: data, response: resp)
    }

    /**
      Updates an existing document with the specified fields.
      - Note: This is an asynchronous function.

      - Parameter docRef: The `DocumentReference` of the document to be updated.
      - Parameter fields: A dictionary containing the fields to update.
      - Parameter completion: An optional completion handler that returns an `Error?` if the operation fails.

      - Throws: An error if the document update fails.
      - Returns: A dictionary containing the updated document's data, or `nil` if the update was unsuccessful.
    */
    @available(macOS 10.15.0, *)
    func updateDocument(docRef: DocumentReference, fields: [AnyHashable : Any], completion: ((Error?) -> Void)? = nil) async throws -> [String: Any] {

        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.updDoc, ref: docRef, docData: fields)
        let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
        return try handleHttpResponse(data: data, response: resp)
    }

    /**
      Sets the given document at the specified path to new data. If the path doesn't exist, a new one will be created.
      - Note: This is an asynchronous function.

      - Parameter colRef: The `CollectionReference` where the document will be created.
      - Parameter docData: A dictionary containing the document data.
      - Parameter completion: An optional completion handler that returns an `Error?` if the operation fails.

      - Throws: An error if the document creation fails.
      - Returns: A dictionary containing the created document's data.
    */
    @available(macOS 10.15.0, *)
    func createDocument(colRef: CollectionReference, docData: [String : Any], completion: ((Error?) -> Void)? = nil) async throws -> [String: Any] {

        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.addDoc, ref: colRef, docData: docData)
        let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
        return try handleHttpResponse(data: data, response: resp)
    }

    /**
      Fetches the document data from the specified document reference.
      - Note: This is an asynchronous function.

      - Parameter docRef: The `DocumentReference` representing the Oracledb document to fetch.
      - Parameter completion: An optional completion handler that returns an `Error?` if the operation fails.

      - Throws: An error if the document fetch operation fails.
      - Returns: A dictionary containing the document's data.
    */
    @available(macOS 10.15.0, *)
    func fetchDocuments(ref: Any, completion: ((Error?) -> Void)? = nil) async throws -> [String: Any] {

        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.qryDoc, ref: ref)
        let (data, resp) = try await SecureNetworking.secureSession.data(for: req)
        // Parity with Android: on 403/404, return empty result instead of throwing
        if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 403 || httpResp.statusCode == 404 {
            OracledbLogger.info("fetchDocuments: returning empty 'ret' for HTTP status \(httpResp.statusCode)")
            return ["ret": []]
        }
        return try handleHttpResponse(data: data, response: resp)
    }
    
    
    // Sync call

    /// Performs a synchronous HTTP request using the given URLRequest.
    /// - Parameter request: A standard URLRequest.
    /// - Returns: A tuple of (Data, URLResponse).
    /// - Throws: Any error that occurred during the request.
    func syncHttpRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
        var resultData: Data?
        var resultResponse: URLResponse?
        var resultError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        SecureNetworking.secureSession.dataTask(with: request) { data, response, error in
            resultData = data
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()

        semaphore.wait()

        if let error = resultError {
            throw error
        }

        guard let data = resultData, let response = resultResponse else {
            throw URLError(.badServerResponse)
        }

        return (data, response)
    }


    func deleteDocumentSync(docRef: DocumentReference, txnOp: TransactionOperation? = nil) -> [String: Any] {
        do {
            let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.delDoc, ref: docRef, docData: nil, txnOp: txnOp)
            let (data, resp) = try syncHttpRequest(req)
            return try handleHttpResponse(data: data, response: resp)
        } catch {
            OracledbLogger.error("deleteDocumentSync request failed: \(error.localizedDescription)")
        }
        return [:]
    }

    func setDocumentSync(docRef: DocumentReference, docData: [String : Any], merge: Bool, txnOp: TransactionOperation? = nil) -> [String: Any] {
        do {
            let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.setDoc, ref: docRef, docData: docData, merge: merge, txnOp: txnOp)
            let (data, resp) = try syncHttpRequest(req)
            return try handleHttpResponse(data: data, response: resp)
        } catch {
            OracledbLogger.error("setDocumentSync request failed: \(error.localizedDescription)")
        }
        return [:]
    }

    func updateDocumentSync(docRef: DocumentReference, fields: [AnyHashable : Any], txnOp: TransactionOperation? = nil) -> [String: Any] {
        do {
            let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.updDoc, ref: docRef, docData: fields, txnOp: txnOp)
            let (data, resp) = try syncHttpRequest(req)
            return try handleHttpResponse(data: data, response: resp)
        } catch {
            OracledbLogger.error("updateDocumentSync request failed: \(error.localizedDescription)")
        }
        return [:]
    }

    // Throwing variants to surface errors to callers (e.g., WriteBatch.commitThrowing())
    func deleteDocumentSyncThrowing(docRef: DocumentReference, txnOp: TransactionOperation? = nil) throws -> [String: Any] {
        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.delDoc, ref: docRef, docData: nil, txnOp: txnOp)
        let (data, resp) = try syncHttpRequest(req)
        return try handleHttpResponse(data: data, response: resp)
    }

    func setDocumentSyncThrowing(docRef: DocumentReference, docData: [String : Any], merge: Bool, txnOp: TransactionOperation? = nil) throws -> [String: Any] {
        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.setDoc, ref: docRef, docData: docData, merge: merge, txnOp: txnOp)
        let (data, resp) = try syncHttpRequest(req)
        return try handleHttpResponse(data: data, response: resp)
    }

    func updateDocumentSyncThrowing(docRef: DocumentReference, fields: [AnyHashable : Any], txnOp: TransactionOperation? = nil) throws -> [String: Any] {
        let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.updDoc, ref: docRef, docData: fields, txnOp: txnOp)
        let (data, resp) = try syncHttpRequest(req)
        return try handleHttpResponse(data: data, response: resp)
    }
    
    func fetchDocumentsSync(ref: Any) -> [String: Any] {
        do {
            let req = try setHttpRequest(queryHelperFunc: QueryHelperFunc.qryDoc, ref: ref)
            let (data, resp) = try syncHttpRequest(req)
            // Parity with Android: on 403/404, return empty result instead of throwing
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 403 || httpResp.statusCode == 404 {
                OracledbLogger.info("fetchDocumentsSync: returning empty 'ret' for HTTP status \(httpResp.statusCode)")
                return ["ret": []]
            }
            return try handleHttpResponse(data: data, response: resp)
        } catch {
            OracledbLogger.error("fetchDocumentsSync request failed: \(error.localizedDescription)")
        }
        return [:]
    }

    // Core methods similar to Java

    /**
     * Fetches documents from the database.
     */
    func fetchDocs(path: [String], payload: [String: Any], operation: TransactionOperation) throws -> [String: Any] {
        let urlStr = options.ordsHost + ":" + options.ordsPort + "/ords/" + options.schema + QueryHelper.BAAS_SERVICE + QueryHelper.DATABASE + "/" + options.projectId + "/" + (API_VERSION == "2.0" ? QueryHelper.V2 : QueryHelper.V1) + QueryHelper.RUN_QUERY + "?apiKey=" + options.appId

        guard let url = URL(string: urlStr) else {
            throw OracledbErrorUtilities.invalidURLError(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Transaction header
        let tranAttr: [String: Any] = [
            "begin_trans": operation.getBeginTrans,
            "end_trans": operation.getEndTrans,
            "trans_name": operation.getTransactionName
        ]
        if let tranData = try? JSONSerialization.data(withJSONObject: tranAttr),
           let tranStr = String(data: tranData, encoding: .utf8) {
            request.setValue(tranStr, forHTTPHeaderField: "x-transaction")
        }

        // Authorization - securely add header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        // Body
        if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = bodyData
        }

        let (data, response) = try syncHttpRequest(request)
        if let httpResp = response as? HTTPURLResponse {
            if httpResp.statusCode == 200 {
                return try handleHttpResponse(data: data, response: response)
            } else if httpResp.statusCode == 403 || httpResp.statusCode == 404 {
                OracledbLogger.info("fetchDocs: returning empty 'ret' for HTTP status \(httpResp.statusCode)")
                return ["ret": []]
            }
        }
        return try handleHttpResponse(data: data, response: response)
    }

    /**
     * Removes documents from the database.
     */
    func removeDocs(path: [String], entityReference: Any, operation: TransactionOperation) throws -> [String: Any] {
        let urlStr = options.ordsHost + ":" + options.ordsPort + "/ords/" + options.schema + QueryHelper.BAAS_SERVICE + QueryHelper.DATABASE + "/" + options.projectId + "/" + QueryHelper.DELETE_DOCUMENT

        guard let url = URL(string: urlStr) else {
            throw OracledbErrorUtilities.invalidURLError(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Transaction header
        let tranAttr: [String: Any] = [
            "begin_trans": operation.getBeginTrans,
            "end_trans": operation.getEndTrans,
            "trans_name": operation.getTransactionName
        ]
        if let tranData = try? JSONSerialization.data(withJSONObject: tranAttr),
           let tranStr = String(data: tranData, encoding: .utf8) {
            request.setValue(tranStr, forHTTPHeaderField: "x-transaction")
        }

        // Authorization - securely add header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }

        // Query params
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "apiKey", value: options.appId)
        ]
        if let finalURL = urlComponents?.url {
            request.url = finalURL
        }

        // Payload
        var payload: [String: Any] = [:]
        // Simplified: assume entityReference is DocumentReference or similar
        payload["path"] = path

        if let dualityDoc = entityReference as? DualityViewDocReference {
            payload["dv_name"] = path[0]
            payload["oid"] = dualityDoc.documentId
            payload.removeValue(forKey: "path")
        }

        // Add version to payload if available
        if let ver = operation.getVersion, ver != TransactionOperation.DOES_NOT_EXIST_VERSION {
            payload["version"] = ver
        }

        if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = bodyData
        }

        let (data, response) = try syncHttpRequest(request)
        return try handleHttpResponse(data: data, response: response)
    }

    /**
     * Sets documents in the database.
     */
    func setDocs(path: [String], data: Any, setOptions: SetOptions?, entityReference: Any, operation: TransactionOperation) throws -> [String: Any] {
        // Versioned endpoint for setDocument (parity with Android)
        let versionSegment = (API_VERSION == "2.0") ? QueryHelper.V2 : QueryHelper.V1
        let urlStr = options.ordsHost + ":" + options.ordsPort + "/ords/" + options.schema + QueryHelper.BAAS_SERVICE + QueryHelper.DATABASE + "/" + options.projectId + "/" + versionSegment + "/" + QueryHelper.SET_DOCUMENT

        guard let url = URL(string: urlStr) else {
            throw OracledbErrorUtilities.invalidURLError(message: "Invalid URL")
        }
        
        OracledbLogger.info("url: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Transaction header
        let tranAttr: [String: Any] = [
            "begin_trans": operation.getBeginTrans,
            "end_trans": operation.getEndTrans,
            "trans_name": operation.getTransactionName
        ]
        if let tranData = try? JSONSerialization.data(withJSONObject: tranAttr),
           let tranStr = String(data: tranData, encoding: .utf8) {
            request.setValue(tranStr, forHTTPHeaderField: "x-transaction")
        }

        // Authorization - securely add header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }

        // Query params
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "apiKey", value: options.appId)
        ]
        if let finalURL = urlComponents?.url {
            request.url = finalURL
        }

        // Convert data and create payload using createUpdatePayload
        guard let dataDict = data as? [String: Any] else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Data must be [String: Any]")
        }

        let isAddDoc = (setOptions == nil)
        let merge = setOptions?.merge ?? false
        let payloadResult = createUpdatePayload(data: dataDict, path: path, entityReference: entityReference, operation: operation, isAddDoc: isAddDoc, setOptions: SetOptions(merge: merge, mergeFields: nil))

        var payload: [String: Any] = [:]
        payload["path"] = path
        payload["data"] = payloadResult.data
        if let servertimestamps = payloadResult.servertimestamp, !servertimestamps.isEmpty {
            payload["servertimestamp"] = servertimestamps
        }

        if let setOpts = setOptions {
            payload["options"] = [
                "merge": setOpts.merge,
                "mergeFields": setOpts.mergeFields ?? []
            ]
            // Only include apiversion for v2 when options (merge) are provided (Android parity)
            if API_VERSION == "2.0" {
                payload["apiversion"] = 2
            }
        }

        if let dvDoc = entityReference as? DualityViewDocReference {
            payload.removeValue(forKey: "path")
            payload["dv_name"] = path[0]
            // Only include OID for DV set if it already exists (overwrite/merge existing doc).
            if dvDoc.oidGenerated {
                payload["oid"] = dvDoc.documentId
            }
        }

        // Add version to payload if available
        if let ver = operation.getVersion, ver != TransactionOperation.DOES_NOT_EXIST_VERSION {
            payload["version"] = ver
        }

        OracledbLogger.info("payload \(payload)")
        if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = bodyData
        }

        let (respData, response) = try syncHttpRequest(request)
        return try handleHttpResponse(data: respData, response: response)
    }

    /**
     * Updates documents in the database.
     */
    func updateDocs(path: [String], data: [AnyHashable: Any], entityReference: Any, operation: TransactionOperation, conditions: [[String: Any]]? = nil) throws -> [String: Any] {
        // Versioned endpoint for updateDocument (parity with Android)
        let versionSegment = (API_VERSION == "2.0") ? QueryHelper.V2 : QueryHelper.V1
        let urlStr = options.ordsHost + ":" + options.ordsPort + "/ords/" + options.schema + QueryHelper.BAAS_SERVICE + QueryHelper.DATABASE + "/" + options.projectId + "/" + versionSegment + "/" + QueryHelper.UPDATE_DOCUMENT

        guard let url = URL(string: urlStr) else {
            throw OracledbErrorUtilities.invalidURLError(message: "Invalid URL")
        }
        
        OracledbLogger.info("url: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Transaction header
        let tranAttr: [String: Any] = [
            "begin_trans": operation.getBeginTrans,
            "end_trans": operation.getEndTrans,
            "trans_name": operation.getTransactionName
        ]
        if let tranData = try? JSONSerialization.data(withJSONObject: tranAttr),
           let tranStr = String(data: tranData, encoding: .utf8) {
            request.setValue(tranStr, forHTTPHeaderField: "x-transaction")
        }

        // Authorization - securely add header using token that gets cleared immediately
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }

        // Query params
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "apiKey", value: options.appId)
        ]
        if let finalURL = urlComponents?.url {
            request.url = finalURL
        }

        // Create payload using createUpdatePayload
        let payloadResult = createUpdatePayload(data: data, path: path, entityReference: entityReference, operation: operation, isAddDoc: false, setOptions: nil)

        var payload: [String: Any] = [:]
        // Modify path for bulk updates (add "*" when conditions are provided)
        var bulkUpdatePath = path
        if let conditions = conditions, !conditions.isEmpty {
            bulkUpdatePath = path + ["*"]
        }
        payload["path"] = bulkUpdatePath
        payload["data"] = payloadResult.data
        if let servertimestamps = payloadResult.servertimestamp, !servertimestamps.isEmpty {
            payload["servertimestamp"] = servertimestamps
        }

        if API_VERSION == "2.0" {
            payload["apiversion"] = 2
        }

        if let dvDoc = entityReference as? DualityViewDocReference {
            payload.removeValue(forKey: "path")
            payload["dv_name"] = path[0]
            // For API v1.0, do NOT include OID in the top-level payload to avoid overwrite semantics.
            // For API v2.0, include OID explicitly.
            if API_VERSION == "2.0" {
                payload["oid"] = dvDoc.documentId
            }
        }

        // Add conditions for bulk update if provided
        if let conditions = conditions {
            payload["conditions"] = conditions
        }

        // Add version to payload if available
        if let ver = operation.getVersion, ver != TransactionOperation.DOES_NOT_EXIST_VERSION {
            payload["version"] = ver
        }

        OracledbLogger.info("payload \(payload)")

        if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
            request.httpBody = bodyData
        }

        let (respData, response) = try syncHttpRequest(request)
        return try handleHttpResponse(data: respData, response: response)
    }

}
