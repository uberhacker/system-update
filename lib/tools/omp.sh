#!/usr/bin/env bash
# lib/tools/omp.sh - oh-my-pi (can1357/oh-my-pi; `omp -v` prints name/version).

tool_omp_detect() { user_bin omp; }

tool_omp_update() {
  tool_standard omp "${SU_TOOL_BIN[omp]}" '/[0-9]+\.[0-9]+|pi.*[0-9]+\.[0-9]+' '' -v -- omp update
}
