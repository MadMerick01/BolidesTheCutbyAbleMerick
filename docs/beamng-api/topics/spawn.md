# Spawn topic

## Purpose
Document vehicle spawning and teleport helpers for this mod. The dump exposes `core_vehicles.spawnNewVehicle` for GE spawning and a dedicated `spawn` module for placing vehicles and safe teleports.【F:docs/beamng-api/raw/api_dump_0.38.txt†L6918-L6955】【F:docs/beamng-api/raw/api_dump_0.38.txt†L50491-L50503】

## Common tasks
- Spawn a new vehicle with `core_vehicles.spawnNewVehicle` when you need a GE-side vehicle reference back. 【F:docs/beamng-api/raw/api_dump_0.38.txt†L6918-L6944】
- Use `spawn.spawnVehicle` for convenience spawns in the `spawn` module. 【F:docs/beamng-api/raw/api_dump_0.38.txt†L50491-L50499】
- Safely teleport newly spawned vehicles using `spawn.safeTeleport` after adjusting position/rotation. 【F:docs/beamng-api/raw/api_dump_0.38.txt†L50497-L50502】
- Calculate placement with `spawn.pickSpawnPoint` or `spawn.calculateRelativeVehiclePlacement` when you need spawn points relative to the player/roads. 【F:docs/beamng-api/raw/api_dump_0.38.txt†L50495-L50503】

## Verified APIs (from dump)
Core spawner:
- `core_vehicles.spawnNewVehicle(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L6918-L6944】

Spawn module:
- `spawn.spawnVehicle(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50491-L50499】
- `spawn.safeTeleport(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50497-L50502】
- `spawn.pickSpawnPoint(...)`, `spawn.calculateRelativeVehiclePlacement(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L50495-L50503】
- `spawn.spawnPlayer(...)`, `spawn.spawnCamera(...)`, `spawn.teleportToLastRoad(...)` for mission-level placement helpers.【F:docs/beamng-api/raw/api_dump_0.38.txt†L50497-L50502】

## Notes / gotchas
- The dump does **not** list `core_vehicle_manager.spawnNewVehicle`, even though some builds have it; keep guards/fallbacks when trying multiple spawners.【F:docs/beamng-api/raw/api_dump_0.38.txt†L2305-L2330】【F:lua/ge/extensions/events/RobberEMP.lua†L214-L285】
- After spawning, call `spawn.safeTeleport` or explicit position/rotation setters to ensure vehicles settle where expected (especially when using custom spawn transforms).【F:docs/beamng-api/raw/api_dump_0.38.txt†L50497-L50502】【F:lua/ge/extensions/events/safeSpawn.lua†L212-L252】

## Example usage patterns (mod-specific)
- The mod’s safe spawn helper uses `core_vehicles.spawnNewVehicle` plus `spawn.safeTeleport` to place vehicles near the player with fallback road/parking logic.【F:lua/ge/extensions/events/safeSpawn.lua†L200-L259】
- Robber/fire attack events try multiple spawners (`core_vehicles`, `core_vehicle_manager`, then `spawn.spawnVehicle`) to keep version compatibility.【F:lua/ge/extensions/events/RobberEMP.lua†L214-L285】
