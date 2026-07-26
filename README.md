# Citadel

A macOS application firewall (**Fortress**) with Keep agents and Prism UI.

**Citadel** ships a Citadel-native firewall engine (rules, helper, DNS/pf, network extension) plus Fortress Activity / Suspects / History and Keep (local + cloud AI agents), with Prism UI.

## Features

### Fortress
- **Activity** — process families, Sites breakdown, 2D/3D map, firewall actions
- **Suspects** — hard, explainable signals (unsigned apps, first-seen destinations, sensitive ports…)
- **History** — persisted connections with filters and CSV export
- **Connection alerts** — allow/deny with real scope + duration (app / host / IP+port; forever / session / 1h / 24h)
- **Rules** — domains, IPs, process + Team ID identity, blocklists, temporary expiry
- **DNS over HTTPS** — local DNS proxy with blocklist integration
- **Packet filtering** — `pfctl` anchor for IP/CIDR/port rules
- **Per-app filter** — embedded Network System Extension (approve in System Settings)
- **Menubar** — live traffic, mode picker, protection status
- **Guide** — in-app Fortress help (English / French), same pattern as Keep

### Keep
- Local AI agents for files, code, and chores (Ollama / LM Studio / MLX)
- Cloud models via BYOK (your API keys)
- Guarded by Fortress network policy

### Prism UI
- Dark glass shell, animated ambient canvas, desk companion

## Requirements

- macOS 13.0+ (map view requires macOS 14+)
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- For full per-app filtering: Apple Developer signing + `xcodebuild -scheme CitadelFull` (builds/embeds `CitadelNetExt`). Debug `Citadel` scheme runs Fortress without the extension until you ship a signed Full build.

## Release / packaging

Developer ID sign + DMG + optional notarize (same flow as Murmure):

```bash
# See RELEASE.md for notary profile setup
./Scripts/package-direct.sh
```

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
CITADEL_FORTRESS_DEMO=1 open build/Build/Products/Debug/Citadel.app
```

## What works when

| Component | Without approval | With helper + NetExt approved |
|-----------|------------------|-------------------------------|
| Activity / map / Suspects | Yes (local observation) | Yes |
| Allow/deny remembered | May be limited | Enforced per-app via NetExt |
| DNS blocklists | Needs helper | Yes |
| Connection history | Yes (on-device) | Yes |

## Architecture

```
Citadel.app (Fortress + Keep + Settings)
    ↕ XPC
CitadelHelper (DNS proxy, pfctl, privileged NetMonitor)
    ↕ app group JSON
CitadelNetExt (per-process filter — embedded in app bundle)
```

## Project layout

```
Sources/
├── CitadelDesign/   # Prism UI + map
├── Fortress/        # Activity, Suspects, History, telemetry
├── GUI/             # Shell, menubar, alerts, settings, help
├── Shared/          # Models + Firewall evaluator + RuleStore + help catalogs
├── Helper/          # Privileged daemon
└── NetExt/          # Network system extension
```

## Attribution

See `ATTRIBUTIONS.md` and `NOTICES.md`.

## License

Third-party notices are in `NOTICES.md` and `ATTRIBUTIONS.md`.
