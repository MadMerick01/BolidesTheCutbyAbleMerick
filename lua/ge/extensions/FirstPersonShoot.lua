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
  rayStartOffset = 3.0,
  targetSnapRadius = 6.0,
  accuracyRadius = 1.5,
}

local AUDIO = {
  file = "/art/sound/bolides/PlayerGunShot.wav",
  name = "playerGunshot",
  volume = 12.0,
  pitch = 1.0,
  poolSize = 6,
}

local Audio = {}

local function _getPlayerVeh()
  return (be and be.getPlayerVehicle) and be:getPlayerVehicle(0) or nil
end

local function _resolveAudioVeh(v)
  return _getPlayerVeh() or v
end

function Audio.ensurePooledSources(v, source)
  v = _resolveAudioVeh(v)
  if not v or not v.queueLuaCommand then return end
  if not source or not source.name or not source.file then return end

  local poolSize = tonumber(source.count) or tonumber(source.poolSize) or 4
  poolSize = math.max(1, math.floor(poolSize))
  local name = tostring(source.name)
  local file = tostring(source.file)

  local cmd = string.format([[
    _G.__bolidesPlayerShotAudio = _G.__bolidesPlayerShotAudio or { ids = {}, pools = {} }
    local A = _G.__bolidesPlayerShotAudio.ids
    local P = _G.__bolidesPlayerShotAudio.pools
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

function Audio.playPooledFile(v, name, vol, pitch, file)
  v = _resolveAudioVeh(v)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  file = tostring(file or "")

  local cmd = string.format([[
    if not (_G.__bolidesPlayerShotAudio and _G.__bolidesPlayerShotAudio.ids) then return end
    local A = _G.__bolidesPlayerShotAudio.ids
    local P = _G.__bolidesPlayerShotAudio.pools or {}
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

function Audio.playPlayerShot(v)
  if not AUDIO.file or AUDIO.file == "" then return end
  Audio.ensurePooledSources(v, {
    file = AUDIO.file,
    name = AUDIO.name,
    count = AUDIO.poolSize,
  })
  Audio.playPooledFile(v, AUDIO.name, AUDIO.volume, AUDIO.pitch, AUDIO.file)
end

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
  isInputBlocked = nil,
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

local function _listVehicles()
  if not scenetree or not scenetree.findClassObjects or not scenetree.findObject then
    return {}
  end
  local vehicles = {}
  local refs = scenetree.findClassObjects("BeamNGVehicle") or {}
  for i = 1, #refs do
    local obj = scenetree.findObject(refs[i])
    if _isValidVeh(obj) then
      vehicles[#vehicles + 1] = obj
    end
  end
  return vehicles
end

local function _findSnapTargetNearPoint(point, playerVeh)
  if not point then return nil end
  local playerId = playerVeh and playerVeh.getID and playerVeh:getID() or nil
  local bestVeh = nil
  local bestDist = nil
  local maxDist = CFG.targetSnapRadius or 0
  if maxDist <= 0 then return nil end
  local vehicles = _listVehicles()
  for i = 1, #vehicles do
    local veh = vehicles[i]
    if veh and (not playerId or veh:getID() ~= playerId) then
      local pos = veh:getPosition()
      if pos then
        local dist = (pos - point):length()
        if dist <= maxDist and (not bestDist or dist < bestDist) then
          bestVeh = veh
          bestDist = dist
        end
      end
    end
  end
  return bestVeh
end

local function _findSnapTargetAlongRay(rayStart, rayDir, maxDistance, playerVeh)
  if not rayStart or not rayDir then return nil end
  local playerId = playerVeh and playerVeh.getID and playerVeh:getID() or nil
  local maxDist = CFG.targetSnapRadius or 0
  if maxDist <= 0 then return nil end
  local bestVeh = nil
  local bestRayDist = nil
  local bestAlong = nil
  local vehicles = _listVehicles()
  for i = 1, #vehicles do
    local veh = vehicles[i]
    if veh and (not playerId or veh:getID() ~= playerId) then
      local pos = veh:getPosition()
      if pos then
        local toPos = pos - rayStart
        local along = toPos:dot(rayDir)
        if along >= 0 and (not maxDistance or along <= maxDistance) then
          local closestPoint = rayStart + (rayDir * along)
          local dist = (pos - closestPoint):length()
          if dist <= maxDist and (not bestRayDist or dist < bestRayDist) then
            bestVeh = veh
            bestRayDist = dist
            bestAlong = along
          end
        end
      end
    end
  end
  if bestVeh and bestAlong then
    return bestVeh, rayStart + (rayDir * bestAlong)
  end
  return nil
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
  local playerVeh = callbacks.getPlayerVeh and callbacks.getPlayerVeh() or nil
  Audio.playPlayerShot(playerVeh)
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
      callbacks.onShot(false, "out_of_ammo", nil)
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
      callbacks.onShot(false, "ray_unavailable", nil)
    end
    return
  end

  local rayDir = _vec3From(ray.dir)
  if not rayDir or rayDir:length() < 0.001 then
    if callbacks.onShot then
      callbacks.onShot(false, "ray_invalid", nil)
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

  local rayStartPos = camPos
  local rayEndPos = camPos + (rayDir * CFG.maxDistance)
  local hit = nil

  if castRay and CFG.rayStartOffset and CFG.rayStartOffset > 0 then
    local offsetStartPos = camPos + (rayDir * CFG.rayStartOffset)
    local ok, result = pcall(castRay, offsetStartPos, rayEndPos)
    if ok and type(result) == "table" then
      hit = result
      rayStartPos = offsetStartPos
    end
  end

  if not hit then
    hit = cameraMouseRayCast and cameraMouseRayCast(true) or nil
    rayStartPos = camPos
  end
  local objId, hitPos, hitDist = _extractHitInfo(hit)
  if not hitPos and hitDist then
    hitPos = rayStartPos + (rayDir * hitDist)
  end

  local playerVeh = callbacks.getPlayerVeh and callbacks.getPlayerVeh() or nil
  local targetVeh = objId and be:getObjectByID(objId) or nil
  if not _isValidVeh(targetVeh) then
    targetVeh = _findSnapTargetNearPoint(hitPos, playerVeh)
    if not targetVeh then
      targetVeh, hitPos = _findSnapTargetAlongRay(rayStartPos, rayDir, CFG.maxDistance, playerVeh)
    end
    if not _isValidVeh(targetVeh) then
      if callbacks.onShot then
        callbacks.onShot(false, "no_vehicle_hit", hitPos)
      end
      return
    end
  end

  if playerVeh and targetVeh:getID() == playerVeh:getID() then
    if callbacks.onShot then
      callbacks.onShot(false, "self_hit_blocked", hitPos)
    end
    return
  end

  if not hitPos then
    if callbacks.onShot then
      callbacks.onShot(false, "no_hit_position", nil)
    end
    return
  end

  local ok, info = BulletDamage.trigger({
    targetId = targetVeh:getID(),
    sourcePos = camPos,
    impactPos = hitPos,
    approachDir = rayDir,
    accuracyRadius = CFG.accuracyRadius or 0.0,
    applyDamage = true,
  })

  if callbacks.onShot then
    callbacks.onShot(ok and true or false, info, hitPos)
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
  callbacks.isInputBlocked = opts.isInputBlocked

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

  if callbacks.isInputBlocked and callbacks.isInputBlocked() then
    return
  end

  if imgui.IsMouseClicked and imgui.IsMouseClicked(0) then
    _fireShot()
  end
end

return M
