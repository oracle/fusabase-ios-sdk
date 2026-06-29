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
 * Represents the result of creating an update payload.
 * Contains the processed data to send and optional server timestamp fields.
 */
struct UpdatePayloadResult {
    let data: Any  // Can be [String: Any] for document data or [[String: Any]] for operations array
    let servertimestamp: [String]?  // Server timestamp field names, if any
}

extension QueryHelper {
    
    // getPathArray - makes an array containing the path in the format the API expects
    internal func getPathArray(fromPath pathString: String) -> [String] {
        return pathString.components(separatedBy: "/")
    }
    
    
    internal func processUpdateData(docData: [AnyHashable: Any]) throws -> [String: Any] {
        var updatedFormat: [[String: Any]] = []
        var servertimestamp: [String] = []

        // --- Vector field extraction (API v2 operations array) ---
        // Collect vector set/delete ops and later skip them from normal field operations.
        var vectorSetMap: [String: Any] = [:]
        var vectorDeleteKeys: [String] = []

        for (k, v) in docData {
            guard let keyStr = k as? String else { continue }
            if let vec = v as? VectorSentinel {
                switch vec {
                case .dense(let values):
                    try validateDenseVector(values, message: "Vector '\(keyStr)' must be a numeric array.")
                    vectorSetMap[keyStr] = encodeDenseVectorPayload(values)
                case .sparse(let sparse):
                    try validateSparseVector(sparse)
                    vectorSetMap[keyStr] = encodeSparseVectorPayload(sparse)
                case .delete:
                    vectorDeleteKeys.append(keyStr)
                }
            }
        }

        if !vectorSetMap.isEmpty {
            updatedFormat.append([
                "field": "$embeddings",
                "op": "set",
                "value": vectorSetMap,
                "valueType": "mapValue",
            ])
        }
        if !vectorDeleteKeys.isEmpty {
            updatedFormat.append([
                "field": "$embeddings",
                "op": "delete",
                "value": vectorDeleteKeys,
                "valueType": "arrayValue",
            ])
        }

        // Inner helper: normalize AnyHashable key to String; only String and FieldPath are allowed.
        func stringifyFieldKey(_ key: AnyHashable) throws -> String {
            // Accept FieldPath
            if let fp = key as? FieldPath {
                // Validate FieldPath segments are not empty/whitespace
                if fp.fieldNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    throw OracledbErrorUtilities.invalidArgumentError(message: "Field path contains an empty segment")
                }
                return fp.path
            }
            // Accept String (non-empty, no empty segments)
            if let s = key as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix(".") || trimmed.hasSuffix(".") || trimmed.contains("..") {
                    throw OracledbErrorUtilities.invalidArgumentError(message: "Field name cannot be empty")
                }
                return trimmed
            }
            // Everything else is an error (explicitly fail fast)
            throw OracledbErrorUtilities.invalidArgumentError(message: "Unsupported key type for updateData: only String and FieldPath are allowed.")
        }

        for (key, value) in docData {
            var elem: [String: Any] = [:]
            let fieldKey = try stringifyFieldKey(key) // always a String or trap above

            // Skip vector keys already handled via $embeddings.
            if (vectorSetMap[fieldKey] != nil) || vectorDeleteKeys.contains(fieldKey) {
                continue
            }
            elem["field"] = fieldKey

            if let fv = value as? FieldValue {
                // If value is FieldValue: use operation string and carry its values array
                elem["op"] = fv.operationString
                if fv.operationString == "increment" {
                    elem["value"] = fv.getValues()[0]
                } else if fv.getValues().isEmpty {
                    elem["value"] = ""
                } else {
                    elem["value"] = fv.getValues()
                }
                // Collect servertimestamp fields
                if fv.operationString == "servertimestamp" {
                    servertimestamp.append(fieldKey)
                }
            } else {
                // Default: plain "set" with the given value
                elem["op"] = "set"
                elem["value"] = value
            }

            updatedFormat.append(elem)
        }
        return ["dataArray": updatedFormat, "servertimestamp": servertimestamp]
    }

    /// Validate update keys before building payload to fail fast on invalid field names.
    internal func validateUpdateKeys(_ docData: [AnyHashable: Any]) throws {
        for (key, _) in docData {
            if let fp = key as? FieldPath {
                if fp.fieldNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    throw OracledbErrorUtilities.invalidArgumentError(message: "Field path contains an empty segment")
                }
            } else if let s = key as? String {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix(".") || trimmed.hasSuffix(".") || trimmed.contains("..") {
                    throw OracledbErrorUtilities.invalidArgumentError(message: "Field name cannot be empty")
                }
            } else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "Unsupported key type for updateData: only String and FieldPath are allowed.")
            }
        }
    }

    internal func normalizeV2CreatePayloadData(_ data: [String: Any]) throws -> [String: Any] {
        var normalized: [String: Any] = [:]
        var embeddings: [String: Any] = [:]

        for (key, value) in data {
            if let vec = value as? VectorSentinel {
                switch vec {
                case .dense(let values):
                    try validateDenseVector(values, message: "Vector '\(key)' must be a numeric array.")
                    embeddings[key] = encodeDenseVectorPayload(values)
                case .sparse(let sparse):
                    try validateSparseVector(sparse)
                    embeddings[key] = encodeSparseVectorPayload(sparse)
                case .delete:
                    throw OracledbErrorUtilities.invalidArgumentError(message: "deleteVector() is not supported in addDocument/create payload. Use update/set merge contexts.")
                }
            } else {
                normalized[key] = value
            }
        }

        if !embeddings.isEmpty {
            normalized["$embeddings"] = embeddings
        }
        return normalized
    }

    /**
     * Creates the update payload based on API version.
     * Equivalent to Android's createUpdatePayload method.
     */
    internal func createUpdatePayload(data: [AnyHashable: Any], path: [String], entityReference: Any, operation: TransactionOperation, isAddDoc: Bool, setOptions: SetOptions?) -> UpdatePayloadResult {
        var updatedData: [String: Any] = [:]

        do {
            var doc: [String: Any] = [:]
            var servertimestamp: [String] = []

            if API_VERSION == "1.0" {
                // For v1.0, fetch existing document for merge operations
                if !path.last!.contains("BAAS_DOC_TEMP_ID=") && (setOptions == nil || setOptions!.merge) {
                    
                    let fetchResult = try fetchDocs(path: path, payload: entityReference is DualityViewDocReference ? self.getDualityViewPathObject(path: path) : getPathObject(path: path), operation: operation)
                    OracledbLogger.debug("res: \(fetchResult)")

                    if setOptions == nil && (fetchResult["ret"] as? [[String: Any]])?.isEmpty != false {
                        throw OracledbErrorUtilities.notFound(message: "Document does not exist")
                    }

                    if let retArr = fetchResult["ret"] as? [[String: Any]], let firstElem = retArr.first {
                        if let osonsData = firstElem["osons"] as? [String: Any] {
                            if entityReference is DualityViewDocReference {
                                // Some DV responses wrap the data inside "DATA"; others provide fields directly.
                                if let dataDict = osonsData["DATA"] as? [String: Any] {
                                    doc = dataDict
                                } else {
                                    doc = osonsData
                                }
                            } else {
                                doc = osonsData["DOCUMENT"] as? [String: Any] ?? osonsData
                            }
                        }
                    }

                    // Remove metadata for duality views
                    if entityReference is DualityViewDocReference {
                        doc.removeValue(forKey: "_metadata")
                        doc.removeValue(forKey: "oid")
                    }
                }

                try updateDoc(servertimestamp: &servertimestamp, doc: &doc, data: data)
                OracledbLogger.debug("doc: \(doc)")
                return UpdatePayloadResult(data: doc, servertimestamp: servertimestamp.isEmpty ? nil : servertimestamp)
            } else {
                // API v2.0
                if isAddDoc {
                    try updateDoc(servertimestamp: &servertimestamp, doc: &doc, data: data)
                    doc = try normalizeV2CreatePayloadData(doc)
                    return UpdatePayloadResult(data: doc, servertimestamp: servertimestamp.isEmpty ? nil : servertimestamp)
                } else {
                    let result = try processUpdateData(docData: data) as! [String: Any]
                    return UpdatePayloadResult(data: result["dataArray"]!, servertimestamp: result["servertimestamp"] as? [String])
                }
            }
        } catch {
            OracledbLogger.error("Error in creating updated payload: \(error.localizedDescription)")
            return UpdatePayloadResult(data: updatedData, servertimestamp: nil)
        }
    }

    /**
     * Updates the document with new data and processes server timestamps.
     * For API v1.0 this function applies updates to the fetched document so the payload
     * contains the fully-updated document data. Supports:
     *  - String and FieldPath keys
     *  - FieldValue operations: delete, increment, arrayUnion, arrayRemove, serverTimestamp
     */
    private func updateDoc(servertimestamp: inout [String], doc: inout [String: Any], data: [AnyHashable: Any]) throws {
        if data.isEmpty {
            return
        }

        // Helpers to navigate and mutate nested dictionaries (value-type safe)
        func getValue(in dict: [String: Any], path: [String]) -> Any? {
            guard !path.isEmpty else { return nil }
            if path.count == 1 { return dict[path[0]] }
            guard let next = dict[path[0]] as? [String: Any] else { return nil }
            return getValue(in: next, path: Array(path.dropFirst()))
        }

        func setValue(in dict: inout [String: Any], path: [String], newValue: Any?) {
            guard !path.isEmpty else { return }
            if path.count == 1 {
                let key = path[0]
                if let v = newValue {
                    dict[key] = v
                } else {
                    dict.removeValue(forKey: key)
                }
                return
            }
            let head = path[0]
            var child = (dict[head] as? [String: Any]) ?? [:]
            setValue(in: &child, path: Array(path.dropFirst()), newValue: newValue)
            dict[head] = child
        }

        func normalizeKeyPath(_ key: AnyHashable) -> [String]? {
            if let fp = key as? FieldPath {
                return fp.fieldNames
            }
            if let s = key as? String, !s.isEmpty {
                return FieldPath(dotPath: s).fieldNames
            }
            return nil
        }

        func areEqual(_ a: Any, _ b: Any) -> Bool {
            // Best-effort equality for common JSON-compatible types
            switch (a, b) {
            case let (x as String, y as String): return x == y
            case let (x as Int, y as Int): return x == y
            case let (x as Int64, y as Int64): return x == y
            case let (x as Double, y as Double): return x == y
            case let (x as Bool, y as Bool): return x == y
            case let (x as NSNumber, y as NSNumber): return x == y
            default:
                return String(describing: a) == String(describing: b)
            }
        }

        func unionArray(existing: [Any], with additions: [Any]) -> [Any] {
            var result = existing
            for elem in additions {
                if !result.contains(where: { areEqual($0, elem) }) {
                    result.append(elem)
                }
            }
            return result
        }

        func removeFromArray(existing: [Any], removals: [Any]) -> [Any] {
            return existing.filter { ex in
                !removals.contains(where: { areEqual($0, ex) })
            }
        }

        for (rawKey, rawValue) in data {
            guard let pathSegments = normalizeKeyPath(rawKey), !pathSegments.isEmpty else {
                OracledbLogger.warning("Skipping update with invalid or empty key: \(rawKey)")
                continue
            }
            let dotPath = pathSegments.joined(separator: ".")

            // Prepare value to write
            if let fv = rawValue as? FieldValue {
                switch fv.getOperation() {
                case .serverTimestamp:
                    // Let backend assign timestamp; record the path and set JSON null
                    servertimestamp.append(dotPath)
                    setValue(in: &doc, path: pathSegments, newValue: NSNull())

                case .delete:
                    setValue(in: &doc, path: pathSegments, newValue: nil)

                case .increment:
                    let delta = fv.getValues().first
                    let current = getValue(in: doc, path: pathSegments)
                    if let d = delta as? Int64 {
                        if let cur = current as? Int64 {
                            setValue(in: &doc, path: pathSegments, newValue: cur &+ d)
                        } else if let cur = current as? Int {
                            setValue(in: &doc, path: pathSegments, newValue: Int64(cur) &+ d)
                        } else if let cur = current as? Double {
                            setValue(in: &doc, path: pathSegments, newValue: cur + Double(d))
                        } else {
                            setValue(in: &doc, path: pathSegments, newValue: d)
                        }
                    } else if let d = delta as? Double {
                        if let cur = current as? Double {
                            setValue(in: &doc, path: pathSegments, newValue: cur + d)
                        } else if let cur = current as? Int64 {
                            setValue(in: &doc, path: pathSegments, newValue: Double(cur) + d)
                        } else if let cur = current as? Int {
                            setValue(in: &doc, path: pathSegments, newValue: Double(cur) + d)
                        } else {
                            setValue(in: &doc, path: pathSegments, newValue: d)
                        }
                    } else {
                        OracledbLogger.warning("increment with non-numeric delta at \(dotPath)")
                    }

                case .arrayUnion:
                    let additions = fv.getValues()
                    let current = getValue(in: doc, path: pathSegments)
                    if let arr = current as? [Any] {
                        setValue(in: &doc, path: pathSegments, newValue: unionArray(existing: arr, with: additions))
                    } else {
                        // No array yet -> start with unique additions
                        setValue(in: &doc, path: pathSegments, newValue: unionArray(existing: [], with: additions))
                    }

                case .arrayRemove:
                    let removals = fv.getValues()
                    let current = getValue(in: doc, path: pathSegments)
                    if let arr = current as? [Any] {
                        setValue(in: &doc, path: pathSegments, newValue: removeFromArray(existing: arr, removals: removals))
                    } else {
                        // Nothing to remove
                    }
                }

            } else {
                setValue(in: &doc, path: pathSegments, newValue: rawValue)
            }
        }
    }

    /**
     * Applies a FieldValue operation to the document.
     */
    private func applyFieldValueOperation(_ fieldMap: inout [String: Any], key: String, value: FieldValue, servertimestamp: inout [String]) {
        if value.getOperation() == .serverTimestamp {
            servertimestamp.append(key)
            fieldMap[key] = value  // Keep FieldValue for now
        } else {
            // Handle other FieldValue operations
            fieldMap[key] = value
        }
    }

    /**
     * Creates a path JSON object for standard paths.
     */
    private func getPathObject(path: [String]) -> [String: Any] {
        return ["path": path]
    }



    
    internal func setHttpRequest(queryHelperFunc: QueryHelperFunc, ref: Any, docData: Any? = nil, merge: Bool? = nil, mergeFields: [String]? = nil, txnOp: TransactionOperation? = nil, snapshot: Bool = false) throws -> URLRequest {
        
        var db: FusabaseOracledb
        var pathArr: [String]
        var reqBody: [String: Any] = [:]
        
        // Decide the variable type for each QueryHelperFunc
        // Validate parameter combinations
        if queryHelperFunc == .delDoc || queryHelperFunc == .qryDoc {
            if docData != nil || merge != nil || mergeFields != nil {
                throw OracledbErrorUtilities.invalidArgumentError(message: "Unexpected parameters for \(queryHelperFunc)")
            }
        } else if queryHelperFunc == .addDoc {
            guard docData is [String: Any] else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "docData must be [String: Any] for addDoc")
            }
            if merge != nil || mergeFields != nil {
                throw OracledbErrorUtilities.invalidArgumentError(message: "merge/mergeFields not allowed for addDoc")
            }
        } else if queryHelperFunc == .updDoc {
            guard docData is [AnyHashable: Any] else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "docData must be [AnyHashable: Any] for updDoc")
            }
            if merge != nil || mergeFields != nil {
                throw OracledbErrorUtilities.invalidArgumentError(message: "merge/mergeFields not allowed for updDoc")
            }
        } else if queryHelperFunc == .setDoc {
            guard docData is [String: Any] else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "docData must be [String: Any] for setDoc")
            }
            guard merge != nil else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "merge must be provided for setDoc")
            }
        }
        
        // Decide the type for ref
        if let colRef = ref as? CollectionReference {
            db = colRef.oracledb
            pathArr = getPathArray(fromPath: colRef.path)

        } else if let query = ref as? Query {
            db = query.oracledb
            pathArr = query._pathSegArr

            // Set reqBody's fields related to query colRef
            if !query.filterArr.isEmpty {
                // Validation: disallow combining array-contains with array-contains-any on the same field
                let acFields = Set(query.filterArr.filter { $0.op == "array-contains" }.map { $0.field })
                let acaFields = Set(query.filterArr.filter { $0.op == "array-contains-any" }.map { $0.field })
                if !acFields.intersection(acaFields).isEmpty {
                    throw OracledbErrorUtilities.invalidArgumentError(message: "Cannot combine array-contains and array-contains-any on the same field")
                }

                var conditions: [[String: Any]] = []
                for elem in query.filterArr {

                    let elem2 = elem.copy()
                    // change op to proper String in reqBody
                    if elem.op == "==" {
                        elem2.op = "="
                    } else if elem.op == "not-in" {
                        // Normalize SDK operator to backend expected form
                        elem2.op = "not in"
                    }

                    conditions.append(elem2.toDictionary())
                }
                reqBody["conditions"] = conditions
            }
            if !query.orderArr.isEmpty {
                var orders: [[String: Any]] = []
                for elem in query.orderArr {
                    orders.append(elem.toDictionary())
                }
                reqBody["explicitOrder"] = orders
            }
            if query.limit > 0 {
                reqBody["limit"] = query.limit
            }

            // aggregate
            if !query._aggFieldArr.isEmpty {
                var aggregates: [[String: Any]] = []
                for elem in query._aggFieldArr {
                    aggregates.append(elem.toDictionary())
                }
                reqBody["aggregate"] = aggregates
            }
            if !query._joins.isEmpty {
                pathArr = []
                reqBody["joins"] = ["view_name": query._joins.last!]
            }
            if !query._columns.isEmpty {
                reqBody["column"] = query._columns
            }

            // Vector similarity search (API v2 only)
            if API_VERSION == "2.0", let vec = query._vectorSearch {
                reqBody["vectorSearch"] = vec
            }

        } else if let docRef = ref as? DocumentReference {
            db = docRef.oracledb
            pathArr = getPathArray(fromPath: docRef.path)
        } else {
            throw OracledbErrorUtilities.invalidRefTypeError(message: "Invalid ref type")
        }

        // Android parity:
        // If this is a DocumentReference whose id has not been generated yet, its last path segment
        // will be a temp id: "BAAS_DOC_TEMP_ID=<uuid>".
        // For the initial set/create call, the temp id MUST NOT be sent in the REST payload.
        // The backend expects only the collection path for add/set when OID isn't generated.
        if queryHelperFunc == .setDoc, let docRef = ref as? DocumentReference {
            if let last = pathArr.last, last.contains("BAAS_DOC_TEMP_ID=") {
                pathArr.removeLast()
            }
        }

        // set reqBody's "path" or "col_group" for collection groups
        if let query = ref as? Query, query._isColGroup {
            reqBody["path"] = []
            reqBody["col_group"] = pathArr.first
        } else {
            reqBody["path"] = pathArr
        }
        if queryHelperFunc == .qryDoc, snapshot {
            reqBody["snapshot"] = 1
        }
        
        // 1. get endpointStr
        let versionSegment = (API_VERSION == "2.0") ? "v2" : "v1"
        let needsVersion: Bool
        var endpointBase = ""
        switch queryHelperFunc {
            case .addDoc:
                endpointBase = "setDocument"
                needsVersion = true
            case .delDoc:
                endpointBase = "deleteDocument"
                needsVersion = false // Unversioned per Android parity
            case .setDoc:
                endpointBase = "setDocument"
                needsVersion = true
            case .updDoc:
                endpointBase = "updateDocument"
                needsVersion = true
            case .qryDoc:
                endpointBase = "runQuery"
                needsVersion = true
        }
        let endpointStr = needsVersion ? "\(versionSegment)/\(endpointBase)" : endpointBase
        
        var urlStr: String = db.app.options.ordsHost + ":" + db.app.options.ordsPort + "/ords/" + db.app.options.schema + "/_/baas-services/database/" + db.app.options.projectId + "/" + endpointStr + "?apiKey=" + db.app.options.appId
        guard let url = URL(string: urlStr)
        else {
            throw OracledbErrorUtilities.invalidURLError(message: "Invalid URL")
        }
        OracledbLogger.debug("Constructed URL: \(url)")
        
        // 3. set reqBody's fields related to docData
        switch queryHelperFunc {
            case .addDoc:
                // Reject deleteVector() in create payloads for parity with web.
                if let data = docData as? [String: Any] {
                    for (_, v) in data {
                        if let vec = v as? VectorSentinel, case .delete = vec {
                            throw OracledbErrorUtilities.invalidArgumentError(message: "deleteVector() is not supported in addDocument/create payload. Use update/set merge contexts.")
                        }
                    }
                }
                let payloadResult = createUpdatePayload(
                    data: docData as! [String: Any],
                    path: pathArr,
                    entityReference: ref,
                    operation: txnOp ?? TransactionOperation(beginTrans: 0, endTrans: 0, transactionName: ""),
                    isAddDoc: true,
                    setOptions: nil
                )
                reqBody["data"] = payloadResult.data
                if let servertimestamps = payloadResult.servertimestamp, !servertimestamps.isEmpty {
                    reqBody["servertimestamp"] = servertimestamps
                }

            case .delDoc:
                break

            case .setDoc:

            // For current ORDS version, there's no mergeFields option to pass.
                reqBody["options"] = ["merge": merge!]

                // Reject deleteVector() in non-merge set contexts.
                if merge == false, let data = docData as? [String: Any] {
                    for (_, v) in data {
                        if let vec = v as? VectorSentinel, case .delete = vec {
                            throw OracledbErrorUtilities.invalidArgumentError(message: "deleteVector() is not supported in set(create) payload. Use update/set merge contexts.")
                        }
                    }
                }

                if API_VERSION == "2.0" {
                    // For API v2 sets, always send operations array and apiversion 2 (regardless of merge flag).
                    let processed = try self.processUpdateData(docData: docData as! [AnyHashable: Any])
                    if let ops = processed["dataArray"] as? [[String: Any]] {
                        reqBody["data"] = ops
                    }
                    if let st = processed["servertimestamp"] as? [String], !st.isEmpty {
                        reqBody["servertimestamp"] = st
                    }
                    reqBody["apiversion"] = 2
                } else {
                    // For API v1, send full document with servertimestamp list if any.
                    let payloadResult = createUpdatePayload(
                        data: docData as! [AnyHashable: Any],
                        path: pathArr,
                        entityReference: ref,
                        operation: txnOp ?? TransactionOperation(beginTrans: 0, endTrans: 0, transactionName: ""),
                        isAddDoc: true,
                        setOptions: SetOptions(merge: merge!, mergeFields: nil)
                    )
                    reqBody["data"] = payloadResult.data
                    if let servertimestamps = payloadResult.servertimestamp, !servertimestamps.isEmpty {
                        reqBody["servertimestamp"] = servertimestamps
                    }
                    // Do not set apiversion for v1-style full document set.
                }

            case .updDoc:

                // Pre-validate update keys to throw client-side invalidArgument for cases like empty field names.
                try self.validateUpdateKeys(docData as! [AnyHashable: Any])

                let payloadResult = createUpdatePayload(data: docData as! [AnyHashable: Any], path: pathArr, entityReference: ref, operation: txnOp ?? TransactionOperation(beginTrans: 0, endTrans: 0, transactionName: ""), isAddDoc: false, setOptions: nil)
                reqBody["data"] = payloadResult.data
                if let servertimestamps = payloadResult.servertimestamp, !servertimestamps.isEmpty {
                    reqBody["servertimestamp"] = servertimestamps
                }
                if API_VERSION == "2.0" {
                    reqBody["apiversion"] = 2
                }

            case .qryDoc:
                break
        }
        // Add version to request body if transaction operation has a valid version
        if let txnOp = txnOp, let version = txnOp.getVersion, version != TransactionOperation.DOES_NOT_EXIST_VERSION {
            reqBody["version"] = version
        }

        guard let jsonReqBody = try? JSONSerialization.data(withJSONObject: reqBody) else {
            throw OracledbErrorUtilities.jsonSerializationFailed(message: "Error serializing JSON")
        }

        // 4. create json trans attribute in req header
        var tranAttr: [String: Any] = [
                                        "begin_trans": 0,
                                        "end_trans": 0,
                                        "trans_name": ""
                                    ]
        if txnOp != nil {
            tranAttr["begin_trans"] = txnOp?.getBeginTrans
            tranAttr["end_trans"] = txnOp?.getEndTrans
            tranAttr["trans_name"] = txnOp?.getTransactionName
        }

        guard let jsonTranAttr = try? JSONSerialization.data(withJSONObject: tranAttr),
              let jsonTranAttrStr = String(data: jsonTranAttr, encoding: .utf8) else {
            throw OracledbErrorUtilities.jsonSerializationFailed(message: "Error serializing x-transaction header")
        }

        // 5. Create the URLRequest
        var req = URLRequest(url: url)
        
        // 6. setup http method
        switch queryHelperFunc {
            case .addDoc:
                req.httpMethod = "POST"
            case .delDoc:
                // Unversioned deleteDocument uses PUT (Android parity)
                req.httpMethod = "PUT"
            case .setDoc:
                req.httpMethod = "POST"
            case .updDoc:
                req.httpMethod = "PUT"
            case .qryDoc:
                req.httpMethod = "POST"
        }
        
        // 7. setup other attributes in http header
        req.httpBody = jsonReqBody
        req.setValue(jsonTranAttrStr, forHTTPHeaderField: "x-transaction")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // OracledbLogger.debug("req header:")
        // print (req.allHTTPHeaderFields!) // todo: log it !
        
        // Securely add authorization header using immediate token clearing
        KeychainTokenStore.shared.withSecureToken(.access) { token in
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        // If no token was available, proceed without Authorization header
        // relying on apiKey query param for unauthenticated flows
         
        
        OracledbLogger.debug("Final URLRequest: \(req)")
        return req;
    }
    
    internal func handleHttpResponse(data: Data, response: URLResponse) throws -> [String: Any] {
        OracledbLogger.debug("Response data length: \(data.count) bytes")
        if let httpResp = response as? HTTPURLResponse {
            OracledbLogger.debug("Response status: \(httpResp.statusCode)")
        }
        
        // Check the response status code
        guard let httpResp = response as? HTTPURLResponse else {
            throw OracledbErrorUtilities.invalidResponse(message: "Non-HTTP response")
        }
        if !(200...299).contains(httpResp.statusCode) {
            let message: String
            if let respBody = String(data: data, encoding: .utf8), !respBody.isEmpty {
                message = respBody
            } else {
                message = HTTPURLResponse.localizedString(forStatusCode: httpResp.statusCode)
            }
            let error: Error
            switch httpResp.statusCode {
            case 400: error = OracledbErrorUtilities.invalidArgumentError(message: message)
            case 401: error = OracledbErrorUtilities.unauthenticatedError(message: message)
            case 403: error = OracledbErrorUtilities.unauthorizedError(message: message)
            case 404: error = OracledbErrorUtilities.notFound(message: message)
            case 412: error = OracledbErrorUtilities.preconditionFailed(message: message)
            case 500...599: error = OracledbErrorUtilities.internalError(message: message)
            default: error = OracledbErrorUtilities.invalidResponse(message: message)
            }
            throw error
        }

        // Parse the JSON response and return it
        guard let jsonResult = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OracledbErrorUtilities.invalidJSON(message: "Invalid JSON format")
        }

        OracledbLogger.debug("Parsed JSON response successfully")
        return jsonResult
    }
}
