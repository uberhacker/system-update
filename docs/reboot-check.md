# Reboot check (`reboot-check`)

Runs last and reports whether the system needs a reboot to use what was just installed. It never reboots.

| | |
| --- | --- |
| Step name | `reboot-check` |
| Runs as | the current user (read-only) |
| Result | `ok` (no reboot needed) or `warn` (reboot required); never `failed` |

## How it decides

The first source that gives an answer wins:

| Package manager | Check |
| --- | --- |
| apt | `/var/run/reboot-required` (and the packages listed in `reboot-required.pkgs`) |
| dnf | `needs-restarting -r`, or `dnf5 needs-restarting -r` |
| zypper | `zypper needs-rebooting` |
| rpm-ostree | a staged deployment that is not booted yet |
| any | the running kernel's modules directory is gone, i.e. a newer kernel replaced it |

In containers the step is skipped.

## Warnings

* A `warn` does not change the exit status. Scripts that must react to it can look for `reboot-check` with `warn` in the output.
* Services that were updated but not restarted are not reported (on Debian `needrestart` handles those).
