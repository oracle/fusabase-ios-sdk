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

public class FusabaseLogger {

    // Internal testing flag. When true, all logs from SDK modules are emitted regardless of configured level.
    // Intended to be toggled by tests via `@testable import FusabaseCore`.
    public static var testingEnabled: Bool = false

    private let subsystem = "com.oracle.database.fusabase"
    private let category: String

    public init(category: String = "default") {
        self.category = category
    }

    private var logger: os.Logger {
        return os.Logger(subsystem: subsystem, category: category)
    }

    private var currentLevel: FusabaseLoggerLevel {
        return FusabaseConfiguration.shared.loggerLevel()
    }

    private func shouldLog(level: FusabaseLoggerLevel) -> Bool {
        // If testing flag is enabled, always log.
        if FusabaseLogger.testingEnabled { return true }
        return level.rawValue >= currentLevel.rawValue
    }

    public func debug(_ message: String) {
        if shouldLog(level: .debug) {
            logger.debug("\(message)")
        }
    }

    public func info(_ message: String) {
        if shouldLog(level: .info) {
            logger.info("\(message)")
        }
    }

    public func warning(_ message: String) {
        if shouldLog(level: .warning) {
            logger.warning("\(message)")
        }
    }

    public func error(_ message: String) {
        if shouldLog(level: .error) {
            logger.error("\(message)")
        }
    }
}
