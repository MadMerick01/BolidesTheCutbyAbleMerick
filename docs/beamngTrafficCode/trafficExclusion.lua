local M = {}

local logTag = 'trafficExclusion'
local defaultRadius = 10

local function loadRacePath(mission)
  if not mission or not mission.missionFolder then return nil end
  local racePathFile = mission.missionFolder .. "/race.race.json"

  if not FS:fileExists(racePathFile) then
    log('D', logTag, "Race path file not found: " .. tostring(racePathFile))
    return nil
  end

  local path = require('/lua/ge/extensions/gameplay/race/path')("Temp Path")
  local content = jsonReadFile(racePathFile)
  if content then
    path:onDeserialized(content)
    return path
  else
    log('E', logTag, "Failed to read/parse race path: " .. tostring(racePathFile))
  end
  return nil
end

local function createZonesForRallyStage(mission)
  local zones = {}
  local path = loadRacePath(mission)
  if not path then return zones end

  -- Get all start positions
  if path.startPositions and path.startPositions.objects then
    for _, sp in pairs(path.startPositions.objects) do
      if sp.pos then
        table.insert(zones, {pos = vec3(sp.pos), radius = defaultRadius})
      end
    end
  end

  -- Get all pathnodes
  if path.pathnodes and path.pathnodes.objects then
    for _, pn in pairs(path.pathnodes.objects) do
      if pn.pos then
        table.insert(zones, {pos = vec3(pn.pos), radius = defaultRadius})
      end
    end
  end

  return zones
end

local function createZonesForRallyRoadSection(mission)
  local zones = {}
  local path = loadRacePath(mission)
  if not path then return zones end

  -- Get all start positions
  if path.startPositions and path.startPositions.objects then
    for _, sp in pairs(path.startPositions.objects) do
      if sp.pos then
        table.insert(zones, {pos = vec3(sp.pos), radius = defaultRadius})
      end
    end
  end

  return zones
end

local function createZones(missions)
  missions = missions or {}
  local zones = {}

  -- If missions aren't provided, try to get the current active one from the editor
  if not next(missions) and editor_rallyEditor then
    local missionId = editor_rallyEditor.getMissionId()
    if missionId then
      local mission = gameplay_missions_missions.getMissionById(missionId)
      if mission then
        table.insert(missions, mission)
      else
        log('E', logTag, "Mission not found: " .. tostring(missionId))
      end
    end
  end

  if not next(missions) then
    log('W', logTag, "No missions available for traffic exclusion")
    return {}
  end

  for _, mission in ipairs(missions) do
    if mission.missionType == "rallyStage" then
      local zones1 = createZonesForRallyStage(mission)
      for _, z in ipairs(zones1) do table.insert(zones, z) end
    elseif mission.missionType == "rallyRoadSection" then
      local zones1 = createZonesForRallyRoadSection(mission)
      for _, z in ipairs(zones1) do table.insert(zones, z) end
    else
      log('W', logTag, "Unsupported mission type for traffic exclusion: " .. tostring(mission.missionType))
    end
  end

  log('I', logTag, string.format("Created %d traffic exclusion zones for %d missions", #zones, #missions))
  return zones
end

M.createZones = createZones

return M
