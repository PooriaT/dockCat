# Architecture notes

- `AppState` is the top-level choreography owner. Its single `apply(_:)` entry point consumes typed state-machine decisions, publishes/logs accepted transitions once, and sends semantic effects through one bounded executor. Successful async effects emit the next semantic event; rejection or an impossible prerequisite stops the chain and enters fail-closed recovery.
- `CardWindowController` owns only the AppKit panel. Its presentation, replacement, and dismissal operations are async and return `PresentationAnimationResult.completed` or `.cancelled`. Each operation has a fresh token so stale animation completions cannot mutate a newer notification's final panel state.
- `CatWindowController` exposes a handoff-anchor contract through `handoffSourceRect()`. The rect is derived from the cat overlay panel origin plus the documented visual anchor and mini-card carry offset, avoiding SpriteKit internals in app choreography.
- Mini-card visibility is controlled through focused cat-window APIs. Pickup and travel keep the card visible; successful expanded-card presentation completes the handoff pose and hides the mini-card; dismissal and return home reset it.
- Transient timers are scheduled only after the expanded-card animation completes and the state machine accepts `cardPresented`. Persistent notifications do not schedule timeout tasks.
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
# External lifecycle reconciliation

`ExternalNotificationLifecycleTracker` serializes bounded visible-item state and emits typed lifecycle events. `ExternalPresentationPolicy` deterministically maps structural evidence to best-effort presentation behavior. `NotificationQueue` remains the atomic owner of pending/current items and supports identity-based update, removal, and location while preserving DockCat UUIDs and pending FIFO order.

Presentation-session ownership, cancellation redesign, and injectable timing remain deferred to issue #75.
