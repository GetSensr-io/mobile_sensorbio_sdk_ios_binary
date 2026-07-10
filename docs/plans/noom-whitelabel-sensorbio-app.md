# Noom White-Labeled SensorBio iOS App Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task after Product/Design approves Phase 0 outputs.

**Goal:** Build a Noom-branded, white-labeled iOS 18+ SwiftUI app powered by the SensorBio iOS SDK, using `docs/brand/noom-brand.md` as the branding source of truth.

**Architecture:** Create a new host app that consumes the binary `SensorBioSDK` through CocoaPods rather than modifying or skinning SDK binaries. Wrap the SDK singleton (`sensorBio`) behind app-owned adapters, view models, design tokens, and Noom-specific product flows so brand, UX, analytics, and testing remain isolated from the binary distribution.

**Tech Stack:** iOS 18+, Xcode 16.3+ / Swift 6.1, SwiftUI + Observation/Combine, CocoaPods 1.16+, SensorBioSDK binary `.xcframework`s, XCTest/XCUITest, real-device BLE validation.

---

## 0. Status, Inputs, and Blockers

### 0.1 Files inspected

- `/Users/anton/mobile_sensorbio_sdk_ios_binary/README.md`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/SDK_INTERFACE.md`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/Podfile`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/SDKExampleApp.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/ContentView.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/MainTabView.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/DashboardView.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/DashboardState.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/PairDeviceState.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/Metric.swift`
- `/Users/anton/mobile_sensorbio_sdk_ios_binary/ExampleApp/ExampleApp/InsightsView.swift`
- `https://www.noom.com/` via `web_extract` for temporary public positioning only.

### 0.2 Brandfetch status

`docs/brand/noom-brand.md` has been regenerated from Brandfetch and is now the canonical Noom brand source for this plan. Raw Brandfetch audit data exists at `docs/brand/noom-brandfetch.raw.json`.

Generated from `/Users/anton/mobile_sensorbio_sdk_ios_binary`:

```bash
python ~/.hermes/skills/productivity/brandfetch-brand-md/scripts/brand_md_from_brandfetch.py \
  --url noom.com \
  --output docs/brand/noom-brand.md \
  --raw-output docs/brand/noom-brandfetch.raw.json
```

Verified:

- `docs/brand/noom-brand.md` exists and no longer contains the missing-key blocker.
- `docs/brand/noom-brandfetch.raw.json` exists.
- Brandfetch quality score: `0.9600756727112258` — high reliability.
- No API key was written to either output file.

### 0.3 Verified Brandfetch Noom facts

Use these for product framing and initial app tokens. Final production asset usage should still be visually spot-checked against Brandfetch asset URLs and Noom approvals.

- Noom positions around weight loss, behavior change, coaching, GLP-1 support, and preventive health.
- Public site phrases observed:
  - “Meds to lose the weight. Noom to keep it off.”
  - “Psychology-based weight loss.”
  - “Improve your health and see it in your biomarkers.”
  - “Noom’s customized plans harness the power of psychology and biology for weight-loss results that last.”
  - “Don’t just lose weight—keep it off.”
- Brandfetch colors:
  - Noom red: `#FB513B`
  - Warm surface: `#F6F4EE`
  - Deep teal/ink: `#1D3A44`
- Brandfetch typography:
  - `Untitled Sans Web Regular`
  - `Untitled Serif Web Regular`
- Brandfetch voice: confident, measured, empowering, factual.
- Brandfetch style: modern, clean, approachable, high-contrast.
- Avoid: cutesy, hard sell, stuffy.

### 0.4 Hard constraints

- Do not modify SDK binaries under `/SensorBio/*.xcframework`.
- Build a host app around the SDK; do not try to skin the SDK internals.
- iOS 18+ minimum deployment target.
- Xcode 16.3+ / Swift 6.1.
- CocoaPods 1.16+.
- Required Info.plist:
  - `NSBluetoothAlwaysUsageDescription`
  - `NSBluetoothPeripheralUsageDescription`
  - `UIBackgroundModes` with `bluetooth-central`
- Required CocoaPods `post_install` settings:
  - `IPHONEOS_DEPLOYMENT_TARGET = 18.0`
  - `CLANG_CXX_LANGUAGE_STANDARD = c++17`
  - `CLANG_CXX_LIBRARY = libc++`
  - `BUILD_LIBRARY_FOR_DISTRIBUTION = YES`
- Pairing must respect the SDK flow: `startScan` → `deviceDiscovered` → `connect(pairing: true)` → `pairingConnection` → blink/ask device confirmation → `setAskForDeviceResponse(true)` → wait for button tap → `persistDeviceState` → `disconnect`.

---

## 1. Product Vision

### 1.1 One-sentence vision

A Noom-branded metabolic health companion that turns SensorBio wearable data into simple daily readiness, behavior-change guidance, and biomarker-aware coaching moments.

### 1.2 Product promise

**“Understand today’s body state, learn the why behind it, and take one Noom-aligned action that helps tomorrow.”**

This app should not feel like a generic wearable dashboard. It should feel like Noom’s psychology-and-biology positioning extended into passive biometric sensing:

