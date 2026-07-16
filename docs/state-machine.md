# DockCat state machine

Primary flow:

```text
sleeping
→ waking
→ pickingUpCard (mini-card visible)
→ walkingToPresentation (mini-card carried)
→ presenting (expanded-card handoff)
→ waitingForDismissal
→ preparingNextNotification
→ dismissingCard
→ walkingHome
→ settlingDown
→ sleeping
```

A queued item with stay-in-place enabled transitions from `preparingNextNotification` to `presenting` with `nextNotificationAvailable`; it does not enter `dismissingCard`, `walkingHome`, `settlingDown`, or `sleeping` between queued cards. An empty queue transitions from `preparingNextNotification` to `dismissingCard`; only the `cardDismissed` event can then enter `walkingHome`.

Ordering invariants:

- `cardPresented` is valid only from `presenting`, which is reached only after travel reports `animationCompleted` from `walkingToPresentation`.
- `waitingForDismissal` begins only after the card presentation operation completes and `cardPresented` is accepted.
- Return-home motion begins only after `dismissingCard` accepts `cardDismissed`.
- Invalid events are rejected, including return-home animation completion while the expanded card is still dismissing.
