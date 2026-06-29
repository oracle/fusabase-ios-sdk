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


class IDCSConfigHelper {
    
    var AUTHENTICATE_PATH = "authenticate"
    var REVOKE_REFRESH_TOKEN_PATH = "rf/revoke"
    var SEND_EMAIL_PATH = "sendemail"
    var VERIFY_CODE_PATH = "verifycode"
    var RESET_PASSWORD_PATH = "resetpwd"
    var REDIRECT_RESULT_PATH = "redirectResult"
    var PROFILE_PATH = "profile"
    var CHANGE_PASSWORD_PATH = "changePassword"
    var SELF_REGISTER_EP = "useradd"

    
    init(appID: String) {
        let _appID = appID
        
        // we add the app id to all constants
        AUTHENTICATE_PATH += "?apiKey=" + _appID
        REVOKE_REFRESH_TOKEN_PATH += "?apiKey=" + _appID
        SEND_EMAIL_PATH += "?apiKey=" + _appID
        VERIFY_CODE_PATH += "?apiKey=" + _appID
        RESET_PASSWORD_PATH += "?apiKey=" + _appID
        REDIRECT_RESULT_PATH += "?apiKey=" + _appID
        PROFILE_PATH += "?apiKey=" + _appID
        CHANGE_PASSWORD_PATH += "?apiKey=" + _appID
        SELF_REGISTER_EP += "?apiKey=" + _appID
    }
}
