-- lua/ge/extensions/events/bulletHit.lua
-- Standalone bullet-hit damage helper (self-contained, no external dependencies).
-- Runs damage logic inside the player vehicle via queueLuaCommand so it works for any player car.

local M = {}

local DEFAULT = {
  -- Probabilities per trigger call
  p_breakRandomPart = 1.00, -- 100%
  p_deformRandomPart = 0.70, -- 70%
  p_deflateTire = 0.10, -- 10%
  p_ignitePart = 0.10, -- 10%
  p_breakRandomBeam = 0.50, -- 50%

  -- Safety filters (recommended on)
  ignoreWheels = true,
  ignorePowertrain = true,
  ignoreBrittleDeform = true,

  -- If breakRandomPart finds nothing, allow fallback to breakRandomBeam or deform
  allowFallback = true,

  -- Optional: seed randomness for determinism (nil = no seeding)
  seed = nil,

  debug = false,
}

local function _vehById(id)
  if not id then return nil end
  return be:getObjectByID(id)
end

local function _isValidVeh(veh)
  return veh ~= nil and veh.getID and veh:getJBeamFilename() ~= ""
end

local function _mergeCfg(args)
  local cfg = {}
  for k, v in pairs(DEFAULT) do cfg[k] = v end
  if args then
    for k, v in pairs(args) do
      if cfg[k] ~= nil then cfg[k] = v end
    end
  end
  return cfg
end

