-- @noindex

 retval, filename, sectionID, cmdID, mode, resolution, val = reaper.get_action_context()

if cmdID == 70667 then 
    
    if 1 == reaper.GetToggleCommandState(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386")) then --Script: Saxmand_Articulation_Background Server.lua
    --    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0) --Script: Saxmand_Articulation_Background Server.lua
    else
    
    --if reaper.GetExtState("articulationMap", "running") == "1" then 
        reaper.JS_Window_SetFocus(reaper.GetMainHwnd())
    --end
    end
    
    if 0 == reaper.GetToggleCommandState(reaper.NamedCommandLookup("_RS841db956c42cd98894e1219da2c9184f5909a15e"), 0) then --Script: Saxmand_Articulation_Background Server.lua
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS841db956c42cd98894e1219da2c9184f5909a15e"), 0) --Script: Saxmand_Articulation_Keyboard Trigger Surface.lua
    end
    
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0) --Script: Saxmand_Articulation_Background Server.lua
    reaper.SetToggleCommandState(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0, 1)
    
    return
else

end

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
local buttons = require("special_buttons")
require("imgui_colors")
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

function getCreatorScriptId()
    local sep = package.config:sub(1,1)
    local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
    local devMode = scriptPath:match("jesperankarfeldt") ~= nil
    local creatorScriptPath = reaper.GetResourcePath()
    .. sep .. "Scripts"
    .. sep .. (devMode and "Saxmand-ReaPack" or "Saxmand ReaPack")
    .. sep .. "Articulation Scripts"
    .. sep .. "Saxmand_Articulation_Script Creator.lua"
    local command_id = reaper.AddRemoveReaScript(true, 0, creatorScriptPath, false)
    local creatorIsOpen = reaper.GetToggleCommandState(command_id) > 0
    return command_id, creatorIsOpen
end

function export.openCreatorWindow(path, save)    
    local command_id, creatorIsOpen = getCreatorScriptId()

    if save then 
        reaper.SetExtState("articulationMap", "saveScript", "1", false)
        --if reaper.GetToggleCommandState(command_id) == 1 then 
        --    reaper.Main_OnCommand(command_id, 0)  
        --end
    else
        if path then 
            reaper.SetExtState("articulationMap", "openScript", path, false)
        end

        if not creatorIsOpen then 
            reaper.Main_OnCommand(command_id, 0)    
        end
    end
end

function GetTextColorForBackground(u32_color)
    -- Extract 8-bit R, G, B from U32 (ImGui format: 0xAABBGGRR)
    r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(u32_color)

    -- Calculate relative luminance (W3C standard)
    local luminance = 0.4 * r * 256 + 0.8 * g * 256 + 0.4 * b * 256

    -- Use black if background is bright, white if it's dark
    if luminance > 186 then
        return reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1) -- black
    else
        return reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1) -- white
    end
end

