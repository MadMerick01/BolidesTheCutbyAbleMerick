# UI: ImGui windows vs Beam message panels

## What our movable/collapsible panel is
Our mod panel is an **ImGui window** rendered via the `ui_imgui` API. In `bolidesTheCut.lua` we:
- gate rendering on `CFG.windowVisible`,
- set an initial size with `imgui.SetNextWindowSize(...)`, and
- open a standard ImGui window with `imgui.Begin(CFG.windowTitle, openPtr)`.

Because it is a normal ImGui window, it inherits ImGui's default behaviors: it can be dragged around by the title bar and collapsed unless we explicitly disable those features with flags.

## What Beam "message" panels are
The colored, fixed-position panels used by scenarios, challenges, career events, part notifications, etc. are driven by the **GUI hook + UI app container pipeline**, not ImGui windows.

From the API dump:
- `guihooks` exposes `trigger`, `triggerClient`, `message`, and related functions that push events into the UI layer.
- `ui_messagesTasksAppContainers` manages the visibility/lifecycle of the messages/tasks UI apps (`showApp`, `hideApp`, `setAppVisibility`, `toggleApp`, etc.).

These panels are rendered by the game's UI apps (CEF/Angular), so their placement and styling are controlled by those apps. That is why they appear fixed in specific screen regions with BeamNG's standard colored styles.

## The key difference (mental model)
- **ImGui window (our panel):** immediate-mode debug UI that lives in the render pass. It is interactive like a tool window (movable/collapsible) unless you opt out via flags.
- **Beam messages:** UI-app-driven HUD elements. You request them via `guihooks.*`, and the UI app decides where they go and how they look.

## Why this matters for mod design
If you want something:
- **movable/collapsible/tool-like** → build it with `ui_imgui`.
- **consistent with scenario/career messaging** → route it through `guihooks` and the messages/tasks app containers.