- Body state is explained in plain language.
- Metrics are grouped around behavior and outcomes, not raw sensor novelty.
- Coaching prompts emphasize sustainable habits.
- Pairing feels guided and reassuring, not technical.
- Clinical/biomarker-style data is presented as understandable context, not a diagnostic claim.

### 1.3 Target users

Primary:

- Noom users enrolled in weight-loss, Noom Med, GLP-1 Companion, or preventive-health programs.
- Users who need behavior-change feedback backed by real sleep, recovery, HR/HRV, respiratory rate, activity, and wearable adherence signals.

Secondary:

- Coaches/clinical support teams who may need users to capture better longitudinal sensor data.
- Enterprise/health-plan pilots where Noom wants a branded wearable experience without maintaining BLE infrastructure.

### 1.4 Success outcomes

- User pairs a SensorBio wearable in one guided session without support intervention.
- User understands “how ready is my body today?” within five seconds of opening Home.
- User can drill into sleep, recovery, activity, HR, HRV, and respiratory rate with an explanation-first layout.
- User receives Noom-style recommendations that translate data into one sustainable action.
- Engineering can ship a Noom flavor without forking SensorBio SDK binaries.

---

## 2. Brand Translation from `docs/brand/noom-brand.md`

### 2.1 Brand source-of-truth rule

All Noom visual decisions must be sourced from:

- Primary: `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/brand/noom-brand.md`
- Raw audit data if available: `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/brand/noom-brandfetch.raw.json`

Because `noom-brand.md` is now Brandfetch-derived, implementation may finalize initial brand tokens from it:

- Colors: `#FB513B`, `#F6F4EE`, `#1D3A44`
- Fonts: `Untitled Sans Web Regular`, `Untitled Serif Web Regular`
- Logo/icon assets from the Brandfetch asset URLs in `docs/brand/noom-brand.md`
- App icon, splash, and marketing screenshot directions after visual spot-check and Noom approval

### 2.2 Brand-to-app token mapping

Create token files from the Brandfetch-derived `brand.md`:

- `NoomSensorBio/DesignSystem/Brand/NoomBrandTokens.swift`
- `NoomSensorBio/DesignSystem/Brand/NoomColorTokens.swift`
- `NoomSensorBio/DesignSystem/Brand/NoomTypographyTokens.swift`
- `NoomSensorBio/DesignSystem/Brand/NoomAssetCatalog.md`
- `NoomSensorBio/Resources/Assets.xcassets/NoomLogo.imageset/`
- `NoomSensorBio/Resources/Assets.xcassets/AppIcon.appiconset/`

Recommended token categories:

```swift
enum NoomColorToken {
    static let backgroundPrimary: Color = ...       // from brand.md or derived semantic neutral
    static let backgroundElevated: Color = ...
    static let textPrimary: Color = ...
    static let textSecondary: Color = ...
    static let accentPrimary: Color = ...           // from Brandfetch primary/accent
    static let accentSubtle: Color = ...
    static let success: Color = ...                 // app semantic, accessible against brand palette
    static let warning: Color = ...
    static let critical: Color = ...
    static let chartSleep: Color = ...
    static let chartRecovery: Color = ...
    static let chartActivity: Color = ...
}
```

### 2.3 Visual direction

Use the approved UI inspiration direction:

- **Oura calm:** soft hierarchy, quiet surfaces, subtle gradients, ring/score metaphors.
- **Superpower premium health intelligence:** large typography, executive-summary cards, explanation-first insights.
- **WHOOP daily coaching:** daily body-state emphasis, recovery/readiness interpretation, action guidance.
- **Function-adjacent biomarker patterns:** clinical grouping, reference ranges, “why it matters” education.

Adapt this through Brandfetch Noom tokens, not through copied competitor styling.

### 2.4 Tone and copy rules

Use the generated Brandfetch Brand Context voice:

- Confident, measured, empowering, factual.
- Explain the “why” behind metrics.
- Avoid cutesy, hard-sell, stuffy, shame-based, alarmist, or over-medicalized language.
- Avoid diagnostic language: “may indicate,” “can help you understand,” “talk to your clinician” where relevant.
- Tie recommendations to sustainable routines and behavior change, not biohacking extremes.

Example app copy direction:

- Home headline: “Your body state today”
- Recovery card explainer: “Recovery reflects how your sleep, resting heart rate, and HRV are trending together.”
- Pairing ritual: “Let’s connect your sensor so Noom can personalize your day with real body signals.”
- Coaching CTA: “Try one small reset today”

Refine against `docs/brand/noom-brand.md` before final copy review.

---

## 3. Information Architecture

### 3.1 Top-level navigation

Use a four-tab app shell:

1. **Today** — daily body state, key scores, next best action.
2. **Trends** — sleep/recovery/activity/biometrics over day/week/month/year.
3. **Insights** — SensorBio personal/population insights, Noom explanations, experiments.
4. **Profile** — device, goals, account, permissions, support, developer diagnostics in non-production builds.

Recommended SwiftUI structure:

```text
NoomSensorBio/App/NoomSensorBioApp.swift
NoomSensorBio/App/AppRootView.swift
NoomSensorBio/App/AppRouter.swift
NoomSensorBio/App/AppEnvironment.swift
NoomSensorBio/Features/Today/TodayView.swift
NoomSensorBio/Features/Trends/TrendsView.swift
NoomSensorBio/Features/Insights/InsightsView.swift
NoomSensorBio/Features/Profile/ProfileView.swift
NoomSensorBio/Features/DevicePairing/PairDeviceFlowView.swift
```

