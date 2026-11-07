# Research: "Mark for Deletion" in the Sample Browser

Goal: a new button in the sample browser that appends the item under the cursor (a
file or a directory) to a text file at the root of the SD card. The Tracker deletes
nothing; the list is for review and cleanup on a computer. Findings are from
reading the source; nothing was built or run on hardware.

## Implementation status

Implemented on branch `feat/mark-for-deletion` (compiles for Tracker+; not run on hardware).
Button 7 in the Sample Loader (`functMarkForDeletion`, `fSampleImport.cpp`) appends
`/Dir/Sub/File.wav` or `/Dir/Sub/Folder/` to `MARKED_FOR_DELETION.txt` at the SD root,
skips duplicates, strips the paged `(a-b)` suffix, rejects `/..`. The label replaced
"Memory"; the `%` readout is gone (the memory bar remains). Multi-select, flagging in
the list and un-mark are not done.

## Summary

Feasible with small, well-contained changes. The browser already exposes everything
needed to build an SD-relative path for the cursor item, the platform file API
supports appending, and the root file will not show up in any browser listing.
The real design work is choosing the button, handling paged folders, and picking a
safe moment to touch the SD card.

## "The sample browser" is the Sample Loader

The screen titled **Sample Loader**
([`gSampleImport.cpp`](../core/interface/sampleImporter/gSampleImport.cpp)
`showDefaultScreen()` ~L147) is implemented by `cSampleImporter` in
[`core/interface/sampleImporter/`](../core/interface/sampleImporter/). It has an
SD-card explorer pane and a project instrument pane; `selectedPlace` says which has
focus: 0 = explorer files, 1 = instrument list, 2 = preview volume
([`fSampleImport.cpp`](../core/interface/sampleImporter/fSampleImport.cpp) ~L865).

The same `cFileManager` explorer state also backs the project, mod, firmware and
game browsers (`fmBrowseProjects`, `fmBrowseMods`, ... in `fileManager.h`); the
Sample Loader is the only one in scope here.

## Existing buttons

Bound in `fSampleImport.cpp` ~L354-361, labels in `gSampleImport.cpp` ~L151-159:

| Button | Label | Handler | Acts on |
|---|---|---|---|
| 0 | Enter / Add | `functEnter` | explorer item |
| 1 | Add next | `functInstrumentAddNext` | explorer item -> instrument |
| 2 | Preview | `functPreviewFile` | explorer item |
| 3 | Rename | `functRename` | **instrument** (needs `selectedPlace == 1`) |
| 4 | Import | `functInstrumentImport` | explorer item |
| 5 | Delete / unused | `functDeleteUnused` | **project instruments**, not SD files |
| 6 | Preview Vol | `functSelectPreviewVolume` | setting |
| 7 | *(none bound)* | - | `label[7]` shows "Memory" (status text) |

Two takeaways: (1) nothing in this screen deletes or touches SD files, and the
existing "Delete" is about project instruments, so a new "Mark for deletion" must
not be confused with it in the UI text; (2) button 7 has no handler in the default
screen, but its label slot currently holds the "Memory" readout, so using it means
moving or dropping that display. Alternatives: a Shift-combo (`functShift` exists),
or repurposing a button only when `selectedPlace == 0`. Tracker Mini has a
different button set (`interfaceButtonMiniMenu` / `MiniMiddle` are handled
separately); not checked.

## Getting the cursor item and its path

* Item name: `SI->explorerNames[SI->selectedFile]`
  ([`fSampleImport.cpp`](../core/interface/sampleImporter/fSampleImport.cpp)
  `instrumentAdd` ~L378-386 shows the idiom).
* Folders are entries whose first character is `/` (e.g. `/Drums`); that is the
  test used throughout the file (`*explorerNames[...] == '/'`). The first entry in
  any non-root folder is `/..` (parent) - created in
  [`listOnlyFolderNames()`](../core/FileManager/fileManagerBrowse.cpp) ~L192-244.
