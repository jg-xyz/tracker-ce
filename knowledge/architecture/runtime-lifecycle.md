---
type: Execution Flow
title: Firmware runtime lifecycle
description: Boot, foreground update, and real-time audio callback flow for Tracker CE firmware.
tags: [firmware, runtime, audio, embedded]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: tracker-core
    resource: ../../core/source/Tracker.cpp
    title: Core Tracker lifecycle implementation
  - id: mk66-entry
    resource: ../../platforms/mk66/source/TrackerMain.cpp
    title: Original Tracker setup and loop entry points
  - id: imx-entry
    resource: ../../platforms/imx/source/PlatformTrackerIMX.cpp
    title: i.MX startup and main loop
  - id: tracker-api
    resource: ../../core/include/Tracker.h
    title: Tracker lifecycle interface
---

# Boot path

Each platform creates the process-wide `Tracker` instance and its concrete `PlatformImpl`, initializes hardware, passes audio/input/display callbacks to the hardware layer, initializes the platform, then calls `Tracker::init(platform)`.

The i.MX entry point additionally configures the MPU, pins, clocks, and peripherals; initializes USB before entering the Tracker lifecycle; and enables a malloc failure assertion only after initialization. The MK66 path uses Arduino-style `setup()` and `loop()` entry points.

# Foreground loop

The application loop is cooperative. In [`TrackerImpl::update()`](../../core/source/Tracker.cpp), a sleeping device returns immediately; otherwise it performs:

1. SD streaming update.
2. Display update.
3. A second SD streaming update.
4. Pad-backlight, exporter, slice-detector, file-manager, and UI updates.
5. A final SD streaming update followed by the sequencer update.

The repeated SD streaming calls make refill work available around foreground work rather than deferring it to a single end-of-loop phase.[^tracker-core]

# Real-time audio path

Hardware invokes `Tracker::updateAudioBuffers(left, right, length)` through platform-provided callbacks. The core:

1. Skips normal rendering during offline render mode.
2. Marks the MIDI/audio-block start timestamp and starts profiler timing.
3. Processes MIDI, advances the sequencer using the target sample rate, updates the engine, and fills the output buffers.
4. Stops profiler timing.

The exact sample-rate constant is `44100.0f` for i.MX and `44117.6470588f` for MK66. Input buffers flow separately through `Tracker::updateInputAudioBuffers()` into the engine. On i.MX, the output callback brackets the core render with USB-audio fill calls and input handling also fetches USB input audio.[^imx-entry]

# Change guidance

Preserve the distinction between foreground work and audio callbacks. The foreground loop owns UI, persistence, export, and SD-stream refill scheduling; the audio callback owns MIDI timing, sequencer ticks, engine update, and buffer rendering. Changes that move blocking storage or UI work into the audio path risk real-time failures.

[^tracker-core]: Core Tracker lifecycle implementation
[^imx-entry]: i.MX startup and main loop