function export.listOverviewSurface(focusIsOn)
    EnsureValidContext(ctx)    
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    modern_ui.apply(ctx)
    
    
    local windowIsFocused      
    local menuOpen = false
    local articulationChange = false
    
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), (120 - settings.listOverview_transparency)/100)
    --local windowColorBg = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0, (100 - settings.listOverview_transparency)/100)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), windowColorBg)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), colorBlack)
    
    reaper.ImGui_PushFont(ctx, fontFat,  13)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 7)

    reaper.ImGui_SetNextWindowSize(ctx, 200, 600, reaper.ImGui_Cond_FirstUseEver())
    local visible, open =  reaper.ImGui_Begin(ctx, "Articulations List", true,
            --    reaper.ImGui_WindowFlags_NoDecoration() |
                reaper.ImGui_WindowFlags_TopMost()                 -- | reaper.ImGui_WindowFlags_NoMove()
            -- | reaper.ImGui_WindowFlags_NoBackground()
            -- | reaper.ImGui_FocusedFlags_None()
            | reaper.ImGui_WindowFlags_MenuBar()
            
            )
    --reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopFont(ctx)
    
    reaper.ImGui_PopStyleVar(ctx)
    if visible then    

      --[[
        if waitForFocused > 10 then
            focusedPopupWindow = reaper.JS_Window_GetFocus()
            waitForFocused = -1
        end
        if waitForFocused > -1 then waitForFocused = waitForFocused + 1 end

]]      
        
        --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 4)
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), colorDarkGrey)

        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 1)
        reaper.ImGui_PushFont(ctx, font,  13)
        if reaper.ImGui_BeginMenuBar(ctx) then 
            --reaper.ImGui_PushFont(ctx, font,  12)
            
            --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 4)
            
            notation_events.options()
            
            
            --local posX1 = reaper.ImGui_GetCursorPosX(ctx)
            if reaper.ImGui_BeginMenu(ctx, "Settings") then
                menuOpen = true
                if reaper.ImGui_Checkbox(ctx, "Show Layer text", settings.listOverview_showLayerText) then
                    settings.listOverview_showLayerText = not settings.listOverview_showLayerText
                    saveSettings()
                end

                reaper.ImGui_Indent(ctx)
                if reaper.ImGui_Checkbox(ctx, "Show Layer text on layers with a single articulation", settings.listOverview_showLayerTextWithSingleArticulation) then
                    settings.listOverview_showLayerTextWithSingleArticulation = not settings.listOverview_showLayerTextWithSingleArticulation
                    saveSettings()
                end
                reaper.ImGui_Unindent(ctx)

                if reaper.ImGui_Checkbox(ctx, "Organize buttons in group names", settings.listOverview_organizeButtonsInGroupNames) then
                    settings.listOverview_organizeButtonsInGroupNames = not settings.listOverview_organizeButtonsInGroupNames
                    saveSettings()
                end
                
                reaper.ImGui_Indent(ctx)
                    if reaper.ImGui_Checkbox(ctx, "Show group name as header", settings.listOverview_showGroupNameAsHeader) then
                        settings.listOverview_showGroupNameAsHeader = not settings.listOverview_showGroupNameAsHeader
                        if settings.listOverview_showGroupNameAsHeader then 
                            settings.listOverview_organizeButtonsInGroupNames = true
                        end
                        saveSettings()
                    end
                reaper.ImGui_Unindent(ctx)


                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_Checkbox(ctx, "Only show list overview when there's a map", settings.listOverview_onlyShowWhenTheresAMap) then
                    settings.listOverview_onlyShowWhenTheresAMap = not settings.listOverview_onlyShowWhenTheresAMap
                    saveSettings()
                end
                if reaper.ImGui_Checkbox(ctx, "Only show list overview when MIDI editor is open", settings.listOverview_onlyShowOnMidiEditor) then
                    settings.listOverview_onlyShowOnMidiEditor = not settings.listOverview_onlyShowOnMidiEditor
                    saveSettings()
                end

                
                reaper.ImGui_SetNextItemWidth(ctx, 150)
                ret, settings.listOverview_size = reaper.ImGui_SliderInt(ctx, "Size", settings.listOverview_size, 50, 300)
                if ret then  
                    saveSettings()
                end
                

                reaper.ImGui_SetNextItemWidth(ctx, 150)
                ret, settings.listOverview_transparency = reaper.ImGui_SliderInt(ctx, "Window transparency", settings.listOverview_transparency, 0, 80)
                if ret then                 
                    saveSettings()
                end

                notation_events.others()

                reaper.ImGui_EndMenu(ctx)
            end
            
            reaper.ImGui_Text(ctx, (focusIsOn and " [" .. focusIsOn .. "]" or ""))
            --local posX2 = reaper.ImGui_GetCursorPosX(ctx)
            --reaper.ImGui_SetCursorPosX(ctx, 4)
            --if buttons.cogwheel(ctx, "listOverview_settings",  math.ceil(settings.listOverview_size/100 * 18), colorGrey, "Settings", colorGrey, colorWhite, colorTransparent, colorDarkGrey, colorDarkGrey, colorBlack) then
                --reaper.ImGui_OpenPopup(ctx, "listOverview_settings")
            --end
            --reaper.ImGui_SetCursorPosX(ctx, posX2)

            --reaper.ImGui_PopStyleVar(ctx)
            --reaper.ImGui_PopFont(ctx)
            reaper.ImGui_EndMenuBar(ctx)
        end


        --reaper.ImGui_PopStyleColor(ctx,1)
        reaper.ImGui_PopFont(ctx)
        
        reaper.ImGui_PopStyleVar(ctx)
        --if reaper.ImGui_BeginPopup(ctx, "listOverview_settings") then
            
        
        --    reaper.ImGui_EndPopup(ctx)
        --end
        --[[
        windowIsFocused = reaper.ImGui_IsWindowFocused(ctx)
        local forgroundHwnd = reaper.JS_Window_GetForeground()
        local mainHwnd = reaper.GetMainHwnd()
        
        if reaper.ImGui_IsWindowHovered(ctx) and not windowIsFocused then
            if forgroundHwnd == mainHwnd then 
                last_window_focus = forgroundHwnd
            end
        end
        ]]
        modern_ui.bypassed_begin(ctx)
        
        reaper.ImGui_PushFont(ctx, font,  math.ceil(settings.listOverview_size/100 * 12))

        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

        reaper.ImGui_SetNextFrameWantCaptureKeyboard(ctx, 1)
        retval, unicode_char = reaper.ImGui_GetInputQueueCharacter(ctx, 0)
        keyInput = string.char(unicode_char & 0xFF):upper()
        -- reaper.ShowConsoleMsg(unicode_char)


        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        
        
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_SelectableTextAlign(), isLayerCollabsed and 0 or 0.5, 0) 
        local trackColor = track and modern_ui.getTrackColor(track) or 0x222222FF 
        local textColor = GetTextColorForBackground(trackColor)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), trackColor )
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), trackColor)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), trackColor)
        --reaper.ImGui_Text(ctx, tostring(trackName))
        local btnName = trackName
        local path, scriptAlreadyOpen, creatorIsOpen
        if fxName then 
            local scriptThatIsOpen = reaper.GetExtState("articulationMap", "scriptThatIsOpen")
            --local fxNumber, fxName = track_depending_on_selection.findArticulationScript(track) 
            path = reaper.GetResourcePath() .. "/Effects/Articulation Scripts/" .. fxName .. ".jsfx"
            scriptAlreadyOpen = scriptThatIsOpen == path
        end
        if trackNameIsHovered then 
            _, creatorIsOpen = getCreatorScriptId()            
        end
        btnName = trackNameIsHovered and (scriptAlreadyOpen and "Save script and update" or (path and "Click to edit script" or (creatorIsOpen and "Create new script" or "Open Script Creator"))) or trackName
        if reaper.ImGui_Selectable(ctx,btnName, true) then 
            if creatorIsOpen then 
                if not path then path = "[EMPTY]" end
            end
            export.openCreatorWindow(path, scriptAlreadyOpen) 
            --if track and fxNumber then 
                --local val = reaper.TrackFX_GetFloatingWindow(track, fxNumber)
                --reaper.TrackFX_Show(track, fxNumber, not val and 3 or 2)
            --end
        end        
        trackNameIsHovered = reaper.ImGui_IsItemHovered(ctx)
        
        reaper.ImGui_PopStyleColor(ctx,4)
        reaper.ImGui_PopStyleVar(ctx)

        if #triggerTableLayers == 1 then
            reaper.ImGui_Separator(ctx)
        end
        reaper.ImGui_Spacing(ctx)
        
        local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x444444FF )
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x555555FF)
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x666666FF)
        

        local colorText = true
        local layerColor
        for layerNumber, layer in ipairs(triggerTableLayers) do 
            local layerX, layerY, layerX2, layerY2
            local isLayerCollabsed = layerCollabsed[layerNumber]
            if #triggerTableLayers > 1 then
                layerColor = layer[1].layerColor and tonumber(layer[1].layerColor) or  0x000000FF
                
                if (layerCollabsed[layerNumber]) or (settings.listOverview_showLayerText and (#layer > 1 or settings.listOverview_showLayerTextWithSingleArticulation))  then 
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x222222FF )
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x000000FF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x000000FF)
                    
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_SelectableTextAlign(), isLayerCollabsed and 0 or 0.5, 0) 
                    local layerName = "Layer " .. layerNumber .. (isLayerCollabsed and (": " .. layer[artSelected[layerNumber] + 1].articulation) or "")
                    if reaper.ImGui_Selectable(ctx,layerName, true, selectflag) then 
                        reaper.TrackFX_SetParam(track, fxNumber, artSliders[layerNumber].param + 1, layerCollabsed[layerNumber] and 0 or 1) 
                    end
                    reaper.ImGui_PopStyleColor(ctx,4)
                    reaper.ImGui_PopStyleVar(ctx)
                    layerX, layerY = reaper.ImGui_GetItemRectMin(ctx) 

                    if not layerCollabsed[layerNumber] then
                        reaper.ImGui_Separator(ctx)
                    end
                end             
            end

            if not isLayerCollabsed or #triggerTableLayers == 1 then

                local sortedGroups = {}
                local groupFound = {}
                local groupIndexCount = 1
                local layerOrganized = {}
                if settings.listOverview_organizeButtonsInGroupNames then 
                    for artNum, key in ipairs(layer) do  
                        local group = (key.group and key.group ~= "") and key.group or "NOGROUPTAG"
                        if not groupFound[group] then 
                            groupFound[group] = groupIndexCount
                            sortedGroups[groupFound[group]] = {}
                            groupIndexCount = groupIndexCount + 1
                        end
                        table.insert(sortedGroups[groupFound[group]], key)
                    end         
                    for artNum, gr in ipairs(sortedGroups) do
                        for _, art in ipairs(gr) do
                            table.insert(layerOrganized, art)
                        end
                    end   
                else
                    layerOrganized = layer
                end
              

                local groupHeaderShown = {}
                local groupAmountTbl = {}
                local groupAmount = 0
                for artNum, key in ipairs(layerOrganized) do        
                    if key.group and not groupAmountTbl[key.group] then
                        groupAmountTbl[key.group] = true
                        groupAmount = groupAmount + 1
                    end                
                end
                for artNum, key in ipairs(layerOrganized) do        
                    if settings.listOverview_showGroupNameAsHeader then --#triggerTableLayers > 1 then
                        if key.group and not groupHeaderShown[key.group] and groupAmount > 1 then
                            groupHeaderShown[key.group] = true
                            groupColor = key.groupColor and tonumber(key.groupColor) or  0x000000FF
                        
                        --if (layerCollabsed[layerNumber]) or (settings.listOverview_showLayerText and (#layer > 1 or settings.listOverview_showLayerTextWithSingleArticulation))  then 
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x00000000 )
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x00000000)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x00000000)
                            
                            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_SeparatorTextAlign(), 0.5, 0.5) 
                            local layerName = key.group
                            
                            reaper.ImGui_SeparatorText(ctx, key.group)
                            --if reaper.ImGui_Selectable(ctx,layerName, true) then 
                                --reaper.TrackFX_SetParam(track, fxNumber, artSliders[layerNumber].param + 1, layerCollabsed[layerNumber] and 0 or 1) 
                            --end
                            reaper.ImGui_PopStyleColor(ctx,4)
                            reaper.ImGui_PopStyleVar(ctx)
                            groupX, groupY = reaper.ImGui_GetItemRectMin(ctx) 

                            if not groupCollabsed[layerNumber] then
                                --reaper.ImGui_Separator(ctx)
                            end
                        end             
                    end      
                    
                    isSelected = key.artInLayer == artSelected[layerNumber]
                    local buttonTitle
                    --if #key.group > 0 then
                        buttonTitle = ((not settings.listOverview_showGroupNameAsHeader and key.group and key.group ~= "") and (key.group .. ": " ) or "") 
                        .. key.title--:gsub("+ ", "+")--:gsub(" ", "\n")                                                    -- .. " " .. colorGradient
                    --else
                    ----    buttonTitle = key.title:gsub("+ ", "+")--:gsub(" ", "\n")                                      -- .. " " .. colorGradient
                    --end
                    if reaper.ImGui_Selectable(ctx, buttonTitle .. "##" .. layerNumber .. ":".. artNum, isSelected) then 
                        changeArticulation(nil, key.articulation, focusIsOn)
                        articulationChange = true
                    end
                    notation_events.buttons_tooltip()
                    if not layerX then 
                        layerX, layerY = reaper.ImGui_GetItemRectMin(ctx) 
                    end
                end
                
            end
            
            if layerColor and layerX then 
                layerX2, layerY2 = reaper.ImGui_GetItemRectMax(ctx)
                reaper.ImGui_DrawList_AddRect(draw_list, layerX, layerY, layerX2, layerY2, layerColor, 6)
                reaper.ImGui_Spacing(ctx)
            end
        end 
        --reaper.ImGui_PopStyleColor(ctx,3)
        modern_ui.bypassed_end(ctx)        
        reaper.ImGui_PopFont(ctx)
        
        
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx)
    --reaper.ImGui_PopStyleColor(ctx,2)
    modern_ui.ending(ctx)

    if not open then 
        --setToggleCommandState(listOverview_command_id)
    end

    return articulationChange -- not menuOpen and windowIsFocused
end


return export
