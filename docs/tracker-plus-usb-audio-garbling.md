# Tracker+ USB Audio Playback Garbling on Linux

## Status

**Host-side kernel issue; workaround found, no firmware change needed.** With
`snd-usb-audio` in its default explicit-feedback mode, Linux 7.2.11 sends only
~75% of the requested playback packets to the Tracker+ (33.2 kHz instead of
44.1 kHz). Forcing implicit feedback (`implicit_fb=1`) restores 44.1 kHz. The
kernel logic that drops the microframes is still unidentified. An earlier
hypothesis (ring byte/element mismatch in firmware) was refuted; see "Rejected
hypothesis". No firmware change has been made or flashed.

## Reproduction and isolation

Host: Linux 7.2.11, PipeWire 1.6.9 / WirePlumber, Tracker+ connected directly
to the laptop with a USB-A-to-USB-C cable.

1. The Tracker+ is selected as the default PipeWire sink.
2. Normal host playback sounds garbled, as though samples are decoded at the
   wrong format or rate.
3. PipeWire reports the Tracker+ sink as `s16le`, two channels, `44100 Hz`.
4. ALSA reports the same hardware format:

   ```text
   Playback: S16_LE, 2 channels, 44100 Hz
   ```

5. A direct ALSA test bypassing PipeWire is also garbled:

   ```sh
   speaker-test -D hw:2,0 -c 2 -r 44100 -F S16_LE -t sine -f 440 -l 1
   ```

6. Audio from Tracker projects is clean through the same physical output.

Therefore:

* PipeWire resampling/routing is not the cause.
* The Tracker's DAC, headphone/line output, and downstream speakers/headphones
  are not the cause.
* The fault is limited to the host-to-Tracker USB playback receive path.

The device runs at USB 2.0 high speed (`480M`), is self-powered, and its USB
power policy is already `on`; no kernel USB transport errors were logged during
the direct test.

## Rejected hypothesis: ring byte/element mismatch

Claim: `updateUsbInputBuffers()` mixes byte and `int16_t` units for
`audioPlayBuffer.rdidx`. Reality (`platforms/imx/usb/audio_unified.c`):

* The producer (`dataBuffSetData`) uses only `wridx`, in bytes, wrapping at
  `len` = 1,536 bytes.
* The playback consumer never calls `dataBuffGetData`; it indexes the
  `int16_t audioPlayBuff[]` directly with `rdidx` as an **element** index,
  stepping 256 (one 128-frame stereo block) modulo 768 elements. Element
  offsets 0/256/512 are byte offsets 0/512/1024, so reads are block-aligned,
  never straddle the wrap, and cover the same 1,536-byte ring.
* `rdidx` is never read by the producer, so the two cursors do not need to
  share units.

`util/host-tests/usb_play_ring_sim.c` (run via `mise run test:usb-ring`)
feeds a counter ramp through 44/45-frame packets and consumes 128-frame blocks
with the unmodified arithmetic: 0 mismatched frames over ~69k blocks. The
"fix" proposed earlier (bytes everywhere) would change nothing audible. The
sim copies the arithmetic; keep it in sync if `audio_unified.c` changes.

## Open question: what is actually garbled?

Host playback into the Tracker+ **never reaches the analog output** in this
tree:

* `updateUsbOutputBuffers()` (direct-to-DAC path) is commented out at
  `platforms/imx/source/PlatformTrackerIMX.cpp:90`.
* `updateUsbInputBuffers()` feeds `AudioInput::getUsbStream()`, which connects
  only to the USB recording amplifier, RMS meter and record queues
  (`core/AudioEngine/AudioInput.cpp:21-39`). It is not mixed into the master
  output.

So the statement "audio from Tracker projects is clean through the same
physical output" cannot be a comparison of the same path: whatever is heard
from the output is not the host stream. Needed to proceed:

1. Where is the garbling observed? (a) sample **recorded from the USB input
   source** and played back, (b) USB input monitoring on some other firmware
   build, or (c) the host's own capture of the Tracker's 28-channel USB
   record stream (the IN direction)? Each is a different path.
2. Does a recorded USB sample show the problem in the Sample Editor waveform
   (pitch/tempo wrong vs. noise-like)? Pitched/slow/fast points at
   rate/feedback; noise-like points at format/channel layout.

