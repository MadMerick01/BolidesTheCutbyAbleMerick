# Vehicle damage topic

## Purpose
Capture the APIs used to apply damage/deformation or trigger vehicle-side effects. The dump exposes some scenario helper utilities (`breakBreakGroup`, `triggerDeformGroup`, and queue helpers), while many per-vehicle damage calls run in the vehicle Lua context and must be guarded.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50719-L50733】

## Common tasks
- Queue vehicle-side scripts with `scenario/scenariohelper.queueLuaCommand` or `queueLuaCommandByName` for targeted damage effects.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50721】
- Trigger break groups or deform groups via `scenario/scenariohelper.breakBreakGroup` and `triggerDeformGroup`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50720-L50733】
- Use vehicle-context APIs for wheels, beams, and breakgroups (guarded, not listed in the GE dump).【F:lua/ge/extensions/events/deflateRandomTyre.lua†L54-L77】

## Verified APIs (from dump)
Scenario helper (GE):
- `scenario/scenariohelper.queueLuaCommand(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50719-L50721】
- `scenario/scenariohelper.queueLuaCommandByName(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50720】
- `scenario/scenariohelper.breakBreakGroup(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50720-L50722】
- `scenario/scenariohelper.triggerDeformGroup(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50731-L50733】

## Notes / gotchas
- `veh:queueLuaCommand(...)` and `be:queueObjectLuaCommand(...)` are widely used but not listed in the GE dump; always wrap with guards and fallbacks when calling them from GE code.
- Vehicle-side helpers like `wheels.setWheelPressure` or breakgroup lists vary by vehicle and version; probe availability before use and prefer fallback logic.【F:lua/ge/extensions/events/deflateRandomTyre.lua†L54-L77】

## Example usage patterns (mod-specific)
- Bullet hit logic builds a payload and queues it inside the player vehicle to deform parts, break beams, and deflate tires with a safe fallback path.
- Random tyre deflation queues a vehicle-side script that probes the wheels API and sets pressure to zero when available.【F:lua/ge/extensions/events/deflateRandomTyre.lua†L54-L77】
