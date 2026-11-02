#!/usr/bin/env bash
# lib/tools/rustup.sh - Rust toolchains via rustup.
#
# `rustup self update` (unless rustup itself comes from the distro or
# Homebrew, which then own it) followed by `rustup update --no-self-update`
# for every installed toolchain. The dry run uses `rustup check`, which only
# reads the channel manifests.

tool_rustup_detect() {
  local bin
  if bin=$(user_bin rustup); then printf '%s\n' "$bin"; return 0; fi
  bin="${CARGO_HOME:-$SU_USER_HOME/.cargo}/bin/rustup"
  [ -x "$bin" ] || return 1
  printf '%s\n' "$bin"
}

tool_rustup_update() {
  local bin="${SU_TOOL_BIN[rustup]}" method log rc=0 self=1 before after updated unchanged pending notes=()

  # Not tool_identify: a distro-packaged rustup still manages the user's
  # toolchains; only `rustup self update` is then left to the distro.
  method=$(install_method "$bin")
  tool_probe_check rustup "$bin" '^rustup [0-9]' --version || return 0
  before=$(version_from_text "$TOOL_PROBE_OUT")
  case "${method%%:*}" in
    distro) self=0; notes+=("rustup itself comes from $SU_PKG package '${method#*:}'") ;;
    brew) self=0; notes+=("rustup itself comes from Homebrew (see the brew step)") ;;
  esac
  log=$(tmp_file) || return 1

  if [ "$SU_DRY_RUN" = 1 ]; then
    if SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "$bin" check; then
      pending=$(count_matching 'Update available' "$log")
      if [ "$pending" -gt 0 ]; then
        notes+=("$pending update(s) available; would run rustup update")
      else
        notes+=("all toolchains up to date")
      fi
    else
      notes+=("rustup check failed; would run rustup update")
    fi
    [ "$self" = 1 ] && notes+=("would run rustup self update")
    step_dry "$(join_by '; ' "${notes[@]}")"
    return 0
  fi

  if [ "$self" = 1 ]; then
    if run_capture "$log" run_user "$bin" self update; then
      grep -qiE 'rustup updated|updated rustup' "$log" && notes+=("rustup self-updated")
    else
      notes+=("rustup self update failed (toolchains still updated)")
    fi
    : > "$log"
  fi
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_user "$bin" update --no-self-update || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "rustup update failed ($(rc_note "$rc"))${notes[0]:+; $(join_by '; ' "${notes[@]}")}"
    return 0
  fi
  # "  stable-x86_64-unknown-linux-gnu updated - rustc 1.82.0 ..." / "... unchanged - ..."
  updated=$(count_matching '^[[:space:]]*[^[:space:]]+[[:space:]]+updated( |$)' "$log")
  unchanged=$(count_matching '^[[:space:]]*[^[:space:]]+[[:space:]]+unchanged( |$)' "$log")
  after=$(version_from_text "$(tool_probe "$bin" --version)")
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    notes+=("rustup $before -> $after")
  fi
  if [ "$updated" -gt 0 ]; then
    step_updated "$updated toolchain(s) updated, $unchanged unchanged${notes[0]:+; $(join_by '; ' "${notes[@]}")}"
  elif [[ " ${notes[*]} " == *"rustup $before -> $after"* ]]; then
    step_updated "$(join_by '; ' "${notes[@]}"); $unchanged toolchain(s) unchanged"
  else
    step_ok "$unchanged toolchain(s) up to date${notes[0]:+; $(join_by '; ' "${notes[@]}")}"
  fi
}
