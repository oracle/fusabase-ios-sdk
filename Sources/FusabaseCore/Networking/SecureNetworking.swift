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
 Provides secure networking utilities with enforced TLS 1.2 minimum version.
 */
@_documentation(visibility: internal)
public class SecureNetworking {

    private static let logger = FusabaseLogger(category: "networking")

    private static let sessionLock = NSLock()
    private static var _secureSession: URLSession?

    /// A shared URLSession configured with TLS 1.2 minimum supported protocol version.
    public static var secureSession: URLSession {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        if let session = _secureSession {
            return session
        }
        let config = secureDefaultConfiguration()

        let session = URLSession(configuration: config)
        Self.logger.debug("SecureNetworking: Using standard URLSession")
        _secureSession = session
        return session
    }

    /// Installs an app-configured session before the first SDK network request.
    /// Apps can use this to provide narrowly scoped server-trust handling.
    public static func configureSecureSession(_ session: URLSession) {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        _secureSession = session
    }

    /// Creates a default URLSessionConfiguration with TLS 1.2 as the minimum supported protocol version.
    public static func secureDefaultConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = tls_protocol_version_t.TLSv12
        return config
    }

    /// Reset the session when app configuration changes
    internal static func resetSession() {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        _secureSession = nil
    }

}
