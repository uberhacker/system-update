#!/usr/bin/env bash
# lib/tools/claude.sh - Claude Code (native installer or npm @anthropic-ai/claude-code).

tool_claude_detect() { user_bin claude; }

tool_claude_update() {
  tool_standard claude "${SU_TOOL_BIN[claude]}" '[0-9]+\.[0-9]+\.[0-9]+.*Claude Code' \
    '@anthropic-ai/claude-code' --version -- claude update
}
