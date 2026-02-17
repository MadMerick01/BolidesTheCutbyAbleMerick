# Preload/Spawn Behavior Gap Report (RobberEMP)

## Scope
This report analyzes why current preload/spawn behavior does not meet the design goal:

> Frame-judder-free event vehicle flow where the vehicle is preloaded, handed off to the event, then stashed back to preload location after event completion.

No code changes are proposed in this report.

## Playtest Symptoms (mapped to system behavior)

1. **Preload pending state appeared (HUD yellow), then a fallback cold spawn occurred.**
   - Log: `Pending start timed out; fallback cold spawn started.`
   - This indicates the system did **not** hand off a preloaded robber in time, and performed runtime spawning during event start.
2. **Frame judder occurred at event start.**
   - The same window includes vehicle spawn/loading logs (`spawning vehicle /vehicles/roamer/`, `Vehicle loading took...`) consistent with a cold spawn path.
3. **Lua exception fired during the same transition.**
   - `attempt to call global 'mergeStatusInstruction' (a nil value)` in `RobberEMP.lua` line 507.
4. **Event gameplay still continued and completed.**
   - AI and EMP phases proceeded after fallback.
5. **Vehicle was not stashed back to preload spot after completion.**
   - HUD debug showed `Teleport verification failed`; robber remained where event ended.

## Why this misses the design goal

## 1) Timeout path explicitly allows cold spawn (introduces hitch risk)
RobberEMP begins with `PreloadEvent.beginClaim(...)` and enters pending state when claim is not immediately available. On timeout, it intentionally falls back to `spawnVehicleAt(...)` and starts active run from that newly spawned vehicle. This path is designed for continuity, but directly conflicts with “judder-free via preload handoff” because it reintroduces runtime spawn/load work during gameplay. 【F:lua/ge/extensions/events/RobberEMP.lua†L991-L1016】【F:lua/ge/extensions/events/RobberEMP.lua†L1155-L1173】

Preload manager timeout behavior returns `status = "timeout"` when claim retries expire, so this fallback is expected once claim cannot be satisfied before deadline. 【F:lua/ge/extensions/events/PreloadEventNEW.lua†L623-L635】

## 2) The handoff claim fails on teleport verification constraints
Claiming the preloaded car for event use attempts teleport+verify with strict tolerances (`consumeRetries = 3`, `consumeMaxDist = 5.0`) and returns `teleport_verification_failed` when final position check does not pass. Repeated failures drive pending retries until timeout. 【F:lua/ge/extensions/events/RobberEMP.lua†L996-L1002】【F:lua/ge/extensions/events/PreloadEventNEW.lua†L728-L736】

This matches your observed “pending then timeout then cold spawn” progression and the final HUD failure string family.

### Plain-English: why teleport is not a simple “move from A to B”

At first glance, teleport sounds like “set car position and done.” In this system, it is actually a *multi-step physics handoff* that can fail for several practical reasons:

1. **It is not one API call; it is a sequence.**
   The helper first tries to set position/rotation, then optionally calls `spawn.safeTeleport(...)`, then checks if the car ended close enough to the target. If that distance check fails, it retries. So success depends on every step behaving consistently in that frame. 【F:lua/ge/extensions/events/PreloadEventNEW.lua†L152-L180】

2. **Verification is strict and immediate.**
   The code verifies right away using a hard max distance (`maxDist`), and if the vehicle is still outside that radius at check time, it counts as failure. Any short-lived offset (settling, collision resolution, ground snap, rotation correction) can trip this even if the car later looks “close enough.” 【F:lua/ge/extensions/events/PreloadEventNEW.lua†L167-L180】

3. **The world can push back after teleport.**
   Vehicles are physics objects. If target space is slightly obstructed, uneven, or near boundaries, the engine may nudge the vehicle away after placement. That means requested target and final stable position can differ, causing intermittent pass/fail behavior.

4. **Claim/stash use teleport in live gameplay timing.**
   Claim happens during event startup and stash happens during cleanup, both while other systems are updating. The same transform can pass in one frame and fail in another because timing/state are different (AI state, vehicle sleep/wake, nearby objects, safeTeleport side effects).

5. **Retries improve odds, not guarantees.**
   Retrying 2–3 times helps, but each retry repeats the same constrained check. If the underlying placement context is bad, all retries fail. This is why it can feel random: “works sometimes, fails often” depending on local physics/context.

So the key takeaway is: **teleport here is a best-effort physics placement + strict verification loop**, not a guaranteed deterministic coordinate write.

## 3) Runtime Lua error in beginActiveRun adds instability exactly at transition
`beginActiveRun` calls `mergeStatusInstruction(...)` before `mergeStatusInstruction` is declared as a local function. In Lua this makes the earlier call resolve as a global lookup, yielding nil and throwing the exact error seen in logs. This error lands during the start transition (fallback or claimed), which can worsen frame pacing and HUD/state consistency during the most sensitive moment. 【F:lua/ge/extensions/events/RobberEMP.lua†L460-L511】【F:lua/ge/extensions/events/RobberEMP.lua†L514-L521】

