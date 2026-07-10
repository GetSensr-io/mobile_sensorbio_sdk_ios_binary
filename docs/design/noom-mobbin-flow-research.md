# Noom + Best-in-Class Wearable/Health Mobbin Flow Research

Owner phase: creative (research only, no product code touched)
Scope: reference research for improving NoomApp flows and biometric detail
screens. This is pattern inspiration, not a license to clone Noom's or any
competitor's proprietary artwork, copy, or brand assets 1:1.

Constraint honored: no Sensor Bio private source or credentials were
accessed in this phase. All screens below are public Mobbin catalog
entries.

---

## 1. Method

Searched Mobbin (iOS platform) across two axes:

1. Noom-specific flows and screens (onboarding, home, coaching, settings).
2. Best-in-class wearable/health apps for biometric detail-page patterns:
   Apple Health/Fitness, Oura, WHOOP, Fitbit, Ultrahuman, Eight Sleep,
   Google Fit, MyFitnessPal, Gentler Streak.

Every entry below has its Mobbin URL. Mobbin's MCP surface returns flow-
and screen-level metadata plus preview images; it does not expose a bulk
screenshot export endpoint in this environment, so no image files were
exported to disk. Treat the Mobbin URLs as the canonical reference link
for anyone who needs to re-open the exact screen.

---

## 2. Noom flows inventory

| Flow | Screens | Mobbin URL |
|---|---|---|
| Completing a welcome quiz | 14 | https://mobbin.com/flows/811a1670-32be-4e0d-9d4c-02962bd28832 |
| Onboarding (create account + onboarding) | 15 | https://mobbin.com/flows/47ec5a0a-bd4f-4e63-a4ee-3a09bf782478 |
| Completing today's courses | 38 | https://mobbin.com/flows/d9b418b9-fd9b-4c6a-9a27-8b3c90d40a01 |
| First Noom course | 14 | https://mobbin.com/flows/f8762773-abd0-4757-ba6c-522cdd2f3705 |
| Demographic profile | 11 | https://mobbin.com/flows/80d90a90-8a38-4ac1-a2e9-54d9e3f84799 |

Additional standalone Noom screens surfaced by targeted queries (home/
dashboard, settings/profile, empty/error state candidates):

| Topic | Screen id | Mobbin URL |
|---|---|---|
| Home/dashboard candidate | a617cbce-d0e0-4f6f-a2e1-3c74a6065931 | https://mobbin.com/screens/a617cbce-d0e0-4f6f-a2e1-3c74a6065931 |
| Home/dashboard candidate | 69f9c13e-1c53-4b43-9ae0-89271b2ba7f5 | https://mobbin.com/screens/69f9c13e-1c53-4b43-9ae0-89271b2ba7f5 |
| Home/dashboard candidate | 56afe3fb-b927-4b7d-92f8-3061023d5512 | https://mobbin.com/screens/56afe3fb-b927-4b7d-92f8-3061023d5512 |
| Home/dashboard candidate | 1911beba-9d3e-4220-8bb0-04111a2d8592 | https://mobbin.com/screens/1911beba-9d3e-4220-8bb0-04111a2d8592 |
| Progress/weight trend | a66e996e-1ee8-4e03-8d00-dd1840b3a887 | https://mobbin.com/screens/a66e996e-1ee8-4e03-8d00-dd1840b3a887 |
| Progress/weight trend | 4dc59bfb-23b6-4ac6-8a50-d5c8e525f9b3 | https://mobbin.com/screens/4dc59bfb-23b6-4ac6-8a50-d5c8e525f9b3 |
| Course completion / streak state | 020e6f8b-7ba3-4a7e-b21e-ebc316dab160 | https://mobbin.com/screens/020e6f8b-7ba3-4a7e-b21e-ebc316dab160 |
| Settings/profile | 34c750be-5776-4eed-bba6-274a374f0958 | https://mobbin.com/screens/34c750be-5776-4eed-bba6-274a374f0958 |
| Settings/profile | da39bd4c-938e-444c-a10b-95b6044f935a | https://mobbin.com/screens/da39bd4c-938e-444c-a10b-95b6044f935a |
| Settings/profile | b1602c15-33b7-4fa9-9125-23d54f6ee358 | https://mobbin.com/screens/b1602c15-33b7-4fa9-9125-23d54f6ee358 |
| Settings/profile | dc9d6481-9ca7-4307-88bb-8009b9ba0d4a | https://mobbin.com/screens/dc9d6481-9ca7-4307-88bb-8009b9ba0d4a |
| Settings/profile | e5b37c6e-8076-4288-8460-8a11da26abdc | https://mobbin.com/screens/e5b37c6e-8076-4288-8460-8a11da26abdc |
| Settings/profile | efe1998c-35e6-452b-a0d6-6f4bec061aef | https://mobbin.com/screens/efe1998c-35e6-452b-a0d6-6f4bec061aef |
| Habit/streak nudge (possible empty/stale analog) | 9cd863ef-b37d-4829-9b71-88f7455f4edd | https://mobbin.com/screens/9cd863ef-b37d-4829-9b71-88f7455f4edd |

