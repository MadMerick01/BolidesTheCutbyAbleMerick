-- lua/ge/extensions/bolidesTheCut.lua
-- BolidesTheCut (fresh rebuild): GUI + About/Hide Info + Intro audio (OldCode-style) + Breadcrumb debug UI
-- Requires:
--   lua/ge/extensions/breadcrumbs.lua
--   lua/ge/extensions/events/RobberEMP.lua
--   lua/ge/extensions/events/RobberShotgun.lua

local M = {}

local Breadcrumbs = require("lua/ge/extensions/breadcrumbs")
local RobberEMP = require("lua/ge/extensions/events/RobberEMP")
local RobberShotgun = require("lua/ge/extensions/events/RobberShotgun")
local BoldiePacing = require("lua/ge/extensions/events/BoldiePacing")
local FireAttack = require("lua/ge/extensions/events/fireAttack")
local EMP = require("lua/ge/extensions/events/emp")
local BulletDamage = require("lua/ge/extensions/events/BulletDamage")
local PreloadEvent = require("lua/ge/extensions/events/PreloadEventNEW")
local FirstPersonShoot = require("lua/ge/extensions/FirstPersonShoot")
local DeflateRandomTyre = require("lua/ge/extensions/events/deflateRandomTyre")
local CareerMoney = require("CareerMoney")

local markHudTrialDirty
local ensureHudTrialAppVisible
local sendHudTrialPayload
local handleAboutIntroAudio

-- =========================
-- Config
-- =========================
local CFG = {
  windowTitle = "Bolides: The Cut",
  windowVisible = false,
  apiDumpOutputDir = nil, -- Optional override (e.g. "C:/temp") for apiDump output.

  -- Debug marker gate (Codex-safe pattern)
  debugBreadcrumbMarkers = false,
  debugButtons = true,

  -- Make FKB show A LOT for now (you can tighten later)
  forwardKnownCheckIntervalSec = 1.0,
  forwardKnownMinAheadMeters = 0.0,
  forwardKnownMaxAheadMeters = 5000.0,

  -- Travel / crumb settings (breadcrumbs.lua reads CFG.TRAVEL)
  TRAVEL = {
    crumbEveryMeters = 5.0,
    keepMeters = 2500.0,
    teleportResetMeters = 50.0,
  },

  -- Audio
  audioEnabled = true,
  sfxBolidesIntroFile = "/art/sound/bolides/BolidesIntroWav.wav",
  sfxBolidesIntroName = "bolidesIntroHit",
  bolidesIntroVol = 4.0,
  bolidesIntroPitch = 1.0,
  sfxGunshotFile = "/art/sound/bolides/distantgunshot.wav",
  sfxGunshotName = "bolidesGunshot",
  sfxGunshotPoolSize = 6,
  sfxGunshotVol = 12.0,
  sfxGunshotPitch = 1.0,
  sfxPlayerGunshotFile = "/art/sound/bolides/PlayerGunShot.wav",
  sfxPlayerGunshotName = "bolidesPlayerGunshot",
  sfxPlayerGunshotPoolSize = 6,
  sfxPlayerGunshotVol = 12.0,
  sfxPlayerGunshotPitch = 1.0,

  -- GUI threat coloring
  threatDistanceRobber = 50.0,
  threatDistanceFireAttack = 100.0,

  -- Preload pacing
  preloadInitialDelaySec = 60.0,
}

-- =========================
-- Runtime state
-- =========================
local S = {
  uiShowInfo = false,
  uiShowDebug = false,
  uiShowManualEvents = false,

  -- Kept because OldCode printed these lines; safe placeholders for now
  testDumpTruckVehId = nil,
  testDumpTruckStatus = "",
  empTestStatus = "",
  bulletDamageStatus = "",
  apiDumpStatus = "",

  guiStatusMessage = "Nothing unusual",

  hudWallet = nil,
  hudWeapons = nil,
  hudStatus = "",
  hudInstruction = "",
  hudThreat = nil,
  hudDangerReason = nil,
  hudShotgunMessage = "Aim carefully",
  hudShotgunHitPoint = "Raycast hit: --",
  hudEquippedWeapon = nil,
  hudWeaponButtonHover = false,
  hudPauseState = nil,
  hudPauseActive = false,
  towingBlocked = false,
  recoveryPromptWasActive = nil,

  uiShowWeapons = false,
  uiShowAbout = false,

  popupQueue = {},
  popupActive = nil,
  popupDismissed = false,
  popupWaitingForPreload = false,
  popupPreloadEventName = nil,
  popupPauseState = nil,
  popupShownOnce = {},
  hudPreloadPending = false,
  preloadIntroShown = false,
}

local UI = {}

-- =========================
-- Mission Info Message Wrapper (module scope)
-- =========================
M._missionMsg = {
  open = false,
  pauseState = nil,
  onClose = nil,
  onContinue = nil,
  reason = nil,
}

local POPUP = {
  eventName = "bolideTheCutPopupUpdate",
  dirty = true,
  timeSinceEmit = math.huge,
  emitInterval = 0.25,
  lastPayloadKey = nil,
}

local function missionLog(level, msg)
  local line = tostring(msg)
  if type(log) == "function" then
    log(level or "I", "BolidesTheCut", line)
  else
    print(string.format("[BolidesTheCut] %s", line))
  end
end

local function getTimeScaleSafe()
  if getTimeScale then
    local ok, val = pcall(getTimeScale)
    if ok and type(val) == "number" then return val end
  end
  if simTimeAuthority then
    if simTimeAuthority.getTimeScale then
      local ok, val = pcall(simTimeAuthority.getTimeScale)
      if ok and type(val) == "number" then return val end
    end
    if simTimeAuthority.getSpeed then
      local ok, val = pcall(simTimeAuthority.getSpeed)
      if ok and type(val) == "number" then return val end
    end
  end
  return 1.0
end

local function setTimeScaleSafe(scale)
  scale = tonumber(scale)
  if scale == nil then return false end
  if setTimeScale then
    local ok = pcall(setTimeScale, scale)
    if ok then return true end
  end
  if simTimeAuthority and simTimeAuthority.setPause then
    if scale <= 0 then
      local ok = pcall(simTimeAuthority.setPause, true)
      if ok then return true end
    else
      local ok = pcall(simTimeAuthority.setPause, false)
      if ok then return true end
    end
  end
  return false
end

local function requestPauseState()
  if bullettime and bullettime.pushPauseRequest then
    local ok, token = pcall(bullettime.pushPauseRequest)
    if ok then
      return { token = token }
    end
  end
  local prevTimeScale = getTimeScaleSafe()
  setTimeScaleSafe(0)
  return { prevTimeScale = prevTimeScale }
end

local function restorePauseState(state)
  if not state then
    return
  end
  if state.token ~= nil then
    if bullettime and bullettime.popPauseRequest then
      pcall(bullettime.popPauseRequest, state.token)
    end
    return
  end
  if state.prevTimeScale ~= nil then
    setTimeScaleSafe(state.prevTimeScale or 1)
  end
end

local function getHudPauseActive()
  if bullettime and bullettime.getPause then
    -- API dump ref: docs/beamng-api/raw/api_dump_0.38.json
    local ok, paused = pcall(bullettime.getPause)
    if ok then
      return paused == true
    end
  end
  return S.hudPauseState ~= nil
end

local function getRobberPreloaded()
  if not PreloadEvent or not PreloadEvent.hasPreloaded then
    return false
  end
  local ok, res = pcall(PreloadEvent.hasPreloaded, "RobberEMP")
  if ok and res then
    return true
  end
  ok, res = pcall(PreloadEvent.hasPreloaded, "RobberShotgun")
  return ok and res or false
end

local function describePreloadPlacement()
  if not PreloadEvent or not PreloadEvent.getDebugState then
    return "Unknown"
  end
  local ok, state = pcall(PreloadEvent.getDebugState)
  if not ok or not state or not state.preloaded then
    return "Unknown"
  end
  local placed = tostring(state.placed or "unknown")
  local labels = {
    preloadParking = "Preload parking spot (>=300m)",
    fixedPreload = "Fixed map preload",
    fallbackBreadcrumb300m = "Fallback breadcrumb (300m)",
    fallbackBreadcrumb = "Fallback breadcrumb",
    backBreadcrumb300m = "Back breadcrumb (300m)",
    backBreadcrumb = "Back breadcrumb",
  }
  return labels[placed] or placed
end

function M.toggleHudPause()
  if bullettime and bullettime.togglePause then
    -- API dump ref: docs/beamng-api/raw/api_dump_0.38.json
    pcall(bullettime.togglePause)
    S.hudPauseState = nil
    S.hudPauseActive = getHudPauseActive()
    markHudTrialDirty()
    return
  end

  if S.hudPauseState then
    restorePauseState(S.hudPauseState)
    S.hudPauseState = nil
  else
    S.hudPauseState = requestPauseState()
  end
  S.hudPauseActive = getHudPauseActive()
  markHudTrialDirty()
end

function M.preloadRobberFromHud()
  local hasRobber = false
  if RobberEMP and RobberEMP.getRobberVehicleId then
    hasRobber = type(RobberEMP.getRobberVehicleId()) == "number"
  end
  if not hasRobber and RobberShotgun and RobberShotgun.getRobberVehicleId then
    hasRobber = type(RobberShotgun.getRobberVehicleId()) == "number"
  end

  if hasRobber or getRobberPreloaded() then
    markHudTrialDirty()
    return
  end

  if RobberEMP and RobberEMP.getPreloadSpec and PreloadEvent and PreloadEvent.request then
    local spec = RobberEMP.getPreloadSpec()
    if spec then
      if PreloadEvent and PreloadEvent.setUiGateOverride then
        pcall(PreloadEvent.setUiGateOverride, true)
      end
      pcall(PreloadEvent.request, spec)
    end
  end

  markHudTrialDirty()
end

function M.toggleHudAbout()
  S.uiShowAbout = not S.uiShowAbout
  if type(handleAboutIntroAudio) == "function" then
    handleAboutIntroAudio(S.uiShowAbout)
  end
