-- lua/ge/extensions/events/RobberFleeSupervisor.lua
-- Supervisory robber flee-phase driving risk manager for congestion + terrain/corner hazards.
--
-- Design ref: docs/RobberFleeSupervisor.md
-- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt (getObjectByID, gameplay_traffic.getTrafficList/getTrafficData, bolidesTheCut.setNewHudState)

local M = {}

local DEFAULTS = {
  enabled = true,
  evalHz = 8,               -- supervisor evaluation frequency per robber
  hudHz = 5,                -- telemetry card refresh frequency
  corridorBase = 55,        -- meters
  corridorSpeedGain = 0.7,  -- meters per kph
  corridorMax = 120,
  corridorHalfWidth = 4.2,

  moderateEnter = 0.42,
  moderateExit = 0.32,
  heavyEnter = 0.70,
  heavyExit = 0.56,
  emergencyEnter = 0.90,
  emergencyExit = 0.78,

  minStateDwell = 0.75,
  smoothingAlpha = 0.35,

  rerouteHeavyMinTime = 2.5,
  rerouteCooldown = 3.0,

  freeflow = { maxSpeedKph = 75, aggression = 0.28, allowLaneChanges = true, driveInLane = "off" },
  moderate = { maxSpeedKph = 62, aggression = 0.20, allowLaneChanges = true, driveInLane = "off" },
  heavy = { maxSpeedKph = 45, aggression = 0.12, allowLaneChanges = false, driveInLane = "on" },
  emergency = { maxSpeedKph = 30, aggression = 0.05, allowLaneChanges = false, driveInLane = "on" },
}

local cfg = {}
local robbers = {}
local nowClock = 0
local nextHudAt = 0
local hostHudEmitter = nil
local escapePlanner = nil
local trafficReduction = {
  baselineAmount = nil,
  applied = false,
}

local function shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function mergeDefaults(user)
  cfg = shallowCopy(DEFAULTS)
  if type(user) ~= "table" then return end
  for k, v in pairs(user) do
    if type(v) == "table" and type(cfg[k]) == "table" then
      local c = shallowCopy(cfg[k])
      for k2, v2 in pairs(v) do c[k2] = v2 end
      cfg[k] = c
    else
      cfg[k] = v
    end
  end
end

local function safeGetObjById(id)
  if type(id) ~= "number" then return nil end
  -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt (getObjectByID)
  if getObjectByID then return getObjectByID(id) end
  if be and be.getObjectByID then return be:getObjectByID(id) end
  return nil
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  return ok and v or nil
end

local function safePos(veh)
  if not veh then return nil end
  if veh.getPosition then
    local p = safeCall(veh.getPosition, veh)
    if p then return p end
  end
  if veh.getPositionXYZ then
    local x, y, z = safeCall(veh.getPositionXYZ, veh)
    if type(x) == "number" and type(y) == "number" and type(z) == "number" then
      return vec3(x, y, z)
    end
  end
  return nil
end

local function safeDir(veh)
  if not veh or not veh.getDirectionVector then return nil end
  return safeCall(veh.getDirectionVector, veh)
end

local function safeVel(veh)
  if not veh then return nil end
  if veh.getVelocity then
    local v = safeCall(veh.getVelocity, veh)
    if v then return v end
  end
  return vec3(0, 0, 0)
end

local function speedKph(veh)
  local v = safeVel(veh)
  if not v then return 0 end
  local mps = v:length()
  return mps * 3.6
end

local function yawRateDegPerSec(prevDir, curDir, dt)
  if not prevDir or not curDir or not dt or dt <= 0 then return 0 end
  local a = vec3(prevDir.x, prevDir.y, 0)
  local b = vec3(curDir.x, curDir.y, 0)
  if a:length() < 1e-6 or b:length() < 1e-6 then return 0 end
  a:normalize()
  b:normalize()
  local dot = math.max(-1, math.min(1, a:dot(b)))
  local ang = math.deg(math.acos(dot))
  return ang / dt
end

local function resolveTrafficSnapshot()
  local trafficList = {}
  local trafficData = {}

  -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt (gameplay_traffic.getTrafficList/getTrafficData)
  if gameplay_traffic and gameplay_traffic.getTrafficList then
    local list = safeCall(gameplay_traffic.getTrafficList)
    if type(list) == "table" then trafficList = list end
  end
  if gameplay_traffic and gameplay_traffic.getTrafficData then
    local data = safeCall(gameplay_traffic.getTrafficData)
    if type(data) == "table" then trafficData = data end
  end

  return trafficList, trafficData
