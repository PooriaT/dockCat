# Notification sources

All future inputs conform to `NotificationSource`, exposing an identifier plus asynchronous `start(handler:)` and `stop()` methods. The MVP supports developer/UI submissions, menu commands, direct internal service submission, and the custom URL scheme. Arbitrary third-party macOS notifications are explicitly out of scope.

A future source must validate at its trust boundary, avoid blocking the main actor, and submit only model values to the queue. No source may invoke presentation or animation directly.
