-- @noindex

local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")

-- Load the reaper sections id number
local reaper_sections = dofile(scriptPath .. "/Helpers/reaper_sections.lua")

local export = {}

function export.findArticulationScript(track)
    if track then 
        local fxAmount = reaper.TrackFX_GetCount(track)
        for i = 0, fxAmount - 1 do
            local _, fxName = reaper.TrackFX_GetFXName(track, i)
            if fxName:find(" (Articulation Script)", 1, true) then
                local name = fxName:gsub(" %(Articulation Script%)", ""):gsub("JS: ", "")
                local fxNumber = i
                return fxNumber, name
            end
        end
    else 
        return false
    end
end

function isMainWindowInFocus()
    if keyboard_trigger_is_focusing_main then 
        return true
    end
    -- Get the main REAPER window
    local main_hwnd = reaper.GetMainHwnd()
    
    -- Get the currently focused window
    local focused_hwnd = reaper.JS_Window_GetForeground()
    -- Check if the focused window is the main window
    if focused_hwnd == main_hwnd then
        return true
    end
    
    -- Check if the focused window is a child of the main window
    --local parent_hwnd = focused_hwnd
    --while parent_hwnd do
    --    parent_hwnd = reaper.JS_Window_GetParent(parent_hwnd)
       -- if parent_hwnd == main_hwnd then
       --     return true
       -- end
    --end
    
    return false
end

function export.trackDependingOnSelectionSimple()
    local midiEditor = reaper.MIDIEditor_GetActive()
    local forgroundHwnd = reaper.JS_Window_GetForeground()
    if forgroundHwnd == midiEditor then 
        local selectedMediaItemsCount = reaper.CountSelectedMediaItems(0)
        if selectedMediaItemsCount > 0 then
            item = reaper.GetSelectedMediaItem(0, 0)
            take = reaper.GetActiveTake(item)
            track = reaper.GetMediaItemTrack(item)
        else
            take = reaper.MIDIEditor_GetTake(midiEditor)            
            track = reaper.GetMediaItemTake_Track(take)
        end
    else

    end
end

