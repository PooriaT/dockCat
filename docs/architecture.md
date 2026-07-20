# Architecture notes

- `AppState` is the top-level choreography owner. Its single `apply(_:)` entry point consumes typed state-machine decisions, while `PresentationSessionCoordinator` owns notification-specific choreography and timeout tasks. Successful async effects emit the next semantic event; rejection or an impossible prerequisite stops the chain and enters fail-closed recovery.
- `CardWindowController` owns only the AppKit panel. Its presentation, replacement, and dismissal operations are async and return `PresentationAnimationResult.completed` or `.cancelled`. Operation tokens include the presentation session, task cancellation resumes the checked continuation immediately, and force-hide resolves pending work before resetting the panel.
- `CatWindowController` exposes a handoff-anchor contract through `handoffSourceRect()`. The rect is derived from the cat overlay panel origin plus the documented visual anchor and mini-card carry offset, avoiding SpriteKit internals in app choreography.
- Mini-card visibility is controlled through focused cat-window APIs. Pickup and travel keep the card visible; successful expanded-card presentation completes the handoff pose and hides the mini-card; dismissal and return home reset it.
- Transient timers are scheduled only after the expanded-card animation completes and the state machine accepts `cardPresented`. Persistent notifications do not schedule timeout tasks. Timing uses `ContinuousPresentationClock`, never `Date`.
- Queued replacement with stay-in-place enabled crossfades panel content without hiding the panel or sending the cat home. If stay-in-place is disabled, the expanded card dismisses before walk-home starts.
- Reduced Motion uses shorter fades and avoids large frame travel for presentation/dismissal while preserving the same state-machine events and timer ordering.
- Recovery drops only an inconsistent active DockCat item, preserves pending queue items, force-hides stale DockCat UI, resets cat visual work and state to sleeping, and attempts later pending work. Expected animation cancellation remains resumable and is not treated as corruption. Native system UI is not modified by recovery.

## Runtime lifecycle

`DockCatRuntimeLifecycle` is the Foundation-only transition authority. Its modes are `enabling`, `running`, `deliveryPaused`, `disabling`, `disabled`, and `shuttingDown`; transitions return typed results and rejection reasons. Shutdown is terminal, disable wins over delivery pause, pause is accepted only from running, and visual animation mode plus the System Notifications user request remain orthogonal snapshot fields. `AppState.runtimeSnapshot` is the single menu and Settings projection.

Disable blocks submissions and invalidates generation before source shutdown, stops calibration and reconciliation, cancels queue claims and presentation work, resolves visual waiters, force-hides card and cat panels, atomically clears current and pending queue storage while resetting pause, clears projections and deferred external state, resets the cat machine and hidden scene to sleeping, then publishes `disabled`. The queue's recent-completion cache is retained. Repeated disable requests coalesce.

Enable waits behind disable cleanup, clears and unpauses the queue, resets presentation/state projections, applies current visual preferences, resolves placement, prepares the hidden sleeping scene, shows the cat only for a valid placement, installs a new runtime generation, restores the source and reconciliation gates, publishes `running`, and only then permits claims. Saved disabled startup never shows an overlay or starts external observation. Shutdown uses the same cancellation and hiding rules without restart.

## Runtime visual preferences

`EffectiveAnimationPreferences` is the Foundation-only policy boundary for every visual
surface. Its precedence is Pause Visual Animations, effective Reduced Motion, Disable
Walking, then Full. Pause wins because it promises deterministic final states; the union of
the app and current macOS accessibility setting wins next so the stronger accessibility
request applies everywhere. Disable Walking remains a travel-only mode and never makes
`effectiveReducedMotion` true.

Pause Visual Animations is intentionally unrelated to Pause DockCat. It completes current
cat and card visuals at their final states and makes future visual effects immediate, but it
does not mutate the queue, suspend delivery, alter `AppState.isPaused`, stop notification
sources, or reschedule transient timers. A live mode change resolves existing SpriteKit and
AppKit waiters through their operation tokens; cat travel replans within the same
`PresentationSessionID`.