### 3.2 Signed-out IA

Signed-out flow:

1. Brand splash / value prop.
2. Sign in / create account.
3. Agreements if SDK requires them.
4. Profile completion if `forceUserToUpdateProfile` is set.
5. Bluetooth permission education screen.
6. Pairing ritual.
7. First sync / calibration state.
8. Today tab.

### 3.3 Signed-in IA

Signed-in app:

```text
Root
├── Today
│   ├── Body State Summary
│   ├── Recovery Score
│   ├── Sleep Summary
│   ├── Activity Progress
│   ├── Live Device Status
│   └── Today’s Noom Action
├── Trends
│   ├── Recovery
│   ├── Sleep
│   ├── Activity
│   ├── Heart Rate
│   ├── HRV
│   └── Respiratory Rate
├── Insights
│   ├── Personal Insights
│   ├── Positive/Negative Influencers
│   ├── Suggested Experiment
│   └── Population Comparison
└── Profile
    ├── Account
    ├── Goals
    ├── Device
    ├── Permissions
    ├── Help & Support
    └── Diagnostics (debug/internal only)
```

---

## 4. Core UX Flows

### 4.1 Onboarding and auth

#### Flow

1. `WelcomeView`
   - Noom logo from `brand.md`.
   - Value prop: psychology + biology + body signals.
   - CTA: “Sign in” / “Create account”.
2. `SignInView`
   - Calls `sensorBio.signIn(email:password:)` through `AuthService`.
   - Handles SDK outcomes:
     - `.success`
     - `.passwordIncorrect`
     - `.unknownUsername`
     - `.subscriptionRequired`
     - `.loginBlocked`
     - `.other`
3. `CreateAccountView`
   - Calls `validateAccountRequirements`, `checkEmailAvailability`, and `createAccount`.
4. `AgreementGateView`
   - Calls `shouldRequestAgreement` and `acceptCurrentAgreements` / `acceptAgreements` as needed.
5. `ProfileCompletionGateView`
   - Routes from SDK flags `forceUserToUpdateProfile` and `forceUserToUpdatePassword`.

#### Implementation files

```text
NoomSensorBio/Features/Auth/AuthService.swift
NoomSensorBio/Features/Auth/AuthViewModel.swift
NoomSensorBio/Features/Auth/WelcomeView.swift
NoomSensorBio/Features/Auth/SignInView.swift
NoomSensorBio/Features/Auth/CreateAccountView.swift
NoomSensorBio/Features/Auth/AgreementGateView.swift
NoomSensorBio/Features/Auth/ProfileCompletionGateView.swift
```

### 4.2 Pairing as a guided ritual

Use the SDK’s proven reference app flow from `PairDeviceState.swift`, but redesign the presentation.

#### UX phases

1. **Prepare**
   - Explain Bluetooth, charging/wearing, proximity.
   - CTA: “Find my sensor”.
2. **Scanning**
   - Calm animated scanning surface.
   - Show devices sorted by RSSI/proximity.
   - Timeout after 30 seconds with guidance.
3. **Connect**
   - User selects a device.
   - App calls `sensorBio.connect(device.id, pairing: true)`.
4. **Confirm on device**
   - On `pairingConnection`, stop scan, blink LED with `userLED(blue: true, blink: true, for: 5)`, and call `setAskForDeviceResponse(true)`.
   - Tell user: “Press the button on your sensor when it blinks.”
5. **Persist**
   - On `buttonTaps`, call `setAskForDeviceResponse(false)`.
   - Persist device state:
     ```swift
     let entry: [String: Any] = [
         "macAddress": device.id,
         "name": device.name,
         "deviceType": device.deviceType.rawValue
     ]
     sensorBio.persistDeviceState([device.id: entry])
     sensorBio.disconnect()
     ```
6. **First sync / all set**
   - Show connected state and first-sync expectations.
   - Route to Today.

#### Implementation files

```text
NoomSensorBio/Features/DevicePairing/PairDeviceService.swift
NoomSensorBio/Features/DevicePairing/PairDeviceViewModel.swift
NoomSensorBio/Features/DevicePairing/PairDeviceFlowView.swift
NoomSensorBio/Features/DevicePairing/PairingPreparationView.swift
NoomSensorBio/Features/DevicePairing/PairingScanningView.swift
NoomSensorBio/Features/DevicePairing/PairingConfirmDeviceView.swift
NoomSensorBio/Features/DevicePairing/PairingSuccessView.swift
NoomSensorBio/Features/DevicePairing/PairingTroubleshootingView.swift
```

### 4.3 Today dashboard

Home should answer, in order:

1. What is my body state today?
2. What changed since yesterday/baseline?
3. What should I do next?
4. Can I trust the data? Is my device synced/worn/charged?

#### Layout

1. Header
   - Date
   - Greeting
   - Sync status: connected / syncing / last synced / battery
2. Hero score
   - Recovery/body-state score when available.
   - Large typography.
   - Human label: “Ready,” “Steady,” “Take it easy” based on thresholds.
