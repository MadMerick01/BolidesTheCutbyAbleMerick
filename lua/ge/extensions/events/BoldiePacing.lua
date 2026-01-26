local M = {}

local CFG = nil
local Host = nil
local Events = {}
local PreloadRequest = nil

local STATE = {
  intervalSec = 180,
  countdown = 180,
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

  STATE.countdown = STATE.intervalSec
  STATE.activeEventName = nil
  STATE.retryTimer = 0
  STATE.nextIndex = 1
  STATE.preloadRequested = false
  STATE.preloadDelaySec = (CFG and CFG.preloadInitialDelaySec) or STATE.preloadDelaySec or 60
end

function M.getCountdown()
  return math.max(0, STATE.countdown or 0)
end

function M.getNextEventName()
  return EVENT_ORDER[STATE.nextIndex]
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
    if not isEventActive(activeName) then
      STATE.activeEventName = nil
      STATE.countdown = STATE.intervalSec
      STATE.retryTimer = 0
      STATE.preloadRequested = false
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
