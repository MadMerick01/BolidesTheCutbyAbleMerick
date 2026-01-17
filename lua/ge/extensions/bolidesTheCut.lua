-- lua/ge/extensions/bolidesTheCut.lua
-- BolidesTheCut (fresh rebuild): GUI + About/Hide Info + Intro audio (OldCode-style) + Breadcrumb debug UI
-- Requires:
--   lua/ge/extensions/breadcrumbs.lua
--   lua/ge/extensions/events/RobberFkb200mEMP.lua

local M = {}

local Breadcrumbs = require("lua/ge/extensions/breadcrumbs")
local RobberFKB200mEMP = require("lua/ge/extensions/events/RobberFkb200mEMP")
local FireAttack = require("lua/ge/extensions/events/fireAttack")
local WarningShots = require("lua/ge/extensions/events/WarningShots")
local EMP = require("lua/ge/extensions/events/emp")
local Bullets = require("lua/ge/extensions/events/bullets")
local BulletDamage = require("lua/ge/extensions/events/BulletDamage")
local SmashRandomWindow = require("lua/ge/extensions/events/smashRandomWindow")
local DeflateRandomTyre = require("lua/ge/extensions/events/deflateRandomTyre")
local CareerMoney = require("CareerMoney")

-- =========================
-- Config
-- =========================
local CFG = {
  windowTitle = "Bolides: Risk • Pressure • Pursuit",
  windowVisible = false,

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
}

-- =========================
-- Runtime state
-- =========================
local S = {
  uiShowInfo = false,
  uiShowDebug = false,

  -- Kept because OldCode printed these lines; safe placeholders for now
  testDumpTruckVehId = nil,
  testDumpTruckStatus = "",
  empTestStatus = "",
  bulletImpactStatus = "",
  bulletDamageStatus = "",

  guiStatusMessage = "Nothing unusual",
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

-- =========================
-- GUI (safe to call ONLY from onDrawDebug, and wrapped in pcall there)
-- =========================
local function drawGui()
  if not CFG.windowVisible then return end
  local imgui = ui_imgui
  if not imgui then return end

  imgui.SetNextWindowSize(imgui.ImVec2(460, 740), imgui.Cond_FirstUseEver)

  local openPtr = imgui.BoolPtr(CFG.windowVisible)
  if imgui.Begin(CFG.windowTitle, openPtr) then
    CFG.windowVisible = openPtr[0]

    -- Header: Title + tagline (subtle, professional)
imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(235, 235, 235, 255).Value)
imgui.SetWindowFontScale(1.15)
imgui.Text(CFG.windowTitle)
imgui.SetWindowFontScale(1.0)
imgui.PopStyleColor()

-- Tagline (muted, slightly spaced)
imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(200, 200, 200, 180).Value)
imgui.SetWindowFontScale(0.95)
imgui.TextWrapped("You transport value, watch the road")
imgui.SetWindowFontScale(1.0)
imgui.PopStyleColor()

