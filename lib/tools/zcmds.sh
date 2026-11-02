#!/usr/bin/env bash
# lib/tools/zcmds.sh - zcmds (installed with pipx or uv tool).

tool_zcmds_detect() { user_bin zcmds; }

tool_zcmds_update() {
  # No self-update command: the pipx/uv package layout decides how to update.
  tool_standard zcmds "${SU_TOOL_BIN[zcmds]}" 'zcmds|[0-9]+\.[0-9]+' 'zcmds' --version --
}
