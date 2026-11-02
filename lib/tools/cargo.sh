#!/usr/bin/env bash
# lib/tools/cargo.sh - crates installed with `cargo install`.
#
# cargo has no built-in "update everything"; the cargo-update crate adds
# `cargo install-update -a`. When it is not installed the step names the
# crates it would update and how to enable it. Builds can take a while, so
# the package-manager timeout applies.

cargo_home() { printf '%s\n' "${CARGO_HOME:-$SU_USER_HOME/.cargo}"; }

tool_cargo_detect() {
  local bin
  bin=$(user_bin cargo) || bin="$(cargo_home)/bin/cargo"
  [ -x "$bin" ] || return 1
  [ -s "$(cargo_home)/.crates.toml" ] || return 1
  printf '%s\n' "$bin"
}

# cargo_crates: names of the installed crates, from .crates.toml.
cargo_crates() {
  grep -o -E '^"[A-Za-z0-9_-]+ [0-9]' "$(cargo_home)/.crates.toml" 2>/dev/null | sed -E 's/^"//; s/ [0-9]$//'
}

tool_cargo_update() {
  local bin="${SU_TOOL_BIN[cargo]}" crates count log rc=0 pending updated
  crates=$(cargo_crates)
  count=$(printf '%s\n' "$crates" | grep -c . || true)
  [ "$count" -gt 0 ] || { step_skip "no crates installed with cargo install"; return 0; }
  log_info "$count crate(s): $(printf '%s\n' "$crates" | tr '\n' ' ' | sed 's/ $//')"

  if ! has_cmd cargo-install-update && [ ! -x "$(cargo_home)/bin/cargo-install-update" ]; then
    step_skip "$count crate(s) installed with cargo; install cargo-update (cargo install cargo-update) to update them here"
    return 0
  fi
  log=$(tmp_file) || return 1

  if [ "$SU_DRY_RUN" = 1 ]; then
    if SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "$bin" install-update --list -a; then
      pending=$(count_matching '[[:space:]]Yes[[:space:]]*$' "$log")
      step_dry "$pending of $count crate(s) have updates; would run cargo install-update -a"
    else
      step_dry "would run cargo install-update -a for $count crate(s)"
    fi
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "$bin" install-update -a || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "cargo install-update -a failed ($(rc_note "$rc"))"
    return 0
  fi
  updated=$(grep -o -E 'Updated [0-9]+ package' "$log" | grep -o -E '[0-9]+' | head -n1)
  if [ -n "$updated" ] && [ "$updated" -gt 0 ]; then
    step_updated "$updated of $count crate(s) updated"
  else
    step_ok "$count crate(s) up to date"
  fi
}
