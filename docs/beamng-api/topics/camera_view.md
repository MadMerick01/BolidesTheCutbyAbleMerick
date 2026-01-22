# Camera / view topic

## Purpose
Document camera APIs used to detect view state (e.g., first-person/inside camera) and to query camera transforms. The dump exposes both global camera helpers and the `core_camera` module for more detailed control.【F:docs/beamng-api/raw/api_dump_0.38.txt†L23-L29】【F:docs/beamng-api/raw/api_dump_0.38.txt†L160-L162】【F:docs/beamng-api/raw/api_dump_0.38.txt†L440-L443】【F:docs/beamng-api/raw/api_dump_0.38.txt†L12688-L12733】

## Common tasks
- Read camera position or transform via `getCameraPosition` and `getCameraTransform`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L23-L24】【F:docs/beamng-api/raw/api_dump_0.38.txt†L158-L161】
- Adjust camera FOV with `setCameraFovRad` / `setCameraFovDeg` when needed.【F:docs/beamng-api/raw/api_dump_0.38.txt†L23-L29】【F:docs/beamng-api/raw/api_dump_0.38.txt†L440-L442】
- Query camera mode or interior status with `core_camera.isCameraInside` and active camera name helpers.【F:docs/beamng-api/raw/api_dump_0.38.txt†L12688-L12718】【F:docs/beamng-api/raw/api_dump_0.38.txt†L12730-L12733】

## Verified APIs (from dump)
Global camera helpers:
- `getCameraTransform(...)`, `getCameraPosition(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L23-L24】【F:docs/beamng-api/raw/api_dump_0.38.txt†L158-L161】
- `setCameraFovRad(...)`, `setCameraFovDeg(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L23-L29】【F:docs/beamng-api/raw/api_dump_0.38.txt†L440-L442】

Core camera module:
- `core_camera.isCameraInside(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L12688-L12718】
- `core_camera.getActiveCamNameByVehId(...)` and `core_camera.getActiveGlobalCameraName(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L12688-L12733】
- `core_camera.getPositionXYZ(...)`, `core_camera.getForward(...)`, `core_camera.getRight(...)` for directional queries.【F:docs/beamng-api/raw/api_dump_0.38.txt†L12697-L12721】

## Notes / gotchas
- `core_camera.getActiveCamName(...)` is used in the mod but is **not** listed in the dump; keep a guard and fallback (e.g., `getActiveCamNameByVehId`) when available.【F:docs/beamng-api/raw/api_dump_0.38.txt†L12688-L12733】【F:lua/ge/extensions/FirstPersonShoot.lua†L49-L74】
- Camera mode detection is best-effort; combine `isCameraInside` checks with name heuristics to handle different camera presets safely.【F:lua/ge/extensions/FirstPersonShoot.lua†L54-L74】

## Example usage patterns (mod-specific)
- First-person shooting checks active camera name and `core_camera.isCameraInside` before allowing aim/fire input.【F:lua/ge/extensions/FirstPersonShoot.lua†L49-L88】
