-- lua/ge/extensions/events/RobberEscapePlanner.lua
-- Tactical escape planner for robber vehicles when heavy congestion persists.

local M = {}

local DEFAULTS = {
  enabled = true,
  evalHz = 4,
  commitMinTime = 1.6,
  cooldown = 3.0,
  laneWidth = 3.6,
  scanDist = 32,
  reverseDistance = 6.0,
  reverseMaxSpeedKph = 6,
  laneCommitSeconds = 2.2,
}

local cfg = {}
local nowClock = 0
local ctx = {}

local function shallowCopy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function mergeDefaults(user)
  cfg = shallowCopy(DEFAULTS)
  if type(user) ~= "table" then return end
  for k, v in pairs(user) do cfg[k] = v end
end

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
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

local function speedKph(veh)
  if not veh or not veh.getVelocity then return 0 end
  local v = safeCall(veh.getVelocity, veh)
  if not v then return 0 end
  return v:length() * 3.6
end

local function getTrafficState(id, trafficData)
  local row = trafficData and trafficData[id]
  if row and row.pos then
    return row.pos, row.vel or vec3(0, 0, 0)
  end
  local veh = getObjectByID and getObjectByID(id)
  if not veh then return nil, nil end
  local p = safePos(veh)
  local v = safeCall(veh.getVelocity, veh) or vec3(0, 0, 0)
  return p, v
end

local function sideOccupancy(pos, fwd, sideSign, trafficList, trafficData)
  local side = vec3(-fwd.y * sideSign, fwd.x * sideSign, 0)
  local laneCenterOffset = side * cfg.laneWidth
  local occ = 0
  for _, tid in ipairs(trafficList or {}) do
    local tPos = getTrafficState(tid, trafficData)
    if tPos then
      local rel = tPos - pos - laneCenterOffset
      local ahead = rel:dot(fwd)
      local lateral = math.abs(rel:dot(side))
      if ahead > -6 and ahead < cfg.scanDist and lateral < (cfg.laneWidth * 0.8) then
        occ = occ + clamp01((cfg.scanDist - ahead) / cfg.scanDist)
      end
    end
  end
  return occ
end

local function rearClear(pos, fwd, trafficList, trafficData)
  local nearest = math.huge
  for _, tid in ipairs(trafficList or {}) do
    local tPos = getTrafficState(tid, trafficData)
    if tPos then
      local rel = tPos - pos
      local behind = -rel:dot(fwd)
      if behind > 0 and behind < nearest then
        nearest = behind
      end
    end
  end
  return nearest == math.huge and 99 or nearest
end

local function applyLaneEscape(veh, targetId)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand(([[
    local tid = %d
    local function try(fn) pcall(fn) end
    if ai then
      try(function() ai.setMode('flee') end)
      try(function() if ai.setTargetObjectID then ai.setTargetObjectID(tid) end end)
      try(function() if ai.setSpeedMode then ai.setSpeedMode('legal') end end)
      try(function() if ai.setAggression then ai.setAggression(0.32) end end)
      try(function() if ai.setMaxSpeedKph then ai.setMaxSpeedKph(52) end end)
      try(function() if ai.setAllowLaneChanges then ai.setAllowLaneChanges(true) end end)
      try(function() if ai.driveInLane then ai.driveInLane('off') end end)
      try(function() if ai.setAvoidCars then ai.setAvoidCars(true) end end)
    end
  ]]):format(targetId or -1))
end

local function applyStabilize(veh, targetId)
  if not veh or not veh.queueLuaCommand then return end
  veh:queueLuaCommand(([[
    local tid = %d
    local function try(fn) pcall(fn) end
    if ai then
      try(function() ai.setMode('flee') end)
      try(function() if ai.setTargetObjectID then ai.setTargetObjectID(tid) end end)
      try(function() if ai.setSpeedMode then ai.setSpeedMode('legal') end end)
      try(function() if ai.setAggression then ai.setAggression(0.10) end end)
      try(function() if ai.setMaxSpeedKph then ai.setMaxSpeedKph(%0.1f) end end)
      try(function() if ai.setAllowLaneChanges then ai.setAllowLaneChanges(false) end end)
      try(function() if ai.driveInLane then ai.driveInLane('on') end end)
      try(function() if ai.setAvoidCars then ai.setAvoidCars(true) end end)
    end
  ]]):format(targetId or -1, cfg.reverseMaxSpeedKph))
end

local function tryReverseReposition(veh, fwd)
  if not veh or not fwd then return false end
  local pos = safePos(veh)
  if not pos then return false end
  local rot = safeCall(veh.getRotation, veh)
  if not rot then return false end
  local backPos = pos - (fwd * cfg.reverseDistance)

  if spawn and spawn.safeTeleport then
    local ok = pcall(spawn.safeTeleport, veh, backPos, rot)
    if ok then return true end
  end

  if map and map.safeTeleport and veh.getId then
    local id = veh:getId()
    local ok = pcall(map.safeTeleport, id, backPos.x, backPos.y, backPos.z, rot.x, rot.y, rot.z, rot.w, nil, nil, true, true, true)
    if ok then return true end
  end
  return false
end

local function setAiPathIfAvailable(veh, points)
  if type(points) ~= "table" or #points < 2 then return false end
  local helper = scenario and scenario.scenariohelper
  if not helper or type(helper.setAiPath) ~= "function" then return false end
  local vehName = safeCall(veh.getName, veh)
  if not vehName then return false end
  return pcall(helper.setAiPath, vehName, points)
end

