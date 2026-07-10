# NoomApp Physical iPhone Build and Install Path

## Current signing configuration

- Workspace: `NoomApp/NoomApp.xcworkspace`
- Scheme: `NoomApp`
- Bundle id: `ai.sensr.example.NoomApp`
- Signing style: Automatic
- Configured development team: `2V6RCD4SM4`
- Deployment target: iOS 18.0

The project is configured for automatic signing, but this machine still needs local Apple signing assets before a physical-device build can be installed:

1. An Apple Development signing certificate/private key in the login keychain for team `2V6RCD4SM4` or an alternate team Sameer wants to use.
2. An iOS Development provisioning profile for `ai.sensr.example.NoomApp` that includes the connected iPhone UDID.
3. A connected, trusted, unlocked iPhone.

If using a different Apple Developer team, set the team in Xcode for the NoomApp target or run the build script with `DEVELOPMENT_TEAM=<TEAM_ID>`.

## Build commands

From repo root:

```bash
# Generic iphoneos build. Requires signing assets for an installable app.
docs/scripts/build-device.sh

# Build for a connected iPhone by UDID.
docs/scripts/build-device.sh --device <IPHONE_UDID>

# Let xcodebuild create/update signing assets when Xcode is signed in.
docs/scripts/build-device.sh --device <IPHONE_UDID> --allow-provisioning-updates

# Build and install to that iPhone using Xcode's device tooling.
docs/scripts/build-device.sh --device <IPHONE_UDID> --install
```

Equivalent raw build command:

```bash
cd NoomApp
xcodebuild \
  -workspace NoomApp.xcworkspace \
  -scheme NoomApp \
  -destination "generic/platform=iOS" \
  -configuration Debug \
  -derivedDataPath /tmp/hermes-ios-dd-noomapp-device \
  build
```

For a specific phone, replace the destination with:

```bash
-destination "platform=iOS,id=<IPHONE_UDID>"
```

## Install options

Preferred:

1. Open `NoomApp/NoomApp.xcworkspace` in Xcode.
2. Select the connected iPhone destination.
3. Confirm automatic signing resolves the team/profile.
4. Press Run.

CLI:

```bash
docs/scripts/build-device.sh --device <IPHONE_UDID> --install
```

Manual install after a successful build:

```bash
xcrun devicectl device install app \
  --device <IPHONE_UDID> \
  /tmp/hermes-ios-dd-noomapp-device/Build/Products/Debug-iphoneos/NoomApp.app
```

`ios-deploy` is not required. If installed, it can also install the built app:

```bash
ios-deploy --id <IPHONE_UDID> --bundle /tmp/hermes-ios-dd-noomapp-device/Build/Products/Debug-iphoneos/NoomApp.app
```

## Verification on this machine

Observed on Anton's build host:

- `security find-identity -v -p codesigning` returned `0 valid identities found`.
- No local provisioning profile directory exists at `~/Library/MobileDevice/Provisioning Profiles`.
- `xcrun devicectl list devices` returned no connected devices.
- `docs/scripts/build-device.sh --allow-provisioning-updates` failed with `No Accounts: Add a new account in Accounts settings` and `No profiles for 'ai.sensr.example.NoomApp' were found`.
- A compile-only iphoneos build with `CODE_SIGNING_ALLOWED=NO` succeeded at `/tmp/hermes-ios-dd-noomapp-device-nosign/Build/Products/Debug-iphoneos/NoomApp.app`; that artifact is not signed and has no embedded provisioning profile, so it is not installable on a phone.

## BLE requirements verified in source and compile-only artifact

`NoomApp/NoomApp/Info.plist` and the compile-only built app contain:

- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
- `UIBackgroundModes` with `bluetooth-central`

The provisioning profile must preserve any app entitlements Xcode injects for the signed build. BLE background mode itself is in the built app's `Info.plist`, not an app entitlement. After a signed device build, verify with:

```bash
APP=/tmp/hermes-ios-dd-noomapp-device/Build/Products/Debug-iphoneos/NoomApp.app
plutil -p "$APP/Info.plist" | egrep 'NSBluetooth|UIBackgroundModes|bluetooth-central'
codesign -d --entitlements :- "$APP"
security cms -D -i "$APP/embedded.mobileprovision" | plutil -p - | egrep 'application-identifier|com.apple.developer.team-identifier|Entitlements'
```
