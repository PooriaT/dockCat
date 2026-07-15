# State machine

Primary flow: `sleeping → waking → pickingUpCard → walkingToPresentation → presenting → waitingForDismissal → preparingNextNotification`. A queued item returns to `presenting`; an empty queue continues through `walkingHome → settlingDown → sleeping`.

Animations complete before their `animationCompleted` event is sent. Only transient visibility uses a duration timer. Invalid state/event pairs return `false` and are logged by the coordinator. Pause records and restores the prior logical state.

## Locomotion visual selection

The high-level app state machine still owns notification flow, while `CatWindowController` coordinates locomotion visuals with panel motion. For travel, it resolves a typed `CatAnimationContext`, plays a turn animation, starts the carry pose or walk loop, runs the existing panel-motion driver, then stops the loop. Completed outbound motion enters a stopped/waiting carry pose; cancelled motion stops the loop and returns to a stable non-walking carry pose without reporting arrival.

Return-home travel resolves from the current motion path as well, so the cat faces the reverse path back to the sleeping anchor. The app does not duplicate the motion driver's cancellation logic; it reacts to the completion result and avoids arrival-only animations when motion is cancelled.
