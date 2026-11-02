#!/usr/bin/env bash
# lib/tools/grok.sh - grok CLI (self-update: grok update).
# "grok" is also the name of unrelated pattern-matching tools; the version
# probe must look like a semantic version before anything is run.

tool_grok_detect() { user_bin grok; }

tool_grok_update() {
  tool_standard grok "${SU_TOOL_BIN[grok]}" '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+' '' --version -- grok update
}
