#!/usr/bin/env bash
# lib/core/os.sh - distribution and package manager detection.
#
# Reads /etc/os-release (ID, ID_LIKE, VARIANT_ID, ...) and picks one of:
#   apt dnf zypper pacman apk xbps emerge nix rpm-ostree unknown
# Immutable rpm-ostree/bootc systems (Silverblue, Kinoite, Bazzite, ...) are
# detected before dnf so we never run dnf on them.
#
# Test hooks: SU_OS_RELEASE (file path), SU_OSTREE_MARKER (file path),
# SU_PKG_FALLBACK=0 disables the "look for a package manager binary" fallback.

SU_OS_ID=""
SU_OS_ID_LIKE=""
SU_OS_NAME=""
SU_OS_PRETTY=""
SU_OS_VERSION_ID=""
SU_OS_VARIANT_ID=""
SU_PKG="unknown"
SU_ZYPPER_MODE="update"   # dup on rolling openSUSE, update on Leap/SLE

# os_read_release FILE: parse KEY=value lines without sourcing the file.
os_read_release() {
  local file="$1" line key value
  [ -r "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    # Only keep printable characters; os-release values are simple strings.
    value="${value//[^[:print:]]/}"
    case "$key" in
      ID) SU_OS_ID="${value,,}" ;;
      ID_LIKE) SU_OS_ID_LIKE="${value,,}" ;;
      NAME) SU_OS_NAME="$value" ;;
      PRETTY_NAME) SU_OS_PRETTY="$value" ;;
      VERSION_ID) SU_OS_VERSION_ID="$value" ;;
      VARIANT_ID) SU_OS_VARIANT_ID="${value,,}" ;;
    esac
  done < "$file"
  return 0
}

# os_is_ostree: booted from an rpm-ostree/bootc deployment?
os_is_ostree() {
  [ -e "${SU_OSTREE_MARKER:-/run/ostree-booted}" ] && return 0
  case "$SU_OS_VARIANT_ID" in
    silverblue|kinoite|sericea|onyx|sway-atomic|budgie-atomic|cosmic-atomic|coreos|iot) return 0 ;;
  esac
  case "$SU_OS_ID" in
    bazzite|bluefin|aurora|ucore) return 0 ;;
  esac
  return 1
}

# os_pkg_from_ids ID ID_LIKE: pure mapping, prints the manager name.
os_pkg_from_ids() {
  local id="${1,,}" like="${2,,}" candidate

  for candidate in "$id" $like; do
    case "$candidate" in
      debian|ubuntu|linuxmint|pop|elementary|kali|raspbian|neon|zorin|devuan|mx|deepin|tuxedo|parrot)
        echo apt; return 0 ;;
      fedora|rhel|centos|rocky|almalinux|ol|amzn|nobara|scientific|eurolinux|circle)
        echo dnf; return 0 ;;
      opensuse*|sles|sled|suse|sle-micro)
        echo zypper; return 0 ;;
      arch|archarm|manjaro|endeavouros|garuda|artix|cachyos|arcolinux)
        echo pacman; return 0 ;;
      alpine|postmarketos)
        echo apk; return 0 ;;
      void)
        echo xbps; return 0 ;;
      gentoo|funtoo)
        echo emerge; return 0 ;;
      nixos)
        echo nix; return 0 ;;
    esac
  done
  echo unknown
  return 1
}

# os_pkg_from_commands: last resort, look for a manager binary.
os_pkg_from_commands() {
  if has_cmd apt-get && has_cmd dpkg; then echo apt
  elif has_cmd dnf5 || has_cmd dnf || has_cmd yum; then echo dnf
  elif has_cmd zypper; then echo zypper
  elif has_cmd pacman; then echo pacman
  elif has_cmd apk; then echo apk
  elif has_cmd xbps-install; then echo xbps
  elif has_cmd emerge; then echo emerge
  elif has_cmd nix-env || has_cmd nixos-rebuild; then echo nix
  else echo unknown; return 1
  fi
}

# os_detect: populate SU_OS_* and SU_PKG.
os_detect() {
  local file="${SU_OS_RELEASE:-/etc/os-release}"
  if [ ! -r "$file" ] && [ -z "${SU_OS_RELEASE:-}" ] && [ -r /usr/lib/os-release ]; then
    file=/usr/lib/os-release
  fi
  os_read_release "$file" || true

  if os_is_ostree; then
    SU_PKG="rpm-ostree"
  else
    SU_PKG=$(os_pkg_from_ids "$SU_OS_ID" "$SU_OS_ID_LIKE") || true
    if [ "$SU_PKG" = unknown ] && [ "${SU_PKG_FALLBACK:-1}" = 1 ]; then
      SU_PKG=$(os_pkg_from_commands) || true
    fi
  fi

  case "$SU_OS_ID" in
    opensuse-tumbleweed|opensuse-slowroll|opensuse-microos|opensuse-aeon|opensuse-kalpa)
      SU_ZYPPER_MODE=dup ;;
    *) SU_ZYPPER_MODE=update ;;
  esac
  [ -n "$SU_OS_PRETTY" ] || SU_OS_PRETTY="${SU_OS_NAME:-unknown} ${SU_OS_VERSION_ID:-}"
  export SU_OS_ID SU_OS_ID_LIKE SU_PKG
  return 0
}

# os_describe: one line for --list and the banner.
os_describe() {
  local extra=""
  [ "$SU_PKG" = zypper ] && extra=" ($SU_ZYPPER_MODE)"
  printf '%s [id=%s%s] package manager: %s%s\n' \
    "$SU_OS_PRETTY" "${SU_OS_ID:-?}" "${SU_OS_ID_LIKE:+ like=$SU_OS_ID_LIKE}" "$SU_PKG" "$extra"
}

# distro_pkg_owner PATH: print the distro package that owns PATH, if any.
distro_pkg_owner() {
  local path="$1" out=""
  [ -e "$path" ] || return 1
  case "$SU_PKG" in
    apt)
      out=$(dpkg -S "$path" 2>/dev/null | head -n1 | cut -d: -f1) ;;
    dnf|rpm-ostree|zypper)
      out=$(rpm -qf --qf '%{NAME}\n' "$path" 2>/dev/null | grep -v 'not owned' | head -n1) ;;
    pacman)
      out=$(pacman -Qqo "$path" 2>/dev/null | head -n1) ;;
    apk)
      out=$(apk info -W "$path" 2>/dev/null | sed -n 's/.* is owned by //p' | head -n1) ;;
    xbps)
      out=$(xbps-query -o "$path" 2>/dev/null | head -n1 | cut -d: -f1) ;;
    emerge)
      has_cmd qfile && out=$(qfile -q "$path" 2>/dev/null | head -n1) ;;
  esac
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}
