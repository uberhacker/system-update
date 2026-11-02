#!/usr/bin/env bash
# lib/tools/qwen.sh - Qwen Code CLI (npm @qwen-code/qwen-code; self-update: qwen update).

tool_qwen_detect() { user_bin qwen; }

tool_qwen_update() {
  tool_standard qwen "${SU_TOOL_BIN[qwen]}" '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+' \
    '@qwen-code/qwen-code' --version -- qwen update
}
