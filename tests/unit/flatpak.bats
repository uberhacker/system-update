#!/usr/bin/env bats
# flatpak: snapshot of active commits around `flatpak update`, the undo file,
# --undo-flatpak (roll back + mask), and the note for runtimes that update
# without their apps (how the Tor Browser launcher broke).

load ../test_helper

C1=1111111111111111111111111111111111111111111111111111111111111111
C2=2222222222222222222222222222222222222222222222222222222222222222
A1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"; state="$BATS_TEST_TMPDIR/state"
  mkdir -p "$bindir" "$state"
  export PATH="$bindir:$PATH"
  export SU_TIMEOUT=20 SU_PKG_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  export FLATPAK_UNDO_FILE="$BATS_TEST_TMPDIR/undo/flatpak-undo.tsv"
  SU_DRY_RUN=0 SU_DETAILED=0
  STEP_RESULT=""; STEP_NOTE=""
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  # Root commands run directly, as whoever runs the tests (CI is not root,
  # and sudo's secure_path would not find the fake flatpak).
  run_root() { "$@"; }
  sudo_available() { return 0; }
  sudo_prime() { return 0; }
  # Fake flatpak with a system installation only. The KDE runtime has an
  # update; the Tor launcher app that uses it has none. `update` moves the
  # runtime to C2 unless state/update_fail exists.
  echo "$C1" > "$state/kde"
  printf 'flathub\thttps://dl.flathub.org/repo/\n' > "$state/remotes_system"
  : > "$state/remotes_user"
  : > "$state/masks"
  make_fake_bin "$bindir" flatpak "
echo \"flatpak \$*\" >> '$CALLS'
scope=system; for a in \"\$@\"; do [ \"\$a\" = --user ] && scope=user; done
case \"\$1\" in
  remotes) cat '$state/remotes_'\$scope ;;
  mask)
    if [ \"\$#\" -le 2 ]; then cat '$state/masks'; else echo \"\${@: -1}\" >> '$state/masks'; fi ;;
  remote-ls)
    [ \$scope = system ] || exit 0
    case \"\$*\" in
      *version*) printf 'runtime/org.kde.Platform/x86_64/6.11\t\n' ;;
      *) echo runtime/org.kde.Platform/x86_64/6.11 ;;
    esac ;;
  list)
    [ \$scope = system ] || exit 0
    case \"\$*\" in
      *--app*runtime*) printf 'org.torproject.torbrowser-launcher/x86_64/stable\torg.kde.Platform/x86_64/6.11\n' ;;
      *--app*) echo org.torproject.torbrowser-launcher/x86_64/stable ;;
      *--runtime*) echo org.kde.Platform/x86_64/6.11 ;;
      *) printf 'org.torproject.torbrowser-launcher/x86_64/stable\t0.4.0\norg.kde.Platform/x86_64/6.11\t\n' ;;
    esac ;;
  info)
    case \"\$*\" in
      *app/org.torproject*) echo $A1 ;;
      *runtime/org.kde.Platform*) cat '$state/kde' ;;
      *) exit 1 ;;
    esac ;;
  update)
    case \"\$*\" in
      *--commit=*) c=\"\$*\"; c=\"\${c##*--commit=}\"; echo \"\${c%% *}\" > '$state/kde'; echo 'Updating to the requested commit' ;;
      *) [ -e '$state/update_fail' ] && { echo 'error: network'; exit 1; }
         echo \"$C2\" > '$state/kde'; echo ' 1. org.kde.Platform 6.11 u flathub'; echo 'Changes complete.' ;;
    esac ;;
esac"
}

@test "short ref: arch dropped, kind prefix ignored" {
  assert_equal "org.kde.Platform//6.11" "$(flatpak_short_ref runtime/org.kde.Platform/x86_64/6.11)"
  assert_equal "org.gimp.GIMP//stable" "$(flatpak_short_ref org.gimp.GIMP/aarch64/stable)"
}

@test "snapshot lists apps and runtimes with their full active commit" {
  run flatpak_snapshot --system
  assert_equal "app/org.torproject.torbrowser-launcher/x86_64/stable	$A1" "${lines[0]}"
  assert_equal "runtime/org.kde.Platform/x86_64/6.11	$C1" "${lines[1]}"
  grep -q -- 'info --system --show-commit runtime/org.kde.Platform/x86_64/6.11' "$CALLS"
}

