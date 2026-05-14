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
//
// SnapshotListenOptions.swift
//
// Swift port of SnapshotListenOptions configuration found in the Java SDK.
// Provides a builder-based API to configure snapshot listeners (metadata
// changes policy, listen source).
//
// Note: The executor attribute has been removed per module guidance.
//
//-----------------------------------------------------------------------------

import Foundation

/// The source from which to listen for changes.
public enum ListenSource: Equatable {
    /// Default listen source (module-defined behavior).
    case `default`
    /// Listen from server.
    case server
}

/// Configuration options for snapshot listeners. This class allows configuring
/// how snapshot events are delivered, including the metadata changes and listen source.
///
/// Construct using the nested Builder:
/// ```swift
/// let options = SnapshotListenOptions.Builder()
///     .setMetadataChanges(.exclude)
///     .setSource(.default)
///     .build()
/// ```
public final class SnapshotListenOptions: Equatable {

    /// Configuration for which metadata changes to include in events.
    public let metadataChanges: MetadataChanges

    /// The source from which to listen for changes.
    public let source: ListenSource

    var includeMetadataChanges: Bool

    /// Private initializer used by the Builder.
    private init(metadataChanges: MetadataChanges,
                 source: ListenSource) {
        self.metadataChanges = metadataChanges
        self.source = source
        self.includeMetadataChanges = (metadataChanges == .include)
    }

    /// Creates SnapshotListenOptions with default values.
    ///
    /// Defaults:
    /// - metadataChanges: .exclude (metadata-only changes will not trigger callbacks)
    /// - source: .default
    /// - includeMetadataChanges: false (derived from metadataChanges)
    ///
    /// Use this initializer when you want the standard behavior and then refine
    /// options using the withIncludeMetadataChanges(_:) and withSource(_:) helpers,
    /// or prefer the Builder() for a fluent construction API.
    init() {
        self.metadataChanges = .exclude
        self.source = .default
        self.includeMetadataChanges = false
    }

    /// Returns a copy of these options toggling whether metadata-only changes
    /// should trigger snapshot callbacks.
    ///
    /// - Parameter includeMetadataChanges: When true, maps to `MetadataChanges.include`;
    ///   when false, maps to `MetadataChanges.exclude`.
    /// - Returns: A new SnapshotListenOptions instance leaving other fields unchanged.
    /// - Note: This API is value-oriented. It does not mutate the receiver.
    func withIncludeMetadataChanges(_ includeMetadataChanges: Bool ) -> SnapshotListenOptions {
        let metadata: MetadataChanges = includeMetadataChanges ? .include : .exclude
        return SnapshotListenOptions(metadataChanges: metadata,
                                     source: self.source)
    }

    /// Returns a copy of these options using the provided listen source.
    ///
    /// - Parameter source: The desired source for listening (e.g. `.default`, `.server`, `.cache`).
    /// - Returns: A new SnapshotListenOptions instance leaving other fields unchanged.
    /// - Note: This API is value-oriented. It does not mutate the receiver.
    func withSource(_ source: ListenSource ) -> SnapshotListenOptions {
        return SnapshotListenOptions(metadataChanges: self.metadataChanges,
                                     source: source)
    }

    /// Equatable conformance.
    public static func == (lhs: SnapshotListenOptions, rhs: SnapshotListenOptions) -> Bool {
        return lhs.metadataChanges == rhs.metadataChanges
            && lhs.source == rhs.source
    }

    /// Builder class for creating SnapshotListenOptions instances.
    /// Provides a fluent API for configuring listener options.
    public final class Builder {

        private var _metadataChanges: MetadataChanges?
        private var _source: ListenSource?

        /// Sets the metadata changes configuration.
        ///
        /// - Parameter metadataChanges: The metadata changes setting.
        /// - Returns: This Builder instance for chaining.
        @discardableResult
        public func setMetadataChanges(_ metadataChanges: MetadataChanges) -> Builder {
            self._metadataChanges = metadataChanges
            return self
        }

        /// Sets the listen source configuration.
        ///
        /// - Parameter source: The listen source to use.
        /// - Returns: This Builder instance for chaining.
        @discardableResult
        public func setSource(_ source: ListenSource) -> Builder {
            self._source = source
            return self
        }

        /// Builds and returns a SnapshotListenOptions instance with the configured options.
        ///
        /// Defaults:
        /// - metadataChanges: .exclude
        /// - source: .default
        ///
        /// - Returns: A new SnapshotListenOptions instance.
        public func build() -> SnapshotListenOptions {
            let metadata = _metadataChanges ?? .exclude
            let source = _source ?? .default
            return SnapshotListenOptions(metadataChanges: metadata,
                                         source: source)
        }
    }
}
