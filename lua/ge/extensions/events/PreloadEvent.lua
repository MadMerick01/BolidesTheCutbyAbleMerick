-- PreloadEvent.lua
-- Preloads vehicles + audio during UI pauses to avoid gameplay hitches.

local M = {}

local CFG = nil
local Host = nil

local ROBBER_PRELOAD_LOCATIONS = {
  west_coast_usa = {
    mapId = "west_coast_usa",
    mapName = "West Coast, USA",
    pos = vec3(839.916, -742.143, 176.276),
  },
}

local S = {
  pending = nil,
  preloaded = nil,
  preloadInProgress = false,
  lastAttemptAt = 0,
  attemptCount = 0,
  maxAttempts = 4,
  lastUiPauseActive = false,
  uiPauseToken = 0,
  lastUiPauseTokenAttempted = 0,
  uiGateOverride = nil,
  windowStart = nil,
  windowSeconds = nil,
  minDelay = nil,
  stashPending = nil,
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

local makePlacementTowardPlayer

local function normalizeMapId(candidate)
  if type(candidate) ~= "string" then
    return nil
  end
  local lower = candidate:lower()
  if lower:find("west_coast_usa", 1, true) then
    return "west_coast_usa"
  end
  if lower:find("west_coast", 1, true) then
    return "west_coast_usa"
  end
  return nil
end

local function tryAppendMapId(candidates, value)
  local id = normalizeMapId(value)
  if id then
    table.insert(candidates, id)
  end
end

local function getMapId()
  local candidates = {}

  if map and map.getMap then
    local ok, data = pcall(map.getMap)
    if ok and data then
      tryAppendMapId(candidates, data.id)
      tryAppendMapId(candidates, data.levelId)
      tryAppendMapId(candidates, data.levelName)
      tryAppendMapId(candidates, data.name)
      tryAppendMapId(candidates, data.dirname)
      tryAppendMapId(candidates, data.levelDir)
      tryAppendMapId(candidates, data.path)
      if data.levelInfo then
        tryAppendMapId(candidates, data.levelInfo.levelName)
        tryAppendMapId(candidates, data.levelInfo.name)
        tryAppendMapId(candidates, data.levelInfo.level)
        tryAppendMapId(candidates, data.levelInfo.id)
      end
    end
  end

  if be and type(be.getCurrentLevelIdentifier) == "function" then
    local ok, res = pcall(be.getCurrentLevelIdentifier)
    if ok then
      tryAppendMapId(candidates, res)
    end
    ok, res = pcall(be.getCurrentLevelIdentifier, be)
    if ok then
      tryAppendMapId(candidates, res)
    end
  end

  if core_levels and type(core_levels.getLevelName) == "function" then
    local ok, res = pcall(core_levels.getLevelName)
    if ok then
      tryAppendMapId(candidates, res)
    end
    ok, res = pcall(core_levels.getLevelName, core_levels)
    if ok then
      tryAppendMapId(candidates, res)
    end
  end

  return candidates[1]
end

local function getRobberPreloadPlacement(playerVeh, eventName)
  if not (eventName and tostring(eventName):find("Robber")) then
    return nil, nil
  end
  local mapId = getMapId()
  if not mapId then
    return nil, nil
  end
  local location = ROBBER_PRELOAD_LOCATIONS[mapId]
  if not (location and location.pos) then
    return nil, nil
  end
  local placement = makePlacementTowardPlayer(playerVeh, location.pos)
  if not placement then
    return nil, nil
  end
  return placement, "fixedPreload"
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

local function getBackBreadcrumbPos(meters)
  if not Host or not Host.Breadcrumbs or not Host.Breadcrumbs.getBack then
    return nil
  end
  local _, backCrumbPos = Host.Breadcrumbs.getBack()
  if not backCrumbPos then
    return nil
  end
  return backCrumbPos[meters]
end

local function getFallbackPreloadPos()
  if not Host or not Host.Breadcrumbs or not Host.Breadcrumbs.getPreloadFallback then
    return nil
  end
  return Host.Breadcrumbs.getPreloadFallback()
end

makePlacementTowardPlayer = function(playerVeh, spawnPos)
  if not (playerVeh and spawnPos) then
    return nil
  end
  local playerPos = playerVeh:getPosition()
  if not playerPos then
    return { pos = spawnPos }
  end
  local dir = playerPos - spawnPos
  dir.z = 0
  if dir:length() < 1e-6 then
    dir = vec3(0, 1, 0)
  end
  dir = dir:normalized()
  local rot = quat(0, 0, 0, 1)
  if quatFromDir then
    rot = quatFromDir(dir, vec3(0, 0, 1))
  end
  return { pos = spawnPos, rot = rot }
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

  local spawnPos = nil
  local placed = nil
  local fallbackPos = getFallbackPreloadPos()
  local playerPos = playerVeh:getPosition()
  if not playerPos then
    return nil, "no player position"
  end
  local fixedPlacement, fixedPlaced = getRobberPreloadPlacement(playerVeh, opts and opts.eventName)
  if fixedPlacement then
    spawnPos = fixedPlacement.pos
    placed = fixedPlaced
  elseif fallbackPos then
    local candidate = fallbackPos + vec3(0, 0, 0.8)
    if (candidate - playerPos):length() >= 200 then
      spawnPos = candidate
      placed = "fallbackBreadcrumb300m"
    end
  end

  if not spawnPos then
    local backPos = getBackBreadcrumbPos(300)
    if not backPos then
      return nil, "back breadcrumb 300m unavailable"
    end
    spawnPos = backPos + vec3(0, 0, 0.8)
    placed = "backBreadcrumb300m"
    if (spawnPos - playerPos):length() < 200 then
      return nil, "spawn too close"
    end
  end

  local placement = fixedPlacement or makePlacementTowardPlayer(playerVeh, spawnPos)
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
    placed = placed,
    direction = nil,
    distanceTarget = nil,
    tolerance = nil,
  }, nil
