# Architecture notes

- `AppState` is the top-level choreography owner. Its single `apply(_:)` entry point consumes typed state-machine decisions, while `PresentationSessionCoordinator` owns notification-specific choreography and timeout tasks. Successful async effects emit the next semantic event; rejection or an impossible prerequisite stops the chain and enters fail-closed recovery.
- `CardWindowController` owns only the AppKit panel. Its presentation, replacement, and dismissal operations are async and return `PresentationAnimationResult.completed` or `.cancelled`. Operation tokens include the presentation session, task cancellation resumes the checked continuation immediately, and force-hide resolves pending work before resetting the panel.
- `CatWindowController` exposes a handoff-anchor contract through `handoffSourceRect()`. The rect is derived from the cat overlay panel origin plus the documented visual anchor and mini-card carry offset, avoiding SpriteKit internals in app choreography.
- Mini-card visibility is controlled through focused cat-window APIs. Pickup and travel keep the card visible; successful expanded-card presentation completes the handoff pose and hides the mini-card; dismissal and return home reset it.
- Transient timers are scheduled only after the expanded-card animation completes and the state machine accepts `cardPresented`. Persistent notifications do not schedule timeout tasks. Timing uses `ContinuousPresentationClock`, never `Date`.
- Queued replacement with stay-in-place enabled crossfades panel content without hiding the panel or sending the cat home. If stay-in-place is disabled, the expanded card dismisses before walk-home starts.
- Reduced Motion uses shorter fades and avoids large frame travel for presentation/dismissal while preserving the same state-machine events and timer ordering.
- Recovery drops only an inconsistent active DockCat item, preserves pending queue items, force-hides stale DockCat UI, resets cat visual work and state to sleeping, and attempts later pending work. Expected animation cancellation remains resumable and is not treated as corruption. Native system UI is not modified by recovery.

## Atomic notification queue ownership

`NotificationQueue` is the sole owner of pending-versus-current state. Callers never remove
from pending storage themselves and do not infer a decision by combining count/current
queries with mutations.

- `claimNext()` promotes at most one FIFO item. Repeated claims return the existing
  authoritative current item; paused claims never promote; idle claims are explicit.
- `completeCurrent(policy:)` clears the current item and, for `advanceImmediately`, promotes
  exactly one pending item in the same actor transaction. `leavePendingForLater` clears the
  current item without changing pending order. Paused completion never advances.
- Pause writes return a typed outcome before `AppState` publishes pause state, changes the
  cat state machine, cancels timers, changes visuals, or resumes presentation. A single
  coordinator task coalesces rapid requests and applies every confirmed result in actor order.
- External appearance, update, and removal return the affected notification/location and
  revision directly. Active updates carry the authoritative payload; active removals carry
  the removed item needed for ordered DockCat-card dismissal. Pending updates preserve their
  index, and pending removals cannot later be claimed.

Every accepted mutation increments one monotonically increasing queue revision. Rejected
duplicates, full enqueues, missing external identities, repeated claims, unchanged pause or
limit writes, and idempotent lifecycle events retain the current revision. Immutable snapshots
contain pause state, current UUID, counts, limit, revision, and duplicate-cache sizes—never
pending storage or notification content. `AppState.current` is assigned only from claim,
completion, or external-mutation decisions. At stable boundaries it reconciles that projection
against a snapshot and enters the existing fail-closed recovery path on identity mismatch.

Duplicate tracking is bounded: `activeIDs` contains exactly the UUIDs in current plus pending
storage, while a FIFO cache retains only the 256 most recently completed UUIDs. Active and
retained completed UUIDs are rejected. The oldest completed UUID becomes eligible when the
cache evicts it. External removal releases its active UUID immediately and retains no content.

Remaining limitations: the handoff anchor is a stable overlay-frame contract rather than direct SpriteKit node projection, and the notification card size remains fixed for this issue.

## Presentation sessions and clocks

Every claimed notification receives a `PresentationSessionID` containing a monotonically increasing generation and the notification UUID. Queue advancement deliberately starts a new generation. An external content update preserves the session and increments its content revision; old replacement completions therefore fail centralized validation. IDs are never derived from notification text.

