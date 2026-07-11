import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "NoomApp/NoomApp"
CONTENT = (SRC / "ContentView.swift").read_text()
SIGNIN = (SRC / "SignInView.swift").read_text()
SIGNUP = (SRC / "SignUpView.swift").read_text()


class NoomAuthResponsiveLayoutContracts(unittest.TestCase):
    def test_welcome_hero_height_adapts_instead_of_using_one_phone_height(self) -> None:
        signed_out = CONTENT.split("struct NoomSignedOutView", 1)[1].split("private struct NoomWelcomeSlide", 1)[0]
        self.assertIn("GeometryReader", signed_out)
        self.assertIn("adaptiveCarouselHeight", signed_out)
        self.assertNotIn(".frame(height: 420)", signed_out)

    def test_welcome_image_owns_the_exact_card_bounds_and_copy_can_wrap(self) -> None:
        slide = CONTENT.split("private struct NoomWelcomeSlideCard", 1)[1].split("#Preview", 1)[0]
        self.assertIn("GeometryReader", slide)
        self.assertIn(".frame(width: proxy.size.width, height: proxy.size.height)", slide)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", slide)

    def test_sign_in_uses_clamped_hero_and_a_bottom_filling_panel(self) -> None:
        for snippet in (
            "let heroHeight =",
            "min(max(geometry.size.height",
            "minHeight: panelMinimumHeight",
            "geometry.safeAreaInsets.bottom",
            ".ignoresSafeArea(.container, edges: [.top, .bottom])",
        ):
            self.assertIn(snippet, SIGNIN)

    def test_sign_in_links_reflow_and_keyboard_scrolls(self) -> None:
        self.assertIn("ViewThatFits(in: .horizontal)", SIGNIN)
        self.assertIn(".scrollDismissesKeyboard(.interactively)", SIGNIN)

    def test_sign_up_is_scrollable_with_a_safe_bottom_action(self) -> None:
        self.assertIn("ScrollView", SIGNUP)
        self.assertIn(".scrollDismissesKeyboard(.interactively)", SIGNUP)
        self.assertIn(".safeAreaInset(edge: .bottom", SIGNUP)
        self.assertIn("ToolbarItemGroup(placement: .keyboard)", SIGNUP)

    def test_auth_qa_routes_are_available_for_multi_device_screenshots(self) -> None:
        for route in ("signedout_home", "signin_preview", "signup"):
            self.assertIn(f'case "{route}"', CONTENT)


if __name__ == "__main__":
    unittest.main()
