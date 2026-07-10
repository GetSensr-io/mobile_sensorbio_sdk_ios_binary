# Noom Inflammation Signal POC — Design Brief

## Scope

A provider-neutral **Inflammation signal** is a wellness-context metric shown alongside existing health metrics and one transparent input to Body Status. The POC uses debug-only synthetic fixtures to exercise UI and formula behavior. Release/TestFlight production paths show an unavailable state until a real authenticated or SDK-backed source exists.

## Product contract

- Metric title: **Inflammation signal**.
- Score: integer `0...100`; higher means a more favorable / lower-inflammation signal.
- Cadence: one daily overnight value for the completed date it represents.
- V1 behavior: value and 30-day personal trend only; no recommendations, diagnosis, risk language, treatment language, or provider branding.
- Baseline: up to 30 completed dates before the selected date; 14 valid dates required; selected date excluded.
- Real payload: score, completed date, generated time, algorithm version, and quality/status.

## Body Status v2

Base formula: Resting HR 25%, Nocturnal HRV 25%, Sleep 25%, Inflammation signal 25%.

When valid inputs are missing, renormalize available components only and visibly disclose coverage, for example **Based on 3 of 4 available signals**. Missing is never zero. Invalid, stale, or low-confidence input is excluded.

## Inspiration

Mobbin reference: [Oura iOS Readiness Trend](https://mobbin.com/explore/screens/e2d94334-c086-4427-8a8c-6f76a9ac0c7a). Translate its quiet score-plus-trend hierarchy into Noom tokens; do not copy Oura assets, copy, or UI.

## Accessibility and privacy

- Every score includes an accessibility label with value, completed date, quality, and Body Status coverage where applicable.
- Use semantic Noom colors, explicit labels, Dynamic Type, and minimum 44pt targets.
- Synthetic values exist only in debug/preview code and are visibly labeled Preview.
- Do not send the score, date, Body Status, device identity, or account identity to the public demo backend.
