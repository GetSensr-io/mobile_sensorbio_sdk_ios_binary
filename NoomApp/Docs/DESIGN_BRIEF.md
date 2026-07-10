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

## Sleep hub redesign

The Sleep tab becomes a sync-backed daily hub rather than a directory. It surfaces: (1) a concise sleep score and duration, (2) a compact stage preview, (3) recovery drivers from returned score factors, and (4) clear drill-ins for full Sleep and Recovery detail. It uses only SDK-returned data; it does not invent a recovery score, stage history, baseline, or coaching diagnosis.

**Inspiration:** [Ultrahuman iOS Sleep Data Dashboard on Mobbin](https://mobbin.com/explore/screens/36e5a755-9c0d-4afb-ba4e-dff42cd39a47), used only for the score + duration + cycles information hierarchy. The implementation keeps Noom's warm canvas, editorial typography, coral sleep accent, and explicit accessible labels; it does not copy assets, copy, palette, or layout.

## Accessibility and privacy

- Every score includes an accessibility label with value, completed date, quality, and Body Status coverage where applicable.
- Use semantic Noom colors, explicit labels, Dynamic Type, and minimum 44pt targets.
- Synthetic values exist only in debug/preview code and are visibly labeled Preview.
- Do not send the score, date, Body Status, device identity, or account identity to the public demo backend.
