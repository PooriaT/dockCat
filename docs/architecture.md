# Architecture notes

- `AppState` is the top-level choreography owner. It awaits cat travel, card presentation, queued replacement, card dismissal, return-home travel, and settle animations in explicit order.
- `CardWindowController` owns only the AppKit panel. Its presentation, replacement, and dismissal operations are async and return `PresentationAnimationResult.completed` or `.cancelled`. Each operation has a fresh token so stale animation completions cannot mutate a newer notification's final panel state.
- `CatWindowController` exposes a handoff-anchor contract through `handoffSourceRect()`. The rect is derived from the cat overlay panel origin plus the documented visual anchor and mini-card carry offset, avoiding SpriteKit internals in app choreography.
- Mini-card visibility is controlled through focused cat-window APIs. Pickup and travel keep the card visible; successful expanded-card presentation completes the handoff pose and hides the mini-card; dismissal and return home reset it.
- Transient timers are scheduled only after the expanded-card animation completes and the state machine accepts `cardPresented`. Persistent notifications do not schedule timeout tasks.
- Queued replacement with stay-in-place enabled crossfades panel content without hiding the panel or sending the cat home. If stay-in-place is disabled, the expanded card dismisses before walk-home starts.
- Reduced Motion uses shorter fades and avoids large frame travel for presentation/dismissal while preserving the same state-machine events and timer ordering.

Remaining limitations: the handoff anchor is a stable overlay-frame contract rather than direct SpriteKit node projection, and the notification card size remains fixed for this issue.
