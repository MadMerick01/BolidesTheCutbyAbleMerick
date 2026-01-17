-- lua/ge/extensions/events/bullets.lua
-- Standalone bullet impact helper (force + audio) derived from EMP shockwave.

local M = {}

local DEFAULT = {
  shockDurationSec = 0.25,
  thrusterKickSpeed = 1.0,
  planetsUpdateIntervalSec = 0.05,
  planetRadius = 5,
  mass = -60000000000000,
  forceMultiplier = 0.1,
  forceReferenceDistance = 39.0,
  cooldownSec = 0.12,
}

local AUDIO = {
  file = "/art/sound/bolides/distantgunshot.wav",
  name = "bulletHit",
  volume = 2.0,
  pitch = 1.0,
}

local Audio = {}

function Audio.ensureSources(v, sources)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__bulletsAudio = _G.__bulletsAudio or { ids = {} }",
    "local A = _G.__bulletsAudio.ids",
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

function Audio.ensureBullet(v)
  Audio.ensureSources(v, {
    { file = AUDIO.file, name = AUDIO.name },
  })
end

function Audio.playId(v, name, vol, pitch, fileFallback)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  fileFallback = tostring(fileFallback or "")

  local cmd = string.format([[
    if not (_G.__bulletsAudio and _G.__bulletsAudio.ids) then return end
    local id = _G.__bulletsAudio.ids[%q]
    if not id then return end

    if obj.setSFXSourceLooping then pcall(function() obj:setSFXSourceLooping(id, false) end) end
    if obj.setSFXSourceLoop then pcall(function() obj:setSFXSourceLoop(id, false) end) end
    if obj.stopSFX then pcall(function() obj:stopSFX(id) end) end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, 1.0) end) end
    if obj.setSFXVolume then      pcall(function() obj:setSFXVolume(id, 1.0) end) end
    if obj.setVolume then         pcall(function() obj:setVolume(id, 1.0) end) end

    local played = false
    if obj.playSFXOnce and %q ~= "" then
      played = played or pcall(function() obj:playSFXOnce(%q, 0, %0.3f, %0.3f) end)
    end

    if (not played) and obj.playSFX then
      played = played or pcall(function() obj:playSFX(id) end)
      played = played or pcall(function() obj:playSFX(id, 0) end)
      played = played or pcall(function() obj:playSFX(id, false) end)
      played = played or pcall(function() obj:playSFX(id, 0, false) end)
      played = played or pcall(function() obj:playSFX(id, 0, %0.3f, %0.3f, false) end)
      played = played or pcall(function() obj:playSFX(id, %0.3f, %0.3f, false) end)
      played = played or pcall(function() obj:playSFX(id, 0, false, %0.3f, %0.3f) end)
    end

    if obj.setSFXSourceVolume then pcall(function() obj:setSFXSourceVolume(id, %0.3f) end) end
    if obj.setSFXSourcePitch  then pcall(function() obj:setSFXSourcePitch(id, %0.3f) end) end
  ]], name, fileFallback, fileFallback, vol, pitch, vol, pitch, vol, pitch, vol, pitch, vol, pitch)

  v:queueLuaCommand(cmd)
end

function Audio.playBullet(v)
  if not AUDIO.file or AUDIO.file == "" then return end
  Audio.playId(v, AUDIO.name, AUDIO.volume, AUDIO.pitch, AUDIO.file)
end

local active = {}
local lastTriggerTimeByVeh = {}

local function _now()
  return os.clock()
end

local function _vehById(id)
  if not id then return nil end
  return be:getObjectByID(id)
end

local function _isValidVeh(veh)
  return veh ~= nil and veh.getID and veh:getJBeamFilename() ~= ""
end

local function _clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function _vecToLua(v)
  return string.format("vec3(%0.6f,%0.6f,%0.6f)", v.x, v.y, v.z)
end

local function _queue(veh, cmd)
  if not veh then return end
  pcall(function() veh:queueLuaCommand(cmd) end)
end

local function _computeSourcePos(args)
  if args and args.sourcePos then return args.sourcePos end
  if args and args.sourceId then
    local s = _vehById(args.sourceId)
    if _isValidVeh(s) then return s:getPosition() end
  end
  return nil
end

local function _computeKickDir(playerVeh, sourcePos)
  if playerVeh and sourcePos then
    local p = playerVeh:getPosition()
    local dir = p - sourcePos
    if dir:length() > 0.001 then
      return dir:normalized()
    end
  end
  return playerVeh and playerVeh:getDirectionVector() or vec3(0, 1, 0)