3. Explanation card
   - “What’s driving this” from recovery factors when available.
4. Three summary cards
   - Sleep
   - Activity
   - Resting signals (HR/HRV/RR)
5. Noom action card
   - One action mapped from body state + Noom behavior-change framing.
6. Data freshness card
   - Last sync, wearable status, missing-data guidance.

#### Data sources

- `fetchDashboardData(date:tzOffset:)`
- `fetchDailyRecovery(date:)`
- `fetchSleepDetail(endDate:endTimestamp:)` where dashboard sleep links to detail.
- SDK published connection state:
  - `connected`
  - `haveDevice`
  - `batteryLevel`
  - `charging`
  - `worn`
  - `deviceSyncing`
  - `percentSynced`
  - `lastSyncd`

#### Implementation files

```text
NoomSensorBio/Features/Today/TodayRepository.swift
NoomSensorBio/Features/Today/TodayViewModel.swift
NoomSensorBio/Features/Today/TodayView.swift
NoomSensorBio/Features/Today/Components/BodyStateHeroCard.swift
NoomSensorBio/Features/Today/Components/MetricSummaryCard.swift
NoomSensorBio/Features/Today/Components/NoomActionCard.swift
NoomSensorBio/Features/Today/Components/DeviceFreshnessCard.swift
```

### 4.4 Trends and metric detail

Preserve the reference app’s SDK coverage but redesign for explanation-first metric pages.

#### Metric detail template

Each metric detail screen should include:

1. Metric title and plain-English “why it matters”.
2. Current value and trend delta.
3. Chart for selected granularity.
4. Factors/context.
5. Noom interpretation.
6. Data caveats and missing-data state.

#### Screens

- Recovery detail:
  - `fetchDailyRecovery`
  - `fetchRangeRecovery`
  - Factor weights: HRV 40%, RHR 40%, Sleep Efficiency 10%, Sleep Duration 10% per SDK docs.
- Sleep detail:
  - `fetchSleepDetail`
  - `fetchSleepAggregation`
  - Manual edits via sleep writes only if Product approves.
- Steps/activity detail:
  - `fetchSteps`
  - `fetchDailyActivityDetail`
  - `fetchCalories`
- HR detail:
  - `fetchDailyHR`
  - `fetchRangeHR`
- HRV detail:
  - `fetchDailyHRV`
  - `fetchRangeHRV`
- Respiratory rate detail:
  - `fetchDailyRR`
  - `fetchRangeRR`
- SpO2:
  - SDK marks SpO2 WIP; hide behind feature flag until validated.

#### Implementation files

```text
NoomSensorBio/Features/Trends/TrendsRepository.swift
NoomSensorBio/Features/Trends/TrendsViewModel.swift
NoomSensorBio/Features/Trends/TrendsView.swift
NoomSensorBio/Features/Metrics/MetricDetailTemplate.swift
NoomSensorBio/Features/Metrics/Recovery/RecoveryDetailView.swift
NoomSensorBio/Features/Metrics/Sleep/SleepDetailView.swift
NoomSensorBio/Features/Metrics/Activity/ActivityDetailView.swift
NoomSensorBio/Features/Metrics/HeartRate/HeartRateDetailView.swift
NoomSensorBio/Features/Metrics/HRV/HRVDetailView.swift
NoomSensorBio/Features/Metrics/RespiratoryRate/RespiratoryRateDetailView.swift
```

### 4.5 Insights

Use SensorBio insights, but frame them as Noom coaching intelligence.

#### SDK sources

- `fetchNewInsights()`
- `fetchPopulationInsightsMetricList()`
- `fetchPopulationInsights(ageStart:ageEnd:gender:metricType:)`
- `submitInsightsFeedback(insightId:feedback:)`

#### UX sections

1. “What Noom noticed” — personal predictions/recommendations.
2. “What helped” — positive influencers.
3. “What got in the way” — negative influencers.
4. “Try this experiment” — suggested experiment.
5. “How you compare” — population comparison with careful privacy/clinical language.

#### Implementation files

```text
NoomSensorBio/Features/Insights/InsightsRepository.swift
NoomSensorBio/Features/Insights/InsightsViewModel.swift
NoomSensorBio/Features/Insights/InsightsView.swift
NoomSensorBio/Features/Insights/Components/InsightCard.swift
NoomSensorBio/Features/Insights/Components/InfluencerList.swift
NoomSensorBio/Features/Insights/Components/SuggestedExperimentCard.swift
NoomSensorBio/Features/Insights/Components/PopulationComparisonCard.swift
```

### 4.6 Recordings

SDK v0.4.0+ owns biometric, meditation, and activity recording orchestration end-to-end. Add recordings only after core dashboard/pairing are stable.

#### SDK sources

- `recordDetailedBiometrics(duration:minDuration:)`
- `recordMeditation(duration:minDuration:sessionName:sessionNameAlreadyExists:)`
- `recordActivity(activityName:minDuration:)`
- `finishCurrentRecording()`
- `pauseRecording()` / `resumeRecording()` for meditation/activity
- `activeRecording`
- `awaitActiveRecordingCompletion()`
- `cancelCurrentRecording()`
- `pendingSubmissionsPublisher`
- `reconcileSubmissions(against:)`
- `retrySubmission(localId:)`

