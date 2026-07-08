-- @noindex

local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
local commandID  = reaper.AddRemoveReaScript(true, 0, filename, false)
local state      = reaper.GetToggleCommandState(commandID)
local enabled    = state == 1

local function ensureBackgroundServerIsRunning()
    local bg_path = scriptPath .. "Saxmand_Articulation_Background Server.lua"
    local bg_id   = reaper.AddRemoveReaScript(true, 0, bg_path, false)
    if reaper.GetToggleCommandState(bg_id) < 1 then
        reaper.Main_OnCommand(bg_id, 1)
    end
    reaper.RefreshToolbar2(0, bg_id)
end

if enabled then
    reaper.SetToggleCommandState(0, commandID, 0)
    reaper.RefreshToolbar2(0, commandID)
else
    ensureBackgroundServerIsRunning()
    reaper.SetToggleCommandState(0, commandID, 1)
    reaper.RefreshToolbar2(0, commandID)
end
