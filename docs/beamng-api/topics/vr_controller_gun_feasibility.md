# VR pistol implementation plan (BeamNG 0.38 dump + `docs/Vr_files` review)

## Scope for this phase
- **Pistol only** (no rock/throw behavior in this phase).
- **Functional holding only**:
  - “Holding” is represented by HUD/inventory equip state (`hudEquippedWeapon == "pistol"`).
  - No weapon mesh, no hand-attached prop, no physical pickup interaction yet.

## Short answer
Yes, this is feasible with the current architecture, but we should enforce strict mode separation:

- **Desktop (flat-screen):** keep existing camera+mouse flow unchanged.
- **VR with tracked controller:** aim and fire from right-hand controller pointer + trigger action.
- **VR without valid controller tracking:** block firing (no mouse fallback in VR).

This is required because camera-origin mouse rays are not aligned with right-hand pointer origin in VR.

---

## What the new `docs/Vr_files` confirms

### 1) OpenXR state is available for runtime gating
`docs/Vr_files/openxr.lua` exposes state fields like:
- `enabled`
- `sessionRunning`
- `headsetActive`
- `controller0Active` / `controller1Active`
- `controller0poseValid` / `controller1poseValid`

These are enough to gate behavior by mode (desktop vs VR tracked vs VR untracked).

### 2) Action system supports explicit gameplay trigger flow
`docs/Vr_files/actions.lua` confirms action-trigger APIs:
- `triggerDown(actionName)`
- `triggerUp(actionName)`
- `triggerDownUp(actionName)`

So adding a dedicated gameplay action (`btc_fireWeapon`) is consistent with the engine input architecture.

### 3) Virtual input exists but should remain fallback-only
`docs/Vr_files/virtualInput.lua` confirms synthetic input device/event APIs via `getVirtualInputManager()`.
Use this only if action-map flow cannot satisfy VR trigger routing.

### 4) OpenXR actions are already bound through standard action maps
`docs/Vr_files/openxr.json` and `keyboard_openxr.json` show OpenXR-related actions are normal action-map citizens, which supports adding our own mod action for firing.

---

## Hard mode separation (implementation rule)

## A) Desktop / flat-screen (no VR session or no tracked VR controllers)
- **Aim source:** existing camera→mouse raycast path (`getCameraMouseRay`, current `FirstPersonShoot` flow).
- **Fire input:** mouse click.
- **Behavior:** unchanged from current desktop implementation.

## B) VR active + right controller tracked and pose valid
- **Aim source:** right-hand VR pointer ray (controller pointer/cursor ray).
- **Fire input:** dedicated action (`btc_fireWeapon`) bound to VR trigger.
- **Behavior:** mouse firing is ignored/disabled in this mode.

## C) VR active but right controller not tracked or pose invalid
- **Aim source:** none (invalid).
- **Fire input:** ignored.
- **Behavior:** no firing; optional debug/toast like “Controller not tracked / pose invalid”.
- **Important:** do not fallback to camera/mouse in VR.

---

## Input architecture
Use one internal fire-intent path, but with strict gating by mode:

- Desktop mode:
  - `fireIntent = mouseClick`
- VR tracked mode:
  - `fireIntent = btc_fireWeapon action`
- VR untracked mode:
  - `fireIntent = false`

Then feed `fireIntent` into the same centralized shot execution logic (cooldown/ammo/damage) in the existing `_fireShot()` flow.

---

## Why no mouse firing in VR
In VR, the camera/headset origin differs from the right-hand pointer ray origin. If firing uses camera→mouse ray while the player is aiming with right-hand pointer, shots become spatially misaligned. Therefore, VR must use controller-pointer aiming + trigger action only when tracked.

---

## Phased plan

## Phase 1 (now): stable pistol input behavior
1. Add action `btc_fireWeapon` in mod action JSON.
2. Bind VR trigger to `btc_fireWeapon` in VR bindings.
3. Keep desktop mouse-click firing unchanged.
4. Add mode gate checks (VR tracked vs VR untracked).
5. Disable/ignore mouse firing whenever VR tracked mode is active.
6. Add optional debug log/toast for blocked fire in VR-untracked mode.

## Phase 2 (after validation): harden compatibility
7. Add diagnostics around mode transitions (menu/gameplay, recenter, map reload).
8. Keep virtual input bridge as optional fallback only if action routing fails.

## Deferred (explicitly out of scope)
- Rock/throw system.
- Weapon mesh/hand prop attachment.
- Physical pickup interactions.

---

## Immediate next tasks (small PR-ready)
1. Create `btc_fireWeapon` action + bindings.
2. Refactor fire input sampling to compute mode-gated `fireIntent`.
3. Ensure `FirstPersonShoot` consumes pointer-based aim in VR tracked mode only.
4. Add explicit no-fire behavior for VR-untracked mode.
5. Validate with VR matrix:
   - VR tracked in gameplay
   - VR tracking loss/recovery
   - menu focus transitions
   - map reload