local function _mkPayload(cfg)
  -- Note: Everything below executes inside vehicle Lua context (has v, obj, wheels, etc).
  return string.format([[
    -- bulletHit vehicle-side payload (self-contained)
    local cfg = {
      p_breakRandomPart = %0.4f,
      p_deformRandomPart = %0.4f,
      p_deflateTire = %0.4f,
      p_ignitePart = %0.4f,
      p_breakRandomBeam = %0.4f,
      ignoreWheels = %s,
      ignorePowertrain = %s,
      ignoreBrittleDeform = %s,
      allowFallback = %s,
      seed = %s,
      debug = %s,
    }

    local function dprint(msg)
      if cfg.debug and type(obj) == "table" and obj.debugDrawProxy then
        -- no-op; debugDrawProxy doesn't print. We'll just silently accept.
      end
    end

    local function chance(p) return math.random() < p end

    -- Optional deterministic randomness
    if cfg.seed ~= nil then
      local s = tonumber(cfg.seed)
      if s then math.randomseed(s) end
    end

    local okBeamstate, beamstate = pcall(require, "beamstate")
    local okFire, fire = pcall(require, "fire")

    -- Copied/condensed safety heuristics inspired by agentyMechanicalFailure:
    local genericWheelCenterNodeNames = {
      "fw", "rw", "stw", "fh", "rh", "bogw", "bt", "ax"
    }

    local genericPowertrainBreakGroupNames = {
      "eng", "Eng", "transmission", "Transmission", "shaft", "Shaft", "fuel", "Fuel",
      "susp", "leaf", "Leaf", "subframe", "strut", "steering", "Steering", "arm", "Arm",
      "airbox", "shackle", "hub", "axle", "Axle", "damp"
    }

    local brittleGroupsToIgnore = {
      "radiator_damage", "oilpan_damage", "mainEngine", "shaft"
    }

    local function safeNode(n)
      -- agenty checks: if name == nil and slidingFrictionCoef == nil, beam ops can be risky in some mods
      if not n then return false end
      if n.name == nil and n.slidingFrictionCoef == nil then return false end
      return true
    end

    local function beamIsSafe(b)
      if not b or not b.cid then return false end
      if obj:beamIsBroken(b.cid) then return false end
      if not v or not v.data or not v.data.nodes then return false end
      local n1 = v.data.nodes[b.id1]
      local n2 = v.data.nodes[b.id2]
      if not safeNode(n1) then return false end
      if not safeNode(n2) then return false end
      return true
    end

    local function nodeNameMatchesWheelPrefix(name)
      if not name then return false end
      for _, p in ipairs(genericWheelCenterNodeNames) do
        if string.match(name, p) then return true end
      end
      return false
    end

    local function isWheelRelatedBeam(b)
      if not cfg.ignoreWheels then return false end
      if not v or not v.data or not v.data.nodes then return false end
      local n1 = v.data.nodes[b.id1]
      local n2 = v.data.nodes[b.id2]
      local n1n = n1 and n1.name or nil
      local n2n = n2 and n2.name or nil
      if nodeNameMatchesWheelPrefix(n1n) or nodeNameMatchesWheelPrefix(n2n) then return true end
      if b.breakGroup and type(b.breakGroup) ~= "table" then
        if string.match(b.breakGroup, "wheel") or string.match(b.breakGroup, "Wheel") or string.match(b.breakGroup, "axle") then
          return true
        end
      end
      return false
    end

    local function isPowertrainBreakGroup(bg)
      if not cfg.ignorePowertrain then return false end
      if not bg or type(bg) ~= "string" then return false end
      for _, g in ipairs(genericPowertrainBreakGroupNames) do
        if string.match(bg, g) then return true end
      end
      return false
    end

    local function isBrittleDeformGroup(dg)
      if not cfg.ignoreBrittleDeform then return false end
      if not dg or type(dg) ~= "string" then return false end
      for _, g in ipairs(brittleGroupsToIgnore) do
        if string.match(dg, g) then return true end
      end
      return false
    end

    local function pickRandom(t)
      if not t or #t == 0 then return nil end
      return t[math.random(#t)]
    end

    local function breakRandomPart()
      if not v or not v.data or not v.data.beams then return false end
      local candidates = {}
      for _, b in pairs(v.data.beams) do
        if b and b.breakGroup ~= nil and type(b.breakGroup) ~= "table" and b.breakGroupType == 0 then
          if beamIsSafe(b) and (not isWheelRelatedBeam(b)) and (not isPowertrainBreakGroup(b.breakGroup)) then
            table.insert(candidates, b)
          end
        end
      end
      local sel = pickRandom(candidates)
      if not sel then return false end
      obj:breakBeam(sel.cid)
      return true
    end

    local function deformRandomPart()
      if not okBeamstate or not beamstate then return false end
      if not v or not v.data or not v.data.beams then return false end
      local groups = {}
      for _, b in pairs(v.data.beams) do
        if b and b.deformGroup ~= nil and type(b.deformGroup) ~= "table" then
          if beamIsSafe(b) and (not isBrittleDeformGroup(b.deformGroup)) then
            table.insert(groups, b.deformGroup)
          end
        end
      end
      local dg = pickRandom(groups)
      if not dg then return false end
      pcall(beamstate.triggerDeformGroup, dg)
      return true
    end

    local function breakRandomBeam()
      if not v or not v.data or not v.data.beams then return false end
      local candidates = {}
      for _, b in pairs(v.data.beams) do
        if beamIsSafe(b) then
          if not isWheelRelatedBeam(b) then
            table.insert(candidates, b)
          end
        end
      end
      local sel = pickRandom(candidates)
      if not sel then return false end
      obj:breakBeam(sel.cid)
      return true
    end

    local function deflateRandomTire()
      -- Best-effort, safe skipping if unsupported
      if not wheels or not wheels.wheels then return false end
      if not v or not v.data or not v.data.wheels then return false end
      if #wheels.wheels == 0 or #v.data.wheels == 0 then return false end

      -- pick random wheel index in [0, #wheels.wheels-1]
      local idx = math.random(0, #wheels.wheels - 1)
      local wheel = v.data.wheels[idx]
      if not wheel then return false end

      local tireBeams = {}
      local function add(list)
        if not list then return end
        for _, cid in pairs(list) do
          if cid and not obj:beamIsBroken(cid) then
            table.insert(tireBeams, cid)
          end
        end
      end
      add(wheel.treadBeams)
      add(wheel.sideBeams)
      add(wheel.peripheryBeams)
      add(wheel.reinfBeams)
      add(wheel.pressuredBeams)

      local cid = pickRandom(tireBeams)
      if not cid then return false end
      obj:breakBeam(cid)
      return true
    end

    local function igniteRandomPart()
      if not okFire or not fire or not fire.igniteRandomNode then return false end

      -- Exclude wheel nodes when considering if anything is flammable.
      local wheelNodes = {}
      if wheels and wheels.wheels then
        for _, wd in pairs(wheels.wheels) do
          if wd and wd.node1 then wheelNodes[wd.node1] = true end
          if wd and wd.node2 then wheelNodes[wd.node2] = true end
        end
      end

      local flammable = 0
      if v and v.data and v.data.nodes then
        for k, n in pairs(v.data.nodes) do
          if n and n.flashPoint ~= nil and not wheelNodes[k] then
            flammable = flammable + 1
          end
        end
      end
      if flammable <= 0 then return false end

      pcall(fire.igniteRandomNode)
      return true
    end

    -- Apply effects with requested probabilities.
    local didAnything = false

    -- 100% random damage to one part (breakGroup trigger), with safe filters
    if chance(cfg.p_breakRandomPart) then
      local ok = pcall(breakRandomPart)
      didAnything = didAnything or ok
    end

    -- 70% deform random part
    if chance(cfg.p_deformRandomPart) then
      local ok = pcall(deformRandomPart)
      didAnything = didAnything or ok
    end

    -- 10% deflate random tyre
    if chance(cfg.p_deflateTire) then
      local ok = pcall(deflateRandomTire)
      didAnything = didAnything or ok
    end

    -- 10% ignite random part
    if chance(cfg.p_ignitePart) then
      local ok = pcall(igniteRandomPart)
      didAnything = didAnything or ok
    end

    -- 50% break random beam
    if chance(cfg.p_breakRandomBeam) then
      local ok = pcall(breakRandomBeam)
      didAnything = didAnything or ok
    end

    -- Fallback: ensure at least one effect happened if requested
    if cfg.allowFallback and not didAnything then
      pcall(breakRandomBeam)
      pcall(deformRandomPart)
    end
  ]],
    cfg.p_breakRandomPart,
    cfg.p_deformRandomPart,
    cfg.p_deflateTire,
    cfg.p_ignitePart,
    cfg.p_breakRandomBeam,
    cfg.ignoreWheels and "true" or "false",
    cfg.ignorePowertrain and "true" or "false",
    cfg.ignoreBrittleDeform and "true" or "false",
    cfg.allowFallback and "true" or "false",
    cfg.seed ~= nil and string.format("%q", tostring(cfg.seed)) or "nil",
    cfg.debug and "true" or "false"
  )
end

--- Trigger bullet-hit damage on the player vehicle.
-- args:
--   playerId (required)
--   seed (optional), debug (optional)
--   probability overrides: p_breakRandomPart, p_deformRandomPart, p_deflateTire, p_ignitePart, p_breakRandomBeam
--   safety toggles: ignoreWheels, ignorePowertrain, ignoreBrittleDeform, allowFallback
function M.trigger(args)
  if not args or not args.playerId then
    return false, "missing playerId"
  end

  local veh = _vehById(args.playerId)
  if not _isValidVeh(veh) then
    return false, "invalid player vehicle"
  end

  local cfg = _mergeCfg(args)
  local payload = _mkPayload(cfg)

  local ok = false
  if veh.queueLuaCommand then
    ok = pcall(function() veh:queueLuaCommand(payload) end)
  elseif be and be.queueObjectLuaCommand then
    ok = pcall(function() be:queueObjectLuaCommand(veh:getID(), payload) end)
  end
  if not ok then
    return false, "queueLuaCommand failed"
  end

  return true, {
    queued = true,
    effects = {
      breakRandomPart = cfg.p_breakRandomPart,
      deformRandomPart = cfg.p_deformRandomPart,
      deflateTire = cfg.p_deflateTire,
      ignitePart = cfg.p_ignitePart,
      breakRandomBeam = cfg.p_breakRandomBeam,
    },
    safety = {
      ignoreWheels = cfg.ignoreWheels,
      ignorePowertrain = cfg.ignorePowertrain,
      ignoreBrittleDeform = cfg.ignoreBrittleDeform,
      allowFallback = cfg.allowFallback,
    },
  }
end

return M
