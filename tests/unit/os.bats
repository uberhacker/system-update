#!/usr/bin/env bats
# Distro / package manager detection from os-release fixtures.

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  export SU_PKG_FALLBACK=0
  export SU_OSTREE_MARKER="$BATS_TEST_TMPDIR/no-such-marker"
}

detect() {
  SU_OS_RELEASE="$(fixture "os-release/$1.txt")" os_detect
}

@test "fedora -> dnf" { detect fedora; assert_equal dnf "$SU_PKG"; assert_equal fedora "$SU_OS_ID"; }
@test "rhel -> dnf" { detect rhel; assert_equal dnf "$SU_PKG"; }
@test "rocky -> dnf via ID_LIKE" { detect rocky; assert_equal dnf "$SU_PKG"; assert_equal "rhel centos fedora" "$SU_OS_ID_LIKE"; }
@test "almalinux -> dnf" { detect almalinux; assert_equal dnf "$SU_PKG"; }
@test "centos stream -> dnf" { detect centos-stream; assert_equal dnf "$SU_PKG"; }
@test "ubuntu -> apt" { detect ubuntu; assert_equal apt "$SU_PKG"; }
@test "debian -> apt" { detect debian; assert_equal apt "$SU_PKG"; }
@test "mint -> apt via ID_LIKE" { detect mint; assert_equal apt "$SU_PKG"; }
@test "pop -> apt" { detect pop; assert_equal apt "$SU_PKG"; }
@test "arch -> pacman" { detect arch; assert_equal pacman "$SU_PKG"; }
@test "manjaro -> pacman" { detect manjaro; assert_equal pacman "$SU_PKG"; }
@test "endeavouros -> pacman" { detect endeavouros; assert_equal pacman "$SU_PKG"; }
@test "tumbleweed -> zypper dup" { detect opensuse-tumbleweed; assert_equal zypper "$SU_PKG"; assert_equal dup "$SU_ZYPPER_MODE"; }
@test "leap -> zypper update" { detect opensuse-leap; assert_equal zypper "$SU_PKG"; assert_equal update "$SU_ZYPPER_MODE"; }
@test "alpine -> apk" { detect alpine; assert_equal apk "$SU_PKG"; }
@test "void -> xbps" { detect void; assert_equal xbps "$SU_PKG"; }
@test "gentoo -> emerge" { detect gentoo; assert_equal emerge "$SU_PKG"; }
@test "nixos -> nix" { detect nixos; assert_equal nix "$SU_PKG"; }
@test "silverblue -> rpm-ostree (VARIANT_ID), never dnf" { detect silverblue; assert_equal rpm-ostree "$SU_PKG"; }
@test "bazzite -> rpm-ostree" { detect bazzite; assert_equal rpm-ostree "$SU_PKG"; }

@test "ostree marker file forces rpm-ostree on fedora" {
  touch "$SU_OSTREE_MARKER"
  detect fedora
  assert_equal rpm-ostree "$SU_PKG"
}

@test "unknown distro -> unknown without fallback" {
  detect unknown
  assert_equal unknown "$SU_PKG"
  assert_equal "Mystery OS 1.0" "$SU_OS_PRETTY"
}

@test "unknown distro falls back to a package manager binary when allowed" {
  SU_PKG_FALLBACK=1 detect unknown
  # The host has some manager; it must not be "unknown" here.
  [ "$SU_PKG" != unknown ]
}

@test "hostile os-release is never executed" {
  rm -f /tmp/pwned
  detect hostile
  [ ! -e /tmp/pwned ]
  assert_equal apt "$SU_PKG"   # via ID_LIKE=debian
  assert_contains "$SU_OS_ID" "rm -rf"   # kept as inert text
}

@test "missing os-release file is tolerated" {
  SU_OS_RELEASE=/nonexistent os_detect
  assert_equal unknown "$SU_PKG"
}

@test "os_pkg_from_ids is a pure mapping" {
  assert_equal apt "$(os_pkg_from_ids raspbian '')"
  assert_equal dnf "$(os_pkg_from_ids nobara 'fedora')"
  assert_equal zypper "$(os_pkg_from_ids sles '')"
  assert_equal pacman "$(os_pkg_from_ids garuda 'arch')"
  assert_equal apk "$(os_pkg_from_ids postmarketos 'alpine')"
  run os_pkg_from_ids weird ''
  assert_equal 1 "$status"
  assert_equal unknown "$output"
}

@test "os_describe mentions the manager" {
  detect opensuse-tumbleweed
  run os_describe
  assert_contains "$output" "package manager: zypper (dup)"
}
