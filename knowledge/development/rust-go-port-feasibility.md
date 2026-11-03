---
type: Feasibility Study
title: Feasibility of porting Tracker CE firmware to Rust or Go
description: Go is infeasible for this hard-real-time bare-metal firmware; Rust/Zig/C3 are viable only as incremental C-ABI library strategies, blocked at full-port scale by proprietary C++ libraries and the driver surface.
tags: [port, rust, go, zig, c3, feasibility, architecture]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T19:47:45Z }
sources:
  - id: codebase-metrics
    resource: ../../
    title: Source tree metrics (LOC by subsystem, 2026-11-02)
  - id: proprietary-license
    resource: ../../synth/lib/LICENSE-PROPRIETARY.txt
    title: Polyend Precompiled Synthesizer & DSP Library License
  - id: polysynth-sdk
    resource: ../../synth/include/PolySynth/sdk/InstrumentType.h
    title: C++ ABI surface of the PolySynth SDK
  - id: audio-block-config
    resource: ../../platforms/imx/config/config.h
    title: Real-time audio block configuration
  - id: imx-entry
    resource: ../../platforms/imx/source/PlatformTrackerIMX.cpp
    title: Bare-metal startup, XIP, and malloc instrumentation
---

# Verdict

| Target language | Verdict | One-line reason |
|---|---|---|
| **Go** (incl. TinyGo) | **Not feasible** | No hard-real-time guarantees (GC, scheduler), immature bare-metal Cortex-M support, and no practical way to link the mandatory GCC/ARM C++ static libraries. |
| **Rust** | **Technically feasible, practically a multi-year rewrite** | `no_std` Cortex-M is mature and real-time-capable, but the port is blocked at full scale by two proprietary C++ archives and ~450 KLOC of C/C++ including platform SDKs. |
| **Zig** | **Same verdict as Rust** | Excellent freestanding support and C interop, but cannot consume the C++ PolySynth ABI and has a thinner Cortex-M ecosystem; `zig c++` as toolchain breaks on libstdc++ ABI (i.MX only). |
| **C3** | **Not advisable** | Best-in-class C interop, but pre-1.0 maturity, community-grade Cortex-M support, and the same C++ wall. |

# Hard constraints that shape any port

1. **Hard real-time audio.** Both platforms render audio in 128-sample blocks (`kAudioBlockSamples`)[^audio-block-config] at ~44.1 kHz: a ~2.9 ms deadline per block, with ISR-level playback in `core/libs/Audio/play_memory.cpp`. Any language with a stop-the-world GC or a preemptive scheduler in the audio path (Go/TinyGo) fails this by construction.
2. **No hosted runtime.** Builds are `-ffreestanding -fno-builtin -fno-exceptions -fno-rtti`, `nano.specs`; i.MX boots XIP from QSPI flash at `0x60030000` with custom linker scripts and manual cache/MPU maintenance.[^imx-entry]
3. **Proprietary binary dependencies.** Tracker+ / Tracker Mini must link `libPolySynth.a` and `libPolyDSP.a` (precompiled, no source). Their license permits use **only** for firmware targeting authentic Polyend hardware and forbids reverse-engineering.[^proprietary-license] The public SDK headers are C++: `virtual` interfaces, `std::shared_ptr`/`std::unique_ptr`, `std::span`, and Itanium-mangled symbols (e.g. `polysynth::StdFileSystem::open(...)`) compiled with arm-none-eabi-gcc.[^polysynth-sdk]
4. **Code volume.** Roughly 244 KLOC of project C/C++ (core ~159 KLOC, platform code ~72 KLOC) plus ~211 KLOC of vendored third-party code (Teensy core for MK66; NXP MCUXpresso SDK, USB host/device stacks, FatFs/SDMMC for i.MX).[^codebase-metrics]

# Go analysis

* **Runtime mismatch:** Go's GC and goroutine scheduler assume an OS; TinyGo targets Cortex-M but still carries a GC and a conservative runtime, cannot guarantee sub-3 ms ISR deadlines, and has no path to the NXP/Teensy peripheral drivers this firmware depends on.
* **FFI mismatch:** TinyGo's CGo support is limited and cannot consume GCC-built C++ archives with virtual-class APIs; the PolySynth libraries are mandatory for Tracker+ / Mini (synth feature) and cannot be substituted without violating their license or rewriting the DSP.
* **Conclusion:** No viable path, even partial. Go is ruled out for the firmware itself; it remains a fine choice for **host tooling** (e.g. a replacement `ptfx_builder.py`, project-file inspectors like `tracker-lib`).

# Rust analysis

## What works in Rust's favor

* Mature bare-metal Cortex-M support: `no_std`, `cortex-m`/`cortex-m-rt`, PACs for Kinetis/i.MX RT (via `svd2rust`), Embassy/RTIC for async and real-time scheduling, `embedded-hal` traits.
* No GC, deterministic ISR-capable code, C-compatible FFI in both directions, and LLVM can emit code satisfying the audio deadline.
* The `Platform` abstraction (`core/include/Platform.h`) is a clean, flat vtable of hardware capabilities — a natural Rust `trait` boundary.

## Blocking issues