end

local function ensureMissionInfo()
  if not extensions then
    missionLog("E", "Mission Info: extensions system not available.")
    return false
  end

  if not extensions.isExtensionLoaded or not extensions.load then
    missionLog("E", "Mission Info: extensions loader not available.")
    return false
  end

  if not extensions.isExtensionLoaded("missionInfo") then
    local ok = pcall(extensions.load, "missionInfo")
    if not ok or not extensions.isExtensionLoaded("missionInfo") then
      missionLog("E", "Mission Info: failed to load missionInfo extension.")
      return false
    end
  end

  if not extensions.missionInfo or not extensions.missionInfo.openDialogue then
    missionLog("E", "Mission Info: missionInfo extension missing openDialogue.")
    return false
  end

  return true
end

local function formatHitPoint(pos)
  if not pos or type(pos) ~= "table" or not pos.x or not pos.y or not pos.z then
    return "Raycast hit: --"
  end
  return string.format("Raycast hit: %.2f, %.2f, %.2f", pos.x, pos.y, pos.z)
end

local function closeMissionInfoDialogue()
  if extensions and extensions.missionInfo and extensions.missionInfo.closeDialogue then
    pcall(extensions.missionInfo.closeDialogue)
  end
end

local function popupPayloadKey(payload)
  return table.concat({
    tostring(payload.active),
    tostring(payload.title or ""),
    tostring(payload.body or ""),
    tostring(payload.continueLabel or ""),
    tostring(payload.canContinue),
    tostring(payload.statusLine or ""),
  }, "|")
end

local function buildPopupPayload()
  if not S.popupActive then
    return { active = false }
  end
  local msg = S.popupActive or {}
  local canContinue = msg.canContinue ~= false
  if S.popupDismissed and S.popupWaitingForPreload then
    canContinue = false
  end
  local statusLine = ""
  if S.popupWaitingForPreload then
    statusLine = msg.preloadStatus or "Preloading next event..."
  end
  return {
    active = true,
    title = tostring(msg.title or ""),
    body = tostring(msg.body or msg.text or ""),
    continueLabel = tostring(msg.continueLabel or "Continue"),
    canContinue = canContinue,
    statusLine = statusLine,
  }
end

local function markPopupDirty()
  POPUP.dirty = true
end

local function sendPopupPayload(force)
  local hooks = guihooks
  if not hooks or type(hooks.trigger) ~= "function" then
    return false
  end

  local payload = buildPopupPayload()
  local key = popupPayloadKey(payload)
  local changed = key ~= POPUP.lastPayloadKey

  if not force then
    if POPUP.dirty ~= true and not changed and POPUP.timeSinceEmit < POPUP.emitInterval then
      return false
    end
  end

  local ok = pcall(hooks.trigger, POPUP.eventName, payload)
  if ok then
    POPUP.lastPayloadKey = key
    POPUP.dirty = false
    POPUP.timeSinceEmit = 0
  end
  return ok
end

local function isPopupPreloadReady()
  if not S.popupActive or not S.popupWaitingForPreload then
    return true
  end
  if not PreloadEvent then
    return true
  end
  if S.popupPreloadEventName and PreloadEvent.hasPreloaded then
    local ok, res = pcall(PreloadEvent.hasPreloaded, S.popupPreloadEventName)
    if ok and res then
      return true
    end
  end
  if PreloadEvent.getDebugState then
    local ok, state = pcall(PreloadEvent.getDebugState)
    if ok and state then
      if not state.pending then
        return true
      end
      if S.popupPreloadEventName and state.pending ~= S.popupPreloadEventName then
        return true
      end
      if state.preloadInProgress then
        return false
      end
      if state.attemptCount and state.maxAttempts and state.attemptCount >= state.maxAttempts then
        return true
      end
    end
  end
  return false
end

local function finalizePopup(reason)
  local msg = S.popupActive
  local pauseState = S.popupPauseState

  if PreloadEvent and PreloadEvent.setUiGateOverride then
    pcall(PreloadEvent.setUiGateOverride, false)
  end

  S.popupActive = nil
  S.popupDismissed = false
  S.popupWaitingForPreload = false
  S.popupPreloadEventName = nil
  S.popupPauseState = nil

  restorePauseState(pauseState)

  markPopupDirty()
  sendPopupPayload(true)

  if msg then
    if reason == "continue" and type(msg.onContinue) == "function" then
      pcall(msg.onContinue)
    elseif type(msg.onClose) == "function" then
      pcall(msg.onClose)
    end
  end

  if #S.popupQueue > 0 then
    M._activateNextPopup()
  end
end

function M._activateNextPopup()
  if S.popupActive or #S.popupQueue == 0 then
    return false
  end

  local msg = table.remove(S.popupQueue, 1)
  if not msg then
    return false
  end

  if msg.once and msg.id then
    if S.popupShownOnce[msg.id] then
      return M._activateNextPopup()
    end
    S.popupShownOnce[msg.id] = true
  end

  S.popupActive = msg
  S.popupDismissed = false
  S.popupWaitingForPreload = false
  S.popupPreloadEventName = nil

  if msg.freeze ~= false then
    S.popupPauseState = requestPauseState()
  else
    S.popupPauseState = nil
  end

  if msg.preloadSpec or msg.nextEventName then
    local ok = false
    if msg.preloadSpec then
      ok = M.requestEventPreload(msg.preloadSpec)
    elseif msg.nextEventName then
      ok = M.requestEventPreloadByName(msg.nextEventName, msg.preloadOpts)
    end
    if ok then
      S.popupWaitingForPreload = true
      S.popupPreloadEventName = msg.nextEventName or (msg.preloadSpec and msg.preloadSpec.eventName) or nil
      if PreloadEvent and PreloadEvent.setUiGateOverride then
        pcall(PreloadEvent.setUiGateOverride, true)
      end
    end
  end

  ensureHudTrialAppVisible(true)
  markPopupDirty()
  sendPopupPayload(true)
  return true
end

function M.showPopupMessage(args)
  args = args or {}
  local msg = {
    id = args.id or args.key or args.title or ("popup_" .. tostring(os.clock())),
    title = args.title or "Notice",
    body = args.body or args.text or "",
    continueLabel = args.continueLabel or "Continue",
    freeze = args.freeze ~= false,
    once = args.once == true,
    onClose = args.onClose,
    onContinue = args.onContinue,
    preloadSpec = args.preloadSpec,
    preloadOpts = args.preloadOpts,
    nextEventName = args.nextEventName or args.nextEvent,
    preloadStatus = args.preloadStatus,
    canContinue = args.canContinue,
    preloadSuccessBody = args.preloadSuccessBody,
    preloadSuccessPlacementLabel = args.preloadSuccessPlacementLabel,
  }

  if msg.once and msg.id and S.popupShownOnce[msg.id] then
    return false
  end

  table.insert(S.popupQueue, msg)
  ensureHudTrialAppVisible(true)
  M._activateNextPopup()
  return true
end

local function updatePopupPreloadSuccessMessage()
  local msg = S.popupActive
  if not msg or not msg.preloadSuccessBody then
    return false
  end
  local placement = describePreloadPlacement()
  local label = msg.preloadSuccessPlacementLabel or "Preload position:"
  msg.body = string.format("%s\n%s %s", msg.preloadSuccessBody, label, placement)
  msg.preloadStatus = "Preload complete."
  msg.canContinue = true
  return true
end

function M._popupContinue()
  if not S.popupActive then
    return
  end
  if S.popupDismissed then
    return
  end
  S.popupDismissed = true
  if not S.popupWaitingForPreload or isPopupPreloadReady() then
    finalizePopup("continue")
    return
  end
  markPopupDirty()
  sendPopupPayload(true)
end

function M.closePopupMessage(reason)
  if not S.popupActive then
    return
  end
  finalizePopup(reason or "closed")
end

local function formatCountdown(seconds)
  local totalSeconds = math.max(0, math.floor((seconds or 0) + 0.5))
  local minutes = math.floor(totalSeconds / 60)
  local rem = totalSeconds % 60
  return string.format("%02d:%02d", minutes, rem)
end

local function getThreatState()
  local hasEvent = false
  local imminent = false

  local function checkEvent(eventModule, imminentDistance)
    if not (eventModule and eventModule.isActive and eventModule.isActive()) then
      return
    end
    hasEvent = true
    if imminentDistance and eventModule.getDistanceToPlayer then
      local dist = eventModule.getDistanceToPlayer()
      if dist and dist <= imminentDistance then
        imminent = true
      end
    end
  end

  checkEvent(RobberEMP, CFG.threatDistanceRobber)
  checkEvent(RobberShotgun, CFG.threatDistanceRobber)
  checkEvent(FireAttack, CFG.threatDistanceFireAttack)

  if imminent then
    return "imminent"
  end
  if hasEvent then
    return "event"
  end
  return "safe"
end

local function showLegacyMissionMessage(args)
  args = args or {}

  if M._missionMsg.open then
    M.closeMissionMessage("replaced")
  end

  if not ensureMissionInfo() then
    local title = tostring(args.title or "Notice")
    local text = tostring(args.text or "")
    local msg = title
    if text ~= "" then
      msg = string.format("%s\n%s", title, text)
    end
    M.setGuiStatusMessage(msg)
    missionLog("W", "Mission message skipped (missionInfo unavailable).")
    return false
  end

  local freeze = (args.freeze ~= false)
  local continueLabel = tostring(args.continueLabel or "Continue")

  M._missionMsg.open = true
  M._missionMsg.reason = nil
  M._missionMsg.onClose = args.onClose
  M._missionMsg.onContinue = args.onContinue

  if freeze then
    M._missionMsg.pauseState = requestPauseState()
  else
    M._missionMsg.pauseState = nil
  end

  local content = {
    title = tostring(args.title or ""),
    text = tostring(args.text or ""),
    actionMap = (args.actionMap ~= false),
    buttons = {
      {
        label = continueLabel,
        action = "bolides_continue",
        cmd = [[if extensions.bolidesTheCut then extensions.bolidesTheCut._missionContinue() end]],
      },
    },
  }

  pcall(extensions.missionInfo.openDialogue, content)
  missionLog("I", "Mission message opened.")
  return true
