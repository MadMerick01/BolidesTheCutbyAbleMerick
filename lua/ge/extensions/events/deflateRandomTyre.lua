-- lua/ge/extensions/events/deflateRandomTyre.lua
-- DeflateRandomTyre: test utility event
-- When triggered, deflates a random tyre on the player vehicle to 0.

local M = {}

local TYRE_POP_FILE = "/art/sound/tyrepop.wav"
local TYRE_POP_NAME = "bolides_tyre_pop"

-- Small helper: safe random int
local function randi(n)
  if not n or n <= 0 then return nil end
  return math.random(1, n)
end

local function playTyrePop(veh)
  if not veh or not veh.queueLuaCommand then return end
  local cmd = string.format([[
    if obj.playSFXOnce then
      pcall(function() obj:playSFXOnce(%q, 0, 1.0, 1.0) end)
    elseif obj.createSFXSource and obj.playSFX then
      local id = obj:createSFXSource(%q, "Audio2D", %q, -1)
      if id then
        if obj.stopSFX then pcall(function() obj:stopSFX(id) end) end
        if obj.stopSFXSource then pcall(function() obj:stopSFXSource(id) end) end
        if obj.stop then pcall(function() obj:stop(id) end) end
        pcall(function() obj:playSFX(id) end)
      end
    end
  ]], TYRE_POP_FILE, TYRE_POP_FILE, TYRE_POP_NAME)
  veh:queueLuaCommand(cmd)
end

-- Try multiple wheel/pressure APIs because BeamNG versions/mod contexts differ.
local function deflateRandomOnVeh(veh)
  if not veh then return false, "no vehicle" end

  -- Attempt A (some builds): direct wheel list on the vehicle object
  local ok, wheels = pcall(function()
    return veh.getWheels and veh:getWheels() or nil
  end)

  if ok and wheels and #wheels > 0 then
    local wi = randi(#wheels)
    local w = wheels[wi]
    if w then
      -- These fields vary; we try the common ones safely.
      pcall(function() w.pressure = 0 end)
      pcall(function() w.tirePressure = 0 end)
      return true, "deflated via veh:getWheels()"
    end
  end

  -- Attempt B (most reliable): run in vehicle Lua context and use wheels.* API if present
  -- We probe wheel count, pick random index, then set pressure to 0 if possible.
  local cmd = [[
    local wc = 0
    if wheels and wheels.wheels then
      wc = #wheels.wheels
    elseif wheels and wheels.getWheelCount then
      wc = wheels.getWheelCount()
    end

    if wc > 0 then
      local wi = math.random(0, wc-1) -- many vehicle-side APIs are 0-based
      if wheels and wheels.setWheelPressure then
        wheels.setWheelPressure(wi, 0)
      elseif wheels and wheels.setPressure then
        wheels.setPressure(wi, 0)
      end
    end
  ]]

  if veh.queueLuaCommand then
    veh:queueLuaCommand(cmd)
    return true, "deflated via veh:queueLuaCommand()"
  end

  return false, "no supported API found"
end

-- Public trigger function (called by GUI)
function M.trigger(host, cfg)
  -- Prefer host accessor if your mod provides it
  local veh = nil
  if host and host.getPlayerVeh then
    veh = host.getPlayerVeh()
  else
    veh = be:getPlayerVehicle(0)
  end

  playTyrePop(veh)

  local ok, msg = deflateRandomOnVeh(veh)

  -- Optional: post a UI/log line via host if available
  if host and host.postLine then
    host.postLine(ok and "Deflated a random tyre (pressure 0)." or ("Deflate failed: " .. tostring(msg)))
  else
    log("I", "DeflateRandomTyre", ok and "Deflated random tyre (0 pressure)." or ("Deflate failed: " .. tostring(msg)))
  end

  return ok
end

return M
