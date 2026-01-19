-- lua/ge/extensions/NewHud.lua
-- Standalone HUD module for Bolides The Cut (ImGui).
-- Safe to run alongside legacy UI: unique window ID, isolated state, gated visibility.

local M = {}

local imgui = ui_imgui
local ImVec2 = imgui.ImVec2
local im = imgui

-- =========================
-- State (isolated)
-- =========================
local H = {
  visible = false,

  title = "Bolides - The Cut",
  tagline = "You transport value, watch the road",

  wallet = 0,
  status = "",
  instruction = "",

  threat = "safe", -- "safe" | "event" | "danger"
  dangerReason = nil,
  aboutOpen = false,

  weapons = {
    { id = "beretta92fs", name = "shotgun", ammoLabel = "Ammo", ammo = 15 },
    { id = "emp",        name = "EMP Device",   ammoLabel = "Charges", ammo = 2  },
  },

  -- Window behavior
  windowTitle = "Bolides HUD##BTC_NEWHUD", -- unique ImGui ID (do not reuse legacy title)
  windowW = 460,
  windowH = 520,
}

-- Optional host callback (set by bolidesTheCut)
local Host = nil
function M.setHost(host) Host = host end

-- =========================
-- Public API (stable)
-- =========================
function M.setVisible(v) H.visible = v and true or false end
function M.isVisible() return H.visible end

function M.setWallet(amount)
  H.wallet = tonumber(amount) or H.wallet
end

function M.setStatus(msg)
  H.status = tostring(msg or "")
end

function M.setInstruction(msg)
  H.instruction = tostring(msg or "")
end

function M.setThreat(level)
  level = tostring(level or "safe")
  if level ~= "safe" and level ~= "event" and level ~= "danger" then level = "safe" end
  H.threat = level
end

function M.setDangerReason(reason)
  if reason == nil or reason == "" then
    H.dangerReason = nil
  else
    H.dangerReason = tostring(reason)
  end
end

function M.setWeapons(list)
  if type(list) == "table" then
    H.weapons = list
  end
end

function M.addWeaponOrUpdate(id, fields)
  if not id then return end
  fields = fields or {}
  for _, w in ipairs(H.weapons) do
    if w.id == id then
      for k, v in pairs(fields) do w[k] = v end
      return
    end
  end
  local nw = { id = id, name = fields.name or id, ammoLabel = fields.ammoLabel or "Ammo", ammo = fields.ammo or 0 }
  table.insert(H.weapons, nw)
end

-- =========================
-- Styling helpers
-- =========================
local function threatColors()
  -- Return (bgR,bgG,bgB,bgA) for the whole window tint
  if H.threat == "danger" then
    return 0.35, 0.05, 0.05, 0.92 -- red
  elseif H.threat == "event" then
    return 0.35, 0.28, 0.05, 0.92 -- yellow/amber
  end
  return 0.05, 0.20, 0.08, 0.92 -- green
end

local function pushWindowTint()
  local r,g,b,a = threatColors()
  im.PushStyleColor2(im.Col_WindowBg, im.ImVec4(r,g,b,a))
  -- Optional accents (keep conservative so it stays readable)
  im.PushStyleColor2(im.Col_TitleBg, im.ImVec4(r*0.9, g*0.9, b*0.9, 1.0))
  im.PushStyleColor2(im.Col_TitleBgActive, im.ImVec4(r*1.0, g*1.0, b*1.0, 1.0))
end

local function popWindowTint()
  im.PopStyleColor(3)
end

local function drawHeader()
  im.TextUnformatted(H.title)
  im.PushStyleVar1(im.StyleVar_Alpha, 0.85)
  im.TextUnformatted(H.tagline)
  im.PopStyleVar()

  im.Spacing()

  if im.Button("About") then
    H.aboutOpen = not H.aboutOpen
  end

  im.SameLine()
  im.PushStyleVar1(im.StyleVar_Alpha, 0.92)
  im.TextUnformatted(string.format("Wallet: $%s", tostring(H.wallet)))
  im.PopStyleVar()

  if H.aboutOpen then
    im.Separator()
    im.PushStyleVar1(im.StyleVar_Alpha, 0.85)
    im.TextWrapped("placeholder text")
    im.PopStyleVar()
  end
end

local function drawNarrative()
  im.Separator()
  im.TextUnformatted("STATUS")
  im.PushTextWrapPos(0)
  im.TextWrapped(H.status ~= "" and H.status or "—")
  im.PopTextWrapPos()

  im.Spacing()
  im.TextUnformatted("INSTRUCTION")
  im.PushTextWrapPos(0)
  im.TextWrapped(H.instruction ~= "" and H.instruction or "—")
  im.PopTextWrapPos()
end

local function fireWeapon(idx)
  local w = H.weapons[idx]
  if not w then return end
  if (w.ammo or 0) <= 0 then return end

  -- Immediate feedback
  w.ammo = (w.ammo or 0) - 1

  -- Optional hook back into bolidesTheCut
  if Host and Host.onHudWeaponFire then
    pcall(Host.onHudWeaponFire, w.id, w)
  end
end

local function drawWeapons()
  im.Separator()
  im.TextUnformatted("WEAPONS / INVENTORY")
  im.Spacing()

  for i, w in ipairs(H.weapons) do
    local ammo = tonumber(w.ammo) or 0
    local label = w.ammoLabel or "Ammo"

    -- Name
    im.TextUnformatted(w.name or w.id or "Unknown")
    im.SameLine()

    -- Right side controls: ammo + button
    im.PushStyleVar2(im.StyleVar_ItemSpacing, ImVec2(8, 6))

    im.TextUnformatted(string.format("%s: %d", label, ammo))
    im.SameLine()

    local btnText = (w.id == "emp") and "Use" or "Fire"
    if ammo <= 0 then
      im.BeginDisabled()
      im.Button(btnText .. "##" .. tostring(w.id))
      im.EndDisabled()
    else
      if im.Button(btnText .. "##" .. tostring(w.id)) then
        fireWeapon(i)
      end
    end

    im.PopStyleVar()
    im.Spacing()
  end
end

-- =========================
-- Draw entry
-- =========================
function M.draw()
  if not H.visible then return end
  if not im then return end

  im.SetNextWindowSize(ImVec2(H.windowW, H.windowH), im.Cond_FirstUseEver)

  pushWindowTint()

  local openPtr = im.BoolPtr(true)
  local flags = bit.bor(im.WindowFlags_NoCollapse)

  if im.Begin(H.windowTitle, openPtr, flags) then
    drawHeader()
    drawNarrative()
    drawWeapons()
  end

  im.End()
  popWindowTint()

  -- If user closes the window via [X] (if enabled later), reflect it
  -- (Currently openPtr is always true; left here for future.)
end

return M