end

function M.showMissionMessage(args)
  local ok = M.showPopupMessage(args)
  if ok then
    return true
  end
  if args and args.once then
    return false
  end
  return showLegacyMissionMessage(args)
end

function M._missionContinue()
  if not M._missionMsg.open then
    return
  end

  closeMissionInfoDialogue()

  restorePauseState(M._missionMsg.pauseState)
  M._missionMsg.pauseState = nil

  M._missionMsg.open = false

  local onClose = M._missionMsg.onClose
  local onContinue = M._missionMsg.onContinue
  M._missionMsg.onClose = nil
  M._missionMsg.onContinue = nil

  if type(onClose) == "function" then
    pcall(onClose)
  elseif type(onContinue) == "function" then
    pcall(onContinue)
  end

  missionLog("I", "Mission message continued.")
end

function M.closeMissionMessage(reason)
  if S.popupActive then
    finalizePopup(reason or "closed")
    return
  end
  if not M._missionMsg.open then
    return
  end

  M._missionMsg.reason = reason
  closeMissionInfoDialogue()

  restorePauseState(M._missionMsg.pauseState)
  M._missionMsg.pauseState = nil

  M._missionMsg.open = false
  M._missionMsg.onClose = nil
  M._missionMsg.onContinue = nil

  missionLog("I", string.format("Mission message closed (%s).", tostring(reason or "closed")))
end

-- Called by your UI bootstrap app:
-- extensions.bolidesTheCut.setWindowVisible(true)
function M.setWindowVisible(v)
  CFG.windowVisible = (v == true)
  markHudTrialDirty()
  if v == true then
    ensureHudTrialAppVisible(true)
    sendHudTrialPayload(true)
  end
end

function M.setGuiStatusMessage(msg)
  if not msg or msg == "" then
    S.guiStatusMessage = "Nothing unusual"
    return
  end
  S.guiStatusMessage = tostring(msg)
end

function M.requestHudTrialSnapshot()
  markHudTrialDirty()
  ensureHudTrialAppVisible(true)
  sendHudTrialPayload(true)
  sendPopupPayload(true)
  return true
end

local function getPlayerVeh()
  return be:getPlayerVehicle(0)
end

local function findNearestVehicleToPlayer()
  local playerVeh = getPlayerVeh()
  if not playerVeh then return nil, nil, "No player vehicle found." end

  local playerId = playerVeh:getID()
  local playerPos = playerVeh:getPosition()
  local nearestVeh = nil
  local nearestDist = nil

  if scenetree and scenetree.findClassObjects and scenetree.findObject then
    local vehicles = scenetree.findClassObjects("BeamNGVehicle") or {}
    for i = 1, #vehicles do
      local obj = scenetree.findObject(vehicles[i])
      if obj and obj.getID and obj:getID() ~= playerId then
        local pos = obj:getPosition()
        if pos then
          local dist = (pos - playerPos):length()
          if not nearestDist or dist < nearestDist then
            nearestDist = dist
            nearestVeh = obj
          end
        end
      end
    end
  end

  if not nearestVeh then
    return nil, nil, "No nearby vehicle found."
  end

  return nearestVeh, nearestDist, nil
end

-- =========================================================
-- EVENT HOST API (so each event can be fully self-contained)
-- =========================================================
local function postEventLine(tag, msg)
  -- Console line + allow GUI to pull status from the event module too
  print(string.format("[Bolides] %s: %s", tostring(tag), tostring(msg)))
end

local INVENTORY_SAVE_PATH = "settings/bolidesTheCut_inventory.json"

local DEFAULT_HUD_WEAPONS = {
  { id = "pistol", name = "Pistol", ammoLabel = "Ammo", ammo = 0 },
  { id = "emp", name = "EMP Device", ammoLabel = "Charges", ammo = 0 },
}

local HUD_WEAPON_AMMO_LIMITS = {
  pistol = 6,
  emp = 5,
}

local HIDDEN_HUD_WEAPON_IDS = {
  ammo_slug_ap = true,
  ammo_slug_tracking = true,
}

local function isHudWeaponHidden(id)
  return HIDDEN_HUD_WEAPON_IDS[tostring(id or "")] == true
end

local function cloneWeapons(list)
  local out = {}
  for _, w in ipairs(list or {}) do
    out[#out + 1] = {
      id = w.id,
      name = w.name,
      ammoLabel = w.ammoLabel,
      ammo = w.ammo,
    }
  end
  return out
end

