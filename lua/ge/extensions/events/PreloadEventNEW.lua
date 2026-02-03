-- PreloadEventNEW.lua
-- Simplified preload: keep robber vehicle parked at the fixed preload position.

local M = {}

local CFG = nil
local Host = nil

local S = {
  preloaded = nil,
  pending = nil,
  preloadInProgress = false,
  lastAttemptAt = 0,
  attemptCount = 0,
  maxAttempts = 1,
  uiGateOverride = nil,
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

local function safeTeleportVehicle(veh, pos, rot)
  if not veh then return end
  if pos and rot and veh.setPositionRotation then
    pcall(function() veh:setPositionRotation(pos, rot) end)
  elseif pos and veh.setPosition then
    pcall(function() veh:setPosition(pos) end)
  elseif pos and veh.setPosRot and rot then
    pcall(function() veh:setPosRot(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, rot.w) end)
  end
  if spawn and spawn.safeTeleport then
    pcall(function() spawn.safeTeleport(veh, veh:getPosition(), veh:getRotation()) end)
  end
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

local function spawnPreloadedVehicle(opts)
  if not opts or not opts.model then
    return nil, "missing model"
  end

  local options = {
    config = opts.config,
    cling = true,
    autoEnterVehicle = false,
  }

  local veh = core_vehicles.spawnNewVehicle(opts.model, options)
  if not veh then
    return nil, "vehicle spawn failed"
  end

  local distanceInfo, distErr = getPreloadDistanceInfo()
  if not distanceInfo then
    veh:delete()
    return nil, distErr or "preload spawn point unavailable"
  end

  if (distanceInfo.distance or 0) <= 300.0 then
    veh:delete()
    return nil, "preload spawn point too close"
  end

  local playerVeh = getPlayerVeh()
  local playerPos = playerVeh and playerVeh.getPosition and playerVeh:getPosition() or nil
  local transform = makeSpawnTransform(distanceInfo.spawnPoint, playerPos)
  if not transform then
    veh:delete()
    return nil, "missing preload spawn transform"
  end

  safeTeleportVehicle(veh, transform.pos, transform.rot)
  local placed = "breadcrumbPreload"
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
end

function M.request(opts)
  if type(opts) ~= "table" then
    log("Request missing options table")
    return false
  end
  if not opts.eventName then
    log("Request missing eventName")
    return false
  end
  if not opts.model then
    log("Request missing model")
    return false
  end

  if S.preloaded and getObjById(S.preloaded.vehId) then
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
    if err then log("Preload failed: " .. tostring(err)) end
    return false
  end

  ensurePrewarmAudio(S.pending)
  S.preloaded = {
    vehId = res.vehId,
    eventName = S.pending.eventName,
    model = S.pending.model,
    config = S.pending.config,
    placed = res.placed,
    createdAt = os.clock(),
  }
  S.pending = nil
  S.preloadInProgress = false
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
  S.preloadInProgress = false
  S.attemptCount = 0
  S.maxAttempts = 1
  S.lastAttemptAt = 0
end

function M.hasPreloaded(eventName)
  if not S.preloaded then return false end
  if eventName and S.preloaded.eventName ~= eventName then return false end
  return getObjById(S.preloaded.vehId) ~= nil
end

function M.getDebugState()
  local pendingName = S.pending and S.pending.eventName or nil
  local preloadedName = S.preloaded and S.preloaded.eventName or nil
  local distanceInfo = getPreloadDistanceInfo()
  local spawnPointDistance = distanceInfo and distanceInfo.distance or nil
  local spawnPointReady = distanceInfo ~= nil
  return {
    pending = pendingName,
    preloaded = preloadedName,
    preloadedId = S.preloaded and S.preloaded.vehId or nil,
    placed = S.preloaded and S.preloaded.placed or nil,
    preloadInProgress = S.preloadInProgress,
    uiGateOverride = S.uiGateOverride,
    spawnPointReady = spawnPointReady,
    spawnPointDistance = spawnPointDistance,
    spawnPointFarEnough = spawnPointDistance ~= nil and spawnPointDistance > 300.0 or false,
  }
end

function M.consume(eventName, transform)
  if not S.preloaded then return nil end
  if eventName and S.preloaded.eventName ~= eventName then
    return nil
  end

  local veh = getObjById(S.preloaded.vehId)
  if not veh then
    S.preloaded = nil
    return nil
  end

  if transform and transform.pos then
    safeTeleportVehicle(veh, transform.pos, transform.rot)
  end

  local id = S.preloaded.vehId
  S.pending = nil
  S.preloaded.placed = "event"
  S.preloaded.lastUsedAt = os.clock()
  return id
end

function M.stash(eventName, vehId, opts)
  if type(vehId) ~= "number" then
    return false
  end
  local veh = getObjById(vehId)
  if not veh then
    return false
  end

  local distanceInfo = getPreloadDistanceInfo()
  if not distanceInfo then
    return false
  end

  local playerVeh = getPlayerVeh()
  local playerPos = playerVeh and playerVeh.getPosition and playerVeh:getPosition() or nil
  local transform = makeSpawnTransform(distanceInfo.spawnPoint, playerPos)
  if not transform then
    return false
  end

  safeTeleportVehicle(veh, transform.pos, transform.rot)
  local placed = "breadcrumbPreload"
  disableVehicleAI(veh)
  setVehicleIdle(veh)

  S.preloaded = {
    vehId = vehId,
    eventName = eventName or "RobberEMP",
    model = opts and opts.model or nil,
    config = opts and opts.config or nil,
    placed = placed,
    createdAt = os.clock(),
  }
  S.pending = nil
  S.preloadInProgress = false
  return true
end

function M.isPreloadPointAvailable()
  local distanceInfo = getPreloadDistanceInfo()
  if not distanceInfo then
    return false
  end
  return (distanceInfo.distance or 0) > 300.0
end

function M.update(dtSim)
  if not S.preloaded then return end
  if not getObjById(S.preloaded.vehId) then
    local pending = {
      eventName = S.preloaded.eventName,
      model = S.preloaded.model,
      config = S.preloaded.config,
    }
    S.preloaded = nil
    if pending.model then
      M.request(pending)
    end
  end
end

return M
