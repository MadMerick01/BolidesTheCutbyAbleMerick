-- PreloadEventNEW.lua
-- Robust preload: keep a canonical robber vehicle parked and hand it off to events.

local M = {}

local PreloadParking = require("lua/ge/extensions/events/PreloadParking")

local CFG = nil
local Host = nil

local DEFAULT_MIN_PRELOAD_DISTANCE = 300.0

local S = {
  preloaded = nil,
  preloadedBySpec = {},
  activeSpecKey = nil,
  pending = nil,
  preloadInProgress = false,
  lastAttemptAt = 0,
  attemptCount = 0,
  maxAttempts = 1,
  uiGateOverride = nil,
  lastRequestedSpec = nil,
  maintenanceNextAt = 0,
  maintenanceIntervalSec = 1.0,
  lastFailure = nil,
  stats = {
    requests = 0,
    failures = 0,
    consumeCount = 0,
    consumeRetries = 0,
    stashCount = 0,
    stashRetries = 0,
    parkingFallbacks = 0,
  },
}

local function log(msg)
  if Host and Host.postLine then
    Host.postLine("PreloadEventNEW", msg)
  else
    print("[PreloadEventNEW] " .. tostring(msg))
  end
end

local function getPlayerVeh()
  if Host and Host.getPlayerVeh then
    return Host.getPlayerVeh()
  end
  if be and be.getPlayerVehicle then
    return be:getPlayerVehicle(0)
  end
  return nil
end

local function getObjById(id)
  if type(id) ~= "number" then return nil end
  if getObjectByID then return getObjectByID(id) end
  if be and be.getObjectByID then return be:getObjectByID(id) end
  return nil
end

local function getObjectPos(obj)
  if not obj or not obj.getPosition then
    return nil
  end
  local ok, pos = pcall(function()
    return obj:getPosition()
  end)
  if ok then
    return pos
  end
  return nil
end

local function getBreadcrumbs()
  if Host and Host.Breadcrumbs then
    return Host.Breadcrumbs
  end
  if extensions and extensions.breadcrumbs then
    return extensions.breadcrumbs
  end
  return nil
end

local function getPreloadSpawnPoint()
  local breadcrumbs = getBreadcrumbs()
  if not breadcrumbs or not breadcrumbs.getPreloadSpawnPoint then
    return nil
  end
  return breadcrumbs.getPreloadSpawnPoint()
end

local function getPreloadDistanceInfo()
  local spawnPoint = getPreloadSpawnPoint()
  if not spawnPoint or not spawnPoint.pos then
    return nil, "not ready"
  end
  local playerVeh = getPlayerVeh()
  local playerPos = playerVeh and playerVeh.getPosition and playerVeh:getPosition() or nil
  if not playerPos then
    return nil, "missing player position"
  end
  return {
    spawnPoint = spawnPoint,
    distance = playerPos:distance(spawnPoint.pos),
  }, nil
end

local function makeSpecKey(model, config)
  return string.format("%s::%s", tostring(model or ""), tostring(config or ""))
end

local function isPreloadedEntryValid(entry)
  if type(entry) ~= "table" then
    return false
  end

  local veh = getObjById(entry.vehId)
  if not veh then
    return false
  end

  if type(veh.queueLuaCommand) ~= "function" then
    return false
  end

  if entry.placed == "breadcrumbPreload" then
    local spawnPoint = getPreloadSpawnPoint()
    local vehPos = getObjectPos(veh)
    if spawnPoint and spawnPoint.pos and vehPos then
      if vehPos:distance(spawnPoint.pos) > 120.0 then
        return false
      end
    end
  end

  return true
end

local function safeTeleportVehicle(veh, pos, rot, opts)
  if not veh then return end
  opts = opts or {}
  if pos and rot and veh.setPositionRotation then
    pcall(function() veh:setPositionRotation(pos, rot) end)
  elseif pos and veh.setPosition then
    pcall(function() veh:setPosition(pos) end)
  elseif pos and veh.setPosRot and rot then
    pcall(function() veh:setPosRot(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w) end)
  end
  if not opts.skipSafeTeleport and spawn and spawn.safeTeleport then
    pcall(function() spawn.safeTeleport(veh, veh:getPosition(), veh:getRotation()) end)
  end
