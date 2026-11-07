# Sample Loader: Mark for Deletion

The Sample Loader's button 7 ("Mark for / deletion") records an SD card item for later
cleanup on a computer. The Tracker deletes nothing.

## Use

1. Open the **Sample Loader** and focus the SD explorer pane (left side).
2. Move the cursor to a `.wav` / `.pti` file or a folder.
3. Press button 7. A popup confirms:

| Popup | Meaning |
|---|---|
| Marked for deletion | Entry appended |
| Already marked | Same path already in the list |
| No SD card | Nothing written |
| Path too long | Path exceeds the 255-character limit |
| SD write error | Could not open or write the file |

The `/..` entry and an empty list are ignored. The button does nothing while the
instrument pane has focus.

## Output file

`MARKED_FOR_DELETION.txt` at the SD root, one path per line, `/` separators, SD-relative:

```
/Drums/kick_old.wav
/Samples/Unused Pack/
```

Folders end in `/`. Paged folders (`Name (1-100)`) are recorded as the real folder.
The file is not shown in the Sample Loader because it only lists folders, `.wav` and
`.pti`. Treat its contents as untrusted when scripting deletion: check each path
before removing it.

## Notes

* The memory `%` readout that used to share this button's label is gone; the memory bar
  remains.
* Only the cursor item is marked (no multi-select, no un-mark; edit the file by hand).
* Developer notes: [research_mark_for_deletion](research_mark_for_deletion.md). Code:
  `functMarkForDeletion` in `core/interface/sampleImporter/fSampleImport.cpp`; host test:
  `mise run test:mark-for-deletion`.
* Verified by build and host test only; not yet tried on hardware.