#### UX

- Detailed biometric check-in: short guided “body check”.
- Meditation: calm Noom-branded session timer.
- Activity: open-ended recording with pause/resume.
- Pending submissions shown as optimistic cards in timeline.

#### Implementation files

```text
NoomSensorBio/Features/Recordings/RecordingService.swift
NoomSensorBio/Features/Recordings/RecordingViewModel.swift
NoomSensorBio/Features/Recordings/BiometricCheckInView.swift
NoomSensorBio/Features/Recordings/MeditationRecordingView.swift
NoomSensorBio/Features/Recordings/ActivityRecordingView.swift
NoomSensorBio/Features/Recordings/PendingSubmissionCard.swift
```

---

## 5. SDK Adapter Architecture

### 5.1 Why wrap the SDK

Do not call `sensorBio` directly from many views. The reference app does this for brevity; the white-label app needs testability, brand-specific language, analytics, and better failure handling.

### 5.2 Core adapter protocols

Create:

```text
NoomSensorBio/Core/SensorBio/SensorBioClient.swift
NoomSensorBio/Core/SensorBio/LiveSensorBioClient.swift
NoomSensorBio/Core/SensorBio/MockSensorBioClient.swift
NoomSensorBio/Core/SensorBio/SensorBioErrorMapper.swift
```

Protocol sketch:

```swift
protocol SensorBioClient: Sendable {
    var sessionPublisher: AnyPublisher<SB_Session?, Never> { get }
    var connectionPublisher: AnyPublisher<DeviceConnectionState, Never> { get }
    var syncPublisher: AnyPublisher<DeviceSyncState, Never> { get }

    func hydrateSession()
    func signIn(email: String, password: String) async throws -> AuthResult
    func signOut() async throws

    func fetchDashboard(date: Date, tzOffsetMinutes: Int32) async throws -> SB_DashboardData
    func fetchDailyRecovery(date: Date) async throws -> SB_DailyRecoveryTrending

    func startScan()
    func stopScan()
    func connectForPairing(deviceId: String)
    func persistPairedDevice(_ device: SB_DiscoveredDevice)
}
```

### 5.3 App domain models

Use app-owned domain models for UI state and map SDK types into them. This prevents SDK model churn from leaking through the UI.

```text
NoomSensorBio/Core/Models/BodyState.swift
NoomSensorBio/Core/Models/DeviceConnectionState.swift
NoomSensorBio/Core/Models/DeviceSyncState.swift
NoomSensorBio/Core/Models/MetricKind.swift
NoomSensorBio/Core/Models/MetricValue.swift
NoomSensorBio/Core/Models/NoomAction.swift
NoomSensorBio/Core/Models/TrendPoint.swift
```

Example:

```swift
struct BodyState: Equatable, Sendable {
    let date: Date
    let recoveryScore: Int?
    let label: BodyStateLabel
    let drivers: [BodyStateDriver]
    let recommendedAction: NoomAction?
    let dataFreshness: DataFreshness
}
```

### 5.4 View model policy

- View models are `@MainActor`.
- Async SDK calls are isolated in repositories/services.
- Combine subscriptions are held in service/view-model objects, not views, except small read-only UI components.
- Every network/BLE screen has loading, empty, permission, stale-data, and retry states.
- SDK logs are routed through app logging at launch.

---

## 6. Data, State, and Persistence

### 6.1 SDK-owned persistence

The SDK owns:

- Session keychain state.
- Paired-device state after `persistDeviceState`.
- Recording persistence and restore.
- Upload queue / pending submissions.

The app should not attempt to duplicate or wipe SDK persistence except through public APIs such as `signOut()`.

### 6.2 App-owned persistence

Use app storage for:

- Environment in debug/internal builds only.
- Onboarding completion flags.
- Last selected tab/date/granularity.
- User display preferences such as metric/imperial if not fully SDK-owned.
- Feature flags cached from app remote config if added later.

Suggested files:

```text
NoomSensorBio/Core/Persistence/AppPreferences.swift
NoomSensorBio/Core/Persistence/OnboardingStore.swift
NoomSensorBio/Core/Persistence/FeatureFlagStore.swift
```

### 6.3 Freshness rules

- Show sync state whenever `haveDevice == true`.
- For Today, refresh dashboard on `lastSyncd` changes only when selected date is today.
- Preserve the reference-app pattern of delayed post-sync refresh because server processing can lag BLE sync. Start with 30 seconds, then tune.
- Use `latestDeviceEpochInMillis` for diagnostics, not as the primary user-facing freshness label.

---

## 7. Folder Structure

Recommended new app structure under a new app target directory:

