# Oh My Zsh (`oh-my-zsh`)

Updates [Oh My Zsh](https://ohmyz.sh) with its own `tools/upgrade.sh`, non-interactively.

| | |
| --- | --- |
| Step name | `oh-my-zsh` |
| Runs as | the invoking user |
| Detected when | `${ZSH:-~/.oh-my-zsh}/tools/upgrade.sh` exists |
| Needs | `zsh`, `git` |
| Settings | `TIMEOUT` |

## What it does

1. Skipped when `zsh` or `git` is missing, or the directory is not a git checkout.
2. Runs `zsh $ZSH/tools/upgrade.sh` with `ZSH` set and `DISABLE_UPDATE_PROMPT=true`, without `-i`, so it never prompts. Exit code 80 ("already up to date") counts as success.
3. The commit before and after says whether anything changed.

## What will be affected

* The Oh My Zsh checkout (`~/.oh-my-zsh`), moved to the latest `master`.
* Your `~/.zshrc` and the `custom/` directory are not changed by this program. Custom plugins and themes in `custom/` that are their own git checkouts are not updated.

## Dry run and `--detailed`

`--dry-run` runs `git fetch origin master` in the checkout (this updates its remote-tracking ref, nothing else) and reports `already at the latest version` or `N commit(s) behind origin/master`. `--detailed` adds nothing beyond that.

## Warnings

* Local edits inside `~/.oh-my-zsh` (outside `custom/`) can make the upgrade script fail.

## Skipped / failed when

* zsh or git missing, or not a git checkout: skipped.
* The upgrade script exits with anything other than 0 or 80: failed.
