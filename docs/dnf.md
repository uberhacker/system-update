# dnf / yum (`dnf`, `system`)

Fedora, RHEL, CentOS Stream, Rocky Linux, AlmaLinux, Oracle Linux, Amazon Linux. Uses `dnf5`, `dnf` or `yum`, whichever is found first.

| | |
| --- | --- |
| Step name | `dnf` or `system` |
| Runs as | root (`sudo`) |
| Settings | `AUTOREMOVE` / `--no-autoremove` |
| Time limit | 3600 s per command |

## What it does

1. `dnf5 --refresh check-upgrade` (`dnf --refresh check-update`, `yum check-update`): refreshes metadata and lists pending updates. Nothing pending: the step ends here.
2. `dnf -y upgrade` (`yum -y update`).
3. `dnf -y autoremove` (unless `--no-autoremove`).
4. `dnf clean packages`.

## What will be affected

* Every installed package with an update in the enabled repositories, including third-party ones (RPM Fusion, Docker, VSCodium, ...). Obsoleted packages are replaced.
* New kernels are installed alongside the old ones (`installonly_limit` decides how many are kept).
* `autoremove` removes packages that were pulled in as dependencies and are no longer needed. Packages you installed explicitly are kept.
* Downloaded RPMs in the dnf cache are removed.
* Configuration files you changed are kept; the new default is saved as `*.rpmnew`.

## Dry run and `--detailed`

`--dry-run` runs only the check (step 1) and reports `N package(s) would be upgraded`.

`--detailed` adds one row per package, with the installed version from `rpm -q` and the new one from the check:

```
  ◦ 2 package(s) would change:
      curl.x86_64          8.18.0-12.fc44 -> 8.18.0-14.fc44
      openssl-libs.x86_64  1:3.5.8-1.fc44 -> 1:3.5.9-1.fc44
```

A `?` means `rpm` did not know the package under that name and architecture (typically a package that replaces another).

## Warnings

* Review `autoremove` the first time on a long-lived system: `dnf autoremove` (without `-y`) shows what it would remove.
* On Fedora, a version upgrade (Fedora 43 to 44) is not done here; use `dnf system-upgrade`.
* With legacy `yum` a warning is printed; the behaviour is otherwise the same.
