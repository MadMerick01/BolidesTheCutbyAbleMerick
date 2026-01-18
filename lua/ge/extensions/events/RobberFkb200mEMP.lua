-- lua/ge/extensions/events/robber1FKB200.lua
-- Robber1FKB200: manual spawn at ForwardKnownBreadcrumb(200m)
-- Behavior:
--   1) Spawn and FOLLOW player with limit settings (max 20kph).
--   2) When within 25m, fire EMP (engine off + brakes lock 10s + combined shockwave 0.5s).
--   3) 6s after EMP fired, message triggers and robber switches to flee mode.
--   5) Old "contactMade / waitForFlee" logic is disabled once EMP has fired.

local M = {}

local EMP = require('lua/ge/extensions/events/emp')
local CareerMoney = require("CareerMoney")

local CFG = nil
local Host = nil

local R = {
  active = false,
  spawnedId = nil,
  status = "",
  spawnPos = nil,
  spawnMode = nil,
  spawnMethod = nil,

  phase = "idle",      -- "chase" | "flee"
  distToPlayer = nil,
  waitForFlee = false,
  waitTimer = 0,
  closeTimer = 0,
  robberSlowTimer = 0,
  successTriggered = false,
  successDespawnAt = nil,
  guiBaseMessage = nil,
  hideDistance = false,
  postSuccessMessageAt = nil,

  -- Anti-teleport snapback (was referenced but not always initialized)
  spawnClock = nil,
  spawnSnapped = false,

  -- EMP state
  empFired = false,
  empFiredAt = 0,
  empPlayerId = nil,
  empFleeTriggered = false,
  empFleeAt = nil,
  empFootstepsAt = nil,
  empFootstepsPlayed = false,
  empBrakeEnd = nil,
  empPreStopTriggered = false,
  empPreStopEnd = nil,
  fleeProfile = nil,
  downhillHold = 0,
  lastNotDownhillAt = 0,
  downhillActive = false,
  robberyProcessed = false,
  robbedAmount = 0,
  cashFound = nil,
}

local function log(msg)
  R.status = msg or ""
  if Host and Host.postLine then
    Host.postLine("ROBBER1FKB200", R.status)
  else
    print("[Robber1FKB200] " .. tostring(R.status))
  end
end

local function chooseFkbPos(spacing, maxAgeSec)
  maxAgeSec = maxAgeSec or 10.0
  if not Host or not Host.Breadcrumbs or not Host.Breadcrumbs.getForwardKnown then
    return nil, "no breadcrumbs"
  end

  local cache = select(1, Host.Breadcrumbs.getForwardKnown())
  local e = cache and cache[spacing]
  if not e then return nil, "no entry" end

  if e.available and e.pos then
    return e.pos, "live"
  end

  if e.lastGoodPos and e.lastGoodT then
    local age = (os.clock() - e.lastGoodT)
    if age <= maxAgeSec then
      return e.lastGoodPos, "cached"
    end
    return nil, "cached too old"
  end

  return nil, "not ready"
end

local function makeSpawnTransform(playerVeh, spawnPos)
  local playerPos = playerVeh:getPosition()
  local dir = playerPos - spawnPos
  dir.z = 0
  if dir:length() < 1e-6 then dir = vec3(0, 1, 0) end
  dir = dir:normalized()

  local rot = quat(0, 0, 0, 1)
  if quatFromDir then
    rot = quatFromDir(dir, vec3(0, 0, 1))
  end

  return { pos = spawnPos, rot = rot }
end

local function adjustCareerMoney(amount)
  if not CareerMoney or not CareerMoney.isCareerActive or not CareerMoney.isCareerActive() then
    return false
  end
  if not CareerMoney.set then
    return false
  end
  return CareerMoney.set(amount)
end

local function getCareerMoney()
  if not CareerMoney or not CareerMoney.isCareerActive or not CareerMoney.isCareerActive() then
    return nil
  end
  return CareerMoney.get and CareerMoney.get() or nil
end

local function resolveVehicleId(result)
  if result == nil then return nil end
  local t = type(result)
  if t == "number" then return result end
  if t == "userdata" then
    if result.getID then
      local ok, id = pcall(function() return result:getID() end)
      if ok and type(id) == "number" then return id end
    end
    return nil
  end
  if t == "table" then
    if type(result.id) == "number" then return result.id end
    if result.veh and result.veh.getID then
      local ok, id = pcall(function() return result.veh:getID() end)
      if ok and type(id) == "number" then return id end
    end
    return nil
  end
  return nil
