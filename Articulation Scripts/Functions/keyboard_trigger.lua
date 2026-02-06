-- @noindex

local retval, filename, sectionID, cmdID, mode, resolution, val = reaper.get_action_context()

-- If cmdID is non-zero → script was triggered as an action (user)
-- If cmdID is 0 → usually run via another script (Main_OnCommandEx / NamedCommandLookup)

if cmdID == 70649 then 
    reaper.ShowConsoleMsg(tostring(reaper.GetToggleCommandState(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0)).." hej\n")
    
    if 1 == reaper.GetToggleCommandState(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386")) then --Script: Saxmand_Articulation_Background Server.lua
    --    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0) --Script: Saxmand_Articulation_Background Server.lua
    end
    
    if 0 == reaper.GetToggleCommandState(reaper.NamedCommandLookup("_RS45a019eade443d350f788429a7d9124b0a9ed200"), 0) then --Script: Saxmand_Articulation_Background Server.lua
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS45a019eade443d350f788429a7d9124b0a9ed200"), 0) --Script: Saxmand_Articulation_Keyboard Trigger Surface.lua
    end
    
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0) --Script: Saxmand_Articulation_Background Server.lua
    reaper.SetToggleCommandState(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0, 1)
    return
else

end
    
local edit_keyboard_layout = false
    
local contextName = "Articulation_Scripts"
--[[ 
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")

package.path = package.path .. ";" .. scriptPath .. "Functions/Helpers/?.lua"
 ]]
-- Load the keyboard tables
local keyboard_functions = require("keyboard_tables")
local keyboard_tables = keyboard_functions.getKeyboardTables()
local keyboardTableKeys = keyboard_tables.keys
local keyboardTableKeysOrder = keyboard_tables.order

local allRows = keyboard_tables.table

-- Load the pass through function of keycommands
local passThroughCommand = require("pass_through_command").passThroughCommand
local buttons = require("special_buttons")
require("imgui_colors")

function getExtState(name, default)
    local state = reaper.HasExtState(contextName,name) and reaper.GetExtState(contextName,name) or default
    if state == "true" then return true end
    if state == "false" then return flase end
    return state
end

local buttonSizes = {60, 80, 100}
local margin = 10
--local buttonWidth = getExtState("keyboard_trigger_buttonWidth", 100)-- , textHeight = reaper.ImGui_CalcTextSize(ctx,"SELECTE PROJECT FOLDER: 12345",0,0)
--local windowColorBgTransparency = getExtState("keyboard_trigger_windowColorBgTransparency", 0.5)

local startPosX = 10    --
local startPosY = 10    --
local firstFrame = true 
local waitForFocused = 0
local hoverDifference = 0x30
--local ctx

function pulsatingColor(colorIn, speed)
    local time = reaper.time_precise() * (speed and speed or 6)
    local pulsate = (math.sin(time * 2) + 1) / 2 -- range: 0 to 1
    local alpha = math.floor(0x55 + (0xFF - 0x55) * pulsate)
    return colorIn & (0xFFFFFF00 + alpha)        -- combine alpha and RGB
end

function setupLocalSurface()    
    firstFrame = true
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

function selectedButton(on)
    if on then
        return 0x666666FF
    else
        return 0x222222FF
    end
end

function selectedButtonBlue(on)
    if on then
        return 0x222288FF
    else
        return 0x222222FF
    end
end

function colorToggleWhiteBlack(on)
    if on then
        return 0x111111FF
    else
        return 0xFFFFFFFF
    end
end


local edit_keyboard_layout
local edit_key_index
local edit_key_row
local resetNeeded = false

