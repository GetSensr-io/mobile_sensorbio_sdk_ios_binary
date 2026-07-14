#!/usr/bin/env bash
set -euo pipefail

: "${SIMULATOR_UDID:?Set SIMULATOR_UDID to the target iOS Simulator UDID}"
: "${APP_PATH:?Set APP_PATH to the built Debug NoomApp.app path}"

if [[ ! -d "$APP_PATH" ]]; then
  printf 'App bundle not found: %s\n' "$APP_PATH" >&2
  exit 2
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
OUTPUT_DIR="${OUTPUT_DIR:-/private/tmp/noom-sleep-processing-captures}"
mkdir -p "$OUTPUT_DIR"

routes=(
  sleep_processing_detected
  sleep_processing_stored
  sleep_processing_uploaded
  sleep_processing_analyzing
  sleep_processing_ready
  sleep_processing_short
  sleep_processing_error
  sleep_processing_calibrating
  sleep_processing_stale
  sleep_processing_pending_with_history
  sleep_processing_multiple_sessions
)

xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

for route in "${routes[@]}"; do
  xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  SIMCTL_CHILD_NOOM_QA_ROUTE="$route" \
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null
  sleep 1
  xcrun simctl io "$SIMULATOR_UDID" screenshot "$OUTPUT_DIR/$route.png" >/dev/null
  printf '%s\n' "$OUTPUT_DIR/$route.png"
done
