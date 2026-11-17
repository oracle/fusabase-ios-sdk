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
 A class for configuring Fusabase options, including ORDS host, port, project ID, and other settings.
 */
public class FusabaseOptions {

    // MARK: - Properties
    public private(set) var ordsHost: String = ""
    public private(set) var ordsPort: String = ""
    public private(set) var projectId: String = ""
    public private(set) var schema: String = ""
    public private(set) var appName: String = ""
    public private(set) var appType: String = ""
    public private(set) var appId: String = ""
    public private(set) var objsType: String = ""
    public private(set) var storageBucket: String = ""
    public private(set) var authType: String = ""
    public private(set) var authId: String = ""
    public private(set) var useOracledbVersion: Int = 2
    // Prefer WebSocket-based realtime listeners by default.
    // If the application config explicitly provides `use_socket`, that value wins.
    public private(set) var useSocket: Bool = true
    public private(set) var uploadChunkSize: Int = 1024 * 1024
    public private(set) var longPollingInterval: Int = 29
    public private(set) var enableLogging: Bool = false

    /// The ORDS base URL supplied in `ords_host`, normalized with one trailing
    /// slash. It includes any path from the config (for example `/ords/SCOTT/`).
    public var ordsBaseURL: String {
        ordsHost.hasSuffix("/") ? ordsHost : ordsHost + "/"
    }

    private var _idcsConfig: IDCSConfig?

    public private(set) var domainURL: String? = nil

    private init(values: FusabaseOptionsValues) {
        assignValues(values)
    }

    public init (filePath: String) {
        // Argument check: filePath must not be empty
        guard !filePath.isEmpty else {
            fatalError("Invalid filePath: cannot be empty")
        }
        let url = URL(fileURLWithPath: filePath)
        
        guard let values = FusabaseOptionsInternal.loadFromUrl(fileUrl: url) else {
            fatalError("Failed to load options from \(filePath)")
        }
        
        assignValues(values)
    }

    public init (fName: String) {
        // Argument check: fName must not be empty
        guard !fName.isEmpty else {
            fatalError("Invalid fName: cannot be empty")
        }
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: fName, withExtension: "json") else {
            fatalError("\(fName).json not found in bundle")
        }
        guard let values = FusabaseOptionsInternal.loadFromUrl(fileUrl: url) else {
            fatalError("Failed to load options from \(fName).json")
        }
        assignValues(values)
    }

    public convenience init() {
        self.init(jsonName: "fusabase-config")
    }

    public init(jsonName: String) {
        guard !jsonName.isEmpty else {
            fatalError("Invalid jsonName: cannot be empty")
        }
        guard let url = Bundle.main.url(forResource: jsonName, withExtension: "json") else {
            fatalError("\(jsonName).json not found in main bundle")
        }
        guard let values = FusabaseOptionsInternal.loadFromUrl(fileUrl: url) else {
            fatalError("Failed to load options from \(jsonName).json")
        }
        assignValues(values)
    }

    private func assignValues(_ values: FusabaseOptionsValues) {
        self.ordsHost = values.ordsHost
        self.ordsPort = values.ordsPort
        self.projectId = values.projectId
        self.schema = values.schema
        self.appName = values.appName
        self.appType = values.appType
        self.appId = values.appId
        self.objsType = values.objsType
        self.storageBucket = values.storageBucket
        self.authType = values.authType
        self.authId = values.authId
        self.useOracledbVersion = values.useOracledbVersion
        self.useSocket = values.useSocket
        self.uploadChunkSize = values.uploadChunkSize
        self.longPollingInterval = values.longPollingInterval
        self.enableLogging = values.enableLogging
        self._idcsConfig = values.idcsConfig
        self.domainURL = values.domainURL
    }

    /// Gets the IDCS configuration.
    /// - Returns: The IDCS configuration, or nil if not set.
    public func getIDCSConfig() -> IDCSConfig? {
        return _idcsConfig
    }

    /// Sets the IDCS configuration.
    /// - Parameter config: The IDCS configuration to set.
    public func setIDCSConfig(_ config: IDCSConfig?) {
        _idcsConfig = config
    }

    /// THIS IS NOT MEANT FOR PRODUCTION
    public class func defaultOptions() -> FusabaseOptions? {
        return FusabaseOptions(jsonName: "fusabase-config")
    }
}
