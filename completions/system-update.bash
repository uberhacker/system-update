# bash completion for system-update                        -*- shell-script -*-
#
# Installed by install.sh into bash-completion's completions directory, or
# load it by hand:  source completions/system-update.bash
# A single-file build prints it:  source <(system-update --completion bash)
# zsh can use it too:  autoload -U bashcompinit && bashcompinit && source ...
#
# Step names come from the completed command (`system-update --_steps`), so
# a newly added tool completes without touching this file.

# COMPREPLY=($(compgen ...)) is the standard idiom; words never contain spaces.
# shellcheck disable=SC2207

# _system_update_steps CMD: every name --only/--skip accepts, from the
# command itself (`system-update --_steps` prints them and exits before
# reading any config, in both the multi-file and the single-file build).
# When that fails (not executable, too slow), the built-in steps are
# offered without the tool names.
_system_update_steps() {
  local cmd="$1" bin out
  if bin=$(command -v -- "$cmd" 2>/dev/null) && out=$(timeout 5 "$bin" --_steps 2>/dev/null </dev/null) && [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  printf '%s\n' system pkg apt dnf zypper pacman apk xbps emerge nix rpm-ostree \
    extras flatpak snap firmware reboot-check tools
}

_system_update() {
  local cur prev opts pfx=""
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="--dry-run --detailed --yes --only --skip --list --verbose --quiet
    --no-color --color --timeout --config --firmware --prune-node --install-jq
    --allow-unverified-installers --aur --no-autoremove --self-update --source
    --branch --log --no-log --nvim-plugins --runtimes --npm-globals
    --go-toolchain --containers --completion --version --help"

  # --opt=value: bash splits it into "--opt" "=" "value" (= is in
  # COMP_WORDBREAKS); without that, it arrives as one word.
  if [ "$cur" = "=" ]; then
    cur=""
  elif [ "$prev" = "=" ] && [ "$COMP_CWORD" -ge 2 ]; then
    prev="${COMP_WORDS[COMP_CWORD-2]}"
  elif [[ "$cur" == --*=* ]]; then
    prev="${cur%%=*}"
    pfx="$prev="
    cur="${cur#*=}"
  fi

  case "$prev" in
    --only|--skip)
      # Comma separated: complete the item after the last comma and skip
      # the ones already given.
      local done_part="${cur%"${cur##*,}"}" item words="" s
      item="${cur##*,}"
      for s in $(_system_update_steps "${COMP_WORDS[0]}"); do
        [[ ",$done_part" == *",$s,"* ]] || words+="$s "
      done
      COMPREPLY=($(compgen -P "$pfx$done_part" -W "$words" -- "$item"))
      compopt -o nospace 2>/dev/null || true
      return 0 ;;
    --color|--colour)
      COMPREPLY=($(compgen -P "$pfx" -W "auto always never" -- "$cur"))
      return 0 ;;
    --completion)
      COMPREPLY=($(compgen -P "$pfx" -W "bash zsh" -- "$cur"))
      return 0 ;;
    --config|--log)
      compopt -o filenames 2>/dev/null || true
      COMPREPLY=($(compgen -f -- "$cur"))
      return 0 ;;
    --timeout|--source|--branch)
      return 0 ;;   # free-form values
  esac

  COMPREPLY=($(compgen -W "$opts" -- "$cur"))
}

complete -F _system_update system-update
