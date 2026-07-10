# Manual testing

1. Run the app and verify there is a paw in the menu bar and no Dock icon.
2. Send transient and persistent tests; confirm timeout versus explicit close behavior.
3. Open Settings → Developer and try short, long, persistent, and Queue 3 presets.
4. While a card is active, enqueue more items and verify FIFO presentation without walking home between cards.
5. Pause during idle and presentation, enqueue items, resume, and verify queue integrity.
6. Move the Dock to each edge, resize it, toggle auto-hide, change Spaces, and attach/detach a display.
7. Enable macOS Reduce Motion and DockCat's reduced-motion/disable-walking options.
8. Test valid and invalid URL examples, including long text, unsafe actions, and out-of-range duration.
9. Enable launch at login, restart the login session, and verify the actual registration status.
