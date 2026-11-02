#!/usr/bin/env bash
# lib/tools/pi.sh - pi coding agent (self-update: pi update).
# "pi" is also a Debian package that prints digits of pi; the version probe
# must show a semantic version before anything is run.

tool_pi_detect() { user_bin pi; }

tool_pi_update() {
  tool_standard pi "${SU_TOOL_BIN[pi]}" '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+' '' --version -- pi update
}
