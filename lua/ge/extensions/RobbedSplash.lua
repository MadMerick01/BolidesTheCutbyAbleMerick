-- lua/ge/extensions/RobbedSplash.lua
-- Standalone fullscreen splash overlay + time freeze.
-- Usage (from any other GE extension):
--   extensions.load("RobbedSplash")                         -- once (optional if auto-loaded)
--   if extensions.RobbedSplash then
--     extensions.RobbedSplash.trigger(2.5, "YOU'VE BEEN ROBBED")
--   end

local M = {}
local imgui = ui_imgui
local bigFont = nil

-- --------------------------
-- Safe bitwise OR
-- --------------------------
local bor = nil
if bit and bit.bor then
  bor = bit.bor
elseif bit32 and bit32.bor then
  bor = bit32.bor
else
  -- Fallback: sum flags (imgui flags are powers of two)
  bor = function(...)
    local r = 0
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      if type(v) == "number" then r = r + v end
    end
    return r
  end
end

-- --------------------------
-- Runtime
-- --------------------------
local S = {
  active = false,
  msg = "YOU'VE BEEN ROBBED",
  sub = "Chase the robber!",
  startClock = 0,
  requireFreshKey = false,
  keyDownAtStart = false,

  -- Background dim alpha (0..1)
  dimAlpha = 0.70,

  -- Time scale restore
  prevTimeScale = 1,

  -- If true, we will attempt to restore to prevTimeScale; otherwise restore to 1
  restorePrev = true,
}

-- --------------------------
-- Time scale helpers (robust)
-- --------------------------
local function getTimeScaleSafe()
  -- Some builds expose getTimeScale()
  if type(getTimeScale) == "function" then
    local ok, v = pcall(getTimeScale)
    if ok and type(v) == "number" then
      return v
    end
  end
  -- Default if unknown
  return 1
end

local function setTimeScaleSafe(v)
  v = tonumber(v) or 1

  -- Most common
  if type(setTimeScale) == "function" then
    pcall(setTimeScale, v)
    return true
  end

  -- Some builds expose simTimeAuthority pause (no direct scale)
  if simTimeAuthority and type(simTimeAuthority.setPause) == "function" then
    pcall(simTimeAuthority.setPause, v <= 0)
    return true
  end

  return false
end

local function pauseNow()
  S.prevTimeScale = getTimeScaleSafe()
  setTimeScaleSafe(0)
end

local function resumeNow()
  local restore = 1
  if S.restorePrev and type(S.prevTimeScale) == "number" and S.prevTimeScale > 0 then
    restore = S.prevTimeScale
  end
  setTimeScaleSafe(restore)
end

-- --------------------------
-- Public API
-- --------------------------
function M.isActive()
  return S.active
end

function M.stop()
  if not S.active then return end
  S.active = false
  resumeNow()
end

local function isAnyKeyDown()
  local io = imgui.GetIO()
  if not io or not io.KeysDown then return false end
  for i = 0, 511 do
    if io.KeysDown[i] then
      return true
    end
  end
  return false
end

local function shouldCloseOnKey()
  local anyDown = isAnyKeyDown()
  if S.requireFreshKey then
    if not anyDown then
      S.requireFreshKey = false
    end
    return false
  end
  return anyDown
end

function M.trigger(durationSec, message, subMessage)
  if type(message) == "string" and message ~= "" then
    S.msg = message
  else
    S.msg = "YOU'VE BEEN ROBBED"
  end

  if type(subMessage) == "string" and subMessage ~= "" then
    S.sub = subMessage
  else
    S.sub = "Chase the robber!"
  end

  S.startClock = os.clock()
  S.active = true
  S.keyDownAtStart = isAnyKeyDown()
  S.requireFreshKey = S.keyDownAtStart
  pauseNow()
end

