#!/usr/bin/env bats
# --detailed: the per-package "installed -> new" lists of a dry run.
# Fixtures in tests/fixtures/detail are real outputs captured from stock
# containers (apt, dnf, pacman, zypper) or written from the documented
# formats (apk, xbps, emerge, rpm-ostree, fwupd).

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_SYSTEM_CONFIG=/nonexistent
  export SU_CONFIG_FILE="$BATS_TEST_TMPDIR/empty.conf"; : > "$SU_CONFIG_FILE"
  export SU_PKG_FALLBACK=0
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  export PATH="$BIN:$PATH"
}

d() { fixture "detail/$1"; }

@test "--detailed implies --dry-run" {
  args_parse --detailed
  args_apply
  assert_equal 1 "$SU_DETAILED"
  assert_equal 1 "$SU_DRY_RUN"
  detail_enabled
}

@test "--dry-run alone is not detailed" {
  args_parse --dry-run
  args_apply
  assert_equal 0 "$SU_DETAILED"
  ! detail_enabled
}

@test "--help documents --detailed" {
  run usage
  assert_contains "$output" "--detailed"
}

@test "detail_print aligns rows and labels new, removed and rebuilt packages" {
  f="$BATS_TEST_TMPDIR/rows"
  printf '%s\n' 'zlib|1.0|1.1' 'newpkg||2.0' 'gone|3.0|' 'same|4.0|4.0' 'zlib|1.0|1.1' > "$f"
  SU_DRY_RUN=1 SU_DETAILED=1
  run detail_print "$f"
  assert_contains "$output" "4 package(s) would change:"
  assert_contains "$output" "gone    3.0   -> (removed)"
  assert_contains "$output" "newpkg  (new) -> 2.0"
  assert_contains "$output" "same    4.0   -> 4.0 (new build)"
  assert_contains "$output" "zlib    1.0   -> 1.1"
}

@test "detail_show does nothing without --detailed" {
  SU_DRY_RUN=1 SU_DETAILED=0
  run detail_show "package(s)" pacman_changes "$(d pacman-qu.txt)"
  assert_equal "" "$output"
}

@test "apt: Inst lines of apt-get -s" {
  run apt_changes "$(d apt-simulate.txt)"
  assert_equal 35 "${#lines[@]}"
  assert_contains "$output" "libc6|2.39-0ubuntu8.8|2.39-0ubuntu8.9"
  assert_contains "$output" "bsdutils|1:2.39.3-9ubuntu6.5|1:2.39.3-9ubuntu6.6"
}

@test "apt: new installs and removals" {
  f="$BATS_TEST_TMPDIR/apt"
  printf '%s\n' 'Inst linux-image-6.1.0-25-amd64 (6.1.106-3 Debian-Security:12/stable-security [amd64])' \
    'Remv libfoo1 [1.2-3]' 'Conf libc6 (2.36 Debian [amd64])' > "$f"
  run apt_changes "$f"
  assert_equal "linux-image-6.1.0-25-amd64||6.1.106-3" "${lines[0]}"
  assert_equal "libfoo1|1.2-3|" "${lines[1]}"
  assert_equal 2 "${#lines[@]}"
}

@test "dnf5: check-upgrade rows joined with the installed versions from rpm" {
  make_fake_bin "$BIN" rpm 'for a in "$@"; do case "$a" in curl.x86_64) printf "curl.x86_64\t8.11.1-4.fc44\n" ;; openssl-libs.x86_64) printf "openssl-libs.x86_64\t1:3.5.1-1.fc44\n" ;; -*|%*) ;; *) echo "package $a is not installed" ;; esac; done'
  run dnf_changes "$(d dnf5-check-upgrade.txt)"
  assert_equal 38 "${#lines[@]}"
  assert_contains "$output" "curl.x86_64|8.11.1-4.fc44|8.18.0-14.fc44"
  assert_contains "$output" "openssl-libs.x86_64|1:3.5.1-1.fc44|1:3.5.9-1.fc44"
  assert_contains "$output" "tar.x86_64|?|2:1.35-9.fc44"
  assert_not_contains "$output" "Upgrades"
}