end

local function teleportWithVerify(veh, pos, rot, opts)
  if not veh or not pos then return false end
  opts = opts or {}
  local retries = tonumber(opts.retries) or 3
  local maxDist = tonumber(opts.maxDist) or 5.0

  for _ = 1, retries do
    safeTeleportVehicle(veh, pos, rot, opts)
    local current = veh.getPosition and veh:getPosition() or nil
    if current and (current - pos):length() <= maxDist then
      return true
    end
  end
  return false
end

local function makeSpawnTransform(spawnPoint, playerPos)
  if not spawnPoint or not spawnPoint.pos then
    return nil
  end
  local dir = spawnPoint.fwd or (playerPos and (spawnPoint.pos - playerPos)) or vec3(0, 1, 0)
  dir = vec3(dir.x, dir.y, 0)
  if dir:length() < 1e-6 then
    dir = vec3(0, 1, 0)
  end
  dir = dir:normalized()

  local rot = quat(0, 0, 0, 1)
  if quatFromDir then
    rot = quatFromDir(dir, vec3(0, 0, 1))
  end

  return { pos = spawnPoint.pos, rot = rot }
end

local function makeParkingTransform(spot, playerPos)
  if not spot or not spot.pos then
    return nil
  end
  return makeSpawnTransform({ pos = spot.pos, fwd = spot.rot }, playerPos)
end

local function disableVehicleAI(veh)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand([[
    if ai then
      pcall(function() ai.setMode("disabled") end)
      pcall(function() ai.setMode("none") end)
      pcall(function() ai.setAggression(0) end)
    end
  ]])
end

local function setVehicleIdle(veh)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand([[
    pcall(function() electrics.setIgnitionLevel(0) end)
    pcall(function() input.event("brake", 1, 1) end)
  ]])
end

local function ensurePrewarmAudio(opts)
  if not opts then return end
  local pv = getPlayerVeh()
  if not pv then return end
  if type(opts.prewarmAudio) == "function" then
    pcall(opts.prewarmAudio, pv)
  end
end

local function getPreferredPreloadPlacement(requireFar)
  local distanceInfo, distErr = getPreloadDistanceInfo()
  if distanceInfo and distanceInfo.spawnPoint and distanceInfo.spawnPoint.pos then
    local dist = distanceInfo.distance or 0
    if (not requireFar) or dist > DEFAULT_MIN_PRELOAD_DISTANCE then
      return {
        mode = "breadcrumb",
        spawnPoint = distanceInfo.spawnPoint,
      }, nil
    end
  end

  if PreloadParking and PreloadParking.getBestSpot then
    local best, err = PreloadParking.getBestSpot({
      minDistance = DEFAULT_MIN_PRELOAD_DISTANCE,
    })
    if best and best.spot then
      return {
        mode = "parking",
        parking = best,
      }, nil
    end
    return nil, err or distErr or "no preload placement"
  end

  return nil, distErr or "no preload placement"
end

