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
    let clientID: String?
    let clientSecret: String?
    let domainURL: String?
    let uploadChunkSize: Int
    let longPollingInterval: Int
    let allowsSelfSignedCertificates: Bool
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
                  let host = url.host,
                  let port = url.port,
                  let scheme = url.scheme else {
                Self.logger.error("Invalid URL or missing components in \(inHost)")
                return nil
            }

            // Preserve the original scheme (http/https) from the config
            // Note: ordsHost should be just scheme://host, ordsPort should be the port number
            // Any path in the config URL is ignored since /ords/{schema} is added during URL construction
            let ordsHost = scheme + "://" + host
            let ordsPort = String(port)
            
            
            // placeholder object that contains idcs configuration values
            var idcsConfig = IDCSConfig("", "", "")
            
            // only unwrap idcs values if authType is idcs!
            if authType == "idcs" {
                guard let idcsConfigDecoded = decoded.idcs_config else {
                    throw NSError(
                        domain: "FusabaseOptions.LoadError",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: "idcs_config is missing in the JSON for authType 'idcs'"]
                    )
                }
                // Check for required fields inside idcs_config
                guard !idcsConfigDecoded.clientId.isEmpty,
                      !idcsConfigDecoded.clientSecret.isEmpty,
                      !idcsConfigDecoded.domain_url.isEmpty
                else {
                    throw NSError(
                        domain: "FusabaseOptions.LoadError",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "One or more required properties in idcs_config are missing or empty for authType 'idcs'"]
                    )
                }
                idcsConfig.clientId = idcsConfigDecoded.clientId
                idcsConfig.clientSecret = idcsConfigDecoded.clientSecret
                idcsConfig.domain_url = idcsConfigDecoded.domain_url
            }

            let useOracledbVersion = decoded.version ?? 2
            // Prefer WebSocket-based realtime listeners by default.
            // If `use_socket` is explicitly present in the config, that value wins.
            let useSocket = decoded.use_socket ?? true
            let uploadChunkSize = decoded.upload_chunk_size ?? 1024 * 1024
            let longPollingInterval = decoded.long_polling_interval ?? 29
            let allowsSelfSignedCertificates = decoded.allows_self_signed_certificates ?? false
            let enableLogging = decoded.enable_logging ?? false
            Self.logger.debug("FusabaseOptions: allows_self_signed_certificates from config = \(decoded.allows_self_signed_certificates ?? false)")
            Self.logger.debug("FusabaseOptions: final allowsSelfSignedCertificates = \(allowsSelfSignedCertificates)")
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
                clientID: idcsConfig.clientId,
                clientSecret: idcsConfig.clientSecret,
                domainURL: idcsConfig.domain_url,
                uploadChunkSize: uploadChunkSize,
                longPollingInterval: longPollingInterval,
                allowsSelfSignedCertificates: allowsSelfSignedCertificates,
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
