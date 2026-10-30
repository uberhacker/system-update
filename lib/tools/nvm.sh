#!/usr/bin/env bash
# lib/tools/nvm.sh - Node.js via nvm: keep the current LTS as the default.
#
#  * installs the newest LTS with --reinstall-packages-from the previous
#    default (or the active version), so global packages survive;
#  * sets `default` to lts/* and verifies the alias resolves;
#  * never uninstalls anything unless PRUNE_NODE=1 (--prune-node), and then
#    only after the new default is in place and never the new default itself;
#  * no iojs, no Node 4/6/8.
#
# nvm is a shell function, so each call runs in a child bash that sources
# nvm.sh with --no-use, under timeout and with stdin from /dev/null.

tool_nvm_detect() {
  local dir="${NVM_DIR:-$SU_USER_HOME/.nvm}"
  [ -s "$dir/nvm.sh" ] || return 1
  printf '%s\n' "$dir/nvm.sh"
}

# nvm_run ARGS...: run an nvm command in a fresh shell.
nvm_run() {
  local nvmsh="${SU_TOOL_BIN[nvm]}"
  # shellcheck disable=SC2016  # expanded by the child bash on purpose
  SU_RUN_TIMEOUT=${SU_RUN_TIMEOUT:-$SU_TIMEOUT} run_user bash -c \
    'export NVM_DIR="${1%/nvm.sh}"; set +u; . "$1" --no-use >/dev/null 2>&1; shift; nvm "$@"' _ "$nvmsh" "$@"
}

# nvm_version_of ALIAS: resolved version (vX.Y.Z) or empty.
nvm_version_of() {
  local v
  v=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT nvm_run version "$1" 2>/dev/null | tail -n1)
  [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$v"
}

tool_nvm_update() {
  local current prev target have rc=0 installed v pruned=0 note

  current=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT nvm_run current 2>/dev/null | tail -n1)
  prev=$(nvm_version_of default) || prev=""
  if [ -z "$prev" ] && [[ "$current" =~ ^v[0-9]+ ]]; then prev="$current"; fi
  log_info "default: ${prev:-none}${current:+ (active: $current)}"

  target=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT nvm_run version-remote --lts 2>/dev/null | tail -n1)
  if ! [[ "$target" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    step_fail "could not determine the current LTS version (nvm version-remote --lts)"
    return 0
  fi
  log_info "current LTS: $target"
  have=$(nvm_version_of "$target") || have=""

  if [ "$SU_DRY_RUN" = 1 ]; then
    if [ "$have" = "$target" ] && [ "$prev" = "$target" ]; then
      step_dry "already on LTS $target"
    else
      note="would install $target${prev:+ (migrating global packages from $prev)} and set default to lts/*"
      cfg_bool PRUNE_NODE && note="$note; would remove other versions"
      step_dry "$note"
    fi
    return 0
  fi

  if [ "$have" != "$target" ]; then
    if [ -n "$prev" ] && [ "$prev" != "$target" ]; then
      nvm_run install "$target" --reinstall-packages-from="$prev" || rc=$?
    else
      nvm_run install "$target" || rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
      step_fail "nvm install $target failed ($(rc_note "$rc")); previous default left in place"
      return 0
    fi
  fi
  nvm_run alias default 'lts/*' >/dev/null || { step_fail "could not set the default alias"; return 0; }
  if [ "$(nvm_version_of default)" != "$target" ]; then
    step_fail "default alias does not resolve to $target"
    return 0
  fi

  if cfg_bool PRUNE_NODE; then
    installed=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT nvm_run ls --no-colors --no-alias 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -u)
    for v in $installed; do
      [ "$v" = "$target" ] && continue
      if nvm_run uninstall "$v" >/dev/null; then pruned=$((pruned + 1)); else log_warn "could not remove $v"; fi
    done
  fi

  note="default is $target"
  [ "$pruned" -gt 0 ] && note="$note; removed $pruned other version(s)"
  if [ "$prev" != "$target" ]; then
    step_updated "${prev:-none} -> $target; $note"
  else
    step_ok "$note"
  fi
}
