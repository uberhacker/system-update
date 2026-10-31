#!/usr/bin/env bash
# lib/core/github.sh - GitHub REST API helper.
#
#  * one function does every request (gh_api) with curl -f, optional
#    GITHUB_TOKEN/GH_TOKEN auth and the recommended API headers;
#  * 403/429 with X-RateLimit-Remaining: 0 is recognised as rate limiting:
#    a warning is printed once and every later lookup is skipped quickly;
#  * null/empty answers are "unknown" (return 1) - callers must treat unknown
#    as "skip", never as "update needed";
#  * latest-release lookups are cached per run. The cache lives in a temp
#    directory (not in shell variables) because callers use $(...) subshells.
#
# Test hooks: SU_GITHUB_API overrides the base URL; curl is looked up on PATH
# so a stub can replace it.

: "${SU_GITHUB_API:=https://api.github.com}"
GH_RATE_LIMITED=0
GH_LAST_STATUS=""
GH_FILE=""

# gh_init: create the per-run cache directory (call once from the main shell).
gh_init() {
  if [ -z "${GH_CACHE_DIR:-}" ] || [ ! -d "$GH_CACHE_DIR" ]; then
    GH_CACHE_DIR=$(tmp_dir) || return 1
    export GH_CACHE_DIR
  fi
  return 0
}

gh_cache_dir() {
  gh_init || return 1
  printf '%s\n' "$GH_CACHE_DIR"
}

# gh_rate_limited: has this run hit the API rate limit?
gh_rate_limited() {
  [ "$GH_RATE_LIMITED" = 1 ] && return 0
  [ -n "${GH_CACHE_DIR:-}" ] && [ -e "$GH_CACHE_DIR/.ratelimited" ]
}

# gh_cache_key REPO: file-name safe form of owner/repo.
gh_cache_key() { printf '%s\n' "${1//[^A-Za-z0-9_.-]/_}"; }

# gh_api PATH OUTFILE: GET $SU_GITHUB_API/PATH into OUTFILE. Returns 0 on 2xx.
gh_api() {
  local path="$1" out="$2" hdr rc=0 token status dir
  dir=$(gh_cache_dir) || return 1
  if gh_rate_limited; then
    log_detail "GitHub API: skipping $path (rate limited)"
    return 1
  fi
  if ! has_cmd curl; then
    log_detail "GitHub API: curl is not installed; skipping $path"
    return 1
  fi
  hdr=$(mktemp "$dir/hdr.XXXXXX") || return 1
  token=$(cfg GITHUB_TOKEN 2>/dev/null || true)
  # The token goes to curl as a config file on stdin (-K -), never as an
  # argument: `ps` shows every process's arguments to every user. Its
  # characters are restricted by the config validator (token type), so the
  # quoted curl config line cannot be broken out of.
  local auth=""
  [ -n "$token" ] && auth="header = \"Authorization: Bearer $token\""
  log_cmd "curl -fsSL ${SU_GITHUB_API}/${path}"
  printf '%s\n' "$auth" | curl -fsSL --proto-redir '=https' --connect-timeout 20 --max-time 60 \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -K - \
    -D "$hdr" -o "$out" "${SU_GITHUB_API}/${path}" || rc=$?
  # Header lines end in CRLF; drop the CR before comparing. (No awk: some
  # minimal images do not ship it.)
  read -r _ status _ <<< "$(grep -i '^HTTP/' "$hdr" 2>/dev/null | tail -n1 | tr -d '\r')"
  GH_LAST_STATUS="${status:-}"
  if [ "$rc" -ne 0 ]; then
    case "$status" in
      403|429)
        if grep -qi '^x-ratelimit-remaining:[[:space:]]*0' "$hdr" 2>/dev/null || [ "$status" = 429 ]; then
          GH_RATE_LIMITED=1
          : > "$dir/.ratelimited"
          log_warn "GitHub API rate limit reached; version pre-checks are skipped for the rest of this run (set GITHUB_TOKEN to raise the limit)"
        else
          log_detail "GitHub API: $path returned HTTP $status"
        fi ;;
      404) log_detail "GitHub API: $path not found" ;;
      *) log_detail "GitHub API: request for $path failed (curl exit $rc${status:+, HTTP $status})" ;;
    esac
    rm -f -- "$out" "$hdr"
    return 1
  fi
  rm -f -- "$hdr"
  [ -s "$out" ] || return 1
  return 0
}

# gh_latest_release_file REPO: sets GH_FILE to the cached latest-release JSON.
gh_latest_release_file() {
  local repo="$1" dir key
  dir=$(gh_cache_dir) || return 1
  key=$(gh_cache_key "$repo")
  GH_FILE="$dir/$key.latest.json"
  [ -s "$GH_FILE" ] && return 0
  [ -e "$dir/$key.latest.missing" ] && return 1
  if gh_api "repos/${repo}/releases/latest" "$GH_FILE"; then
    return 0
  fi
  : > "$dir/$key.latest.missing"
  return 1
}

