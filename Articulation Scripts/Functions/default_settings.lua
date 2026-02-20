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
    ["Layer"] = "Increment",
    ["Delay"] = "Same",
    ["Pitch"] = "Fixed",
    ["Velocity"] = "Fixed",
    ["FilterVelocity"] = "Fixed",
    ["Note"] = "Same",
    ["CC"] = "Same", 
}

return export