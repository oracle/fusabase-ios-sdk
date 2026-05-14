# Auth Module

Use `FusabaseAuth` for sign-in, sign-out, current-user access, auth-state listeners, token listeners, password flows, and provider-based authentication.

## Primary Types

- `FusabaseAuth`
- `FusabaseUser`
- `AuthDataResult`
- `AuthCredential`
- `UserCredential`
- `UserProfileChangeRequest`
- Provider types such as `GoogleAuthProvider`, `FacebookAuthProvider`, `GithubAuthProvider`, `EmailAuthProvider`, `IDCSAuthProvider`, `OAuthProvider`, and `SAMLAuthProvider`

## Common Patterns

### Get the auth instance

```swift
import FusabaseAuth

let auth = FusabaseAuth.auth()
```

Or bind auth to a specific app:

```swift
let auth = FusabaseAuth.auth(app: app)
```

### Observe auth state

```swift
let handle = auth.addStateDidChangeListener { _, user in
    print(user?.email ?? "signed out")
}
```

### Observe token changes

```swift
let tokenHandle = auth.addIDTokenDidChangeListener { _, user in
    print(user?.uid ?? "no user")
}
```

### Email and password

```swift
let created = try await auth.createUser(withEmail: email, password: password)
let signedIn = try await auth.signIn(withEmail: email, password: password)
print(created.user.email)
print(signedIn.user.email)
```

### Sign out

```swift
try await auth.signOut()
```

### Provider sign-in

```swift
let provider = GoogleAuthProvider(auth: auth)
let result = try await auth.signIn(with: provider)
print(result.user.email)
```

### Profile and account management

```swift
// Update display name and phone number.
let change = auth.currentUser?.createProfileChangeRequest()
change?.displayName = "Killian"
change?.phoneNumber = "+1-555-0100"
try await change?.commitChanges()

// Send verification / reset emails.
try await auth.currentUser?.sendEmailVerification()
try await auth.sendPasswordReset()

// Link and unlink providers.
let linked = try await auth.currentUser?.link(with: GoogleAuthProvider(auth: auth))
let unlinked = try await auth.currentUser?.unlink(fromProvider: "google.com")
```

The async `sendPasswordReset()` on `FusabaseAuth` uses the email saved at last sign-in. Use the completion variant `sendPasswordReset(withEmail:completion:)` to pass a different address.

## Notes

- The module exposes both `async` APIs and completion-handler variants.
- `currentUser` is available on the auth instance.
- The current implementation persists tokens locally and attempts an initial sign-in when auth initializes.

## Related Docs

- `agent_docs/core.md`
