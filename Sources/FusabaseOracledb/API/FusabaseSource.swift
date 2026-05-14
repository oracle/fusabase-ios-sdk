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

/// An enumeration of the different sources supported by Oracle Database read operations.
@available(iOS 15.0, macOS 10.15, tvOS 13.0, watchOS 7.0, *)
public enum FusabaseSource: String {
    /// Causes Oracle Database to try to retrieve an up-to-date (server-retrieved) snapshot,
    /// but may return cached data if the server can't be reached.
    case `default`

    /// Causes Oracle Database to avoid the cache, ignoring any previously cached data and
    /// retrieving data directly from the server.
    case server

    /// Causes Oracle Database to get the data from the cache. Returns an error if the data
    /// has not been cached.
    case cache
}
