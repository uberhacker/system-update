#!/usr/bin/env bash
# lib/tools/asdf.sh - asdf: plugin updates, self-update where possible and,
# with RUNTIMES=1 (--runtimes), conservative runtime upgrades.
#
# Two generations exist and both are handled:
#   * asdf <= 0.15: a bash script in a git checkout (~/.asdf). `asdf update`
#     pulls it, unless the install came from a package manager (the checkout
#     then carries asdf_updates_disabled);
#   * asdf >= 0.16: a Go binary. It has no self-update; its releases publish
#     only md5 files, which is not good enough to install from here, so the
#     step says how to update it instead.
# `asdf plugin update --all` works in both. Runtimes: for every tool pinned
# in the user's own ~/.tool-versions, the newest version with the same major
# is installed and becomes the home default (asdf global / asdf set -u).
# Project .tool-versions files are never touched.

asdf_data_dir() { printf '%s\n' "${ASDF_DATA_DIR:-${ASDF_DIR:-$SU_USER_HOME/.asdf}}"; }

tool_asdf_detect() {
  local bin
  if bin=$(user_bin asdf); then printf '%s\n' "$bin"; return 0; fi
  bin="${ASDF_DIR:-$SU_USER_HOME/.asdf}/bin/asdf"
  [ -x "$bin" ] || return 1
  printf '%s\n' "$bin"
}

# asdf_is_legacy BIN: the bash implementation (a script), not the Go binary.
asdf_is_legacy() { [ "$(head -c 2 "$1" 2>/dev/null)" = '#!' ]; }

# asdf_plugin_heads: "<plugin> <commit>" for every plugin checkout.
asdf_plugin_heads() {
  local d
  for d in "$(asdf_data_dir)"/plugins/*/; do
    [ -d "$d/.git" ] || continue
    printf '%s %s\n' "$(basename "$d")" "$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')"
  done
}

# asdf_runtimes BIN LEGACY DRY: upgrade the home pins within their majors.
# Appends to ASDF_NOTES; sets ASDF_CHANGED / ASDF_FAILED.
asdf_runtimes() {
  local bin="$1" legacy="$2" tv="$SU_USER_HOME/.tool-versions" plugin pinned rest major latest n
  [ -r "$tv" ] || { ASDF_NOTES+=("runtimes: no $tv"); return 0; }
  n=${#ASDF_NOTES[@]}
  while read -r plugin pinned rest; do
    [ -n "$plugin" ] || continue
    [[ "$plugin" != \#* ]] || continue
    [[ "$pinned" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue   # system, latest, ref:, path: are left alone
    major="${pinned%%.*}"
    latest=$(SU_RUN_TIMEOUT=$SU_PROBE_TIMEOUT run_user "$bin" latest "$plugin" "$major" 2>/dev/null | tail -n1)
    [[ "$latest" =~ ^[0-9]+(\.[0-9]+)*$ ]] || continue
    version_lt "$pinned" "$latest" || continue
    if [ "$SU_DRY_RUN" = 1 ]; then
      ASDF_NOTES+=("would upgrade $plugin $pinned -> $latest")
      continue
    fi
    if ! SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user "$bin" install "$plugin" "$latest"; then
      ASDF_NOTES+=("$plugin $latest install failed"); ASDF_FAILED=1
      continue
    fi
    if [ "$legacy" = 1 ]; then
      run_user "$bin" global "$plugin" "$latest" || { ASDF_NOTES+=("could not set $plugin global version"); ASDF_FAILED=1; continue; }
    else
      run_user "$bin" set -u "$plugin" "$latest" || { ASDF_NOTES+=("could not set $plugin home version"); ASDF_FAILED=1; continue; }
    fi
    ASDF_NOTES+=("$plugin $pinned -> $latest"); ASDF_CHANGED=1
  done < "$tv"
  [ "${#ASDF_NOTES[@]}" -gt "$n" ] || ASDF_NOTES+=("runtimes: all current within their majors")
}

tool_asdf_update() {
  local bin="${SU_TOOL_BIN[asdf]}" ver legacy=0 method before after count moved
  ASDF_NOTES=(); ASDF_FAILED=0; ASDF_CHANGED=0

  ver=$(version_from_text "$(tool_probe "$bin" version)")
  [ -n "$ver" ] || { step_skip "$bin does not answer 'asdf version'; it looks like a different program"; return 0; }
  asdf_is_legacy "$bin" && legacy=1
  log_info "asdf $ver ($([ "$legacy" = 1 ] && echo 'bash checkout' || echo 'Go binary'))"
  method=$(install_method "$bin")

  # Self-update.
  case "${method%%:*}" in
    distro) ASDF_NOTES+=("asdf itself comes from $SU_PKG package '${method#*:}'") ;;
    brew) ASDF_NOTES+=("asdf itself comes from Homebrew (see the brew step)") ;;
    *)
      if [ "$legacy" = 1 ]; then
        if [ -e "$(asdf_data_dir)/asdf_updates_disabled" ]; then
          ASDF_NOTES+=("asdf self-update disabled by its package")
        elif [ "$SU_DRY_RUN" = 1 ]; then
          ASDF_NOTES+=("would run asdf update")
        elif run_user "$bin" update; then
          after=$(version_from_text "$(tool_probe "$bin" version)")
          if [ -n "$after" ] && [ "$after" != "$ver" ]; then ASDF_NOTES+=("asdf $ver -> $after"); ASDF_CHANGED=1; else ASDF_NOTES+=("asdf up to date ($ver)"); fi
        else
          ASDF_NOTES+=("asdf update failed"); ASDF_FAILED=1
        fi
      else
        ASDF_NOTES+=("asdf $ver is a binary release; update it with your package manager or from github.com/asdf-vm/asdf/releases (no sha256 published)")
      fi ;;
  esac

  # Plugins.
  before=$(asdf_plugin_heads)
  count=$(printf '%s\n' "$before" | grep -c . || true)
  if [ "$count" -gt 0 ]; then
    if [ "$SU_DRY_RUN" = 1 ]; then
      ASDF_NOTES+=("would run asdf plugin update --all ($count plugin(s))")
    elif SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_user "$bin" plugin update --all; then
      after=$(asdf_plugin_heads)
      moved=$(printf '%s\n%s\n' "$before" "$after" | sort | uniq -u | cut -d' ' -f1 | sort -u | grep -c . || true)
      if [ "$moved" -gt 0 ]; then ASDF_NOTES+=("$moved of $count plugin(s) updated"); ASDF_CHANGED=1; else ASDF_NOTES+=("$count plugin(s) up to date"); fi
    else
      ASDF_NOTES+=("asdf plugin update --all failed"); ASDF_FAILED=1
    fi
  else
    ASDF_NOTES+=("no plugins installed")
  fi

  # Runtimes (opt-in).
  if cfg_bool RUNTIMES; then
    asdf_runtimes "$bin" "$legacy"
  else
    ASDF_NOTES+=("runtimes: off; enable with --runtimes or RUNTIMES=1")
  fi

  if [ "$SU_DRY_RUN" = 1 ]; then step_dry "$(join_by '; ' "${ASDF_NOTES[@]}")"; return 0; fi
  if [ "$ASDF_FAILED" = 1 ]; then step_fail "$(join_by '; ' "${ASDF_NOTES[@]}")"; return 0; fi
  if [ "$ASDF_CHANGED" = 1 ]; then step_updated "$(join_by '; ' "${ASDF_NOTES[@]}")"; else step_ok "$(join_by '; ' "${ASDF_NOTES[@]}")"; fi
}