Note: Mobbin's Noom catalog is weighted toward onboarding and course/
coaching flows; it does not have deep coverage of true empty/loading/
error states or device pairing (Noom's core loop doesn't pair a wearable
directly), so those patterns are pulled from Apple Health, Oura, WHOOP,
Fitbit and Ultrahuman below.

### 2a. Onboarding/auth pattern takeaways (Noom)
- Welcome quiz uses one question per screen with immediate visual
  feedback (illustration changes per answer), progress indicator at top,
  and a single primary CTA per screen — never two competing CTAs.
- Onboarding flow interleaves value-prop screens between data-collection
  steps (goal, age, sex, height/weight) to keep motivation up during a
  long form.
- Demographic profile flow groups related fields (activity level, meal
  pattern) into short single-purpose screens rather than one long form.

### 2b. Coaching/habit takeaways
- "Completing today's courses" (38 screens) shows a card-based daily
  task list on a home screen, each card showing state (locked/available/
  done), with course completion ending in a lightweight congratulatory
  screen plus streak counter, not a heavy modal.

---

## 3. Best-in-class biometric detail screens (cross-app)

| Metric focus | App | Screen id | Mobbin URL |
|---|---|---|---|
| HRV detail | Oura | f1e3a074-87db-4094-98a0-a328c8d403ec | https://mobbin.com/screens/f1e3a074-87db-4094-98a0-a328c8d403ec |
| HRV/readiness detail | Gentler Streak | 9358f142-108a-493f-834d-2d02de575174 | https://mobbin.com/screens/9358f142-108a-493f-834d-2d02de575174 |
| HRV detail | Ultrahuman | 8e7fedb4-8b6a-4723-b84f-ab33aa2d16eb | https://mobbin.com/screens/8e7fedb4-8b6a-4723-b84f-ab33aa2d16eb |
| HRV/sleep detail | Oura | 8e72bedf-7cca-494d-916e-ab662e23e6ec | https://mobbin.com/screens/8e72bedf-7cca-494d-916e-ab662e23e6ec |
| HRV detail | Fitbit | 21890303-2c55-4e1b-aa9b-1dc3c414926d | https://mobbin.com/screens/21890303-2c55-4e1b-aa9b-1dc3c414926d |
| HRV detail | Ultrahuman | b9a11036-827a-4e10-84ba-442f51045344 | https://mobbin.com/screens/b9a11036-827a-4e10-84ba-442f51045344 |
| Sleep/recovery detail | Bevel | c4c2dd72-1d95-431b-898f-ad415b4f5c39 | https://mobbin.com/screens/c4c2dd72-1d95-431b-898f-ad415b4f5c39 |
| Sleep/recovery detail | Oura | 43477a06-2c84-40d6-abd7-431d2b236c2d | https://mobbin.com/screens/43477a06-2c84-40d6-abd7-431d2b236c2d |
| Recovery/readiness | Ultrahuman | b1321729-e1fc-44d3-b9ab-ba94a2941ebd | https://mobbin.com/screens/b1321729-e1fc-44d3-b9ab-ba94a2941ebd |
| Recovery detail | WHOOP | f91de068-fb36-4d69-a8d0-5c5b77404fb0 | https://mobbin.com/screens/f91de068-fb36-4d69-a8d0-5c5b77404fb0 |
| Sleep detail | Eight Sleep | 752cd0a8-8a8b-4d09-a116-4e0cab9f18c4 | https://mobbin.com/screens/752cd0a8-8a8b-4d09-a116-4e0cab9f18c4 |
| Sleep stages detail | Eight Sleep | 1950371b-dbdc-4144-a424-049b44c06602 | https://mobbin.com/screens/1950371b-dbdc-4144-a424-049b44c06602 |
| Sleep score detail | Oura | ba155f65-c5ce-4e60-996d-1182d0fd3845 | https://mobbin.com/screens/ba155f65-c5ce-4e60-996d-1182d0fd3845 |
| Resting HR trend | Apple Health | 733d1e46-221f-4ac0-b188-4215a8513a8b | https://mobbin.com/screens/733d1e46-221f-4ac0-b188-4215a8513a8b |
| HR detail w/ range picker | Apple Health | 65dbe9fb-db0e-4e7a-ad53-e6c334fde23c | https://mobbin.com/screens/65dbe9fb-db0e-4e7a-ad53-e6c334fde23c |
| HR detail w/ range picker | Apple Health | 92cf868c-3d1c-434b-aba1-ea52a196e03a | https://mobbin.com/screens/92cf868c-3d1c-434b-aba1-ea52a196e03a |
| Device sync/pairing status | Oura | dba74111-f472-4298-8de7-754c4dc6fe03 | https://mobbin.com/screens/dba74111-f472-4298-8de7-754c4dc6fe03 |
| Device pairing (watch) | Apple Watch | d459aeb4-34ee-4b37-9e53-eded643e2521 | https://mobbin.com/screens/d459aeb4-34ee-4b37-9e53-eded643e2521 |
| Device pairing/status | WHOOP | df1f6948-28d0-4762-89fb-5ca2ce1ee56d | https://mobbin.com/screens/df1f6948-28d0-4762-89fb-5ca2ce1ee56d |
| Device pairing/status | Fitbit | fca8e9f3-7f94-4942-a8f3-8930d0664e70 | https://mobbin.com/screens/fca8e9f3-7f94-4942-a8f3-8930d0664e70 |
| Device pairing/status | Fitbit | 21e5ba5f-adad-4cf0-b414-7af10416f243 | https://mobbin.com/screens/21e5ba5f-adad-4cf0-b414-7af10416f243 |
| Device pairing/status | WHOOP | 7a95bd3d-ab09-43e9-bd5d-4d7cbd5b9d18 | https://mobbin.com/screens/7a95bd3d-ab09-43e9-bd5d-4d7cbd5b9d18 |
| Steps/activity detail | Google Fit | 33f47968-e0ac-4111-b5b0-a9ad871f2727 | https://mobbin.com/screens/33f47968-e0ac-4111-b5b0-a9ad871f2727 |
| Steps/activity ring detail | Apple Fitness | 17983edf-6073-47c5-b072-270002fce54e | https://mobbin.com/screens/17983edf-6073-47c5-b072-270002fce54e |
| Calories detail | MyFitnessPal | d5384da7-036e-4ed6-94d6-36e5a35a2f8a | https://mobbin.com/screens/d5384da7-036e-4ed6-94d6-36e5a35a2f8a |
| Calories detail | Yazio | 5090bdec-34c7-4872-9931-d825286d9bfd | https://mobbin.com/screens/5090bdec-34c7-4872-9931-d825286d9bfd |
| Activity detail | Google Fit | 7e924261-2c27-4453-b9ca-43ff67a60c4e | https://mobbin.com/screens/7e924261-2c27-4453-b9ca-43ff67a60c4e |
| Sleep/recovery detail | Oura | c8eceb02-6db4-4cfd-9a46-e1ed8fa90e0a | https://mobbin.com/screens/c8eceb02-6db4-4cfd-9a46-e1ed8fa90e0a |
| Calories/nutrition detail | MyFitnessPal | fa5def3b-6ab8-44e4-b535-d59000a48a06 | https://mobbin.com/screens/fa5def3b-6ab8-44e4-b535-d59000a48a06 |

