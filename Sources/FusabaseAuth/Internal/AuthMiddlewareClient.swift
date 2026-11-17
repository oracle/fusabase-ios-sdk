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
final class AuthMiddlewareClient {
    let config: FusabaseOptions
    private let authPath: String

    private var baseURL: String {
        "\(config.ordsBaseURL)_/baas-services/idm/\(authPath)/\(config.projectId)/"
    }

    init(config: FusabaseOptions, authPath: String) {
        self.config = config
        self.authPath = authPath
    }

    func url(_ endpoint: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw AuthErrorUtilities.internalError(message: "Unable to construct \(authPath) ORDS endpoint.")
        }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else {
            throw AuthErrorUtilities.internalError(message: "Unable to build \(authPath) ORDS URL.")
        }
        return url
    }

    func send(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        methodDescription: String
    ) async throws -> Data {
        var request = URLRequest(url: try url(endpoint, queryItems: queryItems))
        request.httpMethod = method
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if let body {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                throw AuthErrorUtilities.internalError(message: "Couldn't serialize request body for \(methodDescription).")
            }
            request.httpBody = jsonData
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await AuthUtils.fusabaseCall(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthErrorUtilities.networkError(message: "Invalid HTTP response received from server.")
        }
        try AuthUtils.checkResponse(response: httpResponse, data: data, method: methodDescription)
        return data
    }

    func sendJSON(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        methodDescription: String
    ) async throws -> [String: Any] {
        let data = try await send(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers,
            queryItems: queryItems,
            methodDescription: methodDescription
        )
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw AuthErrorUtilities.internalError(message: "Couldn't parse response for \(methodDescription).")
        }
        return jsonObject
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
        let data = try await send(
            endpoint: endpoint,
            method: method,
            body: body,
            headers: headers,
            queryItems: queryItems,
            methodDescription: methodDescription
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AuthErrorUtilities.internalError(message: "Couldn't decode response for \(methodDescription).")
        }
    }

    static func persistNormalizedTokens(_ tokens: BearerTokenResponse, replacingAuthTokens: Bool = false) {
        if replacingAuthTokens {
            KeychainTokenStore.shared.replaceAuthTokens(
                accessToken: tokens.access_token,
                refreshToken: tokens.refresh_token
            )
        } else {
            KeychainTokenStore.shared.write(tokens.access_token, for: .access)
            if let refreshToken = tokens.refresh_token, !refreshToken.isEmpty {
                KeychainTokenStore.shared.write(refreshToken, for: .refresh)
            }
        }
        KeychainTokenStore.shared.delete(.authn)
        KeychainTokenStore.shared.delete(.authnRefresh)
        KeychainTokenStore.shared.delete(.idcsAccess)
        KeychainTokenStore.shared.delete(.idcsRefresh)
    }
}
