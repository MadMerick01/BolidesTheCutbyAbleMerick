--[[
Safe spawn helper: spawns a vehicle within a distance band in front of or behind the player.

Location / require:
  local SafeSpawn = require("lua/ge/extensions/events/safeSpawn")

Example:
-- local SafeSpawn = require("lua/ge/extensions/events/safeSpawn")
-- local playerVeh = be:getPlayerVehicle(0)
-- local playerPos = playerVeh:getPosition()
-- local f = playerVeh:getDirectionVector() -- raw ok; module flattens+normalizes
--
-- local res = SafeSpawn.spawn({
--   side = "infront",
--   model = "simple_traffic",
--   options = { config = "vehicles/simple_traffic/bx_base_hatch.pc" },
--   distance = 250,
--   tolerance = 50,
--   playerPos = playerPos,
--   playerForward = f,
-- })
-- if res then
--   print("Spawned id:", res.vehId, "placed:", res.placed)
-- end

Arguments:
  Required:
    side (string): "infront" or "behind" (aliases: "front", "ahead", "rear", "back")
    model (string): vehicle model/JBeam key for core_vehicles.spawnNewVehicle
    options (table): spawn options for core_vehicles.spawnNewVehicle; default {}
    distance (number): target distance from player (approximate)
    playerPos (vec3): player world position
    playerForward (vec3): player forward direction (raw ok; module flattens+normalizes)
  Optional:
    tolerance (number): default 50; distance band is [distance - tolerance, distance + tolerance]
    preferParking (boolean): default true
    parkChance (number): default 0.25; chance we try parking first
    searchRadius (number): default 1200; search radius for parking/road candidates
    maxAttempts (integer): default 800; number of random road nodes to sample
    seed (integer): optional RNG seed for deterministic testing

Integration note:
  This module is standalone and does not depend on any specific event module.
--]]

local M = {}

local function normalizeForwardFlat(forward)
  local f = vec3(forward.x, forward.y, 0)
  if f:length() < 0.0001 then
    return vec3(0, 1, 0)
  end
  return f:normalized()
end

local function parseSide(side)
  if not side then
    return nil
  end
  local s = tostring(side):lower()
  if s == "infront" or s == "front" or s == "ahead" then
    return "infront"
  end
  if s == "behind" or s == "rear" or s == "back" then
    return "behind"
  end
  return nil
end

local function inHemisphere(candidatePos, playerPos, playerForwardFlat, side)
  local dir = (candidatePos - playerPos):normalized()
  local dot = dir:dot(playerForwardFlat)
  if side == "infront" then
    return dot >= 0
  end
  return dot <= 0
end

local function inDistanceBand(candidatePos, playerPos, minD, maxD)
  local dist = playerPos:distance(candidatePos)
  return dist >= minD and dist <= maxD
end

local function relaxBand(minD, maxD)
  return math.max(0, minD - 100), maxD + 150
end

local function tryFindParkingSpots(playerPos, searchRadius)
  if not gameplay_parking then
    return nil
  end

  pcall(gameplay_parking.getParkingSpots)

  local attempts = {
    function()
      return gameplay_parking.findParkingSpots(playerPos, nil, searchRadius)
    end,
    function()
      return gameplay_parking.findParkingSpots(playerPos.x, playerPos.y, playerPos.z, searchRadius)
    end,
    function()
      return gameplay_parking.findParkingSpots(nil, nil, searchRadius)
    end,
  }

  for _, fn in ipairs(attempts) do
    local ok, res = pcall(fn)
    if ok and type(res) == "table" then
      return res
    end
  end

  return nil
end

local function pickParkingSpot(parkingSpots, playerPos, playerForwardFlat, side, minD, maxD)
  if type(parkingSpots) ~= "table" then
    return nil
  end

  for _, entry in ipairs(parkingSpots) do
    if entry and entry.ps and entry.ps.pos then
      local pos = entry.ps.pos
      if inDistanceBand(pos, playerPos, minD, maxD) and inHemisphere(pos, playerPos, playerForwardFlat, side) then
        return entry
      end
    end
  end

  return nil
end

