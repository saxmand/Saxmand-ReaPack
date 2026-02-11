-- @noindex

local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")

-- Load the reaper sections id number
local reaper_sections = dofile(scriptPath .. "/Helpers/reaper_sections.lua")


local function findArticulationScript(track)
    if not track then return end
    local fxAmount = reaper.TrackFX_GetCount(track)
    for i = 0, fxAmount - 1 do
        local _, fxName = reaper.TrackFX_GetFXName(track, i)
        if fxName:match("Articulation Script") then
            local name = fxName:gsub(" %(Articulation Script%)", ""):gsub("JS: ", "")
            if name:match(" %[Articulation Scripts/") then
                name = name:match("^(.-) %[Sound")
            end -- "fix" if more maps have the same description
            local fxNumber = i
            return fxNumber, name
        end
    end
end

local export = {}

function export.trackDependingOnSelection()
    local midiEditor = reaper.MIDIEditor_GetActive()
    local track, section_id, name, fxNumber, item, take
    local isRecording = reaper.GetPlayState() & 4 == 4 
    local firstSelectedTrack = reaper.GetSelectedTrack(0, 0)

    if not isRecording then
        if midiEditor then
            take = reaper.MIDIEditor_GetTake(midiEditor)
            if take then 
                item = reaper.GetMediaItemTake_Item(take)
                track = reaper.GetMediaItemTrack(item)
                section_id = reaper_sections["MIDI Editor"]
            end
        end
            -- inline editor = 32061
        if not section_id then
            local selectedMediaItemsCount = reaper.CountSelectedMediaItems(0)
            if selectedMediaItemsCount > 0 then
                item = reaper.GetSelectedMediaItem(0, 0)
                take = reaper.GetActiveTake(item)
                track = reaper.GetMediaItemTrack(item)
            end
            section_id = reaper_sections["Main"]

            -- if last defer track was focused, we stay here, by keep reseting last selected track
            if trackIsFocused then 
                -- unless we have a different take than last time
                if take and last_take_selection ~= take then                    
                    last_take_selection = take
                    takeIsFocused = true
                    trackIsFocused = false
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
        end
    end

    
    if not track then track = firstSelectedTrack end
    fxNumber, name = findArticulationScript(track)
    return track, section_id, name, fxNumber, item, take, midiEditor
end

return export