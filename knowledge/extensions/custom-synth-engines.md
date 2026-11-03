---
type: Extension Point
title: Custom synth engine integration
description: Open PolySynth engine extension path for Tracker+ and Tracker Mini firmware.
tags: [synth, sdk, extension, imx]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: synth-sdk-guide
    resource: ../../docs/custom_synth_sdk.md
    title: Custom Synth Engine SDK developer guide
  - id: synth-registry
    resource: ../../core/synth/registry.cpp
    title: Registered synth-engine factories
  - id: core-build
    resource: ../../core/makefile
    title: Feature-gated core build configuration
---

# Scope

Custom synth engines are a Tracker+ and Tracker Mini extension seam. The core enables `FEATURE_SYNTH` only for `PLATFORM=IMX`; on those products, `TrackerImpl` constructs and initializes the shared synth runtime before the audio engine and UI.[^core-build]

# Registration model

`InstrumentTypeRegistry::registerInstrumentTypes()` in [`core/synth/registry.cpp`](../../core/synth/registry.cpp) registers built-in factories from the precompiled PolySynth libraries and the open-source Chiptune factory. A new engine is registered there by instrument-type ID and factory; this does not require recompiling `libPolySynth.a` or `libPolyDSP.a`.

The SDK guide specifies the associated integration work:

1. Add an `InstrumentTypeId` and update its terminal synth marker in `synth/include/PolySynth/config.h`.
2. Implement the voice and factory using the public headers in `synth/include/PolySynth/sdk/`.
3. Add the type to `Synth::kSynthTypes`.
4. Register the factory in `core/synth/registry.cpp`.
5. Add display name and mini/medium icon IDs to the instrument-editor and FT812 bitmap tables.

# Constraints

Only active synth slots instantiate voices, but registry entries exist at boot. Keep inactive-engine RAM small: use `CustomSynthVoice`/`ParamHelper` rather than per-parameter `std::function` state, and place large shared tables in flash or external RAM. Icon additions also consume the FT812 bitmap RAM budget.[^synth-sdk-guide]

The existing [`core/synth/engines/`](../../core/synth/engines/) implementation is the local reference for an engine that ships as source.

[^core-build]: Feature-gated core build configuration
[^synth-sdk-guide]: Custom Synth Engine SDK developer guide

