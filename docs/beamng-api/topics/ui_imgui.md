# Ui imgui topic

## Purpose
`ui_imgui` exposes BeamNG’s Lua bindings for Dear ImGui. It provides immediate-mode UI building blocks (windows, widgets, layout helpers, input state, draw lists, and styling) plus ImGui constants for flags/enum values. Use it for in-game HUD panels, debug tooling, or overlays that need dynamic, frame-by-frame updates.

## Common tasks
- **Create a window:** `SetNextWindowSize` + `Begin`/`End`, then fill with text and buttons.
- **Layout controls:** `SameLine`, `Spacing`, `Separator`, `Indent`/`Unindent`, `PushTextWrapPos`/`PopTextWrapPos`.
- **UI inputs:** `InputText*`, `InputInt*`, `InputFloat*`, `Slider*`, `Drag*`, `Checkbox`, `RadioButton*`.
- **Conditional UI blocks:** `BeginDisabled`/`EndDisabled`, `CollapsingHeader*`, `TreeNode*`.
- **Tables and tabs:** `BeginTable`/`EndTable`, `BeginTabBar`/`EndTabBar` for structured layouts.
- **Overlays/draw lists:** `GetForegroundDrawList2` + `ImDrawList_*` primitives for crosshairs or debug visuals.
- **Styling:** `PushStyleColor*`, `PushStyleVar*`, `SetWindowFontScale`, `ImColorByRGB`.
- **Input state:** `GetIO`, `IsMouseClicked`, `IsKeyDown` for interaction logic.

## Verified APIs (from dump)
### Window + layout
- Window lifecycle: `Begin`, `End`, `BeginChild1`, `BeginChild2`, `EndChild`, `BeginChildFrame`, `EndChildFrame`.
- Window setup: `SetNextWindowSize`, `SetNextWindowPos`, `SetNextWindowCollapsed`, `SetNextWindowFocus`, `SetNextWindowBgAlpha`, `SetNextWindowViewport`, `SetNextWindowDockID`, `SetNextWindowSizeConstraints`, `SetNextWindowClass`.
- Window metrics/state: `GetWindowPos`, `GetWindowSize`, `GetWindowWidth`, `GetWindowHeight`, `GetWindowDockID`, `IsWindowFocused`, `IsWindowHovered`, `IsWindowAppearing`, `IsWindowCollapsed`, `IsWindowDocked`.
- Content/scroll: `GetContentRegionAvail`, `GetContentRegionAvailWidth`, `GetWindowContentRegionMin`, `GetWindowContentRegionMax`, `GetWindowContentRegionWidth`, `GetScrollX`, `GetScrollY`, `GetScrollMaxX`, `GetScrollMaxY`, `SetScrollX`, `SetScrollY`, `SetScrollHereX`, `SetScrollHereY`.
- Cursor/layout helpers: `SetCursorPos`, `SetCursorPosX`, `SetCursorPosY`, `SetCursorScreenPos`, `GetCursorPos`, `GetCursorPosX`, `GetCursorPosY`, `GetCursorScreenPos`, `AlignTextToFramePadding`, `SameLine`, `Spacing`, `NewLine`, `Separator`, `SeparatorText`, `Indent`, `Unindent`, `Dummy`, `BeginGroup`, `EndGroup`, `BeginDisabled`, `EndDisabled`, `PushItemWidth`, `PopItemWidth`, `SetNextItemWidth`, `PushTextWrapPos`, `PopTextWrapPos`, `Columns`, `NextColumn`, `GetColumnIndex`, `GetColumnsCount`, `GetColumnWidth`, `SetColumnWidth`, `GetColumnOffset`, `SetColumnOffset`.
- Sizing/metrics: `GetFrameHeight`, `GetFrameHeightWithSpacing`, `GetTextLineHeight`, `GetTextLineHeightWithSpacing`, `CalcTextSize`, `CalcItemWidth`.