local function chooseOption(r, pos, fwd, trafficList, trafficData)
  local leftOcc = sideOccupancy(pos, fwd, 1, trafficList, trafficData)
  local rightOcc = sideOccupancy(pos, fwd, -1, trafficList, trafficData)
  local holdCost = (r.lastSupervisor and (r.lastSupervisor.queueCount or 0) or 0) * 0.3 + 1.0
  local leftCost = leftOcc + 0.5
  local rightCost = rightOcc + 0.5

  local chosen = "HoldLane"
  local best = holdCost
  if leftCost < best then chosen, best = "LeftBypass", leftCost end
  if rightCost < best then chosen, best = "RightBypass", rightCost end

  local rear = rearClear(pos, fwd, trafficList, trafficData)
  local vKph = speedKph(getObjectByID(r.vehId))
  if best > 1.45 and rear > 10 and vKph < 10 then
    chosen = (leftOcc <= rightOcc) and "ReverseThenLeft" or "ReverseThenRight"
  end

  return chosen, {
    leftOccupancy = leftOcc,
    rightOccupancy = rightOcc,
    holdCost = holdCost,
    rearClearance = rear,
  }
end

local function markTelemetry(r)
  r.telemetry = {
    plannerState = r.state,
    selectedOption = r.option,
    reverseUsed = r.reverseUsed == true,
    laneCommitUntil = r.laneCommitUntil,
    cooldownUntil = r.cooldownUntil,
    score = r.score,
  }
end

function M.init(opts)
  mergeDefaults(opts)
end

function M.registerRobber(opts)
  if type(opts) ~= "table" or type(opts.vehId) ~= "number" then return false end
  ctx[opts.vehId] = {
    vehId = opts.vehId,
    targetId = opts.targetId,
    phase = opts.phase or "flee",
    state = "Idle",
    option = "None",
    active = true,
    nextEvalAt = 0,
    commitUntil = 0,
    cooldownUntil = 0,
    laneCommitUntil = 0,
    reverseUsed = false,
    score = {},
    lastSupervisor = nil,
    telemetry = nil,
  }
  return true
end

function M.unregisterRobber(vehId)
  ctx[vehId] = nil
  return true
end

function M.setPhase(vehId, phase)
  if not ctx[vehId] then return false end
  ctx[vehId].phase = phase or ctx[vehId].phase
  return true
end

function M.setTargetId(vehId, targetId)
  if not ctx[vehId] then return false end
  ctx[vehId].targetId = targetId
  return true
end

function M.onSupervisorFrame(vehId, card, veh, trafficList, trafficData)
  if cfg.enabled == false then return end
  local r = ctx[vehId]
  if not r then
    r = {
      vehId = vehId,
      targetId = card and card.targetId,
      phase = (card and card.phase) or "flee",
      state = "Idle",
      option = "None",
      active = true,
      nextEvalAt = 0,
      commitUntil = 0,
      cooldownUntil = 0,
      laneCommitUntil = 0,
      reverseUsed = false,
      score = {},
      lastSupervisor = nil,
      telemetry = nil,
    }
    ctx[vehId] = r
  end
  if not r.active or not veh then return end
  r.lastSupervisor = card or r.lastSupervisor
  if r.phase ~= "flee" then return end
  if nowClock < (r.nextEvalAt or 0) then return end
  r.nextEvalAt = nowClock + (1 / math.max(1, cfg.evalHz))

  local dir = safeDir(veh)
  local pos = safePos(veh)
  if not dir or not pos then return end
  local fwd = vec3(dir.x, dir.y, 0)
  if fwd:length() < 1e-6 then return end
  fwd:normalize()

  if nowClock < (r.cooldownUntil or 0) then
    r.state = "Idle"
    r.option = "Cooldown"
    markTelemetry(r)
    return
  end

  if r.laneCommitUntil and nowClock < r.laneCommitUntil then
    r.state = "LaneCommitWindow"
    applyLaneEscape(veh, r.targetId)
    markTelemetry(r)
    return
  end

  if card and card.rerouteSuggested == true then
    local option, score = chooseOption(r, pos, fwd, trafficList, trafficData)
    r.option = option
    r.score = score
    r.state = "CommitOption"

    if option == "ReverseThenLeft" or option == "ReverseThenRight" then
      applyStabilize(veh, r.targetId)
      r.reverseUsed = tryReverseReposition(veh, fwd)
      r.state = "ReverseWindow"
    end

    local waypoint = pos + (fwd * (cfg.scanDist * 0.8)) + vec3(-fwd.y, fwd.x, 0) * ((option == "LeftBypass" or option == "ReverseThenLeft") and cfg.laneWidth or (option == "RightBypass" or option == "ReverseThenRight") and -cfg.laneWidth or 0)
    setAiPathIfAvailable(veh, { pos, waypoint })
    applyLaneEscape(veh, r.targetId)
    r.laneCommitUntil = nowClock + cfg.laneCommitSeconds
    r.commitUntil = nowClock + cfg.commitMinTime
    r.cooldownUntil = nowClock + cfg.cooldown
    r.state = "RouteFollow"
  else
    r.state = "Idle"
    r.option = "None"
  end

  markTelemetry(r)
end

function M.getTelemetry(vehId)
  local r = ctx[vehId]
  return r and r.telemetry or nil
end

function M.getTelemetryCards()
  local out = {}
  for _, r in pairs(ctx) do
    if r.active and r.telemetry then
      out[#out + 1] = {
        robberId = r.vehId,
        escapePlanner = r.telemetry,
      }
    end
  end
  return out
end

function M.update(dt)
  nowClock = nowClock + (dt or 0)
end

function M.reset()
  ctx = {}
  nowClock = 0
end

return M
