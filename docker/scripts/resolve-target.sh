#!/usr/bin/env bash
set -euo pipefail

normalize_target_arch() {
  local raw_arch=$1

  # The rest of the toolchain wants one normalized target plus the Neovim asset name and artifact suffix.

  case "$raw_arch" in
    x86_64|amd64)
      printf 'TARGET_ARCH=amd64\n'
      printf 'NVIM_ARCH=x86_64\n'
      printf 'ARCH_SUFFIX=linux-x86_64\n'
      ;;
    aarch64|arm64)
      printf 'TARGET_ARCH=arm64\n'
      printf 'NVIM_ARCH=arm64\n'
      printf 'ARCH_SUFFIX=linux-arm64\n'
      ;;
    *)
      printf 'unsupported TARGET_ARCH: %s\n' "$raw_arch" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  normalize_target_arch "${1:-$(uname -m)}"
fi
