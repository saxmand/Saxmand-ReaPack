-- @noindex

local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()

seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
scriptPathSubfolder = scriptPath .. "Functions" .. seperator  

local functionsFilePath = ""
local functionsFileExtension = ""
local devMode = scriptPath:match("jesperankarfeldt") ~= nil
if devMode then
    local devFilesPath = reaper.GetResourcePath() .. "/Scripts/Saxmand-ReaPack-Private/Articulation Scripts/Functions/"
    package.path = package.path .. ";" .. devFilesPath .. "?.lua"
else
    package.path = package.path .. ";" .. scriptPathSubfolder .. "?.dat"
end
package.path = package.path .. ";" .. scriptPathSubfolder .. "?.lua"
package.path = package.path .. ";" .. scriptPathSubfolder .. "Helpers" .. seperator  .. "?.lua"



local addMapToInstruments = require("add_script_to_instrument").addMapToInstruments
local modern_ui = require("modern_ui")

-- Load pathes
require("pathes")
-- load list of articulation scripts
local articulation_scripts_list = require("get_articulation_scripts").get_articulation_scripts(articulationScriptsPath)
local file_handling = require("file_handling")
local mapping_handling = require("mapping_handling")
local midi_note_names = require("midi_note_names")
json = require("json")
local export = require("export")
require("imgui_colors")
local articulation_scripts_library = require("articulation_scripts_library")

local columnsToNotUseLanes = mapping_handling.columnsToNotUseLanes()

local articulation_scripts_list_currentVersion = {}

--function readLocalScripts()
    --articulation_scripts_list_currentVersion = {}
    for i, script in ipairs(articulation_scripts_list) do 
        --local jsonString = file_handling.readFileForJsonLine(script.path) 
        --if jsonString then 
            --local foundJson, tbl = file_handling.importJsonString(jsonString)
            --if foundJson then -- file_handling.importJsonString(jsonString) then 
                table.insert(articulation_scripts_list_currentVersion, script)
            --end
        --end
    end
--end

local database_path = scriptPath .. "articulation_scripts_library.txt"
local database_articulation_scripts = {}

local function readCloudDatabase()
    local lines = file_handling.readFileLines(database_path, "//json:") 
    for _, line in ipairs(lines) do
        local foundJson, tbl = file_handling.importJsonString(line)
        if foundJson then 
            table.insert(database_articulation_scripts, tbl)
        end
    end
end

function updateCloudLibrary()
    local text = articulation_scripts_library.readSharedText()
    export.writeFile(database_path, text)
    database_articulation_scripts = {}
    readCloudDatabase()
end

--if reaper.file_exists(database_path) then 
--updateCloudLibrary()
readCloudDatabase()
--end

--[[ 
local license = require("check_license")
local registeredEmail, registeredCode = license.registered_license()
local isDemo = license.is_demo_valid()
--local isFree = license.check_articulation_script_list()
-- UI state
local email_buf = registeredEmail and registeredEmail or ''
local code_buf  = registeredCode and registeredCode or ''
local status_msg = (registeredEmail and registeredCode) and 'Active license installed' or ('Activation requires an active internet connection')
local validLicense = (registeredEmail and registeredCode)

isDemo = not validLicense and isDemo or false
]]

-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end



local ctx = reaper.ImGui_CreateContext('Articulation Script - Browser')

