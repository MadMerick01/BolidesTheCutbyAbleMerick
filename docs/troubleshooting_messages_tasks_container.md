# Troubleshooting: repeating "container not found" console spam

## Symptom
- Console repeatedly prints container lookup errors (for example, around `messagesTasks`) while gameplay continues normally.

## Root cause pattern
This usually happens when the HUD app/container API is called with container-specific arguments in a state where:
- the messages/tasks container is not mounted yet, or
- the engine API signature differs and the container-name overload is unavailable.

Even with `pcall` in Lua, BeamNG can still emit internal log noise if the underlying lookup fails repeatedly.

## Fix pattern used in this mod
In `lua/ge/extensions/bolidesTheCut.lua`:
1. **Retry backoff** for container checks (`HUD_TRIAL.containerRetryAt`, `containerRetryBackoff`) so we do not hammer failing lookups.
2. **Fallback API calls** without container name when container-arg calls fail:
   - `getMessagesTasksAppContainerMounted(container)` -> fallback `getMessagesTasksAppContainerMounted()`
   - `getAvailableApps(container)` -> fallback `getAvailableApps()`
   - `getAppVisibility(app, container)` -> fallback `getAppVisibility(app)`
   - `showApp(app, container)` -> fallback `showApp(app)`
   - `setAppVisibility(app, true, container)` -> fallback `setAppVisibility(app, true)`
3. **Skip visibility forcing** while in backoff window.

## Quick checklist if this reappears
- Confirm the HUD app still targets `types: ["messagesTasks"]`.
- Confirm the container is mounted before trying to show/visibility-toggle apps.
- Keep the fallback/no-container call path in place for API variance.
- Keep backoff active to prevent high-frequency log spam.
