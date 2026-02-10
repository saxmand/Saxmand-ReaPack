-- @noindex

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
--local ImGui = require 'imgui' '0.9.3'

local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()
-- Check where we load from

local toolbarSet
-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end


if contextstr and #contextstr > 0 then
    --reaper.ShowConsoleMsg("from key command\n")
    --reaper.SetExtState("articulationMapOnDevice", "useOnlyOnDevice", "0", true)
    --showSurface = true
    --notShowingSurface = true
else
    --reaper.ShowConsoleMsg("from surface\n")
    --showSurface = false
    --notShowingSurface = true
end

-- load dependencies

local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
local scriptPathSubfolder = scriptPath .. "Functions" .. seperator   

local devMode = scriptPath:match("jesperankarfeldt") ~= nil
if devMode then
    local devFilesPath = reaper.GetResourcePath() .. "/Scripts/Saxmand-ReaPack-Private/Articulation Scripts/Functions/"
    package.path = package.path .. ";" .. devFilesPath .. "?.lua"
    functionsFilePath = reaper.GetResourcePath() .. "/Scripts/Saxmand-ReaPack-Private/Articulation Scripts/Functions/"
    functionsFileExtension  = "lua"
else
    functionsFilePath = scriptPathSubfolder
    package.path = package.path .. ";" .. scriptPathSubfolder .. "?.dat"
    functionsFileExtension  = "dat"
end
package.path = package.path .. ";" .. scriptPathSubfolder .. "?.lua"
package.path = package.path .. ";" .. scriptPathSubfolder .. "Helpers" .. seperator  .. "?.lua"

if not require("dependencies").main() then return end

-- Load the json functions
local json = require("json")

-- Load the articulation map export function
local export = require("export")


local addMapToInstruments = require("add_script_to_instrument").addMapToInstruments
-- Load pathes
require("pathes")

local readArticulationScript = require("read_articulation_script").readArticulationScript
if not readArticulationScript then
    reaper.ShowConsoleMsg("Somethings wrong!")
    --return
end
changeArticulationScript = require("change_articulation")
changeArticulation = changeArticulationScript.changeArticulation
updateArticulationJSFX = changeArticulationScript.updateArticulationJSFX

local keyboardTriggerSurface = require("keyboard_trigger").keyboardTriggerSurface

local listOfArticulationsScripts = require("scripts_list").listOfArticulationsScripts

local listOverviewSurface = require("list_overview").listOverviewSurface

-- Load the articulation map export function
local trackDependingOnSelection = require("track_depending_on_selection").trackDependingOnSelection



mirror_notation_to_unique_text_events = require("mirror_notation_to_unique_text_events").mirror_notation_to_unique_text_events


-- Load the reaper sections id number, used for
local reaper_sections = dofile(scriptPath .. "/Functions/Helpers/reaper_sections.lua")


local defaultSettings = { 
    listOverview_onlyShowOnMidiEditor = false,
    listOverview_size = 100,
    listOverview_transparency = 20,
    keyboardTrigger_size = 100,
    keyboardTrigger_transparency = 30,
}

function saveSettings()
    local settingsStr = json.encodeToJson(settings)
    reaper.SetExtState(contextstr,"settings", settingsStr, true) 
end


if reaper.HasExtState(contextstr, "settings") then 
    local settingsStr = reaper.GetExtState(contextstr,"settings") 
    settings = json.decodeFromJson(settingsStr)
else    
    settings = defaultSettings
    saveSettings()
end


-- BACKWARDS COMPATABILITY
for key, value in pairs(defaultSettings) do
    if type(value) == "table" then 
        if settings[key] == nil then
            settings[key] = {}
        end
        
        for subKey, subValue in pairs(value) do
            if settings[key][subKey] == nil then
                settings[key][subKey] = subValue
            end
        end
    else  
        if settings[key] == nil then
            settings[key] = value
        end
    end
end



-- SURFACES
keyboardTrigger_name = "Saxmand_Articulation_Keyboard Trigger Surface.lua"
keyboardTrigger_script_path = scriptPath .. keyboardTrigger_name
-- Register (or just retrieve if already added)
keyboardTrigger_command_id = reaper.AddRemoveReaScript(true, 0, keyboardTrigger_script_path, false)


