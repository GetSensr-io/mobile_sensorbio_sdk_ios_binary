# NoomPlus — Screen States

| State | Sleep hub behavior |
|---|---|
| Loading | Skeleton/progress state; no invented metrics |
| Fresh nightly detail | Show returned sleep score, duration, stages, and score factors; each section has an explicit drill-in |
| No sleep session | Explain overnight sync is required and link to band setup/reconnect |
| Partial detail | Show only returned fields and retain drill-ins; do not use zero as a substitute |
| Offline/stale | Label availability/freshness and preserve only SDK-returned cached data |

| State | Metric detail | Body Status behavior |
|---|---|---|
| Valid, fresh | 0–100 value, completed date, 30-day baseline/trend | Four inputs, 25% each, `Based on 4 of 4 available signals` |
| Valid, insufficient history | Value and completed date; baseline-building copy | Four inputs; coverage remains 4/4 |
| Missing / unavailable | Explicit **Unavailable**; no zero or placeholder score | Reweight valid inputs and show coverage, e.g. 3/4 |
| Stale / low confidence | Explain why excluded; no score presentation | Exclude signal; reweight valid inputs and show coverage |
| Loading | Progress label; no stale value implied | Preserve current unavailable/partial state until resolved |
| Offline | Explain that a real source is unavailable offline | Do not fabricate or cache a fresh state without an approved freshness rule |
| Debug preview | Clearly labeled **Preview sample** | May exercise 4/4 formula only in debug/preview route |

## Home empty and early-history states

| State | Home behavior |
|---|---|
| Metric absent, zero, negative, or non-finite | Show `—`, omit the unit, and use metric-specific waiting copy; never present a plausible zero |
| Sleep absent on Today | Show `—` and **Waiting for today's sleep data** |
| Sleep absent on a historical date | Show `—` and **No sleep data for this day** |
| Fewer than 3 unique weekly Sleep/Recovery dates | Hide the Home Progress preview entirely |
| At least 3 unique weekly Sleep/Recovery dates | Show **Progress**, count each returned date once across both streams, and leave missing dates blank |
| Debug empty-state preview | Use `dashboard_empty_tiles_preview`; keep the Inflammation Signal visibly labeled as sample input |

## Accessibility focus order

1. Metric title and selected date.
2. Value or explicit unavailable state.
3. Quality/freshness explanation.
4. Personal baseline context and chart description.
5. Body Status coverage and component rows.

## Recording states

| State | Spot check | Activity tracking |
|---|---|---|
| Ready, Band connected | 60-second purpose, stillness guidance, supported signals, one Start action | Activity choices from recent/featured SDK values, one Start action |
| Starting | Lock navigation ownership, show progress, offer Cancel start, and cancel the caller task if the view disappears before SDK leaves idle | Same; do not allow a second start or orphan the control context |
| Band unavailable | Keep experience visible; disable Start and route to Band setup/reconnect | Same; never pretend recording can start |
| Warming up | Countdown begins; PPG area says finding signal; metrics remain `—` until emitted | Timer begins; live HR remains `—` until emitted |
| Weak or missing signal | Keep the real waveform/metrics that exist, explain that the Band is still finding a usable signal, and gate Finish through `canFinalize` | Preserve elapsed time and controls; do not invent HR, HRV, or IBI values |
| Recording | Fixed progress/countdown, bounded PPG waveform, HR/HRV/IBI/RR/SpO₂/SNR when emitted | Large count-up timer, live HR hierarchy, bounded HR trend, HRV/IBI/SNR secondary |
| Paused | Not exposed for detailed biometrics | Freeze elapsed state from SDK, label **Paused**, make Resume primary and Finish secondary |
| Too short | Finish remains disabled until SDK `canFinalize`; early cancellation is explicit | Same minimum-duration gate |
| Finalizing | Stopping capture → syncing Band → saving session | Same, driven by `SB_RecordingFinalizationPhase` |
| Saved | Confirm local session was saved and queued; disclose processing continues securely | Show actual captured duration and last emitted values, not a fabricated workout analysis |
| Failed | Friendly, cause-specific recovery; never raw SDK error text | Same; retry starts only a new recording |
| Restored after relaunch | Route to persisted biometrics and await SDK completion | Preserve the exact activity name, elapsed time, pause state, and await SDK completion |
| Restored unsupported kind | Keep meditation or unknown SDK-owned sessions separate; show elapsed/finalizing state and cancel only | Never coerce an unsupported kind into Activity tracking |
| Cancel confirmation | Cancel only the caller task for fresh capture, or call the explicit restored-session SDK cancel; hide controls and wait for SDK idle before enabling Start | Same |

## Recording accessibility focus order

1. Current experience and Band connection state.
2. Recording state and elapsed/remaining time.
3. Live signal summary; charts expose one concise VoiceOver description rather than every point.
4. Primary action (Start, Pause/Resume, or Finish).
5. Secondary cancel/end action and minimum-duration explanation.

No recording state uses disease, diagnosis, risk, treatment, ECG language for PPG, or invented health values.
