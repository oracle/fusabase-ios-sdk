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
// Licensed under the Apache License, Version 2.0 (the \"License\");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an \"AS IS\" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
//-----------------------------------------------------------------------------

import Foundation
import os
import FusabaseCore

/// Entry point for the Oracledb module.
///
/// This class provides access to collections, documents, queries, transactions,
/// write batches, and module-level configuration such as logging.
/// It is designed as a shared singleton with convenience constructors.
///
/// Typical usage:
/// ```swift
/// let oradb = FusabaseOracledb.oracledb()
/// let users = oradb.collection(\"users\")
/// let doc = oradb.document(\"users/123\")
/// ```
///
/// Logging: SDK logs are intended for internal/testing visibility only. In test targets,
/// set `FusabaseLogger.testingEnabled = true` to emit verbose logs.
public class FusabaseOracledb {

    // MARK: - Stored Properties

    /// Backing `FusabaseApp` instance used to acquire options and shared state.
    private var _app: FusabaseApp

    /// Per-instance settings used by controllers and helpers.
    private var _settings: FusabaseOracledbSettings

    /// Maximum number of attempts for network requests (subject to change).
    private static let REQUEST_MAX_ATTEMPT: Int = 1

    // MARK: - Public Getters

    /// The backing `FusabaseApp` for this Oracledb instance.
    public var app: FusabaseApp {
        get { return _app }
    }

    /// The current Oracledb settings for this instance.
    public var settings: FusabaseOracledbSettings {
        get { return _settings }
    }

    // MARK: - Initialization

    /// Private initializer to prevent direct instantiation. Use `oracledb()` constructors.
    private init() {
        OracledbLogger.info("oracledb instance initialized")
        self._app = FusabaseApp.app()!
        self._settings = FusabaseOracledbSettings(
            options: self._app.options,
            interval: self._app.options.longPollingInterval * 1000,
            maxAttempt: 1
        )
    }

    /// Creates an instance bound to the given `FusabaseApp`.
    /// - Parameter app: The app to bind this Oracledb instance to.
    private init(app: FusabaseApp) {
        OracledbLogger.info("Oracledb instance initialized with given FusabaseApp.")
        self._app = app
        self._settings = FusabaseOracledbSettings(
            options: self._app.options,
            interval: self._app.options.longPollingInterval * 1000,
            maxAttempt: FusabaseOracledb.REQUEST_MAX_ATTEMPT
        )
    }

    // MARK: - Singleton

    /// Singleton storage.
    private static var sharedInstance: FusabaseOracledb?

    /// Retrieves the shared Oracledb instance using the default `FusabaseApp`.
    /// - Returns: The shared `FusabaseOracledb` instance.
    public class func oracledb() -> Self {
        if sharedInstance == nil {
            sharedInstance = FusabaseOracledb() as? Self
        }
        return sharedInstance as! Self
    }

    /// Replaces the shared instance with one bound to the provided `FusabaseApp`.
    /// - Parameter app: The app that the shared instance should be bound to.
    /// - Returns: The shared `FusabaseOracledb` instance bound to `app`.
    public class func oracledb(app: FusabaseApp) -> Self {
        sharedInstance = FusabaseOracledb(app: app)
        return sharedInstance as! Self
    }

    // MARK: - References

    /// Creates a reference to a collection at the specified absolute path.
    /// - Parameter collectionPath: Absolute collection path (e.g., \"users\").
    /// - Returns: A `CollectionReference` pointing at `collectionPath`.
    public func collection(_ collectionPath: String) -> CollectionReference {
        return CollectionReference(oracledb: self, path: collectionPath)
    }

    /// Creates a reference to a document at the specified absolute path.
    /// - Parameter documentPath: Absolute document path (e.g., \"users/123\").
    /// - Returns: A `DocumentReference` pointing at `documentPath`.
    public func document(_ documentPath: String) -> DocumentReference {
        return DocumentReference(oracledb: self, path: documentPath)
    }

    /// Creates a query operating over all collections with the specified ID.
    /// - Parameter collectionID: The collection ID group to query (e.g., \"users\").
    /// - Returns: A `Query` configured for the collection group.
    public func collectionGroup(_ collectionID: String ) -> Query {
        return Query(oracledb: self, path: collectionID, isColGroup: true)
    }