end

local function spawnVehicleAt(transform)
  local model = "roamer"
  local config = "robber_light.pc"

  if core_vehicles and core_vehicles.spawnNewVehicle then
    local ok, res = pcall(function()
      return core_vehicles.spawnNewVehicle(model, {
        pos = transform.pos,
        rot = transform.rot,
        config = config,
        cling = true,
        autoEnterVehicle = false,
      })
    end)
    if ok then
      local id = resolveVehicleId(res)
      if id then
        R.spawnMethod = "core_vehicles.spawnNewVehicle"
        return id
      end
    else
      log("ERROR: core_vehicles.spawnNewVehicle threw: " .. tostring(res))
    end
  end

  if core_vehicle_manager and core_vehicle_manager.spawnNewVehicle then
    local ok, res = pcall(function()
      return core_vehicle_manager.spawnNewVehicle(model, {
        pos = transform.pos,
        rot = transform.rot,
        config = config,
        cling = true,
        autoEnterVehicle = false,
      })
    end)
    if ok then
      local id = resolveVehicleId(res)
      if id then
        R.spawnMethod = "core_vehicle_manager.spawnNewVehicle"
        return id
      end
    else
      log("ERROR: core_vehicle_manager.spawnNewVehicle threw: " .. tostring(res))
    end
  end

  if spawn and spawn.spawnVehicle then
    local ok, res = pcall(function()
      return spawn.spawnVehicle(model, config, transform.pos, transform.rot)
    end)
    if ok then
      local id = resolveVehicleId(res)
      if id then
        R.spawnMethod = "spawn.spawnVehicle(model, config, pos, rot)"
        return id
      end
    end

    ok, res = pcall(function()
      return spawn.spawnVehicle(model, { pos = transform.pos, rot = transform.rot, config = config })
    end)
    if ok then
      local id = resolveVehicleId(res)
      if id then
        R.spawnMethod = "spawn.spawnVehicle(model, opts)"
        return id
      end
    end
  end

  log("ERROR: No supported vehicle spawner found OR spawner returned non-id.")
  return nil
end

local AUDIO = {
  eventStartFile = "/art/sound/bolides/EventStart.wav",
  eventStartName = "robberEventStart",
  eventStartVol = 1.0,
  eventStartPitch = 1.0,
  footstepsFile = "/art/sound/bolides/footsteps.wav",
  footstepsName = "robberFootsteps",
  footstepsVol = 1.0,
  footstepsPitch = 1.0,
  chase2File = "/art/sound/bolides/chase2.wav",
  chase2Name = "robberChase2",
  chase2Vol = 1.0,
  chase2Pitch = 1.0,
}

local Audio = {}

function Audio.ensureSources(v, sources)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__robber1FKB200Audio = _G.__robber1FKB200Audio or { ids = {} }",
    "local A = _G.__robber1FKB200Audio.ids",
    "local function mk(path, name)",
    "  if A[name] then return end",
    "  local id = obj:createSFXSource(path, \"Audio2D\", name, -1)",
    "  A[name] = id",
    "end"
  }

  for _, source in ipairs(sources) do
    if source and source.file and source.name then
      lines[#lines + 1] = string.format("mk(%q, %q)", source.file, source.name)
    end
  end

  v:queueLuaCommand(table.concat(lines, "\n"))
end

function Audio.ensureAll(v)
  Audio.ensureSources(v, {
    { file = AUDIO.eventStartFile, name = AUDIO.eventStartName },
    { file = AUDIO.footstepsFile, name = AUDIO.footstepsName },
    { file = AUDIO.chase2File, name = AUDIO.chase2Name },
  })
end

function Audio.playId(v, name, vol, pitch, fileFallback)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  fileFallback = tostring(fileFallback or "")

  local cmd = string.format([[
    if not (_G.__robber1FKB200Audio and _G.__robber1FKB200Audio.ids) then return end
    local id = _G.__robber1FKB200Audio.ids[%q]
    if not id then return end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 1.0) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, 1.0) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, 1.0) end) end

    local played = false
    if obj.playSFX then
      played = played or pcall(function() obj:playSFX(id) end)
      played = played or pcall(function() obj:playSFX(id, 0) end)
      played = played or pcall(function() obj:playSFX(id, false) end)
      played = played or pcall(function() obj:playSFX(id, 0, false) end)
      played = played or pcall(function() obj:playSFX(id, 0, %0.3f, %0.3f, false) end)
      played = played or pcall(function() obj:playSFX(id, %0.3f, %0.3f, false) end)
      played = played or pcall(function() obj:playSFX(id, 0, false, %0.3f, %0.3f) end)
    end

    if (not played) and obj.playSFXOnce and %q ~= "" then
      pcall(function() obj:playSFXOnce(%q, 0, %0.3f, %0.3f) end)
    end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, %0.3f) end) end
    if obj.setSFXSourcePitch  then pcall(function() obj:setSFXSourcePitch(id, %0.3f) end) end
  ]], name, vol, pitch, vol, pitch, vol, pitch, fileFallback, fileFallback, vol, pitch, vol, pitch)

  v:queueLuaCommand(cmd)
