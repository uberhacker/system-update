#!/usr/bin/env bash
# lib/core/args.sh - command line parsing.
#
# Flags are collected into SU_ARG_* variables first; args_apply() then layers
# them on top of the config/environment values so that flags always win.

SU_ARG_DRY_RUN=""
SU_ARG_YES=""
SU_ARG_ONLY=""
SU_ARG_SKIP=""
SU_ARG_LIST=0
SU_ARG_VERBOSE=""
SU_ARG_QUIET=""
SU_ARG_COLOR=""
SU_ARG_FIRMWARE=""
SU_ARG_SELF_UPDATE=0
SU_ARG_SOURCE=""
SU_ARG_BRANCH=""
SU_ARG_VERSION=0
SU_ARG_HELP=0
SU_ARG_TIMEOUT=""
SU_ARG_INSTALL_JQ=""
SU_ARG_UNVERIFIED=""
SU_ARG_PRUNE_NODE=""
SU_ARG_AUR=""
SU_ARG_AUTOREMOVE=""
SU_ARG_NVIM_PLUGINS=""
SU_ARG_RUNTIMES=""
SU_ARG_NPM_GLOBALS=""
SU_ARG_GO_TOOLCHAIN=""
SU_ARG_CONTAINERS=""
SU_ARG_USER_TOOLS=0     # internal: child process running user-level tools
SU_CONFIG_FILE="${SU_CONFIG_FILE:-}"