### Widgets + inputs
- Text: `Text`, `TextWrapped`, `TextColored`, `TextDisabled`, `TextUnformatted`.
- Buttons/selection: `Button`, `SmallButton`, `InvisibleButton`, `ArrowButton`, `Selectable1`, `Selectable2`, `RadioButton1`, `RadioButton2`.
- Lists and combo boxes: `BeginCombo`, `EndCombo`, `Combo1`, `Combo2`, `Combo3`, `BeginListBox`, `EndListBox`, `ListBox1`, `ListBox2`.
- Inputs: `InputText`, `InputTextWithHint`, `InputTextMultiline`, `InputInt`, `InputInt2`, `InputInt3`, `InputInt4`, `InputFloat`, `InputFloat2`, `InputFloat3`, `InputFloat4`, `InputDouble`.
- Drag/slider controls: `DragFloat`, `DragFloat2`, `DragFloat3`, `DragFloat4`, `DragFloatRange2`, `DragInt`, `DragInt2`, `DragInt3`, `DragInt4`, `DragIntRange2`, `SliderFloat`, `SliderFloat2`, `SliderFloat3`, `SliderFloat4`, `SliderInt`, `SliderInt2`, `SliderInt3`, `SliderInt4`, `SliderAngle`.
- Checkbox/toggles: `Checkbox`, `CheckboxFlags1`, `CheckboxFlags2`, `ProgressBar`.
- Trees: `TreeNode1`, `TreeNode2`, `TreeNode3`, `TreeNodeEx1`, `TreeNodeEx2`, `TreeNodeEx3`, `TreePop`, `TreePush1`, `TreePush2`, `CollapsingHeader1`, `CollapsingHeader2`.
- Images: `Image`, `ImageButton`.

### Tables + tabs
- Tables: `BeginTable`, `EndTable`, `TableSetupColumn`, `TableHeadersRow`, `TableHeader`, `TableNextRow`, `TableNextColumn`, `TableSetBgColor`, `TableSetupScrollFreeze`, `TableSetColumnIndex`, `TableSetColumnEnabled`, `TableGetColumnIndex`, `TableGetColumnCount`, `TableGetColumnName`, `TableGetColumnFlags`, `TableGetRowIndex`, `TableGetSortSpecs`, `TableSetSortSpecsDirty`, `TableToArrayFloat`.
- Tabs: `BeginTabBar`, `EndTabBar`, `BeginTabItem`, `EndTabItem`, `TabItemButton`, `SetTabItemClosed`.

### Menus, popups, tooltips
- Menus: `BeginMainMenuBar`, `EndMainMenuBar`, `BeginMenuBar`, `EndMenuBar`, `BeginMenu`, `EndMenu`, `MenuItem1`, `MenuItem2`.
- Popups: `OpenPopup`, `OpenPopupOnItemClick`, `BeginPopup`, `BeginPopupModal`, `BeginPopupContextItem`, `BeginPopupContextVoid`, `BeginPopupContextWindow`, `EndPopup`, `IsPopupOpen`, `CloseCurrentPopup`.
- Tooltips: `BeginTooltip`, `EndTooltip`, `BeginItemTooltip`, `SetItemTooltip`.

### Drag & drop
- `BeginDragDropSource`, `EndDragDropSource`, `BeginDragDropTarget`, `EndDragDropTarget`, `SetDragDropPayload`, `AcceptDragDropPayload`, `GetDragDropPayload`.
- Payload helpers: `ImGuiPayload`, `ImGuiPayloadPtr`, `ImGuiPayload_Clear`, `ImGuiPayload_IsDataType`, `ImGuiPayload_IsDelivery`, `ImGuiPayload_IsPreview`.

### Styling, fonts, colors
- Style stacks: `PushStyleColor1`, `PushStyleColor2`, `PopStyleColor`, `PushStyleVar1`, `PushStyleVar2`, `PopStyleVar`.
- Global style: `GetStyle`, `StyleColorsDark`, `StyleColorsLight`, `StyleColorsClassic`.
- Fonts: `PushFont`, `PushFont2`, `PushFont3`, `PopFont`, `SetDefaultFont`, `GetFont`, `GetFontSize`, `GetFontTexUvWhitePixel`, `SetWindowFontScale`.
- Colors: `ImColor`, `ImColorPtr`, `ImColorByRGB`, `ImColor_HSV`, `ImColor_SetHSV`, `ColorButton`, `ColorEdit3`, `ColorEdit4`, `ColorPicker3`, `ColorPicker4`, `ColorConvertFloat4ToU32`, `ColorConvertU32ToFloat4`, `ColorConvertHSVtoRGB`, `ColorConvertRGBtoHSV`, `GetColorU321`, `GetColorU322`, `GetColorU323`, `GetStyleColorVec4`, `SetColorEditOptions`.

