-- @noindex

local export = {}

function export.main(track, fx_id)
    if not track or fx_id < 0 then return end

    local rv, chunk = reaper.GetTrackStateChunk(track, "", false)
    if not rv then return end
    local fx_count = reaper.TrackFX_GetCount(track)
    if fx_id >= fx_count then return end

    local pos = 1
    local current_fx = 0

    while true do
        -- Match VST/AU/JSFX/CLAP start line
        local s, e = chunk:find("<.-\n", pos)
        if not s then break end

        if current_fx == fx_id then
            -- Only replace the WAK value for this FX
            -- Try to find an existing WAK line
            local wak_s, wak_e = chunk:find("WAK%s+%d+", e)
            if wak_s then

                chunk = chunk:sub(1, wak_s-1) ..
                        "WAK 1 1" ..
                        chunk:sub(wak_e+1)
            else
                -- If WAK is missing, insert after the FX header line
                chunk = chunk:sub(1, e) ..
                        "WAK 1\n" ..
                        chunk:sub(e+1)
            end
            break
        end

        current_fx = current_fx + 1
        pos = e + 1
    end

    reaper.SetTrackStateChunk(track, chunk, false)
end

function export.on_selected_tracks()
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i) 
        local fxFound = false
        local fxAmount = reaper.TrackFX_GetCount(track)
        for fxIndex = 0, fxAmount - 1 do
            _, fxName = reaper.TrackFX_GetFXName(track, fxIndex)
            if fxName:match("Articulation Script") ~= nil then
                fxFound = true -- , articulationMap = reaper.BR_TrackFX_GetFXModuleName(track,i+1,"FILE")
                export.main(track, fxIndex)
                break
            end
        end 
    end
end

return export
