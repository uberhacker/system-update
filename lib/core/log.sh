#!/usr/bin/env bash
# lib/core/log.sh - colours, icons and logging.
#
# Output conventions:
#   * Everything the script itself says goes to the "console" file descriptor
#     (SU_OUT), which is a copy of the original stdout. This lets --quiet
#     silence third-party command output by redirecting fd 1 while our own
#     status lines, warnings and the final summary still reach the terminal.
#   * Colours are used only when stdout is a TTY, NO_COLOR is unset and
#     --no-color was not given (or COLOR=always forces them on).
#   * Icons are Unicode when the locale is UTF-8, plain ASCII otherwise.
#   * With a run log open (SU_LOG_FILE, see lib/core/runlog.sh) every line is
#     also appended there, timestamped and without colours, including what
#     --quiet hides and the verbose-only lines (commands, details). The log
#     is written by path, never through a kept-open descriptor: commands
#     this program runs would inherit such a descriptor (runuser passes
#     them on), and a package's scripts have no business holding our log.

: "${SU_VERBOSE:=0}"
: "${SU_QUIET:=0}"
: "${SU_COLOR:=auto}"   # auto|always|never
SU_USE_COLOR=0
SU_USE_UTF8=0

# Duplicate stdout once so later redirections of fd 1 do not hide our output.
if [ -z "${SU_OUT:-}" ]; then
  exec {SU_OUT}>&1
fi

# Decide whether colours should be used.
log_color_enabled() {
  case "${SU_COLOR}" in
    always) return 0 ;;
    never) return 1 ;;
  esac
  [ -n "${NO_COLOR:-}" ] && return 1
  [ "${TERM:-}" = "dumb" ] && return 1
  # -t tests the *console* fd, which mirrors the original stdout.
  [ -t "$SU_OUT" ] || return 1
  return 0
}

# Decide whether the locale can show the Unicode status icons.
log_utf8_enabled() {
  local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  case "${loc,,}" in
    *utf-8*|*utf8*) return 0 ;;
    *) return 1 ;;
  esac
}

# log_init: (re)compute colour/icon settings. Call after argument parsing.
log_init() {
  if log_color_enabled; then SU_USE_COLOR=1; else SU_USE_COLOR=0; fi
  if log_utf8_enabled; then SU_USE_UTF8=1; else SU_USE_UTF8=0; fi

  if [ "$SU_USE_COLOR" = 1 ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'
  else
    C_RESET=''; C_BOLD=''; C_DIM=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
  fi

  if [ "$SU_USE_UTF8" = 1 ]; then
    I_STEP='▶'; I_OK='✔'; I_UPDATED='↑'; I_SKIPPED='–'
    I_FAILED='✖'; I_WARN='⚠'; I_DRY='◦'; I_INFO='·'
  else
    I_STEP='>'; I_OK='OK'; I_UPDATED='UP'; I_SKIPPED='--'
    I_FAILED='XX'; I_WARN='!!'; I_DRY='..'; I_INFO='-'
  fi
}

SU_LOG_FILE="${SU_LOG_FILE:-}"

# _log_file TEXT: append TEXT to the run log, if one is open: a timestamp,
# then the text with colour escapes removed.
_log_file() {
  [ -n "$SU_LOG_FILE" ] || return 0
  local s="$*" esc=$'\033' re
  re="$esc"'\[[0-9;]*m'
  while [[ "$s" == *"$esc["* ]] && [[ "$s" =~ $re ]]; do
    s="${s//"${BASH_REMATCH[0]}"/}"
  done
  if [ -z "$s" ]; then
    printf '\n' >> "$SU_LOG_FILE"
  else
    printf '%(%H:%M:%S)T %s\n' -1 "$s" >> "$SU_LOG_FILE"
  fi
}

# Low level writers: the console fd and the run log.
_log_write() {
  printf '%s\n' "$*" >&"$SU_OUT"
  _log_file "$*"
}

# _log_quiet TEXT: the console unless --quiet; the run log always.
_log_quiet() {
  if [ "$SU_QUIET" = 1 ]; then _log_file "$*"; else _log_write "$*"; fi
}

# _log_verbose TEXT: the console only with --verbose; the run log always.
_log_verbose() {
  if [ "$SU_VERBOSE" = 1 ]; then _log_write "$*"; else _log_file "$*"; fi
}

log_step() {
  _log_quiet ""
  _log_quiet "${C_BOLD}${C_BLUE}${I_STEP}${C_RESET} ${C_BOLD}$*${C_RESET}"
}

log_info() {
  _log_quiet "  ${C_DIM}${I_INFO}${C_RESET} $*"
}

log_detail() {
  # Verbose-only chatter.
  _log_verbose "  ${C_DIM}  $*${C_RESET}"
}

log_warn() {
  _log_write "  ${C_YELLOW}${I_WARN} $*${C_RESET}"
}

log_error() {
  _log_write "  ${C_RED}${I_FAILED} $*${C_RESET}"
}

log_ok() {
  _log_quiet "  ${C_GREEN}${I_OK}${C_RESET} $*"
}

log_updated() {
  _log_quiet "  ${C_CYAN}${I_UPDATED}${C_RESET} $*"
}

log_skipped() {
  _log_quiet "  ${C_DIM}${I_SKIPPED} $*${C_RESET}"
}

log_dry() {
  _log_quiet "  ${C_MAGENTA}${I_DRY}${C_RESET} $*"
}

# log_change TEXT: one row of a --detailed change list (under a log_dry line).
log_change() {
  _log_quiet "      $*"
}

# log_cmd "cmd args": shown in verbose mode before a command runs (and
# always written to the run log).
log_cmd() {
  _log_verbose "  ${C_DIM}\$ $*${C_RESET}"
}

# log_plain: always printed (summary, --list, --version).
log_plain() {
  _log_write "$*"
}

# Initialise with defaults so the functions are usable before args parsing.
log_init
