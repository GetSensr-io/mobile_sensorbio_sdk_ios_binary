# NoomApp BLE Real-Device Test Checklist

BLE is unavailable in iOS Simulator. Run this only on a physical iPhone with Bluetooth enabled and a Sensor Bio / Noom Band nearby.

## Build and install

1. Connect the iPhone over USB-C/Lightning and unlock it.
2. Trust this Mac on the phone if prompted.
3. In Xcode, open `NoomApp/NoomApp.xcworkspace`.
4. Select the `NoomApp` scheme.
5. Select the connected iPhone as the run destination.
6. Confirm signing uses an Apple Development team that can sign bundle id `ai.sensr.example.NoomApp`.
7. Press Run in Xcode, or from the repo root run:
   - Build for generic device: `docs/scripts/build-device.sh`
   - Build for a specific phone: `docs/scripts/build-device.sh --device <IPHONE_UDID>`
   - Let Xcode create/update signing assets when signed in: `docs/scripts/build-device.sh --device <IPHONE_UDID> --allow-provisioning-updates`
   - Build and install: `docs/scripts/build-device.sh --device <IPHONE_UDID> --install`

## App flow

1. Launch NoomApp on the phone.
2. Sign in with a staging/test account that is allowed to pair a band.
3. Navigate to the device/pairing flow.
4. Start scan for Noom Band.
5. Confirm the expected band appears in discovered devices.
6. Pair/connect to the band.
7. Verify connection-state truth:
   - Connected UI appears only after SDK `connected` state is true.
   - Disconnected UI appears when SDK `connected` state is false.
   - The UI does not show a stale connected state after BLE disconnect.
8. If the band has pending data, keep the app foregrounded and confirm sync starts automatically after connect.
9. Verify sync progress moves and eventually completes.
10. Verify dashboard data updates after sync completes.
11. Disconnect the band from the app.
12. Verify the UI changes to disconnected state.
13. Reconnect the same band.
14. Verify connected state returns and no duplicate paired-device row appears.
15. Unpair/remove the band.
16. Verify the app returns to the unpaired/scan state.
17. Sign out.
18. Relaunch the app and verify the signed-out state persists.

## Pass/fail notes to capture

- iPhone model and iOS version.
- App build configuration and commit/worktree state.
- Band serial/model/firmware if shown.
- Whether scan, pair, connect, sync, disconnect, reconnect, unpair, and sign-out each passed.
- Screenshots or logs for any stale connection state, pairing failure, or sync failure.
