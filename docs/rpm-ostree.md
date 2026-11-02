# rpm-ostree / bootc (`rpm-ostree`, `system`)

Image based Fedora: Silverblue, Kinoite and the other Atomic desktops, Bazzite, Bluefin, Aurora, uCore, Fedora CoreOS.

| | |
| --- | --- |
| Step name | `rpm-ostree` or `system` |
| Runs as | root (`sudo`) |
| Time limit | 3600 s |

## What it does

* Booted from a bootc container image: `bootc upgrade`.
* Otherwise: `rpm-ostree upgrade`.

Both download and **stage** a new deployment; the running system is not changed. dnf is never run on these systems, and nothing is layered.

## What will be affected

* A new deployment in `/ostree`, used from the next boot. The current deployment stays available as the rollback entry in the boot menu (`rpm-ostree rollback`).
* Layered packages are carried over to the new deployment.
* `/etc` changes are merged into the new deployment; `/var` and home directories are shared.

## Dry run and `--detailed`

`--dry-run` runs `rpm-ostree upgrade --check` (or `bootc upgrade --check`) and reports whether an update exists.

`--detailed` runs `rpm-ostree upgrade --preview` instead, which also prints the package diff, and lists each upgraded, added and removed package. bootc only reports that a new image exists; there is no package list for an image.

## Warnings

* Nothing takes effect until you reboot; the [reboot check](reboot-check.md) reports a staged deployment.
* Rebasing to a new Fedora release (`rpm-ostree rebase`) is not done here.
