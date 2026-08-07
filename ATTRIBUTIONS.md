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

## PureSnitch (inspiration)

Early Citadel firewall ideas (local DNS proxy, privileged helper, `pfctl` anchor,
network system extension) were informed by [PureSnitch](https://github.com/momenbasel/puresnitch)
by Moamen Basel (MIT License).

Citadel's helper, DNS resolver, packet filter, persistence, and network-extension
code in `Sources/Helper/`, `Sources/Shared/Firewall/`, and `Sources/NetExt/` were
rewritten as Cyberesia-specific implementations. Remaining overlap is limited to
small frozen wire contracts (XPC selectors, app-group JSON snapshots) and is not
a derivative of PureSnitch source code.