@test "dnf4: a long name wrapped onto its own line is joined" {
  make_fake_bin "$BIN" rpm 'exit 0'
  run dnf_changes "$(d dnf4-check-update.txt)"
  assert_contains "$output" "bash.x86_64|?|5.1.8-9.el9"
  assert_contains "$output" "verylongpackagename-with-a-suffix.noarch|?|1.0-1.el9"
}

@test "pacman: checkupdates / pacman -Qu" {
  run pacman_changes "$(d pacman-qu.txt)"
  assert_equal "device-mapper|2.03.43-2|2.03.44-1" "${lines[0]}"
  assert_equal "gnupg|2.4.9-3|2.4.9-4" "${lines[1]}"
}

@test "zypper: Tumbleweed dup --details (wrapped columns)" {
  run zypper_changes "$(d zypper-dup-details.txt)"
  assert_equal 13 "${#lines[@]}"
  assert_contains "$output" "openSUSE-build-key|1.0-68.1|1.0-69.1"
  assert_contains "$output" "krb5||1.22.2-5.1"
  assert_contains "$output" "libcurl-mini4|8.23.0-2.1|"
}

@test "zypper: Leap update --details skips patterns and repo/vendor lines" {
  run zypper_changes "$(d zypper-update-details.txt)"
  assert_equal "patterns-base-fips|20241218-lp160.5.1|20241218+leap-lp160.1.1" "${lines[0]}"
  assert_equal 15 "${#lines[@]}"
  assert_not_contains "$output" "repo-oss"
  assert_not_contains "$output" "SUSE|"
  # The two patterns ("fips", "minimal_base") are not packages.
  assert_not_contains "$output"$'\n' $'\n'"fips|"
  assert_not_contains "$output"$'\n' $'\n'"minimal_base|"
}

@test "zypper: one-line rows from a wide terminal" {
  f="$BATS_TEST_TMPDIR/z"
  printf '%s\n' 'The following 2 packages are going to be upgraded:' \
    '  bash  5.2-1 -> 5.2-2  x86_64  repo-oss  openSUSE' '  vim  9.0-1 -> 9.1-1  x86_64  repo-oss  openSUSE' '' \
    'The following package is going to be REMOVED:' '  oldpkg  1.0-1  noarch  @System' > "$f"
  run zypper_changes "$f"
  assert_equal "bash|5.2-1|5.2-2" "${lines[0]}"
  assert_equal "vim|9.0-1|9.1-1" "${lines[1]}"
  assert_equal "oldpkg|1.0-1|" "${lines[2]}"
}

@test "apk: upgrade -s" {
  run apk_changes "$(d apk-upgrade-s.txt)"
  assert_equal "musl|1.2.4-r2|1.2.5-r0" "${lines[0]}"
  assert_equal "libfoo||1.0-r0" "${lines[1]}"
  assert_equal "busybox|1.36.1-r5|1.36.1-r6" "${lines[2]}"
  assert_equal 3 "${#lines[@]}"
}

@test "xbps: -Sun with installed versions from xbps-query" {
  make_fake_bin "$BIN" xbps-query '[ "$3" = bash ] && echo bash-5.2.21_1 || exit 2'
  run xbps_changes "$(d xbps-sun.txt)"
  assert_equal "bash|5.2.21_1|5.2.37_1" "${lines[0]}"
  assert_equal "newpkg||1.0_1" "${lines[1]}"
}

@test "emerge: --pretend upgrades, new packages and rebuilds" {
  run emerge_changes "$(d emerge-pretend.txt)"
  assert_equal "sys-libs/glibc|2.38-r10|2.39-r6" "${lines[0]}"
  assert_equal "app-misc/foo||1.0" "${lines[1]}"
  assert_equal "dev-lang/perl|5.40.0-r1|5.40.0-r1" "${lines[2]}"
  assert_equal "dev-libs/openssl|3.3.1|3.3.2_p1" "${lines[3]}"
}

