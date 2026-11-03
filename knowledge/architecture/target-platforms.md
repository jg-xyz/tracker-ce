---
type: Platform Architecture
title: Firmware target platforms
description: Hardware families, compiler selection, and product-specific feature boundaries for Tracker CE.
tags: [firmware, platforms, mk66, imx, build]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: repository-readme
    resource: ../../README.md
    title: Supported hardware overview
  - id: root-makefile
    resource: ../../Makefile
    title: Unified firmware build targets
  - id: core-makefile
    resource: ../../core/makefile
    title: Shared core compilation configuration
  - id: mk66-makefile
    resource: ../../platforms/mk66/makefile
    title: MK66 platform build configuration
  - id: imx-makefile
    resource: ../../platforms/imx/makefile
    title: i.MX platform build configuration
---

# Product matrix

| Product | Platform | CPU | Top-level target | Firmware artifact |
|---|---|---|---|---|
| Original Tracker | `MK66` | Kinetis MK66, Cortex-M4F at 180 MHz | `make original` | `build/PolyendTracker_CE_<version>.ptf` |
| Tracker+ | `IMX` | i.MX RT1051/RT1064, Cortex-M7 at 600 MHz | `make plus` | `build/TrackerPlus_CE_<version>.ptf` |
| Tracker Mini | `IMX` | i.MX RT1051/RT1064, Cortex-M7 at 600 MHz | `make mini` | `build/TrackerMini_CE_<version>.ptf` |

# Compile-time boundaries

The core makefile accepts `PLATFORM` and `PRODUCT`. `PLATFORM=MK66` compiles for Cortex-M4F; `PLATFORM=IMX` compiles for Cortex-M7, defines `PLATFORM_IMX`, and enables `FEATURE_SYNTH`. `PRODUCT=MINI` additionally defines `TRACKER_MINI`.

Consequently, Tracker+ and Tracker Mini build the PolySynth-enabled core and link `libPolySynth.a` and `libPolyDSP.a`; the Original Tracker does not enable `FEATURE_SYNTH`. Product conditionals should use these established macros rather than platform directory checks.

# Packaging flow

The root makefile builds the shared static library first, then the platform image. Each platform linker produces an ELF (`.axf`); `arm-none-eabi-objcopy` converts it to the distributable Intel-hex-format `.ptf`. The root target copies that artifact into `build/` with an edition and version postfix from [`version.mk`](../../version.mk).

Use the target-specific entry points for hardware changes and keep shared behavior inside `core/`. The `Platform` interface is the preferred addition point when a new common hardware capability is needed; both platform implementations must then remain consistent.

[^root-makefile]: Unified firmware build targets
[^core-makefile]: Shared core compilation configuration

