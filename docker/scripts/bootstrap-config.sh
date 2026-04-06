#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ROOT=${1:-}
CONFIG_SOURCE=${2:-}
APP_NAME=${3:-${APP_NAME:-nvim}}

if [[ -z "$BUNDLE_ROOT" || -z "$CONFIG_SOURCE" ]]; then
  printf 'usage: %s <bundle-root> <config-source> [app-name]\n' "$0" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_SOURCE/init.lua" ]]; then
  printf 'init.lua not found in %s\n' "$CONFIG_SOURCE" >&2
  exit 1
fi

XDG_CONFIG_HOME="$BUNDLE_ROOT/xdg/config"
XDG_DATA_HOME="$BUNDLE_ROOT/xdg/data"
XDG_STATE_HOME="$BUNDLE_ROOT/xdg/state"
XDG_CACHE_HOME="$BUNDLE_ROOT/xdg/cache"
APP_CONFIG_DIR="$XDG_CONFIG_HOME/$APP_NAME"

# The bundle owns its XDG roots so the packaged Neovim never reads or writes the host user's nvim state.

mkdir -p \
  "$BUNDLE_ROOT/home" \
  "$APP_CONFIG_DIR" \
  "$XDG_DATA_HOME/$APP_NAME" \
  "$XDG_STATE_HOME/$APP_NAME" \
  "$XDG_CACHE_HOME/$APP_NAME"

cp -R "$CONFIG_SOURCE"/. "$APP_CONFIG_DIR"/

# run.sh is the stable entrypoint that recreates the bundle-local environment before launching Neovim.
cat > "$BUNDLE_ROOT/run.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)

export HOME="\$ROOT_DIR/home"
export XDG_CONFIG_HOME="\$ROOT_DIR/xdg/config"
export XDG_DATA_HOME="\$ROOT_DIR/xdg/data"
export XDG_STATE_HOME="\$ROOT_DIR/xdg/state"
export XDG_CACHE_HOME="\$ROOT_DIR/xdg/cache"
export NVIM_APPNAME="$APP_NAME"
export PATH="\$ROOT_DIR/nvim/bin:\$PATH"

exec "\$ROOT_DIR/nvim/bin/nvim" "\$@"
EOF

chmod +x "$BUNDLE_ROOT/run.sh"

printf 'Bundle root: %s\n' "$BUNDLE_ROOT"
printf 'Config source: %s\n' "$CONFIG_SOURCE"
printf 'App name: %s\n' "$APP_NAME"
printf 'XDG_CONFIG_HOME: %s\n' "$XDG_CONFIG_HOME"
printf 'XDG_DATA_HOME: %s\n' "$XDG_DATA_HOME"
printf 'XDG_STATE_HOME: %s\n' "$XDG_STATE_HOME"
printf 'XDG_CACHE_HOME: %s\n' "$XDG_CACHE_HOME"
