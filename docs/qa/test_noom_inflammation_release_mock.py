import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
SIGNAL = (SRC / "InflammationSignal.swift").read_text()
STATE = (SRC / "DashboardState.swift").read_text()
DASHBOARD = (SRC / "DashboardView.swift").read_text()
CONTENT = (SRC / "ContentView.swift").read_text()


class InflammationReleaseMockContractTests(unittest.TestCase):
    def test_local_sample_provider_supplies_release_dashboard_snapshot(self) -> None:
        provider_index = SIGNAL.index("struct MockInflammationSignalProvider")
        prefix = SIGNAL[:provider_index]
        self.assertGreaterEqual(
            prefix.rfind("#endif"),
            prefix.rfind("#if DEBUG"),
            "Mock provider is still compiled out of TestFlight release builds",
        )
        self.assertIn(
            "private let inflammationSignalProvider = MockInflammationSignalProvider()",
            STATE,
        )
        self.assertIn(
            "inflammationSignal: inflammationSignalProvider.signal(for: date)",
            STATE,
        )

    def test_sample_is_quiet_on_dashboard_but_disclosed_on_tile_and_detail(self) -> None:
        self.assertNotIn('title: "Sample inflammation input"', DASHBOARD)
        self.assertNotIn("Synthetic POC data — not personal health data", DASHBOARD)
        self.assertIn('"Sample overnight input"', DASHBOARD)
        self.assertIn(
            "historicalValues: MockInflammationSignalProvider().trailingValues",
            DASHBOARD,
        )
        self.assertIn("previewDisclosure: signal.isPreview", SIGNAL)
        self.assertIn("Synthetic POC data. This is not personal health data.", SIGNAL)

    def test_direct_detail_qa_route_uses_the_release_sample_fixture(self) -> None:
        self.assertIn('case "inflammation_detail_preview"', CONTENT)
        self.assertIn("InflammationSignalDetailView(", CONTENT)
        self.assertIn("MockInflammationSignalProvider().signal", CONTENT)


if __name__ == "__main__":
    unittest.main()
