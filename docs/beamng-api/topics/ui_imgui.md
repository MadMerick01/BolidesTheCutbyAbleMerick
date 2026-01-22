# Ui imgui topic

## Purpose
TODO: describe what this category covers.

## Common tasks
- TODO: list common tasks.

## Verified APIs (from dump)
- `ImTextureHandler` (callable, returns an `ImTextureID`)
- `ImTextureHandlerIsCached`
- `Image`
- `GetContentRegionAvail`
- `ImVec2`

## Notes / gotchas
- Prefer `ImTextureHandler(path)` for loading textures in ImGui. It is present in the 0.38 dump and works with `Image` calls. `LoadTexture` is not listed in the dump, so treat it as a legacy fallback if it exists at runtime.

## Example usage patterns (mod-specific)
- Banner loading flow (Bolides GUI):
  - Call `imgui.ImTextureHandler("/art/ui/bolides_the_cut/bolides_the_cut_banner.png")`.
  - Cache the returned `ImTextureID` and draw it via `imgui.Image(tex, imgui.ImVec2(width, height))`.
