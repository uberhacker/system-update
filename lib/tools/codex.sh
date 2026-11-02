#!/usr/bin/env bash
# lib/tools/codex.sh - OpenAI Codex CLI (npm @openai/codex).

tool_codex_detect() { user_bin codex; }

tool_codex_update() {
  tool_standard codex "${SU_TOOL_BIN[codex]}" 'codex(-cli)? [0-9]+\.[0-9]+' \
    '@openai/codex' --version -- codex update
}
