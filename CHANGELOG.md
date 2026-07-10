# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- Legacy ENC1 credential QR, NASPAIR1/NASPAIR2 pairing formats, and build-time `Encryption_key` asset (pairing uses NASPAIR3 + TLS only)

## [1.0.1] - 2026-07-05

### Added

- MIT license and open-source README, SECURITY policy, and `Encryption_key.example` compatibility template
- CONTRIBUTING guide and GitHub CI workflow

### Changed

- Initial public release baseline at version 1.0.1
- Network debug logging enabled only in debug builds
- Sanitized example IPs and removed internal-only documentation from the public tree

### Fixed

- Relay chat: first incoming file now appears without re-entering the conversation
- Relay upload progress no longer jumps backward when merging local and WebSocket updates

## [1.0.0] - (internal)

- Pre-open-source development history on private remotes
