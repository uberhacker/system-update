#!/usr/bin/env bash
# lib/tools/kilo.sh - Kilo Code CLI (npm @kilocode/cli; self-update: kilo upgrade).
#
# "kilo" is also antirez's terminal text editor, which treats "-v" as a file
# name and then spins forever reading the terminal. tool_identify() only
# calls the binary with a timeout and stdin from /dev/null, and only after
# the npm package layout did not already identify it.

tool_kilo_detect() { user_bin kilo; }

tool_kilo_update() {
  tool_standard kilo "${SU_TOOL_BIN[kilo]}" '^v?[0-9]+\.[0-9]+\.[0-9]+' \
    '@kilocode/cli' --version -- kilo upgrade
}