end

local function getActiveRobberCount()
  local count = 0
  for _, r in pairs(robbers) do
    if r and r.active then
      count = count + 1
    end
  end
  return count
end

local function getTrafficAmountSafe()
  if not gameplay_traffic then return nil end

  if gameplay_traffic.getTrafficAmount then
    local v = safeCall(gameplay_traffic.getTrafficAmount)
    if type(v) == "number" then return v end
  end

  if gameplay_traffic.getNumOfTraffic then
    local v = safeCall(gameplay_traffic.getNumOfTraffic)
    if type(v) == "number" then return v end
  end

  return nil
end

local function setActiveTrafficAmountSafe(amount)
  if not gameplay_traffic or not gameplay_traffic.setActiveAmount then return false end
  if type(amount) ~= "number" then return false end
  local whole = math.max(0, math.floor(amount + 0.5))
  local ok = safeCall(gameplay_traffic.setActiveAmount, whole)
  return ok ~= nil
end

local function applyTrafficReductionIfNeeded()
  if trafficReduction.applied then return end

  local baseline = getTrafficAmountSafe()
  if type(baseline) ~= "number" then return end

  local baselineWhole = math.max(0, math.floor(baseline + 0.5))
  local reduced = math.max(0, math.ceil(baselineWhole * 0.5))
  if setActiveTrafficAmountSafe(reduced) then
    trafficReduction.baselineAmount = baselineWhole
    trafficReduction.applied = true
  end
end

local function restoreTrafficIfNeeded()
  if not trafficReduction.applied then return end
  if getActiveRobberCount() > 0 then return end

  if type(trafficReduction.baselineAmount) == "number" then
    setActiveTrafficAmountSafe(trafficReduction.baselineAmount)
  end

  trafficReduction.baselineAmount = nil
  trafficReduction.applied = false
end

local function getTrafficVehicleState(id, trafficData)
  if type(id) ~= "number" then return nil, nil end
  local pos, vel
  local row = trafficData and trafficData[id]
  if row then
    if row.pos then pos = row.pos end
    if row.vel then vel = row.vel end
  end

  if not pos or not vel then
    local veh = safeGetObjById(id)
    if veh then
      pos = pos or safePos(veh)
      vel = vel or safeVel(veh)
    end
  end

  return pos, vel
end

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function smoothScore(prev, cur)
  if not prev then return cur end
  return (prev * (1 - cfg.smoothingAlpha)) + (cur * cfg.smoothingAlpha)
end

local function weightedRisk(obs)
  local queueNorm = clamp01((obs.queueCount or 0) / 5)
  local closeNorm = clamp01(((obs.closingKph or 0) / 80))
  local nearNorm = 1 - clamp01(((obs.nearestLeadDist or 200) / 40))
  local lanePenalty = clamp01(obs.laneBlockedPenalty or 0)

  local pitchNorm = clamp01(math.abs(obs.pitchDeg or 0) / 15)
  local cornerNorm = clamp01((obs.yawRateDegPerSec or 0) / 35)
  local comboNorm = clamp01((pitchNorm * 0.55) + (cornerNorm * 0.45))

  local congestion = (queueNorm * 0.40) + (closeNorm * 0.25) + (nearNorm * 0.25) + (lanePenalty * 0.10)
  local terrain = comboNorm

  local final = clamp01((congestion * 0.70) + (terrain * 0.30))
  return final, congestion, terrain
end

local function shouldReroute(r)
  if r.state ~= "HeavyRisk" and r.state ~= "EmergencyAvoid" then return false end
  if (nowClock - (r.heavyStartedAt or nowClock)) < cfg.rerouteHeavyMinTime then return false end
  if nowClock < (r.nextRerouteAllowedAt or 0) then return false end
  if (r.obs.queueCount or 0) < 3 then return false end
  r.nextRerouteAllowedAt = nowClock + cfg.rerouteCooldown
  return true
end