end

local function _cmdThrusterKick(kickVec, delaySec)
  if delaySec and delaySec > 0 then
    return string.format("thrusters.applyVelocity(%s, %0.2f)", _vecToLua(kickVec), delaySec)
  end
  return string.format("thrusters.applyVelocity(%s)", _vecToLua(kickVec))
end

local function _cmdSetPlanets(sourcePos, planetRadius, massScaled)
  return string.format("obj:setPlanets({%0.6f, %0.6f, %0.6f, %d, %0.6f})",
    sourcePos.x, sourcePos.y, sourcePos.z, planetRadius, massScaled)
end

function M.trigger(args)
  if not args or not args.playerId then return false, "missing playerId" end

  local cfg = {}
  for k, v in pairs(DEFAULT) do cfg[k] = v end
  for k, v in pairs(args) do
    if cfg[k] ~= nil then cfg[k] = v end
  end

  local playerVeh = _vehById(args.playerId)
  if not _isValidVeh(playerVeh) then return false, "invalid player vehicle" end

  local now = _now()
  local last = lastTriggerTimeByVeh[args.playerId] or -9999
  if (now - last) < cfg.cooldownSec then
    return false, "cooldown"
  end
  lastTriggerTimeByVeh[args.playerId] = now

  local sourcePos = _computeSourcePos(args)
  local kickDir = _computeKickDir(playerVeh, sourcePos)
  local kickSpeed = cfg.thrusterKickSpeed
  local kickVec = kickDir * kickSpeed

  Audio.ensureBullet(playerVeh)
  Audio.playBullet(playerVeh)

  _queue(playerVeh, _cmdThrusterKick(kickVec, nil))
  _queue(playerVeh, _cmdThrusterKick(kickVec, 0.05))

  active[args.playerId] = active[args.playerId] or {}
  local st = active[args.playerId]
  st.shockEnd = now + cfg.shockDurationSec
  st.nextPlanets = 0
  st.planetsInterval = cfg.planetsUpdateIntervalSec
  st.sourcePos = sourcePos
  st.sourceId = args.sourceId
  st.planetRadius = cfg.planetRadius
  st.mass = cfg.mass
  st.forceMultiplier = cfg.forceMultiplier
  st.forceReferenceDistance = cfg.forceReferenceDistance

  return true
end

function M.onUpdate(dtReal, dtSim, dtRaw)
  local now = _now()

  for vid, st in pairs(active) do
    local veh = _vehById(vid)
    if not _isValidVeh(veh) then
      active[vid] = nil
    else
      if st.shockEnd and now < st.shockEnd then
        st.nextPlanets = (st.nextPlanets or 0) - dtSim
        if st.nextPlanets <= 0 then
          st.nextPlanets = st.planetsInterval or DEFAULT.planetsUpdateIntervalSec

          local sourcePos = st.sourcePos
          if st.sourceId then
            local s = _vehById(st.sourceId)
            if _isValidVeh(s) then
              sourcePos = s:getPosition()
            end
          end

          if sourcePos then
            local bbox = veh:getSpawnWorldOOBB()
            local he = bbox and bbox.getHalfExtents and bbox:getHalfExtents() or nil
            local vehicleSizeFactor = 1.0
            if he then
              local longest = math.max(math.max(he.x, he.y), he.y)
              vehicleSizeFactor = longest / 3
              vehicleSizeFactor = _clamp(vehicleSizeFactor, 0.5, 2.0)
            end

            local massScaled = (st.mass or DEFAULT.mass) * vehicleSizeFactor * (st.forceMultiplier or 1.0)

            local referenceDistance = st.forceReferenceDistance or DEFAULT.forceReferenceDistance
            if referenceDistance and referenceDistance > 0 then
              local playerPos = veh:getPosition()
              local distance = (playerPos - sourcePos):length()
              if distance > 0.001 then
                local distanceScale = (distance / referenceDistance)
                massScaled = massScaled * (distanceScale * distanceScale)
              end
            end
            _queue(veh, _cmdSetPlanets(sourcePos, st.planetRadius or DEFAULT.planetRadius, massScaled))
          end
        end
      elseif st.shockEnd and now >= st.shockEnd then
        _queue(veh, "obj:setPlanets({})")
        st.shockEnd = nil
      end

      if not st.shockEnd then
        active[vid] = nil
      end
    end
  end
end

function M.isActive(playerId)
  return active[playerId] ~= nil
end

return M
