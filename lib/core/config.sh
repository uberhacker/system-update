#!/usr/bin/env bash
# lib/core/config.sh - settings from config files, environment and flags.
#
# Precedence (lowest to highest):
#   built-in default < /etc/system-update.conf < user config < environment < flags
#
# Config files are simple KEY=value lines. They are parsed line by line and
# never sourced or eval'd, so a hostile value cannot run code. Unknown keys
# and malformed values are reported and ignored.

SU_DEFAULT_REPO="https://github.com/bradvrudney/system-update"

# Allowed keys with their default values and a validation class.
#   str      any printable text without control characters
#   bool     1/0/yes/no/true/false/on/off
#   int      non-negative integer
#   list     comma separated names [A-Za-z0-9_.-]
#   url      https:// URL (file:// only when SYSTEM_UPDATE_ALLOW_FILE_SOURCE=1)
#   color    auto|always|never
#   token    [A-Za-z0-9_.-]
#   name     a git ref name
#   path     an absolute path (no "..", no spaces or shell metacharacters)
declare -gA SU_CFG_DEFAULT=(
  [SELF_UPDATE_REPO]="$SU_DEFAULT_REPO"
  [SELF_UPDATE_BRANCH]=""
  [SKIP]=""
  [ONLY]=""
  [TIMEOUT]="300"
  [PROBE_TIMEOUT]="20"
  [GITHUB_TOKEN]=""
  [COLOR]="auto"
  [INSTALL_JQ]="0"
  [ALLOW_UNVERIFIED_INSTALLERS]="0"
  [FIRMWARE]="0"
  [PRUNE_NODE]="0"
  [AUR_HELPER]="0"
  [AUTOREMOVE]="1"
  # Opt-in steps (off by default); the flag of each is its key in lower case.
  [NVIM_PLUGINS]="0"
  [RUNTIMES]="0"
  [NPM_GLOBALS]="0"
  [GO_TOOLCHAIN]="0"
  [CONTAINERS]="0"
  [LOGGING]="1"
  [LOG_DIR]=""
  [LOG_KEEP]="10"
)
declare -gA SU_CFG_TYPE=(
  [SELF_UPDATE_REPO]=url
  [SELF_UPDATE_BRANCH]=name
  [SKIP]=list
  [ONLY]=list
  [TIMEOUT]=int
  [PROBE_TIMEOUT]=int
  [GITHUB_TOKEN]=token
  [COLOR]=color
  [INSTALL_JQ]=bool
  [ALLOW_UNVERIFIED_INSTALLERS]=bool
  [FIRMWARE]=bool
  [PRUNE_NODE]=bool
  [AUR_HELPER]=bool
  [AUTOREMOVE]=bool
  [NVIM_PLUGINS]=bool
  [RUNTIMES]=bool
  [NPM_GLOBALS]=bool
  [GO_TOOLCHAIN]=bool
  [CONTAINERS]=bool
  [LOGGING]=bool
  [LOG_DIR]=path
  [LOG_KEEP]=int
)
declare -gA SU_CFG=()        # effective values
declare -gA SU_CFG_SOURCE=() # where each value came from (for --list)

config_user_file() {
  printf '%s/system-update/config\n' "${XDG_CONFIG_HOME:-${SU_USER_HOME:-$HOME}/.config}"
}

# config_valid TYPE VALUE: validation per class.
config_valid() {
  local type="$1" value="$2"
  # No control characters anywhere.
  [[ "$value" =~ [[:cntrl:]] ]] && return 1
  case "$type" in
    str) return 0 ;;
    bool) [[ "${value,,}" =~ ^(1|0|yes|no|true|false|on|off|y|n)$ ]] ;;
    int) [[ "$value" =~ ^[0-9]{1,9}$ ]] ;;
    list) [[ "$value" =~ ^[A-Za-z0-9_.,[:space:]-]*$ ]] ;;
    url)
      if [[ "$value" =~ ^https://[A-Za-z0-9._~:/?#@!$\&\'()*+,\;=%-]+$ ]]; then
        return 0
      fi
      if [ "${SYSTEM_UPDATE_ALLOW_FILE_SOURCE:-0}" = 1 ] && [[ "$value" =~ ^file:///[A-Za-z0-9._/-]+$ ]]; then
        return 0
      fi
      return 1 ;;
    color) [[ "$value" =~ ^(auto|always|never)$ ]] ;;
    token) [[ "$value" =~ ^[A-Za-z0-9_.-]*$ ]] ;;
    name) [[ "$value" =~ ^[A-Za-z0-9_./-]*$ ]] && [[ "$value" != *..* ]] && [[ "$value" != -* ]] ;;
    path) [ -z "$value" ] || { [[ "$value" =~ ^/[A-Za-z0-9_.@+/-]*$ ]] && [[ "$value" != *..* ]]; } ;;
    *) return 1 ;;
  esac
}

# config_normalize TYPE VALUE: canonical form (bools become 1/0).
config_normalize() {
  local type="$1" value="$2"
  case "$type" in
    bool) if bool "$value"; then echo 1; else echo 0; fi ;;
    url) printf '%s\n' "${value%/}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

# config_set KEY VALUE SOURCE: validate and store.
config_set() {
  local key="$1" value="$2" src="$3" type
  type="${SU_CFG_TYPE[$key]:-}"
  if [ -z "$type" ]; then
    log_warn "config: unknown key '$key' ($src) ignored"
    return 1
  fi
  if ! config_valid "$type" "$value"; then
    log_warn "config: invalid value for $key ($src) ignored"
    return 1
  fi
  SU_CFG[$key]=$(config_normalize "$type" "$value")
  SU_CFG_SOURCE[$key]="$src"
  return 0
}

# config_parse_file FILE: read KEY=value lines.
config_parse_file() {
  local file="$1" line key value lineno=0
  [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # Trim surrounding whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    if ! [[ "$line" =~ ^([A-Z][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
      log_warn "config: $file:$lineno: not a KEY=value line, ignored"
      continue
    fi
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    # Strip one layer of matching quotes.
    if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    config_set "$key" "$value" "$file:$lineno" || true
  done < "$file"
}

# config_load: defaults, system file, user file, environment.
config_load() {
  local key
  for key in "${!SU_CFG_DEFAULT[@]}"; do
    SU_CFG[$key]="${SU_CFG_DEFAULT[$key]}"
    SU_CFG_SOURCE[$key]="default"
  done
  config_parse_file "${SU_SYSTEM_CONFIG:-/etc/system-update.conf}"
  if [ -n "${SU_CONFIG_FILE:-}" ]; then
    if [ -r "$SU_CONFIG_FILE" ]; then
      config_parse_file "$SU_CONFIG_FILE"
    else
      log_warn "config file not readable: $SU_CONFIG_FILE"
    fi
  else
    config_parse_file "$(config_user_file)"
  fi
  # Environment overrides. GH_TOKEN is accepted as an alias for GITHUB_TOKEN.
  for key in "${!SU_CFG_DEFAULT[@]}"; do
    if [ -n "${!key:-}" ]; then
      config_set "$key" "${!key}" "env" || true
    fi
  done
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
    config_set GITHUB_TOKEN "$GH_TOKEN" "env GH_TOKEN" || true
  fi
}

# cfg KEY: print the effective value.
cfg() { printf '%s\n' "${SU_CFG[$1]-}"; }

# cfg_bool KEY: true when the effective value is on.
cfg_bool() { bool "${SU_CFG[$1]-0}"; }