usage() {
  cat <<EOF
Usage: system-update [OPTIONS]

Update the operating system packages and every supported third-party tool
that is installed, then print a summary.

Options:
  -n, --dry-run           show what would be updated; change nothing (-d is an alias)
  -y, --yes               non-interactive (package managers already never prompt)
      --only LIST         run only these steps (comma separated; see --list)
      --skip LIST         skip these steps (comma separated)
      --list              show detected distro, package manager and tools, then exit
  -v, --verbose           show every command that is run
  -q, --quiet             hide third-party output; show only status and summary
      --no-color          disable colours (NO_COLOR and non-TTY output do too)
      --color WHEN        auto (default), always or never
      --timeout SECONDS   per-command timeout for third-party tools (default 300)
      --config FILE       read this config file instead of the user config
      --firmware          apply firmware updates with fwupd (default: list only)
      --prune-node        remove Node.js versions other than the new default (nvm/nodebrew)
      --install-jq        allow installing jq with the package manager when missing
      --allow-unverified-installers
                          allow vendor "curl | sh" installers (ollama, AnythingLLM)
      --aur               run an AUR helper (yay/paru) as the invoking user on Arch
      --no-autoremove     do not remove orphaned packages after upgrading
  Opt-in steps (off by default; config keys NVIM_PLUGINS, RUNTIMES, ...):
      --nvim-plugins      sync Neovim plugins (lazy.nvim, packer or vim-plug)
      --runtimes          upgrade runtimes managed by mise/asdf within their configured specs
      --npm-globals       npm update -g under the user's own Node (nvm); never a system prefix
      --go-toolchain      replace /usr/local/go with the latest stable Go (sha256-verified)
      --containers        distrobox/toolbox upgrades, podman auto-update, re-pull container images
      --self-update       update this script from its git source and exit
      --source URL        git source for --self-update (https only)
      --branch NAME       branch for --self-update (default: the remote's default branch)
      --version           print the version and exit
  -h, --help              show this help and exit

Step names for --only/--skip: system (or the package manager name), flatpak,
snap, firmware, reboot-check, tools, and any tool name shown by --list
(rustup, azure-cli, bicep, cloudflared, gh-extensions, brew, oh-my-zsh,
oh-my-bash, tpm, cargo, mise, asdf, nvim-plugins, npm-globals, go,
containers, nvm, composer, docker-compose, ...).

Config: \${XDG_CONFIG_HOME:-~/.config}/system-update/config and
/etc/system-update.conf (KEY=value). Environment variables override the
files, flags override everything. See config.example.
EOF
}

# args_need OPT VALUE: fail when an option that needs a value has none.
args_need() {
  if [ -z "${2:-}" ]; then
    log_error "option $1 requires a value"
    return 1
  fi
}

# args_parse "$@": fill SU_ARG_*. Returns 2 on usage error.
args_parse() {
  local opt val
  while [ $# -gt 0 ]; do
    opt="$1"; val=""
    # Split --opt=value.
    case "$opt" in
      --*=*) val="${opt#*=}"; opt="${opt%%=*}"; set -- "$opt" "$val" "${@:2}" ;;
    esac
    case "$opt" in
      -n|-d|--dry-run|--simulate) SU_ARG_DRY_RUN=1 ;;
      -y|--yes) SU_ARG_YES=1 ;;
      --only) args_need "$opt" "${2:-}" || return 2; SU_ARG_ONLY="$2"; shift ;;
      --skip) args_need "$opt" "${2:-}" || return 2; SU_ARG_SKIP="$2"; shift ;;
      --list) SU_ARG_LIST=1 ;;
      -v|--verbose) SU_ARG_VERBOSE=1 ;;
      -q|--quiet) SU_ARG_QUIET=1 ;;
      --no-color|--no-colour) SU_ARG_COLOR=never ;;
      --color|--colour) args_need "$opt" "${2:-}" || return 2; SU_ARG_COLOR="$2"; shift ;;
      --timeout) args_need "$opt" "${2:-}" || return 2; SU_ARG_TIMEOUT="$2"; shift ;;
      --config) args_need "$opt" "${2:-}" || return 2; SU_CONFIG_FILE="$2"; shift ;;
      --firmware) SU_ARG_FIRMWARE=1 ;;
      --prune-node) SU_ARG_PRUNE_NODE=1 ;;
      --install-jq) SU_ARG_INSTALL_JQ=1 ;;
      --allow-unverified-installers) SU_ARG_UNVERIFIED=1 ;;
      --aur) SU_ARG_AUR=1 ;;
      --no-autoremove) SU_ARG_AUTOREMOVE=0 ;;
      --nvim-plugins) SU_ARG_NVIM_PLUGINS=1 ;;
      --runtimes) SU_ARG_RUNTIMES=1 ;;
      --npm-globals) SU_ARG_NPM_GLOBALS=1 ;;
      --go-toolchain|--go) SU_ARG_GO_TOOLCHAIN=1 ;;
      --containers) SU_ARG_CONTAINERS=1 ;;
      --self-update) SU_ARG_SELF_UPDATE=1 ;;
      --source) args_need "$opt" "${2:-}" || return 2; SU_ARG_SOURCE="$2"; shift ;;
      --branch) args_need "$opt" "${2:-}" || return 2; SU_ARG_BRANCH="$2"; shift ;;
      --version|-V) SU_ARG_VERSION=1 ;;
      -h|--help) SU_ARG_HELP=1 ;;
      --_user-tools) SU_ARG_USER_TOOLS=1 ;;
      --) shift; break ;;
      -*)
        # Combined short flags like -nv.
        if [[ "$opt" =~ ^-[a-zA-Z]{2,}$ ]]; then
          local i chars="${opt#-}" rest=()
          for ((i = 0; i < ${#chars}; i++)); do rest+=("-${chars:i:1}"); done
          shift
          set -- "${rest[@]}" "$@"
          continue
        fi
        log_error "unknown option: $opt"
        return 2 ;;
      *)
        log_error "unexpected argument: $opt"
        return 2 ;;
    esac
    shift
  done
  if [ $# -gt 0 ]; then
    log_error "unexpected argument: $1"
    return 2
  fi
  return 0
}

# args_apply: layer flags over the loaded configuration and export the
# runtime globals used by the rest of the program.
args_apply() {
  [ -n "$SU_ARG_ONLY" ] && config_set ONLY "$SU_ARG_ONLY" flag
  [ -n "$SU_ARG_SKIP" ] && config_set SKIP "$SU_ARG_SKIP" flag
  [ -n "$SU_ARG_TIMEOUT" ] && { config_set TIMEOUT "$SU_ARG_TIMEOUT" flag || return 2; }
  [ -n "$SU_ARG_COLOR" ] && { config_set COLOR "$SU_ARG_COLOR" flag || return 2; }
  [ -n "$SU_ARG_FIRMWARE" ] && config_set FIRMWARE "$SU_ARG_FIRMWARE" flag
  [ -n "$SU_ARG_PRUNE_NODE" ] && config_set PRUNE_NODE "$SU_ARG_PRUNE_NODE" flag
  [ -n "$SU_ARG_INSTALL_JQ" ] && config_set INSTALL_JQ "$SU_ARG_INSTALL_JQ" flag
  [ -n "$SU_ARG_UNVERIFIED" ] && config_set ALLOW_UNVERIFIED_INSTALLERS "$SU_ARG_UNVERIFIED" flag
  [ -n "$SU_ARG_AUR" ] && config_set AUR_HELPER "$SU_ARG_AUR" flag
  [ -n "$SU_ARG_AUTOREMOVE" ] && config_set AUTOREMOVE "$SU_ARG_AUTOREMOVE" flag
  [ -n "$SU_ARG_NVIM_PLUGINS" ] && config_set NVIM_PLUGINS "$SU_ARG_NVIM_PLUGINS" flag
  [ -n "$SU_ARG_RUNTIMES" ] && config_set RUNTIMES "$SU_ARG_RUNTIMES" flag
  [ -n "$SU_ARG_NPM_GLOBALS" ] && config_set NPM_GLOBALS "$SU_ARG_NPM_GLOBALS" flag
  [ -n "$SU_ARG_GO_TOOLCHAIN" ] && config_set GO_TOOLCHAIN "$SU_ARG_GO_TOOLCHAIN" flag
  [ -n "$SU_ARG_CONTAINERS" ] && config_set CONTAINERS "$SU_ARG_CONTAINERS" flag
  [ -n "$SU_ARG_SOURCE" ] && { config_set SELF_UPDATE_REPO "$SU_ARG_SOURCE" flag || return 2; }
  [ -n "$SU_ARG_BRANCH" ] && { config_set SELF_UPDATE_BRANCH "$SU_ARG_BRANCH" flag || return 2; }

  SU_DRY_RUN="${SU_ARG_DRY_RUN:-${SU_DRY_RUN:-0}}"
  SU_YES="${SU_ARG_YES:-0}"
  SU_VERBOSE="${SU_ARG_VERBOSE:-${SU_VERBOSE:-0}}"
  SU_QUIET="${SU_ARG_QUIET:-${SU_QUIET:-0}}"
  if [ "$SU_VERBOSE" = 1 ] && [ "$SU_QUIET" = 1 ]; then
    SU_QUIET=0
  fi
  SU_COLOR=$(cfg COLOR)
  SU_TIMEOUT=$(cfg TIMEOUT)
  SU_PROBE_TIMEOUT=$(cfg PROBE_TIMEOUT)
  SU_ONLY=$(cfg ONLY)
  SU_SKIP=$(cfg SKIP)
  export SU_DRY_RUN SU_VERBOSE SU_QUIET SU_COLOR SU_TIMEOUT SU_PROBE_TIMEOUT
  log_init
  return 0
}
