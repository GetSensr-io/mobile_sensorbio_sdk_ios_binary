# Noom Inflammation Signal POC — Screen States

| State | Metric detail | Body Status behavior |
|---|---|---|
| Valid, fresh | 0–100 value, completed date, 30-day baseline/trend | Four inputs, 25% each, `Based on 4 of 4 available signals` |
| Valid, insufficient history | Value and completed date; baseline-building copy | Four inputs; coverage remains 4/4 |
| Missing / unavailable | Explicit **Unavailable**; no zero or placeholder score | Reweight valid inputs and show coverage, e.g. 3/4 |
| Stale / low confidence | Explain why excluded; no score presentation | Exclude signal; reweight valid inputs and show coverage |
| Loading | Progress label; no stale value implied | Preserve current unavailable/partial state until resolved |
| Offline | Explain that a real source is unavailable offline | Do not fabricate or cache a fresh state without an approved freshness rule |
| Debug preview | Clearly labeled **Preview sample** | May exercise 4/4 formula only in debug/preview route |

## Accessibility focus order

1. Metric title and selected date.
2. Value or explicit unavailable state.
3. Quality/freshness explanation.
4. Personal baseline context and chart description.
5. Body Status coverage and component rows.

No state uses disease, diagnosis, risk, or treatment language.
