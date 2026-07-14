# NoomPlus — Product Design Brief

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

### Full-bleed welcome

Mobbin references reviewed on 2026-07-12:
- [Vrbo iOS full-screen onboarding](https://mobbin.com/explore/screens/769774d5-519e-4360-b60a-9338ad2b0862): edge-to-edge lifestyle imagery with copy and navigation layered over the photograph.
- [Life360 iOS onboarding](https://mobbin.com/explore/screens/4de3adbc-c29e-46d1-92f5-97bb9b6b39d6): a single prominent action and restrained visual hierarchy over a full-screen image.

NoomPlus translates those patterns into its own warm editorial system: every welcome image bleeds beneath the status and home-indicator regions; the logo, Weight Care pill, page indicator, and authentication actions remain inside safe-area-aware overlays. Swiping keeps native paging while the outgoing and incoming images subtly scale and drift, the copy settles vertically, and the active page indicator morphs between positions. Reduce Motion disables those decorative transforms while preserving paging and every action. The image remains decorative to VoiceOver; each page is exposed as one concise combined message and each page indicator is a labeled selectable button.

### Population histogram axes

The same Oura chart reference was re-reviewed on 2026-07-11 for restrained axis density and clear marker hierarchy. Population histograms use one shared Swift Charts component for every SDK metric, including HRV, resting HR, respiratory rate, and total sleep. The horizontal domain is derived from finite buckets with positive population; zero-population tail buckets do not stretch a real distribution into an unreadable sliver. The domain receives modest bin-aware padding and readable “nice” ticks. If every bucket is empty, the validated bucket extent remains the safe fallback. A personal value never silently widens the distribution: it is drawn only when it falls in the displayed range and remains available in text otherwise.

### Today metric-tile visual system

Mobbin references reviewed on 2026-07-10:
- [Oura iOS User Dashboard](https://mobbin.com/explore/screens/c659bd1e-9301-4281-a238-422ceaff9e71): dominant numeric hierarchy, restrained context cues, and generous grouping space.
- [Ultrahuman iOS Health Metrics Dashboard](https://mobbin.com/explore/screens/ad181c1e-9e70-4fbc-b01a-8be0893805aa): smaller baseline-aligned units, consistent marker cards, and lightweight trend context.

NoomPlus translates those durable patterns into its warm Noom surface rather than copying dark palettes, assets, or proprietary layouts. Every Today metric uses one SF Rounded numeric family with monospaced digits; units are separate, smaller, normalized (`bpm`, `ms`, `/min`, `/100`), and baseline aligned. Labels, values, captions, and tap affordances occupy fixed roles. Sleep uses the same component and type family as the two-column grid, differentiated only by full-width prominence. Metric cards use a subtle Noom-tinted icon well, a quiet context footer, continuous 22-point corners, 12-point grid gutters, and a visible chevron while preserving the existing real SDK values and destinations.

### Home empty and early-history states

The same Oura and Ultrahuman Mobbin references above support keeping card anatomy stable while data arrives, rather than replacing the dashboard with plausible zeros. A dashboard metric is available only when the SDK returns a finite positive value; otherwise its value is `—`, its unit is omitted, and the footer explains what will unlock it. Missing Sleep on Today reads **Waiting for today's sleep data**; a historical day reads **No sleep data for this day**. The Home **Progress** preview remains hidden until the weekly SDK responses cover at least three unique returned dates across Sleep or Recovery, then uses the concise title **Progress**. Missing dates remain missing and are never converted to zero or duplicated across streams to inflate coverage.

## Sleep hub redesign

The Sleep tab becomes a sync-backed daily hub rather than a directory. It surfaces: (1) a concise sleep score and duration, (2) a compact stage preview, (3) recovery drivers from returned score factors, and (4) clear drill-ins for full Sleep and Recovery detail. It uses only SDK-returned data; it does not invent a recovery score, stage history, baseline, or coaching diagnosis.

**Inspiration:** [Ultrahuman iOS Sleep Data Dashboard on Mobbin](https://mobbin.com/explore/screens/36e5a755-9c0d-4afb-ba4e-dff42cd39a47), used only for the score + duration + cycles information hierarchy. The implementation keeps Noom's warm canvas, editorial typography, coral sleep accent, and explicit accessible labels; it does not copy assets, copy, palette, or layout.

## Interactive metric charts

Recent-pattern charts use Apple Swift Charts on iOS 18+ rather than a custom Canvas sparkline. The implementation preserves real completed dates, shows readable X (date) and Y (native value/unit) labels, keeps the personal typical-range band and median reference, and supports zero-distance drag scrubbing for tap, hold, and continuous inspection. VoiceOver exposes the selected coordinates and adjustable previous/next-day navigation.

Mobbin references used for hierarchy—not copied branding or assets:
- [Oura Readiness Trend](https://mobbin.com/explore/screens/e2d94334-c086-4427-8a8c-6f76a9ac0c7a)
- [Visible Trend Chart](https://mobbin.com/explore/screens/874e1de2-556c-4e15-ad3c-fbb397178369)
- [Ultrahuman Health Metrics Dashboard](https://mobbin.com/explore/screens/ad181c1e-9e70-4fbc-b01a-8be0893805aa)

## Recording experiences

NoomPlus exposes recording from one floating action at the bottom-right of Home, above the tab bar. The destination is a focused recording hub—not a second tab—with two deliberately different paths:

1. **Spot check** — a calm, fixed 3-minute (180-second) biometrics capture with Finish available after the SDK's 30-second minimum and signal criteria are met. The user receives stillness guidance, visible elapsed-time progress, a bounded interpolated live PPG waveform, and real metrics only as the SDK emits them. The waveform is explicitly described as a light-based pulse signal, not an ECG or diagnosis.
2. **Activity tracking** — an open-ended session with activity selection, a large count-up timer, live HR emphasis, bounded HR trend, pause/resume, and explicit finish. No distance, pace, route, calorie, or heart-rate-zone value is invented because those values are not exposed as live recording streams by the current SDK contract.

### SensorBioSDK recording capability matrix

| Stream/state | Public SDK source | Spot check | Activity tracking | UI rule |
|---|---|---:|---:|---|
| PPG | `sensorBio.ppg` raw `(timestamp, Float)` | Live bounded waveform | Not foregrounded during motion | Normalize only for drawing; never label as ECG |
| HR | `sensorBio.hr` `(timestamp, bpm)` | Live metric | Primary live metric + trend | Missing remains `—` |
| HRV | `sensorBio.hrv` `(timestamp, ms)` | Live metric | Secondary live metric | No interpretation from one sample |
| IBI | `sensorBio.bbi` `(timestamp, ms)` | Shown to users as **IBI** | Secondary live metric | Preserve SDK value; rename only for user-facing terminology |
| RR | `sensorBio.rr` `(timestamp, breaths/min)` | Secondary live metric | Available but not primary | Missing remains `—` |
| SpO₂ | `sensorBio.spo2` `(timestamp, %)` | Secondary live metric | Available but not primary | Display only finite emitted values |
| SNR | `sensorBio.snr` `(timestamp, raw ratio)` | Signal-received context | Signal context | Convert each current packet exactly with `raw / 10`, then `10 * log10(raw / 10)`; no EMA or invented clinical quality bands |
| ECG | `sensorBio.ecg` raw stream | Not displayed in this client | Not displayed | Avoid diagnostic framing |
| Lifecycle | `recordingState`, `canFinalize`, `isRecordingPaused` | Elapsed-time/finalize | Elapsed-time/pause/finalize | SDK is source of truth |
| Submission | Awaited `recordDetailedBiometrics` / `recordActivity` orchestration | After completion | After completion | Completion means queued/processing, not server analysis complete |

### Mobbin references reviewed on 2026-07-11

- [Oura iOS Workout start](https://mobbin.com/explore/screens/90c1b4a8-1bcd-48d7-8d48-ef0231f3673c): one selected activity, a dominant timer, and one clear start action.
- [Oura Android Recording workout HR flow](https://mobbin.com/explore/flows/1fa13090-f7b3-4621-adf2-17f6ed5c5aef): explicit idle/recording/paused/completed hierarchy, Resume as the paused primary action, and missing-data explanations.
- [Oura iOS Adding a workout flow](https://mobbin.com/explore/flows/a57f8da1-9ffc-4677-be08-cd66f20682a9): bottom-right floating entry, labeled action expansion, and frequent activity choices before the full list.

No Oura palette, ring-specific language, proprietary score, route behavior, or exact layout is copied. NoomPlus translates the hierarchy into warm cream surfaces, white cards, editorial type, rose accents, and the SensorBioSDK capabilities actually available.

## Accessibility and privacy

- Every score includes an accessibility label with value, completed date, quality, and Body Status coverage where applicable.
- Use semantic Noom colors, explicit labels, Dynamic Type, and minimum 44pt targets.
- Synthetic values exist only in debug/preview code and are visibly labeled Preview.
- Do not send the score, date, Body Status, device identity, or account identity to the public demo backend.
