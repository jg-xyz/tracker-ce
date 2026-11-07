# Research: Song/Pattern Playback During Sample Recording

Question: can the sequencer (song or pattern) keep playing while the Sample
Recorder is recording? Findings are from reading the source; nothing here was
built or run on hardware. Line numbers refer to the tree at the time of writing.

## Summary

Today the recorder is deliberately exclusive: entering it with the sequencer
running forces a stop prompt, and entering it silences the whole mix. Lifting that
needs more than flipping a flag, because **recording overwrites the same memory
the project plays its samples from**. That memory conflict is the main blocker;
the audio-routing part is comparatively small.

## What happens today

### Entry: the stop-pattern prompt

[`cSampleRecorder::start()`](../core/interface/sampleRecorder/fSampleRec.cpp)
(~L280) checks `sequencer.isPlay()`. If playing it sets `patternIsPlayingFlag`,
shows a "stop pattern?" selection (`showSelectionStopPattern()`), and installs
only two buttons (`setStopSeqFunctions()`, ~L494). `functStopPatternYes()`
(~L1384) calls `sequencer.stop()` and restarts `start(0)`; `functStopPatternCancel()`
returns to the previous module. `stop()` (~L399) mirrors this: if the flag was
set it only clears it, otherwise it stops the sequencer and re-enables the engine.

### Recorder start: the mix is dismantled

With the sequencer stopped, `start()` (~L300-330) does:

* `sequencer.setMidiInVoiceMode(midiInVoiceMode_SampleRecorder)` - MIDI/pad input
  is routed to the recorder's own preview voice instead of the sequencer.
* `engine.blockAllNoteOn()` ([`mtAudioEngine.cpp`](../core/AudioEngine/mtAudioEngine.cpp)
  ~L1462) - blocks note-on for every sample instrument.
* `sequencer.setSynthMute(kMuted)` ([`mtSequencer.cpp`](../core/source/mtSequencer.cpp)
  ~L3744) - mutes synth engines.
* `engine.clearDelay()` / `clearReverb()` / `blockDelayRefresh()`.
* `engine.disconnectMixerImpact()` (~L1571) - stores then resets the mixer gains.
* `engine.disableLineInImpact()` (~L990) - mutes the live line-in into the master
  mix and the delay/reverb pre-mixers.
* `engine.setLimiterSidechain(0)`.

`stop()` undoes these (`unblockAllNoteOn`, `connectMixerImpact`,
`enableLineInImpact`, ...). So the "silence while recording" is not an incidental
side effect; it is an explicit multi-step setup.

### The recording tap is independent of the output mix

[`Recorder`](../core/source/Recorder.cpp) reads `AudioRecordQueue`s attached to the
input graph (`getRecordingQueueI2s()` / `getRecordingQueueUsb()`, wired in
[`AudioInput.cpp`](../core/AudioEngine/AudioInput.cpp) L21-39). It copies input
blocks (`AUDIO_BLOCK_SAMPLES` = 128) into a destination buffer in `update()`.
Playback voices and the master mix are not in that path, so project playback would
not end up in the recording by itself (an external loop-back from the output to
the line input would, of course).

### The blocker: shared sample memory

`functActionRecord()` ([`fSampleRec.cpp`](../core/interface/sampleRecorder/fSampleRec.cpp)
~L1520) configures the recorder with:

```cpp
config.destinationBufferAddress = externalRamSampleMemory;
config.destinationBufferSize    = SAMPLE_MEMORY_SIZE;
```

i.e. the **entire sample pool** (11.25 MB on Original, ~60 MB on Tracker+/Mini; see
[`mtStructs.h`](../core/source/mtStructs.h) L65/L70). It also sets
`wasSampleMemoryOverwritten = 1`. When leaving the recorder
(~L2296) that flag forces `newFileManager.reloadSamplesFromWorkspace()` so the
project's samples are re-read from `/Workspace/` after the recording was written
over them. Consequently:

* Any instrument playing during a recording would read samples that are being
  overwritten by the recording head.
* The post-record reload is the existing "repair" step - a design that assumes no
  project audio is needed while recording.

Related memory facts from [`developer_guide.md`](developer_guide.md): samples
>= 256 KB are SD-streamed with a 64 KB pre-cache in `externalRamSampleMemory`
(`VoiceStreamManager`), and the FX edit buffer (`externalRamEffectsBuff`,
`EDIT_BUFF_OFFSET`, [`Tracker.cpp`](../core/source/Tracker.cpp) L28) is carved from
the top of the pool.