```text
/Users/anton/mobile_sensorbio_sdk_ios_binary/NoomSensorBio/
├── NoomSensorBio.xcodeproj or workspace-generated project files
├── Podfile
├── NoomSensorBio/
│   ├── App/
│   │   ├── NoomSensorBioApp.swift
│   │   ├── AppRootView.swift
│   │   ├── AppRouter.swift
│   │   └── AppEnvironment.swift
│   ├── Core/
│   │   ├── SensorBio/
│   │   ├── Models/
│   │   ├── Persistence/
│   │   ├── Logging/
│   │   └── Utilities/
│   ├── DesignSystem/
│   │   ├── Brand/
│   │   ├── Components/
│   │   ├── Charts/
│   │   ├── Layout/
│   │   └── Motion/
│   ├── Features/
│   │   ├── Auth/
│   │   ├── Onboarding/
│   │   ├── DevicePairing/
│   │   ├── Today/
│   │   ├── Trends/
│   │   ├── Metrics/
│   │   ├── Insights/
│   │   ├── Recordings/
│   │   └── Profile/
│   └── Resources/
│       ├── Assets.xcassets/
│       ├── Info.plist
│       └── Localizable.xcstrings
├── NoomSensorBioTests/
└── NoomSensorBioUITests/
```

Keep the existing `ExampleApp/` intact as a reference integration and regression comparison.

---

## 8. Build and Configuration Plan

### 8.1 Podfile

Create `/Users/anton/mobile_sensorbio_sdk_ios_binary/NoomSensorBio/Podfile`:

```ruby
platform :ios, '18.0'
inhibit_all_warnings!

target 'NoomSensorBio' do
  use_frameworks!

  pod 'SensorBioSDK', :path => '..'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']     = '18.0'
      config.build_settings['CLANG_CXX_LANGUAGE_STANDARD']    = 'c++17'
      config.build_settings['CLANG_CXX_LIBRARY']              = 'libc++'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
```

For a customer-style external app, replace `:path => '..'` with the pinned Git/tag pattern from `README.md` / `SDK_INTERFACE.md`.

### 8.2 Info.plist strings

Create Noom-specific copy:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Noom uses Bluetooth to connect to your Sensor Bio wearable and personalize your health insights in the background.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Noom uses Bluetooth to connect to your Sensor Bio wearable.</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

### 8.3 App startup

In `NoomSensorBioApp.swift`:

- Set `SB_SDK.environment` before the first RPC.
- Call `sensorBio.hydrateSession()` on startup.
- Subscribe `SB_SDK.log` to OSLog / app logger.
- Detect `sensorBio.activeRecording` and route to restored recording if needed.

---

## 9. Implementation Phases

### Phase 0 — Brand and project readiness

**Objective:** Unblock branding and make implementation deterministic.

**Tasks:**

1. Review generated `/docs/brand/noom-brand.md` and `/docs/brand/noom-brandfetch.raw.json`.
2. Confirm Brandfetch quality score and asset completeness remain acceptable.
3. Extract approved logos, colors, and fonts into a design-token checklist.
4. Confirm whether the app name is `Noom`, `Noom Sensor`, `Noom Body State`, or another approved white-label name.
5. Confirm bundle identifier, team ID, app group/keychain requirements, and environments.
6. Rotate the Brandfetch API key that was exposed in Telegram and update the `Brandfetch API Key` item in 1Password if needed.

**Verification:**

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary
test -s docs/brand/noom-brand.md
python - <<'PY'
from pathlib import Path
text = Path('docs/brand/noom-brand.md').read_text()
assert 'Brandfetch' in text or 'brandfetch' in text
assert 'Missing BRANDFETCH_API_KEY' not in text
print('brand.md ready')
PY
```

### Phase 1 — New app scaffold

**Objective:** Create a clean Noom host app that links SensorBioSDK.

**Tasks:**

1. Create `NoomSensorBio/` app target.
2. Add Podfile with required post-install settings.
3. Add Info.plist Bluetooth usage strings and background mode.
4. Add `NoomSensorBioApp.swift` startup configuration.
5. Add root routing for signed-out/signed-in states.
6. Wire SDK logging to OSLog.
7. Run `pod install`.
8. Build on arm64 simulator and real device.

**Verification:**

```bash
cd /Users/anton/mobile_sensorbio_sdk_ios_binary/NoomSensorBio
pod install
xcodebuild -workspace NoomSensorBio.xcworkspace \
  -scheme NoomSensorBio \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Expected: build succeeds; no C++17/library-evolution linkage errors.

### Phase 2 — Design system and Noom theme

**Objective:** Implement brand tokens and reusable premium health UI components.

**Tasks:**

1. Create `NoomBrandTokens.swift` from `docs/brand/noom-brand.md`.
2. Add color tokens with dark/adaptive support.
3. Add typography tokens from Brandfetch font data.
4. Add logo/app icon assets from Brandfetch URLs or approved downloaded assets.
5. Build base components:
   - `NoomCard`
   - `NoomScoreRing`
   - `MetricPill`
   - `InsightCard`
   - `DeviceStatusPill`
   - `PrimaryCTAButton`
   - `EmptyStateView`
   - `MetricTrendChart`
6. Add preview fixtures and accessibility checks.

**Verification:**

- Snapshot/previews render in light/dark mode.
- All text meets WCAG contrast targets.
- No placeholder or invented brand colors remain.

### Phase 3 — Auth and onboarding

**Objective:** Replace the reference app’s list-based auth with Noom-branded onboarding.

**Tasks:**

1. Implement `AuthService` using SDK auth methods.
2. Implement `AuthViewModel` with outcome mapping.
3. Build `WelcomeView`, `SignInView`, `CreateAccountView`.
4. Add agreement/profile completion gates.
5. Add Bluetooth education screen before pairing.
6. Add error copy for subscription-required/login-blocked states.

