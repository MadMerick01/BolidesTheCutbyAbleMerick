-- PreloadEvent.lua
-- Preloads vehicles + audio during UI pauses to avoid gameplay hitches.

local M = {}

local CFG = nil
local Host = nil

local S = {
  pending = nil,
  preloaded = nil,
  preloadInProgress = false,
  lastAttemptAt = 0,
  attempted = false,
  uiGateOverride = nil,
  windowStart = nil,
  windowSeconds = nil,
  minDelay = nil,
}

local function log(msg)
  if Host and Host.postLine then
    Host.postLine("PreloadEvent", msg)
  else
    print("[PreloadEvent] " .. tostring(msg))
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

local function detectUiPause()
  if S.uiGateOverride ~= nil then
    return S.uiGateOverride == true
  end

  if core_gamestate then
    local ok, res = pcall(core_gamestate.loadingScreenActive)
    if ok and res then return true end
    ok, res = pcall(core_gamestate.loading)
    if ok and res then return true end
    if core_gamestate.state and core_gamestate.state.state then
      local st = tostring(core_gamestate.state.state):lower()
      if st:find("menu", 1, true) or st:find("loading", 1, true) then
        return true
      end
    end
  end

  if gameplay_loading_ui and gameplay_loading_ui.loadingScreenActive then
    local ok, res = pcall(gameplay_loading_ui.loadingScreenActive)
    if ok and res then return true end
  end

  if ui_visibility then
    local ok, cef = pcall(ui_visibility.getCef)
    local ok2, imgui = pcall(ui_visibility.getImgui)
    if (ok and cef) or (ok2 and imgui) then
      return true
    end
  end

  return false
end

local function parsePlacement(res)
  if type(res) ~= "table" then
    return nil
  end
  if res.pos or res.rot then
    return res
  end
  if res.position or res.rotation then
    return { pos = res.position, rot = res.rotation }
  end
  if res.transform and (res.transform.pos or res.transform.rot) then
    return res.transform
  end
  return nil
end

local function tryPickSpawnPoint(playerVeh, distance, tolerance)
  if not spawn or not spawn.pickSpawnPoint then
    return nil
  end

  local attempts = {
    function()
      return spawn.pickSpawnPoint()
    end,
    function()
      return spawn.pickSpawnPoint(playerVeh)
    end,
    function()
      return spawn.pickSpawnPoint(playerVeh, distance)
    end,
    function()
      return spawn.pickSpawnPoint(playerVeh, distance, tolerance)
    end,
    function()
      return spawn.pickSpawnPoint({
        vehicle = playerVeh,
        distance = distance,
        tolerance = tolerance,
      })
    end,
  }

  for _, fn in ipairs(attempts) do
    local ok, res = pcall(fn)
    if ok then
      local placement = parsePlacement(res)
      if placement then
        return placement
      end
    end
  end

  return nil
end

local function tryRelativePlacement(playerVeh, distance)
  if not spawn or not spawn.calculateRelativeVehiclePlacement then
    return nil
  end

  local attempts = {
    function()
      return spawn.calculateRelativeVehiclePlacement(playerVeh, distance)
    end,
    function()
      return spawn.calculateRelativeVehiclePlacement({
        vehicle = playerVeh,
        distance = distance,
      })
    end,
  }

  for _, fn in ipairs(attempts) do
    local ok, res = pcall(fn)
    if ok then
      local placement = parsePlacement(res)
      if placement then
        return placement
      end
    end
  end

  return nil
end

local function attemptLightweightPreload(opts)
  local playerVeh = getPlayerVeh()
  if not playerVeh then
    return nil, "no player vehicle"
  end
  if not opts or not opts.model then
    return nil, "missing model"
  end

  local distance = tonumber(opts.distance) or 500
  local tolerance = tonumber(opts.tolerance) or 150

  local placement = tryPickSpawnPoint(playerVeh, distance, tolerance)
  if not placement then
    placement = tryRelativePlacement(playerVeh, distance)
  end
  if not placement then
    return nil, "no spawn placement"
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

  if placement.pos or placement.rot then
    safeTeleportVehicle(veh, placement.pos, placement.rot)
  elseif spawn and spawn.teleportToLastRoad then
    pcall(spawn.teleportToLastRoad, veh)
  end

  return {
    veh = veh,
    vehId = veh:getId(),
    placed = placement and placement.pos and "spawnModule" or "teleport",
    direction = nil,
    distanceTarget = distance,
    tolerance = tolerance,
  }, nil
