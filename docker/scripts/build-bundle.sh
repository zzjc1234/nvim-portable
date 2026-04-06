#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRA_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
source "$SCRIPT_DIR/resolve-target.sh"

TARGET_ARCH=${TARGET_ARCH:-$(uname -m)}
SOURCE_ROOT=${SOURCE_ROOT:-}
CONFIG_PATH=${CONFIG_PATH:-}
BOOTSTRAP_SCRIPT=${BOOTSTRAP_SCRIPT:-}
OUTPUT_DIR=${OUTPUT_DIR:-.nvim-portable/out}
BUNDLE_NAME=${BUNDLE_NAME:-nvim-bundle}
APP_NAME=${APP_NAME:-nvim}
NVIM_VERSION=${NVIM_VERSION:-v0.11.7}
BUILD_CONTAINER_IMAGE=${BUILD_CONTAINER_IMAGE:-ubuntu:24.04}
BUILD_APT_PACKAGES=${BUILD_APT_PACKAGES:-bash build-essential ca-certificates curl fd-find file git python3 ripgrep unzip xz-utils}
HOST_UID=${HOST_UID:-$(id -u)}
HOST_GID=${HOST_GID:-$(id -g)}
REQUIRED_BUNDLE_PATHS_INPUT=${REQUIRED_BUNDLE_PATHS:-}
REQUIRED_TREESITTER_PARSERS_INPUT=${REQUIRED_TREESITTER_PARSERS:-}

# Re-entering inside a container keeps host setup minimal while making the actual bundle build reproducible.
if [[ "${1:-}" != "--inside" ]]; then
  if [[ -z "$SOURCE_ROOT" || -z "$CONFIG_PATH" ]]; then
    printf 'SOURCE_ROOT and CONFIG_PATH are required\n' >&2
    exit 1
  fi

  docker run --rm -t \
    -e TARGET_ARCH="$TARGET_ARCH" \
    -e CONFIG_PATH="$CONFIG_PATH" \
    -e BOOTSTRAP_SCRIPT="$BOOTSTRAP_SCRIPT" \
    -e OUTPUT_DIR="$OUTPUT_DIR" \
    -e BUNDLE_NAME="$BUNDLE_NAME" \
    -e APP_NAME="$APP_NAME" \
    -e NVIM_VERSION="$NVIM_VERSION" \
    -e REQUIRED_BUNDLE_PATHS="$REQUIRED_BUNDLE_PATHS_INPUT" \
    -e REQUIRED_TREESITTER_PARSERS="$REQUIRED_TREESITTER_PARSERS_INPUT" \
    -e HOST_UID="$HOST_UID" \
    -e HOST_GID="$HOST_GID" \
    -v "$SOURCE_ROOT":/consumer \
    -v "$INFRA_ROOT":/infra \
    -w /infra \
    "$BUILD_CONTAINER_IMAGE" \
    bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get update >/dev/null; apt-get install -y --no-install-recommends $BUILD_APT_PACKAGES >/dev/null; bash /infra/docker/scripts/build-bundle.sh --inside"
  exit 0
fi

if [[ -z "$CONFIG_PATH" ]]; then
  printf 'CONFIG_PATH is required\n' >&2
  exit 1
fi

# Neovim release assets and artifact suffixes do not use the same architecture strings as GitHub runners.
eval "$(normalize_target_arch "$TARGET_ARCH")"

CONFIG_SOURCE="/consumer/$CONFIG_PATH"
BOOTSTRAP_SOURCE=""
if [[ -n "$BOOTSTRAP_SCRIPT" ]]; then
  BOOTSTRAP_SOURCE="/consumer/$BOOTSTRAP_SCRIPT"
fi

if [[ ! -d "$CONFIG_SOURCE" ]]; then
  printf 'config path not found: %s\n' "$CONFIG_SOURCE" >&2
  exit 1
fi

if [[ -n "$BOOTSTRAP_SOURCE" && ! -f "$BOOTSTRAP_SOURCE" ]]; then
  printf 'bootstrap script not found: %s\n' "$BOOTSTRAP_SOURCE" >&2
  exit 1
fi

BUNDLE_ROOT="/consumer/$OUTPUT_DIR/$BUNDLE_NAME"
ARTIFACT_DIR="$(dirname "$BUNDLE_ROOT")"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz"
TMP_DIR=$(mktemp -d)
OLD_BUNDLE_ROOT=""

cleanup() {
  rm -rf "$TMP_DIR"
  if [[ -n "$OLD_BUNDLE_ROOT" && -e "$OLD_BUNDLE_ROOT" ]]; then
    rm -rf "$OLD_BUNDLE_ROOT" 2>/dev/null || true
  fi
}

trap cleanup EXIT

mkdir -p "$ARTIFACT_DIR"

if [[ -e "$BUNDLE_ROOT" ]]; then
  OLD_BUNDLE_ROOT="${BUNDLE_ROOT}.old.$$.${RANDOM}"
  mv "$BUNDLE_ROOT" "$OLD_BUNDLE_ROOT"
