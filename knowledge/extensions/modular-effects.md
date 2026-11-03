---
type: Extension Point
title: Modular sample-editor effects
description: `.ptfx` plugin architecture, SDK workflow, and hardware-specific execution constraints.
tags: [effects, sdk, ptfx, samples, extension]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: effects-sdk-guide
    resource: ../../docs/modular_effects_system.md
    title: Modular Effects System and PTFX developer SDK
  - id: root-makefile
    resource: ../../Makefile
    title: PTFX build target
  - id: effects-loader
    resource: ../../core/effector/ptfx_loader.h
    title: PTFX loader resource limits
---

# Extension model

The Sample Editor supports built-in effects and modular `.ptfx` binaries loaded from the SD-card `/Effects/` directory. The host indexes up to 128 plugins, and each plugin can expose up to 12 parameters. The public SDK is [`editor-fx-sdk/tracker_plugin.h`](../../editor-fx-sdk/tracker_plugin.h); reference effect sources are under [`editor-fx-sdk/effects/`](../../editor-fx-sdk/effects/).

# Build workflow

`make ptfx` invokes `editor-fx-sdk/ptfx_builder.py` for every C source in `editor-fx-sdk/effects/` and writes the plugin binaries to `editor-fx-sdk/build/Effects/`. Third-party plugins should use the SDK's binary header, parameter descriptors, host API, lifecycle, and capability flags rather than depending on firmware internals.

# Resource and compatibility limits

| Constraint | MK66 Original Tracker | i.MX Tracker+ / Mini |
|---|---:|---:|
| Plugin code plus BSS | 32 KB | 128 KB |
| Shared effect scratch region | 640 KB after the 128 KB code reservation | 640 KB after the 128 KB code reservation |
| Execution concern | MPU is disabled for plugin code | Loader must synchronize data and instruction caches |

Plugins exceeding the MK66 limit or requiring i.MX performance should declare the i.MX-only capability flag. On i.MX, SD/FatFs reads that reach USDHC DMA must use 4-byte-aligned buffers in DMA-accessible memory (or small reads through the internal bounce buffer).[^effects-sdk-guide]

# Integration boundary

Plugin binaries execute only through the sample-editor loader and share the global scratch allocation with other modal features. Treat plugin loading, cache synchronization, SD reads, and scratch-memory ownership as one lifecycle. See [memory and storage](../architecture/memory-and-storage.md) for the broader shared-memory constraints.

[^effects-sdk-guide]: Modular Effects System and PTFX developer SDK

