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
/**
    Internal struct needed to hold the attributes of the authentication form
 */
@available(iOS 15, tvOS 13, macOS 10.15, watchOS 7, *)
struct AuthForm {
    var USERNAME_PWD: [String: Any]
    var applicationName: String
    var ecId: String
    var keepMeSignedInEnabled: Int
    var nextAuthFactors: [String]
    var nextOp: [String]
    var requestState: String
    var status: String

    init(USERNAME_PWD: [String : Any], applicationName: String, ecId: String, keepMeSignedInEnabled: Int, nextAuthFactors: [String], nextOp: [String], requestState: String, status: String) {
        self.USERNAME_PWD = USERNAME_PWD
        self.applicationName = applicationName
        self.ecId = ecId
        self.keepMeSignedInEnabled = keepMeSignedInEnabled
        self.nextAuthFactors = nextAuthFactors
        self.nextOp = nextOp
        self.requestState = requestState
        self.status = status
    }
}

