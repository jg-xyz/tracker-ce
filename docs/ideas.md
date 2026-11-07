# Ideas to investigate

Unscoped notes, not commitments. Source pointers are starting points from a quick
directory listing, not verified findings.

## 1. Song/pattern playback during recording

Allow the sequencer (song or pattern) to run while sampling, so a take can be
recorded in time with the project.

Questions to answer:

* Does the sample recorder currently stop or block the sequencer? (see
  `core/interface/sampleRecorder/`, `core/AudioEngine/AudioInput.cpp`)
* Audio-path load: recording queues (I2S/USB) plus full voice and FX mixing in
  the same block callback. CPU/RAM headroom on Original (MK66) vs Tracker+/Mini
  (i.MX).
* Monitoring: should playback be mixed into the monitored input, and must the
  sequencer output be kept out of the recorded signal (no feedback into the take)?
* Does playback share the sample memory the recording writes into (risk of
  playing a sample while it is being replaced)?

## 2. Punch-in recording

Start and stop recording at chosen points while the project plays, replacing or
filling part of a sample (or recording a fresh one) in sync.

Questions to answer:

* Punch triggers: manual button, pattern step/position markers, or a fixed
  length from a start position.
* Target: new sample vs overwrite a region of an existing one (and undo).
* Click avoidance at the boundaries (short crossfade/ramp).
* Depends on idea 1 (playback while recording).

## 3. Sample browser: "mark for deletion"

In the sample browser (likely the `core/interface/sampleImporter/` UI) add a
button, **Mark for deletion**, that appends the item under the cursor (a file or
a directory) to a text file at the root of the SD card. Nothing is deleted by
the Tracker itself; the list is for later review/cleanup on a computer.

Design questions:

* File name and location, e.g. `/DELETE.txt` or `/delete-list.txt`; confirm it
  is not picked up by the browser, project scanner or import code.
* Line format: SD-relative path, one per line, forward slashes, UTF-8; whether
  directories get a trailing `/`.
* Duplicates: skip if the path is already listed; allow un-marking?
* Feedback: toast/indicator on the button press and a visual mark on items
  already in the list.
* Edge cases: cursor on `..` or an empty directory, long paths/non-ASCII
  names (FAT long file names), SD write failure or read-only card, renaming or
  moving a marked item afterwards.
* Safety: since it only records paths, a later tool must verify entries before
  deleting anything.