end

function Audio.stopId(v, name)
  if not v or not v.queueLuaCommand then return end
  name = tostring(name)

  local cmd = string.format([[
    if not (_G.__robber1FKB200Audio and _G.__robber1FKB200Audio.ids) then return end
    local id = _G.__robber1FKB200Audio.ids[%q]
    if not id then return end

    if obj.stopSFX then
      pcall(function() obj:stopSFX(id) end)
      pcall(function() obj:stopSFX(id, true) end)
    end
    if obj.stopSFXSource then
      pcall(function() obj:stopSFXSource(id) end)
    end
    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 0) end) end
  ]], name)

  v:queueLuaCommand(cmd)
end

local function getObjById(id)
  if type(id) ~= "number" then return nil end
  if getObjectByID then return getObjectByID(id) end
  if be and be.getObjectByID then return be:getObjectByID(id) end
  return nil
end

local function setGuiStatusMessage(msg)
  if Host and Host.setGuiStatusMessage then
    Host.setGuiStatusMessage(msg)
    return
  end
  if extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.setGuiStatusMessage then
    extensions.bolidesTheCut.setGuiStatusMessage(msg)
  end
end

local function updateGuiDistanceMessage(distance)
  if not R.guiBaseMessage then return end
  if R.hideDistance then
    setGuiStatusMessage(R.guiBaseMessage)
    return
  end
  local distMeters = math.floor((distance or 0) + 0.5)
  setGuiStatusMessage(string.format("%s\nRobber distance: %dm", R.guiBaseMessage, distMeters))
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