The SpriteKit hierarchy is `layoutRoot` (user scale and visual anchor) → `facingRoot`
(mirroring and Dock-edge rotation) → `poseRoot` (breathing, bobbing, settlement) → artwork.
Consequently facing, breathing, cancellation, and sleep reset cannot overwrite `catScale`.
Idle breathing is one keyed repeat-forever action; disabling it removes that action and
leaves the sleeping pose static, while active choreography adopts the preference on its next
sleep settlement.

`CatOverlayGeometry` owns scaled artwork/panel dimensions, named tail/paw, rotation, and
breathing safety padding, the visual anchor, transformed carry offset, handoff rect, and full
presentation exclusion frame. Panel resize first recovers the global visual anchor from the
old geometry and then derives the new origin, so positive and negative display coordinates
and home/travel/presentation anchors do not drift. Scale ticks coalesce on the main actor;
the latest resize cancels only panel motion for replanning and refreshes card placement
without replacing the presentation session.

Disable Walking uses a short fade-assisted relocation in both directions. Wake and pickup
remain normally animated unless Reduced Motion or Pause Visual Animations takes precedence.
No turn or walking loop is started in this mode. macOS Reduce Motion is observed from the
public workspace accessibility-display notification and refreshed when the app becomes
active; observation is injectable and stops during app shutdown.

Menu-bar-hidden recovery remains deferred to issue #83.

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
- `clearForGlobalDisable()` removes current and pending storage, clears active IDs, resets
  pause, and increments the revision exactly once when any of those values changed. It is
  idempotent and preserves the bounded recent-completion cache.

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

Remaining limitation: the handoff anchor is a stable overlay-frame contract rather than direct SpriteKit node projection.

## Presentation sessions and clocks

Every claimed notification receives a `PresentationSessionID` containing a monotonically increasing generation and the notification UUID. Queue advancement deliberately starts a new generation. An external content update preserves the session and increments its content revision; old replacement completions therefore fail centralized validation. IDs are never derived from notification text.

The main-actor session coordinator stores the phase, revision, choreography and timeout tasks, pause state, monotonic deadline, remaining transient duration, winning dismissal cause, cancellation reason, and session-scoped deferred lifecycle markers. Replacing or cancelling a session cancels every registered child. Async completions validate session, notification, expected phase, and revision through one coordinator API before touching state, queue projection, cat motion, or card UI.

`PresentationClock` exposes a monotonic instant and deadline sleep. Production uses `ContinuousClock`; deterministic tests use `ManualPresentationClock`, whose explicit advance resumes reached waiters and whose cancellation removes and resolves a waiter. When paused, the coordinator stores `max(0, deadline - now)` and cancels the wait. Resume creates a deadline from that remainder. Repeated cycles cannot restore the original duration, and remaining time is intentionally not persisted across relaunch because sessions are process-lifetime UI work.

Dismissal is arbitrated once per session. User close, transient expiry, source disappearance, disable, source shutdown, permission loss, recovery, queue removal, replacement, and shutdown are explicit causes. Only the first cause can enter dismissal; later causes are stale or already dismissing. Logs record generation and cause only, never content.

SpriteKit awaited actions use unique keyed operation IDs and checked continuations. Cancellation or slot replacement removes only that action and resumes `.cancelled`; loop removal stays independent. Cat panel travel is tied to the presentation token and validates before every frame or final snap. AppKit animations use cancellation handlers and deterministic completion/cancellation frames. Shutdown and recovery cancel the session before resetting visuals, so no animation waiter intentionally survives.

## Card focus and interaction

Every expanded card starts in `CardInteractionMode.passive`, including persistent cards and
cards with Open actions. `orderFrontRegardless()` may order the accessory-app panel without
activating DockCat, assigning a first responder, or making the panel key. Placement, fitting-size,
queue-context, and visual-preference refreshes retain that passive state and never call
`NSApp.activate`. This keeps typing in the previously active application and preserves DockCat's
agent-app behavior.

