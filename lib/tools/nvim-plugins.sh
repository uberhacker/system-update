#!/usr/bin/env bash
# lib/tools/nvim-plugins.sh - Neovim plugin sync (opt-in: NVIM_PLUGINS=1 / --nvim-plugins).
#
# lazy.nvim:  nvim --headless "+Lazy! sync" +qa
# packer.nvim: nvim --headless -c 'autocmd User PackerComplete quitall' -c PackerSync
# vim-plug:   nvim --headless +PlugUpdate +qa
# Headless nvim can still wait on something (a prompt, a plugin build), so
# it runs with the usual timeout and stdin from /dev/null. For lazy.nvim the
# lockfile before and after says whether plugins actually moved.

nvim_data_dir() { printf '%s/nvim\n' "${XDG_DATA_HOME:-$SU_USER_HOME/.local/share}"; }
nvim_config_dir() { printf '%s/nvim\n' "${XDG_CONFIG_HOME:-$SU_USER_HOME/.config}"; }

tool_nvim_plugins_detect() {
  local data cfg
  user_bin nvim >/dev/null || return 1
  data=$(nvim_data_dir); cfg=$(nvim_config_dir)
  if [ -d "$data/lazy/lazy.nvim" ] || [ -f "$cfg/lazy-lock.json" ]; then echo lazy.nvim; return 0; fi
  if [ -d "$data/site/pack/packer/start/packer.nvim" ]; then echo packer.nvim; return 0; fi
  if [ -f "$data/site/autoload/plug.vim" ] || [ -f "$cfg/autoload/plug.vim" ]; then echo vim-plug; return 0; fi
  return 1
}

tool_nvim_plugins_update() {
  local manager="${SU_TOOL_BIN[nvim-plugins]}" nvim lock before="" after="" rc=0
  local -a cmd
  tool_opt_in NVIM_PLUGINS --nvim-plugins || return 0
  nvim=$(user_bin nvim) || { step_skip "nvim not found"; return 0; }
  case "$manager" in
    lazy.nvim) cmd=("$nvim" --headless "+Lazy! sync" +qa) ;;
    packer.nvim) cmd=("$nvim" --headless -c 'autocmd User PackerComplete quitall' -c PackerSync) ;;
    vim-plug) cmd=("$nvim" --headless +PlugUpdate +qa) ;;
    *) step_skip "unknown plugin manager '$manager'"; return 0 ;;
  esac
  lock="$(nvim_config_dir)/lazy-lock.json"
  log_info "plugin manager: $manager"
  if [ "$SU_DRY_RUN" = 1 ]; then
    step_dry "would run: ${cmd[*]}"
    return 0
  fi
  [ -r "$lock" ] && before=$(sha256_of "$lock")
  run_user env TERM=dumb "${cmd[@]}" || rc=$?
  if [ "$rc" -ne 0 ]; then
    step_fail "$manager sync failed ($(rc_note "$rc"))"
    return 0
  fi
  [ -r "$lock" ] && after=$(sha256_of "$lock")
  if [ -n "$before" ] && [ "$before" != "$after" ]; then
    step_updated "plugins updated ($manager; lazy-lock.json changed)"
  elif [ -n "$before" ]; then
    step_ok "plugins up to date ($manager)"
  else
    step_updated "plugins synced ($manager)"
  fi
}
