-- lua/ge/extensions/events/RobberShotgun.lua
-- RobberShotgun: manual spawn at ForwardKnownBreadcrumb(200m)
-- Behavior:
--   1) Spawn and FOLLOW player (legal speed, lane changes, avoid cars/obstacles).
--   2) When within 50m, fire shotgun damage at fixed 2.0s intervals.
--   3) When within 30m, switch to FLEE until event end.
--   4) End when robber escapes to 800m (despawn).

local M = {}

local BulletDamage = require("lua/ge/extensions/events/BulletDamage")
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
  preloadEventName = nil,

  phase = "idle",
  distToPlayer = nil,
  nextShotAt = nil,

  spawnClock = nil,
  spawnSnapped = false,

  shotsStarted = false,
  fleeNotified = false,
  hudStatusBase = nil,
  successTriggered = false,
  successDespawnAt = nil,
  closeTimer = 0,
  robberSlowTimer = 0,
  robberStationaryTimer = 0,
}

local ROBBER_MODEL = "roamer"
local ROBBER_CONFIG = "robber_light.pc"
local ROBBER_SHOT_FORCE_MULTIPLIER = 0.35
local ROBBER_SHOT_EXPLOSION_FORCE = 30.0
local ROBBER_SHOT_EXPLOSION_RADIUS = 1.0

local function log(msg)
  R.status = msg or ""
  if Host and Host.postLine then
    Host.postLine("ROBBERSHOTGUN", R.status)
  else
    print("[RobberShotgun] " .. tostring(R.status))
  end
end

local function addCareerMoney(amount)
  if not amount or amount == 0 then return false end
  if not career_modules_payment then return false end
  if amount > 0 then
    if type(career_modules_payment.reward) == "function" then
      return career_modules_payment.reward({ money = { amount = amount } }, { label = "Reward" }, true)
    end
  end
  if type(career_modules_payment.pay) == "function" then
    return career_modules_payment.pay(amount, { label = "Reward" })
  end
  return false
end

local function formatStatusWithDistance(status, distance)
  if not status or status == "" then return status end
  local distMeters = math.floor((distance or 0) + 0.5)
  return string.format("%s\nDistance to contact: %dm", status, distMeters)
end

local function pushHudState(payload)
  if Host and Host.setNewHudState then
    Host.setNewHudState(payload)
  elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.setNewHudState then
    extensions.bolidesTheCut.setNewHudState(payload)
  end
end

local function setHud(threat, status, instruction, dangerReason)
  R.hudStatusBase = status
  pushHudState({
    threat = threat,
    status = formatStatusWithDistance(status, R.distToPlayer),
    instruction = instruction,
    dangerReason = dangerReason,
  })
end

local function refreshHudStatusDistance()
  if not R.hudStatusBase then return end
  pushHudState({
    status = formatStatusWithDistance(R.hudStatusBase, R.distToPlayer),
  })
end

local function resetRuntime()
  R.active = false
  R.spawnedId = nil
  R.spawnPos = nil
  R.spawnMode = nil
  R.spawnMethod = nil
  R.preloadEventName = nil
  R.phase = "idle"
  R.distToPlayer = nil
  R.nextShotAt = nil
  R.spawnClock = nil
  R.spawnSnapped = false
  R.shotsStarted = false
  R.fleeNotified = false
  R.hudStatusBase = nil
  R.successTriggered = false
  R.successDespawnAt = nil
  R.closeTimer = 0
  R.robberSlowTimer = 0
  R.robberStationaryTimer = 0
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
  eventStartName = "robberShotgunStart",
  eventStartVol = 1.0,
  eventStartPitch = 1.0,
}

local function getAudioHelper()
  if not extensions or not extensions.bolidesTheCut then return nil end
  return extensions.bolidesTheCut.Audio
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
  local audio = getAudioHelper()
  if playerVeh and audio and audio.ensureSources then
    audio.ensureSources(playerVeh, {
      { file = AUDIO.eventStartFile, name = AUDIO.eventStartName },
    })
  end
  queueAI_FollowLegal(veh, targetId)
  R.phase = "follow"
  R.nextShotAt = nil

  if playerVeh and audio and audio.playId then
    audio.playId(playerVeh, AUDIO.eventStartName, AUDIO.eventStartVol, AUDIO.eventStartPitch, AUDIO.eventStartFile)
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