fi

mkdir -p "$BUNDLE_ROOT"

printf 'Target arch: %s\n' "$TARGET_ARCH"
printf 'Bundle root: %s\n' "$BUNDLE_ROOT"
printf 'Config source: %s\n' "$CONFIG_SOURCE"
printf 'Neovim URL: %s\n' "$NVIM_URL"

curl -fL --retry 3 --retry-delay 2 "$NVIM_URL" -o "$TMP_DIR/nvim.tar.gz"
tar -xzf "$TMP_DIR/nvim.tar.gz" -C "$TMP_DIR"
mv "$TMP_DIR/nvim-linux-$NVIM_ARCH" "$BUNDLE_ROOT/nvim"

"$SCRIPT_DIR/bootstrap-config.sh" "$BUNDLE_ROOT" "$CONFIG_SOURCE" "$APP_NAME"

export HOME="$BUNDLE_ROOT/home"
export XDG_CONFIG_HOME="$BUNDLE_ROOT/xdg/config"
export XDG_DATA_HOME="$BUNDLE_ROOT/xdg/data"
export XDG_STATE_HOME="$BUNDLE_ROOT/xdg/state"
export XDG_CACHE_HOME="$BUNDLE_ROOT/xdg/cache"
export NVIM_APPNAME="$APP_NAME"
export PATH="$BUNDLE_ROOT/nvim/bin:$PATH"
export BUNDLE_ROOT
export BUNDLE_RUN="$BUNDLE_ROOT/run.sh"

if [[ -n "$BOOTSTRAP_SOURCE" ]]; then
  bash "$BOOTSTRAP_SOURCE"
fi

if [[ ! -d "$XDG_DATA_HOME/$APP_NAME/lazy/lazy.nvim" ]]; then
  printf 'lazy.nvim not found under %s\n' "$XDG_DATA_HOME/$APP_NAME/lazy/lazy.nvim" >&2
  exit 1
fi

declare -a REQUIRED_BUNDLE_PATH_ITEMS=()
declare -a REQUIRED_TREESITTER_PARSER_ITEMS=()

# GitHub workflow inputs arrive as multiline strings, so the shared script normalizes them once here.
append_multiline_items() {
  local raw_value=$1
  local -n target_array=$2

  if [[ -z "$raw_value" ]]; then
    return
  fi

  while IFS= read -r line; do
    if [[ -n "${line//[[:space:]]/}" ]]; then
      target_array+=("$line")
    fi
  done <<< "$raw_value"
}

append_multiline_items "$REQUIRED_BUNDLE_PATHS_INPUT" REQUIRED_BUNDLE_PATH_ITEMS
append_multiline_items "$REQUIRED_TREESITTER_PARSERS_INPUT" REQUIRED_TREESITTER_PARSER_ITEMS

bundle_path_present() {
  local relative_path=$1
  [[ -e "$BUNDLE_ROOT/$relative_path" ]]
}

managed_parser_present() {
  local parser=$1

  [[ -f "$XDG_DATA_HOME/$APP_NAME/lazy/nvim-treesitter/parser/$parser.so" \
      || -f "$XDG_DATA_HOME/$APP_NAME/site/parser/$parser.so" ]]
}

for parser in "${REQUIRED_TREESITTER_PARSER_ITEMS[@]}"; do
  if managed_parser_present "$parser"; then
    continue
  fi

  "$BUNDLE_RUN" --headless "+TSInstallSync! $parser" +qa
done

declare -a MISSING_BUNDLE_PATHS=()
for relative_path in "${REQUIRED_BUNDLE_PATH_ITEMS[@]}"; do
  if ! bundle_path_present "$relative_path"; then
    MISSING_BUNDLE_PATHS+=("$relative_path")
  fi
done

if (( ${#MISSING_BUNDLE_PATHS[@]} > 0 )); then
  printf 'missing bundle paths: %s\n' "${MISSING_BUNDLE_PATHS[*]}" >&2
  exit 1
fi

declare -a MISSING_PARSERS=()
for parser in "${REQUIRED_TREESITTER_PARSER_ITEMS[@]}"; do
  if ! managed_parser_present "$parser"; then
    MISSING_PARSERS+=("$parser")
  fi
done

if (( ${#MISSING_PARSERS[@]} > 0 )); then
  printf 'missing treesitter parsers: %s\n' "${MISSING_PARSERS[*]}" >&2
  exit 1
fi

# Container builds usually run as root; chown avoids permission surprises for the caller repo on the host side.
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown -R "$HOST_UID:$HOST_GID" "$ARTIFACT_DIR"
fi

printf 'Built bundle: %s\n' "$BUNDLE_ROOT"
printf 'Artifact directory: %s\n' "$ARTIFACT_DIR"
printf 'Artifact stem: %s-%s\n' "$BUNDLE_NAME" "$ARCH_SUFFIX"