-- --------------------------
-- Drawing (fullscreen ImGui overlay)
-- --------------------------
local function drawOverlay()
  if not S.active then return end

  local now = os.clock()
  if shouldCloseOnKey() then
    S.active = false
    resumeNow()
    return
  end

  local io = imgui.GetIO()
  local w, h = io.DisplaySize.x, io.DisplaySize.y

  -- Fullscreen, click-through overlay window
  imgui.SetNextWindowPos(imgui.ImVec2(0, 0), imgui.Cond_Always)
  imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond_Always)

  local flags = bor(
    imgui.WindowFlags_NoDecoration,
    imgui.WindowFlags_NoMove,
    imgui.WindowFlags_NoSavedSettings,
    imgui.WindowFlags_NoBringToFrontOnFocus,
    imgui.WindowFlags_NoInputs
  )

  imgui.PushStyleColor(imgui.Col_WindowBg, imgui.ImVec4(0, 0, 0, 0))
  imgui.Begin("##RobbedSplashOverlay", nil, flags)

  local dl = imgui.GetWindowDrawList()

  -- Dim background
  dl:AddRectFilled(
    imgui.ImVec2(0, 0),
    imgui.ImVec2(w, h),
    imgui.GetColorU32(imgui.ImVec4(0, 0, 0, S.dimAlpha))
  )

  local age = now - S.startClock
  local punchDuration = 0.2
  local shakeDuration = 0.3
  local punch = 0
  if age <= punchDuration then
    punch = (1 - (age / punchDuration)) * 1.25
  end
  local shakePx = 2.5
  local sx, sy = 0, 0
  if age <= shakeDuration then
    sx = (math.random() - 0.5) * shakePx
    sy = (math.random() - 0.5) * shakePx
  end

  -- Colors
  local text = tostring(S.msg)
  local sub  = tostring(S.sub)

  local mainScale = 1.6
  local subScale = 1.15
  local paddingX = 64
  local paddingY = 40
  local spacing = 12

  local baseMainSize = imgui.CalcTextSize(text)
  local baseSubSize = imgui.CalcTextSize(sub)
  local mainSize = imgui.ImVec2(baseMainSize.x * mainScale, baseMainSize.y * mainScale)
  local subSize = imgui.ImVec2(baseSubSize.x * subScale, baseSubSize.y * subScale)

  local boxWidth = math.max(mainSize.x, subSize.x) + (paddingX * 2)
  local boxHeight = mainSize.y + subSize.y + (paddingY * 2) + spacing
  local boxX = (w - boxWidth) * 0.5
  local boxY = (h - boxHeight) * 0.5

  -- Message box
  dl:AddRectFilled(
    imgui.ImVec2(boxX, boxY),
    imgui.ImVec2(boxX + boxWidth, boxY + boxHeight),
    imgui.GetColorU32(imgui.ImVec4(0.05, 0.05, 0.05, 0.85))
  )
  dl:AddRect(
    imgui.ImVec2(boxX, boxY),
    imgui.ImVec2(boxX + boxWidth, boxY + boxHeight),
    imgui.GetColorU32(imgui.ImVec4(1, 1, 1, 0.15))
  )

  -- Main text
  local textX = boxX + (boxWidth - mainSize.x) * 0.5
  local textY = boxY + paddingY
  imgui.SetCursorScreenPos(imgui.ImVec2(textX + sx, textY + sy))
  imgui.SetWindowFontScale(mainScale + (punch * 0.02))
  imgui.PushStyleColor(imgui.Col_Text, imgui.ImVec4(0.92, 0.12, 0.12, 1.00))
  imgui.Text(text)
  imgui.PopStyleColor()

  -- Subtext
  local subX = boxX + (boxWidth - subSize.x) * 0.5
  local subY = textY + mainSize.y + spacing
  imgui.SetCursorScreenPos(imgui.ImVec2(subX, subY))
  imgui.SetWindowFontScale(subScale)
  imgui.PushStyleColor(imgui.Col_Text, imgui.ImVec4(1, 1, 1, 0.92))
  imgui.Text(sub)
  imgui.PopStyleColor()
  imgui.SetWindowFontScale(1)

  imgui.End()
  imgui.PopStyleColor()
end

-- --------------------------
-- BeamNG hooks
-- --------------------------
function M.onGuiDraw()
  drawOverlay()
end

-- Extra safety: if the extension unloads while active, restore time
function M.onExtensionUnloaded()
  if S.active then
    S.active = false
    resumeNow()
  end
end

return M
