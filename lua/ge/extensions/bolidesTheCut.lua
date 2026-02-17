-- lua/ge/extensions/bolidesTheCut.lua
-- BolidesTheCut (fresh rebuild): HUD-first runtime (legacy ImGui panel removed)
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
local FirstPersonShoot = require("lua/ge/extensions/FirstPersonShoot")
local DeflateRandomTyre = require("lua/ge/extensions/events/deflateRandomTyre")
local CareerMoney = require("CareerMoney")

local markHudTrialDirty
local ensureHudTrialAppVisible
local sendHudTrialPayload
local getPlayerVeh
local Audio = {}

-- =========================
-- Config
-- =========================
local CFG = {
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
  pacingModeDefault = "real",

  -- Messaging
  popupMessagesEnabled = false,
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
  hudPreloadPromptActive = false,
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
  return false
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
  markHudTrialDirty()
end

handleAboutHudAudio = function(showing)
  local v = getPlayerVeh and getPlayerVeh() or nil
  if not v then
    if not showing then
      return
    end
    M.setGuiStatusMessage("About audio unavailable: no player vehicle yet.")
    return
  end
  Audio.ensureIntro(v)
  if showing then
    Audio.stopId(v, CFG.sfxBolidesIntroName)
    Audio.playId(v, CFG.sfxBolidesIntroName, CFG.bolidesIntroVol, CFG.bolidesIntroPitch)
  else
    Audio.stopId(v, CFG.sfxBolidesIntroName)
  end
end

function M.toggleHudAbout()
  local playerVeh = getPlayerVeh and getPlayerVeh() or nil
  if not playerVeh then
    S.uiShowAbout = false
    M.setGuiStatusMessage("Purchase/spawn a vehicle to enable About audio.")
    markHudTrialDirty()
    return false
  end

  S.uiShowAbout = not S.uiShowAbout
  handleAboutHudAudio(S.uiShowAbout)
  markHudTrialDirty()
  return true
end

function M.setHudPacingMode(mode)
  if BoldiePacing and BoldiePacing.setMode then
    BoldiePacing.setMode(mode)
    markHudTrialDirty()
    sendHudTrialPayload(true)
    return true
  end
  return false
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
  return true
end

local function finalizePopup(reason)
  local msg = S.popupActive
  local pauseState = S.popupPauseState

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

  ensureHudTrialAppVisible(true)
  markPopupDirty()
  sendPopupPayload(true)
  return true
end

function M.showPopupMessage(args)
  if not CFG.popupMessagesEnabled then
    return false
  end
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
  if not CFG.popupMessagesEnabled then
    local title = tostring(args and args.title or "")
    local text = tostring(args and (args.text or args.body) or "")
    local combined = ""
    if title ~= "" and text ~= "" then
      combined = string.format("%s: %s", title, text)
    else
      combined = text ~= "" and text or title
    end
    if combined ~= "" then
      M.setGuiStatusMessage(combined)
    end
    return true
  end
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

function M.setWindowVisible(v)
  -- Legacy no-op kept for backward compatibility with older bootstrap scripts.
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

getPlayerVeh = function()
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
  appName = "BolideTheCutHUD",
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

local function getHudTrialContainerName()
  if HUD_TRIAL.containerName ~= nil and HUD_TRIAL.containerName ~= "" then
    return HUD_TRIAL.containerName
  end
  HUD_TRIAL.containerName = "messagesTasks"
  return HUD_TRIAL.containerName
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
  local preloadKey = ""
  if type(payload.preloadDebug) == "table" then
    local pd = payload.preloadDebug
    preloadKey = table.concat({
      tostring(pd.ready or ""),
      tostring(pd.owner or ""),
      tostring(pd.specKey or ""),
      tostring(pd.pending or ""),
      tostring(pd.placed or ""),
      tostring(pd.anchorReady or ""),
      tostring(pd.anchorDistance or ""),
      tostring(pd.anchorFarEnough or ""),
      tostring(pd.lastFailure or ""),
      tostring(pd.consumeCount or ""),
      tostring(pd.stashCount or ""),
      tostring(pd.parkingFallbacks or ""),
      tostring(pd.empPending or ""),
      tostring(pd.empPendingAttempts or ""),
      tostring(pd.empPendingEta or ""),
      tostring(pd.shotgunPending or ""),
      tostring(pd.shotgunPendingAttempts or ""),
      tostring(pd.shotgunPendingEta or ""),
      tostring(pd.coldSpawnAllowed or ""),
    }, ":")
  end

  return table.concat({
    tostring(payload.title or ""),
    tostring(payload.tagline or ""),
    tostring(payload.status or ""),
    tostring(payload.threat or ""),
    tostring(payload.dangerReason or ""),
    tostring(payload.wallet or ""),
    tostring(payload.hasPlayerVehicle or ""),
    tostring(payload.paused or ""),
    tostring(payload.preloaded or ""),
    tostring(payload.preloadAvailable or ""),
    tostring(payload.pacingMode or ""),
    tostring(payload.pendingPacingMode or ""),
    preloadKey,
    weaponsKey,
  }, "|")
end

local function buildHudTrialPayload()
  ensureHudState()
  local walletAmount = tonumber(S.hudWallet) or 0
  local empPending = RobberEMP and RobberEMP.getPendingStartState and RobberEMP.getPendingStartState() or nil
  local shotgunPending = RobberShotgun and RobberShotgun.getPendingStartState and RobberShotgun.getPendingStartState() or nil

  local function secondsUntil(ts)
    if type(ts) ~= "number" then return nil end
    return math.max(0, ts - os.clock())
  end

  return {
    title = "Bolides: The Cut",
    tagline = "You transport value, watch the road",
    status = (S.hudStatus and S.hudStatus ~= "") and S.hudStatus or "—",
    threat = getHudThreatLevel(),
    dangerReason = S.hudDangerReason or "",
    wallet = math.floor(walletAmount),
    weapons = cloneWeapons(S.hudWeapons),
    equippedWeapon = S.hudEquippedWeapon,
    hasPlayerVehicle = getPlayerVeh() ~= nil,
    paused = getHudPauseActive(),
    preloaded = getRobberPreloaded(),
    preloadAvailable = false,
    preloadDebug = {
      ready = false,
      owner = nil,
      specKey = nil,
      pending = nil,
      placed = nil,
      anchorReady = false,
      anchorDistance = nil,
      anchorFarEnough = false,
      lastFailure = nil,
      consumeCount = 0,
      stashCount = 0,
      parkingFallbacks = 0,
      empPending = empPending and empPending.pending or false,
      empPendingAttempts = empPending and empPending.attempts or 0,
      empPendingEta = secondsUntil(empPending and empPending.deadline or nil),
      shotgunPending = shotgunPending and shotgunPending.pending or false,
      shotgunPendingAttempts = shotgunPending and shotgunPending.attempts or 0,
      shotgunPendingEta = secondsUntil(shotgunPending and shotgunPending.deadline or nil),
      coldSpawnAllowed = true,
    },
    pacingMode = BoldiePacing and BoldiePacing.getMode and BoldiePacing.getMode() or (CFG.pacingModeDefault or "real"),
    pendingPacingMode = BoldiePacing and BoldiePacing.getPendingMode and BoldiePacing.getPendingMode() or nil,
  }
end

local function isHudTrialAppAvailable(apps)
  if not apps or type(apps.getAvailableApps) ~= "function" then
    return false
  end

  local containerName = HUD_TRIAL.containerName
  if containerName == nil or containerName == "" then
    return false
  end

  local ok, available = pcall(apps.getAvailableApps, containerName)
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
    return true
  end

  local ok, mounted = pcall(apps.getMessagesTasksAppContainerMounted, containerName)
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
    local ok, res
    if HUD_TRIAL.containerName ~= nil and HUD_TRIAL.containerName ~= "" then
      ok, res = pcall(apps.getAppVisibility, HUD_TRIAL.appName, HUD_TRIAL.containerName)
    else
      ok, res = pcall(apps.getAppVisibility, HUD_TRIAL.appName)
    end
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
    if HUD_TRIAL.containerName ~= nil and HUD_TRIAL.containerName ~= "" then
      pcall(apps.showApp, HUD_TRIAL.appName, HUD_TRIAL.containerName)
    else
      pcall(apps.showApp, HUD_TRIAL.appName)
    end
  elseif type(apps.setAppVisibility) == "function" then
    -- API dump ref: docs/beamng-api/raw/api_dump_0.38.txt
    if HUD_TRIAL.containerName ~= nil and HUD_TRIAL.containerName ~= "" then
      pcall(apps.setAppVisibility, HUD_TRIAL.appName, true, HUD_TRIAL.containerName)
    else
      pcall(apps.setAppVisibility, HUD_TRIAL.appName, true)
    end
  end

  HUD_TRIAL.timeSinceEnsureVisible = 0
  return true
end

sendHudTrialPayload = function(force)
  local hooks = guihooks
  if not hooks or type(hooks.trigger) ~= "function" then
    return false
  end

  if force then
    ensureHudTrialAppVisible(true)
  end

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
  host.setHudPacingMode = M.setHudPacingMode
end

-- =========================================================
-- AUDIO UTILITY (vehicle-side, version-tolerant)  [MATCHES OLDCODE]
-- =========================================================
Audio = Audio or {}

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

-- Legacy ImGui debug panel removed for release; HUD app is the only display path.

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
    }, nil)
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
      S.popupWaitingForPreload = false
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
end

function M.requestEventPreload(spec)
  return false
end

function M.requestEventPreloadByName(name, opts)
  return false
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
  handleEquippedEmpInput()

  if FirstPersonShoot and FirstPersonShoot.onDraw then
    pcall(FirstPersonShoot.onDraw)
  end
end


M.Audio = Audio
M.toggleHudWeapon = toggleHudWeapon
M.setHudWeaponButtonHover = setHudWeaponButtonHover
M.setHudPacingMode = M.setHudPacingMode

return M
