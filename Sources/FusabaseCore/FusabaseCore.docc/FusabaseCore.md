# ``FusabaseCore``

Oracle&reg; Backend for Firebase iOS SDK — Core module.

## Overview

`FusabaseCore` contains shared functionality used by other modules in this package:

- SDK configuration and app initialization (`FusabaseApp`, `FusabaseOptions`)
- Shared models and utilities
- Secure persistence utilities

## Modules

This Swift package also includes:

- `FusabaseAuth`
- `FusabaseOracledb`
- `FusabaseStorage`

## Getting Started

```swift
import FusabaseCore

let app = FusabaseApp.configure()
```
