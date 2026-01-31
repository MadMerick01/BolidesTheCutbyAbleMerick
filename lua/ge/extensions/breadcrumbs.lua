-- lua/ge/extensions/breadcrumbs.lua
-- Robust Breadcrumbs + Forward Known (FKB) system (forward + back)
-- Safe draw pattern (no draw in update; draw only in onDrawDebug with vehicle gate + pcall)

local M = {}

-- =========================
-- Host refs (optional)
-- =========================
local CFG = nil
local HOST_STATE = nil

-- =========================
-- Travel config (defaults; may be overridden by CFG.TRAVEL in init)
-- =========================
local TRAVEL = {
  crumbEveryMeters = 1.0,
  keepMeters = 5200.0,
  teleportResetMeters = 50.0,
}

-- =========================
-- Debug
-- =========================
local debugBreadcrumbMarkers = false

local FORWARD_DEBUG_SPACINGS = { 200, 300 }
local BACK_BREADCRUMB_METERS = { 10, 100, 200, 300 }

local DEBUG_LABEL_OFFSET = vec3(0, 0, 1.5)
local DEBUG_FWD_COLOR  = ColorF(0.2, 0.9, 1.0, 1.0)
local DEBUG_BACK_COLOR = ColorF(1.0, 0.6, 0.2, 1.0)
local DEBUG_TEXT_COLOR = ColorF(1.0, 1.0, 1.0, 1.0)

-- =========================
-- Internal helpers
-- =========================
local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function safeClock()
  if os and os.clock then return os.clock() end
  return 0
end

local function getPlayerVehicle()
  -- BeamNG GE helper usually exists; keep it simple
  return be:getPlayerVehicle(0)
end

local function getHorizontalFwdFromVehicle(veh)
  if not veh then return vec3(0,1,0) end
  local dir = veh:getDirectionVector()
  if not dir then return vec3(0,1,0) end
  dir.z = 0
  local len = dir:length()
  if len < 1e-6 then return vec3(0,1,0) end
  return dir / len
end

local function cosDeg(deg)
  return math.cos((deg or 0) * math.pi / 180)
end

local function isSegmentWithinCone(segDir, playerFwd, coneDeg)
  if not (segDir and playerFwd) then return false end
  local sd = vec3(segDir.x, segDir.y, 0)
  local pf = vec3(playerFwd.x, playerFwd.y, 0)
  local sdl = sd:length()
  local pfl = pf:length()
  if sdl < 1e-6 or pfl < 1e-6 then return false end
  sd = sd / sdl
  pf = pf / pfl
  local d = sd:dot(pf)
  local threshold = cosDeg((coneDeg or 80) * 0.5)
  return d >= threshold
end

local function projectPointToSegment(p, a, b)
  local ab = b - a
  local abLen2 = ab:squaredLength()
  if abLen2 < 1e-6 then
    return a, 0
  end
  local t = (p - a):dot(ab) / abLen2
  t = clamp01(t)
  return a + ab * t, t
end

-- =========================
-- Runtime travel state
-- =========================
local travelCrumbs = {}     -- {pos=vec3, fwd=vec3, dist=number}
local travelTotalForward = 0.0
local travelLastPos = nil
local travelLastFwd = nil
local travelAccumSinceCrumb = 0.0

-- Back crumb positions
local backCrumbPos = {
  [10]  = nil,
  [100] = nil,
  [200] = nil,
  [300] = nil,
}

-- Fallback preload spot (fixed after enough travel)
local fallbackPreloadPos = nil
local fallbackPreloadReady = false
local FALLBACK_PRELOAD_DISTANCE = 600.0

local function findCrumbAtOrBeforeDist(targetDist)
  if #travelCrumbs == 0 then return nil end
  for i = #travelCrumbs, 1, -1 do
    local d = travelCrumbs[i].dist or 0
    if d <= targetDist then
      return travelCrumbs[i]
    end
  end
  return travelCrumbs[1]
end