# gh_latest_field REPO FIELD: e.g. gh_latest_field docker/compose tag_name
gh_latest_field() {
  local repo="$1" field="$2" value
  gh_latest_release_file "$repo" || return 1
  value=$(json_get ".$field" "$GH_FILE") || return 1
  printf '%s\n' "$value"
}

# gh_latest_tag REPO: tag_name of the latest release ("unknown" => return 1).
gh_latest_tag() { gh_latest_field "$1" tag_name; }

# gh_latest_name REPO: release name (some projects use it as the version).
gh_latest_name() { gh_latest_field "$1" name; }

# gh_latest_version REPO: tag_name normalised (leading v stripped).
gh_latest_version() {
  local tag
  tag=$(gh_latest_tag "$1") || return 1
  version_norm "$tag"
}

# gh_release_has_asset REPO NAME: does the latest release publish asset NAME?
gh_release_has_asset() {
  local repo="$1" name="$2"
  gh_latest_release_file "$repo" || return 1
  grep -q "\"browser_download_url\"[[:space:]]*:[[:space:]]*\"[^\"]*/${name}\"" "$GH_FILE"
}

# gh_release_asset_url REPO TAG NAME: the fixed download URL for an asset.
gh_release_asset_url() {
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$1" "$2" "$3"
}

# gh_release_checksum REPO TAG ASSET: the sha256 a project publishes for
# ASSET of its latest release: a checksums file among the assets, an
# <asset>.sha256 asset, or a release-notes line naming the asset next to
# a 64-digit hash. Prints the hash; returns 1 when none is published.
gh_release_checksum() {
  local repo="$1" tag="$2" asset="$3" dir key file sum name body line
  dir=$(gh_cache_dir) || return 1
  key=$(gh_cache_key "$repo")
  for name in checksums.txt SHA256SUMS SHA256SUMS.txt sha256sums.txt checksums.sha256 "$asset.sha256" "$asset.sha256sum"; do
    gh_release_has_asset "$repo" "$name" || continue
    file="$dir/$key.$(gh_cache_key "$name")"
    if [ ! -s "$file" ]; then
      download "$(gh_release_asset_url "$repo" "$tag" "$name")" "$file" || continue
    fi
    sum=""
    case "$name" in
      "$asset".*) sum=$(head -n1 "$file"); sum="${sum%%[[:space:]]*}" ;;   # "<hash>  name" or a bare hash
      *) sum=$(checksum_for "$file" "$asset") || sum="" ;;
    esac
    if [[ "${sum,,}" =~ ^[0-9a-f]{64}$ ]]; then
      log_detail "checksum for $asset from release asset $name"
      printf '%s\n' "${sum,,}"
      return 0
    fi
  done
  gh_latest_release_file "$repo" || return 1
  body=$(json_get .body "$GH_FILE" 2>/dev/null) || return 1
  while IFS= read -r line; do
    [[ "$line" =~ (^|[^A-Za-z0-9._-])${asset//./\\.}([^A-Za-z0-9._-]|$) ]] || continue
    [[ "$line" =~ ([0-9a-fA-F]{64}) ]] || continue
    log_detail "checksum for $asset from the release notes"
    printf '%s\n' "${BASH_REMATCH[1],,}"
    return 0
  done <<< "$body"
  return 1
}

# gh_release_commit REPO: 7-character commit of the latest release tag.
# Handles both lightweight tags (object.type == commit) and annotated tags,
# which must be dereferenced through git/tags/<sha> on the same repo.
gh_release_commit() {
  local repo="$1" tag file sha type dir
  dir=$(gh_cache_dir) || return 1
  tag=$(gh_latest_tag "$repo") || return 1
  file="$dir/$(gh_cache_key "$repo").ref.json"
  gh_api "repos/${repo}/git/ref/tags/${tag}" "$file" || return 1
  sha=$(json_get .object.sha "$file") || return 1
  type=$(json_get .object.type "$file") || return 1
  if [ "$type" != commit ]; then
    gh_api "repos/${repo}/git/tags/${sha}" "$file" || return 1
    sha=$(json_get .object.sha "$file") || return 1
  fi
  [[ "$sha" =~ ^[0-9a-f]{7,40}$ ]] || return 1
  printf '%s\n' "${sha:0:7}"
}

# gh_latest_semver_tag REPO: newest tag that looks like a version, from the
# tags endpoint (for projects that do not publish GitHub releases).
gh_latest_semver_tag() {
  local repo="$1" file dir
  dir=$(gh_cache_dir) || return 1
  file="$dir/$(gh_cache_key "$repo").tags.json"
  gh_api "repos/${repo}/tags?per_page=100" "$file" || return 1
  json_array_field '.[].name' "$file" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 | grep .
}
