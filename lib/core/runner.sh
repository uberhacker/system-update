#!/usr/bin/env bash
# lib/core/runner.sh - step execution, result tracking and the summary.
#
# A step is a function. It reports its outcome by calling one of
#   step_ok NOTE | step_updated NOTE | step_skip NOTE | step_fail NOTE | step_dry NOTE
#   step_warn NOTE   (finished, but something needs the user's attention:
#                     a reboot, a package source that could not be refreshed)
# If it returns non-zero without reporting, the step is recorded as failed.
# There is deliberately no `set -e`: every step handles its own errors and a
# failing step never aborts the run.

SU_STEP_NAMES=()
SU_STEP_RESULTS=()
SU_STEP_NOTES=()
STEP_RESULT=""
STEP_NOTE=""
SU_ONLY="${SU_ONLY:-}"
SU_SKIP="${SU_SKIP:-}"

step_ok()      { STEP_RESULT=ok;      STEP_NOTE="${1:-}"; }
step_updated() { STEP_RESULT=updated; STEP_NOTE="${1:-}"; }
step_skip()    { STEP_RESULT=skipped; STEP_NOTE="${1:-}"; }
step_fail()    { STEP_RESULT=failed;  STEP_NOTE="${1:-}"; }
step_dry()     { STEP_RESULT=dry-run; STEP_NOTE="${1:-}"; }
step_warn()    { STEP_RESULT=warn;    STEP_NOTE="${1:-}"; }

# step_enabled GROUP NAME [ALIAS...]: honours --only/--skip.
step_enabled() {
  local group="$1" name="$2"; shift 2
  local x
  if [ -n "$SU_SKIP" ]; then
    for x in "$group" "$name" "$@"; do
      list_has "$SU_SKIP" "$x" && return 1
    done
  fi
  if [ -n "$SU_ONLY" ]; then
    for x in "$group" "$name" "$@"; do
      list_has "$SU_ONLY" "$x" && return 0
    done
    return 1
  fi
  return 0
}

# runner_record NAME RESULT NOTE
runner_record() {
  SU_STEP_NAMES+=("$1")
  SU_STEP_RESULTS+=("$2")
  SU_STEP_NOTES+=("$3")
  if [ -n "${SU_RESULTS_OUT:-}" ]; then
    printf '%s\t%s\t%s\n' "$1" "$2" "${3//$'\t'/ }" >> "$SU_RESULTS_OUT" 2>/dev/null || true
  fi
}

# runner_import_file FILE: results written by a child process.
runner_import_file() {
  local file="$1" name result note
  [ -r "$file" ] || return 0
  while IFS=$'\t' read -r name result note; do
    [ -n "$name" ] || continue
    case "$result" in
      ok|updated|skipped|failed|dry-run|warn) ;;
      *) result=failed; note="unrecognised result '$result'" ;;
    esac
    SU_STEP_NAMES+=("$name")
    SU_STEP_RESULTS+=("$result")
    SU_STEP_NOTES+=("$note")
  done < "$file"
}

# runner_print_result NAME RESULT NOTE: the one-line status after a step.
runner_print_result() {
  local name="$1" result="$2" note="$3"
  case "$result" in
    ok)      log_ok "$name: ${note:-up to date}" ;;
    updated) log_updated "$name: ${note:-updated}" ;;
    skipped) log_skipped "$name: ${note:-skipped}" ;;
    failed)  log_error "$name: ${note:-failed}" ;;
    dry-run) log_dry "$name: ${note:-dry run}" ;;
    warn)    log_warn "$name: ${note:-warning}" ;;
  esac
}

# run_step GROUP NAME FUNC [ARGS...]
run_step() {
  local group="$1" name="$2" func="$3"; shift 3
  local rc=0
  if ! step_enabled "$group" "$name"; then
    log_detail "skipping $name (--only/--skip)"
    return 0
  fi
  log_step "$name"
  STEP_RESULT=""; STEP_NOTE=""
  "$func" "$@" || rc=$?
  if [ -z "$STEP_RESULT" ]; then
    if [ "$rc" -eq 0 ]; then
      STEP_RESULT=ok
    else
      STEP_RESULT=failed
      STEP_NOTE="${STEP_NOTE:-$(rc_note "$rc")}"
    fi
  fi
  runner_record "$name" "$STEP_RESULT" "$STEP_NOTE"
  runner_print_result "$name" "$STEP_RESULT" "$STEP_NOTE"
  return 0
}

# ---------------------------------------------------------------------------
# Detailed dry run (--detailed)
# ---------------------------------------------------------------------------
# A step that can tell what would change writes one "name|installed|new" line
# per package to a file and hands it to detail_print. An empty installed
# version means "would be newly installed", an empty new version "would be
# removed", and "?" a version that could not be determined.

