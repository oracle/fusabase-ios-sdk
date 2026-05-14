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

struct FusabaseOptionsData: Codable {

    let apiVersion: String?
    let app_id: String
    let app_name: String
    let app_type: String
    let auth_id: String
    let auth_type: String
    let objs_type: String
    let ords_host: String
    let project_id: String
    let schema: String
    let storage_bucket: String
    let idcs_config: IDCSConfig?
    let use_socket: Bool?
    let long_polling_interval: Int?
    let version: Int?
    let upload_chunk_size: Int?
    let allows_self_signed_certificates: Bool?
    let enable_logging: Bool?
    
}
