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


// TransactionOptions.swift
//
// Configuration options for transactions, controlling retry behavior and other
// transaction-specific settings.
//
// This is the Swift counterpart of the Java TransactionOptions class. It follows
// the same intent and defaults, exposing a value-oriented API (copy-with helpers)
// while omitting the builder in this translation per module guidance.
//
//-----------------------------------------------------------------------------

import Foundation

/**
 Configuration options for transactions, controlling retry behavior
 and other transaction-specific settings.
 */
public class TransactionOptions {

    /** Maximum number of attempts to retry a failed transaction. */
    public let maxAttempts: Int

    /**
     Private constructor for creating TransactionOptions instances.

     - Parameter maxAttempts maximum number of retry attempts
     */
    private init(maxAttempts: Int) {
        self.maxAttempts = maxAttempts
    }

    /**
     Builder class for creating TransactionOptions instances.
     Provides a fluent API for configuring transaction options.
     */
    public class Builder {

        /** Default value used by fusabase is 5. */
        private var maxAttempts: Int = 5

        /**
         Sets the maximum number of attempts to retry a failed transaction.

         - Parameter maxAttempts maximum number of retry attempts
         - Returns this Builder instance for chaining
         */
        public func setMaxAttempts(_ maxAttempts: Int) -> Builder {
            self.maxAttempts = maxAttempts
            return self
        }

        /**
         Builds and returns a TransactionOptions instance with the configured options.

         - Returns a new TransactionOptions instance
         */
        public func build() -> TransactionOptions {
            return TransactionOptions(maxAttempts: self.maxAttempts)
        }
    }
}
