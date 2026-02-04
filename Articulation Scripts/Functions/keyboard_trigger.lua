-- @version 1.0
-- @noindex

local contextName = "ArticulationControls_KeyboardTrigger"
--[[ 
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")

package.path = package.path .. ";" .. scriptPath .. "Functions/Helpers/?.lua"
 ]]
-- Load the keyboard tables
local keyboard_tables = require("keyboard_tables").getKeyboardTables()
local keyboardTableKeys = keyboard_tables.keys
local keyboardTableKeysOrder = keyboard_tables.order

local allRows = keyboard_tables.table
local allRowsArt = keyboard_tables.table

local keep
local keepStr = reaper.GetExtState(contextName, "keep") or "false"
if keepStr and keepStr == "true" then
    keep = true
else
    keep = false
end

-- Load the pass through function of keycommands
local passThroughCommand = require("pass_through_command").passThroughCommand


local buttonSpacer = 10
local margin = 10
local buttonWidth = 100 -- , textHeight = reaper.ImGui_CalcTextSize(ctx,"SELECTE PROJECT FOLDER: 12345",0,0)
local buttonHeight = buttonWidth
local startPosX = 10    --
local startPosY = 10    --
local firstFrame = true 
local waitForFocused = 0
local hoverDifference = 0x40
--local ctx


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
        return 0x888888FF
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


local export = {}
function export.keyboardTriggerSurface()
    EnsureValidContext(ctx)

    if reaper.ImGui_Begin(ctx, contextName, nil,
                reaper.ImGui_WindowFlags_NoDecoration() |
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



        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

        reaper.ImGui_SetNextFrameWantCaptureKeyboard(ctx, 1)
        retval, unicode_char = reaper.ImGui_GetInputQueueCharacter(ctx, 0)
        keyInput = string.char(unicode_char & 0xFF):upper()
        -- reaper.ShowConsoleMsg(unicode_char)


        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())

        
        
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
            keep = not keep
          else
            finish = true
          end
      end
      ]] --
      
      
        posX = startPosX
        posY = startPosY

        mainText = "Keyboard Trigger Articulation Control"
        mainText = mainText -- .. " - click a letter to color"
        -- reaper.ImGui_DrawList_AddTextEx(draw_list,font,font_size,posX, posY, 0xFFFFFFFF, mainText, 0.0)

        

        reaper.ImGui_PushFont(ctx, font, 20)
        reaper.ImGui_SetCursorPos(ctx, posX, posY)
        reaper.ImGui_Text(ctx, mainText)
        reaper.ImGui_PopFont(ctx)

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

        posY = posY + buttonHeight / 2

        reaper.ImGui_PushFont(ctx, font, 18)
        reaper.ImGui_SameLine(ctx)
        local color = selectedButton(keep)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color - hoverDifference)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), keep and 0x333333FF or 0x999999FF)
        if reaper.ImGui_Button(ctx,"Keep open: " .. (keep and "On" or "Off")) then        
            keep = not keep
            reaper.SetExtState(contextName, "keep", tostring(keep), true)
        end
        reaper.ImGui_PopStyleColor(ctx, 4)
        
        reaper.ImGui_PopFont(ctx)


        --if retval and keyInput then lastKeyInput = keyInput end
        reaper.ImGui_PushFont(ctx, font, 16)
        if lastChar and lastCommand then
            reaper.ImGui_Text(ctx, "Passthrough: " .. lastChar .. " (" .. lastCommand .. ")")
        end
        reaper.ImGui_PopFont(ctx)

        -- Evaluate the JSFX slider value
        if track and fxNumber then
            --selectedArticulationIdx, minval, maxval = reaper.TrackFX_GetParam(track, fxNumber, 0) -- 0 is the parameter index, 0 is the parameter value


            local counter = 1
            finish = false
            for r, row in ipairs(allRows) do
                for k, key in ipairs(row) do
                    reaper.ImGui_SetCursorPos(ctx, posX, posY)
                    -- currentFont = reaper.ImGui_GetFont(ctx)
                    -- currentFont.FontSize = font_size
                    reaper.ImGui_PushFont(ctx, font, 16)
                    
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
                    elseif key == "<" then
                        color = selectedButton(keep)
                        buttonTitle = "Keep\nOpen"
                        textColor = 0x444444FF
                    else
                        buttonTitle = " "
                        color = 0x00000040
                        textColor = 0x444444FF
                    end

                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color - hoverDifference)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)

                    buttonSizeW = buttonWidth - buttonSpacer
                    buttonSizeH = buttonHeight - buttonSpacer

                    -- if triggerTableKeys[key].title  or key == "K" or key == "<"   or key == "J" or key == "I"  or key == "0" or key == "+" or key == "-" then

                    if not shift and (retval and keyInput and key == keyInput) or
                        --if (key == keyInput) or
                        (reaper.ImGui_Button(ctx, buttonTitle .. "##" .. r .. ":" .. k, buttonSizeW, buttonSizeH)) then
                        if triggerTableKeys[key] then
                            changeArticulation(triggerTableKeys[key].programChange, triggerTableKeys[key].articulation)
                            finish = true
                            lastClickedColor = buttonTitle
                            reaper.SetExtState(contextName, "lastClickedArticulation", buttonTitle, true)
                        elseif key == "<" then
                            --reaper.ShowConsoleMsg(tostring(keep))
                            --keep = not keep
                            --reaper.SetExtState(contextName, "keep", tostring(keep), true)
                            --elseif key == "," then
                            --passThroughCommand(9900)
                            --elseif key == "." then
                            --passThroughCommand(9901)
                        else
                        end
                    end



                    -- end

                    if (triggerTableKeys[key]) then --or key == "<" then --or key == "K" then
                        textColor = 0x444444FF
                    else
                        -- reaper.ImGui_SetCursorPos(ctx,posX+ buttonWidth/2 - textWidth/2 -4,posY + buttonHeight / 2 - textHeight/2)
                        textColor = 0x444444FF
                    end
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)
                    reaper.ImGui_SetCursorPos(ctx, posX + 2, posY + 2) -- + buttonWidth - buttonSpacer- textWidth -4,posY + buttonHeight / 2 - textHeight/2)
                    reaper.ImGui_PushFont(ctx, font, 16)
                    -- reaper.ImGui_DrawList_AddTextEx(draw_list,font,25,posX, posY, textColor, buttonTitle)
                    keyTitle = key
                    textWidth, textHeight = reaper.ImGui_CalcTextSize(ctx, keyTitle, 0, 0)

                    reaper.ImGui_Text(ctx, keyTitle)

                    reaper.ImGui_Spacing(ctx)
                    posX = posX + buttonWidth

                    reaper.ImGui_PopFont(ctx)
                    reaper.ImGui_PopFont(ctx)
                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_PopStyleColor(ctx)
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
            if not triggerTableKeys[key] and key ~= "<" then
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

                if unicode_char > 0 then
                    lastCommand = passThroughCommand(key, cmd, alt, shift, ctrl)
                    --passThroughCommand(unicode_char)
                    finish = false
                end
            end
        end

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


        if not reaper.ImGui_IsWindowFocused(ctx) then
            reaper.JS_Window_SetFocus(focusedPopupWindow)
        end

        reaper.ImGui_End(ctx)
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) or
            (finish and not keep and key ~= "<") then
            reaper.SetToggleCommandState(0, keyboardTrigger_command_id, 0)
            reaper.RefreshToolbar(0)
            --stopScript = true
        end

        --if key == "<" then
        --    keep = not keep
        --    reaper.SetExtState(contextName, "keep", tostring(keep), true)
        --end
    end
end

return export