local function chooseState(risk, curState, since)
  local dwell = nowClock - (since or nowClock)

  if curState == "EmergencyAvoid" then
    if risk <= cfg.emergencyExit and dwell >= cfg.minStateDwell then
      return "HeavyRisk"
    end
    return curState
  end

  if curState == "HeavyRisk" then
    if risk >= cfg.emergencyEnter and dwell >= cfg.minStateDwell then
      return "EmergencyAvoid"
    end
    if risk <= cfg.heavyExit and dwell >= cfg.minStateDwell then
      return "ModerateRisk"
    end
    return curState
  end

  if curState == "ModerateRisk" then
    if risk >= cfg.emergencyEnter and dwell >= cfg.minStateDwell then
      return "EmergencyAvoid"
    end
    if risk >= cfg.heavyEnter and dwell >= cfg.minStateDwell then
      return "HeavyRisk"
    end
    if risk <= cfg.moderateExit and dwell >= cfg.minStateDwell then
      return "FreeFlow"
    end
    return curState
  end

  if risk >= cfg.emergencyEnter then return "EmergencyAvoid" end
  if risk >= cfg.heavyEnter then return "HeavyRisk" end
  if risk >= cfg.moderateEnter then return "ModerateRisk" end
  return "FreeFlow"
end

local function profileForState(state)
  if state == "EmergencyAvoid" then return cfg.emergency end
  if state == "HeavyRisk" then return cfg.heavy end
  if state == "ModerateRisk" then return cfg.moderate end
  return cfg.freeflow
end

local function queueProfile(veh, targetId, profile)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand(([[]
    local function try(_, fn)
      local ok = pcall(fn)
      return ok
    end
    local tid = %d
    local mode = %q
    if ai then
      try('mode', function() ai.setMode('flee') end)
      try('target', function() if ai.setTargetObjectID then ai.setTargetObjectID(tid) end end)
      try('speedMode', function() if ai.setSpeedMode then ai.setSpeedMode('legal') end end)
      try('avoidCars', function() if ai.setAvoidCars then ai.setAvoidCars(true) end end)
      try('avoidCrash', function() if ai.setAvoidCrash then ai.setAvoidCrash(true) end end)
      try('recover', function() if ai.setRecoverOnCrash then ai.setRecoverOnCrash(false) end end)

      if mode == 'EmergencyAvoid' then
        try('speed', function() if ai.setMaxSpeedKph then ai.setMaxSpeedKph(%0.1f) end end)
        try('agg', function() if ai.setAggression then ai.setAggression(%0.2f) end end)
        try('laneChange', function() if ai.setAllowLaneChanges then ai.setAllowLaneChanges(%s) end end)
        try('lane', function() if ai.driveInLane then ai.driveInLane(%q) end end)
      elseif mode == 'HeavyRisk' then
        try('speed', function() if ai.setMaxSpeedKph then ai.setMaxSpeedKph(%0.1f) end end)
        try('agg', function() if ai.setAggression then ai.setAggression(%0.2f) end end)
        try('laneChange', function() if ai.setAllowLaneChanges then ai.setAllowLaneChanges(%s) end end)
        try('lane', function() if ai.driveInLane then ai.driveInLane(%q) end end)
      elseif mode == 'ModerateRisk' then
        try('speed', function() if ai.setMaxSpeedKph then ai.setMaxSpeedKph(%0.1f) end end)
        try('agg', function() if ai.setAggression then ai.setAggression(%0.2f) end end)
        try('laneChange', function() if ai.setAllowLaneChanges then ai.setAllowLaneChanges(%s) end end)
        try('lane', function() if ai.driveInLane then ai.driveInLane(%q) end end)
      else
        try('speed', function() if ai.setMaxSpeedKph then ai.setMaxSpeedKph(%0.1f) end end)
        try('agg', function() if ai.setAggression then ai.setAggression(%0.2f) end end)
        try('laneChange', function() if ai.setAllowLaneChanges then ai.setAllowLaneChanges(%s) end end)
        try('lane', function() if ai.driveInLane then ai.driveInLane(%q) end end)
      end
    end
  ]]):format(
    targetId or -1,
    profile.state,
    cfg.emergency.maxSpeedKph, cfg.emergency.aggression, tostring(cfg.emergency.allowLaneChanges), cfg.emergency.driveInLane,
    cfg.heavy.maxSpeedKph, cfg.heavy.aggression, tostring(cfg.heavy.allowLaneChanges), cfg.heavy.driveInLane,
    cfg.moderate.maxSpeedKph, cfg.moderate.aggression, tostring(cfg.moderate.allowLaneChanges), cfg.moderate.driveInLane,
    cfg.freeflow.maxSpeedKph, cfg.freeflow.aggression, tostring(cfg.freeflow.allowLaneChanges), cfg.freeflow.driveInLane
  ))
