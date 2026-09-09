-- @noindex

local reaper_sections = {
    ["Main"]                   = 0,
    ["MIDI Editor"]            = 32060,
    ["MIDI Event List Editor"] = 32061,
    ["MIDI Inline Editor"]     = 32062,
    ["Media Explorer"]         = 32063,
}

local function textConvert(name)
    local textConverts = {
        ["Escape"]          = "ESC",
        ["Enter"]           = "Return",
        ["DownArrow"]       = "Down",
        ["UpArrow"]         = "Up",
        ["LeftArrow"]       = "Left",
        ["RightArrow"]      = "Right",
        ["Keypad0"]         = "NumPad 0",
        ["Keypad1"]         = "NumPad 1",
        ["Keypad2"]         = "NumPad 2",
        ["Keypad3"]         = "NumPad 3",
        ["Keypad4"]         = "NumPad 4",
        ["Keypad5"]         = "NumPad 5",
        ["Keypad6"]         = "NumPad 6",
        ["Keypad7"]         = "NumPad 7",
        ["Keypad8"]         = "NumPad 8",
        ["Keypad9"]         = "NumPad 9",
        ["KeypadDecimal"]   = "NumPad .",
        ["KeypadEnter"]     = "Return",
        ["KeypadAdd"]       = "NumPad +",
        ["KeypadSubtract"]  = "NumPad -",
        ["KeypadDivide"]    = "NumPad /",
        ["KeypadMultiply"]  = "NumPad *",
        ["NumLock"]         = "Clear",
        [" "]               = "Space",
        ["Comma"]               = ",",
        ["Period"]               = ".",
    }
    return textConverts[name] or name
end

local function GetCommandByShortcut(section_id, shortcut)
    local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
    if version < 6.71 then return end
    local sec = reaper.SectionFromUniqueID(section_id)
    local i = 0
    repeat
        local cmd, stringName = reaper.kbd_enumerateActions(sec, i)
        if cmd ~= 0 then
            for n = 0, reaper.CountActionShortcuts(sec, cmd) - 1 do
                local _, desc = reaper.GetActionShortcutDesc(sec, cmd, n, '')
                if desc == shortcut then return cmd, n, stringName end
            end
        end
        i = i + 1
    until cmd == 0
end

-----------------------------------------------------------------
-- Key enum cache (lazy-initialised)
-----------------------------------------------------------------

local allImguiKeys

local function buildAllImguiKeys()
    if allImguiKeys then return allImguiKeys end
    allImguiKeys = {}
    for func_name, func in pairs(reaper) do
        local key_name = func_name:match('^ImGui_Key_(.+)$')
        if key_name and type(func) == "function" then
            local ok, val = pcall(func)
            if ok and type(val) == "number" then
                allImguiKeys[val] = key_name
            end
        end
    end
    return allImguiKeys
end

-----------------------------------------------------------------
-- Input tracking
-- Solves the problem of SetNextFrameWantCaptureKeyboard needing
-- to know whether any text field has keyboard focus this frame.
-----------------------------------------------------------------

local inputActive = false

local export = {}

-- Call at the very start of each ImGui frame to reset the tracker.
function export.resetInputTracking()
    inputActive = false
end

-- Returns true if any tracked InputText had keyboard focus this frame.
-- Use to drive SetNextFrameWantCaptureKeyboard at the end of the frame.
function export.isInputActive()
    return inputActive
end

-- Drop-in replacement for reaper.ImGui_InputText that automatically
-- records whether this field has keyboard focus. Replace every
-- ImGui_InputText call with this and the tracking is handled for you.
function export.trackedInputText(ctx, label, value, flags)
    local rv, val = reaper.ImGui_InputText(ctx, label, value, flags or 0)
    if reaper.ImGui_IsItemActive(ctx) then inputActive = true end
    return rv, val
end

-- Detect any key pressed this frame and fire the matching REAPER action.
-- Call each frame when no text input is focused. cmd/alt/shift/ctrl are
-- the current modifier states (booleans). section_name defaults to "Main".
function export.handlePassThrough(ctx, cmd, alt, shift, ctrl, section_name)
    local keys = buildAllImguiKeys()
    for key, name in pairs(keys) do
        -- skip modifier keys themselves
        if not name:match("Shift") and not name:match("Ctrl") and
           not name:match("Alt") and not name:match("Super") and
           not name:match("Mod") and not name:match("Menu") then
            if reaper.ImGui_IsKeyPressed(ctx, key, false) then
                export.passThroughCommand(textConvert(name), cmd, alt, shift, ctrl, section_name)
                break
            end
        end
    end
end

-----------------------------------------------------------------
-- Pass-through command
-- Finds and fires the REAPER action bound to a given shortcut.
-- section_name: "Main" (default) or "MIDI Editor"
-----------------------------------------------------------------

function export.passThroughCommand(char, cmd, alt, shift, ctrl, section_name)
    local sid = reaper_sections[section_name or "Main"]
    local modifierText = (cmd and "Cmd+" or "") ..
                         (alt and "Opt+" or "") ..
                         (char:match("%a") and (shift and "Shift+" or "") or "") ..
                         (ctrl and "Control+" or "")
    local fullChar = modifierText .. textConvert(char)
    local action_id, _, stringName = GetCommandByShortcut(sid, fullChar)
    if action_id then
        if sid == reaper_sections["Main"] then
            reaper.Main_OnCommand(action_id, -1)
        elseif sid == reaper_sections["MIDI Editor"] then
            local midi_editor = reaper.MIDIEditor_GetActive()
            reaper.MIDIEditor_OnCommand(midi_editor, action_id)
        end
        return stringName
    end
end

return export