-- ============================================
-- AI scripting helpers (runs inside vehicle)
-- ============================================
local function queueAI_ChaseConservative(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[Robber1FKB200 AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[Robber1FKB200 AI] ai missing"); return end

    -- FOLLOW the player (conservative)
    try('ai.setMode("follow")', function() ai.setMode("follow") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    -- speedMode: limit
    try('ai.setSpeedMode("limit")', function()
      if ai.setSpeedMode then ai.setSpeedMode("limit") end
    end)

    -- maxSpeedKph: 20
    try("ai.setMaxSpeed(5.5556)", function()
      if ai.setMaxSpeed then ai.setMaxSpeed(5.5556) end -- m/s
    end)
    try("ai.setMaxSpeedKph(20)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(20) end
    end)

    -- aggression: 0.1
    try("ai.setAggression(0.1)", function()
      if ai.setAggression then ai.setAggression(0.1) end
    end)

    -- driveInLane: off
    try('ai.driveInLane("off")', function()
      if ai.driveInLane then ai.driveInLane("off") end
    end)

    -- avoidCars: on
    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)

    -- stop short of the player
    try("ai.setStopDistance(11)", function()
      if ai.setStopDistance then ai.setStopDistance(11) end
    end)

    -- recoverOnCrash: false (avoid AI respawn/teleport)
    try("ai.setRecoverOnCrash(false)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end
    end)
    try("ai.setAvoidCrash(true)", function()
      if ai.setAvoidCrash then ai.setAvoidCrash(true) end
    end)

    print("[Robber1FKB200 AI] FOLLOW armed (limit, max 20kph, aggr 0.1, avoidCars on, stopDistance 11). targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_EmpSlowChase(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[Robber1FKB200 AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[Robber1FKB200 AI] ai missing"); return end

    -- slow chase to close in after EMP
    try('ai.setMode("follow")', function() ai.setMode("follow") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)

    try("ai.setMaxSpeed(1.3889)", function()
      if ai.setMaxSpeed then ai.setMaxSpeed(1.3889) end -- m/s (5 kph)
    end)
    try("ai.setMaxSpeedKph(5)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(5) end
    end)

    try("ai.setAggression(0.05)", function()
      if ai.setAggression then ai.setAggression(0.05) end
    end)

    try("ai.setStopDistance(11)", function()
      if ai.setStopDistance then ai.setStopDistance(11) end
    end)

    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)
    try("ai.setRecoverOnCrash(false)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end
    end)
    try("ai.setAvoidCrash(true)", function()
      if ai.setAvoidCrash then ai.setAvoidCrash(true) end
    end)

    print("[Robber1FKB200 AI] EMP slow chase (max 5kph, aggr 0.05, stopDistance 11). targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_Flee(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[Robber1FKB200 AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[Robber1FKB200 AI] ai missing"); return end

    try('ai.setMode("flee")', function() ai.setMode("flee") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)
    try("ai.setMaxSpeedKph(75)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(75) end
    end)

    try("ai.setAggression(0.28)", function()
      if ai.setAggression then ai.setAggression(0.28) end
    end)

    -- avoid traffic + change lanes (best-effort)
    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)
    try("ai.setAllowLaneChanges(true)", function()
      if ai.setAllowLaneChanges then ai.setAllowLaneChanges(true) end
    end)
    try('ai.driveInLane("off")', function()
      if ai.driveInLane then ai.driveInLane("off") end
    end)
    try("ai.setAvoidCrash(true)", function()
      if ai.setAvoidCrash then ai.setAvoidCrash(true) end
    end)
    try("ai.setRecoverOnCrash(false)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end
    end)

    print("[Robber1FKB200 AI] FLEE armed (aggr 0.28, max 75kph, legal, avoidCars on). targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_FleeProfile(veh, targetId, profile)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[Robber1FKB200 AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    local profile = %q
    if not ai then print("[Robber1FKB200 AI] ai missing"); return end

    try('ai.setMode("flee")', function() ai.setMode("flee") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)

    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)
    try("ai.setAvoidCrash(true)", function()
      if ai.setAvoidCrash then ai.setAvoidCrash(true) end
    end)
    try("ai.setRecoverOnCrash(false)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end
    end)

    if profile == "downhill" then
      try("ai.setMaxSpeedKph(45)", function()
        if ai.setMaxSpeedKph then ai.setMaxSpeedKph(45) end
      end)
      try("ai.setAggression(0.12)", function()
        if ai.setAggression then ai.setAggression(0.12) end
      end)
      try("ai.setAllowLaneChanges(false)", function()
        if ai.setAllowLaneChanges then ai.setAllowLaneChanges(false) end
      end)
      try('ai.driveInLane("on")', function()
        if ai.driveInLane then ai.driveInLane("on") end
      end)
    else
      try("ai.setMaxSpeedKph(75)", function()
        if ai.setMaxSpeedKph then ai.setMaxSpeedKph(75) end
      end)
      try("ai.setAggression(0.28)", function()
        if ai.setAggression then ai.setAggression(0.28) end
      end)
      try("ai.setAllowLaneChanges(true)", function()
        if ai.setAllowLaneChanges then ai.setAllowLaneChanges(true) end
      end)
      try('ai.driveInLane("off")', function()
        if ai.driveInLane then ai.driveInLane("off") end
      end)
    end

    print("[Robber1FKB200 AI] FLEE profile="..tostring(profile).." targetId="..tostring(tid))
  ]]):format(targetId, profile or "normal"))
end

local function updateDownhillState(dtSim, robberVeh)
  if not robberVeh or not robberVeh.getDirectionVector then
    return R.downhillActive
  end

  local fwd = robberVeh:getDirectionVector()
  if not fwd then
    return R.downhillActive
  end

  local clampedZ = math.max(-1, math.min(1, fwd.z or 0))
  local pitchDeg = math.deg(math.asin(clampedZ))

  if pitchDeg <= -6 then
    R.downhillActive = true
    R.downhillHold = 0
    R.lastNotDownhillAt = 0
    return true
  end

  if R.downhillActive then
    if pitchDeg >= -3 then
      if not R.lastNotDownhillAt or R.lastNotDownhillAt == 0 then
        R.lastNotDownhillAt = os.clock()
      end
      R.downhillHold = R.downhillHold + (dtSim or 0)
      if R.downhillHold >= 1.0 then
        R.downhillActive = false
        R.downhillHold = 0
        R.lastNotDownhillAt = 0
      end
    else
      R.downhillHold = 0
      R.lastNotDownhillAt = 0
    end
  end

  return R.downhillActive