local function sanitizeWeaponEntry(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local id = tostring(entry.id or "")
  if id == "" then
    return nil
  end
  if isHudWeaponHidden(id) then
    return nil
  end
  if id == "beretta92fs" or id == "beretta1301" then
    id = "pistol"
  end
  local defaultName = id == "pistol" and "Pistol" or id
  local defaultLabel = id == "pistol" and "Ammo" or "Ammo"
  local ammoLimit = HUD_WEAPON_AMMO_LIMITS[id]
  local ammo = math.max(0, tonumber(entry.ammo or 0) or 0)
  if ammoLimit then
    ammo = math.min(ammo, ammoLimit)
  end
  return {
    id = id,
    name = tostring(entry.name or defaultName),
    ammoLabel = tostring(entry.ammoLabel or defaultLabel),
    ammo = ammo,
  }
end

local function loadInventory()
  if not jsonReadFile then
    return nil
  end
  local ok, data = pcall(jsonReadFile, INVENTORY_SAVE_PATH)
  if not ok or type(data) ~= "table" then
    return nil
  end
  local weapons = data.weapons or data
  if type(weapons) ~= "table" then
    return nil
  end
  local out = {}
  for _, w in ipairs(weapons) do
    local sanitized = sanitizeWeaponEntry(w)
    if sanitized then
      out[#out + 1] = sanitized
    end
  end
  if #out == 0 then
    return nil
  end
  return out
end

local function saveInventory()
  if not jsonWriteFile then
    return false
  end
  if type(S.hudWeapons) ~= "table" then
    return false
  end
  local payload = {
    version = 1,
    weapons = cloneWeapons(S.hudWeapons),
  }
  pcall(jsonWriteFile, INVENTORY_SAVE_PATH, payload, true)
  return true
end

local function getCareerMoney()
  if not CareerMoney or not CareerMoney.isCareerActive or not CareerMoney.isCareerActive() then
    return nil
  end
  return CareerMoney.get and CareerMoney.get() or nil
end

local function getActiveRobberVehicle(eventModule)
  if not (eventModule and eventModule.isActive and eventModule.isActive()) then
    return nil
  end
  if eventModule.getRobberVehicleId then
    return eventModule.getRobberVehicleId()
  end
  return nil
end

local function getActiveRobberDistance(eventModule)
  if not (eventModule and eventModule.isActive and eventModule.isActive()) then
    return nil
  end
  if eventModule.getDistanceToPlayer then
    return eventModule.getDistanceToPlayer()
  end
  return nil
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function distanceChance(distance, nearDist, farDist, nearChance, farChance)
  if not distance then
    return nil
  end
  if distance <= nearDist then
    return nearChance
  end
  if distance >= farDist then
    return farChance
  end
  local t = (distance - nearDist) / (farDist - nearDist)
  return lerp(nearChance, farChance, t)
end

local function formatChanceLine(label, chance)
  if not chance then
    return string.format("%s: --", label)
  end
  return string.format("%s: %d%%", label, math.floor((chance * 100) + 0.5))
end

local function disableRobberAI(robberVeh)
  if not robberVeh then
    return false
  end
  if robberVeh.queueLuaCommand then
    local ok = pcall(function()
      robberVeh:queueLuaCommand([[
        if ai then
          pcall(function() ai.setMode("disabled") end)
          pcall(function() ai.setMode("none") end)
          pcall(function() ai.setAggression(0) end)
        end
      ]])
    end)
    return ok == true
  end
  return false
end

local function ensureHudState()
  if S.hudWeapons == nil then
    S.hudWeapons = loadInventory() or cloneWeapons(DEFAULT_HUD_WEAPONS)
  end
  if S.hudWallet == nil then
    S.hudWallet = getCareerMoney() or 0
  end
  if S.hudStatus == nil then
    S.hudStatus = "Normal"
  end
  if S.hudInstruction == nil then
    S.hudInstruction = "Lets make money"
  end
end

local function getHudThreatLevel()
  if S.hudThreat and S.hudThreat ~= "" then
    return S.hudThreat
  end
  local threatState = getThreatState()
  if threatState == "imminent" then
    return "danger"
  end
  if threatState == "event" then
    return "event"
  end
  return "safe"
end

local HUD_TRIAL = {
  appName = "BolideHudTrialApp",
  containerName = "messagesTasks",
  eventName = "bolideTheCutHudTrialUpdate",
  dirty = true,
  timeSinceEmit = math.huge,
  emitInterval = 0.25,
  forceEmitInterval = 1.0,
  timeSinceEnsureVisible = math.huge,
  ensureVisibleInterval = 2.0,
  lastPayloadKey = nil,
}

local TOWING_BLOCK_MESSAGE = "Towing disabled during active threat."

local function addTowBlockMessage(instruction)
  if not instruction or instruction == "" then
    return TOWING_BLOCK_MESSAGE
  end
  if string.find(instruction, TOWING_BLOCK_MESSAGE, 1, true) then
    return instruction
  end
  return string.format("%s\n%s", instruction, TOWING_BLOCK_MESSAGE)
end

local function removeTowBlockMessage(instruction)
  if not instruction or instruction == "" then
    return instruction
  end
  if instruction == TOWING_BLOCK_MESSAGE then
    return ""
  end
  local cleaned = string.gsub(instruction, "\n" .. TOWING_BLOCK_MESSAGE, "")
  return cleaned
end

local function isRecoveryPromptActive()
  if not (core_recoveryPrompt and core_recoveryPrompt.isActive) then
    return nil
  end
  local ok, active = pcall(core_recoveryPrompt.isActive)
  if ok then
    return active == true
  end
  return nil
end

local function setRecoveryPromptActive(active)
  if not core_recoveryPrompt then
    return false
  end
  if core_recoveryPrompt.setActive then
    local ok = pcall(core_recoveryPrompt.setActive, active)
    return ok
  end
  if core_recoveryPrompt.setEverythingActive then
    local ok = pcall(core_recoveryPrompt.setEverythingActive, active)
    return ok
  end
  return false
end

local function setVehicleRecoveryBlocked(blocked)
  local veh = getPlayerVeh()
  if not veh or not veh.queueLuaCommand then
    return false
  end

  local flag = blocked and "true" or "false"
  local cmd = string.format([[
    local recovery = extensions.recovery or recovery
    _G.btcRecoveryBlocked = %s
    if recovery and not recovery._btcWrapped then
      recovery._btcWrapped = true
      recovery._btcRecoverInPlace = recovery.recoverInPlace
      recovery._btcStartRecovering = recovery.startRecovering
      recovery.recoverInPlace = function(...)
        if not _G.btcRecoveryBlocked then
          return recovery._btcRecoverInPlace(...)
        end
      end
      recovery.startRecovering = function(...)
        if not _G.btcRecoveryBlocked then
          return recovery._btcStartRecovering(...)
        end
      end
    end
    if _G.btcRecoveryBlocked and recovery and recovery.stopRecovering then
      recovery.stopRecovering()
    end
  ]], flag)
  pcall(function() veh:queueLuaCommand(cmd) end)
  return true
end

local function setTowingBlocked(blocked)
  if S.towingBlocked then
    if S.recoveryPromptWasActive == nil or S.recoveryPromptWasActive == true then
      setRecoveryPromptActive(true)
    end
    setVehicleRecoveryBlocked(false)
    S.towingBlocked = false
    S.recoveryPromptWasActive = nil
    if S.hudInstruction then
      S.hudInstruction = removeTowBlockMessage(S.hudInstruction)
      if S.hudInstruction == "" then
        S.hudInstruction = nil
      end
    end
    markHudTrialDirty()
  end
end

local function hudTrialPayloadKey(payload)
  local weaponsKey = ""
  if type(payload.weapons) == "table" then
    local parts = {}
    for _, w in ipairs(payload.weapons) do
      parts[#parts + 1] = string.format("%s:%s", tostring(w.id or ""), tostring(w.ammo or ""))
    end
    weaponsKey = table.concat(parts, ",")
  end
  return table.concat({
    tostring(payload.title or ""),
    tostring(payload.tagline or ""),
    tostring(payload.status or ""),
    tostring(payload.instruction or ""),
    tostring(payload.threat or ""),
    tostring(payload.dangerReason or ""),
    tostring(payload.wallet or ""),
    tostring(payload.paused or ""),
    tostring(payload.preloaded or ""),
    weaponsKey,
  }, "|")
end

local function buildHudTrialPayload()
  ensureHudState()
  local walletAmount = tonumber(S.hudWallet) or 0
  return {
    title = CFG.windowTitle or "Bolides: The Cut",
    tagline = "You transport value, watch the road",
    status = (S.hudStatus and S.hudStatus ~= "") and S.hudStatus or "—",
    instruction = (S.hudInstruction and S.hudInstruction ~= "") and S.hudInstruction or "—",
    threat = getHudThreatLevel(),
    dangerReason = S.hudDangerReason or "",
    wallet = math.floor(walletAmount),
    weapons = cloneWeapons(S.hudWeapons),
    equippedWeapon = S.hudEquippedWeapon,
    paused = getHudPauseActive(),
    preloaded = getRobberPreloaded(),
  }
end

local function isHudTrialAppAvailable(apps)
  if not apps or type(apps.getAvailableApps) ~= "function" then
    return false
  end

  local ok, available = pcall(apps.getAvailableApps)
  if not ok or type(available) ~= "table" then
    return false
  end

  for _, entry in ipairs(available) do
    if entry == HUD_TRIAL.appName then
      return true
    end
    if type(entry) == "table" then
      local name = entry.name or entry.appName or entry.id
      if name == HUD_TRIAL.appName then
        return true
      end
    end
  end

  return false
end

local function isMessagesTasksContainerMounted(apps)
  if not apps or type(apps.getMessagesTasksAppContainerMounted) ~= "function" then
    return true
  end

  local containerName = HUD_TRIAL.containerName
  if containerName == nil or containerName == "" then
    local ok, mounted = pcall(apps.getMessagesTasksAppContainerMounted)
    if ok and type(mounted) == "boolean" then
      return mounted
    end
    return true
  end

  local ok, mounted = pcall(apps.getMessagesTasksAppContainerMounted, containerName)
  if ok and type(mounted) == "boolean" then
    return mounted
  end

  ok, mounted = pcall(apps.getMessagesTasksAppContainerMounted)
  if ok and type(mounted) == "boolean" then
    return mounted
  end

  return true
end

ensureHudTrialAppVisible = function(force)
  HUD_TRIAL.timeSinceEnsureVisible = force and math.huge or HUD_TRIAL.timeSinceEnsureVisible
  if not force and HUD_TRIAL.timeSinceEnsureVisible < HUD_TRIAL.ensureVisibleInterval then
    return false
  end

  local apps = ui_messagesTasksAppContainers
  if not apps then return false end
  if not isMessagesTasksContainerMounted(apps) then
    return false
  end
  if not isHudTrialAppAvailable(apps) then
    return false
  end

  local visible = nil
  if type(apps.getAppVisibility) == "function" then
    local ok, res = pcall(apps.getAppVisibility, HUD_TRIAL.appName)
    if ok then
      visible = res == true
    end
  end

  if visible == true and not force then
    HUD_TRIAL.timeSinceEnsureVisible = 0
    return true
  end

  if type(apps.showApp) == "function" then
    -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt
    pcall(apps.showApp, HUD_TRIAL.appName)
  elseif type(apps.setAppVisibility) == "function" then
    -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt
    pcall(apps.setAppVisibility, HUD_TRIAL.appName, true)
  end

  HUD_TRIAL.timeSinceEnsureVisible = 0
  return true
end

sendHudTrialPayload = function(force)
  local hooks = guihooks
  if not hooks or type(hooks.trigger) ~= "function" then
    return false
  end

  ensureHudTrialAppVisible(force)

  local payload = buildHudTrialPayload()
  local key = hudTrialPayloadKey(payload)
  local changed = key ~= HUD_TRIAL.lastPayloadKey

  if not force then
    if HUD_TRIAL.dirty ~= true and not changed and HUD_TRIAL.timeSinceEmit < HUD_TRIAL.forceEmitInterval then
      return false
    end
    if HUD_TRIAL.timeSinceEmit < HUD_TRIAL.emitInterval and not changed and HUD_TRIAL.dirty ~= true then
      return false
    end
  end

  -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt
  local ok = pcall(hooks.trigger, HUD_TRIAL.eventName, payload)
  if ok then
    HUD_TRIAL.lastPayloadKey = key
    HUD_TRIAL.dirty = false
    HUD_TRIAL.timeSinceEmit = 0
  end
  return ok
end

markHudTrialDirty = function()
  HUD_TRIAL.dirty = true
end

local function getHudWeaponById(id)
  if not id then return nil end
  ensureHudState()
  for _, w in ipairs(S.hudWeapons) do
    if w.id == id then
      return w
    end
  end
  return nil
end

local function consumeHudAmmo(id, amount)
  local w = getHudWeaponById(id)
  if not w then return false end
  local current = tonumber(w.ammo) or 0
  local delta = tonumber(amount) or 0
  w.ammo = math.max(0, current - delta)
  saveInventory()
  return true
end

local function triggerEmpOnNearestVehicle()
  local playerVeh = getPlayerVeh()
  local targetVeh, targetDist, targetErr = findNearestVehicleToPlayer()
  local targetInRange = targetDist ~= nil and targetDist <= 20.0
  if targetVeh and playerVeh and targetInRange then
    local ok, reason = EMP.trigger({
      playerId = targetVeh:getID(),
      sourceId = playerVeh:getID(),
      sourcePos = playerVeh:getPosition(),
      empDurationSec = 10.0,
      shockDurationSec = 0.5,
      thrusterKickSpeed = 5.0,
      forceMultiplier = 0.5,
      aiDisableDurationSec = 5.0,
    })
    if ok then
      return true
    end
    return false, reason
  end

  return false, targetErr or "out_of_range"
end

local function setHudEquippedWeapon(id)
  if id ~= "emp" and id ~= "pistol" then
    id = nil
  end

  if id == "pistol" then
    if FirstPersonShoot and FirstPersonShoot.setAimEnabled then
      local ok = FirstPersonShoot.setAimEnabled(true)
      if ok then
        S.hudEquippedWeapon = "pistol"
      else
        if S.hudEquippedWeapon == "pistol" then
          S.hudEquippedWeapon = nil
        end
      end
    else
      S.hudEquippedWeapon = "pistol"
    end
  elseif id == "emp" then
    if FirstPersonShoot and FirstPersonShoot.setAimEnabled then
      FirstPersonShoot.setAimEnabled(false)
    end
    S.hudEquippedWeapon = "emp"
  else
    if FirstPersonShoot and FirstPersonShoot.setAimEnabled then
      FirstPersonShoot.setAimEnabled(false)
    end
    S.hudEquippedWeapon = nil
  end

  markHudTrialDirty()
end

local function toggleHudWeapon(id)
  local weaponId = tostring(id or "")
  if weaponId == "" then
    return false
  end

  if weaponId == S.hudEquippedWeapon then
    setHudEquippedWeapon(nil)
    return true
  end

  setHudEquippedWeapon(weaponId)
  return true
end

local function setHudWeaponButtonHover(isHovering)
  S.hudWeaponButtonHover = isHovering and true or false
end

local function triggerHudEmp()
  local w = getHudWeaponById("emp")
  local ammo = w and tonumber(w.ammo) or 0
  if ammo <= 0 then
    return false, "out_of_ammo"
  end

  local ok, reason = triggerEmpOnNearestVehicle()
  if ok then
    consumeHudAmmo("emp", 1)
    markHudTrialDirty()
  end
  return ok, reason
end

local function handleEquippedEmpInput()
  if S.hudEquippedWeapon ~= "emp" then
    return
  end

  local imgui = ui_imgui
  if not imgui then
    return
  end

  local io = imgui.GetIO and imgui.GetIO() or nil
  if io and io.WantCaptureMouse then
    return
  end

  if S.hudWeaponButtonHover then
    return
  end

  if imgui.IsMouseClicked and imgui.IsMouseClicked(0) then
    local ok, reason = triggerHudEmp()
    if ok then
      log("I", "BolidesTheCut", "EMP deployed on nearest vehicle (HUD).")
    else
      log("W", "BolidesTheCut", "EMP deploy failed (HUD): " .. tostring(reason))
    end
  end
end

local function applyHudInventoryDelta(inventoryDelta)
  if type(inventoryDelta) ~= "table" then
    return
  end
  ensureHudState()

  for _, delta in ipairs(inventoryDelta) do
    local id = delta.id
    local ammoDelta = tonumber(delta.ammoDelta or 0) or 0
    if id then
      if isHudWeaponHidden(id) then
        goto continue
      end
      local existing = nil
      for _, w in ipairs(S.hudWeapons) do
        if w.id == id then
          existing = w
          break
        end
      end
      if not existing then
        local isEmp = id == "emp"
        existing = {
          id = id,
          name = delta.name or (isEmp and "EMP Device" or id),
          ammoLabel = delta.ammoLabel or (isEmp and "Charges" or "Ammo"),
          ammo = 0,
        }
        table.insert(S.hudWeapons, existing)
      end
      local nextAmmo = math.max(0, (tonumber(existing.ammo) or 0) + ammoDelta)
      local limit = HUD_WEAPON_AMMO_LIMITS[id]
      if limit then
        nextAmmo = math.min(nextAmmo, limit)
      end
      existing.ammo = nextAmmo
    end
    ::continue::
  end

  saveInventory()
end

function M.setNewHudState(payload)
  payload = payload or {}
  ensureHudState()

  if payload.threat then
    S.hudThreat = tostring(payload.threat)
  end
  if payload.status then
    S.hudStatus = tostring(payload.status)
  end
  if payload.instruction then
    local instruction = tostring(payload.instruction)
    if S.towingBlocked then
      instruction = addTowBlockMessage(instruction)
    else
      instruction = removeTowBlockMessage(instruction)
    end
    S.hudInstruction = instruction
  end
  if payload.dangerReason then
    S.hudDangerReason = tostring(payload.dangerReason)
  end

  if payload.moneyDelta then
    local delta = tonumber(payload.moneyDelta)
    if delta then
      S.hudWallet = (tonumber(S.hudWallet) or 0) + delta
    end
  end

  if payload.inventoryDelta then
    applyHudInventoryDelta(payload.inventoryDelta)
  end

  markHudTrialDirty()
  sendHudTrialPayload(true)
end

local EVENT_HOST = {
  Breadcrumbs = Breadcrumbs,
  getPlayerVeh = getPlayerVeh,
  postLine = postEventLine,
}

local function attachHostApi(host)
  if not host then return end
  host.showMissionMessage = M.showMissionMessage
  host.closeMissionMessage = M.closeMissionMessage
  host.showPopupMessage = M.showPopupMessage
  host.closePopupMessage = M.closePopupMessage
  host.setGuiStatusMessage = M.setGuiStatusMessage
  host.setNewHudState = M.setNewHudState
  host.requestHudTrialSnapshot = M.requestHudTrialSnapshot
end

-- =========================================================
-- AUDIO UTILITY (vehicle-side, version-tolerant)  [MATCHES OLDCODE]
-- =========================================================
local Audio = {}

local function resolveAudioVehicle(v)
  return getPlayerVeh() or v
end

function Audio.ensureSources(v, sources)
  v = resolveAudioVehicle(v)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__bolidesAudio = _G.__bolidesAudio or { ids = {} }",
    "local A = _G.__bolidesAudio.ids",
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

function Audio.ensurePooledSources(v, source)
  v = resolveAudioVehicle(v)
  if not v or not v.queueLuaCommand then return end
  if not source or not source.name or not source.file then return end

  local poolSize = tonumber(source.count) or tonumber(source.poolSize) or CFG.sfxGunshotPoolSize or 4
  poolSize = math.max(1, math.floor(poolSize))
  local name = tostring(source.name)
  local file = tostring(source.file)

  local cmd = string.format([[
    _G.__bolidesAudio = _G.__bolidesAudio or { ids = {}, pools = {} }
    local A = _G.__bolidesAudio.ids
    local P = _G.__bolidesAudio.pools
    local function mk(path, nm)
      if A[nm] then return end
      local id = obj:createSFXSource(path, "Audio2D", nm, 0)
      A[nm] = id
    end
    local base = %q
    local path = %q
    local count = %d
    P[base] = P[base] or { ids = {}, index = 1 }
    local pool = P[base]
    for i = 1, count do
      local nm = base .. "_" .. tostring(i)
      mk(path, nm)
      pool.ids[i] = nm
    end
    if (pool.index or 1) < 1 or (pool.index or 1) > count then
      pool.index = 1
    end
  ]], name, file, poolSize)

  v:queueLuaCommand(cmd)
end

function Audio.ensureIntro(v)
  Audio.ensureSources(v, {
    { file = CFG.sfxBolidesIntroFile, name = CFG.sfxBolidesIntroName }
  })
end

function Audio.playId(v, name, vol, pitch)
  if not CFG.audioEnabled then return end
  v = resolveAudioVehicle(v)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)

  local cmd = string.format([[
    if not (_G.__bolidesAudio and _G.__bolidesAudio.ids) then return end
    local id = _G.__bolidesAudio.ids[%q]
    if not id then return end

    if obj.setSFXSourceLooping then pcall(function() obj:setSFXSourceLooping(id, false) end) end
    if obj.setSFXSourceLoop then pcall(function() obj:setSFXSourceLoop(id, false) end) end
    if obj.stopSFX then pcall(function() obj:stopSFX(id) end) end
    if obj.stopSFXSource then pcall(function() obj:stopSFXSource(id) end) end

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

    if (not played) and obj.playSFXOnce then
      pcall(function() obj:playSFXOnce(%q, 0, %0.3f, %0.3f) end)
    end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, %0.3f) end) end
    if obj.setSFXSourcePitch  then pcall(function() obj:setSFXSourcePitch(id, %0.3f) end) end
  ]], name, vol, pitch, vol, pitch, vol, pitch, CFG.sfxBolidesIntroFile, vol, pitch, vol, pitch)

  v:queueLuaCommand(cmd)
