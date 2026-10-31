#!/usr/bin/env bash
# lib/pkg/emerge.sh - Gentoo (best effort, untested in CI).
#
# A world update on Gentoo can take hours and may need manual USE/keyword
# changes; this module only does the straightforward part and reports.

pkg_emerge_dry_needs_root() { return 1; }

# emerge_atom_split ATOM: "name|version" of cat/pkg-1.2.3-r1[:slot][::repo].
emerge_atom_split() {
  local atom="${1%%::*}"
  atom="${atom%%:*}"
  if [[ "$atom" =~ ^(.+)-([0-9][^-]*(-r[0-9]+)?)$ ]]; then
    printf '%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  else
    printf '%s|?\n' "$atom"
  fi
}

# emerge_changes LOGFILE: "name|installed|new" from `emerge --pretend`:
#   [ebuild     U  ] sys-libs/glibc-2.39-r6:2.2::gentoo [2.38-r10:2.2::gentoo]
#   [ebuild  N     ] app-misc/foo-1.0::gentoo
emerge_changes() {
  local line split name new old re='^\[ebuild[^]]*\] ([^ ]+)( \[([^]]+)\])?'
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] || continue
    old="${BASH_REMATCH[3]}"
    split=$(emerge_atom_split "${BASH_REMATCH[1]}")
    name="${split%%|*}"; new="${split#*|}"
    old="${old%%::*}"; old="${old%%:*}"
    # A rebuild of the same version shows no bracket; say so.
    if [ -z "$old" ] && [[ "$line" =~ ^\[ebuild[^]]*R ]]; then old="$new"; fi
    printf '%s|%s|%s\n' "$name" "$old" "$new"
  done < "$1"
}

pkg_emerge_update() {
  local log rc=0 count
  log=$(tmp_file) || return 1
  log_warn "Gentoo support is best effort: emerge --sync followed by emerge -uDN @world"

  if [ "$SU_DRY_RUN" = 1 ]; then
    run_capture "$log" run_root_opt emerge --pretend --update --deep --newuse --color n @world || rc=$?
    if [ "$rc" -ne 0 ]; then
      step_fail "emerge --pretend failed ($(rc_note "$rc"))"
      return 0
    fi
    count=$(count_matching '^\[ebuild' "$log")
    detail_show "package(s)" emerge_changes "$log"
    step_dry "$count package(s) would be rebuilt/updated (tree not synced in dry run)"
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root emerge --sync --quiet || { step_fail "emerge --sync failed"; return 0; }
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root emerge --update --deep --newuse --color n @world || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "emerge @world failed ($(rc_note "$rc"))"
    return 0
  fi
  count=$(count_matching '^>>> Installing' "$log")
  if cfg_bool AUTOREMOVE; then
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root emerge --depclean --quiet || log_warn "emerge --depclean failed"
  fi
  if [ "$count" = 0 ]; then
    step_ok "no updates available"
  else
    step_updated "$count package(s) installed"
  fi
}

pkg_emerge_install() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root emerge --noreplace --quiet "$@"
}
