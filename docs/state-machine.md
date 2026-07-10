# State machine

Primary flow: `sleeping → waking → pickingUpCard → walkingToPresentation → presenting → waitingForDismissal → preparingNextNotification`. A queued item returns to `presenting`; an empty queue continues through `walkingHome → settlingDown → sleeping`.

Animations complete before their `animationCompleted` event is sent. Only transient visibility uses a duration timer. Invalid state/event pairs return `false` and are logged by the coordinator. Pause records and restores the prior logical state.
