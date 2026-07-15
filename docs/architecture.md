# Architecture

`AppState` is the main-actor coordinator. Sources submit immutable `DockCatNotification` values to the `NotificationQueue` actor. The pure `CatStateMachine` accepts semantic events, while `CatWindowController` executes cat overlay animations and reports completion. The card has its own interactive AppKit panel; the cat panel is small and click-through.

Dock placement is derived only from `NSScreen.frame` and `visibleFrame`. `DockLocator` returns sleeping and presentation anchors plus the inferred `DockEdge`; `ScreenChangeMonitor` triggers recalculation after screen and Space changes. Settings use `UserDefaults`; login registration uses `SMAppService`.

## Cat overlay motion

Window travel is split into pure planning and AppKit mutation:

- `DockCatCore` owns `CatMotionPlanner`, which constrains destinations to the Dock axis, computes distance, clamps animation speed, and derives a distance-aware duration with named minimum and maximum bounds.
- Bottom Docks move only on the x-axis. Left and right Docks move only on the y-axis. The current perpendicular panel coordinate is preserved so travel does not drift diagonally.
- `CatWindowController` centralizes conversion from the visual cat anchor to the `NSPanel` frame origin before handing movement to `CatMotionDriver`.
- `CatMotionDriver` is main-actor isolated and is the only layer that continuously mutates the panel origin during travel. It uses monotonic elapsed time and finishes completed travel at the exact planned destination.
- Starting a replacement movement invalidates the previous session. Cancelled or stale sessions stop updating and report `cancelled` instead of snapping to an obsolete destination.
- Effective Reduced Motion uses a short fade-assisted relocation rather than a long traversal, while preserving normal completion ordering unless the task is cancelled.
