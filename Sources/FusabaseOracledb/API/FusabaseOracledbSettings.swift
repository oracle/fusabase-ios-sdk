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

/**
 Configuration settings for Oracle Database operations in the FUSABASE SDK.

 This class encapsulates various settings that control the behavior of database operations,
 including timeouts, retry policies, and connection options. It provides a centralized way
 to configure database behavior for different environments and use cases.

 Settings include long polling timeout configuration, maximum retry attempts for operations,
 and general FUSABASE options that affect connection and authentication behavior.
 */
public final class FusabaseOracledbSettings {

    /// Timeout duration for long polling operations in milliseconds.
    public let longPollingTimeout: Int

    /// Maximum number of retry attempts for failed operations.
    public let maxAttempt: Int

    /// General FUSABASE options affecting connection and authentication behavior.
    public let options: FusabaseOptions

    /**
     Constructs a new `FusabaseOracledbSettings` instance with the specified configuration.

     - Parameters:
       - options: The FUSABASE options containing connection and authentication settings.
       - interval: The timeout interval for long polling operations in milliseconds.
       - maxAttempt: The maximum number of retry attempts for failed operations.
     */
    public init(options: FusabaseOptions, interval: Int, maxAttempt: Int) {
        self.options = options
        self.longPollingTimeout = interval
        self.maxAttempt = maxAttempt
    }
}
