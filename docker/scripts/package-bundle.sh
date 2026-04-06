#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/resolve-target.sh"

TARGET_ARCH=${TARGET_ARCH:-$(uname -m)}
SOURCE_ROOT=${SOURCE_ROOT:-}
OUTPUT_DIR=${OUTPUT_DIR:-.nvim-portable/out}
BUNDLE_NAME=${BUNDLE_NAME:-nvim-bundle}
ARTIFACT_FILE=${ARTIFACT_FILE:-}

if [[ -z "$SOURCE_ROOT" ]]; then
  printf 'SOURCE_ROOT is required\n' >&2
  exit 1
fi

if [[ -z "$ARTIFACT_FILE" ]]; then
  eval "$(normalize_target_arch "$TARGET_ARCH")"
  ARTIFACT_FILE="${BUNDLE_NAME}-${ARCH_SUFFIX}.tar.gz"
fi

BUNDLE_ROOT="$SOURCE_ROOT/$OUTPUT_DIR/$BUNDLE_NAME"
ARTIFACT_PATH=${ARTIFACT_PATH:-$SOURCE_ROOT/$OUTPUT_DIR/$ARTIFACT_FILE}
TMP_ARTIFACT="${ARTIFACT_PATH}.tmp"
STAGE_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$STAGE_DIR"
}

trap cleanup EXIT

if [[ ! -x "$BUNDLE_ROOT/run.sh" ]]; then
  printf 'bundle not found at %s\n' "$BUNDLE_ROOT" >&2
  exit 1
fi

mkdir -p "$(dirname "$ARTIFACT_PATH")"
rm -f "$TMP_ARTIFACT"
# Archive from a staged snapshot so tar does not race against mutations in the live bundle tree.
tar -C "$SOURCE_ROOT/$OUTPUT_DIR" -cf - "$BUNDLE_NAME" | tar -C "$STAGE_DIR" -xf -
# COPYFILE_DISABLE keeps macOS metadata out of Linux bundle archives when callers package locally.
COPYFILE_DISABLE=1 tar -C "$STAGE_DIR" -czf "$TMP_ARTIFACT" "$BUNDLE_NAME"
mv "$TMP_ARTIFACT" "$ARTIFACT_PATH"

printf 'Artifact: %s\n' "$ARTIFACT_PATH"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARTIFACT_PATH"
fi
