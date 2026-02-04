-- @version 1.0
-- @noindex

local ex = {}

local file_handling = require("file_handling")
local json = require("json")
local embed_ui = require("embed_ui").main
local export = require("export")



local function getLuaTable(mapName)
    local specificFilePath = articulationScriptsPath .. seperator .. mapName .. ".jsfx"
    local jsonString = file_handling.readFileForJsonLine(specificFilePath)
    if jsonString then
        local luaTable = json.decodeFromJson(jsonString)
        return luaTable or {}
    end
    return {}
end

local function findLargestDelay(luaTable)
    local largestDelay = 0
    if luaTable and luaTable.tableInfo and luaTable.tableInfo.Delay then
        for _, value in pairs(luaTable.tableInfo.Delay) do
            if value < largestDelay then
                largestDelay = value
            end
        end
    end
    return largestDelay 
end




local stateName = "ArticulationScripts"
if not appSettings then 
    if reaper.HasExtState(stateName, "appSettings") then 
        local settingsStr = reaper.GetExtState(stateName,"appSettings") 
        appSettings = json.decodeFromJson(settingsStr)
    else    
        appSettings = {}
    end
end

local function addMapToTrack(track, mapName)
    local fxNumber
    local fxFound = false
    local fxAmount = reaper.TrackFX_GetCount(track)
    for i = 0, fxAmount - 1 do
        local _, fxName = reaper.TrackFX_GetFXName(track, i)
        if fxName:match("Articulation Script") ~= nil then
            fxFound = true -- , articulationMap = reaper.BR_TrackFX_GetFXModuleName(track,i+1,"FILE")
            fxNumber = i
            reaper.TrackFX_Delete(track, i)                    
            break
        end
    end
    local fxIndex = reaper.TrackFX_AddByName(track, mapName, false, -1)
    if fxIndex ~= -1 then
        if not fxFound then fxNumber = 0 end
        reaper.TrackFX_CopyToTrack(track, fxIndex, track, fxNumber, true)
        
        if appSettings.alwaysEmbedUi then
            embed_ui(track, fxIndex)
        end
    end

    local luaTable = getLuaTable(mapName)
    
    if luaTable and luaTable.instrumentSettings then 
        if not luaTable.instrumentSettings.usePDC then
            local largestDelay = findLargestDelay(luaTable)
            if largestDelay and largestDelay < 0 then 
                --local offsetFlag = reaper.GetMediaTrackInfo_Value(track, "I_PLAY_OFFSET_FLAG" )            
                reaper.SetMediaTrackInfo_Value(track, "I_PLAY_OFFSET_FLAG", 0)
                reaper.SetMediaTrackInfo_Value(track, "D_PLAY_OFFSET", largestDelay < 0 and largestDelay/1000 or 0)
            end
        else
            reaper.SetMediaTrackInfo_Value(track, "I_PLAY_OFFSET_FLAG", 1)
        end

        if luaTable.instrumentSettings.addKeyswitchNamesToPianoRoll then
            local articulationLayers = export.getArticulationsLayers(luaTable.tableInfo)

            local overwrite = true --reaper.ShowMessageBox("Overwrite old MIDI note and cc names", "SELECT",1) == 1
            for t = 0, reaper.CountSelectedTracks(0)- 1 do
                track = reaper.GetSelectedTrack(0,t)
                if overwrite then
                    for n = 0, 255 do
                        reaper.SetTrackMIDINoteNameEx( 0, track, n, 0, "" )
                    end
                end
            end

            -- number = numberStr:gsub("CC","") + 128
            local usedKeyswitches = {}
            local usedCCswitches = {}
            for layerCounter, artLayer in pairs(articulationLayers) do        
                for i, art in ipairs(artLayer) do
                    if art.keyswitchInfo and #art.keyswitchInfo == 1 and not usedKeyswitches[art.keyswitchInfo[1].key] then   
                        local key = art.keyswitchInfo[1].key                            
                        reaper.SetTrackMIDINoteNameEx( 0, track, key, 0, luaTable.instrumentSettings.addKeyswitchNamesToPianoRollOnlyUseTitle and art.Title or art.articulation )                            
                        usedKeyswitches[art.keyswitchInfo[1].key] = true
                    end
                    --if art.ccswitchInfo and not usedCCswitches[art.ccswitchInfo.key]  then
                    --    reaper.SetTrackMIDINoteNameEx( 0, track, art.ccswitchInfo.number + 128, 0, art.articulation )
                    --    usedCCswitches[art.ccswitchInfo.number]
                    --end
                end
            end                
        end

        if luaTable.instrumentSettings.addCCNamesToTrack then
            for num, name in pairs(luaTable.instrumentSettings.ccNamesOnTrack) do
                if name ~= "" then
                    reaper.SetTrackMIDINoteNameEx( 0, track, num + 128, 0, name )                            
                end
            end
        end
    end
