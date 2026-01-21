-- lua/ge/extensions/bolidesGangsterChase.lua
-- Bolides (cartel) ambush + flee system (Wallet-only, Career-safe)
-- States: IDLE -> PREWARN (30s warning) -> AMBUSH (armed; spawn when player is slow) -> FLEE -> (RECOVERED/FAILED) -> IDLE
--
-- CLEAN UI PASS:
--  - NO bottom-left ui_message HUD app
--  - NO top-left ui_message popups
--  - Everything shown only in the ImGui drawUI window
--
-- Existing features preserved:
--  - NO RAYCASTS
--  - Supports player on foot via player anchor (vehicle preferred, camera fallback)
--  - Random earnings trigger each cycle: $500 / $1000 / $3000 / $5000
--  - Money restored/bonus is NOT counted as "earnings since last robbery"
--  - driveInLane("off") for robber flee AI
--
-- Forward-distance breadcrumb tracking (spawn failsafe):
--  - Track forward-only travel distance breadcrumbs
--  - Spawn uses your own proven-safe road history crumbs
--  - Spawn sequence cannot start until:
--      (1) player travelled >= 300m forward AND
--      (2) BOTH 10m-back and 300m-back crumbs exist/valid
--      (1) player travelled >= 100m forward AND
--      (2) BOTH 10m-back and 100m-back crumbs exist/valid
--  - Tracks 200m-back crumb for future spawn options
--  - Tracks 300m-back crumb for future spawn options
--
-- Mob system:
--  - All mobs spawn under same earnings trigger
--  - Random mob pick each cycle; never same as last (if possible)
--  - Includes IntimidatorTruck (T-Series w/ plow)
--      * Spawns at 200m breadcrumb
--      * Chase AI, max speed 80 km/h
--      * Always tries to stay ~80m away from player
--      * No stealing (intimidation chase only)
--  - Includes bomb_car (beaten up bomb car)
--      * Spawns at 100m breadcrumb
--      * Chase AI, max speed 50 km/h
--      * Detonates + ignites at 30m
--
-- CHANGE REQUEST (Rowan):
--  - Remove ALL player handbrake forcing. (No handbrake references anywhere.)
--  - Add BolidesIntroWav.wav and play it ONCE when About/Info button is opened.
--  - If Hide Info is pressed, BolidesIntroWav must STOP.

local M = {}

log("I", "BOLIDES", "Bolides extension loaded (Clean UI pass + mobs + unified audio)")

M.showWindow = true

local Mobs = require("mobs")

-- =========================
-- Config
-- =========================
local CFG = {
  cartelName = "Bolide",

  spawnLift = 1.0, -- no raycast to ground
  spawnOnlyIfPlayerUnderKph = 5.0,

  stealDelaySec     = 0.5,
  fleeStartDelaySec = 8.0,

  getawayDistMeters = 1000.0,
  intimidatorGetawayDistMeters = 500.0,
  intimidatorCatchDistMeters = 8.0,

  disableDistMeters   = 8.0,
  disableHoldSec      = 5.0,
  playerStopSpeed     = 1.2, -- m/s
  robberDisableSpeed  = 1.0, -- m/s

  fleeAggression  = 0.35,
  fleeSpeedMode   = "legal",

  fleeReissueEverySec = 2.0,
  fleeStuckSpeed      = 2.0,
  fleeStuckGraceSec   = 1.2,

  robberyPercent = 0.50,

  autoRobberyEnabled = true,
  autoRobberyWarningSec = 30.0,
  autoRobberyThresholdOptions = { 500, 1000, 3000, 5000 },
  autoRobberyWealthThreshold = 5000,
  forwardKnownCheckIntervalSec = 0.35,
  forwardKnownMinAheadMeters = 150.0,
  forwardKnownMaxAheadMeters = 800.0,
  forwardKnownApproachRadiusMeters = 45.0,
  forwardKnownTriggerSpacingMeters = 200.0,
  forwardKnownMinMinutesSinceEvent = 3.0,
  debugBreadcrumbMarkers = false,

  eligibilityTickSec = 0.5,
  cooldownSec = 90.0,
  heatPerSec = (1 / 240),
  heatAfterTrigger = 0.0,
  heatGateThreshold = 0.35,

  moneyWeight = 0.60,
  forwardWeight = 0.30,
  backWeight = 0.10,
  opportunityGateThreshold = 0.45,
  opportunitySmoothFactor = 0.15,
  opportunityForwardSpacingMeters = 200.0,
  opportunityForwardMinAheadMeters = 150.0,
  opportunityForwardMaxAheadMeters = 800.0,
  opportunityBackMeters = 200.0,

  manualExpireSec = 180.0,

  bombCarPostIgnitionLingerSec = 120.0,

  -- UI:
  showImGuiWindow = true,     -- ONLY UI we use
  showUiMessages = false,     -- keep false
  hudRefreshSec = 0.25,
  audioEnabled = true,

  -- Intro hit for About/Info button
  sfxBolidesIntroFile = "/art/sound/bolides/BolidesIntroWav.wav",
  sfxBolidesIntroName = "bolidesIntroHit",
  bolidesIntroVol = 4.0,
  bolidesIntroPitch = 1.0,
}

-- Bonus reward for catching the robber
CFG.recoveryBonusAmounts = { 20, 500, 1000, 1500, 5000 }

-- =========================================================
-- RLS AUDIO UTILITY (vehicle-side, version-tolerant)
-- =========================================================
local Audio = {}

-- Ensure audio sources exist on a vehicle
function Audio.ensureSources(v, sources)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__bolidesAudio = _G.__bolidesAudio or { ids = {} }",
    "local A = _G.__bolidesAudio.ids",
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

  local cmd = table.concat(lines, "\n")
  v:queueLuaCommand(cmd)
end

function Audio.ensureIntro(v)
  Audio.ensureSources(v, {
    { file = CFG.sfxBolidesIntroFile, name = CFG.sfxBolidesIntroName }
  })
end

-- Play a controllable (stoppable) sound by SOURCE ID
function Audio.playId(v, name, vol, pitch)
  if not CFG.audioEnabled then return end
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)

  local cmd = string.format([[
    if not (_G.__bolidesAudio and _G.__bolidesAudio.ids) then return end
    local id = _G.__bolidesAudio.ids[%q]
    if not id then return end

    -- Ensure audible baseline (some builds create sources muted)
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

    -- Guaranteed fallback (not stoppable, but always audible)
    if (not played) and obj.playSFXOnce then
      pcall(function() obj:playSFXOnce(%q, 0, %0.3f, %0.3f) end)
    end
  ]], name, vol, pitch, vol, pitch, vol, pitch, name, vol, pitch)

  v:queueLuaCommand(cmd)
end

-- Stop a sound reliably (mute-first strategy)
function Audio.stopId(v, name)
  if not v or not v.queueLuaCommand then return end
  name = tostring(name)

  local cmd = string.format([[
    if not (_G.__bolidesAudio and _G.__bolidesAudio.ids) then return end
    local id = _G.__bolidesAudio.ids[%q]
    if not id then return end

    if obj then
      if obj.stopSFX then pcall(function() obj:stopSFX(id) end) end
      if obj.stopSFXSource then pcall(function() obj:stopSFXSource(id) end) end
      if obj.stop then pcall(function() obj:stop(id) end) end
    end

    -- Mute ALWAYS works
    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 0.0) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, 0.0) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, 0.0) end) end
  ]], name)

  v:queueLuaCommand(cmd)
end

-- Set volume for an existing sound id (for fade/ramping)
function Audio.setVol(v, name, vol)
  if not v or not v.queueLuaCommand then return end
  name = tostring(name)
  vol = tonumber(vol) or 0

  local cmd = string.format([[
    if not (_G.__bolidesAudio and _G.__bolidesAudio.ids) then return end
    local id = _G.__bolidesAudio.ids[%q]
    if not id then return end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, %0.3f) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, %0.3f) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, %0.3f) end) end
  ]], name, vol, vol, vol)

  v:queueLuaCommand(cmd)
end

-- =========================
-- Built-in BeamNG UI sounds
-- =========================
local SFX = {
  start       = "event:/ui/main_menu/confirm",
  armed       = "event:/ui/modules/apps/notification",
  moneyTaken  = "event:/ui/modules/apps/error",
  chaseGo     = "event:/ui/modules/apps/mission_start",
  recovered   = "event:/ui/modules/apps/achievement",
  failed      = "event:/ui/modules/apps/mission_fail",
  cancel      = "event:/ui/main_menu/back",
}

local function playCue(key)
  if not CFG.audioEnabled then return end
  local ev = SFX[key]
  if not ev then return end
  pcall(function()
    if Engine and Engine.Audio and Engine.Audio.playOnce then
      Engine.Audio.playOnce("AudioGui", ev)
    end
  end)
end

-- =========================
-- State machine
-- =========================
local STATE = {
  IDLE      = "IDLE",
  PREWARN   = "PREWARN",
  AMBUSH    = "AMBUSH",
  FLEE      = "FLEE",
  RECOVERED = "RECOVERED",
  FAILED    = "FAILED"
}

-- =========================
-- Runtime state
-- =========================
local CTX = { S = {}, CFG = CFG, STATE = STATE }

local function initState(ctx)
  ctx.S = {
    state = STATE.IDLE,
    playerVeh = nil,
    robberVeh = nil,
    trafficFirePending = false,
    trafficFireTimer = 0,
    trafficFireVehId = nil,
    tState = 0,
    prewarnTimer = 0,
    simTime = 0.0,
    lastEventTime = -math.huge,
    lastEventTimeSec = -math.huge,
    heat = 0.0,
    cooldownUntilSec = 0.0,
    eligibilityTimer = 0.0,
    opportunitySmoothed = 0.0,
    manualRequest = {
      eventKey = nil,
      requestedAtSec = 0,
      statusMsg = "",
      required = "",
      pending = false,
      lastStatusMsg = ""
    },
    lastMobKey = nil,
    forcedNextMobKey = nil,
    activeMobKey = nil,
    activeMobDef = nil,
    earningsSinceRobbery = 0,
    lastMoneySample = nil,
    ignorePositiveCredit = 0,
    currentEarningsTarget = nil,
    tArmCountdown = 0,
    ambushArmed = false,
    spawnSequenceStarted = false,
    spawnSeqTimer = 0,
    spawnCommitted = false,
    footstepsPlayed = false,
    tSteal = 0,
    didSteal = false,
    tFleeStart = 0,
    didStartFlee = false,
    tDisableHold = 0,
    lastDist = nil,
    bombTriggered = false,
    intimidatorCaught = false,
    tFleeReissue = 0,
    tRobberSlow = 0,
    limoPhase = nil,
    limoPhaseTimer = 0,
    bombPhase = nil,
    intimidatorPhase = nil,
    obstructionSpawnPos = nil,
    obstructionSpawnTime = 0,
    obstructionSuccessTimer = 0,
    traySeqDidRun = false,
    traySeqActive = false,
    traySeqState = nil,
    traySeqUntil = 0,
    endMode = nil,
    forwardFireCrumb = nil,
    forwardFirePhase = nil,
    forwardFireTimer = 0,
    forwardFireExplosionTimer = 0,
    forwardFireSpawnModel = nil,
    forwardFireSpawnConfig = nil,
    stolenMoney = 0,
    lastReturnedMoney = 0,
    lastBonusMoney = 0,
    lastEventLine = "",
    lastEventTtl = 0,
    lastOutcomeLine = "",
    eventLog = {},
    uiShowInfo = false,
    uiShowEventLog = false,
    chaseActive = false,
    fkbAnchor = nil,
    fkbAnchorBadFrames = 0,
    testDumpTruckVehId = nil,
    testDumpTruckStatus = "",
    backCrumbPos = {
      [10] = nil,
      [100] = nil,
      [200] = nil,
      [300] = nil
    },
    ambientLoopName = nil,
    ambientLoopVol = 1.0,
    ambientFadeRemaining = 0,
    ambientFadeTotal = 0,
    ambientActive = false,
    objectiveTimer = 0,
    objectiveText = ""
  }
end

initState(CTX)
local S = CTX.S
S = S or {}

-- =========================
-- Helpers
-- =========================
local function isValidVeh(v)
  if not v then return false end
  local ok, id = pcall(function() return v:getId() end)
  return ok and id ~= nil
end

local function getPlayerVehicle()
  local v = be:getPlayerVehicle(0)
  return (isValidVeh(v) and v) or nil
end

local function vehSpeed(v)
  if not isValidVeh(v) then return 0 end
  local vel = v:getVelocity()
  return vel and vel:length() or 0
end

local function kphToMps(kph)
  return (kph or 0) * (1000 / 3600)
end

local function sanitizeAiCommand(cmd)
  if not cmd then return cmd end
  if cmd:match("ai%.setAvoidTraffic") then
    cmd = cmd:gsub("ai%.setAvoidTraffic", "ai.setAvoidCars")
  end
  if cmd:match("ai%.setAvoidStatic") then
    cmd = cmd:gsub("ai%.setAvoidStatic", "ai.setAvoidCars")
  end
  if cmd:match("ai%.setAggressionMode") then
    if not cmd:match('ai%.setAggressionMode%("%s*rubberBand%s*"%s*%)')
      and not cmd:match('ai%.setAggressionMode%("%s*"%s*%)') then
      cmd = 'ai.setAggressionMode("")'
    end
  end
  if cmd:match("ai%.followRoad") then
    return "-- TODO: ai.followRoad not available in this BeamNG version"
  end
  if cmd:match("ai%.predictTarget") then
    return "-- TODO: ai.predictTarget not available in this BeamNG version"
  end
  if cmd:match("ai%.lineOfSightRequired") then
    return "-- TODO: ai.lineOfSightRequired not available in this BeamNG version"
  end
  if cmd:match("ai%.allowContact") then
    return "-- TODO: ai.allowContact not available in this BeamNG version"
  end
  if cmd:match("ai%.ramIntent") then
    return "-- TODO: ai.ramIntent not available in this BeamNG version"
  end
  if cmd:match("ai%.throttleSmoothing") then
    return "-- TODO: ai.throttleSmoothing not available in this BeamNG version"
  end
  if cmd:match("ai%.setTractionModel") then
    return "-- TODO: ai.setTractionModel requires numeric mode in this BeamNG version"
  end
  if cmd:match("ai%.engineRunning") then
    return "-- TODO: ai.engineRunning not available in this BeamNG version"
  end
  return cmd
end

local function wrapAiCommand(cmd)
  if not cmd or cmd == "" then return cmd end
  if cmd:match("^%s*pcall%(") then return cmd end
  if cmd:match("ai%.") then
    return string.format("pcall(function() %s end)", cmd)
  end
  return cmd
end

