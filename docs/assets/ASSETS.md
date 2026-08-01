# README media assets

Compressed PNGs for the root README files (max width 1440px; banners optimized separately).

## English (`README.md`) — `docs/assets/`

| File | Section |
|------|---------|
| `banner.png` | Top banner (1920×640 crop from Activity) |
| `fortress-overview.png` | Hero · Fortress Activity |
| `fortress-activity.png` | Fortress · stream detail |
| `fortress-suspects.png` | Fortress · Suspects |
| `fortress-rules.png` | Trust · Rules |
| `keep-sessions.png` | Keep · Ask |
| `keep-agents.png` | Keep · Agents |
| `keep-mcp.png` | Keep · Assistants · More menu |
| `prism-shell.png` | Keep · Assistants grid |

## French (`README.fr.md`) — `docs/assets/fr/`

| File | Section |
|------|---------|
| `banner.png` | Bannière marketing (1600×800, ChatGPT composite) |
| `fortress-overview.png` | Hero · Fortress Activité |
| `fortress-activity.png` | Fortress · Activité (vue globale) |
| `fortress-suspects.png` | Fortress · Suspects |
| `fortress-rules.png` | Confiance · Règles |
| `keep-sessions.png` | Keep · Demander |
| `keep-agents.png` | Keep · Agents |
| `keep-mcp.png` | Keep · Assistants |
| `prism-shell.png` | Keep · Réglages (Apparence, Compagnon) |

## Optional (not yet captured)

| File | Spec | Section |
|------|------|---------|
| `hero.webm` | 16:9 demo video | Hero video |
| `menubar.png` | Menubar / Crest | Shell |
| `install-dmg.png` | DMG install | Install |
| `permissions-helper.png` | Login Items | Install |
| `permissions-netext.png` | Network filter approval | Install |

## Regenerate

Resize with ImageMagick (`1440x>` or `1920x>` for banners) + `oxipng -o 4 --strip all`.
