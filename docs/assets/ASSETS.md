# README media assets

Compressed PNGs used by the root `README.md` (max width 1440px; banner 1920×640 crop).

## In use

| File | Source capture | Section |
|------|----------------|---------|
| `banner.png` | Activity dashboard (crop) | Top banner |
| `fortress-overview.png` | Fortress · Activity | Hero + features intro |
| `fortress-activity.png` | Activity · stream detail | Fortress |
| `fortress-suspects.png` | Fortress · Suspects | Fortress |
| `fortress-rules.png` | Fortress · Rules | Trust |
| `keep-sessions.png` | Keep · Ask | Keep |
| `keep-agents.png` | Keep · Agents | Keep |
| `keep-mcp.png` | Keep · Assistants · More menu | MCP / tools |
| `prism-shell.png` | Keep · Assistants grid | Prism |

## Optional (not yet captured)

| File | Spec | Section |
|------|------|---------|
| `hero.webm` | 16:9 demo video | Hero (replaces static overview) |
| `menubar.png` | Menubar / Crest | Prism |
| `install-dmg.png` | DMG install | Install |
| `permissions-helper.png` | Login Items | Install |
| `permissions-netext.png` | Network filter approval | Install |

## Regenerate

From `__temp-images-readme/` originals:

```bash
python3 Scripts/optimize-readme-assets.py   # if added
```

Or re-run ImageMagick resize (`1440x>`) + `oxipng -o 4 --strip all` on each PNG.
