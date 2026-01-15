-- lua/ge/extensions/events/fireAttack.lua
-- Fire Attack: spawn pigeon vehicle near player and ignite on approach.

local M = {}

local CFG = nil
local Host = nil

local R = {
  active = false,
  spawnedId = nil,
  status = "",
  spawnPos = nil,
  spawnMode = nil,
  spawnMethod = nil,

  phase = "idle", -- "follow" | "chase" | "disabled"
  distToPlayer = nil,
  igniteTriggered = false,
  detonated = false,
  detonateAt = nil,
  disableApplied = false,
  guiMessage = nil,

  -- Anti-teleport snapback
  spawnClock = nil,
  spawnSnapped = false,
}

local randomSeeded = false

local function seedRandom()
  if randomSeeded then return end
  randomSeeded = true
  if os and os.time then
    math.randomseed(os.time())
  else
    math.randomseed(0)
  end
  math.random()
  math.random()
  math.random()
end

local function log(msg)
  R.status = msg or ""
  if Host and Host.postLine then
    Host.postLine("FIRE_ATTACK", R.status)
  else
    print("[FireAttack] " .. tostring(R.status))
  end
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

local function getPlayerVeh()
  if Host and Host.getPlayerVeh then
    return Host.getPlayerVeh()
  end
  if be and be.getPlayerVehicle then
    return be:getPlayerVehicle(0)
  end
  return nil
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

local function getBackCrumbPos(meters)
  if not Host or not Host.Breadcrumbs then return nil, "no breadcrumbs" end

  if Host.Breadcrumbs.getCrumbBack then
    local ok, pos = pcall(Host.Breadcrumbs.getCrumbBack, meters)
    if ok and pos then
      return pos, "host"
    end
  end

  if Host.Breadcrumbs.getBack then
    local _, backPos = Host.Breadcrumbs.getBack()
    if backPos and backPos[meters] then
      return backPos[meters], "cache"
    end
  end

  return nil, "no back crumb"
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
  local model = "pigeon"
  local config = "race"

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
  eventStartName = "fireAttackEventStart",
  eventStartVol = 1.0,
  eventStartPitch = 1.0,
}

local Audio = {}

function Audio.ensureSources(v, sources)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__fireAttackAudio = _G.__fireAttackAudio or { ids = {} }",
    "local A = _G.__fireAttackAudio.ids",
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

function Audio.playId(v, name, vol, pitch, file)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)

  local cmd = string.format([[
    if not (_G.__fireAttackAudio and _G.__fireAttackAudio.ids) then return end
    local id = _G.__fireAttackAudio.ids[%q]
    if not id then return end
    if obj.playSFXSource then
      obj:playSFXSource(id)
    end
    if obj.setSFXSourceVolume then obj:setSFXSourceVolume(id, %f) end
    if obj.setSFXSourcePitch then obj:setSFXSourcePitch(id, %f) end
  ]], name, vol, pitch)

  v:queueLuaCommand(cmd)
end

function Audio.stopId(v, name)
  if not v or not v.queueLuaCommand then return end
  name = tostring(name)

  local cmd = string.format([[
    if not (_G.__fireAttackAudio and _G.__fireAttackAudio.ids) then return end
    local id = _G.__fireAttackAudio.ids[%q]
    if not id then return end
    if obj.stopSFXSource then
      obj:stopSFXSource(id)
    end
    if obj.setSFXSourceVolume then obj:setSFXSourceVolume(id, 0) end
  ]], name)

  v:queueLuaCommand(cmd)
end

