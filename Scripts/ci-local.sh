#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${1:-$ROOT_DIR}"
LOG_DIR="$OUTPUT_ROOT/.ci-logs"
RESULTS_DIR="$OUTPUT_ROOT/.ci-results"
DERIVED_DATA_PATH="$OUTPUT_ROOT/.local-derived-data"

mkdir -p "$LOG_DIR" "$RESULTS_DIR"
cd "$ROOT_DIR"

echo "Swift version:"
swift --version
echo "Xcode version:"
xcodebuild -version

echo "Validating Xcode project and shared DockCat scheme..."
xcodebuild -list -project DockCat.xcodeproj | tee "$LOG_DIR/xcodebuild-list.log"
xcodebuild -list -project DockCat.xcodeproj | grep -E '^[[:space:]]+DockCat$' >/dev/null

echo "Running Swift package tests..."
swift test --parallel 2>&1 | tee "$LOG_DIR/swift-test.log"

echo "Building DockCat app with code signing disabled..."
xcodebuild \
  -project DockCat.xcodeproj \
  -scheme DockCat \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -resultBundlePath "$RESULTS_DIR/DockCatBuild.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  build 2>&1 | tee "$LOG_DIR/xcodebuild.log"
