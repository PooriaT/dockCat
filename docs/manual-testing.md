# Manual testing

## Accessibility normalization and burst deduplication

1. Enable system notifications, trigger one synthetic notification, and verify multiple AX callbacks produce one DockCat card.
2. Trigger two notifications from the same app with different invented bodies and verify both appear.
3. Enable hidden previews and verify no hidden title or body is exposed; only visible source/placeholder information may appear.
4. Open Notification Center widgets and verify they do not produce cards.
5. Trigger visible text longer than 512 characters and verify it is safely truncated.
6. Send developer and `dockcat://notify` events and verify both still enter the queue normally.
7. Inspect Console output and verify it contains result categories but no notification text.
8. Generate repeated callbacks for longer than the retention window and verify storage stays at or below 256 digest records.

Lifecycle disappearance, active-card updates, and native-banner dismissal are intentionally left for issue #70.

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
- Pause while idle, enqueue several notifications, and confirm none presents until resume.
- Pause while a card is visible, enqueue more notifications, then resume and confirm the visible card remains authoritative before FIFO delivery continues.
- Toggle pause/resume rapidly from both Settings and the menu bar. Confirm controls disable during an actor transition and the final published state, visuals, and queue behavior match the final request.
- Update an active external notification and confirm replacement uses the updated payload without duplicate presentation.
- Remove active and pending external notifications. Confirm active removal follows ordered card dismissal/replacement and pending removal never presents.
- Change the queue limit while items are present. Existing items must remain ordered; only later admissions use the new limit.
- Inspect queue and transition logs. They may include UUIDs, revisions, counts, limits, and outcome categories, but never notification content.

## Reduced Motion

- Enable Reduce Motion and confirm presentation uses fade-in, dismissal uses fade-out, queued replacement uses crossfade, and logical ordering is unchanged.

## Cancellation

- Pause, disable, stop, or otherwise cancel during card presentation and confirm stale animation completion does not show, dismiss, or overwrite a later notification.

## Effect-driven transitions and recovery

- Send an internal transient notification and confirm the complete wake, pickup, travel, presentation, timeout, card dismissal, return, settle, and sleep flow.
- Send an internal persistent notification and confirm it waits for close before ordered dismissal and return.
- Queue three notifications with stay-in-place enabled and confirm each replacement remains at the presentation anchor.
- Update an active external item and confirm replacement; remove it and confirm ordered card dismissal before return home.
- Pause during travel and during card animation, then resume and confirm the prior state/effect continues.
- Through a debug-only test seam, submit an invalid event and confirm no later effect runs, stale DockCat UI is hidden, the cat resets to sleeping, and a later notification can present.
- Inspect transition and recovery logs. They may contain states, events, effect categories, reasons, and identifiers, but no title, body, AX text, or card content.

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
# External lifecycle checks

With experimental system notifications enabled, verify a simple banner is transient, an action-oriented alert is persistent, and an ambiguous fixture remains until its source disappears. Update visible content and confirm the card changes without cat travel. Remove active and pending native items and confirm ordered active dismissal and pending removal. Revoke Accessibility permission and confirm external cards clear while internal test and URL notifications continue. Queue several items to verify FIFO. Logs must contain identities/outcomes only, never content.

DockCat deliberately does not close or act on the original native notification; native action execution belongs to issue #71.

## Experimental original-banner closing

With the System Notifications source active and Accessibility permission granted, enable **Best-effort close original banner after capture**. Verify that DockCat accepts the mirror before the native close attempt; the original may appear briefly or remain. Exercise close, reply, open, options, and destructive controls and confirm only a strongly identified close is pressed. Exclude an app by bundle identifier and confirm its banner remains while its mirror appears. Then disable the option, revoke permission, and test a banner without an exposed close button; all must safely perform no action. Confirm logs contain no notification text or control labels and that the mirrored card follows the existing disappearance lifecycle.
