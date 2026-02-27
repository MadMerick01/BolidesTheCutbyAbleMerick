# Robber AI Traffic-Avoidance Feasibility Re-evaluation (Multi-Vehicle Congestion)

## Request re-evaluated
Goal: make robber AI reliably avoid **multiple traffic vehicles ahead** (especially 3+), brake earlier, and route around congestion instead of pushing through.

This re-evaluation incorporates the additional BeamNG AI/traffic source references in:
- `docs/ai_files/*`
- `docs/traffic_files/*`

## Executive conclusion
This is **feasible**, but only as a **hybrid solution**.

- **Feasible now (medium effort):** noticeably better behavior using existing AI knobs + event-side supervisory logic.
- **Not feasible with tuning alone:** true reliability in dense 3+ vehicle stacks if we keep robber on stock `ai.setMode("flee")` only.
- **High-confidence path:** keep native flee planner for base driving, but add GE-side congestion detection + dynamic behavior profile switching + temporary reroute triggers.

## What the current robber setup is doing
`RobberBoss` currently configures flee AI with:
- `ai.setMode("flee")`
- `ai.setSpeedMode("legal")`
- `ai.setMaxSpeedKph(75)` in normal profile
- `ai.setAggression(0.28)` in normal profile
- `ai.setAvoidCars(true)`
- `ai.setAllowLaneChanges(true)`
- `ai.driveInLane("off")`

That profile is intentionally evasive and lane-flexible, but it is still primarily a target-centric flee behavior (escape pressure first). In heavy traffic this can still commit late and squeeze/push when escape urgency dominates. It is not explicitly congestion-aware in event logic today.

## What the added AI docs change in the feasibility picture
The AI core (`docs/ai_files/ai.lua`) confirms useful internals and also key limits:

### Positive signals (why improvement is realistic)
1. AI already has traffic-aware target-speed logic and can brake for lead vehicles via computed `trafficTargetSpeed` and TTC-style checks.
2. AI supports options already used by robber (`avoidCars`, lane settings, aggression), so profile switching can be done immediately.
3. AI has OBB/raycast-based nearby object handling (`populateOBBinRange` etc.), so there is native obstacle perception.

### Limiting signals (why reliability with 3+ stacks is hard if untouched)
1. Traffic lookahead defaults are short for high-speed chase/flee contexts (`distAhead = 40`).
2. Following logic is very tight (`time_gap = 0.3`), which can delay braking comfort margin.
3. In `calculateTrafficTargetSpeed`, the loop uses `stopFlag` and breaks after first blocking condition, biasing response to the nearest conflict and reducing anticipation of deep queues (3+ vehicles).

Net: base AI is traffic-aware, but **not engineered specifically for robust multi-car queue anticipation under flee pressure**.

## What the added traffic docs change in the feasibility picture
The traffic system (`docs/traffic_files/traffic.lua`) exposes useful runtime state and control points:

- `getTrafficData()` and `getTrafficList()` allow external systems to inspect active traffic entities.
- Traffic supports dynamic focus/spawn and lifecycle controls through gameplay traffic APIs.

This means robber event code can build a lightweight **forward-congestion sensor** without rewriting core vehicle AI:
- sample robber transform + heading,
- project traffic vehicles into forward corridor,
- count/score queue density and relative speed,
- switch flee profiles (or temporary modes) based on congestion score.

So the additional docs materially increase confidence that a supervisory layer is practical.

## Re-evaluated feasibility rating
- **Tuning-only (current flee mode + static params):** **Low-to-medium** chance of “reliable” 3+ queue handling.
- **Supervised hybrid (recommended):** **High** feasibility for noticeable reliability gains.
- **Full custom traffic-aware planner replacing stock flee:** feasible but high complexity/risk and likely unnecessary for this project.

## Recommended implementation strategy (phased)

### Phase 1 — Fast win (parameter/state supervision)
Add robber-side congestion states and profile switching:
- `free_flow`
- `moderate_congestion`
- `heavy_congestion`

For heavier congestion, apply safer settings temporarily:
- lower max speed,
- lower aggression,
- force in-lane driving during queue approach,
- increase lane-change selectivity (fewer panic lane swaps),
- stronger crash-avoid priority.

Expected outcome: earlier braking and less pushing in obvious traffic packs.

### Phase 2 — Forward queue estimator (GE-side)
Using traffic tables, compute a forward corridor score:
- count vehicles ahead within N meters,
- estimate queue depth (3+ threshold),
- include relative speed/closing rate.

Trigger preemptive behavior before close-range conflict:
- pre-brake profile,
- temporary follow/pace mode,
- delayed return to aggressive flee until corridor clears.

Expected outcome: significantly better handling of stacked slow traffic.

### Phase 3 — Congestion bypass behavior
When heavy congestion persists:
- request alternative route tendency (where possible through AI mode/path nudges),
- or temporarily bias lane discipline + reduced target speed until escape lane appears.

Expected outcome: robber navigates around jams more often instead of forcing through center mass.

## Risks and constraints
1. **Flee objective conflict:** robber must still escape player; over-conservative logic can make event too easy.
2. **Map variance:** narrow roads and intersections can reduce available bypass options regardless of logic.
3. **AI black-box limits:** some native flee decisions remain opaque and may override ideal congestion behavior.

## Success criteria for “reliable” improvement
Use scenario tests with controlled traffic packs (single lane + multilane, 3–6 vehicles ahead):
- ≥80% no-contact pass/queue behavior in heavy packs,
- earlier brake onset distance versus baseline,
- reduced “push-through” incidents,
- no major regression in flee continuity.

## Final re-evaluation answer
With the new AI/traffic references, I now rate the request as:

- **Feasible and worth implementing** via a hybrid supervisor approach.
- **Unlikely to be reliably solved** by static `flee` parameter tuning alone.
- Best next step is a **RobberBoss congestion supervisor** that uses traffic-state sampling + dynamic flee profile switching, then iterative tuning against 3+ vehicle queue test scenarios.