**Verification:**

- Unit test outcome mapping for all `SB_SignInOutcome` cases.
- XCUITest can navigate welcome → sign-in form.
- Manual staging sign-in routes to pairing or Today based on `haveDevice`.

### Phase 4 — Pairing ritual

**Objective:** Implement the complete SensorBio BLE pairing flow with Noom UX.

**Tasks:**

1. Port reference `PairDeviceState` logic into `PairDeviceViewModel`.
2. Add scanning timeout and troubleshooting states.
3. Add device-confirmation screen with LED/button instructions.
4. Persist paired device exactly using the SDK dictionary shape.
5. Add first-sync state and route to Today.
6. Add cancellation cleanup: stop scan, disconnect if needed, disable ask-for-device response.

**Verification:**

- Real device discovers wearable.
- Pairing connection event triggers LED blink.
- Button tap advances to success.
- `sensorBio.haveDevice` and `sensorBio.pairedDevice` update after `persistDeviceState`.
- App relaunch preserves paired device.

### Phase 5 — Today dashboard MVP

**Objective:** Ship the main value surface: today’s body state and next action.

**Tasks:**

1. Implement `TodayRepository` around `fetchDashboardData` and recovery detail.
2. Map SDK dashboard/recovery data into `BodyState`.
3. Build `TodayView` with hero score, metric cards, Noom action, device freshness.
4. Subscribe to sync state and refresh today after `lastSyncd` changes.
5. Add missing-data states for no paired device, no sync, stale sync, no metrics.
6. Add deep links to metric detail screens.

**Verification:**

- Unit tests cover body-state label thresholds.
- Mock data renders Today without SDK/network.
- Manual staging account loads dashboard.
- Post-sync refresh fires only for today.

### Phase 6 — Trends and metric details

**Objective:** Give users explanation-first access to sleep, activity, recovery, HR, HRV, and RR.

**Tasks:**

1. Implement shared `MetricDetailTemplate`.
2. Implement chart primitives for day/range data.
3. Port and redesign existing reference detail screens.
4. Add granularity picker: day/week/month/year.
5. Hide SpO2 behind feature flag because SDK marks it WIP.
6. Add copy blocks: “What it means,” “Why it matters,” “What you can try.”

**Verification:**

- Each detail screen has loading/error/empty states.
- Unit tests cover timestamp/date formatting; preserve reference `MetricFormatting` behavior for local-epoch timestamps.
- Manual checks for all granularity options.

### Phase 7 — Insights and coaching

**Objective:** Translate SDK insights into Noom-style coaching intelligence.

**Tasks:**

1. Implement `InsightsRepository` for personal/population endpoints.
2. Build insight cards with feedback affordances.
3. Add suggested experiment card.
4. Add population comparison filters.
5. Add privacy/clinical disclaimers.
6. Add analytics events for insight viewed/helpful/not helpful if analytics is approved.

**Verification:**

- Personal insights load and group correctly.
- Population filters fetch updated data.
- Feedback submission handles success/failure gracefully.

### Phase 8 — Recordings and timeline enhancement

**Objective:** Add active biometric check-ins, meditation, and activity capture.

**Tasks:**

1. Implement `RecordingService` over SDK recording orchestration.
2. Build biometric, meditation, and activity recording screens.
3. Handle pause/resume/finalize/cancel.
4. Restore active recordings on app relaunch using `activeRecording` and `awaitActiveRecordingCompletion()`.
5. Render pending submissions and retry failed submissions.
6. Reconcile submissions after workout timeline fetches.

**Verification:**

- Real device can start and finalize a biometric recording.
- App kill during recording restores correct state.
- Too-short/insufficient-data errors show user-friendly copy.

### Phase 9 — Profile, goals, settings, support

**Objective:** Complete account/device management.

**Tasks:**

1. Add user profile view.
2. Add goals view for steps/calories/sleep using `fetchGoals` / `updateGoals`.
3. Add device detail: connection, battery, firmware, charging, worn, last sync.
4. Add remove/re-pair flow using SDK methods.
5. Add support and troubleshooting entries.
6. Add debug diagnostics gated to internal builds.

**Verification:**

- Goals update handles all `SB_UpdateGoalsOutcome` cases.
- Sign-out disconnects device and clears SDK state.
- Device settings reflect live SDK published state.

### Phase 10 — QA, release hardening, and pilot readiness

**Objective:** Make the app safe for Noom pilot users.

**Tasks:**

1. Add unit tests for adapters, mappers, view models.
2. Add XCUITests for auth shell, pairing shell, Today shell with mocks.
3. Add real-device BLE test matrix.
4. Add accessibility audit.
5. Add privacy copy review.
6. Add crash/log redaction review.
7. Add App Store entitlement/capability checklist.
8. Run full regression against the existing `ExampleApp` when SDK versions change.

**Verification:**

- `xcodebuild test` passes for unit/UI tests.
- Manual BLE validation passes on at least two iPhone models and at least one supported SensorBio wearable model.
- No secrets in logs, screenshots, or committed docs.

---

## 10. Testing and QA Strategy

### 10.1 Unit tests

Target:

