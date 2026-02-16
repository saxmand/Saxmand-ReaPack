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

local function getArtNameFromSliders(track, artSliders)
    local newName = ""
    for i, slider in ipairs(artSliders) do
        local selectedArticulationIdx, min, max = reaper.TrackFX_GetParam(track, slider.fxNumber, slider.param)     -- 0 is the parameter index, 0 is the parameter value
        if selectedArticulationIdx > -1 and selectedArticulationIdx <= max then
            local artNameFromSlider = triggerTableLayers[i][selectedArticulationIdx + 1].articulation
            newName = newName .. (i > 1 and " / " or "") .. artNameFromSlider
        end
    end
    return newName
end


local function updateSliderFromArticulation(track, articulation)
    local triggerTables, triggerTableLayers, triggerTableKeys, artSliders, articulationNotFoundParam = readArticulationScript(track, name)

    if articulation then 
        local existsInScript
        local isAToggle = false
        local isToggleOn = false
        for i, art in ipairs(triggerTables) do
            if art.articulation == articulation then
                --reaper.ShowConsoleMsg(tostring(artSliders[art.layer].fxNumber) .. " - " .. art.layer.."\n")
                local selectedArticulationIdx, artMin, artMax = reaper.TrackFX_GetParam(track, artSliders[art.layer].fxNumber, artSliders[art.layer].param)
                isAToggle = math.floor(artMax) == 0
                isToggleOn = math.floor(selectedArticulationIdx) == math.floor(artMin)
                local sliderVal = isAToggle and (isToggleOn and 1 or 0) or art.artInLayer 
                reaper.TrackFX_SetParam(track, artSliders[art.layer].fxNumber, artSliders[art.layer].param, sliderVal)
                existsInScript = art
                break;
            end
        end
        return existsInScript, triggerTableLayers, artSliders, isAToggle, isToggleOn
    else
        return true, triggerTableLayers, artSliders
    end
end

local function updateSlidersOnAllTrack(articulation)
    for t = 0, reaper.CountSelectedTracks(0)- 1 do
        local track = reaper.GetSelectedTrack(0,t)
        updateSliderFromArticulation(track, articulation)
    end
end

-- Function to set notation text for selected notes
local function setNotationText(take, articulation, allNotes)
    
    local takeTrack = reaper.GetMediaItemTake_Track(take)
    local existsInScript, triggerTableLayers, artSliders, isAToggle, isToggleOn = updateSliderFromArticulation(track, articulation)
    

    if existsInScript then 
        local _, numNotes = reaper.MIDI_CountEvts(take)
        local nothingSelected = reaper.MIDI_EnumSelNotes(take, 0) == -1
        for noteidx = 0, numNotes - 1 do
            local retval, selected, muted, notePpqpos, endppqpos, noteChannel, notePitch, vel = reaper.MIDI_GetNote(take, noteidx)
            if allNotes or selected then
                local newName = ""
                local artLayer
                -- look more at this
                if not cmd then
                    local currentText = getNoteText(take, noteChannel, notePpqpos, notePitch)
                    if currentText then
                        local arts = split_exact(currentText)
                        --[[ for i, a in ipairs(arts) do
                            for _, t in ipairs(triggerTableLayers[existsInScript.layer]) do
                                if a == t.articulation then
                                    if isAToggle then 
                                        --table.remove(arts, i)
                                        arts[i] = ""
                                    else
                                        arts[i] = articulation
                                    end
                                    break
                                end  
                            end
                        end ]]
                        local newArtsTbl = {}
                        for layerIndex, layer in ipairs(triggerTableLayers) do
                            local found = false
                            if existsInScript.layer == layerIndex then
                                newArtsTbl[layerIndex] = (not isAToggle or not isToggleOn) and articulation or ""
                            else
                                for artIndexInLayer, art in ipairs(layer) do
                                    for i, a in ipairs(arts) do                                         
                                        if art.articulation == a then 
                                            newArtsTbl[layerIndex] = a
                                            found = true
                                            break                     
                                        end
                                    end
                                end    
                                if not found then 
                                    newArtsTbl[layerIndex] = #layer > 1 and layer[1].articulation or ""
                                end
                            end
                        end

                        --if not isToggleOn and isAToggle then                            
                        --    local insertIndex = existsInScript.layer--#arts + 1 <= existsInScript.layer and #arts+1 or existsInScript.layer
                            --table.insert(arts, insertIndex, articulation)
                        --end
                        --if #arts < #artSliders then 
                        --    for i = 1, #artSliders - #arts do
                               -- table.insert(arts, "")                            
                        --    end
                        --end
                        
                        newName = table.concat(newArtsTbl, " / ")
                    else
                        newName = getArtNameFromSliders(takeTrack, artSliders)
                    end
                else
                    newName = getArtNameFromSliders(takeTrack, artSliders)
                end
                local text = "NOTE " .. noteChannel .. " " .. notePitch .. " text " .. '"' .. newName .. '"'
                reaper.MIDI_InsertTextSysexEvt(take, selected, muted, notePpqpos, 15, text, true)
            end
        end
        -- Resync the MIDI editor to update the changes
        reaper.MIDI_Sort(take)

        mirror_notation_to_unique_text_events(take)
    end
end

