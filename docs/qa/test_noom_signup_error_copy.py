import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SIGNUP = (ROOT / "NoomApp/NoomApp/SignUpView.swift").read_text()
STATE = (ROOT / "NoomApp/NoomApp/SignUpFormState.swift").read_text()
DEPENDENCIES = (ROOT / "NoomApp/NoomApp/SignUpDependencies.swift").read_text()


class NoomSignupErrorCopyContracts(unittest.TestCase):
    def test_invalid_email_copy_does_not_imply_verification_email(self):
        self.assertNotIn("Please check your email and try again.", SIGNUP)
        self.assertNotIn("verification email", SIGNUP.lower())
        self.assertIn("Enter a valid email address.", SIGNUP)
        self.assertIn("An account with this email already exists. Sign in instead.", SIGNUP)

    def test_signup_has_no_access_code_or_organization_input(self):
        for forbidden in (
            "Program access",
            "Access code",
            "Organization (optional)",
            "Org ID",
            "form.orgId",
        ):
            self.assertNotIn(forbidden, SIGNUP)
        self.assertNotIn("var orgId", STATE)
        self.assertIn("orgId: nil", DEPENDENCIES)
        self.assertIn("accountVerificationAccessCode: nil", DEPENDENCIES)

    def test_signup_disambiguates_email_format_from_email_already_in_use(self):
        self.assertNotIn("validateAccountRequirements", STATE + DEPENDENCIES)
        self.assertIn("sensorBio.checkEmailAvailability(email: email)", DEPENDENCIES)
        self.assertIn("sensorBio.createAccount(request)", DEPENDENCIES)
        self.assertLess(
            STATE.index("dependencies.checkEmailAvailability(normalizedEmail)"),
            STATE.index("dependencies.createAccount(request)"),
        )
        for outcome in (
            ".ok",
            ".invalidEmail",
            ".emailInUse",
            ".other",
        ):
            self.assertIn(f"case {outcome}:", DEPENDENCIES)
        self.assertIn("result = .emailInUse", STATE)
        self.assertIn("case emailInUse", STATE)
        self.assertGreaterEqual(STATE.count("dependencies.checkEmailAvailability(normalizedEmail)"), 2)

    def test_every_documented_create_account_outcome_is_explicitly_mapped(self):
        for outcome in (
            ".success",
            ".invalidBirthday",
            ".invalidEmail",
            ".invalidHeight",
            ".invalidWeight",
            ".invalidAccessCode",
            ".accessCodeAlreadyInUse",
            ".deviceSerialNumberRequired",
            ".deviceSerialNumberMismatch",
            ".other",
        ):
            self.assertIn(f"case {outcome}:", DEPENDENCIES)
        self.assertNotIn("@unknown default:\n                break", DEPENDENCIES)
        self.assertIn("@unknown default:", DEPENDENCIES)
        self.assertIn("result = .unexpected", STATE)

    def test_every_signup_result_has_specific_user_facing_copy(self):
        for result in (
            ".invalidBirthday",
            ".invalidEmail",
            ".emailInUse",
            ".invalidHeight",
            ".invalidWeight",
            ".invalidAccessCode",
            ".accessCodeAlreadyInUse",
            ".deviceSerialNumberRequired",
            ".deviceSerialNumberMismatch",
            ".serviceUnavailable",
            ".threw",
            ".unexpected",
        ):
            self.assertIn(f"case {result}:", SIGNUP)

    def test_sdk_error_messages_are_not_rendered_verbatim(self):
        self.assertNotIn("other(message:", STATE)
        self.assertNotIn("Label(message", SIGNUP)
        self.assertIn("case .other:", DEPENDENCIES)
        self.assertIn("return .serviceUnavailable", DEPENDENCIES)


if __name__ == "__main__":
    unittest.main()