local function spawnPreloadedVehicle(opts)
  if not opts or not opts.model then
    return nil, "missing model"
  end

  local placement, placeErr = getPreferredPreloadPlacement(true)
  if not placement then
    return nil, placeErr or "preload placement unavailable"
  end

  local playerVeh = getPlayerVeh()
  local playerPos = playerVeh and playerVeh.getPosition and playerVeh:getPosition() or nil

  local transform = nil
  if placement.mode == "breadcrumb" then
    transform = makeSpawnTransform(placement.spawnPoint, playerPos)
  elseif placement.mode == "parking" then
    transform = makeParkingTransform(placement.parking.spot, playerPos)
  end
  if not transform then
    return nil, "missing preload spawn transform"
  end

  local options = {
    config = opts.config,
    cling = true,
    autoEnterVehicle = false,
    pos = transform.pos,
    rot = transform.rot,
  }

  local veh = core_vehicles.spawnNewVehicle(opts.model, options)
  if not veh then
    return nil, "vehicle spawn failed"
  end

  local placed = "breadcrumbPreload"
  if placement.mode == "parking" then
    local parked = false
    if gameplay_parking and gameplay_parking.moveToParkingSpot and placement.parking and placement.parking.spot then
      local okMove, moved = pcall(function()
        return gameplay_parking.moveToParkingSpot(veh:getId(), placement.parking.spot, true)
      end)
      parked = okMove and moved == true
    end
    if parked then
      placed = "preloadParking"
      S.stats.parkingFallbacks = (S.stats.parkingFallbacks or 0) + 1
    end
  end

  if placed ~= "preloadParking" then
    local ok = teleportWithVerify(veh, transform.pos, transform.rot, { retries = 3, maxDist = 5.0 })
    if not ok then
      veh:delete()
      return nil, "preload teleport verification failed"
    end
  end

  disableVehicleAI(veh)
  setVehicleIdle(veh)

  return {
    veh = veh,
    vehId = veh:getId(),
    placed = placed,
  }, nil
end

function M.init(cfg, host)
  CFG = cfg
  Host = host
  if PreloadParking and PreloadParking.init then
    PreloadParking.init(cfg, host)
  end
end

function M.request(opts)
  if type(opts) ~= "table" then
    log("Request missing options table")
    return false
  end
  S.stats.requests = (S.stats.requests or 0) + 1
  if not opts.eventName then
    log("Request missing eventName")
    return false
  end
  if not opts.model then
    log("Request missing model")
    return false
  end

  S.lastRequestedSpec = {
    eventName = tostring(opts.eventName),
    model = opts.model,
    config = opts.config,
    prewarmAudio = opts.prewarmAudio,
  }

  local specKey = makeSpecKey(opts.model, opts.config)
  local existing = S.preloadedBySpec[specKey]
  if existing and isPreloadedEntryValid(existing) then
    S.preloaded = existing
    S.activeSpecKey = specKey
    return true
  end

  S.pending = {
    eventName = tostring(opts.eventName),
    model = opts.model,
    config = opts.config,
    prewarmAudio = opts.prewarmAudio,
  }

  local res, err = spawnPreloadedVehicle(S.pending)
  if not res or not res.vehId then
    S.stats.failures = (S.stats.failures or 0) + 1
    S.lastFailure = err or "preload spawn failed"
    if err then log("Preload failed: " .. tostring(err)) end
    return false
  end

  ensurePrewarmAudio(S.pending)
  local entry = {
    vehId = res.vehId,
    eventName = S.pending.eventName,
    model = S.pending.model,
    config = S.pending.config,
    specKey = specKey,
    placed = res.placed,
    createdAt = os.clock(),
  }
  S.preloaded = entry
  S.preloadedBySpec[specKey] = entry
  S.activeSpecKey = specKey
  S.pending = nil
  S.preloadInProgress = false
  S.lastFailure = nil
  return true
end

function M.updateWindow(eventName, windowStart, windowSeconds, minDelay)
  return false
end

function M.setUiGateOverride(active)
  if active == nil then
    S.uiGateOverride = nil
    return
  end
  S.uiGateOverride = active == true
end

function M.clear()
  S.pending = nil
  S.preloaded = nil
  S.preloadedBySpec = {}
  S.activeSpecKey = nil
  S.preloadInProgress = false
  S.attemptCount = 0
  S.maxAttempts = 1
  S.lastAttemptAt = 0
  S.lastRequestedSpec = nil
  S.lastFailure = nil
end

function M.hasPreloaded(eventName)
  local entry = S.preloaded
  if not entry and S.activeSpecKey then
    entry = S.preloadedBySpec[S.activeSpecKey]
  end
  if not entry then return false end
  if eventName and entry.eventName ~= eventName then return false end
  if not isPreloadedEntryValid(entry) then
    if entry.specKey then
      S.preloadedBySpec[entry.specKey] = nil
    end
    if S.preloaded == entry then
      S.preloaded = nil
    end
    return false
  end
  S.preloaded = entry
  return true
