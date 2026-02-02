# Preload Parking Report

## Goal
Introduce a new Lua helper that selects a parking spot far enough from the player (>= 300m) for preloaded robber vehicles, and reuse that selection whenever the robber vehicle is stashed back after an event.

## New module: `PreloadParking.lua`
**Purpose:** Query the gameplay parking system for parking spots, cache them briefly, and pick the farthest candidate beyond a minimum distance from the player.

### Responsibilities
- **Find parking spots** using the gameplay parking API with safe fallbacks.
- **Cache** results for a short TTL so repeated stash calls do not re-scan every frame.
- **Pick the farthest** spot beyond a configurable minimum distance (default 300m).
- **Expose** a simple `getBestSpot` API for other modules (preload event handler).

### Key methods
- `init(cfg, host)`: receives config + host for logging and player vehicle access.
- `getBestSpot(opts)`: returns `{ entry, spot, distance }` for the farthest valid spot.
- `clearCache()`: wipes cached spots (optional hook for map changes).

### Configuration
Defaults are defined in the module and can be overridden through the same config object passed into `init`:
- `preloadParkingMinDistance`: minimum distance in meters (default 300).
- `preloadParkingSearchRadius`: how far to search (default 4000).

## Integration in the preload flow

### `PreloadEventNEW.lua`
This module now:
1. **Requires** the new `PreloadParking.lua`.
2. **Initializes** it in `init(cfg, host)`.
3. **Moves vehicles** to the chosen parking spot during:
   - initial preloading (`request`)
   - stash after event (`stash`)
4. **Aborts the preload** when no valid parking spot is found so the event uses its normal FKB 200m spawn path.

### UI/Debug label
`bolidesTheCut.lua` is updated so debug output labels `preloadParking` clearly (e.g., “Preload parking spot (>=300m)”).

## Expected behavior
When the system requests a preload:
1. **Player position is captured** at the moment of the request.
2. **Parking spots are queried** (cached).
3. The **farthest spot ≥ 300m** from the player is selected.
4. The robber vehicle is moved into that parking spot.
5. If no spot is found, preloading is skipped so the event spawns via its existing FKB 200m path.
6. When the event ends, `stash` repeats the selection logic using the **current** player position and stores the vehicle at the new farthest spot (or skips if no spot is found).

## How to integrate in additional event modules (if needed)
If another event module handles custom preloads:
1. Require the new helper:
   ```lua
   local PreloadParking = require("lua/ge/extensions/events/PreloadParking")
   ```
2. Call `PreloadParking.getBestSpot({ playerPos = be:getPlayerVehicle(0):getPosition() })`.
3. Place the vehicle via `gameplay_parking.moveToParkingSpot(vehId, best.spot, true)`.
4. Skip the preload when no spot exists so the event uses its normal spawn flow.

This keeps all parking selection logic in one place and ensures consistent behavior across events.
