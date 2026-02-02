-- @description Articulation Script Creator
-- @author Saxmand
-- @package Articulation Scripts
-- @version 0.0.2
-- @about
--   Create new articulation scripts
-- @provides
--   Functions/*.lua
--   Functions/*.luac
--   Functions/Helpers/*.lua
-- @changelog
--   + 

version = 0.2


local stateName = "ArticulationScripts"


local inDevMappings = {
    --["Position (Legato)"] = true, 
    --["Trills Trigger"] = true, 
    ["Live Articulation"] = true,
    ["Filter Channel"] = true,
    ["Filter Pitch"] = true,
    ["Notation"] = true,
    --["Filter Velocity"] = true,
    --["Transpose"] = true, -- would need to keep track of notes, to know proper note off
}

seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
local scriptPathSubfolder = scriptPath .. "Functions" .. seperator  

local devMode = scriptPath:match("jesperankarfeldt") ~= nil
if devMode then
    local devFilesPath = reaper.GetResourcePath() .. "/Scripts/Jesper/Articulations/Functions/"
    package.path = package.path .. ";" .. devFilesPath .. "?.lua"
else
    package.path = package.path .. ";" .. scriptPathSubfolder .. "?.luac"
end
package.path = package.path .. ";" .. scriptPathSubfolder .. "?.lua"
package.path = package.path .. ";" .. scriptPathSubfolder .. "Helpers" .. seperator  .. "?.lua"


-- Load the json functions
--local json = require(scriptPath .. "/Functions/Helpers/json")
local json = require("json")

-- Load the articulation map export function
--local export = require(scriptPath .. "/Functions/export")
local export = require("export")

local file_handling = require("file_handling")
local musicxml = require("musicxml")


local addMap = require("add_script_to_instrument")


local embed_ui = require("embed_ui")

local columnsToNotUseLanes = {
    ["Title"] = true,
    ["Subtitle"] = true,
    ["Notation"] = true,
    ["Layer"] = true,
    ["KT"] = true,
}

local undo_redo = require("undo_redo")

-- Load the keyboard tables
--local keyboard_tables = require(scriptPath .."/Functions/Helpers/keyboard_tables")
local keyboard_tables = require("keyboard_tables")
local kt = keyboard_tables.getKeyboardTables()
local keyboardTableKeys = kt.keys
local keyboardTableKeysOrder = kt.keysOrder 


function GenerateSpectrumColors(count, saturation, value)
  local colors = {}
  saturation = saturation or 1
  value = value or 1

  for i = 1, count do
    local hue = (i - 1) / count
    local r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(hue, saturation, value)
    local R = math.floor(r * 255 + 0.5)
    local G = math.floor(g * 255 + 0.5)
    local B = math.floor(b * 255 + 0.5)
    local A = 255
    local color = (R << 24) | (G << 16) | (B << 8) | A
    table.insert(colors, color)
  end

  return colors
end

local colors = GenerateSpectrumColors(10)



function readLicense()
    -- LICENSE
    local license = require("check_license")
    
    local email, code = license.registered_license()

    if email and code then
        --reaper.SetExtState("ArticualtionScripts", "LicenseCode", "reset", false)
        
        if license.verify_code(email, code) then        
            return true
        else
            license.openLicenseWindow(true)
            return false
        end        
    else            
        if not license.check_articulation_script_list() then
            license.openLicenseWindow(true)
            return false
        else
            return true
        end        
    end
end

readLicense()

-- Load pathes
--require(scriptPath .."/Functions/pathes")
require("pathes")

--- SETTINGS STUFF

local function saveAppSettings()
    local settingsStr = json.encodeToJson(appSettings)
    reaper.SetExtState(stateName,"appSettings", settingsStr, true) 
end


if reaper.HasExtState(stateName, "appSettings") then 
    local settingsStr = reaper.GetExtState(stateName,"appSettings") 
    appSettings = json.decodeFromJson(settingsStr)
else    
    appSettings = {}
    saveAppSettings()
end

-- Function to open a folder in Finder (macOS) or File Explorer (Windows)
function openFolderInExplorer(folderPath)
    -- Check the operating system
    local osName = reaper.GetOS()

    -- Construct and execute the appropriate command based on the OS
    if osName:find("OS") then
        -- macOS
        local command = 'open "' .. folderPath .. '"'
        os.execute(command)
    elseif osName:find("Win") then
        -- Windows
        local command = 'explorer "' .. folderPath:gsub("/", "\\") .. '"'
        os.execute(command)
    else
        reaper.ShowMessageBox("Unsupported OS: " .. osName, "Error", 0)
    end
end

-------------------------------------------------
------------------ HELPERS ----------------------
-------------------------------------------------

local function changeArticulationScriptEmbedUiTextSize(bigger)
    local sameSize
    local trackCount = reaper.CountSelectedTracks(0)
    for t = 0, trackCount - 1 do
        local track = reaper.GetSelectedTrack(0, t)
        local fxAmount = reaper.TrackFX_GetCount(track) 
        for i = 0, fxAmount - 1 do
            local ret, fxName = reaper.TrackFX_GetFXName(track, i)
            if ret and fxName:match("Articulation Script") ~= nil then
                local numParams = reaper.TrackFX_GetNumParams(track, i)
                for p = 0, numParams - 1 do 
                    local ret, paramName = reaper.TrackFX_GetParamName(track, i, p) 
                    if ret and paramName == "Text Size" then
                        local size, sizeMin, sizeMax = reaper.TrackFX_GetParam(track, i, p) 
                        if size then
                            if shift then
                                if not sameSize then sameSize = size end
                                size = sameSize
                            end
                            
                            if bigger then 
                                if size < sizeMax then
                                    reaper.TrackFX_SetParam(track, i, p, size + 1)
                                end
                            else
                                if size > sizeMin then
                                    reaper.TrackFX_SetParam(track, i, p, size - 1)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function getFirstArticulationMapFX()
    local track = reaper.GetSelectedTrack(0, 0)
    if track then
        fxAmount = reaper.TrackFX_GetCount(track)
        for i = 0, fxAmount - 1 do
            _, fxName = reaper.TrackFX_GetFXName(track, i)
            if fxName:match("Articulation Script") ~= nil then    
                fxFound, articulationMap = reaper.BR_TrackFX_GetFXModuleName(track, i)
                fxNumber = i
                break
            end
        end
        if fxFound then          
            return effectsPath .. seperator .. articulationMap
        end
    end
end


function getFirstArticulationMapFXJsonLine(returnPath)
    local path = getFirstArticulationMapFX()
    if path then 
        local jsonStr = file_handling.readFileForJsonLine(path)
        if jsonStr then
            if returnPath then 
                return path 
            else
                return jsonStr
            end
        end
    end
    return false 
end



-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------
-------------------------------

function createMidiNotesMap()
    local midiNotesMap = {}
    local noteNamesSharp = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
    local noteNamesFlat = { 'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B' }

    local noteIndex = 0

    for i = -2, 9 do -- MIDI note range spans from C-1 to G9
        for j = 1, #noteNamesSharp do
            local noteSharp = noteNamesSharp[j] .. i
            local noteFlat = noteNamesFlat[j] .. i

            if noteIndex <= 127 then
                midiNotesMap[noteSharp] = noteIndex
                midiNotesMap[noteFlat] = noteIndex
                noteIndex = noteIndex + 1
            end
        end
    end

    return midiNotesMap
end

-- Example usage
local noteNameValues = createMidiNotesMap()

function createAllMidiNotesArray()
    local notes = {}
    local noteNames = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
    for i = 0, 11 do
        for _, noteName in ipairs(noteNames) do
            table.insert(notes, noteName .. (i - 2))
        end
    end
    local limitedNotes = {}
    for i = 1, 128 do limitedNotes[i - 1] = notes[i] end
    return limitedNotes
end

local allNoteValuesMap = createAllMidiNotesArray()

function createAllWhiteMidiNotesArray()
    local notes = {}
    local noteNames = { 'C', '-', 'D', '-', 'E', 'F', '-', 'G', '-', 'A', '-', 'B' }
    counter = 0
    for i = 0, 11 do
        for _, noteName in ipairs(noteNames) do
            if noteName == '-' then
                table.insert(notes, false)
            else
                table.insert(notes, noteName .. (i - 2))
            end
        end
    end
    local limitedNotes = {}
    for i = 1, 128 do limitedNotes[i - 1] = notes[i] end
    return limitedNotes
end
local allWhiteNoteValuesMap = createAllWhiteMidiNotesArray()

function createAllBlackMidiNotesArray()
    local notes = {}
    local noteNames = { '-', 'C#', '-', 'D#', '-', '-', 'F#', '-', 'G#', '-', 'A#', '-' }
    counter = 0
    for i = 0, 11 do
        for _, noteName in ipairs(noteNames) do
            if noteName == '-' then
                table.insert(notes, false)
            else
                table.insert(notes, noteName .. (i - 2))
            end
        end
    end
    local limitedNotes = {}
    for i = 1, 128 do limitedNotes[i - 1] = notes[i] end
    return limitedNotes
end
local allBlackNoteValuesMap = createAllBlackMidiNotesArray()

function getArrayOfSubarray(origArray, arrayName)
    local newArray = {}
    for _, ar in ipairs(origArray) do
        table.insert(newArray, ar[arrayName]) 
    end
    return newArray
end


function getLargestDelay(specificFilePath)
    jsonString = file_handling.readFileForJsonLine(specificFilePath)
    if jsonString then
        luaTable = json.decodeFromJson(jsonString)

    end
end

function importTable(specificFilePath)
    if not specificFilePath then
        retval, filePath = reaper.GetUserFileNameForRead( articulationScriptsPath .. seperator, "Select an action main script", "")
    else
        retval = true
        filePath = specificFilePath
    end
    if retval then
        file = io.open(filePath)
        if not file then
            print("Error: Unable to read file " .. filename)
            return nil
        end
        local jsonString = file_handling.readFileForJsonLine(filePath)
        
        if jsonString then
            local luaTable = json.decodeFromJson(jsonString)
            local articulationMapCreatorVersion = luaTable.articulationMapCreatorVersion and tonumber(luaTable.articulationMapCreatorVersion) or 0
            
            mapping = {}
            mapping.NoteM = {}
            mapping.NoteH = {}
            mapping.CC = {}
            if articulationMapCreatorVersion > 0 and articulationMapCreatorVersion < 0.2 then 
                modifierSettings = luaTable.modifierSettings or defaultModifierSettings
                --mappingType = luaTable.mappingType or {}
                --mapping.CC = luaTable.mapping.CC or {}
                --mapping.NoteH = luaTable.mapping.NoteH or {}
                --mapping.NoteM = luaTable.mapping.NoteM or {}
                --mapping.Velocity = luaTable.mapping.Velocity or false
                --mapping.Channel = luaTable.mapping.Channel or false
                --mapping.Delay = luaTable.mapping.Delay or false
                --aaa = luaTable.tableInfo.NoteM2
                for key, value in pairs(luaTable.tableInfo) do
                    
                    --reaper.ShowConsoleMsg(key .. "\n")
                    --
                    
                    if key:match("Note") ~= nil then
                        if key:match("NoteM") ~= nil and key:match("Velocity") == nil then
                            local anyValues = false
                            for k, v in pairs(value) do
                                if v and v ~= "" then 
                                    anyValues = true
                                    break
                                end
                            end 
                            if not anyValues then
                                luaTable.tableInfo[key] = nil
                            else
                                table.insert(mapping.NoteM, true)
                            end
                        elseif key:match("NoteH") ~= nil and key:match("Velocity") == nil  then
                            local anyValues = false
                            for k, v in pairs(value) do
                                if v and v ~= "" then 
                                    anyValues = true
                                    break
                                end
                            end 
                            if not anyValues then
                                luaTable.tableInfo[key] = nil
                            else
                                table.insert(mapping.NoteH, true)
                            end
                        end
                    elseif key:match("CC") ~= nil then
                        local anyValues = false
                        for k, v in pairs(value) do
                            if v and v ~= "" then 
                                anyValues = true
                                break
                            end
                        end 
                        if not anyValues then
                            luaTable.tableInfo[key] = nil
                        else
                            mapping.CC[key:gsub("CC", "")] = true
                        end
                    else
                        local anyValues = false
                        for k, v in pairs(value) do
                            if v and v ~= "" then 
                                anyValues = true
                                break
                            end
                        end 
                        if anyValues then
                            if key:match("Velocity") ~= nil and key:match("FilterVelocity") == nil then mapping.Velocity = true end
                            if key:match("Channel") ~= nil then mapping.Channel = true end
                            if key:match("Subtitle") ~= nil then mapping.Subtitle = true end
                            if key:match("KT") ~= nil then mapping.KeyboardTrigger = true end
                            if key:match("Notation") ~= nil then mapping.Notation = true end
                            if key:match("UI Text") ~= nil then mapping.UIText = true end
                            if key:match("Delay") ~= nil then mapping.Delay = true end
                            if key:match("Pitch") ~= nil then mapping.Pitch = true end
                            if key:match("Layer") ~= nil or key:match("Group") ~= nil then mapping.Layer = true end
                            if key:match("Position") ~= nil then mapping.Position = true end
                            if key:match("Transpose") ~= nil then mapping.Transpose = true end
                            if key:match("FilterVelocity") ~= nil then mapping.FilterVelocity = true end
                            if key:match("FilterSpeed") ~= nil then mapping.FilterSpeed = true end
                            if key:match("Interval") ~= nil then mapping.Interval = true end
                        end
                    end
                end
                
                tableInfo = {} 
                for key, value in pairs(luaTable.tableInfo) do                   
                    for k, v in pairs(value) do                    
                        if not tableInfo[k] then tableInfo[k] = {} end
                        tableInfo[k][key] = v 
                        if key == "Title" and v:match("!!Lane:") ~= nil then
                            tableInfo[k].isLane = true
                        end
                    end                    
                end
                
                --tableInfo = luaTable.tableInfo
            elseif articulationMapCreatorVersion == 0.25 then 
                tableInfo = luaTable.tableInfo
                if luaTable.mapping then
                    mapping = luaTable.mapping
                else
                    local usedNoteMapping = {}
                    for _, a in ipairs(tableInfo) do
                        for k, v in pairs(a) do 
                            if v and v ~= "" then
                                if k:match("NoteM") ~= nil and k:match("Velocity") == nil then
                                    if not usedNoteMapping[k] then 
                                        table.insert(mapping.NoteM, true)
                                        usedNoteMapping[k] = true
                                    end
                                elseif k:match("NoteH") ~= nil and k:match("Velocity") == nil  then
                                    if not usedNoteMapping[k] then 
                                        table.insert(mapping.NoteH, true)
                                         usedNoteMapping[k] = true
                                     end 
                                elseif k:match("CC") ~= nil then
                                    mapping.CC[key:gsub("CC", "")] = true
                                else
                                    if k:match("KT") ~= nil then 
                                        mapping.KeyboardTrigger = true 
                                    else
                                        mapping[k] = true
                                    end
                                end
                            end
                        end
                    end
                end
            elseif articulationMapCreatorVersion == 0.2 then   
                tableInfo = luaTable.tableInfo
                if luaTable.mapping then
                    mapping = luaTable.mapping
                end
                if mapping.NoteM or mapping.NoteH then
                    mapping.NoteM = nil
                    mapping.NoteH = nil
                    mapping.Note = {}
                    local usedNoteMapping = {}
                    local newTable = {}
                    for i, a in ipairs(tableInfo) do
                        if not newTable[i] then newTable[i] = {} end
                        for k, v in pairs(a) do 
                            if v and v ~= "" then
                                if k:match("Note") ~= nil and k:match("Velocity") == nil then
                                    if not usedNoteMapping[k] then 
                                        table.insert(mapping.Note, #mapping.Note + 1)
                                        usedNoteMapping[k] = #mapping.Note
                                    end 
                                    
                                    newTable[i]["Note" .. usedNoteMapping[k]] = v
                                elseif k:match("CC") ~= nil then
                                    mapping.CC[key:gsub("CC", "")] = true
                                    newTable[i][k] = v
                                else
                                    newTable[i][k] = v
                                    if k:match("KT") ~= nil then 
                                        mapping.KeyboardTrigger = true 
                                    else
                                        mapping[k] = true
                                    end
                                end
                            end
                        end
                    end
                    tableInfo = newTable
                end
            else
                reaper.ShowConsoleMsg("Script not supported from version: " .. tostring(articulationMapCreatorVersion) .. "\n")
            end
            
            --#tableInfo = #tableInfo -- luaTable.tableInfo.Title and #luaTable.tableInfo.Title or 0
            mapName = luaTable.mapName
            instrumentSettings = luaTable.instrumentSettings and luaTable.instrumentSettings or instrumentSettingsDefault
            undo_redo.commit({tableInfo, mapping})
        end
        -- modifierSettings,mappingType,mapping.CC, mapping.NoteH, mapping.NoteM, tableInfo, #tableInfo, mapName = unpickle(fileText)
    end
end



function openArticulationFolder() 
    openFolderInExplorer(articulationScriptsPath) 
end


-- FROM CLIPBOARD
function importArticulationSet()
    function splitString(inputstr, sep)
        if sep == nil then sep = "%s" end
        local t = {}
        for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
            table.insert(t, str)
        end
        return t
    end

    clipboard = reaper.CF_GetClipboard()

    if clipboard and focusedColumn then
        local row = focusedRow and focusedRow or 0
        for line in string.gmatch(clipboard, "([^\n]*)\n?") do
            if line ~= "" then -- To avoid adding empty strings if the string ends with a newline
                parts = splitString(line, ";")

                for i, name in ipairs(parts) do
                    columnToInsertTo = focusedColumn + i - 1
                    focusedColumnName = mappingType[columnToInsertTo]
                    if focusedColumnName then
                        if focusedColumnName:match("Note") ~= nil then
                            nameNumber = tonumber(name)
                            if not nameNumber then
                                nameNumber = tonumber(noteNameValues[name])
                            end
                            name = nameNumber
                        end
                        if not tableInfo[row] then tableInfo[row] = {} end
                        
                        tableInfo[row][focusedColumnName] = name
                        
                    end
                end
                -- reaper.ShowConsoleMsg()
                row = row + 1
                --if #tableInfo < lineCount then
                    --#tableInfo = inputLine
                --end
            end
        end
    end
end

function deleteRowsStart() 
    reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
    deleteRowsAction = 1
end

function moveRowStart(direction) --if reaper.ImGui_IsAnyItemFocused(ctx) then
    if not moveRowsAction then 
        reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
        moveRowsAction = 1
        moveRowsDirection = direction
    end
end

function deleteRows()
    if #selectedArticulationsCountKeys > 0 then  
        for i = #selectedArticulationsCountKeys, 1, -1 do
            local rowKey = selectedArticulationsCountKeys[i]
            table.remove(tableInfo, rowKey) 
        end
        undo_redo.commit({tableInfo, mapping})
    end 
end

function makeArticulationALaneOrNot()
    if #selectedArticulationsCountKeys > 0 then  
        for i = #selectedArticulationsCountKeys, 1, -1 do
            local rowKey = selectedArticulationsCountKeys[i]
            if tableInfo[rowKey].isLane then
                tableInfo[rowKey].isLane = nil
            else
                tableInfo[rowKey].isLane = true
            end
        end
        undo_redo.commit({tableInfo, mapping})
    end 
end

function duplicateRows() 
    if (selectedArticulationsCountKeys and #selectedArticulationsCountKeys > 0) then  
        local rowsToDuplicate = {}
        for i, row in ipairs(selectedArticulationsCountKeys) do
            rowsToDuplicate[i] = {}
            for k, v in pairs(tableInfo[row]) do
                rowsToDuplicate[i][k] = v
            end
        end
        
        local newSelectedArticulationsCountKeys = {}
        local newSelectedArticulations = {}
        if #selectedArticulationsCountKeys > 0 then 
            for i = #selectedArticulationsCountKeys, 1, -1 do
                local rowKey = selectedArticulationsCountKeys[i]
                table.insert(tableInfo, rowKey + 1, rowsToDuplicate[selectedArticulations[rowKey]]) 
                newSelectedArticulations[rowKey + i] = i
                newSelectedArticulationsCountKeys[i] = rowKey + i
            end
        end
        selectedArticulations = newSelectedArticulations
        selectedArticulationsCountKeys = newSelectedArticulationsCountKeys
        focusNextRow = true
        setFocusOnNewMapping = true
        undo_redo.commit({tableInfo, mapping})
    end
end


function addArticulation(multi)
    local insertRowFromSelection = (selectedArticulationsCountKeys and #selectedArticulationsCountKeys > 0)
    local insertRow =  insertRowFromSelection and selectedArticulationsCountKeys[#selectedArticulationsCountKeys] + 1 or #tableInfo + 1
    
    if not multi then
        table.insert(tableInfo, insertRow, {})
    else
        for i = 1, multi do
            table.insert(tableInfo, insertRow, {}) 
        end
    end
    
    if not insertRowFromSelection then 
        selectNewArt = true  -- fix to not select last only
    else
        focusNextRow = true
    end
    
    --selectedArticulations = {}
    --lastSelectedRow = nil 
    --updateItemFocus(insertRow, focusedColumn, 0, 0)
    addNewArticulation = true
    undo_redo.commit({tableInfo, mapping})
end


function addLane()
    local insertRow = (selectedArticulationsCountKeys and #selectedArticulationsCountKeys > 0) and selectedArticulationsCountKeys[#selectedArticulationsCountKeys] + 1 or #tableInfo + 1
    table.insert(tableInfo, insertRow, {["isLane"] = true}) 
    undo_redo.commit({tableInfo, mapping})
    selectNewArt = true -- fix to not select last only
end



function deleteColumn()
    reaper.ShowConsoleMsg("NOT YET IMPLEMENTED\n")
end

function moveRows(up)
    local firstRow = firstSelectedArticulation
    local lastRow = firstSelectedArticulation
    local direction
    if firstRow then
        -- Extract keys
        local keys = {}
        for k in pairs(selectedArticulations) do table.insert(keys, k) end
        -- Sort keys
        table.sort(keys)
    
        if up then
            direction = -1
        else
            direction = 1
        end
        
        if (up and firstRow > 1) or (not up and lastRow < #tableInfo) then
            if not up then
                local reversedTable = {}
                for i = #keys, 1, -1 do
                    table.insert(reversedTable, keys[i])
                end
                keys = reversedTable
            end
            selectedArticulations = {}
            for i, rowKey in ipairs(keys) do
                rowKeyToMove = tonumber(rowKey)
                --for _, map in pairs(mappingType) do
                    --if tableInfo[map][rowKeyToMove] then
                        local tempMappingInfo = tableInfo[rowKeyToMove + direction]
                        reaper.ShowConsoleMsg(rowKeyToMove .. " - " .. direction .. "\n")
                        tableInfo[rowKeyToMove + direction] = tableInfo[rowKeyToMove]
                        tableInfo[rowKeyToMove] = tempMappingInfo
                    --end
                --end
                selectedArticulations[rowKeyToMove + direction] = i
            end
    
            setFocus = (firstRow + direction - 1) * columnAmount + focusedColumn - 1
            if setFocus < 1 then
                setFocus = 1
                adjust = -1
            end
            moveRow = true
        end
    end

end
-----------------------------------------------------------------
-- RUN
-- ---
contextName = "Articulation Creator"
focusedWindow = reaper.JS_Window_GetFocus()
ctx = reaper.ImGui_CreateContext(contextName)
-- font = reaper.ImGui_CreateFont('Arial', 30, reaper.ImGui_FontFlags_Bold())
font = reaper.ImGui_CreateFont('Arial', 16)
reaper.ImGui_Attach(ctx, font)
font30 = reaper.ImGui_CreateFont('Arial', 30)
reaper.ImGui_Attach(ctx, font30)
reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_KeyRepeatDelay(), 0.5)
--reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_KeyRepeatRate(), 0.2)

--reaper.ImGui_SetConfigVar(ctx,reaper.ImGui_ConfigVar_MacOSXBehaviors(),0)

defaultModifierSettings = {
    ["Title"] = "Same",
    ["Subtitle"] = "Same",
    ["Channel"] = "Increment",
    ["Layer"] = "Increment",
    ["Delay"] = "Same",
    ["Pitch"] = "Same",
    ["Velocity"] = "Fixed",
    ["Note"] = "Same",
    ["CC"] = "Same", 
}

instrumentSettingsDefault = {
    usePDC = true, 
    sustainPedalForcesLegato = true, 
    addKeyswitchNamesToPianoRoll = true, 
    recognizeArticulationsKeyswitches = true
}

function resetCreator()
    --#tableInfo = 0
    mapName = nil
    mapping = {}
    mapping.Note = {} 
    mapping.CC = {}
    subtitles = {}
    titles = {} 
    selectedArticulations = {}  
    modifierSettings = defaultModifierSettings
    mappingType = {}
    tableInfo = {}
    instrumentSettings = instrumentSettingsDefault
    mapName = nil
end
resetCreator()

waitTimeBeforeRetrigger = 0.2
--[[
tableInfo["Title"] = {}
tableInfo["Subtitle"] = {}
tableInfo["Velocity"] = {}
tableInfo["VelocityType"] = {}
tableInfo["Channel"] = {}
tableInfo["Delay"] = {}
tableInfo["Layer"] = {}
tableInfo["Legato"] = {}
tableInfo["Transpose"] = {}
tableInfo["KT"] = {}
]]
loading = true
local minimumsWidth = 650

-- APP SETTINGS
showToolTip = true
autoFitWindow = true



colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0,0)
colorBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.0,0,0,1)
colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.2,0.2,1)
colorGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.4,0.4,1)
colorLightGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.6,0.6,0.6,1)
colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1,1)
colorBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 1,1)
colorAlmostWhite = reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8,1)

colorTabSelected = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.1,0.4,1)
colorTabHovered = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.2,0.6,1)
colorTab = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.1,0.4,0.6)
--[[
mapping.CC[4] = {}
modifierSettings.CC4 = "Same"
modifierSettings.CC4Increment = 1
tableInfo["CC4"] = {}
kts = {"1","2","q","w"}
for i = 1, 4 do 
  tableInfo["CC4"][i] = 20 + i*20
  tableInfo["Title"][i] = "Hej " .. i 
  tableInfo["Subtitle"][i] = "Short"
  tableInfo["KT"][i] = kts[i]
end
]]

-- local number = 7
-- aasqrt_value = math.sqrt(number)
function redCross(id, big)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF0000FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x880000FF)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),6)
    if big then
        buttonValue = reaper.ImGui_Button(ctx, "##" .. id, 20, 20)
    else
        buttonValue = reaper.ImGui_Button(ctx, "##" .. id, 10, 10)
        --buttonValue = reaper.ImGui_SmallButton(ctx, "X##" .. id)
    end 
    
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    local sizeW, sizeH = reaper.ImGui_GetItemRectSize(ctx)
    local x1 = posX + 6
    local x2 = posX + sizeW - 6
    local y1 = posY + 6
    local y2 = posY + sizeH - 6
    reaper.ImGui_DrawList_AddLine(draw_list, x1 , y1, x2, y2, 0xFF0000FF)
    reaper.ImGui_DrawList_AddLine(draw_list, x1 , y2, x2, y1, 0xFF0000FF)
    
    
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_PopStyleVar(ctx)
    return buttonValue
end

function cogwheel(ctx, id, size, lock, tooltipText, lockedColor, unlockedColor, background, hover, active, centerColor)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),background)
    local clicked = false
    
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    if reaper.ImGui_Button(ctx,"##" .. id, size, size) then
        clicked = true
    end 
    if reaper.ImGui_IsItemHovered(ctx) and tooltipText then
        reaper.ImGui_SetTooltip(ctx,tooltipText)    
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    
    local lineThickness = 2
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.5), posY + size * 0.15, posX + size * (0.5), posY + size * 0.85, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.15), posY + size * 0.5, posX + size * (0.85), posY + size * 0.5, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.25), posY + size * 0.25, posX + size * (0.75), posY + size * 0.75, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.25), posY + size * 0.75, posX + size * (0.75), posY + size * 0.25, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, posX + size * 0.52, posY + size * 0.5, size * 0.25, lock and lockedColor or unlockedColor)
    reaper.ImGui_DrawList_AddCircle(draw_list, posX + size * 0.52, posY + size * 0.5, size * 0.14, centerColor,nil, 2)
    
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx)
    
    return clicked 
end

function expandIcon(id, big, enabled)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), enabled and 0x444444FF or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x666666FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x444444FF)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),6)
    local buttonValue
    if big then
        --buttonValue = reaper.ImGui_InvisibleButton(ctx, "X##" .. id, 20, 20)
        buttonValue = reaper.ImGui_Button(ctx, "##" .. id, 20, 20)
    else
        buttonValue = reaper.ImGui_Button(ctx, "##" .. id, 10, 10)
    end 
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    local sizeW, sizeH = reaper.ImGui_GetItemRectSize(ctx)
    local x1 = posX + 4
    local x2 = posX + sizeW -4
    local x3 = x1 + 4
    local x4 = x2 - 4
    local y1 = posY + sizeH / 2
    local y2 = posY + sizeH / 2 - 4
    local y3 = posY + sizeH / 2 + 4
    reaper.ImGui_DrawList_AddLine(draw_list, x1 , y1, x2, y1, colorLightGrey)
    reaper.ImGui_DrawList_AddLine(draw_list, x1 , y1, x3, y2, colorLightGrey)
    reaper.ImGui_DrawList_AddLine(draw_list, x1 , y1, x3, y3, colorLightGrey)
    reaper.ImGui_DrawList_AddLine(draw_list, x2 , y1, x4, y2, colorLightGrey)
    reaper.ImGui_DrawList_AddLine(draw_list, x2 , y1, x4, y3, colorLightGrey)
    
    
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_PopStyleVar(ctx)
    return buttonValue
end

function setToolTipFunc(text, color)
    if showToolTip and text then  
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorWhite) 
        reaper.ImGui_SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx)
    end
end

function createActionButton(data)  
    if data.sameLine then reaper.ImGui_SameLine(ctx) end
    local keyTrigger = nil
    if #data.key > 1 then
        keys = {["up"] = reaper.ImGui_Key_UpArrow(), ["down"] = reaper.ImGui_Key_DownArrow(), ["delete"] = reaper.ImGui_Key_Delete()}
        keyTrigger = keys[data.key]
    else
        keyTrigger = _G["reaper"]["ImGui_Key_" .. data.key]()
    end
    
    if reaper.ImGui_Button(ctx, data.name) or ((not data.ctrl or data.ctrl == ctrl) and (not data.shift or data.shift == shift) and (not data.alt or data.alt == alt) and (not data.cmd or data.cmd == cmd) and reaper.ImGui_IsKeyReleased(ctx, keyTrigger)) then  
        data.func()
    end
    
    setToolTipFunc(data.tip)
    reaper.ImGui_SameLine(ctx)
    local shortcut = (data.ctrl and "ctrl+" or "") .. (data.shift and "shift+" or "") .. (data.alt and "alt+" or "") .. (data.cmd and "cmd+" or "") .. string.lower(data.key)
    reaper.ImGui_TextColored(ctx, 0x777777FF, "(".. shortcut .. ")")
    setToolTipFunc(data.tip)
    
end

        
----------------------------------------------------------------------
----------------------------------------------------------------------
----------------------------------------------------------------------
----------------------------------------------------------------------
function multipleSelectionOptionsInfo(title, modifierNames, modifierKeys, modifierInfo, compact)
    reaper.ImGui_TextColored(ctx, 0x777777FF, "Options for " .. title .. ":")
    --if not modifierSettings[title] then
    --    modifierSettings[title] = modifierNames[1]
    --end
    for i, name in ipairs(modifierNames) do
        --isSelected = modifierSettings[title] == name
        --if not isSelected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
            -- reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Text(),0xFF0000FF)
        --end
        local btnName = modifierKeys and modifierKeys[i] .. " = " .. name or name
        if reaper.ImGui_Button(ctx, btnName) then
            modifierSettings[title] = name
            changeValue = true
        end
        if modifierInfo then 
            setToolTipFunc(modifierInfo[i])
        end

        --if not isSelected then
            reaper.ImGui_PopStyleColor(ctx, 1)
        --end
        
        if changeValue then
            --reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
            for rowKey, counter in pairs(selectedArticulations) do
                tableInfo[rowKey][mappingType[focusedColumn]] = name
            end 
            changeValue = false 
        end 
        
        if i < #modifierNames and i ~= 24 then 
            if compact then
                reaper.ImGui_SameLine(ctx) 
                local posX = reaper.ImGui_GetCursorPosX(ctx) - 16
                reaper.ImGui_SameLine(ctx, posX) 
            else
                reaper.ImGui_SameLine(ctx) 
            end
        end
    end
end

function multipleSelectionOptionsDropDown(title, array)
    reaper.ImGui_TextColored(ctx, 0x777777FF, "Options for " .. title .. ":")
    --if not modifierSettings[title] then
    --    modifierSettings[title] = modifierNames[1]
    --end
    
    local comboText = "\0"
    local selected = 0
    for i, ar in ipairs(array) do
        comboText = comboText .. ar.name.. "\0"
        if tableInfo[focusedRow] and tableInfo[focusedRow][mappingType[focusedColumn]] == ar.name then
            selected = i
        end
    end
    while not tableInfo[focusedRow] do
        focusedRow = focusedRow - 1
    end
    
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    if tableInfo[focusedRow] then 
        if reaper.ImGui_BeginCombo(ctx, "Articulations", tableInfo[focusedRow][mappingType[focusedColumn]]) then --, reaper.ImGui_ComboFlags_WidthFitPreview()) then 
        --ret, val = reaper.ImGui_Combo(ctx, "Articulations", selected, comboText, reaper.ImGui_ComboFlags_WidthFitPreview())
            
            for i, ar in ipairs(array) do
                local isSelected = ar.name == tableInfo[focusedRow][mappingType[focusedColumn]]
                local ret = reaper.ImGui_Selectable(ctx, ar.name, isSelected)
                if ret then
                    tableInfo[focusedRow][mappingType[focusedColumn]] = ar.name
                    for row, val in pairs(tableInfo) do
                        if row ~= focusedRow and tableInfo[row][mappingType[focusedColumn]] == ar.name then
                            tableInfo[row][mappingType[focusedColumn]] = nil
                        end
                    end
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
    end
end



function multipleSelectionOptions(title, modifierNames)
    --reaper.ImGui_SetCursorPosX(ctx, 200)
    if title:match("Note") ~= nil then
        shownTitle = "Note"
    elseif title:match("CC") ~= nil then
        shownTitle = "Controller"
    else
        shownTitle = title
    end
    reaper.ImGui_TextColored(ctx, 0x777777FF, "Fill in options for " .. shownTitle .. ":")
    if not modifierSettings[title] then
        modifierSettings[title] = modifierNames[1]
    end
    for i, name in ipairs(modifierNames) do
        isSelected = modifierSettings[title] == name
        if not isSelected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
            -- reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Text(),0xFF0000FF)
        end
        if not modifierSettings[title .. "Increment"] then
            modifierSettings[title .. "Increment"] = 1
        end
        if cmd and
            reaper.ImGui_IsKeyReleased(ctx, _G["reaper"]["ImGui_Key_" .. i]()) then
            modifierSettings[title] = name
            if isSelected and name == "Increment" then
                popup = name
                modifierSettingsPopupName = title .. name
                modifierSettingsPopupMin = 1
                modifierSettingsPopupMax = 127
            end
        end
        if name == "Increment" then
            isPositive = modifierSettings[title .. name] >= 0
            extendedName = isPositive and "+" or ""
            if reaper.ImGui_Button(ctx, name .. ": " .. extendedName .. modifierSettings[title .. name]) then
                if isSelected then
                    popup = name
                    modifierSettingsPopupName = title .. name
                    modifierSettingsPopupMin = 1
                    modifierSettingsPopupMax = 127
                else
                    modifierSettings[title] = name
                end
            end
        else
            if reaper.ImGui_Button(ctx, name) then
                modifierSettings[title] = name
            end
        end

        if not isSelected then
            reaper.ImGui_PopStyleColor(ctx, 1)
        end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0x777777FF, "(cmd+" .. i .. ")")
        
        
        if i ~= 3 and i < #modifierNames then reaper.ImGui_SameLine(ctx) end
    end
end

function multipleSelectionVelocity(title, modifierNames, defaultType)
    reaper.ImGui_TextColored(ctx, 0x777777FF, "Options for " .. title)

    if not firstSelectedArticulation then
        firstSelectedArticulation = focusedRow
    end
    
    if not tableInfo[firstSelectedArticulation][title .. "Type"] then
        tableInfo[firstSelectedArticulation][title .. "Type"] = defaultType and defaultType or modifierNames[1]
    end
    for i, name in ipairs(modifierNames) do
    
        isSelected = tableInfo[firstSelectedArticulation][title .. "Type"] == name
        if not isSelected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
            -- reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Text(),0xFF0000FF)
        end

        if cmd and
            reaper.ImGui_IsKeyReleased(ctx, _G["reaper"]["ImGui_Key_" .. i]()) then
            for rowKey, counter in pairs(selectedArticulations) do
                tableInfo[rowKey][title .. "Type"] = name
            end
        end

        if reaper.ImGui_Button(ctx, name) then
            for rowKey, counter in pairs(selectedArticulations) do
                tableInfo[rowKey][title .. "Type"] = name
            end
        end

        if not isSelected then
            reaper.ImGui_PopStyleColor(ctx, 1)
        end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0x777777FF, "(cmd+" .. i .. ")")
        
        
        if i % 3 ~= 0 and i < #modifierNames then reaper.ImGui_SameLine(ctx) end
    end
end

-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------

local keyNameTranslation = {
["up"] = reaper.ImGui_Key_UpArrow(), 
["down"] = reaper.ImGui_Key_DownArrow(), 
["delete"] = reaper.ImGui_Key_Delete(),
["minus"] = reaper.ImGui_Key_Minus(),
["keypadMinus"] = reaper.ImGui_Key_KeypadSubtract(),
["plus"] = reaper.ImGui_Key_KeypadAdd(),
}

function createMappingButton(data)   
    local disable = (not devMode and inDevMappings[data.name]) or data.disabled
    if disable then 
        reaper.ImGui_BeginDisabled(ctx) 
    end
    
    if disable and inDevMappings[data.name] then
        data.tip = "IN DEVELOPEMENT: " .. data.tip
    end
     
    if disable and data.disabledText then
        data.tip = data.disabledText
    end
    
    if not data.hide then
        if data.sameLine then reaper.ImGui_SameLine(ctx) end
        local triggerName = data.triggerName and data.triggerName or data.name:gsub("%s", "")
        
        local keyTrigger = nil 
        if not data.key then
            keyTrigger = false
        elseif #data.key > 1 then 
            keyTrigger = keyNameTranslation[data.key]
        else
            keyTrigger = _G["reaper"]["ImGui_Key_" .. data.key]()
        end
        
        if not reaper.ImGui_IsKeyReleased(ctx, keyTrigger) and data.key2 then
            local keyTrigger2 = nil
            if #data.key2 > 1 then 
                keyTrigger2 =  keyNameTranslation[data.key2]
            else
                keyTrigger = _G["reaper"]["ImGui_Key_" .. data.ke2]()
            end
            if keyTrigger2 then
                keyTrigger = keyTrigger2
            end
        end
        
        
        local keyTriggerTrigger = not disable and reaper.ImGui_IsKeyPressed(ctx, keyTrigger, false) -- (data.quickKeyTrigger and reaper.ImGui_IsKeyPressed(ctx, keyTrigger) or reaper.ImGui_IsKeyReleased(ctx, keyTrigger)) or nil
        
        if data.func then
            if reaper.ImGui_Button(ctx, data.name) or (keyTrigger and (not data.ctrl and not ctrl or data.ctrl == ctrl) and (not data.shift and not shift or data.shift == shift) and (not data.alt and not alt or data.alt == alt) and (not data.cmd and not cmd or data.cmd == cmd) and keyTriggerTrigger) then 
                data.func()
            end
        --elseif data.buttonType == "articulation" then
        --    if reaper.ImGui_Button(ctx, data.name) or ((not data.ctrl and not ctrl or data.ctrl == ctrl) and (not data.shift and not shift or data.shift == shift) and (not data.alt and not alt or data.alt == alt) and (not data.cmd and not cmd or data.cmd == cmd) and keyTriggerTrigger) then 
        --        selectNewArt = true 
        --       #tableInfo = #tableInfo + 1
        --    end
        elseif data.buttonType == "popup" then
            if reaper.ImGui_Button(ctx, data.name) or ((not data.ctrl and not ctrl or data.ctrl == ctrl) and (not data.shift and not shift or data.shift == shift) and (not data.alt and not alt or data.alt == alt) and (not data.cmd and not cmd or data.cmd == cmd) and keyTriggerTrigger) then 
                popup = triggerName
            end
        elseif data.buttonType == "multi" then
            if reaper.ImGui_Button(ctx, data.name) or ((not data.ctrl and not ctrl or data.ctrl == ctrl) and (not data.shift and not shift or data.shift == shift) and (not data.alt and not alt or data.alt == alt) and (not data.cmd and not cmd or data.cmd == cmd) and keyTriggerTrigger) then 
                if triggerName == "Note realtime" then
                    table.insert(instrumentSettings.realtimeTrigger, {"Note", "", "", ""})
                elseif triggerName == "Channel realtime" then 
                    table.insert(instrumentSettings.realtimeTrigger, {"Channel", nil, "", ""})
                elseif triggerName == "Velocity realtime" then 
                    table.insert(instrumentSettings.realtimeTrigger, {"Velocity", nil, "", ""})
                else
                    table.insert(mapping[triggerName], #mapping[triggerName] + 1)
                    setFocusOnNewMapping = triggerName .. #mapping[triggerName]
                    modifierSettings[setFocusOnNewMapping] = "Same"
                    tableInfo[setFocusOnNewMapping] = {}
                end
            end
        else
            if not mapping[triggerName] then
                if reaper.ImGui_Button(ctx, data.name) or ((not data.ctrl and not ctrl or data.ctrl == ctrl) and (not data.shift and not shift or data.shift == shift) and (not data.alt and not alt or data.alt == alt) and (not data.cmd and not cmd or data.cmd == cmd) and keyTriggerTrigger) then 
                    mapping[triggerName] = true
                    setFocusOnNewMapping = data.focusName and data.focusName or data.name
                end
            else
                if redCross(triggerName .. "Remove", true) then
                    mapping[triggerName] = nil
                    undo_redo.commit({tableInfo, mapping})
                end 
                setToolTipFunc("Remove " .. data.name .. " from mapping")
                reaper.ImGui_SameLine(ctx, 20)
                reaper.ImGui_Text(ctx, data.name)
            end  
        end
        setToolTipFunc(data.tip)
        
        if data.key and not data.doNotshowShortCut then
            reaper.ImGui_SameLine(ctx)  
            local shortcut = (data.ctrl and "ctrl+" or "") .. (data.shift and "shift+" or "") .. (data.alt and "alt+" or "") .. (data.cmd and "cmd+" or "") .. string.lower(data.key)  
            reaper.ImGui_TextColored(ctx, 0x777777FF, "(".. shortcut .. ")")
            setToolTipFunc(data.tip) 
        end
    end 
    if disable then 
        reaper.ImGui_EndDisabled(ctx)
    end
end

local firstLoop = true



local function loop()

    reaper.ImGui_SetNextWindowBgAlpha(ctx, 1) -- Transparent background

    local visible, open = reaper.ImGui_Begin(ctx, 'Articulation Creator', true,
    -- reaper.ImGui_WindowFlags_NoDecoration() |
                                             reaper.ImGui_WindowFlags_TopMost() -- | reaper.ImGui_WindowFlags_NoMove()
    -- | reaper.ImGui_WindowFlags_NoBackground()
    -- | reaper.ImGui_FocusedFlags_None() 
    | reaper.ImGui_WindowFlags_NoTitleBar() -- | reaper.ImGui_WindowFlags_AlwaysAutoResize()
    --| reaper.ImGui_WindowFlags_MenuBar()
    )

    if visible then
        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        enterDown = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Enter())
        enter = reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_Enter())
        escape = reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_Escape())
        mouseDown = reaper.ImGui_IsMouseClicked(ctx, 0, false)
        mouseRelease = reaper.ImGui_IsMouseReleased(ctx, 0)
        downArrow = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_DownArrow())
        upArrow = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_UpArrow())
        leftArrow = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftArrow())
        rightArrow = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightArrow())
        tab = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Tab())
        mouse_pos_x, mouse_pos_y = reaper.ImGui_GetMousePos(ctx)
        
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)

        windowWidth = reaper.ImGui_GetWindowSize(ctx) 
        reaper.ImGui_PushFont(ctx, font, 16)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),4)
        
        --reaper.ImGui_SetCursorPosX(ctx,windowWidth / 2 - 440/2)
        function closeApp()
            closeAppWindow = true -- workaround for some reason needed
        end
        
        reaper.ImGui_BeginGroup(ctx)
        
        if redCross("CloseApp", true) or (cmd and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_W())) then 
            popupOkCancelTitle = 'Close app?'
            popupOkCancelDescription = 'Do you want to close this window.\n\nAll non saved settings will be lost!!' 
            popupOkCancelFunc = closeApp
            reaper.ImGui_OpenPopup(ctx, popupOkCancelTitle)  
        end 
        setToolTipFunc("Close Articulation Map Creator (cmd+w)")
        
        
        if expandIcon("expandWindow", true, appSettings.expandWindow) or (cmd and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_R())) then
            appSettings.expandWindow = not appSettings.expandWindow
            saveAppSettings()
        end
        setToolTipFunc("Auto resize window to table (cmd+r)")
        
        reaper.ImGui_EndGroup(ctx)
        
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 100000)
        
        reaper.ImGui_PushFont(ctx, font, 34)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
        reaper.ImGui_Text(ctx, 'ARTICULATION SCRIPT CREATOR')
        --if reaper.ImGui_Button(ctx, 'ARTICULATION SCRIPT CREATOR') then
            --showSettings = not showSettings 
        --end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_PopFont(ctx)
        
        --setToolTipFunc("Show app settings")
        
        
        reaper.ImGui_SameLine(ctx) 
        reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) - 6) 
        if cogwheel(ctx, "settings", 40, showSettings, "Show app settings",colorWhite,  colorGrey, colorTransparent, colorDarkGrey, colorTransparent, colorBlack) then
            showSettings = not showSettings
        end
        
        --if reaper.ImGui_BeginMenu(ctx, "Options") then
            if showSettings then  
                local license = require("check_license")
                local email = license.registered_license()
                local licenseText = email and ("Licensed to: " .. email) or "No license"
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey)
                if reaper.ImGui_Button(ctx, licenseText) then
                    license.openLicenseWindow(true)  
                end 
                reaper.ImGui_PopStyleColor(ctx, 2)
                
                ret, val = reaper.ImGui_Checkbox(ctx, "Always overwrite maps", appSettings.alwaysOverwriteApps)
                if ret then 
                    appSettings.alwaysOverwriteApps = val
                    saveAppSettings()
                end 
                
                ret, val = reaper.ImGui_Checkbox(ctx, "Always embed UI in TCP", appSettings.alwaysEmbedUi)
                if ret then 
                    appSettings.alwaysEmbedUi = val
                    saveAppSettings()
                end 
                setToolTipFunc("When adding a script to a track, embed the UI in the TCP")
                
                
            end
            
        --    reaper.ImGui_EndMenu(ctx)
        --end
        
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), colorTabSelected)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), colorTabHovered)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), colorTab)

        --reaper.ImGui_SameLine(ctx)
        --reaper.ImGui_InvisibleButton(ctx, "close", 30, 30) 
        --reaper.ImGui_SameLine(ctx)  
        --headerWidth = reaper.ImGui_GetCursorPosX(ctx) 
        --reaper.ImGui_NewLine(ctx)
        
        --windowW, windowH = reaper.ImGui_GetWindowSize(ctx)
        --if not lastWindowW or lastWindowW ~= windowW then
        --    lastWindowW = windowW
        --end
        --reaper.ImGui_SameLine(ctx, lastWindowW - 30)
        

        reaper.ImGui_Separator(ctx)
        -- mapName = "test"
        -- reaper.ImGui_Text(ctx, 'Map name: ' .. mapName) 
        -- Infinite Brass Trumpet
        if not mapName then
            reaper.ImGui_Text(ctx, "Write a name for a new map:")
            if not focusNameInput or focusNameInput > 10 then
                reaper.ImGui_SetKeyboardFocusHere(ctx);
                focusNameInput = 0
            end
            ret, stringInput = reaper.ImGui_InputText(ctx, "##nameinput", nil, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
            if ret then mapName = stringInput end
            
            if not reaper.ImGui_IsItemFocused(ctx) and not popupOkCancelTitle then
                focusNameInput = focusNameInput + 1
            end
        else
            -- reaper.ImGui_TextColored(ctx,0x777777FF,"Map name:")
            -- reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushFont(ctx, font, 30)
            if reaper.ImGui_Button(ctx, mapName, 380) or
                (cmd and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_R())) then
                popup = "Name"
                mapNameButton = ""
                popupStringName = mapName or ""
            end
            reaper.ImGui_PopFont(ctx)
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0x777777FF, "(cmd+r)")

        end

        function newMap()
            if #tableInfo > 0 then   
                popupOkCancelTitle = 'Create new script?'
                popupOkCancelDescription = 'Do you want to create a new articualtion script.\n\nAll settings will be reset!!'
                popupOkCancelFunc = resetCreator
                reaper.ImGui_OpenPopup(ctx, popupOkCancelTitle) 
            else
                resetCreator()  
            end
        end

        function editFirstSelected(firstArticulationScriptOnFirstSelectedTrack)
            if firstArticulationScriptOnFirstSelectedTrack then
                if #tableInfo > 0 then   
                    popupOkCancelTitle = 'Edit other articulation script?'
                    popupOkCancelDescription = 'Edit articulation script from first selected track?\n\nAll non-saved settings will be lost!!'
                    popupOkCancelFunc = importTable
                    popupOkCancelFuncVal = firstArticulationScriptOnFirstSelectedTrack
                    reaper.ImGui_OpenPopup(ctx, popupOkCancelTitle) 
                else
                    importTable(firstArticulationScriptOnFirstSelectedTrack)
                end
            end
        end
        
        function popupOkCancel(title, message, func, funcVal)
            -- Always center this window when appearing
            local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
            reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
            
            if reaper.ImGui_BeginPopupModal(ctx, title, nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
              reaper.ImGui_Text(ctx, message)
              reaper.ImGui_NewLine(ctx)
              reaper.ImGui_Separator(ctx)
            
              --static int unused_i = 0;
              --ImGui.Combo("Combo", &unused_i, "Delete\0Delete harder\0");
            
              --ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
              --rv,popups.modal.dont_ask_me_next_time =
              --  ImGui.Checkbox(ctx, "Don't ask me next time", popups.modal.dont_ask_me_next_time)
              --ImGui.PopStyleVar(ctx)
            
              if reaper.ImGui_Button(ctx, 'OK', 120, 0) or enter then  
                  func(funcVal)
                  reaper.ImGui_CloseCurrentPopup(ctx)  
                  popupOkCancelTitle = nil
              end
              reaper.ImGui_SetItemDefaultFocus(ctx)
              reaper.ImGui_SameLine(ctx)
              if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or escape then 
                  reaper.ImGui_CloseCurrentPopup(ctx) 
                  popupOkCancelTitle = nil
              end
              reaper.ImGui_EndPopup(ctx)
            end
        end
        
        
        
        function popupOk(title, message)
            -- Always center this window when appearing
            local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
            reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
            
            if reaper.ImGui_BeginPopupModal(ctx, title, nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
              reaper.ImGui_Text(ctx, message)
              reaper.ImGui_NewLine(ctx)
              reaper.ImGui_Separator(ctx)
            
              if reaper.ImGui_Button(ctx, 'OK', 120, 0) or enter then  
                  reaper.ImGui_CloseCurrentPopup(ctx)  
                  popupOkCancelTitle = nil
              end
              reaper.ImGui_SetItemDefaultFocus(ctx)
              reaper.ImGui_EndPopup(ctx)
            end
        end
        
        
        local firstArticulationPath = getFirstArticulationMapFXJsonLine(true)
        local buttonsData = {{
          name = "New", key = "N", cmd = true, sameLine = false, func = function() newMap() end,
          tip = 'Create a new map', disabled = not mapName --#tableInfo == 0
        },{
          name = "Edit first selected", key = "E", cmd = true, sameLine = true, func = function() editFirstSelected(firstArticulationPath) end,
          tip = "Edit articulation map on first selected track.", 
          disabled = not firstArticulationPath, 
          disabledText = "No articulation map matching this format on selected track"
        },{
          name = "Open", key = "O", cmd = true, sameLine = false, func = function() importTable() end,
          tip = "Open an existing articulation map."
        },{
          name = "Folder", key = "F", cmd = true, sameLine = true, func = function() openArticulationFolder() end,
          tip = "Show folder containing articulation maps."
        },{
          name = "Save", key = "S", cmd = true, sameLine = true, func = function() export.createObjectForExport() end,
          tip = "Save the current map", hide = #tableInfo == 0, buttonType = "action"
        }}
        for _, data in ipairs(buttonsData) do
            createMappingButton(data) 
        end
        
        
        -- NOW WE ARE ABLE TO LOOK THROUGH AND ENSURE IT's only one character. It would be great to be able to match it to a string specifically
        if not reaper.ImGui_ValidatePtr(filterFunction3Characters, 'ImGui_Function*') then
            filterFunction3Characters = reaper.ImGui_CreateFunctionFromEEL([[
                strlen(#Buf) > 3 ? ( 
                    c = str_getchar(#Buf, 3);
                    str_setchar(#first, 0, c);
                    InputTextCallback_DeleteChars(0, strlen(#Buf));
                    InputTextCallback_InsertChars(0, #first);
                );
                
            ]])
            reaper.ImGui_Function_SetValue_String(filterFunction3Characters, '#allowed', reaper.ImGui_InputTextFlags_CallbackEdit())
        end
        
        
        local legatoSelection = {"First", "Legato", "Repeated", "First+Repeated", "Any"}
        local legatoInfo = {"Trigger on the first note of a phrase.\nThis is only useful for monophonic material.", "Trigger on notes connected to the first note, eg the legato note after.", "Trigger if a note is repeated by being connected to the previous note", "Trigger if a note is the first note or repeated by being connected to the previous note", "Trigger anytime. This might be useful when using layers"}
        local legatoKeys = {"F", "L", "R", "X", "A"}

        if mapName then
            --reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)
            if #tableInfo == 0 then
                reaper.ImGui_Text(ctx, "Amount of new articaultions to add:")
                if not focusTrackAmountInput then
                    reaper.ImGui_SetKeyboardFocusHere(ctx);
                    focusTrackAmountInput = true
                end
                ret, stringInput = reaper.ImGui_InputText(ctx, "##art", 1, reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                if ret and tonumber(stringInput) then
                    --#tableInfo = tonumber(stringInput)
                    addArticulation(tonumber(stringInput))
                end
            else  
                if reaper.ImGui_BeginTabBar(ctx, 'MyTabBar') then  
                    
                    
                    
                    local filterNames = {"Position", "FilterChannel", "FilterPitch", "FilterVelocity", "FilterSpeed", "FilterInterval", "FilterCount"}
                    local hasFilterMapping = false
                    for _, filterMappings in ipairs(filterNames) do
                        if mappingType then
                            for _, exisitingMappings in ipairs(mappingType) do
                                if filterMappings == exisitingMappings then
                                    hasFilterMapping = true
                                    break
                                end
                            end
                        end
                    end
                    
                    --mappingsFlag = reaper.ImGui_TabItemFlags_SetSelected()
                    tipTable = {}
                    openMappingsTab = cmd and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_M())
                    mappingsTabFlag = openMappingsTab and reaper.ImGui_TabItemFlags_SetSelected() or nil
                    if reaper.ImGui_BeginTabItem(ctx, 'Mappings (cmd+m)', openMappingsTab, mappingsTabFlag) then
                        reaper.ImGui_Spacing(ctx)
                        local buttonsData = {{
                        name = "Add Articulation", key = "A", cmd = true, func = function() addArticulation() end,
                        },{
                        name = "Add Multiple Articulations", triggerName = "Art", key = "A",cmd = true, ctrl = true, buttonType = "popup", sameLine = true
                        },{
                        name = "Duplicate", key = "D",cmd = true, func = function() duplicateRows() end, sameLine = false
                        }}
                        
                        if hasFilterMapping then
                            table.insert(buttonsData, {
                            name = "Add Filter Lane", key = "L",cmd = true, func = function() addLane() end, sameLine = true
                            })
                            table.insert(buttonsData, {
                            name = "Articulation <> Lane", key = "L", cmd = true, ctrl = true, func = function()  makeArticulationALaneOrNot() end, sameLine = true, 
                            tip = "Swap row between being an articulation or lane"
                            })
                        end
                        
                        for _, data in ipairs(buttonsData) do
                            createMappingButton(data) 
                        end
                        
                        
                        reaper.ImGui_Separator(ctx)
                        --if reaper.ImGui_BeginChild(ctx, 'mappingChild', 300, 320, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_ResizeY()) then
                        mappingX, MappingY = reaper.ImGui_GetCursorPos(ctx)
                        reaper.ImGui_BeginGroup(ctx)
                            
                            reaper.ImGui_TextColored(ctx, 0x777777FF, "Mappings:")
                            
                            buttonsData = {{
                            name = "Controller", triggerName = "CC", key = "C", ctrl = true, buttonType = "popup",
                            tip = "Add a CC switch to the articulation."
                            },{
                            name = "Note", triggerName = "Note", key = "N", ctrl = true, buttonType = "multi",
                            tip = "Add a note keyswitch to the articulation."
                            },{
                            --name = "Note Held", triggerName = "NoteH", key = "H", ctrl = true, buttonType = "multi",
                            --tip = "Add a held note keyswitch to the articulation."
                            --},{
                            name = "Velocity", key = "V", ctrl = true, triggerName = "Velocity", 
                            tip = "Make note a specific velocity.\nCan also be used to just limit the velocity range."
                            },{
                            name = "Channel",key = "X", ctrl = true,triggerName = "Channel", 
                            tip = "Send articulation and note to sepecific channel."
                            },{
                            name = "Delay", key = "D", ctrl = true,triggerName = "Delay", 
                            tip = "Delay articulation and note in miliseconds.\nUsually used together with a negative track delay."
                            },{
                            name = "Pitch", key = "P", ctrl = true, triggerName = "Pitch", 
                            tip = "Make note a specific pitch.\nThis is great for remapping notes to a percussion instrument."
                            }}
                            
                            for _, data in ipairs(buttonsData) do
                                createMappingButton(data) 
                                tipTable[data.triggerName] = data.tip
                            end
                        reaper.ImGui_EndGroup(ctx)
                        
                        _, MappingEndsY = reaper.ImGui_GetCursorPos(ctx)
                        --reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_SetCursorPos(ctx, mappingX + 160, MappingY)
                        
                        reaper.ImGui_BeginGroup(ctx)
                            --reaper.ImGui_Separator(ctx) 
                            reaper.ImGui_TextColored(ctx, 0x777777FF, "Filter incoming:")  
                            
                            local buttonsData = {{
                            name = "Position (Legato)", triggerName = "Position", key = "P", ctrl = true,
                            tip = "Filter articulation based on position in legato phrase." -- could extend to numbers in phrase maybe
                            },{
                            name = "Filter Channel", triggerName = "FilterChannel", key = "C", ctrl = true, shift = true,
                            tip = "Filter based on incoming channel"
                            },{
                            name = "Filter Pitch", triggerName = "FilterPitch", key = "P", ctrl = true, shift = true,
                            tip = "Filter based on incoming velocity"
                            },{
                            name = "Filter Velocity", triggerName = "FilterVelocity", key = "V", ctrl = true, shift = true,
                            tip = "Filter based on incoming velocity"
                            },{
                            name = "Filter Speed", triggerName = "FilterSpeed", key = "S", ctrl = true, shift = true,
                            tip = "Filter based on speed of notes, from last note to the next"
                            },{
                            name = "Filter Interval", triggerName = "FilterInterval", key = "I", ctrl = true, shift = true,
                            tip = "Filter based on inteval of notes, from last note to the next"
                            },{
                            name = "Filter Note Count", triggerName = "FilterCount", key = "N", ctrl = true, shift = true,
                            tip = "Filter based on note count pressed"
                            }}

                            for _, data in ipairs(buttonsData) do
                                createMappingButton(data) 
                                --table.insert(filterNames, data.triggerName)
                                tipTable[data.triggerName] = data.tip
                            end 
                            
                            
                            function findMainRowForArticulationLane(laneName)
                                local newTable = {}
                                local laneAmount = 0
                                local typeTable = tableInfo.Title 
                                rowFromName = laneName:gsub("!!Lane:","")
                                for i = 1, #tableInfo do
                                    if typeTable[i] and typeTable[i]:match("!!Lane") ~= nil then
                                        laneAmount = laneAmount + 1
                                    end
                                    if tostring(i - laneAmount) == tostring(rowFromName) then
                                        return i
                                    end
                                end
                            end
                            
                            --[[
                            function addFilterLane()
                                local newTable = {}
                                local laneAmount = 0
                                for key, typeTable in pairs(tableInfo) do 
                                    newTable[key] = {}
                                    for i = 1, #tableInfo do
                                        if typeTable[i] then
                                            if i > focusedRow then
                                                newTable[key][i+1] = typeTable[i]
                                            else
                                                newTable[key][i] = typeTable[i]
                                            end
                                        end
                                        if i == focusedRow then
                                            if key == "Title" then 
                                                newTable[key][i+1] = (typeTable[i] and typeTable[i]:match("!!Lane") ~= nil) and typeTable[i] or "!!Lane:" .. (focusedRow - laneAmount)
                                            else
                                                newTable[key][i+1] = ""
                                            end
                                        end
                                        if key == "Title" and typeTable[i] and typeTable[i]:match("!!Lane") ~= nil then 
                                            laneAmount = laneAmount + 1
                                        end
                                    end
                                end
                                tableInfo = newTable
                                --#tableInfo = #tableInfo + 1
                            end
                            
                            function removeFilterLane()
                                isLane = tableInfo[focusedRow].isLane
                                local lastLaneOfArticulation = isLane and focusedRow or nil
                                if not isLane then 
                                    local onLaneFound = false
                                    for i = focusedRow + 1, #tableInfo do  
                                        if tableInfo[i].isLane then
                                            onLaneFound = true
                                        end
                                        if onLaneFound and not tableInfo[focusedRow].isLane then
                                            lastLaneOfArticulation = i - 1
                                            break;
                                        end
                                    end 
                                end
                                if lastLaneOfArticulation then
                                    local newTable = {}
                                    for key, typeTable in pairs(tableInfo) do 
                                        newTable[key] = {}
                                        for i = 1, #tableInfo do 
                                            if typeTable[i] then
                                                if i < lastLaneOfArticulation then
                                                    newTable[key][i] = typeTable[i]
                                                elseif i > lastLaneOfArticulation then
                                                    newTable[key][i-1] = typeTable[i]
                                                end
                                            end
                                        end
                                    end
                                    tableInfo = newTable
                                    #tableInfo = #tableInfo - 1
                                end
                            end
                            
                            buttonsData = {{
                            name = "Add", key = "A", ctrl = true, shift = true, func = function() addFilterLane() end,
                            tip = "Add one more filter lane to articulations" -- could extend to numbers in phrase maybe
                            },{
                            name = "Remove", key = "R", ctrl = true, shift = true, func = function() removeFilterLane() end,
                            tip = "Remove the last filter lane from articulations"
                            }}
                            
                            
                            
                            if lol and hasFilterMapping and focusedRow then 
                                reaper.ImGui_TextColored(ctx, 0x777777FF, "Filter lanes:")
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x22AA2255)
                                for _, data in ipairs(buttonsData) do
                                    createMappingButton(data) 
                                end 
                                reaper.ImGui_PopStyleColor(ctx) 
                            end
                            
                            
                            ]]
                            
                        reaper.ImGui_EndGroup(ctx)
                        
                        --reaper.ImGui_SameLine(ctx) 
                        reaper.ImGui_SetCursorPos(ctx, mappingX + 400, MappingY)
                        
                        reaper.ImGui_BeginGroup(ctx)
                            --reaper.ImGui_Separator(ctx) 
                            reaper.ImGui_TextColored(ctx, 0x777777FF, "Extras:")  
                            
                            local buttonsData = {{
                            name = "Subtitle", key = "S", ctrl = true, triggerName = "Subtitle",
                            tip = "Add a subtitle to articulations."
                            },{
                            name = "Layer", key = "L", ctrl = true,triggerName = "Layer", 
                            tip = "Add Layers to triggers, to have multilayered articulations.\nMultiple layers will be triggered based on articulation name."
                            },{
                            name = "Transpose", key = "T", ctrl = true, triggerName = "Transpose",
                            tip = "Transpose notes when articulation is selected."
                            },{
                            name = "Interval Trigger", key = "I", ctrl = true, focusName = "Interval", triggerName = "Interval",
                            tip = "Add trill note to articulations."
                            },{
                            name = "Keyboard Trigger", key = "K", ctrl = true, focusName = "KT", triggerName = "KeyboardTrigger",
                            tip = "Set Computer Keyboard Articulation controller keys how you like."
                            },{
                            name = "Live Articulation", key = "Q", ctrl = true,triggerName = "LiveArticulation", 
                            tip = "Send note keyswitches and CCs when clicking articulation instead of attaching it to a note.\nThis will not use 'Delay' and 'Layer' or mappings who's relate to incoming notes"
                            },{
                            name = "Notation", key = "O", ctrl = true,triggerName = "Notation", 
                            tip = "Use notation articulations for triggering"
                            },{
                            name = "UI Text", key = "U", ctrl = true,triggerName = "UIText", 
                            tip = "Add user defined text on the script UI"
                            }}
                            
                            for _, data in ipairs(buttonsData) do
                                createMappingButton(data) 
                                tipTable[data.triggerName] = data.tip
                            end
                            
                        reaper.ImGui_EndGroup(ctx)
                        
                        reaper.ImGui_SameLine(ctx)
                        headerWidth = reaper.ImGui_GetCursorPosX(ctx)
                        reaper.ImGui_NewLine(ctx)
                        
                        
                        reaper.ImGui_SetCursorPos(ctx, mappingX, MappingEndsY + 100)
            
                        reaper.ImGui_Separator(ctx)

                        function selectAllRows()
                            for r = 1, #tableInfo do
                                selectedArticulations[r] = r
                            end
                        end
      
      
                        if deleteRowsAction then
                            if deleteRowsAction > 4 then
                                deleteRows()
                                deleteRowsAction = nil
                            else
                                deleteRowsAction = deleteRowsAction + 1
                            end
                        end
                        
                        if moveRowsAction then
                            if moveRowsAction > 4 then
                                moveRows(moveRowsDirection)
                                moveRowsAction = nil
                            else
                                moveRowsAction = moveRowsAction + 1
                            end
                        end
                        
                                                
                        
                        local buttonsData = {{
                        name = "Select all rows", key = "A", cmd = true, shift = true, sameLine = false, func = function() selectAllRows(true) end,
                        tip = 'Select all rows'
                        },{
                        name = "Import clipboard", key = "V", cmd = true, shift = true, sameLine = true, func = function() importArticulationSet() end,
                        tip = 'Import clipboard.\n - A new line is a new row.\n - ";" seperates columns.\n\n-Example:\nShort;C0;10\nLong;D0;11\nFX;E0;12'
                        },{
                        name = "Move up rows", key = "up", cmd = true, alt = true, sameLine = false, func = function() moveRowStart(true) end,
                        tip = "Move selected articulations rows up"
                        },{
                        name = "Move down rows", key = "down", cmd = true, alt = true, sameLine = true, func = function() moveRowStart(false) end,
                        tip = "Move selected articulations rows up"
                        },{
                        name = "Delete rows", key = "delete", cmd = true, sameLine = false, func = function() deleteRowsStart() end,
                        tip = "Deleted selected articulations rows"
                        },{
                        name = "Delete column", key = "delete",shift = true, cmd = true, sameLine = true, func = function() deleteColumn() end,
                        tip = "Deleted selected focused column"
                        },{
                        name = "Undo", cmd = true, ctrl = true, key = "Z",
                        tip = "Undo last action", sameLine = false,
                        func = function() 
                            local t = undo_redo.undo({tableInfo, mapping}) 
                            tableInfo = t[1]
                            mapping = t[2]
                        end, quickKeyTrigger = true
                        },{
                        name = "Redo", cmd = true, ctrl = true, shift = true, key = "Z",
                        tip = "Redo last action", sameLine = true,
                        func = function() 
                            local t = undo_redo.redo({tableInfo, mapping}) 
                            tableInfo = t[1]
                            mapping = t[2]
                        end, quickKeyTrigger = true
                        }}
                        for _, data in ipairs(buttonsData) do
                            createMappingButton(data) 
                        end

                        reaper.ImGui_Separator(ctx) 
                
                        

                        ------------ INPUTS -------------------
                        
                        --if focusedColumn then reaper.ShowConsoleMsg(focusedColumn .. "\n") end
                        reaper.ImGui_BeginGroup(ctx)
                        if focusedColumn and mappingType[focusedColumn] 
                            --and (mappingType[focusedColumn] ~= "KT") 
                            --and (mappingType[focusedColumn] ~= "Layer") 
                            then
                            --reaper.ImGui_SameLine(ctx)
                            
                            --
                            
                            -- #selectedArticulationsCountKeys = 0 
                            -- for _,_ in ipairs(selectedArticulations) do #selectedArticulationsCountKeys = #selectedArticulationsCountKeys + 1 end
                            -- if not focusedColumn then focusedColumn = 1 end
                            mappingTypeName = mappingType[focusedColumn]
                            --reaper.ImGui_SetCursorPosY(ctx, artY)
                            if mappingType[focusedColumn] and mappingTypeName == "Title" then
                                local modifierNames = {"Same", "Increment"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "Subtitle" then
                                local modifierNames = {"Same", "Increment"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and mappingTypeName:match("CC") ~= nil then
                                local modifierNames = {"Same", "Increment", "Even Divided"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName:match("Note") ~= nil then
                                local modifierNames = { "Same", "Increment", "Chromatic", "White Keys", "Black Keys" }
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                                
                                reaper.ImGui_SameLine(ctx)
                                local column_name = mappingType[focusedColumn]
                                local isHeld = false
                                for row, v in ipairs(tableInfo) do
                                    if tableInfo[row][column_name .. "Held"] then
                                        isHeld = true
                                    end
                                end
                                
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isHeld and 0x22AA2299 or colorTransparent)
                                local buttenName = "Notes Held: " .. (isHeld and "On" or "Off") .. "##mappingsettings"
                                if reaper.ImGui_Button(ctx, buttenName) or (cmd and reaper.ImGui_IsKeyReleased(ctx, _G["reaper"]["ImGui_Key_" .. 6]())) then 
                                    for row, v in ipairs(tableInfo) do 
                                        tableInfo[row][column_name .. "Held"] = not isHeld and true or nil
                                    end
                                    
                                end
                                
                                reaper.ImGui_PopStyleColor(ctx, 1)
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_TextColored(ctx, 0x777777FF, "(cmd+" .. #modifierNames + 1 .. ")")
                                
                                --[[
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x22AA2299)
                                
                                local modifierSettingsPopupName = mappingTypeName .. "Velocity"
                                local hasVel = tableInfo[modifierSettingsPopupName] and tableInfo[modifierSettingsPopupName][focusedRow]
                                local velText = (hasVel and "Remove " or "Set ") .. "velocity"
                                if reaper.ImGui_Button(ctx, velText) or (cmd and reaper.ImGui_IsKeyReleased(ctx, _G["reaper"]["ImGui_Key_" .. 6]())) then 
                                    for rowKey, counter in pairs(selectedArticulations) do
                                        if hasVel then
                                            tableInfo[modifierSettingsPopupName][rowKey] = nil
                                        else
                                            if not tableInfo[modifierSettingsPopupName] then tableInfo[modifierSettingsPopupName] = {} end
                                            tableInfo[modifierSettingsPopupName][rowKey] = 127
                                        end
                                    end
                                end
                        
                                reaper.ImGui_PopStyleColor(ctx, 1)
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_TextColored(ctx, 0x777777FF, "(cmd+" .. #modifierNames + 1 .. ")")
                                ]]
                                
                            elseif mappingType[focusedColumn] and  mappingTypeName == "Channel" then
                                local modifierNames = {"Same", "Increment"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "Velocity" then
                                local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and mappingTypeName == "Delay" then
                                local modifierNames = {"Same"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and mappingTypeName == "Pitch" then
                                local modifierNames = { "Same", "Increment", "Chromatic", "White Keys", "Black Keys" }
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                                --local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                --multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "Layer" then
                                local modifierNames = {"Same", "Increment"}
                                multipleSelectionOptions(mappingTypeName, modifierNames) 
                            elseif mappingType[focusedColumn] and  mappingTypeName == "Transpose" then
                                local modifierNames = {"Same", "Increment"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "Interval" then
                                local modifierNames = {"Same", "Increment"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)  
                            elseif mappingType[focusedColumn] and mappingTypeName == "Position" then
                                local modifierNames = legatoSelection
                                multipleSelectionOptionsInfo(mappingTypeName, modifierNames, legatoKeys, legatoInfo)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "FilterChannel" then
                                local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "FilterPitch" then
                                local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "FilterVelocity" then
                                local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "FilterSpeed" then
                                 local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                 multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "FilterInterval" then
                                 local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                 multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingType[focusedColumn] and  mappingTypeName == "FilterCount" then
                                local modifierNames = {"Fixed", "Minimum", "Maximum", "Within", "Outside"}
                                multipleSelectionVelocity(mappingTypeName, modifierNames)
                            elseif mappingTypeName == "KT" then
                                --reaper.ImGui_TextColored(ctx, 0x777777FF, "Options for keyboard triggers:")
                                --reaper.ImGui_TextColored(ctx, 0xFFFFFFFF, "0-9 and A-Z")  
                                multipleSelectionOptionsInfo("Keyboard Triggers", keyboardTableKeysOrder, nil, nil, true)
                            elseif mappingTypeName == "Notation" then
                                --reaper.ImGui_TextColored(ctx, 0x777777FF, "Options for keyboard triggers:")
                                --reaper.ImGui_TextColored(ctx, 0xFFFFFFFF, "0-9 and A-Z")  
                                multipleSelectionOptionsDropDown("Notation", musicxml.articulations)
                                
                                --reaper.ImGui_InvisibleButton(ctx,"dummy",16,2)
                            elseif mappingType[focusedColumn] and mappingTypeName == "UIText" then
                                local modifierNames = {"Same"}
                                multipleSelectionOptions(mappingTypeName, modifierNames)
                            end
                        
                            if mappingTypeName 
                            and mappingTypeName:match("Note") == nil 
                            and mappingTypeName:match("Velocity") == nil 
                            and mappingTypeName:match("FilterVelocity") == nil 
                            and mappingTypeName:match("FilterSpeed") == nil 
                            and mappingTypeName:match("FilterInterval") == nil 
                            and mappingTypeName:match("FilterCount") == nil 
                            and mappingTypeName:match("FilterChannel") == nil 
                            and mappingTypeName:match("FilterPitch") == nil 
                            and mappingTypeName:match("Pitch") == nil 
                            and mappingTypeName:match("KT") == nil 
                            --and mappingTypeName:match("Notation") == nil 
                            then 
                                reaper.ImGui_InvisibleButton(ctx,"dummy",16,22)
                            end
                        else 
                            reaper.ImGui_TextColored(ctx, 0x777777FF, "Fill in options..")
                            reaper.ImGui_InvisibleButton(ctx,"dummy1",16,22)
                            reaper.ImGui_InvisibleButton(ctx,"dummy2",16,22)
                            --
                        end
                        reaper.ImGui_EndGroup(ctx)
                    
            
                    
                        tableX, tableY = reaper.ImGui_GetCursorPos(ctx)
            
                    
            
                        -- flags =reaper.ImGui_WindowFlags_NoMove() | reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_TopMost()
                        -- reaper.ImGui_FocusedFlags_NoPopupHierarchy()
                
                        mappingType = {}
                        table.insert(mappingType, "Title") 
                        
                        if mapping.Subtitle then table.insert(mappingType, "Subtitle") end
                        
                        
                        if mapping.Notation then table.insert(mappingType, "Notation") end
                        
                        for key, value in pairs(mapping.CC) do
                            table.insert(mappingType, "CC" .. key)
                        end
                        firstColumnForNote = #mappingType
                        aaa = mapping
                        for key, value in pairs(mapping.Note) do
                            table.insert(mappingType, "Note" .. key)
                            --table.insert(mappingType, "NoteM" .. key.."Velocity")
                        end
                        
                        if mapping.Layer then table.insert(mappingType, "Layer") end
                        if mapping.Velocity then table.insert(mappingType, "Velocity") end
                        if mapping.Channel then table.insert(mappingType, "Channel") end
                        if mapping.Delay then table.insert(mappingType, "Delay") end
                        if mapping.Pitch then table.insert(mappingType, "Pitch") end
                        if mapping.Transpose then table.insert(mappingType, "Transpose") end
                        if mapping.Interval then table.insert(mappingType, "Interval") end
                        
                        if mapping.Position then table.insert(mappingType, "Position") end
                        if mapping.FilterChannel then table.insert(mappingType, "FilterChannel") end
                        if mapping.FilterPitch then table.insert(mappingType, "FilterPitch") end
                        if mapping.FilterVelocity then table.insert(mappingType, "FilterVelocity") end
                        if mapping.FilterSpeed then table.insert(mappingType, "FilterSpeed") end
                        if mapping.FilterInterval then table.insert(mappingType, "FilterInterval") end
                        if mapping.FilterCount then table.insert(mappingType, "FilterCount") end
                        
                        if mapping.KeyboardTrigger then table.insert(mappingType, "KT") end
                        
                        if mapping.UIText then table.insert(mappingType, "UIText") end
                
                        columnAmount = #mappingType
                        
                        totalItemAmount = (#tableInfo) * (columnAmount)
                
                        function waitTimer()
                            if not lastTime or reaper.time_precise() - lastTime > waitTimeBeforeRetrigger then
                                lastTime = reaper.time_precise()
                                return true
                            end
                        end
            
                        if reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_DownArrow()) or
                            reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_UpArrow()) or
                            reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_RightArrow()) or
                            reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_LeftArrow()) then
                            lastTime = nil
                        end
                        
                        
                        ----------------------------------------------------------------------
                        ----------------------------------------------------------------------
                        --------------------------NAVIGATION----------------------------------
                        ----------------------------------------------------------------------
                        ----------------------------------------------------------------------
                    
                        local movingRows = cmd and alt
                        
                        if (downArrow and (not movingRows)) or (not popup and not (shift or cmd or alt) and (enter)) or focusNextRow then 
                            if waitTimer() then
                                if popupGone or focusNextRow then
                                    if not focusedItem then
                                        setFocus = 1
                                        adjust = -1
                                    else 
                                        if #tableInfo > 1 then
                                            if ctrl and shift then
                                                if not focusedColumn then
                                                    setFocus = 0
                                                    adjust = -1
                                                else
                                                    setFocus = (#tableInfo - 1) * columnAmount + focusedColumn - 1
                                                end
                                            else
                                                if focusedRow == #tableInfo then
                                                    setFocus = focusedColumn
                                                    adjust = -1
                                                else
                                                    setFocus = math.floor(focusedItem) + columnAmount - 1
                                                    
                                                    -- TODO: Needs more work, to jump to the next thing that's not a lane
                                                    local adjustFocusABit = nil
                                                    
                                                    if mappingType[focusedColumn]:match("Note") ~= nil and focusedOnVel then 
                                                        adjust = -1
                                                        setFocus = setFocus + 1
                                                    end
                                                    
                                                    if adjustFocusABit  then
                                                        setFocus = setFocus + (focusedColumn - 1)
                                                    end
                                                    --reaper.ShowConsoleMsg(math.floor((setFocus) / columnAmount) .. " - " .. focusedColumn .. " - " .. tostring(tableInfo[mappingType[focusedColumn]][math.floor((setFocus) / columnAmount) + 1]) .. "\n")
                                                end
                                            end
                                        end
                                        focusNextRow = nil
                                    end
                                else
                                    setFocus = focusedItem and math.floor(focusedItem)
                                    adjust = -1
                                    -- setFocusOnNewMapping = focusBack
                                    popupGone = true
                                end
                            end
                        end
                
                        if upArrow and not movingRows then
                            if waitTimer() then
                                if not focusedItem then
                                    setFocus = 1
                                    adjust = -1
                                else
                                    if #tableInfo > 1 then
                                        if ctrl and shift then
                                            setFocus = focusedColumn
                                            adjust = -1
                                        else
                                            if focusedRow == 1 then 
                                                setFocus = ((#tableInfo - 1) * columnAmount) + focusedColumn - 1 -- totalItemAmount - columnAmount + focusedItem - 1
                                                -- setFocus = (columnAmount)-(totalItemAmount%focusedItem) 
                                                
                                            else
                                                setFocus = math.floor(focusedItem) - (columnAmount)
                                                
                                                if mappingType[focusedColumn]:match("Note") ~= nil and not focusedOnVel then 
                                                    --adjustFocusABit = true 
                                                    adjust = nil
                                                    setFocus = setFocus - 1
                                                else
                                                    adjust = -1
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        
                        if ctrl and rightArrow then
                            if shift then 
                                setFocus = focusedRow * columnAmount - 1
                            else
                                --if not lastTime or reaper.time_precise() - lastTime > 0.2 then
                                if waitTimer() then
                                    if not focusedItem then
                                        setFocus = 1
                                        adjust = -1
                                    else
                                        if focusedItem == totalItemAmount then
                                            setFocus = 1
                                            adjust = -1
                                        else
                                            setFocus = math.floor(focusedItem)
                                        end
                                    end
                                    lastTime = reaper.time_precise()
                                end
                            end
                        end
                
                        if ctrl and leftArrow then
                            if shift then
                                setFocus = (focusedRow - 1) * columnAmount + 1
                                adjust = -1
                            else
                                if waitTimer() then
                                    if not focusedItem then
                                        setFocus = 0
                                        adjust = -1
                                    else
                                        if focusedItem == 1 then
                                            setFocus = totalItemAmount - 1
                                        else
                                            setFocus = math.floor(focusedItem) - 1
                                            adjust = -1
                                        end
                                    end
                                end
                            end
                        end
                
                        
                        
                
                        if (cmd or alt) and enter then
                            toggleSelectArticulationRow = true
                            setFocus = math.floor(focusedItem)
                            adjust = -1
                        end
                
                        -- this is kind of a hack for the mouse to select toggle select a selected field
                        if cmd and mouseDown then toggleSelectMouse = true end
                
                        if selectNewArt then
                            setFocus = (#tableInfo - 1) * columnAmount
                            selectNewArt = false
                        end
                
                        if selectNewArts then
                            if newRowsAmount then
                                setFocus = (lastRowsAmount) * columnAmount - 1
                                -- selectedArticulations = {}
                                -- for k = #tableInfo-1, #tableInfo - newRowsAmount + 2, -1  do
                                --  selectedArticulations[k] = true
                                -- end 
                                selectNewArts = false
                            else
                                -- setFocus = focusedItem
                                -- adjust = -1
                            end
                        end
                
                        -- NOT SURE WHAT THIS WAS USED FOR
                        --[[
                        if cmd and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_D()) then
                            -- setFocus = 0
                            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
                            -- reaper.ImGui_InputText(ctx,"dummy","",nil)
                            firstRow = firstSelectedArticulation
                            lastRow = firstSelectedArticulation
                            for rowKey, counter in pairs(selectedArticulations) do
                                for _, mapping in pairs(mappingType) do
                                    if tableInfo[mapping][rowKey] then
                                        -- tableInfo[mapping][rowKey] = nil
                                    end
                                end
                                lastRow = rowKey
                            end
                
                            amountDeleted = lastRow - firstRow + 1
                            for rowAfter = lastRow + 1, #tableInfo do
                                for _, mapping in pairs(mappingType) do
                                    if tableInfo[mapping][rowAfter] then
                                        tableInfo[mapping][rowAfter - amountDeleted] =
                                            tableInfo[mapping][rowAfter]
                                        tableInfo[mapping][rowAfter] = nil
                                    end
                                end
                            end
                            -- tableInfo[mappingType[focusedColumn]]  --[[[firstRow] = currentString
                            #tableInfo = #tableInfo - amountDeleted
                        end
                        ]]
                        
                        ----------------------------------------------------------------------
                        ----------------------------------------------------------------------
                        ----------------------------------------------------------------------
                        ----------------------------------------------------------------------
                        function updateItemFocus(row, column, itemNumber, itemOffset)
                            if reaper.ImGui_IsItemFocused(ctx) then
                                focusedItem = itemNumber + (itemOffset and itemOffset or 0)
                                focusedRow = row
                                focusedColumn = column
                                focusedColumnName = mappingType[focusedColumn]
                                addRemoveToSelection(focusedRow)
                                lastSelectedRow = focusedRow
                                lastSelectedItem = focusedItem  -- probably not used
                                return true
                            end 
                        end
                        
                        function numberWithinMinMax(stringInput,min,max, default) 
                            if stringInput and tonumber(stringInput) ~= nil and min and max then 
                                local newNumber = tonumber(stringInput)
                                if newNumber < min then
                                    return min
                                elseif newNumber > max then
                                    return max
                                else
                                    return newNumber
                                end
                            elseif not stringInput or stringInput == "" then 
                                return default and default or stringInput
                            else
                                return stringInput
                            end
                        end
                        
                        
                        
                        -- NOW WE ARE ABLE TO LOOK THROUGH AND ENSURE IT's only one character. It would be great to be able to match it to a string specifically
                        if not reaper.ImGui_ValidatePtr(filterFunctionSingleCharacter, 'ImGui_Function*') then
                            filterFunctionSingleCharacter = reaper.ImGui_CreateFunctionFromEEL([[
                                strlen(#Buf) > 1 ? ( 
                                    c = str_getchar(#Buf, 1);
                                    str_setchar(#first, 0, c);
                                    InputTextCallback_DeleteChars(0, strlen(#Buf));
                                    InputTextCallback_InsertChars(0, #first);
                                );
                                
                            ]])
                            reaper.ImGui_Function_SetValue_String(filterFunctionSingleCharacter, '#allowed', reaper.ImGui_InputTextFlags_CallbackEdit())
                        end
                        
                        function getMainLaneRow(columnName, row) 
                            if tableInfo[row].isLane and columnsToNotUseLanes[columnName] then
                                for r = row, 1, -1 do
                                    if not tableInfo[r].isLane then
                                        return r 
                                    end
                                end
                            end
                        end
                        
                        function getArticulationTextFromLane(columnName, row, defaultValue)
                            if not tableInfo[row] then
                                tableInfo[row] = {}
                            end 
                            local value, mainLane
                            if tableInfo[row].isLane and columnsToNotUseLanes[columnName] then
                                for r = row, 1, -1 do
                                    if not tableInfo[r].isLane then
                                        value = tableInfo[r][columnName]
                                        mainLane = r
                                        break
                                    end
                                end
                            else
                                if tableInfo[row][columnName] then
                                    value = tableInfo[row][columnName]
                                end
                            end 
                            
                            
                            if not value then 
                                value = defaultValue and defaultValue or ""
                            end
                            return value, mainLane
                        end
                        
                        function setNewTableValue(row, columnName, newValue)
                            local mainLaneRow = getMainLaneRow(columnName, row)
                            if mainLaneRow then 
                                tableInfo[mainLaneRow][columnName] = newValue
                            else
                                tableInfo[row][columnName] = newValue
                            end
                            undo_redo.commit({tableInfo, mapping})
                        end
                    
                        function modifyIncrement(id, columnName, row, column, same, notNumber, min, max, defaultValue)
                            
                            local title, mainLaneRow = getArticulationTextFromLane(columnName, row, defaultValue) 
                        
                            if mainLaneRow then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
                            
                            local inputFlags = notNumber and reaper.ImGui_InputTextFlags_AutoSelectAll() or (reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal())
                            ret, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, title, inputFlags) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue()) 
                            
                            if mainLaneRow then reaper.ImGui_PopStyleColor(ctx) end
                            
                            if ret then  
                                stringFix = numberWithinMinMax(stringInput,min,max, default) 
                                local counter = 0
                                for _, rowKey in ipairs(selectedArticulationsCountKeys) do
                                    if same or #selectedArticulationsCountKeys == 1 then
                                        setNewTableValue(rowKey, columnName, stringFix)
                                    else
                                        if notNumber then
                                            local newNumber = stringFix .. " " .. math.floor(counter * (modifierSettings and modifierSettings[columnName .. "Increment"] or 1))  
                                            setNewTableValue(rowKey, columnName, newNumber)
                                        else
                                            if stringInput and stringInput ~= "" then 
                                                newNumber = stringFix + math.floor(modifierSettings[columnName .. "Increment"] * (counter)) 
                                                newNumber = numberWithinMinMax(newNumber,min,max)  
                                                setNewTableValue(rowKey, columnName, newNumber)
                                            end
                                        end
                                        if not tableInfo[rowKey].isLane then
                                            counter = counter + 1
                                        end
                                    end
                                end
                            end
                        end
                        
                        function modifyVelocity(id, columnName, row, column, min, max, itemWidth, lane, defaultModifyType)
                            local prefix
                            local modify
                            if not tableInfo[row] then
                                tableInfo[row] = {}
                            end
                            

                            if tableInfo[row][columnName] then
                                title = tableInfo[row][columnName]
                            else
                                title = ""
                            end
                            if tableInfo[row] and tableInfo[row][columnName .. "Type"] and tableInfo[row][columnName .. "Type"] ~= "" then
                                modify = tableInfo[row][columnName .. "Type"]
                            else
                                modify = defaultModifyType and defaultModifyType or "Fixed"
                            end
                        
                            if modify == "Fixed" then
                                prefix = "="
                            elseif modify == "Minimum" then
                                prefix = ">"
                            elseif modify == "Maximum" then
                                prefix = "<" 
                            end
                        
                            
                            
                            -- add value to both values
                            if modify == "Within" or modify == "Outside" then 
                                if tableInfo[row][columnName .. "2"] then 
                                    title2 = tableInfo[row][columnName .. "2"]
                                else
                                    title2 = title 
                                    tableInfo[row][columnName .. "2"] = title2
                                end 
                            end
                            
                            if modify == "Within" then -- or modify == "Outside" then 
                                reaper.ImGui_SetNextItemWidth(ctx, itemWidth/2)
                                ret, stringInput = reaper.ImGui_InputText(ctx, "##1 - " .. id, title, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                updateItemFocus(row, column, itemNumber,0.1) 
                                
                                reaper.ImGui_SameLine(ctx,itemWidth/2-4)
                                reaper.ImGui_SetNextItemWidth(ctx, 20)
                                reaper.ImGui_Text(ctx, "<>")
                                reaper.ImGui_SameLine(ctx, itemWidth/2+16) 
                                
                                reaper.ImGui_SetNextItemWidth(ctx, itemWidth/2-10)
                                ret2, stringInput2 = reaper.ImGui_InputText(ctx, "##2 - " .. id, title2, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                            elseif modify == "Outside" then 
                                reaper.ImGui_SetNextItemWidth(ctx, 8)
                                reaper.ImGui_Text(ctx, "<")
                                reaper.ImGui_SameLine(ctx, 8)
                                
                                reaper.ImGui_SetNextItemWidth(ctx, itemWidth/2 - 8)
                                ret, stringInput = reaper.ImGui_InputText(ctx, "##1 - " .. id, title, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                updateItemFocus(row, column, itemNumber, 0.1)
                                
                                --reaper.ImGui_SameLine(ctx,tableSizeVelocity/2)
                                --reaper.ImGui_SetNextItemWidth(ctx, 5)
                                --reaper.ImGui_Text(ctx, "-")
                                
                                reaper.ImGui_SameLine(ctx,itemWidth-8)
                                reaper.ImGui_SetNextItemWidth(ctx, 8)
                                reaper.ImGui_Text(ctx, ">") 
                                
                                reaper.ImGui_SameLine(ctx, itemWidth/2 - 2) 
                                reaper.ImGui_TextColored(ctx, 0x555555FF, "|")
                                
                                reaper.ImGui_SameLine(ctx, itemWidth/2) 
                                reaper.ImGui_SetNextItemWidth(ctx, itemWidth/2)
                                ret2, stringInput2 = reaper.ImGui_InputText(ctx, "##2 - " .. id, title2, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue()) 
                                
                            else  
                                reaper.ImGui_SetNextItemWidth(ctx, 10)
                                reaper.ImGui_Text(ctx, prefix)
                                reaper.ImGui_SameLine(ctx, 10)
                                reaper.ImGui_SetNextItemWidth(ctx, itemWidth)
                                ret, stringInput = reaper.ImGui_InputText(ctx, "##1 - " .. id, title, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                            end
                        
                            if ret then 
                                local newNumber = numberWithinMinMax(stringInput,min,max)
                                for rowKey, counter in pairs(selectedArticulations) do  
                                    setNewTableValue(rowKey, columnName, newNumber)
                                end
                            end
                            if ret2 then
                                local newNumber = numberWithinMinMax(stringInput2,min,max) 
                                for rowKey, counter in pairs(selectedArticulations) do
                                    setNewTableValue(rowKey, columnName .. "2", newNumber or "") 
                                end
                            end
                            if modify == "Within" or modify == "Outside" then 
                                return true
                            end
                        end
                        
                        
                        function modifyNotes(id, columnName, row, column, modify, defaultValue) 
                            local title = getArticulationTextFromLane(columnName, row, defaultValue) 
                            
                            textInputIsFocused = (column == focusedColumn and row == focusedRow)
                            
                            visualTitle = allNoteValuesMap[title] -- Only using sharps
                            velocityValue = tableInfo[row][columnName .. "Velocity"] and tableInfo[row][columnName .. "Velocity"] or nil
                            
                            
                            parenteseTitle = ""
                            if not visualTitle then 
                            else
                                parenteseTitle = "(" .. visualTitle .. ")"
                            end
                            
                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeNote / 2)
                            --if tableInfo[row][columnName .. "Velocity"] then -- and #tableInfo[columnName .. "Velocity"] > 0 then 
                                --reaper.ImGui_SetNextItemWidth(ctx, velocityValue and tableSizeNote or tableSizeNoteVel) 
                            --else
                            --    reaper.ImGui_SetNextItemWidth(ctx, tableSizeNote)
                            --end
                            ret, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, visualTitle, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsUppercase() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- ,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                            updateItemFocus(row, column, itemNumber, 0.1)
                            
                            if focusedRow == row and focusedColumn == column and reaper.ImGui_IsItemFocused(ctx) then
                               focusedOnVel = false
                            end
                            
                            --if velocityValue then
                                if not (column == focusedColumn and row == focusedRow and tonumber(stringInput) ~= nil and parenteseTitle ~= "") then
                                    reaper.ImGui_SameLine(ctx,tableSizeNoteVel/2 - 6)
                                    reaper.ImGui_SetNextItemWidth(ctx, 20)
                                    reaper.ImGui_TextColored(ctx, colorGrey, "vel:")
                                end
                                reaper.ImGui_SameLine(ctx, tableSizeNoteVel/2+18) 
                                reaper.ImGui_SetNextItemWidth(ctx, tableSizeNoteVel/2-18)
                                velocityValueRet, velocityValueString = reaper.ImGui_InputText(ctx, "##2 - " .. id, velocityValue, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue()) 
                                 
                                if focusedRow == row and focusedColumn == column and reaper.ImGui_IsItemFocused(ctx) then
                                   focusedOnVel = true 
                                end
                                
                                if visualTitle ~= "" and velocityValue then
                                  --  visualTitle = visualTitle .. " (" .. velocityValue .. ")"
                                end
                                if velocityValueRet and velocityValueString then 
                                    for rowKey, counter in pairs(selectedArticulations) do
                                        setNewTableValue(rowKey, columnName .. "Velocity", tonumber(velocityValueString))
                                        --tableInfo[rowKey][columnName .. "Velocity"] = tonumber(velocityValueString)
                                    end
                                end
                            --end
                            
                            if column == focusedColumn and row == focusedRow then
                                if ret and stringInput then  
                                    if stringInput ~= title then 
                                        if title and tonumber(stringInput) then
                                            local stringSize = reaper.ImGui_CalcTextSize(ctx, stringInput, 0,0)
                                            reaper.ImGui_SameLine(ctx, stringSize + 8)
                                            reaper.ImGui_TextColored(ctx,colorGrey, parenteseTitle)
                                        end
                                    
                                    end
                                end
                            end
                        
                            if ret then
                                if tonumber(stringInput) ~= nil and
                                    allNoteValuesMap[tonumber(stringInput)] then
                                    startNote = tonumber(stringInput)
                                elseif noteNameValues[stringInput] then
                                    startNote = tonumber(noteNameValues[stringInput])
                                else
                                    startNote = nil
                                end
                        
                                extraCounter = 0
                                for rowKey, counter in pairs(selectedArticulations) do
                                    if modify == "Same" or not startNote then
                                        noteIndexValue = startNote
                                    elseif modify == "Increment" then
                                        noteIndexValue = startNote + math.floor((counter - 1) * modifierSettings[columnName .. "Increment"])
                                    elseif modify == "Chromatic" then
                                        noteIndexValue = startNote + (counter - 1)
                                    elseif modify == "White Keys" then
                                        noteIndexValue = startNote + (counter - 1) + extraCounter
                                        if allWhiteNoteValuesMap[noteIndexValue] ==
                                            false then
                                            extraCounter = extraCounter + 1
                                            noteIndexValue = noteIndexValue + 1
                                        end
                                    elseif modify == "Black Keys" then
                                        noteIndexValue = startNote + (counter - 1) + extraCounter
                                        while allBlackNoteValuesMap[noteIndexValue] == false do
                                            extraCounter = extraCounter + 1
                                            noteIndexValue = noteIndexValue + 1
                                        end
                                    end
                                    if noteIndexValue and noteIndexValue > 127 then
                                        noteIndexValue = 127
                                    end
                                    if noteIndexValue and noteIndexValue < 0 then
                                        noteIndexValue = 0
                                    end
                                    
                                    setNewTableValue(rowKey, columnName, tonumber( noteIndexValue))
                                end
                            end
                        end
                        
                        function evenDivided(id, columnName, row, column)
                            local title = getArticulationTextFromLane(columnName, row, defaultValue) 
                        
                            -- reaper.ImGui_SetNextItemWidth(ctx,50)
                            -- if tableInfo[row][columnName] then noteName = allNoteValuesMap[title] else noteName = "" end
                            -- reaper.ImGui_Text(ctx,noteName)
                            -- reaper.ImGui_SameLine(ctx,50) 
                            -- reaper.ImGui_SetNextItemWidth(ctx,40)
                            if #selectedArticulationsCountKeys == 1 then
                                local ret, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, title, reaper.ImGui_InputTextFlags_CharsDecimal()) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                if ret and tonumber(stringInput) then
                                    newNumber = tonumber(stringInput)
                                    if newNumber > 127 then
                                        newNumber = 127
                                    end
                                    if newNumber < 0 then
                                        newNumber = 0
                                    end
                                    --tableInfo[row][columnName] = newNumber
                                    setNewTableValue(row, columnName, newNumber)
                                end
                            else
                                if row == focusedRow and column == focusedColumn then
                                    reaper.ImGui_Text(ctx, title)
                                    reaper.ImGui_SameLine(ctx, 30)
                                    reaper.ImGui_SetNextItemWidth(ctx, 60)
                                    local ret, stringInput =
                                        reaper.ImGui_InputText(ctx, "##" .. id, nil, reaper.ImGui_InputTextFlags_CharsDecimal()) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                    if stringInput ~= title and tonumber(stringInput) and
                                        firstSelectedArticulation == focusedRow then
                                        offset = tonumber(stringInput)
                                        maxNumber = 127 - offset
                                    elseif stringInput ~= title and tonumber(stringInput) and
                                        tonumber(stringInput) > 0 then
                                        offset = 0
                                        maxNumber = (tonumber(stringInput) / (focusedArticulationRelative - 1)) * (#selectedArticulationsCountKeys - 1)
                                    else
                                        offset = 0
                                        maxNumber = 127
                                    end
                                else
                                    reaper.ImGui_InputText(ctx, "##" .. id, title, reaper.ImGui_InputTextFlags_CharsDecimal()) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                end
                        
                                if not maxNumber then
                                    maxNumber = 127
                                end
                        
                                if not offset then offset = 0 end
                                for rowKey, counter in pairs(selectedArticulations) do
                                    newNumber = math.floor((maxNumber / (#selectedArticulationsCountKeys - 1)) * (counter - 1)) + offset
                                    if newNumber > 127 then
                                        newNumber = 127
                                    end
                                    if newNumber < 0 then
                                        newNumber = 0
                                    end
                                    --tableInfo[rowKey][columnName] = newNumber
                                    setNewTableValue(rowKey, columnName, newNumber)
                                end
                            end
                        end
                        
                        function modifyKeyboardTrigger(id, columnName, row, column)
                            if not keyboardTriggerTitles then keyboardTriggerTitles = {} end
                            
                            local title, mainLaneRow = getArticulationTextFromLane(columnName, row, defaultValue)
                            
                            if mainLaneRow then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end 
                            
                            ret, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, title, reaper.ImGui_InputTextFlags_CharsUppercase() | reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunctionSingleCharacter) -- ,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                            if mainLaneRow then reaper.ImGui_PopStyleColor(ctx) end
                            
                            if ret and (not lastInput or lastInput ~= stringInput) then
                                if keyboardTableKeys[stringInput] then
                                    usedKeyboardTriggers = {}
                                    posInKeyboard = keyboardTableKeys[stringInput] 
                                    
                                    local counter = 0
                                    for _, rowKey in ipairs(selectedArticulationsCountKeys) do 
                                        addKey = keyboardTableKeysOrder[posInKeyboard+counter] 
                                        if not tableInfo[rowKey].isLane then
                                            usedKeyboardTriggers[addKey] = true  
                                            counter = counter + 1
                                        end
                                    end
                                    
                                    for rowKey = 1, #tableInfo do
                                        if usedKeyboardTriggers[tableInfo[rowKey][columnName]] then 
                                            --tableInfo[rowKey][columnName] = nil 
                                            setNewTableValue(rowKey, columnName, nil)
                                        end
                                    end
                                    
                                    local counter = 0
                                    for _, rowKey in ipairs(selectedArticulationsCountKeys) do 
                                        --tableInfo[rowKey][columnName] = addKey
                                        if not tableInfo[rowKey].isLane then  
                                            addKey = keyboardTableKeysOrder[posInKeyboard+counter] 
                                            setNewTableValue(rowKey, columnName, addKey)
                                            counter = counter + 1
                                        end
                                    end
                                elseif stringInput == "" or stringInput == " " then 
                                    for rowKey, counter in pairs(selectedArticulations) do 
                                        --tableInfo[rowKey][columnName] = ""
                                        setNewTableValue(rowKey, columnName, "") 
                                    end
                                end
                                
                                lastInput = stringInput
                            end
                        end
                        
                        function modifyExact(id, columnName, row, column, selections, keys) 
                            local title, mainLaneRow = getArticulationTextFromLane(columnName, row, defaultValue)
                            
                            if mainLaneRow then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
                            
                            
                            local ret2, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, title, reaper.ImGui_InputTextFlags_CharsUppercase() | reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunctionSingleCharacter) -- ,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                            
                            if mainLaneRow then reaper.ImGui_PopStyleColor(ctx) end
                            
                            if ret2 then
                                for i, key in ipairs(keys) do
                                    if stringInput == key then 
                                        local name = selections[i]
                                        for rowKey, counter in pairs(selectedArticulations) do
                                            setNewTableValue(rowKey, columnName, name) 
                                        end
                                        if column == focusedColumn and row == focusedRow then
                                            local width = reaper.ImGui_CalcTextSize(ctx, key,0,0)
                                            reaper.ImGui_SameLine(ctx, width+4)
                                            reaper.ImGui_Text(ctx, name:sub(2))
                                        end
                                    elseif stringInput == "" then
                                        for rowKey, counter in pairs(selectedArticulations) do
                                            setNewTableValue(rowKey, columnName, "") 
                                        end
                                    end
                                end
                            end
                            --[[
                            for i, key in ipairs(keys) do
                                if tableInfo[row][columnName] == key then
                                    name = selections[i]
                                    local width = reaper.ImGui_CalcTextSize(ctx, key,0,0)
                                    reaper.ImGui_SameLine(ctx, width+4)
                                    reaper.ImGui_Text(ctx, name:sub(2))
                                end
                            end]]
                        end
                        
                        function modifyExactFromTable(id, columnName, row, column, keys) 
                            
                            local title, mainLaneRow = getArticulationTextFromLane(columnName, row, defaultValue)
                            
                            if mainLaneRow then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
                            
                            local ret2, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, title, reaper.ImGui_InputTextFlags_AutoSelectAll()) -- ,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                            
                            if mainLaneRow then reaper.ImGui_PopStyleColor(ctx) end
                            
                            if ret2 then
                                if stringInput == "" then
                                    for rowKey, counter in pairs(selectedArticulations) do
                                        setNewTableValue(rowKey, columnName, nil)
                                        --tableInfo[row][columnName] = ""
                                    end
                                else
                                    local matching
                                    local moreMatches
                                    for i, key in ipairs(keys) do
                                        if key:sub(0, #stringInput):lower() == stringInput:lower() then      
                                            if matching then 
                                                moreMatches = true
                                            else
                                                matching = key 
                                            end
                                        end
                                    end
                                    
                                    if matching and column == focusedColumn and row == focusedRow then
                                        local width = reaper.ImGui_CalcTextSize(ctx, stringInput,0,0)
                                        reaper.ImGui_SameLine(ctx, width+4)
                                        reaper.ImGui_Text(ctx, matching:sub(#stringInput + 1))
                                    end
                                    
                                    if matching and enterDown then
                                        tableInfo[row][columnName] = matching
                                        
                                        for r, val in pairs(tableInfo[row]) do
                                            if val == matching then --and row ~= r then
                                                setNewTableValue(row, columnName, nil)
                                                --tableInfo[row][r] = nil
                                            end
                                        end
                                    end
                                
                                
                                    for i, key in ipairs(keys) do
                                        if stringInput:lower() == key:lower() and (not moreMatches or (not moreMatches and enter)) then 
                                            --tableInfo[row][columnName] = key
                                            setNewTableValue(row, columnName, key)
                                            if not moreMatches then 
                                                for k, val in pairs(tableInfo[row]) do
                                                    if val == matching then -- and row ~= k then
                                                        setNewTableValue(row, columnName, nil)
                                                        --tableInfo[row][r] = nil
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            --[[
                            for i, key in ipairs(keys) do
                                if tableInfo[row][columnName] == key then
                                    name = selections[i]
                                    local width = reaper.ImGui_CalcTextSize(ctx, key,0,0)
                                    reaper.ImGui_SameLine(ctx, width+4)
                                    reaper.ImGui_Text(ctx, name:sub(2))
                                end
                            end]]
                        end
                        
                        
                        ------------------------------------------------------------------------------------------
                        ------------------------------------------------------------------------------------------
                        ------------------------------------------------------------------------------------------
                        
                    
                        tableSizePlay = 20
                        tableSizeTitle = 120
                        tableSizeSubtitle = 100
                        tableSizeOthers = 90
                        tableSizeCC = reaper.ImGui_CalcTextSize(ctx, "CC127 X",0,0)
                        tableSizeKT = reaper.ImGui_CalcTextSize(ctx, "KT X",0,0)
                        tableSizeNotation = reaper.ImGui_CalcTextSize(ctx, "Notation     X",0,0)
                        tableSizeUIText = reaper.ImGui_CalcTextSize(ctx, "UIText  X",0,0)
                        tableSizeDelay = reaper.ImGui_CalcTextSize(ctx, "Delay (ms)  X",0,0)
                        tableSizeChannel = reaper.ImGui_CalcTextSize(ctx, "Channel X",0,0)
                        tableSizePitch = reaper.ImGui_CalcTextSize(ctx, "Pitch",0,0)
                        tableSizeLayer = reaper.ImGui_CalcTextSize(ctx, "Layer  X",0,0)
                        tableSizePosition = reaper.ImGui_CalcTextSize(ctx, "Position   X",0,0)
                        tableSizeTranspose = reaper.ImGui_CalcTextSize(ctx, "Traspose   X",0,0)
                        tableSizeInterval = reaper.ImGui_CalcTextSize(ctx, "Interval   X",0,0)
                        tableSizeFilterChannel = reaper.ImGui_CalcTextSize(ctx, "F.Channel  X",0,0)
                        tableSizeFilterPitch = reaper.ImGui_CalcTextSize(ctx, "F.Pitch  X",0,0)
                        tableSizeFilterVelocity = reaper.ImGui_CalcTextSize(ctx, "F.Velocity  X",0,0)
                        tableSizeFilterSpeed = reaper.ImGui_CalcTextSize(ctx, "F.Speed  X",0,0)
                        tableSizeFilterInterval = reaper.ImGui_CalcTextSize(ctx, "F.Interval  X",0,0)
                        tableSizeFilterCount = reaper.ImGui_CalcTextSize(ctx, "F.Note Count  X",0,0)
                        tableSizeFilterVelocity = tableSizeFilterVelocity + 10 -- added for extra space or something??
                        
                        tableSizeVelocity = tableSizeFilterVelocity--reaper.ImGui_CalcTextSize(ctx, "Velocity    X",0,0)
                        tableSizeNote = reaper.ImGui_CalcTextSize(ctx, "Note (M)     X",0,0)
                        tableSizeNoteVel = tableSizeNote
                        tableWidth = 0
                        for _, mappingName in ipairs(mappingType) do
                            if mappingName == "Title" then
                                tableWidth = tableWidth + tableSizeTitle 
                            --elseif mappingName == "PlayArticulation" then
                            --    tableWidth = tableWidth + tableSizeSubtitle
                            elseif mappingName == "Subtitle" then
                                tableWidth = tableWidth + tableSizeSubtitle
                            elseif mappingName:match("CC") ~= nil then
                                tableWidth = tableWidth + tableSizeCC
                            elseif mappingName == "KT" then
                                tableWidth = tableWidth + tableSizeKT  
                            elseif mappingName == "Notation" then
                                tableWidth = tableWidth + tableSizeNotation
                            elseif mappingName == "UIText" then
                                tableWidth = tableWidth + tableSizeUIText
                            elseif mappingName == "Delay" then
                                tableWidth = tableWidth + tableSizeDelay 
                            elseif mappingName == "Pitch" then
                                tableWidth = tableWidth + tableSizePitch
                            elseif mappingName == "Velocity" then
                                tableWidth = tableWidth + tableSizeVelocity
                            elseif mappingName == "Channel" then
                                tableWidth = tableWidth + tableSizeChannel
                            elseif mappingName == "Layer" then
                                tableWidth = tableWidth + tableSizeLayer
                            elseif mappingName == "Transpose" then
                                tableWidth = tableWidth + tableSizeTranspose
                            elseif mappingName == "Interval" then
                                tableWidth = tableWidth + tableSizeInterval
                            
                            elseif mappingName == "Position" then
                                tableWidth = tableWidth + tableSizePosition
                            elseif mappingName == "FilterChannel" then
                                tableWidth = tableWidth + tableSizeFilterChannel
                            elseif mappingName == "FilterPitch" then
                                tableWidth = tableWidth + tableSizeFilterPitch
                            elseif mappingName == "FilterVelocity" then
                                tableWidth = tableWidth + tableSizeFilterVelocity
                            elseif mappingName == "FilterSpeed" then
                                tableWidth = tableWidth + tableSizeFilterSpeed
                            elseif mappingName == "FilterInterval" then
                                tableWidth = tableWidth + tableSizeFilterInterval
                            elseif mappingName == "FilterCount" then
                                tableWidth = tableWidth + tableSizeFilterCount
                                                                
                            elseif mappingName:match("Note") ~= nil then
                                --if tableInfo[mappingName .. "Velocity"] and next(tableInfo[mappingName .. "Velocity"]) ~= nil then
                                    tableWidth = tableWidth + tableSizeNoteVel 
                                --else
                                --    tableWidth = tableWidth + tableSizeNote 
                                --end
                            else
                                tableWidth = tableWidth + tableSizeOthers 
                            end
                        end
                
                        tableWidth = tableWidth + 24 + ((#mappingType - 1) * 9) + 24 + (tableSizePlay + 9)

                        --reaper.ImGui_SetCursorPosY(ctx, tableY)
                        --reaper.ImGui_SetCursorPosX(ctx, tableX + 30)
                        
                        
                        local childSizeW = windowW - 16 < tableWidth and windowW - 16 or tableWidth
                        if reaper.ImGui_BeginChild(ctx, "tablechild2", childSizeW, windowH - tableY - 70) then
                            
                            tableFlags = 
                                            reaper.ImGui_TableFlags_ScrollY()
                                            | reaper.ImGui_TableFlags_ScrollX()
                                            | reaper.ImGui_TableFlags_RowBg() 
                                            --| reaper.ImGui_TableFlags_NoHostExtendX()
                                            --| reaper.ImGui_TableFlags_NoHostExtendY() 
                                            
                                            | reaper.ImGui_TableFlags_Borders()
                            if reaper.ImGui_BeginTable(ctx, 'table1', columnAmount + 1, tableFlags) then --, tableWidth - 10, windowH - tableY - 40) then -- ,reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 20) then
                                reaper.ImGui_TableSetupScrollFreeze(ctx, 1, 1)
                                -- Display headers so we can inspect their interaction with borders.
                                -- (Headers are not the main purpose of this section of the demo, so we are not elaborating on them too much. See other sections for details)
                                reaper.ImGui_TableSetupColumn(ctx, "play", reaper.ImGui_TableColumnFlags_WidthFixed(), tableSizePlay)
                                
                                for _, mappingName in ipairs(mappingType) do 
                                    local tbSize = _G["tableSize" .. mappingName]
                                    if not tbSize then 
                                        if mappingName:match("Note") ~= nil then
                                            if tableInfo[mappingName .. "Velocity"] and next(tableInfo[mappingName .. "Velocity"]) ~= nil then
                                                tbSize = tableSizeNoteVel 
                                            else
                                                tbSize = tableSizeNote 
                                            end
                                        else
                                            tbSize = tableSizeOthers 
                                        end
                                    end
                                    
                                    reaper.ImGui_TableSetupColumn(ctx, mappingName, reaper.ImGui_TableColumnFlags_WidthFixed(), tbSize)
                                end
                                
    
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0)
    
                                -- reaper.ImGui_TableHeadersRow(ctx)
                                -- Instead of calling TableHeadersRow() we'll submit custom headers ourselves
                                reaper.ImGui_TableNextRow(ctx, reaper.ImGui_TableRowFlags_Headers())
    
                                for column = 1, columnAmount  do
                                    reaper.ImGui_TableSetColumnIndex(ctx, column)
                                    local column_name = mappingType[column] -- reaper.ImGui_TableGetColumnName(ctx, column) -- Retrieve name passed to TableSetupColumn()
    
                                    if column_name:match("Note") then
                                        visualColumnName = "Note"
                                    elseif column_name == "Delay" then
                                        visualColumnName = column_name .. " (ms)" 
                                    elseif column_name:match("FilterCount") ~= nil then
                                        visualColumnName = "F.N.Count"
                                    elseif column_name:match("Filter") ~= nil then
                                        visualColumnName = column_name:gsub("Filter","F.")
                                    else
                                        visualColumnName = column_name
                                    end
                                    reaper.ImGui_AlignTextToFramePadding(ctx)
                                    
                                    reaper.ImGui_TextWrapped(ctx, visualColumnName)
                                    setToolTipFunc(tipTable[column_name])
                                    
                                    -- for note held system
                                    if column_name:match("Note") then 
                                        local clean = column_name:gsub("Note", "")
                                        reaper.ImGui_SameLine(ctx, 38)
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent) 
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorGrey)
                                        local isHeld = false
                                        for row, v in ipairs(tableInfo) do
                                            if tableInfo[row][column_name .. "Held"] then
                                                isHeld = true
                                            end
                                        end
                                        
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), isHeld and colorWhite or colorLightGrey)
                                        if reaper.ImGui_Button(ctx, "Held##" .. clean) then  
                                            for row, v in ipairs(tableInfo) do
                                                tableInfo[row][column_name .. "Held"] = not isHeld and true or nil
                                            end
                                        end
                                        reaper.ImGui_PopStyleColor(ctx, 3)
                                        
                                        visualColumnName = visualColumnName .. " Held "
                                    end
                                    
                                    if column_name ~= "Title" then 
                                        local textSize = reaper.ImGui_CalcTextSize(ctx, visualColumnName,0,0)
                                        reaper.ImGui_SameLine(ctx, textSize)
                                        -- if reaper.ImGui_InvisibleButton(ctx, "X##"..column,xSizeW+10, xSizeH) then
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF0000FF)
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x880000FF)
                                        if reaper.ImGui_SmallButton(ctx, "X##" .. column) then
                                            if column_name == "Subtitle" then
                                                mapping.Subtitle = false
                                            elseif column_name == "Channel" then
                                                mapping.Channel = false
                                            elseif column_name == "Velocity" then
                                                mapping.Velocity = false
                                            elseif column_name == "Delay" then
                                                mapping.Delay = false  
                                            elseif column_name == "Pitch" then
                                                mapping.Delay = false 
                                            elseif column_name == "Position" then
                                                mapping.Position = false
                                            elseif column_name == "FilterChannel" then
                                                mapping.FilterChannel = false  
                                            elseif column_name == "FilterPitch" then
                                                mapping.FilterPitch = false 
                                            elseif column_name == "FilterVelocity" then
                                                mapping.FilterVelocity = false 
                                            elseif column_name == "FilterSpeed" then
                                                mapping.FilterSpeed = false 
                                            elseif column_name == "FilterInterval" then
                                                mapping.FilterInterval = false 
                                            elseif column_name == "FilterCount" then
                                                mapping.FilterCount = false
                                                                                            
                                            elseif column_name == "Layer" then
                                                mapping.Layer = false  
                                            elseif column_name == "Transpose" then 
                                                mapping.Transpose = false 
                                            elseif column_name == "Interval" then
                                                mapping.Interval = false 
                                            elseif column_name == "KT" then
                                                mapping.KeyboardTrigger = false 
                                            elseif column_name == "Notation" then
                                                mapping.Notation = false
                                            elseif column_name == "UIText" then
                                                mapping.UIText = false
                                            elseif column_name:match("CC") ~= nil then
                                                local clean = column_name:gsub("CC", "") 
                                                mapping.CC[tonumber(clean)] = nil
                                                mapping.CC[clean] = nil -- for safety
                                            elseif column_name:match("Note") ~= nil then 
                                                local clean = column_name:gsub("Note", "")
                                                mapping.Note[tonumber(clean)] = nil
                                                mapping.Note[clean] = nil
                                            end
                                            undo_redo.commit({tableInfo, mapping})
                                        end
                                        reaper.ImGui_PopStyleColor(ctx, 3)
                                    end
                                    -- reaper.ImGui_PopID(ctx)
                                end

                                function rowIsALane(row)
                                    return tableInfo[row] and tableInfo[row].isLane
                                end
                            
                                function isNotALane(typeColumn, row, defaultValue)
                                    if tableInfo[row] and tableInfo[row].isLane then
                                        reaper.ImGui_AlignTextToFramePadding(ctx)
                                        local value
                                        for r = row, 1, -1 do
                                            if not tableInfo[r].isLane then
                                                value = tableInfo[r][typeColumn]
                                                break
                                            end
                                        end
                                        if not value and defaultValue then value = defaultValue end
                                        if not value then value = "" end 
                                        reaper.ImGui_TextColored(ctx, colorGrey," " .. value)
                                    else
                                        return true
                                    end 
                                end
                                
                                
                                
                                local sendNote = 50
                                
                                function bypassAnyArticulationScriptOnSelectedTracks(bypass)
                                    anyArticulationScriptOnSelectedTrackHasBeenBypassed = false
                                    for i = 0, reaper.CountSelectedTracks(0) - 1 do
                                        local track = reaper.GetSelectedTrack(0, i)
                                        
                                        local fxIndex
                                        local fxAmount = reaper.TrackFX_GetCount(track)
                                        for i = 0, fxAmount - 1 do
                                            _, fxName = reaper.TrackFX_GetFXName(track, i)
                                            if fxName:match("Articulation Script") ~= nil then
                                                fxIndex = i
                                                break
                                            end
                                        end
                                        if fxIndex then
                                            anyArticulationScriptOnSelectedTrackHasBeenBypassed = bypass
                                            reaper.TrackFX_SetEnabled(track, fxIndex, not bypass)
                                        end
                                    end 
                                end
                                
                                function sendANoteArticulation(index, triggerType)
                                    
                                    playingArticulationId = index
                                    playingArticulationTime = reaper.time_precise() 
                                    mouseOrKeyHasTriggeredArticulation = triggerType
                                    
                                    reaper.StuffMIDIMessage(0, 0x90, sendNote, 64)
                                end
                                
                                if playingArticulationTime and reaper.ImGui_IsMouseReleased(ctx, 0) and mouseOrKeyHasTriggeredArticulation == "mouse" then 
                                    mouseOrKeyHasTriggeredArticulation = nil
                                end
                                
                                if playingArticulationTime and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_P()) and mouseOrKeyHasTriggeredArticulation == "key" then 
                                    mouseOrKeyHasTriggeredArticulation = nil
                                end
                                
                                if playingArticulationTime and reaper.time_precise() - playingArticulationTime > 1 then
                                    if not mouseOrKeyHasTriggeredArticulation then
                                        if playingArticulationTime then 
                                            reaper.StuffMIDIMessage(0, 0x80, sendNote, 64) 
                                            playingArticulationId = nil
                                            playingArticulationTime = nil 
                                            unbypassAnyArticulationMapTime = reaper.time_precise()
                                        end 
                                    end
                                end
                                
                                if anyArticulationScriptOnSelectedTrackHasBeenBypassed and unbypassAnyArticulationMapTime then
                                    if reaper.time_precise() - unbypassAnyArticulationMapTime > 0.1 then
                                        bypassAnyArticulationScriptOnSelectedTracks(false)
                                        unbypassAnyArticulationMapTime = nil
                                    end
                                end
                                
                                function sendArticulation(row, triggerType)
                                    if playingArticulationId then
                                        reaper.StuffMIDIMessage(0, 0x80, sendNote, 64)
                                    end
                                    bypassAnyArticulationScriptOnSelectedTracks(true)
                                    
                                    for column = 1, columnAmount do 
                                        columnName = mappingType[column]
                                        if columnName:match("Note") ~= nil then  
                                            local msg2 = tableInfo[row][columnName]
                                            if msg2 then 
                                                local msg3 = (tableInfo[row] and tableInfo[row][columnName.. "Velocity"]) and tableInfo[row][columnName.. "Velocity"] or 127
                                                reaper.StuffMIDIMessage(0, 0x90, msg2, msg3)
                                                reaper.StuffMIDIMessage(0, 0x80, msg2, msg3)
                                            end
                                        elseif columnName:match("CC") ~= nil then 
                                            local msg2 = columnName:gsub("CC", "")
                                            local msg3 = tableInfo[row][columnName]
                                            if msg3 then 
                                                reaper.StuffMIDIMessage(0, 0xB0, tonumber(msg2), msg3)
                                            end
                                        end
                                    end
                                    -- TODO: impelement pitch
                                    sendANoteArticulation(row, triggerType)
                                end
                                
                                for row = 1, #tableInfo do
                                    
                                    --reaper.ImGui_TableNextRow(ctx) 
                                    
                                    reaper.ImGui_TableNextRow(ctx)
                                    
                                    
                                    reaper.ImGui_TableSetColumnIndex(ctx, 0)
                                    reaper.ImGui_InvisibleButton(ctx, "play" .. row, tableSizePlay ,tableSizePlay)
                                    local isHovered = reaper.ImGui_IsItemHovered(ctx)
                                    
                                    if not mouseOrKeyHasTriggeredArticulation then 
                                        if (isHovered and reaper.ImGui_IsMouseClicked(ctx, 0)) then 
                                            sendArticulation(row, "mouse")
                                        end
                                        
                                        if (row == focusedRow and cmd and ctrl and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_P())) then
                                            sendArticulation(focusedRow, "key") 
                                        end
                                    end
                                    
                                    
                                    local color = isHovered and colorLightGrey or colorGrey
                                    if playingArticulationId and playingArticulationId == row then
                                        color = colorWhite
                                    end
                          
                                    
                                    posX, posY = reaper.ImGui_GetItemRectMin(ctx)
                                    posXFix = posX + 10
                                    posYFix = posY + 12
                                    
                                    reaper.ImGui_DrawList_AddCircle(draw_list, posXFix, posYFix, 8, color, 3, 2)
                                    --reaper.ImGui_DrawList_AddText(draw_list, posXFix, posYFix, colorLightGrey,row)
    
                                    for column = 1, columnAmount do
                                    
                                    
                                    
                                        id = row .. ":" .. column
                                        itemNumber = (row - 1) * (columnAmount) + column
                                        reaper.ImGui_TableSetColumnIndex(ctx, column)
                                        columnName = mappingType[column]
                                        modify = modifierSettings[columnName] and modifierSettings[columnName] or "same"
                                        --modify = tableInfo[row][columnName .. "Type"] and tableInfo[row][columnName .. "Type"] or "Same"
                                        if columnName == "Title" then 
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeTitle)
                                            --if isNotALane(columnName, row) then
                                                if modify == "Same" then
                                                    modifyIncrement(id, columnName, row, column, true, true)
                                                elseif modify == "Increment" then
                                                    modifyIncrement(id, columnName, row, column, false, true)
                                                end
                                            --end
                                            
                                        elseif columnName == "Subtitle" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeSubtitle)
                                            --if isNotALane(columnName, row) then
                                                if modify == "Same" then
                                                    modifyIncrement(id, columnName, row, column, true, true)
                                                elseif modify == "Increment" then
                                                    modifyIncrement(id, columnName, row, column, false, true)
                                                end
                                            --end
                                        elseif columnName == "Layer" then
                                            
                                            -- we insert color picker before to ensure navigation works
                                            --if not tableInfo[row] then tableInfo[row] = {} end
                                            --if not tableInfo[row][columnName] then tableInfo[row][columnName] = 1 end
                                            
                                            --reaper.ShowConsoleMsg(tableSizeLayer .. "\n")
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeLayer -20)
                                            --if isNotALane(columnName, row, 1) then 
                                                
                                                if not tableInfo[row] then tableInfo[row] = {} end
                                                local layerNumber = tonumber(tableInfo[row][columnName]) or 1 
                                                
                                                if not layerInfo then layerInfo = {} end
                                                if not layerInfo[layerNumber] then layerInfo[layerNumber] = {} end
                                                if not layerInfo[layerNumber].color then layerInfo[layerNumber].color = colors[(layerNumber-1)%10 + 1] end 
                                                local layerColor = layerInfo[layerNumber].color
                                                local layerName = layerInfo[layerNumber].name or layerNumber
                                                
                                                if modify == "Increment" then
                                                    modifyIncrement(id, columnName, row, column, false, false, 1, 99, 1)
                                                else -- modify == "Increment" 
                                                    modifyIncrement(id, columnName, row, column, true, false, 1, 99, 1)
                                                end
                                                    
                                                local w, h = reaper.ImGui_GetItemRectSize(ctx)
                                                local x, y = reaper.ImGui_GetItemRectMin(ctx)
                                                local posX = x + w
                                                local posY = y + 3
                                                local posX2 = posX + 16
                                                local posY2 = posY + 16

                                                reaper.ImGui_DrawList_AddRectFilled(draw_list, posX, posY, posX2, posY2, layerColor, 4)
                                                if mouse_pos_x >= posX and mouse_pos_x <= posX2 and mouse_pos_y >= posY and mouse_pos_y <= posY2 and mouseRelease then 
                                                    reaper.ImGui_OpenPopup(ctx, "colorPicker" .. id)
                                                end
                                                
                                                if reaper.ImGui_BeginPopup(ctx, "colorPicker" .. id) then 
                                                    reaper.ImGui_PushFont(ctx, font, 20)
                                                    reaper.ImGui_Text(ctx, "Layer " .. layerNumber) 
                                                    reaper.ImGui_PopFont(ctx)
                                                    
                                                    reaper.ImGui_TextColored(ctx, colorGrey, "Name:")
                                                    local inputFlags = reaper.ImGui_InputTextFlags_AutoSelectAll()
                                                    local ret, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, layerName, inputFlags) -- | reaper.ImGui_InputTextFlags_EnterReturnsTrue()) 
                                                    if ret then   
                                                        layerInfo[layerNumber].name = stringInput
                                                    end
                                                    
                                                    reaper.ImGui_TextColored(ctx, colorGrey, "Color:")
                                                    local ret, col = reaper.ImGui_ColorPicker4(ctx, "##color"..id, layerColor , reaper.ImGui_ColorEditFlags_PickerHueWheel() | reaper.ImGui_ColorEditFlags_AlphaBar())
                                                    if ret and col then
                                                        if col < 0 then
                                                        col = col + 0x100000000
                                                        end 
                                                        layerInfo[layerNumber].color = col 
                                                    end
                                                    if escape then
                                                        reaper.ImGui_CloseCurrentPopup(ctx)
                                                    end
                                                    
                                                    reaper.ImGui_EndPopup(ctx)
                                                end
                                                
                                                
                                            
                                            --end
                                            
                                            
                                            
                                        elseif columnName == "Channel" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeChannel)
                                            if modify == "Same" then
                                                modifyIncrement(id, columnName, row, column, true, false, 1, 16, 1)
                                            elseif modify == "Increment" then
                                                modifyIncrement(id, columnName, row, column, false, false, 1, 16, 1)
                                            end
                                        elseif columnName == "Delay" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeDelay)
                                            if modify == "Same" then
                                                modifyIncrement(id, columnName, row, column, true, false, -3000, 4000)
                                            end
                                        elseif columnName == "Pitch" then   
                                            modifyNotes(id, columnName, row, column, modify)
                                        elseif columnName == "Velocity" then  
                                            --reaper.ImGui_SetNextItemWidth(ctx, tableSizeVelocity)
                                            modifyVelocity(id, columnName, row, column, 0, 127,tableSizeVelocity) 
                                        elseif columnName:match("Note") ~= nil then 
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeNote)
                                            -- tableInfo[row][columnName] = 12
                                            -- reaper.ShowConsoleMsg(#(tableInfo[row]).. " note\n")
                                            -- reaper.ImGui_Button(ctx,columnName)
                                            --if isNotALane(columnName, row) then
                                                modifyNotes(id, columnName, row, column, modify)
                                            --end
                                            
                                            
                                        elseif columnName:match("CC") ~= nil then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeCC)
                                            --if isNotALane(columnName, row) then
                                                
                                                    
                                                if modify == "Increment" then
                                                    modifyIncrement(id, columnName, row, column, false, false, 0, 127)
                                                elseif modify == "Even Divided" then
                                                    evenDivided(id, columnName, row, column)
                                                else -- same or default
                                                    modifyIncrement(id, columnName, row, column, true, false, 0, 127)
                                                end 
                                            --end
                                        elseif columnName == "Position" then 
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizePosition)
                                            modifyExact(id, columnName, row, column, legatoSelection, legatoKeys)
                                            
                                        elseif columnName == "FilterVelocity" then  
                                            --reaper.ImGui_SetNextItemWidth(ctx, tableSizeFilterVelocity)
                                            modifyVelocity(id, columnName, row, column, 0, 127, tableSizeFilterVelocity)    
                                        elseif columnName == "FilterSpeed" then  
                                            --reaper.ImGui_SetNextItemWidth(ctx, tableSizeFilterVelocity)
                                            modifyVelocity(id, columnName, row, column, 0, 2000, tableSizeFilterSpeed, nil)
                                        elseif columnName == "FilterInterval" then  
                                            --reaper.ImGui_SetNextItemWidth(ctx, tableSizeFilterVelocity)
                                            modifyVelocity(id, columnName, row, column, 0, 127, tableSizeFilterInterval, nil)
                                        elseif columnName == "FilterCount" then  
                                            modifyVelocity(id, columnName, row, column, 0, 100, tableSizeFilterCount, nil)
                                        elseif columnName == "FilterChannel" then  
                                            --reaper.ImGui_SetNextItemWidth(ctx, tableSizeFilterVelocity)
                                            modifyVelocity(id, columnName, row, column, 1, 16, tableSizeFilterChannel) 
                                        elseif columnName == "FilterPitch" then  
                                            --reaper.ImGui_SetNextItemWidth(ctx, tableSizeFilterVelocity)
                                            modifyVelocity(id, columnName, row, column, 0, 127, tableSizeFilterVelocity)
                                            
                                        elseif columnName == "Transpose" then 
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeTranspose)
                                            if modify == "Same" then
                                                modifyIncrement(id, columnName, row, column, true, false, -127, 127,0)
                                            elseif modify == "Increment" then
                                                modifyIncrement(id, columnName, row, column, false, false, -127, 127,0)
                                            end 
                                        elseif columnName == "Interval" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeInterval)
                                            --if isNotALane(columnName, row) then
                                                if modify == "Same" then
                                                    modifyIncrement(id, columnName, row, column, true, false, -127, 127)
                                                elseif modify == "Increment" then
                                                    modifyIncrement(id, columnName, row, column, false, false, -127, 127)
                                                end 
                                            --end
                                        elseif columnName == "KT" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeKT)
                                            --if isNotALane(columnName, row) then
                                                modifyKeyboardTrigger(id, columnName, row, column)
                                            --end
                                        elseif columnName == "Notation" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeNotation)
                                            --if isNotALane(columnName, row) then 
                                                modifyExactFromTable(id, columnName, row, column, getArrayOfSubarray(musicxml.articulations, "name"))
                                            --end
                                        elseif columnName == "UIText" then
                                            reaper.ImGui_SetNextItemWidth(ctx, tableSizeUIText)
                                            --if modify == "Same" then
                                                local defaultText = (tableInfo[row].Position and tableInfo[row].Position ~= "" and tableInfo[row].Position ~= "Any") and ("(" .. tableInfo[row].Position .. ")") or ""
                                                modifyIncrement(id, columnName, row, column, true, true, nil, nil, defaultText)
                                            --end
                                        end
                                        -- elseif column > 3 then 
                                        --  reaper.ImGui_SetNextItemWidth(ctx,90)
                                        -- reaper.ImGui_InputText(ctx, "##"..id, nil,reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                        -- end 
    
                                        if setFocus then 
                                            if not setFocus or setFocus == itemNumber then
                                            --reaper.ShowConsoleMsg(setFocus .. " - " .. tostring(adjust) .. "\n")
                                                reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
                                                if adjust then
                                                    reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
                                                    
                                                    adjust = nil
                                                end
                                                setFocus = nil
                                            end
                                        end
                                        
                                        
    
                                        function addRemoveToSelection(newKey)
                                            if setFocusOnNewMapping then
                                                setFocusOnNewMapping = nil
                                            elseif moveRow then
                                                moveRow = nil
                                            elseif not lastSelectedRow then
                                                selectedArticulations[newKey] = true
                                            elseif toggleSelectArticulationRow then
                                                selectedArticulations[newKey] = not selectedArticulations[newKey]
                                                toggleSelectArticulationRow = false
                                            elseif toggleSelectMouse then
                                                if mouseRelease then
                                                    if lastSelectedRow == newKey then
                                                        selectedArticulations[newKey] = not selectedArticulations[newKey]
                                                    end
                                                    toggleSelectMouse = false
                                                end
                                            elseif lastSelectedRow ~= newKey then
                                                if ctrl and alt then
                                                elseif cmd and not addNewArticulation then
                                                    selectedArticulations[newKey] = not selectedArticulations[newKey]
                                                elseif shift then
                                                    if tab then
                                                        if not selectedArticulations[newKey] then
                                                            selectedArticulations[lastSelectedRow] = false
                                                            selectedArticulations[newKey] = true
                                                        end
                                                    else
                                                        if lastSelectedRow > newKey then
                                                            for k = newKey, lastSelectedRow do
                                                                selectedArticulations[k] = true
                                                            end
                                                        else
                                                            for k = lastSelectedRow, newKey do
                                                                selectedArticulations[k] = true
                                                            end
                                                        end
                                                    end
                                                else 
                                                    if tab and selectedArticulations[newKey] then
                                                        -- We do nothing as we want the current articulations to be selected
                                                    else
                                                        selectedArticulations = {}
                                                        selectedArticulations[newKey] = true
                                                        -- if adding multiple new articulations, then select all of them
                                                        -- BUG: The above seems to not work
                                                        if newRowsAmount then
                                                            for k = newKey + 1, newKey +
                                                                newRowsAmount do
                                                                selectedArticulations[k] = true
                                                            end
                                                            newRowsAmount = false
                                                        end
                                                        
                                                        addNewArticulation = nil
                                                    end
                                                end
                                            end
                                            
    
                                            local sortedKeys = {}
                                            for key, value in pairs(selectedArticulations) do
                                                if value then
                                                    table.insert(sortedKeys, key)
                                                end
                                            end
                                            table.sort(sortedKeys)
                                            selectedArticulationsCountKeys = {}
                                            for counter, rowKey in pairs(sortedKeys) do
                                                selectedArticulations[rowKey] = counter
                                                selectedArticulationsCountKeys[counter] = rowKey
                                            end
    
                                            for rowKey, i in pairs(selectedArticulations) do
                                                if i == 1 then
                                                    firstSelectedArticulation = rowKey -- used for velocity
                                                elseif rowKey == focusedRow then
                                                    focusedArticulationRelative = i -- used for velocity
                                                end
                                            end
    
                                            if #sortedKeys == 0 then
                                                selectedArticulations[focusedRow] = 1
                                                --#selectedArticulationsCountKeys = 1
                                            else
                                                --#selectedArticulationsCountKeys = #sortedKeys
                                            end
                                            if focusedRow and focusedColumn then
                                                if tableInfo[mappingType[focusedColumn]] and tableInfo[focusedRow][mappingType[focusedColumn]] then
                                                    currentString = tableInfo[focusedRow][mappingType[focusedColumn]]
                                                end
                                            end
                                        end
    
                                        if reaper.ImGui_IsItemFocused(ctx) then 
                                            focusedItem = itemNumber
                                            focusedRow = row
                                            focusedColumn = column
                                            focusedColumnName = mappingType[focusedColumn]
                                            addRemoveToSelection(focusedRow)
                                            lastSelectedRow = focusedRow
                                            lastSelectedItem = focusedItem -- probably not used
                                        end
                                        
                                        
    
                                        if setFocusOnNewMapping then
                                            if focusedRow == row and setFocusOnNewMapping == mappingType[column + 1] then
                                                reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
                                                reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
                                            end
                                        end
    
                                        if selectedArticulations[row] then
                                            reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), 0x4d4db366)
                                        end
                                    end
    
                                end
                                reaper.ImGui_PopStyleColor(ctx)
                                reaper.ImGui_EndTable(ctx)
                            
                                reaper.ImGui_EndChild(ctx)
                            end
                        end
                        reaper.ImGui_SameLine(ctx)
                        tableWidthFromTable = reaper.ImGui_GetCursorPosX(ctx)
                        --tableWidth = reaper.ImGui_GetCursorPosX(ctx)
                        reaper.ImGui_NewLine(ctx)

                        
                        reaper.ImGui_EndTabItem(ctx)
                    end
                    
                    ----------------------------------------------------------------------
                    ----------------------------------------------------------------------
                    ----------------------------------------------------------------------
                    
                    
                    
                    ----------------------------------------------------------------------
                    -------------------------NEW TAB--------------------------------------
                    ----------------------------------------------------------------------
                    
                    openSettingsTab = cmd and reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_I())
                    settingsTabFlag = openSettingsTab and reaper.ImGui_TabItemFlags_SetSelected() or nil
                    if reaper.ImGui_BeginTabItem(ctx, 'Instrument Settings (cmd+i)',openSettingsTab, settingsTabFlag) then
                        
                        local childSizeW = windowW - 16
                        if reaper.ImGui_BeginChild(ctx, "instrument settings", childSizeW, windowH - reaper.ImGui_GetCursorPosY(ctx) - 60) then 
                            local width = 200
                            reaper.ImGui_TextColored(ctx, 0x777777FF, 'Instrument settings')
                            
                            
                            reaper.ImGui_SetNextItemWidth(ctx, width)
                            _, instrumentSettings.globalTranspose = reaper.ImGui_SliderInt(ctx, "Global transpose", instrumentSettings.globalTranspose or 0, -48, 48)
                            setToolTipFunc("Transpose playing notes globally.\nArticulation notes are not affected")
                            
                            
                            reaper.ImGui_SetNextItemWidth(ctx, width)
                            _, instrumentSettings.forceChannel = reaper.ImGui_SliderInt(ctx, "Force channel", instrumentSettings.forceChannel or 0, 0, 16)
                            setToolTipFunc("Force output to a specific midi channel.\nThis overwrites any channel settings in the mappings page.\n0 = off")
                            
                            
                            reaper.ImGui_NewLine(ctx) 
                            reaper.ImGui_TextColored(ctx, 0x777777FF, 'Instrument performance')
                            
                            if instrumentSettings.sustainPedalForcesLegato == nil then instrumentSettings.sustainPedalForcesLegato = true end 
                            _, instrumentSettings.sustainPedalForcesLegato = reaper.ImGui_Checkbox(ctx, "Sustain pedal forces legato", instrumentSettings.sustainPedalForcesLegato)
                            setToolTipFunc("This is useful for instruments like Cinematic Studio Series, that will consider notes with large space a legato line when sustain pedal (CC64) is pressed.\nOnly relevant when using position filter")
                            
                            
                             
                            if instrumentSettings.maxLegatoSpacingInMiliseconds == nil then instrumentSettings.maxLegatoSpacingInMiliseconds = 1 end
                            reaper.ImGui_SetNextItemWidth(ctx, width)
                            _, instrumentSettings.maxLegatoSpacingInMiliseconds = reaper.ImGui_SliderInt(ctx, "Max time to reset legato", instrumentSettings.maxLegatoSpacingInMiliseconds, 1, 2000)
                            setToolTipFunc("Some instruments register legato even when notes are not connected.\nYou can obtain this behavior by setting this value higher")
                             
                            _, instrumentSettings.enableSustainPedalOnRepeatedNotes = reaper.ImGui_Checkbox(ctx, "Enable Sustain pedal on repeated notes", instrumentSettings.enableSustainPedalOnRepeatedNotes)
                            setToolTipFunc("This is useful for instruments like Cinematic Studio Series, that triggers a repeat sample when sustain pedal (CC64) is pressed")
                            
                            
                            
                            reaper.ImGui_NewLine(ctx)
                            reaper.ImGui_TextColored(ctx, 0x777777FF, 'Track settings')
                            
                            if instrumentSettings.addKeyswitchNamesToPianoRoll == nil then instrumentSettings.addKeyswitchNamesToPianoRoll = true end 
                            _, instrumentSettings.addKeyswitchNamesToPianoRoll = reaper.ImGui_Checkbox(ctx, "Add keyswitch names to piano roll keys", instrumentSettings.addKeyswitchNamesToPianoRoll)
                            setToolTipFunc("Show key switch names on the piano roll keys.\nThis will only show for keyswitches that uses a single keyswitch")
                            
                            reaper.ImGui_Indent(ctx)
                            if instrumentSettings.addKeyswitchNamesToPianoRoll then
                                _, instrumentSettings.addKeyswitchNamesToPianoRollOnlyUseTitle = reaper.ImGui_Checkbox(ctx, "Only use title", instrumentSettings.addKeyswitchNamesToPianoRollOnlyUseTitle)
                                setToolTipFunc("For simpler names, only use the Title and not include subtitle on the piano roll keys") 
                            end
                            reaper.ImGui_Unindent(ctx)
                            
                            --if instrumentSettings.addCCNamesToTrack == nil then instrumentSettings.addCCNamesToTrack = true end 
                            _, instrumentSettings.addCCNamesToTrack = reaper.ImGui_Checkbox(ctx, "Add CC names to track", instrumentSettings.addCCNamesToTrack)
                            setToolTipFunc("Show specific names on CC lanes in the piano roll")
                            
                            if instrumentSettings.addCCNamesToTrack then
                                
                                if not instrumentSettings.ccNamesOnTrack then instrumentSettings.ccNamesOnTrack = {} end
                                tableFlags = reaper.ImGui_TableFlags_ScrollY() |
                                                --reaper.ImGui_TableFlags_ScrollX() |
                                                reaper.ImGui_TableFlags_NoHostExtendX() |
                                                reaper.ImGui_TableFlags_RowBg() |
                                                reaper.ImGui_TableFlags_Borders() 
                                                 --| reaper.ImGui_TableFlags_ScrollY()      
                                                                
                                                                --ImGui.TableFlags_BordersOuter |
                                                                --ImGui.TableFlags_BordersV     |
                                if reaper.ImGui_BeginTable(ctx, 'table3', 2, tableFlags, 500, 160) then --, tableWidth - 10, windowH - tableY - 40) then -- ,reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 20) then 
                                    reaper.ImGui_TableSetupColumn(ctx, "CC", reaper.ImGui_TableColumnFlags_WidthFixed(), 30)
                                    reaper.ImGui_TableSetupColumn(ctx, "Name", reaper.ImGui_TableColumnFlags_WidthFixed())
                                    reaper.ImGui_TableHeadersRow(ctx)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0)
                                
                                    for n = 0, 127 do
                                        reaper.ImGui_TableNextRow(ctx)
                                        
                                        reaper.ImGui_TableSetColumnIndex(ctx, 0)
                                        reaper.ImGui_Text(ctx, n)
                                        reaper.ImGui_TableSetColumnIndex(ctx, 1)
                                        reaper.ImGui_SetNextItemWidth(ctx, 110)
                                        ret, stringInput = reaper.ImGui_InputText(ctx, "##ccnaming" .. n,  instrumentSettings.ccNamesOnTrack[n], reaper.ImGui_InputTextFlags_AutoSelectAll()) -- ,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                        if ret then 
                                            instrumentSettings.ccNamesOnTrack[n] = stringInput
                                        end
                                        
                                    end
                                    
                                    reaper.ImGui_PopStyleColor(ctx)
                                    
                                  reaper.ImGui_EndTable(ctx)
                                end
                                
                            end
                            
                            
                            
                            
                            
                            reaper.ImGui_NewLine(ctx)
                            reaper.ImGui_TextColored(ctx, 0x777777FF, 'Script settings')
                            
                            
                            if instrumentSettings.recognizeArticulationsKeyswitches == nil then instrumentSettings.recognizeArticulationsKeyswitches = true end
                            
                            _, instrumentSettings.recognizeArticulationsKeyswitches = reaper.ImGui_Checkbox(ctx, "Recognize articulation triggers", instrumentSettings.recognizeArticulationsKeyswitches)
                            setToolTipFunc("If you want to the script to update when pressing articulations keyswitches or CC's manually")
                            
                            
                            if instrumentSettings.usePDC == nil then instrumentSettings.usePDC = true end 
                            _, instrumentSettings.usePDC = reaper.ImGui_Checkbox(ctx, "Use PDC", instrumentSettings.usePDC)
                            setToolTipFunc("Use script PDC timer delay instead of Track's media playback offset.\nThis option is only relevant if you script contains Delay")
                            
                            
                            reaper.ImGui_NewLine(ctx)
                            
                            
                            
                            reaper.ImGui_TextColored(ctx, 0x777777FF, 'Realtime / Articulation triggers')
                            
                            local alreadyHaveChannel
                            local alreadyHaveVelocity
                            if instrumentSettings.realtimeTrigger then 
                                for i, c in ipairs(instrumentSettings.realtimeTrigger) do
                                    if c[1] == "Channel" then
                                        alreadyHaveChannel = true
                                    elseif c[1] == "Velocity" then
                                        alreadyHaveVelocity = true
                                    end
                                end
                            end
                            
                            buttonsData = {{
                            name = "Controller", triggerName = "CC realtime", key = "C", ctrl = true, buttonType = "popup",
                            tip = "Send a CC switch on realtime / articulation playing"
                            },{
                            name = "Note", triggerName = "Note realtime", key = "N", ctrl = true, buttonType = "multi",
                            tip = "Send a note keyswitch on realtime / articulation playing"
                            },{
                            name = "Velocity", key = "V", ctrl = true, triggerName = "Velocity realtime", buttonType = "multi",
                            tip = "Make notes a specific velocity on realtime / articulation playing", disabled = alreadyHaveVelocity,
                            },{
                            name = "Channel",key = "X", ctrl = true, triggerName = "Channel realtime", buttonType = "multi",
                            tip = "Set global channel on realtime / articulation playing", disabled = alreadyHaveChannel,
                            }}
                            
                            for _, data in ipairs(buttonsData) do
                                createMappingButton(data) 
                                tipTable[data.triggerName] = data.tip
                            end
                            
                            if not instrumentSettings.realtimeTrigger then instrumentSettings.realtimeTrigger = {} end
                            
                            local rowAmount = #instrumentSettings.realtimeTrigger + 1
                            
                            
                            --if reaper.ImGui_BeginChild(ctx, "tablechild", 400, 30 * rowAmount) then
                                tableFlags = --reaper.ImGui_TableFlags_ScrollY() |
                                                --reaper.ImGui_TableFlags_ScrollX() |
                                                reaper.ImGui_TableFlags_NoHostExtendX() |
                                                reaper.ImGui_TableFlags_RowBg() |
                                                reaper.ImGui_TableFlags_Borders()
                                if reaper.ImGui_BeginTable(ctx, 'table2', 4, tableFlags, 600) then --, tableWidth - 10, windowH - tableY - 40) then -- ,reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 20) then
                                    reaper.ImGui_TableSetupScrollFreeze(ctx, 1, 1)
                                    -- Display headers so we can inspect their interaction with borders.
                                    -- (Headers are not the main purpose of this section of the demo, so we are not elaborating on them too much. See other sections for details)
                                
                                    reaper.ImGui_TableSetupColumn(ctx, "Type", reaper.ImGui_TableColumnFlags_WidthFixed(), 120)
                                    reaper.ImGui_TableSetupColumn(ctx, "Number", reaper.ImGui_TableColumnFlags_WidthFixed(), 120)
                                    reaper.ImGui_TableSetupColumn(ctx, "Realtime", reaper.ImGui_TableColumnFlags_WidthFixed(), 120)
                                    reaper.ImGui_TableSetupColumn(ctx, "Articulation", reaper.ImGui_TableColumnFlags_WidthFixed(), 120)
                                
                                    reaper.ImGui_TableHeadersRow(ctx)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0)
                                
                                    -- reaper.ImGui_TableHeadersRow(ctx)
                                    -- Instead of calling TableHeadersRow() we'll submit custom headers ourselves
                                    --reaper.ImGui_TableNextRow(ctx, reaper.ImGui_TableRowFlags_Headers())
                                
                                    --for column = 1, 3 do
                                    --    reaper.ImGui_TableSetColumnIndex(ctx, column - 1) 
                                    --end
                                    for n, t in ipairs(instrumentSettings.realtimeTrigger) do
                                        reaper.ImGui_TableNextRow(ctx)
                                        
                                        reaper.ImGui_TableSetColumnIndex(ctx, 0)
                                        if reaper.ImGui_Button(ctx, t[1] .. "##realtime" .. n .. ":0") then
                                            table.remove(instrumentSettings.realtimeTrigger, n)
                                        end
                                        
                                        
                                        for i = 1, 3 do
                                            local id = "##realtime" .. n .. ":" .. i
                                            reaper.ImGui_TableSetColumnIndex(ctx, i)
                                            reaper.ImGui_SetNextItemWidth(ctx, 112)
                                            if (t[1] == "Channel" or t[1] == "Velocity") and i == 1 then
                                            elseif t[1] == "Note" and i == 1 then
                                            
                                                if instrumentSettings.realtimeTrigger[n] and instrumentSettings.realtimeTrigger[n][i+1] then
                                                    title = instrumentSettings.realtimeTrigger[n][i+1]
                                                else
                                                    title = ""
                                                end  
                                                
                                                visualTitle = allNoteValuesMap[title] -- Only using sharps
                                                 
                                                parenteseTitle = ""
                                                if not visualTitle then 
                                                else
                                                    parenteseTitle = "(" .. visualTitle .. ")"
                                                end
                                                
                                                ret, stringInput = reaper.ImGui_InputText(ctx, "##" .. id, visualTitle, reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsUppercase() | reaper.ImGui_InputTextFlags_CallbackEdit(), filterFunction3Characters) -- ,reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                                                
                                                --if column == focusedColumn and row == focusedRow then
                                                    if ret and stringInput then  
                                                        if stringInput ~= title then 
                                                            if title and tonumber(stringInput) then
                                                                local stringSize = reaper.ImGui_CalcTextSize(ctx, stringInput, 0,0)
                                                                reaper.ImGui_SameLine(ctx, stringSize + 8)
                                                                reaper.ImGui_TextColored(ctx,colorGrey, parenteseTitle)
                                                            end
                                                        
                                                        end
                                                    end
                                                --end
                                                
                                                if ret then
                                                    if tonumber(stringInput) ~= nil and
                                                        allNoteValuesMap[tonumber(stringInput)] then
                                                        startNote = tonumber(stringInput)
                                                    elseif noteNameValues[stringInput] then
                                                        startNote = tonumber(noteNameValues[stringInput])
                                                    else
                                                        startNote = nil
                                                    end
                                                
                                                    instrumentSettings.realtimeTrigger[n][i+1] = tonumber( startNote)
                                                end
                                            else
                                                newInput, inputString = reaper.ImGui_InputText(ctx, id, t[ i + 1], reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_CharsDecimal())
                                                if newInput and (inputString == "" or (tonumber(inputString) >= 0 and (t[1] == "Channel" and tonumber(inputString) <= 16 or tonumber(inputString) <= 127))) then 
                                                    instrumentSettings.realtimeTrigger[n][i + 1] = tonumber(inputString)
                                                end
                                            end
                                        end
                                        
                                    end
                                    
                                    reaper.ImGui_PopStyleColor(ctx)
                                    
                                  reaper.ImGui_EndTable(ctx)
                                end
                                --if reaper.ImGui_Button(ctx, "Clear realtime triggers") then
                                --    instrumentSettings.realtimeTrigger = {}
                                --end
                            reaper.ImGui_EndChild(ctx)
                        end
                        
                        reaper.ImGui_EndTabItem(ctx)
                    end  
                    openMappingsTab = false
                    openSettingsTab = false
                    reaper.ImGui_EndTabBar(ctx)           
                end
                
                function addmapToSelectedTracks()
                    --local focusedWindow = reaper.JS_Window_GetFocus() 
                    --addMap.updateMapOnInstrumentsWithMap(mapName, true)  
                    --if not overWriteFile_Wait then 
                        addMap.addMapToInstruments(mapName) 
                    --end
                    --reaper.JS_Window_SetFocus(focusedWindow)
                end
                
                function updateMapOnTracks()
                    --local focusedWindow = reaper.JS_Window_GetFocus() 
                    --if not overWriteFile_Wait then 
                        addMap.updateMapOnInstrumentsWithMap(mapName) 
                    --end
                    --reaper.JS_Window_SetFocus(focusedWindow)
                    -- RESET TRACK SELECTION HERE TO ENSURE WE UPDATE MAP. MAYBE VIA EXT STATE
                end
                
                
                reaper.ImGui_SetCursorPosY(ctx, windowH - 60)
                buttonsData = {{
                name = "Add script to selected tracks", key = "P", cmd = true, func = function() addmapToSelectedTracks() end,
                },{
                name = "Update script", key = "U", cmd = true, func = function() updateMapOnTracks() end, tip = "Update script on all tracks that already have the script", sameLine = true,
                },{
                name = "Embed UI in TCP", triggerName = "Position", key = "T", cmd = true,
                tip = "UI from articulation script can be shown next to the track name.", sameLine = false,
                func = function() embed_ui.on_selected_tracks() end, -- FX: Show next single FX embedded UI in TCP (selected tracks)
                },{
                name = "-", triggerName = "EmbedUISize", key = "minus", key2 = "keypadMinus" ,cmd = true, doNotshowShortCut = true,
                tip = "Make embedded UI text smaller.\nHold shift to make all the same size.\nUse 'cmd+minus' or 'cmd+keypad minus' to change with keyboard shortcut", sameLine = true,
                func = function() changeArticulationScriptEmbedUiTextSize(false) end, 
                },{
                name = "+", triggerName = "EmbedUISize", key = "plus", cmd = true, doNotshowShortCut = true,
                tip = "Make embedded UI text bigger.\nHold shift to make all the same size.\nUse ''cmd+keypad plus' to change with keyboard shortcut", sameLine = true,
                func = function() changeArticulationScriptEmbedUiTextSize(true) end, 
                }}
                
                for _, data in ipairs(buttonsData) do
                    createMappingButton(data) 
                end
            
            end
        end
        
        if popupOkCancelTitle then
            popupOkCancel(popupOkCancelTitle, popupOkCancelDescription,popupOkCancelFunc,popupOkCancelFuncVal)
        end
        
        
        if popupOkTitle then
            popupOk(popupOkTitle, popupOkDescription)
        end
        
        if popup then 
            reaper.ImGui_OpenPopup(ctx, "popup")
            popupFocus = true
            posX, posY = reaper.ImGui_GetWindowPos(ctx)
            sizeW, sizeH = reaper.ImGui_GetWindowSize(ctx)
            cursorX, cursorY = reaper.ImGui_GetCursorPos(ctx)

            reaper.ImGui_SetNextWindowBgAlpha(ctx, 0.8) -- Transparent background
            reaper.ImGui_SetNextWindowPos(ctx, posX + sizeW / 2 - 120, posY + sizeH / 2 - 10)
            reaper.ImGui_SetNextWindowSize(ctx, 240, 60)

            if reaper.ImGui_BeginPopupContextItem(ctx, "popup", reaper.ImGui_PopupFlags_NoReopen()) then

                -- reaper.ImGui_SetCursorPos(ctx,10, cursorY)
                reaper.ImGui_SetNextItemWidth(ctx, 180)
                if popup == "Name" then
                    reaper.ImGui_Text(ctx, "Write a name for the map:")
                elseif popup == "Art" then
                    reaper.ImGui_Text(ctx, "Amount of new Articulations:")
                elseif popup == "CC" or popup == "CC realtime" then
                    reaper.ImGui_Text(ctx, "Add CC with number:")
                elseif popup == "Increment" then
                    reaper.ImGui_Text(ctx, "Increment value or string with:")
                elseif popup == "Set Velocity" then
                    reaper.ImGui_Text(ctx, "Set velocity for notes to:")
                end
                if popupFocus then
                    reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
                    popupFocus = false
                end

                reaper.ImGui_SetNextItemWidth(ctx, 220)
                if popup == "Name" then
                    newInput, inputString = reaper.ImGui_InputText(ctx, "##cc", popupStringName, reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                else
                    newInput, inputString = reaper.ImGui_InputText(ctx, "##cc", popupStringValue, reaper.ImGui_InputTextFlags_CharsDecimal() | reaper.ImGui_InputTextFlags_EnterReturnsTrue())
                end
                if not reaper.ImGui_IsItemFocused(ctx) then
                    if not firstPopupFocus then 
                        firstPopupFocus = true
                    else
                        --popupGone = false
                        popup = false
                        firstPopupFocus = false
                    end 
                end

                if newInput and inputString == "" then
                    popup = false
                elseif newInput then
                    inputStringNumber = tonumber(inputString)
                    if popup == "Name" then
                        if newInput then
                            mapName = inputString
                        end
                    elseif popup == "Art" then
                        if newInput and inputStringNumber > 0 and inputStringNumber < 128 then 
                            lastRowsAmount = #tableInfo + 1
                            addArticulation(inputStringNumber)
                        end
                    elseif popup == "CC" or popup == "CC realtime" then
                        -- ensure to not add the same CC twice
                        --[[for _, cc in ipairs(mapping.CC) do
                            if inputStringNumber == cc then
                                newInput = false
                            end
                        end]]
                        local setFocusOnNewMapping = "CC" .. inputStringNumber
                        
                        if popup == "CC" then 
                            if tableInfo[setFocusOnNewMapping] then
                                newInput = false
                            end
                            if newInput and inputStringNumber >= 0 and inputStringNumber < 128 then
                                mapping.CC[inputStringNumber] = true
                                modifierSettings[setFocusOnNewMapping] = "Same"
                                tableInfo[setFocusOnNewMapping] = {}
                            end
                        elseif popup == "CC realtime" then
                            if not instrumentSettings.realtimeTrigger then instrumentSettings.realtimeTrigger = {} end
                            
                            if instrumentSettings.realtimeTrigger[setFocusOnNewMapping] then
                                newInput = false
                            end
                            
                            if newInput and inputStringNumber >= 0 and inputStringNumber < 128 then
                                table.insert(instrumentSettings.realtimeTrigger, {"CC", inputStringNumber, 0, 127})
                            end
                        end
                    elseif popup == "Increment" then
                        if newInput then
                            if inputStringNumber < -modifierSettingsPopupMax then
                                inputStringNumber = -modifierSettingsPopupMax
                            end
                            if inputStringNumber > modifierSettingsPopupMax then
                                inputStringNumber = modifierSettingsPopupMax
                            end
                            modifierSettings[modifierSettingsPopupName] = inputStringNumber
                        end
                    elseif popup == "Set Velocity" then
                        if newInput then
                            if inputStringNumber < modifierSettingsPopupMin then
                                inputStringNumber = modifierSettingsPopupMin
                            end
                            if inputStringNumber > modifierSettingsPopupMax then
                                inputStringNumber = modifierSettingsPopupMax
                            end
                            if not tableInfo[modifierSettingsPopupName] then
                                tableInfo[modifierSettingsPopupName] = {}
                            end
                            for rowKey, _ in pairs(selectedArticulations) do
                                tableInfo[modifierSettingsPopupName][rowKey] = inputStringNumber
                            end
                        end
                    end

                    popupGone = false
                    popup = false
                end
                reaper.ImGui_EndPopup(ctx)
                
            end 
        end
        
        
        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        
        if reaper.ImGui_BeginPopupModal(ctx, "Overwrite file", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, "Articulation map already exists!\n\nDo you want to create it with a new name?")
            
            if reaper.ImGui_Button(ctx, 'Overwrite', 120, 30) or enter or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_O(), false) then 
                export.writeFile(overWriteFile_filePath, overWriteFile_text)
                addMap.updateOrAddMapAfterWait()
                reaper.ShowConsoleMsg("hej\n")
                reaper.ImGui_CloseCurrentPopup(ctx) 
            end
            reaper.ImGui_SameLine(ctx)
            setToolTipFunc("Press O or enter on keyboard")
            
            if reaper.ImGui_Button(ctx, 'Unique file', 120, 30) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_U(), false) then 
                export.writeFile(overWriteFile_uniqueFilePath, overWriteFile_text)
                addMap.updateOrAddMapAfterWait()
                reaper.ImGui_CloseCurrentPopup(ctx) 
            end 
            reaper.ImGui_SameLine(ctx)
            setToolTipFunc("Press U on keyboard")
            
            if reaper.ImGui_Button(ctx, 'Cancel', 120, 30) or escape or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_C(), false) then
                reaper.ImGui_CloseCurrentPopup(ctx) 
            end 
            setToolTipFunc("Press C or escape on keyboard")
            
            reaper.ImGui_EndPopup(ctx)
        end
        
        
        counter = 0
        for _, _ in pairs(selectedArticulations) do counter = counter + 1 end
        multipleSelected = counter > 1

        windowW, windowH = reaper.ImGui_GetWindowSize(ctx)
        
        if appSettings.expandWindow then
            if tableWidth and tableWidth > minimumsWidth then
                reaper.ImGui_SetWindowSize(ctx, tableWidth+16+8, windowH)
            else
                reaper.ImGui_SetWindowSize(ctx, minimumsWidth+8, windowH)
            end
        else
            if windowW < minimumsWidth+8 then
                reaper.ImGui_SetWindowSize(ctx, minimumsWidth+8, windowH)
            end
        end

        reaper.ImGui_PopStyleColor(ctx, 4)
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_End(ctx)
    end

    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        -- reaper.JS_Window_SetFocus(focusedWindow)
        if popup then
            popup = false 
            setFocus = focusedItem and math.floor(focusedItem)
            adjust = -1
        else
            -- CONSIDER: MAYBE I'll CHANGE THIS BEHAVIOR
            setFocus = focusedItem and math.floor(focusedItem)
            adjust = -1
        end
    end
    
    --[[
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) and cmd and ctrl then
        tableInfo = undo_redo.undo(tableInfo)
    end
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) and cmd and shift and ctrl then
        tableInfo = undo_redo.redo(tableInfo)
    end
    ]]
    
    if firstLoop then 
        --editFirstSelected()
        firstLoop = false
    end

    if open and not closeAppWindow then reaper.defer(loop) end
end

reaper.defer(loop)
