# Privacy

DockCat currently processes only events submitted directly through its own UI, internal API, or custom URL. An experimental System Notifications setting is opt-in and disabled by default. It provides onboarding for a future Accessibility-based observer that may read notification text that is visible on screen; the observer itself is not implemented yet. DockCat checks trust without prompting and asks macOS to present permission UI only after the user presses the permission button.

DockCat does not read Notification Center databases, capture the screen, use OCR, inject code, or use private APIs. Any future visible notification content will remain on the Mac and will not be transmitted. Source-health logging is limited to enablement, trust, lifecycle, and typed error-state changes; it never includes notification titles, body text, Accessibility values, account names, or Accessibility trees.
