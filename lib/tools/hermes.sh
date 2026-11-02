#!/usr/bin/env bash
# lib/tools/hermes.sh - Hermes agent (NousResearch/hermes-agent; self-update: hermes update).

tool_hermes_detect() { user_bin hermes; }

tool_hermes_update() {
  tool_standard hermes "${SU_TOOL_BIN[hermes]}" '[Hh]ermes.*[0-9]+\.[0-9]+|[0-9]+\.[0-9]+\.[0-9]+' \
    'hermes-agent' -V -- hermes update
}