### Drawing + draw lists
- Viewport access: `GetMainViewport`.
- Draw list access: `GetWindowDrawList`, `GetForegroundDrawList1`, `GetForegroundDrawList2`, `GetBackgroundDrawList1`, `GetBackgroundDrawList2`.
- Primitives: `ImDrawList_AddLine`, `ImDrawList_AddRect`, `ImDrawList_AddRectFilled`, `ImDrawList_AddRectFilledMultiColor`, `ImDrawList_AddCircle`, `ImDrawList_AddCircleFilled`, `ImDrawList_AddTriangle`, `ImDrawList_AddTriangleFilled`, `ImDrawList_AddQuad`, `ImDrawList_AddQuadFilled`, `ImDrawList_AddBezierCubic`, `ImDrawList_AddBezierQuadratic`, `ImDrawList_AddText1`, `ImDrawList_AddText2`, `ImDrawList_AddImage`, `ImDrawList_AddImageQuad`, `ImDrawList_AddImageRounded`, `ImDrawList_AddPolyline`, `ImDrawList_AddConvexPolyFilled`.
- Paths/clip/texture: `ImDrawList_PathClear`, `ImDrawList_PathLineTo`, `ImDrawList_PathLineToMergeDuplicate`, `ImDrawList_PathRect`, `ImDrawList_PathArcTo`, `ImDrawList_PathArcToFast`, `ImDrawList_PathBezierCubicCurveTo`, `ImDrawList_PathBezierQuadraticCurveTo`, `ImDrawList_PathFillConvex`, `ImDrawList_PathStroke`, `ImDrawList_PushClipRect`, `ImDrawList_PopClipRect`, `ImDrawList_PushClipRectFullScreen`, `ImDrawList_PushTextureID`, `ImDrawList_PopTextureID`.
- Channels/prim: `ImDrawList_ChannelsSplit`, `ImDrawList_ChannelsSetCurrent`, `ImDrawList_ChannelsMerge`, `ImDrawList_PrimReserve`, `ImDrawList_PrimUnreserve`, `ImDrawList_PrimWriteVtx`, `ImDrawList_PrimWriteIdx`.
- Texture handling: `ImTextureHandler`, `ImTextureHandlerIsCached`.

### Input/state + IO helpers
- IO/state: `GetIO`, `IsMouseClicked`, `IsMouseDoubleClicked`, `IsMouseDown`, `IsMouseReleased`, `IsMouseDragging`, `IsMouseHoveringRect`, `IsMousePosValid`, `GetMousePos`, `GetMousePosOnOpeningCurrentPopup`, `GetMouseDragDelta`, `GetMouseClickedCount`, `SetMouseCursor`.
- Keyboard: `IsKeyDown`, `IsKeyPressed`, `IsKeyReleased`, `SetKeyboardFocusHere`.
- Item state: `IsAnyItemActive`, `IsAnyItemFocused`, `IsAnyItemHovered`, `IsItemHovered`, `IsItemActive`, `IsItemClicked`, `IsItemEdited`, `IsItemActivated`, `IsItemDeactivated`, `IsItemDeactivatedAfterEdit`, `IsItemVisible`, `IsItemToggledOpen`.
- IO injection: `ImGuiIO_AddFocusEvent`, `ImGuiIO_AddInputCharacter`, `ImGuiIO_AddInputCharacterUTF16`, `ImGuiIO_AddInputCharactersUTF8`, `ImGuiIO_AddKeyAnalogEvent`, `ImGuiIO_AddKeyEvent`, `ImGuiIO_AddMouseButtonEvent`, `ImGuiIO_AddMousePosEvent`, `ImGuiIO_AddMouseSourceEvent`, `ImGuiIO_AddMouseViewportEvent`, `ImGuiIO_AddMouseWheelEvent`, `ImGuiIO_ClearEventsQueue`, `ImGuiIO_ClearInputKeys`, `ImGuiIO_FontGlobalScale`, `ImGuiIO_SetAppAcceptingEvents`, `ImGuiIO_SetKeyEventNativeData`.

