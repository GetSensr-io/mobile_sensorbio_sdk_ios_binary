#!/usr/bin/env bash
set -euo pipefail

# Build NoomApp for a physical iOS device.
#
# Default: build for a generic iOS device destination. This verifies the
# iphoneos build path, but the resulting .app is only installable if local
# signing assets are valid.
#
# Examples:
#   docs/scripts/build-device.sh
#   docs/scripts/build-device.sh --device 00008110-001234567890801E
#   docs/scripts/build-device.sh --device 00008110-001234567890801E --install
#
# Optional env:
#   CONFIGURATION=Debug|Release
#   DERIVED_DATA_PATH=/tmp/hermes-ios-dd-noomapp-device
#   DEVELOPMENT_TEAM=XXXXXXXXXX   # override if using a different Apple team

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/hermes-ios-dd-noomapp-device}"
DEVICE_ID="${DEVICE_ID:-}"
INSTALL_AFTER_BUILD=0
ALLOW_PROVISIONING_UPDATES=0

usage() {
  cat <<'USAGE'
Usage: docs/scripts/build-device.sh [--device <UDID>] [--install] [--allow-provisioning-updates]

Builds NoomApp for iphoneos using NoomApp.xcworkspace and scheme NoomApp.
If --device is omitted, builds for generic/platform=iOS.
If --install is supplied, --device is required and the built .app is installed
with xcrun devicectl.
Pass --allow-provisioning-updates when Xcode is signed in to Apple Developer
and you want xcodebuild to create/update local provisioning profiles.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || { echo "error: --device requires a UDID" >&2; exit 2; }
      DEVICE_ID="$2"
      shift 2
      ;;
    --install)
      INSTALL_AFTER_BUILD=1
      shift
      ;;
    --allow-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$INSTALL_AFTER_BUILD" -eq 1 && -z "$DEVICE_ID" ]]; then
  echo "error: --install requires --device <UDID>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/NoomApp"
WORKSPACE="$APP_DIR/NoomApp.xcworkspace"

if [[ ! -d "$WORKSPACE" ]]; then
  echo "error: missing workspace: $WORKSPACE" >&2
  echo "Run from repo root: (cd NoomApp && pod install)" >&2
  exit 1
fi

cd "$APP_DIR"

DESTINATION="generic/platform=iOS"
if [[ -n "$DEVICE_ID" ]]; then
  DESTINATION="platform=iOS,id=$DEVICE_ID"
fi

BUILD_SETTINGS=(
  -workspace "NoomApp.xcworkspace"
  -scheme "NoomApp"
  -destination "$DESTINATION"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  BUILD_SETTINGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
fi

if [[ "$ALLOW_PROVISIONING_UPDATES" -eq 1 ]]; then
  BUILD_SETTINGS+=(-allowProvisioningUpdates)
fi

echo "Building NoomApp for destination: $DESTINATION"
echo "DerivedData: $DERIVED_DATA_PATH"
set -x
xcodebuild "${BUILD_SETTINGS[@]}" build
set +x

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphoneos/NoomApp.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build finished but app was not found at $APP_PATH" >&2
  exit 1
fi

echo "Built app: $APP_PATH"

if [[ "$INSTALL_AFTER_BUILD" -eq 1 ]]; then
  echo "Installing $APP_PATH to device $DEVICE_ID"
  set -x
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
  set +x
fi
