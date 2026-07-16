# Privacy

DockCat's opt-in experimental observer reads only attributes exposed for visible Notification Center UI through public Accessibility APIs. Content is held in bounded in-memory snapshots, normalized at a second bounded parser boundary, and presented only after structural validation. DockCat checks trust without prompting and asks macOS to present permission UI only after the user presses the permission button.

DockCat does not read Notification Center databases, capture the screen, use OCR, inject code, or use private APIs. Visible text remains on the Mac and is never logged. Logs contain only process/registration results, typed error categories, snapshot counts, and truncation counts—never titles, bodies, values, account names, or tree dumps.

Hidden previews are never inferred. Only an actually visible placeholder is preserved, or the parser supplies the generic “Preview hidden” representation after confidently identifying redacted notification structure. Deduplication stores a SHA-256 fingerprint and non-content observation metadata—not source, title, or message text—and is bounded to 256 entries with a 15-second default retention.
