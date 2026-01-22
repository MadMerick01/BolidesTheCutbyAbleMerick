-- lua/ge/extensions/events/emp.lua
-- Standalone EMP effect helper for BeamNG (GE Lua).
--
-- Features (timed, reversible):
--  - Temporary engine/ignition cut (best-effort; no permanent damage)
--  - Brake lock for N seconds
--  - Hazard lights on during EMP (best-effort state restore)
--  - Combined shockwave for S seconds:
--      * Thrusters velocity "kick" (instant + a couple delayed kicks)
--      * Temporary "planets" force (forceField-style) centered on the robber/source
--
-- Usage (examples):
--   local EMP = require('lua/ge/extensions/events/emp')  -- or extensions.events_emp if loaded as extension
--   EMP.trigger({ playerId = be:getPlayerVehicle(0):getID(), sourceId = robberVehId })
--   -- call EMP.onUpdate(dtReal, dtSim, dtRaw) from your event's onUpdate if EMP isn't registered as an extension.
--
-- Notes:
--  - This module avoids powertrain.breakDevice (permanent).
--  - Some vehicle-side APIs differ by BeamNG version; engine cut + hazard restore are best-effort fallbacks.
--  - Planets force is applied repeatedly during shock window and then cleared with obj:setPlanets({}).

local M = {}

local logTag = "EMP"

-- =========================
-- Defaults (override per trigger call)
-- =========================
local DEFAULT = {
  empDurationSec = 10.0,
  shockDurationSec = 0.5,

  -- Thruster kick strength (m/s). This is an added velocity vector.
  thrusterKickSpeed = 10.0,

  -- Planets force parameters (forceField-style)
  planetsUpdateIntervalSec = 0.05,
  planetRadius = 5,
  mass = -60000000000000, -- negative gives repulsion in stock forceField
  forceMultiplier = 1.0,
  forceReferenceDistance = 39.0,

  -- Optional AI disable for NPC drivers (seconds)
  aiDisableDurationSec = 0.0,

  -- Safety / spam prevention
  cooldownSec = 2.0,
}

local AUDIO = {
  file = "/art/sound/bolides/EMP.wav",
  name = "empTrigger",
  volume = 1.0,
  pitch = 1.0,
}

local Audio = {}

local function _getPlayerVeh()
  return (be and be.getPlayerVehicle) and be:getPlayerVehicle(0) or nil
end

local function _resolveAudioVeh(v)
  return _getPlayerVeh() or v
end

