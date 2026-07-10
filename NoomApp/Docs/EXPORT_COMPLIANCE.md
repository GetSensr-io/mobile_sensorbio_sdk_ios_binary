# App Encryption Export Compliance

## Current declaration

- **App:** NoomPlus (`ai.sensr.example.NoomApp`)
- **Decision owner:** Sameer Sontakey
- **Decision date:** 2026-07-10
- **Questionnaire answer:** The app uses standard encryption algorithms instead of, or in addition to, encryption provided by Apple’s operating system.
- **France availability answer:** No.
- **Apple questionnaire outcome:** App Store Connect stated that no encryption documentation upload is required for these answers and advised declaring that the app does not use non-exempt encryption in `Info.plist`.
- **Shipping plist declaration:** `ITSAppUsesNonExemptEncryption = NO`

## Verification

The first build 12 upload attempt with `ITSAppUsesNonExemptEncryption = YES` was rejected by App Store Connect with error `90592` because there was no matching Apple-issued export-compliance code. No code was displayed or issued by the questionnaire, and none was fabricated.

After completing the authenticated App Store Connect questionnaire with the recorded answers, build 6’s Missing Compliance state cleared to Ready to Submit. Build 12 must be archived with the `NO` declaration, uploaded, and re-opened in TestFlight to verify that no Missing Compliance warning remains.

Re-run the questionnaire and this decision whenever the app’s cryptography, distribution territories, or linked SDK behavior changes.
