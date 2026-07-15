# Animation assets

The MVP draws a cat and carried card with `SKShapeNode`. `CatAnimation` is the stable abstraction used by the coordinator, so a future `SKTextureAtlas` loader can map sleeping, waking, pickup, walking, waiting, turning, and settling sequences without changing queue or state logic.

Walking currently combines two separate pieces: the placeholder SpriteKit in-place bob and continuous `NSPanel` motion between Dock anchors. The panel motion is distance-based, follows only the Dock axis, and is cancellable. The cat art still does not face the travel direction or use proper paw cycles; that remains intentionally deferred to issue #64. Mini-card handoff and expanded-card animation remain deferred to issue #65.

Replacement atlases should include Retina-resolution frames, stable anchor points, consistent canvas sizes, per-sequence frame durations, and a license/source manifest.
