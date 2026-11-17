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

internal struct FusabaseOptionsValues {
    let ordsHost: String
    let ordsPort: String
    let projectId: String
    let schema: String
    let appName: String
    let appType: String
    let appId: String
    let objsType: String
    let storageBucket: String
    let authType: String
    let authId: String
    let useOracledbVersion: Int
    let useSocket: Bool
    let idcsConfig: IDCSConfig
    let domainURL: String?
    let uploadChunkSize: Int
    let longPollingInterval: Int
    let enableLogging: Bool
}

internal class FusabaseOptionsInternal {

    private static let logger = FusabaseLogger(category: "options")
    
    /// Internal method that loads data from a user provided file.
    /// - Parameter fileUrl: URL object containing the path to the object
    /// - Returns : FusabaseOptionsValues? object containing the received values or nil
    internal static func loadFromUrl(fileUrl: URL) -> FusabaseOptionsValues? {
        do {
            let data = try Data(contentsOf: fileUrl)
            let decoded = try JSONDecoder().decode(FusabaseOptionsData.self, from: data)

            // Assign values
            let schema = decoded.schema
            let appName = decoded.app_name
            let appType = decoded.app_type
            let appId = decoded.app_id
            let objsType = decoded.objs_type
            let projectId = decoded.project_id
            let storageBucket = decoded.storage_bucket
            let authType = decoded.auth_type
            let authId = decoded.auth_id
            
            let inHost = decoded.ords_host
            guard let url = URL(string: inHost),
                  url.host != nil,
                  url.scheme != nil else {
                Self.logger.error("Invalid URL or missing components in \(inHost)")
                return nil
            }

            // Preserve the configured ORDS base URL, including its ORDS/schema
            // path. Endpoint builders append their service path directly to it.
            let ordsHost = inHost.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let ordsPort = url.port.map(String.init) ?? ""
            
            
            let idcsConfig = IDCSConfig("")

            let useOracledbVersion = decoded.version ?? 2
            // Prefer WebSocket-based realtime listeners by default.
            // If `use_socket` is explicitly present in the config, that value wins.
            let useSocket = decoded.use_socket ?? true
            let uploadChunkSize = decoded.upload_chunk_size ?? 1024 * 1024
            let longPollingInterval = decoded.long_polling_interval ?? 29
            let enableLogging = decoded.enable_logging ?? false
            Self.logger.debug("FusabaseOptions: enable_logging from config = \(decoded.enable_logging ?? false)")
            Self.logger.debug("FusabaseOptions: final enableLogging = \(enableLogging)")

            // If enable_logging is true, set logger level to info (avoid verbose wire logging in production)
            if enableLogging {
                FusabaseConfiguration.shared.setLoggerLevel(.info)
                Self.logger.debug("FusabaseOptions: Logger level set to info due to enable_logging=true")
            }

            Self.logger.info("FusabaseOptions loaded from \(fileUrl)")
            
            return FusabaseOptionsValues(
                ordsHost: ordsHost,
                ordsPort: ordsPort,
                projectId: projectId,
                schema: schema,
                appName: appName,
                appType: appType,
                appId: appId,
                objsType: objsType,
                storageBucket: storageBucket,
                authType: authType,
                authId: authId,
                useOracledbVersion: useOracledbVersion,
                useSocket: useSocket,
                idcsConfig: idcsConfig,
                domainURL: nil,
                uploadChunkSize: uploadChunkSize,
                longPollingInterval: longPollingInterval,
                enableLogging: enableLogging
            )
        }
        catch let error as DecodingError {
            Self.logger.error("JSON decoding error: \(error)")
        } catch {
            Self.logger.error("Failed to load or decode \(fileUrl): \(error.localizedDescription)")
        }
        
        return nil
    }

}