-- Breathing room + subtle divider
imgui.Spacing()
imgui.Separator()


    local TR, crumbs, totalFwd = Breadcrumbs.getTravel()
    local fwdCache, fwdMeta, spacings = Breadcrumbs.getForwardKnown()
    local backMetersList, _, isBackReady = Breadcrumbs.getBack()

    imgui.SetWindowFontScale(1.5)
    imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(0, 255, 0, 255).Value)
    CareerMoney.draw(imgui)
    imgui.PopStyleColor()
    imgui.SetWindowFontScale(1.0)

    -- =========================
    -- Status Messages
    -- =========================
    imgui.Separator()
    imgui.Text("Whats Happening?")
    imgui.SetWindowFontScale(2.0)
    imgui.PushStyleColor2(imgui.Col_Text, imgui.ImColorByRGB(255, 0, 0, 255).Value)
    imgui.TextWrapped(S.guiStatusMessage or "Nothing unusual")
    imgui.PopStyleColor()
    imgui.SetWindowFontScale(1.0)

    -- =========================
    -- Manual Events
    -- =========================
    imgui.Separator()
    imgui.Text("Manual Events:")

    if imgui.Button("TEST MISSION MESSAGE", imgui.ImVec2(-1, 0)) then
      M.showMissionMessage({
        title = "TEST",
        text = "Scenario-style message.\n\nPress Continue.",
        freeze = true,
      })
    end

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

    if imgui.Button("Bullet impact player", imgui.ImVec2(-1, 0)) then
      local playerVeh = getPlayerVeh()
      if playerVeh then
        local ok, reason = Bullets.trigger({
          playerId = playerVeh:getID(),
        })
        if ok then
          S.bulletImpactStatus = "Bullet impact triggered on player."
        else
          S.bulletImpactStatus = "Bullet impact failed: " .. tostring(reason)
        end
      else
        S.bulletImpactStatus = "Bullet impact skipped: no player vehicle."
      end
    end

    if S.bulletImpactStatus and S.bulletImpactStatus ~= "" then
      imgui.TextWrapped(S.bulletImpactStatus)
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

    if CFG.debugButtons then
      if imgui.Button("Smash random window (player)", imgui.ImVec2(-1, 0)) then
        SmashRandomWindow.trigger(Host, CFG)
      end
    end

    if imgui.Button("RobberFKB200mEMP event (spawn @ FKB 200m)", imgui.ImVec2(-1, 0)) then
      RobberFKB200mEMP.triggerManual()
    end

    if imgui.Button("End RobberFKB200mEMP", imgui.ImVec2(-1, 0)) then
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

    if imgui.Button("Start Warning Shots", imgui.ImVec2(-1, 0)) then
      M.startEvent("WarningShots")
    end

    if imgui.Button("Stop Warning Shots", imgui.ImVec2(-1, 0)) then
      M.stopEvent("WarningShots")
    end

    local warningStatus = WarningShots and WarningShots.status and WarningShots.status() or ""
    if warningStatus and warningStatus ~= "" then
      imgui.TextWrapped("WarningShots: " .. warningStatus)
    end

    if CFG.debugButtons then
      if imgui.Button("Deflate random tyre (player)", imgui.ImVec2(-1, 0)) then
        DeflateRandomTyre.trigger(Host, CFG)
      end
    end

    -- =========================
    -- About / Hide Info
    -- =========================
    imgui.Separator()

    local wasInfo = S.uiShowInfo
    local btnLabel = S.uiShowInfo and "Hide info" or "About"
    if imgui.Button(btnLabel, imgui.ImVec2(-1, 0)) then
      S.uiShowInfo = not S.uiShowInfo
      local v = getPlayerVeh()
      if v then
        Audio.ensureIntro(v)
        if S.uiShowInfo and (not wasInfo) then
          Audio.playId(v, CFG.sfxBolidesIntroName, CFG.bolidesIntroVol, CFG.bolidesIntroPitch)
        elseif (not S.uiShowInfo) and wasInfo then
          Audio.stopId(v, CFG.sfxBolidesIntroName)
        end
      end
    end

    if S.uiShowInfo then
      imgui.Spacing()
      imgui.TextWrapped("BolidesTheCut\n\n- About opens this panel and plays the intro.\n- Hide info closes the panel and stops/mutes the intro.\n\nBreadcrumb system is running continuously and exposing debug lines above.")
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
      imgui.Text(string.format("Crumb every: %.2f m", (TR.crumbEveryMeters or 0)))
      imgui.Text(string.format("Crumb keep: %.0f m", (TR.keepMeters or 0)))
      imgui.Text(string.format("Crumbs: %d", #crumbs))
      imgui.Text(string.format("Forward dist: %.0f m", totalFwd or 0))

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
end

-- =========================
-- Extension hooks
-- =========================
function M.onExtensionLoaded()
  attachHostApi(EVENT_HOST)
  if _G and _G.Host then
    attachHostApi(_G.Host)
  end

  Breadcrumbs.init(CFG, S)
  Breadcrumbs.reset()

  -- init events
  if RobberFKB200mEMP and RobberFKB200mEMP.init then
    RobberFKB200mEMP.init(CFG, EVENT_HOST)
  end
  if FireAttack and FireAttack.init then
    FireAttack.init(CFG, EVENT_HOST)
  end
  if WarningShots and WarningShots.init then
    WarningShots.init(CFG, EVENT_HOST)
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
  if FireAttack and FireAttack.update then
    FireAttack.update(dtSim)
  end
  if WarningShots and WarningShots.update then
    WarningShots.update(dtSim)
  end
end

function M.startEvent(name, cfg)
  if name == "WarningShots" then
    return WarningShots.start(EVENT_HOST, cfg or CFG)
  end
  if name == "RobberFKB200mEMP" then
    return RobberFKB200mEMP.triggerManual()
  end
  if name == "FireAttack" then
    return FireAttack.triggerManual()
  end
  return false
end

function M.stopEvent(name)
  if name == "WarningShots" then
    WarningShots.stop("user")
    return true
  end
  if name == "RobberFKB200mEMP" then
    RobberFKB200mEMP.endEvent()
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
