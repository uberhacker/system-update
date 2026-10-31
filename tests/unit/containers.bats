#!/usr/bin/env bats
# Containers (opt-in): distrobox upgrade --all, the package manager inside
# each toolbox, podman auto-update, re-pull of images used by existing
# containers (pull only: never recreate or restart).

load ../test_helper

setup() {
  SU_OUT=1
  load_su
  bindir="$BATS_TEST_TMPDIR/bin"; state="$BATS_TEST_TMPDIR/state"
  mkdir -p "$bindir" "$state"
  export PATH="$bindir:$PATH"
  export SU_PROBE_TIMEOUT=5
  export SU_TIMEOUT=20
  SU_USER_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$SU_USER_HOME"
  SU_PKG=apt
  SU_DRY_RUN=0
  SU_CFG[CONTAINERS]=1
  STEP_RESULT=""; STEP_NOTE=""
  LOG="$BATS_TEST_TMPDIR/calls.log"; : > "$LOG"
  printf 'docker.io/library/alpine:3.20\nlocalhost/mybuild:latest\nghcr.io/foo/bar:1.2\nsha256:0123456789abcdef\n' > "$state/podman_ps"
  printf 'nginx:1.27\n' > "$state/docker_ps"
  echo 'container-web.service' > "$state/units"
  # Images that have a newer version on the registry.
  printf 'docker.io/library/alpine:3.20\nnginx:1.27\n' > "$state/newer"
  # One fake for both engines: image ids live in state, pull moves them for
  # the images listed in state/newer.
  engine_body="
me=\$(basename \"\$0\")
echo \"\$me \$*\" >> '$LOG'
idfile() { printf '%s/id_%s_%s' '$state' \"\$me\" \"\$(printf '%s' \"\$1\" | tr '/:' '__')\"; }
case \"\$*\" in
  'ps -q') [ -e '$state/docker_down' ] && [ \"\$me\" = docker ] && { echo 'Cannot connect to the Docker daemon' >&2; exit 1; } ;;
  'ps -a --format {{.Image}}') cat \"$state/\${me}_ps\" ;;
  'image inspect --format {{.Id}} '*) f=\$(idfile \"\${@: -1}\"); [ -f \"\$f\" ] && cat \"\$f\" || echo sha256:old ;;
  'pull -q '*) [ -e '$state/pull_fail' ] && exit 125
      if grep -qx -- \"\$3\" '$state/newer'; then echo sha256:new > \"\$(idfile \"\$3\")\"; fi ;;
  'auto-update --dry-run --format {{.Unit}}') cat '$state/units' ;;
  'auto-update') [ -e '$state/autoupdate_fail' ] && exit 1 ;;
esac
exit 0"
  make_fake_bin "$bindir" podman "$engine_body"
  make_fake_bin "$bindir" docker "$engine_body"
  make_fake_bin "$bindir" distrobox "
echo \"distrobox \$*\" >> '$LOG'
case \"\$*\" in
  'list --no-color') [ -e '$state/no_distrobox' ] || printf 'ID           | NAME        | STATUS | IMAGE\\nabc123       | ubuntu-box  | Up     | ubuntu:24.04\\n' ;;
  'upgrade --all') [ -e '$state/distrobox_fail' ] && exit 1 ;;
esac
exit 0"
  make_fake_bin "$bindir" toolbox "
echo \"toolbox \$*\" >> '$LOG'
case \"\$1 \$2\" in
  'list -c') printf 'CONTAINER ID  CONTAINER NAME     CREATED      STATUS   IMAGE NAME\\nabc123def456  fedora-toolbox-40  2 weeks ago  running  registry.fedoraproject.org/fedora-toolbox:40\\n' ;;
  'run -c') [ -e '$state/toolbox_fail' ] && exit 1; echo \"toolbox-upgrade \$3\" >> '$LOG' ;;
esac
exit 0"
  tools_discover
}

@test "detects every container tool that is present" {
  assert_equal "distrobox,toolbox,podman,docker" "${SU_TOOL_BIN[containers]}"
}

@test "off by default: nothing runs" {
  SU_CFG[CONTAINERS]=0
  tool_containers_update
  assert_equal skipped "$STEP_RESULT"
  assert_equal "off by default; enable with --containers or CONTAINERS=1" "$STEP_NOTE"
  ! grep -q . "$LOG"
}

@test "dry run lists and pulls nothing" {
  SU_DRY_RUN=1
  tool_containers_update
  assert_equal dry-run "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "distrobox: would upgrade 1 container(s)"
  assert_contains "$STEP_NOTE" "toolbox: would upgrade 1 container(s)"
  assert_contains "$STEP_NOTE" "podman: 1 auto-update unit(s) would be checked"
  assert_contains "$STEP_NOTE" "podman: would re-pull 2 image(s)"
  assert_contains "$STEP_NOTE" "docker: would re-pull 1 image(s)"
  ! grep -qE 'pull|upgrade --all|run -c|^podman auto-update$' "$LOG"
}

@test "upgrades containers, runs auto-update and re-pulls registry images only" {
  tool_containers_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "distrobox: 1 container(s) upgraded"
  assert_contains "$STEP_NOTE" "toolbox: 1 container(s) upgraded"
  assert_contains "$STEP_NOTE" "podman auto-update: 1 unit(s) checked"
  assert_contains "$STEP_NOTE" "podman: 1 of 2 image(s) got a newer version"
  assert_contains "$STEP_NOTE" "docker: 1 of 1 image(s) got a newer version"
  grep -qx 'distrobox upgrade --all' "$LOG"
  grep -qx 'toolbox-upgrade fedora-toolbox-40' "$LOG"
  grep -qx 'podman auto-update' "$LOG"
  grep -qx 'podman pull -q docker.io/library/alpine:3.20' "$LOG"
  grep -qx 'podman pull -q ghcr.io/foo/bar:1.2' "$LOG"
  grep -qx 'docker pull -q nginx:1.27' "$LOG"
  ! grep -q 'pull -q localhost/' "$LOG"
  ! grep -q 'pull -q sha256:' "$LOG"
  # Never recreate, restart or remove anything.
  ! grep -qE ' (restart|rm|rmi|create|run |stop|start|compose|up) ' "$LOG"
}

@test "the toolbox upgrade picks the package manager inside the container" {
  tool_containers_update
  grep -q 'toolbox run -c fedora-toolbox-40 sh -c if command -v dnf5' "$LOG"
  grep -q 'apt-get -y -q dist-upgrade' "$LOG"
}

@test "nothing newer anywhere is ok" {
  : > "$state/newer"
  tool_containers_update
  assert_equal updated "$STEP_RESULT"     # distrobox/toolbox upgrades count as changes
  assert_contains "$STEP_NOTE" "podman: 0 of 2 image(s) got a newer version"
  touch "$state/no_distrobox"
  rm "$bindir/toolbox"
  tools_discover
  STEP_RESULT=""; STEP_NOTE=""
  tool_containers_update
  assert_equal ok "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "distrobox: no containers"
}

@test "a docker daemon that is not reachable is noted, not a failure" {
  touch "$state/docker_down"
  tool_containers_update
  assert_equal updated "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "docker: daemon not reachable as $SU_USER"
  ! grep -q '^docker pull' "$LOG"
}

@test "a failed pull is a failure with the count" {
  touch "$state/pull_fail"
  tool_containers_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "2 pull(s) failed"
}

@test "a failed distrobox upgrade is a failure" {
  touch "$state/distrobox_fail"
  tool_containers_update
  assert_equal failed "$STEP_RESULT"
  assert_contains "$STEP_NOTE" "distrobox upgrade --all failed"
}
