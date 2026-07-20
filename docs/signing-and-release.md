# Signing and release notes

DockCat's canonical bundle identifier is `io.github.pooriat.DockCat`. Xcode build settings are the source of truth for product name (`DockCat`), marketing version (`0.1.0`), and build number (`1`). `DEVELOPMENT_TEAM` is intentionally empty in source control.

## Entitlement policy

DockCat is a non-sandboxed Developer ID application. No custom entitlement file is currently required and `CODE_SIGN_ENTITLEMENTS` remains unset.

| Capability | Decision |
|---|---|
| App Sandbox | Not enabled; compatibility needs a separate design decision. |
| Accessibility observation | Uses public Accessibility APIs after explicit user consent through TCC; no sandbox entitlement is invented. |
| Login item | Uses ServiceManagement and local user choice. |
| Network | No entitlement for current behavior. |
| Apple Events | Not used. |
| Keychain groups | Not used. |
| Camera, microphone, location, contacts, photos | Not used. |
| Hardened Runtime | Enabled for Release builds. |

Do not add `get-task-allow`, JIT, unsigned-memory, disabled-library-validation, automation, or temporary exception entitlements without a compatibility issue and review.

## Unsigned verification

Run the CI-equivalent signing-disabled build locally:

```bash
xcodebuild \
  -project DockCat.xcodeproj \
  -scheme DockCat \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .local-derived-data \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build
```

## Local development signing

Open Xcode, select the DockCat target, choose your personal team locally, and run. Do not commit a Team ID, certificate name, provisioning profile, password, notary credential, or keychain path. Grant Accessibility permission only when testing the opt-in System Notifications source.

## Release archive

```bash
xcodebuild \
  -project DockCat.xcodeproj \
  -scheme DockCat \
  -configuration Release \
  -archivePath "$PWD/build/DockCat.xcarchive" \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  CODE_SIGN_STYLE=Automatic \
  archive
```

## Developer ID export

Copy `Config/ExportOptions.DeveloperID.example.plist` outside the repo or pass a local override with your real Team ID, then export:

```bash
xcodebuild -exportArchive \
  -archivePath "$PWD/build/DockCat.xcarchive" \
  -exportPath "$PWD/build/DeveloperID" \
  -exportOptionsPlist Config/ExportOptions.DeveloperID.example.plist
```

## Notarization

Store Apple notary credentials in a local keychain profile without putting secrets in shell history:

```bash
xcrun notarytool store-credentials DOCKCAT_NOTARY_PROFILE
```

Package, submit, staple, and validate:

```bash
ditto -c -k --keepParent build/DeveloperID/DockCat.app build/DockCat.zip
xcrun notarytool submit build/DockCat.zip --keychain-profile DOCKCAT_NOTARY_PROFILE --wait
xcrun stapler staple build/DeveloperID/DockCat.app
spctl --assess --type execute --verbose build/DeveloperID/DockCat.app
```

This repository does not automate notarization, import certificates in CI, create a GitHub Release, or publish binaries.
