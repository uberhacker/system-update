# zypper (`zypper`, `system`)

openSUSE and SUSE Linux Enterprise.

| | |
| --- | --- |
| Step name | `zypper` or `system` |
| Runs as | root (`sudo`) |
| Mode | `dup` on Tumbleweed, Slowroll and MicroOS; `update` on Leap and SLE |
| Time limit | 3600 s per command |

## What it does

1. `zypper --non-interactive refresh`.
2. `zypper --non-interactive dup` (rolling releases) or `zypper --non-interactive update` (Leap/SLE). When zypper updates itself first (exit code 103) the command runs once more.

`--list` shows which mode was chosen.

## What will be affected

* `dup` is a **distribution upgrade**: packages are upgraded, downgraded, replaced by their successors, or removed to match the repositories. That is the supported way to keep Tumbleweed current.
* `update` installs newer versions of installed packages only.
* New recommended packages may be installed.
* Exit code 102 (a reboot is needed) is reported as `reboot required`.

## Dry run and `--detailed`

`--dry-run` refreshes the repositories (root) and runs the same command with `--dry-run`, reporting `N package(s) would be upgraded/installed`.

`--detailed` adds `--details` and lists each package that would be upgraded, downgraded, newly installed or removed (the table replaces zypper's own, much longer, listing on the terminal; the run log still has it):

```
  ◦ 13 package(s) would change:
      krb5                (new)      -> 1.22.2-5.1
      libcurl-mini4       8.23.0-2.1 -> (removed)
      openSUSE-build-key  1.0-68.1   -> 1.0-69.1
```

Patterns, patches and products in the summary are not listed.

## Warnings

* Running `dup` on Leap is not supported and is never done here. Running `update` on Tumbleweed would miss package replacements, which is why the mode is chosen from `/etc/os-release`.
* Vendor changes (for example to Packman) follow zypper's own vendor stickiness rules.
* Orphaned packages are not removed automatically on openSUSE.
