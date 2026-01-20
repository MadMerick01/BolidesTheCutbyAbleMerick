-- lua/ge/extensions/events/RobberShotgun.lua
-- RobberShotgun: manual spawn at ForwardKnownBreadcrumb(200m)
-- Behavior:
--   1) Spawn and FOLLOW player (legal speed, lane changes, avoid cars/obstacles).
--   2) When within 50m, fire shotgun damage at fixed 2.0s intervals.
--   3) When within 30m, switch to FLEE until event end.
--   4) End when robber escapes to 500m while fleeing (despawn).

local M = {}

local BulletDamage = require("lua/ge/extensions/events/BulletDamage")
local NewHud = require("lua/ge/extensions/NewHud")

local CFG = nil
local Host = nil

local R = {
  active = false,
  spawnedId = nil,
  status = "",
  spawnPos = nil,
  spawnMode = nil,
  spawnMethod = nil,

  phase = "idle",
  distToPlayer = nil,
  nextShotAt = nil,

  spawnClock = nil,
  spawnSnapped = false,

  shotsStarted = false,
  fleeNotified = false,
  hudStatusBase = nil,
}

local function log(msg)
  R.status = msg or ""
  if Host and Host.postLine then
    Host.postLine("ROBBERSHOTGUN", R.status)
  else
    print("[RobberShotgun] " .. tostring(R.status))
  end
end

local function formatStatusWithDistance(status, distance)
  if not status or status == "" then return status end
  local distMeters = math.floor((distance or 0) + 0.5)
  return string.format("%s\nDistance to contact: %dm", status, distMeters)
end

local function setHud(threat, status, instruction, dangerReason)
  if not NewHud then return end
  if NewHud.setThreat then
    NewHud.setThreat(threat)
  end
  if NewHud.setStatus then
    R.hudStatusBase = status
    NewHud.setStatus(formatStatusWithDistance(status, R.distToPlayer))
  end
  if NewHud.setInstruction then
    NewHud.setInstruction(instruction)
  end
  if NewHud.setDangerReason then
    NewHud.setDangerReason(dangerReason)
  end
end

local function refreshHudStatusDistance()
  if not NewHud or not NewHud.setStatus then return end
  if not R.hudStatusBase then return end
  NewHud.setStatus(formatStatusWithDistance(R.hudStatusBase, R.distToPlayer))
end

local function resetRuntime()
  R.active = false
  R.spawnedId = nil
  R.spawnPos = nil
  R.spawnMode = nil
  R.spawnMethod = nil
  R.phase = "idle"
  R.distToPlayer = nil
  R.nextShotAt = nil
  R.spawnClock = nil
  R.spawnSnapped = false
  R.shotsStarted = false
  R.fleeNotified = false
  R.hudStatusBase = nil
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
  eventStartName = "robberShotgunStart",
  eventStartVol = 1.0,
  eventStartPitch = 1.0,
}

local Audio = {}

function Audio.ensureSources(v, sources)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__robberShotgunAudio = _G.__robberShotgunAudio or { ids = {} }",
    "local A = _G.__robberShotgunAudio.ids",
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
  })
end

