# Composer (`composer`)

Updates [Composer](https://getcomposer.org) itself, the invoking user's global packages, and the `cgr` and `drush-versions` helpers when present.

| | |
| --- | --- |
| Step name | `composer` |
| Runs as | the invoking user; `composer self-update` as root when the phar is not writable by the user |
| Detected when | `composer` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

1. **Composer itself** (`composer self-update --no-interaction --no-ansi`):
   * phar owned by a distro package: skipped, the system package step updates it;
   * phar writable by the user: run as the user;
   * otherwise (for example `/usr/local/bin/composer` owned by root): run as root through `sudo`, with `COMPOSER_ALLOW_SUPERUSER=1`;
   * not writable and no `sudo`: skipped.
2. **Global packages**: `composer global update --no-interaction --no-ansi --no-progress` as the user.
3. `cgr update` when `cgr` is installed, `drush-versions up` when `drush-versions` is installed.
4. `composer clear-cache`.

## What will be affected

* The Composer phar (in place, keeping its location and owner).
* `~/.config/composer/vendor` (or `$COMPOSER_HOME/vendor`) and its `composer.lock`: every global package is updated as far as the constraints in the global `composer.json` allow.
* Tools installed with `cgr` (each in its own directory) and the Drush versions managed by `drush-versions`.
* The Composer download cache is emptied.

## Dry run and `--detailed`

`--dry-run` prints the commands it would run (`would run: composer global update ...`) and changes nothing.

`--detailed` adds:

* the latest Composer release from GitHub (`installed -> latest` in the summary);
* the list from `composer global outdated --direct` (read-only): each global package that would change, with its installed and latest version.

## Warnings

* Global constraints such as `*` or `>=` let `composer global update` move to new **major** versions of tools like Drush. Pin them in the global `composer.json` if you depend on a major line.
* `self-update` follows the channel of the installed Composer (stable by default) and replaces the phar in place; the previous version is kept by Composer for `composer self-update --rollback`.
* Running `self-update` as root uses `COMPOSER_ALLOW_SUPERUSER=1`; nothing else in this step runs as root.

## Skipped / failed when

* Any of the commands fails: the step is failed and the note lists which one.
