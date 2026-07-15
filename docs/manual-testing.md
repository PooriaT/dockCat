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

## Issue #64 locomotion scenarios

Manual verification should cover these animation-selection cases on macOS:

- Bottom Dock with the sleeping anchor on the left: send a notification and confirm the cat turns right, picks up the mini-card, and walks right for the full panel movement.
- Bottom Dock with the sleeping anchor on the right: send a notification and confirm the cat turns left and returns right/left according to the actual path.
- Left Dock: move between anchors above and below the presentation point and confirm upward travel rotates the placeholder cat upward while downward travel rotates it downward.
- Right Dock: repeat the upward and downward checks and confirm direction is derived from motion rather than the Dock side name.
- Persistent notification: leave the card open and confirm the cat stops in a stable wait pose while holding the mini-card.
- Transient notification: allow timeout and confirm the cat turns toward home and walks in the resolved return-home direction.
- Pause or cancel during movement: confirm the walk loop stops and the cat remains in a stable non-walking carry pose.
- Reduced Motion: enable Reduce Motion and confirm the static carry pose replaces the repeated walk loop while the card remains attached.
- Multiple queued notifications with “remain for queued messages”: confirm the cat stays at presentation and does not restart the walk loop between queued cards.
