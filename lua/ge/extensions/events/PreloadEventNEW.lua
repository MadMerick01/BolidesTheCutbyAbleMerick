-- PreloadEventNEW.lua
-- Simplified preload: keep robber vehicle parked at the fixed preload position.

local M = {}

local CFG = nil
local Host = nil

local ORIGIN_POS = vec3(839.916, -742.143, 176.276)

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

  safeTeleportVehicle(veh, ORIGIN_POS, quat(0, 0, 0, 1))
  disableVehicleAI(veh)
  setVehicleIdle(veh)

  return {
    veh = veh,
    vehId = veh:getId(),
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
    placed = "origin",
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
  return {
    pending = pendingName,
    preloaded = preloadedName,
    preloadedId = S.preloaded and S.preloaded.vehId or nil,
    placed = S.preloaded and S.preloaded.placed or nil,
    preloadInProgress = S.preloadInProgress,
    uiGateOverride = S.uiGateOverride,
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

  safeTeleportVehicle(veh, ORIGIN_POS, quat(0, 0, 0, 1))
  disableVehicleAI(veh)
  setVehicleIdle(veh)

  S.preloaded = {
    vehId = vehId,
    eventName = eventName or "RobberEMP",
    model = opts and opts.model or nil,
    config = opts and opts.config or nil,
    placed = "origin",
    createdAt = os.clock(),
  }
  S.pending = nil
  S.preloadInProgress = false
  return true
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
