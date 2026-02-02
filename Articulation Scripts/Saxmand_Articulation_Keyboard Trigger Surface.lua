-- @description Toggle Toolbar Icon For Keyboard Trigger Surface of selected articulation script
-- @version 0.0.2
-- @author saxmand
-- @package Articulation Scripts
-- @about
--   Toggles the toolbar button

--local commandID = ({reaper.get_action_context()})[4]  -- This script's command ID

local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
local commandID = reaper.AddRemoveReaScript(true, 0, filename, false)
-- Get current state
local state = reaper.GetToggleCommandState(commandID)
local enabled = state == 1

function ensureBackgroundServerIsRunning(stop)
    background_server_name = "Saxmand_Articulation_Background Server.lua"
    background_server_script_path = scriptPath .. background_server_name 
    background_server_command_id = reaper.AddRemoveReaScript(true, 0, background_server_script_path, false)
    
    
    if stop then
        if reaper.GetToggleCommandState(background_server_command_id) == 1 then
            reaper.SetToggleCommandState(0, background_server_command_id, 0)
        end
    else
        if reaper.GetToggleCommandState(background_server_command_id) < 1 then
            reaper.Main_OnCommand(background_server_command_id, 1)
            --reaper.SetToggleCommandState(0, background_server_command_id, 1)
        end
    end  
    reaper.RefreshToolbar2(0, background_server_command_id)
end

-- Toggle state
if enabled then
  -- Turn off
  --ensureBackgroundServerIsRunning(true)
  reaper.SetToggleCommandState(0, commandID, 0)
  reaper.RefreshToolbar2(0, commandID)
else
  ensureBackgroundServerIsRunning()
  -- Turn on
  reaper.SetToggleCommandState(0, commandID, 1)
  reaper.RefreshToolbar2(0, commandID)
end

