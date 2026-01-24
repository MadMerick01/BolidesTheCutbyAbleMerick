# Virtual reality (OpenXR) topic

## Purpose
Document the VR-facing APIs visible in the 0.38 dump. The dump exposes a global `OpenXR` table, OpenXR-related settings under `core_settings_settings`, and virtual input helpers that are likely relevant for controller-style input emulation in VR contexts.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11051-L11065】【F:docs/beamng-api/raw/api_dump_0.38.txt†L41922-L41935】【F:docs/beamng-api/raw/api_dump_0.38.txt†L11813-L11824】

## VR entry points at a glance
- **Runtime control:** the global `OpenXR` table provides enable/toggle, recentering, quad composition controls, and pose helpers.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11051-L11063】
- **Settings surface:** many VR tuning knobs are exposed as `openXR*` settings inside `core_settings_settings` defaults/default values.【F:docs/beamng-api/raw/api_dump_0.38.txt†L41922-L41935】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42728-L42985】
- **Input integration:** `core_input_virtualInput` plus `getVirtualInputManager` appear to be the primary GE-side hooks for synthetic/virtualized input devices, which may be useful for VR controllers or UI interaction layers.【F:docs/beamng-api/raw/api_dump_0.38.txt†L94-L94】【F:docs/beamng-api/raw/api_dump_0.38.txt†L11813-L11824】

## Verified APIs (from dump)

### Global OpenXR table (runtime control)
Global table: `OpenXR`【F:docs/beamng-api/raw/api_dump_0.38.txt†L11051-L11055】

Functions:
- `OpenXR.getEnable(...)`
- `OpenXR.toggle(...)`
- `OpenXR.requestState(...)`
- `OpenXR.center(...)`
- `OpenXR.getCameraPosRotPredictedXYZXYZW(...)`
- `OpenXR.setGeluaCameraPosRot(...)`
- `OpenXR.setUseQuadComposition(...)`
- `OpenXR.getUseQuadComposition(...)`
- `OpenXR.generateUiCurvature(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L11052-L11063】

### OpenXR lifecycle/error hooks
The dump lists two global hooks that look like OpenXR lifecycle/error entry points:
- `openXRStateChanged(...)`
- `openXRErrorDetected(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L276-L276】【F:docs/beamng-api/raw/api_dump_0.38.txt†L397-L397】

### OpenXR-related settings fields (`core_settings_settings`)
The following VR-facing settings keys are present in the dump’s `defaultValues` for `core_settings_settings`:

**Rendering / composition / debug**
- `openXRresolutionScale: number`
- `openXRquadCompositionEnabled: boolean`
- `openXRdebugEnabled: boolean`
- `openXRimguiEnabled: boolean`
- `openXRapidumpEnabled: boolean`【F:docs/beamng-api/raw/api_dump_0.38.txt†L42730-L42730】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42818-L42818】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42814-L42814】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42950-L42950】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42828-L42828】

**UI presentation in VR**
- `openXRuiEnabled: boolean`
- `openXRuiMode: number`
- `openXRuiDepth: number`
- `openXRuiWidth: number`
- `openXRuiHeight: number`
- `openXRuiCurve: number`
- `openXRwindowViewMode: number`【F:docs/beamng-api/raw/api_dump_0.38.txt†L42874-L42875】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42965-L42965】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42728-L42728】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42801-L42801】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42875-L42875】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42879-L42879】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42933-L42933】

**Comfort / locomotion / pose tuning**
- `openXRsnapTurnDriver: boolean`
- `openXRsnapTurnUnicycle: boolean`
- `openXRsnapTurnUnicycleDegrees: number`
- `openXRhorizonLockDriver: boolean`
- `openXRfreeCenter: boolean`
- `openXRhandPoseDirectionDegrees: number`
- `openXRhandPoseMultiplier: number`
- `openXRuseControllers: boolean`【F:docs/beamng-api/raw/api_dump_0.38.txt†L42750-L42750】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42754-L42754】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42809-L42809】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42885-L42885】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42985-L42985】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42825-L42825】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42846-L42846】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42769-L42769】

### Virtual/VR-adjacent input surfaces
VR often needs synthetic device input. The following interfaces are present:
- `getVirtualInputManager(...)` (global helper).【F:docs/beamng-api/raw/api_dump_0.38.txt†L94-L94】
- `core_input_virtualInput.createDevice(...)`
- `core_input_virtualInput.emit(...)`
- `core_input_virtualInput.deleteDevice(...)`
- `core_input_virtualInput.getDeviceInfo(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L11813-L11819】
- A `VirtualInputManager` table exists but the dump does not enumerate rich methods on it here.【F:docs/beamng-api/raw/api_dump_0.38.txt†L41437-L41445】

## Notes / gotchas
- The dump confirms **what exists**, but does not document signatures or argument schemas. Treat all OpenXR calls as version-sensitive and prefer guarded calls (`if OpenXR and OpenXR.toggle then ... end`) when wiring gameplay features to VR state.【F:docs/beamng-api/raw/api_dump_0.38.txt†L11051-L11063】
- Two older-looking OpenXR settings are explicitly marked obsolete in the dump metadata:
  - `openXRdumpEnabled`
  - `openXRnearPlaneDist`【F:docs/beamng-api/raw/api_dump_0.38.txt†L42262-L42264】【F:docs/beamng-api/raw/api_dump_0.38.txt†L42307-L42309】
- The presence of `core/input/virtualInput` in the dump’s extension/module inventory suggests the virtual input system is backed by a concrete extension path, even though the API dump only surfaces the `core_input_virtualInput` table directly.【F:docs/beamng-api/raw/api_dump_0.38.txt†L48506-L48506】【F:docs/beamng-api/raw/api_dump_0.38.txt†L11813-L11819】
