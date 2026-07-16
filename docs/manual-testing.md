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

## Experimental System Notifications onboarding

- With fresh preferences, open the System tab and confirm the experimental source is disabled and no Accessibility prompt appears.
- Enable it without trust and confirm the status is **Accessibility permission required** while Developer test notifications and `dockcat://notify` continue to work.
- Press **Request Accessibility Permission** and confirm only that explicit action initiates the system-controlled permission flow.
- Return from System Settings or press **Recheck** and confirm the status updates without relaunching.
- With trust granted, enable the source and confirm status truthfully reaches **Active** or **Degraded**.
- Trigger notifications from several applications and confirm privacy-safe candidate counts increase, but DockCat presents no raw candidate.
- Restart Notification Center (or log out and back in) when practical and confirm the observer resolves the replacement PID.
- Revoke permission, reactivate DockCat, and confirm the status returns to permission required with revocation guidance.
- Disable the source and confirm callback counts stop and it remains disabled after relaunch. Confirm native banners are not suppressed and logs contain no notification text.
