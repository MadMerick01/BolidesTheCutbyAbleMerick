# Traffic topic

## Purpose
Document traffic system APIs for spawning, managing, and querying traffic vehicles. The dump exposes the core traffic module (`gameplay_traffic`) and traffic spawn utilities (`gameplay_traffic_trafficUtils`).【F:docs/beamng-api/raw/api_dump_0.38.txt†L11690-L11750】【F:docs/beamng-api/raw/api_dump_0.38.txt†L7319-L7334】

## Common tasks
- Enable or disable traffic via `gameplay_traffic.activate`, `deactivate`, and `toggle`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11703-L11720】
- Spawn traffic with `gameplay_traffic.setupTraffic`, `setupCustomTraffic`, and `spawnTraffic`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11739-L11745】
- Query traffic counts and IDs via `getNumOfTraffic`, `getTrafficAiVehIds`, and `getTrafficList`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11705-L11750】
- Find safe spawn points and create traffic groups using `gameplay_traffic_trafficUtils.findSpawnPoint*` and `createTrafficGroup`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L7319-L7333】

## Verified APIs (from dump)
Traffic core (`gameplay_traffic`):
- `activate`, `deactivate`, `toggle`, `setupTraffic`, `setupCustomTraffic`, `spawnTraffic`, `removeTraffic`, `scatterTraffic`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11702-L11745】
- `getTraffic`, `getTrafficList`, `getTrafficData`, `getTrafficPool`, `getTrafficVars`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11712-L11750】
- `getNumOfTraffic`, `getTrafficAmount`, `getTrafficAiVehIds`, `setTrafficVars`, `setActiveAmount`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11705-L11736】

Traffic spawn helpers (`gameplay_traffic_trafficUtils`):
- `findSafeSpawnPoint`, `findSpawnPoint`, `findSpawnPointOnLine`, `findSpawnPointOnRoute`, `findSpawnPointRadial`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L7319-L7333】
- `createTrafficGroup`, `createPoliceGroup`, `placeTrafficVehicles`, `getNearestTrafficVehicle`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L7323-L7331】
- `getRoleConstructor`, `checkSpawnPoint`, `finalizeSpawnPoint`, `getTrafficGroupFromFile`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L7320-L7333】

## Notes / gotchas
- Traffic APIs are GE-level systems; vehicle-side AI tuning still requires `veh:queueLuaCommand` and `ai.*` in the vehicle context for individual behaviors (guard those calls).【F:lua/ge/extensions/events/fireAttack.lua†L368-L452】
- `gameplay_traffic` owns lifecycle hooks such as `onClientStartMission` and `onTrafficStarted`; call setup methods after the traffic system is initialized in mission flow if needed.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11702-L11747】

## Example usage patterns (mod-specific)
- The mod currently uses bespoke spawned AI vehicles rather than global traffic; these APIs are the verified path for future traffic/police expansions.【F:lua/ge/extensions/events/RobberEMP.lua†L214-L285】
