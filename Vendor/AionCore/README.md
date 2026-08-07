# AionCore MCP tool schema sanitization (Citadel)

Citadel curates MCP **server selection** and validates tool schemas in Swift before send.
The bundled **CoworkCore** binary (AionCore) still forwards raw MCP `input_schema` JSON to cloud APIs.

Upstream gap: AionCore has no Codex/OpenCode-style `sanitizeOpenAISchema` pass yet.

## Reference

- `tool_schema_sanitize.rs` — Rust port of OpenCode PR #32489 (OpenAI/Gemini lowering)
- Citadel Swift mirror: `Sources/Shared/CoworkMcpToolSchemaSanitizer.swift`

## Integration (when building CoworkCore from source)

1. Copy `tool_schema_sanitize.rs` into `crates/aionui-mcp/src/`
2. Call `sanitize_for_provider(schema, platform)` immediately before serializing tools for OpenAI/Anthropic/Gemini adapters
3. Rebuild via `Scripts/prepare-coworkcore.sh` (set `CITADEL_PATCH_AIONCORE=1` when patch wiring is added)

Until upstream merges this, Citadel's client-side curation reduces rejections but cannot rewrite schemas inside the runtime.
