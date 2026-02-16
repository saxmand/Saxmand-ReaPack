-- @noindex

local retval, filename, sectionID, cmdID, mode, resolution, val = reaper.get_action_context()

-- If cmdID is non-zero → script was triggered as an action (user)
-- If cmdID is 0 → usually run via another script (Main_OnCommandEx / NamedCommandLookup)

if cmdID == 70642 then 
    --reaper.ShowConsoleMsg(tostring(reaper.GetToggleCommandState(reaper.NamedCommandLookup("_RSeedd38f0dcb0bb0f0e04e3a6ce2c2d0769246386"), 0)).." hej\n")
    
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
    
local ImGui = require 'imgui' '0.10'
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

function toggleButtonColor(on)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), on and theme.button_active or theme.button)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), on and theme.button)
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

function buttenSelectedColor(on)
    if on then
        return theme.button
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
local cache = {}

local export = {}
function export.keyboardTriggerSurface(focusIsOn, focusHwnd)
    EnsureValidContext(ctx)
    modern_ui.apply(ctx)
    local buttonWidth = settings.keyboardTrigger_size
    local buttonHeight = buttonWidth 
    local buttonSpacer = math.ceil(buttonWidth/10)
    local fontSize = math.ceil(buttonWidth/100 * 16)
    local keep_open = settings.keyboard_trigger_keep_open --getExtState("keyboard_trigger_keep_open", "false")
    local keep_focused = settings.keyboard_trigger_keep_focused--getExtState("keyboard_trigger_keep_focused", "true")
    draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), (100 - settings.keyboardTrigger_transparency)/100)
    
    --local windowColorBg = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0, (100 - settings.keyboardTrigger_transparency)/100)
    
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), windowColorBg)
    
    reaper.ImGui_PushFont(ctx, fontFat,  13)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)

    local visible, open =  reaper.ImGui_Begin(ctx, "Keyboard Trigger Articulation Control", true,
                --reaper.ImGui_WindowFlags_NoDecoration() |
                reaper.ImGui_WindowFlags_NoDocking() |
                reaper.ImGui_WindowFlags_TopMost()                 -- | reaper.ImGui_WindowFlags_NoMove()
            -- | reaper.ImGui_WindowFlags_NoBackground()
            -- | reaper.ImGui_FocusedFlags_None()
            | reaper.ImGui_WindowFlags_MenuBar()
            )
    reaper.ImGui_PopFont(ctx)    
    reaper.ImGui_PopStyleVar(ctx)

    if visible then    
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
        keyInput = string.char(unicode_char & 0xFF)
        --keyInput = (utf8.char(unicode_char)):upper()--string.char(unicode_char & 0xFF):upper()
        
        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        
        backspace = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace())
        delete = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete())
        enter = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
        
        function getAllImguiKeys()
            local enum = "Key"
            local enum_cache = cache[enum]
            if not enum_cache then
                enum_cache = {}
                cache[enum] = enum_cache

                for func_name, value in pairs(ImGui) do
                local enum_name = func_name:match(('^%s_(.+)$'):format(enum))
                if enum_name then
                    enum_cache[#enum_cache + 1] = {value, enum_name}
                end
                end
                table.sort(enum_cache, function(a, b) return a[1] < b[1] end)
            end

            local i = 0
            return function()
                i = i + 1
                if not enum_cache[i] then return end
                return table.unpack(enum_cache[i])
            end
        end
        local imgui_key_pressed
        for key, name in getAllImguiKeys() do
            if reaper.ImGui_IsKeyPressed(ctx, key) then
                if name:match("Shift") == nil and name:match("Alt") == nil and name:match("Super") == nil and name:match("Ctrl") == nil then 
                    imgui_key_pressed = name
                end
            end
        end
        
        if retval then 
            if unicode_char == 32 then keyInput = " "
            elseif unicode_char == 33 then keyInput = "!"
            elseif unicode_char == 34 then keyInput = "\""
            elseif unicode_char == 35 then keyInput = "#"
            elseif unicode_char == 36 then keyInput = "$"
            elseif unicode_char == 37 then keyInput = "%"
            elseif unicode_char == 38 then keyInput = "&"
            elseif unicode_char == 39 then keyInput = "'"
            elseif unicode_char == 40 then keyInput = "("
            elseif unicode_char == 41 then keyInput = ")"
            elseif unicode_char == 42 then keyInput = "*"
            elseif unicode_char == 43 then keyInput = "+"
            elseif unicode_char == 44 then keyInput = ","
            elseif unicode_char == 45 then keyInput = "-"
            elseif unicode_char == 46 then keyInput = "."
            elseif unicode_char == 47 then keyInput = "/"

            elseif unicode_char >= 48 and unicode_char <= 57 then
                keyInput = string.char(unicode_char) -- 0–9

            elseif unicode_char == 58 then keyInput = ":"
            elseif unicode_char == 59 then keyInput = ";"
            elseif unicode_char == 60 then keyInput = "<"
            elseif unicode_char == 61 then keyInput = "="
            elseif unicode_char == 62 then keyInput = ">"
            elseif unicode_char == 63 then keyInput = "?"
            elseif unicode_char == 64 then keyInput = "@"

            elseif unicode_char >= 65 and unicode_char <= 90 then
                keyInput = string.char(unicode_char) -- A–Z

            elseif unicode_char == 91 then keyInput = "["
            elseif unicode_char == 92 then keyInput = "\\"
            elseif unicode_char == 93 then keyInput = "]"
            elseif unicode_char == 94 then keyInput = "^"
            elseif unicode_char == 95 then keyInput = "_"
            elseif unicode_char == 96 then keyInput = "`"

            elseif unicode_char >= 97 and unicode_char <= 122 then
                keyInput = string.char(unicode_char) -- a–z
            
            elseif unicode_char == 167 then keyInput = "§"
            elseif unicode_char == 192 then keyInput = "À"
            elseif unicode_char == 193 then keyInput = "Á"
            elseif unicode_char == 194 then keyInput = "Â"
            elseif unicode_char == 195 then keyInput = "Ã"
            elseif unicode_char == 196 then keyInput = "Ä"
            elseif unicode_char == 197 then keyInput = "Å"
            elseif unicode_char == 198 then keyInput = "Æ"
            elseif unicode_char == 199 then keyInput = "Ç"
            elseif unicode_char == 200 then keyInput = "È"
            elseif unicode_char == 201 then keyInput = "É"
            elseif unicode_char == 202 then keyInput = "Ê"
            elseif unicode_char == 203 then keyInput = "Ë"
            elseif unicode_char == 204 then keyInput = "Ì"
            elseif unicode_char == 205 then keyInput = "Í"
            elseif unicode_char == 206 then keyInput = "Î"
            elseif unicode_char == 207 then keyInput = "Ï"
            
            elseif unicode_char == 208 then keyInput = "Ð"
            elseif unicode_char == 209 then keyInput = "Ñ"
            elseif unicode_char == 210 then keyInput = "Ò"
            elseif unicode_char == 211 then keyInput = "Ó"
            elseif unicode_char == 212 then keyInput = "Ô"
            elseif unicode_char == 213 then keyInput = "Õ"
            elseif unicode_char == 214 then keyInput = "Ö"
            elseif unicode_char == 216 then keyInput = "Ø"
            elseif unicode_char == 217 then keyInput = "Ù"
            elseif unicode_char == 218 then keyInput = "Ú"
            elseif unicode_char == 219 then keyInput = "Û"
            elseif unicode_char == 220 then keyInput = "Ü"
            elseif unicode_char == 221 then keyInput = "Ý"
            elseif unicode_char == 222 then keyInput = "Þ"
            elseif unicode_char == 223 then keyInput = "ß"
            
            elseif unicode_char == 224 then keyInput = "à"
            elseif unicode_char == 225 then keyInput = "á"
            elseif unicode_char == 226 then keyInput = "â"
            elseif unicode_char == 227 then keyInput = "ã"
            elseif unicode_char == 228 then keyInput = "ä"
            elseif unicode_char == 229 then keyInput = "å"
            elseif unicode_char == 230 then keyInput = "æ"
            elseif unicode_char == 231 then keyInput = "ç"
            elseif unicode_char == 232 then keyInput = "è"
            elseif unicode_char == 233 then keyInput = "é"
            elseif unicode_char == 234 then keyInput = "ê"
            elseif unicode_char == 235 then keyInput = "ë"
            elseif unicode_char == 236 then keyInput = "ì"
            elseif unicode_char == 237 then keyInput = "í"
            elseif unicode_char == 238 then keyInput = "î"
            elseif unicode_char == 239 then keyInput = "ï"
            
            elseif unicode_char == 240 then keyInput = "ð"
            elseif unicode_char == 241 then keyInput = "ñ"
            elseif unicode_char == 242 then keyInput = "ò"
            elseif unicode_char == 243 then keyInput = "ó"
            elseif unicode_char == 244 then keyInput = "ô"
            elseif unicode_char == 245 then keyInput = "õ"
            elseif unicode_char == 246 then keyInput = "ö"
            elseif unicode_char == 248 then keyInput = "ø"
            elseif unicode_char == 249 then keyInput = "ù"
            elseif unicode_char == 250 then keyInput = "ú"
            elseif unicode_char == 251 then keyInput = "û"
            elseif unicode_char == 252 then keyInput = "ü"
            elseif unicode_char == 253 then keyInput = "ý"
            elseif unicode_char == 254 then keyInput = "þ"
            elseif unicode_char == 255 then keyInput = "ÿ"
            end
            
            if not imgui_key_pressed then 
                imgui_key_pressed = keyInput
            end
        end
        keyInput = keyInput:upper()
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
      
      


        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 1)
        reaper.ImGui_PushFont(ctx, font,  13)
        if reaper.ImGui_BeginMenuBar(ctx) then 
            --reaper.ImGui_PushFont(ctx, font,  12)
            
            --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 4)
            
            notation_events.options()
            
            
            --local posX1 = reaper.ImGui_GetCursorPosX(ctx)
            if reaper.ImGui_BeginMenu(ctx, "Settings") then

                if reaper.ImGui_Checkbox(ctx, "Show group name", settings.keyboardTrigger_showGroupText) then
                    settings.keyboardTrigger_showGroupText = not settings.keyboardTrigger_showGroupText
                    saveSettings()
                end


                if reaper.ImGui_Checkbox(ctx, "Passthrough keys that don't have articulations", settings.keyboardTrigger_passthroughKeys) then
                    settings.keyboardTrigger_passthroughKeys = not settings.keyboardTrigger_passthroughKeys
                    saveSettings()
                end
                
                reaper.ImGui_Indent(ctx)
                    if reaper.ImGui_Checkbox(ctx, "Only non articulations keys", settings.keyboardTrigger_passthroughKeys_only_non) then
                        settings.keyboardTrigger_passthroughKeys_only_non = not settings.keyboardTrigger_passthroughKeys_only_non
                        saveSettings()
                    end
                    setToolTipFunc("This will omit any keys that can be used as articulation triggers.\nYou can which keys to use in the settings.")
                reaper.ImGui_Unindent(ctx)

                reaper.ImGui_Separator(ctx)
                
                if reaper.ImGui_Button(ctx, "Edit keyboard layout") then
                    edit_keyboard_layout = not edit_keyboard_layout 
                    if not edit_keyboard_layout then
                        --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                        resetNeeded = true
                    end
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                
                reaper.ImGui_SameLine(ctx) 
                reaper.ImGui_Text(ctx, "Reset to default:")
                reaper.ImGui_SameLine(ctx) 
                if reaper.ImGui_Button(ctx, "US") then
                    keyboard_functions.resetKeyboard("US")
                    --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                    reaper.ImGui_CloseCurrentPopup(ctx)
                    resetNeeded = true
                end
                reaper.ImGui_SameLine(ctx) 
                if reaper.ImGui_Button(ctx, "DA") then
                    keyboard_functions.resetKeyboard("DA")
                    --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                    reaper.ImGui_CloseCurrentPopup(ctx)
                    resetNeeded = true
                end
                reaper.ImGui_SameLine(ctx) 
                if reaper.ImGui_Button(ctx, "AZERTY") then
                    keyboard_functions.resetKeyboard("AZERTY")
                    --reaper.SetExtState(contextName, "ReloadArticulation", "1", true)
                    reaper.ImGui_CloseCurrentPopup(ctx)
                    resetNeeded = true
                end
                
                
                ret, settings.keyboardTrigger_size = reaper.ImGui_SliderInt(ctx, "Size", settings.keyboardTrigger_size, 10, 200)
                if ret then  
                    saveSettings()
                end
                
                ret, settings.keyboardTrigger_transparency = reaper.ImGui_SliderInt(ctx, "Window transparency", settings.keyboardTrigger_transparency, 0, 80)
                if ret then
                    saveSettings()
                end
                
                
                ret, settings.keyboardTrigger_textSize = reaper.ImGui_SliderInt(ctx, "Text Size", settings.keyboardTrigger_textSize, 4, 40)
                if ret then
                    saveSettings()
                end
                

                notation_events.others()

                reaper.ImGui_EndMenu(ctx)
            end

            ---------- OTHER BUTTONS ON MENU LINE
            ---
            reaper.ImGui_AlignTextToFramePadding(ctx)   
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 0)

            reaper.ImGui_Text(ctx, (focusIsOn and " [" .. focusIsOn .. "]" or ""))

            local trackColor = modern_ui.getTrackColor(track) or 0x222222FF 
            local textColor = GetTextColorForBackground(trackColor)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), trackColor )
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), trackColor)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), trackColor)
            --reaper.ImGui_Text(ctx, tostring(trackName))
            if reaper.ImGui_Button(ctx,trackName) then 
                local val = reaper.TrackFX_GetFloatingWindow(track, fxNumber)
                reaper.TrackFX_Show(track, fxNumber, not val and 3 or 2)
            end
            reaper.ImGui_PopStyleColor(ctx,4)


            if resetNeeded or edit_keyboard_layout then 
                reaper.ImGui_Text(ctx, "Edit keyboard layout   |   Press key on your keyboard to remap the selected key   |   Use arrows to navigate   |   Delete or backspace to remove   |   Press escape to finish")            
            else      
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), keep_open and theme.accent or theme.button)
                if reaper.ImGui_Button(ctx,"Keep open: " .. (keep_open and "On" or "Off")) then        
                    settings.keyboard_trigger_keep_open = not settings.keyboard_trigger_keep_open
                    saveSettings()
                end
                reaper.ImGui_PopStyleColor(ctx, 1)
                
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), keep_focused and theme.accent or theme.button)
                if reaper.ImGui_Button(ctx,"Keep focused: " .. (keep_focused and "On" or "Off")) then        
                    settings.keyboard_trigger_keep_focused = not settings.keyboard_trigger_keep_focused
                    saveSettings()                
                end
                reaper.ImGui_PopStyleColor(ctx, 1)

                if reaper.ImGui_IsWindowFocused(ctx) then 
                     --reaper.ImGui_Text(ctx, (focusIsOn and " [" .. focusIsOn .. "]" or ""))
                end
                
                if lastChar and lastCommand then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Text(ctx, "Passthrough: " .. lastChar .. " (" .. lastCommand .. ")")
                end
            end
            reaper.ImGui_PopStyleVar(ctx)

            
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

        posX = startPosX
        posY = startPosY
        --if buttons.cogwheel(ctx, "keyboardTriggerSettings",  math.ceil(buttonWidth/100 * 30), colorGrey, "Settings", colorGrey, colorWhite, colorTransparent, colorDarkGrey, colorDarkGrey, colorBlack) then
        --    reaper.ImGui_OpenPopup(ctx, "keyboardTriggerSettings")
        --end
        
        --if reaper.ImGui_BeginPopup(ctx, "keyboardTriggerSettings") then
            
            
           -- reaper.ImGui_EndPopup(ctx)
       -- end

        if edit_keyboard_layout and (not edit_key_row or not edit_key_index) then 
            edit_key_row = 1
            edit_key_index = 1
        end
        --reaper.ImGui_SameLine(ctx)
        

        mainText = (resetNeeded or edit_keyboard_layout) and "Edit keyboard layout" or "Keyboard Trigger Articulation Control"
        --mainText = mainText -- .. " - click a letter to color"
        -- reaper.ImGui_DrawList_AddTextEx(draw_list,font,font_size,posX, posY, 0xFFFFFFFF, mainText, 0.0)

        

        --reaper.ImGui_PushFont(ctx, font,  math.ceil(buttonWidth/100 * 20))
        --reaper.ImGui_SetCursorPos(ctx, posX, posY)
        --reaper.ImGui_Text(ctx, mainText)
        --reaper.ImGui_PopFont(ctx)
        
        
        posY = posY + 36--buttonHeight / 2 --+ 8

        
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorDarkGrey)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
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
                    
                    buttonTitle = ""
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
                            if #triggerTableKeys[key].group > 0 and lol then
                                buttonTitle = triggerTableKeys[key].group ..
                                ":\n" ..
                                triggerTableKeys[key].title:gsub("+ ", "+"):gsub(" ", "\n")                                                    -- .. " " .. colorGradient
                            else
                                buttonTitle = triggerTableKeys[key].title--:gsub("+ ", "+"):gsub(" ", "\n")                                      -- .. " " .. colorGradient
                            end
                            colorTitle = buttonTitle
                            isSelected = triggerTableKeys[key].artInLayer == artSelected[triggerTableKeys[key].layer]
                            color = buttenSelectedColor(isSelected) -- 0x222222FF or 0
                            textColor = 0xFFFFFFFF
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
                    function clickingArticulation()
                        if edit_keyboard_layout then
                            edit_key_row = r
                            edit_key_index = k
                        else
                            if triggerTableKeys[key] then
                                changeArticulation(triggerTableKeys[key].programChange, triggerTableKeys[key].articulation, focusIsOn)
                                finish = true
                                lastClickedColor = buttonTitle
                                reaper.SetExtState(contextName, "lastClickedArticulation", buttonTitle, true)                            
                            end
                        end
                    end
                        --if (key == keyInput) or
                    if (reaper.ImGui_Button(ctx,  "##" .. r .. ":" .. k, buttonSizeW, buttonSizeH)) then
                        clickingArticulation()
                    end
                    if (not resetNeeded and not edit_keyboard_layout and (retval and imgui_key_pressed and key == imgui_key_pressed)) then
                        clickingArticulation()
                    end

                    if not edit_keyboard_layout then 
                        notation_events.buttons_tooltip()   
                    end

                    btnX1, btnY1 = reaper.ImGui_GetItemRectMin(ctx)
                    btnW, btnH = reaper.ImGui_GetItemRectSize(ctx)
                    btnX1 = btnX1 + 8
                    btnW = btnW - 16
                    
                    reaper.ImGui_PushFont(ctx, font, settings.keyboardTrigger_textSize)
                    local btnGroupTextW = 0
                    local btnGroupTextH = 0
                    local groupText = triggerTableKeys[key] and triggerTableKeys[key].group or ""
                    if settings.keyboardTrigger_showGroupText then 
                        if groupText ~= "" then 
                            groupText = groupText .. ":"
                            btnGroupTextW, btnGroupTextH = reaper.ImGui_CalcTextSize(ctx, groupText, 0, 0, nil, btnW) 
                        end
                    end
                    local btnTextW, btnTextH = reaper.ImGui_CalcTextSize(ctx, buttonTitle, 0, 0, nil, btnW)
                    reaper.ImGui_PopFont(ctx)
                    
                    if settings.keyboardTrigger_showGroupText then 
                        reaper.ImGui_DrawList_AddTextEx(draw_list, font, settings.keyboardTrigger_textSize, 
                        btnX1 + btnW/2 - btnGroupTextW/2, 
                        btnY1 + btnH/2 - (btnTextH + btnGroupTextH) / 2, 
                        textColor, groupText, btnW) 
                    end
                    
                    reaper.ImGui_DrawList_AddTextEx(draw_list, font, settings.keyboardTrigger_textSize, 
                      btnX1 + btnW/2 - btnTextW/2, 
                      btnY1 + btnH/2 - (btnTextH + btnGroupTextH) / 2  + btnGroupTextH, 
                      textColor, buttonTitle, btnW) 
                    
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
                        
                        reaper.ImGui_SetCursorPos(ctx, posX + 5, posY + 4) -- + buttonWidth - buttonSpacer- textWidth -4,posY + buttonHeight / 2 - textHeight/2)
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
            
            if not triggerTableKeys[key] and settings.keyboardTrigger_passthroughKeys and (not settings.keyboardTrigger_passthroughKeys_only_non or not keyboardTableKeys[key]) then
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
        reaper.ImGui_PopStyleVar(ctx, 2)
        reaper.ImGui_PopStyleColor(ctx)
        --reaper.ImGui_PopStyleColor(ctx)
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

        keyboard_trigger_is_focusing_main = false
        if not reaper.ImGui_IsWindowFocused(ctx) and keep_focused then
            local main_hwnd = reaper.GetMainHwnd()  
            local focused_hwnd = reaper.JS_Window_GetForeground()
            reaper.JS_Window_SetFocus(focusedPopupWindow)
            keyboard_trigger_is_focusing_main = main_hwnd == focused_hwnd
        end

        reaper.ImGui_End(ctx)
        if not open then closeWindow = true end
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
                reaper.JS_Window_SetFocus(focusHwnd)
            end
        end
        
        --if key == "<" then
        --    keep_open = not keep_open
        --    reaper.SetExtState(contextName, "keep_open", tostring(keep_open), true)
        --end
    end
    modern_ui.ending(ctx)
end

return export
