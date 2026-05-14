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

/**
 A transaction context for batching atomic read/write operations.

 Transactions allow multiple writes to be applied atomically at commit time,
 with optional optimistic concurrency based on tracked document versions.
 Use setData, updateData, and deleteDocument to enqueue operations, then call apply().
 */
public class Transaction {
    //
    private let oracledb: FusabaseOracledb
    private let options: TransactionOptions
    private let transactionName: String
    private var wOperationArr: [WriteOperation] = []
    private var path2version: [String: String] = [:]

    private static let logger = Logger(subsystem: "com.oracle.database.fusabase.oracledb", category: "Transaction")
    
    /// Generates a unique transaction name.
    private static func generateUniqueTransactionName() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    
    /// Transaction initializer
    /// - Parameters:
    ///   - oracledb: The Oracledb instance.
    ///   - options: Transaction options.
    init(oracledb: FusabaseOracledb, options: TransactionOptions) {
        self.oracledb = oracledb
        self.options = options
        self.transactionName = Transaction.generateUniqueTransactionName()
        OracledbLogger.info("Transaction initialized with name: \(self.transactionName)")
    }

    public func getDocument(_ document: DocumentReference) throws -> DocumentSnapshot {
        
        let queryHelper = document.queryHelper
        let promJson = queryHelper.fetchDocumentsSync(ref: document)
        OracledbLogger.debug("Fetched promJson: \(promJson)")
        let metadata = SnapshotMetadata(fromCache: false, hasPendingWrites: false)
        
        if !promJson.isEmpty {
            if let retArr = promJson["ret"] as? [[String: Any]], let firstElem = retArr.first {
                if !firstElem.isEmpty {
                    if let osonsData = firstElem["osons"] as? [String: Any] {
                        
                        // Record version for optimistic concurrency if available
                        if let verInt = osonsData["VERSION"] as? Int {
                            self.path2version[document.path] = String(verInt)
                        } else if let verStr = osonsData["VERSION"] as? String {
                            self.path2version[document.path] = verStr
                        } else if let meta = osonsData["_metadata"] as? [String: Any],
                                  let etag = meta["etag"] as? String {
                            self.path2version[document.path] = etag
                        }

                        // Unwrap the DOCUMENT key for standard documents
                        var docData = osonsData
                        if let documentDict = osonsData["DOCUMENT"] as? [String: Any] {
                            docData = documentDict
                        }

                        return DocumentSnapshot(data: docData, docRef: document, metadata: metadata)
                        
                    } else {
                        OracledbLogger.error("osons not a key, or not a [String: Any] dict")
                    }
                } else {
                    OracledbLogger.error("firstElem is empty")
                }
            } else {
                OracledbLogger.error("'ret' key is missing, not an array of dictionaries, or empty.")
            }
        }
        // Document doesn't exist, set version to indicate non-existence
        self.path2version[document.path] = TransactionOperation.DOES_NOT_EXIST_VERSION
        return DocumentSnapshot(data: nil, docRef: document, metadata: metadata, exists: false)
    }
    
    
    /// Queues a set operation for a document in this transaction (overwrites by default).
    /// - Parameters:
    ///   - data: Full document data to write.
    ///   - document: Target document reference.
    /// - Returns: Self for chaining.
    public func setData(_ data: [String : Any], forDocument document: DocumentReference) -> Transaction {
        // Use known version or indicate "does not exist" for creation semantics
        let currentVersion = self.path2version[document.path] ?? TransactionOperation.DOES_NOT_EXIST_VERSION
        let wOp = WriteOperation(operation: .set, docRef: document, data: data, version: currentVersion)
        wOperationArr.append(wOp)
        return self
    }
    
    /// Queues a set operation with merge semantics.
    /// - Parameters:
    ///   - data: Document data to write.
    ///   - document: Target document reference.
    ///   - merge: When `true`, merge fields instead of overwrite.
    /// - Returns: Self for chaining.
    public func setData(_ data: [String : Any], forDocument document: DocumentReference, merge: Bool) -> Transaction? {
        // Use known version or indicate "does not exist" for creation semantics
        let currentVersion = self.path2version[document.path] ?? TransactionOperation.DOES_NOT_EXIST_VERSION
        let wOp = WriteOperation(operation: .set, docRef: document, data: data, merge: merge, version: currentVersion)
        wOperationArr.append(wOp)
        return self
    }

