#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/resolve-target.sh"

TARGET_ARCH=${TARGET_ARCH:-$(uname -m)}
SOURCE_ROOT=${SOURCE_ROOT:-}
OUTPUT_DIR=${OUTPUT_DIR:-.nvim-portable/out}
BUNDLE_NAME=${BUNDLE_NAME:-nvim-bundle}
TEST_CONTAINER_IMAGE=${TEST_CONTAINER_IMAGE:-ubuntu:24.04}
TEST_APT_PACKAGES=${TEST_APT_PACKAGES:-bash ca-certificates file python3 xz-utils}
TEST_INSTALL_ROOT=${TEST_INSTALL_ROOT:-/opt/nvim-bundle-test}
KEEP_TEST_CONTAINER=${KEEP_TEST_CONTAINER:-0}
VERIFY_SCRIPT=${VERIFY_SCRIPT:-}
ARTIFACT_FILE=${ARTIFACT_FILE:-}

if [[ -z "$SOURCE_ROOT" ]]; then
  printf 'SOURCE_ROOT is required\n' >&2
  exit 1
fi

if [[ -z "$ARTIFACT_FILE" ]]; then
  eval "$(normalize_target_arch "$TARGET_ARCH")"
  ARTIFACT_FILE="${BUNDLE_NAME}-${ARCH_SUFFIX}.tar.gz"
else
  ARCH_SUFFIX="custom"
fi

ARTIFACT_PATH=${ARTIFACT_PATH:-$SOURCE_ROOT/$OUTPUT_DIR/$ARTIFACT_FILE}

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  SOURCE_ROOT="$SOURCE_ROOT" OUTPUT_DIR="$OUTPUT_DIR" BUNDLE_NAME="$BUNDLE_NAME" TARGET_ARCH="$TARGET_ARCH" ARTIFACT_FILE="$ARTIFACT_FILE" bash "$SCRIPT_DIR/package-bundle.sh"
fi

CONTAINER_NAME=${CONTAINER_NAME:-${BUNDLE_NAME}-test-${ARCH_SUFFIX}-$$}

cleanup() {
  if [[ "$KEEP_TEST_CONTAINER" != "1" ]]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

# The container needs network briefly for apt-get, then we detach it before launching the bundle.
docker create --name "$CONTAINER_NAME" "$TEST_CONTAINER_IMAGE" sleep infinity >/dev/null
docker start "$CONTAINER_NAME" >/dev/null
docker exec "$CONTAINER_NAME" bash -lc "export DEBIAN_FRONTEND=noninteractive; apt-get update >/dev/null; apt-get install -y --no-install-recommends $TEST_APT_PACKAGES >/dev/null"

while IFS= read -r network_name; do
  if [[ -n "$network_name" ]]; then
    docker network disconnect "$network_name" "$CONTAINER_NAME" >/dev/null
  fi
done < <(docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$CONTAINER_NAME")

docker cp "$ARTIFACT_PATH" "$CONTAINER_NAME:/tmp/${BUNDLE_NAME}.tar.gz"
# TEST_INSTALL_ROOT stays configurable, but the archive still expands from the bundle's fixed top-level directory.
docker exec -e TEST_INSTALL_ROOT="$TEST_INSTALL_ROOT" -e BUNDLE_NAME="$BUNDLE_NAME" "$CONTAINER_NAME" bash -lc 'mkdir -p "$(dirname "$TEST_INSTALL_ROOT")" && tar -xzf "/tmp/${BUNDLE_NAME}.tar.gz" -C "$(dirname "$TEST_INSTALL_ROOT")" && if [[ "$TEST_INSTALL_ROOT" != "$(dirname "$TEST_INSTALL_ROOT")/$BUNDLE_NAME" ]]; then rm -rf "$TEST_INSTALL_ROOT" && mv "$(dirname "$TEST_INSTALL_ROOT")/$BUNDLE_NAME" "$TEST_INSTALL_ROOT"; fi'

if [[ -n "$VERIFY_SCRIPT" ]]; then
  docker cp "$VERIFY_SCRIPT" "$CONTAINER_NAME:/tmp/consumer-verify.sh"
  docker exec "$CONTAINER_NAME" chmod +x /tmp/consumer-verify.sh
fi

docker exec -e TEST_INSTALL_ROOT="$TEST_INSTALL_ROOT" "$CONTAINER_NAME" bash -lc 'BUNDLE_ROOT="$TEST_INSTALL_ROOT"; BUNDLE_RUN="$BUNDLE_ROOT/run.sh"; if [[ ! -x "$BUNDLE_RUN" ]]; then echo "bundle missing in container" >&2; exit 1; fi; BUNDLE_EXPECTED_ROOT="$BUNDLE_ROOT" "$BUNDLE_RUN" --headless "+lua local root = vim.env.BUNDLE_EXPECTED_ROOT; assert(vim.startswith(vim.fn.stdpath(\"config\"), root .. \"/xdg/config\")); assert(vim.startswith(vim.fn.stdpath(\"data\"), root .. \"/xdg/data\")); assert(vim.startswith(vim.fn.stdpath(\"state\"), root .. \"/xdg/state\")); assert(vim.startswith(vim.fn.stdpath(\"cache\"), root .. \"/xdg/cache\")); print(\"stdpath_ok=true\")" "+lua assert(vim.fn.exists(\":Lazy\") == 2, \"Lazy command missing\"); print(\"lazy_cmd=true\")" "+lua local ok,lazy=pcall(require,\"lazy\"); assert(ok and lazy, \"lazy missing\"); print(\"lazy_count=\" .. lazy.stats().count)" "+lua print(\"startup_ok=true\")" +qa'

if [[ -n "$VERIFY_SCRIPT" ]]; then
  docker exec -e TEST_INSTALL_ROOT="$TEST_INSTALL_ROOT" "$CONTAINER_NAME" bash -lc 'export BUNDLE_ROOT="$TEST_INSTALL_ROOT"; export BUNDLE_RUN="$BUNDLE_ROOT/run.sh"; bash /tmp/consumer-verify.sh'
fi

printf 'Verified container: %s\n' "$CONTAINER_NAME"
if [[ "$KEEP_TEST_CONTAINER" == "1" ]]; then
  printf 'Container preserved. Enter it with:\n  docker exec -it %s bash\n' "$CONTAINER_NAME"
fi
