#!/usr/bin/env bash
# lib/core/json.sh - tiny JSON field access.
#
# jq is used when available. Without it, a conservative grep/sed extractor
# returns the first string/number/bool value for a given key. That is enough
# for the GitHub API fields we read (tag_name, name, object.sha, ...). jq is
# never required; it may be installed with INSTALL_JQ=1 / --install-jq.
#
# Test hook: SU_FORCE_NO_JQ=1 forces the fallback extractor.

json_has_jq() {
  [ "${SU_FORCE_NO_JQ:-0}" = 1 ] && return 1
  has_cmd jq
}

# json_unescape STRING: undo the common JSON escapes in a string value.
json_unescape() {
  local s="$1"
  s="${s//\\\"/\"}"
  s="${s//\\\//\/}"
  s="${s//\\n/$'\n'}"
  s="${s//\\t/$'\t'}"
  s="${s//\\\\/\\}"
  printf '%s\n' "$s"
}

# json_get_raw KEY FILE: fallback extractor (first occurrence of "KEY": value).
json_get_raw() {
  local key="$1" file="$2" match value
  # Match "key" : "string" | number | true | false | null
  match=$(grep -o -E -m1 "\"${key}\"[[:space:]]*:[[:space:]]*(\"([^\"\\\\]|\\\\.)*\"|-?[0-9.eE+-]+|true|false|null)" "$file" 2>/dev/null | head -n1)
  [ -n "$match" ] || return 1
  value="${match#*:}"
  value="${value#"${value%%[![:space:]]*}"}"
  case "$value" in
    null) return 1 ;;
    \"*\") value="${value#\"}"; value="${value%\"}"; json_unescape "$value" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

# json_narrow KEY FILE OUTFILE: fallback helper; write the body of the
# (non-nested) object stored under KEY into OUTFILE. Good enough for the
# small sub-objects we read ("object": {...}).
json_narrow() {
  local key="$1" file="$2" out="$3"
  grep -o -E -m1 "\"${key}\"[[:space:]]*:[[:space:]]*\{[^{}]*\}" "$file" 2>/dev/null | head -n1 > "$out"
  [ -s "$out" ]
}

# json_get PATH FILE: PATH is a jq-style path such as .tag_name or .object.sha.
# Prints the value; returns 1 when the field is missing or null.
json_get() {
  local path="$1" file="$2" value key seg src tmp
  [ -s "$file" ] || return 1
  [[ "$path" == .* ]] || path=".$path"
  if json_has_jq; then
    value=$(jq -r "$path // empty" "$file" 2>/dev/null) || return 1
  else
    # Walk the intermediate segments to scope the search, then take the key.
    src="$file"
    tmp=""
    path="${path#.}"
    while [[ "$path" == *.* ]]; do
      seg="${path%%.*}"; path="${path#*.}"
      [ -n "$seg" ] || continue
      [[ "$seg" == *\[* ]] && { seg="${seg%%\[*}"; }
      tmp=$(mktemp "${TMPDIR:-/tmp}/su-json.XXXXXX") || return 1
      if ! json_narrow "$seg" "$src" "$tmp"; then
        rm -f -- "$tmp"; return 1
      fi
      [ "$src" != "$file" ] && rm -f -- "$src"
      src="$tmp"
    done
    key="${path##*.}"
    local rc=0
    value=$(json_get_raw "$key" "$src") || rc=$?
    [ "$src" != "$file" ] && rm -f -- "$src"
    [ "$rc" -eq 0 ] || return 1
  fi
  [ -n "$value" ] || return 1
  [ "$value" != null ] || return 1
  printf '%s\n' "$value"
}

# json_array_field PATH FILE: print every value of a field inside a top-level
# array, one per line (e.g. .[].name for the tags endpoint).
json_array_field() {
  local path="$1" file="$2" key
  [ -s "$file" ] || return 1
  if json_has_jq; then
    jq -r "${path} // empty" "$file" 2>/dev/null
  else
    key="${path##*.}"
    grep -o -E "\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" "$file" 2>/dev/null \
      | sed -E 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//; s/"$//'
  fi
}

# json_ensure_jq: optionally install jq (real runs only, with consent).
json_ensure_jq() {
  json_has_jq && return 0
  if [ "$SU_DRY_RUN" = 1 ]; then
    log_detail "jq not found; using the built-in JSON extractor"
    return 1
  fi
  if cfg_bool INSTALL_JQ && declare -F pkg_install >/dev/null; then
    log_info "jq not found; installing it with $SU_PKG (INSTALL_JQ=1)"
    pkg_install jq || log_warn "could not install jq; using the built-in JSON extractor"
  else
    log_detail "jq not found; using the built-in JSON extractor (set INSTALL_JQ=1 to install it)"
  fi
  json_has_jq
}
