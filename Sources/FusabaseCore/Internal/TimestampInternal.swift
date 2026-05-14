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

internal struct TimestampComponents {
    let seconds: Int64
    let nanoseconds: Int32
}

internal class TimestampInternal {

    internal static func components(from date: Date) -> TimestampComponents {
        let timeInterval = date.timeIntervalSince1970
        let secs = Int64(timeInterval)
        let nanos = Int32((timeInterval - Double(secs)) * 1_000_000_000)
        return TimestampComponents(seconds: secs, nanoseconds: nanos)
    }

    internal static func compare(lhs: Timestamp, rhs: Timestamp) -> ComparisonResult {
        if lhs.seconds < rhs.seconds {
            return .orderedAscending
        }
        if lhs.seconds > rhs.seconds {
            return .orderedDescending
        }

        // seconds equal → compare nanos
        if lhs.nanoseconds < rhs.nanoseconds {
            return .orderedAscending
        }
        if lhs.nanoseconds > rhs.nanoseconds {
            return .orderedDescending
        }

        return .orderedSame
    }

    /// Creates a Timestamp instance from an RFC3339 formatted string.
    ///
    /// - Parameter rfc3339String: The RFC3339 formatted timestamp string.
    /// - Returns: A Timestamp instance, or nil if the string cannot be parsed.
    internal static func timestamp(fromRFC3339String rfc3339String: String) -> Timestamp? {
        // RFC3339 format: 2023-12-25T10:30:45.123456789Z
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: rfc3339String) {
            return Timestamp(date: date)
        }

        // Fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: rfc3339String) {
            return Timestamp(date: date)
        }

        return nil
    }
}
