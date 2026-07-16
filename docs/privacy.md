# Privacy

DockCat's opt-in experimental observer reads only attributes exposed for visible Notification Center UI through public Accessibility APIs. Content is held in bounded, in-memory candidate snapshots and is not presented before issue #69 adds parsing. DockCat checks trust without prompting and asks macOS to present permission UI only after the user presses the permission button.

DockCat does not read Notification Center databases, capture the screen, use OCR, inject code, or use private APIs. Visible text remains on the Mac and is never logged. Logs contain only process/registration results, typed error categories, snapshot counts, and truncation counts—never titles, bodies, values, account names, or tree dumps.
