# Composer (`composer`)

Updates [Composer](https://getcomposer.org) itself, the invoking user's global packages, and the `cgr` and `drush-versions` helpers when present.

| | |
| --- | --- |
| Step name | `composer` |
| Runs as | the invoking user; `composer self-update` as root when the phar or its directory is not writable by the user |
| Detected when | `composer` is on `PATH` |
| Settings | `TIMEOUT` |

## What it does

1. **Composer itself** (`composer self-update --no-interaction --no-ansi`):
   * phar owned by a distro package: skipped, the system package step updates it;
   * phar and its directory writable by the user: run as the user (the update writes a new file next to the phar, so the directory matters too);
   * otherwise (for example a root-owned `/usr/local/bin`): run as root through `sudo`, with `COMPOSER_ALLOW_SUPERUSER=1`;
   * not writable and no `sudo`: skipped.
2. **Global packages**, as the user, in three parts:
   * it looks first with `composer global update --dry-run`; when nothing would change, the real update is not run;
   * when the plan would **downgrade** any package (for example Symfony 7 back to 5 after a PHP change or a new constraint), nothing is changed: the step warns and names the packages and the PHP version, so you can check with `composer global why-not <package> <version>` and run the update yourself;
   * otherwise it copies the global `composer.json`, `composer.lock` and `vendor/` aside, runs `composer global update --no-interaction --no-ansi --no-progress`, and puts the copy back if the update fails half way (a patch that no longer applies, a network error), so `cgr` and other global tools are not left with a broken autoloader. The copy is removed afterwards.
3. `cgr update` when `cgr` is installed, `drush-versions up` when `drush-versions` is installed.
4. `composer clear-cache`.

## What will be affected

* The Composer phar (in place, keeping its location and owner).
* `~/.config/composer/vendor` (or `$COMPOSER_HOME/vendor`) and its `composer.lock`: every global package is updated as far as the constraints in the global `composer.json` allow.
* Tools installed with `cgr` (each in its own directory) and the Drush versions managed by `drush-versions`.
* The Composer download cache is emptied.

## Moving it out of /usr/local/bin

With `--move-to-home composer` (or `MOVE_TO_HOME=composer`), a copy in a root-owned directory is moved to `~/.local/bin` once (when that directory is on your `PATH` ahead of the old one), so later updates run as you without sudo. See [Third-party tools](../README.md#third-party-tools).

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

* The global update would downgrade packages: the step warns and the global packages are left as they were.
* Any of the commands fails: the step is failed and the note lists which one (and whether the global packages were restored).
