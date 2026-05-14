// Copyright (c) 2015, 2025, Oracle and/or its affiliates.
//
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
//
// Centralized logger facade for the FusabaseAuth module.
// Backed by FusabaseCore.FusabaseLogger with category "auth".
// Emission of logs is controlled by the configured logger level.
//
//-----------------------------------------------------------------------------

import Foundation
import FusabaseCore

internal enum AuthLogger {
    private static let logger = FusabaseLogger(category: "auth")

    /// Logs a debug-level message for the Auth module.
    static func debug(_ message: String) {
        logger.debug(message)
    }

    /// Logs an informational message for the Auth module.
    static func info(_ message: String) {
        logger.info(message)
    }

    /// Logs a warning message for the Auth module.
    static func warning(_ message: String) {
        logger.warning(message)
    }

    /// Logs an error message for the Auth module.
    static func error(_ message: String) {
        logger.error(message)
    }
}