No dedicated empty/error/offline-state screen for a wearable metric
surfaced from targeted Mobbin queries in this pass (queries mostly
returned generic app empty states unrelated to biometrics — Google Fit,
Headspace, Acorns, Messenger, adidas). Mobbin's catalog does not appear
to index granular error/offline states as their own tagged category for
health apps. Treat section 4's empty/error guidance as informed by the
loading/date-range/data-gap patterns visible inside the detail screens
above (e.g. Apple Health and Oura both show a distinct dimmed/placeholder
bar style when a day has no data) rather than as a separate exact-match
screen citation.

---

## 4. Biometric detail page pattern definition

For each dimension below, "source" cites which app screen(s) demonstrate
it well. This defines the target pattern for NoomApp's own metric detail
views (HRDetailView, HRVDetailView, RRDetailView, StepsDetailView,
CaloriesDetailView, SleepDetailView, RecoveryDetailView). No clinical
ranges or causal language are asserted anywhere in this brief; all
range/context values must come from the SDK/backend, never computed
client-side.

1. **Information hierarchy** — big number (current/latest value + unit)
   at the top, metric name as a small eyebrow above it, secondary context
   (e.g. "as of 6:42 AM" or last-sync time) directly under the number.
   Source: Apple Health HR detail (92cf868c…), Oura HRV (f1e3a074…).

