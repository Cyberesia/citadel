# Attributions

Citadel includes or interoperates with third-party open-source software. This file
records attribution for bundled or referenced components.

## CoworkCore (upstream: AionCore)

Citadel's **Cowork** feature communicates with a local agent backend referred to in
code as **CoworkCore**. The upstream project is [AionCore](https://github.com/iOfficeAI/AionCore)
by iOfficeAI / AionUi contributors.

- **License:** Apache License 2.0
- **Repository:** https://github.com/iOfficeAI/AionCore
- **Related UI reference:** [AionUi](https://github.com/iOfficeAI/AionUi) (Apache-2.0)

Citadel's Swift UI, client bridge (`CoworkCoreClient`), and process lifecycle are
Cyberesia-specific implementations. The CoworkCore binary (when bundled) is built
from the AionCore source tree and may be distributed under Apache-2.0 terms.

## Cleanshot / Prism

Design system adapted from Cyberesia's Cleanshot Prism UI patterns in `Sources/CitadelDesign/Prism/`.