end

function Audio.playFile(v, name, vol, pitch, file)
  if not CFG.audioEnabled then return end
  v = resolveAudioVehicle(v)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  file = tostring(file or "")

  local cmd = string.format([[
    if not (_G.__bolidesAudio and _G.__bolidesAudio.ids) then return end
    local id = _G.__bolidesAudio.ids[%q]
    if not id then return end

    if obj.setSFXSourceLooping then pcall(function() obj:setSFXSourceLooping(id, false) end) end
    if obj.setSFXSourceLoop then pcall(function() obj:setSFXSourceLoop(id, false) end) end
    if obj.stopSFX then pcall(function() obj:stopSFX(id) end) end
    if obj.stopSFXSource then pcall(function() obj:stopSFXSource(id) end) end
    if obj.stop then pcall(function() obj:stop(id) end) end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 1.0) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, 1.0) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, 1.0) end) end

    if obj.playSFX then
      pcall(function() obj:playSFX(id) end)
      pcall(function() obj:playSFX(id, 0) end)
      pcall(function() obj:playSFX(id, false) end)
      pcall(function() obj:playSFX(id, 0, false) end)
      pcall(function() obj:playSFX(id, 0, %0.3f, %0.3f, false) end)
      pcall(function() obj:playSFX(id, %0.3f, %0.3f, false) end)
      pcall(function() obj:playSFX(id, 0, false, %0.3f, %0.3f) end)
    end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, %0.3f) end) end
    if obj.setSFXSourcePitch  then pcall(function() obj:setSFXSourcePitch(id, %0.3f) end) end
  ]], name, vol, pitch, vol, pitch, vol, pitch, vol, pitch, vol, pitch)

  v:queueLuaCommand(cmd)
end

function Audio.playPooledFile(v, name, vol, pitch, file)
  if not CFG.audioEnabled then return end
  v = resolveAudioVehicle(v)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  file = tostring(file or "")

  local cmd = string.format([[
    if not (_G.__bolidesAudio and _G.__bolidesAudio.ids) then return end
    local A = _G.__bolidesAudio.ids
    local P = _G.__bolidesAudio.pools or {}
    local pool = P[%q]
    if not pool or not pool.ids or #pool.ids == 0 then return end
    local idx = pool.index or 1
    if idx > #pool.ids then idx = 1 end
    local nm = pool.ids[idx]
    pool.index = idx + 1
    if pool.index > #pool.ids then pool.index = 1 end
    local id = A[nm]
    if not id then return end

    if obj.setSFXSourceLooping then pcall(function() obj:setSFXSourceLooping(id, false) end) end
    if obj.setSFXSourceLoop then pcall(function() obj:setSFXSourceLoop(id, false) end) end

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
  ]], name, vol, pitch, vol, pitch, vol, pitch, file, file, vol, pitch, vol, pitch)

  v:queueLuaCommand(cmd)
end

function Audio.playGunshot(v)
  if not CFG.audioEnabled then return end
  local source = {
    file = CFG.sfxGunshotFile,
    name = CFG.sfxGunshotName,
    count = CFG.sfxGunshotPoolSize,
  }
  Audio.ensurePooledSources(v, source)
  Audio.playPooledFile(v, CFG.sfxGunshotName, CFG.sfxGunshotVol, CFG.sfxGunshotPitch, CFG.sfxGunshotFile)
