# VR controller gun feasibility (BeamNG 0.38 dump)

## Short answer
Yes, this looks **feasible with the current mod architecture**, as long as the VR right-hand pointer/trigger continue to emulate mouse aim + left-click in BeamNG VR. The mod’s shotgun already aims using the camera mouse ray and fires on mouse button 0, and it applies full `BulletDamage` damage when a vehicle is hit.

The main limitation is that the 0.38 API dump does **not** expose an obvious, documented way to read VR controller pose or trigger state directly from Lua. That means the safest plan is to lean on the existing mouse-based path (which matches your VR experience so far) rather than trying to wire controller data ourselves.

## What the current gun actually needs
The player shotgun implementation in this repo uses:

1. **Camera-based aiming** via mouse-ray helpers.
   - It uses `getCameraPosition()` plus `getCameraMouseRay()` to compute the shot ray direction.
   - It raycasts using `castRay(...)` (guarded) and falls back to `cameraMouseRayCast(true)`.
2. **Mouse click to fire**.
   - It fires when `ui_imgui.IsMouseClicked(0)` returns true.
3. **Damage application** through the shared damage helper.
   - It calls `BulletDamage.trigger({ ..., applyDamage = true })` (explicitly set in the shotgun code).
   - `BulletDamage` applies extra effects and calls `BulletHit.trigger(...)` when `applyDamage` is true.

Implication: if the VR controller pointer drives the mouse cursor/ray, and the VR trigger maps to mouse button 0, the existing shotgun path should work with no engine-level VR API required.

## What the VR docs + dump confirm (and don’t)

### Confirmed: VR runtime + settings exist
The dump confirms a global `OpenXR` table and several VR settings including controller-related toggles:

- `OpenXR.*` functions exist (enable/toggle/center/camera pose predicted, etc.).
- VR settings include:
  - `openXRuseControllers`
  - `openXRhandPoseDirectionDegrees`
  - `openXRhandPoseMultiplier`

These indicate VR controllers are a first-class feature in the engine, even if the Lua surface is thin.

### Confirmed: input synthesis hooks exist
The dump shows multiple ways to synthesize or trigger inputs:

- `core_input_virtualInput.createDevice(...)`
- `core_input_virtualInput.emit(...)`
- `core_input_virtualInput.deleteDevice(...)`
- `getVirtualInputManager(...)`
- `core_input_actions.triggerDown(...) / triggerUp(...) / triggerDownUp(...)`
- `triggerInputAction(...)`
- `ActionMap.triggerBindingByNameDigital(...)`
- `ActionMap.triggerBindingByNameAnalogue(...)`

These are promising as fallback levers if we need to emulate a click or action.

### Not confirmed: direct VR controller pose/buttons in Lua
What we do *not* see in the dump:

- No clearly named functions such as `OpenXR.getControllerPose`, `OpenXR.getHandPose`, `OpenXR.getActionState`, etc.
- No obvious VR-controller-specific input functions beyond the general input/action-map systems.

So from a “verified API” perspective, it would be risky to design a solution that depends on direct controller pose/button reads in Lua.

## Feasibility assessment

### Feasible path (high confidence)
**Use the existing mouse-ray + mouse-click shotgun path and rely on VR controller mouse emulation.**

Why this is likely to work well:
- Your in-game report already indicates the controller pointer and trigger behave like standard UI interaction (which is usually mouse-like behavior in BeamNG VR).
- The shotgun uses mouse-ray and mouse-click surfaces that are present in the dump.
- Damage is already wired correctly through `BulletDamage`.

This approach has the best chance of working across versions because it stays within the verified, widely used input surfaces.

### Stretch path (medium confidence)
If the VR trigger does *not* register as mouse button 0 in all contexts, we can likely add a compatibility layer that programmatically fires the shot by:

- Triggering a custom action via `core_input_actions.triggerDownUp(...)`, `triggerInputAction(...)`, or `ActionMap.triggerBindingByNameDigital(...)`, and
- Handling that action inside the mod to call the same `_fireShot()` path.

This still depends on action naming and binding behavior that the dump doesn’t fully document, so it would require empirical testing.

### Risky path (low confidence, not recommended first)
Trying to aim directly from controller pose (true “gun in hand” independent of cursor) appears blocked by the verified API surface in the 0.38 dump. That would likely require undocumented APIs or engine support outside the dump.

## Recommended implementation plan

1. **First, test the current shotgun unchanged in VR**:
   - Unholster via the VR pointer.
   - Aim with the right-hand pointer.
   - Pull the trigger.
2. If firing doesn’t register consistently:
   - Add a small, guarded input bridge that can trigger the existing fire path via one of the verified input-trigger APIs.
   - Keep the mouse-click path intact as the default.
3. Only if we want “true controller pose aiming,” treat it as an engine-research task rather than a mod-only task.

## Bottom line
Given the verified VR + input APIs in the dump and the way this mod already fires shots, the “pointer to aim + trigger to shoot” behavior looks **very feasible** *without* needing new VR-specific Lua APIs — provided BeamNG VR continues to map the controller pointer/trigger into mouse-style input in gameplay contexts.