listOverview_name = "Saxmand_Articulation_List Overview Surface.lua"
listOverview_script_path = scriptPath .. listOverview_name
-- Register (or just retrieve if already added)
listOverview_command_id = reaper.AddRemoveReaScript(true, 0, listOverview_script_path, false)

scriptsList_name = "Saxmand_Articulation_Scripts List.lua"
scriptsList_script_path = scriptPath .. scriptsList_name
-- Register (or just retrieve if already added)
scriptsList_command_id = reaper.AddRemoveReaScript(true, 0, scriptsList_script_path, false)

background_server_command_id = cmdID

contextName = "Articulation_Scripts"

function setupLocalSurface()
    firstFrame = true
    ctx = reaper.ImGui_CreateContext(contextName)
    -- font = reaper.ImGui_CreateFont('Arial', 30, reaper.ImGui_FontFlags_Bold())
    font = reaper.ImGui_CreateFont('Arial')
    -- imgui_font
    reaper.ImGui_Attach(ctx, font)
    return false
end

function EnsureValidContext(ctx)
    if not ctx or type(ctx) ~= "userdata" or not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
        return setupLocalSurface()
    end
    return true
end

function setToggleCommandState(commandID, forceState, ensureBackgroundServer)
    local state = reaper.GetToggleCommandState(commandID)
    local enabled = state == 1
    if forceState ~= nil then
        enabled = not forceState
    end
    -- Toggle state
    if enabled then
        -- Turn off
        --ensureBackgroundServerIsRunning(true)
        reaper.SetToggleCommandState(0, commandID, 0)
        reaper.RefreshToolbar2(0, commandID)
    else
        if ensureBackgroundServer then
            ensureBackgroundServerIsRunning()
        end
        -- Turn on
        reaper.SetToggleCommandState(0, commandID, 1)
        reaper.RefreshToolbar2(0, commandID)
    end
end

-- RUN

