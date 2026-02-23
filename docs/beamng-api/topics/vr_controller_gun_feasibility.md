# VR pistol implementation plan (head-aim mode for current phase)

## Scope for this phase
- **Pistol only** (no rock/throw behavior in this phase).
- **Functional holding only**:
  - “Holding” is represented by HUD/inventory equip state (`hudEquippedWeapon == "pistol"`).
  - No weapon mesh, no hand-attached prop, no physical pickup interaction yet.

## Short answer
Yes, this is feasible with the current architecture, and for this phase we should enforce strict mode separation:

- **Desktop (flat-screen):** keep existing camera+mouse flow unchanged.
- **VR (OpenXR session running):** aim from headset/head-forward direction (center of view).
- **VR input:** keep mouse click firing for this phase (same as flatscreen), only change aim ray + crosshair.

This keeps desktop behavior untouched while making VR aiming spatially consistent with what the player is looking at.

---

## What the API/docs confirm

### 1) OpenXR state is available for runtime gating
Preferred runtime check is:
- `render_openxr and render_openxr.isSessionRunning and render_openxr.isSessionRunning()`

Fallback if needed:
- `OpenXR.getEnable()` plus available session-running signal already used in this project.

### 2) Predicted camera pose exists for head-origin aim
Use `OpenXR.getCameraPosRotPredictedXYZXYZW()` to get headset position + quaternion.
From that quaternion, compute forward vector and use it as the VR aim direction.

### 3) Existing shot/hit logic can stay unchanged
Only the ray origin/direction source changes in VR. Downstream hit resolution/damage flow remains the same.

---

## Implementation rule (this phase)

## A) Desktop / flat-screen (VR inactive)
- **Aim source:** existing camera→mouse raycast path (`getCameraMouseRay`, current `FirstPersonShoot` flow).
- **Fire input:** mouse click.
- **Behavior:** unchanged from current desktop implementation.

## B) VR active (OpenXR running)
- **Aim source:** headset predicted camera pose:
  - origin = camera/head position
  - direction = quaternion forward vector
- **Fire input:** mouse click (same path as current implementation).
- **Behavior:** only aim ray and crosshair placement change.

---

## Core code change
Create `getAimRay()` and use it from both:
- shot raycast path
- crosshair draw path

`getAimRay()` behavior:
- VR active -> return origin/dir from OpenXR predicted camera pose.
- VR inactive -> return existing mouse-based ray.

---

## Crosshair behavior
- Desktop: keep current mouse-following crosshair exactly unchanged.
- VR: place crosshair at ray hit point from head-forward ray.
- If no hit: place crosshair at `origin + dir * 100` (or similar stable distance).

---


## Which fire input is better right now?
- **For this task, mouse click is better** because it is the smallest, safest change and preserves existing behavior while we validate VR head-aim.
- Controller trigger can be added later as a separate phase once aim behavior is confirmed stable.
- Recommended decision now: **VR shoot = mouse click**, **VR aim = head-forward**.

---

## Logging and debug
In debug mode only, log active aim mode when sampling/using aim:
- `aim=VR_HEAD`
- `aim=FLAT_MOUSE`

## Deferred (out of scope for this task)
- Controller-pose aiming.
- New VR trigger/action mapping.
- Weapon mesh/hand prop/pickup interactions.

---

## Immediate next tasks (small PR-ready)
1. Add `isVRActive()` helper using preferred OpenXR session-running check.
2. Add `getAimRay()` (VR head-forward vs flat mouse ray).
3. Replace direct aim sampling in shot code with `getAimRay()`.
4. Replace crosshair placement source with `getAimRay()` in VR.
5. Keep all existing hit/damage/fire-input logic unchanged.
6. Add debug-only log line for current aim mode.
