# Oh My Bash (`oh-my-bash`)

Updates [Oh My Bash](https://ohmybash.github.io) with its own `tools/upgrade.sh`.

| | |
| --- | --- |
| Step name | `oh-my-bash` |
| Runs as | the invoking user |
| Detected when | `${OSH:-~/.oh-my-bash}/tools/upgrade.sh` exists |
| Needs | `git` |
| Settings | `TIMEOUT` |

## What it does

Works exactly like [oh-my-zsh](oh-my-zsh.md), with the same shared code: skipped when `git` is missing or the directory is not a git checkout, then `bash $OSH/tools/upgrade.sh` with `OSH` set; exit code 0 or 80 is success, and the commit before and after says whether anything changed.

## What will be affected

* The Oh My Bash checkout (`~/.oh-my-bash`), moved to the latest `master`.
* Your `~/.bashrc` and the `custom/` directory are not changed by this program.

## Dry run and `--detailed`

`--dry-run` runs `git fetch origin master` in the checkout and reports `already at the latest version` or `N commit(s) behind origin/master`. `--detailed` adds nothing beyond that.

## Warnings

* Local edits inside `~/.oh-my-bash` (outside `custom/`) can make the upgrade script fail.

## Skipped / failed when

* git missing, or not a git checkout: skipped.
* The upgrade script exits with anything other than 0 or 80: failed.