end

local function buildTelemetryCard(r)
  local o = r.obs or {}
  return {
    robberId = r.vehId,
    eventName = r.eventName,
    phase = r.phase,
    state = r.state,
    risk = r.riskScore,
    congestion = r.congestionScore,
    terrain = r.terrainScore,
    leadDistance = o.nearestLeadDist,
    relativeSpeedKph = o.closingKph,
    queueCount = o.queueCount,
    rerouteSuggested = r.rerouteSuggested == true,
  }
end

local function emitHudCards()
  local cards = {}
  for _, r in pairs(robbers) do
    if r.active then
      cards[#cards + 1] = buildTelemetryCard(r)
    end
  end
  table.sort(cards, function(a, b) return (a.startedAt or 0) < (b.startedAt or 0) end)

  local payload = {
    robberTelemetryCards = cards,
  }

  if hostHudEmitter then
    pcall(hostHudEmitter, payload)
    return
  end

  -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt (bolidesTheCut.setNewHudState)
  if extensions and extensions.bolidesTheCut and extensions.bolidesTheCut.setNewHudState then
    pcall(function() extensions.bolidesTheCut.setNewHudState(payload) end)
  end
end

local function evaluateRobber(r, dt, trafficList, trafficData)
  if not r.active then return end
  if nowClock < (r.nextEvalAt or 0) then return end

  local veh = safeGetObjById(r.vehId)
  if not veh then
    r.active = false
    return
  end

  local pos = safePos(veh)
  local dir = safeDir(veh)
  local vel = safeVel(veh)
  if not pos or not dir or not vel then return end

  local fwd = vec3(dir.x, dir.y, 0)
  if fwd:length() < 1e-6 then fwd = vec3(0, 1, 0) else fwd:normalize() end

  local corridorDist = math.min(cfg.corridorMax, cfg.corridorBase + (speedKph(veh) * cfg.corridorSpeedGain))
  local nearestLeadDist = math.huge
  local queueCount = 0
  local slowCount = 0
  local closingKph = 0

  local myForwardMps = vel:dot(fwd)

  for _, tid in ipairs(trafficList) do
    if tid ~= r.vehId then
      local tPos, tVel = getTrafficVehicleState(tid, trafficData)
      if tPos then
        local rel = tPos - pos
        local ahead = rel:dot(fwd)
        if ahead > 0 and ahead <= corridorDist then
          local lateral = math.abs((rel.x * fwd.y) - (rel.y * fwd.x))
          if lateral <= cfg.corridorHalfWidth then
            queueCount = queueCount + 1
            if ahead < nearestLeadDist then
              nearestLeadDist = ahead
              local tv = tVel or vec3(0, 0, 0)
              local leadForwardMps = tv:dot(fwd)
              local closingMps = math.max(0, myForwardMps - leadForwardMps)
              closingKph = closingMps * 3.6
            end
            if (tVel and tVel:length() or 0) < 3.0 then
              slowCount = slowCount + 1
            end
          end
        end
      end
    end
  end

  if nearestLeadDist == math.huge then nearestLeadDist = nil end

  local pitchDeg = 0
  if dir.z then
    local clampedZ = math.max(-1, math.min(1, dir.z))
    pitchDeg = math.deg(math.asin(clampedZ))
  end

  local yawRate = yawRateDegPerSec(r.prevDir, dir, math.max(1e-4, dt or 0.125))
  r.prevDir = vec3(dir.x, dir.y, dir.z)

  local laneBlockedPenalty = 0
  if queueCount >= 3 then laneBlockedPenalty = 0.6 end
  if slowCount >= 2 then laneBlockedPenalty = math.min(1, laneBlockedPenalty + 0.2) end

  local obs = {
    queueCount = queueCount,
    slowCount = slowCount,
    nearestLeadDist = nearestLeadDist,
    closingKph = closingKph,
    laneBlockedPenalty = laneBlockedPenalty,
    pitchDeg = pitchDeg,
    yawRateDegPerSec = yawRate,
  }

  local riskRaw, congestionRaw, terrainRaw = weightedRisk(obs)
  r.riskScore = smoothScore(r.riskScore, riskRaw)
  r.congestionScore = smoothScore(r.congestionScore, congestionRaw)
  r.terrainScore = smoothScore(r.terrainScore, terrainRaw)
  r.obs = obs

  local nextState = chooseState(r.riskScore, r.state, r.stateSince)
  if nextState ~= r.state then
    r.state = nextState
    r.stateSince = nowClock
    if nextState == "HeavyRisk" or nextState == "EmergencyAvoid" then
      r.heavyStartedAt = nowClock
    end
  end

  if r.phase == "flee" then
    local profile = profileForState(r.state)
    local profileKey = string.format("%s_%s_%s_%s", r.state, tostring(profile.maxSpeedKph), tostring(profile.aggression), profile.driveInLane)
    if profileKey ~= r.profileKey then
      queueProfile(veh, r.targetId, { state = r.state })
      r.profileKey = profileKey
    end
  else
    r.profileKey = nil
  end

  r.rerouteSuggested = shouldReroute(r)

  if escapePlanner and escapePlanner.onSupervisorFrame then
    local card = buildTelemetryCard(r)
    pcall(function() escapePlanner.onSupervisorFrame(r.vehId, card, veh, trafficList, trafficData) end)
  end

  r.lastEvalAt = nowClock
  r.nextEvalAt = nowClock + (1 / math.max(1, cfg.evalHz))
end

function M.init(options)
  mergeDefaults(options)
  return true
end

function M.setHudEmitter(fn)
  hostHudEmitter = type(fn) == "function" and fn or nil
end

function M.setEscapePlanner(planner)
  escapePlanner = planner
end

function M.registerRobber(opts)
  if type(opts) ~= "table" or type(opts.vehId) ~= "number" then
    return false, "invalid opts/vehId"
  end

  local id = opts.vehId
  robbers[id] = robbers[id] or {}
  local r = robbers[id]
  r.vehId = id
  r.eventName = opts.eventName or "Robber"
  r.phase = opts.phase or "flee"
  r.targetId = opts.targetId
  r.active = true
  r.startedAt = nowClock
  r.state = "FreeFlow"
  r.stateSince = nowClock
  r.heavyStartedAt = nowClock
  r.nextEvalAt = 0
  r.lastEvalAt = nil
  r.nextRerouteAllowedAt = 0
  r.riskScore = 0
  r.congestionScore = 0
  r.terrainScore = 0
  r.obs = {}
  r.profileKey = nil
  r.rerouteSuggested = false
  r.prevDir = nil

  applyTrafficReductionIfNeeded()

  return true
end

function M.unregisterRobber(vehId)
  if type(vehId) ~= "number" then return false end
  robbers[vehId] = nil
  restoreTrafficIfNeeded()
  return true
end

function M.setPhase(vehId, phase)
  local r = robbers[vehId]
  if not r then return false end
  r.phase = phase or r.phase
  return true
end

function M.setTargetId(vehId, targetId)
  local r = robbers[vehId]
  if not r then return false end
  r.targetId = targetId
  return true
end

function M.getTelemetry(vehId)
  local r = robbers[vehId]
  if not r then return nil end
  return buildTelemetryCard(r)
end

function M.getTelemetryCards()
  local cards = {}
  for _, r in pairs(robbers) do
    if r.active then
      cards[#cards + 1] = buildTelemetryCard(r)
    end
  end
  return cards
end

function M.reset()
  if trafficReduction.applied and type(trafficReduction.baselineAmount) == "number" then
    setActiveTrafficAmountSafe(trafficReduction.baselineAmount)
  end
  trafficReduction.baselineAmount = nil
  trafficReduction.applied = false

  robbers = {}
  nowClock = 0
  nextHudAt = 0
end

function M.update(dtSim)
  if cfg.enabled == false then return end
  nowClock = nowClock + (dtSim or 0)

  local trafficList, trafficData = resolveTrafficSnapshot()
  for _, r in pairs(robbers) do
    if r.active then
      evaluateRobber(r, dtSim, trafficList, trafficData)
    end
  end

  if nowClock >= nextHudAt then
    emitHudCards()
    nextHudAt = nowClock + (1 / math.max(1, cfg.hudHz))
  end
end

return M
