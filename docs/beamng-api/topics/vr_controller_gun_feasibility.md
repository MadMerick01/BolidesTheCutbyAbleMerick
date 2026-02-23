# VR pistol feasibility (Phase 1: head-aim + existing fire input)

## Decision summary
Yes — this is feasible in the current architecture with low risk if we keep strict mode separation:

- **Desktop (flat-screen):** no behavior changes.
- **VR (OpenXR session running):** compute aiming from headset pose (head-forward ray).
- **Fire input in this phase:** keep existing mouse click path.

This gives us VR-correct aim behavior while preserving all existing shot, hit, and damage logic.

---

## Phase-1 scope (explicit)

### In scope
- Pistol flow only.
- “Holding pistol” represented by existing HUD/inventory equip state (`hudEquippedWeapon == "pistol"`).
- VR head-forward aim ray when VR is active.
- Crosshair placement driven by the active aim ray.

### Out of scope (deferred)
- Controller-pose aiming.
- OpenXR trigger/action mapping.
- Physical pickup/throw interactions.
- Weapon mesh or hand-attached prop rendering.

---

## API basis for feasibility

### 1) Runtime VR gating is available
Preferred runtime check:
- `render_openxr and render_openxr.isSessionRunning and render_openxr.isSessionRunning()`

Fallback if required by runtime availability:
- `OpenXR.getEnable()` and existing in-project session-running signal.

### 2) Predicted headset pose exists for aim origin/direction
Use:
- `OpenXR.getCameraPosRotPredictedXYZXYZW()`

From quaternion, derive forward vector and use it as the aim direction.

### 3) Existing downstream combat path can stay unchanged
Only replace ray **source** (origin/direction) in VR mode. Keep current hit resolution, damage application, and fire cadence logic intact.

---

## Implementation contract

### A) Desktop / flat-screen (`VR inactive`)
- Aim source: existing camera+mouse ray flow (`getCameraMouseRay`, current shooting path).
- Fire input: existing mouse click.
- Expected behavior: exactly unchanged.

### B) VR (`OpenXR session running`)
- Aim source:
  - origin = predicted headset/camera position
  - direction = headset forward vector from predicted quaternion
- Fire input: existing mouse click (same path as desktop for now).
- Expected behavior: only ray/crosshair source changes.

---

## Required code shape
Add a shared aim accessor and use it everywhere aim is sampled:

- `getAimRay()`
  - If VR active: return head-origin/head-forward ray.
  - If VR inactive: return existing mouse-based ray.

Then route both of these call sites through `getAimRay()`:
1. Shot raycast path.
2. Crosshair placement path.

This prevents drift between “where we shoot” and “where we draw the crosshair.”

---

## Crosshair rules

- **Desktop:** preserve current mouse-following behavior.
- **VR:** draw at hit point from head-forward aim ray.
- If no hit: place at `origin + dir * 100` (stable fallback distance).

---

## Why keep mouse-click fire in Phase 1?
- Smallest safe change set.
- Minimizes risk to existing input stack.
- Isolates VR validation to one variable: aim ray origin/direction.

Recommended current decision:
- **Aim:** VR head-forward when VR is active.
- **Fire:** existing mouse-click path.

---

## Debug / observability
In debug builds only, log active mode when sampling aim:

- `aim=VR_HEAD`
- `aim=FLAT_MOUSE`

Optional helpful debug fields:
- ray origin (xyz)
- ray direction (xyz)
- whether crosshair used hit-point or fallback distance

---

## PR-ready implementation checklist
1. Add `isVRActive()` helper using `render_openxr.isSessionRunning()` when available.
2. Add `getAimRay()` helper (VR head-forward vs flat mouse ray).
3. Replace direct shot aim sampling with `getAimRay()`.
4. Replace crosshair source with `getAimRay()` in VR mode.
5. Keep hit/damage/fire-input logic unchanged.
6. Add debug-only aim mode logs.
7. Verify desktop behavior is unchanged.
8. Verify VR crosshair aligns with center-of-view target selection.
