# Noom Inflammation Signal POC — Navigation Map

```text
Dashboard
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
