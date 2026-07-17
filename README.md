# DockCat

> The experimental System Notifications integration includes an independently opt-in, disabled-by-default best-effort operation to close an original banner *after* DockCat accepts its mirror. It does not prevent native banners: they may appear briefly or remain, and compatibility may change with macOS updates. Detection fails closed, executes no content actions, and bundle-identifier exclusions do not affect mirroring.

DockCat is a native macOS 14+ menu-bar app that places a small animated cat beside the Dock. Internal notifications wake the cat, send it toward the Dock centre with a card, and return it home when the queue becomes idle.

## Current capabilities

- SwiftUI menu bar, settings, notification card, and developer simulator
- Separate click-through cat and interactive card `NSPanel` overlays
- SpriteKit placeholder cat with callback-driven wake, carry, walk, wait, and settle animations
- FIFO actor-backed queue with duplicate protection, limits, persistence blocking, pause/resume, and sequential delivery
- Public-API Dock edge inference for bottom, left, right, multiple displays, and auto-hide fallback
- Internal/test and validated `dockcat://notify` sources
- Reduced-motion behavior, ServiceManagement login item support, structured logging, and XCTest coverage

DockCat does not currently mirror other apps' notifications. Settings includes a disabled-by-default, experimental System Notifications permission-onboarding control for a future observer. Accessibility permission is requested only after the user presses the request button; no observer or Accessibility-tree parsing exists yet. DockCat continues to avoid private APIs, injection, OCR, screen scraping, and direct Notification Center database access.

## Build and run

Open `DockCat.xcodeproj`, select the DockCat scheme, choose your signing team if required, and Run. The app has no normal Dock icon; use its paw menu-bar item.

From Terminal:

```sh
swift build
swift test
```

## URL examples

```sh
open 'dockcat://notify?title=Build%20Complete&message=The%20project%20finished&source=Codex&type=transient&duration=5'
open 'dockcat://notify?title=Build%20Failed&message=Review%20the%20logs&source=Codex&type=persistent'
```

Only explicit `https` action URLs are accepted. See [docs/url-scheme.md](docs/url-scheme.md).

## Structure

`Sources/DockCatCore` contains platform-independent queue, state-machine, URL, and geometry logic. `Sources/DockCat` contains AppKit overlays, SpriteKit rendering, SwiftUI UI, settings, and application coordination. `Tests` contains core tests; `docs` contains design and manual-testing notes.

## Screenshot

Placeholder: run the Developer tab's presets to view the live SpriteKit cat and material notification card.

## Roadmap

- Replace vector placeholders with an artist-authored sprite atlas
- Add user-selectable specific displays and appearance themes
- Add opt-in integrations through the `NotificationSource` protocol
- Add a carefully sandboxed localhost source if demand justifies its security/maintenance cost
