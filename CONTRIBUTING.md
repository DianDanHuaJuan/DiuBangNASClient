# Contributing

Thank you for your interest in contributing to **DiuBangNASClient**.

## Getting started

1. Fork the repository and clone your fork.
2. Install Flutter (Dart ^3.10.7 per `pubspec.yaml`).
3. Run `flutter pub get`.
4. Run the app: `flutter run`
5. Run tests: `flutter test`
6. Run the analyzer: `flutter analyze`

### Local HTTP proxy (one-line switch)

Java/Gradle does not use the OS system proxy by default. To route Gradle downloads through Clash / V2RayN (or similar) on this machine, flip one flag in `android/gradle.properties`:

```properties
localProxyEnabled=true
localProxyHost=127.0.0.1
localProxyPort=7890
```

Set `localProxyEnabled=false` to turn it off. Set `localProxyPort` to your client's **HTTP or mixed** port (not SOCKS). When enabled, build logs show `[localProxy] enabled …`. A TUN-mode VPN can make this switch unnecessary.

## Pull requests

- Keep changes focused; one logical change per PR when possible.
- Add or update tests for behavior changes.
- Ensure `flutter analyze` and `flutter test` pass locally before opening a PR.
- Do not include secrets, debug log dumps, or personal network identifiers in commits.

## Code style

- Follow existing patterns under `lib/app`, `lib/core`, and `lib/features`.
- Use the established feature layout: `data/`, `domain/`, `application/`, `presentation/` where applicable.
- Prefer meaningful names over comments that restate the code.

## Security

See [SECURITY.md](SECURITY.md) before reporting or fixing security-sensitive areas (pairing TLS, certificate pinning).

## Questions

Open a GitHub issue for bugs or feature discussions. For security issues, follow SECURITY.md instead of filing a public issue with exploit details.
