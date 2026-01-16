# Copilot Instructions for Bolides: The Cut

## Project Overview

**Bolides: The Cut** is a BeamNG game extension mod implementing a career robbery + chase system. The mod spawns a robber vehicle that chases the player, fires an EMP weapon to disable the player's vehicle, and triggers mission events.

**Key Technology Stack**: Lua (GE extensions) + JavaScript (UI bootstrap) + JSON (configs)

---

## Architecture

### Core Components

1. **Main Extension** ([lua/ge/extensions/bolidesTheCut.lua](lua/ge/extensions/bolidesTheCut.lua))
   - Entry point loaded by [lua/ge/modScript.lua](lua/ge/modScript.lua)
   - Manages GUI, audio, mission dialogs, and event lifecycle
   - Hosts the `EVENT_HOST` API that all events depend on
   - Safe debug drawing (via `onDrawDebug` with `pcall`)

2. **Breadcrumbs System** ([lua/ge/extensions/breadcrumbs.lua](lua/ge/extensions/breadcrumbs.lua))
   - Tracks player vehicle's path in 3D space
   - **Forward Known (FKB)**: Predicts positions 10-5000m ahead on road
   - **Travel Crumbs**: Records past positions (every 1.0m) for up to 5200m behind
   - Used by robber spawn logic to position at safe, predictable locations

3. **Robber Event** ([lua/ge/extensions/events/RobberFkb200mEMP.lua](lua/ge/extensions/events/RobberFkb200mEMP.lua)) ~1100 lines
   - Spawns robber ~200m ahead of player (using FKB)
   - Chase phase: follows player at limited speed (max 20kph)
   - EMP trigger: when within 25m, fires EMP
   - Flee phase: robber escapes after EMP hits

4. **EMP System** ([lua/ge/extensions/events/emp.lua](lua/ge/extensions/events/emp.lua))
   - Disables engine, locks brakes for 10s
   - Applies repulsive force (planets forceField) for 0.5s shock
   - Supports audio cues and hazard lights (best-effort, version-tolerant)

5. **Mission Splash Overlay** ([lua/ge/extensions/RobbedSplash.lua](lua/ge/extensions/RobbedSplash.lua))
   - Fullscreen "YOU'VE BEEN ROBBED" message with time freeze
   - Paired with `missionInfo` extension for scenario dialogs

6. **Career Money Tracker** ([lua/ge/extensions/CareerMoney.lua](lua/ge/extensions/CareerMoney.lua))
   - Safe wallet access via `career_modules_playerAttributes`
   - Formats and displays money in GUI

---

## Critical Patterns

### Event Lifecycle

Events are **fully self-contained modules** that receive a `Host` object:

```lua
local EMP = require('lua/ge/extensions/events/emp')
local function triggerManual()
  EMP.trigger({ playerId = targetId, sourceId = robberId })
end
```

Events never call parent directly; they invoke host callbacks:
- `Host.showMissionMessage()` - freeze time + show dialog
- `Host.closeMissionMessage()` - unfreeze
- `Host.setGuiStatusMessage()` - update GUI status line
- `Host.postLine(tag, msg)` - log to console

### Safe API Access Patterns

**Problem**: BeamNG APIs vary by game version. **Solution**: Always wrap in `pcall()` with fallbacks.

Example (from `emp.lua`):
```lua
if obj.setSFXSourceVolume then 
  pcall(function() obj:setSFXSourceVolume(id, vol) end) 
end
```

Example (time freeze in `bolidesTheCut.lua`):
```lua
local function getTimeScaleSafe()
  if getTimeScale then
    local ok, val = pcall(getTimeScale)
    if ok and type(val) == "number" then return val end
  end
  if simTimeAuthority and simTimeAuthority.getTimeScale then
    -- fallback...
  end
  return 1.0
end
```

### UI Bootstrap Pattern

[ui/modules/apps/BolideBootstrapApp/](ui/modules/apps/BolideBootstrapApp/) uses an **inline AngularJS directive** with **no templateUrl** (avoids 404s):

```javascript
template: '<div style="display:none"></div>',
controller: function() {
  bngApi.engineLua('extensions.load("bolidesTheCut");')
}
```

This guarantees the extension loads when the app initializes in Career mode.

### Vehicle Configurations

