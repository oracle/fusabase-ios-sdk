<br />
<p align="center">
  <img src="assets/fusabase-color.svg" alt="Fusabase logo" width="180" />
</p>

<h1 align="center">Oracle Backend with Firebase APIs (Fusabase) iOS SDK</h1>

<p align="center">
  <a href="https://docs.oracle.com/en/database/oracle/backend-for-firebase/26.3/index.html">Guides</a>
  ·
  <a href="https://livelabs.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=4403&amp;clear=180,RR&amp;session=15619800424542">Free Workshop</a>
</p>

A native Swift SDK for Oracle Backend with Firebase APIs (Fusabase). It provides authentication, document database, object storage, and vector search through four public modules:

- `FusabaseCore` — app configuration and shared types
- `FusabaseAuth` — sign-in, user state, provider flows, and token listeners
- `FusabaseOracledb` — collections, documents, queries, transactions, vector search, and duality views
- `FusabaseStorage` — uploads, downloads, metadata, listing, and storage tasks

The SDK can load app settings from a bundled `fusabase-config.json` file or from `FusabaseOptions` you provide. It follows Firebase design patterns, API conventions, and rules-based authorization. Its interfaces mirror Firebase SDK interfaces to help developers move across backends with minimal changes. Fusabase is a distinct Oracle offering.

## Prerequisites

- iOS 15.0+ / macOS 11.0+ / tvOS 13.0+ / watchOS 7.0+
- Swift 5.10+

The SDK has no external third-party runtime dependencies — it builds on Apple frameworks only (`Foundation`, `AuthenticationServices`, `os`, `CryptoKit`, `Security`, `UIKit`, `UniformTypeIdentifiers`).

## Installation

### Xcode

1. In Xcode, choose **File → Add Package Dependencies…**.
2. Enter the GitHub URL: `https://github.com/oracle/fusabase-ios-sdk`.
3. Select the version you want and click **Add Package**.
4. Add the products you need (`FusabaseCore`, `FusabaseAuth`, `FusabaseOracledb`, `FusabaseStorage`) to your target.

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/oracle/fusabase-ios-sdk.git", from: "26.1.0")
]
```

Then add the libraries to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "FusabaseCore", package: "fusabase-ios-sdk"),
        .product(name: "FusabaseAuth", package: "fusabase-ios-sdk"),
        .product(name: "FusabaseOracledb", package: "fusabase-ios-sdk"),
        .product(name: "FusabaseStorage", package: "fusabase-ios-sdk")
    ]
),
```

## Configuration (`fusabase-config.json`)

Place a `fusabase-config.json` file in your project root. The SDK reads it for initialization.

Example `fusabase-config.json`:
```json
{
  "ords_host": "https://your-ords.example.com/ords/",
  "schema": "YOUR_SCHEMA",
  "app_name": "YourApp",
  "app_id": "your-app-id",
  "objs_type": "oci-objects",
  "storage_bucket": "your-bucket",
  "auth_type": "idcs",
  "auth_id": "your-auth-id",
  "project_id": "your-project-id",
  "api_version": 2,
  "use_socket": true,
  "upload_chunk_size": 1048576,
  "long_polling_interval": 3000,
}
```

## Quickstart

Auto-initialization:
- The SDK initializes automatically via `FusabaseApp.configure()` using values from `fusabase-config.json`.
- For most apps, no code is required beyond placing `fusabase-config.json` in the project root.

Manual initialization (if needed):
```swift
import FusabaseCore

let app = FusabaseApp.configure()
```

Initialize with explicit options (advanced):
```swift
import FusabaseCore
import FusabaseOracledb

let options = FusabaseOptions(
    ordsHost: "https://your-ords.example.com/ords/",
    projectId: "your-project-id",
    appId: "your-app-id",
    appName: "YourApp",
    authType: "idcs",
    schema: "YOUR_SCHEMA",
    useSocket: true
)

let app = FusabaseApp.configure(options: options)
```

## Usage

### Authentication

```swift
import FusabaseCore
import FusabaseAuth

let auth = FusabaseAuth.auth(app: FusabaseApp.app()!)

// Sign up
let createResult = try await auth.createUser(withEmail: "user@example.com", password: "password123!")
let newUser = createResult.user

// Sign in
let signInResult = try await auth.signIn(withEmail: "user@example.com", password: "password123!")
let user = signInResult.user

// Observe auth state
let handle = auth.addStateDidChangeListener { authInstance, currentUser in
    if let currentUser {
        print("Signed in as \(currentUser.uid)")
    } else {
        print("Signed out")
    }
}

// Sign out later
try await auth.signOut()
// Remove the listener later:
// auth.removeStateDidChangeListener(handle)
```

### Database (OracleDB)

