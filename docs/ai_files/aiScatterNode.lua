-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local C = {}

C.name = 'Scatter Other Vehicles'
C.description = 'Teleports all other vehicles away from the player or camera position.'
C.category = 'once_instant'
C.color = ui_flowgraph_editor.nodeColors.traffic
C.author = 'BeamNG'
C.pinSchema = {}

C.tags = {}

function C:workOnce()
  for _, v in ipairs(getAllVehiclesByType()) do
    local id = v:getID()
    if id ~= be:getPlayerVehicleID(0) then
      gameplay_traffic.forceTeleport(id, nil, nil, 250, 1000)
    end
  end
end

return _flowgraph_createNode(C)
