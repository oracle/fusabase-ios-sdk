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

@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
final class IDCSMiddlewareClient {
    let config: FusabaseOptions
    let endpoints: IDCSConfigHelper
    private let client: AuthMiddlewareClient

    var idcsDomainURL: String {
        var value = config.domainURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    init(config: FusabaseOptions) {
        self.config = config
        self.endpoints = IDCSConfigHelper(appID: config.appId)
        self.client = AuthMiddlewareClient(config: config, authPath: "idcs")
    }

    func url(_ endpoint: String, queryItems: [URLQueryItem] = []) throws -> URL {
        try client.url(endpoint, queryItems: queryItems)
    }

    func send(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        methodDescription: String
    ) async throws -> Data {
        try await client.send(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers,
            queryItems: queryItems,
            methodDescription: methodDescription
        )
    }

    func sendJSON(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        methodDescription: String
    ) async throws -> [String: Any] {
        try await client.sendJSON(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers,
            queryItems: queryItems,
            methodDescription: methodDescription
        )
    }

    func sendDecodable<T: Decodable>(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        methodDescription: String,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        try await client.sendDecodable(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers,
            queryItems: queryItems,
            methodDescription: methodDescription,
            decoder: decoder
        )
    }

    static func persistNormalizedTokens(_ tokens: BearerTokenResponse, replacingAuthTokens: Bool = false) {
        AuthMiddlewareClient.persistNormalizedTokens(tokens, replacingAuthTokens: replacingAuthTokens)
    }
}