    /// Creates and returns a reference to a duality view collection in the database.
    ///
    /// Duality views provide a relational interface to document collections.
    /// - Parameter collectionPath: The path of the duality view collection.
    /// - Returns: A `DualityViewColReference` pointing to the specified duality view collection.
    public func dualityViewCollection(collectionPath: String) -> DualityViewColReference {
        return DualityViewColReference(oracledb: self, path: collectionPath)
    }

    /// Creates a join query for the specified view name.
    /// - Parameter viewName: The name of the view to join with.
    /// - Returns: A `Query` instance configured for the join operation.
    public func join(viewName: String) -> Query {
        return Query(oracledb: self).join(viewName: viewName)
    }
    
    
    // MARK: - Transactions and Write Batches

    /// Runs a transaction using default options.
    ///
    /// Executes the provided `updateBlock` inside a transaction context. If the block
    /// sets an error through the provided `NSErrorPointer`, the transaction will not be
    /// applied and the `completion` will receive the error. Otherwise, this method will
    /// attempt to apply the transaction and call `completion` with the result or error.
    ///
    /// - Parameters:
    ///   - updateBlock: The transaction body receiving a `Transaction` and an `NSErrorPointer`.
    ///   - completion: Completion handler invoked with the block's return value or an error.
    public func runTransaction(_ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?, completion: @escaping (Any?, (any Error)?) -> Void) {

        let tmpTxnOptions = TransactionOptions.Builder().setMaxAttempts(_settings.maxAttempt).build()

        runTransaction(tmpTxnOptions, updateBlock, completion: completion)
    }

    /// Internal runTransaction helper
    func runTransaction(_ options: TransactionOptions, _ updateBlock: @escaping (Transaction, NSErrorPointer) -> Any?, completion: @escaping (Any?, (any Error)?) -> Void) {

        var retries = options.maxAttempts
        var result: Any?
        var lastError: Error?

        while retries > 0 {
            do {
                // Step 1: Create the transaction context
                let transaction = Transaction(oracledb: FusabaseOracledb.sharedInstance!, options: options)

                // Step 2: Allocate space for error reporting
                var error: NSError?

                // Step 3: Execute the update block
                result = updateBlock(transaction, &error)

                // Step 4: Check for errors in update block
                if let error = error {
                    // Update block failed, do not commit
                    completion(nil, error)
                    return
                }

                // Step 5: Try to commit transaction operations
                try transaction.apply()
                // Success
                completion(result, nil)
                return

            } catch let error as NSError {
                // Check if this is a retryable error (similar to Android's "OID is null")
                if error.domain == OracledbErrors.OracledbErrorDomain &&
                   error.code == OracledbErrorCode.internalError.rawValue &&
                   error.localizedDescription.contains("OID is null") {
                    retries -= 1
                    if retries > 0 {
                        // Add random delay between 0-3 seconds to avoid collision
                        let delay = Double.random(in: 0...3)
                        Thread.sleep(forTimeInterval: delay)
                        OracledbLogger.debug("Retrying transaction with delay \(delay) seconds, attempts remaining: \(retries)")
                        continue
                    } else {
                        lastError = error
                        break
                    }
                } else {
                    // Non-retryable error
                    completion(nil, error)
                    return
                }
            } catch {
                // Other errors
                completion(nil, error)
                return
            }
        }

        // If we get here, all retries failed
        completion(nil, lastError ?? OracledbErrorUtilities.internalError(message: "Transaction failed after \(options.maxAttempts) attempts"))
    }



    public func batch() -> WriteBatch {
        return WriteBatch()
    }

    /// Creates and returns a BulkUpdate instance for performing bulk update operations on a collection.
    ///
    /// - Parameter collectionPath: The path to the collection on which the bulk update will be applied.
    /// - Returns: A `BulkUpdate` instance configured for the specified collection.
    public func bulkUpdate(_ collectionPath: String) -> BulkUpdate {
        return BulkUpdate(db: self, path: collectionPath)
    }
}