end


local function getArticulationScriptSettings(track, fxIndex)
    local articulationScriptSettings = {}
    
    local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
    
    for p = 0, param_count - 1 do
        local retval, param_name = reaper.TrackFX_GetParamName(track, fxIndex, p)
        local value = reaper.TrackFX_GetParam(track, fxIndex, p)
        articulationScriptSettings[param_name] = value
    end
    return articulationScriptSettings
end

local function setArticulationScriptSettings(track, fxIndex, articulationScriptSettings)    
    local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
    for p = 0, param_count - 1 do
        local retval, param_name = reaper.TrackFX_GetParamName(track, fxIndex, p)
        if articulationScriptSettings[param_name] then
            reaper.TrackFX_SetParam(track, fxIndex, p, articulationScriptSettings[param_name])
        end
    end
end

function ex.updateOrAddMapAfterWait()   
    if overWriteFile_Wait == "UpdateMap" then 
        ex.updateMapOnInstrumentsWithMap(overWriteFile_Wait_Name)
    elseif overWriteFile_Wait == "AddMap" then
        ex.addMapToInstruments(overWriteFile_Wait_Name)
    end
end

function ex.updateMapOnInstrumentsWithMap(mapName)       

    if not overWriteFile_Wait then 
        export.createObjectForExport() -- generate script
    else
        overWriteFile_Wait = false
    end
    
    if not overWriteFile_Wait then 
        local somethingAdded = false
        for i = 0, reaper.GetNumTracks() - 1 do
            local track = reaper.GetTrack(0, i)
            local fxFound = false
            local fxAmount = reaper.TrackFX_GetCount(track)
            for fxIndex = 0, fxAmount - 1 do
                local _, fxName = reaper.TrackFX_GetFXName(track, fxIndex)
                if fxName:match("Articulation Script") ~= nil and fxName:match(mapName) ~= nil then
                    local articulationScriptSettings = getArticulationScriptSettings(track, fxIndex)
                    addMapToTrack(track, mapName)
                    setArticulationScriptSettings(track, fxIndex, articulationScriptSettings) 
                    break
                end
            end
        end
        return somethingAdded
    else
        overWriteFile_Wait_Name = mapName
        overWriteFile_Wait = "UpdateMap"
    end
end

function ex.addMapToInstruments(mapName)          
    if not overWriteFile_Wait then 
        export.createObjectForExport() -- generate script
    else
        overWriteFile_Wait = false
    end

    if not overWriteFile_Wait then 
        local somethingAdded = false
        for i = 0, reaper.GetNumTracks() - 1 do
            local track = reaper.GetTrack(0, i)
            if reaper.IsTrackSelected(track) then
                addMapToTrack(track, mapName)-- .. " (Articulation script)")
            end
        end
        reaper.SetExtState("ArticulationScripts", "ReloadArticaultion", "1", true) 
        --return somethingAdded
    else                
        overWriteFile_Wait_Name = mapName
        overWriteFile_Wait = "AddMap"
    end
end

return ex