# detail_enabled: was --detailed given (it always comes with --dry-run)?
detail_enabled() { [ "${SU_DETAILED:-0}" = 1 ] && [ "$SU_DRY_RUN" = 1 ]; }

# detail_print FILE [WHAT]: sorted, aligned "name  installed -> new" rows.
# WHAT names the items in the heading (default "package(s)").
detail_print() {
  local file="$1" what="${2:-package(s)}" name old new w=0 ow=0 i n
  local -a names=() olds=() news=()
  [ -s "$file" ] || return 0
  while IFS='|' read -r name old new; do
    [ -n "$name" ] || continue
    [ -n "$old" ] || old="(new)"
    if [ -z "$new" ]; then
      new="(removed)"
    elif [ "$new" = "$old" ] && [ "$new" != "?" ]; then
      new="$new (new build)"
    fi
    names+=("$name"); olds+=("$old"); news+=("$new")
    [ ${#name} -gt $w ] && w=${#name}
    [ ${#old} -gt $ow ] && ow=${#old}
  done < <(sort -s -u -t'|' -k1,1 "$file")
  n=${#names[@]}
  [ "$n" -gt 0 ] || return 0
  log_dry "$n $what would change:"
  for ((i = 0; i < n; i++)); do
    log_change "$(printf '%-*s  %-*s -> %s' "$w" "${names[i]}" "$ow" "${olds[i]}" "${news[i]}")"
  done
}

# detail_show WHAT CMD [ARGS...]: with --detailed, run CMD (a producer of
# "name|installed|new" lines) and print what it found; otherwise do nothing.
detail_show() {
  local what="$1" out; shift
  detail_enabled || return 0
  out=$(tmp_file) || return 0
  "$@" > "$out" 2>/dev/null || true
  detail_print "$out" "$what"
}

# summary_counts: prints "ok updated skipped failed dry-run warn" counts.
summary_counts() {
  local r ok=0 up=0 sk=0 fa=0 dr=0 wa=0
  for r in "${SU_STEP_RESULTS[@]-}"; do
    case "$r" in
      ok) ok=$((ok + 1)) ;;
      updated) up=$((up + 1)) ;;
      skipped) sk=$((sk + 1)) ;;
      failed) fa=$((fa + 1)) ;;
      dry-run) dr=$((dr + 1)) ;;
      warn) wa=$((wa + 1)) ;;
    esac
  done
  printf '%s %s %s %s %s %s\n' "$ok" "$up" "$sk" "$fa" "$dr" "$wa"
}

# summary_print: table of every step; returns 1 when anything failed.
summary_print() {
  local i name result note icon color width=8 counts
  local n=${#SU_STEP_NAMES[@]}
  log_plain ""
  log_plain "${C_BOLD}Summary${C_RESET}${SU_DRY_RUN:+ }$([ "$SU_DRY_RUN" = 1 ] && printf '%s(dry run)%s' "$C_MAGENTA" "$C_RESET")"
  if [ "$n" -eq 0 ]; then
    log_plain "  (no steps were run)"
    return 0
  fi
  for ((i = 0; i < n; i++)); do
    [ ${#SU_STEP_NAMES[i]} -gt $width ] && width=${#SU_STEP_NAMES[i]}
  done
  for ((i = 0; i < n; i++)); do
    name="${SU_STEP_NAMES[i]}"; result="${SU_STEP_RESULTS[i]}"; note="${SU_STEP_NOTES[i]}"
    case "$result" in
      ok)      icon="$I_OK";      color="$C_GREEN" ;;
      updated) icon="$I_UPDATED"; color="$C_CYAN" ;;
      skipped) icon="$I_SKIPPED"; color="$C_DIM" ;;
      failed)  icon="$I_FAILED";  color="$C_RED" ;;
      dry-run) icon="$I_DRY";     color="$C_MAGENTA" ;;
      warn)    icon="$I_WARN";    color="$C_YELLOW" ;;
      *)       icon="?";          color="" ;;
    esac
    log_plain "$(printf '  %s%-2s %-8s%s %-*s %s' "$color" "$icon" "$result" "$C_RESET" "$width" "$name" "$note")"
  done
  read -r c_ok c_up c_sk c_fa c_dr c_wa <<< "$(summary_counts)"
  log_plain ""
  local totals="  $c_ok ok, $c_up updated, $c_sk skipped, $c_fa failed, $c_dr dry-run"
  [ "$c_wa" -gt 0 ] && totals+=", $c_wa warning(s)"
  log_plain "$totals"
  [ "$c_fa" -eq 0 ]
}
