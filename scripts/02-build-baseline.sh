#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILDER_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ENV_FILE="$BUILDER_DIR/.polylinux-builder.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Run scripts/01-setup-buildroot.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
. "$ENV_FILE"

CONFIG_ROOT="$BUILDER_DIR/config-sets"
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}

mapfile -t CONFIG_SETS < <(find "$CONFIG_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if [ "${#CONFIG_SETS[@]}" -eq 0 ]; then
  echo "No config sets found under $CONFIG_ROOT" >&2
  exit 1
fi

if [ "${1:-}" = "--config" ]; then
  SELECTED=${2:-}
else
  echo "Available Buildroot config sets:"
  select choice in "${CONFIG_SETS[@]}"; do
    SELECTED=$choice
    break
  done
fi

if [ -z "${SELECTED:-}" ] || [ ! -d "$CONFIG_ROOT/$SELECTED" ]; then
  echo "Unknown config set: ${SELECTED:-<empty>}" >&2
  exit 1
fi

CONFIG_DIR="$CONFIG_ROOT/$SELECTED"
DEFCONFIG="$CONFIG_DIR/defconfig"
FRAGMENT="$CONFIG_DIR/features.fragment"
BUILD_OUTPUT="$BUILD_DIR/$SELECTED"
STAMP=$(date +%Y%m%d-%H%M%S)
PACKAGE_DIR="$ARTIFACT_DIR/${SELECTED}-${STAMP}"

if [ ! -f "$DEFCONFIG" ]; then
  echo "Missing defconfig: $DEFCONFIG" >&2
  exit 1
fi

mkdir -p "$BUILD_OUTPUT" "$PACKAGE_DIR/images" "$PACKAGE_DIR/configs" "$PACKAGE_DIR/logs" "$PACKAGE_DIR/manifest"

cp "$DEFCONFIG" "$BUILD_OUTPUT/.config"
if [ -f "$FRAGMENT" ]; then
  cat "$FRAGMENT" >> "$BUILD_OUTPUT/.config"
fi
if grep -q '^BR2_DOWNLOAD_FORCE_CHECK_HASHES=y$' "$BUILD_OUTPUT/.config"; then
  echo "Removing BR2_DOWNLOAD_FORCE_CHECK_HASHES=y for custom Linux tarball compatibility."
  sed -i '/^BR2_DOWNLOAD_FORCE_CHECK_HASHES=y$/d' "$BUILD_OUTPUT/.config"
fi

echo "Running olddefconfig for $SELECTED"
make -C "$BUILDROOT_SRC" O="$BUILD_OUTPUT" olddefconfig | tee "$PACKAGE_DIR/logs/olddefconfig.log"

echo "Building $SELECTED with JOBS=$JOBS"
make -C "$BUILDROOT_SRC" O="$BUILD_OUTPUT" -j"$JOBS" 2>&1 | tee "$PACKAGE_DIR/logs/build.log"

BZIMAGE="$BUILD_OUTPUT/images/bzImage"
ROOTFS="$BUILD_OUTPUT/images/rootfs.cpio.gz"
if [ ! -f "$BZIMAGE" ] || [ ! -f "$ROOTFS" ]; then
  echo "Build completed, but expected images were not found under $BUILD_OUTPUT/images" >&2
  exit 1
fi

cp "$BZIMAGE" "$PACKAGE_DIR/images/bzImage"
cp "$ROOTFS" "$PACKAGE_DIR/images/rootfs.cpio.gz"
cp "$BZIMAGE" "$PACKAGE_DIR/images/${SELECTED}-bzImage"
cp "$ROOTFS" "$PACKAGE_DIR/images/${SELECTED}-rootfs.cpio.gz"
cp "$BUILD_OUTPUT/.config" "$PACKAGE_DIR/configs/final-buildroot.config"
cp "$DEFCONFIG" "$PACKAGE_DIR/configs/starting.defconfig"
[ ! -f "$FRAGMENT" ] || cp "$FRAGMENT" "$PACKAGE_DIR/configs/features.fragment"
[ ! -f "$CONFIG_DIR/required-commands.txt" ] || cp "$CONFIG_DIR/required-commands.txt" "$PACKAGE_DIR/manifest/required-commands.txt"

(
  cd "$PACKAGE_DIR/images"
  sha256sum bzImage rootfs.cpio.gz "${SELECTED}-bzImage" "${SELECTED}-rootfs.cpio.gz"
) > "$PACKAGE_DIR/manifest/artifact-sha256.txt"

cat > "$PACKAGE_DIR/manifest/validation-notes.md" <<EOF
# Validation Notes

- Buildroot version: $BUILDROOT_VERSION
- Config set: $SELECTED
- Build output: $BUILD_OUTPUT
- Boot validation: not run by this script.

Run command-presence checks and v86 boot validation before publishing this baseline.
EOF

echo "Baseline package written to $PACKAGE_DIR"
echo "Use this package with scripts/03-package-payload.sh --baseline $PACKAGE_DIR ..."