### Types + pointer utilities
- Basic types/structs: `ImVec2`, `ImVec4`, `ImVec2Ptr`, `ImVec4Ptr`, `ImVecPtrDeref`, `ImGuiIO`, `ImGuiIOPtr`, `ImGuiStyle`, `ImGuiStylePtr`, `ImGuiViewport`, `ImGuiViewportPtr`, `ImGuiPlatformIO`, `ImGuiPlatformIOPtr`, `ImGuiPlatformMonitor`, `ImGuiPlatformMonitorPtr`, `ImGuiPlatformImeData`, `ImGuiPlatformImeDataPtr`, `ImGuiWindowClass`, `ImGuiWindowClassPtr`, `ImGuiTableSortSpecs`, `ImGuiTableSortSpecsPtr`, `ImGuiTableColumnSortSpecs`, `ImGuiTableColumnSortSpecsPtr`, `ImGuiListClipper`, `ImGuiListClipperPtr`, `ImGuiTextFilter`, `ImGuiTextFilterPtr`.
- Helper/pointer wrappers: `BoolPtr`, `BoolTrue`, `BoolFalse`, `IntPtr`, `FloatPtr`, `DoublePtr`, `ArrayCharPtrByTbl`, `GetLengthArrayCharPtr`.
- Data helpers: `ImGuiListClipper_Begin`, `ImGuiListClipper_End`, `ImGuiListClipper_IncludeRangeByIndices`, `ImGuiListClipper_Step`, `ImGuiStorage_*`, `ImGuiTextFilter_Build`, `ImGuiTextFilter_Clear`, `ImGuiTextFilter_Draw`, `ImGuiTextFilter_IsActive`, `ImGuiTextFilter_PassFilter`.

### Debug helpers
- `ShowDemoWindow`, `ShowMetricsWindow`, `ShowStyleEditor`, `ShowStyleSelector`, `ShowFontSelector`, `ShowUserGuide`, `ShowAboutWindow`, `ShowDebugLogWindow`, `ShowStackToolWindow`.

### Constants / enums (field prefixes)
`ui_imgui` exposes ImGui constants as numeric fields. Useful groups include:
- `Col_*` (e.g., `Col_Text`, `Col_WindowBg`)
- `Cond_*`
- `WindowFlags_*`
- `TableFlags_*`, `TableColumnFlags_*`, `TableRowFlags_*`
- `TreeNodeFlags_*`
- `SelectableFlags_*`
- `InputTextFlags_*`
- `HoveredFlags_*`, `FocusedFlags_*`
- `ComboFlags_*`, `PopupFlags_*`
- `TabBarFlags_*`, `TabItemFlags_*`
- `DockNodeFlags_*`
- `DragDropFlags_*`
- `SliderFlags_*`
- `ColorEditFlags_*`
- `ConfigFlags_*`, `BackendFlags_*`
- `Dir_*`, `Key_*`, `MouseButton_*`, `MouseCursor_*`, `NavInput_*`
- `DataType_*`, `ButtonFlags_*`, `SortDirection_*`, `StyleVar_*`

## Notes / gotchas
- Many APIs come in numbered variants (e.g., `BeginChild1` vs. `BeginChild2`, `Selectable1`/`Selectable2`, `Combo1`/`Combo2`/`Combo3`). Pick the signature that matches the parameters you want to pass.
- Pair every `Begin*` with the matching `End*` call in the same frame to avoid UI stack issues.
- Style and item stacks (`PushStyleColor*`, `PushStyleVar*`, `PushItemWidth`) must always be balanced with the corresponding `Pop*` calls.
- `SetNextWindow*` calls affect the next `Begin` only; call them immediately before `Begin`.
- Use pointer helpers (`BoolPtr`, `IntPtr`, `FloatPtr`) when an API expects a mutable pointer (e.g., window open/close flags).

## Example usage patterns (mod-specific)
- **Window setup + layout:** We set an initial size with `SetNextWindowSize`, then open a window with `Begin`/`End`, using `PushStyleColor2`, `Text`, `TextWrapped`, `Button`, and layout helpers (`SameLine`, `Spacing`, `Separator`) for the main HUD panel.
- **Overlay drawing:** For the first-person crosshair, we grab the viewport and draw list (`GetMainViewport`, `GetForegroundDrawList2`) and then draw lines with `ImDrawList_AddLine` using color values from `GetColorU321`.
- **Simple status panel:** The money HUD uses `Text` to render a compact readout inside the UI draw callback.