end

function Audio.playPlayerGunshot(v)
  if not CFG.audioEnabled then return end
  local source = {
    file = CFG.sfxPlayerGunshotFile,
    name = CFG.sfxPlayerGunshotName,
    count = CFG.sfxPlayerGunshotPoolSize,
  }
  Audio.ensurePooledSources(v, source)
  Audio.playPooledFile(
    v,
    CFG.sfxPlayerGunshotName,
    CFG.sfxPlayerGunshotVol,
    CFG.sfxPlayerGunshotPitch,
    CFG.sfxPlayerGunshotFile
  )
end

function Audio.stopId(v, name)
  v = resolveAudioVehicle(v)
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

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 0.0) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, 0.0) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, 0.0) end) end
  ]], name)

  v:queueLuaCommand(cmd)
end

handleAboutIntroAudio = function(showing)
  local v = getPlayerVeh()
  if not v then return end
  Audio.ensureIntro(v)
  if showing then
    Audio.stopId(v, CFG.sfxBolidesIntroName)
    Audio.playId(v, CFG.sfxBolidesIntroName, CFG.bolidesIntroVol, CFG.bolidesIntroPitch)
  else
    Audio.stopId(v, CFG.sfxBolidesIntroName)
  end
end

-- =========================
-- GUI (safe to call ONLY from onDrawDebug, and wrapped in pcall there)
-- =========================
local function drawGui()
  if not CFG.windowVisible then return end
  local imgui = ui_imgui
  if not imgui then return end

  imgui.SetNextWindowSize(imgui.ImVec2(460, 740), imgui.Cond_FirstUseEver)

  ensureHudState()
  local currentMoney = getCareerMoney()
  if currentMoney ~= nil then
    S.hudWallet = currentMoney
  end

  local function getHudTint()
    local threat = getHudThreatLevel()
    if threat == "danger" then
      return imgui.ImColorByRGB(89, 13, 13, 235).Value
    end
    if threat == "event" then
      return imgui.ImColorByRGB(89, 71, 13, 235).Value
    end
    return imgui.ImColorByRGB(13, 51, 20, 235).Value
  end

  local windowColor = getHudTint()

  imgui.PushStyleColor2(imgui.Col_WindowBg, windowColor)
  local openPtr = imgui.BoolPtr(CFG.windowVisible)
  if imgui.Begin(CFG.windowTitle, openPtr) then
    CFG.windowVisible = openPtr[0]

    local baseTextScale = 1.05

    -- Header (New HUD)
    imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(242, 214, 128, 255).Value)
    imgui.SetWindowFontScale(1.25)
    imgui.Text(CFG.windowTitle)
    imgui.SetWindowFontScale(baseTextScale)
    imgui.PopStyleColor()

    imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(170, 210, 255, 210).Value)
    imgui.TextWrapped("You transport value, watch the road")
    local countdown = BoldiePacing and BoldiePacing.getCountdown and BoldiePacing.getCountdown()
    if countdown ~= nil then
      imgui.Text(string.format("next event occurs in: %s", formatCountdown(countdown)))
    end
    imgui.PopStyleColor()

    imgui.Spacing()
    if imgui.Button("About") then
      S.uiShowAbout = not S.uiShowAbout
      if type(handleAboutIntroAudio) == "function" then
        handleAboutIntroAudio(S.uiShowAbout)
      end
    end

    imgui.SameLine()
    imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(235, 235, 235, 230).Value)
    local walletAmount = tonumber(S.hudWallet) or 0
    imgui.Text(string.format("Wallet: $%d", math.floor(walletAmount)))
    imgui.PopStyleColor()

    if S.uiShowAbout then
      imgui.Separator()
      imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(210, 210, 210, 220).Value)
      imgui.TextWrapped("Bolides: The Cut drops you into an unpredictable career—where every run carries risk, every job builds pressure, and the road can turn into a pursuit at any moment. Stay sharp, protect your earnings, and watch the road.")
      imgui.PopStyleColor()
    end

    -- Narrative (New HUD)
    imgui.Separator()
    local threatLevel = getHudThreatLevel()
    local statusScale = baseTextScale
    if threatLevel == "event" or threatLevel == "danger" then
      statusScale = baseTextScale + 0.05
    end
    imgui.SetWindowFontScale(statusScale)
    imgui.Text("STATUS")
    imgui.TextWrapped((S.hudStatus and S.hudStatus ~= "") and S.hudStatus or "—")

    imgui.Spacing()
    imgui.Text("INSTRUCTION")
    imgui.TextWrapped((S.hudInstruction and S.hudInstruction ~= "") and S.hudInstruction or "—")
    imgui.SetWindowFontScale(baseTextScale)

    -- Weapons (New HUD)
    imgui.Separator()
    local weaponsLabel = S.uiShowWeapons and "Hide Weapons / Inventory" or "Show Weapons / Inventory"
    if imgui.Button(weaponsLabel, imgui.ImVec2(-1, 0)) then
      S.uiShowWeapons = not S.uiShowWeapons
    end

    if S.uiShowWeapons then
      imgui.Spacing()
      for i = 1, #S.hudWeapons do
        local w = S.hudWeapons[i]
        if isHudWeaponHidden(w.id) then
          goto continue
        end
        local ammo = tonumber(w.ammo) or 0
        local label = w.ammoLabel or "Ammo"

        imgui.Text(w.name or w.id or "Unknown")
        imgui.Text(string.format("%s: %d", label, ammo))
        if w.id == "emp" then
          local _, dist, err = findNearestVehicleToPlayer()
          local inRange = dist ~= nil and dist <= 20.0
          if dist ~= nil then
            imgui.TextWrapped(inRange and "Nearest vehicle in range (20m)" or "Nearest vehicle out of range (20m)")
          else
            imgui.TextWrapped("No nearby vehicle.")
          end
          local btnText = "Use"
          if ammo <= 0 then
            imgui.BeginDisabled()
            imgui.Button(btnText .. "##" .. tostring(w.id))
            imgui.EndDisabled()
          else
            if imgui.Button(btnText .. "##" .. tostring(w.id)) then
              local ok, reason = triggerEmpOnNearestVehicle()
              if ok then
                w.ammo = math.max(0, ammo - 1)
                log("I", "BolidesTheCut", "EMP deployed on nearest vehicle.")
              else
                log("W", "BolidesTheCut", "EMP deploy failed: " .. tostring(reason))
              end
            end
          end
        elseif w.id == "pistol" then
          local aimEnabled = FirstPersonShoot and FirstPersonShoot.isAimEnabled and FirstPersonShoot.isAimEnabled()
          local aimLabel = aimEnabled and "Reholster Pistol" or "Unholster Pistol"

          if ammo <= 0 then
            imgui.BeginDisabled()
            imgui.Button(aimLabel .. "##pistol_aim")
            imgui.EndDisabled()
          else
            if imgui.Button(aimLabel .. "##pistol_aim") then
              FirstPersonShoot.toggleAim()
            end
          end

          imgui.TextWrapped(S.hudShotgunHitPoint or "Raycast hit: --")

          if not aimEnabled then
            imgui.TextWrapped(S.hudShotgunMessage or "Unholster to aim.")
          else
            imgui.TextWrapped(S.hudShotgunMessage or "Aim and left-click to fire.")
          end
        else
          local btnText = "Fire"
          if ammo <= 0 then
            imgui.BeginDisabled()
            imgui.Button(btnText .. "##" .. tostring(w.id))
            imgui.EndDisabled()
          else
            if imgui.Button(btnText .. "##" .. tostring(w.id)) then
              w.ammo = math.max(0, ammo - 1)
              log("I", "BolidesTheCut", "Weapon fired: " .. tostring(w.id))
            end
          end
        end
        imgui.Spacing()
        ::continue::
      end
    end

    -- Breathing room + subtle divider
    imgui.Spacing()
    imgui.Separator()


    local TR, crumbs, totalFwd = Breadcrumbs.getTravel()
    local fwdCache, fwdMeta, spacings = Breadcrumbs.getForwardKnown()
    local backMetersList, _, isBackReady = Breadcrumbs.getBack()

    imgui.SetWindowFontScale(1.0)

    -- =========================
    -- Manual Events
    -- =========================
    imgui.Separator()
    local manualEventsLabel = S.uiShowManualEvents and "Hide Manual Events" or "Manual Events"
    if imgui.Button(manualEventsLabel, imgui.ImVec2(-1, 0)) then
      S.uiShowManualEvents = not S.uiShowManualEvents
    end

    if S.uiShowManualEvents then
      imgui.Spacing()
      if imgui.Button("EMP test (nearest vehicle)", imgui.ImVec2(-1, 0)) then
        local playerVeh = getPlayerVeh()
        local targetVeh, dist, err = findNearestVehicleToPlayer()
        if playerVeh and targetVeh then
          local ok, reason = EMP.trigger({
            playerId = targetVeh:getID(),
            sourceId = playerVeh:getID(),
            sourcePos = playerVeh:getPosition(),
          })
          if ok then
            S.empTestStatus = string.format("EMP test fired at %.1f m.", dist or 0)
          else
            S.empTestStatus = "EMP test failed: " .. tostring(reason)
          end
        else
          S.empTestStatus = "EMP test skipped: " .. tostring(err)
        end
      end

      if S.empTestStatus and S.empTestStatus ~= "" then
        imgui.TextWrapped(S.empTestStatus)
      end

      if imgui.Button("Bullet Damage", imgui.ImVec2(-1, 0)) then
        local playerVeh = getPlayerVeh()
        if playerVeh then
          local ok, info = BulletDamage.trigger({
            targetId = playerVeh:getID(),
            accuracyRadius = 1.5,
          })
          if ok then
            local lines = { "Bullet damage triggered on player." }
            if info then
              lines[#lines + 1] = string.format("Impact force queued: %s", info.impactQueued and "yes" or "no")
              lines[#lines + 1] = string.format("Gunshot audio: %s", info.audioPlayed and "played" or (info.audioAttempted and "attempted" or "not available"))
              if info.damage then
                lines[#lines + 1] = string.format("Damage queued: %s", info.damage.queued and "yes" or "no")
                local effects = info.damage.effects or {}
                lines[#lines + 1] = string.format("Break random part chance: %.0f%%", (effects.breakRandomPart or 0) * 100)
                lines[#lines + 1] = string.format("Deform random part chance: %.0f%%", (effects.deformRandomPart or 0) * 100)
                lines[#lines + 1] = string.format("Deflate tire chance: %.0f%%", (effects.deflateTire or 0) * 100)
                lines[#lines + 1] = string.format("Ignite part chance: %.0f%%", (effects.ignitePart or 0) * 100)
                lines[#lines + 1] = string.format("Break random beam chance: %.0f%%", (effects.breakRandomBeam or 0) * 100)
                local safety = info.damage.safety or {}
                lines[#lines + 1] = string.format(
                  "Safety filters: wheels=%s, powertrain=%s, brittle=%s, fallback=%s",
                  safety.ignoreWheels and "on" or "off",
                  safety.ignorePowertrain and "on" or "off",
                  safety.ignoreBrittleDeform and "on" or "off",
                  safety.allowFallback and "on" or "off"
                )
              end
            end
            S.bulletDamageStatus = table.concat(lines, "\n")
            S.bulletDamageStatusLines = lines
          else
            S.bulletDamageStatus = "Bullet damage failed: " .. tostring(info)
            S.bulletDamageStatusLines = nil
          end
        else
          S.bulletDamageStatus = "Bullet damage skipped: no player vehicle."
          S.bulletDamageStatusLines = nil
        end
      end

      if S.bulletDamageStatusLines and #S.bulletDamageStatusLines > 0 then
        for _, line in ipairs(S.bulletDamageStatusLines) do
          imgui.TextWrapped(line)
        end
      elseif S.bulletDamageStatus and S.bulletDamageStatus ~= "" then
        imgui.TextWrapped(S.bulletDamageStatus)
      end

      if imgui.Button("RobberEMP", imgui.ImVec2(-1, 0)) then
        RobberEMP.triggerManual()
      end

      if imgui.Button("End RobberEMP", imgui.ImVec2(-1, 0)) then
        RobberEMP.endEvent()
      end

      local st = RobberEMP.status and RobberEMP.status() or ""
      if st and st ~= "" then
        imgui.TextWrapped("RobberEMP: " .. st)
      end
      local spawnMethod = RobberEMP.getSpawnMethod and RobberEMP.getSpawnMethod() or ""
      if spawnMethod and spawnMethod ~= "" then
        imgui.TextWrapped("RobberEMP spawn method: " .. spawnMethod)
      end

      if imgui.Button("RobberShotgun event (spawn @ FKB 200m)", imgui.ImVec2(-1, 0)) then
        RobberShotgun.triggerManual()
      end

      if imgui.Button("End RobberShotgun", imgui.ImVec2(-1, 0)) then
        RobberShotgun.endEvent()
      end

      local sg = RobberShotgun.status and RobberShotgun.status() or ""
      if sg and sg ~= "" then
        imgui.TextWrapped("RobberShotgun: " .. sg)
      end
      local sgSpawn = RobberShotgun.getSpawnMethod and RobberShotgun.getSpawnMethod() or ""
      if sgSpawn and sgSpawn ~= "" then
        imgui.TextWrapped("RobberShotgun spawn method: " .. sgSpawn)
      end

      if imgui.Button("Fire Attack (Pigeon)", imgui.ImVec2(-1, 0)) then
        if FireAttack and FireAttack.isActive and FireAttack.isActive() then
          FireAttack.endEvent()
        else
          FireAttack.triggerManual()
        end
      end

      local fireStatus = FireAttack.status and FireAttack.status() or ""
      if fireStatus and fireStatus ~= "" then
        imgui.TextWrapped("FireAttack: " .. fireStatus)
      end

    end

    -- =========================
    -- Debug (moved under About)
    -- =========================
    imgui.Separator()
    local debugLabel = S.uiShowDebug and "Hide debug" or "Debug"
    if imgui.Button(debugLabel, imgui.ImVec2(-1, 0)) then
      S.uiShowDebug = not S.uiShowDebug
    end

    if S.uiShowDebug then
      imgui.Spacing()
      if imgui.Button("Add +5 ammo (Rifled Slugs + EMP)", imgui.ImVec2(-1, 0)) then
        applyHudInventoryDelta({
          { id = "pistol", name = "Pistol", ammoLabel = "Ammo", ammoDelta = 5 },
          { id = "emp", name = "EMP Device", ammoLabel = "Charges", ammoDelta = 5 },
        })
      end

      imgui.Spacing()
      if imgui.Button("Dump BeamNG API (0.38)", imgui.ImVec2(-1, 0)) then
        extensions.load("apiDump")
        if extensions.apiDump and extensions.apiDump.dump then
          local ok, err, jsonPath, textPath = extensions.apiDump.dump({
            outputDir = CFG.apiDumpOutputDir,
          })
          if ok then
            S.apiDumpStatus = string.format("API dump written to %s and %s", textPath or "?", jsonPath or "?")
            log("I", "Bolides", "API dump complete")
          else
            S.apiDumpStatus = err or "API dump failed to write"
            log("E", "Bolides", S.apiDumpStatus)
          end
        else
          S.apiDumpStatus = "apiDump extension missing or failed to load"
          log("E", "Bolides", "apiDump extension missing or failed to load")
        end
      end
      if S.apiDumpStatus and S.apiDumpStatus ~= "" then
        imgui.TextWrapped(S.apiDumpStatus)
      end

      imgui.Spacing()
      imgui.Text(string.format("Crumb every: %.2f m", (TR.crumbEveryMeters or 0)))
      imgui.Text(string.format("Crumb keep: %.0f m", (TR.keepMeters or 0)))
      imgui.Text(string.format("Crumbs: %d", #crumbs))
      imgui.Text(string.format("Forward dist: %.0f m", totalFwd or 0))

      imgui.Spacing()
      imgui.Text("RobberEMP money/debug:")
      local robberDebug = RobberEMP.getDebugState and RobberEMP.getDebugState() or nil
      if robberDebug then
        local activeText = robberDebug.careerActive and "yes" or "no"
        imgui.Text(string.format("Career active: %s", activeText))
        local moneyText = robberDebug.money and string.format("$%s", CareerMoney.fmt(robberDebug.money)) or "n/a"
        imgui.Text(string.format("Wallet (CareerMoney.get): %s", moneyText))
        local robbedText = robberDebug.robbedAmount and CareerMoney.fmt(robberDebug.robbedAmount) or "n/a"
        imgui.Text(string.format("Robbery processed: %s", tostring(robberDebug.robberyProcessed)))
        imgui.Text(string.format("Robbed amount: %s", robbedText))
        imgui.Text(string.format("EMP fired: %s", tostring(robberDebug.empFired)))
        imgui.Text(string.format("EMP pre-stop triggered: %s", tostring(robberDebug.empPreStopTriggered)))
        imgui.Text(string.format("EMP slow chase applied: %s", tostring(robberDebug.empSlowChaseApplied)))
        imgui.Text(string.format("EMP flee triggered: %s", tostring(robberDebug.empFleeTriggered)))
        imgui.Text(string.format("Success triggered: %s", tostring(robberDebug.successTriggered)))
        imgui.Text(string.format("Phase: %s", tostring(robberDebug.phase)))
      else
        imgui.Text("RobberEMP debug unavailable.")
      end

      imgui.Spacing()
      imgui.Text("ForwardKnownBreadcrumbs:")

      local segText = fwdMeta.segStartIdx and tostring(fwdMeta.segStartIdx) or "n/a"
      local dirText = fwdMeta.dir and tostring(fwdMeta.dir) or "n/a"
      local distText = fwdMeta.distToProjection and string.format("%.2f m", fwdMeta.distToProjection) or "n/a"
      imgui.Text(string.format("Anchor segStartIdx: %s", segText))
      imgui.Text(string.format("Anchor dir: %s, distToProjection: %s", dirText, distText))

      for i = 1, #spacings do
        local spacing = spacings[i]
        local a = fwdCache[spacing] or {}

        local status = "Not"
        if a.available then
          status = (a.eligible and "Available" or "Known")
        end

        local distA = a.distAhead and string.format("%.0f m", a.distAhead) or "-"
        local dirA = a.dir and tostring(a.dir) or "n/a"
        imgui.Text(string.format("%dm: %s, dist ahead: %s, dir: %s", spacing, status, distA, dirA))
      end

      imgui.Spacing()
      imgui.Text("PreloadEvent debug:")
      if PreloadEvent and PreloadEvent.getDebugState then
        local preloadDebug = PreloadEvent.getDebugState()
        imgui.Text(string.format("Pending: %s", tostring(preloadDebug.pending)))
        imgui.Text(string.format("Preloaded: %s", tostring(preloadDebug.preloaded)))
        imgui.Text(string.format("Preloaded ID: %s", tostring(preloadDebug.preloadedId)))
        imgui.Text(string.format("Placed: %s", tostring(preloadDebug.placed)))
        imgui.Text(string.format("Direction: %s", tostring(preloadDebug.direction)))
        imgui.Text(string.format("Window start: %s", tostring(preloadDebug.windowStart)))
        imgui.Text(string.format("Window seconds: %s", tostring(preloadDebug.windowSeconds)))
        imgui.Text(string.format("Min delay: %s", tostring(preloadDebug.minDelay)))
        imgui.Text(string.format("Last attempt: %s", tostring(preloadDebug.lastAttemptAt)))
        imgui.Text(string.format("Attempts: %s / %s", tostring(preloadDebug.attemptCount), tostring(preloadDebug.maxAttempts)))
        imgui.Text(string.format("UI token: %s (last attempted: %s)", tostring(preloadDebug.uiPauseToken), tostring(preloadDebug.lastUiPauseTokenAttempted)))
        imgui.Text(string.format("In progress: %s", tostring(preloadDebug.preloadInProgress)))
        imgui.Text(string.format("UI override: %s", tostring(preloadDebug.uiGateOverride)))
      else
        imgui.Text("PreloadEvent debug unavailable.")
      end

      imgui.Spacing()
      imgui.Text("Back breadcrumbs ready:")
      for i = 1, #backMetersList do
        local backMeters = backMetersList[i]
        local ready = isBackReady(backMeters)
        imgui.Text(string.format("%dm back ready: %s", backMeters, ready and "yes" or "no"))
      end

      imgui.Spacing()
      local markerLabel = CFG.debugBreadcrumbMarkers and "Debug Breadcrumb Markers: ON" or "Debug Breadcrumb Markers: OFF"
      if imgui.Button(markerLabel, imgui.ImVec2(-1, 0)) then
        CFG.debugBreadcrumbMarkers = not CFG.debugBreadcrumbMarkers
        Breadcrumbs.setDebugMarkersEnabled(CFG.debugBreadcrumbMarkers)
      end

      if S.testDumpTruckStatus and S.testDumpTruckStatus ~= "" then
        imgui.Text(S.testDumpTruckStatus)
      end
    end
  end
  imgui.End()
  imgui.PopStyleColor()
end

-- =========================
-- Extension hooks
-- =========================
function M.onExtensionLoaded()
  attachHostApi(EVENT_HOST)
  if _G and _G.Host then
    attachHostApi(_G.Host)
  end

  ensureHudState()
  markHudTrialDirty()
  ensureHudTrialAppVisible(true)
  sendHudTrialPayload(true)

  Breadcrumbs.init(CFG, S)
  Breadcrumbs.reset()

  -- init events
  if RobberEMP and RobberEMP.init then
    RobberEMP.init(CFG, EVENT_HOST)
  end
  if RobberShotgun and RobberShotgun.init then
    RobberShotgun.init(CFG, EVENT_HOST)
  end
  if FireAttack and FireAttack.init then
    FireAttack.init(CFG, EVENT_HOST)
  end
  if BoldiePacing and BoldiePacing.init then
    BoldiePacing.init(CFG, EVENT_HOST, {
      RobberEMP = RobberEMP,
      RobberShotgun = RobberShotgun,
    }, function(nextName, opts)
      if not S.preloadIntroShown then
        S.preloadIntroShown = true
        M.showPopupMessage({
          id = "preload_intro",
          title = "Welcome",
          body = "Welcome to Bolide-the Cut (preloading...)",
          continueLabel = "Continue",
          nextEventName = nextName,
          preloadOpts = opts,
          preloadStatus = "Preloading next event...",
          canContinue = false,
          preloadSuccessBody = "Welcome to Bolide-the Cut (preload successful)",
          preloadSuccessPlacementLabel = "Preload position:",
          once = true,
          freeze = true,
        })
        return true
      end
      return M.requestEventPreloadByName(nextName, opts)
    end)
  end
  if PreloadEvent and PreloadEvent.init then
    PreloadEvent.init(CFG, EVENT_HOST)
    if RobberEMP and RobberEMP.getPreloadSpec and PreloadEvent.request then
      local spec = RobberEMP.getPreloadSpec()
      if spec then
        pcall(PreloadEvent.request, spec)
      end
    end
  end

  if FirstPersonShoot and FirstPersonShoot.init then
    FirstPersonShoot.init({
      getAmmo = function()
        local w = getHudWeaponById("pistol")
        return w and tonumber(w.ammo) or 0
      end,
      consumeAmmo = function(amount)
        return consumeHudAmmo("pistol", amount or 1)
      end,
      getPlayerVeh = getPlayerVeh,
      isInputBlocked = function()
        return S.hudWeaponButtonHover
      end,
      onShot = function(ok, info, hitPos)
        S.hudShotgunHitPoint = formatHitPoint(hitPos)
        if ok then
          S.hudShotgunMessage = "DIRECT HIT"
        else
          if type(info) == "string" then
            if info == "no_vehicle_hit" then
              S.hudShotgunMessage = "NO VEHICLE HIT"
            elseif info == "out_of_ammo" then
              S.hudShotgunMessage = "OUT OF AMMO"
            elseif info == "self_hit_blocked" then
              S.hudShotgunMessage = "SHOT BLOCKED"
            else
              S.hudShotgunMessage = "MISSED"
            end
          else
            S.hudShotgunMessage = "MISSED"
          end
        end
      end,
      onAimChanged = function(enabled, reason)
        if enabled then
          S.hudShotgunMessage = "Aim and left-click to fire."
          S.hudEquippedWeapon = "pistol"
        else
          if reason == "not_first_person" then
            S.hudShotgunMessage = "First-person view only."
          elseif reason == "no_ammo" then
            S.hudShotgunMessage = "Out of ammo."
          end
          if S.hudEquippedWeapon == "pistol" then
            S.hudEquippedWeapon = nil
          end
        end
        markHudTrialDirty()
      end,
    })
  end
end

-- Update-only: NO drawing here (prevents loading hang)
function M.onUpdate(dtReal, dtSim, dtRaw)
  Breadcrumbs.update(dtSim)

  local dt = tonumber(dtSim) or 0
  HUD_TRIAL.timeSinceEmit = (HUD_TRIAL.timeSinceEmit or 0) + dt
  HUD_TRIAL.timeSinceEnsureVisible = (HUD_TRIAL.timeSinceEnsureVisible or 0) + dt
  POPUP.timeSinceEmit = (POPUP.timeSinceEmit or 0) + dt

  if HUD_TRIAL.dirty or HUD_TRIAL.timeSinceEmit >= HUD_TRIAL.emitInterval then
    local currentMoney = getCareerMoney()
    if currentMoney ~= nil then
      local prevMoney = tonumber(S.hudWallet) or 0
      if math.floor(prevMoney) ~= math.floor(currentMoney) then
        S.hudWallet = currentMoney
        markHudTrialDirty()
      end
    end
  end

  if HUD_TRIAL.timeSinceEnsureVisible >= HUD_TRIAL.ensureVisibleInterval then
    ensureHudTrialAppVisible(false)
  end

  local hudPaused = getHudPauseActive()
  if hudPaused ~= S.hudPauseActive then
    S.hudPauseActive = hudPaused
    markHudTrialDirty()
  end

  if HUD_TRIAL.dirty or HUD_TRIAL.timeSinceEmit >= HUD_TRIAL.emitInterval then
    sendHudTrialPayload(false)
  end

  if S.popupActive and S.popupWaitingForPreload then
    if isPopupPreloadReady() then
      updatePopupPreloadSuccessMessage()
      S.popupWaitingForPreload = false
      if PreloadEvent and PreloadEvent.setUiGateOverride then
        pcall(PreloadEvent.setUiGateOverride, false)
      end
      if S.popupDismissed then
        finalizePopup("continue")
      else
        markPopupDirty()
      end
    end
  end

  if POPUP.dirty or POPUP.timeSinceEmit >= POPUP.emitInterval then
    sendPopupPayload(false)
  end

  local threatLevel = getHudThreatLevel()
  setTowingBlocked(threatLevel == "event" or threatLevel == "danger")

  if EMP and EMP.onUpdate then
    EMP.onUpdate(dtReal, dtSim, dtRaw)
  end

  if FirstPersonShoot and FirstPersonShoot.onUpdate then
    FirstPersonShoot.onUpdate(dtSim)
  end

  if RobberEMP and RobberEMP.update then
    RobberEMP.update(dtSim)
  end
  if RobberShotgun and RobberShotgun.update then
    RobberShotgun.update(dtSim)
  end
  if FireAttack and FireAttack.update then
    FireAttack.update(dtSim)
  end
  if BoldiePacing and BoldiePacing.update then
    BoldiePacing.update(dtSim)
  end
  if PreloadEvent and PreloadEvent.update then
    PreloadEvent.update(dtSim)
  end
end

function M.requestEventPreload(spec)
  if not (PreloadEvent and PreloadEvent.request) then
    return false
  end
  return PreloadEvent.request(spec)
end

function M.requestEventPreloadByName(name, opts)
  if not name then return false end
  local spec = nil
  if name == "RobberEMP" and RobberEMP and RobberEMP.getPreloadSpec then
    spec = RobberEMP.getPreloadSpec()
  elseif name == "RobberShotgun" and RobberShotgun and RobberShotgun.getPreloadSpec then
    spec = RobberShotgun.getPreloadSpec()
  end
  if not spec then
    return false
  end
  if type(opts) == "table" then
    for k, v in pairs(opts) do
      if spec[k] == nil then
        spec[k] = v
      end
    end
  end
  return M.requestEventPreload(spec)
end

function M.startEvent(name, cfg)
  if name == "RobberEMP" then
    return RobberEMP.triggerManual()
  end
  if name == "RobberShotgun" then
    return RobberShotgun.triggerManual()
  end
  if name == "FireAttack" then
    return FireAttack.triggerManual()
  end
  return false
end

function M.stopEvent(name)
  if name == "RobberEMP" then
    RobberEMP.endEvent()
    return true
  end
  if name == "RobberShotgun" then
    RobberShotgun.endEvent()
    return true
  end
  if name == "FireAttack" then
    FireAttack.endEvent()
    return true
  end
  return false
end

-- Draw-only: safe gating + pcall (Codex working pattern)
function M.onDrawDebug()
  -- safe draw UI
  pcall(drawGui)

  handleEquippedEmpInput()

  if FirstPersonShoot and FirstPersonShoot.onDraw then
    pcall(FirstPersonShoot.onDraw)
  end

  -- safe draw markers (keep behind CFG gate)
  if CFG.debugBreadcrumbMarkers and Breadcrumbs.onDrawDebug then
    pcall(Breadcrumbs.onDrawDebug)
  end
end


M.Audio = Audio
M.toggleHudWeapon = toggleHudWeapon
M.setHudWeaponButtonHover = setHudWeaponButtonHover

return M