1. **PolySynth libraries (showstopper for a full port).** They export C++ symbols, not a C API. Rust cannot call C++ virtual interfaces across FFI without either (a) maintaining the exact Itanium/GCC ABI layout by hand, or (b) writing a C++ shim that exposes a C API — but the shim still has to be C++ and linked into the final firmware, meaning **the final artifact is never a pure-Rust build**. The license forbids reimplementing their DSP for non-Polyend targets and forbids reverse-engineering outright.[^proprietary-license]
2. **Driver surface.** MK66 needs Teensy-core equivalents (SGTL5000 codec, EEPROM, FT812 display, SD/FatFs, USB MIDI/audio); i.MX needs the MCUXpresso stack (USB device audio/MSC/CDC, USDHC SDMMC with ADMA2, QSPI XIP flash, SEMC SDRAM). Only fragments exist in the Rust ecosystem; most would be written from scratch against the reference manuals.
3. **Memory-layout discipline.** The firmware relies on precise linker-section placement (`.sample_memory`, `.scratch_memory`, `.noinit_RAM4`), no-init SDRAM singletons, and manual D-cache maintenance for DMA/plugins. All reproducible in Rust, but each is bespoke linker/unsafe work, not ecosystem defaults.
4. **Scale.** Even with perfect tooling, ~450 KLOC of behavior — including binary-compatible `.mt`/`.mtp`/`.pti` file formats, the FT812 UI, and the sequencer — must be reproduced bit-exactly to keep project compatibility.

## Realistic incremental path (recommended if pursued)

1. **Rust-as-a-library, not Rust-as-the-firmware.** Compile Rust modules to a `staticlib` with `extern "C"` APIs and link them into the existing GCC build (same pattern as `libTracker.a`). Candidates: leaf, pure-logic modules with no C++ dependencies — file-format parsing (`tracker-lib`-style code), CRC, theme/JSON handling, new DSP effects.
2. **New subsystems in Rust.** Any *new* feature (e.g. a new `.ptfx`-style offline effect, a new file importer) can be authored in Rust behind a C ABI from day one.
3. **Do not port:** the audio ISR path, the platform HALs, or anything touching `libPolySynth.a` — replace-or-shim costs exceed rewrite value there.
4. **Tooling in any language.** Host-side tools (`ptfx_builder`, validators, project converters) can be Go or Rust freely; the MIT-licensed `editor-fx-sdk/` and the docs impose no constraints there.

# C3 and Zig (follow-up analysis, 2026-11-02)

Both are C-family, GC-free, LLVM-based systems languages with first-class C ABI interop — which makes them strictly better candidates than Go, but neither removes the two structural blockers (C++ ABI proprietary libraries, platform SDK driver surface).

## Zig

* **Freestanding support:** first-class `arm-freestanding-eabihf` target, no libc required, comptime and explicit allocators fit bare-metal work well. `MicroZig` provides an embedded framework, but has no Kinetis MK66 or i.MX RT1051 chip support — the HAL/driver layer would still be written from scratch, as with Rust, with a thinner ecosystem (no RTIC/Embassy equivalent).
* **C++ wall (unchanged):** `@cImport` consumes C headers only. `libPolySynth.a`/`libPolyDSP.a` expose C++ classes (`std::shared_ptr`, `std::span`, libstdc++ `std::__cxx11::basic_string`)[^polysynth-sdk] — a full port still requires a C++ shim, so the artifact is never pure-Zig.
* **Unique angle — Zig as toolchain:** `zig cc` can cross-compile the vendored C code today. However `zig c++` hardcodes libc++, whose `std::string`/container layouts are ABI-incompatible with the GCC libstdc++ used to build the PolySynth archives — so `zig c++` **cannot** link the i.MX products. The MK66 build links only `libTracker` (C++, self-consistent under one compiler) and `libarm_cortexM4lf_math` (C, ABI-safe), so a `zig c++` toolchain experiment is plausible for Original Tracker only, and buys little over the pinned GCC 10.3 toolchain.
* **As an incremental port language:** as viable as Rust (compile to a staticlib, export `extern "C"`, link into the GCC build) with lower interop friction, but weaker memory-safety guarantees and a smaller embedded ecosystem.

## C3

* **Interop:** full C ABI compatibility by design — C and C3 mix in one project with no bindings layer, making it the lowest-friction incremental option of the four languages considered.
* **Freestanding support:** c3c offers freestanding targets (LLVM backend), but Cortex-M support is community-grade: no mature HAL crates, no RTIC/Embassy analogue, no MK66/i.MX-RT board support.
* **C++ wall (unchanged):** C ABI compatibility does not extend to C++; the PolySynth libraries remain reachable only through a C++ shim.
* **Maturity risk:** pre-1.0 language with a small community; betting a multi-year firmware maintenance story on it is the highest project risk of the options.

## Updated decision summary

| Language | Full firmware port | Incremental (C-ABI staticlib into GCC build) | Host tooling |
|---|---|---|---|
| Go / TinyGo | Not feasible | Not practical | Fine |
| Rust | Possible, not economical | Feasible (recommended) | Fine |
| Zig | Possible, not economical | Feasible (viable alternative) | Fine |
| C3 | Highest risk, not advisable | Easiest interop, but ecosystem/maturity risk | Fine |

The two structural blockers — the libstdc++-ABI PolySynth binaries and the ~211 KLOC of vendored platform SDKs (Teensy core, MCUXpresso) — are language-independent. No alternative systems language changes the recommendation: keep the C++ firmware, add new leaf modules behind a C ABI in the language of choice, and keep host tooling free-form.

[^codebase-metrics]: Source tree metrics (LOC by subsystem, 2026-11-02)
[^proprietary-license]: Polyend Precompiled Synthesizer & DSP Library License
[^polysynth-sdk]: C++ ABI surface of the PolySynth SDK
[^audio-block-config]: Real-time audio block configuration
[^imx-entry]: Bare-metal startup, XIP, and malloc instrumentation
