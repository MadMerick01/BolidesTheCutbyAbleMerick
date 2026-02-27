# RobberCongestionSupervisor (Design Draft)

## Purpose
This document defines the **plain-English design** for a future `RobberCongestionSupervisor.lua` module.

The supervisor’s job is to make robber vehicles:
- much safer around normal traffic,
- better at handling multi-vehicle queues (3+ cars ahead),
- safer on steep hills and tight corners,
- still fast and threatening enough to preserve chase intensity.

It does this by adding a lightweight “safety brain” above the existing robber AI, rather than replacing the base flee behavior.

---

## Design goals
1. **Prevent late braking and rear-ending in traffic.**
2. **Avoid push-through behavior in dense queues.**
3. **Negotiate steep hills and tight corners with fewer loss-of-control events.**
4. **Keep pace high when roads are clear.**
5. **Recover to aggressive fleeing quickly after hazards clear.**
6. **Reroute when congestion or terrain risk is persistent, not just momentary.**

---

## High-level concept
Treat the supervisor as a state machine that continuously answers:

- “How congested is the road in front of the robber?”
- “How risky is current speed versus traffic, slope, and corner geometry?”
- “Should we keep normal flee behavior, apply a safer profile, or reroute?”

The supervisor should run on a timer (for example, several checks per second) and only make changes when thresholds are clearly crossed to avoid jitter.

---

## Critical part 1: Forward congestion sensing
The most important input is a **forward corridor scan** in front of each robber vehicle.

### What to measure in plain English
- Number of vehicles ahead in the same driving direction.
- Distance to the nearest lead vehicle.
- Whether there are multiple stopped/slow vehicles stacked ahead.
- Relative speed (are we rapidly closing in?).
- Lane availability (is there an adjacent free lane soon?).

### Why this matters
Without this, the robber only reacts when already too close. A forward congestion score allows early safety actions while still leaving room for speed.

### Practical scoring idea
Build a simple score from:
- **queue count weight** (more cars ahead = higher score),
- **closing speed weight** (higher approach speed = higher score),
- **near distance penalty** (very close lead car = sharp score jump),
- **lane blocked penalty** (fewer escape lanes = higher score).

This score drives behavior-state transitions.

---

## Critical part 2: Terrain and corner risk sensing
Steep grades and tight bends should be first-class supervisor inputs, not side mitigations.

### What to measure in plain English
- Road grade trend ahead (uphill/downhill severity).
- Corner sharpness ahead (curvature over short lookahead windows).
- Combined risk with current speed (e.g., fast approach + downhill + tight turn).
- Surface confidence (if available) and recent stability signs (wheel slip, abrupt yaw growth).

### Why this should be in the supervisor
Yes, it makes sense to include this here. Congestion, hills, and corners are all “speed viability” problems. A single supervisor can arbitrate speed/lane/reroute decisions consistently, rather than splitting logic across separate ad hoc patches.

### Practical risk behavior
- Apply early speed reduction before crest-downhill turn combinations.
- Increase safety margin for tight corners when traffic blocks ideal line choice.
- Delay aggressive acceleration until corner exit is stable.

---

## Critical part 3: Behavior states that protect safety without killing pace
Use three primary states and one emergency state:

1. **FreeFlow**
   - Used when corridor and terrain risk are low.
   - Keep high flee speed and normal aggression.

2. **ModerateRisk**
   - Triggered by developing congestion or moderate hill/corner risk.
   - Reduce top speed moderately.
   - Start braking earlier.
   - Prefer smoother lane decisions instead of rapid weaving.

3. **HeavyRisk**
   - Triggered by dense queue, short time-to-collision trend, or severe hill/corner approach risk.
   - Reduce speed further.
   - Prioritize stable lane position.
   - Increase following gap behavior and commit less to risky merges.

4. **EmergencyAvoid**
   - Triggered by imminent collision/loss-of-control risk.
   - Immediate strong deceleration and protective maneuver bias.

### Why state-based control is critical
It preserves “speed when safe” because aggressive settings are not permanently removed; they are only suppressed while risk is high.

---

## Critical part 4: Hysteresis and cooldowns (anti-oscillation)
If the supervisor flips states too quickly, robber behavior becomes unstable.

### Required protections
- **Enter threshold vs exit threshold** (harder to enter than leave, or vice versa).
- **Minimum dwell time** in each state.
- **Cooldown before re-entering reroute mode**.
- **Smoothing of congestion and terrain scores** over short windows.

