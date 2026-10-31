# Flatpak (`flatpak`)

Updates Flatpak applications and runtimes, both the system installation and the invoking user's own.

| | |
| --- | --- |
| Step name | `flatpak` |
| Runs as | root for the system installation, the invoking user for `--user` |
| Detected when | `flatpak` is installed and has at least one remote |
| Time limit | 3600 s per command |

## What it does

* System installation (when it has remotes): `flatpak update --system -y --noninteractive` as root.
* The invoking user's installation (when it has remotes): `flatpak update --user -y --noninteractive` as the user.

## What will be affected

* Applications and runtimes in `/var/lib/flatpak` (system) and `~/.local/share/flatpak` (user), including new runtime versions the apps need. Unused runtimes are not removed (`flatpak uninstall --unused` does that).
* Running apps keep using the old version until restarted.
* App data in `~/.var/app` is not touched.

## Dry run and `--detailed`

`--dry-run` counts pending updates per installation with `flatpak remote-ls --updates`.

`--detailed` lists them with the installed and the new version:

```
  ◦ 3 system flatpak(s) would change:
      com.github.jeromerobert.pdfarranger//stable  1.14.0 -> 1.14.0 (new build)
      org.freedesktop.Platform.GL.default//24.08   ?      -> (new build)
      org.gimp.GIMP//stable                        3.0.4  -> 3.0.6
```

Many runtimes carry no version number; `(new build)` means a new commit of the same version.

## Warnings

* An app update can add permissions; flatpak accepts them non-interactively here. Review with `flatpak info --show-permissions <app>` if that matters to you.
