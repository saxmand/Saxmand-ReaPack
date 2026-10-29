-- @description NKI Importer
-- @author Saxmand
-- @version 1.2.1
-- @about
--   # NKI Importer
--
--   Drop Kontakt instruments (.nki) or multis (.nkm) on the arrange view, or select them in
--   Finder/Explorer and run "Import selected NKI files", and each one gets a new track with
--   Kontakt and the instrument or multi loaded. Several files load one after another with a
--   progress window.
--
--   Drop folders too: their Kontakt files (subfolders included) go into a list to confirm
--   first, and load into folder tracks named after the folders. Turn on "Collect files before
--   loading" to gather files in that list from several places before loading - once loading
--   starts, the mouse is busy.
--
--   - Drag and drop needs the "NKI Importer extension" package (same repository).
--   - Requires js_ReaScriptAPI.
--   - Kontakt 7 and 8. When more than one Kontakt is installed you're asked once which to use
--     (change it later with "Choose Kontakt version").
--   - The instrument is loaded by clicking Kontakt's File > Load... for you. If the clicks miss
--     (other Kontakt versions, display scaling), run "Calibrate Kontakt clicks".
--   - macOS: REAPER needs Accessibility access (System Settings > Privacy & Security >
--     Accessibility).
-- @provides
--   [nomain] nki_common.lua
--   [darwin] nki_helper.js
--   [nomain] Saxmand_NKI Importer - Import dropped files.lua
--   [main darwin] Saxmand_NKI Importer - Import selected NKI files in Finder.lua
--   [main windows] Saxmand_NKI Importer - Import selected NKI files in Explorer.lua
--   [main] Saxmand_NKI Importer - Calibrate Kontakt clicks.lua
--   [main] Saxmand_NKI Importer - Collect files before loading (toggle).lua
--   [main] Saxmand_NKI Importer - Set loading delays.lua
-- @changelog
--   + Fixed: loading more than two files could crash Kontakt. A file was treated as loaded the
--     moment its Load dialog closed, but Kontakt goes on reading the instrument after that, and
--     closing its window or adding the next instance mid-load makes it abort the process.
--     Loading now waits for it, and a window is only closed once the next file is about to start.
--   + "Set loading delays" to adjust those waits for big libraries or slow storage

-- NKI Importer: choose which installed Kontakt new tracks get (asked automatically on first
-- use when more than one is installed). Click offsets are kept per version.

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")
if not C.checkRequirements() then return end

C.chooseKontakt()