### Outcome
The robber feels deliberate: early safe response in hazards, then confident acceleration once conditions truly improve.

---

## Critical part 5: Preserve chase intensity (speed budget)
To avoid making robbers too easy to catch, define a “speed budget” policy:

- In open road, allow near current top chase pace.
- In moderate risk, cap speed only enough to prevent late-brake crashes and unstable corner entry.
- In heavy risk, cap harder but never force unnecessary crawling if route conditions open.
- Return speed quickly after confirmed clearance.

This keeps the robber dangerous on clear stretches while reducing reckless collisions and loss-of-control events.

---

## Critical part 6: Reroute logic when congestion or terrain risk is too high
When conditions remain bad, the supervisor should escalate from “slow and wait” to “find another path.”

### When to trigger reroute
Reroute should trigger if most of these are true for a sustained period:
- HeavyRisk persists beyond a time threshold.
- Queue depth remains high (e.g., 3+ vehicles with low movement), or
- Upcoming route has repeated steep/tight segments causing repeated forced slowdowns.
- Progress toward escape objective is poor.
- Alternative path candidates exist with lower combined risk score.

### Plain-English reroute strategies
1. **Adjacent-lane bypass first**
   - If a side lane is moving better and merge risk is low, shift there.

2. **Short local detour**
   - Prefer upcoming turns/branches that preserve general escape heading while avoiding jam pockets or risky grade/curve clusters.

3. **Temporary de-prioritization of direct line-away path**
   - Accept slightly less direct escape direction for a short period if it avoids dead queue conditions or high rollover/spin risk terrain.

4. **Rejoin escape-optimal route after clearance**
   - Once risk score drops and speed recovers, transition back toward the strongest flee path.

### Safety guardrails during reroute
- Never reroute into clearly worse congestion/risk.
- Avoid last-second intersection cuts at high closing speed.
- Block repeated left-right lane thrashing with cooldown.

---

## Critical part 7: Multi-robber coordination
If multiple robbers are active, they should avoid creating their own mini-jam.

### Coordination principles
- Slightly stagger decision timing so all robbers do not switch lanes simultaneously.
- Apply local spacing rules between robbers in the same corridor.
- Prevent “follow-the-leader bad decision chains” by allowing independent risk evaluation per robber.

---

## Critical part 8: Failsafes and fallback behavior
When data is incomplete or uncertain:
- Prefer conservative speed reduction over aggressive guessing.
- Keep default flee mode active rather than disabling AI.
- Reattempt normal operation after a short stabilization window.

This avoids brittle behavior and keeps the event running smoothly.

---

## Telemetry and tuning checklist
For each robber, log at low overhead:
- current supervisor state,
- congestion score,
- terrain/corner risk score,
- lead distance,
- relative speed,
- lane-change/reroute decisions,
- time spent in heavy risk,
- collision/near-miss events.

Use this telemetry ("telementry" in prior notes) to tune thresholds so safety improves without excessive speed loss.

### HUD visibility requirement
The telemetry/tuning checklist output should be visible in HUD cards at the bottom of the screen:
- If **1 robber** is active: show **one telemetry card** for that robber.
- If **another robber** becomes active: create **an additional telemetry card below the first**.
- Continue stacking one card per active robber in activation order.
- Each card should show compact key fields: state, risk scores, lead distance, relative speed, and reroute status.

---

## Acceptance targets for first implementation pass
1. Clear reduction in rear-end and push-through collisions in 3–6 vehicle queues.
2. Earlier braking in heavy traffic versus current robber behavior.
3. Fewer spin/loss-of-control moments entering steep downhill corners.
4. Robber still reaches high speeds on uncongested roads.
5. Reroute engages in persistent jams/risky terrain and improves progress in a meaningful share of cases.

---

## Proposed implementation roadmap (no code yet)
1. Define state machine + thresholds in config terms (traffic + terrain components).
2. Build forward congestion and terrain/corner risk scores with smoothing.
3. Wire risk scores to behavior profile switching.
4. Add persistent-risk reroute trigger and candidate ranking.
5. Add HUD telemetry cards with one-card-per-active-robber stacking at bottom of screen.
6. Add telemetry logs for balancing safety vs speed.
7. Run scenario tests (dense traffic, steep hills, tight corners) and iterate thresholds.

This roadmap should deliver safer traffic behavior first, then improve bypass intelligence while keeping chase pacing strong.
