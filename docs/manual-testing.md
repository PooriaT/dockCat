# Manual testing

## Hidden menu-bar recovery

- In Settings, turn off **Show menu-bar icon**. Cancel the warning and confirm the paw remains. Repeat, copy the recovery command, and confirm the command is on the pasteboard without hiding. Repeat and choose **Hide Menu Item**.
- Confirm the warning says DockCat has no normal Dock icon and that hiding does not affect notification delivery.
- With the paw hidden, run `open 'dockcat://settings'`; Settings must open and the paw must remain hidden. Run `open 'dockcat://settings?restoreMenuBar=1'`; the existing Settings scene must come forward and the paw must return.
- Hide the paw again and run `open -a DockCat` while DockCat is already running. The existing process must open Settings through the reopen callback without restoring the preference.
- Quit DockCat, then separately test `open -a DockCat --args --show-settings` and `open -a DockCat --args --restore-menu-bar`.
- Repeat the URL, reopen, and command-line cases while delivery is paused, while DockCat is globally disabled, and while a transient is active. Enabled state, pause, queue/current item, and remaining time must not change.
- Repeat once with launch at login enabled and once disabled. A background login launch with the paw hidden must not automatically show Settings, and later recovery must use the existing process without duplicate overlays or sources.
- Temporarily test a build without the `dockcat` entry in `CFBundleURLTypes`. The Settings toggle must refuse to hide and show an actionable error; runtime repair must not be attempted.
- Inspect Console logs. They may identify URL/recovery categories, Settings request sources, verification results, visibility transitions, and duplicate bootstrap rejection, but never URL queries or notification content.
- For the narrow fallback, quit the app, run `defaults delete com.example.DockCat DockCat.menuBarVisible`, relaunch, and confirm the paw defaults visible while unrelated settings remain unchanged.

## Global lifecycle

- Launch once with DockCat enabled and once with it disabled. Disabled startup must show no cat, card, or calibration preview and must not start System Notifications observation.
- Disable while sleeping, waking, travelling out, presenting or replacing a card, waiting on transient expiry, showing a persistent card, returning home, delivery-paused, and with visual animations suppressed. Both overlays and calibration markers must disappear and remain hidden.
- While disabled, trigger menu tests, simulator events, URL events, and external system notifications. Nothing should enter delivery or modify native system UI.
- Re-enable and confirm the queue is empty, no prior or partially presented item replays, pause is reset, and the sleeping cat appears only after a valid placement resolves.
- Leave the System Notifications preference enabled across disable/re-enable and confirm observation stops and restarts. Repeat with the preference disabled and confirm re-enable does not force it on.
- Pause an active transient, wait longer than its original duration, and resume. The active overlays and queue remain in place and only the saved remaining duration runs. New bounded items may queue while paused.
- Repeatedly invoke enable/disable and pause/resume, including during transition states, and confirm the menu and Settings always show the same authoritative mode.
- Quit from each runtime mode and confirm no overlay, source observer, timer, animation continuation, or reconciliation task remains. Menu-bar-hidden recovery is deferred to issue #83.

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

## Passive and interactive card focus

- Type continuously in another application while transient and persistent cards appear. Confirm
  DockCat does not activate, the card is not key, and every keystroke remains in that application.
- With a passive card visible, press Escape and confirm nothing dismisses. Confirm presentation,
  replacement, queue-footer changes, fitting-size updates, and placement refreshes never activate
  DockCat.
- Click card background and message/scroll content. Confirm DockCat becomes active, the panel becomes
  key, no control fires, and Tab/Shift-Tab traverse Open then Close where present.
- Click Open and Close directly on a passive card. Confirm each works on its first deliberate click
  and fires once. Confirm a failed or rejected non-HTTPS Open leaves the card visible and interactive.
- After background interaction, press Escape on a dismissible card and confirm it follows the same
  one-shot dismissal route as Close. Repeat with a non-dismissible transient and confirm Escape is
  ignored.
- Interact with a card, close it, and confirm the previously active running application regains focus
  only after the card resigns key or hides. Repeat after terminating that application and confirm no
  activation is attempted.
- Invoke Open and confirm the browser/target remains focused after card dismissal; the application
  that was active before card interaction must not be reactivated over it.
- Interact, manually switch to a third application, then close the card or let it expire. Confirm
  DockCat does not steal focus from the third application.
