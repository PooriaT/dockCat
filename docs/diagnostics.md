# Diagnostic summaries

DockCat can copy or save a user-controlled diagnostic summary from Settings > Developer. The summary is pretty-printed JSON and is never uploaded automatically.

Included data is bounded and typed: app version/build, bundle ID, macOS version, architecture, build configuration, runtime mode, cat state, queue counts, source health enums, presentation phase, safe display geometry, a short display diagnostics token, accessibility display booleans, Accessibility trust, and a ring buffer of typed events.

Omitted data includes notification title, body, message, UUIDs, source display text, action URLs, posting bundle IDs, Accessibility roles, labels, values, PIDs, trees, OSLog archives, analytics identifiers, localized display names, raw display UUIDs, and hardware identifiers.

The event history is in memory only, evicts oldest entries first, clears on process restart, and can be cleared manually with Clear Diagnostic History.
