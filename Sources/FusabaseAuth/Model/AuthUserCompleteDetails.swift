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


import FusabaseCore

/**
 Internal struct AuthUserCompleteDetails contains the user's complete information to be later utilized on AuthUser
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
struct AuthUserCompleteDetails {
    var accessToken: AuthTokenResult
    /// Refresh token is not retained in memory; it is persisted to and read from Keychain.
    var refreshToken: String {
        KeychainTokenStore.shared.read(.refresh) ?? ""
    }
    var userInfo: AuthUserInterface?

    init(accessToken: AuthTokenResult, refreshToken: String, userInfo: AuthUserInterface?) {
        self.accessToken = accessToken
        // Persist provided refresh token to Keychain; avoid storing as a field
        KeychainTokenStore.shared.write(refreshToken, for: .refresh)
        self.userInfo = userInfo
    }
}
