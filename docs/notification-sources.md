# Notification sources

All future inputs conform to `NotificationSource`, exposing an identifier plus asynchronous `start(handler:)` and `stop()` methods. The MVP supports developer/UI submissions, menu commands, direct internal service submission, and the custom URL scheme. Those sources never require Accessibility permission.

A future source must validate at its trust boundary, avoid blocking the main actor, and submit only model values to the queue. No source may invoke presentation or animation directly.

## Experimental System Notifications onboarding

The disabled-by-default System Notifications setting is independent of DockCat's global enabled state. Enabling it performs only a non-prompting trust check. The macOS Accessibility prompt is requested exclusively by the permission button. A later observer may read visible notification text locally; it is not implemented and third-party notifications are not mirrored in this release. Native banners remain visible because suppression is not implemented.

The reusable health model reports `disabled`, `permissionRequired`, `starting`, `active`, `degraded`, or `unavailable`. `active` can only follow startup success reported by a real source. Until issue #68 supplies that source, a trusted configuration reports `unavailable` with an observer-not-implemented reason. Permission loss stops a running/starting source and returns to `permissionRequired`; typed compatibility and startup failures map to `degraded` and `unavailable` respectively.
