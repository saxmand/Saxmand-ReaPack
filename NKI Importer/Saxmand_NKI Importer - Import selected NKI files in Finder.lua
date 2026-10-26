-- @noindex
-- NKI Importer: imports the .nki files selected in Finder (macOS; Windows has the Explorer
-- version). Assign a shortcut in the action list. Same queue and progress window as drops.

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")
if not C.checkRequirements() then return end

C.importSelectedFiles()
