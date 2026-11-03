---
type: Build Workflow
title: Firmware build and release workflow
description: GNU Arm build commands, version selection, and artifact paths for all Tracker CE products.
tags: [build, release, toolchain, firmware]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: repository-readme
    resource: ../../README.md
    title: Build prerequisites and commands
  - id: root-makefile
    resource: ../../Makefile
    title: Build orchestration and packaging
  - id: version-makefile
    resource: ../../version.mk
    title: Centralized product version configuration
---

# Toolchain

Firmware uses GNU Arm Embedded Toolchain `10.3-2021.10`, `make`, and Python 3. The root makefile prefers a repository-local `agt/10.3/bin/arm-none-eabi-` prefix when present; otherwise it uses `arm-none-eabi-` from `PATH`. Override it with `TOOLCHAIN=/path/to/arm-none-eabi-` when necessary.

# Commands

| Command | Result |
|---|---|
| `make all` | Builds Original Tracker, Tracker+, and Tracker Mini. |
| `make original` | Builds the MK66 Original Tracker image. |
| `make plus` | Builds the i.MX Tracker+ image. |
| `make mini` | Builds the i.MX Tracker Mini image. |
| `make ptfx` | Compiles each `editor-fx-sdk/effects/*.c` source into `editor-fx-sdk/build/Effects/*.ptfx`. |
| `make clean` | Cleans all platform/core build outputs and generated effect binaries. |
| `make version` | Displays configured versions, build tag, and output filenames. |

# Versioning

`version.mk` is the canonical version source. It holds separate major/minor/patch/beta values for `ORIGINAL`, `PLUS`, and `MINI`, then selects firmware defines from `PRODUCT`. `BUILD_TAG` defaults to the current short Git revision and becomes the build identifier.

Use `make bump-patch TARGET=all|original|plus|mini` for patch increments and `make bump-minor TARGET=...` for minor increments; the latter resets the patch component. These commands edit `version.mk`, so review and commit that file with the release change.

# Outputs

Platform builds first produce a platform-local `.axf` and `.ptf`; root targets copy the final `.ptf` into the repository `build/` directory. Output names include the edition and selected product version. The Original Tracker's firmware filename must remain within the bootloader's documented 31-character limit.[^repository-readme]

[^repository-readme]: Build prerequisites and commands

