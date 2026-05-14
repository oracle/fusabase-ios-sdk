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
    
    var AUTHENTICATE_REST_EP = "/sso/v1/sdk/authenticate"
    var OAUTH_TOKEN_REST_EP = "/oauth2/v1/token"
    var SELF_ME_REST_EP = "/admin/v1/Me"
    var LOGOUT_REST_EP = "/oauth2/v1/userlogout"
    var REVOKE_REFRESH_TOKEN_REST_EP = "/oauth2/v1/revoke"
    var SEND_PASSWORD_RESET_EMAIL = "/admin/v1/MePasswordResetRequestor"
    var CONFIRM_PASSWORD_RESET = "/admin/v1/MePasswordResetter"
    var VERIFY_PASSWORD_RESET_CODE = "/admin/v1/UserTokenValidator"
    var UPDATE_PASSWORD_HELPER = "/admin/v1/MePasswordChanger"
    var SEND_EMAIL_VERIFICATION = "/admin/v1/MeEmailVerifier"
    var TOKEN_EXCHANGE_PATH = "tokenExchange"
    var SELF_REGISTER_EP = "useradd"
    
    private var _domainURL: String
    private var _appID: String
    private var _clientID: String
    private var _clientSecret: String

    
    init(_domainURL: String, _appID: String, _clientID: String, _clientSecret: String) {
        self._domainURL = _domainURL
        self._appID = _appID
        self._clientID = _clientID
        self._clientSecret = _clientSecret
        
        // we add the app id to all constants
        AUTHENTICATE_REST_EP += "?apiKey=" + _appID
        OAUTH_TOKEN_REST_EP += "?apiKey=" + _appID
        SELF_ME_REST_EP += "?apiKey=" + _appID
        LOGOUT_REST_EP += "?apiKey=" + _appID
        REVOKE_REFRESH_TOKEN_REST_EP += "?apiKey=" + _appID
        SEND_PASSWORD_RESET_EMAIL += "?apiKey=" + _appID
        CONFIRM_PASSWORD_RESET += "?apiKey=" + _appID
        VERIFY_PASSWORD_RESET_CODE += "?apiKey=" + _appID
        UPDATE_PASSWORD_HELPER += "?apiKey=" + _appID
        SEND_EMAIL_VERIFICATION += "?apiKey=" + _appID
        TOKEN_EXCHANGE_PATH += "?apiKey=" + _appID
        SELF_REGISTER_EP += "?apiKey=" + _appID
    }
}
