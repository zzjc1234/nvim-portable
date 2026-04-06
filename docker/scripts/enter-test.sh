#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/resolve-target.sh"

TARGET_ARCH=${TARGET_ARCH:-$(uname -m)}
SOURCE_ROOT=${SOURCE_ROOT:-}
OUTPUT_DIR=${OUTPUT_DIR:-.nvim-portable/out}
BUNDLE_NAME=${BUNDLE_NAME:-nvim-bundle}
ARTIFACT_PATH=${ARTIFACT_PATH:-}
ARTIFACT_FILE=${ARTIFACT_FILE:-}

if [[ -z "$SOURCE_ROOT" ]]; then
  printf 'SOURCE_ROOT is required\n' >&2
  exit 1
fi

if [[ -z "$ARTIFACT_PATH" ]]; then
  if [[ -z "$ARTIFACT_FILE" ]]; then
    eval "$(normalize_target_arch "$TARGET_ARCH")"
    ARTIFACT_FILE="${BUNDLE_NAME}-${ARCH_SUFFIX}.tar.gz"
  fi
  ARTIFACT_PATH="$SOURCE_ROOT/$OUTPUT_DIR/$ARTIFACT_FILE"
fi

# Reuse the normal verification path first so the interactive shell lands in the same environment CI would validate.
CONTAINER_NAME=${CONTAINER_NAME:-${BUNDLE_NAME}-enter-$$}
KEEP_TEST_CONTAINER=1 CONTAINER_NAME="$CONTAINER_NAME" TARGET_ARCH="$TARGET_ARCH" SOURCE_ROOT="$SOURCE_ROOT" OUTPUT_DIR="$OUTPUT_DIR" BUNDLE_NAME="$BUNDLE_NAME" ARTIFACT_PATH="$ARTIFACT_PATH" ARTIFACT_FILE="${ARTIFACT_FILE:-}" VERIFY_SCRIPT="${VERIFY_SCRIPT:-}" TEST_CONTAINER_IMAGE="${TEST_CONTAINER_IMAGE:-}" TEST_APT_PACKAGES="${TEST_APT_PACKAGES:-}" TEST_INSTALL_ROOT="${TEST_INSTALL_ROOT:-}" bash "$SCRIPT_DIR/test-bundle.sh"
docker exec -it "$CONTAINER_NAME" bash
