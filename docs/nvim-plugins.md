# Neovim plugins (`nvim-plugins`) - opt-in

Syncs Neovim plugins with the plugin manager you use, headlessly. **Off by default**: enable it with `--nvim-plugins` or `NVIM_PLUGINS=1`.

| | |
| --- | --- |
| Step name | `nvim-plugins` |
| Runs as | the invoking user |
| Detected when | `nvim` is on `PATH` and one of lazy.nvim, packer.nvim or vim-plug is installed (see below) |
| Settings | `NVIM_PLUGINS` / `--nvim-plugins` (off by default), `TIMEOUT` |

## What it does

The plugin manager is detected from the Neovim data and config directories (`${XDG_DATA_HOME:-~/.local/share}/nvim`, `${XDG_CONFIG_HOME:-~/.config}/nvim`), first match wins:

| Manager | Detected by | Command |
| --- | --- | --- |
| lazy.nvim | `lazy/lazy.nvim` in the data dir, or `lazy-lock.json` in the config dir | `nvim --headless "+Lazy! sync" +qa` |
| packer.nvim | `site/pack/packer/start/packer.nvim` in the data dir | `nvim --headless -c 'autocmd User PackerComplete quitall' -c PackerSync` |
| vim-plug | `autoload/plug.vim` in the data or config dir | `nvim --headless +PlugUpdate +qa` |

The command runs with `TERM=dumb`, stdin closed and the `TIMEOUT` limit. For lazy.nvim, the checksum of `lazy-lock.json` before and after says whether plugins moved.

## What will be affected

* Plugin checkouts in the Neovim data directory, moved to what your plugin spec allows (`Lazy! sync` also installs missing plugins and cleans removed ones).
* lazy.nvim: `lazy-lock.json` is rewritten when plugins move. If you keep it in version control, commit or revert the change.

## Dry run and `--detailed`

`--dry-run` reports the command it would run; nothing else is checked. `--detailed` adds nothing beyond that.

## Warnings

* Headless Neovim loads your whole configuration; a plugin that prompts or builds something (for example a treesitter parser compile) can run until `TIMEOUT` (300 s) kills it.
* Plugins move to new commits; a breaking plugin change shows up the next time you start Neovim. lazy.nvim's `:Lazy restore` goes back to the lockfile.

## Skipped / failed when

* Not enabled, or nvim missing: skipped.
* The sync command fails or times out: failed.
