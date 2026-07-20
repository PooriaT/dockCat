# DockCat Orange v1 Export Notes

- Source application: editable SVG authored as project-owned vector source; runtime PNGs generated with a deterministic Python 3 standard-library raster export script for this PR.
- Export target: 300 × 220 transparent RGBA PNG (`@2x`) with no trimming, packing rotation, background fill, or per-frame canvas changes.
- Runtime location: `Sources/DockCat/Resources/CatAnimations/DockCatCat.atlas/`.
- Manifest: `Sources/DockCat/Resources/CatAnimations/manifest.json` lists frames explicitly and owns all timing/playback values.
- Manual cleanup: none after export; generated frames were reviewed for canvas bounds, anchor stability, no baked card, and compact file size.
- To update: edit `DockCat-Cat-v1.svg`, adjust pose/export script parameters consistently, regenerate every listed PNG, then run Swift tests and the visual QA checklist.

## Binary-free PR note

The GitHub PR tooling for this repository currently rejects binary file diffs, so generated PNG frames are intentionally not committed in this revision. Run `Scripts/export-cat-animation-assets.py` from the repository root to materialize the local `Sources/DockCat/Resources/CatAnimations/DockCatCat.atlas/` PNG atlas and manifest before production packaging in an environment that accepts binary assets.