end

function M.getDebugState()
  local pendingName = S.pending and S.pending.eventName or nil
  local preloadedName = S.preloaded and S.preloaded.eventName or nil
  local spec = S.preloaded and makeSpecKey(S.preloaded.model, S.preloaded.config) or nil
  local distanceInfo = getPreloadDistanceInfo()
  local spawnPointDistance = distanceInfo and distanceInfo.distance or nil
  local spawnPointReady = distanceInfo ~= nil
  return {
    pending = pendingName,
    preloaded = preloadedName,
    specKey = spec,
    preloadedId = S.preloaded and S.preloaded.vehId or nil,
    placed = S.preloaded and S.preloaded.placed or nil,
    preloadInProgress = S.preloadInProgress,
    uiGateOverride = S.uiGateOverride,
    spawnPointReady = spawnPointReady,
    spawnPointDistance = spawnPointDistance,
    spawnPointFarEnough = spawnPointDistance ~= nil and spawnPointDistance > DEFAULT_MIN_PRELOAD_DISTANCE or false,
    lastRequestedSpec = S.lastRequestedSpec and makeSpecKey(S.lastRequestedSpec.model, S.lastRequestedSpec.config) or nil,
    lastFailure = S.lastFailure,
    stats = S.stats,
  }
end

function M.consume(eventName, transform, opts)
  if not S.preloaded then return nil, "no_preloaded_vehicle" end
  if eventName and S.preloaded.eventName ~= eventName then
    local expectedModel = opts and opts.model or nil
    local expectedConfig = opts and opts.config or nil
    if expectedModel ~= nil and expectedModel == S.preloaded.model and expectedConfig == S.preloaded.config then
      -- Allow shared preloads when the vehicle spec matches.
    else
      return nil, "event_mismatch"
    end
  end

  local veh = getObjById(S.preloaded.vehId)
  if not veh or not isPreloadedEntryValid(S.preloaded) then
    if S.preloaded and S.preloaded.specKey then
      S.preloadedBySpec[S.preloaded.specKey] = nil
    end
    S.preloaded = nil
    return nil, "preloaded_vehicle_missing"
  end

  local usedRetries = 0
  if transform and transform.pos then
    local consumeRetries = opts and tonumber(opts.consumeRetries) or 3
    local consumeMaxDist = opts and tonumber(opts.consumeMaxDist) or 5.0
    local skipSafeTeleport = opts and opts.consumeSkipSafeTeleport
    if skipSafeTeleport == nil then
      skipSafeTeleport = false
    end
    usedRetries = consumeRetries
    local ok = teleportWithVerify(veh, transform.pos, transform.rot, {
      retries = consumeRetries,
      maxDist = consumeMaxDist,
      skipSafeTeleport = skipSafeTeleport,
    })
    if not ok then
      log("Consume failed: teleport verification failed.")
      S.lastFailure = "consume teleport verification failed"
      return nil, "teleport_verification_failed"
    end
  end

  local id = S.preloaded.vehId
  S.pending = nil
  S.preloaded.placed = "event"
  S.preloaded.lastUsedAt = os.clock()
  S.preloaded.eventName = eventName or S.preloaded.eventName
  S.stats.consumeCount = (S.stats.consumeCount or 0) + 1
  S.stats.consumeRetries = (S.stats.consumeRetries or 0) + usedRetries
  S.lastFailure = nil
  return id, nil
end

