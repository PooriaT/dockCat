# Architecture notes

- `AppState` is the top-level choreography owner. Its single `apply(_:)` entry point consumes typed state-machine decisions, publishes/logs accepted transitions once, and sends semantic effects through one bounded executor. Successful async effects emit the next semantic event; rejection or an impossible prerequisite stops the chain and enters fail-closed recovery.
- `CardWindowController` owns only the AppKit panel. Its presentation, replacement, and dismissal operations are async and return `PresentationAnimationResult.completed` or `.cancelled`. Each operation has a fresh token so stale animation completions cannot mutate a newer notification's final panel state.
- `CatWindowController` exposes a handoff-anchor contract through `handoffSourceRect()`. The rect is derived from the cat overlay panel origin plus the documented visual anchor and mini-card carry offset, avoiding SpriteKit internals in app choreography.
- Mini-card visibility is controlled through focused cat-window APIs. Pickup and travel keep the card visible; successful expanded-card presentation completes the handoff pose and hides the mini-card; dismissal and return home reset it.
- Transient timers are scheduled only after the expanded-card animation completes and the state machine accepts `cardPresented`. Persistent notifications do not schedule timeout tasks.
- Queued replacement with stay-in-place enabled crossfades panel content without hiding the panel or sending the cat home. If stay-in-place is disabled, the expanded card dismisses before walk-home starts.
- Reduced Motion uses shorter fades and avoids large frame travel for presentation/dismissal while preserving the same state-machine events and timer ordering.
- Recovery drops only an inconsistent active DockCat item, preserves pending queue items, force-hides stale DockCat UI, resets cat visual work and state to sleeping, and attempts later pending work. Expected animation cancellation remains resumable and is not treated as corruption. Native system UI is not modified by recovery.

Remaining limitations: the handoff anchor is a stable overlay-frame contract rather than direct SpriteKit node projection, and the notification card size remains fixed for this issue.
# External lifecycle reconciliation

`ExternalNotificationLifecycleTracker` serializes bounded visible-item state and emits typed lifecycle events. `ExternalPresentationPolicy` deterministically maps structural evidence to best-effort presentation behavior. `NotificationQueue` remains the atomic owner of pending/current items and supports identity-based update, removal, and location while preserving DockCat UUIDs and pending FIFO order.

Queue transaction redesign is deferred to issue #74. Presentation-session ownership and injectable timing are deferred to issue #75.