The main-actor session coordinator stores the phase, revision, choreography and timeout tasks, pause state, monotonic deadline, remaining transient duration, winning dismissal cause, cancellation reason, and session-scoped deferred lifecycle markers. Replacing or cancelling a session cancels every registered child. Async completions validate session, notification, expected phase, and revision through one coordinator API before touching state, queue projection, cat motion, or card UI.

`PresentationClock` exposes a monotonic instant and deadline sleep. Production uses `ContinuousClock`; deterministic tests use `ManualPresentationClock`, whose explicit advance resumes reached waiters and whose cancellation removes and resolves a waiter. When paused, the coordinator stores `max(0, deadline - now)` and cancels the wait. Resume creates a deadline from that remainder. Repeated cycles cannot restore the original duration, and remaining time is intentionally not persisted across relaunch because sessions are process-lifetime UI work.

Dismissal is arbitrated once per session. User close, transient expiry, source disappearance, disable, source shutdown, permission loss, recovery, queue removal, replacement, and shutdown are explicit causes. Only the first cause can enter dismissal; later causes are stale or already dismissing. Logs record generation and cause only, never content.

SpriteKit awaited actions use unique keyed operation IDs and checked continuations. Cancellation or slot replacement removes only that action and resumes `.cancelled`; loop removal stays independent. Cat panel travel is tied to the presentation token and validates before every frame or final snap. AppKit animations use cancellation handlers and deterministic completion/cancellation frames. Shutdown and recovery cancel the session before resetting visuals, so no animation waiter intentionally survives.

## Logical placement refresh

Screen and position-setting changes resolve a Foundation-only `CatLogicalPlacement` from
the state machine, the active presentation phase, choreography ownership, and global
recovery/enable state. The states are `home`, `travellingToPresentation`, `presentation`,
`travellingHome`, and `hiddenOrRecovering`. A paused flow uses its unchanged presentation
phase, so pausing during either travel direction does not make the cat logically home.

`AppState` coalesces geometry bursts to the next main-actor turn and applies the newest
preferences as one cat-and-card transaction. Refresh policy is state specific:

- Home, wake, pickup, and settlement install both anchors and move the panel to the new
  sleeping origin without replacing the current SpriteKit pose.
- Outbound and return travel install both anchors and the new Dock edge, preserve the
  current panel origin, and cancel only the current motion operation. The existing travel
  loop keeps its `PresentationSessionID`, reads the new destination, edge, axis, and
  direction, then plans again from the panel's actual origin. A placement revision also
  catches a refresh during the arrival pose, and repeated refreshes collapse to the newest
  target. Paused travel reads that target after resume.
- Presentation, waiting, replacement, and card dismissal move the cat to the new
  presentation anchor. The card stores the matching anchor in the same main-actor turn.
  Stable cards relocate immediately. Active AppKit operations record a placement revision,
  retarget their visual frame, and reassert the newest frame before accepting completion;
  content, operation/session identity, timers, and the user-dismiss callback are untouched.
- Recovery and global disable may accept newer anchors for their eventual reset, but never
  restart or relocate active visual work; their existing fail-closed policy owns the reset.

`DockLocator` returns no placement when AppKit has no screen. `AppState` then retains the
last valid anchors and current overlay frames—never a synthetic zero coordinate—and applies
the next valid resolution when a screen returns. Before the first valid placement, the cat
stays unordered and notification claiming waits; the first valid geometry establishes the
sleeping overlay before queued delivery begins. Falling back from a missing selected screen
to an available screen is recorded without logging screen descriptions.

Geometry refresh has its own privacy-safe revision and does not submit a state-machine
event, claim/complete a queue item, change the projected notification, create a presentation
session, or restart transient timing. Dock-edge-aware/clamped card geometry remains issue
#78; stable display identity, selection policy, calibration, and previews remain issue #79.
# External lifecycle reconciliation

`ExternalNotificationLifecycleTracker` serializes bounded visible-item state and emits typed lifecycle events. `ExternalPresentationPolicy` deterministically maps structural evidence to best-effort presentation behavior. `NotificationQueue` remains the atomic owner of pending/current items and supports identity-based update, removal, and location while preserving DockCat UUIDs and pending FIFO order.

Presentation-session ownership, cancellation redesign, and injectable timing remain deferred to issue #75.
