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
 A reference to a collection of documents in the database.

 CollectionReference can represent a root collection or a subcollection nested under a parent document.
 From a collection reference you can:
 - Create DocumentReference instances (with or without an explicit document ID).
 - Add new documents with provided data (async or callback-based).
 - Build queries by chaining filters, ordering, and limits inherited from Query.

 Collection paths are slash-separated and always end at a collection segment.
 */
public class CollectionReference: Query {
    
    
    /// Internal storage for the collection's identifier (last segment of the collection path).
    private var _collectionID: String
    /// The parent document when this is a subcollection; nil for root collections.
    private var _parent: DocumentReference?
    /// Absolute slash-separated path to this collection.
    private var _path: String
    
    /// Logger for CollectionReference diagnostics.
    private static let logger = Logger(subsystem: "com.oracle.database.fusabase.oracledb", category: "CollectionReference")

    /// The ID of the collection.
    public var collectionID: String {
        get {
            return _collectionID
        }
    }

    /// The parent document reference of this collection, or nil if this is a root collection.
    public var parent: DocumentReference? {
        get {
            return _parent
        }
    }

    /// The path of this collection relative to the database root.
    public override var path: String {
        get {
            return _path
        }
    }
    
    /**
     Initializes a new CollectionReference.

     The provided path must point to a collection (an odd number of slash-separated segments),
     for example "cities" or "cities/SF/neighborhoods".

     - Parameters:
       - oracledb: The database instance associated with this reference.
       - path: The absolute slash-separated path to the collection.
       - parent: The parent document reference when this is a subcollection; `nil` for root collections.
     */
    init(oracledb: FusabaseOracledb, path: String, parent: DocumentReference? = nil) {
        
        var tokens = path.components(separatedBy: "/")
        OracledbLogger.debug("DocumentReference init with tokens: \(tokens)")
        
        
        self._collectionID = tokens.removeLast()
        
        
        self._parent = parent
        
        self._path = path
        
        // Call superclass initializer
        super.init(oracledb: oracledb)
        self._pathSegArr = path.components(separatedBy: "/")
    }
    
    /**
     Creates a DocumentReference for a new document with an auto-generated ID under this collection.

     - Returns: A DocumentReference pointing to the new document.
     */
    public func document() -> DocumentReference {
        // Android parity: create a DocumentReference with a temporary id segment.
        // This temp id is never sent to the backend; it is stripped from the payload until
        // the server generates the real OID. Keeping a doc-shaped path prevents path/OID
        // rewrite bugs after setData.
        let tempId = "BAAS_DOC_TEMP_ID=\(UUID().uuidString)"
        return DocumentReference(oracledb: super.oracledb, path: _path + "/" + tempId, parent: self)
    }
    
    /**
     Returns a DocumentReference at the given relative path under this collection.

     - Parameter documentPath: The slash-separated relative document path or identifier.
     - Returns: A DocumentReference pointing to the document at the given path.
     */
    public func document(_ documentPath: String) -> DocumentReference {
        return DocumentReference(oracledb: super.oracledb, path: _path + "/" + documentPath, parent: self)
    }
    
    /**
     Sanitizes document data by converting nil values to NSNull.
     */
    private func sanitizeDocumentData(_ data: [String: Any?]) -> [String: Any] {
        return data.mapValues { $0 != nil ? $0! : NSNull() }
    }

    /**
     Adds a new document to this collection with the specified data, assigning a document ID automatically.

     - Parameter data: A dictionary containing the data for the new document. Nil values are converted to NSNull.
     - Returns: A DocumentReference pointing to the newly created document.
     - Throws: An error if the write fails.
     */
    @available(macOS 10.15.0, *)
    public func addDocument(data: [String : Any?]) async throws -> DocumentReference {
        let sanitizedData = sanitizeDocumentData(data)
        let promJson = try await super.queryHelper.createDocument(colRef: self, docData: sanitizedData)

        let docId = promJson["OID"] as! String

        let ref = DocumentReference(oracledb: super.oracledb, path: self.path + "/" + docId, parent: self)
        // Propagate optional VERSION / _metadata.etag if the backend returned it.
        ref.applyWriteResult(promJson)
        return ref

    }

    /**
     Adds a new document to this collection with the specified data, assigning it a document ID automatically.

     - Parameters:
       - data: A Dictionary containing the data for the new document.
       - completion: A block to execute once the document has been successfully written to the server. This block will not be called while the client is offline, though local changes will be visible immediately.
     - Returns: A DocumentReference pointing to the newly created document.
     */
    @available(macOS 10.15.0, *)
    @discardableResult
    public func addDocument(data: [String : Any], completion: (((any Error)?) -> Void)? = nil) -> DocumentReference {
        let documentRef = self.document()

        Task {
            do {
                let createdRef = try await self.addDocument(data: data)
                completion?(nil)
            } catch {
                completion?(error)
            }
        }

        return documentRef
    }



    /**
     Encodes an instance of Encodable and adds a new document to this collection with the encoded data, assigning it a document ID automatically.

     - Parameters:
       - value: An instance of Encodable to be encoded to a document.
       - encoder: An encoder instance to use to run the encoding.
       - completion: A block to execute once the document has been successfully written to the server. This block will not be called while the client is offline, though local changes will be visible immediately.
     - Returns: A DocumentReference pointing to the newly created document.
     */
    @available(macOS 10.15.0, *)
    @discardableResult
    public func addDocument<T: Encodable>(from value: T,
                                         encoder: JSONEncoder = JSONEncoder(),
                                         completion: ((Error?) -> Void)? = nil) -> DocumentReference {
        do {
            let data = try encoder.encode(value)
            let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] ?? [:]
            return self.addDocument(data: dict, completion: completion)
        } catch {
            completion?(error)
            return self.document() // Return a placeholder document reference
        }
    }

        
    /**
     Compares two CollectionReference instances for equality.

     Two references are equal if their parent, path, and collection ID match.
     - Parameters:
       - lhs: The left-hand side reference.
       - rhs: The right-hand side reference.
     - Returns: true if both references are equal; otherwise, false.
     */
    static func == (lhs: CollectionReference, rhs: CollectionReference) -> Bool {
        return lhs._parent == rhs._parent && lhs._path == rhs._path && lhs._collectionID == rhs._collectionID
    }
}
