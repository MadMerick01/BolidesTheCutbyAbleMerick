# BeamNG Parking System Notes (for modding)

## High-level flow

- The parking system is centered around `gameplay_parking` (`parking.lua`). It loads **sites data** (typically `city.sites.json`) and uses the `sites.parkingSpots` collection to find, validate, and move vehicles into parking spots. It only runs when the parking system is active (via `setState(true)` or `activate`).【F:docs/parking code/parking.lua†L1-L101】【F:docs/parking code/parking.lua†L560-L671】
- Parking spots are cached near the player/focus position and refreshed when the focus moves far enough (`checkRadius`, `lookDist`, `areaRadius`). This cache is filtered by probability rules and other checks, then used to respawn parked vehicles when they’re far enough from the player to be hidden.【F:docs/parking code/parking.lua†L8-L25】【F:docs/parking code/parking.lua†L760-L922】

## Core data structures & fields to be aware of

### Sites + parking spot data

- The system relies on **sites data** (loaded with `gameplay_city.loadSites()` or `gameplay_sites_sitesManager.loadSites(file)`), which must include `sites.parkingSpots.sorted` and `sites.parkingSpots.objects` for lookup and occupancy tracking.【F:docs/parking code/parking.lua†L29-L74】
- Each parking spot (`ps`) is expected to have:
  - `pos`, `rot`, `scl` (position, rotation, scale) used for placement and fit checks. The flowgraph `Parking Spot` node exposes these fields directly.【F:docs/parking code/parkingSpot.lua†L16-L25】【F:docs/parking code/parkingSpot.lua†L102-L118】
  - `customFields.tags` used to influence parking behavior (see “Tags” below).【F:docs/parking code/parking.lua†L79-L151】
  - `id`, `name`, and `vehicle` fields used for identification and occupancy tracking.【F:docs/parking code/parking.lua†L129-L151】

### Parking system runtime tables

- **`parkedVehIds` / `parkedVehData`**: list + metadata for parked vehicles managed by the system. Each entry includes the current spot id, active radius, and flags like `_teleport` and `randomPaint`.【F:docs/parking code/parking.lua†L17-L24】【F:docs/parking code/parking.lua†L514-L538】
- **`trackedVehData`**: runtime info for **player or tracked vehicles** used to detect parking validity (inside/outside, parked, etc.). This is updated each frame by `trackParking`.【F:docs/parking code/parking.lua†L18-L24】【F:docs/parking code/parking.lua†L425-L520】

## Useful parking fields and tags

### Parking variables (tune behavior)

The parking system uses a `vars` table you can customize via `gameplay_parking.setParkingVars`:

- `precision` (0..1): parking accuracy required for “valid” parking detection.
- `neatness` (0..1): how neatly parked cars are placed (less offset/rotation when higher).
- `parkingDelay`: seconds a vehicle must be parked to be considered “valid”.
- `baseProbability`: global probability multiplier for choosing spots.
- `activeAmount`: limit for active (visible) pooled parked cars.

These defaults are defined in `resetParkingVars` and are also settable in the flowgraph node `Parking System Parameters`.【F:docs/parking code/parking.lua†L360-L399】【F:docs/parking code/parkingParams.lua†L13-L78】

### Parking spot tags (behavior modifiers)

Parking spot tags are read from `parkingSpot.customFields.tags`:

- `forwards` / `backwards`: forces parking direction in `moveToParkingSpot`.
- `perfect`: disables random position/rotation offsets (neatness randomization).
- `street`: enables vehicle map tracking so AI can avoid parked vehicles on the street.
- `ignoreOthers`: spot is ignored if another vehicle is present.
- `nightTime` / `dayTime`: biases spot probability by time-of-day.

These tags directly affect move/reset and filtering logic.【F:docs/parking code/parking.lua†L79-L151】【F:docs/parking code/parking.lua†L200-L266】

## Key functions + what they do

### Sites / parking spot discovery

- `loadSites()` / `setSites(data)`: load or override sites data; **no sites = no parking**.【F:docs/parking code/parking.lua†L29-L74】
- `findParkingSpots(pos, minRadius, maxRadius)`: radial query of `sites.parkingSpots`, sorted by distance.【F:docs/parking code/parking.lua†L158-L188】
- `filterParkingSpots(psList, filters)`: filters for occupancy and probability (time-of-day, base probability).【F:docs/parking code/parking.lua†L196-L266】
- `getRandomParkingSpots(originPos, minDist, maxDist, minCount, filters)`: chooses a random subset of spots, biased by distance.【F:docs/parking code/parking.lua†L292-L353】

### Spot fit + movement

- `checkParkingSpot(vehId, parkingSpot)`: rejects occupied or too-large spots and performs `vehicleFits` checks.【F:docs/parking code/parking.lua†L128-L156】
- `moveToParkingSpot(vehId, parkingSpot, lowPrecision)`: teleports a vehicle into a spot, applies random offsets, and sets tracking/occupancy state.【F:docs/parking code/parking.lua†L79-L151】
- `forceTeleport(vehId, psList, minDist, maxDist)`: force-respawns a parked vehicle into the next valid spot.【F:docs/parking code/parking.lua†L268-L290】

### Parking system lifecycle

