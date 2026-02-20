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
    sustainPedalForcesLegato = true, 
    addKeyswitchNamesToPianoRoll = true, 
    addKeyswitchNamesOverwriteAllNotes = true, 
    addKeyswitchNamesOverwriteAllCC = false, 
    recognizeArticulationsKeyswitches = true
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