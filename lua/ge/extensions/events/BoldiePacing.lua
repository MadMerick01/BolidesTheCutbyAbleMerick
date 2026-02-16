local M = {}

local CFG = nil
local Host = nil
local Events = {}
local PreloadRequest = nil

local STATE = {
  activeMode = "real",
  pendingMode = nil,
  intervalSec = 30,
  countdown = 30,
  activeEventName = nil,
  nextIndex = 1,
  retryDelay = 0.5,
  retryTimer = 0,
  preloadRequested = false,
  preloadDelaySec = 60,
}

local EVENT_ORDER = {
  "RobberEMP",
  "RobberShotgun",
}

local HARASSING_INTERVAL_SEC = 30
local REAL_MIN_INTERVAL_SEC = 180
local REAL_MAX_INTERVAL_SEC = 600
local rngSeeded = false

local function normalizeMode(mode)
  local v = tostring(mode or ""):lower()
  if v == "harassing" then
    return "harassing"
  end
  return "real"
end

local function ensureRngSeeded()
  if rngSeeded then
    return
  end
  local seed = math.floor((os.time() or 0) + ((os.clock() or 0) * 100000))
  math.randomseed(seed)
  rngSeeded = true
end

local function sampleIntervalSec(mode)
  local normalized = normalizeMode(mode)
  if normalized == "harassing" then
    return HARASSING_INTERVAL_SEC
  end
  ensureRngSeeded()
  return math.random(REAL_MIN_INTERVAL_SEC, REAL_MAX_INTERVAL_SEC)
end

local function beginCountdownForMode(mode)
  STATE.activeMode = normalizeMode(mode)
  STATE.intervalSec = sampleIntervalSec(STATE.activeMode)
  STATE.countdown = STATE.intervalSec
  STATE.preloadRequested = false
end

local function applyPendingModeIfNeeded()
  if not STATE.pendingMode then
    return
  end
  beginCountdownForMode(STATE.pendingMode)
  STATE.pendingMode = nil
end

local function setNextIndexFromName(name)
  for i, eventName in ipairs(EVENT_ORDER) do
    if eventName == name then
      STATE.nextIndex = (i % #EVENT_ORDER) + 1
      return
    end
  end
end

local function getEventModule(name)
  return Events and Events[name]
end

local function isEventActive(name)
  local eventModule = getEventModule(name)
  if eventModule and eventModule.isActive then
    return eventModule.isActive()
  end
  return false
end

local function isEventPending(name)
  local eventModule = getEventModule(name)
  if eventModule and eventModule.isPendingStart then
    return eventModule.isPendingStart()
  end
  return false
end

local function detectActiveEvent()
  for _, eventName in ipairs(EVENT_ORDER) do
    if isEventActive(eventName) then
      return eventName
    end
  end
  return nil
end

local function triggerEvent(name)
  local eventModule = getEventModule(name)
  if eventModule and eventModule.triggerManual then
    return eventModule.triggerManual()
  end
  return false
end

function M.init(hostCfg, hostApi, eventModules, preloadRequestFn)
  CFG = hostCfg
  Host = hostApi
  Events = eventModules or Events
  PreloadRequest = preloadRequestFn

  STATE.activeMode = normalizeMode((CFG and CFG.pacingModeDefault) or STATE.activeMode)
  beginCountdownForMode(STATE.activeMode)
  STATE.pendingMode = nil
  STATE.activeEventName = nil
  STATE.retryTimer = 0
  STATE.nextIndex = 1
  STATE.preloadDelaySec = (CFG and CFG.preloadInitialDelaySec) or STATE.preloadDelaySec or 60
end

function M.getCountdown()
  return math.max(0, STATE.countdown or 0)
end

function M.getNextEventName()
  return EVENT_ORDER[STATE.nextIndex]
end

function M.getMode()
  return STATE.activeMode
end

function M.getPendingMode()
  return STATE.pendingMode
end

function M.setMode(mode)
  local target = normalizeMode(mode)
  if target == STATE.activeMode then
    STATE.pendingMode = nil
    return true
  end

  local activeName = STATE.activeEventName or detectActiveEvent()
  if activeName then
    STATE.pendingMode = target
    return true
  end

  beginCountdownForMode(target)
  STATE.pendingMode = nil
  return true
end

function M.isEventActive()
  return STATE.activeEventName ~= nil
end

function M.update(dtSim)
  if not dtSim then
    return
  end

  local activeName = STATE.activeEventName or detectActiveEvent()
  if activeName then
    STATE.activeEventName = activeName
    setNextIndexFromName(activeName)
    if not isEventActive(activeName) and not isEventPending(activeName) then
      STATE.activeEventName = nil
      applyPendingModeIfNeeded()
      beginCountdownForMode(STATE.activeMode)
      STATE.retryTimer = 0
    end
    return
  end

  if not STATE.preloadRequested and type(PreloadRequest) == "function" then
    local nextName = M.getNextEventName()
    if nextName then
      PreloadRequest(nextName, {
        windowStart = os.clock(),
        windowSeconds = STATE.intervalSec,
        minDelay = STATE.preloadDelaySec,
      })
      STATE.preloadRequested = true
    end
  end

  if STATE.countdown > 0 then
    STATE.countdown = math.max(0, STATE.countdown - dtSim)
    return
  end

  if STATE.retryTimer > 0 then
    STATE.retryTimer = math.max(0, STATE.retryTimer - dtSim)
    return
  end

  local nextName = M.getNextEventName()
  if nextName then
    local ok = triggerEvent(nextName)
    if ok then
      STATE.activeEventName = nextName
      STATE.retryTimer = 0
      STATE.nextIndex = (STATE.nextIndex % #EVENT_ORDER) + 1
      STATE.preloadRequested = false
    else
      STATE.retryTimer = STATE.retryDelay
      STATE.countdown = 0
    end
  end
end

return M
