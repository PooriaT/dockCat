# Privacy

DockCat's opt-in experimental observer reads only attributes exposed for visible Notification Center UI through public Accessibility APIs. Content is held in bounded in-memory snapshots, normalized at a second bounded parser boundary, and presented only after structural validation. DockCat checks trust without prompting and asks macOS to present permission UI only after the user presses the permission button.

DockCat does not read Notification Center databases, capture the screen, use OCR, inject code, or use private APIs. Visible text remains on the Mac and is never logged. Logs contain only process/registration results, typed error categories, snapshot counts, and truncation counts—never titles, bodies, values, account names, or tree dumps.

Hidden previews are never inferred. Only an actually visible placeholder is preserved, or the parser supplies the generic “Preview hidden” representation after confidently identifying redacted notification structure. Deduplication stores a SHA-256 fingerprint and non-content observation metadata—not source, title, or message text—and is bounded to 256 entries with a 15-second default retention.

When a callback snapshot contains sibling banners, DockCat reads fields only from the structurally matched banner subtree and rejects ambiguous snapshots. The Notification Center host bundle is not attributed to the posting app; posting bundle metadata is used only when exposed inside that matched AX subtree. Destroyed observations never create cards.
# Lifecycle metadata

External lifecycle identity contains only a source namespace and opaque stable item identifier. DockCat does not retain raw Accessibility references or AX trees in notifications, and lifecycle diagnostics must not include notification title or body content.
