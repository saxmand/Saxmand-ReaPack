-- @noindex
-- NKI Importer: toggles collect mode. On: dropped/selected files wait in the list window until
-- you press Load, so you can gather files from several places first (the mouse is busy once
-- loading starts). Off (default): files load right away. Folders always go to the list.

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")

local on = not C.get("collectMode")
C.set("collectMode", on)

local _, _, sectionID, cmdID = reaper.get_action_context()
reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
reaper.RefreshToolbar2(sectionID, cmdID)
