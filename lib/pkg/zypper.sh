#!/usr/bin/env bash
# lib/pkg/zypper.sh - openSUSE Tumbleweed/Slowroll/MicroOS (dup) and Leap/SLE (update).

ZYPPER=(zypper --non-interactive --no-color)

pkg_zypper_dry_needs_root() { return 0; }

zypper_refresh() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${ZYPPER[@]}" refresh
}

# zypper_count LOGFILE: sum of "The following N packages are going to be upgraded/installed".
zypper_count() {
  local n sum=0
  while read -r n; do
    sum=$((sum + n))
  done < <(grep -E -o 'The following [0-9]+ (NEW )?packages? (are|is) going to be (upgraded|installed)' "$1" \
    | grep -E -o '[0-9]+')
  printf '%s\n' "$sum"
}

# zypper_changes LOGFILE: "name|installed|new" from the package sections of
# a `--dry-run --details` summary. Without a terminal zypper prints every
# column of the table on a line of its own:
#   The following 2 packages are going to be upgraded:
#   patterns-base-fips
#     20241218-lp160.5.1 -> 20241218+leap-lp160.1.1
#     x86_64
#     repo-oss (16.0)
# on a wide terminal the same row is one line ("  name  old -> new  arch ...").
# Patterns, patches and products are not packages and are left out.
zypper_changes() {
  local line mode="" name="" ver wrapped=0
  local re_head='^The following ([0-9]+ )?(NEW )?packages? (is|are) going to be ([A-Za-z]+)'
  local re_row='^[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)([[:space:]]+->[[:space:]]+([^[:space:]]+))?'
  while IFS= read -r line; do
    line="${line%"${line##*[![:space:]]}"}"
    if [[ "$line" =~ $re_head ]]; then
      case "${BASH_REMATCH[4]}" in
        upgraded|downgraded) mode=change ;;
        installed) mode=new ;;
        removed|REMOVED) mode=rm ;;
        *) mode="" ;;
      esac
      name=""; wrapped=0; continue
    fi
    if [ -z "$line" ] || [[ "$line" == "The following "* ]]; then mode=""; name=""; continue; fi
    [ -n "$mode" ] || continue
    if [[ "$line" != [[:space:]]* ]]; then
      name="$line"; wrapped=1; continue   # wrapped form: the name stands alone
    fi
    if [ -n "$name" ]; then
      ver="${line#"${line%%[![:space:]]*}"}"
      case "$mode" in
        change) printf '%s|%s|%s\n' "$name" "${ver%% -> *}" "${ver##* -> }" ;;
        new) printf '%s||%s\n' "$name" "$ver" ;;
        rm) printf '%s|%s|\n' "$name" "$ver" ;;
      esac
      name=""; continue
    fi
    [ "$wrapped" = 0 ] || continue          # arch/repo/vendor of a wrapped row
    [[ "$line" =~ $re_row ]] || continue   # one-line form
    [ -n "${BASH_REMATCH[4]}" ] || [ "$mode" != change ] || continue
    case "$mode" in
      change) printf '%s|%s|%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[4]}" ;;
      new) printf '%s||%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ;;
      rm) printf '%s|%s|\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" ;;
    esac
  done < "$1"
}

pkg_zypper_update() {
  local mode="$SU_ZYPPER_MODE" log rc=0 count note
  log=$(tmp_file) || return 1
  log_info "mode: zypper $mode (${SU_OS_PRETTY})"

  zypper_refresh || { step_fail "zypper refresh failed"; return 0; }

  if [ "$SU_DRY_RUN" = 1 ]; then
    if detail_enabled; then
      # --details prints several lines per package; the table below replaces it.
      SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${ZYPPER[@]}" "$mode" --dry-run --details >"$log" 2>&1 || rc=$?
      [ "$rc" -eq 0 ] || [ "$rc" -eq 100 ] || cat -- "$log"
    else
      SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${ZYPPER[@]}" "$mode" --dry-run || rc=$?
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 100 ]; then
      step_fail "zypper $mode --dry-run failed ($(rc_note "$rc"))"
      return 0
    fi
    count=$(zypper_count "$log")
    detail_show "package(s)" zypper_changes "$log"
    if grep -q 'Nothing to do' "$log"; then
      step_dry "no updates available"
    else
      step_dry "$count package(s) would be upgraded/installed"
    fi
    return 0
  fi

  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${ZYPPER[@]}" "$mode" || rc=$?
  if [ "$rc" -eq 103 ]; then
    # zypper itself was updated; run once more.
    log_info "zypper was updated; running $mode again"
    rc=0
    SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_capture "$log" run_root "${ZYPPER[@]}" "$mode" || rc=$?
  fi
  case "$rc" in
    0|102) ;;
    *) step_fail "zypper $mode failed ($(rc_note "$rc"))"; return 0 ;;
  esac
  count=$(zypper_count "$log")
  if grep -q 'Nothing to do' "$log" && [ "$count" = 0 ]; then
    step_ok "no updates available"
  else
    note="$count package(s) upgraded/installed"
    [ "$rc" = 102 ] && note="$note; reboot required"
    step_updated "$note"
  fi
}

pkg_zypper_install() {
  SU_RUN_TIMEOUT=$SU_PKG_TIMEOUT run_root "${ZYPPER[@]}" install "$@"
}

pkg_zypper_reboot_check() {
  local rc=0
  zypper needs-rebooting >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) return 1 ;;
    102) echo "zypper needs-rebooting reports a pending reboot"; return 0 ;;
    *) return 2 ;;
  esac
}