end

local function applyFleeProfile(robberVeh, targetId, profile)
  if not robberVeh or not targetId then return end
  if R.fleeProfile == profile then return end
  queueAI_FleeProfile(robberVeh, targetId, profile)
  R.fleeProfile = profile
end

local function startFollowAI(robberId)
  local veh = getObjById(robberId)
  if not veh then
    log("ERROR: robber vehicle object missing after spawn (id=" .. tostring(robberId) .. ")")
    return
  end

  local targetId = (be and be.getPlayerVehicleID) and be:getPlayerVehicleID(0) or nil
  if not targetId or targetId <= 0 then
    log("ERROR: could not resolve player targetId for AI.")
    return
  end

  local playerVeh = getPlayerVeh()
  if playerVeh then
    Audio.ensureAll(playerVeh)
  end
  queueAI_ChaseConservative(veh, targetId)
  R.phase = "chase"
  R.waitForFlee = false
  R.waitTimer = 0

  if playerVeh then
    Audio.playId(playerVeh, AUDIO.eventStartName, AUDIO.eventStartVol, AUDIO.eventStartPitch, AUDIO.eventStartFile)
  end
  log("Robber AI: FOLLOW (limit, max20, aggr0.1, stop@10m). targetId=" .. tostring(targetId))
end

local function switchToFleeAI(robberId)
  local veh = getObjById(robberId)
  if not veh then
    log("ERROR: robber missing when switching to flee.")
    return
  end

  local targetId = (be and be.getPlayerVehicleID) and be:getPlayerVehicleID(0) or nil
  if not targetId or targetId <= 0 then
    log("ERROR: could not resolve player targetId for flee.")
    return
  end

  R.phase = "flee"
  R.fleeProfile = nil
  R.downhillHold = 0
  R.lastNotDownhillAt = 0
  R.downhillActive = false
  applyFleeProfile(veh, targetId, "normal")
  log("Robber AI: switched to FLEE (post-EMP)")
end

-- =========================
-- Public API
-- =========================
function M.init(hostCfg, hostApi)
  CFG = hostCfg
  Host = hostApi
end

function M.status()
  return R.status
end

function M.getSpawnMethod()
  return R.spawnMethod
end

function M.isActive()
  return R.active == true
end

function M.triggerManual()
  if R.active then
    log("Already active.")
    return false
  end

  local pv = (Host and Host.getPlayerVeh and Host.getPlayerVeh()) or (be and be.getPlayerVehicle and be:getPlayerVehicle(0))
  if not pv then
    log("BLOCKED: no player vehicle.")
    return false
  end

  local fkbPos, mode = chooseFkbPos(200, 10.0)
  if not fkbPos then
    log("BLOCKED: FKB 200m not available (no stable cached point).")
    return false
  end

  R.spawnMode = mode
  R.spawnPos = fkbPos + vec3(0, 0, 0.8)
  R.spawnMethod = nil
  log("Using FKB 200 (" .. tostring(mode) .. ")")

  local tf = makeSpawnTransform(pv, R.spawnPos)
  local id = spawnVehicleAt(tf)
  if not id then return false end

  R.active = true
  R.spawnedId = id
  R.phase = "idle"
  R.distToPlayer = nil
  R.waitForFlee = false
  R.waitTimer = 0
  R.closeTimer = 0
  R.robberSlowTimer = 0
  R.successTriggered = false
  R.successDespawnAt = nil
  R.guiBaseMessage = "??????"
  R.hideDistance = true
  R.postSuccessMessageAt = nil
  setGuiStatusMessage(R.guiBaseMessage)

  -- init anti-teleport window
  R.spawnClock = os.clock()
  R.spawnSnapped = false

  -- init EMP state
  R.empFired = false
  R.empFiredAt = 0
  R.empPlayerId = nil
  R.empFleeTriggered = false
  R.empFleeAt = nil
  R.empSlowChaseApplied = false
  R.empFootstepsAt = nil
  R.empFootstepsPlayed = false
  R.empBrakeEnd = nil
  R.empPreStopTriggered = false
  R.empPreStopEnd = nil
  R.fleeProfile = nil
  R.downhillHold = 0
  R.lastNotDownhillAt = 0
  R.downhillActive = false
  R.robberyProcessed = false
  R.robbedAmount = 0
  R.cashFound = nil

  startFollowAI(id)
  return true
