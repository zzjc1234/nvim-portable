# nvim-portable

Build self-contained Neovim bundles from any config repo with reusable GitHub Actions workflows.

## Intuition

The point of this project is to turn a Neovim config into a portable artifact that can be moved and reused as-is.

That is especially useful when:

- the target machine sits inside a company intranet and cannot access GitHub
- the target machine has an unusual architecture and you want a prebuilt bundle for it
- you want the exact same config, plugins, parsers, and runtime layout everywhere

Instead of cloning a config repo and letting the target machine bootstrap itself online, this project builds a portable bundle ahead of time and verifies that it can start from its own internal paths.

## Current scope

This provider currently supports consumers that use `lazy.nvim` as their plugin manager. The shared scripts and default checks assume a `lazy.nvim`-managed bundle layout.

## What this repo provides

- A reusable `workflow_call` GitHub Actions workflow
- Generic scripts to build, smoke-test, package, and verify portable Neovim bundles

## Provider vs consumer responsibilities

| Layer | Repository | Responsibility |
|-------|------------|----------------|
| Provider | `nvim-portable` | Build orchestration, bundle layout, XDG isolation, artifact packaging, fresh-container verification, shared contract enforcement |
| Consumer | your config repo | The actual Neovim config, lazy.nvim bootstrap, repo-specific checks, and declaring what must exist in the final bundle |

The provider answers **how to build and verify a portable bundle**.
The consumer answers **what should be inside this specific bundle**.

## Consumer repo contract

A consumer repo needs to provide:

1. A Neovim config directory containing `init.lua`
2. A bootstrap script that installs `lazy.nvim`, repo-specific plugins, and any other runtime assets into the bundle
3. Optionally, workflow inputs that declare repo-specific bundle paths and Treesitter parsers
4. Optionally, smoke and verify scripts with extra assertions

The reusable workflow handles:

- x64/arm64 matrix orchestration
- artifact upload/download
- bundle packaging
- fresh-container verification
- default lazy.nvim baseline checks

The consumer repo handles:

- config contents
- plugin manager bootstrapping
- parser/tool selection
- repo-specific smoke checks
- repo-specific verify checks

## Example consumer workflow

```yaml
name: build-neovim-bundle

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  bundle:
    uses: zzjc1234/nvim-portable/.github/workflows/neovim-bundle.yml@v1
    with:
      config_path: .config/nvim
      bootstrap_script: .github/nvim/bootstrap.sh
      neovim_version: v0.11.7
      target_arches: amd64,arm64
      build_container_image: ubuntu:24.04
      test_container_image: ubuntu:24.04
      output_dir: .nvim-portable/out
      test_install_root: /opt/nvim-bundle-test
      required_bundle_paths: |
        xdg/data/nvim/lazy/lazy.nvim
        xdg/data/nvim/lazy/telescope.nvim
      required_treesitter_parsers: |
        lua
        vim
        vimdoc
        query
        bash
      smoke_script: .github/nvim/smoke.sh
      verify_script: .github/nvim/verify.sh
      bundle_name: my-nvim
```

## Consumer workflow inputs

The shared workflow accepts multiline string inputs for repo-specific static checks:

```yaml
required_bundle_paths: |
  xdg/data/nvim/lazy/lazy.nvim
  xdg/data/nvim/lazy/telescope.nvim

required_treesitter_parsers: |
  lua
  vim
  vimdoc
  query
  bash
```

Both inputs are optional. The shared build script treats them as post-build assertions without hardcoding plugin or parser lists in the infrastructure repo.

## Build and test container inputs

The reusable workflow now exposes these environment-style knobs through `workflow_call` inputs:

- `target_arches`
- `neovim_version`
- `build_container_image`
- `test_container_image`
- `build_apt_packages`
- `test_apt_packages`
- `output_dir`
- `test_install_root`

That means the consumer workflow, not the shared scripts, decides the target arches, Neovim version, container images, package lists, and artifact output location.

## Consumer bootstrap script contract

The reusable build script exports these variables before calling the consumer bootstrap script:

- `BUNDLE_ROOT`
- `BUNDLE_RUN`
- `XDG_CONFIG_HOME`
- `XDG_DATA_HOME`
- `XDG_STATE_HOME`
- `XDG_CACHE_HOME`
- `NVIM_APPNAME`

These variables are for **consumer hook authors**, not for end users of the final artifact. End users only need to run the bundle's generated `run.sh`.

The bootstrap script can call:

```bash
"$BUNDLE_RUN" --headless "+Lazy! sync" +qa
```

or any equivalent repo-specific setup command.

## Smoke vs verify scripts

- If you provide no override scripts, the shared workflow still performs default startup and stdpath isolation checks.
- `smoke_script` runs after the bundle is built on the CI runner
- `verify_script` runs after the packaged artifact is unpacked inside a fresh offline test container

This split lets each consumer repo keep its own plugin/parser/provider assertions without hardcoding them into shared infrastructure.

## Runtime dependency note

The shared verify container intentionally keeps its package list minimal. If a consumer config performs runtime checks that require extra system tools (for example a compiler toolchain), the consumer should opt in through `test_apt_packages`.

## Fixed assumptions that remain

Some assumptions are still fixed on purpose because they are part of the product contract rather than caller-specific customization:

- supported targets are still `amd64` and `arm64`
- consumers are expected to use `lazy.nvim`
- the bundle archive still contains a top-level `nvim-bundle` directory by default unless `bundle_name` is changed
- the bundle still uses the internal XDG layout plus `run.sh`
- the Neovim download still assumes the official release naming pattern `nvim-linux-<arch>.tar.gz`

These stay fixed because the rest of the scripts and verification flow depend on them as the shared portability contract.

## TODO

- Add first-class support for non-glibc Linux distributions such as Alpine/musl-based systems.

## Refs and versioning

Use semver tags from this repo in consumer workflows, for example `@v1`. The recommended caller pattern is:

```yaml
uses: zzjc1234/nvim-portable/.github/workflows/neovim-bundle.yml@v1
with:
  infra_repository: zzjc1234/nvim-portable
  infra_ref: v1
```

If you want to test unreleased provider changes, point both the reusable workflow ref and `infra_ref` to `main` explicitly.
