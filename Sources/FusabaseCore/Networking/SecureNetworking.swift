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

import Foundation

/**
 Provides secure networking utilities with enforced TLS 1.2 minimum version.
 */
@_documentation(visibility: internal)
public class SecureNetworking {

    private static let logger = FusabaseLogger(category: "networking")

    private static var _secureSession: URLSession?

    /// A shared URLSession configured with TLS 1.2 minimum supported protocol version.
    public static var secureSession: URLSession {
        if let session = _secureSession {
            return session
        }
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = tls_protocol_version_t.TLSv12

        let session: URLSession
        // Check if the current app allows self-signed certificates
        let allowsSelfSigned = FusabaseApp.app()?.options.allowsSelfSignedCertificates == true
        Self.logger.debug("SecureNetworking: allowsSelfSignedCertificates = \(allowsSelfSigned)")
        if allowsSelfSigned {
            let delegate = SelfSignedDelegate()
            session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            Self.logger.debug("SecureNetworking: Using SelfSignedDelegate for self-signed certificates")
        } else {
            session = URLSession(configuration: config)
            Self.logger.debug("SecureNetworking: Using standard URLSession (no self-signed certificates)")
        }
        _secureSession = session
        return session
    }

    /// Reset the session when app configuration changes
    internal static func resetSession() {
        _secureSession = nil
    }

}

/**
    This should NOT be used in prod. this is just to test https with self-signed certificates
 */
class SelfSignedDelegate: NSObject, URLSessionDelegate {

    private let logger = FusabaseLogger(category: "networking")
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

        logger.debug("SelfSignedDelegate: Received challenge for \(challenge.protectionSpace.host) with method \(challenge.protectionSpace.authenticationMethod)")

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {

            logger.debug("SelfSignedDelegate: Accepting self-signed certificate for \(challenge.protectionSpace.host)")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            logger.debug("SelfSignedDelegate: Not a server trust challenge, cancelling")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
