---
type: Software Architecture
title: Tracker CE system overview
description: Shared embedded firmware architecture for the three Polyend Tracker hardware targets.
tags: [firmware, architecture, embedded, tracker]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: repository-readme
    resource: ../../README.md
    title: Repository overview and layout
  - id: tracker-implementation
    resource: ../../core/source/Tracker.cpp
    title: Tracker implementation and subsystem initialization
  - id: platform-interface
    resource: ../../core/include/Platform.h
    title: Platform abstraction interface
---

# Structure

Tracker CE is one shared C++ firmware core with two hardware-specific platform implementations. The core is compiled into `libTracker.a`; platform projects link it with their HAL, board support, linker script, and third-party drivers to create the device firmware image.

| Area | Primary path | Responsibility |
|---|---|---|
| Application core | `core/source/` | Tracker singleton, sequencing, MIDI, configuration, theme, hardware-independent state, and application orchestration. |
| User interface | `core/interface/` | UI framework plus pattern, instrument, sample, song, project, performance, configuration, and image-viewer editors. |
| Audio | `core/AudioEngine/`, `core/libs/Audio/` | Audio graph, voices, sequencing integration, streaming, mixing, master processing, and low-level DSP objects. |
| Persistence | `core/FileManager/`, `core/Exporter/` | Project/workspace lifecycle, samples and instruments, imports/exports, recovery, and recording. |
| Offline effects | `core/effector/` | Built-in sample-editor effects and `.ptfx` modular-effect loading and execution. |
| Platform adapters | `platforms/mk66/`, `platforms/imx/` | Startup, board support, storage, display, input, audio/USB drivers, and concrete `Platform` implementations. |
| Shared libraries | `util/`, `synth/` | Utility headers, third-party headers, and the PolySynth SDK/precompiled libraries. |

# Core-to-platform boundary

[`Platform`](../../core/include/Platform.h) is the central hardware boundary. The core receives a `Platform*` during initialization and uses it for display, timers, storage, CRC, buttons/pads, LEDs, battery, MIDI, USB audio, and bootloader/power control. `platforms/mk66/source/PlatformImpl.*` and `platforms/imx/source/PlatformImpl.*` implement that interface for their target family.

The shared core is deliberately not a host application: it expects a bare-metal platform to invoke its lifecycle and real-time buffer callbacks. See [runtime lifecycle](runtime-lifecycle.md) for those calls and [target platforms](target-platforms.md) for target-specific compilation.

# Subsystem initialization order

`TrackerImpl::init()` establishes runtime services in this order:

1. Wavetable envelope and timing helpers.
2. MIDI and power/SD-card callbacks.
3. Optional PolySynth registry and audio engine.
4. Sequencer, pad backlight, exporter, profiler, and file-manager CRC support.
5. Platform configuration, UI, then file manager.

The UI is initialized before the file manager, while the file manager is initialized after it with the platform file system, optional synth registry, and a platform-derived stereo mode.[^tracker-implementation]

[^tracker-implementation]: Tracker implementation and subsystem initialization

