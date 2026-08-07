# Changelog

All notable changes to Citadel are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.1] - 2026-08-06

### Fixed

- **Document attachments** — PDF/DOCX sent as proper `local` file refs; copied into workspace on send; preview panel (*Aperçu*) clarified.
- **Document indexing (chat-only models)** — PDF/DOCX text extracted on-device (Murmura-style) and inlined in the message, so models without tool support (e.g. DeepSeek R1) can answer about attached or workspace files.
- **Workspace file matching** — asking about "Sophie" auto-includes matching PDFs/DOCX from the workspace folder.
- **Document attachments UI** — excerpts render in collapsible indexed cards with think-tag shimmer (not raw text in the orange bubble); question stays in the orange bubble only.
- **Cloud model + MCP** — Cursor/Aisance-style MCP curation; cloud-first error messages (no spurious Ollama advice on OpenAI); auto-retry without MCP on failure.

## [0.1.0] - 2026-08-03

### Added

- Initial public release: Fortress firewall, Keep agents, Prism UI.
- Open-source README (EN/FR), documentation scaffold, and release guide.

[Unreleased]: https://github.com/Sal-ix/citadel/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Sal-ix/citadel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Sal-ix/citadel/releases/tag/v0.1.0