local database_focus = "Local"
local focusedScript, focusedScriptIndex
------------------------------------------------------------
-- UI loop
------------------------------------------------------------
local function loop()
    modern_ui.apply(ctx)
    reaper.ImGui_SetNextWindowSize(ctx, 600, 456, reaper.ImGui_Cond_Appearing())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Articulation Scripts Browser Window', true, 
    reaper.ImGui_WindowFlags_TopMost() 
    --| reaper.ImGui_WindowFlags_AlwaysAutoResize()
    
    --| reaper.ImGui_WindowFlags_NoCollapse()
    )
    if visible then
        
        if not focusedScriptIndex then focusedScriptIndex = 1 end
                
        modifierSettings = nil
        --local isEscape = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
        
        
        local btns = {"Local", "Database"}
        for _, b in ipairs(btns) do
            
            if reaper.ImGui_RadioButton(ctx, b, database_focus == b) then
                database_focus = b
                focusedScriptIndex = nil
            end
            reaper.ImGui_SameLine(ctx)
        end

        local scripts_to_use =  database_focus == "Local" and articulation_scripts_list_currentVersion or database_articulation_scripts

        if reaper.ImGui_Button(ctx, "UPDATE DATABASE") then
            updateCloudLibrary()
        end
        
        if focusedScriptIndex then 
            -- on local we only read the file if we have it selected
            if database_focus == "Local" then 
                local jsonString = file_handling.readFileForJsonLine(scripts_to_use[focusedScriptIndex].path)
                        
                if jsonString then
                    local foundJson, tbl = file_handling.importJsonString(jsonString) 
                    if foundJson then 
                        focusedScript = tbl
                    end
                end
            else
                focusedScript = scripts_to_use[focusedScriptIndex]
            end
        end

        if focusedScript then 
            reaper.ImGui_SameLine(ctx)
            mapping = focusedScript.mapping
            tableInfo = focusedScript.tableInfo
            instrumentSettings = focusedScript.instrumentSettings
            mapName = focusedScript.mapName
            if reaper.ImGui_Button(ctx, "Add script to selected tracks") then
                addMapToInstruments(mapName) 
            end
        end

        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, "ARTICULATION SCRIPTS")
        reaper.ImGui_Separator(ctx)
        
        if reaper.ImGui_BeginChild(ctx, "Script name", 300) then 
            for i, tbl in ipairs(scripts_to_use) do 
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x222222FF )
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x000000FF)
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x000000FF)
                local name = database_focus == "Local"  and tbl.name or tbl.mapName
                if reaper.ImGui_Selectable(ctx, name .. "##" .. i, focusedScriptIndex == i) then  
                    focusedScriptIndex = i
                    --scriptAdded = addMapToInstruments(script)
                end
                 
                --reaper.ImGui_PopStyleColor(ctx,4)
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_EndGroup(ctx)
        
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then 
            if focusedScriptIndex > 1 then focusedScriptIndex = focusedScriptIndex - 1 end
        end
        
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then 
            if focusedScriptIndex < #scripts_to_use then 
                focusedScriptIndex = focusedScriptIndex + 1 
            end
        end
        if focusedScriptIndex and focusedScriptIndex > #scripts_to_use then
            focusedScriptIndex = 1
        end
        

        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_BeginGroup(ctx)
        
        
        
        if focusedScript then 
            local mapping = focusedScript.mapping
            local tableInfo = focusedScript.tableInfo
            local instrumentSettings = focusedScript.instrumentSettings
            local mapName = focusedScript.mapName
            
            function infoButtons(value, forceText) 
                reaper.ImGui_TextColored(ctx, colorGrey, value ..":")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextWrapped(ctx, forceText and forceText or (instrumentSettings and instrumentSettings[value]))
            end
            
            reaper.ImGui_TextColored(ctx, colorGrey, "PREVIEW")
            reaper.ImGui_Separator(ctx)            
            infoButtons("Name", mapName) 
            infoButtons("Creator") 
            infoButtons("Vendor") 
            infoButtons("Product") 
            infoButtons("Patch") 
            infoButtons("Info") 
            
            mappingType = mapping_handling.createTableOrderFromUsedMappings(mapping)  
            local columnAmount = #mappingType 
            totalItemAmount = (#tableInfo) * (columnAmount)
            
            local totalArticulations = 0
            local totalLayers = 0
            local layersUsed = {}
            -- WE COULD ADD FILTERS, KEYSWITCHES ETC HERE
            for _, t in ipairs(tableInfo) do
                if t.Layer and not layersUsed[t.Layer] then 
                    layersUsed[t.Layer] = true
                    totalLayers = totalLayers + 1
                elseif not layersUsed[1] then
                    layersUsed[1] = true
                    totalLayers = totalLayers + 1
                end
                if not t.isLane then
                    totalArticulations = totalArticulations + 1 
                end
            end
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Articulations: " .. totalArticulations .. " / Layers: " .. totalLayers)
            
            --if reaper.ImGui_BeginChild(ctx, "tablechild2") then
                                        
            tableFlags = --
                       
                       reaper.ImGui_TableFlags_RowBg() 
                       | reaper.ImGui_TableFlags_ScrollX()
                       | reaper.ImGui_TableFlags_ScrollY()
                       | reaper.ImGui_TableFlags_Borders()
                       | reaper.ImGui_TableFlags_NoHostExtendX()
                       | reaper.ImGui_TableFlags_NoHostExtendY()
                       --| reaper.ImGui_TableFlags_SizingFixedFit()
                       --| reaper.ImGui_TableFlags_Resizable()
                       
            if reaper.ImGui_BeginTable(ctx, 'table1', columnAmount, tableFlags) then
                
                reaper.ImGui_TableSetupScrollFreeze(ctx, 1, 1)
                
                for _, mappingName in ipairs(mappingType) do 
                    local tbSize = _G["tableSize" .. mappingName]
                    if not tbSize then                                             
                        if mapping_handling.getNoteNumber(mappingName) then                                                
                            tbSize = tableSizeNote                                                                                
                        elseif mapping_handling.getCCNumber(mappingName) then                                                
                            tbSize = tableSizeCC   
                        --else
                        --    tbSize = tableSizeOthers 
                        end
                    end
                    
                    --reaper.ImGui_TableSetupColumn(ctx, mappingName, reaper.ImGui_TableColumnFlags_WidthFixed(), tbSize)
                end
                                                    
                            
                            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), colorGrey) 
                reaper.ImGui_TableNextRow(ctx)--, reaper.ImGui_TableRowFlags_Headers())
                --reaper.ImGui_TableHeadersRow(ctx)
                for column = 1, columnAmount  do
                    reaper.ImGui_TableSetColumnIndex(ctx, column - 1)
                    local column_name = mappingType[column]

                    visualColumnName = mapping_handling.getVisualColumnName(column_name)
                    
                    reaper.ImGui_Text(ctx, visualColumnName)
                    reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), colorDarkGrey)  
                end
                
                --reaper.ImGui_PopStyleColor(ctx)
                
                for row = 1, #tableInfo do
                    
                    --reaper.ImGui_TableNextRow(ctx) 
                    
                    reaper.ImGui_TableNextRow(ctx) 
                    for column = 1, columnAmount do
                        reaper.ImGui_TableSetColumnIndex(ctx, column - 1)
                        local columnName = mappingType[column]
                        local text = tableInfo[row][columnName]
                        if tostring(text):match("!!Lane") ~= nil then 
                            if columnsToNotUseLanes[columnName] then 
                                local mainLaneRow = mapping_handling.getMainLaneRow(tableInfo, columnName, row)
                                if tableInfo[mainLaneRow][columnName] then 
                                    reaper.ImGui_TextColored(ctx, colorGrey, tableInfo[mainLaneRow][columnName])
                                end
                            end
                        else
                            reaper.ImGui_Text(ctx, text)
                        end
                    end
                end
                        
                    
                
                reaper.ImGui_EndTable(ctx)
            --end
            --reaper.ImGui_EndChild(ctx)
            end
        else
            reaper.ImGui_Text(ctx, "PREVIEW")
            
            
            
        end
            
        reaper.ImGui_EndGroup(ctx)
        
        
        
        --reaper.ImGui_PopStyleColor(ctx,3)                
        
        reaper.ImGui_End(ctx)
    end
    
    modern_ui.ending(ctx)

    if not toolbarSet then 
        setToolbarState(true) 
        toolbarSet = true
    end
    reaper.atexit(exit)
    
    if open then 
        reaper.defer(loop) 
    end
end

loop()
