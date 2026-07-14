# NoomPlus Capability Matrix

Last updated: 2026-07-14

States are intentionally separate: **Implemented**, **Simulator-verified**, **TestFlight-verified**, and **physical-device-verified** are not interchangeable.

| Capability | Implementation source | Implemented | Simulator-verified | TestFlight-verified | Physical-device-verified | Notes |
|---|---|---:|---:|---:|---:|---|
| Dashboard/detail parity for Steps, Active Calories, RHR, HRV, and RR | `MetricDisplayPolicy.swift` + routed snapshots | Yes | 159 XCTest + 172 contracts | Pending build 30 | No | Same-day value, canonical unit, missing state, source-day context, and loading/error continuity are preserved; physical sensor lineage is not inferred. |
| Home floating Record action | `DashboardView.swift` | Yes | Yes | Pending build 30 | No | Anchored above the tab bar and accessibility-labeled. |
| Recording hub | `RecordingExperienceView.swift` | Yes | Yes | Pending build 30 | No | Distinct Spot check and Activity tracking choices. |
| 3-minute (180-second) Spot check | `recordDetailedBiometrics(duration: 180, minDuration: 30)` | Yes | Deterministic Debug fixture | Pending build 30 | No | Real Band capture requires hardware; Finish still follows SDK signal readiness. |
| Open-ended Activity tracking | `recordActivity(activityName:minDuration:)` | Yes | Deterministic Debug fixture | Pending build 30 | No | Activity choices come from SDK recent/featured lists. |
| Pause/resume/finish/cancel | SensorBioSDK recording controls | Yes | Yes, UI contracts | Pending build 30 | No | Runtime continuity requires Band testing. |
| Active-recording restoration | `activeRecording` + `awaitActiveRecordingCompletion()` | Yes | Yes, source contract | Pending build 30 | No | Restores biometrics and exact activity name by kind; exposes meditation/unknown kinds as separate SDK-owned sessions instead of coercing them. |
| Live PPG waveform | `sensorBio.ppg` | Yes | Synthetic Debug fixture | Pending build 30 | No | Finite samples are buffered before display-cadence interpolation; labeled as light-based wellness context, not ECG. |
| Live heart rate | `sensorBio.hr` | Yes | Synthetic Debug fixture | Pending build 30 | No | Invalid/non-positive samples are omitted. |
| Live HRV | `sensorBio.hrv` | Yes | Synthetic Debug fixture | Pending build 30 | No | Presented as provisional until processing completes. |
| Live IBI/BBI | `sensorBio.bbi` | Yes | Synthetic Debug fixture | Pending build 30 | No | Exposed to users as IBI under More live signals for Spot check. |
| Live respiratory rate | `sensorBio.rr` | Yes | Synthetic Debug fixture | Pending build 30 | No | No medical interpretation. |
| Live SpO₂ | `sensorBio.spo2` | Yes | Synthetic Debug fixture | Pending build 30 | No | Omitted when unavailable or non-finite. |
| Live signal quality/SNR | `sensorBio.snr` | Yes | Synthetic Debug fixture | Pending build 30 | No | The current raw SDK ratio is converted to dB without EMA history or an invented quality grade. |
| Accelerometer stream | SensorBioSDK surface | Not shown in UI | No | No | No | No derived pace, distance, calories, or motion classification is fabricated. |
| Setup/warming/finalizing/completed/error states | Recording state machine and friendly error mapping | Yes | Yes, contracts and fixtures | Pending build 30 | No | Includes too-short, insufficient-data, unavailable, and generic failure paths. |
| Debug QA route exclusion from Release | `#if DEBUG` routes and fixtures | Yes | Debug routes verified | Pending archive scan | No | Archived executable must be scanned before upload. |
| BLE recording continuity/background behavior | SensorBioSDK + iOS | Code path present | Simulator cannot verify | Pending | No | Requires a physical iPhone and Noom Band. |