2. **Current value + unit** — always shown with the unit inline (bpm, ms,
   breaths/min, steps, kcal, hrs), never a bare number. Source: Apple
   Health, Oura, WHOOP screens above.

3. **Time range / date navigation** — segmented control (D / W / M / 6M /
   Y) or simple back/forward day arrows; Apple Health uses the segmented-
   range pattern, Oura/WHOOP use a horizontal day-scroller with the
   current day centered. Either pattern is acceptable; segmented control
   scales better if NoomApp needs consistent range selection across all
   seven metrics.

4. **Chart style and interaction** — line chart for continuous trend
   (HR, HRV, RHR over time), bar chart for discrete daily totals (steps,
   calories), stacked/segmented bar for composition (sleep stages).
   Charts are tappable/scrubbable: tapping a point updates the header
   value + timestamp instead of opening a new screen. Source: Apple
   Health HR/RHR (65dbe9fb…, 733d1e46…), Eight Sleep sleep stages
   (1950371b…), Oura sleep score (ba155f65…).

5. **Baseline / range / context** — shown as a shaded band behind the
   trend line (Oura, WHOOP) or a caption line under the chart. Any
   range/band value must be backend-supplied per the parent implementation
   task's constraint — never computed on-device.

6. **Trend comparison** — small delta chip ("+3 vs last week") near the
   header value, sourced from backend, not calculated in-app. Source:
   Ultrahuman HRV/recovery screens (8e7fedb4…, b1321729…).

7. **Provenance / freshness / coverage** — a persistent small-caption row
   showing device name/source and "last synced" timestamp; when data is
   stale, that same caption should flip to a warning tone rather than
   introducing a separate banner. Source: Oura sync/status (dba74111…),
   Apple Watch pairing (d459aeb4…).

8. **Trend/related metrics** — a "related" or "see also" row below the
   chart linking to adjacent metrics (e.g. HRV detail links to Sleep and
   Recovery). Source: Oura and WHOOP detail screens consistently cross-
   link recovery/sleep/HRV.

9. **Explanatory copy** — one to two sentences under the chart explaining
   what the metric is in plain language, no medical claims. Source: Apple
   Health's metric definitions, Gentler Streak's plain-language HRV blurb
   (9358f142…).