## Existing pieces that already help

* **Pre-roll / count-in metronome during recording.** The sequencer already ticks a
  metronome while `SR->recordInProgressFlag` or pre-roll is active
  ([`mtSequencer.cpp`](../core/source/mtSequencer.cpp) ~L183-224:
  `engine.makeMetronomeTick`, `extRecMetronomeStep`). `isPreRollConfigOn()` (~L3404)
  gates it; `showPreRollPopup()` (~L1670) shows "Counting in"; on pre-roll end it
  calls the recorder's `onPreRollMetronomeEnd` callback
  ([`fSampleRec.cpp`](../core/interface/sampleRecorder/fSampleRec.cpp) ~L2910) which
  starts recording. This is the natural place to also start the pattern, and
  `Sequencer::play(uint8_t)` already has a `preRecMetronomeActive` branch that calls
  `playPattern(false)` after the count-in (~L205-215).
* **The recorder can target other buffers.** `Recorder::Config` takes an arbitrary
  `destinationBufferAddress/Size`. [`mtTest.cpp`](../core/source/mtTest.cpp)
  ~L894/930 already records into `externalRamEffectsBuff` for a test, so recording
  into a region other than the full pool is supported by the class.
* Recorder internals: `crop()` / `undo()` only adjust addresses and length
  (`Recorder.cpp`), `DestinationChannelConfig::maxLength` bounds the recording, and
  full memory is reported via `setFullMemoryCallback`.

## Design options

| Option | Idea | Pros | Cons |
|---|---|---|---|
| A. Record into the FX edit buffer | Point `destinationBufferAddress` at `externalRamEffectsBuff` (the FX edit region is `2 * SAMPLE_CHANNELS * EDIT_BUFF_SIZE` = 7.5 MB on MK66, 15 MB on IMX; `mtStructs.h` L77-85) | Project samples untouched, no reload on exit, no new RAM | Max take length drops; must check what else uses the edit buffer while the recorder is open; save path assumes the take is at the pool start |
| B. Record into free tail of the sample pool | Start after the last used instrument slot (`calcFirstSlotToMoveInMemory`-style accounting) | Longer takes | Shrinks as the project grows; "memory full" semantics change; loading the take later must move it |
| C. Stream the recording to SD | Write blocks to a file while recording | No RAM limit | Needs an SD write path with real-time guarantees next to sample streaming; larger change |
| D. Keep current behaviour, add a click-track only | Use the existing metronome | Already works | Not what is wanted |

Then, independent of the buffer choice, the engine setup in `start()` needs to be
split: keep `disableLineInImpact` / limiter-sidechain handling for the live input,
but skip `blockAllNoteOn`, `setSynthMute`, `disconnectMixerImpact` and the
delay/reverb clearing when "play while recording" is on, and drop the stop prompt
in `start()` / `functStopPatternYes`.

## Open questions (not answered by reading code)

* CPU headroom: the recorder's `update()` runs in the main loop while the audio
  graph already mixes up to the voice limit. Not measured on MK66 or i.MX.
* Monitoring/feedback: with line-in monitoring on and speakers feeding the mic,
  playback would be re-recorded. The existing `monitor` setting
  (`strRecorderConfig::monitor`) and `Mic` sources need a policy.
* MIDI/pad input during recording: `midiInVoiceMode_SampleRecorder` currently
  sends pads to the recorder preview voice; with playback running, what should
  pads play?
* Mini differs: separate source enum order and button columns
  (`ConfigScreenColumns` in `sampleRecorder.h`); check Mini before assuming the
  same screen flow.
* `engine.setLimiterSidechain(0)` is forced in `start()` to avoid sidechaining to
  line-in; with a running song the project value should probably be kept.

## Where to start reading

1. [`fSampleRec.cpp`](../core/interface/sampleRecorder/fSampleRec.cpp) `start()`,
   `stop()`, `functActionRecord()`, `functStopPatternYes()`
2. [`Recorder.cpp`](../core/source/Recorder.cpp) / [`Recorder.h`](../core/source/Recorder.h)
3. [`mtSequencer.cpp`](../core/source/mtSequencer.cpp) pre-roll block (~L183-224) and `play()` (~L1307)
4. [`mtAudioEngine.cpp`](../core/AudioEngine/mtAudioEngine.cpp) `blockAllNoteOn`, `disconnectMixerImpact`, `disableLineInImpact`
