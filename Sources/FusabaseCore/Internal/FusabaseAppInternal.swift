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

internal class FusabaseAppInternal {
    
    private static var _app: FusabaseApp?
    private static let defaultAppName: String = "__FUSABASEAPP_DEFAULT"
    
    internal static func configure() {
        _app = FusabaseApp(name: defaultAppName, options: FusabaseOptions.defaultOptions()!)
    }
    
    internal static func configure(options: FusabaseOptions) {
        // Argument check: ensure options are valid (basic check)
        guard !options.projectId.isEmpty else {
            fatalError("Invalid options: projectId cannot be empty")
        }
        self._app = FusabaseApp(name: defaultAppName, options: options)
    }
    
    internal static func configure(name: String, options: FusabaseOptions) {
        // Argument check: ensure options are valid (basic check)
        guard !options.projectId.isEmpty else {
            fatalError("Invalid options: projectId cannot be empty")
        }
        self._app = FusabaseApp(name: name, options: options)
    }
    
    internal static func app() -> FusabaseApp? {
        if _app == nil {
            self.configure()
            return self._app
        } else {
            return self._app
        }
    }
    
}