end

function M.endEvent(opts)
  if not R.active then return end
  opts = opts or {}

  local pv = getPlayerVeh()
  if pv then
    Audio.stopId(pv, AUDIO.chase2Name)
  end

  -- Cancel EMP if still active/was fired (ensures brakes/ignition/planets restored)
  if R.empFired and R.empPlayerId then
    pcall(function() EMP.cancel(R.empPlayerId) end)
  end

  local id = R.spawnedId
  R.active = false
  R.spawnedId = nil
  R.spawnPos = nil
  R.spawnMode = nil
  R.spawnMethod = nil
  R.phase = "idle"
  R.distToPlayer = nil
  R.waitForFlee = false
  R.waitTimer = 0
  R.closeTimer = 0
  R.robberSlowTimer = 0
  R.successTriggered = false
  R.successDespawnAt = nil
  R.guiBaseMessage = nil
  R.hideDistance = false
  R.spawnClock = nil
  R.spawnSnapped = false

  R.empFired = false
  R.empFiredAt = 0
  R.empPlayerId = nil
  R.empFleeTriggered = false
  R.empFleeAt = nil
  R.empSlowChaseApplied = false
  R.empFootstepsAt = nil
  R.empFootstepsPlayed = false
  R.empBrakeEnd = nil
  R.empPreStopTriggered = false
  R.empPreStopEnd = nil
  R.fleeProfile = nil
  R.downhillHold = 0
  R.lastNotDownhillAt = 0
  R.downhillActive = false
  R.robberyProcessed = false
  R.robbedAmount = 0
  R.cashFound = nil

  if not opts.keepGuiMessage then
    setGuiStatusMessage(nil)
    R.postSuccessMessageAt = nil
  end

  if type(id) == "number" then
    local v = getObjById(id)
    if v then
      if v.queueLuaCommand then
        pcall(function() v:queueLuaCommand("input.event('brake', 0, 1)") end)
      end
      pcall(function() v:delete() end)
    end
  end

  log("Ended.")
end

