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

/// A batch of write operations (set, update, delete) that are executed atomically on commit.
/// - Note: Use the async commit() on platforms that support Swift concurrency; the synchronous commit() is retained for compatibility.
public class WriteBatch {
    
    private var transactionName: String
    private var wOperationArr: [WriteOperation]
    
    /// Generates a unique transaction name.
    private static func generateUniqueTransactionName() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    
    /// Creates an empty write batch with a unique transaction identifier.
    init () {
        self.transactionName = WriteBatch.generateUniqueTransactionName()
        self.wOperationArr = []
    }
    
    /// Queues a set operation for the given document.
    /// - Parameters:
    ///   - data: The document fields to set.
    ///   - document: The target document reference.
    /// - Returns: Self to allow method chaining.
    public func setData(_ data: [String : Any], forDocument document: DocumentReference) -> WriteBatch {
        let wOp = WriteOperation(operation: WriteOperationType.set, docRef: document, data: data, version: TransactionOperation.DOES_NOT_EXIST_VERSION)
        self.wOperationArr.append(wOp)
        return self
    }
    
    /// Queues a set operation with merge semantics.
    /// - Note: Merge semantics are not supported yet for WriteBatch; this currently returns `nil`.
    /// - Parameters:
    ///   - data: Document data to write.
    ///   - document: Target document reference.
    ///   - merge: When `true`, would merge fields instead of overwrite (not yet supported).
    /// - Returns: `nil` until merge support is implemented.
    public func setData(_ data: [String : Any], forDocument document: DocumentReference, merge: Bool) -> WriteBatch? {

        let wOp = WriteOperation(operation: WriteOperationType.set, docRef: document, data: data, merge: merge, version: TransactionOperation.DOES_NOT_EXIST_VERSION)
        self.wOperationArr.append(wOp)
        return self
    }
    
    /// Queues a set operation that selectively merges specific fields.
    /// - Note: Selective field merge is not supported yet for WriteBatch; this currently returns `nil`.
    /// - Parameters:
    ///   - data: Document data to write.
    ///   - document: Target document reference.
    ///   - mergeFields: Array containing field names or FieldPath instances to merge (not yet supported).
    /// - Returns: `nil` until selective merge support is implemented.
    public func setData(_ data: [String : Any], forDocument document: DocumentReference, mergeFields: [Any]) -> WriteBatch? {
        let wOp = WriteOperation(operation: WriteOperationType.set, docRef: document, data: data, merge: true, mergeFields: mergeFields, version: TransactionOperation.DOES_NOT_EXIST_VERSION)
        self.wOperationArr.append(wOp)
        return self
    }
    
    /// Queues an update operation for the given document.
    /// - Parameters:
    ///   - fields: Partial fields to update. Keys may be String or FieldPath.
    ///   - document: The target document reference.
    /// - Returns: Self to allow method chaining.
    public func updateData(_ fields: [AnyHashable : Any], forDocument document: DocumentReference) -> WriteBatch {
        let wOp = WriteOperation(operation: WriteOperationType.upd, docRef: document, data: fields, version: TransactionOperation.DOES_NOT_EXIST_VERSION)
        self.wOperationArr.append(wOp)
        return self
    }

    /// Queues a delete operation for the given document.
    /// - Parameter document: The target document reference.
    /// - Returns: Self to allow method chaining.
    public func deleteDocument(_ document: DocumentReference) -> WriteBatch? {
        let wOp = WriteOperation(operation: WriteOperationType.del, docRef: document, version: TransactionOperation.DOES_NOT_EXIST_VERSION)
        self.wOperationArr.append(wOp)
        return self
    }

    /// Commits the queued operations synchronously.
    /// - Important: This method performs blocking I/O. Prefer the async variant when available.
    public func commit() {

        var txnOperation: TransactionOperation
        
        for (i, wOp) in self.wOperationArr.enumerated() {
            let docRef = wOp.getDocRef
            let wType = wOp.getOperation
            
            let isFirstOperation = (i == 0) ? 1 : 0
            let isLastOperation = (i == self.wOperationArr.count - 1) ? 1 : 0
            txnOperation = TransactionOperation(beginTrans: isFirstOperation, endTrans: isLastOperation, transactionName: self.transactionName, version: wOp.getVersion)
            
            switch wType {
                case .set:
                    var docData = wOp.getData as! [String : Any]
                    let merge = wOp.getMerge ?? false

                    // Handle mergeFields by filtering data
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

                    let result = docRef.queryHelper.setDocumentSync(docRef: docRef, docData: docData, merge: merge, txnOp: txnOperation)
                    if !result.isEmpty {
                        docRef.applyWriteResult(result)
                    }
                case .upd:
                    let result = docRef.queryHelper.updateDocumentSync(docRef: docRef, fields: wOp.getData as! [AnyHashable : Any], txnOp: txnOperation)
                    if !result.isEmpty {
                        docRef.applyWriteResult(result)
                    }
                case .del:
                    docRef.queryHelper.deleteDocumentSync(docRef: docRef, txnOp: txnOperation)
            }
        }
    }
}