## Measured on hardware (2026-11-06)

Garbled audio is the host's playback stream received by the Tracker+ (USB
input). With `aplay -D hw:2,0` of a 44.1 kHz/S16 stereo tone (Tracker+ at
`usb-0000:03:00.3-2`, high speed, ASYNC OUT ep 0x03 + feedback ep 0x83):

* ALSA `hw_ptr` advances at **~33,230 frames/s** (stable, +-50, from the first
  half second, identical over 15 s and over repeated runs), not 44,100.
  The host is pacing its packets to 75.4% of nominal.
* In async mode the Linux host paces OUT packets from the device's feedback
  value, so the device is (directly or via host interpretation) requesting the
  wrong rate. Sending 25% fewer frames than the device consumes starves the
  ring and produces constant dropouts/repeats, which matches the symptom.
* usbmon capture (`util/host-tests/capture_usb_feedback.sh`) **clears the
  device**: EP3 IN feedback is a sane ~5.54 samples/microframe (~44.3 kHz,
  `0x000588xx`-`0x00058bxx`; nominal `0x00058349`). The ring servo works.
* The host's OUT stream is the problem. Each URB carries a single 20/24-byte
  packet (5/6 frames, avg 5.5 = correct size), but 4 of every 16 microframes
  get **no packet at all** (frame numbers skip 3, then 1, repeating).
  12/16 = 75% of microframes -> 33.2 kHz on the wire, matching `hw_ptr`.
* So the garble is a host-side isochronous scheduling problem (Linux 7.2.11
  `snd-usb-audio`, `lowlatency=Y` -> 1 packet/URB at 125 us, AMD Renoir/Cezanne
  xHCI `03:00.3`), not firmware ring or feedback logic. The firmware ring code
  and feedback are not implicated by this evidence.
* `lowlatency=0` (reloaded, param reads `N`): no change, still ~33.2 kHz.
* Capture (IN, 28 ch) on the same port/controller runs at a correct ~44.1 kHz.
* **Userspace usbfs test** (`mise run test:usb-iso`, no `snd-usb-audio`):
  8000 packets/s, 0 gaps, 0 errors, 44,092 frames/s over 10 s; feedback
  converges to ~44,096 Hz (matches firmware `CODEC_SAMPLE_RATE` 44098).
  Same device, cable, port and xHCI sustain full-rate playback.
* **Conclusion:** firmware (ring + feedback) and xHCI are fine; the 25% microframe
  loss is introduced by the in-kernel `snd-usb-audio` playback path (Linux
  7.2.11) when driving this device. Not yet known which kernel logic.

## Workaround found: `snd_usb_audio implicit_fb=1`

