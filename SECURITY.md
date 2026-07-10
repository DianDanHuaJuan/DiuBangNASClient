# Security Policy

## Reporting a Vulnerability

If you discover a security issue, please **do not** open a public GitHub issue with exploit details.

Report privately via GitHub Security Advisories for this repository, or contact the maintainer through the repository owner's profile.

We will acknowledge reports within a reasonable timeframe and coordinate a fix before public disclosure when appropriate.

## Supported Versions

Security fixes are applied to the default branch. There is no long-term support policy for older releases yet.

## Known Security Considerations

Review these before deploying in production or on untrusted networks.

### TLS certificate pinning window during pairing

During initial server pairing, `pairing_client.dart` temporarily accepts any server certificate while downloading the CA certificate (`badCertificateCallback` returns `true`). This is intentional for bootstrap but means pairing must occur on a trusted network.

Credential-based device enrollment (`POST /api/v1/auth/credential-device-enroll`) uses the same bootstrap certificate download path. Owner credentials are sent only for that request and are **not** persisted on the client.

After pairing, connections use the pinned CA via `TrustedServerHttpClientFactory`.

### Debug logging

Network debug interceptors may log request URLs and response bodies in debug builds. Do not enable verbose logging when handling sensitive data on shared devices.

### Release signing

Release builds use `com.diubang.nasclient`. For local testing, the Gradle config can fall back to the debug keystore when `android/key.properties` is absent. For any distributed release, create your own signing keystore, point `android/key.properties` to it (see `android/key.properties.example`), and never commit keystore files or passwords.