@test "diff: only refs whose commit changed; new and removed refs left out" {
  b="$BATS_TEST_TMPDIR/b"; a="$BATS_TEST_TMPDIR/a"
  printf 'app/x.A/x86_64/stable\t%s\nruntime/x.R/x86_64/1\t%s\napp/x.Gone/x86_64/stable\t%s\n' "$A1" "$C1" "$C1" > "$b"
  printf 'app/x.A/x86_64/stable\t%s\nruntime/x.R/x86_64/1\t%s\nruntime/x.New/x86_64/2\t%s\n' "$A1" "$C2" "$C2" > "$a"
  run flatpak_diff_snapshots --user "$b" "$a"
  assert_equal 1 "${#lines[@]}"
  assert_equal "user	runtime/x.R/x86_64/1	$C1	$C2" "$output"
}

@test "a runtime that updates without its app is named with the app" {
  run flatpak_runtime_only_updates --system
  assert_equal "org.kde.Platform//6.11|org.torproject.torbrowser-launcher" "$output"
}

@test "a runtime whose app updates too is not named" {
  make_fake_bin "$bindir" flatpak '
case "$1" in
  remote-ls) printf "app/org.gimp.GIMP/x86_64/stable\nruntime/org.gnome.Platform/x86_64/48\n" ;;
  list) printf "org.gimp.GIMP/x86_64/stable\torg.gnome.Platform/x86_64/48\n" ;;
esac'
  run flatpak_runtime_only_updates --system
  assert_equal "" "$output"
}

@test "real run: updates, records the runtime's old commit, points to the undo" {
  flatpak_step
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "system: done"
  assert_contains "$STEP_NOTE" "1 changed, undo: system-update --undo-flatpak"
  grep -qx "system	runtime/org.kde.Platform/x86_64/6.11	$C1	$C2" "$FLATPAK_UNDO_FILE"
  grep -q -- 'update --system -y --noninteractive' "$CALLS"
}

@test "real run says which runtime updates without its app" {
  run flatpak_step
  assert_contains "$output" "org.kde.Platform//6.11 updates without its app(s) org.torproject.torbrowser-launcher"
}

@test "a failed update is a failure, and refs it did deploy are still recorded" {
  touch "$state/update_fail"
  # Simulate a partial deploy: the runtime moved before the failure.
  sed -i "s|\[ -e '$state/update_fail' \] && { echo 'error: network'; exit 1; }|[ -e '$state/update_fail' ] \&\& { echo $C2 > '$state/kde'; echo 'error: network'; exit 1; }|" "$bindir/flatpak"
  flatpak_step
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "system: failed"
  grep -q "runtime/org.kde.Platform/x86_64/6.11	$C1	$C2" "$FLATPAK_UNDO_FILE"
}

@test "nothing changed: ok, and the previous undo file is kept" {
  mkdir -p "$(dirname "$FLATPAK_UNDO_FILE")"; echo keep > "$FLATPAK_UNDO_FILE"
  echo "$C2" > "$state/kde"
  make_fake_bin "$bindir" flatpak "
case \"\$1\" in
  remotes) [ \"\$2\" = --system ] && echo flathub ;;
  list) case \"\$*\" in *--runtime*) echo org.kde.Platform/x86_64/6.11 ;; esac ;;
  info) echo $C2 ;;
  update) echo 'Looking for updates…'; echo 'Nothing to do.' ;;
esac"
  flatpak_step
  assert_equal ok "$STEP_RESULT"
  assert_equal keep "$(cat "$FLATPAK_UNDO_FILE")"
}

@test "dry run changes nothing and shows held patterns" {
  echo 'org.kde.Platform//6.11' > "$state/masks"
  SU_DRY_RUN=1
  flatpak_step
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "system: 0 update(s) available, held: org.kde.Platform//6.11"
  ! grep -q -- '^flatpak update' "$CALLS"
  [ ! -e "$FLATPAK_UNDO_FILE" ]
}

