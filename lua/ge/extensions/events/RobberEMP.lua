-- lua/ge/extensions/events/RobberEMP.lua
-- RobberEMP: manual spawn at ForwardKnownBreadcrumb(200m)
-- Behavior:
--   1) Spawn and FOLLOW player with limit settings (max 20kph).
--   2) When within 25m, fire EMP (engine off + brakes lock 10s + combined shockwave 0.5s).
--   3) 6s after EMP fired, message triggers and robber switches to flee mode.
--   5) Old "contactMade / waitForFlee" logic is disabled once EMP has fired.

local M = {}

local EMP = require('lua/ge/extensions/events/emp')
local CareerMoney = require("CareerMoney")
local PreloadEvent = require("lua/ge/extensions/events/PreloadEventNEW")

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
  robberStationaryTimer = 0,
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

  hudThreat = nil,
  hudStatus = nil,
  hudStatusBase = nil,
  pendingAiFrames = 0,
  aiStarted = false,
  pendingStart = false,
  pendingStartTransform = nil,
  pendingStartDeadline = nil,
  pendingStartNextAttemptAt = nil,
  pendingStartAttempts = 0,
}

local ROBBER_MODEL = "roamer"
local ROBBER_CONFIG = "robber_light.pc"

local function log(msg)
  R.status = msg or ""
  if Host and Host.postLine then
    Host.postLine("RobberEMP", R.status)
  else
    print("[RobberEMP] " .. tostring(R.status))
  end
end

local function chooseFkbPos(spacing, maxAgeSec, allowCached)
  maxAgeSec = maxAgeSec or 10.0
  allowCached = allowCached == true
  if not Host or not Host.Breadcrumbs or not Host.Breadcrumbs.getForwardKnown then
    return nil, "no breadcrumbs"
  end

  local cache = select(1, Host.Breadcrumbs.getForwardKnown())
  local entry = cache and cache[spacing]
  if not entry then return nil, "no entry" end

  if entry.available and entry.pos then
    return entry.pos, "live"
  end

  if allowCached and entry.lastGoodPos and entry.lastGoodT then
    local age = (os.clock() - entry.lastGoodT)
    if age <= maxAgeSec then
      return entry.lastGoodPos, "cached"
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
  if CareerMoney.set and CareerMoney.set(amount) then
    return true
  end
  return false
end

local function getCareerMoney()
  if not CareerMoney or not CareerMoney.isCareerActive or not CareerMoney.isCareerActive() then
    return nil
  end
  return CareerMoney.get and CareerMoney.get() or nil
end

local function addCareerMoney(delta)
  if not CareerMoney or not CareerMoney.isCareerActive or not CareerMoney.isCareerActive() then
    return false
  end
  if CareerMoney.add and CareerMoney.add(delta) then
    return true
  end
  local current = getCareerMoney()
  if current == nil then
    return false
  end
  return adjustCareerMoney(current + (tonumber(delta) or 0))
end

local function walletCanPay(amount)
  if not career_modules_payment or type(career_modules_payment.canPay) ~= "function" then return false end
  local ok, can = pcall(function()
    return career_modules_payment.canPay({ money = { amount = amount, canBeNegative = false } })
  end)
  return ok and can == true
end

local function walletRemove(amount)
  if not career_modules_payment or type(career_modules_payment.pay) ~= "function" then return false end
  local ok, res = pcall(function()
    return career_modules_payment.pay({ money = { amount = amount, canBeNegative = false } }, { label = "Robbery" })
  end)
  return ok and res == true
end

local function walletAdd(amount)
  if not career_modules_payment or type(career_modules_payment.reward) ~= "function" then return false end
  local ok, res = pcall(function()
    return career_modules_payment.reward({ money = { amount = amount } }, { label = "Recovered money" }, true)
  end)
  return ok and res == true
end

