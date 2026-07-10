# Noom Mobile White Label Mockups

## What this contains

This directory contains a self-contained HTML contact sheet for a Noom-only, white-label mobile app concept. It includes six iPhone-style screens:

1. Today / Weight Care Plan
2. Noom Band setup
3. GLP-1 Check-in
4. Sleep & Recovery
5. Progress Signals
6. Coach Plan

Primary artifact:

- `index.html`

Exported screenshots:

- `screenshots/contact-sheet.png`
- `screenshots/screen-01-today-weight-care.png`
- `screenshots/screen-02-noom-band-setup.png`
- `screenshots/screen-03-glp1-check-in.png`
- `screenshots/screen-04-sleep-recovery.png`
- `screenshots/screen-05-progress-signals.png`
- `screenshots/screen-06-coach-plan.png`

## Official logo source

The mockups use the official Noom Brandfetch logo from `docs/brand/noom-brandfetch.raw.json`, selected from the transparent light theme SVG logo entry:

- Brandfetch asset URL: `https://cdn.brandfetch.io/id8j69r4Jm/theme/light/logo.svg?c=1bxu9k3zjvo9600ztpa87cveybpqHggSGwB`
- Local copied artifact: `assets/noom-logo-brandfetch.svg`

The HTML uses the local SVG file so the contact sheet and screenshot export work offline. The local SVG preserves the official Brandfetch wordmark path and overrides only the artwork fill to Noom black `#191717`. Every visible logo sits on a white rounded logo plate so the mark reads as black on white. No logo was recreated with styled text.

## Noom research sources used

Research was kept to current Noom sources and translated into product-safe UI copy:

- Noom homepage: https://www.noom.com/
  - Positioning: lose weight and keep it off, psychology-based weight loss, Noom Med, GLP-1 Companion, habit tracking, coaching, biology plus psychology.
- Noom Med: https://www.noom.com/med/
  - Positioning: medication plus tailored support, clinician access, GLP-1 Companion, progress tools, muscle defense, lifestyle support paired with medication.
- Noom 4-Cs article: https://www.noom.com/health/resources/blog/unlocking-lasting-change-how-nooms-4-cs-drive-better-engagement-and-outcomes/
  - Positioning: clinicians, coaching, community, and content as behavior-change support, including nutrition, movement, sleep, stress, and GLP-1 Companion support.
- Noom Research: https://www.noom.com/research/
  - Positioning: science-grounded behavior change and peer-reviewed research.
- Local brand source: `docs/brand/noom-brand.md`
  - Brand tokens, voice, typography, product context, and Brandfetch logo table.

## White-label rule and naming

The app UI is fully Noom-only. User-facing screen copy does not name the source integration, does not include SDK language, and does not expose implementation terms. The wearable is named exactly `Noom Band` throughout the app screens.

## Design stance

The direction is a premium Noom weight-care companion rather than a raw wearable dashboard. It focuses on:

- Daily body state in plain language.
- A Noom Weight Care Plan with one next habit action.
- GLP-1 check-ins that track appetite, fullness, nausea, energy, and care-team ready notes without medication dosing guidance.
- Sleep and recovery explanations that connect to hunger, cravings, and movement readiness.
- Progress shown as trends and supportive signals, not judgment or diagnosis.
- Coach-led tiny steps across nutrition, activity, and sleep.

Medical care language is deliberately careful. The screens avoid dosing instructions, medication promises, diagnosis, and hard outcome claims.

## Brand token mapping

Source of truth: `docs/brand/noom-brand.md`.

- Noom red `#FB513B`: primary actions, selected states, score emphasis, and GLP-1 support highlights.
- Warm surface `#F6F4EE`: mobile background and contact sheet base for a lower-pressure health experience.
- Deep teal ink `#1D3A44`: text, phone shell, structure, and clinical calm.
- Typography: Brandfetch lists `Untitled Sans Web Regular` and `Untitled Serif Web Regular`. A live Noom.com spot check showed Noom serving `Untitled Sans`, `Untitled Serif`, and `BrownLLWeb`, with body copy in Untitled Sans, headings in Untitled Serif, and labels/buttons in BrownLLWeb. The artifact uses local copies of those Noom-hosted web fonts under `assets/fonts/` for offline screenshot export, then falls back to close system fonts if the files are unavailable.
- Voice: confident, measured, empowering, factual.

## Mobbin pattern usage

The references were transformed into product patterns rather than copied layouts:

- Oura: calm daily readiness hierarchy, score storytelling, low-anxiety cards.
- Superpower: premium health intelligence framing and grouped signals.
- WHOOP: daily coaching loop and decision support.
- Adjacent health and lab apps: explain-before-detail, clear ranges, clinical caveats, and no spreadsheet UI.

No proprietary competitor screens, exact layouts, or branded components were cloned.

## Tradeoffs

- The HTML is static and self-contained for quick product and design review.
- Metrics are plausible placeholder product data and should be replaced with approved fixtures before client review.
- The mockups use a light theme only to match Noom warmth and keep the contact sheet cohesive.
- White-label source integration details are intentionally omitted from visible app UI.
