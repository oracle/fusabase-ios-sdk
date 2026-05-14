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
 * Represents a bulk update operation on documents in the Oracledb database.
 * Provides methods to filter documents and perform bulk updates.
 */
public class BulkUpdate {

    // Logging tag for this class.
    private static let TAG = "FusabaseOradb"

    // The Oracledb database instance.
    private let oradb: FusabaseOracledb

    // Query helper for performing operations.
    private let queryHelper: QueryHelper

    // The path segments representing the collection's location.
    private let path: [String]

    // Filter conditions for the bulk update.
    private var conditions: [Filter] = []

    // List of operators used to track conflicts (e.g., array-contains vs array-contains-any).
    private var ops: [String] = []

    /**
     * Creates a new BulkUpdate instance for the specified collection path.
     *
     * - Parameter db: the Oracledb database instance
     * - Parameter path: the path to the collection
     */
    internal init(db: FusabaseOracledb, path: String) {
        self.oradb = db
        self.queryHelper = QueryHelper(options: db.settings.options, oradb: db)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPath.isEmpty else {
            fatalError("Path cannot be empty!")
        }

        self.path = trimmedPath.components(separatedBy: "/")

        guard self.path.count % 2 == 1 else {
            fatalError("Invalid path for bulk update. Path should point to a collection.")
        }
    }

    /**
     * Creates a deep copy of this BulkUpdate instance.
     *
     * - Returns: a new BulkUpdate instance with copied properties
     */
    private func deepCopy() -> BulkUpdate {
        let newUpdate = BulkUpdate(db: self.oradb, path: self.path.joined(separator: "/"))
        newUpdate.conditions = self.conditions
        newUpdate.ops = self.ops
        return newUpdate
    }

    /**
     * Adds a where clause to filter documents for the bulk update.
     *
     * - Parameter filter: the filter to apply
     * - Returns: a new BulkUpdate instance with the filter applied
     */
    @discardableResult
    public func `where`(_ filter: Filter) -> BulkUpdate {
        let opStr = filter.op

        if opStr == "array-contains-any" {
            for existingOp in self.ops {
                if existingOp == "array-contains" {
                    fatalError("array-contains-any can't be used with array-contains.")
                }
            }
        }
        if opStr == "array-contains" {
            for existingOp in self.ops {
                if existingOp == "array-contains-any" {
                    fatalError("array-contains can't be used with array-contains-any.")
                }
            }
        }

        let newUpdate = self.deepCopy()
        newUpdate.conditions.append(filter)
        newUpdate.ops.append(opStr)

        return newUpdate
    }

    /**
     * Performs the bulk update operation.
     *
     * - Parameter data: the data to update
     * - Returns: a Task representing the asynchronous operation
     */
    @available(macOS 10.15.0, *)
    public func update(_ data: [String: Any]) async throws {
        guard !data.isEmpty else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Invalid data provided")
        }

        let operation = TransactionOperation(beginTrans: 0, endTrans: 0, transactionName: "")
        let conditionsDicts = self.conditions.map { $0.toDictionary() }

        do {
            try self.queryHelper.updateDocs(path: self.path, data: data, entityReference: NSNull(), operation: operation, conditions: conditionsDicts)
        } catch {
            throw error
        }
    }

    /**
     * Performs the bulk update operation with field-value pairs.
     *
     * - Parameter field: First field to update with its name
     * - Parameter value: First value of the field
     * - Parameter moreFieldsAndValues: More field value pairs
     */
    @available(macOS 10.15.0, *)
    public func update(_ field: String, _ value: Any?, _ moreFieldsAndValues: Any...) async throws {
        guard !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Invalid field provided to update()")
        }

        var data: [String: Any] = [:]
        data[field] = value

        guard moreFieldsAndValues.count % 2 == 0 else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Uneven number of field-value pairs.")
        }

        guard isValidUpdateField(field) else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Invalid field name provided.")
        }

        for i in stride(from: 0, to: moreFieldsAndValues.count, by: 2) {
            guard let key = moreFieldsAndValues[i] as? String else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "Field names must be strings.")
            }
            let val = moreFieldsAndValues[i + 1]
            data[key] = val
        }

        try await self.update(data)
    }

    /**
     * Performs the bulk update operation with FieldPath and field-value pairs.
     *
     * - Parameter fieldPath: First field to update with its FieldPath
     * - Parameter value: First value of the field
     * - Parameter moreFieldsAndValues: More field value pairs
     */
    @available(macOS 10.15.0, *)
    public func update(_ fieldPath: FieldPath, _ value: Any?, _ moreFieldsAndValues: Any...) async throws {
        guard isValidUpdateField(fieldPath.path) else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Invalid field name provided.")
        }

        var data: [String: Any] = [:]
        data[fieldPath.path] = value

        guard moreFieldsAndValues.count % 2 == 0 else {
            throw OracledbErrorUtilities.invalidArgumentError(message: "Uneven number of field-value pairs.")
        }

        for i in stride(from: 0, to: moreFieldsAndValues.count, by: 2) {
            guard let fieldPathKey = moreFieldsAndValues[i] as? FieldPath else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "Field must be of type FieldPath.")
            }
            guard isValidUpdateField(fieldPathKey.path) else {
                throw OracledbErrorUtilities.invalidArgumentError(message: "Invalid field name provided.")
            }
            let val = moreFieldsAndValues[i + 1]
            data[fieldPathKey.path] = val
        }

        try await self.update(data)
    }

    private func isValidUpdateField(_ field: String) -> Bool {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix(".") || trimmed.hasSuffix(".") || trimmed.contains("..") {
            return false
        }

        let segments = trimmed.components(separatedBy: ".")
        for segment in segments {
            if segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }
        return true
    }
}