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
 The entry point of the Fusabase SDK, providing access to configured apps and their options.
 */
public class FusabaseApp {
        
    public private(set) var options: FusabaseOptions
    public private(set) var name: String
    
    @MainActor private static var allApps: [String: FusabaseApp] = [:]
    @MainActor private static let instances : [FusabaseApp] = []
    private static let defaultAppName: String = "__FUSABASEAPP_DEFAULT"
    
    internal init(name: String, options: FusabaseOptions) {
        self.options = options
        self.name = name
    }
    
    public class func configure() {
        configure(options: FusabaseOptions.defaultOptions()!)
    }
    
    public class func configure(options: FusabaseOptions) {
        configure(name: defaultAppName, options: options);
    }
    
    public class func configure(name: String, options: FusabaseOptions) {
        if name != defaultAppName {
            fatalError("Multiple FusabaseApp instances are not supported. Initialize only the default instance (__FUSABASEAPP_DEFAULT).")
        }
        FusabaseAppInternal.configure(name: name, options: options)
    }
    
    public class func app() -> FusabaseApp? {
        return FusabaseAppInternal.app()
    }
    
    @MainActor public class func app(name: String) -> FusabaseApp? {
        if name != defaultAppName {
            fatalError("Named FusabaseApp instances are not supported. Use FusabaseApp.app() for the default instance.")
        }
        return FusabaseAppInternal.app()
    }
    
}