-- ============================================
-- AI scripting helpers (runs inside vehicle)
-- ============================================
local function queueAI_FollowConservative(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[FireAttack AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[FireAttack AI] ai missing"); return end

    try('ai.setMode("follow")', function() ai.setMode("follow") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)

    try("ai.setMaxSpeedKph(60)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(60) end
    end)

    try("ai.setAggression(0.1)", function()
      if ai.setAggression then ai.setAggression(0.1) end
    end)

    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)

    try("ai.setRecoverOnCrash(false)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end
    end)

    print("[FireAttack AI] FOLLOW conservative. targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_ChaseAggressive(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[FireAttack AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[FireAttack AI] ai missing"); return end

    try('ai.setMode("chase")', function() ai.setMode("chase") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("limit")', function()
      if ai.setSpeedMode then ai.setSpeedMode("limit") end
    end)

    try("ai.setMaxSpeedKph(120)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(120) end
    end)

    try("ai.setAggression(0.7)", function()
      if ai.setAggression then ai.setAggression(0.7) end
    end)

    try("ai.setAvoidCars(false)", function()
      if ai.setAvoidCars then ai.setAvoidCars(false) end
    end)

    try('ai.driveInLane("off")', function()
      if ai.driveInLane then ai.driveInLane("off") end
    end)

    try("ai.setRecoverOnCrash(false)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end
    end)

    print("[FireAttack AI] CHASE aggressive. targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_Disable(veh)
  veh:queueLuaCommand([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[FireAttack AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end
    if not ai then print("[FireAttack AI] ai missing"); return end
    try('ai.setMode("disabled")', function() ai.setMode("disabled") end)
    try('ai.setMode("none")', function() ai.setMode("none") end)
    print("[FireAttack AI] AI disabled.")
  ]])
end

local function startFollowAI(id)
  local veh = getObjById(id)
  if not veh then
    log("ERROR: pigeon vehicle missing after spawn (id=" .. tostring(id) .. ")")
    return
  end

  local playerVeh = getPlayerVeh()
  local targetId = playerVeh and playerVeh.getID and playerVeh:getID() or nil
  if not targetId then
    log("WARN: no player vehicle id; AI target not set.")
    return
  end

  queueAI_FollowConservative(veh, targetId)
end

local function switchToChaseAI(id)
  local veh = getObjById(id)
  if not veh then
    log("ERROR: pigeon missing when switching to chase.")
    return
  end

  local playerVeh = getPlayerVeh()
  local targetId = playerVeh and playerVeh.getID and playerVeh:getID() or nil
  if not targetId then
    log("WARN: no player vehicle id; chase AI not set.")
    return
  end

  queueAI_ChaseAggressive(veh, targetId)
  R.phase = "chase"
  log("Fire attack AI: switched to CHASE.")
end

local function resetState(keepGui)
  local id = R.spawnedId
  R.active = false
  R.spawnedId = nil
  R.spawnPos = nil
  R.spawnMode = nil
  R.spawnMethod = nil
  R.phase = "idle"
  R.distToPlayer = nil
  R.igniteTriggered = false
  R.detonated = false
  R.detonateAt = nil
  R.disableApplied = false
  R.guiMessage = nil
  R.spawnClock = nil
  R.spawnSnapped = false

  if not keepGui then
    setGuiStatusMessage(nil)
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
end

local function tryIgnite(veh)
  local Mobs = nil
  if extensions and extensions.mobs then
    Mobs = extensions.mobs
  elseif package and package.searchpath then
    local path = package.searchpath("mobs", package.path)
    if path then
      Mobs = require("mobs")
    end
  end

  if Mobs and Mobs.igniteVehicle then
    pcall(function() Mobs.igniteVehicle(veh) end)
  end
end

local function tryDetonate(veh)
  local Mobs = nil
  if extensions and extensions.mobs then
    Mobs = extensions.mobs
  elseif package and package.searchpath then
    local path = package.searchpath("mobs", package.path)
    if path then
      Mobs = require("mobs")
    end
  end

  if Mobs and Mobs.detonateBomb then
    pcall(function() Mobs.detonateBomb(veh) end)
  end
end

-- =========================
-- Public API
-- =========================
function M.init(hostCfg, hostApi)
  CFG = hostCfg
  Host = hostApi
end

function M.isActive()
  return R.active == true
end

function M.status()
  return R.status
end

function M.triggerManual()
  if R.active then
    log("Already active.")
    return false
  end

  seedRandom()

  local pv = getPlayerVeh()
  if not pv then
    log("BLOCKED: no player vehicle.")
    return false
  end

  local useBack = math.random() < 0.5
  local spawnPos, spawnMode

  if useBack then
    spawnPos, spawnMode = getBackCrumbPos(300)
    if not spawnPos then
      spawnPos, spawnMode = chooseFkbPos(300, 10.0)
      if spawnPos then
        spawnMode = "forwardKnown300"
      end
    else
      spawnMode = "back300"
    end
  else
    spawnPos, spawnMode = chooseFkbPos(300, 10.0)
    if spawnPos then
      spawnMode = "forwardKnown300"
    else
      spawnPos, spawnMode = getBackCrumbPos(300)
      if spawnPos then
        spawnMode = "back300"
      end
    end
  end

  if not spawnPos then
    log("BLOCKED: no breadcrumb available for spawn.")
    return false
  end

  R.spawnPos = spawnPos + vec3(0, 0, 0.8)
  R.spawnMode = spawnMode
  R.spawnMethod = nil
  log("Spawn using " .. tostring(spawnMode))

  local tf = makeSpawnTransform(pv, R.spawnPos)
  local id = spawnVehicleAt(tf)
  if not id then return false end

  R.active = true
  R.spawnedId = id
  R.phase = "follow"
  R.distToPlayer = nil
  R.igniteTriggered = false
  R.detonated = false
  R.detonateAt = nil
  R.disableApplied = false
  R.guiMessage = "??????"
  setGuiStatusMessage(R.guiMessage)

  R.spawnClock = os.clock()
  R.spawnSnapped = false

  startFollowAI(id)

  if pv then
    Audio.ensureAll(pv)
    Audio.playId(pv, AUDIO.eventStartName, AUDIO.eventStartVol, AUDIO.eventStartPitch, AUDIO.eventStartFile)
  end

  return true
end

function M.endEvent(opts)
  if not R.active then return end
  opts = opts or {}

  local pv = getPlayerVeh()
  if pv then
    Audio.stopId(pv, AUDIO.eventStartName)
  end

  resetState(opts.keepGuiMessage)
  log("Ended.")
end

function M.update(dtSim)
  if not R.active then return end

  local attacker = getObjById(R.spawnedId)
  if not attacker then
    resetState(false)
    log("Ended (pigeon missing).")
    return
  end

  local pv = getPlayerVeh()
  if not pv then return end

  local rp = attacker:getPosition()
  local pp = pv:getPosition()
  if not (rp and pp) then return end

  local d = (rp - pp):length()
  R.distToPlayer = d

  local now = os.clock()

  -- Anti-teleport snapback (first 2 seconds after spawn)
  if R.spawnPos and R.spawnClock and (now - R.spawnClock) <= 2.0 and not R.spawnSnapped then
    local spawnDist = (rp - R.spawnPos):length()
    if spawnDist >= 50.0 then
      local ok = pcall(function()
        if attacker.setPositionRotation then
          attacker:setPositionRotation(R.spawnPos, quat(0, 0, 0, 1))
        elseif attacker.setPosition then
          attacker:setPosition(R.spawnPos)
        end
      end)
      R.spawnSnapped = true
      if ok then
        log("Fire attack: snapped back to spawn (anti-teleport).")
        startFollowAI(R.spawnedId)
      else
        log("ERROR: failed to snap pigeon back to spawn.")
      end
    end
  end

  if (not R.igniteTriggered) and d <= 100.0 then
    R.igniteTriggered = true
    R.detonateAt = now + 1.0
    R.guiMessage = "You smell something cooking"
    setGuiStatusMessage(R.guiMessage)
    tryIgnite(attacker)
    switchToChaseAI(R.spawnedId)
  end

  if R.igniteTriggered and (not R.detonated) and R.detonateAt and now >= R.detonateAt then
    R.detonated = true
    tryDetonate(attacker)
  end

  if (not R.disableApplied) and d <= 30.0 then
    R.disableApplied = true
    queueAI_Disable(attacker)
    R.phase = "disabled"
  end
end

return M
