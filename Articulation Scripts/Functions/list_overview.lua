-- @version 1.0
-- @noindex

local contextName = "ArticulationControls_ListOverview"
--[[ 
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
package.path = package.path .. ";" .. scriptPath .. "Functions/Helpers/?.lua"
package.path = package.path .. ";" .. scriptPath .. "Helpers/?.lua"
 ]]
-- Load pathes
require("pathes")
-- load list of articulation scripts
local articulation_scripts_list = require("get_articulation_scripts").get_articulation_scripts(articulationScriptsPath)
--[[ 
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
 ]]
local export = {}

function export.listOverviewSurface()
    EnsureValidContext(ctx)
    local windowIsFocused
    local visible, open =  reaper.ImGui_Begin(ctx, "Articulations", true,
            --    reaper.ImGui_WindowFlags_NoDecoration() |
                reaper.ImGui_WindowFlags_TopMost()                 -- | reaper.ImGui_WindowFlags_NoMove()
            -- | reaper.ImGui_WindowFlags_NoBackground()
            -- | reaper.ImGui_FocusedFlags_None()
            | reaper.ImGui_WindowFlags_MenuBar()
            
            )

    if visible then    
      --[[
        if waitForFocused > 10 then
            focusedPopupWindow = reaper.JS_Window_GetFocus()
            waitForFocused = -1
        end
        if waitForFocused > -1 then waitForFocused = waitForFocused + 1 end
]]      
        
        if reaper.ImGui_BeginMenuBar(ctx) then 
            if reaper.ImGui_BeginMenu(ctx, "Options") then
                
                local midi_editor = reaper.MIDIEditor_GetActive()
                
                if midi_editor then
                    if reaper.ImGui_BeginMenu(ctx, "View") then
                        
                        local show = reaper.GetToggleCommandStateEx(32060, 42101) == 1
                        if reaper.ImGui_Checkbox(ctx, "Show notation text on notes", show) then
                            reaper.MIDIEditor_OnCommand(midi_editor, 42101) --View: Show notation text on notes 
                        end
                        
                        local show = reaper.GetToggleCommandStateEx(32060, 40040) == 1
                        if reaper.ImGui_Checkbox(ctx, "Show velocity handles on notes", show) then
                            reaper.MIDIEditor_OnCommand(midi_editor, 40040) --View: Show velocity handles on notes
                        end
                        
                        local show = reaper.GetToggleCommandStateEx(32060, 40045) == 1
                        if reaper.ImGui_Checkbox(ctx, "Show note names on notes", show) then
                            reaper.MIDIEditor_OnCommand(midi_editor, 40045) --View: Show note names on notes
                        end
                        
                        
                        local show = reaper.GetToggleCommandStateEx(32060, 40632) == 1
                        if reaper.ImGui_Checkbox(ctx, "Show velocity numbers on notes", show) then
                            reaper.MIDIEditor_OnCommand(midi_editor, 40632) --View: Show velocity numbers on notes
                        end
                        
                        reaper.ImGui_Separator(ctx)
                        
                        
                        local show = reaper.GetToggleCommandStateEx(32060, 42472) == 1
                        if reaper.ImGui_Checkbox(ctx, "Only show CCs on channels of selected notes (MPE mode)", show) then
                            reaper.MIDIEditor_OnCommand(midi_editor, 42472) --Options: only show CCs on channels of selected notes (MPE mode) 
                        end
                    
                    
                        reaper.ImGui_EndMenu(ctx)
                    end
                
                
                    if reaper.ImGui_BeginMenu(ctx, "Notation") then   
                        if reaper.ImGui_Selectable(ctx, "Remove all notation for selected notes", false) then
                            reaper.MIDIEditor_OnCommand(midi_editor, 41298) --Notation: Remove all notation for selected notes 
                        end
                        
                        reaper.ImGui_EndMenu(ctx)
                    end
                end
                
                reaper.ImGui_EndMenu(ctx)
            end
            reaper.ImGui_EndMenuBar(ctx)
        end
        
        windowIsFocused = reaper.ImGui_IsWindowFocused(ctx)
        

        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

        reaper.ImGui_SetNextFrameWantCaptureKeyboard(ctx, 1)
        retval, unicode_char = reaper.ImGui_GetInputQueueCharacter(ctx, 0)
        keyInput = string.char(unicode_char & 0xFF):upper()
        -- reaper.ShowConsoleMsg(unicode_char)


        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        
        local layerAmount = 0
        for layerNumber, layer in pairs(triggerTableLayers) do
            layerAmount = layerAmount + 1
        end
        
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x444444FF )
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x555555FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x666666FF)
        
        local colorText = true
        local layerColor
        local layerX, layerY, layerX2, layerY2
        for layerNumber, layer in pairs(triggerTableLayers) do 
            local isLayerCollabsed = layerCollabsed[layerNumber]
            if layerAmount > 1 then
                layerColor = layer[1].layerColor and tonumber(layer[1].layerColor) or  0x000000FF
                
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x222222FF )
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x000000FF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x000000FF)
                
                reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_SelectableTextAlign(), isLayerCollabsed and 0 or 0.5, 0) 
                local layerName = "Layer " .. layerNumber .. (isLayerCollabsed and (": " .. layer[artSelected[layerNumber] + 1].articulation) or "")
                if reaper.ImGui_Selectable(ctx,layerName, true, selectflag) then 
                    reaper.TrackFX_SetParam(track, fxNumber, artSliders[layerNumber].param + 1, layerCollabsed[layerNumber] and 0 or 1) 
                end
                reaper.ImGui_PopStyleVar(ctx)
                
                layerX, layerY = reaper.ImGui_GetItemRectMin(ctx) 
                
                if not layerCollabsed[layerNumber] then
                    reaper.ImGui_Separator(ctx)
                end
                
                reaper.ImGui_PopStyleColor(ctx,4)
            end
            if not isLayerCollabsed then
                for artNum, key in ipairs(layer) do
                    isSelected = artNum - 1 == artSelected[layerNumber]
                    local buttonTitle
                    if #key.subtitle > 0 then
                        buttonTitle = key.subtitle ..
                        ": " .. -- \n" ..
                        key.title:gsub("+ ", "+")--:gsub(" ", "\n")                                                    -- .. " " .. colorGradient
                    else
                        buttonTitle = key.title:gsub("+ ", "+")--:gsub(" ", "\n")                                      -- .. " " .. colorGradient
                    end
                    if reaper.ImGui_Selectable(ctx, buttonTitle .. "##" .. layerNumber .. ":".. artNum, isSelected) then 
                        changeArticulation(key.programChange, key.articulation)
                    end
                end
                
            end
            
            if layerColor then 
                layerX2, layerY2 = reaper.ImGui_GetItemRectMax(ctx)
                reaper.ImGui_DrawList_AddRect(draw_list, layerX, layerY, layerX2, layerY2, layerColor)
                reaper.ImGui_Spacing(ctx)
            end
        end
        
        reaper.ImGui_PopStyleColor(ctx,3)
                
        
        reaper.ImGui_End(ctx)
    end

    if not open then 
        setToggleCommandState(listOverview_command_id)
    end

    return windowIsFocused
end


return export