local export = {}
function export.keyboardTriggerSurface()
    EnsureValidContext(ctx)
    local buttonWidth = settings.keyboardTrigger_size
    local buttonHeight = buttonWidth 
    local buttonSpacer = math.ceil(buttonWidth/10)
    local fontSize = math.ceil(buttonWidth/100 * 16)
    local keep_open = settings.keyboard_trigger_keep_open --getExtState("keyboard_trigger_keep_open", "false")
    local keep_focused = settings.keyboard_trigger_keep_focused--getExtState("keyboard_trigger_keep_focused", "true")
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    local windowColorBg = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0, (100 - settings.keyboardTrigger_transparency)/100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), windowColorBg)
    
    if reaper.ImGui_Begin(ctx, contextName .. "_Keyboard_Trigger", nil,
                reaper.ImGui_WindowFlags_NoDecoration() |
                reaper.ImGui_WindowFlags_NoDocking() |
                reaper.ImGui_WindowFlags_TopMost()                 -- | reaper.ImGui_WindowFlags_NoMove()
            -- | reaper.ImGui_WindowFlags_NoBackground()
            -- | reaper.ImGui_FocusedFlags_None()
            )
    then    
        reaper.ImGui_SetWindowSize(ctx, 0, 0)
        if firstFrame then
            windowHeight = buttonHeight * (#(allRows) + 0.5) + margin * 1
            --reaper.ImGui_SetWindowSize(ctx, buttonWidth * 13 + margin * 1,windowHeight )

            --reaper.ImGui_SetWindowPos(ctx, windowStartPosX, windowHeight)

            firstFrame = false
            focusedPopupWindow = reaper.JS_Window_GetFocus()
        end


        if waitForFocused > 10 then
            focusedPopupWindow = reaper.JS_Window_GetFocus()
            waitForFocused = -1
        end
        if waitForFocused > -1 then waitForFocused = waitForFocused + 1 end




        reaper.ImGui_SetNextFrameWantCaptureKeyboard(ctx, 1)
        retval, unicode_char = reaper.ImGui_GetInputQueueCharacter(ctx, 0)
        keyInput = string.char(unicode_char & 0xFF):upper()
        --keyInput = (utf8.char(unicode_char)):upper()--string.char(unicode_char & 0xFF):upper()
        
        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        
        backspace = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace())
        delete = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete())
        enter = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
        
        
        if retval then 
            if unicode_char == 229 then
                keyInput = "Å"
            elseif unicode_char == 230 then
                keyInput = "Æ"
            elseif unicode_char == 248 then
                keyInput = "Ø"
            end
        end
        
        --[[
      if retval and key then
          if triggerTableKeys[key].title and tonumber(key) then
            colorGradient = key
          elseif triggerTableKeys[key].title then
            buttonTitle = triggerTableKeys[key].title .. " " .. colorGradient
            color = colorTable[buttonTitle]
            doColor(color)
            finish = true
          elseif key == "K" then
            keep_open = not keep_open
          else
            finish = true
          end
      end
      ]] --
      
      
        posX = startPosX
        posY = startPosY

        if buttons.cogwheel(ctx, "keyboardTriggerSettings",  math.ceil(buttonWidth/100 * 30), colorGrey, "Settings", colorGrey, colorWhite, colorTransparent, colorDarkGrey, colorDarkGrey, colorBlack) then
            reaper.ImGui_OpenPopup(ctx, "keyboardTriggerSettings")
        end
        
        if reaper.ImGui_BeginPopup(ctx, "keyboardTriggerSettings") then
            if reaper.ImGui_Button(ctx, "Edit keyboard layout") then
                edit_keyboard_layout = not edit_keyboard_layout 
                if not edit_keyboard_layout then
                    --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                    resetNeeded = true
                end
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            
            reaper.ImGui_SameLine(ctx) 
            if reaper.ImGui_Button(ctx, "Default US") then
                keyboard_functions.resetKeyboard("US")
                --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                reaper.ImGui_CloseCurrentPopup(ctx)
                resetNeeded = true
            end
            reaper.ImGui_SameLine(ctx) 
            if reaper.ImGui_Button(ctx, "Default DA") then
                keyboard_functions.resetKeyboard("DA")
                --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                reaper.ImGui_CloseCurrentPopup(ctx)
                resetNeeded = true
            end
            
            
            ret, settings.keyboardTrigger_size = reaper.ImGui_SliderInt(ctx, "Size", settings.keyboardTrigger_size, 10, 200)
            if ret then  
                saveSettings()
            end
            
            ret, settings.keyboardTrigger_transparency = reaper.ImGui_SliderInt(ctx, "Window transparency", settings.keyboardTrigger_transparency, 0, 100)
            if ret then
                saveSettings()
            end
            
            
            reaper.ImGui_EndPopup(ctx)
        end
        if edit_keyboard_layout and (not edit_key_row or not edit_key_index) then 
            edit_key_row = 1
            edit_key_index = 1
        end
        
        reaper.ImGui_SameLine(ctx)
        

        mainText = (resetNeeded or edit_keyboard_layout) and "Edit keyboard layout" or "Keyboard Trigger Articulation Control"
        mainText = mainText -- .. " - click a letter to color"
        -- reaper.ImGui_DrawList_AddTextEx(draw_list,font,font_size,posX, posY, 0xFFFFFFFF, mainText, 0.0)

        

        reaper.ImGui_PushFont(ctx, font,  math.ceil(buttonWidth/100 * 20))
        --reaper.ImGui_SetCursorPos(ctx, posX, posY)
        reaper.ImGui_Text(ctx, mainText)
        reaper.ImGui_PopFont(ctx)
        
        
        posY = posY + buttonHeight / 2
        if resetNeeded or edit_keyboard_layout then 
            reaper.ImGui_AlignTextToFramePadding(ctx)   
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetCursorPosY(ctx, 12)
            reaper.ImGui_Text(ctx, " |   Press key on your keyboard to remap the selected key   |   Use arrows to navigate   |   Delete or backspace to remove   |   Press escape to finish")            
        else
            --[[
          
    
          local currentDeviceShow = reaper.GetExtState("articulationMapOnDevice","useOnlyOnDevice")
          if not currentDeviceShow or currentDeviceShow == "0" then
            newValue = "1"
          else
            newValue = "0"
          end
    
          if reaper.ImGui_Button(ctx,newValue == "1" and "show" or "hide") then
            reaper.SetExtState("articulationMapOnDevice","useOnlyOnDevice",newValue,true)
          end
          ]]
    
            
            
            reaper.ImGui_SameLine(ctx)
            
            
            reaper.ImGui_AlignTextToFramePadding(ctx)
            reaper.ImGui_PushFont(ctx, font,  math.ceil(buttonWidth/100 * 18))
            local color = selectedButton(keep_open)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color - hoverDifference)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), keep_open and 0xFFFFFFFF or 0x999999FF)
            if reaper.ImGui_Button(ctx,"Keep open: " .. (keep_open and "On" or "Off")) then        
                settings.keyboard_trigger_keep_open = not settings.keyboard_trigger_keep_open
                saveSettings()
            end
            reaper.ImGui_PopStyleColor(ctx, 4)
            
            
            reaper.ImGui_SameLine(ctx)
            local color = selectedButton(keep_focused)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color - hoverDifference)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), keep_focused and 0xFFFFFFFF or 0x999999FF)
            if reaper.ImGui_Button(ctx,"Keep focused: " .. (keep_focused and "On" or "Off")) then        
                settings.keyboard_trigger_keep_focused = not settings.keyboard_trigger_keep_focused
                saveSettings()                
            end
            reaper.ImGui_PopStyleColor(ctx, 4)
            
            reaper.ImGui_PopFont(ctx)
              
    
            --if retval and keyInput then lastKeyInput = keyInput end
            reaper.ImGui_PushFont(ctx, font, fontSize)
            if lastChar and lastCommand then
                reaper.ImGui_Text(ctx, "Passthrough: " .. lastChar .. " (" .. lastCommand .. ")")
            end
            reaper.ImGui_PopFont(ctx)
        end
        
        
        
        -- Evaluate the JSFX slider value
        if track and fxNumber then
            --selectedArticulationIdx, minval, maxval = reaper.TrackFX_GetParam(track, fxNumber, 0) -- 0 is the parameter index, 0 is the parameter value

            
            local nextRow = false
            local counter = 1
            finish = false 
            for r, row in ipairs(allRows) do
                for k, key in ipairs(row) do
                    reaper.ImGui_SetCursorPos(ctx, posX, posY)
                    -- currentFont = reaper.ImGui_GetFont(ctx)
                    -- currentFont.FontSize = font_size
                    
                    buttonTitle = " "
                    color = 0x00000040
                    textColor = 0x444444FF
                    if resetNeeded or edit_keyboard_layout then
                        buttonTitle = key
                        textColor = colorWhite
                        fontSize = math.ceil(buttonWidth/100 * 24)
                        if edit_key_row == r and edit_key_index == k then 
                            color = pulsatingColor(colorGrey, speed)
                        end
                    else
                        if triggerTableKeys[key] then
                            if #triggerTableKeys[key].subtitle > 0 then
                                buttonTitle = triggerTableKeys[key].subtitle ..
                                ":\n" ..
                                triggerTableKeys[key].title:gsub("+ ", "+"):gsub(" ", "\n")                                                    -- .. " " .. colorGradient
                            else
                                buttonTitle = triggerTableKeys[key].title:gsub("+ ", "+"):gsub(" ", "\n")                                      -- .. " " .. colorGradient
                            end
                            colorTitle = buttonTitle
                            isSelected = triggerTableKeys[key].programChange == selectedArticulationIdx
                            color = selectedButtonBlue(isSelected) -- 0x222222FF or 0
                            textColor = 0xFFFFFFFF
                        --[[elseif key == "<" then
                            color = selectedButton(keep_open)
                            buttonTitle = "Keep\nOpen"
                            textColor = 0x444444FF]]
                        else
                            buttonTitle = " "
                            color = 0x00000040
                            textColor = 0x444444FF
                        end
                    
                    end
                    
                    reaper.ImGui_PushFont(ctx, font, fontSize)

                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color - hoverDifference)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)

                    buttonSizeW = buttonWidth - buttonSpacer
                    buttonSizeH = buttonHeight - buttonSpacer

                    -- if triggerTableKeys[key].title  or key == "K" or key == "<"   or key == "J" or key == "I"  or key == "0" or key == "+" or key == "-" then
                    
                    if (not resetNeeded and not edit_keyboard_layout and not shift and (retval and keyInput and key == keyInput)) or
                        --if (key == keyInput) or
                        (reaper.ImGui_Button(ctx, buttonTitle .. "##" .. r .. ":" .. k, buttonSizeW, buttonSizeH)) then
                        if edit_keyboard_layout then
                            edit_key_row = r
                            edit_key_index = k
                        else
                            if triggerTableKeys[key] then
                                changeArticulation(triggerTableKeys[key].programChange, triggerTableKeys[key].articulation)
                                finish = true
                                lastClickedColor = buttonTitle
                                reaper.SetExtState(contextName, "lastClickedArticulation", buttonTitle, true)
                            elseif key == "<" then
                                --reaper.ShowConsoleMsg(tostring(keep_open))
                                --keep_open = not keep_open
                                --reaper.SetExtState(contextName, "keep_open", tostring(keep_open), true)
                                --elseif key == "," then
                                --passThroughCommand(9900)
                                --elseif key == "." then
                                --passThroughCommand(9901)
                            else
                            
                            end
                        end
                    end
                    
                    reaper.ImGui_PopFont(ctx)
                    reaper.ImGui_PopStyleColor(ctx, 3)
                    
                    if edit_keyboard_layout and reaper.ImGui_IsItemHovered(ctx) then 
                        reaper.ImGui_SetTooltip(ctx, "Click to edit key")
                    end
  
                    
                    
                        -- end
                    if resetNeeded or edit_keyboard_layout then
                        
                    else
                        if (triggerTableKeys[key]) then --or key == "<" then --or key == "K" then
                            textColor = 0x444444FF
                        else
                            -- reaper.ImGui_SetCursorPos(ctx,posX+ buttonWidth/2 - textWidth/2 -4,posY + buttonHeight / 2 - textHeight/2)
                            textColor = 0x444444FF
                        end
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)
                        
                        reaper.ImGui_SetCursorPos(ctx, posX + 2, posY + 2) -- + buttonWidth - buttonSpacer- textWidth -4,posY + buttonHeight / 2 - textHeight/2)
                        reaper.ImGui_PushFont(ctx, font, fontSize)
                        -- reaper.ImGui_DrawList_AddTextEx(draw_list,font,25,posX, posY, textColor, buttonTitle)
                        keyTitle = key
                        textWidth, textHeight = reaper.ImGui_CalcTextSize(ctx, keyTitle, 0, 0)
    
                        reaper.ImGui_Text(ctx, keyTitle)
    
    
                        reaper.ImGui_PopFont(ctx)
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                    
                    reaper.ImGui_Spacing(ctx)
                    posX = posX + buttonWidth
                end
                counter = counter + 1
                if counter == 1 then
                    posX = startPosX
                elseif counter == 2 then
                    posX = startPosX + buttonWidth / 2
                elseif counter == 3 then
                    posX = startPosX + buttonWidth / 4 * 3
                elseif counter == 4 then
                    posX = startPosX + buttonWidth / 4
                end
                posY = posY + buttonHeight
            end
            key = keyInput
            
            
            if not triggerTableKeys[key] then
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then
                    unicode_char = 1
                    key = "Left"
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then
                    unicode_char = 1
                    key = "Up"
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then
                    unicode_char = 1
                    key = "Right"
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
                    unicode_char = 1
                    key = "Down"
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
                    unicode_char = 1
                    key = "Return"
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Period()) then
                    unicode_char = 1
                    if not shift then
                        key = "."
                    else
                        key = ":"
                    end
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Comma()) then
                    unicode_char = 1
                    if not shift then
                        key = ","
                    else
                        key = ";"
                    end
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z()) then
                    unicode_char = 1
                    key = "Z"
                end
                
                if key == " " then key = "Space" end
                  
                if not resetNeeded and not edit_keyboard_layout then 
                    if unicode_char > 0 then
                        lastCommand = passThroughCommand(key, cmd, alt, shift, ctrl)
                        --passThroughCommand(unicode_char)
                        finish = false
                    end
                end
            end
            
            if edit_key_row and edit_key_index then
                if key == "Space" or key == "Right" then 
                    nextRow = true
                elseif key == "Down" then 
                    edit_key_row = edit_key_row + 1 
                    if edit_key_row > #allRows then
                        edit_key_row = 1
                    end
                elseif key == "Up" then 
                    edit_key_row = edit_key_row - 1 
                    if edit_key_row < 1 then
                        edit_key_row = #allRows 
                    end     
                elseif key == "Left" then 
                    edit_key_index = edit_key_index - 1
                    if edit_key_index < 1 then
                        edit_key_row = edit_key_row - 1 
                        if edit_key_row < 1 then
                            edit_key_row = #allRows 
                        end
                        
                        edit_key_index = #allRows[edit_key_row]  
                    end
                elseif retval and (last_key ~= key) and key then 
                    allRows[edit_key_row][edit_key_index] = key
                    reaper.SetExtState(contextName, "keyboardTable:" .. edit_key_row .. ":" .. edit_key_index, key, true)
                    last_key = key
                    nextRow = true
                elseif backspace or delete then 
                    allRows[edit_key_row][edit_key_index] = "" 
                    reaper.SetExtState(contextName, "keyboardTable:" .. edit_key_row .. ":" .. edit_key_index, key, true)
                    nextRow = true
                end 
                
            end 
            
            
            if nextRow then
                edit_key_index = edit_key_index + 1
                if edit_key_index > #allRows[edit_key_row] then
                    edit_key_index = 1
                    edit_key_row = edit_key_row + 1
                    
                    if edit_key_row > #allRows then
                        edit_key_row = 1
                    end
                end
            end
        end
        
        reaper.ImGui_PopStyleColor(ctx)
        --[[
      -- fix for arrows
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then
          passThroughCommand(9996)
      end
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then
          passThroughCommand(9997)
      end
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then
          passThroughCommand(9998)
      end
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
          passThroughCommand(9999)
      end
      ]]
        if resetNeeded then  
            reaper.ImGui_OpenPopup(ctx, "Reset Needed")
            edit_key_row = nil 
        end
        
        local closeWindow = false
        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        reaper.ImGui_SetNextWindowSize(ctx, 300, 100, reaper.ImGui_Cond_Appearing())
        
        if reaper.ImGui_BeginPopupModal(ctx, "Reset Needed", true) then
             reaper.ImGui_Text(ctx, "Press enter or click ok to close the keyboard trigger")
             reaper.ImGui_Text(ctx, "Open again yourself afterwards!")
             if reaper.ImGui_Button(ctx, 'OK', 100, 0) or enter then   
                 reaper.ImGui_CloseCurrentPopup(ctx)  
                 closeWindow = true
             end
             reaper.ImGui_SetItemDefaultFocus(ctx)
            
            reaper.ImGui_EndPopup(ctx)
        end

        if not reaper.ImGui_IsWindowFocused(ctx) and keep_focused then
            reaper.JS_Window_SetFocus(focusedPopupWindow)
        end

        reaper.ImGui_End(ctx)
        
        if edit_keyboard_layout then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then 
                edit_keyboard_layout = false
                edit_key_row = nil 
                --reaper.SetExtState(contextName, "ReloadArticulation", "1", true) 
                resetNeeded = true
            end
        else 
            if closeWindow or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) or (finish and not keep_open and key ~= "<") then 
                reaper.SetToggleCommandState(0, keyboardTrigger_command_id, 0)
                if resetNeeded then
                    reaper.SetExtState("articulationMap", "stopScript", "1", true)
                    --reaper.SetToggleCommandState(0, background_server_command_id, 0)
                    resetNeeded = false
                end
                reaper.RefreshToolbar(0)
                --stopScript = true
            end
        end

        --if key == "<" then
        --    keep_open = not keep_open
        --    reaper.SetExtState(contextName, "keep_open", tostring(keep_open), true)
        --end
    end
end

return export
