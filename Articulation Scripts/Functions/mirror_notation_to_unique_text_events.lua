-- @noindex

local function deleteTextEvents(take) 
    local _, _, _, textCount = reaper.MIDI_CountEvts(take)
    for i = textCount - 1, 0, -1 do
        local retval, _, _, _, _type, _ = reaper.MIDI_GetTextSysexEvt(take, i)
        if retval and _type == 1 then 
            reaper.MIDI_DeleteTextSysexEvt(take, i)
        end
    end 
end


local function deleteTakeMarkers(take) 
    local count = reaper.GetNumTakeMarkers(take)
    for i = count - 1, 0, -1 do
        reaper.DeleteTakeMarker(take, i)
    end 
end

local function tokenize(str)
    local result = {}
    local current = ""
    local in_quote = false
    local quote_char = nil

    for i = 1, #str do
        local c = str:sub(i, i)
        if not in_quote and (c == '"' or c == "'" or c == '`') then
            in_quote = true
            quote_char = c
        elseif in_quote and c == quote_char then
            in_quote = false
            quote_char = nil
        elseif not in_quote and c == ' ' then
            if current ~= "" then
                -- Strip surrounding quotes if present
                if current:match('^["\'`].*["\'`]$') then
                    current = current:sub(2, -2)
                end
                table.insert(result, current)
                current = ""
            end
        else
            current = current .. c
        end
    end

    if current ~= "" then
        -- Strip surrounding quotes if present
        if current:match('^["\'`].*["\'`]$') then
            current = current:sub(2, -2)
        end
        table.insert(result, current)
    end

    return result
end
    
local export = {}

function export.mirror_notation_to_unique_text_events(take)
    --reaper.Undo_BeginBlock()
    --reaper.PreventUIRefresh(1)
    if settings.mirror_notation_articulations_to_text_events or settings.mirror_notation_dynamics_to_text_events then
         
        local _, _, _, textCount = reaper.MIDI_CountEvts(take)
        
        local lastText = nil
        
        local eventsToGenerate = {}
        for i = 0, textCount - 1 do
            local retval, selected, muted, ppqpos, _type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
            if retval and _type == 15 then  -- 15 = REAPER notation 
                
                local color = 0xFFFFFFFF
                local textEventText 
                local tokens = tokenize(msg)
                local eventType = tokens[1]
                
                if eventType == "NOTE" then 
                    local noteType = tokens[4]
                    if noteType == "text" then 
                        local articulation = tokens[5]
                        textEventText = articulation:sub(0,-4) 
                    end  
                    if noteType == "articulation" then 
                        local articulation = tokens[5]
                        textEventText = articulation
                    end  
                end
                
                if eventType == "TRAC" then
                    local trackType = tokens[2]
                    if trackType == "custom" then 
                        local articulation = tokens[3]
                        textEventText = articulation
                    end
                    if trackType == "text" then 
                        local articulation = tokens[3]
                        textEventText = articulation
                    end

                    if settings.mirror_notation_dynamics_to_text_events and trackType == "dynamic" then 
                        local dynamic = tokens[3]
                        textEventText = dynamic
                    end
                --reaper.ShowConsoleMsg(articulation .."\n")
                    --textEventText = articulation 
                end
                
                if textEventText and textEventText ~= lastText then
                    -- normal MIDI text event
                    table.insert(eventsToGenerate, {ppqpos = ppqpos, textEventText = textEventText, color = color}) 
                    lastText = textEventText
                end
            end
        end
        
        deleteTextEvents(take) 
        --deleteTakeMarkers(take) 
        for _, v in ipairs(eventsToGenerate) do
            reaper.MIDI_InsertTextSysexEvt(take, false, false, v.ppqpos, 0x01, v.textEventText )
            --reaper.SetTakeMarker(take, -1, v.textEventText, reaper.MIDI_GetProjTimeFromPPQPos(take, v.ppqpos) - reaper.MIDI_GetProjTimeFromPPQPos(take, 0), v.color)
        end
        
        reaper.MIDI_Sort(take)
        
        --reaper.PreventUIRefresh(-1)
        --reaper.Undo_EndBlock("Mirror notation to unique text events", 0)
    end
end

return export