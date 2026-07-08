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
cd polylinux-builder

# Optional: override the default LTS release.
# export BUILDROOT_VERSION=2025.02.15

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

Current sets:

- `basic`: shell and setup commands used by simple labs.
- `basic-compression`: `basic` plus archive/compression and inspection tools.
- `basic-compression-networking`: `basic-compression` plus common networking
  tools.

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