@test "detailed dry run names the runtime that updates without its app" {
  SU_DRY_RUN=1 SU_DETAILED=1
  run flatpak_step
  assert_contains "$output" "org.kde.Platform//6.11 updates without its app(s) org.torproject.torbrowser-launcher"
  assert_contains "$output" "1 system flatpak(s) would change"
}

@test "a masked runtime is not counted or named, and the hold is reported" {
  echo 'org.kde.*//6.11' > "$state/masks"
  SU_DRY_RUN=1 SU_DETAILED=1
  run flatpak_step
  [[ "$output" != *"updates without its app"* ]]
  flatpak_step
  assert_contains "$STEP_NOTE" "system: 0 update(s) available, held: org.kde.*//6.11"
}

@test "mask patterns: globs, and an id without a branch holds every branch" {
  flatpak_is_masked org.kde.Platform//6.11 'org.kde.*//6.11'
  flatpak_is_masked org.kde.Platform//6.11 org.kde.Platform
  ! flatpak_is_masked org.kde.Platform//6.11 'org.kde.Platform//6.10'
  ! flatpak_is_masked org.gnome.Platform//48 'org.kde.*'
}

@test "masks: header and empty answers are not patterns" {
  printf 'Masked patterns:\n  org.kde.Platform//6.11\n' > "$state/masks"
  run flatpak_masks --system
  assert_equal "org.kde.Platform//6.11" "$output"
  printf 'No masked patterns\n' > "$state/masks"
  run flatpak_masks --system
  assert_equal "" "$output"
}

@test "undo: rolls the runtime back to the recorded commit and masks it" {
  flatpak_step
  assert_equal "$C2" "$(cat "$state/kde")"
  run flatpak_undo_main
  assert_equal 0 "$status"
  assert_equal "$C1" "$(cat "$state/kde")"
  grep -q -- "update --system -y --noninteractive --commit=$C1 runtime/org.kde.Platform/x86_64/6.11" "$CALLS"
  grep -qx 'org.kde.Platform//6.11' "$state/masks"
  assert_contains "$output" "flatpak mask --system --remove org.kde.Platform//6.11"
}

@test "undo dry run only prints the commands" {
  flatpak_step
  : > "$CALLS"
  SU_DRY_RUN=1
  run flatpak_undo_main
  assert_equal 0 "$status"
  assert_contains "$output" "--commit=$C1 runtime/org.kde.Platform/x86_64/6.11"
  assert_contains "$output" "flatpak mask --system org.kde.Platform//6.11"
  assert_equal "" "$(cat "$CALLS")"
}

@test "undo without a record fails and says why" {
  run flatpak_undo_main
  assert_equal 1 "$status"
  assert_contains "$output" "no flatpak changes to undo"
}

@test "undo skips malformed lines instead of passing them to flatpak" {
  mkdir -p "$(dirname "$FLATPAK_UNDO_FILE")"
  printf 'system\truntime/org.kde.Platform/x86_64/6.11;rm -rf ~\t%s\t%s\nsystem\truntime/x.R/x86_64/1\tnot-a-commit\t%s\n' "$C1" "$C2" "$C2" > "$FLATPAK_UNDO_FILE"
  run flatpak_undo_main
  assert_contains "$output" "skipping a malformed line"
  ! grep -q -- '--commit' "$CALLS"
}

@test "user installation: undo runs as the user with --user" {
  mkdir -p "$(dirname "$FLATPAK_UNDO_FILE")"
  printf 'user\tapp/org.example.App/x86_64/stable\t%s\t%s\n' "$C1" "$C2" > "$FLATPAK_UNDO_FILE"
  run flatpak_undo_main
  assert_equal 0 "$status"
  grep -q -- "update --user -y --noninteractive --commit=$C1 app/org.example.App/x86_64/stable" "$CALLS"
  grep -q -- "mask --user org.example.App//stable" "$CALLS"
}

@test "--undo-flatpak is parsed and listed in --help" {
  run args_parse --undo-flatpak
  assert_equal 0 "$status"
  args_parse --undo-flatpak
  assert_equal 1 "$SU_ARG_UNDO_FLATPAK"
  run usage
  assert_contains "$output" "--undo-flatpak"
}
