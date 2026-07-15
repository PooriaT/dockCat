# Manual testing

## Transient notification

- Send a transient notification and confirm the cat wakes, picks up the mini-card, and carries it during travel.
- Confirm the full card remains hidden during travel and expands only after arrival.
- Confirm the mini-card disappears only after the full card is established.
- Confirm the visible transient duration starts after expansion and the full card dismisses before the cat walks home.

## Persistent notification

- Send a persistent notification and confirm the card remains visible indefinitely while the cat waits at the presentation anchor.
- Close the card and confirm dismissal routes once, the card animates out, and only then does the cat return home.

## Queue

- Queue three transient notifications with stay-in-place enabled and confirm card content transitions in place without walk-home, settle, sleep, or panel flashing.
- Confirm each timeout starts after its own replacement completes.
- Disable stay-in-place and confirm each card dismisses before the cat returns home between notifications.

## Reduced Motion

- Enable Reduce Motion and confirm presentation uses fade-in, dismissal uses fade-out, queued replacement uses crossfade, and logical ordering is unchanged.

## Cancellation

- Pause, disable, stop, or otherwise cancel during card presentation and confirm stale animation completion does not show, dismiss, or overwrite a later notification.
