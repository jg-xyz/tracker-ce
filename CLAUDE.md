# Project instructions (tracker-ce, jg fork)

Firmware for the Polyend Tracker (Original MK66, Tracker+ and Mini on i.MX RT1051).
Build with `mise run build:plus` (also `build:original`, `build:mini`); `mise run test`
runs the docs checks. Host tests live in `util/host-tests/` (`mise run test:*`).

## Changelog (`CHANGELOG.md`)

Keep it current so feature history is easy to scan.

* Every user-visible change (new feature, behaviour change, fix, removed readout) gets an
  entry under `## [Unreleased]` in `CHANGELOG.md` **in the same commit/branch as the
  change**, not afterwards.
* Use the existing sections: `### Added`, `### Changed & Fixed`, `### Documentation`.
  One numbered item per change, bold title, say which devices and screens it affects,
  link the wiki page when there is one.
* Pure research, tooling and test changes go under `### Documentation` or a short
  tooling item only if they matter to someone using the repo; skip noise.
* When cutting a version: `mise run version:bump:patch|minor|major` (all three devices),
  rename `[Unreleased]` to the new version with the date, and start a fresh
  `[Unreleased]`. The base is `1.0.0`; the firmware window shows `<ver> jg`.

## Versioning and builds

* Version numbers live only in `version.mk`; never hard-code them elsewhere.
* The Config > Firmware > Build field is the commit hash, `-dirty` if tracked files are
  uncommitted. Commit before building anything that gets flashed so it can be traced.
* `.ptf` filenames must be 31 characters or fewer (bootloader limit).
* Flash target on the SD card is `/Firmware/`; the card shows up as `TRKR`.

## Wiki (`docs/`)

The GitHub Wiki is generated from `docs/*.md` by `.github/workflows/wiki-sync.yml` on
push to `main`. Treat `docs/` as the wiki; never edit the wiki repo directly.

* **Maintain it:** when behaviour, hardware facts or tooling change, update the affected
  page in the same change. User-facing features get a guide; investigations and
  feasibility work get a `docs/research_*.md` page with code references.
* **Index it:** every new page must be linked from `docs/Home.md` (with a one-line
  description) and `docs/_Sidebar.md`. Pages are flat files in `docs/`; link between
  them with relative paths (`other_page.md`).
* **Reference it:** before answering questions about hardware limits, memory budgets,
  the CPU, USB audio, the Sample Loader or build/versioning, read the relevant wiki page
  first (`docs/developer_guide.md`, `docs/research_tracker_plus_cpu.md`, the USB doc)
  instead of re-deriving. Cite the page and the source file when reporting findings.
* **Keep facts honest:** mark unverified claims, say what was built vs run on hardware,
  and correct stale statements wherever they appear (grep the whole repo, not one page).
* **Check it:** `mise run test` validates frontmatter and relative links in `docs/` and
  `knowledge/`; run it before committing doc changes.

## Git

* Work on a feature branch, merge fast-forward to `main` after testing; delete merged
  branches locally and on origin.
* Preserve existing line endings; several source files (e.g. `fSampleImport.cpp`) mix
  CRLF and LF, so edit in place and check `git diff --stat` for whole-file diffs.
