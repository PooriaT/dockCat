# Animation assets

The MVP draws a cat and carried card with `SKShapeNode`. `CatAnimation` is the stable abstraction used by the coordinator, so a future `SKTextureAtlas` loader can map sleeping, waking, pickup, walking, waiting, turning, and settling sequences without changing queue or state logic.

Walking currently combines two separate pieces: the placeholder SpriteKit in-place bob and continuous `NSPanel` motion between Dock anchors. The panel motion is distance-based, follows only the Dock axis, and is cancellable. The cat art still does not face the travel direction or use proper paw cycles; that remains intentionally deferred to issue #64. Mini-card handoff and expanded-card animation remain deferred to issue #65.

Replacement atlases should include Retina-resolution frames, stable anchor points, consistent canvas sizes, per-sequence frame durations, and a license/source manifest.

## Issue #64 placeholder locomotion contract

Directional walking remains vector-only. The overlay panel is moved by `CatMotionDriver`; SpriteKit keeps the cat node anchored inside the small panel and only animates body-part transforms.

Direction is resolved from the actual planned motion delta: positive x faces right, negative x faces left, positive y faces up, and negative y faces down. Deltas within the near-zero tolerance resolve to a deterministic stationary state so the cat does not jitter when the panel is already at its destination.

Vertical Dock support uses a rotated complete-cat placeholder pose: upward travel rotates the cat visual +90 degrees, and downward travel rotates it -90 degrees. This is intentionally stylized placeholder art; final sprite-atlas art can replace the rotated vector pose without changing the locomotion context.

Locomotion phases are explicit: waking, turning, picking up, walking, static carrying for Reduced Motion, stopping, waiting, settling, and settled. The mini-card is visible only after pickup reaches a carrying phase and remains visible through walking, stopping, waiting, and cancellation-safe carry poses.

SpriteKit action keys are scoped by responsibility: `cat.breathing`, `cat.walking`, `cat.tail`, `cat.turn`, `cat.cardPickup`, and `cat.settle`. Starting wake, turn, pickup, or walking removes only the breathing action. Ending locomotion removes the walking and tail loops and restores paw positions without clearing unrelated card or handoff actions.

The mini-card is attached to a dedicated carry anchor node positioned near the vector mouth/front-paw area. Future sprite-atlas replacement should preserve this anchor as the stable handoff point for issue #65 instead of positioning the card directly in scene coordinates.

When Reduced Motion is effective, the resolver selects a static carrying phase instead of the repeating walk loop. Direction, facing, and mini-card visibility remain logically correct while the panel motion uses the existing reduced-motion timing.
