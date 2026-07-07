#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILDER_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

INSTALL_DEPS=1

usage() {
  cat <<'USAGE'
Usage:
  01-setup-buildroot.sh [options]

By default this script installs Buildroot host dependencies on Ubuntu/Debian
with apt-get, then downloads and extracts Buildroot.

Options:
  --skip-deps       Do not install host packages; only verify required tools.
  -h, --help        Show this help text.

Environment:
  BUILDROOT_VERSION Override the Buildroot release, default: 2026.02.3
  BUILDROOT_URL     Override the source archive URL
  WORK_DIR          Override the local work directory
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-deps|--no-install-deps)
      INSTALL_DEPS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

BUILDROOT_VERSION=${BUILDROOT_VERSION:-2026.02.3}
BUILDROOT_URL=${BUILDROOT_URL:-"https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz"}
WORK_DIR=${WORK_DIR:-"$BUILDER_DIR/work"}
DOWNLOAD_DIR="$WORK_DIR/downloads"
SRC_DIR="$WORK_DIR/src"
BUILD_DIR="$WORK_DIR/build"
ARTIFACT_DIR="$BUILDER_DIR/artifacts"
ARCHIVE="$DOWNLOAD_DIR/buildroot-${BUILDROOT_VERSION}.tar.xz"
BUILDROOT_SRC="$SRC_DIR/buildroot-${BUILDROOT_VERSION}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required host command: $1" >&2
    exit 1
  }
}

install_deps() {
  if ! command -v apt-get >/dev/null 2>&1; then
    cat >&2 <<'EOF'
This script installs dependencies automatically only on apt-based systems.

Install the equivalent packages for your distribution, then rerun with:
  scripts/01-setup-buildroot.sh --skip-deps

Required Ubuntu/Debian packages:
  build-essential bc bison ca-certificates cpio file flex git libncurses-dev
  make patch perl python3 rsync tar unzip wget xz-utils
EOF
    exit 1
  fi

  SUDO=
  if [ "$(id -u)" -ne 0 ]; then
    need_cmd sudo
    SUDO=sudo
  fi

  echo "Installing Buildroot host dependencies with apt-get."
  $SUDO apt-get update
  $SUDO apt-get install -y \
    build-essential \
    bc \
    bison \
    ca-certificates \
    cpio \
    file \
    flex \
    git \
    libncurses-dev \
    make \
    patch \
    perl \
    python3 \
    rsync \
    tar \
    unzip \
    wget \
    xz-utils
}

if [ "$INSTALL_DEPS" -eq 1 ]; then
  install_deps
else
  echo "Skipping dependency installation."
fi

need_cmd git
need_cmd make
need_cmd patch
need_cmd perl
need_cmd python3
need_cmd rsync
need_cmd tar
need_cmd unzip
need_cmd xz
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "missing required host command: curl or wget" >&2
  exit 1
fi

mkdir -p "$DOWNLOAD_DIR" "$SRC_DIR" "$BUILD_DIR" "$ARTIFACT_DIR"

if [ ! -f "$ARCHIVE" ]; then
  echo "Downloading $BUILDROOT_URL"
  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --output "$ARCHIVE" "$BUILDROOT_URL"
  else
    wget -O "$ARCHIVE" "$BUILDROOT_URL"
  fi
else
  echo "Using existing $ARCHIVE"
fi

if [ ! -d "$BUILDROOT_SRC" ]; then
  echo "Extracting $ARCHIVE"
  tar -C "$SRC_DIR" -xf "$ARCHIVE"
else
  echo "Using existing $BUILDROOT_SRC"
fi

cat > "$BUILDER_DIR/.polylinux-builder.env" <<EOF
BUILDROOT_VERSION=$BUILDROOT_VERSION
BUILDROOT_SRC=$BUILDROOT_SRC
WORK_DIR=$WORK_DIR
BUILD_DIR=$BUILD_DIR
ARTIFACT_DIR=$ARTIFACT_DIR
EOF

echo "Setup complete."
echo "Buildroot source: $BUILDROOT_SRC"
echo "Environment file: $BUILDER_DIR/.polylinux-builder.env"
