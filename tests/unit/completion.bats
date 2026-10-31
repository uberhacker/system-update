#!/usr/bin/env bats
# Bash completion (completions/system-update.bash).

load ../test_helper

setup() {
  # shellcheck disable=SC1091
  source "$REPO_ROOT/completions/system-update.bash"
}

# comp WORD...: run the completion function as bash would for these words.
comp() {
  COMP_WORDS=("$@")
  COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
  COMPREPLY=()
  _system_update
  printf '%s\n' "${COMPREPLY[@]}"
}

@test "every option in --help is completed" {
  local opt out
  out=$(comp "$REPO_ROOT/system-update" --)
  for opt in $("$REPO_ROOT/system-update" --help | grep -oE '^ +(-[a-zA-Z], )?--[a-z-]+' | grep -oE -- '--[a-z-]+'); do
    grep -qx -- "$opt" <<< "$out" || { echo "missing: $opt"; return 1; }
  done
}

@test "--only completes every tool module and the system steps" {
  local out f
  out=$(comp "$REPO_ROOT/system-update" --only "")
  for f in "$REPO_ROOT"/lib/tools/*.sh; do
    f=$(basename "$f" .sh)
    grep -qx -- "$f" <<< "$out" || { echo "missing: $f"; return 1; }
  done
  grep -qx system <<< "$out"
  grep -qx reboot-check <<< "$out"
}

@test "--_steps output is clean even when the config has problems" {
  printf 'BOGUS_KEY=1\nnot a key=value line\n' > "$BATS_TEST_TMPDIR/bad.conf"
  SU_CONFIG_FILE="$BATS_TEST_TMPDIR/bad.conf" run "$REPO_ROOT/bin/system-update" --_steps
  assert_equal 0 "$status"
  assert_not_contains "$output" "config"
  grep -qx nvm <<< "$output"
  grep -qx extras <<< "$output"
  grep -qx pkg <<< "$output"
  SU_CONFIG_FILE="$BATS_TEST_TMPDIR/bad.conf" run "$REPO_ROOT/bin/system-update" --completion bash
  assert_equal 0 "$status"
  assert_not_contains "$output" "config:"
}

@test "the static fallback is offered when the command cannot be run" {
  run comp /nonexistent/system-update --only ""
  grep -qx system <<< "$output"
  grep -qx reboot-check <<< "$output"
  ! grep -qx nvm <<< "$output"
}

@test "comma lists complete the last item and drop the ones given" {
  run comp "$REPO_ROOT/system-update" --skip apt,flatpak,fl
  assert_equal "" "$output"
  run comp "$REPO_ROOT/system-update" --skip apt,do
  assert_equal "apt,docker-compose" "$output"
}

@test "--opt=value, split by COMP_WORDBREAKS or not" {
  run comp "$REPO_ROOT/system-update" --color = n
  assert_equal never "$output"
  run comp "$REPO_ROOT/system-update" --only=nod
  assert_equal "--only=nodebrew" "$output"
}