With `implicit_fb=1` (sync EP becomes the capture endpoint 0x82, "Implicit
Feedback Mode: Yes") playback measures **44,102-44,114 Hz** via ALSA `hw_ptr`,
vs 33.2 kHz with the default explicit-feedback mode. So the kernel's
explicit-feedback playback path mishandles this device; implicit mode avoids it.

### Settings used (all runs, 2026-11-06)

Environment: Linux 7.2.11-pikaos, PipeWire 1.6.x / WirePlumber, AMD
Renoir/Cezanne xHCI (`03:00.3`), Tracker+ `16d0:1119` direct on root hub
(bus 1, port 2, 480M), ALSA card 2 `hw:2,0`, stream S16_LE / 2 ch / 44100 Hz,
ASYNC OUT ep 0x03 + explicit feedback ep 0x83.

| Run | `implicit_fb` | `lowlatency` | Playback rate | Sync mode |
|---|---|---|---|---|
| Baseline (distro defaults) | `N` (all slots) | `Y` | ~33,230 Hz | explicit, ep 0x83 |
| Test 1 | `N` | `N` | ~33,230 Hz | explicit, ep 0x83 |
| Userspace usbfs (no `snd-usb-audio`) | n/a | n/a | ~44,092 Hz | explicit, ep 0x83 |
| Test 2 (fix) | `Y,Y,Y,Y,Y,Y,Y,Y,N...` | `Y` | ~44,102-44,114 Hz | implicit, ep 0x82 |

Driver reload sequence used for tests 1 and 2 (PipeWire must release the card
first; run in a real terminal because sudo needs a tty):

```sh
systemctl --user stop pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber
# test 1
sudo modprobe -r snd_usb_audio && sudo modprobe snd_usb_audio lowlatency=0
# test 2 (fix)
sudo modprobe -r snd_usb_audio && sudo modprobe snd_usb_audio implicit_fb=1,1,1,1,1,1,1,1 lowlatency=1
systemctl --user start pipewire pipewire-pulse wireplumber
```

`implicit_fb` is a per-card-slot bool array: the Tracker+ was slot 2. Side
effect: any other USB audio device in slots 0-7 is also forced to implicit
feedback.

Measurement commands (no root unless noted):

```sh
util/host-tests/measure_playback_rate.sh 8                  # ALSA hw_ptr rate, prints params + sync mode
sudo util/host-tests/capture_usb_feedback.sh                # usbmon: feedback values + raw OUT packets
mise run test:usb-iso -- 10                                 # usbfs userspace playback, bypasses snd-usb-audio
mise run test:usb-ring                                      # firmware ring arithmetic sim
```

Persist (root, host-side only; firmware unchanged), not yet applied:

```text
# /etc/modprobe.d/tracker-plus-usb-audio.conf
options snd-usb-audio implicit_fb=1,1,1,1,1,1,1,1
```

`quirk_flags=16d0:1119:<flags>` would be per-device, but the flag name for
generic implicit feedback is unverified on this kernel. Other parameters left
at defaults: `autoclock=Y`, `lowlatency=Y`.

## Caveat: workaround depends on the device's USB configuration

Later in the session the Tracker+ re-enumerated (new bus address) with a
different descriptor set: 3 interfaces (audio control, a **playback-only**
stream on interface 1 with EP3 OUT + EP3 IN feedback, MIDI), and **no 28-channel
capture stream**. In that configuration `implicit_fb=1` has nothing to sync
from, the stream reports `Implicit Feedback Mode: No`, and playback is again
~33.2 kHz. This also shows the explicit-feedback loss does not depend on the
capture stream. `usb_iso_playback_test.c` hardcodes interface 2 and works only
with the earlier (capture + playback) layout. Which Tracker setting or state
selects the layout is unknown.

Helper: `mise run usb:settings -- apply|persist|revert|status [--dry-run]`
(`util/host-tests/tracker_usb_audio_settings.sh`).

## After reboot (2026-11-07)

The user rebooted and reported audio working. The reboot also moved the host
from Linux 7.2.11 to **7.3.1-pikaos**, and `implicit_fb` was back at the stock
`N` (nothing persisted). So the fix is most likely the newer kernel, not the
module setting. The Tracker was not attached when this was recorded, so the
7.3.1 playback rate was not measured (`util/host-tests/measure_playback_rate.sh`).
Treat `implicit_fb=1` as a workaround for 7.2.11 only.

## Open items

* Root cause inside `snd-usb-audio` (why explicit-feedback playback loses 4 of
  every 16 microframes for this device) is unidentified. Next step if wanted:
  patched out-of-tree module logging packet sizes and `freqm`, then an upstream
  patch.
* Firmware robustness nits, not causes of this bug: feedback scales by `0xFFFF`
  instead of `0x10000` (~15 ppm); the consumer reads a full block while
  `samplesToRecv > 0` rather than `>= 128`; `audioPlayReady` never clears on
  underrun. The userspace test converged to 44,096 Hz, so the servo works.
* Subjective check (garble gone by ear with `implicit_fb=1`) still to be
  confirmed by the user.

## Verification workflow

```sh
mise run test:usb-ring   # ring arithmetic sim (passes today)
mise run build:plus      # build Tracker+ firmware
mise run test            # docs/knowledge conformance
```

## Secondary observations

* The USB descriptor correctly advertises only `44.1 kHz`, two-channel,
  16-bit playback. Host-side 48 kHz content should be resampled by PipeWire;
  that is expected and was not the failure.
* The implementation is USB Audio Class 2 with an asynchronous OUT endpoint
  and explicit feedback endpoint. Feedback was investigated because the
  symptom initially resembled a clock/rate mismatch, but the direct ALSA test
  and the ring-unit mismatch provide a complete local explanation.
* No matching open/closed USB-audio garbling report was found in the first
  100 GitHub issues/PRs for `polyend/tracker-ce`.
