-- @noindex
-- NKI Importer: measure where Kontakt's Files button and its "Load..." menu item sit in the
-- floating FX window - for Kontakt versions without built-in positions, or other display
-- scaling. Inserts a Kontakt track, then:
--   1. hover over the Files button (don't click) - the script clicks it to open the menu
--   2. hover over "Load..." in the menu
-- Both offsets are saved for the chosen Kontakt version (see "Choose Kontakt version").

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")
if not C.checkRequirements() then return end
if not C.ensureKontakt() then return end

local COUNTDOWN = 5

local track, fx, title, hwnd = C.createKontaktTrack("NKI calibrate")
if not track then
  reaper.ShowMessageBox(fx, "NKI Importer", 0)
  return
end

reaper.ShowMessageBox(string.format(
  "After pressing OK:\n\n" ..
  "1. Within %d seconds, hover over Kontakt's FILES button (don't click). The script clicks it.\n" ..
  "2. When the menu opens, hover over \"Load...\" within %d seconds.\n\n" ..
  "Calibrating: %s\nCurrent offsets: Files %d, %d   Load %d, %d",
  COUNTDOWN, COUNTDOWN, C.get("fxName"), C.getOffset("clickX"), C.getOffset("clickY"),
  C.getOffset("loadX"), C.getOffset("loadY")), "NKI Importer", 0)

local hints = { Files = "Hover over the FILES button", Load = "Hover over \"Load...\" in the menu" }

C.calibrate(title, hwnd, COUNTDOWN, function(line)
  local label, s = line:match("^COUNTDOWN (%a+) (%d+)")
  if label then
    local x, y = reaper.GetMousePosition()
    reaper.TrackCtl_SetToolTip(hints[label] .. "... " .. s, x + 20, y + 20, true)
  end
end, function(ok, lines)
  reaper.TrackCtl_SetToolTip("", 0, 0, false)
  local offsets = {}
  for _, line in ipairs(lines) do
    local which, a, b = line:match("^OFFSET (%a+) (%-?%d+) (%-?%d+)")
    if which then offsets[which] = { tonumber(a), tonumber(b) } end
  end
  local files, load = offsets.files, offsets.load
  if ok and files and load then
    local save = reaper.ShowMessageBox(string.format(
      "Files button: %d, %d\nLoad... item: %d, %d\n\nSave?", files[1], files[2], load[1], load[2]),
      "NKI Importer", 4)
    if save == 6 then
      C.setOffset("clickX", files[1])
      C.setOffset("clickY", files[2])
      C.setOffset("loadX", load[1])
      C.setOffset("loadY", load[2])
    end
  else
    reaper.ShowMessageBox(table.concat(lines, "\n") .. C.permissionHint(lines), "NKI Importer", 0)
  end
end)