@test "rpm-ostree: upgrade --preview diff" {
  run ostree_changes "$(d rpm-ostree-preview.txt)"
  assert_equal "bash|5.2.26-3.fc40|5.2.26-4.fc40" "${lines[0]}"
  assert_equal "NetworkManager|1:1.44.2-1.fc40|1:1.44.4-1.fc40" "${lines[1]}"
  assert_equal "foo|1.0-1.fc40|" "${lines[2]}"
  assert_equal "bar-baz||2.0-1.fc40" "${lines[3]}"
}

@test "fwupd: device current version and the offered release" {
  run fwupd_changes "$(d fwupd-get-updates.txt)"
  assert_equal "UEFI dbx|20260402|20260707" "$output"
}

@test "flatpak: remote-ls --updates joined with the installed versions" {
  make_fake_bin "$BIN" flatpak 'case "$1" in
  list) printf "org.gimp.GIMP/x86_64/stable\t3.0.4\norg.gnome.Platform/x86_64/48\t\n" ;;
  remote-ls) printf "app/org.gimp.GIMP/x86_64/stable\t3.0.6\nruntime/org.gnome.Platform/x86_64/48\t\n" ;;
esac'
  run flatpak_changes --system
  assert_equal "org.gimp.GIMP//stable|3.0.4|3.0.6" "${lines[0]}"
  assert_equal "org.gnome.Platform//48|?|(new build)" "${lines[1]}"
}

@test "snap: refresh --list joined with snap list" {
  make_fake_bin "$BIN" snap 'printf "Name Version Rev Tracking Publisher Notes\ncore22 20240111 1122 latest/stable canonical base\n"'
  f="$BATS_TEST_TMPDIR/s"
  printf '%s\n' 'Name    Version   Rev   Size   Publisher  Notes' 'core22  20240408  1380  77MB   canonical  base' > "$f"
  run snap_changes "$f"
  assert_equal "core22|20240111|20240408" "$output"
}

@test "tool_latest: an npm-installed tool is looked up by its package" {
  make_fake_bin "$BIN" npm '[ "$1" = view ] && echo 1.2.3'
  SU_DRY_RUN=1 SU_DETAILED=1
  TOOL_METHOD="npm:@openai/codex"
  run tool_latest '@openai/codex'
  assert_equal 1.2.3 "$output"
}

@test "tool_latest uses npm for a self-updating binary with a scoped npm name" {
  make_fake_bin "$BIN" npm '[ "$1" = view ] && [ "$2" = @anthropic-ai/claude-code ] && echo 2.1.314'
  TOOL_METHOD=unknown
  run tool_latest '@anthropic-ai/claude-code'
  assert_equal 2.1.314 "$output"
  run tool_latest ''
  assert_equal 1 "$status"
}

@test "composer: global outdated rows" {
  make_fake_bin "$BIN" composer 'printf "%s\n" "Direct dependencies required in composer.json:" "drush/drush 12.4.3 ! 13.3.3 Drush is a command line shell" "consolidation/cgr 2.0.5 = 2.0.5 Safer global installs"'
  run composer_outdated
  assert_equal "drush/drush|12.4.3|13.3.3" "$output"
}

@test "uv: tool list --outdated rows" {
  make_fake_bin "$BIN" uv 'printf "%s\n" "ruff v0.4.0 [latest: 0.5.0]" "- ruff" "zcmds v1.2.0 [latest: 1.3.1]"'
  SU_TOOL_BIN[uv]="$BIN/uv"
  run uv_outdated
  assert_equal "ruff|0.4.0|0.5.0" "${lines[0]}"
  assert_equal "zcmds|1.2.0|1.3.1" "${lines[1]}"
}
