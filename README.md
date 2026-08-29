# Buildroot Builder2

This directory is the clone-and-run workflow for building PolyLinux/v86 image
pairs and then adding lab payload files to `/root`.

The workflow has three stages:

1. `scripts/01-setup-buildroot.sh` installs Buildroot host dependencies on
   Ubuntu/Debian, downloads a Buildroot LTS release, and creates the local
   working directories.
2. `scripts/02-build-baseline.sh` asks which config set to use and builds a
   baseline `bzImage` plus `rootfs.cpio.gz`.
3. `scripts/03-package-payload.sh` clones a payload repository, stages its files,
   and calls `tools/package_rootfs_payload.py` to merge those files into `/root`
   of the selected baseline rootfs.

Run these scripts on Linux. Buildroot requires a real Linux filesystem and host
toolchain; do not build inside a Windows-synced directory.

## Quick Start

```sh
git clone https://github.com/giacobe/buildroot-builder2.git
cd buildroot-builder2

# The checked-in configurations are validated against this release.
export BUILDROOT_VERSION=2025.02.15

scripts/01-setup-buildroot.sh
scripts/02-build-baseline.sh

scripts/03-package-payload.sh \
  --repo https://github.com/giacobe/polybandit3.git \
  --baseline artifacts/<baseline-dir> \
  --output artifacts/polybandit3 \
  --rename-to-install installbandit.sh \
  --output-prefix polybandit3
```

The packaging stage writes:

```text
<output>/
  polybandit3.bzImage
  polybandit3.rootfs.cpio.gz
  manifest/
```

## Config Sets

Config sets live under `config-sets/<name>/`:

```text
config-sets/<name>/
  defconfig
  features.fragment
  required-commands.txt
  README.md
```

Current sets and their intended lab payloads:

| Configuration | Purpose | Labs |
| --- | --- | --- |
| `basic` | Core shell, filesystem, file-manipulation, and text-processing commands | 1, 2, 3, 5, 6, 8, 11 |
| `basic-compression` | `basic` plus archive, compression, encoding, and inspection tools | 10, 13, 14 |
| `basic-compression-networking` | `basic-compression` plus IP, DNS, HTTP, and SSH tools | 9 |
| `basic-processes` | `basic` plus procps-ng process inspection and priority tools | 7 |

Every configuration directory contains all four authoritative inputs:

| File | Role |
| --- | --- |
| `defconfig` | Complete Buildroot configuration loaded by the build script |
| `features.fragment` | Human-reviewable list of the profile's significant package selections |
| `required-commands.txt` | Commands that must be present in the finished guest |
| `README.md` | Profile scope, rationale, and profile-specific validation notes |

Use the smallest configuration that satisfies a lab. Labs 4 and 12 do not yet
have payload repositories, so their final configuration assignment remains a
tracked migration decision rather than a checked-in mapping.

The existing config sets were developed against Buildroot `2025.02.15`. The
setup script defaults to `2026.02.3`, the current February LTS line as of
2026-07-07. If a config symbol changes in a newer Buildroot release, set
`BUILDROOT_VERSION=2025.02.15` before running setup, or update the config set
and rerun `make olddefconfig`.

The config sets intentionally do not enable `BR2_DOWNLOAD_FORCE_CHECK_HASHES`.
They use a custom Linux version for the v86-compatible kernel profile, and newer
Buildroot releases may not ship a hash entry for that exact Linux tarball. If
forced hash checking is enabled, Buildroot can fail with `No hash found for
linux-<version>.tar.xz`.

## Host Dependencies

On Ubuntu/Debian, `scripts/01-setup-buildroot.sh` installs the usual Buildroot
host dependencies by default:

```sh
build-essential bc bison ca-certificates cpio file flex git libncurses-dev
make patch perl python3 rsync tar unzip wget xz-utils
```

If your machine is already provisioned, or you are using a non-apt
distribution, install equivalent packages yourself and run:

```sh
scripts/01-setup-buildroot.sh --skip-deps
```

The payload packaging script only needs Python 3. It parses and writes gzipped
`newc` cpio archives directly, so it does not need host `cpio`.

## License

Licensed under the GNU General Public License v3.0. See `LICENSE`.
