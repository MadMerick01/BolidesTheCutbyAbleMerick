# AI topic

## Purpose
Document GE-level AI controls exposed via `scenario/scenariohelper`, plus the vehicle-side AI hooks used by this mod for follow/chase/flee behaviors. The dump only lists the scenario helper APIs; vehicle-side `ai.*` functions live in the vehicle Lua context and are not enumerated in the GE dump.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50715-L50733】

## Common tasks
- Set an AI target vehicle via `scenario/scenariohelper.setAiTarget`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50715-L50728】
- Change AI behavior modes with `scenario/scenariohelper.setAiMode` (e.g., follow, chase).【F:docs/beamng-api/raw/api_dump_0.38.txt†L50723-L50726】
- Configure paths/routes with `scenario/scenariohelper.setAiPath` and `scenario/scenariohelper.setAiRoute`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50721-L50726】
- Tune aggressiveness and avoidance using `scenario/scenariohelper.setAiAggression` and `scenario/scenariohelper.setAiAvoidCars`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50725-L50733】

## Verified APIs (from dump)
Scenario helper (GE):
- `scenario/scenariohelper.trackVehicle(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50715-L50718】
- `scenario/scenariohelper.setAiTarget(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50719】
- `scenario/scenariohelper.setAiMode(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50723-L50726】
- `scenario/scenariohelper.setAiPath(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50725-L50727】
- `scenario/scenariohelper.setAiRoute(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50720-L50723】
- `scenario/scenariohelper.setAiAvoidCars(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50726-L50729】
- `scenario/scenariohelper.setAiAggressionMode(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50728-L50730】
- `scenario/scenariohelper.setAiAggression(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50731-L50733】

## Notes / gotchas
- Vehicle-side `ai.*` helpers (e.g., `ai.setMode`, `ai.setSpeedMode`, `ai.setAggression`) run inside the vehicle Lua VM and are not present in the GE dump; always guard them (`pcall`, `nil` checks) and prefer queueing them through `veh:queueLuaCommand` as done in mod AI helpers.【F:lua/ge/extensions/events/fireAttack.lua†L368-L452】
- Use `scenario/scenariohelper.queueLuaCommand` or `queueLuaCommandByName` for targeted vehicle-side script execution if you need GE-driven AI orchestration (see vehicle Lua context notes).【F:docs/beamng-api/raw/api_dump_0.38.txt†L50717-L50721】

## Example usage patterns (mod-specific)
- The mod queues vehicle-side AI scripts to switch between follow and chase behaviors, adjusting speed, aggression, and collision avoidance for robber/burnside events.【F:lua/ge/extensions/events/fireAttack.lua†L368-L452】