    /// Queues a set operation that selectively merges specific fields.
    /// - Parameters:
    ///   - data: Document data to write.
    ///   - document: Target document reference.
    ///   - mergeFields: Array containing field names or FieldPath instances to merge.
    /// - Returns: Self for chaining.
    public func setData(_ data: [String : Any], forDocument document: DocumentReference, mergeFields: [Any]) -> Transaction? {
        // Use known version or indicate "does not exist" for creation semantics
        let currentVersion = self.path2version[document.path] ?? TransactionOperation.DOES_NOT_EXIST_VERSION
        // Passing merge: true since mergeFields imply merge semantics
        let wOp = WriteOperation(operation: .set, docRef: document, data: data, merge: true, mergeFields: mergeFields, version: currentVersion)
        wOperationArr.append(wOp)
        return self
    }
    
    /// Queues a partial update for the given document.
    /// - Parameters:
    ///   - fields: Field/value pairs to update. Keys may be `String` or `FieldPath`.
    ///   - document: Target document reference.
    /// - Returns: Self for chaining.
    public func updateData(_ fields: [AnyHashable : Any], forDocument document: DocumentReference) -> Transaction {
        // Use tracked version if available; otherwise send no version (server decides), while tracking locally
        let currentVersion = self.path2version[document.path]
        let wOp = WriteOperation(operation: .upd, docRef: document, data: fields, version: currentVersion)
        wOperationArr.append(wOp)
        return self
    }

    /// Queues a delete operation for the given document.
    /// - Parameter document: Target document reference.
    /// - Returns: Self for chaining.
    public func deleteDocument(_ document: DocumentReference) -> Transaction {
        // Use tracked version if available; otherwise send no version (server decides), while tracking locally
        let currentVersion = self.path2version[document.path]
        let wOp = WriteOperation(operation: .del, docRef: document, version: currentVersion)
        wOperationArr.append(wOp)
        return self
    }

    /// Commits all enqueued operations atomically.
    /// - Important: This method performs blocking I/O.
    /// - Note: Operations are tagged with begin/end transaction markers and may include a tracked document version.
    func apply() {
        var txnOperation: TransactionOperation

        for (i, wOp) in self.wOperationArr.enumerated() {
            let docRef = wOp.getDocRef
            let wType = wOp.getOperation

            let isFirstOperation = (i == 0) ? 1 : 0
            let isLastOperation = (i == self.wOperationArr.count - 1) ? 1 : 0
            txnOperation = TransactionOperation(beginTrans: isFirstOperation, endTrans: isLastOperation, transactionName: self.transactionName, version: wOp.getVersion)

            var result: [String: Any] = [:]

            switch wType {
                case .set:
                    var docData = wOp.getData as! [String : Any]
                    let merge = wOp.getMerge ?? false

                    // If mergeFields provided, filter the data to those fields only
                    if let mergeFields = wOp.getMergeFields {
                        let stringMergeFields = mergeFields.compactMap { $0 as? String }
                        if !stringMergeFields.isEmpty {
                            var filteredData: [String: Any] = [:]
                            for field in stringMergeFields {
                                if let value = docData[field] {
                                    filteredData[field] = value
                                }
                            }
                            docData = filteredData
                        }
                    }

                    result = docRef.queryHelper.setDocumentSync(docRef: docRef, docData: docData, merge: merge, txnOp: txnOperation)
                case .upd:
                    result = docRef.queryHelper.updateDocumentSync(docRef: docRef, fields: wOp.getData as! [AnyHashable : Any], txnOp: txnOperation)
                case .del:
                    docRef.queryHelper.deleteDocumentSync(docRef: docRef, txnOp: txnOperation)
                    // Delete operations don't update version
                    continue
            }

            // Update version from server response if OID is not null (successful operation)
            if result["OID"] != nil {
                // Apply OID/version/etag back to the reference as well.
                docRef.applyWriteResult(result)

                // Keep transaction-local version tracking updated too.
                if let meta = result["_metadata"] as? [String: Any], let etag = meta["etag"] as? String {
                    self.path2version[docRef.path] = etag
                } else if let version = result["VERSION"] as? String {
                    self.path2version[docRef.path] = version
                } else if let version = result["VERSION"] as? Int {
                    self.path2version[docRef.path] = String(version)
                }
            }
        }
    }

}
