# VR controller gun feasibility (BeamNG 0.38 dump + `docs/Vr_files` review)

## Short answer
Yes — the new OpenXR/action/input files strengthen the case that we can ship a practical VR weapon flow now:

- **Hold a rock/pistol** via your existing HUD weapon-equip flow.
- **Aim with pointer/cursor ray** (already how your VR right-hand pointer behaves).
- **Shoot on trigger** by keeping mouse-click as default and adding an action-based fallback bridge.

The files still do **not** expose a clear Lua API for direct per-controller pose sampling (`getRightControllerPose`, etc.), so cursor/ray-driven aiming remains the safest implementation path.

---

## What is newly useful from `docs/Vr_files`

### 1) OpenXR module exposes runtime state, not controller transforms
`docs/Vr_files/openxr.lua` shows rich OpenXR state notifications (`controller0Active`, `controller1Active`, `controller0poseValid`, `controller1poseValid`, refresh/session fields) and GUI hooks. This is useful for **feature gating and diagnostics** ("VR active? controllers tracked?") but it does not provide direct pose/button read functions for gameplay Lua.

### 2) Action system gives a robust trigger path
`docs/Vr_files/actions.lua` confirms we can programmatically invoke input actions with:

- `triggerDown(actionName)`
- `triggerUp(actionName)`
- `triggerDownUp(actionName)`

That gives us a clean fallback if VR trigger-to-mouse mapping is inconsistent in some contexts.

### 3) Virtual input manager exists for synthetic devices
`docs/Vr_files/virtualInput.lua` confirms device registration + event emission via `getVirtualInputManager()` and `emitEvent(...)`. This is a deeper fallback if action-map triggering alone isn’t enough.

### 4) OpenXR actions are already registered as normal input actions
`docs/Vr_files/openxr.json` + `keyboard_openxr.json` show OpenXR controls are wired through the same action/binding pipeline (e.g., enable/center headset). This is an important signal that adding **our own gameplay action** for VR fire is aligned with engine patterns.

---

## How this maps to your current mod code

### Already in place (good news)
- `FirstPersonShoot` already does camera ray aiming and shot application (`getCameraMouseRay`, `cameraMouseRayCast/castRay`, `BulletDamage.trigger(...applyDamage=true)`).
- It currently fires on `ui_imgui.IsMouseClicked(0)`.
- HUD weapon equip state in `bolidesTheCut.lua` already supports pistol/EMP switching and mouse-based use.

So the lowest-risk VR path is still to preserve this mouse pathway and add a compatibility trigger path.

---

## Implementation plan: “hold rock/pistol + shoot in VR”

## Phase 1 — Ship usable VR now (no engine-risk)
1. **Keep cursor-ray aiming as primary**
   - Do not replace `getCameraMouseRay` aiming.
   - Treat VR pointer as the authoritative aim source.

2. **Use existing equip state as “holding”**
   - When weapon is equipped (`hudEquippedWeapon == "pistol"` / future `"rock"`), treat that as held in VR.
   - Start with UI/inventory truth first; postpone 3D hand-attached props.

3. **Add a new gameplay fire action**
   - Define an action like `btc_fireWeapon` in the mod’s action JSON.
   - Bind it to a keyboard fallback for desktop testing.
   - Handle this action by calling the same internal shot path as mouse click.

4. **Input handling rule**
   - Fire if **mouse click OR `btc_fireWeapon` action** is received.
   - Keep cooldown/ammo/damage logic centralized in existing `FirstPersonShoot._fireShot()` path.

## Phase 2 — VR compatibility bridge
5. **If trigger fails to map to mouse in some contexts**
   - Use `core_input_actions.triggerDownUp("btc_fireWeapon")` from a tiny bridge when VR trigger signal is detected by available bindings.
   - Prefer action-map route before virtual device emulation.

6. **Only if necessary: virtual device route**
   - Use `core_input_virtualInput` style flow to emit a digital control that maps to `btc_fireWeapon`.
   - Keep behind a feature flag; this is more complex and version-sensitive.

## Phase 3 — “holding” polish (optional)
7. **Rock as first throw/use prototype**
   - Add `rock` to HUD inventory/equip list.
   - Reuse the same action trigger architecture (`btc_useWeapon`) to invoke throw/hit logic.

8. **Visual hand-prop polish (later)**
   - After controls are stable, attach world prop models to camera/hand-approx transform.
   - Because direct controller pose API is not clearly exposed in these Lua docs, start with camera-relative offset, then iterate if deeper APIs appear.

---

## Risk/benefit summary

### High confidence
- Pointer aim + trigger/mouse click shooting.
- Action-based fallback trigger wiring.
- Inventory/equip-driven “holding” state.

### Medium confidence
- Synthetic input bridge via action-map triggers in all gameplay states.

### Lower confidence
- True per-hand pose-driven weapon transform purely from documented Lua OpenXR APIs.

---

## Recommended immediate next tasks (small PR-sized)
1. Add `btc_fireWeapon` action + default desktop binding.
2. In shooting update path, accept `mouse click OR action-fired`.
3. Add debug toast/log when shot origin is mouse vs action (for VR testing).
4. Run a VR matrix test:
   - seated/standing
   - menu vs gameplay transitions
   - map reload
   - with/without UI focus

If this passes, you’ll have a stable “hold pistol and shoot in VR” baseline. Then we can add rock behavior on top of the same input abstraction without redoing the VR plumbing.
