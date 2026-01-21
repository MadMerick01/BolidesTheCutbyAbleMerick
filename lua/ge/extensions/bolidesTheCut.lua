-- lua/ge/extensions/bolidesTheCut.lua
-- BolidesTheCut (fresh rebuild): GUI + About/Hide Info + Intro audio (OldCode-style) + Breadcrumb debug UI
-- Requires:
--   lua/ge/extensions/breadcrumbs.lua
--   lua/ge/extensions/events/RobberEMP.lua
--   lua/ge/extensions/events/RobberShotgun.lua

local M = {}

local Breadcrumbs = require("lua/ge/extensions/breadcrumbs")
local RobberFKB200mEMP = require("lua/ge/extensions/events/RobberEMP")
local RobberShotgun = require("lua/ge/extensions/events/RobberShotgun")
local BoldiePacing = require("lua/ge/extensions/events/BoldiePacing")
local FireAttack = require("lua/ge/extensions/events/fireAttack")
local EMP = require("lua/ge/extensions/events/emp")
local BulletDamage = require("lua/ge/extensions/events/BulletDamage")
local DeflateRandomTyre = require("lua/ge/extensions/events/deflateRandomTyre")
local CareerMoney = require("CareerMoney")

-- =========================
-- Config
-- =========================
local CFG = {
  windowTitle = "Bolides: The Cut",
  windowVisible = false,
  bannerEnabled = true,
  bannerImagePath = "/art/ui/bolides_the_cut/bolides_the_cut_banner.png",
  bannerAspect = 0.562,
  bannerMaxHeight = 210,

  -- Debug marker gate (Codex-safe pattern)
  debugBreadcrumbMarkers = false,
  debugButtons = true,

  -- Make FKB show A LOT for now (you can tighten later)
  forwardKnownCheckIntervalSec = 0.10,
  forwardKnownMinAheadMeters = 0.0,
  forwardKnownMaxAheadMeters = 5000.0,

  -- Travel / crumb settings (breadcrumbs.lua reads CFG.TRAVEL)
  TRAVEL = {
    crumbEveryMeters = 1.0,
    keepMeters = 5200.0,
    teleportResetMeters = 50.0,
  },

  -- Audio
  audioEnabled = true,
  sfxBolidesIntroFile = "/art/sound/bolides/BolidesIntroWav.wav",
  sfxBolidesIntroName = "bolidesIntroHit",
  bolidesIntroVol = 4.0,
  bolidesIntroPitch = 1.0,

  -- GUI threat coloring
  threatDistanceRobber = 50.0,
  threatDistanceFireAttack = 100.0,
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

  guiStatusMessage = "Nothing unusual",

  hudWallet = nil,
  hudWeapons = nil,
  hudStatus = "",
  hudInstruction = "",
  hudThreat = nil,
  hudDangerReason = nil,

  uiShowWeapons = false,
  uiShowAbout = false,
}

local UI = {
  bannerTexture = nil,
  bannerLoadFailed = false,
}

