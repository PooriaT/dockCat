# URL commands

DockCat accepts only these command hosts:

- `dockcat://notify` submits one validated notification.
- `dockcat://settings` opens the existing SwiftUI Settings scene without restoring a hidden menu item.
- `dockcat://settings?restoreMenuBar=1` restores the menu item, then opens Settings.
- `dockcat://restore-menu-bar` restores the menu item, then opens Settings.

Hosts and query-key names are case-insensitive. Boolean recovery values accept `1`, `0`, `true`, or `false`. Unknown hosts, unknown or duplicate query keys, malformed Boolean values, paths, credentials, ports, and fragments are rejected. Recovery commands cannot produce a notification or reset preferences.

## Notification command

Parameters: `title` (required, 120 characters), `message` (1,000), `source` (80), `type` (`transient` or `persistent`), `duration` (1–60 seconds), and `action` (optional HTTPS URL, 2,048 characters). Missing type uses transient; missing duration uses the configured default. Invalid input is rejected and never executes commands.

Action URLs require an explicit `https` scheme and host. Diagnostics report only typed rejection categories; query values, notification titles, and notification bodies are not logged.

## Recovery semantics

Opening Settings and restoring the menu are idempotent. They do not enable DockCat, resume paused delivery, change visual-animation mode, modify the queue/current notification/timer, or initialize a second `AppState` or overlay coordinator. URL commands received during cold launch are held in callback order until the guarded application bootstrap is ready.
