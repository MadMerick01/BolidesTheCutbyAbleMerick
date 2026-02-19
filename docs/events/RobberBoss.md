# RobberBoss

## Metadata
- Module: `lua/ge/extensions/events/RobberBoss.lua`
- Owner: Bolides The Cut
- Last verified: 2026-02-18

## Trigger & readiness
- Trigger source: pacing/manual via `triggerManual()`.
- Requires player vehicle.
- Requires ForwardKnownBreadcrumb position at 200m (live or cached).
- If blocked (no player vehicle or no stable FKB), event does not arm and logs blocked reason.

## Spawn contract
- Vehicle model/config: `bolide` + `BolideBolide01`.
- Spawn position: FKB(200m) + vertical offset (`+0.8z`).
- Spawn transform faces toward player position.
- Spawner fallback order attempts compatible spawn APIs, then fails safe.
- Spawn failure behavior: clear threat messaging and return player to safe route status.

## Load-in strategy
- Uses staggered deferred cold start (no preload dependency).
- Trigger path only arms pending start:
  - stores pending transform,
  - sets deadline,
  - schedules next attempt,
  - posts lightweight HUD preparation status.
- Actual spawn happens in `update()` pending-start branch.
- Retry behavior:
  - first update pass waits,
  - subsequent attempts spawn,
  - if deadline exceeded, event fails safe and resets.
- Startup stages across ticks:
  1. `postSpawn`
  2. `audioEnsure`
  3. `aiStart`
  4. `audioPlay`
  5. `done`

## Phase flow
- Start
  - HUD: "A vehicle is tailing you" + instruction to stay alert/control speed.
  - Robber follows player (conservative chase profile).
- Middle
  - EMP fires when robber closes in.
  - Robbery processing removes money from player wallet/career money path.
  - Event transitions to post-EMP flee behavior.
- End outcomes
  - Player escapes before robbery window resolves.
  - Player catches/stops robber and can recover money + loot outcomes.
  - Robber escapes and player loses robbed amount.
  - Pending-start cancellation path also exits safely.

## AI behavior
- Starts in follow/chase with conservative settings.
- Transitions to EMP-specific slow chase handling and then flee profile.
- Uses anti-teleport snapback guard shortly after spawn.
- Includes downhill flee profile logic to avoid unstable AI behavior.

## HUD/messages
- Uses threat levels and status updates through host HUD bridge.
- Merges status + instruction into one status block.
- Distance-to-contact display is controlled by event state (hidden at some points).
- Uses mission summary messaging for event-end outcomes when appropriate.

## Economy/loot
- Removes money using payment module when available, otherwise fallback add/set path.
- Can restore/reward money on successful interception outcome.
- Tracks robbed amount and potential found cash/loot outcomes.

## Cleanup contract
- `endEvent()` handles both pending-start cancel and active-run teardown.
- Must stop event audio and cancel active EMP effects.
- Must clear pending/startup/runtime state fields.
- Must despawn robber vehicle if present.
- Must restore HUD threat/status to safe state unless explicitly preserved.

## Validation checklist
- [ ] Trigger block reasons verified (no vehicle / no FKB).
- [ ] Pending-start deferred spawn path verified.
- [ ] Startup stage sequence verified across ticks.
- [ ] EMP + robbery + flee transitions verified.
- [ ] All end outcomes verified.
- [ ] Full cleanup verified (HUD/audio/vehicle/state).