-- =========================
-- Mission Info Message Wrapper (module scope)
-- =========================
M._missionMsg = {
  open = false,
  prevTimeScale = 1,
  onClose = nil,
  onContinue = nil,
  reason = nil,
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

local function closeMissionInfoDialogue()
  if extensions and extensions.missionInfo and extensions.missionInfo.closeDialogue then
    pcall(extensions.missionInfo.closeDialogue)
  end
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

  checkEvent(RobberFKB200mEMP, CFG.threatDistanceRobber)
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

function M.showMissionMessage(args)
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
    M._missionMsg.prevTimeScale = getTimeScaleSafe()
    setTimeScaleSafe(0)
  else
    M._missionMsg.prevTimeScale = nil
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
end

function M._missionContinue()
  if not M._missionMsg.open then
    return
  end

  closeMissionInfoDialogue()

  if M._missionMsg.prevTimeScale ~= nil then
    setTimeScaleSafe(M._missionMsg.prevTimeScale or 1)
  end

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
  if not M._missionMsg.open then
    return
  end

  M._missionMsg.reason = reason
  closeMissionInfoDialogue()

  if M._missionMsg.prevTimeScale ~= nil then
    setTimeScaleSafe(M._missionMsg.prevTimeScale or 1)
  end

  M._missionMsg.open = false
  M._missionMsg.onClose = nil
  M._missionMsg.onContinue = nil

  missionLog("I", string.format("Mission message closed (%s).", tostring(reason or "closed")))
end

-- Called by your UI bootstrap app:
-- extensions.bolidesTheCut.setWindowVisible(true)
function M.setWindowVisible(v)
  CFG.windowVisible = (v == true)
end

function M.setGuiStatusMessage(msg)
  if not msg or msg == "" then
    S.guiStatusMessage = "Nothing unusual"
    return
  end
  S.guiStatusMessage = tostring(msg)
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
  { id = "beretta1301", name = "Beretta 1301", ammoLabel = "Rifled Slugs", ammo = 0 },
  { id = "emp", name = "EMP Device", ammoLabel = "Charges", ammo = 0 },
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
  if id == "beretta92fs" then
    id = "beretta1301"
  end
  local defaultName = id == "beretta1301" and "Beretta 1301" or id
  local defaultLabel = id == "beretta1301" and "Rifled Slugs" or "Ammo"
  return {
    id = id,
    name = tostring(entry.name or defaultName),
    ammoLabel = tostring(entry.ammoLabel or defaultLabel),
    ammo = math.max(0, tonumber(entry.ammo or 0) or 0),
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
      existing.ammo = math.max(0, (tonumber(existing.ammo) or 0) + ammoDelta)
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
    S.hudInstruction = tostring(payload.instruction)
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
  host.setGuiStatusMessage = M.setGuiStatusMessage
  host.setNewHudState = M.setNewHudState
end

-- =========================================================
-- AUDIO UTILITY (vehicle-side, version-tolerant)  [MATCHES OLDCODE]
-- =========================================================
local Audio = {}

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

  v:queueLuaCommand(table.concat(lines, "\n"))
end

function Audio.ensureIntro(v)
  Audio.ensureSources(v, {
    { file = CFG.sfxBolidesIntroFile, name = CFG.sfxBolidesIntroName }
  })
end

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

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 0.0) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, 0.0) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, 0.0) end) end
  ]], name)

  v:queueLuaCommand(cmd)
end

local function handleAboutIntroAudio(showing)
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

local function ensureBannerTexture(imgui)
  if UI.bannerTexture or UI.bannerLoadFailed then return end
  if not imgui or type(imgui.LoadTexture) ~= "function" then
    UI.bannerLoadFailed = true
    return
  end
  local ok, tex = pcall(imgui.LoadTexture, CFG.bannerImagePath)
  if ok and tex then
    UI.bannerTexture = tex
  else
    UI.bannerLoadFailed = true
    missionLog("W", "Failed to load GUI banner texture: " .. tostring(CFG.bannerImagePath))
  end
end

