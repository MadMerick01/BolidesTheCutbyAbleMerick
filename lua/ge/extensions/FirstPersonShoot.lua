-- lua/ge/extensions/FirstPersonShoot.lua
-- First-person shotgun aiming + raycast fire handler.

local M = {}

local BulletDamage = require("lua/ge/extensions/events/BulletDamage")

local CFG = {
  maxDistance = 250.0,
  shotCooldownSec = 0.35,
  recoilPitchKick = 4.0,
  crosshairSize = 7.0,
  crosshairThickness = 2.0,
}

local state = {
  aimEnabled = false,
  lastShotTime = -math.huge,
  blockedReason = nil,
}

local callbacks = {
  getAmmo = nil,
  consumeAmmo = nil,
  getPlayerVeh = nil,
  onShot = nil,
  onAimChanged = nil,
}

local function _now()
  return os.clock()
end

local function _isValidVeh(veh)
  return veh and veh.getID and veh:getJBeamFilename() ~= ""
end

local function _vec3From(v)
  if not v then return nil end
  if type(v) == "table" and v.x and v.y and v.z then
    return vec3(v.x, v.y, v.z)
  end
  if type(v) == "table" and #v >= 3 then
    return vec3(v[1], v[2], v[3])
  end
  return vec3(v)
end

local function _getAimBlockReason()
  if not core_camera or not core_camera.getActiveCamName then
    return "camera_unavailable"
  end

  local camName = core_camera.getActiveCamName(0)
  local camPos = getCameraPosition and getCameraPosition() or nil
  local isInside = false
  if camPos and core_camera.isCameraInside then
    local ok, inside = pcall(core_camera.isCameraInside, 0, camPos)
    isInside = ok and inside or false
  end

  if isInside then
    return nil
  end

  if camName then
    local name = string.lower(tostring(camName))
    if string.find(name, "onboard", 1, true) or string.find(name, "driver", 1, true)
      or string.find(name, "rider", 1, true) or string.find(name, "first", 1, true) then
      return nil
    end
  end

  return "not_first_person"
end

local function _canAim()
  local reason = _getAimBlockReason()
  if reason then
    return false, reason
  end
  if callbacks.getAmmo then
    local ammo = callbacks.getAmmo()
    if ammo and ammo <= 0 then
      return false, "no_ammo"
    end
  end
  return true
end

local function _setAimEnabled(enabled, reason)
  enabled = enabled and true or false
  if state.aimEnabled == enabled and not reason then
    return
  end
  state.aimEnabled = enabled
  state.blockedReason = reason
  if callbacks.onAimChanged then
    callbacks.onAimChanged(state.aimEnabled, state.blockedReason)
  end
end

local function _extractHitInfo(hit)
  if type(hit) ~= "table" then return nil end

  local objId = hit.objectId or hit.objectID or hit.object or hit.id
  if type(objId) == "table" and objId.getID then
    objId = objId:getID()
  end

  local pos = hit.pos or hit.position or hit.hitPos or hit.hitPoint or hit.point
  if pos then
    pos = _vec3From(pos)
  end

  local dist = hit.dist or hit.distance

  return objId, pos, dist
end

local function _applyRecoilKick()
  -- Recoil kick disabled temporarily to focus on accuracy tuning.
  return
end

local function _playShotAudio()
  if not extensions or not extensions.bolidesTheCut or not extensions.bolidesTheCut.Audio then
    return
  end
  local audio = extensions.bolidesTheCut.Audio
  if audio.playGunshot then
    local playerVeh = callbacks.getPlayerVeh and callbacks.getPlayerVeh() or nil
    audio.playGunshot(playerVeh)
  end
end

