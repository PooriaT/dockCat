#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail(){ echo "error: $*" >&2; exit 1; }
if plutil -lint DockCat/Info.plist >/dev/null 2>&1; then :; else python3 - <<'PY' || fail "Info.plist is invalid"
import plistlib
plistlib.load(open('DockCat/Info.plist','rb'))
PY
fi
if command -v xcodebuild >/dev/null 2>&1; then
  settings(){ xcodebuild -project DockCat.xcodeproj -scheme DockCat -configuration "$1" -showBuildSettings 2>/dev/null; }
  check_config(){
    local cfg="$1" out; out="$(settings "$cfg")"
    grep -q "PRODUCT_BUNDLE_IDENTIFIER = io.github.pooriat.DockCat" <<<"$out" || fail "$cfg bundle identifier is not canonical"
    grep -q "PRODUCT_NAME = DockCat" <<<"$out" || fail "$cfg product name is not DockCat"
    grep -q "MARKETING_VERSION = 0.1.0" <<<"$out" || fail "$cfg marketing version missing"
    grep -q "CURRENT_PROJECT_VERSION = 1" <<<"$out" || fail "$cfg build version missing"
    grep -q "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon" <<<"$out" || fail "$cfg AppIcon is not configured"
    ! grep -Eq "DEVELOPMENT_TEAM = [A-Z0-9]+" <<<"$out" || fail "$cfg commits a development team"
  }
  check_config Debug; check_config Release
  settings Release | grep -q "ENABLE_HARDENED_RUNTIME = YES" || fail "Release hardened runtime is not enabled"
else
  pbx="$(cat DockCat.xcodeproj/project.pbxproj)"
  [[ "$(grep -o 'PRODUCT_BUNDLE_IDENTIFIER = io.github.pooriat.DockCat' DockCat.xcodeproj/project.pbxproj | wc -l | tr -d ' ')" == "2" ]] || fail "Debug/Release bundle identifiers are not canonical"
  [[ "$(grep -o 'PRODUCT_NAME = DockCat' DockCat.xcodeproj/project.pbxproj | wc -l | tr -d ' ')" == "2" ]] || fail "Debug/Release product names are not DockCat"
  grep -q 'MARKETING_VERSION = 0.1.0' DockCat.xcodeproj/project.pbxproj || fail "marketing version missing"
  grep -q 'CURRENT_PROJECT_VERSION = 1' DockCat.xcodeproj/project.pbxproj || fail "build version missing"
  grep -q 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon' DockCat.xcodeproj/project.pbxproj || fail "AppIcon not configured"
  grep -q 'ENABLE_HARDENED_RUNTIME = YES' DockCat.xcodeproj/project.pbxproj || fail "Release hardened runtime is not enabled"
fi
! rg -n "com\.example\.DockCat" DockCat DockCat.xcodeproj Sources README.md docs Scripts .github >/tmp/dockcat-placeholder.$$ || { cat /tmp/dockcat-placeholder.$$; rm -f /tmp/dockcat-placeholder.$$; fail "production placeholder remains"; }
rm -f /tmp/dockcat-placeholder.$$
! rg -n "DEVELOPMENT_TEAM = [A-Z0-9]+|notarytool.*--password|BEGIN PRIVATE KEY" DockCat.xcodeproj Config docs .github 2>/dev/null || fail "possible signing credential committed"
python3 - <<'PY' || fail "dockcat URL scheme is not registered"
import plistlib
p=plistlib.load(open('DockCat/Info.plist','rb'))
assert p['CFBundleURLTypes'][0]['CFBundleURLSchemes'][0] == 'dockcat'
PY
[[ -f Sources/DockCat/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json ]] || fail "AppIcon Contents.json is missing"
echo "DockCat project metadata is valid."
