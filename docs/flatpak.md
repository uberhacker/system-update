# Flatpak (`flatpak`)

Updates Flatpak applications and runtimes, both the system installation and the invoking user's own, and records what changed so it can be rolled back.

| | |
| --- | --- |
| Step name | `flatpak` |
| Runs as | root for the system installation, the invoking user for `--user` |
| Detected when | `flatpak` is installed and has at least one remote |
| Time limit | 3600 s per command |
| Undo | `system-update --undo-flatpak` |

## What it does

* System installation (when it has remotes): `flatpak update --system -y --noninteractive` as root.
* The invoking user's installation (when it has remotes): `flatpak update --user -y --noninteractive` as the user.
* Before each update it notes the active commit of every installed app and runtime (`flatpak info --show-commit`), and afterwards writes the ones that changed to the undo file: `/var/lib/system-update/flatpak-undo.tsv` when run as root, `~/.local/state/system-update/flatpak-undo.tsv` otherwise. A run that changes nothing keeps the previous file.
* Before updating, it names each runtime that is about to update while the apps using it have no update of their own. That is the case where an app can stop starting (see below).
* Refs held back with `flatpak mask` are left alone, as `flatpak update` does, and shown as `held:` in the step's result.

## What will be affected

* Applications and runtimes in `/var/lib/flatpak` (system) and `~/.local/share/flatpak` (user), including new runtime versions the apps need. Unused runtimes are not removed (`flatpak uninstall --unused` does that).
* Running apps keep using the old version until restarted.
* App data in `~/.var/app` is not touched.

## Dry run and `--detailed`

`--dry-run` counts pending updates per installation with `flatpak remote-ls --updates`, leaving out masked refs.

`--detailed` lists them with the installed and the new version, and names runtimes that update without their apps:

```
  ◦ 3 system flatpak(s) would change:
      com.github.jeromerobert.pdfarranger//stable  1.14.0 -> 1.14.0 (new build)
      org.freedesktop.Platform.GL.default//24.08   ?      -> (new build)
      org.gimp.GIMP//stable                        3.0.4  -> 3.0.6
  ◦ flatpak: org.kde.Platform//6.11 updates without its app(s) org.torproject.torbrowser-launcher; if one stops starting: system-update --undo-flatpak
```

Many runtimes carry no version number; `(new build)` means a new commit of the same version.

## Undo (`--undo-flatpak`)

`system-update --undo-flatpak` puts every app and runtime the last run changed back on the commit it had (`flatpak update --commit=<previous>`) and then holds it there with `flatpak mask`, so the next run does not update it again. It prints the `flatpak mask --remove` commands that release the holds; run them once the app has a fixed build. `--undo-flatpak --dry-run` only prints the commands.

Run it the same way you ran system-update (as yourself, or with sudo): each keeps its own undo file.

## When an app stops starting after an update

Flatpak apps can bundle libraries that are built against one particular build of their runtime. When Flathub publishes a rebuilt runtime before the app is rebuilt, the app can fail to start until the app catches up. In November 2026 the Tor Browser launcher (`org.torproject.torbrowser-launcher`, which bundles PySide6 on `org.kde.Platform` 6.11) failed this way with `ImportError: libshiboken: could not import module 'PySide6.QtGui'`. Any `flatpak update`, from system-update or a software centre, does the same.

To get the app working again:

1. `system-update --undo-flatpak` (if system-update did the update), or by hand: `flatpak remote-info --log flathub org.kde.Platform//6.11` to find the previous commit, then `flatpak update --commit=<commit> org.kde.Platform//6.11` and `flatpak mask org.kde.Platform//6.11`.
2. Once the app has a fixed build, `flatpak mask --remove org.kde.Platform//6.11` and update again.

## Warnings

* An app update can add permissions; flatpak accepts them non-interactively here. Review with `flatpak info --show-permissions <app>` if that matters to you.
* A masked runtime also stays old for every other app that uses it.