end

local function ensurePrewarmAudio(opts)
  if not opts then return end
  local pv = getPlayerVeh()
  if not pv then return end
  if type(opts.prewarmAudio) == "function" then
    pcall(opts.prewarmAudio, pv)
  end
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

  if S.preloaded and S.preloaded.eventName == opts.eventName then
    return true
  end

  local now = os.clock()
  S.pending = {
    eventName = tostring(opts.eventName),
    model = opts.model,
    config = opts.config,
    distance = opts.distance,
    tolerance = opts.tolerance,
    searchRadius = opts.searchRadius,
    maxAttempts = opts.maxAttempts,
    parkChance = opts.parkChance,
    prewarmAudio = opts.prewarmAudio,
  }
  S.windowStart = tonumber(opts.windowStart) or now
  S.windowSeconds = tonumber(opts.windowSeconds) or 180
  S.minDelay = tonumber(opts.minDelay) or 0
  S.preloaded = nil
  S.preloadInProgress = false
  S.attempted = false
  return true
end

function M.updateWindow(eventName, windowStart, windowSeconds, minDelay)
  if not S.pending or (eventName and S.pending.eventName ~= eventName) then
    return false
  end
  if windowStart ~= nil then
    S.windowStart = tonumber(windowStart) or S.windowStart
  end
  if windowSeconds ~= nil then
    S.windowSeconds = tonumber(windowSeconds) or S.windowSeconds
  end
  if minDelay ~= nil then
    S.minDelay = tonumber(minDelay) or S.minDelay
  end
  return true
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
  S.attempted = false
  S.windowStart = nil
  S.windowSeconds = nil
  S.minDelay = nil
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
    direction = S.preloaded and S.preloaded.direction or nil,
    windowStart = S.windowStart,
    windowSeconds = S.windowSeconds,
    minDelay = S.minDelay,
    lastAttemptAt = S.lastAttemptAt,
    attempted = S.attempted,
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
  S.preloaded = nil
  S.pending = nil
  return id
end

function M.update(dtSim)
  if not S.pending or S.preloaded or S.preloadInProgress then return end
  if S.attempted then return end

  local now = os.clock()
  local windowStart = S.windowStart or now
  local windowSeconds = S.windowSeconds or 180
  local minDelay = S.minDelay or 0

  if now < (windowStart + minDelay) then
    return
  end
  if windowSeconds > 0 and now > (windowStart + windowSeconds) then
    log("Preload window expired for " .. tostring(S.pending.eventName))
    M.clear()
    return
  end
  if not detectUiPause() then return end

  if S.lastAttemptAt ~= 0 and (now - S.lastAttemptAt) < 1.0 then
    return
  end
  S.lastAttemptAt = now
  S.preloadInProgress = true
  S.attempted = true

  local res, err = attemptLightweightPreload(S.pending)
  if not res or not res.vehId then
    S.preloadInProgress = false
    if err then log("Preload failed: " .. tostring(err)) end
    return
  end

  local veh = res.veh
  disableVehicleAI(veh)
  setVehicleIdle(veh)
  ensurePrewarmAudio(S.pending)

  S.preloaded = {
    vehId = res.vehId,
    eventName = S.pending.eventName,
    model = S.pending.model,
    config = S.pending.config,
    placed = res.placed,
    direction = res.direction,
    distanceTarget = res.distanceTarget,
    tolerance = res.tolerance,
    createdAt = now,
  }
  S.preloadInProgress = false
  log("Preloaded " .. tostring(S.pending.eventName) .. " via " .. tostring(res.placed) .. " (" .. tostring(res.direction) .. ")")
end

return M
