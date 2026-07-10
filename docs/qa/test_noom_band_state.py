#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DASHBOARD = (ROOT / "NoomApp/NoomApp/DashboardView.swift").read_text()
MAIN_TAB = (ROOT / "NoomApp/NoomApp/MainTabView.swift").read_text()
STATE = (ROOT / "NoomApp/NoomApp/NoomBandConnectionState.swift").read_text()
PAIR = (ROOT / "NoomApp/NoomApp/PairDeviceState.swift").read_text()
PAIR_VIEW = (ROOT / "NoomApp/NoomApp/PairDeviceView.swift").read_text()
QA = (ROOT / "NoomApp/NoomApp/ContentView.swift").read_text()
PROFILE = (ROOT / "NoomApp/NoomApp/ProfileView.swift").read_text()
PRODUCT = (ROOT / "NoomApp/NoomApp/NoomProductScreens.swift").read_text()


class NoomBandStateTests(unittest.TestCase):
    def test_all_five_states_are_defined_and_debug_routable(self):
        for state in ("neverPaired", "connecting", "connected", "pairedDisconnected", "error"):
            self.assertIn(f"case {state}", STATE)
        for route in ("band_never_paired", "band_connecting", "band_connected", "band_disconnected", "band_error"):
            self.assertIn(f'case "{route}"', QA)

    def test_ready_requires_current_live_connection(self):
        self.assertIn("if connected { return .connected }", STATE)
        self.assertIn("return paired ? .pairedDisconnected : .neverPaired", STATE)
        self.assertIn("var isLiveReady: Bool { self == .connected }", STATE)
        self.assertNotIn('"Noom Band ready"', DASHBOARD)
        self.assertIn("sensorBio.$connected", DASHBOARD)

    def test_profile_is_real_navigation_destination_with_accessible_hit_target(self):
        self.assertIn("NavigationLink {", DASHBOARD)
        self.assertIn("ProfileView(session: session)", DASHBOARD)
        self.assertIn('.frame(width: 44, height: 44)', DASHBOARD)
        self.assertIn('.contentShape(Circle())', DASHBOARD)
        self.assertIn('.accessibilityLabel("Profile")', DASHBOARD)

    def test_band_status_is_compact_and_adjacent_to_the_profile_control(self):
        self.assertNotIn(".safeAreaInset(edge: .top", MAIN_TAB)
        self.assertIn("struct BandBatteryBadge", MAIN_TAB)
        self.assertIn("BandBatteryBadge()", DASHBOARD)
        badge = DASHBOARD.index("BandBatteryBadge()")
        profile = DASHBOARD.index("NavigationLink {", badge)
        self.assertLess(badge, profile)
        self.assertIn("Text(battery.map { \"\\($0)%\" }", MAIN_TAB)

    def test_sign_out_uses_sdk_only_after_success_and_no_manual_device_wipe(self):
        sdk_call = PROFILE.index("try await sensorBio.signOut()")
        session_clear = PROFILE.index("sensorBio.session = nil")
        self.assertLess(sdk_call, session_clear)
        self.assertIn("@Environment(\\.dismiss) private var dismiss", PROFILE)
        self.assertIn("dismiss()", PROFILE)
        self.assertNotIn("sensorBio.session = nil\n        do {", PROFILE)
        self.assertNotIn("persistDeviceState", PROFILE)
        self.assertNotIn("removeDeviceFromPairedDevices", PROFILE[PROFILE.index("private func signOut"):])
        self.assertIn(".onReceive(sensorBio.$session)", QA)

    def test_pairing_contract_uses_v012_public_persistence(self):
        for snippet in (
            "sensorBio.startScan()",
            "sensorBio.deviceDiscovered",
            "sensorBio.connect(device.id, pairing: true)",
            "sensorBio.pairingConnection",
            "sensorBio.setAskForDeviceResponse(true)",
            "sensorBio.persistPairedDevice(macAddress: device.id, name: device.name, type: device.deviceType)",
            "sensorBio.disconnect()",
        ):
            self.assertIn(snippet, PAIR)
        self.assertNotIn("persistDeviceState", PAIR)

    def test_discovered_bands_are_identified_by_mac_id(self):
        self.assertIn('Text("MAC ID · \\(device.id)")', PAIR_VIEW)
        self.assertNotIn('Text("Noom Band")\n                                    .font(.system(size: 15', PAIR_VIEW)

    def test_unpair_uses_v012_unpair_clear_api(self):
        self.assertIn("sensorBio.removeDeviceFromPairedDevices(device.macAddress)", PROFILE)
        self.assertIn("sensorBio.clearPairedDevice()", PROFILE)
        self.assertNotIn("persistDeviceState", PROFILE)

    def test_reconnect_path_does_not_start_pairing_flow_for_paired_disconnected_device(self):
        self.assertIn("private func reconnectPairedDevice()", PRODUCT)
        self.assertIn("sensorBio.connect(device.macAddress, pairing: false)", PRODUCT)
        start = PRODUCT.index("private func reconnectPairedDevice()")
        end = PRODUCT.index("\n}\n\nstruct NoomSleepRecoveryView", start)
        reconnect_body = PRODUCT[start:end]
        self.assertNotIn("presentingPair = true\n        isReconnecting = true", reconnect_body)


if __name__ == "__main__":
    unittest.main()