function M.stash(eventName, vehId, opts)
  if type(vehId) ~= "number" then
    return false
  end
  local veh = getObjById(vehId)
  if not veh then
    return false
  end

  local placement, placeErr = getPreferredPreloadPlacement(false)
  if not placement then
    S.lastFailure = placeErr or "stash placement unavailable"
    return false
  end

  local playerVeh = getPlayerVeh()
  local playerPos = playerVeh and playerVeh.getPosition and playerVeh:getPosition() or nil
  local transform = nil
  if placement.mode == "breadcrumb" then
    transform = makeSpawnTransform(placement.spawnPoint, playerPos)
  elseif placement.mode == "parking" then
    transform = makeParkingTransform(placement.parking and placement.parking.spot, playerPos)
  end
  if not transform then
    S.lastFailure = "stash transform unavailable"
    return false
  end

  local placed = "breadcrumbPreload"
  local stashRetries = 0
  if placement.mode == "parking" and gameplay_parking and gameplay_parking.moveToParkingSpot and placement.parking and placement.parking.spot then
    local okMove, moved = pcall(function()
      return gameplay_parking.moveToParkingSpot(veh:getId(), placement.parking.spot, true)
    end)
    if okMove and moved == true then
      placed = "preloadParking"
      S.stats.parkingFallbacks = (S.stats.parkingFallbacks or 0) + 1
    end
  end

  if placed ~= "preloadParking" then
    stashRetries = 3
    local ok = teleportWithVerify(veh, transform.pos, transform.rot, { retries = 3, maxDist = 5.0 })
    if not ok then
      log("Stash failed: teleport verification failed.")
      S.lastFailure = "stash teleport verification failed"
      return false
    end
  end

  disableVehicleAI(veh)
  setVehicleIdle(veh)

  local specKey = makeSpecKey(opts and opts.model or nil, opts and opts.config or nil)
  local entry = {
    vehId = vehId,
    eventName = eventName or "RobberEMP",
    model = opts and opts.model or nil,
    config = opts and opts.config or nil,
    specKey = specKey,
    placed = placed,
    createdAt = os.clock(),
  }
  S.preloaded = entry
  S.preloadedBySpec[specKey] = entry
  S.activeSpecKey = specKey
  S.pending = nil
  S.preloadInProgress = false
  S.stats.stashCount = (S.stats.stashCount or 0) + 1
  S.stats.stashRetries = (S.stats.stashRetries or 0) + stashRetries
  S.lastFailure = nil
  return true
end

function M.isPreloadPointAvailable()
  local distanceInfo = getPreloadDistanceInfo()
  if not distanceInfo then
    return false
  end
  return (distanceInfo.distance or 0) > DEFAULT_MIN_PRELOAD_DISTANCE
end

function M.update(dtSim)
  local now = os.clock()

  if S.preloaded and not isPreloadedEntryValid(S.preloaded) then
    local pending = {
      eventName = S.preloaded.eventName,
      model = S.preloaded.model,
      config = S.preloaded.config,
    }
    if S.preloaded.specKey then
      S.preloadedBySpec[S.preloaded.specKey] = nil
    end
    S.preloaded = nil
    if pending.model then
      M.request(pending)
    end
  end

  if S.preloaded then
    return
  end

  if not S.lastRequestedSpec or not S.lastRequestedSpec.model then
    return
  end

  if S.maintenanceNextAt and now < S.maintenanceNextAt then
    return
  end

  local info = getPreloadDistanceInfo()
  if info and info.distance and info.distance <= DEFAULT_MIN_PRELOAD_DISTANCE then
    S.maintenanceNextAt = now + S.maintenanceIntervalSec
    return
  end

  M.request(S.lastRequestedSpec)
  S.maintenanceNextAt = now + S.maintenanceIntervalSec
end

function M.getPreloadDebugInfo()
  local state = M.getDebugState()
  return {
    ready = state and state.preloaded ~= nil,
    owner = state and state.preloaded or nil,
    specKey = state and state.specKey or nil,
    pending = state and state.pending or nil,
    placed = state and state.placed or nil,
    spawnPointReady = state and state.spawnPointReady or false,
    spawnPointDistance = state and state.spawnPointDistance or nil,
    spawnPointFarEnough = state and state.spawnPointFarEnough or false,
    lastFailure = state and state.lastFailure or nil,
    stats = state and state.stats or nil,
  }
end

return M