local function selectArticulationContaining(take, articulation)
    local takeTrack = reaper.GetMediaItemTake_Track(take)
    local triggerTables, triggerTableLayers, triggerTableKeys, artSliders, articulationNotFoundParam = readArticulationScript(track, name)
    local _, numNotes = reaper.MIDI_CountEvts(take)
    local nothingSelected = reaper.MIDI_EnumSelNotes(take, 0) == -1
    local selectedAmount = 0
    local deselected = 0
    local curSelectedAmount = 0
    local selectIfNothingSelected = {}
    for noteidx = 0, numNotes - 1 do
        local retval, selected, muted, notePpqpos, endppqpos, noteChannel, notePitch, vel = reaper.MIDI_GetNote(take, noteidx)
        local currentText = getNoteText(take, noteChannel, notePpqpos, notePitch)
        if currentText then
            local arts = split_exact(currentText)
            for i, a in ipairs(arts) do
                if selected then 
                    curSelectedAmount = curSelectedAmount + 1
                end
                if a == articulation then
                    table.insert(selectIfNothingSelected, noteidx)
                    if selected then 
                        selectedAmount = selectedAmount + 1
                        reaper.MIDI_SetNote( take, noteidx, true, nil, nil, nil, nil, nil, nil, true )
                        break
                    end
                elseif not ctrl and selected then 
                    deselected = deselected + 1
                    reaper.MIDI_SetNote( take, noteidx, false, nil, nil, nil, nil, nil, nil, true )
                end
            end
        end            
    end
    if (selectedAmount == 0 and #selectIfNothingSelected > 0) or (deselected == 0 and #selectIfNothingSelected > selectedAmount) then
        for _, noteidx in ipairs(selectIfNothingSelected) do
            reaper.MIDI_SetNote( take, noteidx, true, nil, nil, nil, nil, nil, nil, true )
        end
    end

    reaper.MIDI_Sort(take)
end

local function setNotationOrSelectNotes(take, articulation, allNotes, forceInsert)
    if shift and not forceInsert then 
        selectArticulationContaining(take, articulation)
    else
        setNotationText(take, articulation, allNotes)
    end
end

-- Function to set notation text for selected notes
local function setNotationText_OLD(take, articulation, allNotes, isOff)
    local takeTrack = reaper.GetMediaItemTake_Track(take)
    local triggerTables, triggerTableLayers, triggerTableKeys, artSliders, articulationNotFoundParam = readArticulationScript(track, name)


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
                        if isOff and arts[artLayer] == articulation then
                            table.remove(arts, artLayer)
                        else 
                            arts[artLayer] = articulation
                        end
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
                        local selectedArticulationIdx, min, max = reaper.TrackFX_GetParam(track, fxNumber, slider.param)     -- 0 is the parameter index, 0 is the parameter value
                        if selectedArticulationIdx > -1 and selectedArticulationIdx <= max then
                            artNameFromSlider = triggerTableLayers[i][selectedArticulationIdx + 1].articulation
                            newName = newName .. (i > 1 and " / " or "") .. artNameFromSlider
                        end
                        --end
                    end
                end
                newName = newName --.. " / "
            else
                newName = articulation --.. " / "
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
    if itemCount > 0 then 
        -- Iterate through selected media items
        for i = 0, itemCount - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)

            -- Get the active take on the item
            local take = reaper.GetActiveTake(item)

            -- Check if the active take is a MIDI take
            if take and reaper.TakeIsMIDI(take) then
                setNotationOrSelectNotes(take, articulation, true)
            end
        end
    end
end

function setArticulationOnTrack(track, prg)
    local fxNumber, fxName = track_depending_on_selection.findArticulationScript(track)
    if fxNumber then 
        local countArts = 0
        for i, slider in ipairs(artSliders) do
            local selectedArticulationIdx, artMin, artMax = reaper.TrackFX_GetParam(track, fxNumber, slider.param)
            if countArts + artMax < tonumber(prg) then
                countArts = countArts + artMax + 1
            else
                local newVal = prg - countArts
                if tonumber(selectedArticulationIdx) == 0 and artMin == 0 and artMax == 0 then
                    reaper.TrackFX_SetParam(track, fxNumber, slider.param, 1)
                    return true
                else
                    reaper.TrackFX_SetParam(track, fxNumber, slider.param, newVal)
                end
                break
            end
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
                        for layerNumber, layer in ipairs(triggerTableLayers) do
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

function export.changeArticulation(prg, articulation, focusIsOn, forceInsert)
    --trackArticulationScripts = {}
    -- make this only happen if the selected track and item is the same
    --for i = 0, 15 do
    -- use this if in recording mode
    -- change this with keyswitches etc
    -- make auto articaultion naming after recording stops
    if prg and tonumber(prg) < 128 then 
        --reaper.StuffMIDIMessage(0, 192, prg, 127)
    end
    
    if focusIsOn == "track" then 
        updateSlidersOnAllTrack(articulation)
    else
        --end
        -- Get the active MIDI editor
        local midiEditor = reaper.MIDIEditor_GetActive()
        if midiEditor and focusIsOn == "editor" then
            -- Get the active take in the MIDI editor
            -- local activeTake = reaper.MIDIEditor_GetTake(midiEditor)
            local numItems = reaper.CountSelectedMediaItems(0)
            if numItems > 0 then 
                for i = 0, numItems - 1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    if reaper.IsMediaItemSelected(item) then
                        local numTakes = reaper.CountTakes(item)
                        for j = 0, numTakes - 1 do
                            local take = reaper.GetMediaItemTake(item, j)
                            if take and reaper.TakeIsMIDI(take) then
                                -- MAYBE ENSURE THAT TAKE IS SELECTED
                                setNotationOrSelectNotes(take, articulation, false, forceInsert)
                            end
                        end
                    end
                end
            else
                local editor_take = reaper.MIDIEditor_GetTake(midiEditor)
                setNotationOrSelectNotes(editor_take, articulation, false, forceInsert)
            end
            -- if activeTake then
            -- Run the function to set notation text for selected notes
            --  setNotationOrSelectNotes(activeTake, articulation, false)
            -- end
        elseif focusIsOn == "take" then
            --isOff = setArticulationOnTrack(track, prg)
            setArticulationOnAllSelectedTakes(articulation)
        end
    end
end

return export
