#!/usr/bin/env bash
# lib/tools/devin.sh - Devin CLI (self-update: devin update).

tool_devin_detect() { user_bin devin; }

tool_devin_update() {
  tool_standard devin "${SU_TOOL_BIN[devin]}" '[0-9]+\.[0-9]+' '' --version -- devin update
}
