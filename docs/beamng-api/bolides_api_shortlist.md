# Bolides API Shortlist (v0.38)

This is the small list of BeamNG APIs Codex should consult first for this mod. Check items as they are verified in the dump and adopted.

## Audio
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `obj:createSFXSource(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `obj:playSFX(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `obj:playSFXOnce(...)`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `forEachAudioChannel(...)`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getAudioChannelsVolume(...)`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `setAudioChannelsVolume(...)`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `sfxCreateDevice(...)`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `testSounds(...)`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_audio.*`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_audioRibbon.*`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_sounds.*`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_audio.*`
- [x] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_settings_audio.*`

## Spawning
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_vehicles.spawnNewVehicle(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_vehicle_manager.spawnNewVehicle(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `spawn.spawnVehicle(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `spawn.safeTeleport(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `spawn.pickSpawnPoint(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `spawn.calculateRelativeVehiclePlacement(...)`

## AI driving / pursuit
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiMode(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiTarget(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiRoute(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiPath(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiAggression(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiAggressionMode(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.setAiAvoidCars(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.trackVehicle(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ai.*` (vehicle-side, not in GE dump)

## UI / ImGui
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.Begin(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.End()`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.Text(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.TextWrapped(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.Button(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.SameLine()`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.SetNextWindowSize(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.SetWindowFontScale(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.PushStyleColor2(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.ImVec2(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.ImColorByRGB(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `ui_imgui.BoolPtr(...)`

## Career / money
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_playerAttributes.getAttributeValue(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_playerAttributes.getAttribute(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_playerAttributes.setAttributes(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_playerAttributes.addAttributes(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_payment.canPay(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_payment.pay(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `career_modules_payment.reward(...)`

## Damage / impact
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.queueLuaCommand(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.queueLuaCommandByName(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.breakBreakGroup(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.triggerDeformGroup(...)`

## Traffic / police / ambience
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.activate(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.deactivate(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.setupTraffic(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.setupCustomTraffic(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.spawnTraffic(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.getTrafficList(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic.getTrafficAiVehIds(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic_trafficUtils.createTrafficGroup(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `gameplay_traffic_trafficUtils.findSafeSpawnPoint(...)`

## Vehicle access / objects
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getObjectByID(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getObjectsByClass(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getAllVehiclesByType(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `activeVehiclesIterator(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getClosestVehicle(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `be:getObjectByID(...)` (GE userdata method, not listed in dump)
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getObjById(...)` (not listed in dump)

## Camera / view
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getCameraPosition(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `getCameraTransform(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `setCameraFovDeg(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `setCameraFovRad(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_camera.isCameraInside(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_camera.getActiveCamNameByVehId(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_camera.getActiveGlobalCameraName(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `core_camera.getActiveCamName(...)` (not listed in dump)

## Vehicle Lua context / queue helpers
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.queueLuaCommand(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `scenario/scenariohelper.queueLuaCommandByName(...)`
- [ ] Verified in dump · [ ] Used in mod · [ ] Wrapped by compat helper — `veh:queueLuaCommand(...)` (vehicle-side, not listed in GE dump)
