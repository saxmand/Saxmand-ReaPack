-- @noindex
-- NKI Importer: how long to wait around each load.
--
-- Kontakt dismisses its Load dialog once it has accepted the path, then goes on reading
-- the instrument on its own threads, and there is nothing to ask it about that. So the
-- importer waits instead: once for the instrument to finish, and once more before
-- building the next instance. Touching Kontakt inside that window -- closing its editor,
-- adding another one -- is what makes it fast-fail and take REAPER with it.
--
-- The defaults suit instruments that load in about a second. Raise them for big
-- libraries or slow storage; lower them if loading a long list feels sluggish and
-- nothing crashes.

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")

local ok, answer = reaper.GetUserInputs("NKI Importer: loading delays", 2,
  "After loading a file (s),Before the next file (s),extrawidth=60",
  string.format("%g,%g", C.get("loadSettle"), C.get("betweenFiles")))
if not ok then return end

local settle, between = answer:match("^([^,]*),([^,]*)$")
settle, between = tonumber(settle), tonumber(between)
if not settle or not between then
  return reaper.ShowMessageBox("Both values have to be numbers, in seconds.",
                               "NKI Importer", 0)
end
-- Clamped rather than rejected: a negative wait is the same as none, and the upper end
-- only exists so a typo cannot leave the importer apparently hung.
local function clamp(v) return math.max(0, math.min(60, v)) end
C.set("loadSettle", clamp(settle))
C.set("betweenFiles", clamp(between))

reaper.ShowMessageBox(string.format(
  "Waiting %gs after each file, and %gs before the next one.\n\n" ..
  "If loading several files still crashes Kontakt, raise the first one.",
  C.get("loadSettle"), C.get("betweenFiles")), "NKI Importer", 0)
