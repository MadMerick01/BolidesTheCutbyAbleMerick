# RobberShotgun

## Metadata
- Module: `lua/ge/extensions/events/RobberShotgun.lua`
- Owner: Bolides The Cut
- Last verified: 2026-02-18

## Trigger & readiness
- Trigger source: pacing/manual via `triggerManual()`.
- Requires player vehicle.
- Requires ForwardKnownBreadcrumb position at 200m.
- If blocked (no player vehicle or no stable FKB), event does not arm and logs blocked reason.

## Spawn contract
- Vehicle model/config: `roamer` + `robber_light.pc`.
- Spawn position: FKB(200m) + vertical offset (`+0.8z`).
- Spawn transform faces player position.
- Compatible spawner fallbacks are attempted.
- If spawn cannot resolve before deadline, event exits safely with threat-cleared HUD state.

## Load-in strategy
- Uses staggered deferred cold start (no preload dependency).
- Trigger path arms pending start and sets deferred attempt timing.
- Actual spawn is executed in `update()` pending-start branch.
- Retry + timeout:
  - early wait tick,
  - repeated deferred attempts,
  - deadline fail-safe to safe HUD state and reset.
- Startup stages across ticks:
  1. `postSpawn`
  2. `audioEnsure`
  3. `aiStart`
  4. `audioPlay`
  5. `done`

## Phase flow
- Start
  - HUD starts with tailing warning/instruction.
  - Robber follows player.
- Engage
  - Shot attacks begin when within engagement distance.
  - Event transitions to flee behavior when close enough.
- End outcomes
  - `escaped_without_harm`
  - `escape`
  - `caught`
  - `garage` abort
  - pending-start cancellation

## AI behavior
- Follow behavior on startup.
- Shot engagement gated by distance and shot interval timing.
- Transitions to flee and can end on long-distance escape.
- Anti-teleport snapback guard applied after spawn.

## HUD/messages
- Uses status + instruction merged in HUD status block.
- Distance to contact is formatted into status while active.
- End outcomes set safe threat status and outcome-specific text.
- Mission summary popups used for relevant escape outcomes.

## Economy/loot
- Handles possible reward flows on successful attacker takedown.
- Uses payment module helpers where available.
- Supports loot-style outcome messaging integration.

## Cleanup contract
- `endEvent()` handles pending-start cancellation and active run exit.
- Must clear runtime state via reset path.
- Must despawn robber vehicle if present.
- Must restore safe HUD state with outcome-appropriate status/instruction.

## Validation checklist
- [ ] Trigger block reasons verified (no vehicle / no FKB).
- [ ] Pending-start deferred spawn path verified.
- [ ] Startup stage sequence verified across ticks.
- [ ] Shot cadence + flee transition verified.
- [ ] All end outcomes verified.
- [ ] Full cleanup verified (HUD/vehicle/state).
