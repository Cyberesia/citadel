# Third-party notices

## License

Citadel is licensed under **Apache License 2.0 with additional obligations**
([LICENSE](./LICENSE)). You may modify and redistribute the software, but you must:

- comply with Apache-2.0 notice requirements;
- **preserve Citadel, Fortress, and Keep** wherever they appear in this repository;
- **preserve the Citadel logo and official branding assets**, and **keep upstream
  updates** to names, logos, and branding from this project;
- keep `NOTICES.md`, `ATTRIBUTIONS.md`, and `CHANGELOG.md` (or their substance).

## Swift Package Manager dependencies

Citadel links the following open-source packages (see `project.yml` and
`Citadel.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`):

| Package | Repository | License |
| :-- | :-- | :-- |
| mlx-swift | https://github.com/ml-explore/mlx-swift | MIT |
| mlx-swift-lm | https://github.com/ml-explore/mlx-swift-lm | MIT |
| swift-huggingface | https://github.com/huggingface/swift-huggingface | Apache-2.0 |
| swift-transformers | https://github.com/huggingface/swift-transformers | Apache-2.0 |

Transitive dependencies (for example swift-collections, Jinja, yyjson) are resolved
by SwiftPM and carry their own licenses in the package checkouts.

## Vendored tooling

| Component | Location | License |
| :-- | :-- | :-- |
| create-dmg | `Scripts/vendor/create-dmg/` | MIT — see `Scripts/vendor/create-dmg/LICENSE.create-dmg` |

## Cleanshot Prism UI

The Prism design system (glass surfaces, theme tokens, motion, living canvas)
is adapted from the Cleanshot project by the Citadel authors.

## CoworkCore / AionCore

See `ATTRIBUTIONS.md` for Apache-2.0 notice covering the bundled CoworkCore backend
derived from [AionCore](https://github.com/iOfficeAI/AionCore).

## PureSnitch

See `ATTRIBUTIONS.md` for inspiration credit. Citadel's firewall stack is a
Cyberesia rewrite; PureSnitch is not bundled or included as source.