`CardInteractionState` is the Foundation-only transition model. It stores only presentation and
monotonic interaction generations, a prior process identifier, the pointer/keyboard/accessibility
trigger category, and whether explicit interaction activated DockCat. Repeated requests for the
same card are idempotent. Stale presentation or interaction generations cannot enter interaction
or restore focus. Queue advancement resets the visible panel to passive. A same-session external
content revision reuses the hosting view and preserves an equivalent live control target.

`CardInteractionCoordinator` is the main-actor bridge between that model and injectable focus and
HTTPS-opening adapters. The panel reports the first deliberate pointer-down before dispatching the
event to SwiftUI, so Open and Close work on that click without duplicating their actions. A card
background or message click enters interactive mode but performs no control action. Accessibility
may request the same typed transition after session validation. After explicit entry, local
traversal is Open, Close, then an overflowing keyboard-scrollable message; Shift-Tab reverses it.
Native Return/Space button activation and ScrollView navigation remain intact.

`CardOverlayPanel.canBecomeKey` is false while passive and true only while interactive;
`canBecomeMain` remains false. Entering interaction changes eligibility before DockCat activation
and `makeKeyAndOrderFront`. Returning passive explicitly resigns key. Escape is accepted only when
the panel is interactive, currently key, and the active semantic card is dismissible. It emits the
same typed close request as the Close control; programmatic order-out, replacement, disable,
recovery, source disappearance, and shutdown never use the Escape callback.

Interactive Close routes through `AppState.dismissCurrent()` and the existing presentation
dismissal arbitration. The prior application is restored once, after the card has resigned key or
hidden, only when the interaction and presentation generations remain current, the process still
runs, and no third application became frontmost. A successful HTTPS Open uses the injected
workspace opener, then takes the same dismissal route with a no-restoration policy because the
browser or target app owns intentional focus. Failed or non-HTTPS Open requests leave the card
interactive and visible.

Non-user disappearance, expiry, disable, permission loss, recovery, and shutdown clear interaction
state. If DockCat still owns focus they may safely restore the prior running app after hiding; if the
user has switched elsewhere they do nothing. Neither interaction entry nor cleanup touches queue
revisions, presentation phases, transient deadlines, pause state, or runtime lifecycle.

`NotificationCardAccessibilityModel` is the Foundation-only source of ordered regions, roles,
stable identifiers, labels, hints, controls, queue status, and privacy-safe arrival copy. The
SwiftUI container contains children rather than replacing them with one label. AppKit announcement
delivery is injected, session/revision deduplicated, and scheduled only after `AppState` accepts the
visible presentation completion. Queue metadata and appearance refreshes never replace session or
timing ownership.

`AccessibilityDisplayOptions` is one coherent four-flag value read by one workspace observer.
`CardAccessibilityAppearancePolicy` resolves material versus opaque semantic background, separator
emphasis, shadow/divider/focus treatment, and non-color-only status requirements without SwiftUI.
Live appearance application does not begin an animation operation or recalculate geometry.

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

`DisplayCatalog` is the single screen-parameter observer and converts `NSScreen` values into
Foundation-only descriptors. Identity prefers the public ColorSync/CoreGraphics display UUID,
then a SHA-256 hash of public vendor/model/serial/built-in metadata, then a clearly temporary
current-display-ID token. Localized names are display copy and legacy migration aliases only.
Public identity remains imperfect for some adapters and displays that expose incomplete data.

Automatic selection chooses the main display on first resolution and retains that runtime
identity while connected. If it disappears, automatic falls back to the main display (or the
first descriptor in deterministic geometry/name/identity order) and does not jump back during
the process run. Pointer movement is never an input. Main-display mode follows the current main
display. A missing specific selection remains persisted while runtime placement uses the retained
valid display, current main display, or deterministic first display. If the specific display
reconnects, restoration is immediate while home/sleeping and deferred during active presentation;
the transition back is applied after that session reaches sleeping.