local function applyAiCommands(v, commands, targetVeh)
  if not (isValidVeh(v) and type(commands) == "table") then return end

  local lines = {}
  if targetVeh and isValidVeh(targetVeh) then
    lines[#lines + 1] = wrapAiCommand(string.format("ai.setTargetObjectID(%d)", targetVeh:getId()))
  end
  for _, cmd in ipairs(commands) do
    cmd = sanitizeAiCommand(cmd)
    if cmd and cmd ~= "" then
      lines[#lines + 1] = wrapAiCommand(cmd)
    end
  end
  if #lines > 0 then
    v:queueLuaCommand(table.concat(lines, "\n"))
  end
end

local function isBigDumpTruckEvent(def)
  return def and def.key == "dumptruck_chase_switch_300m"
end

local function sendDumpTruckTrayInput(v, axis)
  if not isValidVeh(v) then return end
  local axisValue = tonumber(axis) or 0
  v:queueLuaCommand(string.format('input.event("PTOAxis", %d, 1)', axisValue))
end

local function stopDumpTruckTraySequence(resetDidRun)
  if isBigDumpTruckEvent(S.activeMobDef) and S.robberVeh and isValidVeh(S.robberVeh) then
    sendDumpTruckTrayInput(S.robberVeh, 0)
  end
  S.traySeqActive = false
  S.traySeqState = nil
  S.traySeqUntil = 0
  if resetDidRun then
    S.traySeqDidRun = false
  end
end

local function fmtMoney(n)
  n = tonumber(n) or 0
  return string.format("%.2f", n)
end

local function postEventLine(text, ttl)
  S.lastEventLine = tostring(text or "")
  S.lastEventTtl = tonumber(ttl) or 12.0
  if S.lastEventLine ~= "" then
    table.insert(S.eventLog, S.lastEventLine)
    if #S.eventLog > 3 then
      table.remove(S.eventLog, 1)
    end
  end
end

local function postOutcomeLine(text)
  S.lastOutcomeLine = tostring(text or "")
  if S.lastOutcomeLine ~= "" then
    table.insert(S.eventLog, S.lastOutcomeLine)
    if #S.eventLog > 3 then
      table.remove(S.eventLog, 1)
    end
  end
end

local function fmtTimeMMSS(sec)
  sec = math.max(0, tonumber(sec) or 0)
  local m = math.floor(sec / 60)
  local s = math.floor(sec % 60)
  return string.format("%02d:%02d", m, s)
end

local function uiTextWrapped(imgui, s)
  if imgui.TextWrapped then
    imgui.TextWrapped(s)
  else
    imgui.Text(s)
  end
end

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function clamp01(value)
  return clamp(tonumber(value) or 0, 0, 1)
end

local function lerp(a, b, t)
  return (a or 0) + ((b or 0) - (a or 0)) * (t or 0)
end

-- seed RNG once
local __randSeeded = false
local function seedRngOnce()
  if __randSeeded then return end
  __randSeeded = true
  math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
  math.random(); math.random(); math.random()
end

local function pickRandomEarningsTarget()
  seedRngOnce()
  local list = CFG.autoRobberyThresholdOptions or { 500, 1000, 3000, 5000 }
  local idx = math.random(1, #list)
  return tonumber(list[idx]) or 5000
end

local function ensureEarningsTarget()
  if S.currentEarningsTarget == nil then
    S.currentEarningsTarget = pickRandomEarningsTarget()
  end
end

local function resetEarningsCycle()
  S.earningsSinceRobbery = 0
  S.ignorePositiveCredit = 0
  S.currentEarningsTarget = pickRandomEarningsTarget()
end

-- =========================
-- Career gating
-- =========================
local function isCareerActive()
  local active = false
  pcall(function()
    if careerActive == true then active = true end
    if not active and career_modules_playerAttributes ~= nil then active = true end
    if not active and career_career ~= nil then active = true end
  end)
  return active == true
end

local function isPausedOrMenu()
  local paused = false
  pcall(function()
    if simTimeAuthority and type(simTimeAuthority.isPaused) == "function" then
      paused = simTimeAuthority.isPaused()
    end
  end)
  return paused == true
end

-- =========================
-- Player anchor (vehicle preferred, camera fallback)
-- =========================
local lastAnchorPos = nil
local lastAnchorFwd = vec3(0, 1, 0)
local lastAnchorRot = quat(0,0,0,1)

local function safeQuatFromDir(dir, up, fallbackQuat)
  if type(quatFromDir) == "function" then
    local ok, q = pcall(function() return quatFromDir(dir, up) end)
    if ok and q then return q end
  end
  return fallbackQuat or quat(0,0,0,1)
end

local function getCameraAnchor()
  local pos, fwd, rot
  pcall(function()
    if core_camera and type(core_camera.getPosition) == "function" then
      pos = core_camera.getPosition()
    end
  end)
  pcall(function()
    if not pos and type(getCameraPosition) == "function" then
      pos = getCameraPosition()
    end
  end)
  pcall(function()
    if core_camera and type(core_camera.getForward) == "function" then
      fwd = core_camera.getForward()
    end
  end)
  pcall(function()
    if not fwd and type(getCameraForward) == "function" then
      fwd = getCameraForward()
    end
  end)
  pcall(function()
    if core_camera and type(core_camera.getQuat) == "function" then
      rot = core_camera.getQuat()
    end
  end)
  pcall(function()
    if not rot and core_camera and type(core_camera.getRotation) == "function" then
      rot = core_camera.getRotation()
    end
  end)
  return pos, fwd, rot
end

-- Returns: pos, fwd, rot, anchorMode
local function getPlayerAnchor()
  local up = vec3(0,0,1)

  local v = getPlayerVehicle()
  if v then
    local pos = v:getPosition()
    local fwd = v:getDirectionVector()
    if not fwd or fwd:length() < 0.01 then fwd = vec3(0,1,0) end
    fwd:normalize()

    local rot = nil
    pcall(function() rot = v:getRotation() end)
    rot = rot or lastAnchorRot

    lastAnchorPos = pos
    lastAnchorFwd = fwd
    lastAnchorRot = rot
    return pos, fwd, rot, "vehicle"
  end

  local cpos, cfwd, crot = getCameraAnchor()
  if cpos then
    if not cfwd or cfwd:length() < 0.01 then cfwd = lastAnchorFwd end
    cfwd.z = 0
    if cfwd:length() < 0.01 then cfwd = vec3(0,1,0) end
    cfwd:normalize()

    local rot = crot or safeQuatFromDir(cfwd, up, lastAnchorRot)

    lastAnchorPos = cpos
    lastAnchorFwd = cfwd
    lastAnchorRot = rot
    return cpos, cfwd, rot, "camera"
  end

  if lastAnchorPos then
    return lastAnchorPos, lastAnchorFwd, lastAnchorRot, "last"
  end

  return nil, nil, nil, "none"
end

local function canStartRobberyNow()
  if not isCareerActive() then return false, "Career not active." end
  if isPausedOrMenu() then return false, "Paused/menu." end
  local pos = select(1, getPlayerAnchor())
  if not pos then return false, "No player anchor (vehicle/camera missing)." end
  return true, nil
end

-- =========================
-- Forward-distance breadcrumb tracking (spawn failsafe)
-- =========================
local travelTotalForward = 0.0
local travelLastPos = nil
local travelLastFwd = nil
local travelAccumSinceCrumb = 0.0
local travelCrumbs = {} -- { pos=vec3, fwd=vec3, dist=number }
local forwardKnownAvailabilityCache = {
  [10] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
  [50] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
  [100] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
  [200] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
  [300] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil }
}
local forwardKnownAvailabilityMeta = {
  segStartIdx = nil,
  dir = nil,
  distToProjection = nil
}
local forwardKnownCheckTimer = 0.0
local FORWARD_DEBUG_SPACINGS = { 10, 50, 100, 200, 300 }
local BACK_BREADCRUMB_METERS = { 10, 100, 200, 300 }
local DEBUG_LABEL_OFFSET = vec3(0, 0, 1.5)
local DEBUG_FWD_COLOR = ColorF(0.2, 0.9, 1.0, 1.0)
local DEBUG_BACK_COLOR = ColorF(1.0, 0.6, 0.2, 1.0)
local DEBUG_TEXT_COLOR = ColorF(1.0, 1.0, 1.0, 1.0)

local TRAVEL = {
  crumbEveryMeters = 1.0,  -- 1m resolution
  keepMeters = 5200.0,     -- enough to support 5000m anchor reacquisition history
  teleportResetMeters = 50.0
}

local function spawnDebugDumptruckSimple()
  local entry = forwardKnownAvailabilityCache[300] or {}
  local fkbPos = entry.lastGoodPos or entry.pos
  if not fkbPos then
    S.testDumpTruckStatus = "No lastGood FKB 300m position yet"
    return
  end

  if S.testDumpTruckVehId then
    local existing = be:getObjectByID(S.testDumpTruckVehId)
    if existing and isValidVeh(existing) then
      S.testDumpTruckStatus = "Test truck already active"
      return
    end
  end

  local spawnPos = vec3(fkbPos.x, fkbPos.y, fkbPos.z + 1.0)
  local up = vec3(0, 0, 1)

  local fwd = nil
  local crumb = entry.lastGoodCrumb or entry.crumb
  if crumb and crumb.fwd then
    fwd = crumb.fwd
  else
    local _, anchorFwd = getPlayerAnchor()
    fwd = anchorFwd
  end

  if not fwd then fwd = vec3(0, 1, 0) end
  fwd = vec3(fwd.x, fwd.y, 0)
  if fwd:length() < 0.01 then fwd = vec3(0, 1, 0) end
  fwd:normalize()

  local rot = safeQuatFromDir(fwd, up, quat(0, 0, 0, 1))
  local vehicle = Mobs.spawn({ model = "dumptruck", config = "BigDumpTruck" }, spawnPos, rot)
  if vehicle and isValidVeh(vehicle) then
    S.testDumpTruckVehId = vehicle:getId()
    S.testDumpTruckStatus = "Spawned BigDumpTruck (FLEE AI – low aggression). Will persist until EndEvent."
    local playerVeh = getPlayerVehicle()
    applyAiCommands(vehicle, {
      'ai.setMode("flee")',
      'ai.setSpeedMode("legal")',
      'ai.setAvoidCars("on")',
      'ai.driveInLane("off")',
      "ai.setAggression(0.1)",
      'ai.setAggressionMode("")',
      "ai.setRecoverOnCrash(true)"
    }, playerVeh)
  else
    S.testDumpTruckVehId = nil
    S.testDumpTruckStatus = "Test truck spawn failed."
  end
end

local function endDebugSpawnVehicle()
  if S.testDumpTruckVehId then
    local v = be:getObjectByID(S.testDumpTruckVehId)
    if v and isValidVeh(v) then
      pcall(function() v:queueLuaCommand('pcall(function() ai.setMode("disabled") end)') end)
      pcall(function() v:queueLuaCommand('pcall(function() ai.setTargetObjectID(0) end)') end)
      pcall(function() v:delete() end)
      S.testDumpTruckStatus = "Test truck removed."
    else
      S.testDumpTruckStatus = "No test truck active."
    end
  else
    S.testDumpTruckStatus = "No test truck active."
  end
  S.testDumpTruckVehId = nil
end

local warnedMissingFwdFn = false

local function getHorizontalFwdFromVehicle(v)
  if not (v and isValidVeh(v)) then
    return vec3(0, 1, 0)
  end
  local fwd = v:getDirectionVector()
  if not fwd then
    return vec3(0, 1, 0)
  end
  fwd.z = 0
  if fwd:length() < 0.01 then
    return vec3(0, 1, 0)
  end
  fwd:normalize()
  return fwd
end

local function resetTravelHistory()
  travelTotalForward = 0.0
  travelLastPos = nil
  travelLastFwd = nil
  travelAccumSinceCrumb = 0.0
  travelCrumbs = {}
  S.fkbAnchor = nil
  S.fkbAnchorBadFrames = 0
  local v = getPlayerVehicle()
  local pos = v and v:getPosition() or nil
  if pos then
    local fwd
    if type(getHorizontalFwdFromVehicle) == "function" then
      fwd = getHorizontalFwdFromVehicle(v)
    else
      if not warnedMissingFwdFn then
        log("W", "BolidesTheCut", "getHorizontalFwdFromVehicle missing during resetTravelHistory; using default fwd")
        warnedMissingFwdFn = true
      end
      fwd = vec3(0, 1, 0)
    end
    travelCrumbs[1] = { pos = vec3(pos), fwd = vec3(fwd), dist = 0.0 }
    travelCrumbs[2] = { pos = vec3(pos), fwd = vec3(fwd), dist = 0.0 }
  end
  if S and S.backCrumbPos then
    for i = 1, #BACK_BREADCRUMB_METERS do
      S.backCrumbPos[BACK_BREADCRUMB_METERS[i]] = nil
    end
  end
  forwardKnownAvailabilityCache = {
    [10] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
    [50] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
    [100] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
    [200] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil },
    [300] = { available = false, distAhead = nil, pos = nil, crumb = nil, lastGoodPos = nil, lastGoodT = nil, lastGoodCrumb = nil }
  }
  forwardKnownAvailabilityMeta = {
    segStartIdx = nil,
    dir = nil,
    distToProjection = nil
  }
  forwardKnownCheckTimer = 0.0
end

local function pruneTravelCrumbs()
  local minDist = travelTotalForward - (TRAVEL.keepMeters or 220.0)
  if minDist < 0 then return end
  while #travelCrumbs > 0 and (travelCrumbs[1].dist or 0) < minDist do
    table.remove(travelCrumbs, 1)
  end
end

local function pushCrumb(pos, fwd, dist)
  travelCrumbs[#travelCrumbs + 1] = { pos = pos, fwd = fwd, dist = dist }
  pruneTravelCrumbs()
end

local updateBackCrumbPositions -- forward declare (required)

local function updateTravelHistory(dtSim)
  local v = getPlayerVehicle()
  if not v then return end

  local pos = v:getPosition()
  if not pos then return end

  local fwdNow = getHorizontalFwdFromVehicle(v)

  if not travelLastPos then
    travelLastPos = pos
    travelLastFwd = fwdNow
    pushCrumb(pos, fwdNow, travelTotalForward)
    updateBackCrumbPositions()
    return
  end

  local delta = pos - travelLastPos
  local step = delta:length()

  if step >= (TRAVEL.teleportResetMeters or 50.0) then
    resetTravelHistory()
    travelLastPos = pos
    travelLastFwd = fwdNow
    pushCrumb(pos, fwdNow, travelTotalForward)
    updateBackCrumbPositions()
    return
  end

  local stepDist = step -- delta:length()

  if stepDist > 0.0 then
    travelTotalForward = travelTotalForward + stepDist
    travelAccumSinceCrumb = travelAccumSinceCrumb + stepDist

    local every = TRAVEL.crumbEveryMeters or 1.0
    while travelAccumSinceCrumb >= every do
      pushCrumb(pos, fwdNow, travelTotalForward)
      travelAccumSinceCrumb = travelAccumSinceCrumb - every
    end
  end

  travelLastPos = pos
  travelLastFwd = fwdNow
  updateBackCrumbPositions()
end

local function hasTravelAtLeast(meters)
  return (travelTotalForward or 0) >= (tonumber(meters) or 0)
end

local function getCrumbBack(metersBack)
  metersBack = tonumber(metersBack) or 0
  if metersBack <= 0 then return nil end

  local target = (travelTotalForward or 0) - metersBack
  if target < 0 then return nil end
  if #travelCrumbs == 0 then return nil end

  for i = #travelCrumbs, 1, -1 do
    local c = travelCrumbs[i]
    if (c.dist or -1) <= target then
      return c
    end
  end
  return nil
end

local function findClosestCrumbIndex(crumbs, p)
  local bestI, bestD = nil, math.huge
  for i = 1, #crumbs do
    local d = (crumbs[i].pos - p):length()
    if d < bestD then bestD, bestI = d, i end
  end
  return bestI, bestD
end

local FKB_CONE_DEG = 80
local FKB_ANCHOR_HOLD_RADIUS = 12.0
local FKB_ANCHOR_BAD_FRAME_LIMIT = 30
local FKB_ANCHOR_BAD_FRAME_SPEED = 2.0
local FKB_REACQUIRE_HISTORY_METERS = 5000.0
local FKB_REACQUIRE_MAX_DISTANCE = 120.0

local function projectPointToSegment(p, a, b)
  local ab = b - a
  local abLen2 = ab:squaredLength()
  if abLen2 < 1e-6 then return a, 0 end
  local t = (p - a):dot(ab) / abLen2
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return a + ab * t, t
end

local function sampleAtDistanceFrom(originPos, originIdx, dir, crumbs, dist)
  local curPos = originPos
  local curIdx = originIdx
  local remain = dist

  while true do
    local nextIdx = curIdx + dir
    if nextIdx < 1 or nextIdx > #crumbs then return nil end

    local nextPos = crumbs[nextIdx].pos
    local seg = nextPos - curPos
    local segLen = seg:length()
    if segLen < 1e-6 then
      curIdx = nextIdx
      curPos = nextPos
    else
      if remain <= segLen then
        local t = remain / segLen
        local pos = curPos + seg * t
        return pos, (seg / segLen)
      end
      remain = remain - segLen
      curIdx = nextIdx
      curPos = nextPos
    end
  end
end

local function isPosAheadOfPlayer(playerPos, playerFwd, pos, coneDeg)
  if not (playerPos and playerFwd and pos) then return false end

  local toPos = pos - playerPos
  toPos.z = 0
  local toLen = toPos:length()
  if toLen < 0.001 then return false end

  local fwd = vec3(playerFwd.x, playerFwd.y, 0)
  if fwd:length() < 0.001 then return false end
  fwd:normalize()

  local cosCone = math.cos(math.rad(coneDeg or FKB_CONE_DEG))
  local dot = (toPos / toLen):dot(fwd)
  return dot >= cosCone
end

local function findBestAnchorSegment(crumbs, playerPos)
  local closestIdx = findClosestCrumbIndex(crumbs, playerPos)
  if not closestIdx then return nil end

  local best = { dist = math.huge, segStartIdx = nil, anchorPos = nil }

  local function consider(segStartIdx)
    if segStartIdx < 1 or segStartIdx + 1 > #crumbs then return end
    local a = crumbs[segStartIdx].pos
    local b = crumbs[segStartIdx + 1].pos
    local proj = projectPointToSegment(playerPos, a, b)
    local dist = (playerPos - proj):length()
    if dist < best.dist then
      best.dist = dist
      best.segStartIdx = segStartIdx
      best.anchorPos = proj
    end
  end

  if closestIdx < #crumbs then
    consider(closestIdx)
  end
  if closestIdx > 1 then
    consider(closestIdx - 1)
  end

  if not best.segStartIdx then return nil end
  return best.segStartIdx, best.anchorPos, best.dist
end

local function findReacquiredAnchorSegment(crumbs, playerPos, playerFwd, coneDeg, maxHistoryMeters, maxDistance)
  if #crumbs < 2 then return nil end

  local fwd = vec3(playerFwd.x, playerFwd.y, 0)
  if fwd:length() < 0.001 then return nil end
  fwd:normalize()

  local latestDist = crumbs[#crumbs].dist or 0
  local minDist = latestDist - (maxHistoryMeters or FKB_REACQUIRE_HISTORY_METERS)
  local maxDist = maxDistance or FKB_REACQUIRE_MAX_DISTANCE
  local cosCone = math.cos(math.rad(coneDeg or FKB_CONE_DEG))

  local best = { dist = math.huge, dot = -1, segStartIdx = nil, anchorPos = nil }

  for i = #crumbs - 1, 1, -1 do
    local segDist = crumbs[i].dist or 0
    if segDist < minDist then break end

    local a = crumbs[i].pos
    local b = crumbs[i + 1].pos
    local proj = projectPointToSegment(playerPos, a, b)
    local dist = (playerPos - proj):length()
    if dist <= maxDist then
      local segDir = b - a
      segDir.z = 0
      local segLen = segDir:length()
      if segLen > 1e-6 then
        segDir = segDir / segLen
        local dot = segDir:dot(fwd)
        if dot >= cosCone then
          if dist < best.dist or (math.abs(dist - best.dist) < 0.01 and dot > best.dot) then
            best.dist = dist
            best.dot = dot
            best.segStartIdx = i
            best.anchorPos = proj
          end
        end
      end
    end
  end

  if not best.segStartIdx then return nil end
  return best.segStartIdx, best.anchorPos, best.dist
end

local function getAnchorOriginIdx(segStartIdx, segDir)
  return (segDir == 1) and segStartIdx or (segStartIdx + 1)
end

local function isDirectionAhead(anchorPos, segStartIdx, segDir, crumbs, playerPos, playerFwd, coneDeg, testDist)
  local originIdx = getAnchorOriginIdx(segStartIdx, segDir)
  if originIdx < 1 or originIdx > #crumbs then return false end
  local testPos = sampleAtDistanceFrom(anchorPos, originIdx, segDir, crumbs, testDist)
  if not testPos then return false end

  local toTest = testPos - playerPos
  toTest.z = 0
  local toTestLen = toTest:length()
  if toTestLen < 0.001 then return false end

  local fwd = vec3(playerFwd.x, playerFwd.y, 0)
  if fwd:length() < 0.001 then return false end
  fwd:normalize()

  local cosCone = math.cos(math.rad(coneDeg or FKB_CONE_DEG))
  local dot = (toTest / toTestLen):dot(fwd)
  return dot >= cosCone
end

local function resolveFkbAnchor(crumbs, playerPos, playerFwd, coneDeg, testDist)
  if #crumbs < 2 then return nil end

  local anchor = nil
  local anchorValid = false

  if S.fkbAnchor and S.fkbAnchor.segStartIdx then
    local segStartIdx = S.fkbAnchor.segStartIdx
    if segStartIdx >= 1 and segStartIdx + 1 <= #crumbs then
      local a = crumbs[segStartIdx].pos
      local b = crumbs[segStartIdx + 1].pos
      local proj = projectPointToSegment(playerPos, a, b)
      local dist = (playerPos - proj):length()
      if dist <= FKB_ANCHOR_HOLD_RADIUS then
        anchor = {
          segStartIdx = segStartIdx,
          segDir = S.fkbAnchor.segDir,
          anchorPos = proj,
          distToProjection = dist
        }
        anchorValid = true
      end
    end
  end

  if not anchor then
    if S.fkbAnchor and not anchorValid then
      S.fkbAnchor = nil
      S.fkbAnchorBadFrames = 0
    end

    local segStartIdx, anchorPos, dist = nil, nil, nil
    if not S.fkbAnchor then
      segStartIdx, anchorPos, dist = findReacquiredAnchorSegment(
        crumbs,
        playerPos,
        playerFwd,
        coneDeg or FKB_CONE_DEG,
        FKB_REACQUIRE_HISTORY_METERS,
        FKB_REACQUIRE_MAX_DISTANCE
      )
    end
    if not segStartIdx then
      S.fkbAnchor = nil
      S.fkbAnchorBadFrames = 0
      return nil
    end
    anchor = {
      segStartIdx = segStartIdx,
      segDir = nil,
      anchorPos = anchorPos,
      distToProjection = dist
    }
  end

  local minTestDist = testDist or 10
  local dir = anchor.segDir

  if dir and not isDirectionAhead(anchor.anchorPos, anchor.segStartIdx, dir, crumbs, playerPos, playerFwd, coneDeg, minTestDist) then
    dir = -dir
  end

  if not dir then
    if isDirectionAhead(anchor.anchorPos, anchor.segStartIdx, 1, crumbs, playerPos, playerFwd, coneDeg, minTestDist) then
      dir = 1
    elseif isDirectionAhead(anchor.anchorPos, anchor.segStartIdx, -1, crumbs, playerPos, playerFwd, coneDeg, minTestDist) then
      dir = -1
    end
  elseif not isDirectionAhead(anchor.anchorPos, anchor.segStartIdx, dir, crumbs, playerPos, playerFwd, coneDeg, minTestDist) then
    local speed = vehSpeed(getPlayerVehicle())
    if speed > FKB_ANCHOR_BAD_FRAME_SPEED then
      S.fkbAnchorBadFrames = (S.fkbAnchorBadFrames or 0) + 1
      if S.fkbAnchorBadFrames >= FKB_ANCHOR_BAD_FRAME_LIMIT then
        S.fkbAnchor = nil
        return nil
      end
    end
  else
    S.fkbAnchorBadFrames = 0
  end

  if not dir then
    S.fkbAnchor = nil
    S.fkbAnchorBadFrames = 0
    return nil
  end

  anchor.segDir = dir
  S.fkbAnchorBadFrames = 0
  S.fkbAnchor = {
    segStartIdx = anchor.segStartIdx,
    segDir = anchor.segDir,
    lastAnchorPos = anchor.anchorPos
  }

  return anchor
end

local function computeFKBFromCrumbs(crumbs, playerPos, playerFwd, spacings, maxAhead, coneDeg)
  local out = {}
  if #crumbs < 2 then return out end

  local maxLimit = maxAhead or math.huge
  local minSpacing = 10
  for _, spacing in ipairs(spacings or {}) do
    local target = tonumber(spacing) or 0
    if target > 0 and target < minSpacing then
      minSpacing = target
    end
  end
  local anchor = resolveFkbAnchor(crumbs, playerPos, playerFwd, coneDeg, minSpacing)
  if not anchor then return out end

  local originIdx = getAnchorOriginIdx(anchor.segStartIdx, anchor.segDir)
  if originIdx < 1 or originIdx > #crumbs then return out end
  local originPos = anchor.anchorPos

  for _, spacing in ipairs(spacings) do
    local target = tonumber(spacing) or 0
    if target > 0 and target <= maxLimit then
      local pos, fwd = sampleAtDistanceFrom(originPos, originIdx, anchor.segDir, crumbs, target)
      if pos then
        out[spacing] = {
          available = true,
          pos = pos,
          distAhead = target,
          dir = anchor.segDir,
          crumb = { pos = pos, fwd = fwd }
        }
      end
    end
  end

  return out
end

updateBackCrumbPositions = function()
  if not (S and S.backCrumbPos) then return end
  for i = 1, #BACK_BREADCRUMB_METERS do
    local metersBack = BACK_BREADCRUMB_METERS[i]
    local crumb = getCrumbBack(metersBack)
    S.backCrumbPos[metersBack] = (crumb and crumb.pos) or nil
  end
end

local function getForwardKnownBreadcrumb(spacingMeters, minAheadMeters, maxAheadMeters, coneDeg)
  spacingMeters = tonumber(spacingMeters) or 0
  if spacingMeters <= 0 then return nil end

  local playerPos, playerFwd = getPlayerAnchor()
  if not (playerPos and playerFwd) then return nil end

  local minAhead = tonumber(minAheadMeters) or 0
  local maxAhead = tonumber(maxAheadMeters) or nil
  if maxAhead and maxAhead <= 0 then maxAhead = nil end

  local fixedConeDeg = FKB_CONE_DEG
  local found = computeFKBFromCrumbs(travelCrumbs, playerPos, playerFwd, { spacingMeters }, maxAhead, fixedConeDeg)
  local availability = found and found[spacingMeters] or nil
  if not availability or availability.distAhead < minAhead then return nil end
  return availability.crumb, availability.distAhead
end

local function getForwardKnownAvailability(spacingMeters, minAheadMeters, maxAheadMeters, coneDeg)
  local crumb, aheadDist = getForwardKnownBreadcrumb(spacingMeters, minAheadMeters, maxAheadMeters, FKB_CONE_DEG)
  if not crumb then
    return { available = false, distAhead = nil, pos = nil }
  end
  return { available = true, distAhead = aheadDist, pos = crumb.pos, crumb = crumb }
end

local function updateForwardKnownAvailabilityCache()
  local playerPos, playerFwd = getPlayerAnchor()
  if not (playerPos and playerFwd) then return end
  local now = tonumber(S.simTime) or 0

  local spacings = { 10, 50, 100, 200, 300 }
  local maxAhead = tonumber(CFG.forwardKnownMaxAheadMeters) or 800.0
  local coneDeg = FKB_CONE_DEG

  local fkb = computeFKBFromCrumbs(travelCrumbs, playerPos, playerFwd, spacings, maxAhead, coneDeg)
  forwardKnownAvailabilityMeta = {
    segStartIdx = S.fkbAnchor and S.fkbAnchor.segStartIdx or nil,
    dir = S.fkbAnchor and S.fkbAnchor.segDir or nil,
    distToProjection = S.fkbAnchor and S.fkbAnchor.lastAnchorPos and (playerPos - S.fkbAnchor.lastAnchorPos):length() or nil
  }

  for _, spacing in ipairs(spacings) do
    local availability = fkb and fkb[spacing] or nil
    local prev = forwardKnownAvailabilityCache[spacing] or {}
    if availability and availability.available then
      forwardKnownAvailabilityCache[spacing] = {
        available = true,
        distAhead = availability.distAhead,
        pos = availability.pos,
        dir = availability.dir,
        crumb = availability.crumb,
        lastGoodPos = availability.pos,
        lastGoodT = now,
        lastGoodCrumb = availability.crumb
      }
    else
      if prev.lastGoodPos and prev.lastGoodT and (now - prev.lastGoodT) <= 3.0 then
        forwardKnownAvailabilityCache[spacing] = {
          available = true,
          distAhead = prev.distAhead,
          pos = prev.lastGoodPos,
          dir = prev.dir,
          crumb = prev.lastGoodCrumb or prev.crumb,
          lastGoodPos = prev.lastGoodPos,
          lastGoodT = prev.lastGoodT,
          lastGoodCrumb = prev.lastGoodCrumb or prev.crumb
        }
      else
        forwardKnownAvailabilityCache[spacing] = {
          available = false,
          distAhead = nil,
          pos = nil,
          dir = nil,
          crumb = nil,
          lastGoodPos = nil,
          lastGoodT = nil,
          lastGoodCrumb = nil
        }
      end
    end
  end
end

local function getSpawnRequirement(def)
  local sr = def and def.spawnRequirement or nil

  if type(sr) == "table" then
    if not sr.type then sr.type = "none" end
    return sr
  end

  if type(sr) == "string" then
    if sr == "back" then
      local back = tonumber(def and def.spawnBackMeters) or 0
      if back > 0 then return { type = "back", backMeters = back } end
      return { type = "none" }
    elseif sr == "forward" or sr == "fwd" then
      return {
        type = "forward",
        spacings = def and def.fkbSpacings,
        maxAhead = tonumber(def and def.maxAhead) or tonumber(CFG.forwardKnownMaxAheadMeters) or 800,
        coneDeg = tonumber(def and def.coneDeg) or 45,
      }
    end
    return { type = "none" }
  end

  if def and def.spawnBackMeters then
    return { type = "back", backMeters = def.spawnBackMeters }
  end

  return { type = "none" }
end

local function isForwardFireEvent(def)
  return def and def.kind == "traffic_fire" and def.forwardSpawn == true
end

local function describeSpawnRequirement(req)
  if req ~= nil and type(req) ~= "table" then
    return string.format("Invalid spawn requirement (%s)", type(req))
  end
  local reqType = (type(req) == "table") and req.type or "none"
  if not req or reqType == "none" then
    return "No spawn requirement"
  end
  if reqType == "forward" then
    return string.format("ForwardKnownBreadcrumb(%dm) available", tonumber(req.spacing) or 0)
  end
  if reqType == "back" then
    return string.format("BackBreadcrumb(%dm) ready", tonumber(req.backMeters) or 0)
  end
  return "Unknown requirement"
end

local isBackBreadcrumbReady

local function isSpawnRequirementAvailable(req)
  if req == nil then
    return true, nil
  end
  if type(req) ~= "table" then
    return false, { available = false, reason = "spawnRequirement invalid type: " .. type(req) }
  end
  local rtype = req.type
  if rtype == nil then rtype = "none" end
  if type(rtype) ~= "string" then
    return false, { available = false, reason = "spawnRequirement.type missing/invalid" }
  end
  if rtype == "none" then return true, nil end
  if rtype == "forward" then
    local spacing = tonumber(req.spacing) or 0
    local cfg = CFG or {}
    local minAhead = tonumber(req.minAhead) or (tonumber(cfg.forwardKnownMinAheadMeters) or 150.0)
    local maxAhead = tonumber(req.maxAhead) or (tonumber(cfg.forwardKnownMaxAheadMeters) or 800.0)
    local availability = getForwardKnownAvailability(spacing, minAhead, maxAhead, FKB_CONE_DEG)
    return availability.available == true, availability
  end
  if rtype == "back" then
    return isBackBreadcrumbReady(req.backMeters) == true, nil
  end
  return false, nil
end

local function getForwardCommitDistance(req, availability)
  local reqType = (type(req) == "table") and req.type or "none"
  if reqType ~= "forward" then return nil end
  local crumb = availability and availability.crumb
  if not (crumb and crumb.pos) then return nil end
  local pos = select(1, getPlayerAnchor())
  if not pos then return nil end
  return (pos - crumb.pos):length()
end

-- requires BOTH 10m and 300m crumbs, and >=300m forward travel
isBackBreadcrumbReady = function(metersBack)
  local c = getCrumbBack(metersBack)
  return c and c.pos and c.fwd
end

local function spawnPointsReady(def)
  if not def then return false end
  local req = getSpawnRequirement(def)
  if type(req) ~= "table" then req = { type = "none" } end
  local reqType = (type(req) == "table") and req.type or "none"
  if reqType == "forward" then
    local ok = isSpawnRequirementAvailable(req)
    return ok == true
  end

  local back = tonumber(def.spawnBackMeters) or 0
  if back <= 0 then return true end
  if not hasTravelAtLeast(back) then return false end
  return isBackBreadcrumbReady(back) == true
end

local function clearManualRequest()
  S.manualRequest = {
    eventKey = nil,
    requestedAtSec = 0,
    statusMsg = "",
    required = "",
    pending = false,
    lastStatusMsg = ""
  }
end

local function setManualStatus(statusMsg, required)
  S.manualRequest.statusMsg = statusMsg or ""
  S.manualRequest.required = required or ""
  if S.manualRequest.statusMsg ~= S.manualRequest.lastStatusMsg then
    S.manualRequest.lastStatusMsg = S.manualRequest.statusMsg
    if S.manualRequest.statusMsg ~= "" then
      postEventLine(S.manualRequest.statusMsg, 12)
    end
  end
end

local function computeMoneyScore()
  local threshold = tonumber(S.currentEarningsTarget) or 0
  if threshold <= 0 then return 0 end
  return clamp01((S.earningsSinceRobbery or 0) / math.max(1, threshold))
end

local function computeOpportunityScore()
  local moneyScore = computeMoneyScore()
  local forwardSpacing = tonumber(CFG.opportunityForwardSpacingMeters) or 200.0
  local forwardMinAhead = tonumber(CFG.opportunityForwardMinAheadMeters) or 150.0
  local forwardMaxAhead = tonumber(CFG.opportunityForwardMaxAheadMeters) or 800.0
  local backMeters = tonumber(CFG.opportunityBackMeters) or 200.0

  local forwardAvailability = getForwardKnownAvailability(forwardSpacing, forwardMinAhead, forwardMaxAhead)
  local forwardScore = forwardAvailability.available and 1 or 0
  local backScore = isBackBreadcrumbReady(backMeters) and 1 or 0

  local moneyWeight = tonumber(CFG.moneyWeight) or 0.6
  local forwardWeight = tonumber(CFG.forwardWeight) or 0.3
  local backWeight = tonumber(CFG.backWeight) or 0.1

  return (moneyWeight * moneyScore) + (forwardWeight * forwardScore) + (backWeight * backScore)
end

-- =========================
-- Robber engine ON (best effort)
-- =========================
local function forceEngineOn(v)
  if not isValidVeh(v) then return end
  local cmd = [[
    if electrics and electrics.values then
      pcall(function() electrics.values.ignitionLevel = 2 end)
      pcall(function() electrics.values.ignition = 1 end)
      pcall(function() electrics.values.running = 1 end)
    end
    if electrics and electrics.setIgnitionLevel then
      pcall(function() electrics.setIgnitionLevel(2) end)
    end
    if powertrain and powertrain.setIgnition then
      pcall(function() powertrain.setIgnition(true) end)
    end
  ]]
  v:queueLuaCommand(cmd)
end

local function forceEngineOff(v)
  if not isValidVeh(v) then return end
  local cmd = [[
    if electrics and electrics.values then
      pcall(function() electrics.values.ignitionLevel = 0 end)
      pcall(function() electrics.values.ignition = 0 end)
      pcall(function() electrics.values.running = 0 end)
    end
    if electrics and electrics.setIgnitionLevel then
      pcall(function() electrics.setIgnitionLevel(0) end)
    end
    if powertrain and powertrain.setIgnition then
      pcall(function() powertrain.setIgnition(false) end)
    end
  ]]
  v:queueLuaCommand(cmd)
end

-- =========================
-- Wallet-only Career money
-- =========================
local function getWalletMoney()
  local v = nil
  pcall(function()
    if career_modules_playerAttributes and type(career_modules_playerAttributes.getAttributeValue) == "function" then
      v = career_modules_playerAttributes.getAttributeValue("money")
    end
  end)
  return tonumber(v) or 0
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

local function stealCareerMoney(wantAmount)
  wantAmount = tonumber(wantAmount) or 0
  if wantAmount <= 0 then return 0 end

  local walletBal = getWalletMoney()
  local steal = math.min(wantAmount, walletBal)
  if steal <= 0 then return 0 end

  if walletCanPay(steal) and walletRemove(steal) then
    return steal
  end
  return 0
end

local function restoreCareerMoney(amount)
  amount = tonumber(amount) or 0
  if amount <= 0 then return false end

  local ok = walletAdd(amount) == true
  if ok then
    S.ignorePositiveCredit = S.ignorePositiveCredit + amount
    S.lastMoneySample = getWalletMoney()
  end
  return ok
end

local function computeRobberyAmountFromWallet()
  local bal = getWalletMoney()
  local pct = tonumber(CFG.robberyPercent) or 0.5
  local want = bal * pct
  want = math.floor(want * 100 + 0.5) / 100
  return want
end

S.lastMobKey = nil
S.forcedNextMobKey = nil
S.activeMobKey = nil
S.activeMobDef = nil

-- UI list for selecting any mob
Mobs.normalize()
local mobOrder = Mobs.getOrderedKeys()

local function setEventTriggered(now)
  S.lastEventTimeSec = now
  S.lastEventTime = now
  local cooldown = tonumber(CFG.cooldownSec) or 0
  S.cooldownUntilSec = now + cooldown
  S.heat = clamp01(tonumber(CFG.heatAfterTrigger) or 0)
end

local function pickEligibleMobKey(preferredKey)
  local candidates = {}
  for _, key in ipairs(mobOrder) do
    local def = Mobs.getByKey(key)
    if def then
      local req = getSpawnRequirement(def)
      local ok = isSpawnRequirementAvailable(req)
      if ok then
        candidates[#candidates + 1] = key
      end
    end
  end
  if preferredKey then
    for _, key in ipairs(candidates) do
      if key == preferredKey then
        return key
      end
    end
  end

  if #candidates == 0 then return nil end
  seedRngOnce()
  local choice = candidates[math.random(1, #candidates)]
  local tries = 0
  while choice == S.lastMobKey and tries < 12 do
    choice = candidates[math.random(1, #candidates)]
    tries = tries + 1
  end
  return choice
end

local function triggerEventByKey(key, sourceLabel)
  if not key then return end
  S.forcedNextMobKey = key
  beginAmbush()
  if sourceLabel then
    local def = Mobs.getByKey(key)
    local label = def and (def.label or def.key) or key
    postEventLine(string.format("%s: %s triggered.", sourceLabel, label), 10)
  end
end

local function updateManualRequestStatus(now)
  if not S.manualRequest.pending then return end

  local age = now - (S.manualRequest.requestedAtSec or 0)
  local expireSec = tonumber(CFG.manualExpireSec) or 180.0
  if age >= expireSec then
    local def = S.manualRequest.eventKey and Mobs.getByKey(S.manualRequest.eventKey) or nil
    local label = (def and def.label) or S.manualRequest.eventKey or "Unknown"
    setManualStatus(string.format("Manual request: %s expired.", label), "")
    clearManualRequest()
    return
  end

  local def = S.manualRequest.eventKey and Mobs.getByKey(S.manualRequest.eventKey) or nil
  if not def then
    setManualStatus("Manual request: Unknown event.", "Unknown event")
    S.manualRequest.pending = false
    return
  end

  local missing = {}
  if S.state ~= STATE.IDLE then
    missing[#missing + 1] = "Event already active"
  end

  local ok, reason = canStartRobberyNow()
  if not ok then
    missing[#missing + 1] = reason or "Global gating failed"
  end

  local req = getSpawnRequirement(def)
  local reqType = (type(req) == "table") and req.type or "none"
  local reqOk, availability = isSpawnRequirementAvailable(req)
  if not reqOk then
    missing[#missing + 1] = describeSpawnRequirement(req)
  end

  if def.spawnBackMeters and reqType ~= "back" then
    local backReady = isBackBreadcrumbReady(def.spawnBackMeters)
    if not backReady then
      missing[#missing + 1] = string.format("BackBreadcrumb(%dm) ready", tonumber(def.spawnBackMeters) or 0)
    end
  end

  if #missing > 0 then
    local list = table.concat(missing, ", ")
    setManualStatus(string.format("Manual request: %s queued. Waiting for: %s.", def.label or def.key, list), list)
    return
  end

  if reqType == "forward" then
    local commitRadius = tonumber(req.commitRadius) or 100.0
    local crumb = availability and availability.crumb
    local pos = select(1, getPlayerAnchor())
    local dist = (crumb and crumb.pos and pos) and (pos - crumb.pos):length() or math.huge
    if dist <= commitRadius then
      setManualStatus(string.format("Manual request: %s triggered.", def.label or def.key), "")
      S.manualRequest.pending = false
      triggerEventByKey(def.key, nil)
      return
    end

    local armedMsg = string.format(
      "Manual request: %s armed. Will trigger when you approach the target point (<= %.0fm).",
      def.label or def.key,
      commitRadius
    )
    setManualStatus(armedMsg, "")
    return
  end

  setManualStatus(string.format("Manual request: %s triggered.", def.label or def.key), "")
  S.manualRequest.pending = false
  triggerEventByKey(def.key, nil)
end

local function requestManualEvent(key)
  if not key then return end
  S.manualRequest.eventKey = key
  S.manualRequest.requestedAtSec = S.simTime
  S.manualRequest.pending = true
  S.manualRequest.statusMsg = ""
  S.manualRequest.required = ""
  updateManualRequestStatus(S.simTime)
end

local function updateEligibilityTick(dtSim)
  S.eligibilityTimer = S.eligibilityTimer + dtSim
  local tickSec = tonumber(CFG.eligibilityTickSec) or 0.5
  if S.eligibilityTimer < tickSec then return end

  local dt = S.eligibilityTimer
  S.eligibilityTimer = 0

  local now = S.simTime
  local heatRate = tonumber(CFG.heatPerSec) or 0
  S.heat = clamp01((S.heat or 0) + (heatRate * dt))

  local opportunity = computeOpportunityScore()
  local smoothFactor = tonumber(CFG.opportunitySmoothFactor) or 0.15
  S.opportunitySmoothed = clamp01(lerp(S.opportunitySmoothed, opportunity, smoothFactor))

  updateManualRequestStatus(now)

  if S.state ~= STATE.IDLE then return end

  local ok = canStartRobberyNow()
  if not ok then return end

  if S.manualRequest.pending then return end
  if not CFG.autoRobberyEnabled then return end

  if now < (S.cooldownUntilSec or 0) then return end
  if (S.heat or 0) < (tonumber(CFG.heatGateThreshold) or 0) then return end
  if (S.opportunitySmoothed or 0) < (tonumber(CFG.opportunityGateThreshold) or 0) then return end

  local key = pickEligibleMobKey(nil)
  if key then
    triggerEventByKey(key, "Auto trigger")
  end
end

-- Spawn transform (per-mob):
--  - Requires spawnPointsReady(def)
--  - Spawns at mob.spawnBackMeters (robbers: 10m, IntimidatorTruck: 200m)
local function computeMobSpawnTransform()
  if not spawnPointsReady(S.activeMobDef) then
    return nil, nil, "spawn points not ready"
  end
  if not S.activeMobDef then
    return nil, nil, "no mob selected"
  end

  local c = nil
  local req = getSpawnRequirement(S.activeMobDef)
  local reqType = (type(req) == "table") and req.type or "none"
  if reqType == "forward" then
    local ok, availability = isSpawnRequirementAvailable(req)
    if not ok then
      return nil, nil, "no forward crumb"
    end
    c = availability and availability.crumb or nil
  else
    local back = tonumber(S.activeMobDef.spawnBackMeters) or 10.0
    c = getCrumbBack(back)
  end

  if not c or not c.pos or not c.fwd then
    return nil, nil, "no crumb for mob"
  end

  local up = vec3(0,0,1)
  local lift = tonumber(S.activeMobDef.spawnLiftZ) or tonumber(CFG.spawnLift) or 1.0

  local spawnPos = vec3(c.pos.x, c.pos.y, c.pos.z)
  spawnPos.z = spawnPos.z + lift

  local fwd = vec3(c.fwd.x, c.fwd.y, 0)
  if fwd:length() < 0.01 then fwd = vec3(0,1,0) end
  fwd:normalize()

  local dir = S.activeMobDef.faceAwayFromPlayer and (-fwd) or fwd
  local rot = safeQuatFromDir(dir, up, quat(0,0,0,1))
  return spawnPos, rot, nil
end

local function pickRandomFromPool(pool)
  if type(pool) ~= "table" or #pool == 0 then return nil end
  seedRngOnce()
  return pool[math.random(1, #pool)]
end

local function applyScatterImpulse(veh, params)
  if not (veh and isValidVeh(veh)) then return end
  if type(params) ~= "table" then return end

  local radius = tonumber(params.radiusMeters) or 0
  if radius <= 0 then return end

  local strength = params.impulseStrength or "low"
  local strengthMap = { low = 8, medium = 16, high = 28 }
  local magnitude = strengthMap[strength] or tonumber(strength) or 8

  local randomYaw = params.randomYaw == true

  veh:queueLuaCommand(string.format([[if not _G.__bolidesRand then _G.__bolidesRand = {seeded=false} end
if not _G.__bolidesRand.seeded then
  math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
  math.random(); math.random(); math.random()
  _G.__bolidesRand.seeded = true
end
local yaw = %s
local ang = math.rad(yaw)
local dir = vec3(math.cos(ang), math.sin(ang), 0)
local impulse = dir * %0.3f + vec3(0, 0, 1) * (%0.3f * 0.35)
if obj and obj.applyImpulse then
  local p = obj:getPosition() or vec3(0, 0, 0)
  p = p + vec3(0, 0, 0.1)
  pcall(function() obj:applyImpulse(p, impulse) end)
end
]], randomYaw and "math.random() * 360" or "0", magnitude, magnitude))
end

-- =========================
-- Distance helper
-- =========================
local function pickVehicleFromPool(def)
  local pool = def and def.vehiclePool
  if type(pool) ~= "table" or #pool == 0 then
    return def and def.model or nil, def and def.config or nil
  end
  seedRngOnce()
  local entry = pool[math.random(1, #pool)]
  local model = entry.vehicle or entry.model or def.model
  local config = entry.config or def.config
  return model, config
end

local function computeForwardSpawnTransform(def, crumb)
  if not def then return nil, nil, "no definition" end
  if not (crumb and crumb.pos) then return nil, nil, "no forward crumb" end

  local up = vec3(0, 0, 1)
  local lift = tonumber(def.spawnLiftZ) or tonumber(CFG.spawnLift) or 1.0
  local spawnPos = vec3(crumb.pos.x, crumb.pos.y, crumb.pos.z + lift)

  local fwd = crumb.fwd or vec3(0, 1, 0)
  fwd = vec3(fwd.x, fwd.y, 0)
  if fwd:length() < 0.01 then fwd = vec3(0, 1, 0) end
  fwd:normalize()

  local dir = def.faceAwayFromPlayer and (-fwd) or fwd
  local rot = safeQuatFromDir(dir, up, quat(0, 0, 0, 1))
  return spawnPos, rot, nil
end

local function resetForwardFireState()
  S.forwardFireCrumb = nil
  S.forwardFirePhase = nil
  S.forwardFireTimer = 0
  S.forwardFireExplosionTimer = 0
  S.forwardFireSpawnModel = nil
  S.forwardFireSpawnConfig = nil
end

-- =========================
-- Distance helper
-- =========================
local function recomputeDistanceToRobber()
  if not (S.robberVeh and isValidVeh(S.robberVeh)) then return nil end
  local rPos = S.robberVeh:getPosition()
  if not rPos then return nil end

  local p = getPlayerVehicle()
  if p then
    local pPos = p:getPosition()
    if not pPos then return nil end
    return (pPos - rPos):length()
  end

  local aPos = select(1, getPlayerAnchor())
  if not aPos then return nil end
  return (aPos - rPos):length()
end

-- =========================
-- State transitions / cleanup
-- =========================
local function setState(newState)
  S.state = newState
  S.tState = 0
end

local function stopChaseAudioNow()
  local v = getPlayerVehicle()
  if not v then
    S.chaseActive = false
    return
  end
  if S.activeMobDef then
    Audio.ensureSources(v, Mobs.getAudioSources(S.activeMobDef))
    Mobs.stopChaseLoop(Audio, v, S.activeMobDef)
  end
  S.chaseActive = false
end

local function resetAmbientState()
  S.ambientLoopName = nil
  S.ambientLoopVol = 1.0
  S.ambientFadeRemaining = 0
  S.ambientFadeTotal = 0
  S.ambientActive = false
end

local function stopAmbientLoopNow()
  local v = getPlayerVehicle()
  if v and S.ambientLoopName then
    Audio.stopId(v, S.ambientLoopName)
  end
  resetAmbientState()
end

local function beginAmbientFadeOut(fadeSec)
  if not S.ambientActive then return end
  S.ambientFadeRemaining = tonumber(fadeSec) or 0
  S.ambientFadeTotal = S.ambientFadeRemaining
  if S.ambientFadeRemaining <= 0 then
    stopAmbientLoopNow()
  end
end

local function startAmbientLoop(def)
  if not (def and def.audio and def.audio.useAmbientLoop) then
    stopAmbientLoopNow()
    return
  end

  local v = getPlayerVehicle()
  if not v then return end

  S.ambientLoopName = def.audio.ambientName
  S.ambientLoopVol = tonumber(def.audio.ambientVol) or 1.0
  S.ambientFadeRemaining = 0
  S.ambientFadeTotal = 0
  S.ambientActive = true

  Mobs.playAmbientLoop(Audio, v, def)
end

local function stopIntroNow()
  local v = getPlayerVehicle()
  if not v then return end
  Audio.ensureIntro(v)
  Audio.stopId(v, CFG.sfxBolidesIntroName)
end

local function cleanupToIdle()
  -- Hard stop any loop audio
  stopChaseAudioNow()
  stopIntroNow()
  stopAmbientLoopNow()
  S.uiShowInfo = false
  S.uiShowEventLog = false

  stopDumpTruckTraySequence(true)

  if S.robberVeh and isValidVeh(S.robberVeh) then
    pcall(function() S.robberVeh:delete() end)
  end

  S.playerVeh = nil
  S.robberVeh = nil

  S.prewarnTimer = 0
  S.tArmCountdown = 0
  S.ambushArmed = false

  S.spawnSequenceStarted = false
  S.spawnSeqTimer = 0
  S.spawnCommitted = false
  S.footstepsPlayed = false

  S.tSteal, S.tFleeStart = 0, 0
  S.didSteal, S.didStartFlee = false, false

  S.tDisableHold = 0
  S.lastDist = nil
  S.bombTriggered = false
  S.intimidatorCaught = false
  S.bombPhase = nil
  S.intimidatorPhase = nil

  S.tFleeReissue, S.tRobberSlow = 0, 0
  S.limoPhase = nil
  S.limoPhaseTimer = 0
  S.stolenMoney = 0
  S.endMode = nil
  S.obstructionSpawnPos = nil
  S.obstructionSpawnTime = 0
  S.obstructionSuccessTimer = 0
  S.traySeqDidRun = false
  S.traySeqActive = false
  S.traySeqState = nil
  S.traySeqUntil = 0
  resetForwardFireState()

  S.lastReturnedMoney = 0
  S.lastBonusMoney = 0
  S.lastEventLine = ""
  S.lastEventTtl = 0
  S.lastOutcomeLine = ""
  S.eventLog = {}
  S.objectiveTimer = 0
  S.objectiveText = ""

  S.activeMobKey = nil
  S.activeMobDef = nil

  clearManualRequest()
  resetEarningsCycle()
  setState(STATE.IDLE)
end

local function igniteClosestTrafficVehicle()
  local pos = select(1, getPlayerAnchor())
  if not pos then return end

  local excludeId = S.playerVeh and S.playerVeh:getId() or nil
  local trafficVeh = Mobs.findClosestTrafficVehicle(pos, excludeId)
  if trafficVeh and isValidVeh(trafficVeh) then
    Mobs.igniteVehicle(trafficVeh)
    S.trafficFirePending = true
    S.trafficFireTimer = 0
    S.trafficFireVehId = trafficVeh:getId()
  end
end

local function pickRecoveryBonus()
  seedRngOnce()
  local list = CFG.recoveryBonusAmounts or { 20, 500, 1000, 1500, 5000 }
  local idx = math.random(1, #list)
  return tonumber(list[idx]) or 0
end

local function endAsRecovered()
  stopDumpTruckTraySequence(true)
  stopChaseAudioNow()
  beginAmbientFadeOut(2.0)
  playCue("recovered")
  S.objectiveTimer = 0
  S.objectiveText = ""

  S.lastReturnedMoney = tonumber(S.stolenMoney) or 0

  local bonus = pickRecoveryBonus()
  S.lastBonusMoney = tonumber(bonus) or 0

  if (tonumber(S.stolenMoney) or 0) > 0 then
    restoreCareerMoney(S.stolenMoney)
  end

  if bonus > 0 then
    walletAdd(bonus)
    S.ignorePositiveCredit = S.ignorePositiveCredit + bonus
    S.lastMoneySample = getWalletMoney()
  end

  local outcomeText = string.format("Recovered +$%s  Bonus +$%s", fmtMoney(S.lastReturnedMoney), fmtMoney(S.lastBonusMoney))
  postEventLine(outcomeText, 14)
  postOutcomeLine(outcomeText)
  setState(STATE.RECOVERED)
end

local function endAsFailed(reasonText)
  stopDumpTruckTraySequence(true)
  stopChaseAudioNow()
  beginAmbientFadeOut(2.0)
  playCue("failed")
  S.objectiveTimer = 0
  S.objectiveText = ""
  S.endMode = "failed"

  local outcomeText = ""
  if S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
    outcomeText = S.activeMobDef.failureMessage or "Its getting Real Hot"
    postEventLine(outcomeText, S.activeMobDef.outcomeMessageDurationSec or 30.0)
  elseif S.activeMobDef and S.activeMobDef.kind ~= "robber" and S.activeMobDef.failureMessage then
    outcomeText = S.activeMobDef.failureMessage
    postEventLine(outcomeText, S.activeMobDef.outcomeMessageDurationSec or 30.0)
  else
    local why = tostring(reasonText or "")
    if why ~= "" then
      outcomeText = string.format("Escaped with -$%s (%s)", fmtMoney(S.stolenMoney), why)
    else
      outcomeText = string.format("Escaped with -$%s", fmtMoney(S.stolenMoney))
    end
    postEventLine(outcomeText, 14)
  end
  postOutcomeLine(outcomeText)

  setState(STATE.FAILED)
end

local function endAsErrorThenCancel()
  stopDumpTruckTraySequence(true)
  stopChaseAudioNow()
  beginAmbientFadeOut(2.0)
  playCue("failed")
  S.objectiveTimer = 0
  S.objectiveText = ""
  S.endMode = "cancel"

  local errorText = ""
  if S.activeMobDef and S.activeMobDef.errorMessage then
    errorText = S.activeMobDef.errorMessage
    postEventLine(errorText, S.activeMobDef.errorMessageDurationSec or 2.0)
  else
    errorText = "The road ahead is unclear."
    postEventLine(errorText, 2.0)
  end
  postOutcomeLine(errorText)

  if S.activeMobDef and S.activeMobDef.cancelMessage then
    postEventLine(S.activeMobDef.cancelMessage, S.activeMobDef.cancelMessageDurationSec or 1.0)
    postOutcomeLine(S.activeMobDef.cancelMessage)
  end

  setState(STATE.FAILED)
end

local function endAsCancelled()
  stopDumpTruckTraySequence(true)
  stopChaseAudioNow()
  beginAmbientFadeOut(2.0)
  playCue("cancel")
  S.objectiveTimer = 0
  S.objectiveText = ""
  S.endMode = "cancel"

  local outcomeText = ""
  if S.activeMobDef and S.activeMobDef.cancelMessage then
    outcomeText = S.activeMobDef.cancelMessage
    postEventLine(outcomeText, S.activeMobDef.cancelMessageDurationSec or 1.0)
  else
    outcomeText = "Event cleared."
    postEventLine(outcomeText, 1.0)
  end
  postOutcomeLine(outcomeText)

  setState(STATE.FAILED)
end

local function endAsCaughtIntimidator()
  stopDumpTruckTraySequence(true)
  stopChaseAudioNow()
  beginAmbientFadeOut(2.0)
  playCue("failed")
  S.objectiveTimer = 0
  S.objectiveText = ""
  S.endMode = "failed"
  S.intimidatorCaught = true
  local outcomeText = "Caught by the intimidator."
  if S.activeMobDef and S.activeMobDef.failureMessage then
    outcomeText = S.activeMobDef.failureMessage
    postEventLine(outcomeText, S.activeMobDef.outcomeMessageDurationSec or 30.0)
  else
    postEventLine(outcomeText, 12)
  end
  postOutcomeLine(outcomeText)
  setState(STATE.FAILED)
end

local function endAsShookOff()
  stopDumpTruckTraySequence(true)
  stopChaseAudioNow()
  beginAmbientFadeOut(2.0)
  playCue("recovered")
  S.lastReturnedMoney = 0
  S.lastBonusMoney = 0
  S.objectiveTimer = 0
  S.objectiveText = ""
  local outcomeText = ""
  if S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
    outcomeText = S.activeMobDef.successMessage or "You made it"
    postEventLine(outcomeText, S.activeMobDef.outcomeMessageDurationSec or 30.0)
  elseif S.activeMobDef and S.activeMobDef.successMessage then
    outcomeText = S.activeMobDef.successMessage
    postEventLine(outcomeText, S.activeMobDef.outcomeMessageDurationSec or 30.0)
  else
    outcomeText = "You shook them off."
    postEventLine(outcomeText, 12)
  end
  postOutcomeLine(outcomeText)
  setState(STATE.RECOVERED)
end

-- =========================
-- Begin ambush (select mob)
-- =========================
local function selectActiveMob()
  local key = Mobs.pickNext(S.lastMobKey, S.forcedNextMobKey)
  if not key or not Mobs.getByKey(key) then key = "robber_light" end

  S.activeMobKey = key
  S.activeMobDef = Mobs.getByKey(key)
  S.forcedNextMobKey = nil
  S.lastMobKey = key
end

local function beginAmbush()
  if S.state ~= STATE.IDLE and S.state ~= STATE.PREWARN then return end

  local ok = canStartRobberyNow()
  if not ok then
    cleanupToIdle()
    return
  end

  selectActiveMob()

  S.playerVeh = getPlayerVehicle()
  if S.playerVeh then
    Audio.ensureIntro(S.playerVeh)
    if S.activeMobDef then
      Audio.ensureSources(S.playerVeh, Mobs.getAudioSources(S.activeMobDef))
    end
  end

  S.objectiveTimer = 0
  S.objectiveText = ""
  if S.activeMobDef and S.activeMobDef.startMessage then
    postEventLine(S.activeMobDef.startMessage, S.activeMobDef.startMessageDurationSec or 10.0)
    if S.activeMobDef.objectiveText then
      S.objectiveText = S.activeMobDef.objectiveText
      S.objectiveTimer = S.activeMobDef.startMessageDurationSec or 10.0
    end
  elseif S.activeMobDef and S.activeMobDef.objectiveText then
    S.objectiveText = S.activeMobDef.objectiveText
    postEventLine(S.objectiveText, 999999)
  end

  playCue("start")
  if S.playerVeh then
    Mobs.playWarning(Audio, S.playerVeh, S.activeMobDef)
    startAmbientLoop(S.activeMobDef)
    if S.activeMobDef and S.activeMobDef.startAudioFile and S.activeMobDef.startAudioName then
      Audio.ensureSources(S.playerVeh, {
        { file = S.activeMobDef.startAudioFile, name = S.activeMobDef.startAudioName }
      })
      Audio.playId(
        S.playerVeh,
        S.activeMobDef.startAudioName,
        S.activeMobDef.startAudioVol,
        S.activeMobDef.startAudioPitch
      )
    end
  end

  if isForwardFireEvent(S.activeMobDef) then
    resetForwardFireState()
    local req = getSpawnRequirement(S.activeMobDef)
    local reqType = (type(req) == "table") and req.type or "none"
    local crumb = nil
    if reqType == "forward" then
      crumb = getForwardKnownBreadcrumb(req.spacing, req.minAhead, req.maxAhead, FKB_CONE_DEG)
    end
    if not crumb then
      postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
      cleanupToIdle()
      return
    end
    S.forwardFireCrumb = crumb
    S.forwardFirePhase = "armed"
    S.forwardFireTimer = 0
    S.forwardFireExplosionTimer = 0
    S.forwardFireSpawnModel, S.forwardFireSpawnConfig = pickVehicleFromPool(S.activeMobDef)
  end

  if S.activeMobDef and S.activeMobDef.kind == "traffic_fire" and not isForwardFireEvent(S.activeMobDef) then
    igniteClosestTrafficVehicle()
    cleanupToIdle()
    return
  end

  S.robberVeh = nil

  S.tArmCountdown = 0
  S.ambushArmed = false

  S.spawnSequenceStarted = false
  S.spawnSeqTimer = 0
  S.spawnCommitted = false
  S.footstepsPlayed = false

  S.tSteal, S.tFleeStart = 0, 0
  S.didSteal, S.didStartFlee = false, false

  S.tDisableHold = 0
  S.lastDist = nil

  S.tFleeReissue, S.tRobberSlow = 0, 0
  S.stolenMoney = 0

  if S.activeMobDef and S.activeMobDef.kind == "ambient_obstruction" then
    S.obstructionSpawnPos = nil
    S.obstructionSpawnTime = 0
    S.obstructionSuccessTimer = 0
  end
  S.endMode = nil

  S.lastReturnedMoney = 0
  S.lastBonusMoney = 0

  S.limoPhase = nil
  S.limoPhaseTimer = 0
  S.bombPhase = nil

  S.chaseActive = false

  setEventTriggered(S.simTime)
  setState(STATE.AMBUSH)
  S.lastMoneySample = getWalletMoney()
end

-- =========================
-- Earnings + auto-robbery trigger (RANDOM TARGET)
-- =========================
local function updateEarningsAndAutoRobbery(dtSim)
  ensureEarningsTarget()

  forwardKnownCheckTimer = forwardKnownCheckTimer + dtSim
  if forwardKnownCheckTimer >= (CFG.forwardKnownCheckIntervalSec or 0.35) then
    forwardKnownCheckTimer = 0
    updateForwardKnownAvailabilityCache()
  end

  local money = getWalletMoney()
  if S.lastMoneySample == nil then
    S.lastMoneySample = money
    return
  end

  local delta = money - S.lastMoneySample
  S.lastMoneySample = money

  if delta > 0 then
    if S.ignorePositiveCredit > 0 then
      local used = math.min(S.ignorePositiveCredit, delta)
      S.ignorePositiveCredit = S.ignorePositiveCredit - used
      delta = delta - used
    end
    if delta > 0 then
      S.earningsSinceRobbery = S.earningsSinceRobbery + delta
    end
  end
end

-- =========================
-- On-screen UI (ImGui)
-- =========================
local function drawUI()
  if not CFG.showImGuiWindow then return end
  if M.showWindow ~= true then return end

  local imgui = ui_imgui
  if not imgui then return end

  ensureEarningsTarget()

  imgui.SetNextWindowPos(imgui.ImVec2(20, 120), imgui.Cond_Once)
  imgui.SetNextWindowSize(imgui.ImVec2(460, 640), imgui.Cond_Once)

  local flags =
    imgui.WindowFlags_NoCollapse +
    imgui.WindowFlags_NoSavedSettings

  imgui.Begin("Bolides - The Cut", nil, flags)

  imgui.Text("By Mad Merick")
  imgui.Separator()

  local threshold = (S.currentEarningsTarget or 5000)
  local pct = (S.earningsSinceRobbery / math.max(1, threshold))
  local pressure = clamp01(S.heat or 0)

  local status = "Calm"
  if S.state == STATE.PREWARN then status = "Watching"
  elseif S.state == STATE.AMBUSH and S.ambushArmed and not (S.robberVeh and isValidVeh(S.robberVeh)) then status = "Imminent"
  elseif S.state == STATE.AMBUSH and S.didSteal then status = "Robbery"
  elseif S.state == STATE.FLEE then status = "Chase"
  elseif S.state == STATE.RECOVERED then status = "Recovered"
  elseif S.state == STATE.FAILED then status = "Lost"
  end

  imgui.Text(string.format("Status: %s", status))

  if S.activeMobDef and S.state ~= STATE.IDLE then
    imgui.Text(string.format("Mob: %s", tostring(S.activeMobDef.label or S.activeMobKey or "Unknown")))
  end
  if S.lastHardError and S.lastHardError ~= "" then
    uiTextWrapped(imgui, string.format("Last hard error: %s", tostring(S.lastHardError)))
  end

  imgui.Separator()
  imgui.Text(string.format("Pressure: %d%%", math.floor((pressure * 100) + 0.5)))
  if imgui.ProgressBar then
    imgui.ProgressBar(pressure, imgui.ImVec2(-1, 0))
  end

  local hintText = ""
  if S.state == STATE.IDLE then
    if pct >= 0.85 then
      hintText = "This road feels wrong…"
    elseif pct >= 0.60 then
      hintText = "You feel watched."
    else
      hintText = "Stay alert."
    end
  elseif S.state == STATE.PREWARN then
    hintText = "Interest rising."
  elseif S.state == STATE.AMBUSH then
    hintText = "Ambush imminent."
  elseif S.state == STATE.FLEE then
    hintText = "Chase active."
  elseif S.state == STATE.RECOVERED then
    hintText = "Recovered."
  elseif S.state == STATE.FAILED then
    hintText = "Lost."
  end
  if hintText ~= "" then
    imgui.Text(string.format("Hint: %s", hintText))
  end

  local audioLabel = CFG.audioEnabled and "Audio: ON" or "Audio: OFF"
  if imgui.Button(audioLabel, imgui.ImVec2(-1, 0)) then
    local wasEnabled = CFG.audioEnabled
    CFG.audioEnabled = not CFG.audioEnabled
    if wasEnabled and not CFG.audioEnabled then
      stopChaseAudioNow()
      stopAmbientLoopNow()
      local v = getPlayerVehicle()
      if v then
        Audio.stopId(v, CFG.sfxBolidesIntroName)
      end
    end
  end
  if not CFG.audioEnabled then
    imgui.Text("Audio disabled—cues reduced.")
  end

  imgui.Separator()
  imgui.Text(string.format("Crumb keep: %.0f m", TRAVEL.keepMeters or 0))
  imgui.Text(string.format("Crumbs: %d", #travelCrumbs))
  imgui.Text(string.format("Forward dist: %.0f m", travelTotalForward or 0))
  imgui.Text("ForwardKnownBreadcrumbs:")
  local segText = forwardKnownAvailabilityMeta.segStartIdx and tostring(forwardKnownAvailabilityMeta.segStartIdx) or "n/a"
  local dirText = forwardKnownAvailabilityMeta.dir and tostring(forwardKnownAvailabilityMeta.dir) or "n/a"
  local distText = forwardKnownAvailabilityMeta.distToProjection and string.format("%.2f m", forwardKnownAvailabilityMeta.distToProjection) or "n/a"
  imgui.Text(string.format("Anchor segStartIdx: %s", segText))
  imgui.Text(string.format("Anchor dir: %s, distToProjection: %s", dirText, distText))
  for i = 1, #FORWARD_DEBUG_SPACINGS do
    local spacing = FORWARD_DEBUG_SPACINGS[i]
    local availability = forwardKnownAvailabilityCache[spacing] or {}
    local status = availability.available and "Available" or "Not"
    local distText = availability.available and string.format("%.0f m", availability.distAhead or -1) or "-"
    local dir = availability.dir and tostring(availability.dir) or "n/a"
    imgui.Text(string.format("%dm: %s, dist ahead: %s, dir: %s", spacing, status, distText, dir))
  end

  imgui.Text("Back breadcrumbs ready:")
  for i = 1, #BACK_BREADCRUMB_METERS do
    local backMeters = BACK_BREADCRUMB_METERS[i]
    local ready = isBackBreadcrumbReady(backMeters)
    imgui.Text(string.format("%dm back ready: %s", backMeters, ready and "yes" or "no"))
  end

  local debugLabel = CFG.debugBreadcrumbMarkers and "Debug Breadcrumb Markers: ON" or "Debug Breadcrumb Markers: OFF"
  if imgui.Button(debugLabel, imgui.ImVec2(-1, 0)) then
    CFG.debugBreadcrumbMarkers = not CFG.debugBreadcrumbMarkers
  end

  local fkb300 = forwardKnownAvailabilityCache[300] or {}
  local hasLastGood = fkb300.lastGoodPos ~= nil
  local hasDebugVeh = false
  if S.testDumpTruckVehId then
    local v = be:getObjectByID(S.testDumpTruckVehId)
    hasDebugVeh = v and isValidVeh(v)
  end
  imgui.Text(string.format("FKB 300 lastGood: %s | Test truck: %s", hasLastGood and "Yes" or "No", hasDebugVeh and "Yes" or "No"))
  if S.testDumpTruckStatus and S.testDumpTruckStatus ~= "" then
    imgui.Text(S.testDumpTruckStatus)
  end
  if imgui.Button("BigDumpTruckSimple", imgui.ImVec2(-1, 0)) then
    spawnDebugDumptruckSimple()
  end

  if S.manualRequest.pending then
    local age = math.max(0, S.simTime - (S.manualRequest.requestedAtSec or 0))
    imgui.Text(string.format("Manual Pending: %s (%.0fs)", tostring(S.manualRequest.eventKey or "none"), age))
    if S.manualRequest.required and S.manualRequest.required ~= "" then
      imgui.Text(string.format("Missing: %s", S.manualRequest.required))
    end
  end

  -- About button: play intro HIT once when opening, STOP when hiding
  local wasInfo = S.uiShowInfo
  if imgui.Button(S.uiShowInfo and "Hide Info" or "About", imgui.ImVec2(-1, 0)) then
    S.uiShowInfo = not S.uiShowInfo

    local v = getPlayerVehicle()
    if v then Audio.ensureIntro(v) end

    if S.uiShowInfo and not wasInfo then
      if v then
        Audio.playId(v, CFG.sfxBolidesIntroName, CFG.bolidesIntroVol, CFG.bolidesIntroPitch)
      end
    end

    if (not S.uiShowInfo) and wasInfo then
      if v then
        Audio.stopId(v, CFG.sfxBolidesIntroName)
      end
    end
  end

  if imgui.Button(S.uiShowEventLog and "Hide Event Log" or "Event Log", imgui.ImVec2(-1, 0)) then
    S.uiShowEventLog = not S.uiShowEventLog
  end

  if S.uiShowEventLog then
    imgui.Separator()
    if #S.eventLog == 0 then
      uiTextWrapped(imgui, "All is well")
    else
      for i = #S.eventLog, math.max(#S.eventLog - 2, 1), -1 do
        uiTextWrapped(imgui, S.eventLog[i])
      end
    end
  end

  if S.uiShowInfo then
    imgui.Separator()

    if imgui.PushTextWrapPos then imgui.PushTextWrapPos(0) end

    uiTextWrapped(imgui, "Bolides: The Cut is a crime-family mod for BeamNG Career.")
    uiTextWrapped(imgui, "")
    uiTextWrapped(imgui, "The Bolides are led by Benito Bolide, operating out of West Coast with chapters in Utah and Italy. They dont care where you are, if you are building a name, they are watching.")
    uiTextWrapped(imgui, "")
    uiTextWrapped(imgui, "As your career income climbs, The Cut tightens.")
    uiTextWrapped(imgui, "Sometimes its a robbery.")
    uiTextWrapped(imgui, "Sometimes its intimidation.")
    uiTextWrapped(imgui, "Either way, they want their share.")

    if imgui.PopTextWrapPos then imgui.PopTextWrapPos() end
  end

  if imgui.Button("Reload Mod", imgui.ImVec2(-1, 0)) then
    if extensions and extensions.reload then
      extensions.reload("bolidesTheCut")
    end
  end

  imgui.Separator()
  local money = getWalletMoney()
  imgui.Text(string.format("Wallet: $%s", fmtMoney(money)))

  local showStolen = (S.state == STATE.AMBUSH and S.didSteal) or (S.state == STATE.FLEE) or (S.state == STATE.FAILED)
  if showStolen and (tonumber(S.stolenMoney) or 0) > 0 then
    imgui.Text(string.format("Stolen: $%s", fmtMoney(S.stolenMoney)))
  end

  if (S.state == STATE.RECOVERED) or (S.lastReturnedMoney > 0) or (S.lastBonusMoney > 0) then
    if (tonumber(S.lastReturnedMoney) or 0) > 0 then
      imgui.Text(string.format("Returned: $%s", fmtMoney(S.lastReturnedMoney)))
    end
    if (tonumber(S.lastBonusMoney) or 0) > 0 then
      imgui.Text(string.format("Bonus: $%s", fmtMoney(S.lastBonusMoney)))
    end
  end

  imgui.Separator()

  if S.state == STATE.IDLE then
    imgui.Text(string.format("Heat: $%s / $%s", fmtMoney(S.earningsSinceRobbery), fmtMoney(threshold)))
    if pct >= 0.85 then
      imgui.Text("This road feels wrong…")
    elseif pct >= 0.60 then
      imgui.Text("You feel watched.")
    else
      imgui.Text("Stay alert.")
    end
  elseif S.state == STATE.PREWARN then
    local left = math.max(0, (CFG.autoRobberyWarningSec or 30.0) - S.prewarnTimer)
    imgui.Text(string.format("They are moving… (%s)", fmtTimeMMSS(left)))
  elseif S.state == STATE.AMBUSH then
    if not S.ambushArmed then
      imgui.Text("Something is about to happen…")
    else
      if not (S.robberVeh and isValidVeh(S.robberVeh)) then
        imgui.Text(string.format("Spawn triggers when you slow to %.0f km/h or less.", (CFG.spawnOnlyIfPlayerUnderKph or 5.0)))

        if not spawnPointsReady(S.activeMobDef) then
          local backMeters = S.activeMobDef and tonumber(S.activeMobDef.spawnBackMeters) or 0
          local haveBack = (backMeters > 0) and isBackBreadcrumbReady(backMeters) or true
          imgui.Text(string.format("Spawn not ready: %.0f m back breadcrumb needed", backMeters))
          imgui.Text(string.format("Back %.0fm: %s", backMeters, haveBack and "OK" or "NO"))
        end

        if S.spawnSequenceStarted and S.activeMobDef and S.activeMobDef.kind == "robber" then
          imgui.Text("Footsteps close in.")
        end
      else
        if S.activeMobDef and S.activeMobDef.kind == "intimidator" then
          imgui.Text("Truck is tailing you.")
        elseif S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
          imgui.Text("Bomb car is closing in.")
        else
          if not S.didSteal then
            imgui.Text("They’re at your door.")
          else
            local fleeIn = math.max(0, (CFG.fleeStartDelaySec or 1.0) - S.tFleeStart)
            imgui.Text(string.format("Robber fleeing in: %.1fs", fleeIn))
          end
        end
      end
    end
  elseif S.state == STATE.FLEE then
    imgui.Text("Chase Active")
    if S.lastDist then imgui.Text(string.format("Distance: %.0f m", S.lastDist)) end
    local toEscape = math.max(0, (CFG.getawayDistMeters or 1000.0) - (S.lastDist or 0))
    imgui.Text(string.format("Escape gap: %.0f m", toEscape))

  if S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
      local igniteDist = tonumber(S.activeMobDef.igniteDist) or 30.0
      if S.lastDist then
        imgui.Text(string.format("Ignites at: %.0f m", igniteDist))
      end
    end

    if S.activeMobDef and S.activeMobDef.kind == "robber" then
      if S.tDisableHold > 0 then
        imgui.Text(string.format("Stopping… %.1f / %.1f s", S.tDisableHold, (CFG.disableHoldSec or 5.0)))
      end
    end
  elseif S.state == STATE.RECOVERED then
    imgui.Text("Resolved.")
  elseif S.state == STATE.FAILED then
    if S.activeMobDef and S.activeMobDef.failureMessage then
      imgui.Text(S.activeMobDef.failureMessage)
    elseif S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
      imgui.Text(S.activeMobDef.failureMessage or "Its getting Real Hot")
    else
      imgui.Text("Chase failed.")
    end
  end

  imgui.Separator()
  imgui.Text("Recent events:")
  if #S.eventLog == 0 then
    imgui.Text("  (none)")
  else
    for i = #S.eventLog, math.max(#S.eventLog - 2, 1), -1 do
      uiTextWrapped(imgui, string.format("  • %s", S.eventLog[i]))
    end
  end
  if (tonumber(S.lastBonusMoney) or 0) > 0 and S.state == STATE.RECOVERED then
    imgui.Text("Fail-safe: Recovery bonus applied.")
  end

  imgui.Separator()

  if S.state == STATE.IDLE then
    if imgui.Button("Start (Test Random Mob)", imgui.ImVec2(-1, 30)) then
      M.startChase()
    end

    imgui.Separator()
    imgui.Text("Manual event trigger")
    for _, key in ipairs(mobOrder) do
      local def = Mobs.getByKey(key)
      if def then
        if imgui.Button(string.format("Request %s", def.label), imgui.ImVec2(-1, 0)) then
          requestManualEvent(def.key)
        end
      end
    end

    if S.manualRequest.statusMsg and S.manualRequest.statusMsg ~= "" then
      uiTextWrapped(imgui, S.manualRequest.statusMsg)
    end
  else
    if imgui.Button("End", imgui.ImVec2(-1, 30)) then
      M.cancelChase()
    end
  end

  imgui.Separator()
  if imgui.Button("EndEvent", imgui.ImVec2(-1, 0)) then
    endDebugSpawnVehicle()
  end

  imgui.End()
end

local function drawBreadcrumbDebugMarkers()
  if not CFG.debugBreadcrumbMarkers then return end
  local dd = debugDrawer
  if not dd then return end

  for i = 1, #FORWARD_DEBUG_SPACINGS do
    local spacing = FORWARD_DEBUG_SPACINGS[i]
    local availability = forwardKnownAvailabilityCache[spacing]
    if availability and availability.available and availability.pos then
      local pos = availability.pos
      dd:drawSphere(pos, 1.5, DEBUG_FWD_COLOR)
      dd:drawText(pos + DEBUG_LABEL_OFFSET, string.format("F%d available", spacing), DEBUG_TEXT_COLOR)
    end
  end

  if S and S.backCrumbPos then
    for i = 1, #BACK_BREADCRUMB_METERS do
      local backMeters = BACK_BREADCRUMB_METERS[i]
      if isBackBreadcrumbReady(backMeters) then
        local pos = S.backCrumbPos[backMeters]
        if pos then
          dd:drawSphere(pos, 1.5, DEBUG_BACK_COLOR)
          dd:drawText(pos + DEBUG_LABEL_OFFSET, string.format("B%d ready", backMeters), DEBUG_TEXT_COLOR)
        end
      end
    end
  end
end

function M.onDrawDebug()
  -- onDrawDebug can run during loading/menus too.
  -- Do NOTHING until the player vehicle exists (level is live).
  local pv = getPlayerVehicle()
  if not pv then return end

  -- Protect UI draw
  pcall(drawUI)

  -- Protect debug markers, and keep behind the flag
  if CFG.debugBreadcrumbMarkers then
    pcall(drawBreadcrumbDebugMarkers)
  end
end

function M.setWindowVisible(v)
  M.showWindow = (v == true)
  if not M.showWindow then
    -- If they hide the whole window while info is open, stop the intro too
    stopIntroNow()
    S.uiShowInfo = false
    S.uiShowEventLog = false
  end
end

CTX.F = {
  getPlayerVehicle = getPlayerVehicle,
  isValidVeh = isValidVeh,
  vehSpeed = vehSpeed,
  isForwardFireEvent = isForwardFireEvent,
  isCareerActive = isCareerActive,
  isPausedOrMenu = isPausedOrMenu,
  postEventLine = postEventLine,
  postOutcomeLine = postOutcomeLine,
  cleanupToIdle = cleanupToIdle,
  getPlayerAnchor = getPlayerAnchor,
  getSpawnRequirement = getSpawnRequirement,
  computeForwardSpawnTransform = computeForwardSpawnTransform,
  pickVehicleFromPool = pickVehicleFromPool,
  pickRandomFromPool = pickRandomFromPool,
  forceEngineOff = forceEngineOff,
  forceEngineOn = forceEngineOn,
  setState = setState,
  spawnPointsReady = spawnPointsReady,
  isSpawnRequirementAvailable = isSpawnRequirementAvailable,
  getForwardCommitDistance = getForwardCommitDistance,
  kphToMps = kphToMps,
  computeMobSpawnTransform = computeMobSpawnTransform,
  endAsErrorThenCancel = endAsErrorThenCancel,
  endAsFailed = endAsFailed,
  applyAiCommands = applyAiCommands,
  applyScatterImpulse = applyScatterImpulse,
  recomputeDistanceToRobber = recomputeDistanceToRobber,
  computeRobberyAmountFromWallet = computeRobberyAmountFromWallet,
  stealCareerMoney = stealCareerMoney,
  getWalletMoney = getWalletMoney,
  fmtMoney = fmtMoney,
  playCue = playCue,
  Mobs = Mobs,
  Audio = Audio,
}

-- =========================
-- Common update (last event ttl)
-- =========================
local function updateCommon(dtSim)
  if S.trafficFirePending then
    S.trafficFireTimer = S.trafficFireTimer + dtSim
    if S.trafficFireTimer >= 10.0 then
      local veh = S.trafficFireVehId and be:getObjectByID(S.trafficFireVehId) or nil
      if veh and isValidVeh(veh) then
        Mobs.applyExplosionImpulse(veh, 30)
      end
      S.trafficFirePending = false
      S.trafficFireVehId = nil
      S.trafficFireTimer = 0
    end
  end

  if S.lastEventTtl > 0 then
    S.lastEventTtl = math.max(0, S.lastEventTtl - dtSim)
    if S.lastEventTtl == 0 then
      S.lastEventLine = ""
    end
  end

  if S.objectiveTimer > 0 then
    S.objectiveTimer = math.max(0, S.objectiveTimer - dtSim)
    if S.objectiveTimer == 0 and S.objectiveText ~= "" then
      local objectiveTtl = 999999
      if S.activeMobDef and S.activeMobDef.objectiveMessageDurationSec then
        objectiveTtl = tonumber(S.activeMobDef.objectiveMessageDurationSec) or objectiveTtl
      end
      postEventLine(S.objectiveText, objectiveTtl)
    end
  end

  if S.ambientFadeRemaining > 0 and S.ambientLoopName then
    S.ambientFadeRemaining = math.max(0, S.ambientFadeRemaining - dtSim)
    local v = getPlayerVehicle()
    if v then
      local ratio = (S.ambientFadeTotal > 0) and (S.ambientFadeRemaining / S.ambientFadeTotal) or 0
      Audio.setVol(v, S.ambientLoopName, S.ambientLoopVol * ratio)
      if S.ambientFadeRemaining == 0 then
        Audio.stopId(v, S.ambientLoopName)
        resetAmbientState()
      end
    else
      resetAmbientState()
    end
  end
end

-- =========================
-- State updates
-- =========================
local function updatePREWARN(dtSim)
  local ok = canStartRobberyNow()
  if not ok then
    setState(STATE.IDLE)
    S.prewarnTimer = 0
    return
  end

  S.prewarnTimer = S.prewarnTimer + dtSim
  if S.prewarnTimer >= (CFG.autoRobberyWarningSec or 30.0) then
    beginAmbush()
  end
end

local function updateAMBUSH(ctx, dtSim)
  local S = ctx.S
  local F = ctx.F
  local CFG = ctx.CFG
  local STATE = ctx.STATE
  local Mobs = F.Mobs
  local Audio = F.Audio

  S.playerVeh = F.getPlayerVehicle()
  S.playerVeh = S.playerVeh
  S.activeMobDef = S.activeMobDef

  if not S.ambushArmed then
    S.tArmCountdown = S.tArmCountdown + dtSim
    if S.tArmCountdown >= (CFG.stealDelaySec or 1.0) then
      S.ambushArmed = true
      F.playCue("armed")
    end
    return
  end

  if F.isForwardFireEvent(S.activeMobDef) then
    S.forwardFireTimer = S.forwardFireTimer + dtSim

    if not F.isCareerActive() or F.isPausedOrMenu() then
      if S.activeMobDef.cancelMessage then
        F.postEventLine(S.activeMobDef.cancelMessage, S.activeMobDef.cancelMessageDurationSec or 2.0)
      end
      F.cleanupToIdle()
      return
    end

    local timeoutSec = tonumber(S.activeMobDef.timeoutSec) or 0
    if timeoutSec > 0 and S.forwardFireTimer >= timeoutSec then
      if S.activeMobDef.cancelMessage then
        F.postEventLine(S.activeMobDef.cancelMessage, S.activeMobDef.cancelMessageDurationSec or 2.0)
      end
      F.cleanupToIdle()
      return
    end

    if not (S.forwardFireCrumb and S.forwardFireCrumb.pos) then
      F.postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
      F.cleanupToIdle()
      return
    end

    local playerPos, playerFwd = F.getPlayerAnchor()
    if not (playerPos and playerFwd) then
      if S.activeMobDef.cancelMessage then
        F.postEventLine(S.activeMobDef.cancelMessage, S.activeMobDef.cancelMessageDurationSec or 2.0)
      end
      F.cleanupToIdle()
      return
    end

    local req = F.getSpawnRequirement(S.activeMobDef)
    local commitRadius = tonumber(req and req.commitRadius) or tonumber(S.activeMobDef.igniteDistanceMeters) or 50.0
    local distToCrumb = (playerPos - S.forwardFireCrumb.pos):length()

    if not (S.robberVeh and F.isValidVeh(S.robberVeh)) then
      if S.forwardFirePhase == "armed" and distToCrumb <= commitRadius then
        local spacing = tonumber(req and req.spacing) or 0
        if spacing > 0 then
          updateForwardKnownAvailabilityCache()
          local entry = forwardKnownAvailabilityCache[spacing]
          if entry and entry.available and entry.pos then
            if not isPosAheadOfPlayer(playerPos, playerFwd, entry.pos, FKB_CONE_DEG) then
              F.postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
              F.cleanupToIdle()
              return
            end
            if entry.crumb then
              S.forwardFireCrumb = entry.crumb
            end
          end
        end
        if S.forwardFireCrumb and S.forwardFireCrumb.pos then
          if not isPosAheadOfPlayer(playerPos, playerFwd, S.forwardFireCrumb.pos, FKB_CONE_DEG) then
            F.postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
            F.cleanupToIdle()
            return
          end
        end

        local sp, sr = F.computeForwardSpawnTransform(S.activeMobDef, S.forwardFireCrumb)
        if not sp or not sr then
          F.postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
          F.cleanupToIdle()
          return
        end

        local model = S.forwardFireSpawnModel
        local config = S.forwardFireSpawnConfig
        if not model or not config then
          model, config = F.pickVehicleFromPool(S.activeMobDef)
        end

        S.robberVeh = Mobs.spawn({ model = model, config = config }, sp, sr)
        if not (S.robberVeh and F.isValidVeh(S.robberVeh)) then
          F.postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
          F.cleanupToIdle()
          return
        end

        if S.activeMobDef.engineRunning == false then
          F.forceEngineOff(S.robberVeh)
        else
          F.forceEngineOn(S.robberVeh)
        end

        Mobs.igniteVehicle(S.robberVeh)
        if S.activeMobDef.escalateMessage then
          F.postEventLine(S.activeMobDef.escalateMessage, S.activeMobDef.escalateMessageDurationSec or 3.0)
        end
        S.forwardFirePhase = "ignition"
        S.forwardFireExplosionTimer = 0
      end
    end

    if S.forwardFirePhase == "ignition" then
      if not (S.robberVeh and F.isValidVeh(S.robberVeh)) then
        F.postEventLine(S.activeMobDef.errorMessage or "Event aborted — invalid spawn.", S.activeMobDef.errorMessageDurationSec or 3.0)
        F.cleanupToIdle()
        return
      end

      S.forwardFireExplosionTimer = S.forwardFireExplosionTimer + dtSim
      local delaySec = tonumber(S.activeMobDef.explosionDelaySec) or 2.5
      if S.forwardFireExplosionTimer >= delaySec then
        Mobs.detonateBomb(S.robberVeh)
        if S.activeMobDef.explosionImpulseStrength then
          Mobs.applyExplosionImpulse(S.robberVeh, S.activeMobDef.explosionImpulseStrength)
        end

        local currentPlayerVeh = F.getPlayerVehicle()
        if not (currentPlayerVeh and F.isValidVeh(currentPlayerVeh)) then
          F.endAsFailed()
          return
        end

        if S.activeMobDef.successMessage then
          F.postEventLine(S.activeMobDef.successMessage, S.activeMobDef.outcomeMessageDurationSec or 4.0)
        end
        F.setState(STATE.RECOVERED)
      end
    end
    return
  end

  if not (S.robberVeh and F.isValidVeh(S.robberVeh)) then
    local pSpeed = S.playerVeh and F.vehSpeed(S.playerVeh) or 0
    local spawnSeq = S.activeMobDef and S.activeMobDef.spawnSequence or nil
    local speedGateKph = CFG.spawnOnlyIfPlayerUnderKph or 5.0
    if spawnSeq then
      if spawnSeq.cancelIfSpeedExceedsKphBeforeCommit ~= nil then
        speedGateKph = spawnSeq.cancelIfSpeedExceedsKphBeforeCommit
      else
        speedGateKph = nil
      end
    end
    local spawnMpsLimit = speedGateKph and F.kphToMps(speedGateKph) or nil

    local totalWait = (spawnSeq and tonumber(spawnSeq.totalWaitSec)) or 2.0
    local footstepsLead = 2.0
    local commitAt = math.max(0.0, totalWait - footstepsLead) -- 0
    if spawnSeq and spawnSeq.commitAtSec ~= nil then
      commitAt = tonumber(spawnSeq.commitAtSec) or 0.0
    end

    if not S.spawnSequenceStarted then
      if not F.spawnPointsReady(S.activeMobDef) then return end
      local req = F.getSpawnRequirement(S.activeMobDef)
      local reqType = (type(req) == "table") and req.type or "none"
      if reqType == "forward" then
        local ok, availability = F.isSpawnRequirementAvailable(req)
        if not ok then return end
        local commitRadius = tonumber(req.commitRadius) or 0
        if commitRadius > 0 then
          local dist = F.getForwardCommitDistance(req, availability)
          if not dist or dist > commitRadius then
            return
          end
        end
      end
      if (not spawnMpsLimit) or pSpeed <= spawnMpsLimit then
        S.spawnSequenceStarted = true
        S.spawnSeqTimer = 0
        S.spawnCommitted = false
        S.footstepsPlayed = false
      else
        return
      end
    end

    -- if the player speeds up before commit, cancel sequence
    if S.spawnSequenceStarted and (not S.spawnCommitted) and spawnMpsLimit and pSpeed > spawnMpsLimit then
      S.spawnSequenceStarted = false
      S.spawnSeqTimer = 0
      S.spawnCommitted = false
      S.footstepsPlayed = false
      return
    end

    S.spawnSeqTimer = S.spawnSeqTimer + dtSim

    -- SAFETY: if travel got reset (teleport etc), abort sequence cleanly
    if not F.spawnPointsReady(S.activeMobDef) then
      S.spawnSequenceStarted = false
      S.spawnSeqTimer = 0
      S.spawnCommitted = false
      S.footstepsPlayed = false
      return
    end

    -- FOOTSTEPS ONLY for robber mobs (not intimidator)
    if (not S.footstepsPlayed) and S.spawnSeqTimer >= commitAt then
      S.spawnCommitted = true
      if S.playerVeh and S.activeMobDef and S.activeMobDef.kind == "robber" then
        Audio.ensureSources(S.playerVeh, Mobs.getAudioSources(S.activeMobDef))
        Mobs.playFootsteps(Audio, S.playerVeh, S.activeMobDef)
      end
      S.footstepsPlayed = true
    end

    if S.spawnSeqTimer >= totalWait then
      local spawnDef = S.activeMobDef
      if S.activeMobDef and type(S.activeMobDef.randomSelectionPool) == "table" and #S.activeMobDef.randomSelectionPool > 0 then
        local pick = F.pickRandomFromPool(S.activeMobDef.randomSelectionPool)
        if pick and pick.vehicle then
          spawnDef = {
            model = pick.vehicle,
            config = pick.config,
            spawnBackMeters = S.activeMobDef.spawnBackMeters,
            faceAwayFromPlayer = S.activeMobDef.faceAwayFromPlayer,
            engineRunning = S.activeMobDef.engineRunning,
            spawnLiftZ = S.activeMobDef.spawnLiftZ,
          }
        end
      end

      local sp, sr = F.computeMobSpawnTransform()
      if not sp or not sr then
        if S.activeMobDef and (S.activeMobDef.kind == "ambient_obstruction" or S.activeMobDef.useErrorOnSpawnFail) then
          F.endAsErrorThenCancel()
          return
        end
        S.spawnSequenceStarted = false
        S.spawnSeqTimer = 0
        S.spawnCommitted = false
        S.footstepsPlayed = false
        return
      end

      S.robberVeh = Mobs.spawn(spawnDef, sp, sr)
      if not (S.robberVeh and F.isValidVeh(S.robberVeh)) then
        if S.activeMobDef and (S.activeMobDef.kind == "ambient_obstruction" or S.activeMobDef.useErrorOnSpawnFail) then
          F.endAsErrorThenCancel()
        else
          F.endAsFailed("spawn failed")
        end
        return
      end

      if S.activeMobDef and S.activeMobDef.engineRunning == false then
        F.forceEngineOff(S.robberVeh)
      else
        F.forceEngineOn(S.robberVeh)
      end

      -- Start chase loop sound ONLY for robber mobs (not intimidator)
      if S.playerVeh and S.activeMobDef and S.activeMobDef.kind == "robber" then
        S.chaseActive = true
        Audio.ensureSources(S.playerVeh, Mobs.getAudioSources(S.activeMobDef))
        Mobs.playChaseLoop(Audio, S.playerVeh, S.activeMobDef)
      else
        S.chaseActive = false
      end

      S.tSteal, S.tFleeStart = 0, 0
      S.didSteal, S.didStartFlee = false, false
      S.tDisableHold = 0
      S.lastDist = nil
      S.tFleeReissue, S.tRobberSlow = 0, 0
      S.stolenMoney = 0

      S.spawnSequenceStarted = false
      S.spawnSeqTimer = 0
      S.spawnCommitted = false
      S.footstepsPlayed = false

      -- Intimidator/bomb car/limo: start immediately (no stealing flow)
      if S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
        S.bombTriggered = false
        S.bombPhase = "approach"
        if S.activeMobDef.aiApproachCommands then
          F.applyAiCommands(S.robberVeh, S.activeMobDef.aiApproachCommands, S.playerVeh)
        else
          Mobs.startChase(S.robberVeh, S.playerVeh, S.activeMobDef)
        end
        F.playCue("chaseGo")
        F.setState(STATE.FLEE)
        S.lastDist = F.recomputeDistanceToRobber()
      elseif S.activeMobDef and S.activeMobDef.kind == "intimidator" then
        S.bombTriggered = false
        if S.activeMobDef.aiTrafficCommands then
          S.intimidatorPhase = "traffic"
          F.applyAiCommands(S.robberVeh, S.activeMobDef.aiTrafficCommands, nil)
          F.setState(STATE.FLEE)
        else
          Mobs.startChase(S.robberVeh, S.playerVeh, S.activeMobDef)
          F.playCue("chaseGo")
          F.setState(STATE.FLEE)
        end
        S.lastDist = F.recomputeDistanceToRobber()
      elseif S.activeMobDef and S.activeMobDef.kind == "limousine_passing" then
        S.limoPhase = "approach"
        S.limoPhaseTimer = 0
        F.applyAiCommands(S.robberVeh, S.activeMobDef.aiApproachCommands, S.playerVeh)
        F.playCue("chaseGo")
        F.setState(STATE.FLEE)
        S.lastDist = F.recomputeDistanceToRobber()
      elseif S.activeMobDef and S.activeMobDef.kind == "ambient_obstruction" then
        S.obstructionSpawnPos = sp
        S.obstructionSpawnTime = S.simTime
        S.obstructionSuccessTimer = 0
        if S.activeMobDef.worldActions and S.activeMobDef.worldActions.scatterImpulse then
          F.applyScatterImpulse(S.robberVeh, S.activeMobDef.worldActions.scatterImpulse)
        end
        F.setState(STATE.FLEE)
      end
    end

    return
  end

  -- ROBBER KIND FLOW ONLY
  if S.activeMobDef and (S.activeMobDef.kind == "intimidator" or S.activeMobDef.kind == "bomb_car" or S.activeMobDef.kind == "limousine_passing") then
    return
  end

  if not S.didSteal then
    S.tSteal = S.tSteal + dtSim
    if S.tSteal >= (CFG.stealDelaySec or 1.0) then
      local want = F.computeRobberyAmountFromWallet()
      S.stolenMoney = F.stealCareerMoney(want)

      S.earningsSinceRobbery = 0
      S.ignorePositiveCredit = 0
      S.lastMoneySample = F.getWalletMoney()

      S.lastReturnedMoney = 0
      S.lastBonusMoney = 0
      local outcomeText = string.format("Robbed -$%s", F.fmtMoney(S.stolenMoney))
      F.postEventLine(outcomeText, 12)
      F.postOutcomeLine(outcomeText)

      S.didSteal = true
      S.tFleeStart = 0

      if S.playerVeh and (S.stolenMoney or 0) > 0 then
        Audio.ensureSources(S.playerVeh, Mobs.getAudioSources(S.activeMobDef))
        Mobs.playEasyMoney(Audio, S.playerVeh, S.activeMobDef)
      end

      F.playCue("moneyTaken")
    end
    return
  end

  if not S.didStartFlee then
    S.tFleeStart = S.tFleeStart + dtSim
    if S.tFleeStart >= (CFG.fleeStartDelaySec or 1.0) then
      S.didStartFlee = true

      Mobs.startFlee(S.robberVeh, S.playerVeh, CFG)
      F.playCue("chaseGo")
      F.setState(STATE.FLEE)

      S.tDisableHold = 0
      S.tFleeReissue, S.tRobberSlow = 0, 0
      S.lastDist = F.recomputeDistanceToRobber()
    end
  end
end

local function updateFLEE(dtSim)
  S.playerVeh = getPlayerVehicle()

  if not (S.robberVeh and isValidVeh(S.robberVeh)) then
    stopDumpTruckTraySequence(true)
    endAsFailed("robber deleted")
    return
  end

  local dist = recomputeDistanceToRobber()
  if not dist then
    endAsFailed("no distance")
    return
  end
  S.lastDist = dist

  -- Ambient obstruction behavior
  if S.activeMobDef and S.activeMobDef.kind == "ambient_obstruction" then
    if not isCareerActive() or isPausedOrMenu() then
      endAsCancelled()
      return
    end

    local timeoutSec = tonumber(S.activeMobDef.timeoutSec) or 180.0
    if S.obstructionSpawnTime > 0 and (S.simTime - S.obstructionSpawnTime) >= timeoutSec then
      endAsCancelled()
      return
    end

    local successDist = tonumber(S.activeMobDef.successDistanceMeters) or 120.0
    if S.obstructionSpawnPos then
      local pos = select(1, getPlayerAnchor())
      if pos then
        local fromSpawn = (pos - S.obstructionSpawnPos):length()
        if fromSpawn >= successDist then
          endAsShookOff()
          return
        end
      end
    end
    return
  end

  -- Bomb car behavior
  if S.activeMobDef and S.activeMobDef.kind == "bomb_car" then
    local igniteDist = tonumber(S.activeMobDef.igniteDist) or 30.0
    local escapeDist = tonumber(S.activeMobDef.escapeDistMeters) or (CFG.getawayDistMeters or 1000.0)
    local contactDist = tonumber(S.activeMobDef.contactDistMeters) or 5.0

    if dist >= escapeDist then
      endAsShookOff()
      return
    end

    if not S.bombPhase then
      S.bombPhase = "approach"
    end

    if S.bombPhase == "approach" then
      if (not S.bombTriggered) and dist <= igniteDist then
        S.bombTriggered = true
        Mobs.detonateBomb(S.robberVeh)
        if S.activeMobDef.escalateMessage then
          postEventLine(S.activeMobDef.escalateMessage, S.activeMobDef.escalateMessageDurationSec or 10.0)
        end
        S.bombPhase = "ignite_and_chase"
        if S.activeMobDef.aiChaseCommands then
          applyAiCommands(S.robberVeh, S.activeMobDef.aiChaseCommands, S.playerVeh)
        else
          Mobs.startChase(S.robberVeh, S.playerVeh, S.activeMobDef)
        end
      end
      return
    end

    if S.bombPhase == "ignite_and_chase" then
      if dist <= contactDist then
        S.bombPhase = "contact_stop_linger"
        if S.activeMobDef.aiContactCommands then
          applyAiCommands(S.robberVeh, S.activeMobDef.aiContactCommands, nil)
        end
        endAsFailed()
        return
      end
      return
    end

    return
  end

  -- Limousine passing behavior
  if S.activeMobDef and S.activeMobDef.kind == "limousine_passing" then
    S.limoPhaseTimer = S.limoPhaseTimer + dtSim
    local approachDist = tonumber(S.activeMobDef.approachDist) or 25.0
    local passClearDist = tonumber(S.activeMobDef.passClearDist) or 40.0
    local passMinDurationSec = tonumber(S.activeMobDef.passMinDurationSec) or 3.5
    local passDurationSec = tonumber(S.activeMobDef.passDurationSec) or 6.0
    local getawayDist = tonumber(S.activeMobDef.getawayDistMeters) or 140.0

    if S.limoPhase == "approach" then
      if dist <= approachDist then
        S.limoPhase = "pass"
        S.limoPhaseTimer = 0
        applyAiCommands(S.robberVeh, S.activeMobDef.aiPassCommands, nil)
      end
    elseif S.limoPhase == "pass" then
      if (S.limoPhaseTimer >= passMinDurationSec and dist >= passClearDist) or S.limoPhaseTimer >= passDurationSec then
        S.limoPhase = "flee"
        S.limoPhaseTimer = 0
        applyAiCommands(S.robberVeh, S.activeMobDef.aiFleeCommands, S.playerVeh)
      end
    elseif S.limoPhase == "flee" then
      if dist >= getawayDist then
        endAsShookOff()
        return
      end
    else
      S.limoPhase = "approach"
      S.limoPhaseTimer = 0
      applyAiCommands(S.robberVeh, S.activeMobDef.aiApproachCommands, S.playerVeh)
    end
    return
  end

  -- Intimidator behavior
  if S.activeMobDef and S.activeMobDef.kind == "intimidator" and S.activeMobDef.aiTrafficCommands and S.activeMobDef.aiChaseCommands then
    if not isCareerActive() or isPausedOrMenu() then
      endAsCancelled()
      return
    end

    local successDist = tonumber(S.activeMobDef.successDistanceMeters) or (CFG.intimidatorGetawayDistMeters or 500.0)
    if dist >= successDist then
      endAsShookOff()
      return
    end

    local triggerDist = tonumber(S.activeMobDef.trafficTriggerDist) or 50.0
    local releaseDist = tonumber(S.activeMobDef.chaseReleaseDist) or 100.0

    if isBigDumpTruckEvent(S.activeMobDef) then
      if (not S.traySeqDidRun) and dist <= triggerDist then
        S.traySeqDidRun = true
        S.traySeqActive = true
        S.traySeqState = "raise"
        S.traySeqUntil = S.simTime + 25.0
        sendDumpTruckTrayInput(S.robberVeh, 1)
      end

      if S.traySeqActive and S.simTime >= S.traySeqUntil then
        if S.traySeqState == "raise" then
          S.traySeqState = "neutral"
          S.traySeqUntil = S.simTime + 0.5
          sendDumpTruckTrayInput(S.robberVeh, 0)
        elseif S.traySeqState == "neutral" then
          S.traySeqState = "lower"
          S.traySeqUntil = S.simTime + 25.0
          sendDumpTruckTrayInput(S.robberVeh, -1)
        elseif S.traySeqState == "lower" then
          S.traySeqState = "done"
          S.traySeqActive = false
          S.traySeqUntil = 0
          sendDumpTruckTrayInput(S.robberVeh, 0)
        else
          S.traySeqActive = false
          S.traySeqUntil = 0
        end
      end
    end

    if not S.intimidatorPhase then
      S.intimidatorPhase = "traffic"
      applyAiCommands(S.robberVeh, S.activeMobDef.aiTrafficCommands, nil)
    end

    if S.intimidatorPhase == "traffic" and dist <= triggerDist then
      S.intimidatorPhase = "chase"
      applyAiCommands(S.robberVeh, S.activeMobDef.aiChaseCommands, S.playerVeh)
      if S.activeMobDef.escalateMessage then
        postEventLine(S.activeMobDef.escalateMessage, S.activeMobDef.escalateMessageDurationSec or 3.0)
      end
    elseif S.intimidatorPhase == "chase" and dist >= releaseDist then
      S.intimidatorPhase = "traffic"
      applyAiCommands(S.robberVeh, S.activeMobDef.aiTrafficCommands, nil)
      if S.activeMobDef.deescalateMessage then
        postEventLine(S.activeMobDef.deescalateMessage, S.activeMobDef.deescalateMessageDurationSec or 3.0)
      end
    end
    return
  end

  if S.activeMobDef and S.activeMobDef.kind == "intimidator" then
    local spacingDist = Mobs.updateIntimidatorSpacing(S.activeMobDef, S.robberVeh, S.playerVeh)
    if spacingDist then S.lastDist = spacingDist end
    local intimidatorEscape = CFG.intimidatorGetawayDistMeters or 500.0
    local intimidatorCatch = CFG.intimidatorCatchDistMeters or 8.0
    if dist <= intimidatorCatch then
      endAsCaughtIntimidator()
      return
    end
    if dist >= intimidatorEscape then
      endAsShookOff()
      return
    end
    return
  end

  -- Robber behavior
  if dist >= (CFG.getawayDistMeters or 1000.0) then
    endAsFailed("escaped 1km")
    return
  end

  S.tFleeReissue = S.tFleeReissue + dtSim

  local rSpeed = vehSpeed(S.robberVeh)
  if rSpeed < (CFG.fleeStuckSpeed or 2.0) then
    S.tRobberSlow = S.tRobberSlow + dtSim
  else
    S.tRobberSlow = 0
  end

  if S.tFleeReissue >= (CFG.fleeReissueEverySec or 2.0) then
    S.tFleeReissue = 0
    if S.tRobberSlow >= (CFG.fleeStuckGraceSec or 1.2) then
      Mobs.startFlee(S.robberVeh, S.playerVeh, CFG)
      S.tRobberSlow = 0
      log("D", "RLS_COO", "Re-issued flee command to robber (unstick).")
    end
  end

  if S.playerVeh then
    local pSpeed = vehSpeed(S.playerVeh)
    local disableOK =
      dist <= (CFG.disableDistMeters or 5.0) and
      pSpeed <= (CFG.playerStopSpeed or 1.2) and
      rSpeed <= (CFG.robberDisableSpeed or 1.0)

    if disableOK then
      S.tDisableHold = S.tDisableHold + dtSim
      if S.tDisableHold >= (CFG.disableHoldSec or 5.0) then
        endAsRecovered()
        return
      end
    else
      if S.tDisableHold > 0 then S.tDisableHold = 0 end
    end
  else
    if S.tDisableHold > 0 then S.tDisableHold = 0 end
  end
end

local function updateRECOVERED(dtSim)
  local lingerSec = 2.5
  if S.activeMobDef and S.activeMobDef.onSuccessLingerSec ~= nil then
    lingerSec = tonumber(S.activeMobDef.onSuccessLingerSec) or lingerSec
  end
  if isForwardFireEvent(S.activeMobDef) then
    lingerSec = tonumber(S.activeMobDef.successLingerSec) or lingerSec
  end
  if S.tState >= lingerSec then
    cleanupToIdle()
  end
end

local function updateFAILED(dtSim)
  local lingerSec = 3.0
  if S.endMode == "cancel" then
    local cancelLinger = 0.0
    if S.activeMobDef then
      cancelLinger = math.max(
        tonumber(S.activeMobDef.onCancelLingerSec) or 0.0,
        tonumber(S.activeMobDef.cancelMessageDurationSec) or 0.0,
        tonumber(S.activeMobDef.errorMessageDurationSec) or 0.0
      )
    end
    lingerSec = cancelLinger
  end
  if S.activeMobDef and S.activeMobDef.kind == "bomb_car" and S.bombTriggered then
    lingerSec = tonumber(CFG.bombCarPostIgnitionLingerSec) or 120.0
  end
  if isForwardFireEvent(S.activeMobDef) then
    lingerSec = tonumber(S.activeMobDef.failLingerSec) or lingerSec
  end
  if S.activeMobDef and S.activeMobDef.kind == "intimidator" and S.intimidatorCaught then
    lingerSec = tonumber(S.activeMobDef.failureDespawnSec) or 120.0
  end
  if S.tState >= lingerSec then
    cleanupToIdle()
  end
end

-- =========================
-- Public controls
-- =========================
function M.startChase()
  if S.state ~= STATE.IDLE then return end
  local ok = canStartRobberyNow()
  if not ok then return end
  beginAmbush()
end

function M.cancelChase()
  if S.state == STATE.IDLE then return end
  stopChaseAudioNow()
  playCue("cancel")
  cleanupToIdle()
end

function M.onActionEvent(actionName, value)
  if actionName == "bolidesGangsterChase.toggle" and value == 1 then
    if S.state == STATE.IDLE then M.startChase() else M.cancelChase() end
  end
end

-- =========================
-- Main update
-- =========================
function M.onUpdate(dtReal, dtSim)
  local dt = dtSim or dtReal or 0
  if dt <= 0 then return end
  if not S then return end
  S.hardError = S.hardError or false
  if S.hardError then return end

  local ok, err = pcall(function()
    S.simTime = S.simTime + dt
    updateTravelHistory(dt)

    ensureEarningsTarget()
    S.tState = S.tState + dt

    updateEarningsAndAutoRobbery(dt)
    updateEligibilityTick(dt)
    updateCommon(dt)

    if S.state == STATE.IDLE then
      return
    elseif S.state == STATE.PREWARN then
      updatePREWARN(dt)
    elseif S.state == STATE.AMBUSH then
      updateAMBUSH(CTX, dt)
    elseif S.state == STATE.FLEE then
      updateFLEE(dt)
    elseif S.state == STATE.RECOVERED then
      updateRECOVERED(dt)
    elseif S.state == STATE.FAILED then
      updateFAILED(dt)
    end
  end)

  if not ok then
    S.hardError = true
    S.lastHardError = tostring(err)
    log("E", "BolidesTheCut", "Hard error (tick disabled): " .. tostring(err))
  end
end

-- Init
resetEarningsCycle()

function M.getUiState()
  local money = getWalletMoney()
  local _, _, _, anchorMode = getPlayerAnchor()

  local data = {
    state = S.state,
    money = money,
    earnings = S.earningsSinceRobbery,
    threshold = (S.currentEarningsTarget or 0),
    stolen = S.stolenMoney or 0,
    returned = S.lastReturnedMoney or 0,
    bonus = S.lastBonusMoney or 0,
    lastDist = S.lastDist,
    anchorMode = anchorMode,
    travelForward = travelTotalForward or 0,
    mob = S.activeMobKey or ""
  }

  if type(jsonEncode) == "function" then
    return jsonEncode(data)
  end
  return "{}"
end

return M
