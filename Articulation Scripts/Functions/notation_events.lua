-- @noindex

local export = {}

local function notation_events_settings()
    reaper.ImGui_SeparatorText(ctx, "Assigning articulations")
    if reaper.ImGui_Checkbox(ctx, "Add current articulation to new notes", settings.add_current_articulation_to_new_notes) then
        settings.add_current_articulation_to_new_notes = not settings.add_current_articulation_to_new_notes
        saveSettings()
    end
    setToolTipFunc("This will automatically add notation events to notes that are being added.\nThis only affects the midi editor.")

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



function export.options()
    if reaper.ImGui_BeginMenu(ctx, "Options") then
        menuOpen = true
        local midi_editor = reaper.MIDIEditor_GetActive()
        
        if midi_editor then
            if reaper.ImGui_BeginMenu(ctx, "View") then
                
                local show = reaper.GetToggleCommandStateEx(32060, 42101) == 1
                if reaper.ImGui_Checkbox(ctx, "Show notation text on notes", show) then
                    reaper.MIDIEditor_OnCommand(midi_editor, 42101) --View: Show notation text on notes 
                end
                
                local show = reaper.GetToggleCommandStateEx(32060, 40040) == 1
                if reaper.ImGui_Checkbox(ctx, "Show velocity handles on notes", show) then
                    reaper.MIDIEditor_OnCommand(midi_editor, 40040) --View: Show velocity handles on notes
                end
                
                local show = reaper.GetToggleCommandStateEx(32060, 40045) == 1
                if reaper.ImGui_Checkbox(ctx, "Show note names on notes", show) then
                    reaper.MIDIEditor_OnCommand(midi_editor, 40045) --View: Show note names on notes
                end
                
                
                local show = reaper.GetToggleCommandStateEx(32060, 40632) == 1
                if reaper.ImGui_Checkbox(ctx, "Show velocity numbers on notes", show) then
                    reaper.MIDIEditor_OnCommand(midi_editor, 40632) --View: Show velocity numbers on notes
                end
                
                reaper.ImGui_Separator(ctx)
                
                
                local show = reaper.GetToggleCommandStateEx(32060, 42472) == 1
                if reaper.ImGui_Checkbox(ctx, "Only show CCs on channels of selected notes (MPE mode)", show) then
                    reaper.MIDIEditor_OnCommand(midi_editor, 42472) --Options: only show CCs on channels of selected notes (MPE mode) 
                end
            
            
                reaper.ImGui_EndMenu(ctx)
            end
        
        
            if reaper.ImGui_BeginMenu(ctx, "Notation") then   
                if reaper.ImGui_Selectable(ctx, "Remove all notation for selected notes", false) then
                    reaper.MIDIEditor_OnCommand(midi_editor, 41298) --Notation: Remove all notation for selected notes 
                end
                
                reaper.ImGui_EndMenu(ctx)
            end
        else
            reaper.ImGui_Text(ctx, "Open midi editor to see midi editor options")
        end


        notation_events_settings()
        
        reaper.ImGui_EndMenu(ctx)
    end
end

function export.others()
    reaper.ImGui_SeparatorText(ctx, "Others")
    if reaper.ImGui_Checkbox(ctx, "Show tooltip for articulation buttons", settings.show_tooltip_for_articaultion_buttons) then
        settings.show_tooltip_for_articaultion_buttons = not settings.show_tooltip_for_articaultion_buttons
        saveSettings()
    end
    setToolTipFunc("Disable to not see tooltip when hovering an articulation buttons")
end

function export.buttons_tooltip()
    if settings.show_tooltip_for_articaultion_buttons then 
        reaper.ImGui_PushFont(ctx, font, 12)
        setToolTipFunc("- Hold Super to set all selected articulations to the same\n- Hold Shift to select articulations containing name exclusively.\n- Hold Shift + Ctrl to add articulations containing name to selection")
        reaper.ImGui_PopFont(ctx)
    end
end

return export