`DockLocator` returns no placement when AppKit has no screen. `AppState` then retains the
last valid anchors and current overlay frames—never a synthetic zero coordinate—and applies
the next valid resolution when a screen returns. Before the first valid placement, the cat
stays unordered and notification claiming waits; the first valid geometry establishes the
sleeping overlay before queued delivery begins. Falling back from a missing selected screen
to an available screen is recorded without logging screen descriptions.

Dock geometry confidence distinguishes an observed visible-frame inset, the nonzero auto-hide
fallback estimate, and an ambiguous estimate. These values describe public-API evidence; they do
not imply exact Dock-end detection. Base anchors continue to consume the legacy global distance
and Trash-side offsets once. A bounded calibration is then applied in logical Dock coordinates:
`alongDock` is x for a bottom Dock and y for side Docks; positive `awayFromDock` is up for bottom,
right for left, and left for right. Home and presentation values are stored independently in a
deterministically ordered record array keyed by stable identity and Dock edge.

The Position tab edits only the current resolved display/edge record. Its two labelled preview
panels are transparent, nonactivating, click-through, screen-clamped, and independent of the cat,
card, queue, notification model, presentation coordinator, and timers. Preview ends when Settings
closes, DockCat disables or terminates, no display resolves, or a selected display disappears.

Preference decoding accepts the legacy `"automatic"`, `"main"`, decimal screen-number, and
localized-name strings. Number/name aliases migrate only when they identify one connected display;
otherwise the legacy request is preserved and runtime fallback remains safe. The next SettingsStore
save uses only the typed selection model. Calibration entries decode lossily so one corrupt or future
record does not invalidate unrelated preferences, duplicate display/edge records resolve last-wins,
and encoded record order is deterministic. Existing global offsets remain base inputs and are not
re-applied as calibration.

Geometry refresh has its own privacy-safe revision and does not submit a state-machine
event, claim/complete a queue item, change the projected notification, create a presentation
session, or restart transient timing. Card placement consumes the same revision and selected
screen geometry.

## Notification card placement

`CardPlacementPlanner` is a Foundation-only geometry boundary. Its input contains the
presentation anchor, Dock edge, measured card size, selected screen's global visible frame,
optional cat exclusion frame, user offset, and named screen margin. It returns the exact
frame, preferred direction, clamp and collision-fallback flags, and a typed degradation.
AppKit screen selection is not repeated in the card controller.

- A bottom Dock prefers the card above the cat and centers it horizontally on the anchor.
  A left Dock prefers the card to the cat's right and centers it vertically. A right Dock
  prefers the card to the cat's left and centers it vertically. `cardOffset` always means
  extra distance away from the protected cat/anchor region.
- The full card frame is clamped to the selected screen's `visibleFrame`, inset by a 10-point
  margin in global coordinates. Negative x and y origins are preserved. If the card is too
  large, its panel is deterministically constrained to that margin-adjusted available frame.
- The planner protects the handoff rect and presentation anchor with an 8-point minimum gap.
  If clamping creates an intersection, it tries two bounded Dock-axis adjustments, then an
  on-screen opposite-side candidate and screen corners. Preferred-side candidates always
  win. If no collision-free candidate exists, the clamped frame is returned with an
  `unavoidableCollision` degradation.
- `NotificationCardContent` is the immutable semantic boundary for source, title, message,
  presentation kind, control visibility, and privacy-safe `CardQueueContext`. It retains the
  notification UUID only for identity and never contains an action URL, mutable preferences,
  queue storage, or pending notification content.
- `CardContentLayoutPlanner` is Foundation-only. It allocates header, bounded title, Open action,
  queue footer, padding, and spacing before assigning the remaining bounded height to the message.
  Short cards use their natural height above an 84-point compact safety floor. Only an overflowing
  message scrolls; source, title, close, Open, and queue footer remain outside that scroll region.
  The preferred width is 340 points, narrow screens can reduce it below the 220-point normal
  minimum, and total height is bounded by both 480 points and the selected placement context.
