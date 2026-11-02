#!/usr/bin/env bash
# lib/tools/copilot.sh - GitHub Copilot CLI (npm @github/copilot).

tool_copilot_detect() { user_bin copilot; }

tool_copilot_update() {
  tool_standard copilot "${SU_TOOL_BIN[copilot]}" '[Cc]opilot.*[0-9]+\.[0-9]+' \
    '@github/copilot' --version -- copilot update
}