--reaper.ImGui_ValidatePtr(
--finish = false
--unfocused = 0A
--lastKeyInput = ""

--lastClickedColor = reaper.GetExtState(contextName, "lastClickedColor") or ""

local refocusTimer = 100
local isMouseWasReleased_Timer = 0
local refocusBasedOnTimer = false
local timeSinceMouseRelease = 0
local lastTrack


local function loop()
    state            = reaper.JS_Mouse_GetState(-1)
    isShiftPressed   = (state & 0x08) ~= 0
    isSuperPressed   = (state & (isWin and 0x20 or 0x04)) ~= 0
    isAltPressed     = (state & 0x10) ~= 0
    isCtrlPressed    = (state & (isWin and 0x04 or 0x20)) ~= 0
    isMouseDown      = (state & 0x01) ~= 0
    isMouseReleased  = (state & 0x01) == 0
    isMouseRightDown = (state & 0x02) ~= 0

    local time       = reaper.time_precise()
    isMouseClick     = isMouseDown and not isMouseDownStart
    if isMouseDown then isMouseDownStart = true end
    if isMouseReleased then
        isMouseWasReleased = false
        if isMouseDownStart then
            isMouseWasReleased = true
            isMouseWasReleased_Timer = time
        end
        isMouseDownStart = false
    end
    if isMouseWasReleased then
        timeSinceMouseRelease = time - isMouseWasReleased_Timer
        refocusBasedOnTimer = timeSinceMouseRelease > refocusTimer / 1000
    end

    isAnyMouseDown = isMouseDown or isMouseRightDown


    local ReloadArticulation = reaper.GetExtState(contextName, "ReloadArticulation") == "1"
    if ReloadArticulation then
        reaper.SetExtState(contextName, "ReloadArticulation", "0", true)
        lastTrack = nil
    end
    
    

    track, section_id, name, fxNumber, item, take, midi_editor = trackDependingOnSelection()
    if not lastTrack or lastTrack ~= track or (last_fxNumber ~= fxNumber) then
        triggerTables, triggerTableLayers, triggerTableKeys, artSliders, articulationNotFoundParam = readArticulationScript(track, name)
        lastTrack = track        
        last_fxNumber = fxNumber        

        if track then
            trackNameRet, trackName = reaper.GetTrackName(track)
            if trackNameRet then
                reaper.SetProjExtState(0, "articulationMapOnDevice", "trackName", trackName)
            end
        end
    end
    --reaper.StuffMIDIMessage(0, 0xF0, msgBytes)

    if track and triggerTables then
        if fxNumber then
            
            artSelected = {}
            layerCollabsed = {}
            for _, sl in ipairs(artSliders) do
                local selectedArtNumber = reaper.TrackFX_GetParam(track, fxNumber, sl.param)
                artSelected[sl.layer] = selectedArtNumber
                local collabsed = reaper.TrackFX_GetParam(track, fxNumber, sl.param + 1) == 1
                layerCollabsed[sl.layer] = collabsed
            end

            --selectedArticulationIdx, minval, maxval = reaper.TrackFX_GetParam(track, fxNumber, 0) -- 0 is the parameter index, 0 is the parameter value
            if artSelected[1] then
                reaper.SetProjExtState(0, "articulationMapOnDevice", "selectedArticulationIdx", artSelected[1])
            end
        end
    else
        reaper.SetProjExtState(0, "articulationMapOnDevice", "trackName", "")
    end


    retval, newArtFromDevice = reaper.GetProjExtState(0, "articulationMapOnDevice", "setArticulationFromDevice")
    if (retval == 1 and newArtFromDevice) and (newArtFromDevice ~= "") and triggerTables and triggerTables[newArtFromDevice + 1] then
        changeArticulation(newArtFromDevice, triggerTables[newArtFromDevice + 1].articulation)
        reaper.SetProjExtState(0, "articulationMapOnDevice", "setArticulationFromDevice", "")
    end


    useOnlyOnDevice = reaper.GetExtState("articulationMapOnDevice", "useOnlyOnDevice") == "1"


    --[[
    if useOnlyOnDevice then
        --notShowingSurface = true
        showSurface = false
    else
        showSurface = true
        --notShowingSurface = true
    end
    ]]
    if track and triggerTables then
        local scriptsList_command_state = reaper.GetToggleCommandState(scriptsList_command_id) == 1


        local keyboardTrigger_command_state = reaper.GetToggleCommandState(keyboardTrigger_command_id) == 1
        if keyboardTrigger_command_state then
            if fxNumber then
                keyboardTriggerSurface()
            else
                --local keyboardTrigger_command_state = reaper.GetToggleCommandState(keyboardTrigger_command_id) == 1
                --if settings.showScriptsListIfNoArticulations then
                if scriptsList_command_state then
                    if listOfArticulationsScripts() then
                        lastTrack = nil
                    end
                end
            end
        end
        

        local listOverview_command_state = reaper.GetToggleCommandState(listOverview_command_id) == 1
        if listOverview_command_state then
            if midi_editor or not settings.listOverview_onlyShowOnMidiEditor then
                local windowIsFocused = listOverviewSurface() -- show the list overview
                if midi_editor then
                    -- trying is mouse not down to make sure we focus midi editor even when opening the window
                    if (windowIsFocused) and not isMouseDown then -- and isMouseWasReleased) then
                        reaper.JS_Window_SetFocus(midi_editor)
                    end
                else
                    if windowIsFocused and isMouseWasReleased then
                        reaper.JS_Window_SetFocus(reaper.GetMainHwnd())
                    end
                end
            end
        end

        if take then
            if last_take and last_midi_editor and not midi_editor then 
                mirror_notation_to_unique_text_events(last_take)
            end
            if last_take and last_take ~= take then
                mirror_notation_to_unique_text_events(last_take)
            end
        end

        if midi_editor and take then
            updateArticulationJSFX(take)     
            last_midi_editor = midi_editor       
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


    if reaper.GetExtState("articulationMap", "stopScript") == "1" then
        stopScript = true
    end
    if reaper.GetToggleCommandState(0, background_server_command_id) == 0 then
        stopScript = true
    end

    if stopScript then
        reaper.SetExtState("articulationMap", "running", "0", true)
        reaper.JS_Window_SetFocus(focusedWindow)
        reaper.DeleteExtState("articulationMap", "stopScript", true)
        return
    else
        reaper.SetExtState("articulationMap", "running", "1", false)
        reaper.defer(loop)
    end
end

reaper.defer(loop)