10. **Loading / empty / stale / offline / error states** — pattern
    synthesized from the detail screens' placeholder treatment (dimmed
    bars for no-data days in Apple Health/Oura) plus general product
    conventions, since Mobbin does not carry a dedicated tagged category
    for these states in health apps:
    - Loading: skeleton shimmer over the same layout (big number
      placeholder + chart placeholder), never a blocking spinner.
    - Empty (no data ever recorded): replace chart with a short
      illustration + one line: "No {metric} data yet" + a CTA if pairing
      is the likely fix ("Pair your Noom Band").
    - Stale (data exists but is old): keep last known value, but the
      freshness caption switches to a warning color and text
      ("Last synced 3 days ago").
    - Offline (SDK/backend unreachable): banner at top of the same
      screen, chart area shows last cached value dimmed, retry action
      available.
    - Error (backend returned an error): inline message where the chart
      would be, plus a retry button; never fail silently.

11. **Accessibility** — Dynamic Type support on the header value and all
    body text; charts need a VoiceOver-accessible summary string (e.g.
    "Average HRV this week 52 milliseconds, up 4 from last week") rather
    than relying on visual-only chart marks; range-selector segmented
    control needs full VoiceOver labels per segment.

---

## 5. Screen inventory / matrix

| # | Pattern area | Reference app(s) | Mobbin URL(s) | NoomApp route affected |
|---|---|---|---|---|
| 1 | Onboarding value-prop interleave | Noom (Onboarding flow) | https://mobbin.com/flows/47ec5a0a-bd4f-4e63-a4ee-3a09bf782478 | SignUpView.swift, SignUpFormState.swift |
| 2 | Single-question-per-screen quiz | Noom (Welcome quiz) | https://mobbin.com/flows/811a1670-32be-4e0d-9d4c-02962bd28832 | SignUpView.swift |
| 3 | Card-based daily task list home | Noom (Completing today's courses) | https://mobbin.com/flows/d9b418b9-fd9b-4c6a-9a27-8b3c90d40a01 | DashboardView.swift, DashboardState.swift |
| 4 | Settings/profile grouping | Noom settings screens | https://mobbin.com/screens/34c750be-5776-4eed-bba6-274a374f0958 (+5 more, section 2) | ProfileView.swift |
| 5 | HR detail: value+unit, range picker, trend chart | Apple Health, Oura | https://mobbin.com/screens/92cf868c-3d1c-434b-aba1-ea52a196e03a, https://mobbin.com/screens/f1e3a074-87db-4094-98a0-a328c8d403ec | HRDetailView.swift |
| 6 | RHR detail w/ date nav | Apple Health | https://mobbin.com/screens/733d1e46-221f-4ac0-b188-4215a8513a8b | HRDetailView.swift (RHR sub-state, if present) |
| 7 | HRV detail: baseline band, delta chip, explanatory copy | Oura, Ultrahuman, Gentler Streak | https://mobbin.com/screens/f1e3a074-87db-4094-98a0-a328c8d403ec, https://mobbin.com/screens/8e7fedb4-8b6a-4723-b84f-ab33aa2d16eb, https://mobbin.com/screens/9358f142-108a-493f-834d-2d02de575174 | HRVDetailView.swift |
| 8 | Respiratory rate — no direct Mobbin match found; use HRV/HR layout as base | n/a (pattern extrapolated) | n/a | RRDetailView.swift |
| 9 | Steps/activity ring detail | Google Fit, Apple Fitness | https://mobbin.com/screens/33f47968-e0ac-4111-b5b0-a9ad871f2727, https://mobbin.com/screens/17983edf-6073-47c5-b072-270002fce54e | StepsDetailView.swift |
| 10 | Calories detail | MyFitnessPal, Yazio | https://mobbin.com/screens/d5384da7-036e-4ed6-94d6-36e5a35a2f8a, https://mobbin.com/screens/5090bdec-34c7-4872-9931-d825286d9bfd | CaloriesDetailView.swift |
| 11 | Sleep stages + score detail | Eight Sleep, Oura | https://mobbin.com/screens/1950371b-dbdc-4144-a424-049b44c06602, https://mobbin.com/screens/ba155f65-c5ce-4e60-996d-1182d0fd3845 | SleepDetailView.swift |
| 12 | Recovery/readiness detail | WHOOP, Ultrahuman, Bevel | https://mobbin.com/screens/f91de068-fb36-4d69-a8d0-5c5b77404fb0, https://mobbin.com/screens/b1321729-e1fc-44d3-b9ab-ba94a2941ebd, https://mobbin.com/screens/c4c2dd72-1d95-431b-898f-ad415b4f5c39 | RecoveryDetailView.swift |
| 13 | Device pairing/sync status | Oura, Apple Watch, WHOOP, Fitbit | https://mobbin.com/screens/dba74111-f472-4298-8de7-754c4dc6fe03, https://mobbin.com/screens/d459aeb4-34ee-4b37-9e53-eded643e2521, https://mobbin.com/screens/df1f6948-28d0-4762-89fb-5ca2ce1ee56d | PairDeviceView.swift, PairDeviceState.swift, NoomBandConnectionState.swift |
| 14 | Empty/stale/offline treatment (synthesized, see section 4.10) | Apple Health, Oura (placeholder bars) | https://mobbin.com/screens/65dbe9fb-db0e-4e7a-ad53-e6c334fde23c, https://mobbin.com/screens/dba74111-f472-4298-8de7-754c4dc6fe03 | All *DetailView.swift files |
| 15 | Insights/related-metrics cross-linking | Oura, WHOOP (cross-linking convention across their detail screens) | https://mobbin.com/screens/b1321729-e1fc-44d3-b9ab-ba94a2941ebd | InsightsView.swift, InsightsState.swift |

---

## 6. Prioritized change list (mapped to existing NoomApp routes)

Priority 1 (biometric detail consistency — highest leverage, touches all
seven metric views):
1. Standardize header block across HRDetailView, HRVDetailView,
   RRDetailView, StepsDetailView, CaloriesDetailView, SleepDetailView,
   RecoveryDetailView: eyebrow label, big value+unit, freshness caption.
2. Add a shared date/range navigation component (segmented D/W/M/6M/Y or
   day-scroller) reused across all seven detail views instead of each
   view rolling its own.
3. Add the loading/empty/stale/offline/error state matrix (section 4.10)
   to each detail view — omit or explain missing SDK data rather than
   fabricating it, consistent with the parent implementation task's
   constraint.

Priority 2 (chart and context quality):
4. Add baseline/range shading and trend delta chip to HRVDetailView,
   RecoveryDetailView, SleepDetailView where backend supplies baseline
   data; do not compute client-side.
5. Add tap-to-scrub interaction on trend charts (HR, HRV, RHR) that
   updates header value/timestamp instead of navigating away.
6. Add "related metrics" cross-link row at the bottom of each detail view
   surfaced through InsightsView/InsightsState.

Priority 3 (device pairing/status truth):
7. Apply the Oura/WHOOP/Fitbit sync-status pattern to PairDeviceView +
   NoomBandConnectionState: persistent last-synced caption with
   warning-tone flip when stale, distinguishing "paired" vs
   "live-connected" clearly (per parent task's requirement to preserve
   that distinction).

Priority 4 (dashboard/home hierarchy):
8. Apply Noom's card-based daily task list pattern to DashboardView /
   DashboardState for whatever product-loop cards exist today (habit/
   experiment cards), keeping locked/available/done states visually
   distinct.

Priority 5 (settings/profile and onboarding polish):
9. Group ProfileView settings rows to match Noom's settings screen
   grouping (account, device, notifications, legal) if not already
   grouped that way.
10. Apply Noom's single-question-per-screen and interleaved value-prop
    pattern to SignUpView/SignUpFormState if onboarding currently uses
    long multi-field forms.

---

## 7. Explicit non-goals / guardrails carried forward

- Do not clone Noom's or any competitor's illustration style, iconography,
  or copy verbatim — patterns only.
- Do not invent clinical ranges, composite scores, or causal claims for
  any metric; every range/baseline/trend value must come from the
  SDK/backend.
- Respiratory rate had no strong direct Mobbin reference; the
  implementation phase should reuse the HR/HRV layout skeleton rather
  than inventing new chart conventions for it.
- This document does not include exported screenshots — Mobbin's MCP
  surface in this environment returns inline preview images and
  metadata, not a bulk-export function; the Mobbin URLs above are the
  durable reference for anyone who needs to re-open the exact screen.
