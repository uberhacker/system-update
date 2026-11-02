# asdf (`asdf`)

Updates [asdf](https://asdf-vm.com) where it can update itself, its plugins and, only with `--runtimes`, the versions pinned in your home `~/.tool-versions`.

| | |
| --- | --- |
| Step name | `asdf` |
| Runs as | the invoking user |
| Detected when | `asdf` is on the user's `PATH`, or `${ASDF_DIR:-~/.asdf}/bin/asdf` exists |
| Settings | `RUNTIMES` / `--runtimes` (off by default), `TIMEOUT`, `PROBE_TIMEOUT`; plugin and install commands use the one-hour package-manager limit |

## What it does

asdf comes in two generations and both are handled:

1. **asdf itself**:
   * distro or Homebrew package: noted, left to that package manager;
   * **bash asdf (0.15 and older)**, a git checkout: `asdf update`, unless the checkout carries `asdf_updates_disabled` (its package disabled self-update);
   * **Go asdf (0.16 and newer)**, a binary: it has no self-update and its releases publish no sha256, so the step only says how to update it.
2. **Plugins**: `asdf plugin update --all`; the plugin commits before and after say how many moved.
3. **Runtimes**, only with `--runtimes` or `RUNTIMES=1`: for each tool pinned to a plain version number in **`~/.tool-versions`**, `asdf latest <tool> <major>` finds the newest version of the same major. If it is newer, it is installed and becomes the home default (`asdf global` for bash asdf, `asdf set -u` for Go asdf).

## What will be affected

* The `~/.asdf` checkout (bash asdf).
* Plugin checkouts under `${ASDF_DATA_DIR:-~/.asdf}/plugins`.
* With `--runtimes`: new tool versions are installed and the pins in **your home `~/.tool-versions`** are changed to them. Project `.tool-versions` files are never touched, and pins such as `system`, `latest`, `ref:` or `path:` are left alone.

## Dry run and `--detailed`

`--dry-run` reports what would run (`asdf update`, `asdf plugin update --all (N plugin(s))`) and, with `--runtimes`, each pin that would move (`would upgrade nodejs 20.11.0 -> 20.19.5`). `--detailed` adds nothing beyond that.

## Warnings

* With `--runtimes` the home defaults change: shells outside a project with its own `.tool-versions` get the new version.
* Old versions stay installed (`asdf uninstall` removes them).
* Go asdf must be updated by hand or with your package manager.

## Skipped / failed when

* `asdf version` gives no version: skipped as a different program.
* `asdf update`, the plugin update, or a runtime install fails: failed.