Vehicle `.pc` files ([vehicles/roamer/robber_light.pc](vehicles/roamer/robber_light.pc)) are JSON with:
- `mainPartName` / `mainPartPath`: base vehicle model
- `paints`: paint layers (rgba + metallic/roughness)
- `parts`: component customization (brakes, suspension, etc.)

The `robber_light`, `robber_medium`, `robber_heavy` variants use the same base but different part configs for difficulty tuning.

### Logging Convention

All modules use consistent logging:
```lua
local TAG = "MODULE_NAME"
log("I", TAG, "info message")     -- info
log("E", TAG, "error message")    -- error
log("W", TAG, "warning message")  -- warning
```

---

## Input & Settings

- **Input Binding**: [settings/inputmaps/rls_gangster_chase.json](settings/inputmaps/rls_gangster_chase.json)
  - Keyboard `[` toggles the robber event
- **Actions**: [lua/ge/extensions/core/input/actions/rls_gangsterChase.json](lua/ge/extensions/core/input/actions/rls_gangsterChase.json)
  - Defines `rlsGangsterChase.toggle` action

---

## Development Workflows

### Testing a New Event

1. Create a new file in [lua/ge/extensions/events/](lua/ge/extensions/events/):
   ```lua
   local M = {}
   function M.trigger(args) -- args.Host passed by bolidesTheCut
     -- your event logic
   end
   return M
   ```

2. Require it in [bolidesTheCut.lua](lua/ge/extensions/bolidesTheCut.lua):
   ```lua
   local MyEvent = require("lua/ge/extensions/events/myevent")
   ```

3. Add a GUI button in `drawGui()` to call `MyEvent.trigger({ Host = EVENT_HOST })`

4. Test via the ImGui window (press keys for debug mode if available)

### Adding a New Extension Module

Place in [lua/ge/extensions/](lua/ge/extensions/) and ensure:
- It exports a module `M = {}`
- All external API calls are wrapped in `pcall()` with fallbacks
- It logs errors via `log(level, tag, msg)`
- If it needs vehicle commands, use `vehicle:queueLuaCommand(cmd)` (queued, safe)

### Modifying Robber Behavior

Key tuning variables in [RobberFkb200mEMP.lua](lua/ge/extensions/events/RobberFkb200mEMP.lua):
- `CFG.maxChaseSpeedKph` (20) - limits robber speed during chase
- `CFG.empTriggerDistanceM` (25) - when to fire EMP relative to player
- `CFG.maxAheadMeters` (5000) - breadcrumb forecast range
- Chase braking/acceleration profiles in `updateChasePhase()`

---

## Common Pitfalls

1. **Never draw outside `onDrawDebug`** – can crash if vehicle scope isn't ready
2. **Always `pcall()` cross-extension calls** – other extensions may not load
3. **Use `vehicle:queueLuaCommand()` for vehicle changes** – avoids race conditions
4. **Don't assume Career mode exists** – check `M.isCareerActive()` before money access
5. **Freeze time carefully** – always restore `prevTimeScale` on dialog close

---

## Key Files Reference

| File | Purpose |
|------|---------|
| [lua/ge/modScript.lua](lua/ge/modScript.lua) | Bootstrap loader; sets manual unload mode |
| [lua/ge/extensions/bolidesTheCut.lua](lua/ge/extensions/bolidesTheCut.lua) | Main extension, GUI, event host |
| [lua/ge/extensions/breadcrumbs.lua](lua/ge/extensions/breadcrumbs.lua) | Path tracking & FKB prediction (620 lines) |
| [lua/ge/extensions/events/RobberFkb200mEMP.lua](lua/ge/extensions/events/RobberFkb200mEMP.lua) | Robber chase + EMP event (1111 lines) |
| [lua/ge/extensions/events/emp.lua](lua/ge/extensions/events/emp.lua) | EMP trigger, audio, physics (461 lines) |
| [lua/ge/extensions/RobbedSplash.lua](lua/ge/extensions/RobbedSplash.lua) | Fullscreen splash overlay |
| [ui/modules/apps/BolideBootstrapApp/](ui/modules/apps/BolideBootstrapApp/) | AngularJS app that loads extension on startup |
| [vehicles/roamer/robber_*.pc](vehicles/roamer/) | Robber vehicle configs (light/medium/heavy) |
