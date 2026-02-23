local M = {}

local dumped = false

local function dumpOpenXR()
  if dumped then return end
  dumped = true

  if not OpenXR then
    log("E", "RLS_XR", "OpenXR table not found in TLua")
    return
  end

  log("I", "RLS_XR", "Listing OpenXR functions available in TLua:")

  for k,v in pairs(OpenXR) do
    log("I", "RLS_XR", "  "..tostring(k).." ("..type(v)..")")
  end
end

M.onInit = dumpOpenXR

return M
