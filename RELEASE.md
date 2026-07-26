# Citadel Release Guide

Same distribution model as Murmure (`__murmura`): **Developer ID** signed, hardened runtime, **notarized** `.app`, packaged as `.dmg`.

**Notarization is required** for distribution to other Macs (Gatekeeper). Signing alone is not enough.

Citadel additionally embeds:
- `CitadelHelper` (privileged daemon)
- `CitadelNetExt.systemextension` (per-app network filter)

## Direct release

```bash
export VERSION=0.1.0
export BUILD_NUMBER=1
export TEAM_ID=98Y85F8KFJ
# Optional — resolved automatically from the keychain if unset:
# export CODESIGN_IDENTITY="Developer ID Application: Cyberesia SA (98Y85F8KFJ)"
# Default: citadel-notary (local Keychain alias — create once, see below)

./Scripts/package-direct.sh
```

Outputs:
- `.build/distribution/direct/Citadel.app`
- `.build/distribution/direct/Citadel.dmg`

The script:
1. Runs `xcodegen generate` and builds **Release** (`CitadelNetExt` then `Citadel`)
2. Embeds the system extension if needed
3. Signs **inside-out** (dylibs / bundles → helper → NetExt → app) with `Packaging/Entitlements/*`
4. Builds a branded DMG via vendored `create-dmg` (falls back to plain `hdiutil`)
5. Notarizes + staples via `NOTARYTOOL_PROFILE` (default: `citadel-notary`)

### Local signed build only (skip notary)

```bash
SKIP_NOTARIZATION=1 ./Scripts/package-direct.sh
```

### Skip coworkcore / simple DMG

```bash
SKIP_COWORKCORE=1 CITADEL_SIMPLE_DMG=1 ./Scripts/package-direct.sh
```

## Notary profile

`NOTARYTOOL_PROFILE` is only a **local Keychain label** on your Mac (`notarytool store-credentials`). Apple never sees the profile name — each submission is judged on the signed binary (bundle ID, team ID, entitlements, hardened runtime, etc.) and the Developer account used to upload it.

You can safely create a **dedicated Citadel profile** even if it uses the same Apple ID and team as Murmure. No confusion on Apple’s side.

### One-time setup (recommended)

```bash
xcrun notarytool store-credentials citadel-notary \
  --apple-id "you@example.com" \
  --team-id 98Y85F8KFJ \
  --password "<app-specific-password>"
```

Use the same Apple ID / app-specific password as `murmure-notary` if you want — that only duplicates credentials locally under a clearer name.

Verify:

```bash
xcrun notarytool history --keychain-profile citadel-notary
```

## Verification

```bash
APP=.build/distribution/direct/Citadel.app
DMG=.build/distribution/direct/Citadel.dmg

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"
xcrun stapler validate "$DMG"
```

## Local signed install (dev, no notary)

For helper registration on your Mac only (no DMG / notary):

```bash
./Scripts/build-signed.sh
```

## Developer ID provisioning profiles (Fortress / NetExt)

Citadel is **notarized and Gatekeeper-valid** even when it fails to open with Finder’s generic *« Impossible d'ouvrir l'application »*.

That happens when the **host app** is signed with `System Extension` / `Network Extension` entitlements **without** matching **Developer ID provisioning profiles**. macOS (AMFI) kills the process at launch — before any UI.

Default packaging uses **launch-safe** host entitlements (`CitadelDirectLaunch.entitlements`) so the app opens. The NetExt stays signed separately; full embedded-system-extension activation needs profiles.

Create on [developer.apple.com](https://developer.apple.com/account/resources/profiles/list) (Profiles → **Developer ID**):

| Profile | Bundle ID | Capabilities |
|---------|-----------|--------------|
| Citadel app | `com.citadel.firewall` | App Groups, Network Extension, System Extension (install) |
| Citadel NetExt | `com.citadel.firewall.netext` | App Groups, Network Extension (content filter) |

Download, install in Xcode, then ship with:

```bash
export CITADEL_PROVISIONING_PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/<citadel-app>.provisionprofile"
export CITADEL_FULL_ENTITLEMENTS=1   # optional explicit flag
./Scripts/package-direct.sh
```

### Fix an already-installed build that won't open

```bash
./Scripts/resign-launch-safe.sh /Applications/Citadel.app
# or copy to Desktop first if /Applications is locked:
ditto /Applications/Citadel.app ~/Desktop/Citadel.app
./Scripts/resign-launch-safe.sh ~/Desktop/Citadel.app
open ~/Desktop/Citadel.app
```

Re-notarize after changing signatures if you redistribute the build.

## After install on a Mac

1. Open `Citadel.app` (menu bar app — no main window at first)
2. System Settings → General → Login Items & Extensions → allow **Citadel** helper
3. System Settings → Privacy & Security → allow the **network filter** / system extension if prompted
4. Fortress status should move to **Protection active**

## Related scripts

| Script | Role |
|--------|------|
| `Scripts/package-direct.sh` | **Ship** — Release + sign + DMG + notary (this guide) |
| `Scripts/resign-launch-safe.sh` | Fix launch on a signed build missing provisioning profiles |
| `Scripts/build-signed.sh` | Local Debug install to `/Applications` |
| `Scripts/sign_and_notarize.sh` | Older zip-notary path — prefer `package-direct.sh` |
| `Scripts/make_dmg.sh` | Older DMG-only path — prefer `package-direct.sh` |

## Notes

- System extension + Developer ID requires the Network Extension / System Extension capabilities on the team.
- App Group `group.com.citadel.firewall` must match across app, helper, and NetExt.
- Murmure reference implementation: `__murmura/Scripts/package-direct.sh` and `__murmura/RELEASE.md`.
