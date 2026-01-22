# Audio topic

## Purpose
Document the global (GE) audio APIs and settings surfaced in the BeamNG 0.38 API dump,
alongside the core audio modules used to load banks, drive engine/exhaust sound behavior,
manage sound emitters, and play UI audio events.【F:docs/beamng-api/raw/api_dump_0.38.json†L14180-L14212】【F:docs/beamng-api/raw/api_dump_0.38.json†L24531-L24555】【F:docs/beamng-api/raw/api_dump_0.38.json†L26898-L26936】【F:docs/beamng-api/raw/api_dump_0.38.json†L30425-L30746】

## Common tasks
- Load audio banks for the current level or vehicle via `core_audio.loadLevelBank` and `core_audio.loadVehicleBank`.【F:docs/beamng-api/raw/api_dump_0.38.json†L24531-L24555】
- Play UI audio events via `ui_audio.playEventSound`.【F:docs/beamng-api/raw/api_dump_0.38.json†L30742-L30746】
- Manage emitter ribbons (spatial SFX emitters) with `core_audioRibbon` helpers such as `createEmitterHost`, `setRibbons`, and `clearAllSFXEmitters`.【F:docs/beamng-api/raw/api_dump_0.38.json†L14184-L14212】
- Tune vehicle engine/exhaust audio with `core_sounds` helpers such as `initEngineSound`, `initExhaustSound`, `setEngineSoundParameter`, and `updateEngineSound`.【F:docs/beamng-api/raw/api_dump_0.38.json†L26898-L26936】
- Inspect and adjust audio channel volumes via global functions: `forEachAudioChannel`, `getAudioChannelsVolume`, and `setAudioChannelsVolume`.【F:docs/beamng-api/index/index_functions.md†L149-L164】【F:docs/beamng-api/index/index_functions.md†L422-L423】
- Manage audio device options via `core_settings_audio` (e.g., `switchOutputDevice`).【F:docs/beamng-api/raw/api_dump_0.38.json†L15672-L15686】

## Verified APIs (from dump)
Global functions (GE):
- `forEachAudioChannel(...)`【F:docs/beamng-api/index/index_functions.md†L149-L149】
- `getAudioChannelsVolume(...)`【F:docs/beamng-api/index/index_functions.md†L163-L163】
- `setAudioChannelsVolume(...)`【F:docs/beamng-api/index/index_functions.md†L422-L422】
- `sfxCreateDevice(...)`【F:docs/beamng-api/index/index_functions.md†L453-L453】
- `testSounds(...)`【F:docs/beamng-api/index/index_functions.md†L510-L510】

Core audio modules:
- `core_audio`: `loadLevelBank`, `loadVehicleBank`, `registerBaseBank`, `triggerBankHotloading`, `onClientPreStartMission`, `onClientEndMission`, `onFirstUpdate`, `onPhysicsPaused`, `onPhysicsUnpaused`, `onReplayStateChanged`, `onFilesChanged`, `onSerialize`, `onDeserialized`.【F:docs/beamng-api/raw/api_dump_0.38.json†L24531-L24555】
- `core_audioRibbon`: `createEmitterHost`, `setRibbons`, `updateRibbonData`, `getRibbons`, `getRibbonNames`, `getNearList`, `getFarList`, `getSfxEmitters`, `clearAllSFXEmitters`, `clearNearFarLists`, `clearRibbonNames`, `removeRibbon`, `recomputeMap`, `onUpdate`, `onEditorBeforeSaveLevel`, `onClientCustomObjectSpawning`, `onSerialize`, `onDeserialized`.【F:docs/beamng-api/raw/api_dump_0.38.json†L14184-L14212】
- `core_sounds`: `initEngineSound`, `initExhaustSound`, `setEngineSoundParameter`, `setEngineSoundParameterList`, `setExhaustSoundNodes`, `setAudioBlur`, `setCabinFilterStrength`, `updateEngineSound`, plus mission/UI lifecycle hooks (`onSettingsChanged`, `onUiChangedState`, `onMissionInfoChangedState`, `onMissionAvailabilityChanged`, `onVehicleSwitched`, `onPreRender`, `onActivityAcceptGatherData`).【F:docs/beamng-api/raw/api_dump_0.38.json†L26898-L26936】
- `ui_audio`: `playEventSound`, `onFirstUpdate`.【F:docs/beamng-api/raw/api_dump_0.38.json†L30742-L30746】
- `core_settings_audio`: `switchOutputDevice`, `getOptions`, `restoreDefaults`, `buildOptionHelpers`, `onFirstUpdateSettings`.【F:docs/beamng-api/raw/api_dump_0.38.json†L15672-L15686】

Audio settings keys (from `core_settings_settings.impl.defaultValues`):
- `AudioMasterVol`, `AudioMusicVol`, `AudioUiVol`, `AudioOtherVol`, `AudioEnvironmentVol`, `AudioSurfaceVol`, `AudioCollisionVol`, `AudioSuspensionVol`, `AudioTransmissionVol`, `AudioPowerVol`, `AudioForcedInductionVol`, `AudioAeroVol`, `AudioLfeVol`, `AudioInsideModifier`, `AudioIntercomVol`, `AudioMaxSoftwareBuffers`, `AudioUseHardware`, `AudioEnableStereoHeadphones`, `AudioMuteOnWindowLoseFocus`, `AudioFmodLiveUpdate`, `AudioFmodEnableDebugLogging`, plus rally toggles (`rallyAudioPacenotes`, `rallyPreCountdownAudio`).【F:docs/beamng-api/raw/api_dump_0.38.json†L15692-L15726】

Deprecated audio settings (from `core_settings_settings.impl.deprecated`):
- `AudioAmbienceVol`, `AudioEffectsVol`, `AudioInterfaceVol`, `AudioMaxChannels`, `AudioMaxVoices`, `AudioMaximumVoices`, `AudioOutputModes`.【F:docs/beamng-api/raw/api_dump_0.38.json†L19167-L19224】

## Notes / gotchas
- The dump focuses on GE-level modules; vehicle-side SFX APIs (e.g., `obj:createSFXSource`, `obj:playSFX`, `obj:playSFXOnce`) are used by this mod via `queueLuaCommand` but are not listed in the global dump. Treat them as vehicle-context APIs and keep compatibility fallbacks when possible.【F:lua/ge/extensions/bolidesTheCut.lua†L668-L781】【F:lua/ge/extensions/events/BulletDamage.lua†L209-L220】

## Example usage patterns (mod-specific)
- Vehicle-side SFX sources for one-shot sounds: the mod uses `obj:createSFXSource` plus `obj:playSFX`/`obj:playSFXOnce` inside `queueLuaCommand` for version-tolerant playback in the main audio helper and in shot impact audio.【F:lua/ge/extensions/bolidesTheCut.lua†L668-L781】【F:lua/ge/extensions/events/BulletDamage.lua†L209-L220】
