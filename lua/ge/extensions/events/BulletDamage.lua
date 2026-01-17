-- lua/ge/extensions/events/BulletDamage.lua
-- Standalone bullet hit helper with controllable accuracy around target center.

local M = {}

local BulletHit = require("lua/ge/extensions/events/BulletHit")

local DEFAULT = {
  accuracyRadius = 1.0,
  approachDistance = 50.0,
  impactForce = 6000.0,
  impactForceMultiplier = 1.0,
  explosionRadius = 1.0,
  explosionForce = 50.0,
  explosionDirectionInversionCoef = 0.3,
  shotSoundFile = "/art/sound/bolides/distantgunshot.wav",
  shotSoundName = "bulletDamageShot",
  shotSoundVolume = 1.0,
  shotSoundPitch = 1.0,
  applyDamage = true,
}

local random = math.random

local function _vehById(id)
  if not id then return nil end
  return be:getObjectByID(id)
end

local function _isValidVeh(veh)
  return veh ~= nil and veh.getID and veh:getJBeamFilename() ~= ""
end

local function _randomUnitVector()
  local x = random() * 2 - 1
  local y = random() * 2 - 1
  local z = random() * 2 - 1
  local v = vec3(x, y, z)
  if v:length() < 0.001 then
    return vec3(0, 1, 0)
  end
  return v:normalized()
end

local function _randomOffset(radius)
  if not radius or radius <= 0 then
    return vec3(0, 0, 0)
  end
  local dir = _randomUnitVector()
  local scale = radius * (random() ^ (1 / 3))
  return dir * scale
end

local function _getAudioHelper()
  if not extensions or not extensions.bolidesTheCut then return nil end
  return extensions.bolidesTheCut.Audio
end

local function _queue(veh, cmd)
  if not veh or not veh.queueLuaCommand then return end
  pcall(function() veh:queueLuaCommand(cmd) end)
end

local function _buildImpactCmd(impactPos, approachDir, impactForce, impactForceMultiplier, explosionRadius, explosionForce, explosionDirectionInversionCoef)
  local force = (impactForce or DEFAULT.impactForce) * (impactForceMultiplier or 1.0)
  local radius = explosionRadius or DEFAULT.explosionRadius
  local blastForce = explosionForce or DEFAULT.explosionForce
  local inversion = explosionDirectionInversionCoef or DEFAULT.explosionDirectionInversionCoef

  return string.format([[
    local impactPos = vec3(%0.6f, %0.6f, %0.6f)
    local approachDir = vec3(%0.6f, %0.6f, %0.6f)
    local localImpact = impactPos - obj:getPosition()
    local closestId = nil
    local closestDist = math.huge
    for i = 0, #v.data.nodes do
      local node = v.data.nodes[i]
      local nodePos = obj:getNodePosition(node.cid)
      local dist = (nodePos - localImpact):squaredLength()
      if dist < closestDist then
        closestDist = dist
        closestId = node.cid
      end
    end

    if closestId then
      local mass = 1.0
      if obj.getNodeMass then
        local m = obj:getNodeMass(closestId)
        if m then mass = m end
      end
      local forceVec = approachDir * %0.3f * mass
      obj:applyForceVector(closestId, forceVec)
      if obj.applyImpulse then
        pcall(function() obj:applyImpulse(localImpact, forceVec) end)
      end
    end

    if %0.6f > 0 then
      local radius1 = %0.6f * 0.5
      local radius2 = %0.6f
      local forceBase = %0.6f * 2000
      local inversionCoef = %0.6f
      local function clamp(x, a, b)
        if x < a then return a end
        if x > b then return b end
        return x
      end

      local boundLen = vec3(obj:getInitialWidth() + radius2, obj:getInitialLength() + radius2, obj:getInitialHeight() + radius2):squaredLength()
      if localImpact:squaredLength() <= boundLen then
        local nodeCount = #v.data.nodes
        for i = 0, nodeCount do
          local node = v.data.nodes[i]
          local nodePos = obj:getNodePosition(node.cid)
          local distanceVec = nodePos - localImpact
          local distance = math.abs(distanceVec:length())
          if distance <= radius2 then
            local dirInversion = fsign(math.random() - inversionCoef)
            local forceAdjusted = forceBase * clamp(-1 * (distance - radius1) / (radius2 - radius1) + 1, 0, 1)
            obj:applyForceVector(node.cid, distanceVec:normalized() * dirInversion * forceAdjusted)
          end
        end
      end
    end
  ]],
    impactPos.x,
    impactPos.y,
    impactPos.z,
    approachDir.x,
    approachDir.y,
    approachDir.z,
    force,
    radius,
    radius,
    radius,
    blastForce,
    inversion
  )
end

function M.trigger(args)
  args = args or {}
  local cfg = {}
  for k, v in pairs(DEFAULT) do cfg[k] = v end
  for k, v in pairs(args) do
    if cfg[k] ~= nil then cfg[k] = v end
  end

  local targetVeh = args.targetVeh
  if not targetVeh and args.targetId then
    targetVeh = _vehById(args.targetId)
  end
  if not _isValidVeh(targetVeh) then return false, "invalid target vehicle" end

  local targetPos = targetVeh:getPosition()
  if not targetPos then return false, "target position unavailable" end

  local offset = _randomOffset(cfg.accuracyRadius)
  local impactPos = targetPos + offset

  local sourcePos = args.sourcePos
  if not sourcePos and args.sourceId then
    local sourceVeh = _vehById(args.sourceId)
    if _isValidVeh(sourceVeh) then
      sourcePos = sourceVeh:getPosition()
    end
  end

  local approachDir
  if sourcePos then
    local dir = impactPos - sourcePos
    if dir:length() > 0.001 then
      approachDir = dir:normalized()
    end
  end
  if not approachDir then
    approachDir = _randomUnitVector()
  end

  local audio = _getAudioHelper()
  if audio and audio.ensureSources then
    audio.ensureSources(targetVeh, {
      { file = cfg.shotSoundFile, name = cfg.shotSoundName }
    })
    if audio.stopId then
      audio.stopId(targetVeh, cfg.shotSoundName)
    end
    if audio.playFile then
      audio.playFile(targetVeh, cfg.shotSoundName, cfg.shotSoundVolume, cfg.shotSoundPitch, cfg.shotSoundFile)
    end
  end

  local cmd = _buildImpactCmd(
    impactPos,
    approachDir,
    cfg.impactForce,
    cfg.impactForceMultiplier,
    cfg.explosionRadius,
    cfg.explosionForce,
    cfg.explosionDirectionInversionCoef
  )
  _queue(targetVeh, cmd)

  if cfg.applyDamage and BulletHit and BulletHit.trigger then
    local damageArgs = { playerId = targetVeh:getID() }
    if type(args.damageArgs) == "table" then
      for k, v in pairs(args.damageArgs) do
        damageArgs[k] = v
      end
    end
    local ok, reason = BulletHit.trigger(damageArgs)
    if not ok then
      return false, "damage failed: " .. tostring(reason)
    end
  end

  return true, {
    targetId = targetVeh:getID(),
    impactPos = impactPos,
    approachDir = approachDir,
  }
end

return M
