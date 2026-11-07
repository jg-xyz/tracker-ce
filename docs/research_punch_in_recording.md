# Research: Punch-In Recording

Question: what would it take to start/stop recording at chosen points while the
project plays, replacing or filling part of a take or sample? Based on reading the
source only; nothing was built or run on hardware.

## Summary

The recorder has no notion of a *position*: every take starts at the beginning of
a buffer and appends. Punch-in is therefore two separate pieces of work: (1) let
playback run during recording (see
[research_record_with_playback](research_record_with_playback.md)), and (2) add a
write-offset / overwrite mode to `Recorder` plus a trigger that arms and releases
it. Piece (2) is small; piece (1) is the large one.

## Current recorder behaviour

[`Recorder`](../core/source/Recorder.cpp) (`Recorder.h`):

* `record()` always sets `recordingHeadIdx = 0` and `isActive = true`; there is no
  start offset parameter.
* `update()` copies whole 128-sample blocks (`AUDIO_BLOCK_SAMPLES`) from the
  `AudioRecordQueue`s into
  `channelConfig[ch].initialAddress[recordingHeadIdx]` and advances the head. Stereo
  and mono destinations are handled; a mono destination from stereo source averages
  L+R.
* Recording ends when `recordingHeadIdx >= maxLength - AUDIO_BLOCK_SAMPLES`
  (calls `finishRecording()` then the full-memory callback), or via `stop()`, which
  drains remaining queue blocks first.
* The take length is exposed as the static `DestinationChannelConfig::length`.
* `crop(start,end)` and `undo()` only move `addresToSave` and `length`; the PCM is
  never copied, which is why the Recorder's undo stack
  (`strUndoCrop`, `undoCount = 5` in `sampleRecorder.h`) is cheap.

So "punch in at sample N of an existing take" cannot be expressed today. Overwrite
is also unsafe in place: the recorder targets `externalRamSampleMemory` (the whole
pool) and the post-record flow reloads project samples from the workspace
([`fSampleRec.cpp`](../core/interface/sampleRecorder/fSampleRec.cpp) `functActionRecord()`
~L1520, exit path ~L2296).

## Where punch points could come from

* **Pre-roll/metronome infrastructure already exists.** The sequencer counts bars
  in `extRecMetronomeStep` and fires `preRollMetronomeEndCalback` on pre-roll end,
  which the recorder uses to start recording
  ([`mtSequencer.cpp`](../core/source/mtSequencer.cpp) ~L183-224;
  `onPreRollMetronomeEnd()` at [`fSampleRec.cpp`](../core/interface/sampleRecorder/fSampleRec.cpp)
  ~L2910; `setPreRollMetronomeEndCallback` in `mtSequencer.h`). A "punch-in step" is
  conceptually another callback on the same step counter (`timerTicks`,
  `kTicksInStep`).
* **Manual punch** reuses the existing record button path: `functRec()` /
  `functActionRecord()` / `functActionStopRec()` already start/stop the take.
* **Pattern markers** would need a new data field; storing them would mean extending
  the project/pattern data (`.mtp` pattern files), a format decision rather than just
  a UI one. Not investigated further.

## Implementation sketch

1. `Recorder::Config` gains `startOffsetFrames` (and optionally `overwriteMode`);
   `record()` sets `recordingHeadIdx = startOffsetFrames` instead of 0 and
   `DestinationChannelConfig::length` becomes `max(length, head)` at stop.
2. Keep block alignment: `AUDIO_BLOCK_SAMPLES = 128` frames (~2.9 ms @ 44.1 kHz).
   Punch positions are quantised to blocks unless the first/last block is handled
   specially (copy only part of the block into the destination).
3. Click avoidance at the edges: apply a short ramp on the first/last partially
   recorded block; the existing `crop()` path has no fades.
4. Undo: before overwriting, the old region must be saved or the whole take
   duplicated (`strUndoCrop` stores addresses, not audio). This is the main cost of
   true overwrite; a simpler first version is "record new take starting at an
   offset in a fresh buffer, then merge".
5. Triggers: manual (button), and step-synchronised using the pre-roll counter.

## Interactions and risks

* Depends on playback during recording; the memory-sharing problem described in
  [research_record_with_playback](research_record_with_playback.md) applies in full.
* Latency: input queue blocks are read in the main loop (`recorder.update()`), and the
  audio path has buffering; the audible alignment between what was heard and what
  was recorded is *not* characterised. Any punch-in that must be sample-accurate needs
  a measured round-trip offset per platform (MK66 vs i.MX), unmeasured here.
* Mono vs stereo: mono sources (mic) write one channel; overwriting a stereo take
  with mono input needs a rule.
* Recording length limit and "memory full" callback semantics change when the head
  starts mid-buffer.

## Open questions

* Overwrite an existing sample/instrument, or create a new one from the take?
* Where is the punch region edited/previewed - the Sample Recorder or the Sample
  Editor ([`core/interface/sampleEditor/`](../core/interface/sampleEditor/))?
* Is quantising to pattern steps acceptable, or does it need free positioning?
