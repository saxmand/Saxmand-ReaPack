-- @description FX Modulator Linking
-- @author Saxmand
-- @version 0.2.7
-- @provides
--   [effect] ../FX Modulator Linking/*.jsfx
--   Helpers/*.lua
-- @changelog
--   + fixed Modulator always showing output and map button
--   + added AB mappings overview
--   + moved "remove Modulator" button to top left corner X
--   + fixed clean up of removing Modulator
--   + maybe fixed parameters that are not from 0-1 for setting their baseline
--   + fixed minimized version of modulators
--   + added preset support
--   + you can now hide parameters in custom modulators, this will also be stored in presets
--   + fixed to remember pos and dock from last time

local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[\\/])")
package.path = package.path .. ";" .. scriptPath .. "Helpers/?.lua"
local json = require("json")
local specialButtons = require("special_buttons")

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'
local stateName = "ModulationLinking"
local appName = "FX Modulator Linking"
local ctx = ImGui.CreateContext(appName)
font = reaper.ImGui_CreateFont('Arial', 14)
font1 = reaper.ImGui_CreateFont('Arial', 15)
font2 = reaper.ImGui_CreateFont('Arial', 17)
font10 = reaper.ImGui_CreateFont('Arial', 10)
-- imgui_font
reaper.ImGui_Attach(ctx, font)
reaper.ImGui_Attach(ctx, font1)
reaper.ImGui_Attach(ctx, font2)
reaper.ImGui_Attach(ctx, font10)
reaper.ImGui_SetConfigVar(ctx,reaper.ImGui_ConfigVar_MacOSXBehaviors(),0)

function checkIfPluginIsInstalled(name)
     function jsfx_exists(name)
       local i = 0
       while true do
         local ret, fx = reaper.EnumInstalledFX(i)
         if not ret or not fx then break end
         if ret and fx:match("^JS:") and fx:lower():find(name:lower(), 1, true) then
           return true
         end
         i = i + 1
       end
       return false
     end
    
    -- Example
    return jsfx_exists(name) 
end

local isAdsr1Installed = checkIfPluginIsInstalled("ADSR-1")
local isMseg1Installed = checkIfPluginIsInstalled("MSEG-1")
--function reaper_do_file(file) local info = debug.getinfo(1,'S'); local path = info.source:match[[^@?(.*[\/])[^\/]-$]]; dofile(path .. file); end
--reaper_do_file('Helpers/json.lua')
-----------------------------------------
------------ TOOLBAR SETTINGS -----------
-----------------------------------------
local _,_,_,cmdID = reaper.get_action_context()
-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end
-----------------------------------------
-----------------------------------------
-----------------------------------------


local focusedTrackFXNames = {}
local parameterLinks = {}
local focusedTrackFXParametersData = {}
local modulatorNames = {}
local modulatorFxIndexes = {}
modulationContainerPos = nil
local buttonHovering = {}

                    
local directions = {"Downwards", "Bipolar", "Upwards"}

local margin = 8

local defaultSettings = {
    openSelectedFx = false,
    includeModulators = false, 
    showParametersForAllPlugins = false,
    trackSelectionFollowFocus = false, 
    showToolTip = true,
    sortAsType = false,
    partsHeight = 250,
    vertical = false,
    
    onlyMapped = false,
    search = "", 
    partsWidth = 188,
    -- Plugins
    showContainers = true,
    colorContainers = true,
    indentsAmount = 3,
    allowHorizontalScroll = false,
    wwVertical = 180 + margin *4,
    whVertical = 900,
    xVertical = 300,
    yVertical = 300,
    wwHorizontal = 1500,
    whHorizontal = 450, 
    xHorizontal = 300, 
    yHorizontal = 300, 
    showBuildin = true,
    showUser = true,
    showPreset = true,
    userModulators = {},
    mapOnce = false,
    
    defaultMappingWidth = 50,
    defaultDirection = 3,
    defaultLFODirection = 2,
}

local defaultTrackSettings = {
    hideModules = false,
    hideParameters = false,
    hidePlugins = false,
    collabsModules = {},
    show = {},
    renamed = {},
    bigWaveform = {},
}

local function saveSettings()
    local settingsStr = json.encodeToJson(settings)
    reaper.SetExtState(stateName,"settings", settingsStr, true) 
end



if reaper.HasExtState(stateName, "settings") then 
    local settingsStr = reaper.GetExtState(stateName,"settings") 
    settings = json.decodeFromJson(settingsStr)
else    
    settings = defaultSettings
    saveSettings()
end

-- BACKWARDS COMPATABILITY
for key, value in pairs(defaultSettings) do
    if not settings[key] then
        settings[key] = value
    end
end

local function saveTrackSettings(track)
    if track then
        local trackSettingsStr = json.encodeToJson(trackSettings)
        reaper.GetSetMediaTrackInfo_String(track, "P_EXT" .. ":" .. stateName, trackSettingsStr, true)
    end
end

local function loadTrackSettings(track)
    trackSettings = {}
    if track then
        local hasSavedState, savedTrackStates = reaper.GetSetMediaTrackInfo_String(track, "P_EXT" .. ":" .. stateName, "{}", false)
        if hasSavedState then        
            trackSettings = json.decodeFromJson(savedTrackStates)
            
            for key, value in pairs(defaultTrackSettings) do
                if not trackSettings[key] then
                    trackSettings[key] = value
                end
            end
        else
            trackSettings = defaultTrackSettings
            saveTrackSettings(track)
        end 
    end
    return trackSettings
end

-----------------
---- HELPERS ----
-----------------

function splitString(inputstr)
    local t = {}
    for str in string.gmatch(inputstr, "([^, ]+)") do
        table.insert(t, str)
    end
    return t
end

function searchName(name, search)
    name = name:lower()
    search_parts = splitString(search)

    for _, part in ipairs(search_parts) do
        if not string.find(name, part:lower()) then
            return false
        end
    end
    return true
end

function openWebpage(url)
    if reaper.GetOS():match("Win") then
      os.execute('start "" "' .. url .. '"')
    elseif reaper.GetOS():match("mac") then
    reaper.ShowConsoleMsg("HJE\n")
      os.execute('open "' .. url .. '"')
    else -- Assume Linux
      os.execute('xdg-open "' .. url .. '"')
    end
end


--------------------------------------------------------------------------
------------------------------ VERTICAL TEXT -----------------------------
--------------------------------------------------------------------------


-- Define vector shapes for the full alphabet (A-Z)
local char_shapes = {
    A = {{0.0, 1.0, 0.4, 0.0}, {0.85, 1.0}, {0.15, 0.6, 0.7, 0.6}}, -- "A"
    B = {{0.0, 1.0, 0.0, 0.0}, {0.4, 0.0}, {0.60, 0.1}, {0.65, 0.3}, {0.5, 0.45}, {0.7, 0.65}, {0.7, 0.8}, {0.65, 0.9}, {0.45, 1.0}, {0.0, 1.0}, {0.0, 0.45, 0.5, 0.45}}, -- "B"
    C = {{0.8, 0.65, 0.7, 0.85}, {0.5, 1.0}, {0.35, 1.0}, {0.2, 0.95}, {0.05, 0.75}, {0.0, 0.55}, {0.0, 0.4}, {0.1, 0.15}, {0.3, 0.0}, {0.5, 0.0}, {0.65, 0.05}, {0.8, 0.25}}, -- "C"
    D = {{0.0, 1.0, 0.0, 0.0}, {0.4, 0.0}, {0.65, 0.1}, {0.75, 0.35}, {0.75, 0.6}, {0.7, 0.8}, {0.4, 1.0}, {0.0, 1.0}}, -- "D"
    E = {{0.7, 1.0, 0.0, 1.0}, {0.0, 0.0}, {0.65, 0.0}, {0.0, 0.5, 0.6, 0.5}}, -- "E"
    F = {{0.0, 1.05, 0.0, 0.05}, {0.65, 0.05}, {0.0, 0.5, 0.55, 0.5}}, -- "F"
    G = {{0.5, 0.5, 0.85, 0.5}, {0.85, 0.8}, {0.55, 1.0}, {0.3, 1.0}, {0.1, 0.85}, {0.0, 0.6}, {0.0, 0.4}, {0.1, 0.15}, {0.35, 0.0}, {0.55, 0.0}, {0.75, 0.1}, {0.85, 0.25}}, -- "G"
    H = {{0.0, 1.0, 0.0, 0.0}, {0.0, 0.5, 0.7, 0.5}, {0.7, 0.0, 0.7, 1.0}}, -- "H"
    I = {{0, 0, 0, 1}}, -- "I"
    J = {{0.0, 0.7, 0.1, 0.9}, {0.25, 1.0}, {0.4, 0.9}, {0.5, 0.75}, {0.5, 0.0}}, -- "J"
    K = {{0.0, 0.0, 0.0, 1.0}, {0.0, 0.6, 0.6, 0.0}, {0.25, 0.35}, {0.7, 1.0}}, -- "K"
    L = {{0.55, 1.0, 0.0, 1.0}, {0.0, 0.0}}, -- "L"
    M = {{0.0, 1.0, 0.0, 0.0}, {0.1, 0.0}, {0.45, 0.9}, {0.8, 0.0}, {0.9, 0.0}, {0.9, 1.0}}, -- "M"
    N = {{0.0, 1.0, 0.0, 0.0}, {0.7, 1.0}, {0.7, 0.0}}, -- "N"
    O = {{0.35, 1.0, 0.15, 0.9}, {0.0, 0.6}, {0.0, 0.4}, {0.1, 0.2}, {0.35, 0.05}, {0.55, 0.05}, {0.8, 0.2}, {0.9, 0.4}, {0.9, 0.6}, {0.8, 0.8}, {0.6, 1.0}, {0.35, 1.0}}, -- "O"
    P = {{0.0, 1.0, 0.0, 0.0}, {0.45, 0.0}, {0.65, 0.1}, {0.7, 0.25}, {0.7, 0.35}, {0.6, 0.5}, {0.45, 0.55}, {0.0, 0.55}}, -- "P"
    Q = {{0.35, 1.0, 0.1, 0.85}, {0.0, 0.6}, {0.0, 0.4}, {0.1, 0.15}, {0.35, 0.0}, {0.55, 0.0}, {0.8, 0.15}, {0.9, 0.4}, {0.9, 0.6}, {0.8, 0.8}, {0.55, 1.0}, {0.35, 1.0}, {0.45, 0.75, 0.65, 0.8}, {0.75, 0.9}, {0.9, 1.0}}, -- "Q"
    R = {{0.0, 1.0, 0.0, 0.0}, {0.5, 0.0}, {0.7, 0.15}, {0.7, 0.35}, {0.6, 0.45}, {0.4, 0.5}, {0.6, 0.65}, {0.8, 1.0}, {0.0, 0.5, 0.4, 0.5}}, -- "R"
    S = {{0.0, 0.65, 0.1, 0.85}, {0.3, 1.0}, {0.45, 1.0}, {0.65, 0.85}, {0.7, 0.7}, {0.65, 0.55}, {0.45, 0.45}, {0.2, 0.4}, {0.05, 0.3}, {0.05, 0.15}, {0.25, 0.0}, {0.45, 0.0}, {0.6, 0.1}, {0.65, 0.25}}, -- "S"
    T = {{0.0, 0.0, 0.7, 0.0}, {0.35, 0.0, 0.35, 1.0}}, -- "T"
    U = {{0.0, 0.0, 0.0, 0.65}, {0.1, 0.85}, {0.3, 1.0}, {0.45, 1.0}, {0.65, 0.85}, {0.75, 0.65}, {0.75, 0.0}}, -- "U"
    V = {{0.0, 0.0, 0.4, 1.0}, {0.8, 0.0}}, -- "V"
    W = {{0.0, 0.0, 0.3, 1.0}, {0.6, 0.0}, {0.9, 1.0}, {1.2, 0.0}}, -- "W"
    X = {{0.0, 1.0, 0.8, 0.0}, {0.05, 0.0, 0.85, 1.0}}, -- "X"
    Y = {{0.0, 0.0, 0.4, 0.55}, {0.8, 0.0}, {0.4, 0.55, 0.4, 1.0}}, -- "Y"
    Z = {{0.1, 0.0, 0.7, 0.0}, {0.0, 1.0}, {0.7, 1.0}}, -- "Z"
    
    -- Lowercase letters
    ["a"] = {{0.05, 0.45, 0.2, 0.3}, {0.4, 0.3}, {0.55, 0.45}, {0.55, 0.8}, {0.6, 1.0}, {0.55, 0.75, 0.4, 0.9}, {0.2, 1.0}, {0.05, 0.9}, {0.0, 0.75}, {0.15, 0.6}, {0.35, 0.6}, {0.55, 0.5}}, -- "a"
    ["b"] = {{0.0, 1.0, 0.0, 0.0}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.35}, {0.55, 0.55}, {0.55, 0.7}, {0.45, 0.85}, {0.3, 1.0}, {0.15, 0.9}, {0.0, 0.7}}, -- "b"
    ["c"] = {{0.55, 0.45, 0.4, 0.3}, {0.2, 0.3}, {0.05, 0.45}, {0.0, 0.6}, {0.0, 0.7}, {0.05, 0.85}, {0.2, 1.0}, {0.40, 1.0}, {0.5, 0.85}, {0.55, 0.75}}, -- "c"
    ["d"] = {{0.55, 0.55, 0.4, 0.35}, {0.25, 0.3}, {0.1, 0.35}, {0.0, 0.55}, {0.0, 0.7}, {0.1, 0.9}, {0.25, 1.0}, {0.4, 0.9}, {0.55, 0.7}, {0.55, 1.0, 0.55, 0.0}}, -- "d"
    ["e"] = {{0.0, 0.6, 0.6, 0.6}, {0.55, 0.45}, {0.45, 0.35}, {0.3, 0.3}, {0.15, 0.35}, {0.05, 0.45}, {0.0, 0.6}, {0.05, 0.8}, {0.15, 0.9}, {0.3, 1.0}, {0.5, 0.9}, {0.6, 0.75}}, -- "e"
    ["f"] = {{0.0, 0.35, 0.4, 0.35}, {0.20, 1.05, 0.20, 0.15}, {0.25, 0.0}, {0.45, 0.05}}, -- "f"
    ["g"] = {{0.55, 0.55, 0.45, 0.35}, {0.3, 0.3}, {0.15, 0.35}, {0.05, 0.5}, {0.0, 0.65}, {0.05, 0.8}, {0.15, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.55, 0.75}, {0.55, 0.3, 0.55, 1.1}, {0.45, 1.25}, {0.3, 1.3}, {0.15, 1.25}, {0.05, 1.1}}, -- "g"
    ["h"] = {{0.0, 0.0, 0.0, 1.0}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.35}, {0.55, 0.55}, {0.55, 1.0}}, -- "h"
    ["i"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.15, 0.0, 0.05}}, -- "i"
    ["j"] = {{0.15, 0.05, 0.15, 0.15}, {0.15, 0.3, 0.15, 1.15}, {0.1, 1.25}, {0.0, 1.3}}, -- "j"
    ["k"] = {{0.0, 1.0, 0.0, 0.0}, {0.0, 0.7, 0.45, 0.3}, {0.2, 0.55, 0.5, 1.0}}, -- "k"
    ["l"] = {{0.0, 1.0, 0.0, 0.0}}, -- "l"
    ["m"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.4}, {0.45, 1.0}, {0.45, 0.45, 0.65, 0.3}, {0.85, 0.40}, {0.9, 0.55}, {0.9, 1.0}}, -- "m"
    ["n"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.40, 0.35}, {0.5, 0.5}, {0.5, 1.0}}, -- "n"
    ["o"] = {{0.0, 0.55, 0.1, 0.4}, {0.25, 0.3}, {0.4, 0.3}, {0.55, 0.4}, {0.6, 0.55}, {0.6, 0.7}, {0.55, 0.85}, {0.4, 1.0}, {0.25, 1.0}, {0.1, 0.9}, {0.0, 0.7}, {0.0, 0.55}}, -- "o"
    ["p"] = {{0.0, 1.25, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.35}, {0.55, 0.5}, {0.55, 0.7}, {0.5, 0.9}, {0.35, 1.0}, {0.2, 0.95}, {0.1, 0.85}, {0.0, 0.7}}, -- "p"
    ["q"] = {{0.55, 0.3, 0.55, 1.25}, {0.55, 0.7, 0.45, 0.9}, {0.35, 1.0}, {0.2, 1.0}, {0.05, 0.85}, {0.0, 0.7}, {0.0, 0.55}, {0.05, 0.4}, {0.2, 0.3}, {0.35, 0.3}, {0.5, 0.4}, {0.55, 0.55}}, -- "q"
    ["r"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.25, 0.3}, {0.35, 0.4}}, -- "r"
    ["s"] = {{0.0, 0.75, 0.1, 0.9}, {0.25, 1.0}, {0.45, 0.9}, {0.55, 0.8}, {0.45, 0.65}, {0.1, 0.55}, {0.0, 0.45}, {0.1, 0.35}, {0.25, 0.3}, {0.45, 0.35}, {0.5, 0.45}}, -- "s"
    ["t"] = {{0.0, 0.3, 0.3, 0.3}, {0.15, 0.05, 0.15, 0.85}, {0.2, 1.0}, {0.35, 0.9}}, -- "t"
    ["u"] = {{0.0, 0.3, 0.0, 0.8}, {0.1, 0.9}, {0.25, 1.0}, {0.4, 0.9}, {0.5, 0.75}, {0.5, 0.3, 0.5, 1.0}}, -- "u"
    ["v"] = {{0.0, 0.3, 0.3, 1.0}, {0.6, 0.3}}, -- "v"
    ["w"] = {{0.0, 0.3, 0.25, 1.0}, {0.45, 0.3}, {0.65, 1.0}, {0.9, 0.3}}, -- "w"
    ["x"] = {{0.0, 0.3, 0.6, 1.0}, {0.0, 1.0, 0.6, 0.3}}, -- "x"
    ["y"] = {{0.0, 0.3, 0.3, 1.05}, {0.55, 0.3, 0.3, 1.05}, {0.2, 1.25}, {0.05, 1.2}}, -- "y"
    ["z"] = {{0.0, 0.3, 0.55, 0.3}, {0.0, 1.0}, {0.6, 1.0}}, -- "z"



    -- Numbers
    ["0"] = {{0.0, 0.35, 0.0, 0.65}, {0.1, 0.85}, {0.25, 1.0}, {0.4, 1.0}, {0.5, 0.85}, {0.6, 0.65}, {0.6, 0.35}, {0.5, 0.15}, {0.35, 0.05}, {0.25, 0.05}, {0.1, 0.15}, {0.0, 0.35}}, -- "0"
    ["1"] = {{0.0, 0.3, 0.15, 0.2}, {0.3, 0.05}, {0.3, 1.05}}, -- "1"
    ["2"] = {{0.05, 0.3, 0.15, 0.1}, {0.3, 0.05}, {0.5, 0.15}, {0.55, 0.35}, {0.15, 0.75}, {0.0, 1.0}, {0.6, 1.0}}, -- "2"
    ["3"] = {{0.0, 0.7, 0.1, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.55, 0.75}, {0.55, 0.6}, {0.4, 0.45}, {0.25, 0.45}, {0.4, 0.4}, {0.5, 0.25}, {0.45, 0.1}, {0.3, 0.05}, {0.15, 0.05}, {0.05, 0.15}, {0.0, 0.25}}, -- "3"
    ["4"] = {{0.6, 0.7, 0.0, 0.7}, {0.45, 0.05}, {0.45, 1.0}}, -- "4"
    ["5"] = {{0.0, 0.75, 0.15, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.6, 0.7}, {0.6, 0.55}, {0.45, 0.4}, {0.3, 0.35}, {0.05, 0.5}, {0.15, 0.05}, {0.55, 0.05}}, -- "5"
    ["6"] = {{0.0, 0.6, 0.15, 0.45}, {0.3, 0.35}, {0.45, 0.4}, {0.55, 0.6}, {0.5, 0.8}, {0.35, 1.0}, {0.15, 0.9}, {0.05, 0.8}, {0.0, 0.55}, {0.05, 0.25}, {0.15, 0.1}, {0.3, 0.05}, {0.5, 0.1}, {0.55, 0.25}}, -- "6"
    ["7"] = {{0.0, 0.05, 0.6, 0.05}, {0.3, 0.4}, {0.2, 0.7}, {0.2, 1.0}}, -- "7"
    ["8"] = {{0.25, 0.05, 0.35, 0.05}, {0.5, 0.15}, {0.55, 0.3}, {0.45, 0.4}, {0.25, 0.45}, {0.05, 0.55}, {0.0, 0.7}, {0.1, 0.9}, {0.25, 1.0}, {0.4, 1.0}, {0.55, 0.9}, {0.6, 0.7}, {0.55, 0.55}, {0.35, 0.45}, {0.15, 0.4}, {0.05, 0.3}, {0.1, 0.15}, {0.25, 0.05}}, -- "8"
    ["9"] = {{0.05, 0.75, 0.15, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.55, 0.75}, {0.6, 0.45}, {0.55, 0.2}, {0.4, 0.05}, {0.2, 0.05}, {0.05, 0.2}, {0.0, 0.35}, {0.1, 0.55}, {0.25, 0.6}, {0.45, 0.55}, {0.58, 0.4}}, -- "9"

    -- Symbols
    ["'"] = {{0.0, 0.0, 0.0, 0.3}, {0.25, 0.0, 0.25, 0.3}}, -- Single quote
    ['"'] = {{0.3, 0, 0.3, 0.5}, {0.7, 0, 0.7, 0.5}}, -- Double quote
    [","] = {{0.05, 1.0, 0.0, 1.0}, {0.0, 0.9}, {0.05, 0.9}, {0.05, 1.1}, {0.0, 1.2}}, -- Comma
    ["."] = {{0.05, 1.0, 0.0, 1.0}, {0.0, 0.9}, {0.05, 0.9}, {0.05, 1.0}}, -- Period
    [";"] = {{0.05, 1.0, 0.0, 1.0}, {0.0, 0.9}, {0.05, 0.9}, {0.05, 1.1}, {0.0, 1.2}, {0.0, 0.35, 0.05, 0.35}, {0.05, 0.4}, {0.0, 0.4}, {0.0, 0.35}}, -- Semicolon
    [":"] = {{0.0, 0.9, 0.05, 0.9}, {0.05, 1.0}, {0.0, 1.0}, {0.0, 0.9}, {0.0, 0.35, 0.05, 0.35}, {0.05, 0.4}, {0.0, 0.4}, {0.0, 0.35}}, -- Colon
    ["("] = {{0.25, 0.0, 0.1, 0.25}, {0.0, 0.5}, {0.0, 0.75}, {0.1, 1.05}, {0.25, 1.25}}, -- Left parenthesis
    [")"] = {{0.0, 1.25, 0.15, 1.05}, {0.25, 0.75}, {0.25, 0.5}, {0.15, 0.25}, {0.0, 0.0}}, -- Right parenthesis
    ["/"] = {{0.0, 1.0, 0.3, 0.0}}, -- Forward slash
    ["\\"] = {{0.0, 0.0, 0.3, 1.0}}, -- Backslash
    ["?"] = {{0.0, 0.25, 0.15, 0.05}, {0.3, 0.0}, {0.5, 0.1}, {0.55, 0.3}, {0.4, 0.45}, {0.3, 0.6}, {0.3, 0.7}, {0.3, 0.9, 0.3, 1.0}}, -- Question mark
    ["!"] = {{0.1, 1.0, 0.1, 0.9}, {0.1, 0.7, 0.1, 0.0}}, -- Exclamation mark
    ["="] = {{0.0, 0.65, 0.6, 0.65}, {0.0, 0.35, 0.6, 0.35}}, -- Equals sign
    ["-"] = {{0.0, 0.6, 0.35, 0.6}}, -- Dash
    ["_"] = {{0.0, 1, 0.7, 1}}, -- Underscore
    ["<"] = {{0.6, 0.85, 0.0, 0.5}, {0.6, 0.25}}, -- Less than
    [">"] = {{0.0, 0.25, 0.6, 0.5}, {0.0, 0.85}}, -- Greater than
    ["+"] = {{0.0, 0.5, 0.6, 0.5}, {0.3, 0.2, 0.3, 0.8}}, -- Greater than
    [" "] = {0,0.3},
    ["*"] = {{0.25, 0.0, 0.25, 1.0}, {0.0, 0.65, 0.25, 1.0}, {0.5, 0.65}},
    ["["] = {{0.25, 1.25, 0.0, 1.25}, {0.0, 0.0}, {0.25, 0.0}},
    ["]"] = {{0.0, 1.25, 0.25, 1.25}, {0.25, 0.0}, {0.0, 0.0}},
}


-- Convert text into vertical drawing points with customizable alignment
function textToPointsVertical(text, x, y, size, thickness)
    local points = {} 
    
    local lastPos = 0
    for i = #text, 1, -1  do 
        local char = text:sub(i, i)
        local shape = char_shapes[char] and char_shapes[char] or char_shapes["?"] -- Fallback for undefined characters
        
        local offset = lastPos > 0 and lastPos + 0.35*size or y
        if char == " " then 
            lastPos = offset + 0.25*size 
        else
            largestVal = 0
            for j = 1, #shape do
                val = #shape[j] == 4 and math.max(shape[j][1], shape[j][3]) or shape[j][1]
                if val > largestVal then largestVal = val end
            end
            for j = 1, #shape do 
                val1 = #shape[j] == 4 and shape[j][1] or shape[j-1][#shape[j-1]-1]
                val2 = #shape[j] == 4 and shape[j][2] or shape[j-1][#shape[j-1]]
                val3 = #shape[j] == 4 and shape[j][3] or shape[j][1]
                val4 = #shape[j] == 4 and shape[j][4] or shape[j][2]
            
                x1 = x + (val2) * size
                y1 = offset + (largestVal- val1) * size
                x2 = x + (val4) * size
                y2 = offset + (largestVal- val3) * size
                table.insert(points, {x1, y1, x2, y2})
            end 
            lastPos = offset + (largestVal) * size
        end
    end
    return points, lastPos    
end

-----------------
-- ACTIONS ------

function renameModulatorNames(track, modulationContainerPos)
    local ret, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
    if fxAmount == "0" then
        reaper.TrackFX_Delete(track, modulationContainerPos)
    end 
    
    function goTroughNames(counterArray, savedArray)
        for c = 0, fxAmount -1 do  
            local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c) 
            local renamed, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'renamed_name')
            local nameWithoutNumber = fxName:gsub(" %[%d+%]$", "")
            if not renamed or fxName == "" then
                _, nameWithoutNumber = reaper.TrackFX_GetFXName(track,fxIndex)
            end
            idCounter = "_" .. nameWithoutNumber -- enables to use modules starting with a number
            if not counterArray[idCounter] then 
                counterArray[idCounter] = 1
            else
                counterArray[idCounter] = counterArray[idCounter] + 1
            end
            if savedArray then
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'renamed_name',  nameWithoutNumber .. (savedArray[idCounter] > 1 and " [" .. counterArray[idCounter] .. "]" or "") )
            end
        end 
    end
    -- we go through names twice, first to see if there's more than 1 of a name, and if not we don't add a number
    local countNames = {}
    goTroughNames(countNames)
    local namesExtension = {}
    goTroughNames(namesExtension, countNames) 
end

function getModulatorModulesNameCount(track, modulationContainerPos, name, returnName)
    local _, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
    local nameCount = 0
    for c = 0, fxAmount -1 do  
        local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c) 
        local _, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'fx_name')
        if fxName:match(name) then
            nameCount = nameCount + 1
        end
    end
    return returnName and (name .. " " .. nameCount) or nameCount
end


function getModulationContainerPos(track)
    if track then
        local modulatorsPos = reaper.TrackFX_GetByName( track, "Modulators", false )
        if modulatorsPos ~= -1 then
            return modulatorsPos
        end
    end
    return false
end

-- add container and move it to the first slot and rename to modulators
function addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local modulatorsPos = reaper.TrackFX_GetByName( track, "Modulators", false )
    if modulatorsPos == -1 then
        --modulatorsPos = reaper.TrackFX_GetByName( track, "Container", true )
        modulatorsPos = reaper.TrackFX_AddByName( track, "Container", 0, -1 )
        --modulatorsPos = TrackFX_AddByName( track, "Container", modulatorsPos, -1 ) 
        ret, rename = reaper.TrackFX_SetNamedConfigParm( track, modulatorsPos, 'renamed_name', "Modulators" )
    end
    return modulatorsPos
end

function deleteModule(track, fxIndex, modulationContainerPos)
    if fxIndex then 
        if reaper.TrackFX_Delete(track, fxIndex) then
            local mappings = (parameterLinks and parameterLinks[tostring(fxIndex)]) and parameterLinks[tostring(fxIndex)] or {} 
            for i, map in ipairs(mappings) do  
                local mapFxIndex = map.fxIndex
                local mapParam = map.param
                disableParameterLink(track, mapFxIndex, mapParam)
            end
                
            renameModulatorNames(track, modulationContainerPos)
            selectedModule = false
        end
    end
end

function mapModulatorActivate(fxIndex, sliderNum, fxInContainerIndex, name)
    if not fxIndex or map == fxIndex then 
        map = false
        sliderNumber = false
    else 
        map = fxIndex
        mapName = name
        sliderNumber = sliderNum
        fxContainerIndex = fxInContainerIndex
    end
end

function renameModule(track, modulationContainerPos, fxIndex, newName)
    
    
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'renamed_name',  newName)
    renameModulatorNames(track, modulationContainerPos)
end

--[[
function insertLfoFxAndAddContainerMapping(track)
    reaper.Undo_BeginBlock()
    local modulatorsPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = select(2, reaper.TrackFX_GetNamedConfigParm(track, modulatorsPos, 'container_count')) + 1
    local parent_FX_count = reaper.TrackFX_GetCount(track)
    local position_of_container = modulatorsPos+1
    
     insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
     lfo_param = reaper.TrackFX_AddByName( track, 'LFO Modulator', false, insert_position )
     ret, rename = reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'renamed_name', "LFO " .. (lfo_param + 1) )
     
     if fxnumber < 0x2000000 then
        ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulatorsPos, 'container_map.add.'..tostring(lfo_param)..'.1' )
     else
        outputPos = 1
     end 
     reaper.TrackFX_SetOpen(track,fxnumber,true)
     
     
     reaper.Undo_EndBlock("Add modulator plugin",-1)
     return outputPos
end
]]

function insertContainerAddPluginAndRename(track, name, newName)
    reaper.Undo_BeginBlock()
    local modulationContainerPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = select(2, reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')) + 1
    local parent_FX_count = reaper.TrackFX_GetCount(track)
    local position_of_container = modulationContainerPos+1
    
    local insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
    local fxPosition = reaper.TrackFX_AddByName( track, name, false, insert_position )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'renamed_name', newName)--getModulatorModulesNameCount(track, modulationContainerPos, newName, true) )
    renameModulatorNames(track, modulationContainerPos)
    --[[if not paramNumber then paramNumber = 1 end
    if fxnumber < 0x2000000 then
       ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..tostring(fxPosition)..'.' .. paramNumber )
    else
       outputPos = paramNumber
    end ]]
    return modulationContainerPos, insert_position
end


function insertLocalLfoFxAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'JS: LFO Native Modulator', "LFO Native")
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.dir', 0)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertACSAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'JS: ACS Native Modulator', "ACS Native")
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dir', 0)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dblo', -60)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dbhi', 12)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.chan', 2)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.stereo', 1)
    
    --reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.visible', 1)
    
    reaper.TrackFX_SetNamedConfigParm( track, modulationContainerPos, 'container_nch', 4)
    reaper.TrackFX_SetNamedConfigParm( track, modulationContainerPos, 'container_nch_in', 4)
    --reaper.TrackFX_SetOpen(track,fxnumber,true)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertFXAndAddContainerMapping(track, name, newName, paramNumber)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, name, newName)
    -- I think we do not want to open the "original", as it opens the fx randomly on add
    --reaper.TrackFX_SetOpen(track,fxnumber,true) -- return to original focus 
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertGenericParamFXAndAddContainerMapping(track, fxIndex, newName, paramNumber, fxInContainerIndex)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, "Generic Parameter Modulator", newName)
    
    reaper.TrackFX_SetOpen(track,fxnumber,true) -- return to original focus 
    p = 1
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.mod.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.mod.baseline', 0 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.offset',0 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.scale',1 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.effect',fxInContainerIndex ) -- skal nok være relativ i container
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.param', paramNumber )
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end



function getModulatorNames(track, modulationContainerPos)
    if modulationContainerPos then
        local _, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
        local containerData = {}
        local fxIndexs = {}
        allIsCollabsed = true
        allIsNotCollabsed = true
        
        for c = 0, fxAmount -1 do  
            local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c)  
            local _, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'original_name')
            local renamed, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'renamed_name')
            local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
            
            if not renamed or fxName == "" or fxName == nil then 
                fxName = fxOriginalName
            end
            
            local isCollabsed = trackSettings.collabsModules[guid]
            --if not nameCount[fxName] then nameCount[fxName] = 1 else nameCount[fxName] = nameCount[fxName] + 1 end
            --table.insert(containerData, {name = fxName .. " " .. nameCount[fxName], fxIndex = tonumber(fxIndex)})
            table.insert(containerData, {name = fxName, fxIndex = tonumber(fxIndex), guid = guid, fxInContainerIndex = c, fxName = fxOriginalName})
            fxIndexs[fxIndex] = true
            if not isCollabsed then allIsCollabsed = false end
            if isCollabsed then allIsNotCollabsed = false end
        end
        return containerData, fxIndexs
    end
end

function getParameterLinkValues(track, fxIndex, param)
    local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.baseline')
    local ret, scale = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale')
    local ret, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.offset')
    return baseline, scale, offset
end

function disableParameterLink(track, fxnumber, paramnumber, newValue) 
    local baseline, scale, offset = getParameterLinkValues(track, fxnumber, paramnumber)
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.active',0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.active',0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.effect',-1 )
    if newValue == "CurrentValue" then
    
    elseif newValue == "MaxValue" then
        reaper.TrackFX_SetParamNormalized(track,fxnumber,paramnumber,baseline + scale + offset)
    else
        reaper.TrackFX_SetParamNormalized(track,fxnumber,paramnumber,baseline)-- + offset)
    end
end

function setParameterToBaselineValue(track, fxnumber, paramnumber) 
    local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline')
    reaper.TrackFX_SetParamNormalized(track,fxnumber,paramnumber,baseline)
end

function setBaselineToParameterValue(track, fxnumber, paramnumber) 
    local value = reaper.TrackFX_GetParamNormalized(track,fxnumber,paramnumber)
    --local range = max - min
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline', value)
    
end

function toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, newValue)
    if not newValue then
        setParameterToBaselineValue(track, fxIndex, param)  
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', 0 )
    else
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', 1 )
        setBaselineToParameterValue(track, fxnumber, param)  
    end
end

function mapParameterToContainer(track, modulationContainerPos, fxIndex, param)
    reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. param )
end

function deleteParameterFromContainer(track, modulationContainerPos, fxIndex, param)
    reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'param.' .. param .. '.container_map.delete' )
end

function setParamaterToLastTouched(track, modulationContainerPos,fxIndex, fxnumber, param, value, offsetForce, scaleForce, valueForce)
    if tonumber(fxnumber) < 0x2000000 then
       ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. sliderNumber )
    else
       -- could this be done in a better way? -- I need to get the position of the FX inside the container
       outputPos = sliderNumber -- this is the paramater in the lfo plugin 
       modulationContainerPos = fxContainerIndex
    end 
    local retParam, currentOutputPos = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.param')
    local retEffect, currentModulationContainerPos = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.effect')
    if (retParam and outputPos ~= currentOutputPos) or (retEffect and modulationContainerPos ~= currentModulationContainerPos) then 
        local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline')
    --    local ret, offset = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.offset')
    --    local ret, scale = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.scale')
    --    useOffset = offset
    --    useScale = scale
        value = tonumber(baseline) --+ tonumber(offset)
    end
    useOffset = offsetForce and offsetForce or useOffset
    useScale = scaleForce and scaleForce or useScale
    value = valueForce and valueForce or value
    
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.baseline', value )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.offset',useOffset and useOffset or 0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.scale',useScale and useScale or 1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.effect',modulationContainerPos )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.param', outputPos )
    
end


---------------------------------
----- AB SLIDER FUNCTIONS -------
---------------------------------
function disableAllParameterModulationMappingsByName(name, newValue)
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local params = {}
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        -- Iterate through all parameters for the current FX
        local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
        for p = 0, param_count - 1 do 
            _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local isParameterLinkActive = parameterLinkActive == "1"
            
            if isParameterLinkActive then
                local _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then
                    local _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline')
                    local _, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
                    local _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
                    local _, containerItemFxId = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkEffect, 'container_item.'..parameterLinkParam )
                    local _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                    
                    if parameterLinkName:match(name) then
                        --reaper.ShowConsoleMsg(newValue .. " - disabel " .. parameterLinkName .. " on " .. fx_name .. " param: " .. p .. "\n")
                        disableParameterLink(track, fxIndex, p, newValue) 
                    end
                end 
            end
            
        end
    end
end

function parameterWithNameIsMapped(name)
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        -- Iterate through all parameters for the current FX
        local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
        
        for p = 0, param_count - 1 do 
            local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local isParameterLinkActive = parameterLinkActive == "1"
            
            if isParameterLinkActive then
                _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then
                    _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
                    _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                    if parameterLinkName:match(name) then
                        return true
                    end
                end 
            end
            
        end
    end
    return false
end

function getTrackPluginsParameterLinkValues(name, clearType) 
    local plugin_values = {}
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
        if not fx_name:match("^Modulators") then 
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
            for param = 0, param_count - 1 do
                _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active')
                isParameterLinkActive = parameterLinkActive == "1"
                -- we ignore values that have parameter link activated
                if isParameterLinkActive then
                    _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.effect' )
                    if parameterLinkEffect ~= "" then
                        _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.param' )
                        _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                        if parameterLinkName:match(name) then
                            local baseline, scale, offset = getParameterLinkValues(track, fxIndex, param) 
                            
                            valueNormalized = clearType == "MinValue" and baseline + scale + offset or baseline + offset
                            table.insert(params, {
                                valueNormalized = valueNormalized
                            })
                        end
                    end
                else
                    local valueNormalized = reaper.TrackFX_GetParamNormalized(track, fxIndex, param)
                    --reaper.ShowConsoleMsg(param_name .. "\n")
                    -- Save parameter details
                    table.insert(params, {
                        valueNormalized = valueNormalized,
                        param = param,
                    })
                end
            
                -- Save FX details
                plugin_values[guid] = {
                    number = fxIndex,
                    parameters = params
                }
            end
        end 
    end
    return plugin_values
end

-- TODO: Support folders as well
function getTrackPluginValues(track, fx)
    -- Table to store plugin parameter values
    local plugin_values = {}
    
    function removeBeforeColon(input_string)
        -- Find the position of ": " in the string
        local colon_pos = string.find(input_string, ": ")
        if colon_pos then
            -- Return the substring starting after ": "
            return string.sub(input_string, colon_pos + 2)
        else
            -- If ": " is not found, return the original string
            return input_string
        end
    end
    
    -- Iterate through all FX on the track
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
        if not fx_name:match("^Modulators") then 
            local fx_name_simple = removeBeforeColon(fx_name)
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
            for param = 0, param_count - 1 do
                _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active')
                isParameterLinkActive = parameterLinkActive == "1"
                -- we ignore values that have parameter link activated
                if not isParameterLinkActive then
                    local valueNormalized = reaper.TrackFX_GetParamNormalized(track, fxIndex, param)
                    --reaper.ShowConsoleMsg(param_name .. "\n")
                    -- Save parameter details
                    table.insert(params, {
                        valueNormalized = valueNormalized,
                        param = param,
                    })
                end
            
                -- Save FX details
                plugin_values[guid] = {
                    name = fx_name_simple,
                    number = fxIndex,
                    parameters = params
                }
            end
        end 
    end
    return plugin_values
end

-- Function to compare two arrays of plugin values and log changes
function comparePluginValues(a_trackPluginStates, b_trackPluginStates, track, modulationContainerPos, fxIndex) 
    sliderNumber = 0
    local foundParameters = false
    -- Iterate over the plugins in the current values
    for fx, b_plugin in pairs(a_trackPluginStates) do
        local fx_number = b_plugin.number
        local a_plugin = b_trackPluginStates[fx]

        -- Check if plugin exists in both arrays
        if a_plugin then
            -- Compare plugin names
            if a_plugin.number == b_plugin.number then 
                --reaper.ShowConsoleMsg("2\n")
                -- Compare parameters
                for i, b_states in ipairs(b_plugin.parameters) do 
                    local b_param = b_states.param
                    local a_states = a_plugin.parameters[i]
                    local a_value = a_states.valueNormalized
                    local b_value = b_states.valueNormalized
                    -- Check if parameter exists in both plugins
                    if a_states then
                        --reaper.ShowConsoleMsg("3\n")
                        if a_value ~= b_value then
                        
                            local range = b_value - a_value
                            --reaper.ShowConsoleMsg(a_states.name  .. " - " .. b_param .. " - " .. tostring(a_value) .. " - " .. tostring(b_value) .. " - " .. range .. "\n")
                            --local max = a_states.max
                            --local min = a_states.min
                            --local range = (min and max) and max - min or 1 
                            setParamaterToLastTouched(track, modulationContainerPos, fxIndex, fx_number, b_param, a_value, 0, range, a_value)
                            foundParameters = true
                        end
                    end
                end
                
            end
        end
    end
    return foundParameters
end
        
        
        
        
-------------------------------------------
-------------------------------------------
-------------------------------------------



previousWasCollabsed = false

shape = 0
width = 0.5
steps = 4
inputTest = 0
n = 4
lastSelected = nil
map = false
follow = true

timeType = 0
noteTempo = 5
noteTempoValue = 1
hertz = 1
lfoWidth = 100
collabsWidth = 20



--hasModuleState, modulesState = reaper.GetProjExtState(0, stateName, "trackSettings.collabsModules")
--reaper.ShowConsoleMsg(hasModuleState  .. " - " .. modulesState)
--trackSettings.collabsModules = hasModuleState == 1 and unpickle(modulesState) or {}

parametersBaseline = {}
randomPoints = {25,3,68,94,45,70}
 
modulatorNames = {}
lastCollabsModules = {}
sliderNumber = 0

--sortAsType = true
--last_vertical = vertical

--vertical = reaper.GetExtState(stateName, "vertical") == "1"
--hidePlugins = reaper.GetExtState(stateName, "hidePlugins") == "1"
--hideParameters = reaper.GetExtState(stateName, "hideParameters") == "1"
--hideModules = reaper.GetExtState(stateName, "hideModules") == "1"
--partsHeight = tonumber(reaper.GetExtState(stateName, "partsHeight")) or 250

--openSelected = true
--includeModulators = true
--trackSelectionFollowFocus = reaper.GetExtState(stateName, "trackSelectionFollowFocus") == "1"
--showToolTip = reaper.GetExtState(stateName, "showToolTip") == "1"
--sortAsType = reaper.GetExtState(stateName, "sortAsType") == "1"



-------------------------------------------
-- KEY COMMANDS 
local function EachEnum(enum)
    local cache = {}
    
    local enum_cache = {}
    cache[enum] = enum_cache

    for func_name, func in pairs(reaper) do
      local enum_name = func_name:match(('^ImGui_%s_(.+)$'):format(enum))
      if enum_name then
        --table.insert(enum_cache, { func(), enum_name })
        enum_cache[func()] = enum_name
      end
    end
   -- table.sort(enum_cache, function(a, b) return a[1] < b[1] end)

    return enum_cache
end

local tableOfAllKeys = EachEnum('Key')

-- KEY COMMANDS 
local keyCommandSettingsDefault = {
    {name = "Undo", commands  = {"Super+Z"}},
    {name = "Redo", commands  = {"Super+Shift+Z"}},
    {name = "Delete", commands  = {"Super+BACKSPACE", "DELETE"}}, 
    {name = "Close", commands  = {"Super+W", "Alt+M"}},
  }

local keyCommandSettings = keyCommandSettingsDefault
if reaper.HasExtState(stateName,"keyCommandSettings") then
    keyCommandSettings = unpickle(reaper.GetExtState(stateName,"keyCommandSettings"))
end


local function checkKeyPress() 
    local text = ""
    for key, keyName in pairs(tableOfAllKeys) do
      if ImGui.IsKeyDown(ctx, key) then
        if keyName:find("Left") == nil and keyName:find("Right") == nil then
            text = isSuperPressed and text .. "Super+" or text
            text = isCtrlPressed and text .. "Ctrl+" or text
            text = isShiftPressed and text .. "Shift+" or text
            text = isAltPressed and text .. "Alt+" or text
            text = text .. string.upper(keyName)
            addKey = nil 
            return text
        end
      end
    end
end

local function addKeyCommand(index)
    local color = (reaper.time_precise()*10)%10 < 5 and colorOrange or colorGrey
    reaper.ImGui_TextColored(ctx, color, "Press Command")
    if reaper.ImGui_IsItemClicked(ctx) then addKey = nil end
    local newKeyPressed = checkKeyPress() 
    if newKeyPressed then
        table.insert(keyCommandSettings[index].commands, newKeyPressed)
        local keyCommandsAsStrings = getKeyCommandsAsStrings(keyCommandSettings) 
        reaper.SetExtState(stateName,"keyCommandSettings", pickle(keyCommandSettings), true)
    end
end

--test = ((((steps + 1) * (n - (n|0)))|0) / steps * 2 - 1)

local function getAllTrackFxParamValues(track,fxIndex)
    local data = {} 
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        for p = 0, paramCount do 
            local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local isParameterLinkActive = parameterLinkActive == "1"
            if isParameterLinkActive then
                _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then  
                    _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline') 
                    --_, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.offset')
                    --_, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
                    table.insert(data, baseline)
                end
            else 
                local value = reaper.TrackFX_GetParam(track,fxIndex,p)
                table.insert(data, value)
            end
        end
    end
    return data
end

local function setAllTrackFxParamValues(track,fxIndex, settings)
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        for p, val in ipairs(settings) do 
            local value = reaper.TrackFX_SetParam(track,fxIndex,p - 1, val)
        end
    end
end

local nativeLfoList = {"active","dir","phase","speed","strength","temposync","free","shape"}
local function getNativeLFOParamSettings(track,fxIndex) 
    local data = {} 
    for _, l in ipairs(nativeLfoList) do 
        local _, val = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.lfo.' .. l) 
        data[l] = val
    end 
    return data
end

local function setNativeLFOParamSettings(track,fxIndex, settings)  
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.baseline', 0.5)
    for key, val in pairs(settings) do 
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.lfo.' .. key, tonumber(val))  
    end 
end


    
local nativeAcsList = {"active","dir","strength","attack","release","dblo","dbhi","chan","stereo","x2","y2"}
local function getNativeACSParamSettings(track,fxIndex) 
    local data = {} 
    for _, l in ipairs(nativeAcsList) do 
        local _, val = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.acs.' .. l) 
        data[l] = val
    end 
    return data
end

local function setNativeACSParamSettings(track,fxIndex, settings) 
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.baseline', 0.5) 
    for key, val in pairs(settings) do 
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.acs.' .. key, tonumber(val))  
    end 
end

local function getAllDataFromParameter(track,fxIndex,p)
    local retValueName, valueName = reaper.TrackFX_GetFormattedParamValue(track,fxIndex,p)
    local _, name = reaper.TrackFX_GetParamName(track,fxIndex,p)
    local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
    local isParameterLinkActive = parameterLinkActive == "1" 
    local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
    
    local _, parameterModulationActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.active')
    local parameterModulationActive = isParameterLinkActive and parameterModulationActive == "1"
    
    local baseline = false
    local width = 0
    local offset = 0
    local direction = 0
    if isParameterLinkActive then
        _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
        if parameterLinkEffect ~= "" then 
            _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline') 
            _, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.offset')
            _, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
            _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
            if tonumber(width) >= 0 then
                direction = offset * 2 + 1
            else
                direction = math.abs(offset * 2) - 1
            end
            
            
            if tonumber(fxIndex) < 0x200000 then 
                _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                local colon_pos = parameterLinkName:find(":")
                if colon_pos then
                    parameterLinkName = parameterLinkName:sub(1, colon_pos - 1)
                end
            else
               ret, parameterLinkFXIndex = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_item.' .. parameterLinkEffect )
               --reaper.ShowConsoleMsg(tostring(ret) .. " - " ..name .. " - " .. parameterLinkFXIndex .. "\n")
               if ret then
                  _, parameterLinkName = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkFXIndex, 'renamed_name' )
               end
            end 
        end 
    else
        parameterLinkEffect = false
    end
    
    local trackEnvelope = reaper.GetFXEnvelope(track,fxIndex,p,false)
    if trackEnvelope then
        pointCount = reaper.CountEnvelopePoints(trackEnvelope)
        usesEnvelope = pointCount > 0
        if usesEnvelope then
            retval, envelopeValue, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate( trackEnvelope, playPos, 0, 0 )
        end
    else
        envelopeValue = false
        usesEnvelope = false
    end
    
    local value, min, max = reaper.TrackFX_GetParam(track,fxIndex,p)
    local valueNormalized = reaper.TrackFX_GetParamNormalized(track, fxIndex, p)
    if min ~= 0 or max ~= 1 and isParameterLinkActive then
        --_, fxName = reaper.TrackFX_GetFXName(track, fxIndex)
        
        --reaper.ShowConsoleMsg(fxName .. " : " .. name .. " : " .. min .. " : ".. max .. " : " .. tostring(baseline) .."\n")
        
    end
    
    return {param = p, name = name, value = value, valueNormalized = valueNormalized, min = min, max = max, baseline = tonumber(baseline), width = tonumber(width), offset = tonumber(offset), direction = direction,
    valueName = valueName, fxIndex = fxIndex, guid = guid,
    parameterModulationActive = parameterModulationActive, isParameterLinkActive = isParameterLinkActive, parameterLinkEffect = parameterLinkEffect,containerItemFxId = tonumber(containerItemFxId),
    usesEnvelope = usesEnvelope, envelopeValue = envelopeValue, parameterLinkParam = parameterLinkParam, parameterLinkName = parameterLinkName,
    }
end


local function getAllParametersFromTrackFx(track, fxIndex)
    local data = {} 
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        for p = 0, paramCount do
            table.insert(data, getAllDataFromParameter(track,fxIndex,p))
        end
    end
    return data
end


-------------------------------------------
----------CONTAINER FUNCTIONS--------------
-------------------------------------------

function get_fx_id_from_container_path(tr, idx1, ...) -- returns a fx-address from a list of 1-based IDs
  local sc,rv = reaper.TrackFX_GetCount(tr)+1, 0x2000000 + idx1
  for i,v in ipairs({...}) do
    local ccok, cc = reaper.TrackFX_GetNamedConfigParm(tr, rv, 'container_count')
    if ccok ~= true then return nil end
    rv = rv + sc * v
    sc = sc * (1+tonumber(cc))
  end
  return rv
end

function get_container_path_from_fx_id(tr, fxidx) -- returns a list of 1-based IDs from a fx-address
  if fxidx & 0x2000000 then
    local ret = { }
    local n = reaper.TrackFX_GetCount(tr)
    local curidx = (fxidx - 0x2000000) % (n+1)
    local remain = math.floor((fxidx - 0x2000000) / (n+1))
    if curidx < 1 then return nil end -- bad address

    local addr, addr_sc = curidx + 0x2000000, n + 1
    while true do
      local ccok, cc = reaper.TrackFX_GetNamedConfigParm(tr, addr, 'container_count')
      if not ccok then return nil end -- not a container
      ret[#ret+1] = curidx
      n = tonumber(cc)
      if remain <= n then if remain > 0 then ret[#ret+1] = remain end return ret end
      curidx = remain % (n+1)
      remain = math.floor(remain / (n+1))
      if curidx < 1 then return nil end -- bad address
      addr = addr + addr_sc * curidx
      addr_sc = addr_sc * (n+1)
    end
  end
  return { fxid+1 }
end


function fx_map_parameter(tr, fxidx, parmidx) -- maps a parameter to the top level parent, returns { fxidx, parmidx }
  local path = get_container_path_from_fx_id(tr, fxidx)
  if not path then return nil end
  while #path > 1 do
    fxidx = path[#path]
    table.remove(path)
    local cidx = get_fx_id_from_container_path(tr,table.unpack(path))
    if cidx == nil then return nil end
    local i, found = 0, nil
    while true do
      local rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_index",i))
      if not rok then break end
      if tonumber(r) == fxidx - 1 then
        rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_parm",i))
        if not rok then break end
        if tonumber(r) == parmidx then found = true parmidx = i break end
      end
      i = i + 1
    end
    if not found then
      -- add a new mapping
      local rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,"container_map.add")
      if not rok then return nil end
      r = tonumber(r)
      reaper.TrackFX_SetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_index",r),tostring(fxidx - 1))
      reaper.TrackFX_SetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_parm",r),tostring(parmidx))
      parmidx = r
    end
  end
  return fxidx, parmidx
end

--[[

-- example use
track = reaper.GetTrack(0,0);
id = get_fx_id_from_container_path(track, 2, 1, 2, 1) -- test hierarchy
fxidx,fxparm = fx_map_parameter(track,id,5)
env = reaper.GetFXEnvelope(track,fxidx,fxparm,true)
reaper.TrackList_AdjustWindows(true)

]]
-------------------------------------------
-------------------------------------------

function CheckFXParamsMapping(pLinks, track, fxIndex, isModulator)
    local numParams = reaper.TrackFX_GetNumParams(track, fxIndex)
    _, fxName = reaper.TrackFX_GetFXName(track, fxIndex)
    for p = 0, numParams - 1 do
        local _, linkActive = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "param." .. p .. ".plink.active")
        local _, modActive  = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "param." .. p .. ".mod.active") 
        local isLinkActive = linkActive == "1"
        local isModActive  = modActive == "1"
        if isLinkActive then 
            local _, linkFx = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' ) -- index of the fx that's linked. if outside modulation folder, it will be modulation folder index
            local _, linkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )  -- parameter of the fx that's linked. 
            local _, fxIndexInContainer = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'param.' .. linkParam .. '.container_map.fx_index')
            --local _, linkFxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'param.' .. linkParam .. '.container_map.hint_id')
            if isModulator then 
                linkFxIndex = tostring(get_fx_id_from_container_path(track, modulationContainerPos+1, linkFx + 1)) -- test hierarchy
            else
                _, linkFxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. fxIndexInContainer)
            end
            _, parameterLinkName = reaper.TrackFX_GetParamName(track, isModulator and tonumber(linkFxIndex) or tonumber(modulationContainerPos), tonumber(linkParam))
          
            local _, linkedName = reaper.TrackFX_GetParamName(track, fxIndex, p)
            if not pLinks[linkFxIndex] then pLinks[linkFxIndex] = {} end
            --if not parameterLinks[linkFx][linkParam][fxIndex] then 
              --  parameterLinks[linkFx][linkParam] = 0
            --end
            --parameterLinks[linkFx][linkParam] = parameterLinks[linkFx][linkParam] + 1 
            table.insert(pLinks[linkFxIndex], {fxIndex = fxIndex, param = p})
            
            --reaper.ShowConsoleMsg(pLinks[linkFxIndex][1].fxIndex .. " - " .. linkFxIndex .. " llo\n")
                
            --reaper.ShowConsoleMsg(fxName .. " - " ..parameterLinkName .. " -> " .. linkedName .. " - " .. linkFxIndex .. " - link FX index: " .. linkFx .. " - link FX param: " .. linkParam .. " - FX index in container: " .. fxIndexInContainer .. " - from mod con: " .. tostring(isModulator) .. "\n")
        end
    end 
    return pLinks
end

local function findParentContainer(fxContainerIndex)
    for i, container in ipairs(containers) do 
        if container.fxIndex == fxContainerIndex then
            if container.fxContainerIndex then
                return findParentContainer(container.fxContainerIndex)
            else  
                return fxContainerIndex
            end
        end
    end 
end



-- Function to get all plugins on a track, including those within containers
function getAllTrackFXOnTrack(track)
    
    --reaper.ShowConsoleMsg("\n\n")
    local plugins = {} -- Table to store plugin information
    local containersFetch = {} -- Table to store plugin information
    local pLinks = {} -- table to store all link parameters
    -- Helper function to get plugins recursively from containers
    local function getPluginsRecursively(track, fxContainerIndex, indent, fxCount, isModulator, fxContainerName)
        if fxCount then 
            for subFxIndex = 0, fxCount - 1 do
                local ret, fxIndex = reaper.TrackFX_GetNamedConfigParm( track, fxContainerIndex, "container_item." .. subFxIndex )
                local retval, fxName = reaper.TrackFX_GetFXName(track, fxIndex, "") -- Get the FX name'
                local retval, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "fx_name") -- Get the FX name
                local retval, container_count = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "container_count" )
                local isContainer = fxOriginalName == "Container" -- Check if FX is a container 
                local isEnabled = reaper.TrackFX_GetEnabled(track, fxIndex)
                local isOpen = reaper.TrackFX_GetOpen(track,fxIndex)
                local isFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                
                pLinks = CheckFXParamsMapping(pLinks, track, fxIndex, isModulator)
                
                table.insert(plugins, {fxIndex = fxIndex, name = fxName, isModulator = isModulator, indent = indent, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, isContainer = isContainer, base1Index = subFxIndex + 1, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
                if isContainer then
                    table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, isContainer = isContainer, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = subFxIndex + 1, indent = indent, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
                end
                
                if isContainer then
                    indent = indent + 1
                    getPluginsRecursively(track, fxIndex, indent, tonumber(container_count), isModulator, fxName)
                end
            end
        end
    end

    if track then
        -- Total number of FX on the track
        local totalFX = reaper.TrackFX_GetCount(track)
    
        -- Iterate through each FX
        for fxIndex = 0, totalFX - 1 do
            local retval, fxName = reaper.TrackFX_GetFXName(track, fxIndex, "") -- Get the FX name'
            local retval, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "fx_name") -- Get the FX name'
            local retval, container_count = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "container_count" )
            local isContainer = fxOriginalName == "Container" -- Check if FX is a container 
            local isModulator = fxName == "Modulators"
            local isEnabled = reaper.TrackFX_GetEnabled(track, fxIndex)
            local isOpen = reaper.TrackFX_GetOpen(track,fxIndex)
            local isFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
            
            pLinks = CheckFXParamsMapping(pLinks, track, fxIndex)
    
            -- Add the plugin information
            table.insert(plugins, {fxIndex = fxIndex, name = fxName, isContainer = isContainer, isModulator = isModulator, fxContainerName = "ROOT", base1Index = fxIndex + 1, indent = 0, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
            if isContainer then
                table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, isContainer = isContainer, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = fxIndex + 1, indent = indent, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
            end
            -- If the FX is a container, recursively check its contents
            if isContainer then
                local indent = 1 
                getPluginsRecursively(track, fxIndex, indent, tonumber(container_count), isModulator, fxName)
            end
        end
    end
    
    return plugins, pLinks
        
end



local function getAllMappingsOnTrack(track, modulationContainerPos)
    local data = {}
    if track then
        local numFX = reaper.TrackFX_GetCount(track) 
        for fxIndex = 0, numFX - 1 do
            data[fxIndex] = {}
            --CheckFXParams(data, track, fxIndex, parentFXIndex)
        end
    end
end


local function getAllTrackFXOnTrackSimple(track)
    local fxCount = reaper.TrackFX_GetCount(track)
    local data = {}
    for f = 0, fxCount-1 do
       _, name = reaper.TrackFX_GetFXName(track,f)
       table.insert(data, {number = f, name = name})
    end
    return data
end

function mapPlotColor()
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),colorMapDark)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),colorMapDark)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),colorMapDark)
end



function setToLastKnownValue(array)
    local result = reaper.new_array(plotAmount)
    for i = 1, #result do
        result[i] = array[#array]
    end
    return result
end



local function drawFaderFeedback(sizeW, sizeH, fxIndex, param, min, max, isCollabsed, fx)
    local sizeId = isCollabsed and (settings.vertical and 1 or 2) or ((trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 4 or 3)
    if not inputPlots then inputPlots = {}; time = {}; offset = {}; phase = {} end
    --aaa = lastCollabsModules
    --reaper.ShowConsoleMsg(tostring(isCollabsed) .. " - " .. fxIndex .. " - " .. tostring(lastCollabsModules[fxIndex]) .. "\n")
    --if not sizeW then 
    local sizeW, sizeH, plotAmount
    
    local valuesForPlotting = {
        {
          w = buttonWidth,
          h = buttonWidth/3, 
          p = 200
        },{
          w = 20,
          h = 20, 
          p = 50
        },{
          w = buttonWidth,
          h = buttonWidth/2, 
          p = 200
        },{
          w = buttonWidth*2,
          h = buttonWidth, 
          p = 400
        }, 
    }
    local sizeW = valuesForPlotting[sizeId].w
    local sizeH = valuesForPlotting[sizeId].h
    local plotAmount = valuesForPlotting[sizeId].p 
    
    -- ret, value = reaper.TrackFX_GetNamedConfigParm( track, modulatorsPos, 'container_map.get.' .. fxIndex .. '.2' )
    value = reaper.TrackFX_GetParamNormalized(track,fxIndex,param)
    
    for i = 1, #valuesForPlotting do 
        local idTimer = fx.guid.. i 
        local timerPlotAmount = valuesForPlotting[i].p
        
        if not inputPlots[idTimer] then 
            inputPlots[idTimer] = reaper.new_array(timerPlotAmount); 
            for t = 1, timerPlotAmount do 
                inputPlots[idTimer][t] = value
            end
        end
        if not time[idTimer] then time[idTimer] = ImGui.GetTime(ctx) end
        if not offset[idTimer] then offset[idTimer] = 1 end
        if not phase[idTimer] then phase[idTimer] = 0 end
        
        while time[idTimer] < ImGui.GetTime(ctx) do -- Create data at fixed 60 Hz rate
            inputPlots[idTimer][offset[idTimer]] = value -- math.cos(phase[idTimer])--value
            offset[idTimer] = (offset[idTimer] % timerPlotAmount) + 1
            --phase[idTimer] = phase[idTimer] + (offset[idTimer] * 0.1)
            time[idTimer] = time[idTimer] + (1.0 / 120.0)
        end
    end
    
    local isMapping = map == fxIndex
    
    local posX, posY = reaper.ImGui_GetCursorPos(ctx) 
    local toolTip = (sizeId == 1 or sizeId == 2) and "Click to map output" or (sizeId == 4 and "Click to make waveform small" or "Click to make waveform big")
    clicked = reaper.ImGui_Button(ctx, "##plotLinesButton" .. fxIndex ,sizeW,sizeH)
    local lineX, lineY = reaper.ImGui_GetItemRectMin(ctx)
    if settings.showToolTip then ImGui.SetItemTooltip(ctx, toolTip) end
     
    
    local id = fx.guid .. sizeId
    --[[
    -- attempt to write my own plotting, but gives the same result
    for i = 1, plotAmount do 
        local ip = inputPlots[id][i]
        local valRelative = sizeH * ip
        local timeRelative = sizeW * (i / plotAmount)
        local x1 = lineX + timeRelative
        local y1 = lineY + valRelative
        local x2 = x1
        local y2 = y2
        reaper.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2,colorWhite, 1)
    end
    ]]
    
    reaper.ImGui_SetCursorPos(ctx, posX, posY) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), isMapping and colorMap or colorLightBlue)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotLines(), colorWhite)
    
    reaper.ImGui_PlotLines(ctx, '##'..fxIndex, inputPlots[id], offset[id] - 1, nil, 0, 1, valuesForPlotting[sizeId].w, valuesForPlotting[sizeId].h)
    reaper.ImGui_PopStyleColor(ctx,2)
    --clicked = reaper.ImGui_IsItemClicked(ctx)
     
    --if reaper.ImGui_IsItemHovered(ctx) then
    --    reaper.ImGui_SetTooltip(ctx,toolTip)
    --end
    
    
    --

    return clicked
end

-- Function to add newlines after spaces, ensuring no line exceeds chunk_size
function addNewlinesAtSpaces(input_string, chunk_size)
    local result = {}
    local current_line = ""
    
    for word in input_string:gmatch("%S+") do
        -- Add the word to the current line
        if #current_line + #word + 1 <= chunk_size then
            -- Append word to current line (with space if it's not empty)
            current_line = current_line .. (current_line ~= "" and " " or "") .. word
        else
            -- Add current line to result and start a new line
            table.insert(result, current_line)
            current_line = word
        end
    end
    
    -- Add the last line
    if current_line ~= "" then
        table.insert(result, current_line)
    end
    
    -- Concatenate the lines with "\n"
    return table.concat(result, "\n")
end

function modulePartButton(name, tooltipText, sizeW, bigText, background, textSize)
    if settings.vertical then
        return titleButtonStyle(name, tooltipText, sizeW, bigText, background)
    else 
        return verticalButtonStyle(name, tooltipText, sizeW, bigText, background, textSize)
    end
end


function titleButtonStyle(name, tooltipText, sizeW, bigText, background)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),menuGreyHover)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),menuGreyActive)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and menuGrey or colorTransparent)
    local clicked = false
    if bigText then reaper.ImGui_PushFont(ctx, font2) end
    
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    if verticalName then
        name = name:upper():gsub(".", "%0\n")
    end
    
    if reaper.ImGui_Button(ctx,name, sizeW) then
        clicked = true
    end 
    if reaper.ImGui_IsItemHovered(ctx) and settings.showToolTip and tooltipText and tooltipText ~= "" then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorWhite)
        reaper.ImGui_SetTooltip(ctx,tooltipText )  
        reaper.ImGui_PopStyleColor(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx)
    if bigText then reaper.ImGui_PopFont(ctx) end
    if background then 
        local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
        local endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , endPosX, endPosY, colorGrey,4)
    end
    return clicked 
end


function verticalButtonStyle(name, tooltipText, sizeW, verticalName, background, textSize, hover)
    --ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),background and menuGreyHover or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),(background or hover) and menuGreyHover or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),background and menuGreyActive or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and menuGrey or colorTransparent)
    local clicked = false 
    
    reaper.ImGui_PushFont(ctx, font2)
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    
    local points, lastPos = textToPointsVertical(name,0, 0, textSize and textSize or 11, 3)
    
    if reaper.ImGui_Button(ctx, "##"..name,textSize and textSize +9 or 20, sizeW and sizeW or lastPos + 14) then
        clicked = true
    end 
    
    local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
    local text_pos_x = startPosX +4
    local text_pos_y = startPosY +6
    
    for _, line in ipairs(points) do
        reaper.ImGui_DrawList_AddLine(draw_list, text_pos_x + line[1], text_pos_y +line[2],  text_pos_x + line[3],text_pos_y+ line[4], 0xffffffff, 1.2)
    end 
    
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26) )  
    end
    reaper.ImGui_PopStyleColor(ctx,3)
    
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleVar(ctx)
    if background then
        
        startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
        endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , endPosX, endPosY, colorGrey,4)
    end
    return clicked 
end

function setToolTipFunc(text, color)
    if settings.showToolTip and text and #text > 0 then  
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorWhite) 
        ImGui.SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx)
    end
end

function setToolTipFunc2(text,color)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorWhite)  
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx,addNewlinesAtSpaces(text,26))
    reaper.ImGui_EndTooltip(ctx)
    reaper.ImGui_PopStyleColor(ctx)
end

function lastItemClickAndTooltip(tooltipText)
    local clicked
    if reaper.ImGui_IsItemHovered(ctx) then
        if settings.showToolTip then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26)) end
        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
            clicked = "right"
        end
        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
            clicked = "left"
        end
    end
    return clicked
end


function titleTextStyle(name, tooltipText, sizeW, background)
    if background then
        reaper.ImGui_PushFont(ctx, font2)
    end
    local clicked = false
    if not sizeW then sizeW = reaper.ImGui_CalcTextSize(ctx,name, 0,0) end
    reaper.ImGui_Text(ctx, name)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
    if mouseX >= minX - margin and mouseX <= minX + sizeW - margin and mouseY >= minY and mouseY <= maxY then
         if settings.showToolTip then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26)) end
         if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
             clicked = "right"
         end
         if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
             clicked = "left"
         end
    end

    if background then
        reaper.ImGui_PopFont(ctx)
    end
    return clicked 
end

------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
----------------------------------CUSTOM SLIDERS------------------------------------------------
------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------

local sliderGrabWidth = 2 
local sliderHeight = 20


function safePow(base, exp)
    -- Prevent issues with negative or zero base when using fractional exponents
    if base < 0 then return 0 end
    if base == 0 then return 0 end
    return base ^ exp
end

function getLogPosition(value, min, max, curve)
    local log_min = math.log(min)
    local log_max = math.log(max)
    local log_value = math.log(value)
    local position = (log_value - log_min) / (log_max - log_min)
    return position ^ (1 / (curve or 1))  -- Use ^ instead of math.pow
end

function scaleLog(position, min, max, curve)
    local log_min = math.log(min)
    local log_max = math.log(max)
    local curved = safePow(position, curve or 1)
    local log_value = log_min + (log_max - log_min) * curved
    local newVal = math.exp(log_value)
    --reaper.ShowConsoleMsg(tonumber(newVal) .. " - " .. curved .. "\n")
    
    return newVal --math.max(min, math.min(max, newVal))
end

function getPosXForLine(posXOffset, sliderWidthAvailable, value, sliderFlags, min, max)
    local relativeValue = (value - min) / (max - min)
    local logValue = sliderFlags and ((math.log(1 + 3999 * relativeValue) / math.log(4000))) or relativeValue
    --if logValue < min then logValue = min end
    --if logValue > max then logValue = max end
    local val = posXOffset +  logValue * sliderWidthAvailable
    if val < posXOffset then val = posXOffset end
    if val > posXOffset + sliderWidthAvailable then val = posXOffset + sliderWidthAvailable end
    return val
end

function getPosXForLineNormalized(posXOffset, sliderWidthAvailable, value)
    --if logValue < min then logValue = min end
    --if logValue > max then logValue = max end
    local val = posXOffset + value * sliderWidthAvailable
    if val < posXOffset then val = posXOffset end
    if val > posXOffset + sliderWidthAvailable then val = posXOffset + sliderWidthAvailable end
    return val
end


function nativeReaperModuleParameter(track, fxIndex, paramOut,  _type, paramName, visualName, min, max, divide, valueFormat, sliderFlags, checkboxFlipped, dropDownText, dropdownOffset,tooltip, width, resetValue) 
    local buttonId = fxIndex .. paramName
    local faderWidth = width / 2  
    local nameOnSideWidth = faderWidth - 8
    local range = max - min
    local faderResolution = faderWidth / range
    local sliderWidthAvailable = (faderWidth - (sliderGrabWidth) - 4) 
    local colorPos = colorBrightBlue
    local valueColor = colorWhite
    local textColor = colorWhite
    local name = visualName
    
    
    local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName) 
    if ret and tonumber(currentValue) then
        valueFormat = (ret and tonumber(currentValue)) and string.format(valueFormat, tonumber(currentValue)) or ""
        
    --function nativeReaperModuleParameter(nameOnSide, buttonId, currentValue,  min, max, divide, valueFormat, sliderFlags, width, _type, colorPos, p, resetValue)
        reaper.ImGui_InvisibleButton(ctx, "slider" .. buttonId, faderWidth, sliderHeight) 
        
        if reaper.ImGui_IsItemHovered(ctx) then
            if not dragKnob then 
                dragKnob = buttonId
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y
                if not isMouseDown then 
                    setToolTipFunc("Set " .. name .. "\n - press Shift for fine resolution")
                end
            end  
        end
         
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local posXOffset = minX + sliderGrabWidth /2 + 2 
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
        
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        if not canBeMapped then
            reaper.ImGui_SameLine(ctx)
            if textButtonNoBackgroundClipped(visualName, textColor,nameOnSideWidth) and resetValue then 
                if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, resetValue/divide) end 
            end
        end
        
        endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
        parEndPosX, parEndPosY = reaper.ImGui_GetItemRectMax(ctx)
        
        drawCustomSlider(valueFormat, valueColor, colorPos, currentValue, posXOffset, minX, minY, maxX, maxY, sliderWidthAvailable, sliderFlags,  min, max, sliderGrabWidth)
        
        if dragKnob and dragKnob == buttonId then
            local amount
            local changeResolution = isShiftPressed and faderResolution * 10 or faderResolution
            if isMouseDown then 
                valueChange = ((mouse_pos_x - mouseDragStartX)) / changeResolution
                if sliderFlags then
                    local curve = 0.5 
                    local valueNormalized = getLogPosition(currentValue, min, max, curve)
                    local changeRelative = (valueChange * 4) / sliderWidthAvailable
                    local newVal = valueNormalized + changeRelative
                    amount = scaleLog(newVal, min, max, curve)
                else
                    amount = currentValue + ((mouse_pos_x - mouseDragStartX)) / changeResolution
                end 
                
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y 
            elseif isAltPressed and scrollVertical and scrollVertical ~= 0 then
                amount = currentValue + - scrollVertical / changeResolution
            else
                dragKnob = nil
            end
            if amount then 
                
                if amount < min then amount = min end
                if amount > max then amount = max end 
                if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, amount/divide) end  
            end
            
            ignoreScrollHorizontal = true
        end
    end
    
    --[[
    local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)
    if ret and currentValue then 
        scrollValue = nil
        --reaper.ImGui_Text(ctx,visualName)
        --visualName = ""
        reaper.ImGui_SetNextItemWidth(ctx,buttonWidth)
        if _type == "Checkbox" then
            ret, newValue = reaper.ImGui_Checkbox(ctx, visualName .. "##" .. paramName .. fxIndex, currentValue == (checkboxFlipped and "0" or "1"))
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue and (checkboxFlipped and "0" or "1") or (not checkboxFlipped and "0" or "1")) end
            scrollValue = 1
        elseif _type == "SliderDouble" then 
            -- this could probably be unified
            if useFineFaders then
                ret, newValue = pluginParameterSlider(currentValue, fxIndex .. paramName, visualName, min, max, divide, valueFormat, sliderFlags, buttonWidth, "Double", colorBrightBlueTransparent, {})
            else
            -- was the usual slider.
                reaper.ImGui_PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 2) 
            ret, newValue = reaper.ImGui_SliderDouble(ctx, visualName .. '##' .. paramName .. fxIndex, currentValue*divide, min, max, valueFormat, sliderFlags)
                reaper.ImGui_PopStyleVar(ctx)
            end
            
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue/divide) end  
        elseif _type == "Combo" then 
            ret, newValue = reaper.ImGui_Combo(ctx, visualName .. '##' .. paramName .. fxIndex, tonumber(currentValue)+dropdownOffset, dropDownText )
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue-dropdownOffset) end
            scrollValue = divide
        end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end
        scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, 'param.'..paramOut..'.' .. paramName, scrollValue)
        
    end
    return newValue and newValue or currentValue
    ]]
end

function drawCustomSlider(valueFormat, valueColor, colorPos ,currentValue, posXOffset, minX, minY, maxX, maxY, sliderWidthAvailable, sliderFlags, min, max, sliderGrabWidth,hasLink, linkValue, linkWidth, baseline, direction)
    -- background
    reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, minY, maxX, maxY, colorAlmostBlack, 2) 
    
    local posX = getPosXForLine(posXOffset, sliderWidthAvailable, currentValue, sliderFlags, min, max)
    -- baseline value
    reaper.ImGui_DrawList_AddLine(draw_list, posX, minY+2, posX, maxY-2, colorPos,sliderGrabWidth)
    
    if hasLink then  
        local widthColor = linkWidth >= 0 and colorBlueTransparent or colorMapLightTransparent
        local initialValue = baseline + (direction == -1 and - math.abs(linkWidth) or (direction == 0 and - math.abs(linkWidth)/2 or 0))
        
        local posX1 = getPosXForLineNormalized(posXOffset, sliderWidthAvailable, initialValue)
        local posX2 = getPosXForLineNormalized(posXOffset, sliderWidthAvailable, initialValue + math.abs(linkWidth)) --getPosXForLine(posXOffset, sliderWidthAvailable, initialValue + linkWidthAsValue, sliderFlags, min, max)
        -- width bar below
        reaper.ImGui_DrawList_AddLine(draw_list, posX1, maxY-2, posX2, maxY-2, widthColor,2)
        
        
        local posX = getPosXForLine(posXOffset, sliderWidthAvailable, linkValue, sliderFlags, min, max)
        -- playing value
        reaper.ImGui_DrawList_AddLine(draw_list, posX, minY+2, posX, maxY-2, colorMapLittleTransparent,sliderGrabWidth)
    end
    
    
    local textW = reaper.ImGui_CalcTextSize(ctx, valueFormat, 0, 0)
    -- value text
    reaper.ImGui_DrawList_AddText(draw_list, posXOffset + sliderWidthAvailable/2 - textW/2, minY+2, valueColor, valueFormat)
end

function textButtonNoBackgroundClipped(text, color, width, id)
    local click = false
    id = id and id or ""
    if reaper.ImGui_InvisibleButton(ctx, "##".. text .. id,width, 20) then
        click = true
    end 
    local p0_x, p0_y = ImGui.GetItemRectMin(ctx)
    local p1_x, p1_y = ImGui.GetItemRectMax(ctx)
    ImGui.PushClipRect(ctx, p0_x, p0_y, p1_x, p1_y, true)
    reaper.ImGui_DrawList_AddText(draw_list, p0_x, p0_y+2, color, text) 
    ImGui.PopClipRect(ctx) 
    return click
end

function pluginParameterSlider(moduleId,nameOnSide, buttonId, currentValue,  min, max, divide, valueFormat, sliderFlags, width, _type, colorPos, p, showingMappings, resetValue, genericModulatorOutput, parametersWindow, dontShowName)
    local divide = divide or 1
    local range = max - min
    
    local isParameterLinkActive = p.isParameterLinkActive
    local parameterModulationActive = p.parameterModulationActive
    local hasLink = isParameterLinkActive and parameterModulationActive
    
    local parameterLinkEffect = p.parameterLinkEffect
    
    local linkValue = p.valueNormalized -- p.value 
    local linkOffset = p.offset
    local linkWidth = p.width or 1
    local fxIndex = p.fxIndex
    local param = p.param
    local valueName = p.valueName
    local parameterLinkName = p.parameterLinkName 
    local name = p.name and p.name or "NA"
    local areaWidth = width
    local faderWidth = nameOnSide and width / 2 or width
    local sliderWidthAvailable = (faderWidth - (sliderGrabWidth) - 4)
    local nameOnSideWidth = faderWidth - 8
    
    local valueNormalized = p.valueNormalized
    local direction = p.direction
    local padColor = parameterModulationActive and colorMap or colorMapLightTransparent
    
    local parStartPosX, parStartPosY, parEndPosX, parEndPosY
    
    local startPosX, startPosY = reaper.ImGui_GetCursorPos(ctx)
    local faderResolution = sliderWidthAvailable --/ range
    
    local currentValue = p.usesEnvelope and p.envelopeValue or ((parameterLinkEffect and parameterModulationActive) and p.baseline or p.value) 
    local currentValueNormalized = (currentValue - min) / range
    
    local baseline = currentValueNormalized--(p.baseline and p.baseline or currentValue ) / range
    
    local canBeMapped = map and (not isParameterLinkActive or (isParameterLinkActive and mapName ~= parameterLinkName)) 
    -- if we map from a generic modulator
    local isGenericOutput = param == genericModulatorOutput
    local mapOutput = genericModulatorOutput == -1
    -- we check if any overlay is active
    local overlayActive = canBeMapped or mapOutput or (hideParametersFromModulator == p.guid)
    
    local textColor = overlayActive and colorGrey or colorWhite
    local valueColor = textColor
    if (paramnumber ~= param and not nameOnSide and parametersWindow) then
        textColor = colorGrey
    end
    
    -- we overwrite text and value color if it's a generic modulator output
    if isGenericOutput then
        valueColor = colorBlue
        textColor = colorBlue
        overlayActive = false
    end
    
    if name == "Phase" then 
        --reaper.ShowConsoleMsg(tostring(p.baseline) .. "\n")
    end
    
    -- for hiding parameters
    if hideParametersFromModulator and hideParametersFromModulator == p.guid then
        if not trackSettings.hideParametersFromModulator then trackSettings.hideParametersFromModulator = {} end
        if not trackSettings.hideParametersFromModulator[p.guid] then trackSettings.hideParametersFromModulator[p.guid] = {} end
    end
    
    local showName = type(nameOnSide) == "string" and nameOnSide or name
    
    function drawModulatorDirection(size, direction, width, track, fxIndex, param, buttonId, offsetX, offsetY) 
        local pad = 4
        local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, curPosX + offsetX, curPosY + offsetY)
        if reaper.ImGui_InvisibleButton(ctx, "##direction" .. buttonId, size - pad*2,size) then
            if direction == -1 then
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  -0.5)
            elseif direction == 1 then
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  width < 0 and 0 or -1)
            else 
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  width < 0 and -1 or 0)
            end 
        end
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
        minX = minX + pad / 2
        minY = minY + pad
        size = size - pad * 2
        local angle = 4
        local color = colorMap
        -- vertical line
        reaper.ImGui_DrawList_AddLine(draw_list, minX + size/2, minY, minX + size/2, minY+size, color)
        -- top arrow
        if direction >= 0 then
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size/angle, minY + size / angle, minX + size/2, minY, color)
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size-size/angle, minY + size / angle, minX + size/2, minY, color)
        end
        -- bottom arrow
        if direction <= 0 then
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size/angle, minY + size - size / angle, minX + size/2, minY+size, color)
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size-size/angle, minY + size - size / angle, minX + size/2, minY + size, color)
        end
        -- base line
        local lineOffset = size / math.abs(direction+1)/2 
        --reaper.ImGui_DrawList_AddLine(draw_list, minX+size/angle*1.2, minY + lineOffset, minX + size - size/angle*1.2, minY + lineOffset, color) 
    end
    
    function modulatorMappingItems()
        if isParameterLinkActive then
            local nameForText = showingMappings and p.name or parameterLinkName
            local toolTipText = (parameterModulationActive and 'Disable' or 'Enable') .. ' "' .. parameterLinkName .. '" parameter modulation of ' .. p.name
            local ret, newValue = reaper.ImGui_Checkbox(ctx, "##enable" .. buttonId, parameterModulationActive)
            if ret and param > -1 then
                toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, newValue)
                ignoreScroll = true
            end 
            if not overlayActive then setToolTipFunc(toolTipText) end
            
            if showingMappings then 
                parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
            end
            
            if not overlayActive or (overlayActive and not showingMappings) then
                if parameterModulationActive then
                    reaper.ImGui_SameLine(ctx)
                    local overlayText = isMouseDown and "Width\n" .. math.floor(linkWidth * 100) .. "%"
                    if specialButtons.knob(ctx, "width" .. buttonId .. moduleId, -8, 0, 20,linkWidth / 2 + 0.5, overlayText, nil, 2, 0, colorBlue) then
                        if parameterModulationActive and not dragKnob then
                            dragKnob = "width" .. buttonId .. moduleId
                            mouseDragStartX = mouse_pos_x
                            mouseDragStartY = mouse_pos_y
                            if not isMouseDown then  
                                if not overlayActive then setToolTipFunc("Width: " .. math.floor(linkWidth * 100) .. "%") end
                                --reaper.ImGui_SetTooltip(ctx, parameterLinkName .. " width: " ..)
                            end
                        end 
                    end
                    reaper.ImGui_SameLine(ctx)
                    drawModulatorDirection(20, p.direction, p.width, track, fxIndex, param, buttonId, -8,0)
                    if not overlayActive then  
                        local curDir = directions[p.direction+2]
                        -- TODO: maybe make a relative pos or find closest
                        if curDir then
                            setToolTipFunc("Direction: " .. curDir .. "\nClick to change")
                        end
                    end
                end
                reaper.ImGui_SameLine(ctx)
                local cutX = reaper.ImGui_GetCursorPos(ctx) + (showingMappings and 8 or 0)
                local showingWidth = areaWidth - 20 > cutX and areaWidth - cutX or 20
                if reaper.ImGui_InvisibleButton(ctx,"##" .. nameForText .. buttonId, showingWidth, 20) then
                    toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, not newValue)
                    ignoreScroll = true
                end
                local p0_x, p0_y = ImGui.GetItemRectMin(ctx)
                local p1_x, p1_y = ImGui.GetItemRectMax(ctx)
                ImGui.PushClipRect(ctx, p0_x-2, p0_y, p1_x, p1_y, true)
                reaper.ImGui_DrawList_AddText(draw_list, p0_x-2, p0_y+2, padColor, nameForText) 
                ImGui.PopClipRect(ctx)
                if not overlayActive then setToolTipFunc(toolTipText) end
            end
        end
    end
    
    
    if overlayActive then reaper.ImGui_BeginDisabled(ctx) end
    
    if showingMappings then
        modulatorMappingItems()
    else
        if not nameOnSide and not dontShowName then   
            reaper.ImGui_SetNextItemAllowOverlap(ctx)
            textButtonNoBackgroundClipped(not overlayActive and showName or "  ", textColor, faderWidth)
            parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        end
    end
    
    reaper.ImGui_InvisibleButton(ctx, "slider" .. buttonId .. moduleId, faderWidth, sliderHeight)
    if not nameOnSide and dontShowName then 
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
    end
    
    
    if reaper.ImGui_IsItemHovered(ctx) then
        if not dragKnob then 
            dragKnob = "bassline" .. buttonId .. moduleId
            mouseDragStartX = mouse_pos_x
            mouseDragStartY = mouse_pos_y
            if not isMouseDown then 
                setToolTipFunc("Set baseline of " .. name .. "\n - hold Shift for fine resolution\n - hold Ctrl to change width\n - hold Alt and scroll to change value\n - right click for more options")
            end
        end  
    end
    
    
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local posXOffset = minX + sliderGrabWidth /2 + 2
    
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    
    if nameOnSide and not dontShowName then
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        if not overlayActive then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetNextItemAllowOverlap(ctx)
            if textButtonNoBackgroundClipped(showName, textColor, nameOnSideWidth) and resetValue then
            --if reaper.ImGui_Button(ctx, showName, nameOnSideWidth) and resetValue then
                setParam(track, p, resetValue)
                ignoreFocusBecauseOfUiClick = true
                ignoreScroll = true
            end
        end
    end

    
    if not showingMappings then
        modulatorMappingItems()
    end
    
    
    endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
    parEndPosX, parEndPosY = reaper.ImGui_GetItemRectMax(ctx)
    
    
    --local ret, newValue = reaper.ImGui_DragInt(ctx, visualName .. '##' .. buttonId, currentValue*divide, (max - min) / width, min, max, valueFormat, sliderFlags)
    
    
    
    drawCustomSlider(valueFormat, valueColor, colorPos,currentValueNormalized, posXOffset, minX, minY, maxX, maxY, sliderWidthAvailable, sliderFlags, 0, 1, sliderGrabWidth,hasLink, linkValue, linkWidth, baseline, direction)
    
    -- Check if the mouse is within the button area
    
    if parStartPosX and mouse_pos_x >= parStartPosX and mouse_pos_x <= parStartPosX + areaWidth and
       mouse_pos_y >= parStartPosY and mouse_pos_y <= parEndPosY then
      if isParameterLinkActive and reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
          ImGui.OpenPopup(ctx, 'popup##' .. buttonId) 
      end
      
      if not nameOnSide and reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
          paramnumber = param
          -- THIS DOESN*T WORK YET I THINK
          --if not showingMappings then
              ignoreScroll = true
              ignoreFocusBecauseOfUiClick = true
          --end
      end
      
      if isParameterLinkActive then
          
          local hideCloseButton = false
          --if not isMouseDown then
          if dragKnob and isMouseDown then
              hideCloseButton = true
          end
          
          if not hideCloseButton and not overlayActive then
              if specialButtons.close(ctx,startPosX + areaWidth-18,startPosY,16,false,"remove" .. buttonId, valueColor, colorRedHidden,colorTransparent, colorTransparent) then
                  
                  disableParameterLink(track, fxIndex, param)
              end
              setToolTipFunc("Remove mapping")
          end
          --end
          --if settings.showToolTip and reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces("Remove mapping",26)) end
          
          
        end
    end
    
    local padW = 0
    local padH = 1
    if isParameterLinkActive then
        reaper.ImGui_DrawList_AddRect(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, padColor,4,nil,1)
    end
    --
    function setParam(track, p, amount)
        
        ignoreFocusBecauseOfUiClick = true
        ignoreThisIndex = p.fxIndex
        ignoreThisParameter = p.param
        
        if p.param and p.param > -1 then
            if p.usesEnvelope then
            -- write automation
            -- first read automation state
            -- then set to touch
            elseif p.parameterLinkEffect and p.parameterModulationActive then
                reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline', amount ) 
                local ret, newVal = reaper.TrackFX_GetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline') 
                return newVal 
                
            else 
                reaper.TrackFX_SetParam(track, p.fxIndex, p.param, amount)
                return reaper.TrackFX_GetParam(track, p.fxIndex, p.param)
            end
        end 
    end
    
    function setWidthValue()
        local amount
        if isMouseDown then
          
            amount = linkWidth + ((mouse_pos_x - mouseDragStartX) - (mouse_pos_y - mouseDragStartY)) / 100
            mouseDragStartX = mouse_pos_x
            mouseDragStartY = mouse_pos_y 
        elseif isAltPressed and scrollVertical and scrollVertical ~= 0 then
            amount = linkWidth + - scrollVertical / 100
        else
            dragKnob = nil
        end
        if amount then 
            if amount < -1 then amount = -1 end
            if amount > 1 then amount = 1 end 
            
            if amount < 0 then 
                if p.direction == -1 and linkOffset ~= 0 then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset', 0 )
                elseif p.direction == 1 and linkOffset ~= -1 then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset', -1 )
                end
            elseif amount >= 0 then
                if p.direction == -1 and linkOffset ~= -1 then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset', -1 )
                elseif p.direction == 1 and linkOffset ~= 0 then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset', 0 )
                end 
            end
            
            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.scale', amount )
            --reaper.ImGui_SetTooltip(ctx, parameterLinkName .. " width:\n" .. linkWidth * 100 .. "%")
        end
        
        ignoreScrollHorizontal = true
    end
    
    if hasLink then 
        if dragKnob and dragKnob == "width" .. buttonId .. moduleId then
            setWidthValue()
        end
    end
    
    if dragKnob and dragKnob == "bassline" .. buttonId .. moduleId then
        if isCtrlPressed then
            setWidthValue()
        else
            local amount
            local changeResolution = isShiftPressed and faderResolution * 10 or faderResolution
            if isMouseDown then 
                if reaper.ImGui_IsMouseClicked(ctx, 0) and nameOnSide then
                    --reaper.ShowConsoleMsg(faderResolution .. "\n")
                end
                amount = currentValueNormalized + ((mouse_pos_x - mouseDragStartX)) / changeResolution
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y 
            elseif isAltPressed and scrollVertical and scrollVertical ~= 0 then
                amount = currentValueNormalized + - scrollVertical / changeResolution
            else
                dragKnob = nil
                missingOffset = nil
                lastAmount = nil
            end
            if amount then 
                if amount < 0 then amount = 0 end
                if amount > 1 then amount = 1 end 
                if amount ~= currentValueNormalized then 
                    local addOffset = missingOffset and missingOffset or 0 -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference
                    local newVal = (amount + addOffset) * range + min
                    newAmount = setParam(track, p, newVal)
                    
                    newAmountRelative = newAmount and (newAmount - min) / range 
                    -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference to the next time
                    if lastAmount and lastAmount == amount then
                        missingOffset = amount - newAmountRelative + (missingOffset and missingOffset or 0)
                    else
                        missingOffset = 0
                    end
                    lastAmount = amount
                    -----
                end
            end
            
            ignoreScrollHorizontal = true
        end
    end
    
    -- MAPPING OVRELAY
    if overlayActive then 
        local overlayColor = (canBeMapped and not mapOutput) and colorMapLightTransparent or colorBrightBlueOverlay
        local borderColor = (canBeMapped and not mapOutput) and colorMapDark or colorBlue
        
        reaper.ImGui_EndDisabled(ctx)
        reaper.ImGui_SetCursorPos(ctx, startPosX,startPosY)
        local visualName = ("Use " .. name)
        if (canBeMapped and not mapOutput) then visualName = ("Map " .. name) end
        if (hideParametersFromModulator == p.guid) then 
            local hidden = trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[p.guid] and trackSettings.hideParametersFromModulator[p.guid][p.param]
            visualName = (hidden and "Hidding "  or "Showing ") .. name 
            if hidden then
                overlayColor = colorRedTransparent
                borderColor = colorRedHidden
            else
                overlayColor = colorGreenTransparent
                borderColor = colorGreen
            end
                
        end
        
        reaper.ImGui_InvisibleButton(ctx,  visualName .. "##map" .. buttonId,  areaWidth, endPosY - startPosY - 4)
        if ImGui.IsItemClicked(ctx) then
            paramnumber = param
            ignoreScroll = true
            if (canBeMapped and not mapOutput) then
                setParamaterToLastTouched(track, modulationContainerPos, map, fxIndex, param, p.valueNormalized, (mapName:match("LFO") ~= nil and (settings.defaultLFODirection - 3)/2 or (settings.defaultDirection - 3) / 2), settings.defaultMappingWidth / 100)
                if settings.mapOnce then map = false; sliderNumber = false end
                
            elseif mapOutput then
                mapParameterToContainer(track, modulationContainerPos, fxIndex, param)
            elseif hideParametersFromModulator == p.guid then
                trackSettings.hideParametersFromModulator[p.guid][p.param] = not trackSettings.hideParametersFromModulator[p.guid][p.param]
                saveTrackSettings(track)
            end
        end
        if parStartPosX then
            reaper.ImGui_DrawList_AddRectFilled(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, overlayColor,4,nil)
            reaper.ImGui_DrawList_AddRect(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, borderColor,4,nil,1)
            
            local textW = reaper.ImGui_CalcTextSize(ctx, visualName, 0, 0)
            -- value text
            reaper.ImGui_DrawList_AddText(draw_list, posXOffset + areaWidth/2 - textW/2, parStartPosY+2, colorWhite, visualName)
        end
    end
    
    
    if nameOnSide and isParameterLinkActive then
        
        reaper.ImGui_SetCursorPos(ctx, endPosX, endPosY)
        reaper.ImGui_Spacing(ctx)
    end
    --return ret, newValue
end




function hideShowEverything(track, newState)
    
    if modulatorNames  then
        for _, m in ipairs(modulatorNames) do trackSettings.collabsModules[m.guid] = newState end   
    end
    
    trackSettings.hidePlugins = newState
    trackSettings.hideParameters = newState
    trackSettings.hideModules = newState
    
    saveTrackSettings(track)
end

colorMap = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,1)
colorMapDark = reaper.ImGui_ColorConvertDouble4ToU32(0.7,0.2,0.2,1)
colorMapLight = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.65,0.65,1)
colorMapLightest = reaper.ImGui_ColorConvertDouble4ToU32(0.95,0.75,0.75,1)
colorMapLightTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.65,0.65,0.5)
colorMapLittleTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.9)
colorMapSemiTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.7)
colorMapMoreTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.4)
colorGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.4,0.4,1)
colorLightGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.6,0.6,0.6,1)
colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1,1)
colorAlmostWhite = reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8,1)
colorBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.4,0.8,1)
colorBrightBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,1)
colorBrightBlueTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,0.8)
colorBrightBlueOverlay = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,0.3)
colorBlueTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,0.5)
colorLightBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.4,0.8,0.5)
colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0,0)
semiTransparentGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3,0.2)
littleTransparentGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3,0.4)
menuGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.14,0.14,0.14,1)
menuGreyHover = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.30,0.30,1)
menuGreyActive = reaper.ImGui_ColorConvertDouble4ToU32(0.45,0.45,0.45,1)

colorBlack = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1)
colorAlmostBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1)
colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)

colorYellowMinimzed = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 188 / 255, 46 / 255, 0.7) -- 117 122 118
colorRedHidden = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 95 / 255, 88 / 255, 1)  -- 117 122 118
colorRedTransparent = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 95 / 255, 88 / 255, 0.3)  -- 117 122 118
colorGreen = reaper.ImGui_ColorConvertDouble4ToU32(39 / 255, 198 / 255, 65 / 255, 0.7)  -- 117 122 118
colorGreenTransparent = reaper.ImGui_ColorConvertDouble4ToU32(39 / 255, 198 / 255, 65 / 255, 0.3)  -- 117 122 118
colorDarkGreen = reaper.ImGui_ColorConvertDouble4ToU32(20 / 255, 100 / 255, 32 / 255, 0.7)  -- 117 122 118

function buttonTransparent(name, width,height) 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
    reaper.ImGui_Button(ctx,name, width,height)
    reaper.ImGui_PopStyleColor(ctx,3)
end

function mapButtonColor()
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMapSemiTransparent)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMap)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorMapLittleTransparent)
end

local function waitForWindowToClose(browserHwnd, callback)  
    -- we need this to ensure we cancel even if window is not "destroyed", eg. FX Browser seems to still be there after closing
    local visible = reaper.BR_Win32_IsWindowVisible(browserHwnd) 
    
    if (browserHwnd and visible) then 
        reaper.defer(function() waitForWindowToClose(browserHwnd, callback) end) 
    else
        callback()
        return true
    end
end

local function openFxBrowserOnSpecificTrack()
    local index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local trackTitleIndex = "Track " .. math.floor(index)
    local ret, name = reaper.GetTrackName(track)
    local addFXToTrackWindowName = "Add FX to " .. trackTitleIndex .. (name == trackTitleIndex and "" or (' "' .. name .. '"'))
    reaper.SetOnlyTrackSelected(track, true)
    
    -- check if window is already open, if it is we start by closing it
    local hwnd = reaper.JS_Window_Find(addFXToTrackWindowName, true) 
    local visible = reaper.BR_Win32_IsWindowVisible(hwnd)  
    if (hwnd and visible) then
        reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
    end
    
    reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
    return addFXToTrackWindowName, trackTitleIndex
end

function openCloseFx(track, fxIndex, open)  
    function closeParentContainerRecursive(track, fxIndex)
        if reaper.TrackFX_GetOpen(track,fxIndex) then
            local retval, parFxIndex = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "parent_container" )
            if retval and parFxIndex then 
                local fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,tonumber(parFxIndex))
                if fxIsFloating then
                    reaper.TrackFX_SetOpen(track,tonumber(parFxIndex),false)
                else
                    closeParentContainerRecursive(track, tonumber(parFxIndex))
                end
            else 
                local fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                if fxIsFloating then
                    reaper.TrackFX_SetOpen(track,fxIndex,false)
                else 
                    reaper.TrackFX_Show(track,fxIndex,0)   
                end
            end 
        end
    end
    if open then 
        -- opens floating window
        reaper.TrackFX_SetOpen(track,fxIndex,open)
    else 
        local fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
        if fxIsFloating then
            -- closes floating window
            reaper.TrackFX_SetOpen(track,fxIndex,open)
        else 
            -- check if window is in a container
            retval, parFxIndex = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "parent_container" )
            if retval and parFxIndex then
                -- if in container we try to close that one instead
                closeParentContainerRecursive(track, tonumber(parFxIndex))
            else
                -- else we close the window as we know it's the FX window
                reaper.TrackFX_Show(track,fxIndex,0)   
            end
        end
    end
    
end

        
function scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, nativeParameter, dropDownValue, min, max)
    if reaper.ImGui_IsItemHovered(ctx) and isAltPressed then 
        if scrollVertical ~= 0 then
            local newValue = dropDownValue and (nativeParameter and currentValue or (currentValue - (scrollVertical > 0 and dropDownValue or -1*dropDownValue))) or ( currentValue - (scrollVertical * divide/100 ))
            if newValue < min then newValue = min end
            if newValue > max then newValue = max end
            if nativeParameter then
                if dropDownValue then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, nativeParameter, newValue)
                else
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, nativeParameter,newValue)
                end
            else
                if dropDownValue then
                    setParameterNormalizedButReturnFocus( track, fxIndex, paramIndex, newValue)
                else
                    setParameterNormalizedButReturnFocus(track, fxIndex, paramIndex, newValue) 
                end
            end
        end
    end
end



function pluginParameterName(name, valueName, number)
    reaper.ImGui_Text(ctx,name ) -- .. "\n" .. valueName) 
    if not map and ImGui.IsItemClicked(ctx) then paramnumber = number end 
end



function parameterNameAndSliders(moduleId, func2, p, focusedParamNumber, infoModulationSlider, excludeName, showingMappings, nameOnSide, sizeOfFader, resetValue, valueAsString, genericModulatorOutput, parametersWindow) 
    local isParameterLinkActive = p.isParameterLinkActive
    local parameterModulationActive = p.parameterModulationActive
    local containerItemFxId = p.containerItemFxId
    local fxIndex = p.fxIndex
    local param = p.param
    local value = p.valueNormalized --p.value
    local valueNameInput = (p.valueName and p.valueName ~= "") and p.valueName or 0 -- got an error so this is a quick fix
    
    local valueName = valueAsString and ((valueAsString:match("%%") and tonumber(valueNameInput)) and string.format(valueAsString, tonumber(valueNameInput)) or valueAsString) or valueNameInput
    local min = p.min
    local max = p.max
    local usesEnvelope = p.usesEnvelope
    local parameterLinkEffect = p.parameterLinkEffect
    local parameterLinkName = p.parameterLinkName
    local name = p.name
    local envelopeValue = p.envelopeValue
    local baseline = p.baseline
    local linkOffset = p.offset
    local linkWidth = p.width
    local buttonId = fxIndex .. ":" .. param
    
     
    local inclosingX, inclosingY
    
    local mapVariable = false
    if map and (not isParameterLinkActive or (isParameterLinkActive and map ~= containerItemFxId)) then
        mapVariable = true 
        ImGui.SetNextItemAllowOverlap(ctx)
    end 
    local scrollBarOffset = 14
    local textSize = reaper.ImGui_CalcTextSize(ctx, "Offset", 0,0) + 10 
    local itemWidth = moduleWidth - 2 - textSize - scrollBarOffset
    local areaWidth = (infoModulationSlider) and moduleWidth-30 or moduleWidth - scrollBarOffset - 2
    
    local faderWidth = sizeOfFader and sizeOfFader or moduleWidth - scrollBarOffset --(sizeArray and sizeArray.faderWidth) and sizeArray.faderWidth or moduleWidth - scrollBarOffset
    local parameterMappingWidth = itemWidth
    
    if ImGui.BeginPopup(ctx, 'popup##' .. buttonId, nil) then
        if isParameterLinkActive then
            reaper.ImGui_TextColored(ctx, colorGrey, "Direction")
            for i, dir in ipairs(directions) do
                if reaper.ImGui_RadioButton(ctx, dir, p.direction == - (i - 2)) then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  linkWidth >= 0 and -(i - 1) / 2 or  (i - 3) / 2)
                end
            end
            
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_Button(ctx,"Remove ".. '"' ..  parameterLinkName .. '"' .. " modulator mapping##remove" .. buttonId) then
                disableParameterLink(track, fxIndex, param)
                doNotChangeOnlyMapped = true
                ImGui.CloseCurrentPopup(ctx)
            end 
            if reaper.ImGui_Button(ctx,"Open ".. '"' .. parameterLinkName .. '"' .. " modulator plugin##open" .. buttonId) then 
                reaper.TrackFX_SetOpen(track,fxnumber,true)   
                ImGui.CloseCurrentPopup(ctx)
            end 
            if reaper.ImGui_Button(ctx,"Show "..'"' .. name ..'"' .. " parameter modulation/link window##show" .. buttonId) then 
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.visible',1 )
                ImGui.CloseCurrentPopup(ctx)
            end
        end
        ImGui.EndPopup(ctx)
    end
    
    ImGui.BeginGroup(ctx)  
    
    
    local startPosX, startPosY = reaper.ImGui_GetCursorPos(ctx)
    reaper.ImGui_PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 2)  
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),colorMap) 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),semiTransparentGrey)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),semiTransparentGrey)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),semiTransparentGrey) 
    
    if infoModulationSlider then 
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(), parameterModulationActive and colorMapLightest or colorWhite)
    else
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(), param == focusedParamNumber and colorWhite or (parameterModulationActive and colorMapLightest or colorGrey))
    end
    
    
    local parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
    
    local posX, posY = reaper.ImGui_GetCursorPos(ctx)
    
    
     
    local sliderValue = usesEnvelope and envelopeValue or ((parameterLinkEffect and parameterModulationActive) and baseline or value) 
    if mapVariable then ImGui.SetNextItemAllowOverlap(ctx) end -- in order for the overlapping map button to take focus
    
    --if isAltPressed and sliderValue ~= 0 then reaper.ShowConsoleMsg(value .. " - "sliderValue .. "\n") end
    
    --pluginParameterSlider(visualName, buttonId, currentValue,  min, max, divide, valueFormat, sliderFlags, width, _type, colorPos, hasLink, linkValue, linkWidth)
    ImGui.SetNextItemWidth(ctx, faderWidth)
    if infoModulationSlider then
        ret, newValue = func2(track,fxIndex, infoModulationSlider, sliderValue, faderWidth)
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
    else
        ret, newValue = pluginParameterSlider(moduleId, nameOnSide, buttonId, sliderValue,min,max,nil, valueName, nil, faderWidth, "Double", colorBrightBlue, p, showingMappings, resetValue, genericModulatorOutput, parametersWindow, excludeName) 
    end
    
    
    reaper.ImGui_PopStyleColor(ctx,5) 
    ImGui.PopStyleVar(ctx)
    
    
    local endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
    
    
    reaper.ImGui_EndGroup(ctx)
    
end

function placingOfNextElement()
    if settings.vertical then
        reaper.ImGui_Spacing(ctx)
        --reaper.ImGui_Separator(ctx)
        --reaper.ImGui_Spacing(ctx)
    else
        reaper.ImGui_SameLine(ctx)
    end
end

---------------------------------------------------------------------------------------------------------------
-------------------------------------MODULES-------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

function createSliderForNativeLfoSettings(track,fxnumber,paramnumber,name,min,max,sliderFlag)
    reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)
    _, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.lfo.' .. name) 
    ret, value = reaper.ImGui_SliderDouble(ctx, name.. '##lfo' .. name .. fxnumber, currentValue, min, max, nil, sliderFlag)
    if ret then 
        reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.lfo.' .. name, value) 
    end
end


function createSlider2(track,fxIndex, info, currentValue, setSize) 
    local _type = info._type
    local paramIndex = info.paramIndex
    local name = info.name
    local min = info.min
    local max = info.max
    local divide = info.divide
    local valueFormat = info.valueFormat
    local sliderFlag = info.sliderFlag
    local checkboxFlipped = info.sliderFlag
    local dropDownText = info.dropDownText
    local dropdownOffset = info.dropdownOffset
    local tooltip = info.tooltip
    
    
    currentValue = currentValue and currentValue or reaper.TrackFX_GetParam(track, fxIndex, paramIndex)
    if _type == "SliderDoubleLogarithmic" then 
        currentValue2 = reaper.TrackFX_GetParam(track, fxIndex, paramIndex)
    end
    
    if currentValue then
        --buttonTransparent(name, dropDownSize )
        visualName = name
        scrollValue = nil
        if setSize then reaper.ImGui_SetNextItemWidth(ctx,setSize) end
        if _type == "SliderInt" then 
            --ret, val = reaper.ImGui_SliderInt(ctx,visualName.. '##slider' .. name .. fxIndex, math.floor(currentValue * divide), min, max, valueFormat) 
            ret, val = pluginParameterSlider(visualName, '##slider' ..name .. fxIndex, math.floor(currentValue * divide),min,max, nil,valueFormat, sliderFlags, setSize, "Int", colorBrightBlueTransparent, {})
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val/divide) end
        elseif _type == "SliderDouble" then --"%d"
            --ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, currentValue, min, max, valueFormat, sliderFlag)
            ret, val = pluginParameterSlider(visualName, '##slider' .. name .. fxIndex, currentValue, min, max, nil, valueFormat, sliderFlag, setSize, "Double", colorBrightBlueTransparent, {})
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
        elseif _type == "SliderDoubleLogarithmic" then --"%d"
        -- NOT USED AT THE MOMENT
            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, math.floor(min * 2.7183^currentValue), min, max, valueFormat, sliderFlag)
            if ret then 
            
            --reaper.ShowConsoleMsg(name .. " - " .. currentValue .. " - " .. currentValue2 .. " - " .. val ..  "\n")
            setParameterNormalizedButReturnFocus(track, fxIndex, paramIndex, math.log(val/min)) end
        elseif _type == "SliderDoubleLogarithmic2" then --"%d"
            --ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, (2.7183^currentValue), min, max, valueFormat, sliderFlag)
            --if ret then setParameterNormalizedButReturnFocus(track, fxIndex, paramIndex, math.log(val)) end
            ret, val = pluginParameterSlider(visualName, '##slider' .. name .. fxIndex, currentValue, min, max, nil, valueFormat, sliderFlag, setSize, "Double", colorBrightBlueTransparent, {})
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
        elseif _type == "SliderName" then --"%d"
            local hasSliderValueName, sliderValueName = reaper.TrackFX_FormatParamValue(track,fxIndex,paramIndex,currentValue)
            valueFormat = hasSliderValueName and sliderValueName or valueFormat
            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, currentValue, min, max, valueFormat, sliderFlag)
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
        elseif _type == "Combo" then
            ret, val = reaper.ImGui_Combo(ctx, visualName.. '##slider' .. name .. fxIndex, math.floor(currentValue)+dropdownOffset, dropDownText)
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val - dropdownOffset) end
            scrollValue = 1
        elseif _type == "Checkbox" then
            ret, val = reaper.ImGui_Checkbox(ctx, visualName.. '##slider' .. name .. fxIndex, currentValue == (checkboxFlipped and 0 or 1)) 
            if ret then   
                val = checkboxFlipped and (val and 0 or 1) or (val and 1 or 0)
                setParameterButReturnFocus(track, fxIndex, paramIndex, val) 
            end
            scrollValue = 1
        elseif _type == "ButtonToggle" then
            if reaper.ImGui_Button(ctx, name.. '##slider' .. name .. fxIndex,dropDownSize,buttonSizeH) then
                setParameterButReturnFocus(track, fxIndex, paramIndex, currentValue == 1 and 0 or 1) 
            end
            
        end 
        --scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, nil, scrollValue)
        if val == true then val = 1 end
        if val == false then val = 0 end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end 
        return ret, val
    end
end

-- wrap slider in to mapping function
function createSlider(track,fxIndex, _type,paramIndex,name,min,max,divide, valueFormat,sliderFlag, checkboxFlipped, dropDownText, dropdownOffset,tooltip, widthArray)  
    local info = {_type = _type,paramIndex =paramIndex,name = name,min = min,max =max,divide=divide, valueFormat = valueFormat,sliderFlag = sliderFlag, checkboxFlipped =checkboxFlipped, dropDownText = dropDownText, dropdownOffset = dropdownOffset,tooltip =tooltip}
    widthArray = widthArray or {faderWidth = buttonWidth}
    if _type == "Combo" or _type == "Checkbox" or _type == "ButtonToggle" then
        createSlider2(track,fxIndex, info,nil, widthArray.faderWidth) 
    --else  
    --    parameterNameAndSliders(createSlider2, getAllDataFromParameter(track,fxIndex,paramIndex), focusedParamNumber, info, widthArray) 
    end
end


function createModulationLFOParameter(track, fxIndex,  _type, paramName, visualName, min, max, divide, valueFormat, sliderFlags, checkboxFlipped, dropDownText, dropdownOffset,tooltip) 
    local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)
    if ret and currentValue then 
        scrollValue = nil
        --reaper.ImGui_Text(ctx,visualName)
        --visualName = ""
        reaper.ImGui_SetNextItemWidth(ctx,buttonWidth)
        if _type == "Checkbox" then
            ret, newValue = reaper.ImGui_Checkbox(ctx, visualName .. "##" .. paramName .. fxIndex, currentValue == (checkboxFlipped and "0" or "1"))
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue and (checkboxFlipped and "0" or "1") or (not checkboxFlipped and "0" or "1")) end
            scrollValue = 1
        elseif _type == "SliderDouble" then 
            -- this could probably be unified
            if useFineFaders then
                ret, newValue = pluginParameterSlider(currentValue, fxIndex .. paramName, visualName, min, max, divide, valueFormat, sliderFlags, buttonWidth, "Double", colorBrightBlueTransparent, {})
            else
            -- was the usual slider.
                reaper.ImGui_PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 2) 
            ret, newValue = reaper.ImGui_SliderDouble(ctx, visualName .. '##' .. paramName .. fxIndex, currentValue*divide, min, max, valueFormat, sliderFlags)
                reaper.ImGui_PopStyleVar(ctx)
            end
            
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue/divide) end  
        elseif _type == "Combo" then 
            ret, newValue = reaper.ImGui_Combo(ctx, visualName .. '##' .. paramName .. fxIndex, tonumber(currentValue)+dropdownOffset, dropDownText )
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue-dropdownOffset) end
            scrollValue = divide
        end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end
        scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, 'param.'..paramOut..'.' .. paramName, scrollValue)
        
    end
    return newValue and newValue or currentValue
end

function openGui(track, fxIndex, name, gui, extraIdentifier, isCollabsed) 
    if gui then 
        local _, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible' )
        fxIsShowing = currentValue == "1"
    else
        fxIsShowing = reaper.TrackFX_GetOpen(track,fxIndex)
        fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
    end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), fxIsShowing and colorBlue or semiTransparentGrey)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorLightGrey)
    sizeW = isCollabsed and 20 or buttonWidth * 2 --(moduleWidth-dropDownSize-margin*4)
    sizeH = isCollabsed and 20 or dropDownSize/8
    if gui then
        title = isCollabsed and (fxIsShowing and "CG" or "OG") or (fxIsShowing and "Close Gui" or " Open Gui")
    else
        title = isCollabsed and (fxIsShowing and "CP" or "OP") or (fxIsShowing and "Close Plugin" or " Open Plugin")
    end
    if reaper.ImGui_Button(ctx,title .."##"..fxIndex .. (extraIdentifier and extraIdentifier or ""), sizeW,sizeH) then
        if gui then
            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible',fxIsShowing and 0 or 1  )
        else
            --[[if fxIsShowing and fxIsFloating == nil then
                reaper.TrackFX_SetOpen(track,fxIndex, false)
            else
                reaper.TrackFX_Show(track, fxIndex, fxIsShowing and 2 or 3)  
            end]]
            openCloseFx(track, fxIndex, not fxIsShowing) 
        end
    end 
    if settings.showToolTip then
        reaper.ImGui_SetItemTooltip(ctx, "Open " .. name .. " as floating")
    end
    reaper.ImGui_PopStyleColor(ctx,3)
end

function mapAndShow(track, fx, sliderNum, fxInContainerIndex, name) 
    reaper.ImGui_BeginGroup(ctx)
    local isCollabsed = trackSettings.collabsModules[fx.guid]
    local h = isCollabsed and buttonWidth / 3 or buttonWidth/(not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 2 or 3)
    local w = buttonWidth * (not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 1 or 2)
    
    local isShowing = trackSettings.show[fx.guid] 
    local isMapping = map == fx.fxIndex 
    
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isMapping and colorMap or colorDarkGrey)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),isMapping and colorMap or colorGrey) 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),isMapping and colorMap or colorBlue) 
    
    if reaper.ImGui_Button(ctx, isMapping and "MAPPING" or "MAP", w, h) then 
        hideParametersFromModulator = nil
        mapModulatorActivate(fx.fxIndex,sliderNum, fx.fxInContainerIndex, name)
    end
    
    reaper.ImGui_PopStyleColor(ctx, 3) 
     
    local text = (map and (not isMapping and ("Click to map " .. mapName .. "\nPress escape to stop mapping") or "Click or press escape to stop mapping") or "Click to map output")
    if settings.showToolTip then
        reaper.ImGui_SetItemTooltip(ctx, text)
    end
    
    --[[
    if (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) then
        reaper.ImGui_SameLine(ctx) 
    end
    
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isShowing and colorMapDark or colorDarkGrey)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),isShowing and colorMapDark or colorGrey) 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),isShowing and colorMapDark or colorBlue) 
    
    local mappingsAmount = (parameterLinks and parameterLinks[tostring(fx.fxIndex)]) and #parameterLinks[tostring(fx.fxIndex)] or 0
    if reaper.ImGui_Button(ctx, "Show: " .. mappingsAmount, w, h) then 
        trackSettings.show[fx.guid] = not isShowing
        saveTrackSettings(track)
    end
    if settings.showToolTip then
        reaper.ImGui_SetItemTooltip(ctx,  "Show mapped parameters")
    end
    
    reaper.ImGui_PopStyleColor(ctx, 3) 
    
    ]]
    
    
    reaper.ImGui_EndGroup(ctx)
end




function nlfoModulator(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    local noteTempos = {
        {name = "32 D", value = 4*32*1.5},    -- 0.1875
        {name = "32", value = 4*32},          -- 0.125
    
        {name = "16 D", value = 4*16*1.5},    -- 0.375
        {name = "32 T", value = 4*32/1.5},    -- 0.083333...
        {name = "16", value = 4*16},          -- 0.25
    
        {name = "8 D", value = 4*8*1.5},      -- 0.75
        {name = "16 T", value = 4*16/1.5},    -- 0.166666...
        {name = "8", value = 4*8},            -- 0.5
    
        {name = "4 D", value = 4*4*1.5},      -- 1.5
        {name = "8 T", value = 4*8/1.5},      -- 0.333333...
        {name = "4", value = 4*4},            -- 1
    
        {name = "2 D", value = 4*2*1.5},      -- 3
        {name = "4 T", value = 4*4/1.5},      -- 0.666666...
        {name = "2", value = 4*2},            -- 2
    
        {name = "1 D", value = 4*1*1.5},      -- 6
        {name = "2 T", value = 4*2/1.5},      -- 1.333333...
        {name = "1", value = 4*1},            -- 4
    
        {name = "1/2 D", value = 4*0.5*1.5},  -- 3
        {name = "1 T", value = 4*1/1.5},      -- 2.666666...
        {name = "1/2", value = 4*0.5},        -- 2
    
        {name = "1/4 D", value = 4*0.25*1.5}, -- 1.5
        {name = "1/2 T", value = 4*0.5/1.5},  -- 1.333333...
        {name = "1/4", value = 4*0.25},       -- 1
    
        {name = "1/8 D", value = 4*0.125*1.5},-- 0.75
        {name = "1/4 T", value = 4*0.25/1.5}, -- 0.666666...
        {name = "1/8", value = 4*0.125},      -- 0.5
    
        {name = "1/16 D", value = 4*0.0625*1.5}, -- 0.375
        {name = "1/8 T", value = 4*0.125/1.5},   -- 0.333333...
        {name = "1/16", value = 4*0.0625},       -- 0.25
    
        {name = "1/32 D", value = 4*0.03125*1.5}, -- 0.1875
        {name = "1/16 T", value = 4*0.0625/1.5},  -- 0.166666...
        {name = "1/32", value = 4*0.03125},       -- 0.125
    
        {name = "1/64 D", value = 4*0.015625*1.5}, -- 0.09375
        {name = "1/32 T", value = 4*0.03125/1.5},  -- 0.083333...
        {name = "1/64", value = 4*0.015625},       -- 0.0625
    }
    
    paramOut = "1"
    
    --{"32/1","16/1","8/1","4/1","2/1","1/1","1/2","1/4","1/8","1/16","1/32"}
    noteTempoNamesToValues = {}
    noteTemposDropdownText = ""
    for _, t in ipairs(noteTempos) do
        noteTemposDropdownText = noteTemposDropdownText .. t.name .. "\0" 
    end
    
    timeTypes = {"Hertz", "Beats","Beats (triplets)","Beats (dotted)"}
    timeTypeDropDownText = ""
    for _, t in ipairs(timeTypes) do
        timeTypeDropDownText = timeTypeDropDownText .. t .. "\0" 
    end 
    direction = {"Down", "Bipolar","Up"}
    directionDropDownText = ""
    for _, t in ipairs(direction) do
        directionDropDownText = directionDropDownText .. t .. "\0" 
    end
    phaseResetDropDownText = "Free-running\0On seek/loop\0"
    
    
    --| reaper.ImGui_ChildFlags_AutoResizeY()
    

        --local startPosX, startPosY = beginModulator(name, fxIndex)
        
        
        function createShapesPlots()
            plotAmount = 99
            local shapes = {
              function(n) return math.sin((n)*2 * math.pi) end, -- sin
              function(n) return n < width and -1 or (n> width and 1 or 0) end, --square
              function(n) return (n * -2 + 1) end, -- saw L
              function(n) return (n * 2 - 1) end, -- saw R
              function(n) return (math.abs(n - math.floor(n + 0.5)) * 4 - 1) end, -- triangle
              function(n) return randomPoints[math.floor(n*(#randomPoints-1))+1] / 50 -1 end, -- random
            }
            local shapeNames = {"Sin", "Square", "Saw L", "Saw R", "Triangle", "Random"}
            
            shapesPlots = {}
            for i = 0, #shapes-1 do 
                plots = reaper.new_array(plotAmount+1)
                for n = 0, plotAmount do
                    plots[n+1] = shapes[i+1](n/plotAmount)
                end
                table.insert(shapesPlots,plots)
            end 
            
            return shapesPlots, shapeNames
        end
        
        function createShapes() 
            ------------ SHAPE -----------
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
            
            if not shapesPlots then shapesPlots, shapeNames = createShapesPlots() end  
            local _, focusedShape = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. "shape")  
        
            if not hovered then hovered = {} end
            if not hovered[fxIndex]  then hovered[fxIndex] = {} end
            for i, plots in ipairs(shapesPlots) do
                --ImGui.SetNextItemAllowOverlap(ctx)
                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),focusedShape == tostring(i-1) and colorBlue or (hovered and hovered[fxIndex][i]) and colorLightBlue or semiTransparentGrey )
                
                reaper.ImGui_PlotLines(ctx, '', plots, 0, nil, -1.0, 1.0, buttonSizeW, buttonSizeH)
                reaper.ImGui_PopStyleColor(ctx)
                
                if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then
                    shape = i -1
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. "Shape", shape) 
                end
                
                hovered[fxIndex][i] = reaper.ImGui_IsItemHovered(ctx)
                    
                
                ImGui.SetItemTooltip(ctx, "Set shape to: " .. shapeNames[i]) 
                
                if i < #shapesPlots then
                    reaper.ImGui_SameLine(ctx)--, buttonSizeW * i) 
                    posX, posY = reaper.ImGui_GetCursorPos(ctx)
                    reaper.ImGui_SetCursorPos(ctx, posX-8, posY)
                end
            end  
            
            reaper.ImGui_PopStyleColor(ctx,3) 
        end
        
        buttonSizeW = dropDownSize/6
        buttonSize = 20
        
        --[[
        if isCollabsed and settings.vertical then 
            reaper.ImGui_SameLine(ctx)
        end
        if drawFaderFeedback(nil,nil, fxIndex, 0, 0, 1, isCollabsed, fx) then 
            trackSettings.bigWaveform[fx.guid] = not trackSettings.bigWaveform[fx.guid]
            saveTrackSettings(track)
        end 
        if not isCollabsed then 
            if not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) then reaper.ImGui_SameLine(ctx); end
            mapAndShow(track, fx, 0, fxInContainerIndex, name, true) 
        end
        ]]
                                
        --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end
        --if not isCollabsed then openGui(track, fxIndex, name, true, nil, isCollabsed) end
        reaper.ImGui_TableNextColumn(ctx)
        
        
            
            createShapes()
            
            --reaper.ImGui_Spacing(ctx)
            --reaper.ImGui_Spacing(ctx)
            --reaper.ImGui_NewLine(ctx)
            
            --createSlider(track,fxIndex,"SliderDouble",2,"Baseline",0,1,1,"%0.2f",nil,nil,nil)
            --createModulationLFOParameter(track, fxIndex, "SliderDouble", "mod.baseline", "Baseline", 0, 1,1, "%0.2f") 
            isTempoSync = createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.temposync", "Tempo sync",nil,nil,1)
            
        
            local paramName = "Speed"
            if tonumber(isTempoSync) == 0 then
                nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "lfo.speed", "Speed", 0.0039, 16,1, "%0.4f Hz", reaper.ImGui_SliderFlags_Logarithmic(), nil, nil, nil, nil,buttonWidth*2, 1)
                
                --createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.speed", "Speed",0.0039, 16,1, "%0.4f Hz", reaper.ImGui_SliderFlags_Logarithmic())
            else  
                -- speed drop down menu
                reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)
                local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName) 
                if ret then
                    local smallest_difference = math.huge  -- Start with a large number
                
                    for i, division in ipairs(noteTempos) do
                        local difference = math.abs(division.value - currentValue)
                        
                        if difference < smallest_difference then
                            smallest_difference = difference
                            closest_index = i 
                        end
                    end
                    local ret, value = reaper.ImGui_Combo(ctx, "" .. '##lfo' .. paramName .. fxIndex, closest_index - 1, noteTemposDropdownText )
                    if ret then  
                        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName, noteTempos[value + 1].value) 
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        if scrollVertical ~= 0 and isAltPressed then
                            local newScrollValue = (#noteTempos > closest_index + scrollVertical and 1 < closest_index + scrollVertical and mouseWheelValue ~= 0) and 
                            (scrollVertical < 0 and noteTempos[closest_index+1].value or noteTempos[closest_index-1].value) 
                            or noteTempos[closest_index].value
                        
                            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName, newScrollValue) 
                        end
                    end
                    --scrollHoveredItem(track, fxIndex, paramIndex, newScrollValue, 1, 'param.'..paramOut..'.lfo.' .. paramName,1 )
                end
            end
            
            --createSlider(track,fxIndex,"SliderDouble",3,"Strength",0,100,1,"%0.1f %%",nil,nil,nil)
            --createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.strength", "Strength", 0, 100,100, "%0.1f %%") 
            
            nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "lfo.phase", "Phase", 0, 1, 1, "%0.2f", nil, nil, nil, nil, nil,buttonWidth*2, 0)
            
            --createSlider(track, fxIndex, "Combo", 4, "Direction", nil,nil,nil,nil,nil,nil,directionDropDownText, 1) 
            --createModulationLFOParameter(track, fxIndex, "Combo", "lfo.dir", "Direction", nil,nil,nil,nil,nil,nil,directionDropDownText, 1) 
            
            createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.free", "Seek/loop", nil,nil,1,nil,nil,true)
            
            

            --local info = {_type = _type,paramIndex =paramIndex,name = name,min = min,max =max,divide=divide, valueFormat = valueFormat,sliderFlag = sliderFlag, checkboxFlipped =checkboxFlipped, dropDownText = dropDownText, dropdownOffset = dropdownOffset,tooltip =tooltip}
            
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
            
            --parameterNameAndSliders("modulator",pluginParameterSlider,p, focusedParamNumber)
            
            --createSlider(track,fxIndex,"SliderDouble",2,"Offset",0,1,1,"%0.2f",nil,nil,nil)
            --createSlider(track,fxIndex,"SliderDouble",3,"Width",-1,1,1,"%0.2f",nil,nil,nil)
            
            
        
        --mapButton(fxIndex, name)
        -- incase the module is to small
        --[[if not isCollabsed and endPosX - startPosX < moduleWidth - 17 then
            dummyWidth = moduleWidth - (endPosX - startPosX) - 17
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
            endPosX = startPosX + moduleWidth - 17
        end]]
        
        
        --endPosX = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
        
        --endModulator(name, startPosX, startPosY, fxIndex)
    
end




function acsModulator(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    paramOut = "1"
    direction = {"Negative","Centered", "Positive"}
    directionDropDownText = ""
    for _, t in ipairs(direction) do
        directionDropDownText = directionDropDownText .. t .. "\0" 
    end
    
    --local startPosX, startPosY = beginModulator(name, fxIndex)
     
    buttonSizeH = 22
    buttonSizeW = buttonSizeH * 1.25
    
    reaper.ImGui_TableNextColumn(ctx)
    
    
    if not isCollabsed then
        
        --createSlider(track,fxIndex,"SliderDouble",3,"Strength",0,100,1,"%0.1f %%",nil,nil,nil)
        --createSlider(track, fxIndex, "Combo", 4, "Direction", nil,nil,nil,nil,nil,nil,directionDropDownText, 1) 
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.strength", "Strength", 0, 100,100, "%0.1f %%") 
        
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.strength", "Strength N", 0, 100,100, "%0.2f %%")
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.attack", "Attack", 0, 1000, 1, "%0.0f ms", nil, nil, nil, nil, nil,buttonWidth*2, 300)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.release", "Release", 0, 1000, 1, "%0.0f ms", nil, nil, nil, nil, nil,buttonWidth*2, 300)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.dblo", "Min Volume", -60, 12,1, "%0.2f dB", nil, nil, nil, nil, nil,buttonWidth*2, -60)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.dbhi", "Max Volume", -60, 12,1, "%0.2f dB", nil, nil, nil, nil, nil,buttonWidth*2, 12)
        
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.dblo", "Min Volume", -60, 12,1, "%0.2f dB")
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.dbhi", "Max Volume", -60, 12,1, "%0.2f dB")
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.x2", "X pos", 0, 1,1, "%0.2f")
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.y2", "Y pos", 0, 1,1, "%0.2f")
        
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.chan", "Channel", 0, 2,1, "%0.2f")
        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.stereo", "Stereo", 0, 1,1, "%0.2f")
        
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
        
    end
    
    
    --mapButton(fxIndex, name)
    
    --endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
    -- incase the module is to small
    --[[if not isCollabsed and endPosX - startPosX < moduleWidth - 17 then
        dummyWidth = moduleWidth - (endPosX - startPosX) - 17
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
        endPosX = startPosX + moduleWidth - 17
    end]]
    
    
    --endPosX = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
    
    --endModulator(name, startPosX, startPosY, fxIndex)
end

function midiCCModulator(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    typeDropDownText = "Select\0"
    for i = 1, 127 do
        typeDropDownText = typeDropDownText .. "CC" .. i .. "\0" 
    end 
    typeDropDownText = typeDropDownText .. "Pitchbend" .. "\0" 
    channelDropDownText = "All\0"
    for i = 1, 16 do
        channelDropDownText = channelDropDownText .. "" .. i .. "\0" 
    end 
    
    
    reaper.ImGui_TableNextColumn(ctx)
    
    if not isCollabsed then
        --reaper.ImGui_NewLine(ctx)
        createSlider(track,fxIndex,"Combo",1,"Fader",nil,nil,1,nil,nil,nil,typeDropDownText,0,"Select CC or pitchbend to control the output")
        createSlider(track,fxIndex,"Combo",2,"Channel",nil,nil,1,nil,nil,nil,channelDropDownText,0,"Select which channel to use") 

        isListening = reaper.TrackFX_GetParamNormalized(track, fxIndex, 3) == 1
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),isListening and colorMapLittleTransparent or colorMap )
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),isListening and colorMapLittleTransparent or colorMap )
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMap or semiTransparentGrey )
        createSlider(track,fxIndex,"ButtonToggle",3,isListening and "Stop" or "Listen",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input") 
        reaper.ImGui_PopStyleColor(ctx,3)
        createSlider(track,fxIndex,"Checkbox",7,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil)
        
        local faderSelection = reaper.TrackFX_GetParamNormalized(track, fxIndex, 1)
        if faderSelection > 0 then
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
            
        end
    end
    
    
    
    
    --mapButton(fxIndex, name)
    --[[endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
    if not isCollabsed and endPosX - startPosX < moduleWidth - 17 then
        dummyWidth = moduleWidth - (endPosX - startPosX) - 17
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
        endPosX = startPosX + moduleWidth - 17
    end]]
    
    --reaper.ImGui_Spacing(ctx)
    
    --endModulator(name, startPosX, startPosY, fxIndex)
end

function abSliderModulator(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    --local startPosX, startPosY = beginModulator(name, fxIndex) 
    local sliderIsMapped = parameterWithNameIsMapped(name) 
    if not a_trackPluginStates then a_trackPluginStates = {}; b_trackPluginStates = {} end
    local hasBothValues = a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid]
    local clearName = sliderIsMapped
    
    if isCollabsed and hasBothValues then 
        
    elseif isCollabsed then
        reaper.ImGui_InvisibleButton(ctx,"1",20,1)
    end
    reaper.ImGui_TableNextColumn(ctx)
    
    if not isCollabsed then  
        local buttonName = clearName and "Clear! Values to A" or (a_trackPluginStates[fx.guid] and "A values are saved" or "Set A values")
        local clearType = nil 
        --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
        if reaper.ImGui_Button(ctx, buttonName, dropDownSize) then
            if clearName then
                clearType = "MinValue" 
                if not b_trackPluginStates[fx.guid] then
                    b_trackPluginStates[fx.guid] = getTrackPluginsParameterLinkValues(name, clearType) 
                end
            else 
                if a_trackPluginStates[fx.guid] then
                    a_trackPluginStates[fx.guid] = nil
                else
                    a_trackPluginStates[fx.guid] = getTrackPluginValues(track, fx)
                end
            end
            if a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid] then
                if not comparePluginValues(b_trackPluginStates[fx.guid], a_trackPluginStates[fx.guid], track, modulationContainerPos, fxIndex) then
                    a_trackPluginStates[fx.guid] = nil
                    showTextField = true
                end
            end
        end
        reaper.ImGui_Spacing(ctx)
        
        --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
        local buttonName = clearName and "Clear! Values to B" or (b_trackPluginStates[fx.guid] and "B values are saved" or "Set B values")
        if reaper.ImGui_Button(ctx, buttonName, dropDownSize) then
            if clearName then
                clearType =  "MaxValue" 
                if not a_trackPluginStates[fx.guid] then
                    a_trackPluginStates[fx.guid] = getTrackPluginsParameterLinkValues(name, clearType)
                end
            else  
                if b_trackPluginStates[fx.guid] then
                    b_trackPluginStates[fx.guid] = nil
                else
                    b_trackPluginStates[fx.guid] = getTrackPluginValues(track)
                end
            end
            if a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid] then
                if not comparePluginValues(a_trackPluginStates[fx.guid], b_trackPluginStates[fx.guid], track, modulationContainerPos, fxIndex) then
                    b_trackPluginStates[fx.guid] = nil
                    showTextField = true
                end
            end
        end
        reaper.ImGui_Spacing(ctx)
        if showTextField then
            if not showTextFieldTimerStart then showTextFieldTimerStart = reaper.time_precise() end
            if reaper.time_precise() - showTextFieldTimerStart > 3 then showTextField = false; showTextFieldTimerStart = nil end
            reaper.ImGui_Text(ctx, "Values are the same!")
        end
        
        if clearName then
        
            if reaper.ImGui_Button(ctx, "Clear! Leave values", dropDownSize) then
                clearType = "CurrentValue"
            end 
            reaper.ImGui_Spacing(ctx)
            
            
            --parameterNameAndSliders(sliderAB, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, {paramIndex = 0, min = 0, max = 1}, ) 
            --createSlider(track,fxIndex,"SliderDouble",0,"",0,1,1,"%0.2f",nil,nil,nil,nil,nil,{faderWidth = dropDownSize, parameterMapSize = buttonWidth})
            -- AB SLIDER
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, true, false, false, buttonWidth*2, 0, "%0.2f") 
            
            reaper.ImGui_Spacing(ctx)
            
            --if reaper.ImGui_Button(ctx, "Show controlled values", dropDownSize) then
                
            --end 
            
            
        end
        
        if clearType then
            disableAllParameterModulationMappingsByName(name, "CurrentValue")
            if clearType ~= "MaxValue" then
                a_trackPluginStates[fx.guid] = nil
            end
            if clearType ~= "MinValue" then
                b_trackPluginStates[fx.guid] = nil
            end
            
        end
    end
    
    
    
        
    
    
    --[[endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
    if not isCollabsed and endPosX - startPosX < moduleWidth - 17 then
        dummyWidth = moduleWidth - (endPosX - startPosX) - 17
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
        endPosX = startPosX + moduleWidth - 17
    end]]
     
    --endModulator(name, startPosX, startPosY, fxIndex)
end



function adsrModulator(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    
    --local startPosX, startPosY = beginModulator(name, fxIndex)
    
    if not isCollabsed then
        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 0)
        local ret, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 0) 
        if ret then 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, nil, nil, "Attack", buttonWidth*2, 5.01, math.floor(visuelValue) .. " ms") 
        --createSlider(track,fxIndex,"SliderDouble",0,"Attack",min,max,0,math.floor(tonumber(visuelValue)) .. " ms",nil,nil,nil,nil)
        end
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,7), focusedParamNumber, nil, nil, nil, "A.Tension", buttonWidth*2, 0, "%0.2f") 
        --createSlider(track,fxIndex,"SliderDouble",7,"A.Tension",-1,1,1,"%0.2f",nil,nil,nil,nil)
        --createSlider(track,fxIndex,"SliderDoubleLogarithmic",1,"Decay",1,5000,0,"%0.0f ms",reaper.ImGui_SliderFlags_Logarithmic(),nil,nil,nil)
        
        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 1)
        local ret, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 1) 
        if ret then 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, "Decay", buttonWidth*2, 5.3, math.floor(visuelValue) .. " ms")
            --createSlider(track,fxIndex,"SliderDouble",1,"Decay",min,max,0,math.floor(tonumber(visuelValue)) .. " ms", nil,nil,nil,nil)
        end
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,8), focusedParamNumber, nil, nil, nil, "D.Tension", buttonWidth*2, 0, "%0.2f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, "Sustain", buttonWidth*2, 80, "%0.0f") 
        --createSlider(track,fxIndex,"SliderDouble",8,"D.Tension",-1,1,1,"%0.2f",nil,nil,nil,nil)
        --createSlider(track,fxIndex,"SliderDouble",2,"Sustain",0,100,1,"%0.0f",nil,nil,nil,nil)
        
        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 3)
        local ret, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 3) 
        if ret then
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, "Release", buttonWidth*2, 6.214, math.floor(visuelValue) .. " ms")
            --createSlider(track,fxIndex,"SliderDouble",3,"Release",min,max,0,math.floor(tonumber(visuelValue)) .. " ms",nil,nil,nil,nil)  
        end
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,9), focusedParamNumber, nil, nil, nil, "R.Tension", buttonWidth*2, 0, "%0.2f") 
        --createSlider(track,fxIndex,"SliderDouble",9,"R.Tension",-1,1,1,"%0.2f",nil,nil,nil,nil)
        
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, "Min", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, "Max", buttonWidth*2, 100, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, "Smooth", buttonWidth*2, 0, "%0.0f") 
        --createSlider(track,fxIndex,"SliderDouble",4,"Min",0,100,1,"%0.0f",nil,nil,nil,nil)
        --createSlider(track,fxIndex,"SliderDouble",5,"Max",0,100,1,"%0.0f",nil,nil,nil,nil)
        --createSlider(track,fxIndex,"SliderDouble",6,"Smooth",0,100,1,"%0.0f",nil,nil,nil,nil)
    end
    
    
    --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end
    
    
    --endModulator(name, startPosX, startPosY, fxIndex)
end




function msegModulator(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    
    reaper.ImGui_TableNextColumn(ctx)
     
    
    --reaper.ImGui_TableNextRow(ctx)
    if not isCollabsed then
        
        local triggers = {"Sync","Free", "MIDI", "Manual"}
        local triggersDropDownText = ""
        for _, t in ipairs(triggers) do
            triggersDropDownText = triggersDropDownText .. t .. "\0" 
        end
        
        local tempoSync = {"Off","1/16", "1/8", "1/4", "1/2","1/1", "2/1","4/1","1/16 T", "1/8 T", "1/4 T", "1/2 T","1/1 T","1/16 D", "1/8 D", "1/4 D", "1/2 D","1/1 D"}
        local tempoSyncDropDownText = ""
        for _, t in ipairs(tempoSync) do
            tempoSyncDropDownText = tempoSyncDropDownText .. t .. "\0" 
        end
        
        --createSlider(track,fxIndex,"SliderDouble",0,"Pattern",1,12,100,"%0.0f",nil,nil,nil,nil) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, nil, nil, "Pattern", buttonWidth*2, 0, "%0.0f") 
        createSlider(track,fxIndex,"Combo",1,"Trigger",nil,nil,1,nil,nil,nil,triggersDropDownText,0,"Select how to trigger pattern")
        createSlider(track,fxIndex,"Combo",2,"Tempo Sync",nil,nil,1,nil,nil,nil,tempoSyncDropDownText,0,"Select if the tempo should sync")
        
        
        local syncOff = reaper.TrackFX_GetParam(track, fxIndex, 2)
        if math.floor(syncOff) == 0  then 
          parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, "Rate", buttonWidth*2, 0, "%0.2f Hz") 
        end
        
        
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, "Phase", buttonWidth*2, 0, "%0.2f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, "Min", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, "Max", buttonWidth*2, 100, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,7), focusedParamNumber, nil, nil, nil, "Smooth", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,8), focusedParamNumber, nil, nil, nil, "Att. Smooth", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,9), focusedParamNumber, nil, nil, nil, "Rel. Smooth", buttonWidth*2, 0, "%0.0f") 
        
        -- RETRIGGER DOES NOT WORK. PROBABLY CAUSE IT*S A SLIDER WITH 1 STEP ONLY.
        --parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,13), focusedParamNumber, nil, nil, nil, "Retrigger", buttonWidth*2, 0, "%0.0f") 
        --createSlider(track,fxIndex,"SliderDouble",13,"Retrigger",0,1,1,"%0.0f",nil,nil,nil,nil)
        --createSlider(track,fxIndex,"SliderDouble",14,"Vel Modulation",0,1,1,"%0.2f",nil,nil,nil,nil)
    end
    
    
    --mapButton(fxIndex, name)
    --endPosX, endPosY = fixWidth(fxIndex, startPosX)
    
    --reaper.ImGui_Spacing(ctx)
    
    --endModulator(name, startPosX, startPosY, fxIndex)
end




function _4in1Out(name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    
    --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end
    reaper.ImGui_TableNextColumn(ctx)
    --if not isCollabsed then openGui(track, fxIndex, name, false, nil, isCollabsed) end
    
    
    --local startPosX, startPosY = beginModulator(name, fxIndex)
    
    if not isCollabsed then 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, "Input 1", buttonWidth*2, 1) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, "Input 2", buttonWidth*2, 1) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, "Input 3", buttonWidth*2, 1) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, "Input 4", buttonWidth*2, 1) 
    end
    
    
end




function genericModulator(name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo)
    
    local numParams = reaper.TrackFX_GetNumParams(track,fxIndex) 
    local isMapped = genericModulatorInfo and genericModulatorInfo.outputParam ~= -1
    
    
    if not isCollabsed and not isMapped then
        reaper.ImGui_TextWrapped(ctx, "Select parameters to use as output") 
    end 
    
    
    if not isCollabsed then
        for p = 0, numParams -1 do
            
            
            --x, y = reaper.ImGui_GetCursorPos(ctx)
            hide = not hideParametersFromModulator and trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] and trackSettings.hideParametersFromModulator[fx.guid][p]
            
            if not hide then
                if genericModulatorInfo.outputParam == p then reaper.ImGui_BeginDisabled(ctx) end
                parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,p), focusedParamNumber, nil, nil, nil, false, buttonWidth*2, 1, nil, genericModulatorInfo.outputParam) 
                if genericModulatorInfo.outputParam == p then reaper.ImGui_EndDisabled(ctx) end
                
                reaper.ImGui_Spacing(ctx)
            end
             
        end
        
        --if drawFaderFeedback(nil, nil, fxIndex,10, 0, 1, isCollabsed, fx) then
        --    mapModulatorActivate(fxIndex,10, fxInContainerIndex, name)
        --end 
    end
    
    
    --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end 
     
    --endModulator(name, startPosX, startPosY, fxIndex)
    return genericModulatorInfo
end

---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------



local dock_id, is_docked
local runs = -1
local function loop() 
  playPos = reaper.GetPlayPosition() 
  runs = runs + 1
  
  isAltPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
  isCtrlPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
  isShiftPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
  isSuperPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
  isMouseDown = reaper.ImGui_IsMouseDown(ctx,reaper.ImGui_MouseButton_Left())
  isMouseReleased = reaper.ImGui_IsMouseReleased(ctx,reaper.ImGui_MouseButton_Left())
  --isMouseReleased = reaper.JS_Mouse_GetState(1)
  isMouseDragging = reaper.ImGui_IsMouseDragging(ctx,reaper.ImGui_MouseButton_Left()) 
  click_pos_x, click_pos_y = ImGui.GetMouseClickedPos(ctx, 0) 
  mouse_pos_x, mouse_pos_y = ImGui.GetMousePos(ctx)
  scrollVertical, scrollHorizontal = reaper.ImGui_GetMouseWheel(ctx)
  
  local scrollFlags = isAltPressed and reaper.ImGui_WindowFlags_NoScrollWithMouse() or reaper.ImGui_WindowFlags_None()
  
  
  
  
  
  
  --if not ignoreFocusBecauseOfUiClick and not isMouseReleased then
      retvaltouch, trackidx_fromtouch, itemidx_fromtouch, takeidx_fromtouch, fxnumber_fromtouch, paramnumber_fromtouch = reaper.GetTouchedOrFocusedFX( 0 )
  --end
  --retvalfocus, trackidx_fromfocus, itemidx_fromfocus, takeidx_fromfocus, fxnumber_fromfocus, paramnumber_fromfocus = reaper.GetTouchedOrFocusedFX( 1 )
  
  if retvaltouch and modulatorFxIndexes and modulatorFxIndexes[tostring(fxnumber_fromtouch)] then
      ignoreThisIndex = fxnumber_fromtouch
  end
  
  
  
  if ignoreThisIndex == fxnumber_fromtouch then-- and ignoreThisParam == paramnumber_fromtouch then
      last_fxnumber_fromtouch = fxnumber_fromtouch
      last_paramnumber_fromtouch = paramnumber_fromtouch
      ignoreThisIndex = nil
      ignoreThisParam = nil
      ignoreScroll = true
  end
  
  
  firstSelectedTrack = reaper.GetSelectedTrack(0,0)
  if lastFirstSelected and lastFirstSelected ~= firstSelectedTrack then 
      retvaltouch = false
      retvalfocus = false
  end
  lastFirstSelected = firstSelectedTrack  
  


  if retvaltouch then
      if not locked or (last_trackidx_fromtouch == trackidx_fromtouch and locked)  then
          
          if map then
              if ((last_fxnumber_fromtouch and last_fxnumber_fromtouch ~= fxnumber_fromtouch) or ( last_paramnumber_fromtouch and last_paramnumber_fromtouch ~= paramnumber_fromtouch)) then
                  mapNewlyTouched = true
              end
          end
          
          
          if (not last_fxnumber_fromtouch or last_fxnumber_fromtouch ~= fxnumber_fromtouch) then
              if last_fxnumber_fromfocus then
                  settings.onlyMapped = false
              end
              last_fxnumber_fromtouch = fxnumber_fromtouch
              fxnumber = fxnumber_fromtouch
               
              
              last_paramnumber_fromtouch = nil -- ensure to reset scroll focus
              if doNotChangeOnlyMapped then
                  doNotChangeOnlyMapped = false
              end
              
              scrollPlugin = fxnumber
          end 
          
          
          --fxnumberSelectedFromScript PROBABLY DOESN*T WORK. TRYING TO MAKE SURE THAT NOT CONTAINER IS SELECTED WHEN SELECTING VIA SCRIPT!!
          if not fxnumberSelectedFromScript and retvalfocus and fxnumber_fromfocus > -1 and (not last_fxnumber_fromfocus or last_fxnumber_fromfocus ~= fxnumber_fromfocus) then 
              if last_fxnumber_fromfocus then
                  settings.onlyMapped = false
              end
              last_fxnumber_fromfocus = fxnumber_fromfocus
              fxnumber = fxnumber_fromfocus
              --last_paramnumber_fromtouch = nil -- ensure to reset scroll focus
              if doNotChangeOnlyMapped then
                  doNotChangeOnlyMapped = false
              end
              
              scrollPlugin = fxnumber
          end 
          fxnumberSelectedFromScript = false
          
          if not last_paramnumber_fromtouch or last_paramnumber_fromtouch ~= paramnumber_fromtouch then
              if last_paramnumber_fromTouch then
                  settings.onlyMapped = false
              end
              last_paramnumber_fromtouch = paramnumber_fromtouch
              paramnumber = paramnumber_fromtouch
              if not ignoreScroll then
                  scroll = paramnumber
              end
              ignoreScroll = nil
              if doNotChangeOnlyMapped then
                  doNotChangeOnlyMapped = false 
              end
          end
          
          if mapNewlyTouched then 
              setParamaterToLastTouched(track, modulationContainerPos, map, fxnumber, paramnumber, reaper.TrackFX_GetParamNormalized(track,fxnumber, paramnumber), (mapName:match("LFO") ~= nil and -0.5 or nil) )
              mapNewlyTouched = false
              if settings.mapOnce then map = false; sliderNumber = false end
          end
          
          if (not last_trackidx_fromtouch or last_trackidx_fromtouch ~= trackidx_fromtouch) then
              if settings.trackSelectionFollowFocus then
                  last_trackidx_fromtouch = trackidx_fromtouch
                  track = reaper.GetTrack(0,trackidx_fromtouch)
              else
                  track = firstSelectedTrack
              end
          end 
          
          if firstSelectedTrack and track ~= firstSelectedTrack then
              --track = firstSelectedTrack
              
              --reaper.SetOnlyTrackSelected(track)
          end
      end
  else 
      if not track or (firstSelectedTrack ~= track and not locked) then 
          track = firstSelectedTrack 
          
          mapModulatorActivate(nil)
      end
  end
  ignoreFocusBecauseOfUiClick = nil
  
  if not fxnumber then fxnumber = 0 end
  if not paramnumber then paramnumber = 0 end
  --if not track then track = reaper.GetTrack(0,0) end
  if track then
      _, trackName = reaper.GetTrackName(track)
      trackId = reaper.GetTrackGUID(track) 
      
      if not lastTrack or lastTrack ~= track then  
          -- store the current focused plugin for when changing tracks
          if trackSettings then
              trackSettings.fxnumber = fxnumber
              trackSettings.paramnumber = paramnumber
              saveTrackSettings(lastTrack)
          end
          
          loadTrackSettings(track)
          
          
          
          -- load last focused fx if possible 
          fxnumber = trackSettings.fxnumber ~= modulationContainerPos and trackSettings.fxnumber or nil
          paramnumber = trackSettings.fxnumber ~= modulationContainerPos and trackSettings.paramnumber or nil 
          
          _, trackName = reaper.GetTrackName(track)
          lastTrack = track
      end
      
      --if not lastCollabsModules then lastCollabsModules = {} end 
  else
      --trackName = "Select a track or touch a plugin parameter"
      trackName = "No track selected"
      trackSettings = {}
      lastTrack = nil
  end
  
  
  
  if track then 
      modulationContainerPos = getModulationContainerPos(track)
      
      if modulationContainerPos then
          modulatorNames, modulatorFxIndexes = getModulatorNames(track, modulationContainerPos)
      end
      
      focusedTrackFXNames, parameterLinks = getAllTrackFXOnTrack(track)
      if fxnumber and modulationContainerPos ~= fxnumber and not modulatorFxIndexes[fxnumber] then
          focusedTrackFXParametersData = getAllParametersFromTrackFx(track, fxnumber) 
      else
          for i, f in ipairs(focusedTrackFXNames) do
              if not f.isModulator then
                  fxnumber = f.fxIndex
              end
          end
      end
  else 
      focusedTrackFXNames = {}
      parameterLinks = {}
      focusedTrackFXParametersData = {}
      modulatorNames = {}
      modulatorFxIndexes = {}
      modulationContainerPos = nil
      buttonHovering = {} 
  end
  
  
  
  
  if last_vertical ~= settings.vertical then 
      if not dock_id and settings.dock_id then
          reaper.ImGui_SetNextWindowDockID(ctx, settings.dock_id, nil) 
          last_dock_id = settings.dock_id
      end
      
      local ww = settings.vertical and settings.wwVertical or settings.wwHorizontal
      local wh = settings.vertical and settings.whVertical or settings.whHorizontal 
      local x = settings.vertical and settings.xVertical or settings.xHorizontal 
      local y = settings.vertical and settings.yVertical or settings.yHorizontal 
      
      if (dock_id and dock_id == 0) or (not dock_id and settings.dock_id == 0) then 
          reaper.ImGui_SetNextWindowSize(ctx,ww ,wh ,nil)
          reaper.ImGui_SetNextWindowPos(ctx,x ,y ,nil)
      end
      
      last_vertical = settings.vertical 
      resetWindowSize = true
  end
  --trackGuid = reaper.GetTrackGUID(track)
  
  if resetWindowSize then
      --winW, winH = reaper.ImGui_GetWindowSize(ctx)
      --if winW > 1000
      --resetWindowSize = false
  end
  
  
  
  if setWindowWidth and settings.vertical and not reaper.ImGui_IsWindowDocked(ctx) then
      --reaper.ImGui_SetNextWindowSize(ctx,settings.partsWidth+margin*4, 0,nil)
      --setWindowWidth = nil
  end
  
  
  reaper.ImGui_PushFont(ctx, font)
  local visible, open = ImGui.Begin(ctx, appName,true, 
  reaper.ImGui_WindowFlags_TopMost() | 
  --reaper.ImGui_WindowFlags_NoCollapse() | 
  --reaper.ImGui_WindowFlags_MenuBar() |
  reaper.ImGui_WindowFlags_HorizontalScrollbar()
  | scrollFlags
  )
  if visible then
      local winW, winH = reaper.ImGui_GetWindowSize(ctx)
      local winX, winY = reaper.ImGui_GetWindowPos(ctx) 
      is_docked = reaper.ImGui_IsWindowDocked(ctx)
      
      local childFlags = reaper.ImGui_ChildFlags_Border()
      
      if settings.vertical then
          partsWidth = winW - margin * 4
          childFlags = childFlags | reaper.ImGui_ChildFlags_AutoResizeY()
      else
          partsWidth = settings.partsWidth
      end
      
      
      moduleWidth = partsWidth - 16
      dropDownSize = moduleWidth -30--/ 2
      buttonWidth = dropDownSize / 2
      
  
      if not last_dock_id or last_dock_id ~= dock_id then
        if dock_id == -1 or dock_id == -2 then
            settings.vertical = true
        elseif dock_id == -4 or dock_id == -3 then
            settings.vertical = false
        elseif not is_docked and last_dock_id and last_dock_id == 0 then
            --resetWindow = 
        else
        
        end 
        settings.dock_id = dock_id 
        
        saveSettings()
        last_dock_id = dock_id  
      end
      
      dock_id = reaper.ImGui_GetWindowDockID(ctx)
      
      if not reaper.ImGui_IsWindowDocked(ctx) and 
          (settings.vertical and (settings.wwVertical ~= winW or settings.whVertical ~= winH or settings.xVertical ~= winX or settings.yVertical ~= winY))
        or 
          (not settings.vertical and (settings.wwHorizontal ~= winW or settings.whHorizontal ~= winH or settings.xHorizontal ~= winX or settings.yHorizontal ~= winY))
      then
          if settings.vertical then
              settings.wwVertical = winW
              settings.whVertical = winH
              settings.xVertical = winX
              settings.yVertical = winY
          else
              settings.wwHorizontal = winW
              settings.whHorizontal = winH
              settings.xHorizontal = winX
              settings.yHorizontal = winY 
          end
          saveSettings()
      end
      
      
        
        
        
        
        
        if not lastTouchedParam or lastTouchedParam ~= paramnumber or focusedFxNumber ~= fxnumber then
            --lastSelected = focusedTrackFXParametersData[paramnumber+1]
            if not lastTouchedParam or lastTouchedParam ~= paramnumber then 
                focusedParamNumber = tonumber(paramnumber)
                lastTouchedParam = paramnumber 
            end
            if not focusedFxNumber or focusedFxNumber ~= fxnumber then
                if firstRunDone then
                    --if settings.openSelectedFx and focusedFxNumber then 
                        --[[local floating = reaper.TrackFX_GetFloatingWindow( track, fileInfo.fxIndex ) ~= nil
                        local floatingContainer = focusedMapping and fileInfo.fxContainerIndex and reaper.TrackFX_GetFloatingWindow( track, fileInfo.fxContainerIndex ) ~= nil
                        local isInTheRoot = not fileInfo.fxContainerIndex
                        local topContainerFxIndex = focusedMapping and fileInfo.fxContainerIndex and findParentContainer(fileInfo.fxContainerIndex) or fileInfo.fxIndex
                        local fxWindowOpen = focusedMapping and topContainerFxIndex and reaper.TrackFX_GetOpen( track, topContainerFxIndex )
                        if not fileInfo.fxContainerIndex and floatingSampler then fxWindowOpen = false end
                        ]]
                        --openCloseFx(track, fxnumber, true) 
                    --end
                    
                    --focusedFxNumber = fxnumber
                    firstRunDone = false
                end
                firstRunDone = true
            end
        end
        
      
      
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)
        
        
        
        --fxIndex = 3
        
        --oneData = getAllParametersFromTrackFx(track, fxIndex)
        
        --if not lastSelected then lastSelected = focusedTrackFXParametersData[1] end
        
        ImGui.PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 5.0)
        
        local title = trackName 
        local everythingsIsNotMinimized = ((allIsNotCollabsed == nil or allIsNotCollabsed) and not trackSettings.hidePlugins and not trackSettings.hideParameters and not trackSettings.hideModules)
        
        
        ImGui.BeginGroup(ctx)
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        local modulatorsW = settings.vertical and partsWidth or (winW-x-30)
        local pansHeight = winH-y-8
        --reaper.ImGui_SameLine(ctx)
        
        local widthOfTrackName = settings.vertical and partsWidth - 24 or pansHeight - 24
        if not settings.vertical then
            if specialButtons.lock(ctx, "lock", 24, locked, "Lock to selected track", colorWhite, colorGrey, colorTransparent, colorDarkGrey, menuGreyActive, settings.vertical) then
                locked = not locked and track or false 
                --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
            end
            --titleButtonStyle("L", "Lock to current track", 20, true, true)
            reaper.ImGui_SetCursorPos(ctx, x, y + 24)
        end
        if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything", widthOfTrackName, true,false ) then 
            hideShowEverything(track, everythingsIsNotMinimized)
        end
        if settings.vertical then
            reaper.ImGui_SameLine(ctx, widthOfTrackName) 
            if specialButtons.lock(ctx, "lock", 24, locked, "Lock to selected track", colorWhite, colorGrey, colorTransparent, colorDarkGrey, menuGreyActive, settings.vertical) then
                locked = not locked and track or false 
                --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
            end
        end
        
        --reaper.ImGui_SetCursorPos(ctx, x +20, y + 20)
        reaper.ImGui_EndGroup(ctx)
        
        placingOfNextElement()
        
        if not track then
            reaper.ImGui_BeginDisabled(ctx)
        end
        
        
        ImGui.BeginGroup(ctx)
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        modulatorsW = settings.vertical and partsWidth or (winW-x-30)
        pansHeight = winH-y-28
        
        local height = settings.vertical and (isCollabsed and 22 or settings.partsHeight) or pansHeight
        local tableWidth = partsWidth
        
        local title = "PLUGINS"
        click = false
        
        
        ImGui.BeginGroup(ctx)
        if trackSettings.hidePlugins then
            if modulePartButton(title .. "", not trackSettings.hidePlugins and "Minimize plugins" or "Maximize plugins", settings.vertical and partsWidth or nil, true,true ) then 
                click = true
            end        
        else 
            reaper.ImGui_SetNextWindowSizeConstraints(ctx, 40, 60, tableWidth, height)
            if reaper.ImGui_BeginChild(ctx, 'PluginsChilds', nil, nil, childFlags, reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_NoScrollbar()) then -- | scrollFlags)
            
            --if visible then
                if reaper.ImGui_BeginMenuBar(ctx) then 
                     if titleButtonStyle(title, not trackSettings.hidePlugins and "Minimize plugins" or "Maximize plugins",settings.vertical and partsWidth or nil, true, false ) then 
                         click = true
                     end
                    reaper.ImGui_EndMenuBar(ctx)
                end
                
                local allIsClosed = true
                for _, f in ipairs(focusedTrackFXNames) do 
                    if not f.isModulator and f.isOpen then
                        allIsClosed = false
                        break
                    end
                end
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorDarkGrey)
                local textState = (not allIsClosed and "Close " or "Open ")
                if reaper.ImGui_Button(ctx, textState .. ' all##FXOpenall') then 
                    for _, f in ipairs(focusedTrackFXNames) do 
                        if not f.isModulator then
                            openCloseFx(track, tonumber(f.fxIndex), allIsClosed)
                        end
                    end
                end  
                setToolTipFunc(textState .. "all FX windows")
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add FX##add") then  
                    openFxBrowserOnSpecificTrack() 
                end
                setToolTipFunc("Add new FX to track")
                
                
                reaper.ImGui_PopStyleColor(ctx)
                
                reaper.ImGui_Separator(ctx)
                
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), colorAlmostBlack)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), colorDarkGrey)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), colorDarkGrey)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), littleTransparentGrey)
                
                local pluginFlags = reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_NoPadOuterX()
                if settings.allowHorizontalScroll then
                    pluginFlags = pluginFlags | reaper.ImGui_TableFlags_ScrollX()
                end
                
                
                if reaper.ImGui_BeginTable(ctx, 'PluginsTable',2,pluginFlags, 0, 0) then
                    
                    --ImGui.TableHeadersRow(ctx)
                    
                    ImGui.TableSetupColumn(ctx, 'one', reaper.ImGui_TableColumnFlags_WidthFixed(), 16)--settings.partsWidth-60) -- Default to 100.0
                    --ImGui.TableSetupColumn(ctx, 'two', ImGui.TableColumnFlags_WidthFixed, 20.0) -- Default to 200.0
                    reaper.ImGui_TableSetupScrollFreeze(ctx, 1,0)
                    
                    reaper.ImGui_TableNextColumn(ctx)
                    local count = 0
                    for i, f in ipairs(focusedTrackFXNames) do 
                        --if (settings.includeModulators) or (not settings.includeModulators and (not f.isModulator)) then
                        if not f.isModulator and (settings.showContainers or (not settings.showContainers and not f.isContainer)) then
                            count  = count  + 1
                            local name = f.name
                            if f.isContainer then name = name .. ":" end
                            local indentStr = string.rep(" ", settings.indentsAmount)
                            if f.indent then name = string.rep(indentStr, f.indent) .. name end
                            
                            local isFocused = tonumber(fxnumber) == tonumber(f.fxIndex)
                            if isFocused then
                                --name = "> " .. name
                            end
                            
                            reaper.ImGui_TableNextRow(ctx)
                             
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), f.isFloating and colorLightBlue or colorDarkGrey)
                            reaper.ImGui_TableNextColumn(ctx)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), isFocused and colorWhite or colorGrey)
                            if reaper.ImGui_Selectable(ctx, (isFocused and ">" or count) .. '##' .. f.fxIndex, f.isOpen ,nil) then 
                                
                                openCloseFx(track, f.fxIndex, not f.isOpen)
                            end  
                            setToolTipFunc((not f.isOpen and "Open " or "Close ") .. f.name .. " window")
                            reaper.ImGui_PopStyleColor(ctx)
                            
                            reaper.ImGui_PopStyleColor(ctx, 1)
                            reaper.ImGui_TableNextColumn(ctx)
                            
                            --if reaper.ImGui_Checkbox(ctx, "##FXOpen" ..i, f.isOpen) then 
                            --    openCloseFx(track, f.fxIndex, not f.isOpen)
                            --end
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), (settings.colorContainers and f.isContainer) and colorGrey or colorWhite)
                            if reaper.ImGui_Selectable(ctx, name .. '##' .. f.fxIndex, isFocused ,reaper.ImGui_SelectableFlags_AllowDoubleClick()) then 
                               fxnumber = f.fxIndex
                               paramnumber = 0 
                               focusedFxNumber = f.fxIndex 
                               if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                  openCloseFx(track, f.fxIndex, not f.isOpen)
                               end
                            end 
                            
                            reaper.ImGui_PopStyleColor(ctx, 1)
                            setToolTipFunc("Focus on " .. f.name .. " parameters\n- Double click to open or close")
                            
                            if scrollPlugin and tonumber(f.param) == tonumber(scrollPlugin) then
                                reaper.ImGui_SetScrollHereY(ctx, 0)
                                scrollPlugin = nil
                            end
                            
                        end
                    end
                     
                    
                    reaper.ImGui_EndTable(ctx)
                end  
                reaper.ImGui_PopStyleColor(ctx,3)
                
                
                ImGui.EndChild(ctx)
            end
            
            --[[ 
            reaper.ImGui_Indent(ctx, margin)
            local ret, openSelectedFx = reaper.ImGui_Checkbox(ctx,"Open selected",settings.openSelectedFx)
            if ret then 
                settings.openSelectedFx = openSelectedFx
                saveSettings()
            end
            setToolTipFunc("Automatically open the selected plugin FX window")
            
            
            local ret, showParametersForAllPlugins = reaper.ImGui_Checkbox(ctx,"Show all parameters",settings.showParametersForAllPlugins) 
            if ret then 
                settings.showParametersForAllPlugins = showParametersForAllPlugins
                saveSettings()
            end
            setToolTipFunc("Show parameters for all plugins") 
             ]]
            --[[
            local ret, includeModulators = reaper.ImGui_Checkbox(ctx,"Include Modulators",settings.includeModulators) 
            if ret then 
                settings.includeModulators = includeModulators
                saveSettings()
            end
            setToolTipFunc("Show Modulators container in the plugin list") 
            ]]
        end
        
        if click then 
            trackSettings.hidePlugins = not trackSettings.hidePlugins  
            saveTrackSettings(track)
        end
        
        ImGui.EndGroup(ctx)
        ImGui.EndGroup(ctx)
            
        placingOfNextElement()
        
        
        ------------------------
        -- PARAMETERS ----------
        ------------------------
        
        ImGui.BeginGroup(ctx) 
        if not settings.vertical then
            --reaper.ImGui_Indent(ctx)
        end
        click = false
        title = "PARAMETERS" --.. (trackSettings.hideParameters and "" or (" (" .. (focusedParamNumber + 1) .. "/" .. #focusedTrackFXParametersData .. ")"))
        if trackSettings.hideParameters then  
            if modulePartButton(title .. "", not trackSettings.hideParameters and "Minimize parameters" or "Maximize parameters",settings.vertical and partsWidth or nil, true, true ) then 
                click = true
            end
        else 
            reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 30, tableWidth, height)
            local visible = reaper.ImGui_BeginChild(ctx, 'Parameters', -0.0, 0.0, childFlags,reaper.ImGui_WindowFlags_MenuBar() | scrollFlags)
            if visible then
                if reaper.ImGui_BeginMenuBar(ctx) then
                     title = "PARAMETERS" --.. (trackSettings.hideParameters and "" or (" (" .. (focusedParamNumber + 1) .. "/" .. #focusedTrackFXParametersData .. ")"))
                     if titleButtonStyle(title, not trackSettings.hideParameters and "Minimize parameters" or "Maximize parameters",settings.vertical and partsWidth or nil, true, (not settings.vertical and trackSettings.hideParameters)) then 
                         click = true
                     end
                    reaper.ImGui_EndMenuBar(ctx)
                end
                
                local textSize = reaper.ImGui_CalcTextSize(ctx, "Search", 0,0)
                reaper.ImGui_SetNextItemWidth(ctx, moduleWidth - textSize - 20)
                ret, search = reaper.ImGui_InputText(ctx,"Search", settings.search) 
                if ret then
                    settings.search = search
                    settings.onlyMapped = false
                    saveSettings()
                end
                ret, onlyMapped = reaper.ImGui_Checkbox(ctx,"Only mapped",settings.onlyMapped)
                if ret then
                    settings.search = ""
                    settings.onlyMapped = onlyMapped
                    saveSettings()
                end 
                
                reaper.ImGui_Separator(ctx)
                
                size = nil
                
                
                -- check if any parameters links a active
                local someAreActive = false
                if settings.onlyMapped then
                    for _, p in ipairs(focusedTrackFXParametersData) do 
                        if p.isParameterLinkActive then someAreActive = true; break end
                    end
                    --if not someAreActive then settings.onlyMapped = false; saveTrackSettings(track) end
                end
                
                local curPosY = reaper.ImGui_GetCursorPosY(ctx)
                if reaper.ImGui_BeginChild(ctx, "parametersForFocused", tableWidth-16, height-curPosY-16, nil,scrollFlags) then
                    for _, p in ipairs(focusedTrackFXParametersData) do 
                        --if p.param == focusedParamNumber then 
                        --posX, posY = reaper.ImGui_GetCursorPos(ctx) 
                        --end
                        --if not size then startPosY = reaper.ImGui_GetCursorPosY(ctx) end
                        
                        if not someAreActive or not settings.onlyMapped or (settings.onlyMapped and p.isParameterLinkActive) then
                            if not settings.search or settings.search == "" or searchName(p.name, settings.search) then
                                --reaper.ImGui_Text(ctx, "")
                                reaper.ImGui_Spacing(ctx)
                                parameterNameAndSliders("parameter",pluginParameterSlider,p, focusedParamNumber,nil,nil,nil,nil,nil,nil,nil,nil,true)
                            --if not size then size = reaper.ImGui_GetCursorPosY(ctx) - startPosY end
                                --reaper.ImGui_Separator(ctx)
                                
                                --reaper.ImGui_NewLine(ctx)
                                
                                if scroll and p.param == scroll then
                                    ImGui.SetScrollHereY(ctx,  p.isParameterLinkActive and 0.22 or 0.13) 
                                    removeScroll = true
                                end
                            end
                        end
                        --if p.param == focusedParamNumber then
                         --   reaper.ImGui_DrawList_AddRect(draw_list, windowPosX + posX, windowPosY+ posY, windowPosX+ posX+10, windowPosY +posY+10,colorBlue)
                        --end
                    end
                    reaper.ImGui_EndChild(ctx)
                end
                
                reaper.ImGui_EndChild(ctx)
            end 
            
            
            
        end
        if click then 
            trackSettings.hideParameters = not trackSettings.hideParameters  
            saveTrackSettings(track)
        end
        
        ImGui.EndGroup(ctx)
        
        placingOfNextElement()
        

        
        ImGui.BeginGroup(ctx) 
        if not settings.vertical then
            --reaper.ImGui_Indent(ctx)
        end
        click = false
        if trackSettings.hideModules then
          if modulePartButton("MODULES", not trackSettings.hideModules and "Minimize modules" or "Maximize modules",settings.vertical and partsWidth or nil, true,true ) then 
              click = true
          end 
        else
            local height = settings.vertical and settings.partsHeight or pansHeight
            reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 30, partsWidth, height)
            if reaper.ImGui_BeginChild(ctx, "Modules", 0.0, 0.0, childFlags , reaper.ImGui_WindowFlags_MenuBar() ) then
                if reaper.ImGui_BeginMenuBar(ctx) then
                     if titleButtonStyle("MODULES", not trackSettings.hideModules and "Minimize modules" or "Maximize modules",settings.vertical and partsWidth or nil, true, (not settings.vertical and trackSettings.hideModules)) then 
                         click = true
                     end
                    reaper.ImGui_EndMenuBar(ctx)
                end
                
                function menuHeader(text, variable, tooltip)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorDarkGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorDarkGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorLightGrey)
                    local textState = (not settings[variable] and "Show" or "Hide") 
                    if reaper.ImGui_Button(ctx, text, partsWidth- 16) then  
                        settings[variable] = not settings[variable]
                        saveSettings()
                    end
                    
                    reaper.ImGui_PopStyleColor(ctx,4)
                    setToolTipFunc(textState .. " " .. tooltip)  
                end
                
                function moduleButton(text, tooltip)
                    local click = false
                    
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), colorDarkGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), colorDarkGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), colorDarkGrey)
                    if reaper.ImGui_Selectable(ctx, text, false) then 
                        click = true
                    end 
                    reaper.ImGui_PopStyleColor(ctx,3)
                    
                    setToolTipFunc(tooltip)  
                    
                    reaper.ImGui_Spacing(ctx)
                    return click
                end
                
                
                local curPosY = reaper.ImGui_GetCursorPosY(ctx)
                if reaper.ImGui_BeginChild(ctx, "modules list", tableWidth-16, height-curPosY-16, nil,scrollFlags) then
                    local currentFocus 
                    local nameOpened
                    local containerPos, insert_position
                    
                    
                    menuHeader("Buildin [" .. 8 .."]", "showBuildin", "buildin modulators")
                    if settings.showBuildin then 
                        
                        
                        if moduleButton("+ LFO Native    ","Add an LFO modulator that uses the build in Reaper LFO which is sample accurate",nil) then
                            currentFocus = reaper.JS_Window_GetFocus()
                            nameOpened = "LFO Native"
                            --insertLfoFxAndAddContainerMapping(track)
                            containerPos, insert_position = insertLocalLfoFxAndAddContainerMapping(track)
                        end 
                        if moduleButton("+ ACS Native    ", "Add an Audio Control Signal (sidechain) modulator which uses the build in Reaper ACS") then
                            currentFocus = reaper.JS_Window_GetFocus()
                            nameOpened = "ACS Native"
                            containerPos, insert_position = insertACSAndAddContainerMapping(track)
                        end
                        
                        local tooltip = not isAdsr1Installed and 'Install the ReaPack by "tilr" first.\nClick to open webpage' or "Add an ADSR that uses the plugin created by tilr"
                        if not isAdsr1Installed then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
                        if moduleButton("+ ADSR-1 (tilr) ", tooltip) then 
                            if not isAdsr1Installed then
                                openWebpage("https://forum.cockos.com/showthread.php?t=286951")
                            else
                                currentFocus = reaper.JS_Window_GetFocus()
                                nameOpened = "ADSR-1"
                                containerPos, insert_position = insertFXAndAddContainerMapping(track, "JS: ADSR-1", "ADSR")
                            end
                        end  
                        if not isAdsr1Installed then reaper.ImGui_PopStyleColor(ctx) end
                        
                        local tooltip = not isMseg1Installed and 'Install the ReaPack by "tilr" first.\nClick to open webpage' or "Add a multi-segment LFO / Envelope generator\nthat uses the plugin created by tilr"
                        if not isMseg1Installed then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
                        if moduleButton("+ MSEG-1 (tilr) ", tooltip) then
                            if not isMseg1Installed then
                                openWebpage("https://forum.cockos.com/showthread.php?t=286951")
                            else
                                currentFocus = reaper.JS_Window_GetFocus()
                                nameOpened = "MSEG-1"
                                containerPos, insert_position = insertFXAndAddContainerMapping(track, "JS: MSEG-1", "MSEG")
                            end
                        end  
                        if not isMseg1Installed then reaper.ImGui_PopStyleColor(ctx) end
                        
                        if moduleButton("+ MIDI Fader    ", "Use a MIDI fader as a modulator") then 
                            currentFocus = reaper.JS_Window_GetFocus()
                            nameOpened = "MIDI Fader"
                            containerPos, insert_position = insertFXAndAddContainerMapping(track, "JS: MIDI Fader Modulator", "MIDI Fader")
                        end 
                        if moduleButton("+ AB Slider     ", "Map two positions A and B of plugin parameters on the selected track. Only parameters changed will be mapped") then
                            currentFocus = reaper.JS_Window_GetFocus()
                            nameOpened = "AB Slider"
                            containerPos, insert_position = insertFXAndAddContainerMapping(track, "JS: AB Slider Modulator", "AB Slider")
                        end
                        if moduleButton("+ 4-in-1-out ", "Map 4 inputs to 1 output") then
                            currentFocus = reaper.JS_Window_GetFocus()
                            nameOpened = "4-in-1-out"
                            containerPos, insert_position = insertFXAndAddContainerMapping(track, "4-in-1-out", "4-in-1-out")
                        end  
                        
                        if moduleButton("+ [ANY] ", "Add any FX as a modulator") then  
                            local addFXToTrackWindowName, trackTitleIndex = openFxBrowserOnSpecificTrack() 
                            local fx_before = getAllTrackFXOnTrackSimple(track)  
                            local browserHwnd = reaper.JS_Window_GetForeground()
                            waitForWindowToClose(browserHwnd, function()
                                reaper.ShowConsoleMsg("hej11\n")
                                fx_after = getAllTrackFXOnTrackSimple(track)
                                if #fx_after > #fx_before then
                                    -- An FX was added
                                    local fxName = fx_after[#fx_after].name
                                    if reaper.Undo_CanUndo2(0):match("Add FX: " .. trackTitleIndex) ~= nil then
                                        reaper.Undo_DoUndo2(0)
                                    end 
                                    containerPos, insert_position = insertFXAndAddContainerMapping(track, fxName, fxName)
                                    openCloseFx(track, insert_position, false)
                                end
                            end)
                        end
                    end
                        
                    reaper.ImGui_Separator(ctx)
                    --[[
                    local count = settings.userModulators and #settings.userModulators or 0
                    menuHeader("User [" .. count .."]", "showUser", "user modulators")
                    if settings.showUser and count > 0 then 
                        for i, module in ipairs( settings.userModulators) do
                            local visualName = module.name and module.name or module.fxName
                            if moduleButton("+ " .. visualName .. "##" .. i, module.description) then
                                currentFocus = reaper.JS_Window_GetFocus()
                                nameOpened = visualName
                                containerPos, insert_position = insertFXAndAddContainerMapping(track, module.fxName, visualName)
                                mapParameterToContainer(track, containerPos, insert_position, module.outputParam)
                            end 
                            if reaper.ImGui_IsItemClicked(ctx, 1) then 
                                removeCustomModule = i 
                                removeCustomModuleName = visualName
                                openRemoveCustomModule = true
                            end
                        end 
                    end
                    
                    reaper.ImGui_Separator(ctx)
                    ]]
                    
                    local count = #settings.userModulators
                    menuHeader("User [" .. count .."]", "showPreset", "modulator presets")
                    if settings.showPreset and count > 0 then  
                        for i, module in ipairs( settings.userModulators) do
                            local visualName = module.name and module.name or module.fxName
                            if moduleButton("+ " .. visualName .. "##" .. i, module.description) then
                                currentFocus = reaper.JS_Window_GetFocus()
                                nameOpened = visualName
                                containerPos, insert_position = insertFXAndAddContainerMapping(track, module.fxName, visualName)
                                
                                if module.outputParam then
                                    mapParameterToContainer(track, containerPos, insert_position, module.outputParam)
                                end
                                
                                if module.params then
                                    setAllTrackFxParamValues(track,insert_position, module.params)
                                end
                                
                                if module.nativeLfo then
                                    setNativeLFOParamSettings(track,insert_position, module.nativeLfo)
                                end
                                if module.nativeAcs then
                                    setNativeACSParamSettings(track,insert_position, module.nativeAcs)
                                end
                                if module.hideParams then 
                                    local guid = reaper.TrackFX_GetFXGUID( track, insert_position )
                                    trackSettings.hideParametersFromModulator[guid] = module.hideParams
                                end
                                
                            end 
                            if reaper.ImGui_IsItemClicked(ctx, 1) then 
                                removeCustomModule = i 
                                removeCustomModuleName = visualName
                                openRemoveCustomModule = true
                            end
                        end 
                    end
                    
                    reaper.ImGui_Separator(ctx)
                    
                    
                    
                    if currentFocus then 
                        --reaper.ShowConsoleMsg(modulationContainerPos .. " - ".. insert_position .. "\n")
                        fxIsShowing = reaper.TrackFX_GetOpen(track,insert_position)
                        fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,insert_position)
                        if fxIsShowing then
                            reaper.TrackFX_Show(track, insert_position, fxIsFloating and 2 or 0) 
                        end
                        
                        
                        containerIsShowin = reaper.TrackFX_GetOpen(track,containerPos)
                        containerIsFloating = reaper.TrackFX_GetFloatingWindow(track,containerPos)
                        if containerIsShowin then
                            reaper.TrackFX_Show(track, containerPos, containerIsFloating and 2 or 0) 
                        end
                        
                        --local newFocus = reaper.JS_Window_GetFocus() 
                        --if newFocus ~= currentFocus and reaper.JS_Window_GetTitle(newFocus):match(nameOpened) ~= nil then 
                         --   reaper.JS_Window_Show(newFocus, "HIDE") 
                        --end
                    end
            
                    ImGui.EndChild(ctx)
                end
                
                ImGui.EndChild(ctx)
            end 
            
            
        end
        
        if click then
            trackSettings.hideModules = not trackSettings.hideModules
            saveTrackSettings(track)
        end
        
        
        
        ImGui.EndGroup(ctx)
        
        if openRemoveCustomModule then
            ImGui.OpenPopup(ctx, 'Remove custom module') 
            openRemoveCustomModule = false
        end
        
        if reaper.ImGui_BeginPopup(ctx, 'Remove custom module', nil) then
            if reaper.ImGui_Button(ctx, "Remove " .. removeCustomModuleName) or reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                table.remove(settings.userModulators, removeCustomModule)
                saveSettings()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            ImGui.EndPopup(ctx)
        end 
        
        placingOfNextElement()
        --modulesAdd() 
        
        
        
        ImGui.BeginGroup(ctx) 
        if not settings.vertical then
           -- reaper.ImGui_Indent(ctx)
        end
        
        function optionsForModulators()
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), colorDarkGrey)
            ret, sortAsType = reaper.ImGui_Checkbox(ctx,"Sort by name",settings.sortAsType)
            if ret then
                settings.sortAsType = sortAsType
                saveSettings()
            end
            
            
            ret, mapOnce = reaper.ImGui_Checkbox(ctx,"Map once",settings.mapOnce)
            if ret then
                settings.mapOnce = mapOnce
                saveSettings()
            end
            reaper.ImGui_PopStyleColor(ctx)
        
        end
        
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        modulatorsW = settings.vertical and partsWidth or (winW-x-8)
        --modulatorsH = winH-y-30
        local visible = ImGui.BeginChild(ctx, 'ModulatorsChilds', modulatorsW, settings.vertical and 0 or pansHeight, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()| reaper.ImGui_ChildFlags_AutoResizeX(),reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_HorizontalScrollbar())
        --local visible = reaper.ImGui_BeginTable(ctx, 'ModulatorsChilds', settings.vertical and 1 or #modulatorNames,nil, modulatorsW)
        if visible then
            if reaper.ImGui_BeginMenuBar(ctx) then 
                if titleButtonStyle("MODULATORS", allIsNotCollabsed and "Minimize all modulators" or "Maximize all modulators",settings.vertical and partsWidth or nil,true,false ) then 
                    if modulatorNames and #modulatorNames > 0 then
                        if allIsNotCollabsed then
                            for _, m in ipairs(modulatorNames) do trackSettings.collabsModules[m.guid] = true end
                        else
                            for _, m in ipairs(modulatorNames) do trackSettings.collabsModules[m.guid] = false end
                        end 
                        saveTrackSettings(track)
                    end
                end
                
                if not settings.vertical then 
                    optionsForModulators()
                end
                
                
                reaper.ImGui_EndMenuBar(ctx)
            end
            
            if settings.vertical then 
                --optionsForModulators()
            end

             --
            
            function setParameterNormalizedButReturnFocus(track, fxIndex, param, value) 
                reaper.TrackFX_SetParamNormalized(track, fxIndex, param, value)
                -- focus last focused
                reaper.TrackFX_SetParamNormalized(track,fxnumber,paramnumber,reaper.TrackFX_GetParamNormalized(track,fxnumber,paramnumber))
                return value
            end
            
            function setParameterButReturnFocus(track, fxIndex, param, value) 
                reaper.TrackFX_SetParam(track, fxIndex, param, value)
                -- focus last focused
                reaper.TrackFX_SetParam(track,fxnumber,paramnumber,reaper.TrackFX_GetParam(track,fxnumber,paramnumber))
                return value
            end
            
            
            
            ------ LFO -----------
            
            
            function fixWidth(guid, startPosX)
                --mapButton(fxIndex, name)
                endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                if (not guid or not trackSettings.collabsModules[guid]) and endPosX - startPosX < moduleWidth - 17 then
                    dummyWidth = moduleWidth - (endPosX - startPosX) - 17
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
                    endPosX = startPosX + moduleWidth - 17
                end
                return endPosX, endPosY
            end
            
            
            
            function mapButton(fxIndex, name)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), map == fxIndex and colorMap or colorGrey)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorMapSemiTransparent)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), map == fxIndex and colorMap or colorGrey)
                if reaper.ImGui_Button(ctx, "MAP##" .. fxIndex, 45,45) then 
                     mapModulatorActivate(fxIndex, 0, name)
                end 
                reaper.ImGui_PopStyleColor(ctx,3)
            end
            
            
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 5.0)
            
            if modulationContainerPos then
                
                
                
                
                function modulatorWrapper(func, name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx, genericModulatorInfo, outputArray)
                
                    function openCloseMappings()
                        local isShowing = trackSettings.show[fx.guid] 
                        local colorBg = isShowing and colorLightGrey or colorDarkGrey
                        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
                        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 20)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),colorMap)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorDarkGrey)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorDarkGrey)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorDarkGrey)
                        local tv = (isShowing and ">" or "^")
                        
                        reaper.ImGui_PushFont(ctx, font1) 
                        if reaper.ImGui_Button(ctx,  "##" .. fxIndex, 15,15) then
                            trackSettings.show[fx.guid] = not isShowing 
                            saveTrackSettings(track)
                        end 
                        
                        
                        local bX, bY = reaper.ImGui_GetItemRectMin(ctx)
                        reaper.ImGui_DrawList_AddText(draw_list, bX+ (isShowing and 4 or 4), bY + (isShowing and 0 or 2),colorMap, tv)
                        reaper.ImGui_PopStyleColor(ctx, 4)
                        reaper.ImGui_PopStyleVar(ctx,2)
                        
                        reaper.ImGui_PopFont(ctx)
                        
                        setToolTipFunc((isShowing and "Hide" or "Show" ) .. " " .. #mappings .." mappings")
                    end
                    
                    reaper.ImGui_BeginGroup(ctx)
                    local valuesFromModulator
                    isCollabsed = trackSettings.collabsModules[fx.guid]
                    mappings = (parameterLinks and parameterLinks[tostring(fx.fxIndex)]) and parameterLinks[tostring(fx.fxIndex)] or {}
                    
                    toolTipText = (isCollabsed and "Maximize " or "Minimize ") .. name 
                    --windowFlag = isCollabsed and reaper.ImGui_WindowFlags_NoTitleBar() or reaper.ImGui_WindowFlags_MenuBar()
                    --width = isCollabsed and 20 or moduleWidth
                    click = false 
                    local height = settings.vertical and (isCollabsed and 22 + buttonWidth/3 + 16 or settings.partsHeight) or pansHeight-54
                    local minX, minY, maxX, maxY = false, false, false, false
                    
                    local borderColor = selectedModule == fxIndex and (map == fxIndex and colorMap or colorWhite) or colorGrey
                    
                    local flags = reaper.ImGui_TableFlags_BordersOuter()
                    flags = not isCollabsed and flags or flags | reaper.ImGui_TableFlags_NoPadOuterX() --| reaper.ImGui_TableFlags_RowBg()
                    -- ignore scroll if alt is pressed
                    flags = not settings.vertical and flags | reaper.ImGui_TableFlags_ScrollY() or flags
                    
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderStrong(), borderColor)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), menuGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableHeaderBg(), menuGrey)
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableRowBg(), menuGrey)
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableRowBgAlt(), menuGrey)
                    
                    
                    collabsOffsetY = not settings.vertical and 20 or 0
                    collabsOffsetX = settings.vertical and 28 or 0 
                    local smallHeader = isCollabsed and not settings.vertical
                    local tableWidth = smallHeader and 22 or moduleWidth
                    
                    local modulatorStartPosX, modulatorStartPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                    
                    local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                    
                    
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), borderColor)
                    if isCollabsed and not settings.vertical then 
                        
                        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 60, tableWidth, height)
                        if reaper.ImGui_BeginChild(ctx, name .. fxIndex, tableWidth, 0, childFlags,  reaper.ImGui_WindowFlags_NoScrollbar()) then
                            
                            reaper.ImGui_DrawList_AddRectFilled(draw_list, modulatorStartPosX, modulatorStartPosY , modulatorStartPosX+ tableWidth, modulatorStartPosY+height, menuGrey,20)
                             
                             reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
                            --valuesFromModulator = func(name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx)
                            reaper.ImGui_SetCursorPosY(ctx, 4)
                            reaper.ImGui_SetCursorPosX(ctx, 4)
                            openCloseMappings()
                            
                            
                            reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-7, reaper.ImGui_GetCursorPosY(ctx))
                            
                            
                            for _, output in ipairs(outputArray) do 
                                if drawFaderFeedback(nil,nil, fxIndex, output, 0, 1, isCollabsed, fx) then 
                                    mapModulatorActivate(fx.fxIndex,sliderNum, fx.fxInContainerIndex, name)
                                end  
                                
                            end
                            
                            
                            reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-6, reaper.ImGui_GetCursorPosY(ctx))
                            
                            
                            
                            click = verticalButtonStyle(name, toolTipText, nil,false,false,9.5, true)
                            
                            local clickType = lastItemClickAndTooltip(toolTipText)
                            
                            click = false
                            if clickType == "right" then 
                                ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                            elseif clickType == "left" then 
                                click = true
                            end
                            
                            
                            
                            if mouse_pos_x >= screenPosX and mouse_pos_x <= screenPosX + tableWidth and mouse_pos_y >= screenPosY and mouse_pos_y <= screenPosY + height then
                                if specialButtons.close(ctx,2,height - 20,16,false,"remove" .. fxIndex, colorWhite, colorRedHidden,colorTransparent, colorTransparent) then
                                    deleteModule(track, selectedModule, modulationContainerPos)
                                end
                                setToolTipFunc("Remove modulator")
                            end
                            reaper.ImGui_PopStyleColor(ctx, 1)
                            
                            reaper.ImGui_EndChild(ctx)
                        end     
                    else
                        
                        
                        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 60, tableWidth, height)
                        if reaper.ImGui_BeginChild(ctx, name .. fxIndex, tableWidth, 0, childFlags, reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_NoScrollbar() | scrollFlags) then
                         
                        --local visible = reaper.ImGui_BeginTable(ctx, name .. fxIndex,1, flags, tableWidth, settings.vertical and 0 or -4 )
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
                            --reaper.ImGui_TableSetupColumn(ctx, name)
                            
                            --reaper.ImGui_TableSetupScrollFreeze(ctx,1,2) 
                            --reaper.ImGui_TableHeadersRow(ctx)
                            if reaper.ImGui_BeginMenuBar(ctx) then 
                            local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
                            --
                            --reaper.ImGui_TableSetColumnIndex(ctx,0)
                            
                            --reaper.ImGui_PushID(ctx, 0)
                                if mouse_pos_x >= screenPosX and mouse_pos_x <= screenPosX + tableWidth and mouse_pos_y >= screenPosY and mouse_pos_y <= screenPosY + height then
                                    if specialButtons.close(ctx,0,2,16,false,"remove" .. fxIndex, colorWhite, colorRedHidden,colorTransparent, colorTransparent) then
                                        deleteModule(track, selectedModule, modulationContainerPos)
                                    end
                                    setToolTipFunc("Remove modulator")
                                end
                                
                                reaper.ImGui_PushFont(ctx, font1) 
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),menuGreyHover)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),menuGreyActive)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
                                
                                
                                
                                reaper.ImGui_SetCursorPos(ctx, curPosX + 8, curPosY)
                                
                                reaper.ImGui_Button(ctx, name .. "##" .. fxIndex)
                                
                                reaper.ImGui_PopFont(ctx)
                                
                                local clickType = lastItemClickAndTooltip(toolTipText)
                                
                                click = false
                                if clickType == "right" then 
                                    ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                                elseif clickType == "left" then 
                                    click = true
                                end
                                
                                reaper.ImGui_SetCursorPos(ctx, curPosX + tableWidth - 28, curPosY+4)
                                
                                
                                
                                openCloseMappings()
                                
                                
                                --reaper.ImGui_TableHeader(ctx, name)
                                reaper.ImGui_PopStyleColor(ctx, 3)
                                
                                
                                reaper.ImGui_EndMenuBar(ctx)
                            --reaper.ImGui_PopID(ctx)
                            end
                            --reaper.ImGui_SameLine(ctx)
                            --if reaper.ImGui_BeginMenuBar(ctx) then
                                --clickType = titleTextStyle(name, toolTipText, moduleWidth, false)
                                 
                                  
                                 --if settings.vertical and isCollabsed then
                                    
                                  --  func(name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx)
                                --end
                               -- reaper.ImGui_EndMenuBar(ctx)
                            --end
                            --reaper.ImGui_PopStyleVar(ctx)
                            
                            
                            local isMapped = not genericModulatorInfo or genericModulatorInfo.outputParam ~= -1
                            
                            if fx.fxName:match("AB Slider") == nil and isMapped then
                                if hideParametersFromModulator == fx.guid then
                                    if reaper.ImGui_Button(ctx, "Stop editing", tableWidth-16) then
                                        hideParametersFromModulator = nil
                                    end
                                    local allIsShown = true 
                                    local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
                                    for p = 0, param_count - 1 do 
                                        if trackSettings.hideParametersFromModulator[fx.guid][p] then
                                            allIsShown = false
                                            break;
                                        end
                                    end
                                    if reaper.ImGui_Button(ctx, allIsShown and "Hide all" or "Show all", tableWidth-16) then
                                        for p = 0, param_count - 1 do 
                                            trackSettings.hideParametersFromModulator[fx.guid][p] = allIsShown
                                            saveTrackSettings(track)
                                        end
                                    end
                                else
                                    for _, output in ipairs(outputArray) do 
                                        if drawFaderFeedback(nil,nil, fxIndex, output, 0, 1, isCollabsed, fx) then 
                                            trackSettings.bigWaveform[fx.guid] = not trackSettings.bigWaveform[fx.guid]
                                            saveTrackSettings(track)
                                        end 
                                        
                                        if not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) then reaper.ImGui_SameLine(ctx); end
                                        mapAndShow(track, fx, output, fxInContainerIndex, name, true) 
                                    end
                                end
                            end
                            
                            
                            --reaper.ImGui_TableNextColumn(ctx)
                            if not isCollabsed then 
                                reaper.ImGui_Separator(ctx)
                                local curPosY = reaper.ImGui_GetCursorPosY(ctx)
                                if reaper.ImGui_BeginChild(ctx, "params" .. name .. fxIndex, tableWidth-16, height-curPosY-16, nil,scrollFlags) then
                                    local hasGui = fx.fxName:match("ACS Native Modulator") ~= nil
                                    if fx.fxName:match("LFO Native Modulator") == nil then
                                        openGui(track, fxIndex, name, hasGui, "", false) 
                                    end
                                
                                    valuesFromModulator = func(name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx, genericModulatorInfo)
                                    reaper.ImGui_EndChild(ctx)
                                end
                            end
                            
                            -----------------
                            -----REMOVE------
                            -----------------
                            --[[
                            local isHovered = buttonHovering["delete" .. fxIndex]
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), isHovered and colorRedHidden or colorGrey)
                            
                            if reaper.ImGui_Button(ctx, "Delete module##delete" .. fxIndex) then
                                deleteModule(track, selectedModule, modulationContainerPos)
                            end
                            buttonHovering["delete" .. fxIndex] = reaper.ImGui_IsItemHovered(ctx) 
                            reaper.ImGui_PopStyleColor(ctx, 4)
                            ]]
                            -----------------
                            -----------------
                            -----------------
                            
                            reaper.ImGui_PopStyleColor(ctx,1)
                            --reaper.ImGui_EndTable(ctx)
                            reaper.ImGui_EndChild(ctx)
                        end
                        
                        --
                        
                        
                        
                        reaper.ImGui_Spacing(ctx)
                        
                        
                    end
                    
                    reaper.ImGui_PopStyleColor(ctx,1)
                    
                    
                    if click then
                        trackSettings.collabsModules[fx.guid] = not trackSettings.collabsModules[fx.guid]
                        saveTrackSettings(track)
                        selectedModule = fxIndex
                    end
                    
                    
                    if not minX then minX, minY = reaper.ImGui_GetItemRectMin(ctx) end
                    if not maxX then maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) end
                    --reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, selectedModule == fxIndex and (map == fxIndex and colorMap or colorWhite) or colorGrey,4)
                    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
                    
                    -- module hoover
                    if mouseX >= minX and mouseX <= maxX and mouseY >= minY and mouseY <= maxY then
                        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
                            selectedModule = fxIndex
                            ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                        end
                        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
                            selectedModule = fxIndex
                        end
                    end
                    
                        
                    
                    if ImGui.BeginPopup(ctx, 'popup##' .. fxIndex, nil) then
                        if reaper.ImGui_Button(ctx,"Delete##" .. fxIndex) then
                            deleteModule(track, fxIndex, modulationContainerPos)
                            ImGui.CloseCurrentPopup(ctx)
                        end
                        if reaper.ImGui_Button(ctx,"Rename##" .. fxIndex) then
                            ImGui.CloseCurrentPopup(ctx)
                            openRename = true 
                        end
                        originalName = trackSettings.renamed[fx.guid]
                        if originalName and originalName ~= name then
                            if reaper.ImGui_Button(ctx,"Revert to original name##" .. fxIndex) then
                                renameModule(track, modulationContainerPos, fxIndex, originalName)
                                ImGui.CloseCurrentPopup(ctx) 
                            end
                        end
                        
                        if reaper.ImGui_Button(ctx,"Store as preset##" .. fxIndex) then
                            ImGui.CloseCurrentPopup(ctx)
                            addUserModulator = true 
                            addModulatorPreset = true 
                        end
                        setToolTipFunc("This will store the FX as a preset including all it's settings")
                        
                        local genericHasMapping = valuesFromModulator and valuesFromModulator.outputParam ~= - 1
                        if genericHasMapping then
                            reaper.ImGui_NewLine(ctx)
                            reaper.ImGui_TextColored(ctx, colorGrey, "User modulator:")
                            if reaper.ImGui_Button(ctx,"Change modulator output##" .. fxIndex) then
                                deleteParameterFromContainer(track, modulationContainerPos, fxIndex, valuesFromModulator.indexInContainerMapping)
                                ImGui.CloseCurrentPopup(ctx)
                            end
                            reaper.ImGui_TextColored(ctx, colorRedHidden, "This will break any mappings!!")
                            
                            
                            if reaper.ImGui_Button(ctx,"Hide parameters from modulator##" .. fxIndex) then
                                ImGui.CloseCurrentPopup(ctx)
                                hideParametersFromModulator = fx.guid
                            end 
                            setToolTipFunc("This will store the FX as a preset with the FX's standard settings")
                            
                            if reaper.ImGui_Button(ctx,"Add module as preset##" .. fxIndex) then
                                ImGui.CloseCurrentPopup(ctx)
                                addUserModulator = true 
                            end 
                            setToolTipFunc("This will store the FX as a preset with the FX's standard settings")
                            
                            
                        end
                        
                        
                        ImGui.EndPopup(ctx)
                    end 
                    
                    
                    function storeCustomModulator(name, description, fx, outputParam, preset) 
                            
                        local obj = {fxName = fx.fxName, name = name, outputParam = outputParam, description = description, params = params}
                         
                        if preset then
                            local params = getAllTrackFxParamValues(track,fx.fxIndex)
                            obj.params = params
                        end
                        
                        if fx.fxName:match("LFO Native Modulator") ~= nil then
                            obj.nativeLfo = getNativeLFOParamSettings(track,fxIndex) 
                        elseif fx.fxName:match("ACS Native Modulator") ~= nil then
                            obj.nativeAcs = getNativeACSParamSettings(track,fxIndex) 
                        end
                        
                        if trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] then
                            obj.hideParams = trackSettings.hideParametersFromModulator[fx.guid]
                        end
                        
                        table.insert(settings.userModulators, obj) 
                        
                        saveSettings()
                    end
                    
                    
                    if openRename then
                          ImGui.OpenPopup(ctx, 'rename##' .. fxIndex) 
                          openRename = false
                    end
                    
                    if reaper.ImGui_BeginPopup(ctx, 'rename##' .. fxIndex, nil) then
                        reaper.ImGui_Text(ctx, "Rename " .. name)
                        reaper.ImGui_SetKeyboardFocusHere(ctx)
                        local originalName = name
                        local ret, newName = reaper.ImGui_InputText(ctx,"##" .. fxIndex, name,nil,nil)
                        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                            if not trackSettings.renamed then trackSettings.renamed = {} end
                            if trackSettings.renamed[fx.guid] == nil then trackSettings.renamed[fx.guid] = originalName end
                            if newName == "" then newName = trackSettings.renamed[fx.guid] end -- ; trackSettings.renamed[fx.guid] = nil end
                            renameModule(track, modulationContainerPos, fxIndex, newName)
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        ImGui.EndPopup(ctx)
                    end 
                    
                    if addUserModulator then
                        ImGui.OpenPopup(ctx, 'addModulatorPreset##' .. fxIndex)  
                    end
                    
                    if reaper.ImGui_BeginPopup(ctx, 'addModulatorPreset##' .. fxIndex, nil) then
                        reaper.ImGui_Text(ctx, "Add modulator settings as preset to MODULES")
                        if addUserModulator then
                            reaper.ImGui_SetKeyboardFocusHere(ctx)
                        end 
                        addUserModulator = false
                        
                        reaper.ImGui_Spacing(ctx)
                        reaper.ImGui_TextColored(ctx, colorGrey, "Preset name")
                        if not renamingCustomModule then renamingCustomModule = name end
                        local ret, newName = reaper.ImGui_InputText(ctx,"##name" .. fxIndex, renamingCustomModule,nil,nil)
                        renamingCustomModule = newName
                        
                        reaper.ImGui_TextColored(ctx, colorGrey, "Preset description")
                        if not descriptionCustomModule then descriptionCustomModule = "" end
                        local ret, description = reaper.ImGui_InputText(ctx,"##description" .. fxIndex, descriptionCustomModule,nil,nil)
                        descriptionCustomModule = description
                        
                        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                            reaper.ImGui_CloseCurrentPopup(ctx)
                            renamingCustomModule = nil
                            descriptionCustomModule = nil
                            addModulatorPreset = nil
                        end
                        
                        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                            storeCustomModulator(newName, description, fx, valuesFromModulator and valuesFromModulator.outputParam, not addUserModulator)
                            reaper.ImGui_CloseCurrentPopup(ctx)
                            renamingCustomModule = nil
                            descriptionCustomModule = nil
                            addModulatorPreset = nil
                        end
                        
                        ImGui.EndPopup(ctx)
                    end 
                    
                    --modulatorEndPosX, modulatorEndPosY = reaper.ImGui_GetCursorPos(ctx)
                    --reaper.ImGui_SetCursorPos(ctx, modulatorEndPosX, modulatorStartPosY)
                    --
                    
                    reaper.ImGui_EndGroup(ctx)
                    --reaper.ImGui_SameLine(ctx)
                    --func(name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx)
                    
                    function fixMissingIndentOnCollabsModule(isCollabsed)
                        if isCollabsed then 
                            local curX, curY = reaper.ImGui_GetCursorPos(ctx)
                            reaper.ImGui_SetCursorPos(ctx, curX+ 4, curY)
                        end
                    end
                    
                    if trackSettings.show[fx.guid] then   
                        
                        if not settings.vertical then 
                            reaper.ImGui_SameLine(ctx) 
                            
                            reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx)-7)
                        else 
                            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx)-7)
                        end
                        reaper.ImGui_BeginGroup(ctx) 
                        
                        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderStrong(), colorMap)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorMap)
                        
                        local tableWidth = moduleWidth 
                        local height = settings.vertical and settings.partsHeight or  height
                        
                        
                        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 40, 60, tableWidth, height)
                        local visible = reaper.ImGui_BeginChild(ctx, "mappings" .. name .. fxIndex, tableWidth, 0, childFlags ,reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_HorizontalScrollbar())
                        if visible then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorDarkGrey)
                            reaper.ImGui_PushFont(ctx, font1)
                            --reaper.ImGui_TableSetupColumn(ctx, "< Mappings")
                            
                            --reaper.ImGui_TableSetupScrollFreeze(ctx,1,2) 
                            --reaper.ImGui_TableHeadersRow(ctx)
                            if reaper.ImGui_BeginMenuBar(ctx) then 
                                
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),menuGreyHover)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),menuGreyActive)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),colorMap)
                                reaper.ImGui_Button(ctx, "Mappings" .. (#mappings> 0 and (" (" .. #mappings .. ")") or ""))
                                reaper.ImGui_PopStyleColor(ctx, 4)
                                reaper.ImGui_EndMenuBar(ctx)
                            end
                            reaper.ImGui_PopFont(ctx)
                            
                            
                            local clickType = lastItemClickAndTooltip("Hide mapped parameters")
                            if clickType then
                                trackSettings.show[fx.guid] = false
                            end
                            
                            reaper.ImGui_TableNextColumn(ctx)
                            
                            local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
                            local faderWidth = tableWidth - 32
                            local alreadyShowing = {}
                            
                            for i, map in ipairs(mappings) do  
                                local fxIndex = map.fxIndex
                                local _, name = reaper.TrackFX_GetFXName(track, fxIndex)
                                
                                if not alreadyShowing[fxIndex] then 
                                    
                                    --fixMissingIndentOnCollabsModule(isCollabsed)
                                    
                                    
                                    fxIsShowing = reaper.TrackFX_GetOpen(track,fxIndex)
                                    fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                                    local isShowing = (fxIsShowing or fxIsFloating)
                                    
                                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
                                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorLightGrey)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), isShowing and colorLightBlue or colorDarkGrey)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), isShowing and colorLightBlue or colorGrey)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), isShowing and colorLightBlue or colorDarkGrey)
                                    if i > 1 then 
                                        reaper.ImGui_Spacing(ctx)
                                    end
                                    
                                    --reaper.ImGui_SetCursorPosX(ctx, curPosX - 2)
                                    local toggleText = (not isShowing and "Open " or "Close ") .. name .. " plugin"
                                    if reaper.ImGui_Button(ctx, name .. "##" .. name .. fxIndex, faderWidth) then
                                        openCloseFx(track, fxIndex, not isShowing) 
                                    end
                                    setToolTipFunc(toggleText )
                                    reaper.ImGui_PopStyleColor(ctx,4)
                                    reaper.ImGui_PopStyleVar(ctx, 2)
                                    alreadyShowing[fxIndex] = true
                                    
                                end
                                
                                --fixMissingIndentOnCollabsModule(isCollabsed)
                                
                                parameterNameAndSliders("mappings",pluginParameterSlider,getAllDataFromParameter(track,fxIndex,map.param), focusedParamNumber, nil, nil, true, false, faderWidth)
                                
                                reaper.ImGui_Spacing(ctx)
                                --reaper.ImGui_Separator(ctx)
                                if scroll and map.param == scroll then
                                    ImGui.SetScrollHereY(ctx,  0.22)
                                    removeScroll = true
                                end
                            end
                            --reaper.ImGui_SameLine(ctx)
                            --if reaper.ImGui_BeginMenuBar(ctx) then
                                --clickType = titleTextStyle(name, toolTipText, moduleWidth, false)
                                 --local clickType = lastItemClickAndTooltip(toolTipText)
                                
                                 click = false
                                 if clickType == "right" then 
                                     ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                                 elseif clickType == "left" then 
                                     click = true
                                 end
                                  
                                 --if settings.vertical and isCollabsed then
                                    
                                  --  func(name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx)
                                --end
                               -- reaper.ImGui_EndMenuBar(ctx)
                            --end
                            --reaper.ImGui_PopStyleVar(ctx)
                            --reaper.ImGui_TableNextRow(ctx)
                            reaper.ImGui_TableNextColumn(ctx)
                            
                            reaper.ImGui_PopStyleColor(ctx,1)
                            --reaper.ImGui_EndTable(ctx)
                            reaper.ImGui_EndChild(ctx)
                        end
                        
                        
                        reaper.ImGui_PopStyleColor(ctx,1)
                        
                        reaper.ImGui_EndGroup(ctx)
                    end
                    
                    
                    reaper.ImGui_PopStyleColor(ctx,2)
                    if not settings.vertical then reaper.ImGui_SameLine(ctx) end
                end
                    
                
                
                
                if settings.sortAsType then 
                    local modulatorsByNames = {}
                    local allNames = {}
                    local sortedNames = {}
                    for pos, m in ipairs(modulatorNames) do
                        local simpleName = m.name:match("^(.-)%d*$")
                        if not modulatorsByNames[simpleName] then modulatorsByNames[simpleName] = {} end
                        table.insert(modulatorsByNames[simpleName], m)
                        if not allNames[simpleName] then allNames[simpleName] = true; table.insert(sortedNames, simpleName) end
                    end
                    table.sort(sortedNames)
                    modulatorNames = {}
                    for _, nameType in ipairs(sortedNames) do
                        for _, m in pairs(modulatorsByNames[nameType]) do
                            table.insert(modulatorNames, m)
                        end
                    end
                end
                
                
                for pos, m in ipairs(modulatorNames) do
                    local fxIndex = m.fxIndex
                    local fxName = m.fxName
                    local name = m.name
                    local isCollabsed = trackSettings.collabsModules[guid]
                    local fxInContainerIndex = m.fxInContainerIndex
                    
                    if fxName:match("LFO Native") then
                        modulatorWrapper(nlfoModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m, nil, {0}) 
                    elseif fxName:match("ADSR") then
                        modulatorWrapper(adsrModulator,name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,{10})
                    elseif fxName:match("MSEG") then
                        modulatorWrapper(msegModulator,name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,{10})
                    elseif fxName:match("MIDI Fader Modulator") then
                        modulatorWrapper(midiCCModulator,name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,{0})
                    elseif fxName:match("AB Slider") then
                        modulatorWrapper(abSliderModulator,name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,{0})
                    elseif fxName:match("ACS Native") then
                        modulatorWrapper(acsModulator,name,modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,{0})
                    elseif fxName:match("4%-in%-1%-out") then
                        modulatorWrapper(_4in1Out,name,modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,{0})
                    --elseif fxName:match("Generic Parameter Modulator") then
                    --    modulatorWrapper(genericMappingModulator,name:gsub(" %(Generic mapping%)", ""),modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m)
                    else 
                        local numParams = reaper.TrackFX_GetNumParams(track,fxIndex) 
                        
                        local genericModulatorInfo = {outputParam = -1, indexInContainerMapping = -1}
                        for p = 0, numParams -1 do
                            --retval, buf = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "param." .. p .. ".container_map.hint_id" )
                            retval, buf = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, "container_map.get." .. fxIndex .. "." .. p )
                            if retval then
                                genericModulatorInfo = {outputParam = p, indexInContainerMapping = tonumber(buf)}
                                break
                            end
                        end
                        
                        modulatorWrapper(genericModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m, genericModulatorInfo,{genericModulatorInfo.outputParam})
                    end
                end 
                
                --end
            end
        
            reaper.ImGui_PopStyleVar(ctx)
            --reaper.ImGui_EndTable(ctx)
            ImGui.EndChild(ctx)
        end
        
        reaper.ImGui_Text(ctx,"")
        ImGui.EndGroup(ctx)
        
        ImGui.PopStyleVar(ctx) 
        
        if not track then
            reaper.ImGui_EndDisabled(ctx)
        end
    --else
    --    reaper.ImGui_Text(ctx,"SELECT A TRACK OR TOUCH A TRACK PARAMETER")
    --end
    
    
    
    
    if ImGui.BeginPopup(ctx, 'popup##general', nil) then 
        reaper.ImGui_BeginGroup(ctx)
        
        local menuWidth = 200
        ret, vertical = reaper.ImGui_Checkbox(ctx,"Vertical",settings.vertical)
        if ret then 
            settings.vertical = vertical 
            saveSettings()
           -- reaper.ImGui_CloseCurrentPopup(ctx) 
        end
        
        ret, showToolTip = reaper.ImGui_Checkbox(ctx,"Show tips",settings.showToolTip)
        if ret then 
            settings.showToolTip = showToolTip
            saveSettings()
        end

        --[[
        ret, useFineFaders = reaper.ImGui_Checkbox(ctx,"Use fine faders",settings.useFineFaders)
        if ret then 
            reaper.SetExtState(stateName, "useFineFaders", useFineFaders and "1" or "0", true)
        end
        if reaper.ImGui_IsItemHovered(ctx) and settings.showToolTip then
            reaper.ImGui_SetTooltip(ctx,"If enabled the faders will have more fine control\n - Use Shift for for higher values\n - Use Alt for lower")  
        end
        ]]
                
        
         
        --ret, trackSelectionFollowFocus = reaper.ImGui_Checkbox(ctx,"Auto select track on plugin click", settings.trackSelectionFollowFocus)
        --if ret then 
        --    settings.trackSelectionFollowFocus = trackSelectionFollowFocus
        --    saveSettings()
        --end
        
        everythingsIsNotMinimized = (allIsNotCollabsed and not trackSettings.hideModules and not trackSettings.hideParameters and not trackSettings.hideModules)
        if reaper.ImGui_Button(ctx, (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything") then
            hideShowEverything(track,everythingsIsNotMinimized) 
        end
        
        function sliderInMenu(name, tag, width, min, max, toolTip, double) 
            toolTip = toolTip and toolTip or nil
            reaper.ImGui_SetNextItemWidth(ctx, width / 2)
            if double then
                ret, val = reaper.ImGui_SliderDouble(ctx, "##" .. name, settings[tag],min,max)
            else
                ret, val = reaper.ImGui_SliderInt(ctx, "##" .. name, settings[tag],min,max)
            end
            if ret then
                settings[tag] = val
                if not is_docked and settings.vertical then  
                    --reaper.ImGui_SetNextWindowSize(ctx, 0, winH) 
                    --last_vertical = 1
                end  
                saveSettings()
            end
            setToolTipFunc(toolTip)
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_AlignTextToFramePadding(ctx)
            reaper.ImGui_Text(ctx, name)
            setToolTipFunc(toolTip)
            if reaper.ImGui_IsItemClicked(ctx) then
                settings[tag] = defaultSettings[tag]
                saveSettings()
            end
            return ret 
        end
        
        
        
        if sliderInMenu("Modules width", "partsWidth", menuWidth, 140, 400) then 
            setWindowWidth = true
        end
        sliderInMenu("Modules height (only vertical)", "partsHeight", menuWidth, 80, 550) 
        
        
        reaper.ImGui_NewLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Reset track settings") then
            trackSettings = defaultTrackSettings
            saveTrackSettings(tracK)
        end
         
        if reaper.ImGui_Button(ctx, "Reset track settings on all tracks") then
            for i = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, i) 
                local trackSettingsStr = json.encodeToJson(defaultTrackSettings)
                reaper.GetSetMediaTrackInfo_String(tr, "P_EXT" .. ":" .. stateName, trackSettingsStr, true)
            end 
            trackSettings = defaultTrackSettings
            saveTrackSettings(tracK)
        end 
        
        if reaper.ImGui_Button(ctx, "Reset app settings") then
            settings = defaultSettings
            saveSettings()
        end
        
        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndGroup(ctx)
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, "Modules sections settings:")
        
        --reaper.ImGui_NewLine(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, "Plugins settings:")
        
        local ret, val = reaper.ImGui_Checkbox(ctx,"Show containers",settings.showContainers) 
        if ret then 
            settings.showContainers = val
            saveSettings()
        end
        setToolTipFunc("Show FX container in the plugin list")  
        
        if settings.showContainers then
            local ret, val = reaper.ImGui_Checkbox(ctx,"Color containers",settings.colorContainers) 
            if ret then 
                settings.colorContainers = val
                saveSettings()
            end
            setToolTipFunc("Color FX container grey in the plugin list")  
        end
        
        
        
        sliderInMenu("Indents size for containers", "indentsAmount", menuWidth, 0, 8, "Set how large a visual indents size is shown for container content in the plugin list")
        
        local ret, val = reaper.ImGui_Checkbox(ctx,"Allow horizontal scroll",settings.allowHorizontalScroll) 
        if ret then 
            settings.allowHorizontalScroll = val
            saveSettings()
        end
        setToolTipFunc("Allow to scroll horizontal in the plugin list, when namas are too big for module")  
        
        reaper.ImGui_EndGroup(ctx)
        
        
        reaper.ImGui_SameLine(ctx)
        
        
        reaper.ImGui_BeginGroup(ctx)
        
        reaper.ImGui_TextColored(ctx, colorGrey, "Default parameter mapping settings:")
        
        sliderInMenu("Width", "defaultMappingWidth", menuWidth, -100, 100, "Set the default width when mapping a parameter") 
        
        reaper.ImGui_TextColored(ctx, colorGrey, "Direction")
        for i = #directions, 1, -1 do
            dir = directions[i]
            if reaper.ImGui_RadioButton(ctx, dir, i == settings.defaultDirection) then 
                settings.defaultDirection = i
                saveSettings()
            end
        end
        
        reaper.ImGui_TextColored(ctx, colorGrey, "Direction for modulators with LFO in the name")
        for i = #directions, 1, -1 do
            dir = directions[i]
            if reaper.ImGui_RadioButton(ctx, dir, i == settings.defaultLFODirection) then 
                settings.defaultLFODirection = i
                saveSettings()
            end
        end
        
        reaper.ImGui_EndGroup(ctx)
        
        
        ImGui.EndPopup(ctx)
    end
    
    if reaper.ImGui_IsWindowHovered(ctx) then
      --  reaper.ShowConsoleMsg(tostring(reaper.ImGui_IsAnyItemHovered(ctx)) .. "\n")
    end
    
    if reaper.ImGui_IsMouseClicked(ctx,1) and reaper.ImGui_IsWindowHovered(ctx)   then
        
        ImGui.OpenPopup(ctx, 'popup##general') 
    end
    
    ImGui.End(ctx)
  end
  
  reaper.ImGui_PopFont(ctx)
  
  --if (reaper.ImGui_IsKeyDown(ctx,reaper.ImGui_Mod_Super()) and  reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Backspace())) or reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Delete()) then
  --    deleteModule(track, selectedModule, modulationContainerPos)
  --end
  
  if isAltPressed and reaper.ImGui_IsKeyDown(ctx,reaper.ImGui_Key_M()) then
     -- open = false
  end
  
  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
     if map then 
        map = false
     end
     if hideParametersFromModulator then
        hideParametersFromModulator = nil
     end
     
  end 
  
  if removeScroll then
      scroll = nil
      removeScroll = false
  end
  
  --------------- KEY COMMANDS ----------------
  
  local time = reaper.time_precise()
  local newKeyPressed = checkKeyPress()  
  if not newKeyPressed then lastKeyPressedTime = nil; lastKeyPressedTimeInitial = nil end
  if not lastKeyPressed or lastKeyPressed ~= newKeyPressed then 
      for _, info in ipairs(keyCommandSettings) do 
          local name = info.name
          for _, command in ipairs(info.commands) do
              if command == newKeyPressed then
                  if name == "Close" then 
                      open = false
                  elseif name == "Undo" then
                      reaper.Main_OnCommand(40029, 0) --Edit: Undo
                  elseif name == "Redo" then
                      reaper.Main_OnCommand(40030, 0) --Edit: Redo    
                  end  
              end 
          end
      end 
      
      lastKeyPressed = newKeyPressed
      lastKeyPressedTimeInitial = lastKeyPressedTimeInitial and lastKeyPressedTimeInitial or time
  else
      -- hardcoded repeat values
      if lastKeyPressedTimeInitial and time - lastKeyPressedTimeInitial > 0.5 then
          if lastKeyPressedTime and time - lastKeyPressedTime > 0.2 then 
              lastKeyPressed = nil
          else 
              lastKeyPressed = nil
          end 
          lastKeyPressedTime = time 
      end
  end
  
  ----------------------
  -- toolbar settings --
  ----------------------
  if not toolbarSet then 
      setToolbarState(true) 
      toolbarSet = true
  end
  reaper.atexit(exit)
  ---------------
  -- FINISHED ---
  ---------------
  
  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)