```swift
import FusabaseCore
import FusabaseOracledb

let app = FusabaseApp.app()!
let db = FusabaseOracledb.oracledb(app: app)

// References
let posts = db.collection("posts")
let postRef = db.document("posts/post-123")

// Query: filter + order + limit
let q = db.collection("posts")
    .whereField("published", isEqualTo: true)
    .order(by: "createdAt", descending: true)
    .limit(to: 10)
```

### Vector Search

The SDK supports similarity search over dense and sparse embeddings via `Query.findNearest(...)`.

```swift
import FusabaseCore
import FusabaseOracledb

// Dense vector similarity search
let denseQuery = try db.collection("documents")
    .findNearest(
        "embedding",
        .dense([0.22, 0.93, -0.10]),
        metric: .cosine,
        topK: 10
    )

// Sparse vector similarity search
let sparse = try SparseVector(
    dimension: 1000,
    indices: [2, 7, 900],
    values: [0.9, 0.3, 0.5]
)
let sparseQuery = try db.collection("documents")
    .findNearest(
        "embedding",
        .sparse(sparse),
        metric: .dot,
        topK: 5
    )
```

Supported metrics: `.cosine`, `.euclidean`, `.dot`.

### Transactions

```swift
let _ = try await db.runTransaction { transaction, errorPointer -> Any? in
    transaction.setData(["count": 1], forDocument: docRef)
    return nil
}
```

### Batch

```swift
let batch = db.batch()
batch.setData(cityData, forDocument: cityRef)
batch.setData(countryData, forDocument: countryRef)
batch.setData(regionData, forDocument: regionRef)
try await batch.commit()
```

### Duality Views

```swift
let dv = db.dualityViewCollection(collectionPath: "department_dv")
let dvDoc = dv.document("10")
```

### Storage

```swift
import FusabaseCore
import FusabaseStorage

let storage = Storage.storage(app: FusabaseApp.app()!)
let root = storage.reference()
let fileRef = root.child("uploads/photo.jpg")

// Upload from URL
fileRef.putFile(from: fileURL, metadata: nil) { metadata, error in
    if let error { print("Upload failed: \(error)"); return }
    print("Upload succeeded")
}

// Upload Data
let task = fileRef.putData(imageData, metadata: nil)

// Download
fileRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
    // Handle data or error
}

// Download to file
_ = fileRef.write(toFile: localURL)

// Get download URL
fileRef.downloadURL { url, error in
    // Use download URL
}

// Metadata
fileRef.getMetadata { metadata, error in /* ... */ }

// List
root.child("uploads/").listAll { result, error in /* ... */ }

// Delete
fileRef.delete { error in /* ... */ }
```

## Info.plist Configuration

> If you're running on **HTTP**, modify Info.plist:
> 1. Add a new row of type `App Transport Security Settings`.
> 2. Expand it and add `Allow Arbitrary Loads` set to **YES**.

For social login via redirect, register a custom URL scheme:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>your-scheme</string>
        </array>
    </dict>
</array>
```

## Documentation

Generate the Swift-DocC API reference:

```bash
make docs
```

Output is written to `./docs`.

Preview locally:

```bash
python3 -m http.server --directory docs
```

Then open `http://localhost:8000/documentation/`.

Notes:
- Docs are generated for `FusabaseCore`, `FusabaseAuth`, `FusabaseOracledb`, and `FusabaseStorage`.
- A custom DocC header/footer is provided in `Sources/FusabaseCore/FusabaseCore.docc/header.html` and `footer.html`.
- Custom templates require DocC's experimental flag: `--experimental-enable-custom-templates`.

## Building the Project

```bash
swift build              # debug build
swift build -c release   # release build
```

The package is distributed via Swift Package Manager — there is no separate tarball or binary artifact step.

## Running Tests

```bash
swift test
swift test --enable-code-coverage
```

## Troubleshooting

- `fusabase-config.json` is not found — place the config file in the project root.
- Cannot read `fusabase-config.json` — validate JSON and ensure the file is readable.
- Social login redirect not working — add `CFBundleURLTypes` to Info.plist and set the scheme.

## Trademarks

Firebase is a trademark of Google LLC. The Firebase name describes the design patterns and SDK interfaces that Oracle Backend with Firebase APIs follows for developer familiarity and ease of migration. It does not imply affiliation with or endorsement by Google.

## Contributing

This project welcomes contributions from the community. Before submitting a pull request, please [review our contribution guide](./CONTRIBUTING.md).

## Security

Please consult the [security guide](./SECURITY.md) for our responsible security vulnerability disclosure process.

## License

Copyright (c) 2015, 2026, Oracle and/or its affiliates.

This software is dual-licensed to you under the Universal Permissive License
(UPL) 1.0 as shown at https://oss.oracle.com/licenses/upl and Apache License
2.0 as shown at http://www.apache.org/licenses/LICENSE-2.0. You may choose
either license.

If you elect to accept the software under the Apache License, Version 2.0,
the following applies:

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