```text
NoomSensorBioTests/
```

Coverage:

- SDK outcome mappers.
- Body-state calculation and labels.
- Metric formatting.
- Device sync freshness.
- Pairing phase transitions with mocked SDK events.
- Insight grouping.
- Error copy mapping.

### 10.2 UI tests

Target:

```text
NoomSensorBioUITests/
```

Coverage:

- Signed-out navigation.
- Sign-in form validation.
- Pairing shell states with mocked client.
- Today dashboard rendering with fixture data.
- Metric detail navigation.
- Accessibility identifiers for major CTAs.

### 10.3 Real-device BLE validation

Simulator cannot validate BLE pairing and background sync. Use real devices.

Matrix:

- iPhone running iOS 18+.
- At least one additional iPhone model/OS minor version if available.
- SensorBio wearable models available to QA, including SensrV1 if expected in scan results.
- Foreground pairing.
- Background sync with app backgrounded.
- App kill/relaunch after pairing.
- Low battery / charging / not worn states.
- Bluetooth denied/re-enabled.
- Network unreachable during sync/upload.

Checklist:

- Bluetooth prompt displays Noom-specific copy.
- Scan finds devices within 30 seconds.
- LED blink and button confirmation work.
- Persisted device survives relaunch.
- Sync percent updates.
- Dashboard refreshes after sync.
- App does not suspend mid-sync when backgrounded.

### 10.4 Privacy, clinical, and copy QA

- No diagnostic claims from raw biometrics.
- Clearly separate coaching suggestions from medical advice.
- Add “not a medical device / not for diagnosis” copy if required by legal/regulatory review.
- Ensure population comparisons are non-shaming and privacy-safe.
- No secrets/API keys in Brandfetch outputs, app logs, or git history.

---

## 11. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---:|---|
| Brandfetch key exposed in Telegram | Credential leak / quota risk | Rotate the key in Brandfetch, then update the `Brandfetch API Key` item in 1Password. Generated files do not contain the key. |
| SDK binary cannot be modified | Limits skinning options | Build separate host app with adapters/design system; never touch `.xcframework`s. |
| BLE only testable on real devices | Pairing bugs escape simulator QA | Real-device BLE validation matrix is release-gating. |
| Missing Info.plist/background mode | Scan denied or sync drops in background | Add plist/capability checklist and automated plist test. |
| CocoaPods build flags omitted | C++/Swift library-evolution linkage failures | Keep required `post_install` block and CI build verification. |
| Server processing lags BLE sync | User sees stale dashboard immediately after sync | Use delayed post-sync refresh; communicate data freshness. |
| SpO2 marked WIP | Premature unsupported metric in UI | Hide behind feature flag until SDK/product confirms. |
| Noom clinical positioning sensitivity | Compliance/copy risk | Legal review for metric explanations, GLP-1/preventive-health language, and disclaimers. |
| Direct SDK calls spread through UI | Hard to test and rebrand | Enforce `SensorBioClient` adapter pattern. |
| Dark/premium UI harms accessibility | Low contrast/readability issues | WCAG contrast tests and dynamic type support. |

---

## 12. Acceptance Criteria

### 12.1 Brand readiness

- [x] `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/brand/noom-brand.md` is regenerated from Brandfetch and no longer contains the missing-key blocker.
- [x] `/Users/anton/mobile_sensorbio_sdk_ios_binary/docs/brand/noom-brandfetch.raw.json` exists for audit.
- [ ] Design tokens cite `docs/brand/noom-brand.md` and do not invent missing brand facts.

### 12.2 Build readiness

- [ ] New Noom app target exists under `/Users/anton/mobile_sensorbio_sdk_ios_binary/NoomSensorBio/`.
- [ ] Podfile includes `SensorBioSDK` and required post-install flags.
- [ ] Info.plist includes Bluetooth usage strings and `bluetooth-central`.
- [ ] App launches, hydrates SDK session, and routes based on auth/device state.

### 12.3 Product MVP

- [ ] User can sign in/create account and pass agreement gates.
- [ ] User can pair a SensorBio wearable through the full confirmation flow.
- [ ] Today dashboard shows body state, recovery/sleep/activity summaries, device freshness, and one Noom-style action.
- [ ] Trends screens cover recovery, sleep, activity, HR, HRV, and respiratory rate.
- [ ] Insights screen presents personal and population insights with Noom-style explanation.
- [ ] Profile includes account, goals, device, permissions, support, and sign-out.

### 12.4 QA readiness

- [ ] Unit tests pass for adapters/mappers/view models.
- [ ] UI tests pass for core navigation and mocked states.
- [ ] Real-device BLE pairing and background sync pass.
- [ ] Accessibility and privacy copy review pass.
- [ ] No secrets are exposed in docs, logs, or source.

---

## 13. Key Recommendation

Build the Noom white-label app as a **new SwiftUI host application with a Noom-specific design system and SensorBio adapter layer**, not as a modification of the SDK or the reference app. Treat the existing `ExampleApp` as integration proof and API reference, then create a premium Noom experience around today’s body state: guided pairing, a calm dashboard, explanation-first metrics, and coaching-oriented insights. Phase 0 must regenerate `docs/brand/noom-brand.md` from Brandfetch before final visual implementation begins.
