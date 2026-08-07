# Changelog

All notable changes to Citadel are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.3] - 2026-08-08

### Added

- **Response streaming optimisation (Murmura-style)** — delta coalescing + typewriter; live markdown on the answer while it types (no raw `**markdown**` snap at the end); throttled UI updates instead of per-token redraws.
- **Live Ollama reasoning** — direct `/api/chat` stream with `think: true` so thinking appears immediately (no long blank wait).
- **Retractable thinking cards** — stream live, then auto-collapse (expandable); plain text for thinking so large models stay smooth.
- **GFM tables in chat** — bordered markdown tables in answers (not monospace/PDF-style columns).
- **Global tool-permission card** — Allow/Deny prompts stay visible across Keep tabs and Fortress; survive leaving the chat; optional “Open session” when the conversation is closed.
- **Collapsible Fortress status bar** — hide/show the bottom “Watching locally / Surveillance locale” bar so Activity summaries stay readable.
- **Richer agent activity status** — banner/header show the live tool, permission wait, reasoning, or assistant name (with roller + shimmer), not only “Agent working…”.
- **Cloud direct chat** — SOTA / BYOK models (e.g. Luna) can answer without ACP/MCP injection blocking the turn.
- **Clearer MLX → tools guidance** — banner/chips and copy point to Ollama or a cloud model that supports tools; “Switch model…” sheet.

### Fixed

- **Permission prompts missing on the first turn** — resync confirmation queue on tool calls; do not wipe pending confirmations when switching Keep tabs.
- **Allow/Deny after leaving chat** — responses resolve against the anchored conversation ID so tools are not stuck as “User denied”.
- **Reply vanishing mid-stream** — implicit-thinking / coalescer edge cases no longer swallow the answer after it appears.
- **Ollama model persistence** — last Ollama model (e.g. Qwen coding) stays selected instead of resetting to `latest`.
- **Direct-chat transcript** — streamed answers persist across reload instead of wiping.
- **Local dictation** — Apple Speech + mic recorder rewrite; mic turns red while recording / green when idle; phrases append instead of overwrite; clearer “click to dictate / click to transcribe”; main window restored after mic permission (no disappearing app).

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

[Unreleased]: https://github.com/Cyberesia/citadel/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/Cyberesia/citadel/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Cyberesia/citadel/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Cyberesia/citadel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Cyberesia/citadel/releases/tag/v0.1.0
