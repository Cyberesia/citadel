# Citadel Release Guide

**Developer ID** signed, hardened runtime, **notarized** `.app`, packaged as `.dmg`.

**Notarization is required** for distribution to other Macs (Gatekeeper). Signing alone is not enough.

Citadel additionally embeds:
- `CitadelHelper` (privileged daemon)
- `CitadelNetExt.systemextension` (per-app network filter)

## Signing setup (one time per machine)

Team-specific files are **not** in git. Copy the templates and configure locally:

```bash
cp Scripts/signing.local.env.example Scripts/signing.local.env
# Edit TEAM_ID in signing.local.env (10-character Apple Developer Team ID)

./Scripts/prepare-signing.sh
```

This creates (gitignored, local only):

| File | From template |
| :-- | :-- |
| `Scripts/signing.local.env` | `Scripts/signing.local.env.example` |
| `Sources/Helper/Info.plist` | `Sources/Helper/Info.plist.example` |
| `Packaging/Entitlements/CitadelHelper.entitlements` | `Packaging/Entitlements/CitadelHelper.entitlements.example` |

`prepare-signing.sh` skips files that already exist — safe to re-run.

Find your Team ID: **Xcode → Settings → Accounts → Team ID**, or:

```bash
security find-identity -v -p codesigning
```

## Direct release

```bash
export VERSION=0.1.2
export BUILD_NUMBER=3
# TEAM_ID is read from Scripts/signing.local.env
# Optional — resolved automatically from the keychain if unset:
# export CODESIGN_IDENTITY="Developer ID Application: Your Org (YOUR_TEAM_ID)"
# Default notary profile name: citadel-notary (local Keychain alias — create once, see below)

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

### One-time setup (recommended)

```bash
# TEAM_ID from Scripts/signing.local.env
xcrun notarytool store-credentials citadel-notary \
  --apple-id "you@example.com" \
  --team-id "$TEAM_ID" \
  --password "<app-specific-password>"
```

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
| `Scripts/prepare-signing.sh` | Create local signing files from `.example` templates |
| `Scripts/package-direct.sh` | **Ship** — Release + sign + DMG + notary (this guide) |
| `Scripts/resign-launch-safe.sh` | Fix launch on a signed build missing provisioning profiles |
| `Scripts/build-signed.sh` | Local Debug install to `/Applications` |
| `Scripts/sign_and_notarize.sh` | Older zip-notary path — prefer `package-direct.sh` |
| `Scripts/make_dmg.sh` | Older DMG-only path — prefer `package-direct.sh` |

## GitHub remotes (official + mirror)

**Official releases:** [Cyberesia/citadel](https://github.com/Cyberesia/citadel) (public)  
**Mirror:** [Sal-ix/citadel](https://github.com/Sal-ix/citadel) (private, same release history)

Both remotes keep a **clean release history** — one commit per published version (`v0.1.0`, `v0.1.1`, …).  
Do **not** push the full local dev history to GitHub; keep dev commits local (or on `backup/full-dev-history`).

One-time setup:

```bash
git remote add cyberesia https://github.com/Cyberesia/citadel.git   # if missing
# origin → Sal-ix/citadel (private mirror)
```

After tagging and building the notarized DMG:

```bash
VERSION=0.1.2 BUILD_NUMBER=3 ./Scripts/package-direct.sh

# Squash the release tree onto main (one commit per version), then tag:
git checkout "$VERSION_TREE_SHA" -- .
git commit -m "Citadel v$VERSION"
git tag -a "v$VERSION" -m "Citadel v$VERSION"

git push origin main --force-with-lease && git push origin "v$VERSION" --force
git push cyberesia main --force-with-lease && git push cyberesia "v$VERSION" --force

gh release create "v$VERSION" .build/distribution/direct/Citadel.dmg \
  --repo Cyberesia/citadel --title "Citadel v$VERSION" --notes-file CHANGELOG.md
```

Replace `$VERSION_TREE_SHA` with the commit that contains the built tree (e.g. local dev HEAD before squash).

## Notes

- System extension + Developer ID requires the Network Extension / System Extension capabilities on the team.
- App Group `group.com.citadel.firewall` must match across app, helper, and NetExt.
- Forks and third-party builds must use **their own** Team ID in `signing.local.env` and the generated local plists/entitlements.
