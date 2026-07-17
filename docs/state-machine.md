# DockCat state machine

`CatStateMachine` is a pure value type. `handle(_:)` returns either an accepted
`CatTransition` or a privacy-safe `CatTransitionRejection`; it never returns a Boolean.
An accepted transition records the previous state, event, next state, and exactly one
semantic `CatCoordinatorEffect`. State changes only after that complete decision exists.

## Authoritative transition table

| Current state | Event | Next state | Coordinator effect |
| --- | --- | --- | --- |
| sleeping | notificationAvailable | waking | wake |
| waking | animationCompleted | pickingUpCard | pickUpCard |
| pickingUpCard | animationCompleted | walkingToPresentation | travelToPresentation |
| walkingToPresentation | animationCompleted | presenting | presentInitialCard |
| presenting | cardPresented | waitingForDismissal | enterWaitingState |
| waitingForDismissal | notificationUpdated | presenting | replaceActiveCard |
| waitingForDismissal | transientExpired | preparingNextNotification | selectNextQueueAction |
| waitingForDismissal | userDismissed | preparingNextNotification | selectNextQueueAction |
| waitingForDismissal | sourceDisappeared | preparingNextNotification | selectNextQueueAction |
| preparingNextNotification | nextNotificationAvailable | presenting | replaceActiveCard |
| preparingNextNotification | queueEmpty | dismissingCard | dismissExpandedCard |
| dismissingCard | cardDismissed | walkingHome | travelHome |
| walkingHome | animationCompleted | settlingDown | settleToSleep |
| settlingDown | animationCompleted | sleeping | none |
| any non-paused state | pause | paused | pauseVisualWork |
| paused | resume | recorded pre-pause state | resumePriorWork |

All other state/event pairs are rejected without mutation or an executable effect.
Duplicate pause is rejected as `alreadyPaused`; resume outside `paused` is rejected as
`notPaused`. Pause remembers the exact prior state and resume clears that memory after
restoring it.

The ordering invariants remain:

- The expanded card is presented only after travel completes.
- Waiting starts only after card presentation succeeds.
- Queued replacement stays at the presentation location.
- External updates replace the active card; source disappearance enters ordered dismissal.
- `cardDismissed` is required before return-home motion.

## Coordinator sequencing and rejection

`AppState.apply(_:)` is the sole production state-machine entry point. It publishes and
logs an accepted transition once. A bounded coordinator loop executes its semantic effect;
only successful completion emits the next event. Rejection executes no effect and schedules
recovery. Logs include only state, event, effect category, and typed reason—never notification
title, body, Accessibility text, or card content.

Presentation cancellation caused by pause, stop, or operation replacement is expected. It
stops the current chain and may retain resumable visual work; it is not evidence of state
corruption and does not itself trigger recovery.

## Fail-closed recovery policy

An impossible production sequence or missing prerequisite triggers recovery once:

1. Cancel the flow and transient timer.
2. Cancel card presentation and cat motion/animation work.
3. Hide expanded and carried cards and restore the cat at its sleeping anchor.
4. Clear interrupted-flow and deferred external-lifecycle markers.
5. Drop the inconsistent active DockCat queue item, preserving pending items.
6. Reset the state machine to `sleeping`, unpause the queue, and attempt the next pending item.

Recovery does not retry the inconsistent effect and never acts on native system UI.

Queue atomic-operation redesign remains deferred to issue #74. Presentation ownership,
session identifiers, injectable timing, and timer clocks remain deferred to issue #75.
