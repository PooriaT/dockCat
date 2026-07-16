# Notification sources

All inputs use a typed `NotificationSourceEvent`: existing developer and URL inputs remain normal `DockCatNotification` events, while the experimental Accessibility observer emits neutral candidate snapshots. Candidates terminate at a no-op router until issue #69 and cannot reach the card queue.

A source must validate at its trust boundary, avoid blocking the main actor, and submit only model values. No source may invoke presentation or animation directly.

## Experimental System Notifications onboarding

The disabled-by-default observer uses only public Accessibility APIs. It resolves `com.apple.notificationcenterui` (plus a small legacy identifier/name fallback), listens for that process launching or terminating, and reattaches after PID replacement. It independently attempts created, children/layout/value changed, window-created, and destroyed callbacks because availability varies by macOS release. Partial registration is degraded; no useful registration is unavailable.

Callbacks snapshot the changed element's immediate container rather than the desktop. Bursts are coalesced for 40 ms. Traversal defaults to depth 6, 80 nodes, 512 characters per string, and 8,192 total text characters; cycles and repeated elements are stopped. Snapshot data has no AX references, screenshots, OCR, or inferred hidden content. Issue #69 owns fixture-driven parsing, normalization, semantic deduplication, and lifecycle classification. Later issues own dismissal actions.

The health model reports `disabled`, `permissionRequired`, `starting`, `active`, `degraded`, or `unavailable`. `active` requires every attempted structural registration through the preferred bundle identifier; fallback resolution or partial registration is degraded. Permission loss removes registrations and the run-loop source.
