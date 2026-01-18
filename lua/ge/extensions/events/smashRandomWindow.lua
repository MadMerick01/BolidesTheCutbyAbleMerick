-- lua/ge/extensions/events/smashRandomWindow.lua
-- SmashRandomWindow: test utility event
-- When triggered, attempts to break a random glass/window breakGroup on the player vehicle.

local M = {}

local function smashRandomOnVeh(veh)
  if not veh then return false, "no vehicle" end
  if not veh.queueLuaCommand then return false, "veh has no queueLuaCommand" end

  -- Do the work in vehicle Lua context (most reliable for breakgroups / beamstate)
  veh:queueLuaCommand([[
    local function lower(s) return tostring(s or ""):lower() end

    -- Try to fetch breakgroups list (names/ids vary by vehicle)
    local groups = {}
    if beamstate and beamstate.getBreakGroups then
      local ok, res = pcall(beamstate.getBreakGroups)
      if ok and type(res) == "table" then groups = res end
    end

    -- Filter likely glass/window groups by name keywords
    local glass = {}
    for _, g in ipairs(groups) do
      local name = lower(g)
      if name:find("glass") or name:find("window") or name:find("windshield")
         or name:find("windscreen") or name:find("rear") and name:find("screen") then
        table.insert(glass, g)
      end
    end

    -- If none discovered, try a small set of common group names (varies per vehicle)
    if #glass == 0 then
      glass = {
        "glass", "glass_front", "glass_rear",
        "windshield", "windscreen", "rearwindow", "rear_window",
        "glass_windshield", "glass_rearwindow",
        "window_front", "window_rear",
        "sideglass", "side_glass"
      }
    end

    -- Random pick
    local pick = glass[math.random(1, #glass)]

    -- Try multiple breakGroup entry points (BeamNG versions differ)
    local broke = false
    if beamstate and beamstate.breakGroup then
      local ok = pcall(function() beamstate.breakGroup(pick) end)
      broke = broke or ok
    end
    if (not broke) and obj and obj.breakGroup then
      local ok = pcall(function() obj:breakGroup(pick) end)
      broke = broke or ok
    end

    -- If it still didn't break, brute-force attempt: iterate discovered groups (if we had them)
    if (not broke) and groups and #groups > 0 then
      for i = 1, #groups do
        local g = groups[math.random(1, #groups)]
        local name = lower(g)
        if name:find("glass") or name:find("window") or name:find("windshield") or name:find("windscreen") then
          if beamstate and beamstate.breakGroup then
            local ok = pcall(function() beamstate.breakGroup(g) end)
            if ok then broke = true break end
          end
          if obj and obj.breakGroup then
            local ok = pcall(function() obj:breakGroup(g) end)
            if ok then broke = true break end
          end
        end
      end
    end

    -- Optional debug print in vehicle console
    if broke then
      print("[SmashRandomWindow] Broke group: " .. tostring(pick))
    else
      print("[SmashRandomWindow] No suitable glass breakgroup found / breakGroup failed.")
    end
  ]])

  return true, "queued smash command"
end

function M.trigger(host, cfg)
  local veh = nil
  if host and host.getPlayerVeh then
    veh = host.getPlayerVeh()
  else
    veh = be:getPlayerVehicle(0)
  end

  local ok, msg = smashRandomOnVeh(veh)

  -- Optional UI/log line via host if available
  if host and host.postLine then
    host.postLine(ok and "Smashed a random window (if vehicle supports glass breakgroups)." or ("Smash failed: " .. tostring(msg)))
  else
    log("I", "SmashRandomWindow", ok and "Queued random window smash." or ("Smash failed: " .. tostring(msg)))
  end

  return ok
end

return M
