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

-- Load pathes
require("pathes")
-- load list of articulation scripts
local articulation_scripts_list = require("get_articulation_scripts").get_articulation_scripts(articulationScriptsPath)
local file_handling = require("file_handling")
json = require("json")

local articulation_scripts_list_currentVersion = {}
for i, script in ipairs(articulation_scripts_list) do 
    local jsonString = file_handling.readFileForJsonLine(script.path)
            
    if jsonString then
        if file_handling.importJsonString(jsonString) then 
            table.insert(articulation_scripts_list_currentVersion, script)
        end
    end
end

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


------------------------------------------------------------
-- UI loop
------------------------------------------------------------
local function loop()
    
    reaper.ImGui_SetNextWindowSize(ctx, 600, 456, reaper.ImGui_Cond_Appearing())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Articulation scripts - Scripts Browser Window', true, 
    reaper.ImGui_WindowFlags_TopMost() 
    --| reaper.ImGui_WindowFlags_AlwaysAutoResize()
    
    --| reaper.ImGui_WindowFlags_NoCollapse()
    )
    if visible then
                
        modifierSettings = nil
        --local isEscape = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
        
        if reaper.ImGui_BeginChild(ctx, "Script name", 300) then
        
            for i, script in ipairs(articulation_scripts_list_currentVersion) do 
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x222222FF )
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x000000FF)
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x000000FF)
                
                 if reaper.ImGui_Selectable(ctx,script.name .. "##" .. i, false) then  
                    focusedScript = script
                    --scriptAdded = addMapToInstruments(script)
                end
                 
                --reaper.ImGui_PopStyleColor(ctx,4)
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_BeginGroup(ctx)
        reaper.ImGui_Text(ctx, "PREVIEW")
        
        if focusedScript then 
            local jsonString = file_handling.readFileForJsonLine(focusedScript.path)
                    
            if jsonString then
                if file_handling.importJsonString(jsonString) then 
                    reaper.ImGui_Text(ctx, mapName)
                end
            end
            
            
        end
            
        reaper.ImGui_EndGroup(ctx)
        
        
        
        --reaper.ImGui_PopStyleColor(ctx,3)                
        
        reaper.ImGui_End(ctx)
    end
    
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