- Interact with one card and allow queued or external replacement. Confirm prior focus is restored
  when safe and the replacement begins passive. A stale Escape or control callback must not dismiss
  the replacement.
- Repeat source disappearance, transient expiry, global disable, Accessibility permission loss,
  fail-closed recovery, and shutdown while interactive. Confirm no key panel or delayed focus task
  remains and force-hide never invokes user dismissal.
- Repeat with Reduced Motion and Pause visual animations. Confirm focus policy is unchanged and
  entering interaction never restarts or pauses the transient timer or mutates queue state.

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

## Runtime animation and accessibility settings

- Drag Cat scale from 0.5 to 2.0 while sleeping, during outbound/return travel, and with a
  persistent card visible. Repeat with bottom, left, and right Docks and a negative-coordinate
  secondary display. Confirm the Dock anchor does not drift, vector art is not clipped, and the
  card remains separated from the scaled exclusion frame.
- Disable Idle breathing while sleeping and confirm the pose becomes static immediately.
  Re-enable it and confirm exactly one breathing loop. Toggle it during delivery and confirm
  active choreography is not disrupted and the next sleeping pose uses the newest value.
- Enable Disable walking and send transient and persistent notifications. Confirm wake and
  pickup remain animated, the mini-card remains visible, both travel directions use a short
  fade relocation, and no turn/walk loop or continuous Dock traversal occurs.
- Enable Pause visual animations during wake, travel, card presentation, waiting, card
  dismissal, return, and settlement. Confirm each visual reaches a valid final state, delivery
  continues, the transient countdown is neither paused nor restarted, and later queued
  notifications still present. Disable it and confirm skipped animations are not replayed.
- Toggle app Reduced Motion and macOS Reduce Motion while a visual operation is active.
  Confirm the effective mode changes without relaunch, the same notification/session remains
  authoritative, and transient remaining time and queue order are unchanged.
- Compare Pause visual animations with Pause DockCat: the former skips only visuals while the
  latter pauses delivery and preserves transient remaining time.
- Inspect visual diagnostics. They may contain only effective mode, app/system Reduced Motion,
  idle state, clamped scale, overlay dimensions, rebase state, and no-walking use—never
  notification content or display serial values.

## Cancellation

- Pause, disable, stop, or otherwise cancel during card presentation and confirm stale animation completion does not show, dismiss, or overwrite a later notification.
- Pause halfway through a transient card, wait longer than its original duration, resume, and confirm only the saved remainder is visible.
- Repeat pause/resume several times and confirm the total unpaused visible time does not grow.
- Race the close button with transient expiry and source disappearance; confirm one card dismissal and one queue completion.
- Update an external notification during card expansion and replacement, then remove it during wake, travel, expansion, replacement, and dismissal. Confirm disappearance wins and no old content returns.
- Disable DockCat, revoke Accessibility permission, and quit during wake, travel, presentation, and dismissal. After each case, send a new test notification and confirm there is no stuck cat, stale panel, old-destination snap, or delayed dismissal.

## Placement refresh during choreography

- While the cat sleeps, drag each Position slider. Confirm the sleeping cat follows the
  newest anchor without task buildup.
- Change Position while wake and pickup animations run. Confirm the cat moves home while
  the current pose continues and the notification is not restarted.
- During outbound travel, move the Dock to another edge and attach or detach a display.
  Confirm the cat continues from its current origin toward the newest presentation anchor,
  with no snap to home or either old anchor.
- Pause during outbound and return travel, change geometry, then resume. Confirm the cat
  continues toward the new target and the same notification remains active.
- With stable transient and persistent cards visible, change offsets and display resolution.
  Confirm cat and card remain together and the transient remaining duration is unchanged.
- Change geometry during initial card presentation, queued replacement, and card dismissal.
  Confirm the visual operation rebases, content does not revert, and no placement refresh
  is treated as a user close.
- Change the Dock edge during return travel and settlement. Confirm return retargets from
  the current origin and settlement completes at the new sleeping anchor without showing a
  card.
- Repeatedly drag a Position slider and inspect privacy-safe placement logs. They may contain
  only revision, logical placement, old/new Dock edge, retarget/rebase flags, and fallback or
  last-valid use. Confirm a later notification still completes normally.