local function pickRoadNode(playerPos, playerForwardFlat, side, minD, maxD, maxAttempts)
  local mapData = map.getMap()
  if not mapData or not mapData.nodes then
    return nil
  end

  for _ = 1, maxAttempts do
    local node = mapData.nodes[math.random(#mapData.nodes)]
    if node and node.pos then
      local pos = node.pos
      if inDistanceBand(pos, playerPos, minD, maxD) and inHemisphere(pos, playerPos, playerForwardFlat, side) then
        return node
      end
    end
  end

  return nil
end

function M.spawn(opts)
  if type(opts) ~= "table" then
    log("E", "SafeSpawn", "Missing options table")
    return nil
  end

  local side = parseSide(opts.side)
  if not side then
    log("E", "SafeSpawn", "Invalid side option")
    return nil
  end

  if not opts.model or not opts.playerPos or not opts.playerForward or not opts.distance then
    log("E", "SafeSpawn", "Missing required options")
    return nil
  end

  if opts.seed then
    math.randomseed(opts.seed)
  end

  local tolerance = opts.tolerance or 50
  local minD = math.max(0, opts.distance - tolerance)
  local maxD = opts.distance + tolerance
  local playerForwardFlat = normalizeForwardFlat(opts.playerForward)
  local preferParking = opts.preferParking ~= false
  local parkChance = opts.parkChance or 0.25
  local searchRadius = opts.searchRadius or 1200
  local maxAttempts = opts.maxAttempts or 800

  local placement = nil
  local placedType = nil

  if preferParking and math.random() < parkChance then
    local parkingSpots = tryFindParkingSpots(opts.playerPos, searchRadius)
    local entry = pickParkingSpot(parkingSpots, opts.playerPos, playerForwardFlat, side, minD, maxD)
    if not entry then
      minD, maxD = relaxBand(minD, maxD)
      entry = pickParkingSpot(parkingSpots, opts.playerPos, playerForwardFlat, side, minD, maxD)
    end

    if entry and entry.ps then
      placement = entry
      placedType = "parking"
    end
  end

  if not placement then
    local node = pickRoadNode(opts.playerPos, playerForwardFlat, side, minD, maxD, maxAttempts)
    if not node then
      minD, maxD = relaxBand(minD, maxD)
      node = pickRoadNode(opts.playerPos, playerForwardFlat, side, minD, maxD, maxAttempts)
    end
    if node then
      placement = node
      placedType = "road"
    end
  end

  if not placement then
    log("E", "SafeSpawn", "No valid spawn location found")
    return nil
  end

  local car = core_vehicles.spawnNewVehicle(opts.model, opts.options or {})
  if not car then
    log("E", "SafeSpawn", "Vehicle spawn failed")
    return nil
  end

  if placedType == "parking" then
    local ok, result = pcall(function()
      return gameplay_parking.moveToParkingSpot(car:getId(), placement.ps, true)
    end)
    if not ok or result ~= true then
      local node = pickRoadNode(opts.playerPos, playerForwardFlat, side, minD, maxD, maxAttempts)
      if not node then
        minD, maxD = relaxBand(minD, maxD)
        node = pickRoadNode(opts.playerPos, playerForwardFlat, side, minD, maxD, maxAttempts)
      end
      if not node then
        log("E", "SafeSpawn", "Failed to move vehicle to parking spot and no road fallback found")
        return nil
      end
      local pos = node.pos + vec3(0, 0, 0.5)
      local yawDeg = math.random() * 360
      local quat = quatFromEuler(0, 0, yawDeg)
      car:setPosRot(pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w)
      placedType = "road"
    end
  else
    local pos = placement.pos + vec3(0, 0, 0.5)
    local yawDeg = math.random() * 360
    local quat = quatFromEuler(0, 0, yawDeg)
    car:setPosRot(pos.x, pos.y, pos.z, quat.x, quat.y, quat.z, quat.w)
  end

  car:queueLuaCommand("electrics.setIgnitionLevel(0)")
  pcall(spawn.safeTeleport, car, car:getPosition(), car:getRotation())

  return {
    veh = car,
    vehId = car:getId(),
    placed = placedType,
    distanceTarget = opts.distance,
    tolerance = tolerance,
  }
end

return M
