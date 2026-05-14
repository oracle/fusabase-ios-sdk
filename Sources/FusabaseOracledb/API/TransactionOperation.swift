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

/**
 Describes transaction attributes attached to each write request.

 TransactionOperation carries begin/end transaction flags, a transaction name,
 optional TransactionOptions, and an optional optimistic-concurrency version.
 It is used to construct the x-transaction header and query parameters for
 database requests issued within Transactions and WriteBatch.
 */
class TransactionOperation {

    /// Default starting version used when the server does not provide one.
    static let defaultVersion = "1"
    /// Sentinel indicating that the document is expected not to exist (create semantics).
    static let DOES_NOT_EXIST_VERSION = "0"

    /// 1 if this operation begins a transaction; 0 otherwise.
    private let beginTrans: Int
    /// 1 if this operation ends a transaction; 0 otherwise.
    private let endTrans: Int
    /// Unique transaction identifier used to correlate grouped operations.
    private let transactionName: String
    /// Optional transaction configuration (e.g., retry attempts).
    private let options: TransactionOptions?
    /// Optional document version for optimistic concurrency control.
    private var version: String?

    /// Full initializer
    init(beginTrans: Int,
         endTrans: Int,
         transactionName: String,
         options: TransactionOptions? = nil,
         version: String? = nil) {
        self.beginTrans = beginTrans
        self.endTrans = endTrans
        self.transactionName = transactionName
        self.options = options
        self.version = version
    }

    /// Default initializer
//    init() {
//        self.beginTrans = 0
//        self.endTrans = 0
//        self.transactionName = ""
//        self.options = TransactionOptions.Builder().build()
//        self.version = TransactionOperation.defaultVersion
//    }

    /// Returns the optimistic concurrency version, if any.
    var getVersion: String? {
        return version
    }

    /// Returns 1 if this operation begins a transaction; otherwise 0.
    var getBeginTrans: Int {
        return beginTrans
    }

    /// Returns 1 if this operation ends a transaction; otherwise 0.
    var getEndTrans: Int {
        return endTrans
    }

    /// Returns the transaction identifier string.
    var getTransactionName: String {
        return transactionName
    }

    /// Returns the transaction options associated with this operation.
    var getOptions: TransactionOptions? {
        return options
    }

    /// Sets the optimistic concurrency version to use for this operation.
    func setVersion(_ version: String) {
        self.version = version
    }
}