- Where practical, detach the selected display and briefly exercise a no-screen transition.
  Confirm overlays never move to zero; the last valid geometry remains until a valid fallback
  or returning screen is resolved.

## Dock-edge-aware notification card placement

- Put the Dock on the bottom, left, and right edges of the main display. Confirm the card is,
  respectively, above, right of, and left of the cat with a consistent Card offset gap.
- Select a secondary display to the left of or above the main display. Confirm negative global
  x or y coordinates are preserved and the card stays on the selected display.
- Move the cat presentation location near all four visible-frame corners. Confirm the entire
  card remains inside the work area with a small margin and does not cover the handoff anchor
  when a collision-free position exists.
- Present short and long title/message combinations, cards with an Open action, and persistent
  cards with the close control. Confirm the panel height follows the content without flashing.
- Confirm a source and one-line title card is compact, a short body has no scrollbar, and a very
  long invented body scrolls internally while source, title, close, Open, and queue footer stay
  fixed and reachable. Repeat with a two- or three-line title and increased accessibility text size.
- While a card is visible, enqueue one and then several items. Confirm subtle singular/plural queue
  copy appears without a preview, disappears as pending items are removed or claimed, and changes
  to `N waiting · delivery paused` during delivery pause. The current item must not be counted.
- Confirm queue-footer appearance/disappearance resizes the same card in place without a crossfade,
  dismissal callback, presentation-session change, or change to a transient's remaining time.
- Replace a short visible card with a taller card and then reverse the order. Confirm origin and
  size animate together, remain on-screen, and the active notification session is unchanged.
- While a card is visible, change Position settings, display resolution, accessibility text
  size, and action-button visibility. Confirm the card remeasures and follows the newest
  placement without invoking dismissal.
- Enable Dock auto-hide and repeat each Dock edge. Confirm fallback geometry remains within the
  selected screen's visible frame.
- On an unusually small or scaled display, confirm an oversized card is constrained to the
  margin-adjusted visible frame, controls are preserved before body viewport space, and placement
  or content-layout diagnostics report a typed degraded result.
- Inspect card-placement logs. They may contain only Dock edge, card dimensions, clamp and
  collision flags, notification UUID, pending count, placement/queue revisions, scrolling and size
  animation flags, and degradation—never notification text, action URL, or screen name.

## Stable display selection and Dock calibration

- In Automatic mode, move the pointer repeatedly between displays. Confirm DockCat stays on the
  initially resolved main display. Disconnect that display and confirm fallback selects the current
  main display; reconnect it and confirm Automatic does not jump back during this app run.
- Select Main display, change the system main display, and confirm placement follows it. Select a
  specific display, relaunch, and confirm the stable selection returns when public identity permits.
- Disconnect a specifically selected display. Confirm Settings preserves a disconnected row and
  warning, preview stops, runtime placement uses a non-pointer fallback, and no overlay moves to
  `(0, 0)`. Reconnect while sleeping and confirm immediate restoration. Reconnect during travel or
  presentation and confirm restoration waits until that presentation finishes and reaches sleeping.
- If two connected displays have identical localized names, confirm their short identity tokens
  distinguish the picker rows and choosing either resolves the intended geometry.
- Move the Dock between bottom, left, and right. Confirm Position shows the inferred edge and an
  observed, auto-hide, or ambiguous confidence. Enable auto-hide and confirm the UI labels geometry
  as estimated and recommends calibration rather than claiming exact Dock ends.
- Start Preview and adjust all four calibration controls. Confirm blue Home and orange Presentation
  markers move independently, remain click-through/on-screen, and the notification queue, active
  presentation, and transient timer are unchanged. Close Settings, disable DockCat, or remove the
  selected display and confirm both markers disappear.
- Save distinct calibration values on two displays and on two Dock edges, relaunch, and verify each
  record returns only for its display/edge. Use Reset Current and Reset All and confirm the expected
  records return to zero without changing unrelated preferences.
- Change calibration while sleeping, travelling out, presenting, travelling home, and returning.
  Confirm the cat moves immediately at stable anchors, active cat/card stay together, travel retargets
  without a new notification session, and return retargets home.
- Inspect diagnostics. They may contain only short display tokens, selection mode, availability,
  fallback use, Dock edge/confidence, calibration presence, and preview start/stop—not full display
  serials, hardware fingerprints, localized display names, or notification content.

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
