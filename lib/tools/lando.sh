#!/usr/bin/env bash
# lib/tools/lando.sh - Lando (self-update: lando update -y).

tool_lando_detect() { user_bin lando; }

tool_lando_update() {
  tool_standard lando "${SU_TOOL_BIN[lando]}" 'v?[0-9]+\.[0-9]+\.[0-9]+' '' version -- lando update -y
}