function Audio.playId(v, name, vol, pitch, fileFallback)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  fileFallback = tostring(fileFallback or "")

  local cmd = string.format([[ 
    if not (_G.__robberShotgunAudio and _G.__robberShotgunAudio.ids) then return end
    local id = _G.__robberShotgunAudio.ids[%q]
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

local function getObjById(id)
  if type(id) ~= "number" then return nil end
  if getObjectByID then return getObjectByID(id) end
  if be and be.getObjectByID then return be:getObjectByID(id) end
  return nil
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

local function queueAI_FollowLegal(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[RobberShotgun AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[RobberShotgun AI] ai missing"); return end

    try('ai.setMode("follow")', function() ai.setMode("follow") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)

    try("ai.setAggression(0.2)", function()
      if ai.setAggression then ai.setAggression(0.2) end
    end)

    try("ai.setAllowLaneChanges(true)", function()
      if ai.setAllowLaneChanges then ai.setAllowLaneChanges(true) end
    end)
    try('ai.driveInLane("off")', function()
      if ai.driveInLane then ai.driveInLane("off") end
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

    try("ai.setStopDistance(20)", function()
      if ai.setStopDistance then ai.setStopDistance(20) end
    end)

    print("[RobberShotgun AI] FOLLOW armed (legal, lane changes, avoid cars/crash). targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_Flee(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[RobberShotgun AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[RobberShotgun AI] ai missing"); return end

    try('ai.setMode("flee")', function() ai.setMode("flee") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)

    try("ai.setAggression(0.35)", function()
      if ai.setAggression then ai.setAggression(0.35) end
    end)

    try("ai.setAllowLaneChanges(true)", function()
      if ai.setAllowLaneChanges then ai.setAllowLaneChanges(true) end
    end)
    try('ai.driveInLane("off")', function()
      if ai.driveInLane then ai.driveInLane("off") end
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

    print("[RobberShotgun AI] FLEE armed (legal, lane changes, avoid cars/crash). targetId="..tostring(tid))
  ]]):format(targetId))
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
  queueAI_FollowLegal(veh, targetId)
  R.phase = "follow"
  R.nextShotAt = nil

  if playerVeh then
    Audio.playId(playerVeh, AUDIO.eventStartName, AUDIO.eventStartVol, AUDIO.eventStartPitch, AUDIO.eventStartFile)
  end
  log("RobberShotgun AI: FOLLOW (legal, lane changes, avoid cars/crash). targetId=" .. tostring(targetId))
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
  queueAI_Flee(veh, targetId)
  log("RobberShotgun AI: switched to FLEE")
end

local function randomShotDelay()
  return 0.7 + (math.random() * 1.8)
end

local function triggerShot(playerVeh, robberVeh)
  if not BulletDamage or not BulletDamage.trigger then
    log("WARN: BulletDamage module missing.")
    return false
  end
  if not playerVeh or not robberVeh then return false end

  local ok, info = BulletDamage.trigger({
    targetId = playerVeh:getID(),
    sourceId = robberVeh:getID(),
    accuracyRadius = 3.0,
    applyDamage = false,
  })

  if not ok then
    log("Shot failed: " .. tostring(info))
    return false
  end

  return true
end

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
  R.nextShotAt = nil
  R.shotsStarted = false
  R.fleeNotified = false

  R.spawnClock = os.clock()
  R.spawnSnapped = false

  startFollowAI(id)
  setHud(
    "event",
    "A vehicle is tailing you.",
    "Keep moving. Watch your mirrors.",
    nil
  )
  return true
end

function M.endEvent(reason)
  if not R.active then return end

  local status = "Threat cleared."
  if reason == "escape" then
    status = "Contact lost."
  end
  setHud(
    "safe",
    status,
    "Resume route.",
    nil
  )

  local id = R.spawnedId
  resetRuntime()

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
  if not R.active then return end

  local robber = getObjById(R.spawnedId)
  if not robber then
    if R.active then
      setHud(
        "safe",
        "Threat cleared.",
        "Resume route.",
        nil
      )
    end
    resetRuntime()
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
  refreshHudStatusDistance()
  local now = os.clock()

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
        log("RobberShotgun AI: snapped back to spawn (anti-teleport).")
        startFollowAI(R.spawnedId)
      else
        log("ERROR: failed to snap robber back to spawn.")
      end
    end
  end

  if R.phase ~= "flee" and d <= 30.0 then
    switchToFleeAI(R.spawnedId)
    if not R.fleeNotified then
      setHud(
        "danger",
        "The attacker is breaking away.",
        "Pursue if safe. Stop the attacker.",
        R.shotsStarted and "shotsFired" or nil
      )
      R.fleeNotified = true
    end
  end

  if d <= 50.0 then
    if not R.shotsStarted then
      R.shotsStarted = true
      setHud(
        "danger",
        "Shots fired.",
        "Break line of sight or create distance.",
        "shotsFired"
      )
    end
    if not R.nextShotAt then
      R.nextShotAt = now + randomShotDelay()
    elseif now >= R.nextShotAt then
      triggerShot(pv, robber)
      R.nextShotAt = now + randomShotDelay()
    end
  else
    R.nextShotAt = nil
  end

  if R.phase == "flee" and d >= 500.0 then
    M.endEvent("escape")
    return
  end
end

return M
