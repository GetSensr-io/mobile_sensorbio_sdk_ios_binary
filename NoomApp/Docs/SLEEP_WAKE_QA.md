# Noom+ Sleep Wake-Up Physical Acceptance

**Status:** Required before physical-device or TestFlight-ready sleep claims
**Scope:** Sensor Bio Band + iPhone + production backend lifecycle only

## Preconditions

- Record the exact Noom+ commit, Sensor Bio SDK tag/version, iPhone/OS, Band serial/Device ID/firmware, account, timezone, and network conditions.
- Use a test account approved for health-data QA.
- Capture redacted SDK lifecycle logs. Do not include account IDs, email, scores, RHR/HRV, raw signals, or detailed sleep payloads in shared logs.
- Start from the production SDK environment. No DEBUG fixtures may be enabled.
- Define the campaign duration and stop conditions before the first night; do not run an unbounded background campaign.

## Required sequences

### 1. Normal foreground wake

1. Wear the Band overnight.
2. Wake with the iPhone app active and Band connected.
3. Capture the observed order and timestamps for `sleepDetected`, `sleepStored`, `sleepUploaded`, acknowledged `syncCompleted`, session discovery, first processing detail, and typed terminal outcome.
4. Verify detection timing is never displayed as final onset/wake.
5. Verify upload/sync never produces a completed score by itself.
6. Verify one exact account/day/endDate/endTimestamp/timezone session is selected and all sessions remain available.
7. Verify Home, Sleep Hub, Detail, and Body Status change from the same coordinator snapshot.

### 2. Background and foreground resume

1. Put Noom+ in the background before wake/sync.
2. Verify at most one finite background reconciliation attempt runs when iOS gives execution time; no background polling loop.
3. If typed success arrives and notification permission already exists, verify one generic local notification. Confirm Noom+ does not request permission from the sleep pipeline.
4. Foreground the app and verify pending reconciliation resumes within the configured attempt/time limit.
5. Repeat foregrounding and SDK signals; verify no duplicate task or notification.

### 3. Termination and relaunch

1. Terminate Noom+ while sleep is detected, uploaded, or processing.
2. Relaunch under the same account.
3. Verify only protected minimal identity/retry metadata restores; SDK health payload remains SDK-owned.
4. Verify the exact pending session is re-fetched and an older completed result remains dated and visible until replacement.
5. Verify account switch and sign-out clear old metadata, tasks, and pending/delivered sleep notifications.

### 4. Temporary offline and reconnect

1. Interrupt network access after Band synchronization but before processing completes.
2. Verify transport failure is separate from analysis outcome and does not erase the previous completed result.
3. Restore network and explicitly retry/foreground.
4. Verify reconciliation is idempotent, generation-guarded, and bounded to the same exact session.

### 5. Multiple sessions and edge outcomes

- Produce or use approved fixtures/backend data for two sessions on one local day. Verify both are listed, default selection is disclosed, and manual selection fetches the exact identity.
- Verify short-session, processed-with-error, aggregate-invalid, processing, circadian-generating, and processed-success states.
- Verify only processed-success enables Body Status; partial successful payloads keep independent RHR/HRV/score fields without inventing missing stages.
- Resolve one of two detected candidates and verify the other remains pending and bound to its own session.

## Timing evidence

Record separately:

- wake/detection → session stored;
- stored → uploaded;
- uploaded/acknowledged sync → first session discovery;
- first detail processing → typed terminal outcome;
- background event → foreground recovery.

Report median and range only after the predeclared sample count. Do not claim “instant” behavior from one night or Simulator timing.

## Pass criteria

- No fabricated completion, onset/wake timing, session identity, or Body Status.
- No mixed account/day/session snapshot.
- No stale callback overwrites newer state.
- No unbounded foreground/background polling.
- Relaunch, account switch, and sign-out behavior matches the protected-state contract.
- VoiceOver labels expose lifecycle state and source date; Dynamic Type does not truncate critical state/retry controls.
- TestFlight build and physical evidence use the same reviewed commit.
