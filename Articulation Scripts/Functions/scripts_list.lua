-- @noindex

local contextName = "ArticulationControls_ScriptsList"
--[[ 
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
package.path = package.path .. ";" .. scriptPath .. "Functions/Helpers/?.lua"
package.path = package.path .. ";" .. scriptPath .. "Helpers/?.lua"
 ]]

local addMapToInstruments = require("add_script_to_instrument").addMapToInstruments

-- Load pathes
require("pathes")
-- load list of articulation scripts
local articulation_scripts_list = require("get_articulation_scripts").get_articulation_scripts(articulationScriptsPath)

function setupLocalSurface()    
    ctx = reaper.ImGui_CreateContext(contextName)
    -- font = reaper.ImGui_CreateFont('Arial', 30, reaper.ImGui_FontFlags_Bold())
    font = reaper.ImGui_CreateFont('Arial')
    -- imgui_font
    reaper.ImGui_Attach(ctx, font)
    --return ctx, font
end

function EnsureValidContext(ctx)
  if not ctx or type(ctx) ~= "userdata" or not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    return setupLocalSurface()    
  end
end

local export = {}
function export.listOfArticulationsScripts()
    EnsureValidContext(ctx)
    local scriptAdded = false
    local visible, open = reaper.ImGui_Begin(ctx, "Articulations Scripts List", true,
            --    reaper.ImGui_WindowFlags_NoDecoration() |
                reaper.ImGui_WindowFlags_TopMost()                 -- | reaper.ImGui_WindowFlags_NoMove()
            -- | reaper.ImGui_WindowFlags_NoBackground()
            -- | reaper.ImGui_FocusedFlags_None()
            --| reaper.ImGui_WindowFlags_MenuBar()
            
            )
    if visible and open then     
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x444444FF )
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x555555FF)
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x666666FF)
        
        
        for i, script in ipairs(articulation_scripts_list) do 
            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x222222FF )
            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x000000FF)
            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x000000FF)
            
             if reaper.ImGui_Selectable(ctx,script .. "##" .. i, false) then  
                scriptAdded = addMapToInstruments(script)
            end
             
            --reaper.ImGui_PopStyleColor(ctx,4)
        end
        
        --reaper.ImGui_PopStyleColor(ctx,3)                
        
        reaper.ImGui_End(ctx)
    end
    return scriptAdded
end

return export