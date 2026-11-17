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


/**
    Simple struct that holds accesstoken and refreshtoken
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
struct AuthenticationDetails {
    var access_token: AuthTokenResult
    /// Response value; constructing details must not change the current session.
    var refresh_token: String

    init(access_token: AuthTokenResult, refresh_token: String) {
        self.access_token = access_token
        self.refresh_token = refresh_token
    }
}
