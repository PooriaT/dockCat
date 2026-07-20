# Recovery and troubleshooting

DockCat is an `LSUIElement` accessory app, so it has no ordinary Dock icon. Hiding the paw changes only `DockCat.menuBarVisible`; it does not change runtime enablement, delivery pause, visual-animation mode, notification state, calibration, source preferences, or launch-at-login registration.

## Reopen Settings

When the app is running, use Finder to open DockCat again or run:

```sh
open -a DockCat
open 'dockcat://settings'
```

The app-reopen callback and URL router both use the same Settings presenter. The menu remains hidden unless restoration is explicit.

When DockCat is quit, recovery-only launch arguments are also available:

```sh
open -a DockCat --args --show-settings
open -a DockCat --args --restore-menu-bar
```

Unknown arguments are rejected and cannot reset preferences.

## Restore the paw

```sh
open 'dockcat://settings?restoreMenuBar=1'
# Equivalent dedicated URL:
open 'dockcat://restore-menu-bar'
```

If URL registration is unavailable, quit DockCat and narrowly delete only its menu visibility key before relaunching:

```sh
defaults delete io.github.pooriat.DockCat DockCat.menuBarVisible
open -a DockCat
```

Do not delete the entire `io.github.pooriat.DockCat` defaults domain as a first recovery step. Doing so would also remove DockCat preferences such as enablement, notification behavior, animation, source options, and display calibration. The recovery URLs never perform a preference reset.

If `open 'dockcat://settings'` reports that no application handles the URL, confirm DockCat is installed as an application bundle and has been launched once from its installed location. The hide control verifies the bundle's `CFBundleURLTypes` before allowing the menu item to be removed; it does not rewrite registration at runtime.

## Launch at login and single-instance behavior

With launch at login enabled, DockCat can start quietly with the paw still hidden. It does not automatically show Settings at every login. Finder reopen or a recovery URL later opens Settings in that running process. With launch at login disabled, a recovery URL or recovery launch argument cold-launches DockCat and then opens Settings.

DockCat delegates process reuse for Finder and `open -a` launches to standard LaunchServices behavior and does not opt into multiple instances or use a lock file. Independently of that platform behavior, both `AppDelegate` and `AppState` have one-shot bootstrap guards; a repeated startup signal cannot install a second set of overlays, display/source monitors, lifecycle tasks, or presentation coordinators. Settings presentation also reuses an existing Settings window where AppKit exposes it.

## Release, permissions, and diagnostics

If Accessibility permission is missing or revoked, the System Notifications source stops and reports permission-required or permission-revoked health. Re-enable it from Settings only when you want to test that source. macOS updates may degrade the experimental Accessibility observer; copy diagnostics before changing settings if you need support.

Restore only the menu item with:

```bash
defaults delete io.github.pooriat.DockCat DockCat.menuBarVisible
```

Do not delete the whole defaults domain first. For login-at-launch issues, verify the local ServiceManagement login item in System Settings. Unsigned builds are for local verification and may be rejected by Gatekeeper when distributed. Developer ID builds must be archived, exported, notarized, stapled, and validated as described in `docs/signing-and-release.md`; notarization failures are usually credential, certificate, hardened-runtime, packaging, or Apple service issues.

Use Settings > Developer to copy or save diagnostics. The JSON intentionally omits notification text, source names, action URLs, Accessibility text/trees, OSLog archives, raw display identifiers, and analytics. Use Clear Diagnostic History to remove the in-memory event ring.
