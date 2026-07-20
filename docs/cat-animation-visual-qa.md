# Cat Animation Visual QA Checklist

Asset set under review: `dockcat.orange.v1@1.0.0`.

Record PR reviewer initials or PR review confirmation here without adding personal data to runtime assets: `PR review confirmation pending`.

## Checklist

- [ ] Canvas and clipping: every pose remains inside the safe canvas at scales 0.5, 1.0, 1.5, and 2.0.
- [ ] Anchor stability: feet/visual anchor remains fixed during sleep, walking, presenting, and settling.
- [ ] Mini-card stability: separate SpriteKit card remains at carry anchor without jitter; no baked card is visible when hidden.
- [ ] Loop seams: sleep, walk-carry, wait, and walk-home loop without visible pops.
- [ ] Transition seams: sleep → wake → pickup → turn → walk → present → wait → turn home → walk home → settle → sleep remains pose-compatible.
- [ ] Facing and mirroring: right-facing source and left-facing mirror are both readable.
- [ ] Vertical rotation: up/down rotations move feet-first and keep the card transform consistent.
- [ ] Full speed range: minimum, default, and maximum animation speeds remain natural.
- [ ] Runtime visual modes: Full, Reduced Motion, Disable Walking, and Pause Visual Animations land on intentional poses.
- [ ] Scale range: no clipping or excessive blur/pixelation at 0.5 or 2.0.
- [ ] Bottom/left/right Dock: presentation looks correct on all Dock edges.
- [ ] Multiple displays and negative coordinates: panel/card placement remains stable.
- [ ] Dark and light backgrounds: outline contrast remains readable.
- [ ] Global disable during playback: disabling and re-enabling does not leave stale textures.
- [ ] Pause/resume during travel: paused final frames and resumed loops remain valid.
- [ ] Placement refresh during travel: cancellation/restart does not corrupt current art.
- [ ] Fallback verification: intentional local atlas failure falls back to vector renderer, then is reverted.
- [ ] Resource loading and diagnostics: one bounded load summary is emitted, without paths or notification content.

## PR evidence to attach

Attach representative screenshots for sleep, wake/pickup, walk-carry, present/wait, walk-home/settle, bottom Dock, left Dock, right Dock, left mirror, up/down rotation, scales 0.5 and 2.0, Reduced Motion final poses, and Disable Walking relocation pose. Attach one short GIF or screen recording of invented notification content only.
