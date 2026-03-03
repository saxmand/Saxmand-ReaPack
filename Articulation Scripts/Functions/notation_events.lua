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

    reaper.ImGui_SeparatorText(ctx, "Overlays")
    if reaper.ImGui_Checkbox(ctx, "Draw delay lines on Piano Roll", settings.draw_delay_lines_on_piano_roll) then
        settings.draw_delay_lines_on_piano_roll = not settings.draw_delay_lines_on_piano_roll
        saveSettings()
    end
    setToolTipFunc("This will draw custom lines showing the delay amount of a note, if the articulation attached uses a delay.")
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
    reaper.ImGui_SeparatorText(ctx, "Set all Articulation Scripts")
    
    local sliderName = "Trigger articulation on every note" --"Negative delay when not enough time"
    local firstSelectedTrackValue = change_articulation.findParamWithNameValue(track, fxNumber, sliderName)
    reaper.ImGui_TextColored(ctx, 0x777777FF, sliderName)
    local selectionTypes = {"Off", "On"}
    for i, s in ipairs(selectionTypes) do
        if reaper.ImGui_RadioButton(ctx, s .. "##"..sliderName, firstSelectedTrackValue == i - 1) then
            change_articulation.setSliderOnArticulationScripts_allTracks(sliderName, i - 1)
        end
        setToolTipFunc("You can choose to trigger articulation on every note input. Might be useful for some articulations.")
        if i < #selectionTypes then reaper.ImGui_SameLine(ctx) end                                
    end 

    local sliderName = "Force Delay" --"Negative delay when not enough time"
    local firstSelectedTrackValue = change_articulation.findParamWithNameValue(track, fxNumber, sliderName)
    reaper.ImGui_TextColored(ctx, 0x777777FF, sliderName)
    local selectionTypes = {"Off", "On"}
    for i, s in ipairs(selectionTypes) do
        if reaper.ImGui_RadioButton(ctx, s .. "##"..sliderName, firstSelectedTrackValue == i - 1) then
            change_articulation.setSliderOnArticulationScripts_allTracks(sliderName, i - 1)
        end
        setToolTipFunc("You can force the delay on all plugins")
        if i < #selectionTypes then reaper.ImGui_SameLine(ctx) end                                
    end 

    local sliderName = "enough time" --"Negative delay when not enough time"
    local firstSelectedTrackValue = change_articulation.findParamWithNameValue(track, fxNumber, sliderName)
    reaper.ImGui_TextColored(ctx, 0x777777FF, "Negative delay when start playing too close to note")
    local selectionTypes = {"Full negative delay", "Use playstart to note, amount", "Do not delay"}
    for i, s in ipairs(selectionTypes) do
        if reaper.ImGui_RadioButton(ctx, s, firstSelectedTrackValue == i - 1) then
            change_articulation.setSliderOnArticulationScripts_allTracks(sliderName, i - 1)
        end
        setToolTipFunc("If your articulation is using Negative Delay, and you play closer to the note than the negative delay, choose what amount should delay.\nThis option is only relevant if you script contains Delay. This also affects rendering if there's no 'pre-roll' before notes with negative delay.\nThis will set all Articulation scripts")
        if i < #selectionTypes then reaper.ImGui_SameLine(ctx) end                                
    end 

    reaper.ImGui_NewLine(ctx)

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