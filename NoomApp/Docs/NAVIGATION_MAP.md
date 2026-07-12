# NoomPlus — Navigation Map

```text
Sleep tab
  ├─ Sleep & Recovery hub — latest SDK sync summary, stage preview, returned factors
  │    ├─ Open sleep details → SleepDetailView
  │    └─ Open recovery details → RecoveryDetailView

Dashboard / Home tab
  ├─ Floating recording action (bottom-right)
  │    └─ Recording hub
  │         ├─ Spot check
  │         │    ├─ Calm setup and supported-signal explanation
  │         │    ├─ 60-second live PPG + biometrics capture
  │         │    └─ Saved / queued-for-processing confirmation
  │         └─ Activity tracking
  │              ├─ Recent / featured activity selection
  │              ├─ Open-ended live duration + HR trend
  │              ├─ Pause / Resume / Finish
  │              └─ Saved / queued-for-processing confirmation
  ├─ Body Status
  │    └─ Input rows
  │         ├─ Resting HR
  │         ├─ Nocturnal HRV
  │         ├─ Sleep score
  │         └─ Inflammation signal → InflammationSignalDetailView
  └─ Metrics
       └─ Inflammation signal → InflammationSignalDetailView

Debug preview only
  └─ inflammation_preview route
       ├─ mock completed-date score
       ├─ mock 30-day baseline
       └─ Body Status v2 with 4/4 coverage
```

The production route may show the detail screen, but must show **Unavailable** and no fabricated metric value until a real source is integrated.
