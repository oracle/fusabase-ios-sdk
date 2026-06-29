# Oracle Backend for Firebase Swift SDK Guide for Coding Agents

This repository contains the Oracle Backend for Firebase Swift SDK. The product name is **Oracle Backend for Firebase**. The developer-facing Swift module names use the **`Fusabase...`** prefix.

Use this file as background context when you are scanning the SDK or generating application code that consumes it.

## Canonical Imports

Use only the public Swift modules exposed by the package:

```swift
import FusabaseCore
import FusabaseAuth
import FusabaseOracledb
import FusabaseStorage
```

Do not generate application code that imports internal repository paths under `Sources/...`.

## Package Surface

The Swift package publishes four libraries:

- `FusabaseCore`: app configuration, app lookup, timestamps, and shared core types.
- `FusabaseAuth`: authentication, current user state, provider flows, password flows, and token listeners.
- `FusabaseOracledb`: collections, documents, queries, listeners, transactions, write batches, aggregates, vector search, and duality-view helpers.
- `FusabaseStorage`: storage clients, storage references, uploads, downloads, metadata, listing, and task management.

## Configuration

Applications typically configure the SDK with a `FusabaseOptions` instance sourced from the Oracle Backend for Firebase console configuration.

High-level configuration fields include:

- `ordsHost`
- `ordsPort`
- `projectId`
- `schema`
- `appName`
- `appType`
- `appId`
- `objsType`
- `storageBucket`
- `authType`
- `authId`
- `useSocket`
- `uploadChunkSize`
- `longPollingInterval`

Typical setup:

```swift
import FusabaseCore

let options = FusabaseOptions()
FusabaseApp.configure(options: options)
let app = FusabaseApp.app()
```

## Swift Usage Shape

- The SDK is module-based, not subpath-based.
- The SDK exposes both `async` APIs and completion-handler APIs in several modules.
- Core entrypoints are class-based and often use shared-instance accessors such as `FusabaseApp.app()`, `FusabaseAuth.auth()`, `FusabaseOracledb.oracledb()`, and `Storage.storage()`.

## Short Examples

### Core

```swift
import FusabaseCore

let options = FusabaseOptions(jsonName: "fusabase-config")
FusabaseApp.configure(options: options)
let app = FusabaseApp.app()
```

### Auth

```swift
import FusabaseAuth

let auth = FusabaseAuth.auth()
let handle = auth.addStateDidChangeListener { _, user in
    print(user?.email ?? "signed out")
}

let result = try await auth.signIn(withEmail: email, password: password)
print(result.user.email)
```

### OracleDB

```swift
import FusabaseOracledb

let db = FusabaseOracledb.oracledb()
let recipes = db.collection("recipes")
let created = try await recipes.addDocument(data: ["title": "Tea", "category": "Drinks"])
let snapshot = try await created.getDocument()
```

### Storage

```swift
import FusabaseStorage

let storage = Storage.storage()
let imageRef = storage.reference(withPath: "recipes/tea.png")
let uploadTask = imageRef.putData(fileData)
let url = try await imageRef.downloadURL()
```

## More Detail

Use these docs when you need deeper module-specific context:

- `agent_docs/configuration.md`: console config, `FusabaseOptions`, and app setup patterns.
- `agent_docs/core.md`: `FusabaseApp`, app lookup, and shared core types.
- `agent_docs/auth.md`: auth entrypoints, listeners, sign-in flows, and user/token operations.
- `agent_docs/oracledb.md`: references, queries, writes, listeners, transactions, aggregates, vector search, and duality views.
- `agent_docs/storage.md`: storage clients, references, uploads, downloads, metadata, listing, and task APIs.
- `agent_docs/api-reference.md`: how to generate the local DocC site and where the output lives.

## API Reference

Generate local documentation with:

```bash
./Scripts/generate-docs.sh
```

That script writes a static DocC site under `docs/`. See `agent_docs/api-reference.md` for details.