local function _garageMenuActive()
  if not (gameplay_garageMode and gameplay_garageMode.getGarageMenuState) then
    return false
  end
  local ok, state = pcall(gameplay_garageMode.getGarageMenuState)
  if not ok then return false end
  if state == nil or state == false then return false end
  if type(state) == "string" then
    local lowered = string.lower(state)
    return lowered ~= "none" and lowered ~= "closed" and lowered ~= "inactive"
  end
  return true
end

local function _playerInGarageZone(pv)
  if not pv or not pv.getPosition then return false end
  local gm = career_modules_garageManager
  if not gm then return false end

  local pos = pv:getPosition()
  if gm.isPositionInGarageZone and pos then
    local ok, inZone = pcall(gm.isPositionInGarageZone, pos)
    if ok and inZone then return true end
  end

  if gm.isSpawnedVehicleInGarageZone and pv.getID then
    local ok, inZone = pcall(gm.isSpawnedVehicleInGarageZone, pv:getID())
    if ok and inZone then return true end
  end

  return false
end

local function shouldAbortForGarage(pv)
  return _garageMenuActive() or _playerInGarageZone(pv)
end

local function triggerShot(playerVeh, robberVeh)
  if not BulletDamage or not BulletDamage.trigger then
    log("WARN: BulletDamage module missing.")
    return false
  end
  if not playerVeh or not robberVeh then return false end

  local audio = getAudioHelper()
  if audio and audio.playGunshot then
    audio.playGunshot(playerVeh)
  end

  local ok, info = BulletDamage.trigger({
    targetId = playerVeh:getID(),
    sourceId = robberVeh:getID(),
    accuracyRadius = 3.0,
    impactForceMultiplier = ROBBER_SHOT_FORCE_MULTIPLIER,
    explosionForce = ROBBER_SHOT_EXPLOSION_FORCE,
    explosionRadius = ROBBER_SHOT_EXPLOSION_RADIUS,
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

function M.getRobberVehicleId()
  return R.spawnedId
end

function M.getSpawnMethod()
  return R.spawnMethod
end

function M.getPreloadSpec()
  return {
    eventName = "RobberShotgun",
    model = ROBBER_MODEL,
    config = ROBBER_CONFIG,
    prewarmAudio = function(playerVeh)
      local audio = getAudioHelper()
      if audio then
        audio.ensureSources(playerVeh, {
          { file = AUDIO.eventStartFile, name = AUDIO.eventStartName },
        })
      end
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
  local id = nil
  if PreloadEvent and PreloadEvent.consume then
    id = PreloadEvent.consume("RobberEMP", tf)
    if id then
      R.spawnMethod = "PreloadEvent"
      R.preloadEventName = "RobberEMP"
    else
      id = PreloadEvent.consume("RobberShotgun", tf)
      if id then
        R.spawnMethod = "PreloadEvent"
        R.preloadEventName = "RobberShotgun"
      end
    end
  end
  if not id then
    id = spawnVehicleAt(tf)
  end
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
    "A vehicle is tailing you",
    "Keep moving. Watch your mirrors.",
    nil
  )
  return true
end

function M.endEvent(reason)
  if not R.active then return end

  local status = "Threat cleared."
  if reason == "escape" then
    status = "All clear"
  elseif reason == "escaped_without_harm" then
    status = "you live to fight another day"
  elseif reason == "caught" then
    status = R.hudStatusBase or "You took down the attacker"
  elseif reason == "garage" then
    status = "Threat cleared after towing to garage."
  end
  local instruction = "Resume route."
  if reason == "escaped_without_harm" then
    instruction = "carry on with your business"
  end
  setHud(
    "safe",
    status,
    instruction,
    nil
  )

  local id = R.spawnedId
  local preloadName = R.preloadEventName
  resetRuntime()

  if type(id) == "number" then
    local v = getObjById(id)
    if v then
      if PreloadEvent and PreloadEvent.stash then
        preloadName = preloadName or "RobberShotgun"
        local ok = pcall(PreloadEvent.stash, preloadName, id, { model = ROBBER_MODEL, config = ROBBER_CONFIG })
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

  if shouldAbortForGarage(pv) then
    M.endEvent("garage")
    return
  end

  local rp = robber:getPosition()
  local pp = pv:getPosition()
  if not (rp and pp) then return end

  local d = (rp - pp):length()
  R.distToPlayer = d
  refreshHudStatusDistance()
  local now = os.clock()

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
    local msgArgs = {
      title = "NOTICE",
      text = "you live to fight another day",
      freeze = true,
      continueLabel = "Continue",
      nextEventName = "RobberEMP",
    }
    if Host and Host.showMissionMessage then
      Host.showMissionMessage(msgArgs)
    elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
      extensions.bolidesTheCut.showMissionMessage(msgArgs)
    end
    M.endEvent("escaped_without_harm")
    return
  end

  if d >= 800.0 then
    local msgArgs = {
      title = "NOTICE",
      text = "All clear",
      freeze = true,
      continueLabel = "Continue",
    }
    if Host and Host.showMissionMessage then
      Host.showMissionMessage(msgArgs)
    elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
      extensions.bolidesTheCut.showMissionMessage(msgArgs)
    end
    M.endEvent("escape")
    return
  end

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

  if R.phase == "flee" and not R.successTriggered then
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
      R.successDespawnAt = now + 12.0
      R.nextShotAt = nil
      R.shotsStarted = false
      local inventoryDelta = {}
      local rewardNotes = {}
      if math.random() < 0.75 then
        inventoryDelta[#inventoryDelta + 1] = {
          id = "pistol",
          name = "Pistol",
          ammoLabel = "Ammo",
          ammoDelta = 0,
        }
        rewardNotes[#rewardNotes + 1] = "a pistol"
      end
      if math.random() < 0.70 then
        local bonusAmmo = math.random(2, 6)
        inventoryDelta[#inventoryDelta + 1] = {
          id = "pistol",
          name = "Pistol",
          ammoLabel = "Ammo",
          ammoDelta = bonusAmmo,
        }
        rewardNotes[#rewardNotes + 1] = string.format("%d ammo", bonusAmmo)
      end
      local cashFound = math.random(50, 1500)
      addCareerMoney(cashFound)
      rewardNotes[#rewardNotes + 1] = string.format("$%d", cashFound)
      local empRewardText = nil
      if math.random() < 0.5 then
        empRewardText = "an EMP device"
        inventoryDelta[#inventoryDelta + 1] = {
          id = "emp",
          name = "EMP Device",
          ammoLabel = "Charges",
          ammoDelta = 0,
        }
      else
        local empCharges = math.random(1, 3)
        empRewardText = string.format("%d EMP charges", empCharges)
        inventoryDelta[#inventoryDelta + 1] = {
          id = "emp",
          name = "EMP Device",
          ammoLabel = "Charges",
          ammoDelta = empCharges,
        }
      end
      rewardNotes[#rewardNotes + 1] = empRewardText
      local status = "You took down the attacker"
      if #rewardNotes > 0 then
        status = status .. " (and found " .. table.concat(rewardNotes, " and ") .. ")"
      end
      local msgArgs = {
        title = "NOTICE",
        text = status,
        freeze = true,
        continueLabel = "Continue",
      }
      if Host and Host.showMissionMessage then
        Host.showMissionMessage(msgArgs)
      elseif extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.showMissionMessage then
        extensions.bolidesTheCut.showMissionMessage(msgArgs)
      end
      R.hudStatusBase = status
      pushHudState({
        threat = "safe",
        status = formatStatusWithDistance(status, R.distToPlayer),
        instruction = "Secure the area and continue.",
        dangerReason = nil,
        moneyDelta = cashFound,
        inventoryDelta = #inventoryDelta > 0 and inventoryDelta or nil,
      })
    end
  end

  if R.successTriggered and R.successDespawnAt and now >= R.successDespawnAt then
    M.endEvent("caught")
    return
  end

  if R.successTriggered then
    R.nextShotAt = nil
    return
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
        "Shots fired, escape",
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

end

return M
