# Vehicle Lua context topic

## Purpose
Document how the mod executes scripts inside the vehicle Lua VM for per-vehicle effects (damage, AI control, electrics), and which GE-side helpers can queue those scripts. The dump provides GE helpers in `scenario/scenariohelper`, while vehicle-side globals/methods must be guarded because they are not listed in the GE dump.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50721】

## Common tasks
- Queue vehicle-side scripts using `scenario/scenariohelper.queueLuaCommand` or `queueLuaCommandByName` when you have the vehicle name/id in GE context.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50721】
- Prefer `veh:queueLuaCommand(...)` on a vehicle object when available for direct control (guarded, not in dump).
- Use vehicle-side globals like `ai`, `wheels`, and `electrics` in queued scripts to modify behavior safely with checks.【F:lua/ge/extensions/events/deflateRandomTyre.lua†L54-L77】【F:lua/ge/extensions/events/emp.lua†L212-L267】

## Verified APIs (from dump)
Scenario helper queue helpers:
- `scenario/scenariohelper.queueLuaCommand(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50719-L50721】
- `scenario/scenariohelper.queueLuaCommandByName(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50720】

## Notes / gotchas
- Vehicle object methods such as `veh:queueLuaCommand`, `veh:getPosition`, `veh:setPositionRotation`, `veh:getId`, and vehicle-side globals (`ai`, `wheels`, `electrics`) are **not** listed in the GE dump; always guard and fall back when invoking them.【F:lua/ge/extensions/events/deflateRandomTyre.lua†L54-L77】【F:lua/ge/extensions/events/emp.lua†L212-L267】
- Vehicle Lua context is a separate VM: avoid heavy GE calls and pass only needed data in the queued payload string to keep execution deterministic.

## Example usage patterns (mod-specific)
- EMP logic queues a payload into the vehicle to toggle ignition and AI state with guarded access to `electrics` and `ai` globals.【F:lua/ge/extensions/events/emp.lua†L212-L267】
- Tyre deflation queues a vehicle-side script that probes wheel APIs before attempting to set pressure values.【F:lua/ge/extensions/events/deflateRandomTyre.lua†L54-L77】
