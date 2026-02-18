# Event Documentation Contract

Use this contract for all event docs in `docs/events/`.

## Core rule
All events must use **staggered load-in** (deferred cold spawn + staged startup).
Do **not** rely on preload as the primary startup path.

---

## Required sections for every event doc

1. **Metadata**
   - Event name
   - Lua module path
   - Owner
   - Last verified date

2. **Trigger & readiness**
   - Trigger source (pacing/manual)
   - Preconditions (player vehicle, FKB/position readiness, etc.)
   - Block reasons and user-facing behavior

3. **Spawn contract**
   - Model + config
   - Spawn placement strategy
   - Spawner fallback behavior
   - Spawn failure behavior

4. **Load-in strategy (required)**
   - `triggerManual()` arms pending start only
   - spawn occurs from `update()` deferred attempts
   - retry cadence and timeout/deadline
   - staged startup pipeline (example: `postSpawn -> audioEnsure -> aiStart -> audioPlay`)
   - safe abort/reset behavior

5. **Phase flow**
   - Start condition + HUD text
   - Middle/engage condition + gameplay effect
   - End outcomes (escape/caught/abort etc.)

6. **AI behavior**
   - chase/flee rules
   - threshold distances
   - special driving profiles

7. **HUD/messages**
   - threat level usage
   - exact status/instruction strings
   - mission popup usage policy

8. **Economy/loot**
   - money impact (remove/restore/reward)
   - ammo/charges/loot logic

9. **Cleanup contract**
   - what must be reset on all exits
   - despawn behavior
   - audio/effects cancellation

10. **Validation checklist**
   - trigger, spawn, load-in, phases, end outcomes, cleanup verified

---

## Required load-in contract (normative)

Every event must follow all of the rules below:

1. `triggerManual()` must not perform full heavy startup in the same frame.
2. Trigger path must set pending-start state and return quickly.
3. Vehicle spawn must happen in `update()` after deferred wait/retry.
4. Startup must be staged across ticks (not single-frame bundle).
5. Pending start must include attempts + deadline.
6. Deadline failure must clear threat and reset runtime state.
7. `endEvent()` must clear pending + active + startup state fields.

---

## Per-event file template

```md
# <EventName>

## Metadata
- Module:
- Owner:
- Last verified:

## Trigger & readiness
...

## Spawn contract
...

## Load-in strategy
...

## Phase flow
...

## AI behavior
...

## HUD/messages
...

## Economy/loot
...

## Cleanup contract
...

## Validation checklist
...
```
