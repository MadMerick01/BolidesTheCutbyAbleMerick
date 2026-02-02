-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local im  = ui_imgui

local C = {}

C.name = 'Parking Points'
C.description = 'Computes Parking Points.'
C.category = 'repeat_instant'
C.color = im.ImVec4(0.4, 0.9, 1.0, 0.9)
C.author = 'BeamNG'
C.tmpSecondPassFlag = true
C.pinSchema = {

  {dir = 'in', type = 'number', name = 'dotAngle', description = ''},
  {dir = 'in', type = 'number', name = 'sideDist', description = ''},
  {dir = 'in', type = 'number', name = 'forwardDist', description = ''},

  {dir = 'out', type = 'number', name = 'score', description = ''},
  {dir = 'out', type = 'string', name = 'trans', description = ''},
}

C.tags = {}

function C:work()
  local pts = 0
  local angle = math.acos(self.pinIn.dotAngle.value)/math.pi * 180
  if angle ~= angle then angle = 0 end
  local angleScore = clamp(inverseLerp(7.5,1.6, angle), 0,1)

  local sideScore = clamp(inverseLerp(0.55,0.18,math.abs(self.pinIn.sideDist.value)), 0,1)
  local forwardScore = clamp(inverseLerp(0.75,0.22,math.abs(self.pinIn.forwardDist.value)), 0,1)

  local score = round(math.min(20,(angleScore+sideScore+forwardScore) * 6 + 2))
  log("D","",string.format("Parking Score: %d  (angle: %0.2fpts (%0.2f°) | side: %0.2fpts (%0.2fm) | forw: %0.2fpts (%0.2fm) | +2pts by default)",score, angleScore*6, angle, sideScore*6, self.pinIn.sideDist.value, forwardScore*6, self.pinIn.forwardDist.value ))
  if score >= 20 then
    self.pinOut.trans.value = 'missions.precisionParking.gameplay.rating.perfect'
  elseif score >= 15 then
    self.pinOut.trans.value = 'missions.precisionParking.gameplay.rating.great'
  elseif score >= 10 then
    self.pinOut.trans.value = 'missions.precisionParking.gameplay.rating.good'
  elseif score >= 5 then
    self.pinOut.trans.value = 'missions.precisionParking.gameplay.rating.ok'
  else
    self.pinOut.trans.value = 'missions.precisionParking.gameplay.rating.bad'
  end
  self.pinOut.score.value = score

end

return _flowgraph_createNode(C)
