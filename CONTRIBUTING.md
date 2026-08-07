# Contributing to Citadel

Thank you for your interest in Citadel. This project is maintained by [Cyberesia](https://github.com/Cyberesia).

## Before you start

- Read [README.md](./README.md) for architecture overview and build instructions.
- Check [open issues](https://github.com/Cyberesia/citadel/issues) before starting large work.
- For security issues, see [SECURITY.md](./SECURITY.md) — do not open public issues for vulnerabilities.

## Development setup

Requirements: macOS 14+, Apple Silicon, Xcode 15+.

```bash
git clone https://github.com/Cyberesia/citadel.git
cd citadel
brew install xcodegen
./Scripts/build-debug.sh
```

Set `SKIP_COWORKCORE=1` to build without downloading CoworkCore. Set `NO_RUN=1` to skip launching the app after build.

### Signed builds and DMG packaging

Team-specific signing files are gitignored. One-time setup:

```bash
cp Scripts/signing.local.env.example Scripts/signing.local.env
# Edit TEAM_ID, then:
./Scripts/prepare-signing.sh
```

See [RELEASE.md](./RELEASE.md) for notarization and distribution.

Run tests:

```bash
xcodegen generate
xcodebuild -scheme Citadel -configuration Debug -derivedDataPath build -skipMacroValidation test
```

## Pull requests

1. Fork the repo and create a feature branch from `main`.
2. Keep changes focused — one concern per PR when possible.
3. Match existing Swift style and naming in the surrounding code.
4. Update [CHANGELOG.md](./CHANGELOG.md) under `[Unreleased]` for user-visible changes.
5. Preserve **Citadel**, **Fortress**, and **Keep** naming per [LICENSE](./LICENSE).

## License

By contributing, you agree that your contributions will be licensed under the same terms as the project ([Apache License 2.0 with additional obligations](./LICENSE)).