## 4) Release/stash failure is silently swallowed, leaving vehicle at event endpoint
On event end, RobberEMP calls `pcall(PreloadEvent.release, ...)` and only checks whether the call threw, not whether release returned success. If release returns `(false, reason)` (e.g., stash teleport verification failure), RobberEMP does not handle that false return and does not despawn/recover the vehicle; the robber remains in-world where the event finished. 【F:lua/ge/extensions/events/RobberEMP.lua†L1124-L1131】

In preload manager, `release` returns false when `stash` fails, and stash failure includes teleport verification failure with `S.lastFailure = "stash teleport verification failed"`. This is consistent with your final HUD `Teleport verification failed` symptom and “not returned to stash.” 【F:lua/ge/extensions/events/PreloadEventNEW.lua†L763-L778】【F:lua/ge/extensions/events/PreloadEventNEW.lua†L823-L827】

## 5) “Teleport verification failed” is promoted to HUD debug state as last failure
The HUD payload includes `preloadDebug.lastFailure` sourced from preload manager debug info. Once a claim/stash verification failure occurs, this can surface as the visible final failure text. 【F:lua/ge/extensions/bolidesTheCut.lua†L1223-L1225】【F:lua/ge/extensions/bolidesTheCut.lua†L1249-L1258】

## Contributing noise vs core causes
Your log includes input-binding warnings/errors (`pickup__fifthwheelTiltLock`, `uw_fire`) that are likely unrelated global environment noise. They may affect overall log clarity but are not the preload-flow root cause shown by the RobberEMP/PreloadEvent call chain.

## End-to-end mismatch summary
The current implementation prioritizes “event must start somehow” over strict preload handoff and recovery. Concretely:

- **Start path:** claim retry window can end in cold spawn (hitch-prone).【F:lua/ge/extensions/events/RobberEMP.lua†L1163-L1173】
- **Transition robustness:** start path can throw due to local/global function resolution bug. 【F:lua/ge/extensions/events/RobberEMP.lua†L507-L521】
- **End path:** failed stash is not acted on by caller, so vehicle is not guaranteed to return to preload location. 【F:lua/ge/extensions/events/RobberEMP.lua†L1124-L1131】【F:lua/ge/extensions/events/PreloadEventNEW.lua†L823-L827】

That combination explains your observed behavior: pending preload, timeout + juddering cold spawn, event still playable, then failed stash with vehicle left behind.

## Three suggestions to make teleport handoff more reliable (discussion only)

Because preload/breadcrumb positions come from places the player already traveled, they are usually high-quality, driveable placements. Since teleports are also out of the player’s sightline, you can safely trade strictness for reliability without harming perceived quality.

1. **Use a staged verification window instead of instant fail.**
   - Today, teleport success is checked immediately after placement, and a single out-of-radius read can fail that attempt. A more reliable approach is to allow a deliberately larger settle window (for example **30 ticks or more**) and accept the teleport if the vehicle converges inside tolerance during that window.
   - Why this helps: physics/ground snap/collision correction often stabilize over multiple updates, and the timing here is non-player-visible.
   - Practical guidance: because this is off-screen and uses known-good traveled positions, optimize for eventual convergence, not immediate frame-perfect placement.

2. **Relax acceptance criteria for off-screen stash/preload teleports.**
   - Current thresholds are strict (`maxDist` around 4–5m in claim/stash paths). For out-of-view handoffs, use a **wider acceptance radius** (and optionally axis-aware checks, like more vertical tolerance on slopes).
   - Why this helps: many current “fails” are functionally good placements, especially when the target anchor is on known traveled route geometry.
   - Practical guidance: for hidden preload/stash operations, allow a larger “good enough” zone so claim/stash succeeds more consistently and avoids timeout-to-cold-spawn paths.

3. **Prefer robust fallback placement over hard failure on first target.**
   - If verification fails at the intended transform, try alternative nearby safe transforms (small ring/offset candidates, known parking fallback first, then breadcrumb fallback), and only declare failure after those candidates are exhausted.
   - Why this helps: local obstruction/terrain quirks are often highly position-sensitive; a nearby offset can pass reliably.
   - Tradeoff: slightly more complexity in placement policy, but much higher “sure-fire” behavior.

Net recommendation: for hidden teleports, optimize for *event-flow reliability* (successful handoff/stash) rather than strict point-perfect placement.


## Suggested follow-up investigation checklist (no code yet)

1. Capture preload debug each second during pending start (`claim.err`, attempts, deadline, owner id).
2. Log exact teleport delta in `teleportWithVerify` failures for claim/stash to identify whether failure is due to vertical settling, safeTeleport side effects, or obstructed target.
3. Validate success criteria in caller for `PreloadEvent.release` return values (not only exception/no-exception semantics).
4. Validate start-transition function declaration order for all event modules using HUD helper combinators.
5. Decide product behavior for timeout: strict “wait until handoff” vs “fallback cold spawn.” Current behavior is explicitly the latter.