* Current directory: `newFileManager.getExplorerPath()` returns
  `explorerCurrentPath`: `"/"` at the root and `"/Dir/Sub"` (no trailing slash) below
  it ([`fileManagerBrowse.cpp`](../core/FileManager/fileManagerBrowse.cpp)
  ~L77-150, `goUpInActualPath()` ~L391).
* Files shown are only folders plus `.wav` / `.pti` (`enListFileFilter_wave_inst`,
  `listOnlyWavFromActualPath()` ~L245), so **only those can be marked**, and a
  `.txt` at the SD root can never appear in this list.

Resulting path: if the item starts with `/` (folder) it already carries the
separator, so join as `explorerPath` + item for subfolders; at root
(`explorerPath == "/"`) avoid a doubled slash. For a file, join with a single `/`.

### Gotchas

* **Paged folders.** Lists are capped (`list_length_max = 101`, `fileManager.h`
  ~L573). Larger folders appear as pseudo-folders like `/Name (1-100)`;
  `parseFolderName()` (`fileManagerBrowse.cpp` ~L49) strips the `(a-b)` suffix when
  entering them. A mark on such an entry must use the stripped name and should
  probably refer to the whole real folder, not a page.
* **`/..` and empty states.** Cursor on `/..`, an empty list
  (`explorerNames == nullptr`), or a deselected state must be rejected.
* **Multi-select.** `getSelectionStart/End(listFiles)` allows selecting a range;
  decide whether the new action marks the cursor item only (as requested) or the
  whole selection.
* **Path length.** `kMaxFilePathLen` and the `explorerCurrentPath[255]` buffer bound
  the string; FAT long file names can be up to 255 chars per component.

## Writing the text file

`FileSystem` ([`Platform.h`](../core/include/Platform.h) ~L314) provides
`openFile(path, kWriteAppend)`, `writeFile`, `readFile`, `closeFile`, `exists`,
`getFileSize`. There is already a working append-to-a-root-file precedent:
[`BatteryImpl.cpp`](../platforms/imx/source/BatteryImpl.cpp) ~L164 appends lines to
`battLog.txt` using a path with no leading slash and closes the file each time.
Implementations: [`mk66/source/FileSystemImpl.cpp`](../platforms/mk66/source/FileSystemImpl.cpp)
(~L215) and [`imx/source/FileSystemImpl.cpp`](../platforms/imx/source/FileSystemImpl.cpp)
(~L266). The importer reaches the file system via `newFileManager` /
`platform->getFileSystem()` (the recorder does the same: `fileSystem =
platform->getFileSystem()`).

Duplicate detection means reading the existing file back (small, line-per-entry)
and comparing before appending; file size is cheap to check first.

## Suggested design

* File: `/MARKED_FOR_DELETION.txt` (any name not matching `.wav`/`.pti` and not
  colliding with existing root files such as `Workspace`, `Themes`, `Fonts`,
  `Images`, `Effects`, `battLog.txt`).
* Format: one UTF-8 line per entry, SD-relative path with `/` separators, trailing
  `/` for directories.
* Button: new label in the Sample Loader, acting only when `selectedPlace == 0`,
  with a `mtPopups.show(...)` toast ("Marked" / "Already marked" / "SD error").
* Errors: no card (`isSdCardInserted()`), open/write failure, read-only card.
* Safe timing: other code runs SD work as steps of the `cFileManager` state
  machine (`status != fmIdle` guards in `browseSdCard`), and the loader can be
  streaming a preview from SD. Whether a small synchronous append from a button
  handler is safe while preview/async reads are active (`readSectorsAsync`,
  `isAsyncReadBusy`) was not verified; at minimum check `newFileManager` status and
  stop preview first, as other handlers do (`SI->playFromPads(INTERFACE_BUTTON_PREVIEW,
  buttonRelease, -1)`).

## Open questions

* Should marked items be flagged in the list (e.g. colour) so the user sees what is
  already marked? That requires reading the file when a folder is opened.
* Un-mark: toggle on a second press, or only manual editing?
* Mini and Tracker+ vs Original button layout and label space.
* Should the project/mod/firmware browsers get the same button, or only samples?
* Anything on a computer that consumes the list must treat it as untrusted input
  (paths are user-supplied names) and verify before deleting.
