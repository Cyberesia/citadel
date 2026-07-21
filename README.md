# Citadel

A macOS application firewall with Sentinel activity monitoring and Prism UI.

**Citadel** ships a Citadel-native firewall engine (rules, helper, DNS/pf, network extension) plus Sentinel Activity and Keep (local AI agents), with Prism UI.

## Features

- **Sentinel Activity** — process families, Sites breakdown, 2D/3D map, firewall actions
- **Connection alerts** — allow/deny prompts with remember / temporary rules
- **Rules** — domains, IPs, process rules, blocklists, temporary expiry
- **DNS over HTTPS** — local DNS proxy with blocklist integration
- **Packet filtering** — `pfctl` anchor for IP/CIDR/port rules
- **Menubar status** — live traffic, mode picker, quick access
- **Keep** — local AI agents for files, code, and chores (the inner stronghold; formerly labeled Cowork)
- **Prism UI** — dark glass shell, animated ambient canvas

## Requirements

- macOS 13.0+ (map view requires macOS 14+)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
./Scripts/build-debug.sh
```

Manual:

```bash
./Scripts/prepare-coworkcore.sh
xcodegen generate
xcodebuild -scheme Citadel -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Citadel.app
```

Demo UI:

```bash
CITADEL_SENTINEL_DEMO=1 open build/Build/Products/Debug/Citadel.app
```

## Architecture

```
Citadel.app (Sentinel + Keep + Settings)
    ↕ XPC
CitadelHelper (DNS proxy, pfctl, privileged NetMonitor)
    ↕ app group JSON
CitadelNetExt (optional per-process filter)
```

## Project layout

```
Sources/
├── CitadelDesign/   # Prism UI + map
├── Sentinel/        # Activity telemetry + UI
├── GUI/             # Shell, menubar, alerts, settings
├── Shared/          # Models + Firewall/ evaluator + RuleStore
├── Helper/          # Privileged daemon
└── NetExt/          # Network system extension
```

## Attribution

See `ATTRIBUTIONS.md` and `NOTICES.md`.

## License

Third-party notices are in `NOTICES.md` and `ATTRIBUTIONS.md`.
