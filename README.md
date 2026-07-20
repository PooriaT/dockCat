# DockCat

> The experimental System Notifications integration includes an independently opt-in, disabled-by-default best-effort operation to close an original banner *after* DockCat accepts its mirror. It does not prevent native banners: they may appear briefly or remain, and compatibility may change with macOS updates. Detection fails closed, executes no content actions, and bundle-identifier exclusions do not affect mirroring.

DockCat is a native macOS 14+ menu-bar app that places a small animated cat beside the Dock. Internal notifications wake the cat, send it toward the Dock centre with a card, and return it home when the queue becomes idle.

## Current capabilities

- SwiftUI menu bar, settings, notification card, and developer simulator
- Separate click-through cat and interactive card `NSPanel` overlays
- SpriteKit placeholder cat with callback-driven wake, carry, walk, wait, and settle animations
- FIFO actor-backed queue with duplicate protection, limits, persistence blocking, pause/resume, and sequential delivery
- Explicit running, delivery-paused, disabling, disabled, enabling, and shutdown lifecycle with atomic disable cleanup
- Stable automatic/main/specific display selection using public CoreGraphics identity, with safe disconnect fallback
- Public-API Dock edge inference for bottom, left, right, multiple displays, typed confidence, and auto-hide fallback
- Per-display, per-Dock-edge home/presentation calibration with isolated live preview markers
- Internal/test and validated `dockcat://notify` sources, plus state-neutral Settings recovery URLs
- Live app/system Reduced Motion, distinct no-walking and pause-visual modes, scalable anchored cat geometry, idle-breathing control, ServiceManagement login item support, structured logging, and XCTest coverage
- VoiceOver-ordered card semantics, privacy-safe announcements, explicit keyboard traversal, and live Increased Contrast, Reduce Transparency, and Differentiate Without Color adaptation

DockCat does not currently mirror other apps' notifications. Settings includes a disabled-by-default, experimental System Notifications permission-onboarding control for a future observer. Accessibility permission is requested only after the user presses the request button; no observer or Accessibility-tree parsing exists yet. DockCat continues to avoid private APIs, injection, OCR, screen scraping, and direct Notification Center database access.

## Build and run

Open `DockCat.xcodeproj`, select the DockCat scheme, choose your signing team if required, and Run. DockCat is an accessory app and has no normal Dock icon. Use its paw menu-bar item, Finder/open-app reopen, or one of the recovery paths below to reach Settings.

From Terminal:

```sh
swift build
swift test
```

## URL examples

```sh
open 'dockcat://notify?title=Build%20Complete&message=The%20project%20finished&source=Codex&type=transient&duration=5'
open 'dockcat://notify?title=Build%20Failed&message=Review%20the%20logs&source=Codex&type=persistent'
open 'dockcat://settings'
open 'dockcat://settings?restoreMenuBar=1'
open 'dockcat://restore-menu-bar'
```

Only explicit `https` action URLs are accepted. See [docs/url-scheme.md](docs/url-scheme.md).
See [docs/accessibility.md](docs/accessibility.md) for overlay semantics, announcement privacy,
keyboard behavior, and display-option adaptation.

## Menu-bar recovery

Hiding the paw does not disable DockCat, resume or pause delivery, alter animation settings, or change queued/active notifications. DockCat warns before hiding and first verifies that its registered URL, Settings parser, and Settings presenter are available.

Reopen Settings or restore the paw with:

```sh
open -a DockCat
open 'dockcat://settings'
open 'dockcat://settings?restoreMenuBar=1'
# When DockCat is quit:
open -a DockCat --args --show-settings
open -a DockCat --args --restore-menu-bar
```

As a narrow last resort, quit DockCat, delete only the menu-visibility preference, and relaunch. This preserves calibration, notification, source, launch-at-login, and animation preferences:

```sh
defaults delete com.example.DockCat DockCat.menuBarVisible
open -a DockCat
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for launch-at-login behavior, URL-registration troubleshooting, and the single-instance boundary.

## Structure

`Sources/DockCatCore` contains platform-independent queue, state-machine, URL, and geometry logic. `Sources/DockCat` contains AppKit overlays, SpriteKit rendering, SwiftUI UI, settings, and application coordination. `Tests` contains core tests; `docs` contains design and manual-testing notes.

## Runtime controls

Global Disable, Pause Delivery, and Pause Visual Animations are intentionally different. Disable hides every DockCat overlay, stops external observation, cancels the active session, clears current and pending queue work, and resets pause. Re-enable starts from an empty running state and shows the sleeping cat only after placement resolves. Pause Delivery preserves the visible session, queue, and remaining transient duration while continuing to accept bounded input. Pause Visual Animations changes only visual execution; delivery, source observation, queue promotion, and transient timing continue.

## Screenshot

Placeholder: run the Developer tab's presets to view the live SpriteKit cat and material notification card.

## Roadmap

- Replace vector placeholders with an artist-authored sprite atlas
- Add appearance themes
- Add opt-in integrations through the `NotificationSource` protocol
- Add a carefully sandboxed localhost source if demand justifies its security/maintenance cost