function Audio.ensureSources(v, sources)
  v = _resolveAudioVeh(v)
  if not v or not v.queueLuaCommand then return end
  sources = sources or {}

  local lines = {
    "_G.__empAudio = _G.__empAudio or { ids = {} }",
    "local A = _G.__empAudio.ids",
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

function Audio.ensureEmp(v)
  Audio.ensureSources(v, {
    { file = AUDIO.file, name = AUDIO.name },
  })
end

function Audio.playId(v, name, vol, pitch, fileFallback)
  v = _resolveAudioVeh(v)
  if not v or not v.queueLuaCommand then return end
  vol = tonumber(vol) or 1.0
  pitch = tonumber(pitch) or 1.0
  name = tostring(name)
  fileFallback = tostring(fileFallback or "")

  local cmd = string.format([[
    if not (_G.__empAudio and _G.__empAudio.ids) then return end
    local id = _G.__empAudio.ids[%q]
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

function Audio.playEmp(v)
  if not AUDIO.file or AUDIO.file == "" then return end
  Audio.playId(v, AUDIO.name, AUDIO.volume, AUDIO.pitch, AUDIO.file)
end

-- =========================
-- Runtime
-- =========================
local active = {}   -- [vehId] = { empEnd=, shockEnd=, nextPlanets=, sourcePos=vec3, startedAt=, ... }
local lastTriggerTimeByVeh = {} -- [vehId] = os.clock()

-- =========================
-- Helpers
-- =========================
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
  -- returns "vec3(x,y,z)" string; vec3 exists in vehicle lua env
  return string.format("vec3(%0.6f,%0.6f,%0.6f)", v.x, v.y, v.z)
end

local function _queue(veh, cmd)
  if not veh then return end
  -- queueLuaCommand is best effort; avoid hard errors
  pcall(function() veh:queueLuaCommand(cmd) end)
end

local function _computeSourcePos(args)
  -- Prefer explicit sourcePos; else from sourceId vehicle position; else nil
  if args and args.sourcePos then return args.sourcePos end
  if args and args.sourceId then
    local s = _vehById(args.sourceId)
    if _isValidVeh(s) then return s:getPosition() end
  end
  return nil
end

local function _computeKickDir(playerVeh, sourcePos)
  -- Direction away from source (robber) in world space; fallback to player's forward vector
  if playerVeh and sourcePos then
    local p = playerVeh:getPosition()
    local dir = p - sourcePos
    if dir:length() > 0.001 then
      return dir:normalized()
    end
  end
  return playerVeh and playerVeh:getDirectionVector() or vec3(0,1,0)
end

-- =========================
-- Vehicle-side command snippets
-- =========================

local function _cmdEmpStart(empDurationSec)
  -- Store prior states if possible and apply temporary disable effects.
  -- Uses globals on vehicle lua side (emp_prevIgn, emp_prevWarn) to restore later.
  return string.format([[
    -- EMP START (vehicle lua)
    do
      -- capture previous hazard state if available
      if electrics and electrics.values then
        emp_prevWarn = electrics.values.warn_signal
        emp_prevIgn  = electrics.values.ignitionLevel
      end

      -- hazards ON (if we can detect they're off)
      if electrics then
        if electrics.values and electrics.values.warn_signal ~= nil then
          if not electrics.values.warn_signal and electrics.toggle_warn_signal then
            electrics.toggle_warn_signal()
          end
        elseif electrics.toggle_warn_signal then
          -- unknown current state, just toggle (best effort)
          electrics.toggle_warn_signal()
        end
      end

      -- brake lock immediately
      if input and input.event then
        input.event('brake', 1, 1)
      end

      -- engine/ignition cut (best effort, reversible)
      local function _setIgn(level)
        if electrics and electrics.setIgnitionLevel then
          electrics.setIgnitionLevel(level)
          return true
        end
        -- fallback: try common controller hook (may not exist)
        if controller and controller.mainController and controller.mainController.setIgnitionLevel then
          controller.mainController.setIgnitionLevel(level)
          return true
        end
        return false
      end

      -- attempt to cut ignition
      _setIgn(0)

      -- also kill throttle input (optional safety)
      if input and input.event then
        input.event('throttle', 0, 1)
      end
    end
  ]], empDurationSec)
end

local function _cmdEmpEnd()
  -- Restore previous states if captured; release brake.
  return [[
    -- EMP END (vehicle lua)
    do
      -- release brake lock
      if input and input.event then
        input.event('brake', 0, 1)
      end

      -- restore ignition (best effort)
      local function _setIgn(level)
        if electrics and electrics.setIgnitionLevel then
          electrics.setIgnitionLevel(level)
          return true
        end
        if controller and controller.mainController and controller.mainController.setIgnitionLevel then
          controller.mainController.setIgnitionLevel(level)
          return true
        end
        return false
      end

      if emp_prevIgn ~= nil then
        _setIgn(emp_prevIgn)
      else
        _setIgn(2) -- typical "run" level
      end
      emp_prevIgn = nil

      -- restore hazard state if known
      if electrics then
        if emp_prevWarn ~= nil and electrics.values and electrics.values.warn_signal ~= nil then
          if electrics.values.warn_signal ~= emp_prevWarn and electrics.toggle_warn_signal then
            electrics.toggle_warn_signal()
          end
        elseif electrics.toggle_warn_signal then
          -- unknown previous state; best effort: toggle off
          electrics.toggle_warn_signal()
        end
      end
      emp_prevWarn = nil
    end
  ]]
end

local function _cmdAiDisable()
  return [[
    do
      if ai then
        emp_prevAiMode = emp_prevAiMode or nil
        if ai.getState then
          local ok, state = pcall(function() return ai.getState() end)
          if ok and type(state) == "table" and state.mode then
            emp_prevAiMode = state.mode
          end
        end
        if emp_prevAiMode == nil and ai.getMode then
          local ok, mode = pcall(function() return ai.getMode() end)
          if ok then emp_prevAiMode = mode end
        end
        pcall(function() ai.setMode("disabled") end)
        pcall(function() ai.setMode("none") end)
      end
    end
  ]]
end

local function _cmdAiRestore()
  return [[
    do
      if ai and ai.setMode then
        local mode = emp_prevAiMode
        if mode == nil or mode == "" then
          mode = "traffic"
        end
        pcall(function() ai.setMode(mode) end)
      end
      emp_prevAiMode = nil
    end
  ]]
end

local function _cmdThrusterKick(kickVec, delaySec)
  -- delaySec is optional; thrusters.applyVelocity supports (vec, delay) in some mods (see main.lua usage).
  if delaySec and delaySec > 0 then
    return string.format("thrusters.applyVelocity(%s, %0.2f)", _vecToLua(kickVec), delaySec)
  end
  return string.format("thrusters.applyVelocity(%s)", _vecToLua(kickVec))
end

local function _cmdSetPlanets(sourcePos, planetRadius, massScaled)
  -- forceField-style planets: obj:setPlanets({x,y,z, radius, mass})
  return string.format("obj:setPlanets({%0.6f, %0.6f, %0.6f, %d, %0.6f})",
    sourcePos.x, sourcePos.y, sourcePos.z, planetRadius, massScaled)
end

-- =========================
-- Public API
-- =========================

-- args:
--  playerId (required): vehicle ID to affect (player vehicle)
--  sourceId (optional): robber vehicle ID (for shock direction + planets center)
--  sourcePos (optional): vec3 position if you don't have sourceId
--  empDurationSec, shockDurationSec, thrusterKickSpeed, forceMultiplier, forceReferenceDistance,
--  planetRadius, mass, planetsUpdateIntervalSec, aiDisableDurationSec
function M.trigger(args)
  if not args or not args.playerId then return false, "missing playerId" end

  local cfg = {}
  for k,v in pairs(DEFAULT) do cfg[k]=v end
  -- allow overrides
  for k,v in pairs(args) do
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

  -- Vehicle-side: start EMP (engine cut + brake lock + hazards)
  _queue(playerVeh, _cmdEmpStart(cfg.empDurationSec))
  Audio.ensureEmp(playerVeh)
  Audio.playEmp(playerVeh)

  -- Vehicle-side: thruster kicks (instant + delayed)
  _queue(playerVeh, _cmdThrusterKick(kickVec, nil))
  _queue(playerVeh, _cmdThrusterKick(kickVec, 0.10))
  _queue(playerVeh, _cmdThrusterKick(kickVec, 0.30))

  -- GE-side: planets force (applied repeatedly during shock window)
  active[args.playerId] = active[args.playerId] or {}
  local st = active[args.playerId]
  st.startedAt = now
  st.empEnd = now + cfg.empDurationSec
  st.shockEnd = now + cfg.shockDurationSec
  st.nextPlanets = 0
  st.planetsInterval = cfg.planetsUpdateIntervalSec
  st.sourcePos = sourcePos -- may be nil (then we'll fallback each tick)
  st.sourceId = args.sourceId
  st.planetRadius = cfg.planetRadius
  st.mass = cfg.mass
  st.forceMultiplier = cfg.forceMultiplier
  st.forceReferenceDistance = cfg.forceReferenceDistance

  if cfg.aiDisableDurationSec and cfg.aiDisableDurationSec > 0 then
    _queue(playerVeh, _cmdAiDisable())
    st.aiDisableEnd = now + cfg.aiDisableDurationSec
    st.aiDisableApplied = true
  end

  return true
end

-- Optional: cancel immediately (restores, clears planets)
function M.cancel(playerId)
  local veh = _vehById(playerId)
  if _isValidVeh(veh) then
    _queue(veh, _cmdEmpEnd())
    local st = active[playerId]
    if st and st.aiDisableApplied then
      _queue(veh, _cmdAiRestore())
    end
    _queue(veh, "obj:setPlanets({})")
  end
  active[playerId] = nil
end

-- =========================
-- Update loop (call from your event's onUpdate)
-- =========================
function M.onUpdate(dtReal, dtSim, dtRaw)
  local now = _now()

  for vid, st in pairs(active) do
    local veh = _vehById(vid)
    if not _isValidVeh(veh) then
      active[vid] = nil
    else
      -- Shockwave planets effect: apply until shockEnd then clear
      if st.shockEnd and now < st.shockEnd then
        st.nextPlanets = (st.nextPlanets or 0) - dtSim
        if st.nextPlanets <= 0 then
          st.nextPlanets = st.planetsInterval or DEFAULT.planetsUpdateIntervalSec

          -- Update sourcePos if source vehicle exists (robber moving)
          local sourcePos = st.sourcePos
          if st.sourceId then
            local s = _vehById(st.sourceId)
            if _isValidVeh(s) then
              sourcePos = s:getPosition()
            end
          end

          if sourcePos then
            -- Scale mass slightly by player size like forceField.lua does (optional, but helps consistency)
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
        -- Clear planets once
        _queue(veh, "obj:setPlanets({})")
        st.shockEnd = nil
      end

      -- EMP end (restore)
      if st.empEnd and now >= st.empEnd then
        _queue(veh, _cmdEmpEnd())
        st.empEnd = nil
      end

      if st.aiDisableEnd and now >= st.aiDisableEnd then
        _queue(veh, _cmdAiRestore())
        st.aiDisableEnd = nil
      end

      -- Cleanup entry if done
      if not st.empEnd and not st.shockEnd and not st.aiDisableEnd then
        active[vid] = nil
      end
    end
  end
end

-- For convenience, allow checking if a given vehicle currently has EMP active
function M.isActive(playerId)
  return active[playerId] ~= nil
end

return M
