# App Encryption Export Compliance

## Current declaration

- **App:** Noom (`ai.sensr.example.NoomApp`)
- **Decision owner:** Sameer Sontakey
- **Decision date:** 2026-07-10
- **Questionnaire answer:** The app uses standard encryption algorithms instead of, or in addition to, encryption provided by Apple’s operating system.
- **France availability answer:** No.
- **Shipping plist declaration:** `ITSAppUsesNonExemptEncryption = YES`

## Required follow-up

The non-exempt declaration means App Store Connect export-compliance documentation must be completed. Apple provides `ITSEncryptionExportComplianceCode` only after it approves the documentation. Do not invent or add that code until it appears in App Store Connect.

When Apple provides the code, add it to the shipping target’s `Info.plist`, archive a new build, and verify the archived plist contains both keys.
