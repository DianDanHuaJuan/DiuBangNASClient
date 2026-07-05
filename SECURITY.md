# Security Policy

## Reporting a Vulnerability

If you discover a security issue, please **do not** open a public GitHub issue with exploit details.

Report privately via GitHub Security Advisories for this repository, or contact the maintainer through the repository owner's profile.

We will acknowledge reports within a reasonable timeframe and coordinate a fix before public disclosure when appropriate.

## Supported Versions

Security fixes are applied to the default branch. There is no long-term support policy for older releases yet.

## Known Security Considerations

Review these before deploying in production or on untrusted networks.

### Static `Encryption_key`

The client loads a symmetric key from the root-level `Encryption_key` file (bundled as a Flutter asset at build time). The repository does not commit a real `Encryption_key`; it ships `Encryption_key.example` as a public compatibility example for the upstream release build. See `lib/core/crypto/encryption_key_loader.dart`.

- Treat the example key, and any release built from it, as public compatibility data rather than a secret boundary.
- Self-hosted deployments should generate their own independent random `Encryption_key` before building, avoid deriving it from `Encryption_key.example`, and keep client/server values in sync.
- Anyone operating a deployment with a custom key is responsible for distributing and rotating that key safely.

### TLS certificate pinning window during pairing

During initial server pairing, `pairing_client.dart` temporarily accepts any server certificate while downloading the CA certificate (`badCertificateCallback` returns `true`). This is intentional for bootstrap but means pairing must occur on a trusted network.

After pairing, connections use the pinned CA via `TrustedServerHttpClientFactory`.

### Debug logging

Network debug interceptors may log request URLs and response bodies in debug builds. Do not enable verbose logging when handling sensitive data on shared devices.

### Release signing

Release builds use `com.diubang.nasclient`. For local testing, the Gradle config can fall back to the debug keystore when `android/key.properties` is absent. For any distributed release, create your own signing keystore, point `android/key.properties` to it (see `android/key.properties.example`), and never commit keystore files or passwords.
