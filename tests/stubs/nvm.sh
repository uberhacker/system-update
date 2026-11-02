#!/usr/bin/env bash
# Stub nvm.sh for the unit tests. Sourced like the real one; defines an nvm()
# function backed by plain files under $NVM_DIR/state:
#   installed   one version per line (vX.Y.Z)
#   default     what the "default" alias points at (a version or lts/*)
#   current     output of `nvm current`
#   remote_lts  the version `nvm version-remote --lts` reports
#   fail_install  if present, `nvm install` fails
# Every call is appended to $NVM_STUB_LOG.
_nvm_state="${NVM_DIR:?}/state"

nvm() {
  [ -n "${NVM_STUB_LOG:-}" ] && printf '%s\n' "$*" >> "$NVM_STUB_LOG"
  local cmd="$1"; shift
  case "$cmd" in
    current) cat "$_nvm_state/current" ;;
    version-remote)
      cat "$_nvm_state/remote_lts" ;;
    version)
      local want="$1" target
      case "$want" in
        default) target=$(cat "$_nvm_state/default" 2>/dev/null) ;;
        *) target="$want" ;;
      esac
      case "$target" in
        'lts/*') target=$(cat "$_nvm_state/remote_lts") ;;
      esac
      if grep -qx -- "$target" "$_nvm_state/installed" 2>/dev/null; then
        echo "$target"
      else
        echo "N/A"; return 1
      fi ;;
    install)
      if [ -e "$_nvm_state/fail_install" ]; then echo "stub: install failed" >&2; return 1; fi
      local v="$1"
      [ "$v" = 'lts/*' ] && v=$(cat "$_nvm_state/remote_lts")
      grep -qx -- "$v" "$_nvm_state/installed" 2>/dev/null || echo "$v" >> "$_nvm_state/installed"
      echo "Now using node $v" ;;
    alias)
      [ "$1" = default ] || { echo "stub: unsupported alias $1" >&2; return 1; }
      echo "$2" > "$_nvm_state/default"
      echo "default -> $2" ;;
    ls)
      sed 's/^/        /' "$_nvm_state/installed" ;;
    uninstall)
      local def
      def=$(cat "$_nvm_state/default")
      [ "$def" = 'lts/*' ] && def=$(cat "$_nvm_state/remote_lts")
      if [ "$1" = "$def" ]; then echo "stub: refusing to uninstall the default" >&2; return 1; fi
      grep -vx -- "$1" "$_nvm_state/installed" > "$_nvm_state/installed.new" || true
      mv "$_nvm_state/installed.new" "$_nvm_state/installed"
      echo "Uninstalled node $1" ;;
    *) echo "stub: unknown nvm command $cmd" >&2; return 1 ;;
  esac
}