local function removeCareerMoney(amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then
    return false
  end
  if walletCanPay(amount) and walletRemove(amount) then
    return true
  end
  return addCareerMoney(-amount)
end

local function restoreCareerMoney(amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then
    return false
  end
  if walletAdd(amount) then
    return true
  end
  return addCareerMoney(amount)
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
  local model = ROBBER_MODEL
  local config = ROBBER_CONFIG

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

local function _getPlayerVeh()
  return (be and be.getPlayerVehicle) and be:getPlayerVehicle(0) or nil
end

local function _resolveAudioVeh(v)
  return _getPlayerVeh() or v
end

function Audio.ensureSources(v, sources)
  v = _resolveAudioVeh(v)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__robber1FKB200Audio = _G.__robber1FKB200Audio or { ids = {} }",
    "local A = _G.__robber1FKB200Audio.ids",
    "local function mk(path, name)",
    "  if A[name] then return end",
    "  local id = obj:createSFXSource(path, \"Audio2D\", name, 0)",
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
  v = _resolveAudioVeh(v)
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
  v = _resolveAudioVeh(v)
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

local function pushNewHudState(payload)
  if Host and Host.setNewHudState then
    Host.setNewHudState(payload)
    return
  end
  if extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.setNewHudState then
    extensions.bolidesTheCut.setNewHudState(payload)
  end
end

local function formatStatusWithDistance(status, distance)
  if not status or status == "" then return status end
  local distMeters = math.floor((distance or 0) + 0.5)
  return string.format("%s\nDistance to contact: %dm", status, distMeters)
end

local function resetPendingStart()
  R.pendingStart = false
  R.pendingStartTransform = nil
  R.pendingStartDeadline = nil
  R.pendingStartNextAttemptAt = nil
  R.pendingStartAttempts = 0
end

local function beginActiveRun(id)
  R.active = true
  R.spawnedId = id
  R.phase = "idle"
  R.distToPlayer = nil
  R.waitForFlee = false
  R.waitTimer = 0
  R.closeTimer = 0
  R.robberSlowTimer = 0
  R.robberStationaryTimer = 0
  R.successTriggered = false
  R.successDespawnAt = nil
  R.guiBaseMessage = "??????"
  R.hideDistance = true
  R.postSuccessMessageAt = nil
  setGuiStatusMessage(R.guiBaseMessage)

  R.spawnClock = os.clock()
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
  R.hudThreat = nil
  R.hudStatus = nil
  R.hudStatusBase = nil
  R.pendingAiFrames = 2
  R.aiStarted = false
  resetPendingStart()

  updateHudState({
    threat = "event",
    status = mergeStatusInstruction(
      "A vehicle is tailing you",
      "Stay alert and control your speed."
    ),
  })
end

local function mergeStatusInstruction(status, instruction)
  if not instruction or instruction == "" then
    return status
  end
  if not status or status == "" then
    return instruction
  end
  return string.format("%s\n%s", status, instruction)
end

local function updateHudState(payload)
  if not payload then return end

  local hasDelta = payload.moneyDelta or payload.inventoryDelta or payload.dangerReason
  local changed = false

  if payload.threat and payload.threat ~= R.hudThreat then
    R.hudThreat = payload.threat
    changed = true
  end
  if payload.status then
    R.hudStatusBase = payload.status
  end
  local statusToSend = nil
  if R.hudStatusBase then
    statusToSend = formatStatusWithDistance(R.hudStatusBase, R.distToPlayer)
  end
  if statusToSend and statusToSend ~= R.hudStatus then
    R.hudStatus = statusToSend
    changed = true
  end
  if statusToSend then
    payload.status = statusToSend
  end

  if changed or hasDelta then
    pushNewHudState(payload)
  end
end

local function updateGuiDistanceMessage(distance)
  if not R.guiBaseMessage then return end
  if R.hideDistance then
    setGuiStatusMessage(R.guiBaseMessage)
    return
  end
  local distMeters = math.floor((distance or 0) + 0.5)
  setGuiStatusMessage(string.format("%s\nDistance to contact: %dm", R.guiBaseMessage, distMeters))
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

function M.getDistanceToPlayer()
  return R.distToPlayer
end

function M.getRobberVehicleId()
  return R.spawnedId
end
function M.getDebugState()
  return {
    careerActive = CareerMoney and CareerMoney.isCareerActive and CareerMoney.isCareerActive() or false,
    money = getCareerMoney(),
    robberyProcessed = R.robberyProcessed,
    robbedAmount = R.robbedAmount,
    empFired = R.empFired,
    empFleeTriggered = R.empFleeTriggered,
    empSlowChaseApplied = R.empSlowChaseApplied,
    empPreStopTriggered = R.empPreStopTriggered,
    successTriggered = R.successTriggered,
    phase = R.phase,
  }
end

function M.getSpawnMethod()
  return R.spawnMethod
end

function M.getPendingStartState()
  local state = (PreloadEvent and PreloadEvent.getClaimState and PreloadEvent.getClaimState("RobberEMP")) or nil
  return {
    pending = state ~= nil,
    attempts = state and state.attempts or 0,
    deadline = state and state.timeoutAt or nil,
    nextAttemptAt = state and state.nextAttemptAt or nil,
    err = state and state.lastError or nil,
  }
end

function M.getPreloadSpec()
  return {
    eventName = "RobberEMP",
    model = ROBBER_MODEL,
    config = ROBBER_CONFIG,
    prewarmAudio = function(playerVeh)
      Audio.ensureAll(playerVeh)
    end,
  }
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

  local fkbPos, mode = chooseFkbPos(200, 10.0, true)
  if not fkbPos then
    log("BLOCKED: FKB 200m not available (no stable cached point).")
    return false
  end

  R.spawnMode = mode
  R.spawnPos = fkbPos + vec3(0, 0, 0.8)
  R.spawnMethod = nil
  resetPendingStart()
  log("Using FKB 200 (" .. tostring(mode) .. ")")

  local tf = makeSpawnTransform(pv, R.spawnPos)
  if not (PreloadEvent and PreloadEvent.beginClaim) then
    log("BLOCKED: preload manager unavailable.")
    return false
  end

  local claim = PreloadEvent.beginClaim("RobberEMP", tf, {
    requestSpec = (PreloadEvent and PreloadEvent.getRegisteredSpec and PreloadEvent.getRegisteredSpec("RobberEMP"))
      or M.getPreloadSpec(),
    timeoutSec = 30.0,
    retryIntervalSec = 0.25,
    claimOptions = {
      model = ROBBER_MODEL,
      config = ROBBER_CONFIG,
      consumeRetries = 3,
      consumeMaxDist = 5.0,
      consumeSkipSafeTeleport = false,
    },
  })

  if claim and claim.id then
    R.spawnMethod = "PreloadEvent"
    beginActiveRun(claim.id)
    return true
  end

  R.pendingStart = true
  R.pendingStartTransform = tf
  R.pendingStartDeadline = claim and claim.deadline or nil
  R.pendingStartNextAttemptAt = claim and claim.nextAttemptAt or nil
  R.pendingStartAttempts = claim and claim.attempts or 0
  updateHudState({
    threat = "event",
    status = mergeStatusInstruction(
      "Stay Alert",
      "Waiting for robber preload handoff."
    ),
  })
  log("Pending start: waiting for preload handoff.")
  return true
end

function M.endEvent(opts)
  if not R.active and not R.pendingStart then return end
  opts = opts or {}

  if R.pendingStart and not R.active then
    if PreloadEvent and PreloadEvent.cancelClaim then
      pcall(PreloadEvent.cancelClaim, "RobberEMP")
    end
    resetPendingStart()
    if not opts.keepHudState then
      updateHudState({
        threat = "safe",
        status = mergeStatusInstruction(
          "Threat cleared.",
          "Resume route."
        ),
      })
    end
    if not opts.keepGuiMessage then
      setGuiStatusMessage(nil)
    end
    log("Ended (pending start cancelled).")
    return
  end

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
  R.robberStationaryTimer = 0
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
  R.hudThreat = nil
  R.hudStatus = nil
  R.hudStatusBase = nil
  R.pendingAiFrames = 0
  R.aiStarted = false
  resetPendingStart()

  if not opts.keepGuiMessage then
    setGuiStatusMessage(nil)
    R.postSuccessMessageAt = nil
  end

  if not opts.keepHudState then
    updateHudState({
      threat = "safe",
      status = mergeStatusInstruction(
        "The robber has been stopped.",
        "Stay alert and control your speed."
      ),
    })
  end

  if type(id) == "number" then
    local v = getObjById(id)
    if v then
      if PreloadEvent and PreloadEvent.release then
        local ok = pcall(PreloadEvent.release, "RobberEMP", id, { model = ROBBER_MODEL, config = ROBBER_CONFIG })
        if not ok then
          pcall(function() v:delete() end)
        end
      else
        pcall(function() v:delete() end)
      end
    end
  end

  log("Ended.")
end

function M.update(dtSim)

  if R.pendingStart and not R.active then
    if not (PreloadEvent and PreloadEvent.updateClaim) then
      resetPendingStart()
      updateHudState({
        threat = "safe",
        status = mergeStatusInstruction(
          "Threat cleared.",
          "Resume route."
        ),
      })
      log("Pending start cancelled: preload manager unavailable.")
      return
    end

    local claim = PreloadEvent.updateClaim("RobberEMP")
    if claim and claim.status == "claimed" and claim.id then
      R.spawnMethod = "PreloadEvent"
      log("Pending start resolved via preload handoff.")
      beginActiveRun(claim.id)
      return
    end

    if claim and claim.status == "timeout" then
      local fallbackTf = R.pendingStartTransform
      local fallbackId = fallbackTf and spawnVehicleAt(fallbackTf) or nil
      resetPendingStart()

      if fallbackId then
        R.spawnMethod = "FallbackSpawnOnTimeout"
        log("Pending start timed out; fallback cold spawn started.")
        beginActiveRun(fallbackId)
        return
      end

      updateHudState({
        threat = "event",
        status = mergeStatusInstruction(
          "Preload delayed",
          "Robber event will resume once handoff is ready."
        ),
      })
      log("Pending start timed out; preload not ready.")
      return
    end

    if claim then
      R.pendingStartAttempts = claim.attempts or R.pendingStartAttempts
      R.pendingStartDeadline = claim.deadline or R.pendingStartDeadline
      R.pendingStartNextAttemptAt = claim.nextAttemptAt or R.pendingStartNextAttemptAt
      if claim.err and (R.pendingStartAttempts % 8 == 0) then
        log("Pending start retry still waiting (" .. tostring(claim.err) .. ")")
      end
    end
  end

  if not R.active then
    if R.postSuccessMessageAt and os.clock() >= (R.postSuccessMessageAt + 60.0) then
      setGuiStatusMessage("nothing unusual")
      R.postSuccessMessageAt = nil
    end
    return
  end

  if not R.aiStarted and R.pendingAiFrames and R.pendingAiFrames > 0 then
    R.pendingAiFrames = R.pendingAiFrames - 1
    if R.pendingAiFrames <= 0 and R.spawnedId then
      startFollowAI(R.spawnedId)
      R.aiStarted = true
    end
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
    R.robberStationaryTimer = 0
    setGuiStatusMessage(nil)
    updateHudState({
      threat = "safe",
      status = mergeStatusInstruction(
        "The robber has been stopped.",
        "Stay alert and control your speed."
      ),
    })
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
  if R.hudStatusBase then
    updateHudState({ status = R.hudStatusBase })
  end

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

  if robberSpeedKph and robberSpeedKph <= 1.0 then
    R.robberStationaryTimer = R.robberStationaryTimer + (dtSim or 0)
  else
    R.robberStationaryTimer = 0
  end

  if R.robberStationaryTimer >= 30.0 and d >= 500.0 then
    updateHudState({
      threat = "safe",
      status = mergeStatusInstruction(
        "you live to fight another day",
        "carry on with your business"
      ),
    })
    local msgArgs = {
      title = "NOTICE",
      text = "you live to fight another day",
      freeze = true,
      continueLabel = "Continue",
      nextEventName = "RobberShotgun",
    }
    if Host and Host.showMissionMessage then
      Host.showMissionMessage(msgArgs)
    elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
      extensions.bolidesTheCut.showMissionMessage(msgArgs)
    end
    M.endEvent({ keepHudState = true })
    return
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

    updateHudState({
      threat = "danger",
      status = mergeStatusInstruction(
        "You've been robbed, chase the robber down and stop their vehicle to get it back",
        "Create distance or disable the robber."
      ),
      dangerReason = "emp",
    })

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
        R.robbedAmount = math.max(0, math.floor((money * 0.5) + 0.5))
        removeCareerMoney(R.robbedAmount)
      end
      R.robberyProcessed = true
    end

    local robbedDelta = nil
    local robbedText = nil
    if R.robbedAmount and R.robbedAmount > 0 then
      robbedDelta = -R.robbedAmount
      if CareerMoney and CareerMoney.fmt then
        robbedText = CareerMoney.fmt(R.robbedAmount)
      else
        robbedText = string.format("%d", math.floor(R.robbedAmount))
      end
    end
    updateHudState({
      threat = "danger",
      status = mergeStatusInstruction(
        "You've been robbed, chase the robber down and stop their vehicle to get it back",
        "Stop the robber vehicle to recover your money."
      ),
      dangerReason = "robbed",
      moneyDelta = robbedDelta,
    })

    R.guiBaseMessage = "You've been robbed, chase the robber down and stop their vehicle to get it back"
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
        restoreCareerMoney(R.robbedAmount + R.cashFound)
      end
      local recoveredDelta = 0
      if R.robbedAmount then
        recoveredDelta = recoveredDelta + R.robbedAmount
      end
      if R.cashFound then
        recoveredDelta = recoveredDelta + R.cashFound
      end
      local empRewardText = nil
      local empInstruction = nil
      local inventoryDelta = {}
      local rewardNotes = {}
      local empCharges = math.random(1, 3)
      empRewardText = string.format("%d EMP charges", empCharges)
      empInstruction = nil
      inventoryDelta[#inventoryDelta + 1] = {
        id = "emp",
        name = "EMP Device",
        ammoLabel = "Charges",
        ammoDelta = empCharges,
      }
      local bonusAmmo = 0
      if math.random() < 0.7 then
        bonusAmmo = math.random(1, 3)
        inventoryDelta[#inventoryDelta + 1] = {
          id = "pistol",
          name = "Pistol",
          ammoLabel = "Ammo",
          ammoDelta = bonusAmmo,
        }
        rewardNotes[#rewardNotes + 1] = string.format("%d ammo", bonusAmmo)
      end
      local statusMessage = "You got your money back"
      local foundNotes = {}
      if R.cashFound and R.cashFound > 0 then
        foundNotes[#foundNotes + 1] = string.format("$%d", R.cashFound)
      end
      if empRewardText then
        foundNotes[#foundNotes + 1] = empRewardText
      end
      if #rewardNotes > 0 then
        for _, note in ipairs(rewardNotes) do
          foundNotes[#foundNotes + 1] = note
        end
      end
      if #foundNotes > 0 then
        statusMessage = statusMessage .. " (and found " .. table.concat(foundNotes, " and ") .. ")"
      end
      local msgArgs = {
        title = "NOTICE",
        text = statusMessage,
        freeze = true,
        continueLabel = "Continue",
      }
      if Host and Host.showMissionMessage then
        Host.showMissionMessage(msgArgs)
      elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
        extensions.bolidesTheCut.showMissionMessage(msgArgs)
      end
      updateHudState({
        threat = "safe",
        status = mergeStatusInstruction(
          statusMessage,
          empInstruction or "Stay alert and control your speed."
        ),
        moneyDelta = recoveredDelta > 0 and recoveredDelta or nil,
        inventoryDelta = #inventoryDelta > 0 and inventoryDelta or nil,
      })
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
    M.endEvent({ keepGuiMessage = true, keepHudState = true })
    return
  end

  if (not R.successTriggered) and d >= 800.0 then
    local escapedWithMoney = R.robberyProcessed and (R.robbedAmount or 0) > 0
    local finalText = "you live to fight another day"

    if escapedWithMoney then
      local robbedText = nil
      if CareerMoney and CareerMoney.fmt then
        robbedText = CareerMoney.fmt(R.robbedAmount)
      else
        robbedText = string.format("%d", math.floor(R.robbedAmount))
      end
      finalText = string.format("The robber escaped with your money, you lost $%s", robbedText)
    end

    R.guiBaseMessage = finalText
    R.hideDistance = true
    R.postSuccessMessageAt = now
    updateGuiDistanceMessage(d)

    updateHudState({
      threat = "safe",
      status = mergeStatusInstruction(finalText, "Stay alert and control your speed."),
    })

    local msgArgs = {
      title = "NOTICE",
      text = finalText,
      freeze = true,
      continueLabel = "Continue",
    }
    if Host and Host.showMissionMessage then
      Host.showMissionMessage(msgArgs)
    elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
      extensions.bolidesTheCut.showMissionMessage(msgArgs)
    end
    M.endEvent({ keepGuiMessage = true, keepHudState = true })
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
