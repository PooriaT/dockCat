# Animation assets

The MVP draws a cat and carried card with `SKShapeNode`. `CatAnimation` is the stable abstraction used by the coordinator, so a future `SKTextureAtlas` loader can map sleeping, waking, pickup, walking, waiting, turning, and settling sequences without changing queue or state logic.

Replacement atlases should include Retina-resolution frames, stable anchor points, consistent canvas sizes, per-sequence frame durations, and a license/source manifest.
