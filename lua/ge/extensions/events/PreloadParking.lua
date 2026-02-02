-- PreloadParking.lua
-- Selects a parking spot for preloaded robber vehicles.

local M = {}

local CFG = nil
local Host = nil

local CACHE_TTL_SEC = 10
local DEFAULT_MIN_DISTANCE = 300
local DEFAULT_SEARCH_RADIUS = 4000

local S = {
  cachedSpots = nil,
  cacheAt = 0,
}

local function log(msg)
  if Host and Host.postLine then
    Host.postLine("PreloadParking", msg)
  else
    print("[PreloadParking] " .. tostring(msg))
  end
end

local function getDefaultSitesPath()
  if not getCurrentLevelIdentifier then
    return nil
  end
  local levelId = getCurrentLevelIdentifier() or ""
  if levelId == "" then
    return nil
  end
  return string.format("/levels/%s/city.sites.json", levelId)
end

local function ensureSitesLoaded(opts)
  if not gameplay_parking then
    return false
  end

  local ok, spots = pcall(gameplay_parking.getParkingSpots)
  if ok and type(spots) == "table" then
    return true
  end

  local options = opts or {}
  local sitesFile = options.sitesFile
    or (CFG and CFG.preloadSitesFile)
    or getDefaultSitesPath()

  if sitesFile and FS and FS.fileExists and not FS:fileExists(sitesFile) then
    log("Sites file not found: " .. tostring(sitesFile))
    return false
  end

  if sitesFile then
    pcall(function()
      gameplay_parking.setSites(sitesFile)
    end)
  end

  ok, spots = pcall(gameplay_parking.getParkingSpots)
  return ok and type(spots) == "table"
end

local function getPlayerPos()
  if Host and Host.getPlayerVeh then
    local veh = Host.getPlayerVeh()
    if veh and veh.getPosition then
      return veh:getPosition()
    end
  end
  if be and be.getPlayerVehicle then
    local veh = be:getPlayerVehicle(0)
    if veh and veh.getPosition then
      return veh:getPosition()
    end
  end
  return nil
end

local function tryFindParkingSpots(playerPos, searchRadius, opts)
  if not gameplay_parking then
    return nil
  end

  ensureSitesLoaded(opts)

  local attempts = {
    function()
      return gameplay_parking.findParkingSpots(playerPos, nil, searchRadius)
    end,
    function()
      return gameplay_parking.findParkingSpots(playerPos.x, playerPos.y, playerPos.z, searchRadius)
    end,
    function()
      return gameplay_parking.findParkingSpots(nil, nil, searchRadius)
    end,
  }

  for _, fn in ipairs(attempts) do
    local ok, res = pcall(fn)
    if ok and type(res) == "table" then
      return res
    end
  end

  local ok, res = pcall(gameplay_parking.getParkingSpots)
  if ok and type(res) == "table" then
    return res
  end

  return nil
end

local function cacheSpots(playerPos, searchRadius, opts)
  local spots = tryFindParkingSpots(playerPos, searchRadius, opts)
  if type(spots) ~= "table" then
    return nil
  end
  S.cachedSpots = spots
  S.cacheAt = os.clock()
  return spots
end

local function getCachedSpots(playerPos, searchRadius, cacheSeconds, forceRefresh, opts)
  if forceRefresh or not S.cachedSpots then
    return cacheSpots(playerPos, searchRadius, opts)
  end

  local ttl = cacheSeconds or CACHE_TTL_SEC
  if ttl > 0 and os.clock() - (S.cacheAt or 0) > ttl then
    return cacheSpots(playerPos, searchRadius, opts)
  end

  return S.cachedSpots
end

local function pickFarthestSpot(spots, playerPos, minDistance)
  if type(spots) ~= "table" or not playerPos then
    return nil, nil
  end

  local best = nil
  local bestDist = -1
  local threshold = minDistance or DEFAULT_MIN_DISTANCE

  for _, entry in ipairs(spots) do
    local pos = entry and entry.ps and entry.ps.pos
    if pos then
      local dist = playerPos:distance(pos)
      if dist >= threshold and dist > bestDist then
        best = entry
        bestDist = dist
      end
    end
  end

  return best, bestDist
end

function M.init(cfg, host)
  CFG = cfg
  Host = host
end

function M.clearCache()
  S.cachedSpots = nil
  S.cacheAt = 0
end

function M.getBestSpot(opts)
  local options = opts or {}
  local playerPos = options.playerPos or getPlayerPos()
  if not playerPos then
    return nil, "missing player position"
  end

  local searchRadius = options.searchRadius
    or (CFG and CFG.preloadParkingSearchRadius)
    or DEFAULT_SEARCH_RADIUS
  local minDistance = options.minDistance
    or (CFG and CFG.preloadParkingMinDistance)
    or DEFAULT_MIN_DISTANCE
  local cacheSeconds = options.cacheSeconds
  local forceRefresh = options.forceRefresh == true
  local sitesFile = options.sitesFile

  local spots = getCachedSpots(playerPos, searchRadius, cacheSeconds, forceRefresh, {
    sitesFile = sitesFile,
  })
  local best, bestDist = pickFarthestSpot(spots, playerPos, minDistance)
  if not best then
    log("No parking spot beyond min distance: " .. tostring(minDistance))
    return nil, "no spot beyond min distance"
  end

  return {
    entry = best,
    spot = best.ps,
    distance = bestDist,
  }, nil
end

return M