local function drawBanner(imgui)
  if not CFG.bannerEnabled then return end
  ensureBannerTexture(imgui)
  if not UI.bannerTexture or type(imgui.Image) ~= "function" then return end
  if type(imgui.GetContentRegionAvail) ~= "function" then return end
  local avail = imgui.GetContentRegionAvail()
  local width = avail and avail.x or 0
  if not width or width <= 0 then return end
  local height = width * (CFG.bannerAspect or 0.562)
  if CFG.bannerMaxHeight and height > CFG.bannerMaxHeight then
    height = CFG.bannerMaxHeight
  end
  imgui.Image(UI.bannerTexture, imgui.ImVec2(width, height))
  imgui.Spacing()
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

    drawBanner(imgui)

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
      handleAboutIntroAudio(S.uiShowAbout)
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
                })
                if ok then
                  w.ammo = math.max(0, ammo - 1)
                  log("I", "BolidesTheCut", "EMP deployed on nearest vehicle.")
                else
                  log("W", "BolidesTheCut", "EMP deploy failed: " .. tostring(reason))
                end
              else
                log("W", "BolidesTheCut", "EMP deploy blocked (no nearby target or out of range).")
                if targetErr then
                  log("W", "BolidesTheCut", "EMP deploy blocked reason: " .. tostring(targetErr))
                end
              end
            end
          end
        elseif w.id == "beretta1301" then
          local nearestVeh, nearestDist = findNearestVehicleToPlayer()
          local driverChance = distanceChance(nearestDist, 10.0, 60.0, 0.35, 0.05)
          local tyreChance = distanceChance(nearestDist, 10.0, 60.0, 0.6, 0.15)
          imgui.TextWrapped(formatChanceLine("Nearest driver hit chance", driverChance))
          imgui.TextWrapped(formatChanceLine("Nearest tyre hit chance", tyreChance))

          if ammo <= 0 then
            imgui.BeginDisabled()
            imgui.Button("Shoot driver##shotgun_driver")
            imgui.Button("Shoot tyres##shotgun_tyres")
            imgui.EndDisabled()
          else
            if imgui.Button("Shoot driver##shotgun_driver") then
              if nearestVeh and driverChance then
                w.ammo = math.max(0, ammo - 1)
                if math.random() < driverChance then
                  disableRobberAI(nearestVeh)
                  log("I", "BolidesTheCut", "Driver shot landed; AI disabled.")
                else
                  local ok = BulletDamage.trigger({
                    targetId = nearestVeh:getID(),
                    accuracyRadius = 3.0,
                    applyDamage = false,
                  })
                  if not ok then
                    log("W", "BolidesTheCut", "Driver shot missed; fallback hit failed.")
                  end
                end
              else
                log("W", "BolidesTheCut", "Driver shot blocked (no nearby target).")
              end
            end
            if imgui.Button("Shoot tyres##shotgun_tyres") then
              if nearestVeh and tyreChance then
                w.ammo = math.max(0, ammo - 1)
                if math.random() < tyreChance then
                  local ok = BulletDamage.trigger({
                    targetId = nearestVeh:getID(),
                    accuracyRadius = 3.0,
                    applyDamage = false,
                  })
                  if not ok then
                    log("W", "BolidesTheCut", "Tyre shot triggered but hit failed.")
                  end
                end
              else
                log("W", "BolidesTheCut", "Tyre shot blocked (no nearby target).")
              end
            end
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
            accuracyRadius = 3.0,
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
        RobberFKB200mEMP.triggerManual()
      end

      if imgui.Button("End RobberEMP", imgui.ImVec2(-1, 0)) then
        RobberFKB200mEMP.endEvent()
      end

      local st = RobberFKB200mEMP.status and RobberFKB200mEMP.status() or ""
      if st and st ~= "" then
        imgui.TextWrapped("RobberFKB200mEMP: " .. st)
      end
      local spawnMethod = RobberFKB200mEMP.getSpawnMethod and RobberFKB200mEMP.getSpawnMethod() or ""
      if spawnMethod and spawnMethod ~= "" then
        imgui.TextWrapped("RobberFKB200mEMP spawn method: " .. spawnMethod)
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
          { id = "beretta1301", name = "Beretta 1301", ammoLabel = "Rifled Slugs", ammoDelta = 5 },
          { id = "emp", name = "EMP Device", ammoLabel = "Charges", ammoDelta = 5 },
        })
      end

      imgui.Spacing()
      imgui.Text(string.format("Crumb every: %.2f m", (TR.crumbEveryMeters or 0)))
      imgui.Text(string.format("Crumb keep: %.0f m", (TR.keepMeters or 0)))
      imgui.Text(string.format("Crumbs: %d", #crumbs))
      imgui.Text(string.format("Forward dist: %.0f m", totalFwd or 0))

      imgui.Spacing()
      imgui.Text("RobberFKB200mEMP money/debug:")
      local robberDebug = RobberFKB200mEMP.getDebugState and RobberFKB200mEMP.getDebugState() or nil
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
        imgui.Text("RobberFKB200mEMP debug unavailable.")
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

  Breadcrumbs.init(CFG, S)
  Breadcrumbs.reset()

  -- init events
  if RobberFKB200mEMP and RobberFKB200mEMP.init then
    RobberFKB200mEMP.init(CFG, EVENT_HOST)
  end
  if RobberShotgun and RobberShotgun.init then
    RobberShotgun.init(CFG, EVENT_HOST)
  end
  if FireAttack and FireAttack.init then
    FireAttack.init(CFG, EVENT_HOST)
  end
  if BoldiePacing and BoldiePacing.init then
    BoldiePacing.init(CFG, EVENT_HOST, {
      RobberFKB200mEMP = RobberFKB200mEMP,
      RobberShotgun = RobberShotgun,
    })
  end
end

-- Update-only: NO drawing here (prevents loading hang)
function M.onUpdate(dtReal, dtSim, dtRaw)
  Breadcrumbs.update(dtSim)

  if EMP and EMP.onUpdate then
    EMP.onUpdate(dtReal, dtSim, dtRaw)
  end

  if RobberFKB200mEMP and RobberFKB200mEMP.update then
    RobberFKB200mEMP.update(dtSim)
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

function M.startEvent(name, cfg)
  if name == "RobberFKB200mEMP" then
    return RobberFKB200mEMP.triggerManual()
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
  if name == "RobberFKB200mEMP" then
    RobberFKB200mEMP.endEvent()
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

  -- safe draw markers (keep behind CFG gate)
  if CFG.debugBreadcrumbMarkers and Breadcrumbs.onDrawDebug then
    pcall(Breadcrumbs.onDrawDebug)
  end
end


M.Audio = Audio

return M