- SwiftUI reports separate header, title, natural body, action, and queue-footer heights. The
  controller coalesces callbacks, ignores changes of 0.5 point or less, updates the pure plan,
  owns the panel content size, and re-runs placement. Accessibility text-size changes therefore
  grow natural regions until the bound is reached and then move body overflow into scrolling.
  Empty or unusually small available frames return typed degradation rather than invalid geometry.
- `AppState.cardQueueContext` is projected from authoritative revisioned queue snapshots only at
  accepted mutation/reconciliation boundaries. It counts pending items only. Zero is hidden;
  positive counts use deterministic singular/plural secondary copy, with a paused variant.
  `CardWindowController.updateQueueContext` rejects stale revisions and updates the hosted model,
  measurement, and stable frame in place without content replacement, a new presentation session,
  dismissal, or transient timer changes. Full mode may subtly animate the size; Reduced Motion and
  paused visual animations apply the valid final frame immediately.
- Placement contexts carry the app's monotonic placement revision. Active presentation,
  replacement, and dismissal transactions rebase against newer revisions before accepting
  completion. Hidden panels only store context, and geometry updates never call `onDismiss`.

Keyboard focus/scroll activation remains owned by issue #86. Complete VoiceOver traversal,
announcement, and appearance semantics remain owned by issue #87.

# External lifecycle reconciliation

`ExternalNotificationLifecycleTracker` serializes bounded visible-item state and emits typed lifecycle events. `ExternalPresentationPolicy` deterministically maps structural evidence to best-effort presentation behavior. `NotificationQueue` remains the atomic owner of pending/current items and supports identity-based update, removal, and location while preserving DockCat UUIDs and pending FIFO order.

Presentation-session ownership, cancellation redesign, and injectable timing remain deferred to issue #75.

## AppState dependency boundaries

`AppState` is constructed from `AppStateDependencies`, a single main-actor composition container. The live factory owns the AppKit-facing objects (`SettingsStore`, display catalog, window controllers, Dock locator, calibration preview, accessibility source/access controller, notification pipeline, native banner dismissal performer, presentation coordinator, and typed logger) and passes only narrow protocol surfaces into the coordinator. The initializer stores dependencies but does not start sources or overlays; `start()` performs callback binding and runtime startup, while `stop()` unbinds source and card callbacks before hiding UI and clearing the queue.

The queue boundary is `NotificationQueueing`, which keeps revisioned actor decisions authoritative and exposes only the atomic operations AppState already consumes. Cat and card protocols describe semantic visual operations, handoff geometry, presentation, replacement, dismissal, queue context, and accessibility-display updates without exposing panels, scenes, SwiftUI views, or focus objects. Placement remains in the app target through `DockPlacementProviding`; tests can replace it with fixed placements without constructing `NSScreen`.

System notification integration is split into access/health, pipeline lifecycle/reconciliation, event binding, and native banner dismissal protocols. The live composition root uses a small event router so callbacks are bound after AppState is fully initialized, avoids `unowned` captures, and can be unbound during shutdown. `PresentationSessionCoordinator` stays concrete and receives its clock at composition time; production uses `ContinuousPresentationClock`, while coordinator integration harnesses can inject `ManualPresentationClock` and rendezvous on pending waiters.

The logging boundary is intentionally privacy-safe. `DockCatEventLogging` has typed methods for runtime transitions, cat transitions, rejected transitions, stale callbacks, and recovery, plus bounded diagnostic strings for existing non-content events. It deliberately does not accept `DockCatNotification`, titles, message text, source text, action URLs, or accessibility text so issue #91 can extend bounded diagnostics without widening privacy exposure.

Types intentionally left concrete include `CatStateMachine`, `PresentationSessionCoordinator`, `DockCatRuntimeLifecycle`, `StartupNotificationBuffer`, and the revisioned queue result types. These are deterministic domain components and remain the authoritative source for transitions, sessions, runtime generation, and queue state.
