-- @version 1.0
-- @noindex


function getNoteText(take, noteChannel, notePpqpos, notePitch)
    local i = 0
    local notationTexts = {}
    while true do
        local retval, selected, muted, ppqpos, _type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
        if not retval then break end -- Stop if no more events
        -- Check if it's a notation text event (type -1)
        if _type == 15 then
            local eventType, channel, pitch, articulation = msg:match('(%S+) (%d+) (%d+) text%s+"?([^"]+)"?')
            if eventType == "NOTE" and tonumber(channel) == noteChannel and tonumber(ppqpos) == notePpqpos and tonumber(pitch) == notePitch then
                return articulation
            end
        end
        i = i + 1 -- Move to the next event
    end
end

function split_exact(str, sep)
    sep = sep or " / "
    local t = {}
    local pattern = "(.-)" .. sep:gsub("(%p)", "%%%1") -- escape special chars
    local last_end = 1
    local s, e, cap = str:find(pattern, 1)
    while s do
        table.insert(t, cap)
        last_end = e + 1
        s, e, cap = str:find(pattern, last_end)
    end
    table.insert(t, str:sub(last_end))

    if t[#t] == "" then t[#t] = nil end

    return t
end

-- Function to set notation text for selected notes
local function setNotationText(take, articulation, allNotes)
    local _, numNotes = reaper.MIDI_CountEvts(take)
    local nothingSelected = reaper.MIDI_EnumSelNotes(take, 0) == -1
    for noteidx = 0, numNotes - 1 do
        local retval, selected, muted, notePpqpos, endppqpos, noteChannel, notePitch, vel = reaper.MIDI_GetNote(take, noteidx)
        if allNotes or selected then
            local newName = ""
            local artLayer
            -- look more at this
            if not cmd and #triggerTableLayers > 1 and fxNumber then
                -- find what layer the articulation belongs in, as I do not think the sliders update before we check here
                for i, art in ipairs(triggerTables) do
                    if articulation == art.articulation then
                        artLayer = art.layer
                        break
                    end
                end

                local currentText = getNoteText(take, noteChannel, notePpqpos, notePitch)
                local replacedName = false
                if currentText then
                    -- find and replace the current layer articulation
                    --[[
                    local arts = {}


                    for part in currentText:gmatch("([^/]+)") do
                        table.insert(arts, part:match("^%s*(.-)%s*$")) -- trim whitespace
                    end
                    ]]
                    local arts = split_exact(currentText)

                    if arts[artLayer] then
                        arts[artLayer] = articulation
                        newName = table.concat(arts, " / ")
                        replacedName = true
                    end
                    --[[
                    for i, art in ipairs(triggerTableLayers[artLayer]) do
                        if currentText:match(art.articulation) ~= nil then
                            newName = currentText:gsub(art.articulation, articulation)
                            artLayer = art.layer
                            replacedName = true
                            break
                        end
                    end
                    ]]
                end

                if not replacedName then
                    -- updates all articulations based on the slider settings
                    for i, slider in ipairs(artSliders) do
                        --if slider.layer == artLayer then
                        --    newName = newName .. (i > 1 and " / " or "") .. articulation
                        --else
                        local selectedArticulationIdx = reaper.TrackFX_GetParam(track, fxNumber, slider.param)     -- 0 is the parameter index, 0 is the parameter value
                        if selectedArticulationIdx > -1 then
                            artNameFromSlider = triggerTableLayers[i][selectedArticulationIdx + 1].articulation
                            newName = newName .. (i > 1 and " / " or "") .. artNameFromSlider
                        end
                        --end
                    end
                end
                newName = newName .. " / "
            else
                newName = articulation .. " / "
            end

            local text = "NOTE " .. noteChannel .. " " .. notePitch .. " text " .. '"' .. newName .. '"'
            reaper.MIDI_InsertTextSysexEvt(take, selected, muted, notePpqpos, 15, text, true)
        end
    end
    -- Resync the MIDI editor to update the changes
    reaper.MIDI_Sort(take)

    mirror_notation_to_unique_text_events(take)
end

local function setArticulationOnAllSelectedTakes(articulation)
    -- Get the number of selected media items
    local itemCount = reaper.CountSelectedMediaItems(0)

    -- Iterate through selected media items
    for i = 0, itemCount - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)

        -- Get the active take on the item
        local take = reaper.GetActiveTake(item)

        -- Check if the active take is a MIDI take
        if take and reaper.TakeIsMIDI(take) then
            setNotationText(take, articulation, true)
        end
    end