end

local function getHiddenPlacement(playerVeh, distance, eventName)
  if not playerVeh then
    return nil, nil
  end
  local playerPos = playerVeh:getPosition()
  if not playerPos then
    return nil, nil
  end
  local fixedPlacement, fixedPlaced = getRobberPreloadPlacement(playerVeh, eventName)
  if fixedPlacement then
    return fixedPlacement, fixedPlaced
  end
  local fallbackPos = getFallbackPreloadPos()
  if fallbackPos then
    local candidate = fallbackPos + vec3(0, 0, 0.8)
    if (candidate - playerPos):length() >= 200 then
      return makePlacementTowardPlayer(playerVeh, candidate), "fallbackBreadcrumb"
    end
  end

  local backPos = getBackBreadcrumbPos(distance or 300)
  if not backPos then
    return nil, nil
  end
  local spawnPos = backPos + vec3(0, 0, 0.8)
  if (spawnPos - playerPos):length() <= 200 then
    return nil, nil
  end
  return makePlacementTowardPlayer(playerVeh, spawnPos), "backBreadcrumb"
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
  S.attemptCount = 0
  S.maxAttempts = math.max(1, math.floor(tonumber(opts.maxAttempts) or S.maxAttempts or 4))
  S.lastUiPauseActive = false
  S.uiPauseToken = 0
  S.lastUiPauseTokenAttempted = 0
  S.lastAttemptAt = 0
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
  S.attemptCount = 0
  S.maxAttempts = 4
  S.lastUiPauseActive = false
  S.uiPauseToken = 0
  S.lastUiPauseTokenAttempted = 0
  S.lastAttemptAt = 0
  S.windowStart = nil
  S.windowSeconds = nil
  S.minDelay = nil
  S.stashPending = nil
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
    attemptCount = S.attemptCount,
    maxAttempts = S.maxAttempts,
    uiPauseToken = S.uiPauseToken,
    lastUiPauseTokenAttempted = S.lastUiPauseTokenAttempted,
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

  if S.preloaded and S.preloaded.vehId and S.preloaded.vehId ~= vehId then
    local existing = getObjById(S.preloaded.vehId)
    if existing then
      pcall(function() existing:delete() end)
    end
    S.preloaded = nil
  end

  local playerVeh = getPlayerVeh()
  local placement, placed = getHiddenPlacement(playerVeh, (opts and opts.distance) or 300, eventName)
  if placement then
    safeTeleportVehicle(veh, placement.pos, placement.rot)
    disableVehicleAI(veh)
    setVehicleIdle(veh)

    S.preloaded = {
      vehId = vehId,
      eventName = eventName or "RobberEMP",
      model = opts and opts.model or nil,
      config = opts and opts.config or nil,
      placed = placed or "stash",
      createdAt = os.clock(),
    }
    S.pending = nil
    S.preloadInProgress = false
    S.stashPending = nil
    return true
  end

  disableVehicleAI(veh)
  setVehicleIdle(veh)

  S.preloaded = nil
  S.pending = nil
  S.preloadInProgress = false
  S.stashPending = {
    vehId = vehId,
    eventName = eventName or "RobberEMP",
    model = opts and opts.model or nil,
    config = opts and opts.config or nil,
  }
  return false
end

function M.update(dtSim)
  if S.stashPending then
    local pending = S.stashPending
    local veh = getObjById(pending.vehId)
    if not veh then
      S.stashPending = nil
    else
      local playerVeh = getPlayerVeh()
      local placement, placed = getHiddenPlacement(playerVeh, 300, pending.eventName)
      if placement then
        safeTeleportVehicle(veh, placement.pos, placement.rot)
        disableVehicleAI(veh)
        setVehicleIdle(veh)
        S.preloaded = {
          vehId = pending.vehId,
          eventName = pending.eventName,
          model = pending.model,
          config = pending.config,
          placed = placed or "stash",
          createdAt = os.clock(),
        }
        S.stashPending = nil
      else
        disableVehicleAI(veh)
        setVehicleIdle(veh)
      end
    end
  end

  if not S.pending or S.preloadInProgress then return end

  if S.preloaded and not getObjById(S.preloaded.vehId) then
    S.preloaded = nil
  end
  if S.preloaded then
    return
  end

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

  local uiPauseActive = detectUiPause()
  if uiPauseActive and not S.lastUiPauseActive then
    S.uiPauseToken = (S.uiPauseToken or 0) + 1
  end
  S.lastUiPauseActive = uiPauseActive

  if not uiPauseActive then return end

  if S.attemptCount >= (S.maxAttempts or 1) then
    return
  end

  if S.lastAttemptAt ~= 0 and (now - S.lastAttemptAt) < 1.0 then
    return
  end

  local shouldAttempt = false
  if S.attemptCount == 0 then
    shouldAttempt = true
  elseif (S.uiPauseToken or 0) > (S.lastUiPauseTokenAttempted or 0) then
    shouldAttempt = true
  end

  if not shouldAttempt then
    return
  end

  S.lastAttemptAt = now
  S.preloadInProgress = true
  S.attemptCount = (S.attemptCount or 0) + 1
  S.lastUiPauseTokenAttempted = S.uiPauseToken or S.lastUiPauseTokenAttempted

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
  log(string.format(
    "Preloaded %s via %s (%s) on attempt %d/%d",
    tostring(S.pending.eventName),
    tostring(res.placed),
    tostring(res.direction),
    tonumber(S.attemptCount) or 0,
    tonumber(S.maxAttempts) or 0
  ))
end

return M
