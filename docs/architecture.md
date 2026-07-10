# Architecture

`AppState` is the main-actor coordinator. Sources submit immutable `DockCatNotification` values to the `NotificationQueue` actor. The pure `CatStateMachine` accepts semantic events, while `CatWindowController` executes one SpriteKit animation and reports its completion. The card has its own interactive AppKit panel; the cat panel is small and click-through.

Dock placement is derived only from `NSScreen.frame` and `visibleFrame`. `ScreenChangeMonitor` triggers recalculation after screen and Space changes. Settings use `UserDefaults`; login registration uses `SMAppService`.
