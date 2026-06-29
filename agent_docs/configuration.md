# Configuration

Use `FusabaseOptions` from `FusabaseCore` to load and hold the app configuration for the Swift SDK.

## Common Initialization Patterns

The SDK supports several configuration-loading patterns:

```swift
import FusabaseCore

let bundled = FusabaseOptions()
let named = FusabaseOptions(jsonName: "fusabase-config")
let fromFile = FusabaseOptions(filePath: "/path/to/fusabase-config.json")
```

After loading options:

```swift
FusabaseApp.configure(options: bundled)
let app = FusabaseApp.app()
```

## High-Level Fields

Important public properties include:

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
- `useOracledbVersion`
- `useSocket`
- `uploadChunkSize`
- `longPollingInterval`
- `enableLogging`

IDCS-related settings are also available through `getIDCSConfig()`, `setIDCSConfig(_:)`, and optional values such as `clientID`, `clientSecret`, and `domainURL`.

## Notes

- `FusabaseOptions()` defaults to loading `fusabase-config.json`.
- `FusabaseApp.configure()` without arguments also uses default options.
- Current Swift property names use Swift-style casing such as `projectId`, `appId`, and `authId`.

## Related Docs

- `agent_docs/core.md`
- `agent_docs/auth.md`
