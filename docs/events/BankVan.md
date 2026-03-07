# BankVan

## Metadata
- Module: `lua/ge/extensions/events/BankVan.lua`
- Owner: Bolides The Cut
- Last verified: 2026-03-07

## Trigger & readiness
- Trigger source: pacing/manual via `triggerManual()`.
- Requires player vehicle.
- Requires ForwardKnownBreadcrumb position at 200m (live or cached).
- If blocked (no player vehicle or no stable FKB), event does not arm and logs blocked reason.

## Spawn contract
- Vehicle model/config: `roamer` + `robber_light.pc` (temporary bank van stand-in).
- Spawn position: FKB(200m) + vertical offset (`+0.8z`).
- Spawn transform faces toward player position.
- Spawner fallback order attempts compatible spawn APIs, then fails safe.
- Spawn failure behavior: clear threat messaging and return player to safe route status.

## Load-in strategy
- Uses staggered deferred cold start (no preload dependency).
- Trigger path only arms pending start with transform, deadline, next-attempt, and attempt counter.
- Actual spawn occurs in `update()` pending-start branch.
- Retry behavior: initial wait tick + repeated attempts until deadline.
- Startup stages across ticks:
  1. `postSpawn`
  2. `audioEnsure`
  3. `aiStart`
  4. `audioPlay`
  5. `done`

## Phase flow
- Start
  - HUD: "The locals are reporting a Bolide Money Van nearby".
  - Instruction: "Stop the van before they move profits out of town, be careful they are armed and dangerous".
  - Van immediately enters flee behavior (does not pursue player).
- Middle
  - Van fires at player while within shotgun engagement range.
  - Player chases/intercepts and can stop the van.
- End outcomes
  - `escape`: van reaches >800m distance and escapes with profits.
  - `caught`: player catches/stops van and receives reward.
  - `garage` abort.
  - Pending-start cancellation path also exits safely.

## AI behavior
- Van starts directly in flee mode.
- Flee profile uses legal mode with `80 km/h` cap.
- Shot engagement uses same distance/cadence style as RobberShotgun.
- Anti-teleport snapback guard is retained shortly after spawn.

## HUD/messages
- Uses threat levels and status updates through host HUD bridge.
- Distance to van is displayed in HUD status while active.
- Escape mission popup text: "The Bolides have successfully moved their profits out of the area".
- Catch status text includes reward confirmation.

## Economy/loot
- On catch/stop outcome, rewards player with `$10000` via payment helper path.
- On escape, no reward is granted.

## Cleanup contract
- `endEvent()` handles both pending-start cancel and active-run teardown.
- Must clear pending/startup/runtime state fields.
- Must despawn van vehicle if present.
- Must restore HUD threat/status to safe state.

## Validation checklist
- [ ] Trigger block reasons verified (no vehicle / no FKB).
- [ ] Pending-start deferred spawn path verified.
- [ ] Startup stage sequence verified across ticks.
- [ ] Immediate flee behavior + 80 km/h cap verified.
- [ ] Shot cadence + intercept stop condition verified.
- [ ] Escape at >800m verified.
- [ ] Catch reward (+$10000) + wallet update verified.
- [ ] Full cleanup verified (HUD/audio/vehicle/state).