function M.update(dtSim)
  if not R.active then
    if R.postSuccessMessageAt and os.clock() >= (R.postSuccessMessageAt + 60.0) then
      setGuiStatusMessage("nothing unusual")
      R.postSuccessMessageAt = nil
    end
    return
  end

  -- EMP timers + planets cleanup are handled by the main extension update loop.

  local robber = getObjById(R.spawnedId)
  if not robber then
    -- Cancel EMP if event aborts unexpectedly
    if R.empFired and R.empPlayerId then
      pcall(function() EMP.cancel(R.empPlayerId) end)
    end
    local pv = getPlayerVeh()
    if pv then
      Audio.stopId(pv, AUDIO.chase2Name)
    end

    R.active = false
    R.spawnedId = nil
    R.spawnPos = nil
    R.spawnMode = nil
    R.spawnMethod = nil
    R.phase = "idle"
    R.fleeProfile = nil
    R.downhillHold = 0
    R.lastNotDownhillAt = 0
    R.downhillActive = false
    R.hideDistance = false
    R.postSuccessMessageAt = nil
    setGuiStatusMessage(nil)
    log("Ended (robber missing).")
    return
  end

  local pv = getPlayerVeh()
  if not pv then return end

  local rp = robber:getPosition()
  local pp = pv:getPosition()
  if not (rp and pp) then return end

  local d = (rp - pp):length()
  R.distToPlayer = d

  local now = os.clock()

  updateGuiDistanceMessage(d)

  if R.empBrakeEnd and now >= R.empBrakeEnd then
    if robber.queueLuaCommand then
      pcall(function() robber:queueLuaCommand("input.event('brake', 0, 1)") end)
    end
    R.empBrakeEnd = nil
  end

  if R.empPreStopEnd and now >= R.empPreStopEnd then
    if robber.queueLuaCommand then
      pcall(function() robber:queueLuaCommand("input.event('brake', 0, 1)") end)
    end
    R.empPreStopEnd = nil
  end

  local playerSpeedKph = 0
  if pv.getVelocity then
    local vel = pv:getVelocity()
    if vel then
      playerSpeedKph = vel:length() * 3.6
    end
  elseif pv.getSpeed then
    local ok, speed = pcall(function() return pv:getSpeed() end)
    if ok and speed then
      playerSpeedKph = speed * 3.6
    end
  end

  local robberSpeedKph = nil
  if robber.getVelocity then
    local vel = robber:getVelocity()
    if vel then
      robberSpeedKph = vel:length() * 3.6
    end
  elseif robber.getSpeed then
    local ok, speed = pcall(function() return robber:getSpeed() end)
    if ok and speed then
      robberSpeedKph = speed * 3.6
    end
  end

  -- Anti-teleport snapback (first 2 seconds after spawn)
  if R.spawnPos and R.spawnClock and (now - R.spawnClock) <= 2.0 and not R.spawnSnapped then
    local spawnDist = (rp - R.spawnPos):length()
    if spawnDist >= 50.0 then
      local ok = pcall(function()
        if robber.setPositionRotation then
          robber:setPositionRotation(R.spawnPos, quat(0, 0, 0, 1))
        elseif robber.setPosition then
          robber:setPosition(R.spawnPos)
        end
      end)
      R.spawnSnapped = true
      if ok then
        log("Robber AI: snapped back to spawn (anti-teleport).")
        startFollowAI(R.spawnedId)
      else
        log("ERROR: failed to snap robber back to spawn.")
      end
    end
  end

  -- ============================================
  -- Pre-EMP stop: 7m before EMP distance, stop for 5s
  -- ============================================
  if (not R.empFired) and R.phase ~= "flee" and (not R.empPreStopTriggered) and d <= 25.0 then
    R.empPreStopTriggered = true
    R.empPreStopEnd = now + 5.0
    if robber.queueLuaCommand then
      pcall(function() robber:queueLuaCommand("input.event('brake', 1, 1)") end)
    end
    log("Robber AI: pre-EMP stop engaged (5s).")
  end

  -- ============================================
  -- EMP trigger: once, when within 18m
  -- ============================================
  if (not R.empFired) and R.phase ~= "flee" and d <= 18.0 then
    R.empFired = true
    R.empFiredAt = now
    R.empPlayerId = (pv.getID and pv:getID()) or ((be and be.getPlayerVehicleID) and be:getPlayerVehicleID(0)) or nil
    R.empFootstepsAt = (R.empFiredAt or 0) + 2.0
    R.empFootstepsPlayed = false
    R.empBrakeEnd = (R.empFiredAt or 0) + 2.0
    R.empFleeAt = (R.empFiredAt or 0) + 6.0
    R.empPreStopEnd = nil

    if robber.queueLuaCommand then
      pcall(function() robber:queueLuaCommand("input.event('brake', 1, 1)") end)
    end

    if R.empPlayerId and R.spawnedId then
      pcall(function()
        EMP.trigger({
          playerId = R.empPlayerId,
          sourceId = R.spawnedId,
          empDurationSec = 10.0,
          shockDurationSec = 0.5,
          thrusterKickSpeed = 5.0,
          forceMultiplier = 0.5,
        })
      end)
    end

    log("EMP fired: player robbed.")
  end

  if R.empFired and (not R.empFootstepsPlayed) and R.empFootstepsAt and now >= R.empFootstepsAt then
    Audio.playId(pv, AUDIO.footstepsName, AUDIO.footstepsVol, AUDIO.footstepsPitch, AUDIO.footstepsFile)
    R.empFootstepsPlayed = true
  end

  if R.empFired and not R.empSlowChaseApplied then
    local targetId = (be and be.getPlayerVehicleID) and be:getPlayerVehicleID(0) or nil
    if targetId and targetId > 0 then
      queueAI_EmpSlowChase(robber, targetId)
      R.empSlowChaseApplied = true
    end
  end

  -- 6 seconds after EMP firing, show message and switch to flee
  if R.empFired and (not R.empFleeTriggered) and R.empFleeAt and now >= R.empFleeAt then
    R.empFleeTriggered = true
    if not R.robberyProcessed then
      local money = getCareerMoney()
      if money then
        R.robbedAmount = money * 0.5
        adjustCareerMoney(money - R.robbedAmount)
      end
      R.robberyProcessed = true
    end
    local msgArgs = {
      title = "YOU'VE BEEN ROBBED",
      text = "Chase the robber!\n\nPress Continue to resume.",
      freeze = true,
      continueLabel = "Continue",
    }

    if Host and Host.showMissionMessage then
      Host.showMissionMessage(msgArgs)
    elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
      extensions.bolidesTheCut.showMissionMessage(msgArgs)
    else
      log("WARN: Mission message system not available for robbery alert.")
    end

    R.guiBaseMessage = "the robber took half your money"
    R.hideDistance = false
    updateGuiDistanceMessage(d)
    -- Keep audio behavior: chase2 at flee moment
    Audio.playId(pv, AUDIO.chase2Name, AUDIO.chase2Vol, AUDIO.chase2Pitch, AUDIO.chase2File)
    switchToFleeAI(R.spawnedId)
  end

  if R.empFleeTriggered and (not R.successTriggered) then
    if R.phase == "flee" then
      local targetId = (be and be.getPlayerVehicleID) and be:getPlayerVehicleID(0) or nil
      if targetId and targetId > 0 then
        local downhill = updateDownhillState(dtSim, robber)
        applyFleeProfile(robber, targetId, downhill and "downhill" or "normal")
      end
    end

    if d <= 7.0 then
      R.closeTimer = R.closeTimer + (dtSim or 0)
    else
      R.closeTimer = 0
    end

    if robberSpeedKph and robberSpeedKph <= 5.0 then
      R.robberSlowTimer = R.robberSlowTimer + (dtSim or 0)
    else
      R.robberSlowTimer = 0
    end

    if R.closeTimer >= 7.0 and R.robberSlowTimer >= 7.0 then
      R.successTriggered = true
      R.successDespawnAt = now + 15.0
      R.cashFound = math.random(50, 2500)
      if R.robberyProcessed and R.robbedAmount > 0 then
        local money = getCareerMoney()
        if money then
          adjustCareerMoney(money + R.robbedAmount + R.cashFound)
        end
      end
      R.guiBaseMessage = string.format(
        "you got your money back\nand you found $%d cash in the robbers glovebox",
        R.cashFound
      )
      R.hideDistance = true
      R.postSuccessMessageAt = now
      updateGuiDistanceMessage(d)

      if robber.queueLuaCommand then
        pcall(function()
          robber:queueLuaCommand([[
            if ai then
              pcall(function() ai.setMode("disabled") end)
              pcall(function() ai.setMode("none") end)
              pcall(function() ai.setAggression(0) end)
            end
          ]])
        end)
      end
    end
  end

  if R.successTriggered and R.successDespawnAt and now >= R.successDespawnAt then
    M.endEvent({ keepGuiMessage = true })
    return
  end

  if R.empFleeTriggered and (not R.successTriggered) and d >= 1000.0 then
    R.guiBaseMessage = "The robber has escaped with your money"
    R.hideDistance = true
    R.postSuccessMessageAt = now
    updateGuiDistanceMessage(d)
    M.endEvent({ keepGuiMessage = true })
    return
  end

  -- ============================================
  -- Old contactMade/waitForFlee logic:
  -- Disabled once EMP has fired
  -- ============================================
  if not R.empFired then
    local contactMade = d <= 2.5
    if R.phase ~= "flee" and contactMade and playerSpeedKph < 10 then
      if not R.waitForFlee then
        R.waitForFlee = true
        R.waitTimer = 0
        Audio.playId(pv, AUDIO.footstepsName, AUDIO.footstepsVol, AUDIO.footstepsPitch, AUDIO.footstepsFile)
      end
    else
      if not contactMade or playerSpeedKph >= 10 then
        R.waitForFlee = false
        R.waitTimer = 0
      end
    end

    if R.waitForFlee then
      R.waitTimer = R.waitTimer + (dtSim or 0)
      if R.waitTimer >= 3.0 then
        Audio.playId(pv, AUDIO.chase2Name, AUDIO.chase2Vol, AUDIO.chase2Pitch, AUDIO.chase2File)
        switchToFleeAI(R.spawnedId)
        R.waitForFlee = false
        R.waitTimer = 0
      end
    end
  end
end

return M
