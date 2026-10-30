#!/usr/bin/env bash
# install.sh - install or remove system-update.
#
#   ./install.sh              system install: /usr/local/share/system-update
#                             + symlink /usr/local/bin/system-update (uses sudo)
#   ./install.sh --user       user install: ~/.local/share/system-update
#                             + symlink ~/.local/bin/system-update
#   ./install.sh --prefix DIR install under DIR/share and DIR/bin
#   ./install.sh --uninstall  remove the installation (combine with --user/--prefix)
#
# The whole checkout is copied, including .git when present, so that
# `system-update --self-update` can fast-forward the installed copy. Bash
# completion is linked into bash-completion's directory for the same prefix
# (DIR/share/bash-completion/completions, or the user's XDG data dir).

set -euo pipefail

SRC=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MODE=system
ACTION=install
PREFIX=""

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --user) MODE=user ;;
    --prefix) [ -n "${2:-}" ] || { echo "--prefix needs a value" >&2; exit 2; }; PREFIX="$2"; MODE=prefix; shift ;;
    --prefix=*) PREFIX="${1#*=}"; MODE=prefix ;;
    --uninstall|--remove) ACTION=uninstall ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$MODE" in
  user) BIN_DIR="$HOME/.local/bin"; SHARE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/system-update" ;;
  system) PREFIX=/usr/local; BIN_DIR="$PREFIX/bin"; SHARE_DIR="$PREFIX/share/system-update" ;;
  prefix) BIN_DIR="$PREFIX/bin"; SHARE_DIR="$PREFIX/share/system-update" ;;
esac
LINK="$BIN_DIR/system-update"
case "$MODE" in
  user) COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions" ;;
  *) COMP_DIR="$PREFIX/share/bash-completion/completions" ;;
esac
COMP_LINK="$COMP_DIR/system-update"

# priv CMD...: run as root when the target is not writable by us.
priv() {
  local probe="$1"; shift
  local dir="$probe"
  while [ ! -e "$dir" ]; do dir=$(dirname "$dir"); done
  if [ -w "$dir" ]; then
    "$@"
  elif [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "need root to write to $dir and sudo is not available" >&2
    exit 1
  fi
}

if [ "$ACTION" = uninstall ]; then
  # Only our own symlink; a completion file someone else put there stays.
  if [ -L "$COMP_LINK" ] && [[ "$(readlink "$COMP_LINK")" == "$SHARE_DIR/"* ]]; then
    priv "$COMP_LINK" rm -f "$COMP_LINK"
    echo "removed $COMP_LINK"
  fi
  if [ -L "$LINK" ] || [ -e "$LINK" ]; then
    priv "$LINK" rm -f "$LINK"
    echo "removed $LINK"
  fi
  if [ -d "$SHARE_DIR" ]; then
    if [ ! -f "$SHARE_DIR/bin/system-update" ]; then
      echo "$SHARE_DIR does not look like a system-update installation; not removing it" >&2
      exit 1
    fi
    priv "$SHARE_DIR" rm -rf "$SHARE_DIR"
    echo "removed $SHARE_DIR"
  fi
  exit 0
fi

[ -f "$SRC/bin/system-update" ] || { echo "run install.sh from a system-update checkout" >&2; exit 1; }

staging="$(dirname "$SHARE_DIR")/.system-update.install.$$"
priv "$SHARE_DIR" mkdir -p "$(dirname "$SHARE_DIR")" "$BIN_DIR"
priv "$SHARE_DIR" rm -rf "$staging"
priv "$SHARE_DIR" mkdir -p "$staging"
# Copy everything except test vendoring; .git is kept for self-update.
for item in bin lib completions system-update VERSION LICENSE README.md config.example install.sh .git; do
  [ -e "$SRC/$item" ] || continue
  priv "$SHARE_DIR" cp -a "$SRC/$item" "$staging/"
done
if [ -d "$SHARE_DIR" ]; then
  priv "$SHARE_DIR" rm -rf "$SHARE_DIR.old"
  priv "$SHARE_DIR" mv "$SHARE_DIR" "$SHARE_DIR.old"
fi
priv "$SHARE_DIR" mv "$staging" "$SHARE_DIR"
priv "$SHARE_DIR" rm -rf "$SHARE_DIR.old"
priv "$SHARE_DIR" chmod 0755 "$SHARE_DIR/bin/system-update" "$SHARE_DIR/system-update"
priv "$LINK" ln -sfn "$SHARE_DIR/bin/system-update" "$LINK"
if [ -f "$SHARE_DIR/completions/system-update.bash" ]; then
  if [ -e "$COMP_LINK" ] && [ ! -L "$COMP_LINK" ]; then
    echo "note: $COMP_LINK exists and is not ours; bash completion not linked"
  else
    priv "$COMP_DIR" mkdir -p "$COMP_DIR"
    priv "$COMP_LINK" ln -sfn "$SHARE_DIR/completions/system-update.bash" "$COMP_LINK"
    echo "completion: $COMP_LINK (new shells; needs the bash-completion package)"
  fi
fi

echo "installed $(tr -d '[:space:]' < "$SHARE_DIR/VERSION") to $SHARE_DIR"
echo "command:   $LINK"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "note: $BIN_DIR is not on your PATH" ;;
esac
