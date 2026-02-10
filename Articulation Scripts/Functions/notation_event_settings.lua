-- @noindex

local export = {}

function export.notation_event_settings()
    reaper.ImGui_SeparatorText(ctx, "Text events")
    if reaper.ImGui_Checkbox(ctx, "Mirror notation articulations to text events", settings.mirror_notation_articulations_to_text_events) then
        settings.mirror_notation_articulations_to_text_events = not settings.mirror_notation_articulations_to_text_events
        saveSettings()
    end

    if reaper.ImGui_Checkbox(ctx, "Mirror notation dynamics to text events", settings.mirror_notation_dynamics_to_text_events) then
        settings.mirror_notation_dynamics_to_text_events = not settings.mirror_notation_dynamics_to_text_events
        saveSettings()
    end
end

return export