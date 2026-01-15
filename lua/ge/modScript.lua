-- lua/ge/modScript.lua
-- Bolides The Cut bootstrap loader
-- Keeps extension load explicit and sets unload mode to manual (if supported).

local TAG = "BOLIDES_THE_CUT"
local EXT = "bolidesTheCut"

log("I", TAG, "modScript.lua running - loading " .. EXT)

if extensions and extensions.load then
  extensions.load(EXT)
  log("I", TAG, "extensions.load('" .. EXT .. "') called")
else
  log("E", TAG, "extensions.load not available here")
end

if type(setExtensionUnloadMode) == "function" then
  setExtensionUnloadMode(EXT, "manual")
  log("I", TAG, "setExtensionUnloadMode('" .. EXT .. "', 'manual') called")
end
