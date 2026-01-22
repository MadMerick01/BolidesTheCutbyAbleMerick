# UI ImGui topic

## Purpose
Document the ImGui bindings exposed via `ui_imgui` for building mod UI. The dump lists the ImGui function surface plus helper types like `ImVec2`, `ImColorByRGB`, and pointer helpers used in UI state management.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8711-L8726】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8840-L8884】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8987-L8996】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9055-L9065】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9136-L9152】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9171-L9199】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9223-L9240】

## Common tasks
- Start/end a window with `Begin` / `End` and set its initial size via `SetNextWindowSize`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8958-L8960】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8874-L8876】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9171-L9172】
- Draw text and buttons with `Text`, `TextWrapped`, `Button`, and align with `SameLine`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8883-L8884】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9136-L9137】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9151-L9152】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9237-L9238】
- Configure styling with `PushStyleColor2` and `ImColorByRGB`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L9055-L9057】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9198-L9199】
- Use `ImVec2` for sizing (e.g., `Button` sizes) and `BoolPtr` for checkbox/window open state pointers.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8987-L8988】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9061-L9065】
- Adjust font scale per-window with `SetWindowFontScale` for emphasis headers.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8766-L8768】

## Verified APIs (from dump)
Core windowing:
- `Begin`, `End`, `SetNextWindowSize`, `SetNextWindowSizeConstraints`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8874-L8876】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8958-L8959】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8898-L8899】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9171-L9172】

Widgets and layout:
- `Text`, `TextWrapped`, `Button`, `Image`, `ImageButton`, `SameLine`, `Separator`, `Spacing`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8724-L8735】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8776-L8780】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8848-L8884】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9136-L9152】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9223-L9247】

Helpers / types:
- `ImVec2`, `ImColorByRGB`, `BoolPtr`, `ImColor_HSV`, `SetWindowFontScale`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L8766-L8768】【F:docs/beamng-api/raw/api_dump_0.38.txt†L8987-L8988】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9055-L9065】【F:docs/beamng-api/raw/api_dump_0.38.txt†L9211-L9213】

## Notes / gotchas
- ImGui bindings are extensive; prefer a curated subset used by this mod (window setup, layout, buttons, text, color helpers). Keep UI calls inside `onDrawDebug` as the mod already does to avoid unsafe draw calls outside the render pass.【F:lua/ge/extensions/bolidesTheCut.lua†L955-L1038】
- Use `BoolPtr` for toggling the main window visibility in a stable, mutation-safe way (as in the main HUD).【F:docs/beamng-api/raw/api_dump_0.38.txt†L9061-L9065】【F:lua/ge/extensions/bolidesTheCut.lua†L998-L1003】

## Example usage patterns (mod-specific)
- The HUD uses `SetNextWindowSize`, `Begin`, `TextWrapped`, `Button`, `SameLine`, and `ImColorByRGB` to render the main control panel with dynamic tinting based on threat state.【F:lua/ge/extensions/bolidesTheCut.lua†L958-L1038】
