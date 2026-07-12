import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SIGNUP = (ROOT / "NoomApp/NoomApp/SignUpView.swift").read_text()
STATE = (ROOT / "NoomApp/NoomApp/SignUpFormState.swift").read_text()


class NoomSignupErrorCopyContracts(unittest.TestCase):
    def test_invalid_email_copy_does_not_imply_verification_email(self):
        self.assertNotIn("Please check your email and try again.", SIGNUP)
        self.assertNotIn("verification email", SIGNUP.lower())
        self.assertIn("Enter a valid email address.", SIGNUP)

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
        self.assertIn("orgId: nil", STATE)
        self.assertIn("accountVerificationAccessCode: nil", STATE)

    def test_signup_matches_example_app_direct_create_account_flow(self):
        self.assertNotIn("checkEmailAvailability", STATE)
        self.assertNotIn("validateAccountRequirements", STATE)
        self.assertIn("sensorBio.createAccount(request)", STATE)

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
            ".other(let message)",
        ):
            self.assertIn(f"case {outcome}:", STATE)
        self.assertNotIn("@unknown default:\n                break", STATE)
        self.assertIn("@unknown default:", STATE)
        self.assertIn("result = .unexpected", STATE)

    def test_every_signup_result_has_specific_user_facing_copy(self):
        for result in (
            ".invalidBirthday",
            ".invalidEmail",
            ".invalidHeight",
            ".invalidWeight",
            ".invalidAccessCode",
            ".accessCodeAlreadyInUse",
            ".deviceSerialNumberRequired",
            ".deviceSerialNumberMismatch",
            ".other(let message)",
            ".threw",
            ".unexpected",
        ):
            self.assertIn(f"case {result}:", SIGNUP)


if __name__ == "__main__":
    unittest.main()