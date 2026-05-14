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

/**
 A class representing a timestamp with seconds and nanoseconds since the Unix epoch.
 */
public class Timestamp: NSCopying, @unchecked Sendable {

    public let seconds: Int64
    public let nanoseconds: Int32

    public init(seconds: Int64, nanoseconds: Int32) {
        precondition(nanoseconds >= 0 && nanoseconds < 1_000_000_000,
                     "Nanoseconds must be in range 0...999,999,999")
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }

    public convenience init(date: Date) {
        let components = TimestampInternal.components(from: date)
        self.init(seconds: components.seconds, nanoseconds: components.nanoseconds)
    }

    public convenience init() {
        self.init(date: Date())
    }

    public func dateValue() -> Date {
        Date(timeIntervalSince1970: Double(seconds) + Double(nanoseconds) / 1_000_000_000)
    }

    public func compare(_ other: Timestamp) -> ComparisonResult {
        return TimestampInternal.compare(lhs: self, rhs: other)
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        // Immutable → copy just returns a new instance with same values
        Timestamp(seconds: seconds, nanoseconds: nanoseconds)
    }
}
