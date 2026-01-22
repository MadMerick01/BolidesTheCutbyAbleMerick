# Vehicle objects / scenetree topic

## Purpose
Capture GE-level object lookup helpers used to locate vehicles and world objects. These APIs are in the global table and are the safest verified entry points for fetching vehicles by ID or class in GE code.【F:docs/beamng-api/raw/api_dump_0.38.txt†L37-L38】【F:docs/beamng-api/raw/api_dump_0.38.txt†L104-L115】【F:docs/beamng-api/raw/api_dump_0.38.txt†L420-L456】

## Common tasks
- Resolve an object by ID with `getObjectByID`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L440-L443】
- Iterate vehicles using `getAllVehiclesByType` or `activeVehiclesIterator` when you need GE-side loops. 【F:docs/beamng-api/raw/api_dump_0.38.txt†L37-L38】【F:docs/beamng-api/raw/api_dump_0.38.txt†L452-L456】
- Find scene objects by class with `getObjectsByClass`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L113-L115】

## Verified APIs (from dump)
Global helpers:
- `getObjectByID(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L440-L443】
- `getAllVehiclesByType(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L37-L38】
- `activeVehiclesIterator(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L452-L456】
- `getObjectsByClass(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L113-L115】
- `getClosestVehicle(...)` (for nearest-vehicle heuristics).【F:docs/beamng-api/raw/api_dump_0.38.txt†L452-L454】

## Notes / gotchas
- `be:getObjectByID(...)` and `getObjById(...)` are used in the mod but are not listed in the GE dump; prefer `getObjectByID` or guard the call when using those helpers for compatibility.【F:docs/beamng-api/raw/api_dump_0.38.txt†L440-L443】【F:lua/ge/extensions/events/fireAttack.lua†L650-L655】
- `scenetree.findClassObjects` / `scenetree.findObject` usage is outside the dump scope; keep guards when using the scenetree APIs directly.【F:lua/ge/extensions/bolidesTheCut.lua†L352-L355】

## Example usage patterns (mod-specific)
- Fire attack and robber events resolve spawned vehicle objects using `be:getObjectByID` / `getObjById` fallbacks when available.【F:lua/ge/extensions/events/fireAttack.lua†L650-L655】
- Nearby vehicle selection uses `scenetree.findClassObjects` and `scenetree.findObject` to scan for BeamNGVehicle instances.【F:lua/ge/extensions/bolidesTheCut.lua†L352-L369】
