-- @noindex

local export = {}

function export.notation_event_settings()
    reaper.ImGui_SeparatorText(ctx, "Text events")
    if reaper.ImGui_Checkbox(ctx, "Mirror notation articulations to text events", settings.mirror_notation_articulations_to_text_events) then
        settings.mirror_notation_articulations_to_text_events = not settings.mirror_notation_articulations_to_text_events
        saveSettings()
    end
    setToolTipFunc("This will generate text events that shows in their own lane, whenever there's a new notation articulation (so you won't see repeated ones).\nThe text events can also be shown on the media item in the main window and offers a simpler overview")

    if reaper.ImGui_Checkbox(ctx, "Mirror notation dynamics to text events", settings.mirror_notation_dynamics_to_text_events) then
        settings.mirror_notation_dynamics_to_text_events = not settings.mirror_notation_dynamics_to_text_events
        saveSettings()
    end
    setToolTipFunc("This will generate text events that shows in their own lane, whenever there's a new notation dynamic (so you won't see repeated ones).\nThe text events can also be shown on the media item in the main window and offers a simpler overview")
end

return export