local function _fireShot()
  if not state.aimEnabled then return end

  local canAim, reason = _canAim()
  if not canAim then
    _setAimEnabled(false, reason)
    return
  end

  local ammo = callbacks.getAmmo and callbacks.getAmmo() or nil
  if ammo and ammo <= 0 then
    if callbacks.onShot then
      callbacks.onShot(false, "out_of_ammo")
    end
    return
  end

  local now = _now()
  if (now - state.lastShotTime) < CFG.shotCooldownSec then
    return
  end

  local camPosRaw = getCameraPosition and getCameraPosition() or nil
  local camPos = _vec3From(camPosRaw)
  local ray = getCameraMouseRay and getCameraMouseRay() or nil
  if not camPos or not ray or not ray.dir then
    if callbacks.onShot then
      callbacks.onShot(false, "ray_unavailable")
    end
    return
  end

  local rayDir = _vec3From(ray.dir)
  if not rayDir or rayDir:length() < 0.001 then
    if callbacks.onShot then
      callbacks.onShot(false, "ray_invalid")
    end
    return
  end
  rayDir = rayDir:normalized()

  state.lastShotTime = now
  if callbacks.consumeAmmo then
    callbacks.consumeAmmo(1)
  end
  _playShotAudio()
  _applyRecoilKick()

  local hit = cameraMouseRayCast and cameraMouseRayCast(true) or nil
  local objId, hitPos, hitDist = _extractHitInfo(hit)
  if not hitPos and hitDist then
    hitPos = camPos + (rayDir * hitDist)
  end

  local targetVeh = objId and be:getObjectByID(objId) or nil
  if not _isValidVeh(targetVeh) then
    if callbacks.onShot then
      callbacks.onShot(false, "no_vehicle_hit")
    end
    return
  end

  local playerVeh = callbacks.getPlayerVeh and callbacks.getPlayerVeh() or nil
  if playerVeh and targetVeh:getID() == playerVeh:getID() then
    if callbacks.onShot then
      callbacks.onShot(false, "self_hit_blocked")
    end
    return
  end

  if not hitPos then
    if callbacks.onShot then
      callbacks.onShot(false, "no_hit_position")
    end
    return
  end

  local ok, info = BulletDamage.trigger({
    targetId = targetVeh:getID(),
    sourcePos = camPos,
    impactPos = hitPos,
    approachDir = rayDir,
    accuracyRadius = 0.0,
  })

  if callbacks.onShot then
    callbacks.onShot(ok and true or false, info)
  end
end

local function _drawCrosshair(imgui)
  local viewport = imgui.GetMainViewport and imgui.GetMainViewport() or nil
  local drawList = viewport and imgui.GetForegroundDrawList2(viewport) or nil
  if not drawList then return end

  local pos = imgui.GetMousePos and imgui.GetMousePos() or nil
  if not pos then return end

  local size = CFG.crosshairSize
  local thickness = CFG.crosshairThickness
  local color = imgui.GetColorU321(imgui.Col_Text, 1.0)
  local center = imgui.ImVec2(pos.x, pos.y)

  local left = imgui.ImVec2(pos.x - size, pos.y)
  local right = imgui.ImVec2(pos.x + size, pos.y)
  local up = imgui.ImVec2(pos.x, pos.y - size)
  local down = imgui.ImVec2(pos.x, pos.y + size)

  imgui.ImDrawList_AddLine(drawList, left, right, color, thickness)
  imgui.ImDrawList_AddLine(drawList, up, down, color, thickness)
  imgui.ImDrawList_AddLine(drawList, center, center, color, thickness)
end

function M.init(opts)
  opts = opts or {}
  callbacks.getAmmo = opts.getAmmo
  callbacks.consumeAmmo = opts.consumeAmmo
  callbacks.getPlayerVeh = opts.getPlayerVeh
  callbacks.onShot = opts.onShot
  callbacks.onAimChanged = opts.onAimChanged

  if opts.config and type(opts.config) == "table" then
    for k, v in pairs(opts.config) do
      if CFG[k] ~= nil then
        CFG[k] = v
      end
    end
  end
end

function M.setAimEnabled(enabled)
  if enabled then
    local ok, reason = _canAim()
    if not ok then
      _setAimEnabled(false, reason)
      return false, reason
    end
  end
  _setAimEnabled(enabled)
  return true
end

function M.toggleAim()
  return M.setAimEnabled(not state.aimEnabled)
end

function M.isAimEnabled()
  return state.aimEnabled
end

function M.getBlockedReason()
  return state.blockedReason
end

function M.onUpdate(dtSim)
  if state.aimEnabled then
    local canAim, reason = _canAim()
    if not canAim then
      _setAimEnabled(false, reason)
    end
  end
end

function M.onDraw()
  if not state.aimEnabled then return end

  local imgui = ui_imgui
  if not imgui then return end

  local canAim, reason = _canAim()
  if not canAim then
    _setAimEnabled(false, reason)
    return
  end

  if imgui.SetMouseCursor and imgui.MouseCursor_None then
    imgui.SetMouseCursor(imgui.MouseCursor_None)
  end

  _drawCrosshair(imgui)

  local io = imgui.GetIO and imgui.GetIO() or nil
  if io and io.WantCaptureMouse then
    return
  end

  if imgui.IsMouseClicked and imgui.IsMouseClicked(0) then
    _fireShot()
  end
end

return M
