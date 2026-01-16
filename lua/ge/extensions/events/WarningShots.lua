-- lua/ge/extensions/events/WarningShots.lua
-- WarningShots: spawn roamer at FKB 300m, tail player, fire warning shots, then flee.

local M = {}

local CFG = nil
local Host = nil

local R = {
  active = false,
  phase = "idle", -- spawn | follow | shoot | flee | done
  status = "",
  attackerId = nil,
  shotsTotal = 0,
  shotsFired = 0,
  nextShotTime = 0,
  didShatter = false,
  fleeStartTime = 0,
  elapsed = 0,
  maxDuration = 90,
  guiBaseMessage = nil,
  approachMessageShown = false,
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
    Host.postLine("WARNING_SHOTS", R.status)
  else
    print("[WarningShots] " .. tostring(R.status))
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
    return nil, "no breadcrumbs", nil
  end

  local cache = select(1, Host.Breadcrumbs.getForwardKnown())
  local e = cache and cache[spacing]
  if not e then return nil, "no entry", nil end

  if e.available and e.pos then
    return e.pos, "live", e
  end

  if e.lastGoodPos and e.lastGoodT then
    local age = (os.clock() - e.lastGoodT)
    if age <= maxAgeSec then
      return e.lastGoodPos, "cached", e
    end
    return nil, "cached too old", e
  end

  return nil, "not ready", e
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
        return id
      end
    end

    ok, res = pcall(function()
      return spawn.spawnVehicle(model, { pos = transform.pos, rot = transform.rot, config = config })
    end)
    if ok then
      local id = resolveVehicleId(res)
      if id then
        return id
      end
    end
  end

  log("ERROR: No supported vehicle spawner found OR spawner returned non-id.")
  return nil
end

local function queueAI_Follow(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[WarningShots AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[WarningShots AI] ai missing"); return end

    try('ai.setMode("follow")', function() ai.setMode("follow") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("limit")', function()
      if ai.setSpeedMode then ai.setSpeedMode("limit") end
    end)
    try("ai.setMaxSpeedKph(80)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(80) end
    end)

    try("ai.setAggression(0.8)", function()
      if ai.setAggression then ai.setAggression(0.8) end
    end)

    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)
    try('ai.driveInLane("on")', function()
      if ai.driveInLane then ai.driveInLane("on") end
    end)
    try("ai.setRecoverOnCrash(true)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(true) end
    end)

    print("[WarningShots AI] FOLLOW armed (max 80kph, aggr 0.8, avoidCars on, driveInLane on). targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueAI_Flee(veh, targetId)
  veh:queueLuaCommand(([[
    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[WarningShots AI] FAIL: "..desc.." :: "..tostring(err)) end
      return ok
    end

    local tid = %d
    if not ai then print("[WarningShots AI] ai missing"); return end

    try('ai.setMode("flee")', function() ai.setMode("flee") end)
    try("ai.setTargetObjectID(tid)", function()
      if ai.setTargetObjectID then ai.setTargetObjectID(tid) end
    end)

    try('ai.setSpeedMode("legal")', function()
      if ai.setSpeedMode then ai.setSpeedMode("legal") end
    end)
    try("ai.setMaxSpeedKph(110)", function()
      if ai.setMaxSpeedKph then ai.setMaxSpeedKph(110) end
    end)

    try("ai.setAggression(0.3)", function()
      if ai.setAggression then ai.setAggression(0.3) end
    end)

    try("ai.setAvoidCars(true)", function()
      if ai.setAvoidCars then ai.setAvoidCars(true) end
    end)
    try('ai.driveInLane("on")', function()
      if ai.driveInLane then ai.driveInLane("on") end
    end)
    try("ai.setRecoverOnCrash(true)", function()
      if ai.setRecoverOnCrash then ai.setRecoverOnCrash(true) end
    end)

    print("[WarningShots AI] FLEE armed (max 110kph, aggr 0.3, avoidCars on). targetId="..tostring(tid))
  ]]):format(targetId))
end

local function queueSmallImpulse(veh, strength)
  if not veh or not veh.queueLuaCommand then return end
  local cmd = string.format([[
    local mag = %0.3f
    local dir = vec3((math.random() - 0.5) * 0.4, (math.random() - 0.5) * 0.4, math.random() * 0.1)
    local impulse = dir * mag

    local function try(desc, fn)
      local ok, err = pcall(fn)
      if not ok then print("[WarningShots] impulse "..desc.." failed: "..tostring(err)) end
      return ok
    end

    if obj then
      if obj.applyImpulse then
        try("applyImpulse(pos, vec)", function() obj:applyImpulse(vec3(0, 0, 0), impulse) end)
        try("applyImpulse(vec)", function() obj:applyImpulse(impulse) end)
      end
      if obj.applyForce then
        try("applyForce(vec)", function() obj:applyForce(impulse) end)
      end
      if obj.applyTorque then
        try("applyTorque(vec)", function() obj:applyTorque(impulse * 0.1) end)
      end
    end
  ]], strength)

  veh:queueLuaCommand(cmd)
end

local function queueBreakRandomWindow(veh)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand([[
    local didBreak = false

    if beamstate and beamstate.getBreakGroupTable and beamstate.breakBreakGroup then
      local ok, groups = pcall(beamstate.getBreakGroupTable)
      if ok and type(groups) == "table" then
        local keys = {}
        for k, _ in pairs(groups) do
          keys[#keys + 1] = k
        end
        if #keys > 0 then
          local pick = keys[math.random(#keys)]
          pcall(function() beamstate.breakBreakGroup(pick) end)
          didBreak = true
        end
      end
    end

    if (not didBreak) and beamstate and beamstate.breakBreakGroup then
      pcall(function() beamstate.breakBreakGroup("glass") end)
      didBreak = true
    end

    if (not didBreak) and damageTracker and damageTracker.applyDamage then
      pcall(function() damageTracker.applyDamage({ beamDamage = 1200, partDamage = 0 }) end)
      didBreak = true
    end

    if (not didBreak) and obj and obj.applyImpulse then
      local dir = vec3((math.random() - 0.5) * 0.8, (math.random() - 0.5) * 0.8, math.random() * 0.2)
      local impulse = dir * 250
      pcall(function() obj:applyImpulse(vec3(0, 0, 0), impulse) end)
    end
  ]])
end

local function isSpawnAllowed(pos, entry, playerVeh)
  if not pos then return false, "no position" end
  if entry and entry.eligible == false then
    return false, "ineligible breadcrumb"
  end

  if playerVeh and playerVeh.getPosition then
    local playerPos = playerVeh:getPosition()
    if (pos - playerPos):length() < 50 then
      return false, "too close to player"
    end
  end

  return true, nil
end

local function resetState()
  R.active = false
  R.phase = "idle"
  R.status = ""
  R.attackerId = nil
  R.shotsTotal = 0
  R.shotsFired = 0
  R.nextShotTime = 0
  R.didShatter = false
  R.fleeStartTime = 0
  R.elapsed = 0
  R.guiBaseMessage = nil
  R.approachMessageShown = false
end

local function despawnAttacker()
  if type(R.attackerId) ~= "number" then return end
  local v = getObjById(R.attackerId)
  if v then
    if v.queueLuaCommand then
      pcall(function() v:queueLuaCommand("input.event('brake', 0, 1)") end)
    end
    pcall(function() v:delete() end)
  end
end

function M.init(cfg, host)
  CFG = cfg or CFG
  Host = host or Host
end

function M.start(host, cfg)
  if R.active then
    log("Already active.")
    return false
  end

  Host = host or Host
  CFG = cfg or CFG

  seedRandom()

  local playerVeh = getPlayerVeh()
  if not playerVeh then
    log("BLOCKED: no player vehicle.")
    setGuiStatusMessage("No player vehicle found.")
    return false
  end

  local fkbPos, mode, entry = chooseFkbPos(300, 10.0)
  if not fkbPos then
    log("BLOCKED: FKB 300m not available (" .. tostring(mode) .. ").")
    setGuiStatusMessage("No valid spawn point.")
    return false
  end

  local ok, reason = isSpawnAllowed(fkbPos, entry, playerVeh)
  if not ok then
    log("BLOCKED: spawn not safe (" .. tostring(reason) .. ").")
    setGuiStatusMessage("No valid spawn point.")
    return false
  end

  local spawnPos = fkbPos + vec3(0, 0, 0.8)
  local tf = makeSpawnTransform(playerVeh, spawnPos)
  local attackerId = spawnVehicleAt(tf)
  if not attackerId then
    setGuiStatusMessage("No valid spawn point.")
    return false
  end

  resetState()
  R.active = true
  R.attackerId = attackerId
  R.phase = "spawn"
  R.elapsed = 0
  R.guiBaseMessage = "Bolide spotted ahead…"
  setGuiStatusMessage(R.guiBaseMessage)

  local attackerVeh = getObjById(attackerId)
  if attackerVeh then
    queueAI_Follow(attackerVeh, playerVeh:getID())
  end

  log("Spawned warning shots attacker at FKB 300m (" .. tostring(mode) .. ").")
  return true
end

function M.stop(reason)
  if not R.active then return end
  local why = reason or "ended"

  despawnAttacker()
  resetState()
  if why == "attacker_missing" then
    setGuiStatusMessage("Attacker disabled.")
  elseif why == "player_missing" then
    setGuiStatusMessage("Player vehicle missing.")
  else
    setGuiStatusMessage("Warning shots event ended.")
  end
  log("Stopped (" .. tostring(why) .. ").")
end

local function transitionToShoot()
  R.phase = "shoot"
  R.shotsTotal = math.random(3, 5)
  R.shotsFired = 0
  R.nextShotTime = R.elapsed
  R.didShatter = false
  setGuiStatusMessage("Warning shots!")
  log("Warning shots triggered: total=" .. tostring(R.shotsTotal))
end

local function transitionToFlee(attackerVeh, playerVeh)
  R.phase = "flee"
  R.fleeStartTime = R.elapsed
  setGuiStatusMessage("Bolide fleeing…")
  log("Attacker fleeing.")
  if attackerVeh and playerVeh then
    queueAI_Flee(attackerVeh, playerVeh:getID())
  end
end

local function fireShot(playerVeh)
  queueSmallImpulse(playerVeh, 120)
  log("Shot fired (" .. tostring(R.shotsFired + 1) .. "/" .. tostring(R.shotsTotal) .. ").")

  if (not R.didShatter) and (math.random() < 0.45) then
    queueBreakRandomWindow(playerVeh)
    R.didShatter = true
    setGuiStatusMessage("Glass shattered!")
    log("Glass shatter triggered.")
  end
end

function M.update(dtSim)
  if not R.active then return end

  R.elapsed = R.elapsed + (dtSim or 0)
  if R.elapsed >= (R.maxDuration or 90) then
    log("Fail-safe timeout hit.")
    M.stop("timeout")
    return
  end

  local playerVeh = getPlayerVeh()
  if not playerVeh then
    log("Player vehicle missing.")
    M.stop("player_missing")
    return
  end

  local attackerVeh = getObjById(R.attackerId)
  if not attackerVeh then
    log("Attacker disabled or missing.")
    M.stop("attacker_missing")
    return
  end

  local dist = (attackerVeh:getPosition() - playerVeh:getPosition()):length()

  if R.phase == "spawn" then
    R.phase = "follow"
    R.guiBaseMessage = "Bolide is tailing you…"
    setGuiStatusMessage(R.guiBaseMessage)
    log("Follow phase started.")
  end

  if R.phase == "follow" then
    if (not R.approachMessageShown) and dist <= 200 then
      R.approachMessageShown = true
      setGuiStatusMessage("Bolide is closing in…")
      log("Approaching player.")
    end
    if dist <= 150 then
      transitionToShoot()
    end
    return
  end

  if R.phase == "shoot" then
    if R.shotsFired < R.shotsTotal and R.elapsed >= R.nextShotTime then
      fireShot(playerVeh)
      R.shotsFired = R.shotsFired + 1
      R.nextShotTime = R.elapsed + (0.25 + math.random() * 0.30)
    end

    if R.shotsFired >= R.shotsTotal then
      transitionToFlee(attackerVeh, playerVeh)
    end
    return
  end

  if R.phase == "flee" then
    if dist >= 1000 then
      log("Attacker reached safe distance.")
      M.stop("flee_complete")
      return
    end

    if (R.elapsed - R.fleeStartTime) >= 45 then
      log("Flee timeout reached.")
      M.stop("flee_timeout")
      return
    end
  end
end

function M.status()
  if not R.active then return "idle" end
  return string.format("%s (%s)", tostring(R.phase), R.status or "")
end

function M.isActive()
  return R.active == true
end

return M
