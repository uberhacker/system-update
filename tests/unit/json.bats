#!/usr/bin/env bats
# JSON field extraction with jq and with the built-in fallback.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
}

@test "json_get top-level string (jq and fallback agree)" {
  if command -v jq >/dev/null; then
    assert_equal v2.29.1 "$(json_get .tag_name "$(fixture github/compose-latest.json)")"
  fi
  assert_equal v2.29.1 "$(SU_FORCE_NO_JQ=1 json_get .tag_name "$(fixture github/compose-latest.json)")"
}

@test "json_get nested path" {
  assert_equal abcdef1234567890abcdef1234567890abcdef12 "$(json_get .object.sha "$(fixture github/ref-lightweight.json)")"
  assert_equal commit "$(SU_FORCE_NO_JQ=1 json_get .object.type "$(fixture github/ref-lightweight.json)")"
}

@test "null and missing fields return 1" {
  run json_get .tag_name "$(fixture github/null-tag.json)"
  assert_equal 1 "$status"
  assert_equal "" "$output"
  SU_FORCE_NO_JQ=1 run json_get .tag_name "$(fixture github/null-tag.json)"
  assert_equal 1 "$status"
  run json_get .does_not_exist "$(fixture github/compose-latest.json)"
  assert_equal 1 "$status"
  SU_FORCE_NO_JQ=1 run json_get .does_not_exist "$(fixture github/compose-latest.json)"
  assert_equal 1 "$status"
}

@test "empty file returns 1" {
  : > "$BATS_TEST_TMPDIR/empty.json"
  run json_get .tag_name "$BATS_TEST_TMPDIR/empty.json"
  assert_equal 1 "$status"
}

@test "fallback handles escaped quotes" {
  printf '{"name": "say \\"hi\\" now", "n": 5, "b": true}\n' > "$BATS_TEST_TMPDIR/e.json"
  assert_equal 'say "hi" now' "$(SU_FORCE_NO_JQ=1 json_get .name "$BATS_TEST_TMPDIR/e.json")"
  assert_equal 5 "$(SU_FORCE_NO_JQ=1 json_get .n "$BATS_TEST_TMPDIR/e.json")"
  assert_equal true "$(SU_FORCE_NO_JQ=1 json_get .b "$BATS_TEST_TMPDIR/e.json")"
}

@test "json_array_field lists tag names" {
  run json_array_field '.[].name' "$(fixture github/tags.json)"
  assert_contains "$output" "v0.10.2"
  assert_contains "$output" "nightly"
  SU_FORCE_NO_JQ=1 run json_array_field '.[].name' "$(fixture github/tags.json)"
  assert_contains "$output" "v0.10.2"
  assert_equal 4 "${#lines[@]}"
}

@test "json_ensure_jq does not install in dry run" {
  SU_DRY_RUN=1 SU_FORCE_NO_JQ=1 run json_ensure_jq
  assert_equal 1 "$status"
}