- `setupVehicles(amount, options)`: spawns vehicles and tries to park them; **returns false** if no spots are found and `ignoreParkingSpots` is not set.【F:docs/parking code/parking.lua†L577-L668】
- `activate(vehIds, ignoreScatter)` / `deactivate()`: toggles parked vehicle pooling and scattering.【F:docs/parking code/parking.lua†L560-L575】【F:docs/parking code/parking.lua†L674-L679】
- `onUpdate(dt, dtSim)`: main update loop that refreshes spot cache and respawns vehicles only when far enough away.【F:docs/parking code/parking.lua†L760-L922】

### Player/vehicle parking tracking

- `enableTracking(vehId, autoDisable)` + `trackParking(vehId)` detect parking validity and raise events (`enter`, `exit`, `valid`) through `onVehicleParkingStatus` hooks.【F:docs/parking code/parking.lua†L335-L423】【F:docs/parking code/parking.lua†L760-L848】
- Flowgraph node `Track Vehicle Parking` is a thin wrapper around this that outputs the current parking spot and in/out status for a vehicle id.【F:docs/parking code/parkingTrackVehicle.lua†L10-L99】

## Flowgraph nodes you can reuse

- **Parking Spot by Name** (`gameplay/sites/parkingspotByName`): resolves a parking spot using `sitesData` and `spotName` (hardcoded or input).【F:docs/parking code/parkingspotByName.lua†L10-L70】
- **Parking Spot** (`gameplay/sites/parkingspot`): unwraps spot data into name/pos/rot/scl and custom fields.【F:docs/parking code/parkingSpot.lua†L12-L118】
- **Parking System Parameters**: configures the parking system variables (`precision`, `neatness`, etc.).【F:docs/parking code/parkingParams.lua†L10-L78】

## Why the current “preload” flow is failing to resolve

From the provided flowgraph (`parking2.flow.json`):

- The **Parking Spot by Name** node (`gameplay/sites/parkingspotByName`) is hardcoded to `spotName = "start"` and only fires if a **sitesData** input is provided.【F:docs/parking code/parking2.flow.json†L434-L520】
- That `sitesData` comes from a **fileSites** node (`gameplay/sites/fileSites`), whose `file` input is driven by a **getVariable** node reading `varName = "fileSites"`. There is **no** `setVariable` for `fileSites` anywhere in this flowgraph, meaning the file path is never populated, and the sites data never loads.【F:docs/parking code/parking2.flow.json†L434-L520】

**Conclusion:** the preload flow is **not** finding a parking spot because the sites file path is never set. As a result, the `fileSites` node does not load sites data, and `parkingspotByName` has nothing to resolve—so nothing happens on load or when pressing preload.

## Recommendations for the mod

1. **Provide a valid sites file path** to the `fileSites` node (e.g., `levels/<level>/city.sites.json`) by setting the `fileSites` variable or wiring a constant string node into the `file` pin. This ensures `sitesData` is available and the `start` spot can be resolved.【F:docs/parking code/parking2.flow.json†L434-L520】
2. **Verify the `start` spot name exists** in your sites data. If the spot name differs, update the `spotName` pin to match (or parameterize it via UI).【F:docs/parking code/parking2.flow.json†L434-L520】
3. **Confirm the parking system is active** before relying on parking behavior. `gameplay_parking.setState(true)` or `activate()` is required, and no sites data means no parking logic runs at all.【F:docs/parking code/parking.lua†L52-L101】【F:docs/parking code/parking.lua†L560-L575】

## Preload system guidance (non-disruptive)

The goal is to preload a specific spot without interfering with the default parking/traffic system. Use the parking data **read-only** and avoid mutating the global parked vehicle pool.

### Suggested flowgraph approach

- **Load sites data locally** with `gameplay/sites/fileSites` and feed the `sitesData` output to `gameplay/sites/parkingspotByName`. This keeps your flowgraph self-contained and avoids overriding global sites state.【F:docs/parking code/parking2.flow.json†L612-L907】
- **Resolve the target spot** via `parkingspotByName` and then unwrap it with the `Parking Spot` node to get `pos/rot/scl` for placement or UI indicators.【F:docs/parking code/parkingspotByName.lua†L10-L70】【F:docs/parking code/parkingSpot.lua†L12-L118】

### Avoid disrupting the base system

- **Do not call** `setupVehicles` or `activate` from your preload flow; both mutate the parked vehicle pool and can affect the game’s own parking distribution and vehicle pooling behavior.【F:docs/parking code/parking.lua†L560-L668】
- **Do not override** parking vars unless needed; `setParkingVars` impacts global spawn probability and pooling behavior.【F:docs/parking code/parking.lua†L360-L399】
- If you must place a vehicle, do it **only for your controlled vehicle** and avoid marking the spot as occupied unless you truly intend to reserve it. The base system tracks occupancy via `parkingSpot.vehicle` and uses that to filter spots.【F:docs/parking code/parking.lua†L128-L151】

### Optional validation checks

- Use `checkParkingSpot` to validate spot suitability for your vehicle before moving it (ensures fit and avoids occupied spots).【F:docs/parking code/parking.lua†L128-L156】
- If you need runtime “is parked” feedback, wrap `enableTracking` / `Track Vehicle Parking` on only your vehicle. This reads parking status without changing global parking state.【F:docs/parking code/parking.lua†L335-L423】【F:docs/parking code/parkingTrackVehicle.lua†L10-L99】
