---
type: Resource Constraint
title: Memory and storage architecture
description: Embedded memory budgets, shared scratch ownership, SD sample streaming, and project copy-on-write rules.
tags: [firmware, memory, storage, audio, constraints]
status: draft
generated: { by: process:github-copilot-cli, at: 2026-11-02T17:49:31Z }
sources:
  - id: developer-guide
    resource: ../../docs/developer_guide.md
    title: Firmware architecture, hardware limits, and developer gotchas
  - id: tracker-core
    resource: ../../core/source/Tracker.cpp
    title: External RAM allocation definitions
---

# Memory budget

The main limiting resource is external RAM, not program flash. The developer guide reports approximately 1.13 MB immediately free of 16 MB external RAM on MK66 and approximately 8 KB immediately free of 64 MB external RAM on i.MX. The sample-memory allocation is the intended pressure-relief valve: reducing it can reclaim about 3.5–4 MB on MK66 or about 29 MB on i.MX, subject to retaining enough room for the sample-editor buffer.[^developer-guide]

`Tracker.cpp` statically allocates separate external-RAM regions for sample memory, delay, reverb, and the shared scratch buffer. Do not introduce large unplanned static allocations without revisiting the platform memory map.

# Shared scratch buffer

`externalRamScratchBuff` is a 768 KB shared region. It is intentionally reused by mutually exclusive operations, including `.ptfx` code and scratch memory, offline audio export, SD streaming, and selected UI browsers.

When modular effects are active, their executable code occupies the bottom portion (32 KB on MK66 and up to 128 KB on i.MX); the remaining working area starts at the 128 KB boundary. New features should reuse this buffer only when their lifecycle cannot overlap its established consumers.

# Samples and project persistence

Project loading uses header-only copy-on-write workspace instruments to avoid duplicating large PCM payloads. On project open, workspace files receive the instrument header while audio remains in the project backing file. An edit, import, recording, render, or copy promotes the workspace instrument to a full `.pti`; same-project saves update only changed payloads, whereas Save As materializes a self-contained destination.

Hybrid SD streaming targets large, streamable samples. The guide specifies a 256 KB threshold, a 32,768-frame pre-cache, and foreground ring-buffer refill using FastSeek/direct sector reads. Platform support differs: i.MX supports streamable slice modes, while MK66 keeps slice and beat-slice data resident to protect playback reliability.

# Invariants for major changes

* Preserve `strInstrument` binary layout compatibility; it is directly serialized into `.pti` and guarded by a size assertion.
* Keep `SAMPLE_MEMORY_SIZE` larger than the platform's sample-editor reservation.
* Initialize objects explicitly when placing them in no-init external RAM, because startup does not zero that memory.
* Treat sample streaming, offline effects, and export as resource-sharing concerns, not independent subsystems.

[^developer-guide]: Firmware architecture, hardware limits, and developer gotchas

