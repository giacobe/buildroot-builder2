#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILDER_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd -- "$BUILDER_DIR/.." && pwd)
PACKAGER="$REPO_ROOT/tools/package_rootfs_payload.py"

REPO_URL=
REF=
PAYLOAD_SUBDIR=.
BASELINE_DIR=
OUTPUT_DIR=
OUTPUT_PREFIX=packaged
RENAME_TO_INSTALL=
FORCE=0

usage() {
  cat <<'USAGE'
Usage:
  03-package-payload.sh --repo URL --baseline DIR --output DIR [options]

Required:
  --repo URL                 Git repository containing files to add under /root
  --baseline DIR             Baseline package dir, or dir containing bzImage and rootfs.cpio.gz
  --output DIR               Output directory for packaged images

Options:
  --ref REF                  Git branch, tag, or commit to checkout
  --payload-subdir DIR       Subdirectory inside the cloned repo to package, default: .
  --output-prefix NAME       Output names: NAME.bzImage and NAME.rootfs.cpio.gz
  --rename-to-install FILE   Remove install.sh and copy FILE to install.sh in the staged payload
  --force                    Overwrite output files
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) REPO_URL=$2; shift 2 ;;
    --ref) REF=$2; shift 2 ;;
    --payload-subdir) PAYLOAD_SUBDIR=$2; shift 2 ;;
    --baseline) BASELINE_DIR=$2; shift 2 ;;
    --output) OUTPUT_DIR=$2; shift 2 ;;
    --output-prefix) OUTPUT_PREFIX=$2; shift 2 ;;
    --rename-to-install) RENAME_TO_INSTALL=$2; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$REPO_URL" ] || { echo "--repo is required" >&2; exit 2; }
[ -n "$BASELINE_DIR" ] || { echo "--baseline is required" >&2; exit 2; }
[ -n "$OUTPUT_DIR" ] || { echo "--output is required" >&2; exit 2; }
[ -f "$PACKAGER" ] || { echo "packager not found: $PACKAGER" >&2; exit 2; }

WORK_DIR=${WORK_DIR:-"$BUILDER_DIR/work"}
PAYLOAD_WORK="$WORK_DIR/payload"
REPO_NAME=$(basename "$REPO_URL" .git)
CLONE_DIR="$PAYLOAD_WORK/$REPO_NAME/repo"
STAGE_DIR="$PAYLOAD_WORK/$REPO_NAME/staged"

mkdir -p "$PAYLOAD_WORK"
if [ ! -d "$CLONE_DIR/.git" ]; then
  git clone "$REPO_URL" "$CLONE_DIR"
else
  git -C "$CLONE_DIR" fetch --all --tags
fi

if [ -n "$REF" ]; then
  git -C "$CLONE_DIR" checkout "$REF"
else
  git -C "$CLONE_DIR" checkout "$(git -C "$CLONE_DIR" symbolic-ref --short refs/remotes/origin/HEAD | sed 's|^origin/||')"
  git -C "$CLONE_DIR" pull --ff-only
fi

PAYLOAD_SOURCE="$CLONE_DIR/$PAYLOAD_SUBDIR"
[ -d "$PAYLOAD_SOURCE" ] || { echo "payload subdirectory not found: $PAYLOAD_SOURCE" >&2; exit 2; }

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
tar -C "$PAYLOAD_SOURCE" --exclude=.git -cf - . | tar -C "$STAGE_DIR" -xf -

if [ -n "$RENAME_TO_INSTALL" ]; then
  [ -f "$PAYLOAD_SOURCE/$RENAME_TO_INSTALL" ] || {
    echo "rename source not found in payload: $PAYLOAD_SOURCE/$RENAME_TO_INSTALL" >&2
    exit 2
  }
  rm -f "$STAGE_DIR/install.sh"
  cp "$PAYLOAD_SOURCE/$RENAME_TO_INSTALL" "$STAGE_DIR/install.sh"
  rm -f "$STAGE_DIR/$RENAME_TO_INSTALL"
fi

if [ -d "$BASELINE_DIR/images" ]; then
  BZIMAGE="$BASELINE_DIR/images/bzImage"
  ROOTFS="$BASELINE_DIR/images/rootfs.cpio.gz"
else
  BZIMAGE="$BASELINE_DIR/bzImage"
  ROOTFS="$BASELINE_DIR/rootfs.cpio.gz"
fi
[ -f "$BZIMAGE" ] || { echo "baseline bzImage not found: $BZIMAGE" >&2; exit 2; }
[ -f "$ROOTFS" ] || { echo "baseline rootfs.cpio.gz not found: $ROOTFS" >&2; exit 2; }

FORCE_ARG=
[ "$FORCE" -eq 0 ] || FORCE_ARG=--force

python3 "$PACKAGER" \
  --bzimage "$BZIMAGE" \
  --rootfs "$ROOTFS" \
  --payload-dir "$STAGE_DIR" \
  --output-dir "$OUTPUT_DIR" \
  --output-bzimage-name "${OUTPUT_PREFIX}.bzImage" \
  --output-rootfs-name "${OUTPUT_PREFIX}.rootfs.cpio.gz" \
  $FORCE_ARG

git -C "$CLONE_DIR" rev-parse HEAD > "$OUTPUT_DIR/manifest/payload-git-commit.txt"
printf '%s\n' "$REPO_URL" > "$OUTPUT_DIR/manifest/payload-git-url.txt"
echo "Packaged payload written to $OUTPUT_DIR"