end

function setArticulationOnTrack(prg)
    local countArts = 0
    for i, slider in ipairs(artSliders) do
        local selectedArticulationIdx, artMin, artMax = reaper.TrackFX_GetParam(track, fxNumber, slider.param)
        if countArts + artMax < tonumber(prg) then
            countArts = countArts + artMax + 1
        else
            reaper.TrackFX_SetParam(track, fxNumber, slider.param, prg - countArts)
            break
        end
    end
end

local export = {}

-- update when selected new notes in midi editor
function export.updateArticulationJSFX(take)
    if take then
        local _, noteCount = reaper.MIDI_CountEvts(take)
        for n = 0, noteCount - 1 do
            local _, sel, muted, notePpqpos, endppqpos, noteChannel, notePitch, vel = reaper.MIDI_GetNote(take, n)
            if sel then
                if not lastSelectedNote or lastSelectedNote ~= n then
                    lastSelectedNote = n
                    local currentText = getNoteText(take, noteChannel, notePpqpos, notePitch)
                    if currentText then
                        local arts = split_exact(currentText)
                        local allLayersFound = true
                        for layerNumber, layer in pairs(triggerTableLayers) do
                                --reaper.ShowConsoleMsg(tostring(artSelected[layerNumber]) .. " - " ..layerNumber  .. " artsel\n")
                            local layerFound = false
                            for artNum, key in ipairs(layer) do
                                if key.articulation == arts[layerNumber] then
                                    if math.floor(artSelected[layerNumber]) ~= math.floor(artNum - 1) then 
                                        reaper.TrackFX_SetParam(track, fxNumber, artSliders[layerNumber].param, artNum - 1)
                                    end
                                    if articulationNotFoundParam then 
                                        reaper.TrackFX_SetParam(track, fxNumber, articulationNotFoundParam, 0)
                                    end
                                    layerFound = true
                                --reaper.ShowConsoleMsg(tostring(arts[layerNumber]) .. " - " ..layerNumber  .. " found\n")
                                    break
                                end                                
                            end
                            if not layerFound then 
                                --reaper.ShowConsoleMsg(tostring(arts[layerNumber]) .. " - " ..layerNumber  .. " err\n")
                                allLayersFound = false                                
                            end
                        end
                        if not allLayersFound and articulationNotFoundParam then
                            reaper.TrackFX_SetParam(track, fxNumber, articulationNotFoundParam, 1)
                        end
                    end
                end
                break
            end
        end
    end
end

function export.changeArticulation(prg, articulation)
    -- make this only happen if the selected track and item is the same
    --for i = 0, 15 do
    -- use this if in recording mode
    -- change this with keyswitches etc
    -- make auto articaultion naming after recording stops
    if prg < 128 then 
        reaper.StuffMIDIMessage(0, 192, prg, 127)
    end
    
    --end
    setArticulationOnTrack(prg)
    -- Get the active MIDI editor
    local midiEditor = reaper.MIDIEditor_GetActive()
    if midiEditor then
        -- Get the active take in the MIDI editor
        -- local activeTake = reaper.MIDIEditor_GetTake(midiEditor)
        local numItems = reaper.CountMediaItems(0)
        for i = 0, numItems - 1 do
            local item = reaper.GetMediaItem(0, i)
            if reaper.IsMediaItemSelected(item) then
                local numTakes = reaper.CountTakes(item)
                for j = 0, numTakes - 1 do
                    local take = reaper.GetMediaItemTake(item, j)
                    if take and reaper.TakeIsMIDI(take) then
                        -- MAYBE ENSURE THAT TAKE IS SELECTED
                        setNotationText(take, articulation, false)
                    end
                end
            end
        end
        -- if activeTake then
        -- Run the function to set notation text for selected notes
        --  setNotationText(activeTake, articulation, false)
        -- end
    else
        setArticulationOnAllSelectedTakes(articulation)
    end
end

return export
