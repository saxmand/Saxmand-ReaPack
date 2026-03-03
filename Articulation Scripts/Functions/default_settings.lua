-- @noindex

local export = {}

export.app = { 
    auditionNote = 64, 
    auditionVelocity = 100, 
    tableSizeTitle = 120, 
    tableSizeGroup = 100, 
    alwaysOverwriteApps = false,
    alwaysEmbedUi = false,
    autoResizeWindowWidth = false,
    autoResizeWindowHeight = false,    
    fontSize = 100,
}

export.InstrumentSettings = {
    usePDC = true, 
    onlyDelayPrePlayAmount = "Full negative delay", 
    sustainPedalForcesLegato = true, 
    addKeyswitchNamesToPianoRoll = true, 
    addKeyswitchNamesOverwriteAllNotes = true, 
    addKeyswitchNamesOverwriteAllCC = false, 
    recognizeArticulationsKeyswitches = true,
    triggerArticulationOnEveryNote = false,
}



export.column_modifiers = {
    ["Title"] = "Same",
    ["Group"] = "Same",
    ["Channel"] = "Increment",
    ["Layer"] = "Same",
    ["Delay"] = "Same",
    ["Pitch"] = "Fixed",
    ["Velocity"] = "Fixed",
    ["FilterVelocity"] = "Fixed",
    ["Note"] = "Same",
    ["CC"] = "Same", 
    ["Program"] = "Increment",
}

function export.saveSettings(key, tbl)
    local tblStr = json.encodeToJson(tbl)
    reaper.SetExtState(stateName,key, tblStr, true) 
end

function export.getSettings(key, default) 
    if not default then 
        default = export[key]
    end
    if reaper.HasExtState(stateName, key) then 
        local tblStr = reaper.GetExtState(stateName,key) 
        tbl = json.decodeFromJson(tblStr)
    else    
        tbl = {}
    end
    -- BACKWARDS COMPATABILITY
    for key, value in pairs(default) do
        if type(value) == "table" then 
            if tbl[key] == nil then
                tbl[key] = {}
            end
            
            for subKey, subValue in pairs(value) do
                if tbl[key][subKey] == nil then
                    tbl[key][subKey] = subValue
                end
            end
        else  
            if tbl[key] == nil then
                tbl[key] = value
            end
        end
    end
    export.saveSettings(key, tbl)

    return tbl
end


function export.saveAppSettings()
    local settingsStr = json.encodeToJson(appSettings)
    reaper.SetExtState(stateName,"appSettings", settingsStr, true) 
end

function export.getAppSettings() 
    local defaultAppSettings = export.app
    if reaper.HasExtState(stateName, "appSettings") then 
        local settingsStr = reaper.GetExtState(stateName,"appSettings") 
        appSettings = json.decodeFromJson(settingsStr)
    else    
        appSettings = {}
    end


    -- BACKWARDS COMPATABILITY
    for key, value in pairs(defaultAppSettings) do
        if type(value) == "table" then 
            if appSettings[key] == nil then
                appSettings[key] = {}
            end
            
            for subKey, subValue in pairs(value) do
                if appSettings[key][subKey] == nil then
                    appSettings[key][subKey] = subValue
                end
            end
        else  
            if appSettings[key] == nil then
                appSettings[key] = value
            end
        end
    end
    export.saveAppSettings()

    return appSettings
end



return export