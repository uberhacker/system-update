# Vim plugins as git submodules (`vim`)

Updates Vim/Neovim plugins kept as git submodules of a `~/.vim` git repository (the pathogen / native packages layout).

| | |
| --- | --- |
| Step name | `vim` |
| Runs as | the invoking user |
| Detected when | `~/.vim` is a git checkout and `vim` or `nvim` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

`git -C ~/.vim submodule update --init --remote --recursive --jobs 4`: every submodule is fetched and checked out at the tip of its tracked branch (the `branch` in `.gitmodules`, or the remote's default branch). Status before and after is compared.

## What will be affected

* Every plugin checkout under `~/.vim`, moved to its upstream tip (detached HEAD).
* The `~/.vim` repository itself is left **modified** (new submodule commits). Commit the change to keep it, or `git submodule update` to go back.

## Dry run and `--detailed`

`--dry-run` reports how many submodules would be updated.

`--detailed` also asks each submodule's remote for its current tip (`git ls-remote`, read-only, no fetch) and lists the plugins that would move, as `path  old-commit -> new-commit`.

## Warnings

* Plugins move to their latest upstream commit, not a release. A breaking plugin change shows up the next time you start Vim.
* Uncommitted changes inside a submodule can make the update fail for that plugin; commits you made on a branch inside a submodule are left behind when it is detached.
* Plugin managers (vim-plug, lazy.nvim, packer, ...) are not handled; use their own update commands.

## Skipped when

* `~/.vim` has no submodules.