local function sampleCrumbAtDistance(targetDist)
  if #travelCrumbs < 2 then return nil end
  if targetDist <= (travelCrumbs[1].dist or 0) then
    return travelCrumbs[1].pos
  end
  if targetDist >= (travelCrumbs[#travelCrumbs].dist or 0) then
    return travelCrumbs[#travelCrumbs].pos
  end

  for i = #travelCrumbs - 1, 1, -1 do
    local da = travelCrumbs[i].dist or 0
    local db = travelCrumbs[i+1].dist or da
    if da <= targetDist and targetDist <= db and (db - da) > 1e-6 then
      local t = (targetDist - da) / (db - da)
      local a = travelCrumbs[i].pos
      local b = travelCrumbs[i+1].pos
      return a + (b - a) * t
    end
  end

  return nil
end

local function trimCrumbs()
  if #travelCrumbs == 0 then return end
  local latestDist = travelCrumbs[#travelCrumbs].dist or 0
  local minDist = latestDist - (TRAVEL.keepMeters or 0)

  local firstKeep = 1
  for i = 1, #travelCrumbs do
    if (travelCrumbs[i].dist or 0) >= minDist then
      firstKeep = i
      break
    end
  end

  if firstKeep > 1 then
    local new = {}
    for i = firstKeep, #travelCrumbs do
      new[#new+1] = travelCrumbs[i]
    end
    travelCrumbs = new
  end
end

local function pushCrumb(pos, fwd, dist)
  travelCrumbs[#travelCrumbs + 1] = {
    pos = pos,
    fwd = fwd,
    dist = dist
  }
  trimCrumbs()
end

-- =========================
-- Back breadcrumb computation (Codex-safe forward declaration style)
-- =========================
local updateBackCrumbPositions -- forward declare (prevents nil call on some refactor patterns)

local function isBackBreadcrumbReady(meters)
  if not meters then return false end
  return backCrumbPos[meters] ~= nil
end

updateBackCrumbPositions = function()
  if #travelCrumbs == 0 then return end
  local latestDist = travelCrumbs[#travelCrumbs].dist or 0
  for _, meters in ipairs(BACK_BREADCRUMB_METERS) do
    local target = latestDist - meters
    local c = findCrumbAtOrBeforeDist(target)
    backCrumbPos[meters] = c and c.pos or nil
  end

  if not fallbackPreloadReady and latestDist >= FALLBACK_PRELOAD_DISTANCE then
    if backCrumbPos[300] then
      fallbackPreloadPos = backCrumbPos[300]
      fallbackPreloadReady = true
    end
  end
end

-- =========================
-- Forward-known (FKB) robust anchor state
-- =========================
local FKB_CONE_DEG = 80
local FKB_ANCHOR_HOLD_RADIUS = 12.0
local FKB_ANCHOR_BAD_FRAME_LIMIT = 30
local FKB_REACQUIRE_HISTORY_METERS = 5000.0
local FKB_REACQUIRE_MAX_DISTANCE = 120.0

local forwardKnownAvailabilityCache = {
  [10]  = { available=false, eligible=false, distAhead=nil, pos=nil, dir=nil, crumb=nil, lastGoodPos=nil, lastGoodT=nil, lastGoodCrumb=nil },
  [50]  = { available=false, eligible=false, distAhead=nil, pos=nil, dir=nil, crumb=nil, lastGoodPos=nil, lastGoodT=nil, lastGoodCrumb=nil },
  [100] = { available=false, eligible=false, distAhead=nil, pos=nil, dir=nil, crumb=nil, lastGoodPos=nil, lastGoodT=nil, lastGoodCrumb=nil },
  [200] = { available=false, eligible=false, distAhead=nil, pos=nil, dir=nil, crumb=nil, lastGoodPos=nil, lastGoodT=nil, lastGoodCrumb=nil },
  [300] = { available=false, eligible=false, distAhead=nil, pos=nil, dir=nil, crumb=nil, lastGoodPos=nil, lastGoodT=nil, lastGoodCrumb=nil },
}

local forwardKnownAvailabilityMeta = {
  segStartIdx = nil,
  dir = nil,
  distToProjection = nil
}

local fkbAnchor = nil
local fkbAnchorBadFrames = 0

local function clearForwardKnownTransient()
  for _, spacing in ipairs(FORWARD_DEBUG_SPACINGS) do
    local e = forwardKnownAvailabilityCache[spacing]
    e.available = false
    e.eligible = false
    e.distAhead = nil
    e.pos = nil
    e.crumb = nil
    e.dir = nil
  end
end

local function computeAnchorFromSegment(i, playerPos)
  local a = travelCrumbs[i].pos
  local b = travelCrumbs[i+1].pos
  local proj, t = projectPointToSegment(playerPos, a, b)

  local da = travelCrumbs[i].dist or 0
  local db = travelCrumbs[i+1].dist or da
  local projDist = da + (db - da) * t

  local segDir = (b - a)
  segDir.z = 0
  local segLen = segDir:length()
  if segLen < 1e-6 then return nil end
  segDir = segDir / segLen

  return {
    segStartIdx = i,
    segT = t,
    anchorDist = projDist,
    anchorPos = proj,
    segDir = segDir,
    distToProjection = (playerPos - proj):length()
  }
end

local function isAnchorStillGood(anchor, playerPos, playerFwd, coneDeg)
  if not anchor then return false end
  local i = anchor.segStartIdx
  if not i or i < 1 or i >= #travelCrumbs then return false end

  local a = computeAnchorFromSegment(i, playerPos)
  if not a then return false end

  if (a.distToProjection or 9999) > (FKB_ANCHOR_HOLD_RADIUS or 12.0) then
    return false
  end

  if not isSegmentWithinCone(a.segDir, playerFwd, coneDeg) then
    return false
  end

  return true, a
end

local function reacquireAnchor(playerPos, playerFwd, coneDeg)
  if #travelCrumbs < 2 then return nil end

  local latestDist = travelCrumbs[#travelCrumbs].dist or 0
  local minSearchDist = latestDist - (FKB_REACQUIRE_HISTORY_METERS or 5000.0)

  local best = nil
  local bestD = math.huge

  for i = #travelCrumbs - 1, 1, -1 do
    local d = travelCrumbs[i].dist or 0
    if d < minSearchDist then break end

    local a = computeAnchorFromSegment(i, playerPos)
    if a then
      if a.distToProjection < bestD
        and a.distToProjection <= (FKB_REACQUIRE_MAX_DISTANCE or 120.0)
        and isSegmentWithinCone(a.segDir, playerFwd, coneDeg)
      then
        bestD = a.distToProjection
        best = a
      end
    end
  end

  return best
end

local function resolveFkbAnchor(playerPos, playerFwd, coneDeg)
  forwardKnownAvailabilityMeta.segStartIdx = nil
  forwardKnownAvailabilityMeta.dir = nil
  forwardKnownAvailabilityMeta.distToProjection = nil

  coneDeg = coneDeg or FKB_CONE_DEG

  if fkbAnchor then
    local ok, updated = isAnchorStillGood(fkbAnchor, playerPos, playerFwd, coneDeg)
    if ok and updated then
      fkbAnchorBadFrames = 0
      fkbAnchor = {
        segStartIdx = updated.segStartIdx,
        segT = updated.segT,
        anchorDist = updated.anchorDist,
        anchorPos = updated.anchorPos,
        segDir = updated.segDir
      }

      forwardKnownAvailabilityMeta.segStartIdx = updated.segStartIdx
      forwardKnownAvailabilityMeta.dir = "fwd"
      forwardKnownAvailabilityMeta.distToProjection = updated.distToProjection
      return fkbAnchor
    end

    fkbAnchorBadFrames = (fkbAnchorBadFrames or 0) + 1
    if fkbAnchorBadFrames < (FKB_ANCHOR_BAD_FRAME_LIMIT or 30) then
      forwardKnownAvailabilityMeta.segStartIdx = fkbAnchor.segStartIdx
      forwardKnownAvailabilityMeta.dir = "fwd"
      forwardKnownAvailabilityMeta.distToProjection = nil
      return fkbAnchor
    end
  end

  local a = reacquireAnchor(playerPos, playerFwd, coneDeg)
  if not a then
    return nil
  end

  fkbAnchorBadFrames = 0
  fkbAnchor = {
    segStartIdx = a.segStartIdx,
    segT = a.segT,
    anchorDist = a.anchorDist,
    anchorPos = a.anchorPos,
    segDir = a.segDir
  }

  forwardKnownAvailabilityMeta.segStartIdx = a.segStartIdx
  forwardKnownAvailabilityMeta.dir = "fwd"
  forwardKnownAvailabilityMeta.distToProjection = a.distToProjection

  return fkbAnchor
end

local forwardKnownCheckTimer = 0.0

local function updateForwardKnownAvailability(dtSim, playerPos, playerFwd)
  forwardKnownCheckTimer = forwardKnownCheckTimer + (dtSim or 0)

  local interval = (CFG and CFG.forwardKnownCheckIntervalSec) or 0.20
  if forwardKnownCheckTimer < interval then
    return
  end
  forwardKnownCheckTimer = 0.0

  clearForwardKnownTransient()

  -- How wide "in front" is allowed to be (bigger = more spam, as you requested)
  local coneDeg = 110 -- was 80; make it wider for now
  local cosHalf = math.cos((coneDeg * 0.5) * math.pi / 180)

  -- Tolerances: bigger = more likely to find something
  local distTol = 20.0        -- accept +/- 20m around the target spacing
  local maxLateral = 60.0     -- how far sideways we still accept

  local minAhead = (CFG and CFG.forwardKnownMinAheadMeters) or 0.0
  local maxAhead = (CFG and CFG.forwardKnownMaxAheadMeters) or 999999.0

  -- For GUI meta
  forwardKnownAvailabilityMeta.segStartIdx = nil
  forwardKnownAvailabilityMeta.dir = "world"
  forwardKnownAvailabilityMeta.distToProjection = nil

  if #travelCrumbs < 2 then return end

  local now = safeClock()

  -- Precompute unit forward
  local pf = vec3(playerFwd.x, playerFwd.y, 0)
  local pfl = pf:length()
  if pfl < 1e-6 then return end
  pf = pf / pfl

  -- For each desired spacing, find the "best" crumb in front of the car.
  -- Best = closest to target forward distance, and least lateral error.
  for _, spacing in ipairs(FORWARD_DEBUG_SPACINGS) do
    local bestPos = nil
    local bestForward = nil
    local bestLat = math.huge
    local bestAbsErr = math.huge
    local bestDistAhead = nil

    -- Scan all kept crumbs (keepMeters window). With 1m crumbs and ~5200m keep, this is fine.
    for i = 1, #travelCrumbs do
      local cpos = travelCrumbs[i].pos
      if cpos then
        local v = cpos - playerPos
        local vz = vec3(v.x, v.y, 0)
        local s = vz:dot(pf) -- forward distance along car forward

        if s > 0 then
          local vlen = vz:length()
          if vlen > 1e-3 then
            local cosang = s / vlen
            if cosang >= cosHalf then
              -- lateral distance from the forward ray
              local latVec = vz - (pf * s)
              local lat = latVec:length()

              if lat <= maxLateral then
                local absErr = math.abs(s - spacing)

                -- accept if close enough to the target distance
                if absErr <= distTol then
                  -- choose smallest absErr first, then smallest lateral
                  if absErr < bestAbsErr or (absErr == bestAbsErr and lat < bestLat) then
                    bestAbsErr = absErr
                    bestLat = lat
                    bestPos = cpos
                    bestForward = s
                    bestDistAhead = vlen
                  end
                end
              end
            end
          end
        end
      end
    end

    local e = forwardKnownAvailabilityCache[spacing]

    if bestPos then
      e.available = true
      e.pos = bestPos
      e.dir = "fwd"
      e.distAhead = bestDistAhead or bestForward or (bestPos - playerPos):length()
      e.crumb = { idx = -1 } -- optional; we’re not relying on dist-index here

      -- keep eligibility for later gating
      e.eligible = (e.distAhead >= minAhead and e.distAhead <= maxAhead)

      -- lastGood always updated when we find something
      e.lastGoodPos = bestPos
      e.lastGoodT = now
      e.lastGoodCrumb = e.crumb
    else
      -- fallback: hold lastGood for a few seconds to avoid flicker
      if e.lastGoodPos and e.lastGoodT and (now - e.lastGoodT) <= 3.0 then
        e.available = true
        e.pos = e.lastGoodPos
        e.crumb = e.lastGoodCrumb
        e.dir = e.dir or "fwd"
        e.distAhead = (e.pos - playerPos):length()
        e.eligible = true
      end
    end
  end
end


-- =========================
-- Debug marker drawing (ONLY called from onDrawDebug; never from update)
-- =========================
local function drawBreadcrumbDebugMarkers()
  if not debugBreadcrumbMarkers then return end
  local dd = debugDrawer
  if not dd then return end

  for i = 1, #FORWARD_DEBUG_SPACINGS do
    local spacing = FORWARD_DEBUG_SPACINGS[i]
    local availability = forwardKnownAvailabilityCache[spacing]
    if availability and availability.available and availability.pos then
      local pos = availability.pos
      dd:drawSphere(pos, 1.5, DEBUG_FWD_COLOR)
      dd:drawText(pos + DEBUG_LABEL_OFFSET, string.format("F%d (%.0fm)", spacing, availability.distAhead or -1), DEBUG_TEXT_COLOR)

    end
  end

  for i = 1, #BACK_BREADCRUMB_METERS do
    local backMeters = BACK_BREADCRUMB_METERS[i]
    if isBackBreadcrumbReady(backMeters) then
      local pos = backCrumbPos[backMeters]
      if pos then
        dd:drawSphere(pos, 1.5, DEBUG_BACK_COLOR)
        dd:drawText(pos + DEBUG_LABEL_OFFSET, string.format("B%d ready", backMeters), DEBUG_TEXT_COLOR)
      end
    end
  end
end

-- =========================
-- Public API
-- =========================
function M.init(hostCfg, hostState)
  CFG = hostCfg or CFG
  HOST_STATE = hostState or HOST_STATE

  -- Apply host travel config (so your CFG.TRAVEL actually changes behavior)
  if CFG and CFG.TRAVEL then
    TRAVEL.crumbEveryMeters    = CFG.TRAVEL.crumbEveryMeters    or TRAVEL.crumbEveryMeters
    TRAVEL.keepMeters          = CFG.TRAVEL.keepMeters          or TRAVEL.keepMeters
    TRAVEL.teleportResetMeters = CFG.TRAVEL.teleportResetMeters or TRAVEL.teleportResetMeters
  end
end

function M.reset()
  travelCrumbs = {}
  travelTotalForward = 0.0
  travelLastPos = nil
  travelLastFwd = nil
  travelAccumSinceCrumb = 0.0

  backCrumbPos[10] = nil
  backCrumbPos[100] = nil
  backCrumbPos[200] = nil
  backCrumbPos[300] = nil

  fallbackPreloadPos = nil
  fallbackPreloadReady = false

  fkbAnchor = nil
  fkbAnchorBadFrames = 0
  forwardKnownCheckTimer = 0.0

  clearForwardKnownTransient()
end

function M.update(dtSim)
  local v = getPlayerVehicle()
  if not v then return end

  local pos = v:getPosition()
  if not pos then return end

  local fwdNow = getHorizontalFwdFromVehicle(v)

  if travelLastPos then
    local jump = (pos - travelLastPos):length()
    if jump > (TRAVEL.teleportResetMeters or 50.0) then
      M.reset()
      travelLastPos = pos
      travelLastFwd = fwdNow
      pushCrumb(pos, fwdNow, 0.0)
      updateBackCrumbPositions()
      updateForwardKnownAvailability(dtSim, pos, fwdNow)
      return
    end
  end

  if not travelLastPos then
    travelLastPos = pos
    travelLastFwd = fwdNow
    pushCrumb(pos, fwdNow, travelTotalForward)
    updateBackCrumbPositions()
    updateForwardKnownAvailability(dtSim, pos, fwdNow)
    return
  end

  local stepDist = (pos - travelLastPos):length()
  if stepDist > 0.0 then
    travelTotalForward = travelTotalForward + stepDist
    travelAccumSinceCrumb = travelAccumSinceCrumb + stepDist
    travelLastPos = pos
    travelLastFwd = fwdNow

    local every = TRAVEL.crumbEveryMeters or 1.0
    if travelAccumSinceCrumb >= every then
      travelAccumSinceCrumb = 0.0
      pushCrumb(pos, fwdNow, travelTotalForward)
      updateBackCrumbPositions()
    end
  end

  updateForwardKnownAvailability(dtSim, pos, fwdNow)
end

-- Draw hook (Codex-safe): vehicle gate + pcall
function M.onDrawDebug()
  local v = getPlayerVehicle()
  if not v then return end
  if not debugBreadcrumbMarkers then return end
  pcall(drawBreadcrumbDebugMarkers)
end

function M.setDebugMarkersEnabled(v)
  debugBreadcrumbMarkers = (v == true)
end

function M.getDebugMarkersEnabled()
  return debugBreadcrumbMarkers
end

function M.getTravel()
  return TRAVEL, travelCrumbs, travelTotalForward
end

function M.getForwardKnown()
  return forwardKnownAvailabilityCache, forwardKnownAvailabilityMeta, FORWARD_DEBUG_SPACINGS
end

function M.getBack()
  return BACK_BREADCRUMB_METERS, backCrumbPos, isBackBreadcrumbReady
end

function M.getPreloadFallback()
  return fallbackPreloadPos
end

return M
