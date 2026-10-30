#!/usr/bin/env bash
# lib/tools/agy.sh - agy CLI (self-update: agy update).

tool_agy_detect() { user_bin agy; }

tool_agy_update() {
  tool_standard agy "${SU_TOOL_BIN[agy]}" '[0-9]+\.[0-9]+' '' --version -- agy update
}
