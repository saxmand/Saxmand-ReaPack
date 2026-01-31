local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")

-- Load the reaper sections id number, used for 
local reaper_sections = dofile(scriptPath .. "/reaper_sections.lua")

-----------------------------------------------------------------
--------------------------PASSTHROUGH----------------------------
-----------------------------------------------------------------

local function EachEnum(enum)
    local cache = {}

    local enum_cache = {}
    cache[enum] = enum_cache

    for func_name, func in pairs(reaper) do
        local enum_name = func_name:match(('^ImGui_%s_(.+)$'):format(enum))
        if enum_name then
            --table.insert(enum_cache, { func(), enum_name })
            enum_cache[func()] = enum_name
        end
    end
    return enum_cache
end

local function fetchAllActionNames(section_id)
    local actions = {}
    local idx = 0
    local retval, commandID, commandName

    while true do
        -- Enumerate actions
        commandID, commandName = reaper.kbd_enumerateActions(section_id, idx)

        if commandID == 0 then break end

        -- Add the action to the table
        if commandName then
            table.insert(actions, { commandID = commandID, commandName = commandName })
        end

        idx = idx + 1
    end

    return actions
end

local function createTableOfAllCommands()
    local tableOfAllCommandNames = {}
    for section_name, section_id in pairs(reaper_sections) do
        local result = fetchAllActionNames(section_id)
        tableOfAllCommandNames[section_id] = result
    end
    return tableOfAllCommandNames
end

local function textConvert(name)
    local textConverts = {
        ["Escape"] = "ESC",
        ["Enter"] = "Return",
        ["DownArrow"] = "Down",
        ["UpArrow"] = "Up",
        ["LeftArrow"] = "Left",
        ["RightArrow"] = "Right",
        --["Comma"]= ",",
        --["Period"]= ".",
        ["Keypad0"] = "NumPad 0",
        ["Keypad1"] = "NumPad 1",
        ["Keypad2"] = "NumPad 2",
        ["Keypad3"] = "NumPad 3",
        ["Keypad4"] = "NumPad 4",
        ["Keypad5"] = "NumPad 5",
        ["Keypad6"] = "NumPad 6",
        ["Keypad7"] = "NumPad 7",
        ["Keypad8"] = "NumPad 8",
        ["Keypad9"] = "NumPad 9",
        ["KeypadDecimal"] = "NumPad .",
        ["KeypadEnter"] = "Return",
        ["KeypadAdd"] = "NumPad +",
        ["KeypadSubtract"] = "NumPad -",
        ["KeypadDivide"] = "NumPad /",
        ["KeypadMultiply"] = "NumPad *",
        ["NumLock"] = "Clear",

        [" "] = "Space",
    };

    if textConverts[name] then
        return textConverts[name]
    else
        return name
    end
end


local tableOfAllCommandNames = createTableOfAllCommands()
local tableOfAllKeys = EachEnum('Key')

local function getPressedKey()
    for key, name in pairs(tableOfAllKeys) do
        if reaper.ImGui_IsKeyDown(ctx, key) then
            if name:match("Left") ~= nil or name:match("Right") ~= nil then
                --local duration = reaper.ImGui_GetKeyDownDuration(ctx, key)
                --reaper.ImGui_SameLine(ctx)
                --reaper.ImGui_Text(ctx, ('"%s" %d (%.02f secs)'):format(name, key, duration))
            else
                local fullChar = modifierText .. textConvert(name)
                if not lastChar or lastChar ~= fullChar then lastChar = fullChar end
                return fullChar
            end
        end
    end
    return nil
end

local function GetCommandByShortcut(section_id, shortcut)
    -- Check REAPER version
    local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
    if version < 6.71 then return end
    -- On MacOS, replace Ctrl with Cmd etc.
    --[[local is_macos = reaper.GetOS():match('OS')
    if is_macos then
        shortcut = shortcut:gsub('Ctrl%+', 'Cmd+', 1)
        shortcut = shortcut:gsub('Alt%+', 'Opt+', 1)
    end]]
    -- Go through all actions of the section
    local sec = reaper.SectionFromUniqueID(section_id)
    local i = 0
    repeat
        local cmd, stringName = reaper.kbd_enumerateActions(sec, i)
        if cmd ~= 0 then
            -- Go through all shortcuts of each action
            for n = 0, reaper.CountActionShortcuts(sec, cmd) - 1 do
                -- Find the action that matches the given shortcut
                local _, desc = reaper.GetActionShortcutDesc(sec, cmd, n, '')
                if desc == shortcut then return cmd, n, stringName end
            end
        end
        i = i + 1
    until cmd == 0
end

local export = {}

function export.passThroughCommand(char, cmd, alt, shift, ctrl)
    local modifierText = (cmd and "Cmd+" or "") .. (alt and "Opt+" or "") .. (char:match("%a") and (shift and "Shift+" or "") or "") .. (ctrl and "Control+" or "")

    local fullChar = modifierText .. textConvert(char)
    if not lastChar or lastChar ~= fullChar then lastChar = fullChar end

    local action_id, n, stringName = GetCommandByShortcut(section_id, fullChar)

    --extensionName = reaper.ReverseNamedCommandLookup(action_id)
    --if extensionName and #extensionName > 0 then
    --  action_id = extensionName
    --end
    if action_id then
        if reaper_sections["Main"] == section_id then
            reaper.Main_OnCommand(action_id, -1)
        elseif reaper_sections["MIDI Editor"] == section_id then
            local midi_editor = reaper.MIDIEditor_GetActive()
            reaper.MIDIEditor_OnCommand(midi_editor, action_id)
        end

        return stringName
    end
end

return export