# Cat animation asset contract

Issue #93 defines the version-1 sprite-atlas contract; issue #94 will add the first production artwork.

## Required clips

The required manifest clip IDs are `sleep`, `wake`, `pickUp`, `turnToPresentation`, `walkCarry`, `present`, `wait`, `turnHome`, `walkHome`, and `settle`. Semantic travel-only panel moves (`walkToPresentation` and `walkHome`) do not request texture clips; panel movement remains owned by `CatMotionDriver` so artwork cannot move the `NSPanel`.

## Geometry

Version 1 uses a fixed logical canvas of 150 x 110 points, native scale 1...4, and for `nativeScale = 2` every frame must be exactly 300 x 220 pixels. The visual and feet anchor is (75, 35). The carry anchor is (117, 73), derived from the visual anchor plus the (42, 38) mini-card offset. The handoff size is 36 x 24. To change these values later, introduce a new schema version and update `CatOverlayGeometry` and tests in the same PR; never silently rewrite a manifest.

## Manifest rules

Frame names are manifest-ordered basename-only relative names. Absolute paths, subdirectories, traversal, trimming, atlas-packer rotation, per-frame transforms, duplicate ownership across clips, empty clips, invalid durations, and wrong playback policies are rejected. Loop clips are `sleep`, `walkCarry`, `wait`, and `walkHome`; transition clips play once or hold their last frame.

## Orientation and mini-card

Artwork is canonical right-facing. Runtime mirroring handles left-facing, and vertical Dock travel uses +/-90 degree rotation on the existing facing root. Notification content remains a separate SpriteKit mini-card node positioned from the carry anchor; it must not be baked into textures.

## Source and license records

Production assets must populate `Sources/DockCat/Resources/CatAnimations/ASSET-SOURCES.json` or its documented successor with asset set ID/version, files or glob, creator, copyright holder, SPDX license identifier or project-owned identifier, license file, optional source URL, modifications, generated source files, and bounded notes. Runtime animation code does not display license prose.

## Validation and fallback

Run `Scripts/validate-cat-animation-assets.sh <asset-directory>`. Missing or invalid production assets select the vector fallback before playback starts; the app remains launchable and notifications continue to work.

## Test atlas

Tests own tiny generated geometric fixtures. They are not production cat artwork and are never selected by the app production locator.
