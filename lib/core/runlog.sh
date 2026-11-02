#!/usr/bin/env bash
# lib/core/runlog.sh - the per-run log file.
#
# Every real or dry run writes a log (unless LOGGING=0 / --no-log): a header
# describing the run, then every line the program prints, the verbose-only
# lines (commands, details), and the output, exit status and duration of
# every command run through run_root/run_user. Lines are timestamped and
# colour-free (log.sh's _log_file does the writing). SU_LOG_FILE is the
# open log's path; empty means no log.
#
# Location: --log FILE, else LOG_DIR, else /var/log/system-update for root
# and ${XDG_STATE_HOME:-~/.local/state}/system-update for a user. Files are
# named system-update-YYYYmmdd-HHMMSS-PID.log, "latest.log" points at the
# newest, and only the newest LOG_KEEP (default 10, 0 = all) are kept.
# Logs are created 0600: they can show package lists, paths and hostnames.

SU_LOG_PATH="${SU_LOG_PATH:-}"   # --log FILE (also how a child process is told)

# runlog_default_dir: where logs go when LOG_DIR is not set.
runlog_default_dir() {
  if is_root; then
    printf '%s\n' /var/log/system-update
  else
    printf '%s/system-update\n' "${XDG_STATE_HOME:-$SU_USER_HOME/.local/state}"
  fi
}

# runlog_prune DIR KEEP: remove all but the newest KEEP logs in DIR. The
# names sort chronologically, so the glob order is oldest first.
runlog_prune() {
  local dir="$1" keep="$2" n i
  local -a logs=()
  [ "$keep" -gt 0 ] 2>/dev/null || return 0
  for i in "$dir"/system-update-*.log; do
    [ -f "$i" ] && logs+=("$i")
  done
  n=${#logs[@]}
  for ((i = 0; i < n - keep; i++)); do
    rm -f -- "${logs[i]}"
  done
}

# runlog_header ARGS...: what this run is (ARGS: the command line).
runlog_header() {
  local key
  [ -n "$SU_LOG_FILE" ] || return 0
  {
    printf '# %s\n' "$(version_string)"
    printf '# started  %(%Y-%m-%d %H:%M:%S %z)T\n' -1
    printf '# host     %s\n' "$(uname -n) ($(uname -sr) $(uname -m))"
    printf '# os       %s\n' "$(os_describe)"
    printf '# user     %s (uid %s)%s\n' "$SU_CUR_USER" "$SU_UID" \
      "$([ "$SU_USER" != "$SU_CUR_USER" ] && printf '; user tools as %s' "$SU_USER")"
    printf '# command  %s\n' "$SU_BIN${*:+ $*}"
    printf '# mode     %s\n' "$([ "$SU_DRY_RUN" = 1 ] && printf 'dry run' || printf 'real run')$([ "$SU_DETAILED" = 1 ] && printf ' (detailed)')"
    for key in $(printf '%s\n' "${!SU_CFG[@]}" | sort); do
      [ "${SU_CFG_SOURCE[$key]}" = default ] && continue
      if [ "$key" = GITHUB_TOKEN ]; then
        printf '# setting  %s=<set> (%s)\n' "$key" "${SU_CFG_SOURCE[$key]}"
      else
        printf '# setting  %s=%s (%s)\n' "$key" "${SU_CFG[$key]}" "${SU_CFG_SOURCE[$key]}"
      fi
    done
    printf '\n'
  } >> "$SU_LOG_FILE"
}

# runlog_open ARGS...: open the run log (ARGS: the command line, for the
# header). Never fatal: a log that cannot be written is a warning.
runlog_open() {
  local dir file
  if [ -n "$SU_LOG_PATH" ]; then
    file="$SU_LOG_PATH"
    dir=""
  else
    cfg_bool LOGGING || return 0
    dir=$(cfg LOG_DIR)
    [ -n "$dir" ] || dir=$(runlog_default_dir)
    if ! (umask 077; mkdir -p -- "$dir") 2>/dev/null; then
      log_warn "cannot create log directory $dir; this run is not logged (LOG_DIR or --no-log)"
      return 0
    fi
    file="$dir/system-update-$(printf '%(%Y%m%d-%H%M%S)T' -1)-$$.log"
  fi
  if ! (umask 077; : >> "$file") 2>/dev/null; then
    log_warn "cannot write log file $file; this run is not logged"
    return 0
  fi
  SU_LOG_FILE="$file"
  if [ "${SU_ARG_USER_TOOLS:-0}" = 1 ]; then
    printf '\n# user-level tools, running as %s\n' "$SU_CUR_USER" >> "$SU_LOG_FILE"
  else
    runlog_header "$@"
  fi
  if [ -n "$dir" ]; then
    ln -sfn -- "${file##*/}" "$dir/latest.log" 2>/dev/null || true
    runlog_prune "$dir" "$(cfg LOG_KEEP)"
  fi
}

# runlog_append FILE: copy a child process's log into this run's log.
runlog_append() {
  [ -n "$SU_LOG_FILE" ] && [ -s "$1" ] || return 0
  cat -- "$1" >> "$SU_LOG_FILE"
}

# runlog_close RC: final line with the exit status; no more is logged.
runlog_close() {
  [ -n "$SU_LOG_FILE" ] || return 0
  if [ "${SU_ARG_USER_TOOLS:-0}" = 1 ]; then
    printf '# end of user-level tools\n\n' >> "$SU_LOG_FILE"
  else
    printf '\n# finished %(%Y-%m-%d %H:%M:%S %z)T, exit status %s, %ss\n' -1 "$1" "$SECONDS" >> "$SU_LOG_FILE"
  fi
  SU_LOG_FILE=""
}
