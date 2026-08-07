# Changelog

All notable changes to Citadel are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.2] - 2026-08-07

### Added

- **Workspace document search** — generic matching by filename, Finder/Spotlight content index (`kMDItemTextContent`), and local text extraction fallback (PDF, DOCX, PPTX, XLSX, CSV, etc.); no domain-specific keywords.
- **Update detection** — checks [Cyberesia/citadel](https://github.com/Cyberesia/citadel) releases on launch and in Settings; optional alert with direct DMG download link.
- **Model retention** — last Keep model/provider choice restored on relaunch (UserDefaults).

### Fixed

- **Aperçu (Preview) panel** — PDF/DOCX open from local workspace folders via on-disk read (no dependency on CoworkCore `read-buffer`); PDF viewer uses full panel height.
- **Document excerpt UI** — compact « N documents indexés — toucher pour développer » summary in chat history when many files were inlined.
- **Voice dictation** — `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in Info.plist; safer Apple Speech lifecycle (on-device availability check, main-thread buffers, no auto-stop race); clearer error when Keep is not running; CoworkCore STT fallback when on-device text is empty.
- **Cloud model errors** — provider-aware messages (no spurious Ollama advice when using OpenAI).

## [0.1.1] - 2026-08-06

### Fixed

- **Document attachments** — PDF/DOCX sent as proper `local` file refs; copied into workspace on send; preview panel (*Aperçu*) clarified.
- **Document indexing (chat-only models)** — PDF/DOCX text extracted on-device (Murmura-style) and inlined in the message, so models without tool support (e.g. DeepSeek R1) can answer about attached or workspace files.
- **Workspace file matching** — asking about a name auto-includes matching PDFs/DOCX from the workspace folder.
- **Document attachments UI** — excerpts render in collapsible indexed cards with think-tag shimmer (not raw text in the orange bubble); question stays in the orange bubble only.
- **Cloud model + MCP** — Cursor/Aisance-style MCP curation; cloud-first error messages (no spurious Ollama advice on OpenAI); auto-retry without MCP on failure.

## [0.1.0] - 2026-08-03

### Added

- Initial public release: Fortress firewall, Keep agents, Prism UI.
- Open-source README (EN/FR), documentation scaffold, and release guide.

[Unreleased]: https://github.com/Cyberesia/citadel/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/Cyberesia/citadel/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Cyberesia/citadel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Cyberesia/citadel/releases/tag/v0.1.0
