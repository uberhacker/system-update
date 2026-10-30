#!/usr/bin/env bats
# GitHub API helper with a stubbed curl: ok, null, 404, rate limit, caching.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export CURL_STUB_DIR="$BATS_TEST_TMPDIR/api"
  export CURL_STUB_LOG="$BATS_TEST_TMPDIR/curl.log"
  export PATH="$STUBS:$PATH"
  export SU_GITHUB_API="https://api.github.test"
  mkdir -p "$CURL_STUB_DIR/repos/docker/compose/releases" \
           "$CURL_STUB_DIR/repos/docker/compose/git/ref/tags" \
           "$CURL_STUB_DIR/repos/example/null/releases" \
           "$CURL_STUB_DIR/repos/example/limited/releases" \
           "$CURL_STUB_DIR/repos/example/broken/releases" \
           "$CURL_STUB_DIR/repos/example/annotated/releases" \
           "$CURL_STUB_DIR/repos/example/annotated/git/ref/tags" \
           "$CURL_STUB_DIR/repos/example/annotated/git/tags" \
           "$CURL_STUB_DIR/repos/example/tags"
  cp "$(fixture github/compose-latest.json)" "$CURL_STUB_DIR/repos/docker/compose/releases/latest.json"
  cp "$(fixture github/ref-lightweight.json)" "$CURL_STUB_DIR/repos/docker/compose/git/ref/tags/v2.29.1.json"
  cp "$(fixture github/null-tag.json)" "$CURL_STUB_DIR/repos/example/null/releases/latest.json"
  echo "403 ratelimit" > "$CURL_STUB_DIR/repos/example/limited/releases/latest.status"
  echo "500" > "$CURL_STUB_DIR/repos/example/broken/releases/latest.status"
  cp "$(fixture github/annotated-latest.json)" "$CURL_STUB_DIR/repos/example/annotated/releases/latest.json"
  cp "$(fixture github/ref-annotated.json)" "$CURL_STUB_DIR/repos/example/annotated/git/ref/tags/v1.0.0.json"
  cp "$(fixture github/tag-object.json)" "$CURL_STUB_DIR/repos/example/annotated/git/tags/1111111111111111111111111111111111111111.json"
  cp "$(fixture github/tags.json)" "$CURL_STUB_DIR/repos/example/tags/tags.json"
  : > "$CURL_STUB_LOG"
  gh_init
}

calls() { grep -c . "$CURL_STUB_LOG" || true; }

@test "latest tag from a good response" {
  run gh_latest_tag docker/compose
  assert_equal 0 "$status"
  assert_equal v2.29.1 "$output"
}

@test "latest version strips the leading v" {
  assert_equal 2.29.1 "$(gh_latest_version docker/compose)"
}

@test "null tag_name is unknown, not an update" {
  run gh_latest_tag example/null
  assert_equal 1 "$status"
  assert_equal "" "$output"
}

@test "404 is unknown" {
  run gh_latest_tag example/missing
  assert_equal 1 "$status"
  assert_equal "" "$output"
}

@test "500 is unknown" {
  run gh_latest_tag example/broken
  assert_equal 1 "$status"
}

@test "rate limiting is detected once and later lookups are skipped" {
  out=$(gh_latest_tag example/limited 2>&1) || true
  assert_contains "$out" "rate limit reached"
  gh_rate_limited
  assert_equal 1 "$(calls)"
  run gh_latest_tag docker/compose
  assert_equal 1 "$status"
  assert_equal 1 "$(calls)"   # no second HTTP request
}

@test "latest release lookups are cached per run" {
  gh_latest_tag docker/compose >/dev/null
  gh_latest_name docker/compose >/dev/null
  gh_latest_version docker/compose >/dev/null
  assert_equal 1 "$(calls)"
  # A failed lookup is cached too.
  gh_latest_tag example/null >/dev/null || true
  gh_latest_tag example/null >/dev/null || true
  assert_equal 2 "$(calls)"
}

@test "release commit for a lightweight tag" {
  assert_equal abcdef1 "$(gh_release_commit docker/compose)"
}

@test "release commit dereferences an annotated tag on the same repo" {
  assert_equal 2222222 "$(gh_release_commit example/annotated)"
  grep -q 'repos/example/annotated/git/tags/1111111111111111111111111111111111111111' "$CURL_STUB_LOG"
  ! grep -q '{owner}' "$CURL_STUB_LOG"
}

@test "asset presence" {
  gh_release_has_asset docker/compose docker-compose-linux-x86_64
  ! gh_release_has_asset docker/compose docker-compose-linux-riscv64
  assert_equal "https://github.com/docker/compose/releases/download/v2.29.1/checksums.txt" \
    "$(gh_release_asset_url docker/compose v2.29.1 checksums.txt)"
}

@test "newest semver tag from the tags endpoint" {
  assert_equal v0.10.2 "$(gh_latest_semver_tag example/tags)"
}

@test "works without jq (fallback extractor)" {
  export SU_FORCE_NO_JQ=1
  assert_equal v2.29.1 "$(gh_latest_tag docker/compose)"
  assert_equal 2222222 "$(gh_release_commit example/annotated)"
  run gh_latest_tag example/null
  assert_equal 1 "$status"
}

@test "requests go to the configured API base with the version header" {
  gh_latest_tag docker/compose >/dev/null
  grep -q '^https://api.github.test/repos/docker/compose/releases/latest$' "$CURL_STUB_LOG"
}