function export.trackDependingOnSelection()
    local midiEditor = reaper.MIDIEditor_GetActive()
    local midiEditor_is_docked, midiEditor_parent, midiEditor_parent_title, midiEditor_is_focused
    if midiEditor then
        midiEditor_parent = reaper.JS_Window_GetParent(midiEditor)
        midiEditor_parent_title = reaper.JS_Window_GetTitle(midiEditor_parent)
        midiEditor_is_docked = midiEditor_parent_title == "REAPER_dock"
    end
    local track, section_id, fxName, fxNumber, item, take, trackIsFocused
    local isRecording = reaper.GetPlayState() & 4 == 4 
    local firstSelectedTrack = reaper.GetSelectedTrack(0, 0)

    local focusIsOn, focusHwnd
    local forgroundHwnd = reaper.JS_Window_GetForeground()
    --local forgroundHwnd_parent = reaper.JS_Window_GetParent(forgroundHwnd)
    --local forgroundHwnd_parent_title = reaper.JS_Window_GetTitle(forgroundHwnd_parent)
    local focusHwnd = reaper.JS_Window_GetFocus()
    local focusHwnd_parent = reaper.JS_Window_GetParent(focusHwnd)
    local focusHwnd_parent_title = reaper.JS_Window_GetTitle(focusHwnd_parent)
    
    -- ensure we do not change focus when we focus our list overview 
    if focusHwnd_parent_title == "Articulation_Scripts" then 

    else
        if midiEditor_is_docked and focusHwnd_parent_title:match("MIDI take") ~= nil then 
            midiEditor_is_focused = true
        end
        
        local mainHwnd = reaper.GetMainHwnd()
        if not midiEditor_is_focused and (forgroundHwnd == mainHwnd) then-- or focusHwnd_parent == mainHwnd) then
            focusIsOn = "take"
            focusHwnd = focusHwnd
        elseif midiEditor and (forgroundHwnd == midiEditor or midiEditor_is_focused) then 
            focusIsOn = "editor"
            if midiEditor_is_focused then             
                focusHwnd = focusHwnd
            else
                focusHwnd = midiEditor
            end
        end

        if isRecording then
            if firstSelectedTrack then 
                track = firstSelectedTrack
                section_id = reaper_sections["Main"] 
                focusIsOn = "track"
            end
        else
            if midiEditor and (forgroundHwnd == midiEditor or midiEditor_is_focused) then
                take = reaper.MIDIEditor_GetTake(midiEditor)
                if take then 
                    item = reaper.GetMediaItemTake_Item(take)
                    track = reaper.GetMediaItemTrack(item)
                    section_id = reaper_sections["MIDI Editor"]

                    if settings.add_current_articulation_to_new_notes and isMouseReleased then 
                        local _, numNotes = reaper.MIDI_CountEvts(take)
                        if last_numNotes and numNotes - last_numNotes == 1 then
                            changeArticulation(nil, nil, focusIsOn, true)
                        elseif last_numNotes and last_numNotes > numNotes then 
                            mirror_notation_to_unique_text_events(take)
                        end
                        last_numNotes = numNotes
                    end
                end
            end
                -- inline editor = 32061
            if not section_id and forgroundHwnd == mainHwnd then
                local selectedMediaItemsCount = reaper.CountSelectedMediaItems(0)
                if selectedMediaItemsCount > 0 then
                    item = reaper.GetSelectedMediaItem(0, 0)
                    take = reaper.GetActiveTake(item)
                    track = reaper.GetMediaItemTrack(item)
                end
                section_id = reaper_sections["Main"]
                
                
                local GetCursorContext = reaper.GetCursorContext()
                if GetCursorContext == -1 then 
                    GetCursorContext = last_GetCursorContext
                else
                    last_GetCursorContext = GetCursorContext
                end

                local trackIsFocused = GetCursorContext == 0
                
                if (not track or trackIsFocused) and firstSelectedTrack then 
                    track = firstSelectedTrack
                    take = nil
                    trackIsFocused = true    
                    focusIsOn = "track"
                end
                
                --[[
                if cursorContext ~= last_cursorContext then
                    last_cursorContext = cursorContext
                    if cursorContext == 0 then 
                        last_firstSelectedTrack = nil
                    elseif cursorContext == 1 then
                        last_take_selection = nil                    
                    end
                end
                    -- if last defer track was focused, we stay here, by keep reseting last selected track
                    if trackIsFocused then 
                        -- unless we have a different take than last time
                        if last_take_selection ~= take then                    
                            last_take_selection = take
                            if take then 
                                takeIsFocused = true
                                trackIsFocused = false
                            end
                        else
                            if not takeIsFocused then 
                                last_firstSelectedTrack = nil
                            end
                        end
                    end
                    
                    if firstSelectedTrack and last_firstSelectedTrack ~= firstSelectedTrack then
                        track = firstSelectedTrack
                        last_firstSelectedTrack = firstSelectedTrack
                        trackIsFocused = true
                        takeIsFocused = false
                    end
                    ]]
            end
        end
    end

    if focusIsOn then 
        last_focusIsOn = focusIsOn
        last_focusHwnd = focusHwnd
        last_track = track
        last_section_id = section_id
        last_item = item
        last_take = take
        last_midiEditor = midiEditor
    elseif last_focusIsOn then 
        focusIsOn = last_focusIsOn
        focusHwnd = last_focusHwnd
        track = last_track
        section_id = last_section_id
        item = last_item
        take = last_take
        midiEditor = last_midiEditor
    end
    
    fxNumber, fxName = export.findArticulationScript(track)
    return track, section_id, fxName, fxNumber, item, take, midiEditor, focusIsOn, focusHwnd
end

return export