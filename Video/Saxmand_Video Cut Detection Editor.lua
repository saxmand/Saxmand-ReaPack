-- @description Find and edit cuts in videos using an editor and precise cut detection
-- @author saxmand
-- @version 0.8.2
-- @provides
--   Helpers/*.lua
--   Helpers/hosi_exec_hidden.vbs
-- @about
--   # Video Cut Detection Editor
--
--   Detects the cuts in a video, lets you name and colour them, and turns them into
--   markers, regions, take markers, thumbnails or item splits in your session.
--
--   Cuts are found either by the "Video Cut Detection Editor extension" package (same
--   or by FFmpeg. The extension is the default and needs nothing installed: it decodes
--   through AVFoundation on macOS and Media Foundation on Windows. It also reads preview
--   frames and thumbnails, and is what the Compare Videos tab runs on. Without it, set
--   an FFmpeg path on the Settings page and cut detection works as before.
--
--   FFmpeg is still worth having on Windows for ProRes and DNxHD, which Windows has no
--   decoder for; the extension falls back to it for those.
--
--   The Compare Videos tab fingerprints two cuts of the same film and conforms a
--   session from one to the other. It is still in development.
--
--   Optional: Ollama running locally, to label cuts from their picture.
-- @changelog
--   + Fixed: on Windows, Ollama was reported as installed but not running on machines
--     that did not have it, so the page offered to start it and Windows answered with
--     its own "cannot find ollama". Whether a program exists is now read from the exit
--     code rather than from whether anything was printed -- "where" announces a miss on
--     its error output, which counted as output. Starting or pulling now re-checks
--     first and opens the download page instead if it has gone missing.
--   + Fixed: showing the "nothing to describe" message raised an error instead of
--     drawing, having called a helper declared further down the file than itself.
--   + "Describe cuts" with nothing to describe now says so across the thumbnails for a
--     couple of seconds, instead of a dialog that has to be dismissed. It also goes on
--     the next thing you do, whichever comes first.
--   + Fixed: a cut was only selected when the cursor sat on its time exactly. A cut's
--     time comes out of the analysis and has no reason to land on REAPER's frame grid,
--     while the cursor always does -- so stepping a frame off a cut and back again left
--     it unselected despite ending where it started. The cursor now takes the nearest
--     cut within half a frame, nearest rather than first so two cuts closer than a
--     frame cannot both claim it.
--   + Fixed: shift-clicking empty timeline with a cut selected took two clicks to let
--     go of it. The cursor position had not caught up within that frame and still held
--     the cut's own time, so the cut was immediately re-selected.
--   + A "Video" tick under the right-hand preview, on by default. Off, that picture
--     stays on the selected cut while playing instead of following the playhead, so a
--     cut can be compared against whatever is playing past it.
--   + The right-hand caption reads "on playhead" while it is following playback, and
--     "on cut" otherwise.
--   + "Insert marker" pulses, as Analyse does: with no cut selected it is what the page
--     is offering.
--   + Fixed: on Windows, moving to a cut whose frames were not cached left the previous
--     picture on screen until you moved away and came back. Going there is instant
--     because the decode happens elsewhere, but the thumbnail was only fetched when the
--     playhead moved -- so nothing asked again once the real frame arrived. It now keeps
--     asking while the extension reports the frame as still decoding. Needs the Video
--     Preview extension at 1.7.1.
--   + "Describe cuts" leaves alone any cut that already has a name, whether somebody
--     typed it or an earlier run fetched it. Hold alt (opt on macOS) while clicking, or
--     press shift+alt+d, to replace those too. A model run is not deterministic, so
--     describing everything a second time used to quietly reword the lot.
--   + Cut Detection: the transport sits on the same row as the thumbnail captions,
--     centred in the gap between the two pictures, rather than on a row of its own.
--   + shift+d describes every cut on the timeline, where d describes the selected one.
--     Both Describe buttons say so. Stepping back through descriptions already fetched
--     has moved from shift+d to alt+d -- it is the only way back to one that cost a
--     model run, so it moved rather than went.
--   + Cut Detection: one Analyse button instead of two. An unanalysed video showed a
--     second, pulsing one where the cut count goes, a few pixels from the first; the
--     button that is always there now pulses instead.
--   + Cut Detection: the thumbnails fill their full width with black, as the Compare
--     tab's do, so a picture that is not the shape of its slot has an edge rather than
--     fading into the page.
--   + Cut Detection: italic captions under the thumbnails -- "before cut" on the left,
--     "on cut" on the right. The two pictures are often near-identical and nothing said
--     which was which, that being the reason there are two.
--   + Cut Detection: Undo and Redo moved down to the right-hand end of the row of
--     actions, away from the frame-stepping arrows they read as part of.
--   + Fixed: on the open tab, the tab's own tooltip appeared over whichever widget its
--     content happened to end with -- on Settings, the third column. The tooltip was
--     being attached after the tab had been closed off, by which point the last item
--     was a widget inside it rather than the tab.
--   + Selecting a cut whose frames are not cached no longer stalls, with the Video
--     Preview extension at 1.7.0: the decode moves off the calling thread and the
--     previous frame is held for a moment rather than the window freezing.
--   + Keyboard navigation is off. With it on, Tab and the arrow keys moved focus between
--     buttons and space activated whichever had it, so keys this app binds were being
--     swallowed by whatever happened to be focused. It is now cleared every frame, so
--     REAPER's own preference cannot put it back. Typing in a field is unaffected.
--   + Opening the Settings tab stops playback. Every transport control is on the other
--     two tabs, so sound that carried on here could not be stopped without navigating
--     back to find the button.
--   + The extension is now called "Video Cut Detection Editor extension" in ReaPack,
--     rather than "Video Preview extension" - the same package under a name that says
--     what it belongs to. Update it alongside this script.
--   + Settings: a "Max" slider for how much disk the cached frames may use, beside the
--     figure for what they currently occupy. Needs the Video Preview extension at
--     1.5.0, which also brings the read-ahead that Windows previews were missing.
--   + Settings: no gap under the divider, "Reset all settings" moved to the end of its
--     column rather than sitting above the settings it discards, a space above "Frame
--     diagnostics", and "Preview resolution" in grey like the other headings.
--   + Settings: what the cached preview images occupy, a button to delete them, and a
--     "Clear when closing app" toggle, in the second column. The cache already keeps
--     itself inside a budget, so this is not housekeeping anyone has to do -- it is
--     there to see what it costs and take it back on demand. Deleting them loses
--     nothing: frames are rebuilt from the video as they are needed.
--   + Settings: the script and extension versions sit across the top of the page rather
--     than inside the first column, and the "Settings" heading is gone -- the page is
--     plainly the settings page without it.
--   + Fixed: cut thumbnails written by an earlier version were kept and shown, so a fix
--     to which frame gets decoded changed nothing on screen. They are named after their
--     time in the file and nothing in the name said which build made them; the folder
--     now records that, and thumbnails from an older one are rebuilt once. Needs the
--     Video Preview extension at 1.3.2, which does the same for its own frame cache and
--     picks the frame nearest the time asked for.
--   + Fixed: a console window flashed over REAPER on Windows. The Ollama check ran
--     through a shell, which Windows gives a window, and it ran as soon as a cut was
--     selected whether or not Ollama was wanted at all - so it turned up for people who
--     had nothing to do with it. Everything that runs a command now goes through
--     REAPER's hidden process call, as the thumbnail path already did. The terminal
--     that opens while pulling an Ollama model is still meant to be seen: it is the
--     only progress a multi-gigabyte download has.
--   + Fixed: removing an Ollama model did nothing on Windows. The request body was
--     wrapped in single quotes, which cmd.exe does not treat as quoting, so Ollama was
--     sent them literally and rejected the request.
--   + Needs the Video Preview extension at 1.3.1, which fixes thumbnails and preview
--     frames on Windows coming from the wrong moment in the file.
--   + Needs the Video Preview extension at 1.3.0, which fixes the same file
--     fingerprinting differently on macOS and on Windows -- the remaining reason cut
--     detection disagreed between them once frame timing was sorted out. Fingerprint
--     stores built before it rebuild themselves on first use; nothing to do by hand.
--   + Fixed: cut detection on Windows found fewer cuts than macOS and put most of them
--     in the wrong place. A cut's position was worked out by dividing its frame number
--     by the frame rate recorded in the fingerprint store, and on Windows that rate was
--     always 25 whatever the file was. Positions now come from the timestamp each frame
--     carries, which also makes them right for variable frame rate files. Needs the
--     Video Preview extension at 1.2.1 or newer; older ones fall back to the division.
--   + Settings page text wraps inside its column instead of running into the next one.
--   + "Frame diagnostics" also reports the fingerprint store's frame count, measured
--     frame rate and frame timing, so the same file can be compared between machines.
--   + Fixed: the settings page told Windows users the extension was macOS only, which
--     stopped being true when the Windows build shipped.


-------- Possible IDEAS TODO
-- add option to keep old cut information (eg. color and name)
-- support drop frames (never looked at it so don't know how it behavies)
-- add waveform
-- have multiple videos for cross reference (idea by soundfield)
-- Compare two videos
    -- cut timeline depending on video changes for you :) 
-- randomize all colors


package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'
local script_path = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
package.path = package.path .. ";" .. script_path .. "Helpers/?.lua"

local json = require("json")
local ffmpeg = require("ffmpeg")
local undo_redo = require("undo_redo")

local is_windows = package.config:sub(1, 1) == "\\"
local seperator = package.config:sub(1, 1) -- path separator: '/' on Unix, '\\' on Windows

-- Read out of this file's own header rather than kept as a second copy of the number.
-- A hardcoded version is wrong the moment the header is bumped and nobody notices, and
-- the whole point of showing it is to answer "what am I running" correctly.
local scriptVersion = (function()
    local src = debug.getinfo(1, "S").source:match("^@?(.*)$")
    local f = src and io.open(src)
    if not f then return "?" end
    local v
    for _ = 1, 20 do
        local line = f:read("*l")
        if not line then break end
        v = line:match("^%-%-%s*@version%s+(%S+)")
        if v then break end
    end
    f:close()
    return v or "?"
end)()

-- ---------------------------------------------------------------------------
-- Modifier keys, and what to call them
-- ---------------------------------------------------------------------------
-- ReaImGui turns on ConfigVar_MacOSXBehaviors on macOS, which swaps Cmd and Ctrl: there
-- Mod_Ctrl is Cmd and Mod_Super is Ctrl, while on Windows and Linux they are the keys
-- they are named after. So the useful way to think about them is by role, not by key:
--
--   Mod_Ctrl   the primary shortcut modifier -- Cmd on macOS, Ctrl elsewhere
--   Mod_Super  Ctrl on macOS, the Windows/Super key elsewhere
--   Mod_Alt    Opt on macOS, Alt elsewhere
--
-- The names below are only for what the tooltips say, so a Windows user is told to
-- press ctrl and alt rather than cmd and opt. The bindings themselves are platform
-- independent already, by using the role rather than the key.
local isMacOS = not is_windows and (reaper.GetOS() or ""):match("OSX") ~= nil
               or not is_windows and (reaper.GetOS() or ""):match("macOS") ~= nil

MOD_CMD  = isMacOS and "cmd" or "ctrl"   -- the primary modifier; isSuperDown
MOD_ALT  = isMacOS and "opt" or "alt"    -- isOptionDown
MOD_CTRL = "ctrl"                        -- the physical Ctrl key; isCtrlDown


local ctx -- = ImGui.CreateContext('Video cut detection editor')
--font = ImGui.CreateFont('Arial', 14)
stateName = "Saxmand_VideoCutDetectionEditor"

fast = false

local devMode = script_path:match("jesperankarfeldt") ~= nil
--------------------------------------------------------
------------------COLOURS-------------------------------
--------------------------------------------------------
-- MODERN THEME PALETTE
local theme                = {
    bg            = reaper.ImGui_ColorConvertDouble4ToU32(0.12, 0.12, 0.14, 1.00),  -- Very dark grey (VSCode-like)
    panel_bg      = reaper.ImGui_ColorConvertDouble4ToU32(0.16, 0.16, 0.18, 1.00),
    accent        = reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.50, 0.95, 1.00),  -- Modern Blue
    accent_hover  = reaper.ImGui_ColorConvertDouble4ToU32(0.35, 0.60, 0.98, 1.00),
    accent_active = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.40, 0.85, 1.00),
    text          = reaper.ImGui_ColorConvertDouble4ToU32(0.95, 0.95, 0.95, 1.00),
    text_dim      = reaper.ImGui_ColorConvertDouble4ToU32(0.60, 0.60, 0.60, 1.00),
    button        = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    button_hover  = reaper.ImGui_ColorConvertDouble4ToU32(0.28, 0.28, 0.32, 1.00),
    button_active = reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.20, 1.00),
    tab           = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    tab_hover     = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.32, 0.50, 1.00),
    tab_active    = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.40, 0.70, 1.00),
    border        = reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.28, 1.00),
    success       = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.70, 0.40, 1.00),
    warning       = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.60, 0.10, 1.00),
    error         = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.20, 0.20, 1.00),
}

-- Mappings to existing variables (to keep script logic working)
colorTransparent           = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
colorWhite                 = theme.text
colorGrey                  = theme.text_dim
colorLowGrey               = reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1)
colorMidGrey               = reaper.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1)
colorLightGrey             = reaper.ImGui_ColorConvertDouble4ToU32(0.7, 0.7, 0.7, 1)
colorAlmostWhite           = theme.text
colorBlue                  = theme.accent
colorBrightBlue            = theme.accent_hover
colorBrightBlueTransparent = (theme.accent & 0xFFFFFF00) | 0x88
colorBrightBlueOverlay     = (theme.accent & 0xFFFFFF00) | 0x40
colorBlueTransparent       = (theme.accent & 0xFFFFFF00) | 0x80
colorLightBlue             = (theme.accent & 0xFFFFFF00) | 0x40 -- Semi-transparent

colorBlack                 = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1)
colorReallyBlack           = reaper.ImGui_ColorConvertDouble4ToU32(0.07, 0.07, 0.1, 1)
colorAlmostBlack           = theme.bg
colorDarkGrey              = theme.panel_bg
colorDarkGreyTransparent   = (theme.panel_bg & 0xFFFFFF00) | 0x80

colorMap                   = theme.accent
colorMapDark               = theme.accent_active
colorMapLight              = theme.accent_hover
colorMapLightest           = theme.text

-- Palette for cuts
colorRed                   = 0xE06C75FF
colorOrange                = 0xE5C07BFF
colorYellow                = 0xD19A66FF
colorGreen                 = 0x98C379FF
colorCyan                  = 0x56B6C2FF
colorBlue                  = 0x61AFEFFF
colorIndigo                = 0xC678DDFF
colorViolet                = 0xBE5046FF
colorPink                  = 0xD55FDEFF

-- color play button
colorIsPlaying             = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.6, 0.2, 1)

--local cut_data
local old_cut_data = {}
--local cuts_making_threashold = {}
local analyseStartTime
local analyseEndTime
local time_precise


function GetTextColorForBackground(u32_color)
    -- Extract 8-bit R, G, B from U32 (ImGui format: 0xAABBGGRR)
    r, g, b, a = reaper.ImGui_ColorConvertU32ToDouble4(u32_color)

    -- Calculate relative luminance (W3C standard)
    local luminance = 0.4 * r * 256 + 0.8 * g * 256 + 0.4 * b * 256

    -- Use black if background is bright, white if it's dark
    if luminance > 186 then
        return reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1) -- black
    else
        return reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1) -- white
    end
end

function pulsatingColor(colorIn, speed)
    local time = reaper.time_precise() * (speed and speed or 6)
    local pulsate = (math.sin(time * 2) + 1) / 2 -- range: 0 to 1
    local alpha = math.floor(0x55 + (0xFF - 0x55) * pulsate)
    return colorIn & (0xFFFFFF00 + alpha)        -- combine alpha and RGB
end


local markerColors = { colorRed, colorOrange, colorYellow, colorGreen, colorCyan, colorBlue, colorIndigo, colorViolet, colorPink, colorGrey }

--------------------------------------------------------
------------------SETTINGS------------------------------
--------------------------------------------------------
function deep_copy(orig, copies)
    copies = copies or {}
    if type(orig) ~= 'table' then
        return orig
    elseif copies[orig] then
        return copies[orig] -- handle circular references
    end

    local copy = {}
    copies[orig] = copy
    for k, v in next, orig, nil do
        copy[deep_copy(k, copies)] = deep_copy(v, copies)
    end
    setmetatable(copy, deep_copy(getmetatable(orig), copies))
    return copy
end

function deep_compare(t1, t2)
    if t1 == t2 then return true end
    if type(t1) ~= "table" or type(t2) ~= "table" then return false end

    for k, v in pairs(t1) do
        if not deep_compare(v, t2[k]) then return false end
    end
    for k in pairs(t2) do
        if t1[k] == nil then return false end
    end
    return true
end

local defaultSettings = {
    windowSize = 200,
    threshold = 100,
    removeCutsWithinXFrames = 1,
    showToolTip = true,
    --analyseOnlyBetweenMarkers = false,
    --overviewFollowsLoopSelection = true,
    
    defaultColor = colorBlue,
    onlyShowCutsWithEditedName = false,
    alwaysShowCutsWithEditedName = true,
    navigationFollowsPlayhead = true,

    cursorFollowSelectedCut = true,

    timecodeRelativeToSession = false, -- not implemented
    tabSelection = 1,
    
    arrangeviewFollowsOverview = true,
    displayTimeSelection = true,
    selectionType = "Video item",
    useTypeForSingleInsert = "Markers",
    useTypeForSingleInsertSubproject = "Markers",
    
    setNameOnSplitItems = true,
    setColorOnSplitItems = true,

    ai_backend = "ollama",
    ollama_model = "llava",
    ollama_host = "localhost:11434",

    compare_threshold = 0.65,
    compare_threshold2 = 0.40,
    compare_end_frames = true,

    vp_preview_size = 1,    -- live preview resolution: 1=640x360  2=960x540  3=1280x720

    conform_ham = 4,              -- seeding bar in bits of 64; see VP_Match
    conform_min_run = 12,         -- shortest run of frames reported as a match
    conform_list_matched = false, -- include unchanged runs in the change list
    conform_audio = {},           -- [videoPath] = separate audio export to match on
    conform_volume = 1.0,
    conform_use_audio = false,    -- also match on sound, to fill gaps picture cannot reach
    conform_audio_ham = 8,        -- sound seeds looser: matched sound sits near 8, unrelated near 32
    conform_audio_min_run = 100,  -- hops, so one second at 100 per second
    conform_peak_gain = 1.0,      -- waveform display gain; dialogue sits far below full scale
    conform_wave = true,          -- draw the waveform strips at all
    conform_show_result = false,  -- match summary and change list under the timeline
    conform_sync = false,         -- drive REAPER's transport instead of previewing
    conform_min_conf = 0,         -- drop matches below this confidence %; 0 keeps all
    conform_lane_muted = false,   -- show muted items in the session lanes
    -- [row] = true means muted, so a row absent from here is audible: the speakers
    -- default to on, and adding a track starts making sound rather than silently not.
    conform_row_mute = {},
    conform_heal_spread = 5.0,    -- s; pieces further apart than this are not averaged
    conform_heal_gap = 50,        -- frames; widest gap two matches are joined across

    -- "extension" detects from the framestore the VP extension builds; "ffmpeg" runs
    -- the scdet filter in a subprocess. The extension is the default: it needs nothing
    -- installed, it is instant to re-run at a different sensitivity once the store
    -- exists, and it tells a cut from a whip pan. cutMethodIsExtension falls back to
    -- FFmpeg by itself where the extension is not loaded, so this default cannot leave
    -- anyone unable to detect cuts.
    cut_method = "extension",
    cut_motion = 300,             -- jump as a % of the local median distance
    cut_jump = 20,                -- bits of 64 the frame hash must move
    cut_gap = 20,                 -- frames; suppress a weaker cut beside a stronger
    clearCacheOnExit = false,     -- decoded frames are kept between sessions by default
    cacheBudgetMB = 256,          -- ceiling for the decoded-frame cache; see the slider
    previewLiveVideo = true,      -- right preview follows the playhead while playing
}

local function saveSettings()
    local settingsStr = json.encodeToJson(settings)
    reaper.SetExtState(stateName, "settings", settingsStr, true)
end



if reaper.HasExtState(stateName, "settings") then
    local settingsStr = reaper.GetExtState(stateName, "settings")
    -- decodeFromJson returns nil and a reason when it cannot parse, which the fall
    -- back to defaults below already handles. What it does NOT rule out is valid JSON
    -- that is not an object: `"text"` or `123` decode fine, and settings would then be
    -- a string or a number. The compatibility loop underneath immediately does
    -- settings[key] = {} on it, which is an error on a string -- so the type is checked
    -- here and anything that is not a table is treated as unreadable.
    local decoded, decodeErr = json.decodeFromJson(settingsStr)
    settings = (type(decoded) == "table") and decoded or nil
    if not settings then
        reaper.ShowConsoleMsg("Could not read the stored settings, so defaults were restored: "
            .. tostring(decodeErr or "not a settings object") .. "\n")
    end
end
if not settings then
    settings = deep_copy(defaultSettings)
    saveSettings()
end


-- BACKWARDS COMPATABILITY
for key, value in pairs(defaultSettings) do
    if type(value) == "table" then
        if settings[key] == nil then
            settings[key] = {}
        end

        for subKey, subValue in pairs(value) do
            if settings[key][subKey] == nil then
                settings[key][subKey] = subValue
            end
        end
    else
        if settings[key] == nil then
            settings[key] = value
        end
    end
end

-- moondream was briefly the default while not being one of the models on offer, so the
-- dropdown showed a name that could not be chosen again once changed. Anyone carrying
-- that stored value is moved to the default, which is a real entry in the list. Only
-- that one value is touched: a model somebody picked on purpose is left alone.
if settings.ollama_model == "moondream" then
    settings.ollama_model = defaultSettings.ollama_model
    saveSettings()
end

--------------------------------------------------------
-----------------HELPERS--------------------------------
--------------------------------------------------------

local function GetDirectoryFromPath(path)
  return path:match("^(.*)[/\\]")
end

local function GetFilenameFromPath(path)
  if not path or path == "" then return nil end
  return path:match("([^/\\]+)$")
end

local function GetFilenameNoExt(path)
  local filename = GetFilenameFromPath(path)
  if not filename then return nil end
  return filename:match("^(.*)%.")
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
end


local function join_paths(path1, path2)
    local sep = package.config:sub(1, 1)
    -- Normalize mixed slashes to system separator
    if sep == "\\" then
        path1 = path1:gsub("/", "\\")
        path2 = path2:gsub("/", "\\")
    else
        path1 = path1:gsub("\\", "/")
        path2 = path2:gsub("\\", "/")
    end

    if path1:sub(-1) ~= sep then
        path1 = path1 .. sep
    end
    return path1 .. path2
end


local function file_exists_check(path)
    local f = io.open(path, "rb")
    if f then
        local size = f:seek("end")
        f:close()

        return size and size > 0
    end
    return false
end

local function DirectoryExists(path)
  if not path or path == "" then return false end

  -- Try to enumerate subdirectories
  local subdir = reaper.EnumerateSubdirectories(path, 0)
  if subdir then return true end

  -- Try to enumerate files
  local file = reaper.EnumerateFiles(path, 0)
  if file then return true end

  return false
end


local function saveFile(filePath, data)
    -- Make sure subfolder exists (cross-platform)
    --os.execute( (seperator == "/" and "mkdir -p \"" or "mkdir \"" ) .. filePath .. "\"")
    -- Save a file
    local file = io.open(filePath, "w")
    if file then
        file:write(data)
        file:close()
    end
end

local function readFile(filePath)
    local file = io.open(filePath, "r") -- "r" for read mode
    if not file then
        return nil
    end

    local content = file:read("*a") -- read entire file
    file:close()
    -- remove possible no index
    return content
end

-- APP SPECIFIC

local function getPngName(itemStart, name)
    name = name and (name .. ".png") or ('thumbnail' .. math.floor(itemStart * 1000000) .. '.png')
    return name
end

local function compareWithMargin(a, b, marg)
    if not a or not b then return false end
    
    marg = marg or 100000000
    difference = (math.abs(a * marg - b * marg))
    if difference < 1 then
        --reaper.ShowConsoleMsg(difference .. " diff\n")
    end
    return difference < 1
end


function roundToFrame(time_pos_seconds, frames_per_second)
    -- Get the current project's time base (frames per second)
    frames_per_second = frames_per_second and frames_per_second or reaper.TimeMap_curFrameRate(0)

    -- Convert the time position to frames
    local time_pos_frames = time_pos_seconds * frames_per_second

    -- Round the frame value
    local rounded_frame = math.floor(time_pos_frames + 0.5)

    -- Convert the rounded frame value back to seconds
    local rounded_time_pos_seconds = rounded_frame / frames_per_second
    return rounded_time_pos_seconds
end
--------------------------------------------------------
--------------------------------------------------------
--------------------------------------------------------

------------------------------------------------------------
-- Find first track with an exact name match
------------------------------------------------------------
function FindTrackByName(track_name)
  local track_count = reaper.CountTracks(0)

  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    if name == track_name then
      return track
    end
  end

  return nil
end

------------------------------------------------------------
-- Get 0-based track index
------------------------------------------------------------
function GetTrackIndex(track)
  return reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
end

------------------------------------------------------------
-- Create a track directly below another track
------------------------------------------------------------
function CreateTrackBelowTrack(reference_track, new_track_name)
  local ref_index = GetTrackIndex(reference_track)

  -- Insert new track below reference
  reaper.InsertTrackAtIndex(ref_index + 1, true)

  local new_track = reaper.GetTrack(0, ref_index + 1)
  reaper.GetSetMediaTrackInfo_String(
    new_track,
    "P_NAME",
    new_track_name,
    true
  )

  return new_track
end

------------------------------------------------------------
-- Get existing track by name OR create it below reference
------------------------------------------------------------
function GetOrCreateTrackBelow(reference_track, track_name)
  -- Try to find existing track
  local track = FindTrackByName(track_name)
  if track then
    return track
  end

  -- Create if not found
  return CreateTrackBelowTrack(reference_track, track_name)
end

function getSubprojectFromItem(selectedItem)
    if selectedItem then
        local itemTake = reaper.GetActiveTake(selectedItem)
        if itemTake then 
            takeSource = reaper.GetMediaItemTake_Source(itemTake) 
            local mediaItemType = reaper.GetMediaSourceType(takeSource)
            if mediaItemType == "RPP_PROJECT" then  
               proj =  reaper.GetSubProjectFromSource( takeSource )
               return proj
            end
        end
    end
    return false
end



function isSubproject()
  local currentProj, currentProjPath = reaper.EnumProjects(-1)
  for tab = 0, 99 do 
    local reaProj, reaProjPath = reaper.EnumProjects(tab)
    if reaProj ~= currentProj then
      if reaProj == nil then break 
      else  
        allMediaItems = reaper.CountMediaItems(reaProj)
        for i = 0, allMediaItems - 1 do
           local selectedItem = reaper.GetMediaItem(reaProj, i)
           local checkProj = getSubprojectFromItem(selectedItem)
          if checkProj and checkProj == currentProj then
            local mainProj, subProj = reaProj, checkProj
            return mainProj, subProj, selectedItem --copyMarkersToSubproject(reaProj, selectedItem)
          end
        end
      end
    end
  end
end


-- Function to get the position of a marker by its name
local function get_marker_position_by_name(marker_name)
    local numRegionsAndMarkers, numMarkers, numRegions = reaper.CountProjectMarkers(0)
    for i = 0, numRegionsAndMarkers - 1 do
        local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
        if not isrgn and name == marker_name then
            return pos
        end
    end
    return nil
end

-- Function to check if time selection matches project markers
local function get_subproject_length()
    -- Get the loop time selection
    loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    -- Get the positions of the =START and =END markers
    start_marker_pos = get_marker_position_by_name("=START") or 0
    end_marker_pos = get_marker_position_by_name("=END") or 10
    
    if end_marker_pos then
        return end_marker_pos - start_marker_pos
    end 
end


-- FFmpeg is optional once the extension can detect cuts and pull frames itself, so a
-- missing one no longer stops the script loading -- it only rules out the FFmpeg
-- detection mode. Anything that still needs it checks ffmpeg_path first.
--
-- Asked for quietly: without the flag this puts up "FFMpeg is required for this action"
-- and a file browser before the window has even opened, which was true once and is not
-- any more. It is prompted for where it is actually being set up instead -- picking the
-- FFmpeg detector, or the buttons for its path.
local ffmpeg_path = ffmpeg.Get_Path(true)
if ffmpeg_path == "" then ffmpeg_path = nil end
local ffmpeg_available = ffmpeg_path ~= nil

-- The extension decodes through the ffmpeg binary on Windows -- there is no
-- AVFoundation there -- so it has to be told where that is. Harmless on macOS, which
-- decodes in process and ignores it, so there is no platform branch here.
--
-- Called whenever the path changes as well as at startup: the extension holds it in a
-- variable, not a setting, so a path found later in the session has to be handed over
-- rather than waiting for a restart.
function vpTellFfmpegPath()
    if reaper.VP_SetFFmpegPath then
        reaper.VP_SetFFmpegPath(ffmpeg_path or "")
    end
end

-- Asks for the path now, for the places where FFmpeg is the thing being chosen. Returns
-- whether there is one, and keeps the two module-level flags in step with the answer so
-- everything downstream sees it without a restart.
function ensureFfmpegPath()
    if ffmpeg_path then return true end
    local p = ffmpeg.Get_Path()
    if p == "" then p = nil end
    ffmpeg_path = p
    ffmpeg_available = ffmpeg_path ~= nil
    vpTellFfmpegPath()
    return ffmpeg_available
end

-- The extension: hardware-accelerated frame extraction, AVFoundation or Media Foundation.
-- Falls back to ffmpeg subprocess when the extension is not loaded.
local vp_available = reaper.VP_Open ~= nil
local vp_handles = {}      -- [filePath] = handle for the advancing playback head (tB)
local vp_handles_cut = {}  -- [filePath] = handle for the frozen cut-anchor frame (tA)

-- Live preview resolution presets (width, height)
local VP_PREVIEW_SIZES = {{640, 360}, {960, 540}, {1280, 720}}
local function vpPreviewWH()
    local sz = VP_PREVIEW_SIZES[settings.vp_preview_size or 1] or VP_PREVIEW_SIZES[1]
    return sz[1], sz[2]
end

local function vpGetHandle(filePath)
    if not vp_available or not filePath or filePath == "" then return nil end
    if vp_handles[filePath] == nil then
        local h = reaper.VP_Open(filePath)
        vp_handles[filePath] = (h and h > 0) and h or false
    end
    return vp_handles[filePath] or nil
end

-- Separate decoder for the frozen tA frame so it never fights with tB's batch window.
local function vpGetHandleCut(filePath)
    if not vp_available or not filePath or filePath == "" then return nil end
    if vp_handles_cut[filePath] == nil then
        local h = reaper.VP_Open(filePath)
        vp_handles_cut[filePath] = (h and h > 0) and h or false
    end
    return vp_handles_cut[filePath] or nil
end

-- Initialize ImGui Context AFTER blocking calls (Get_FFMpeg_Path) to avoid context invalidation error
ctx = ImGui.CreateContext('Video cut detection editor')

-- ---------------------------------------------------------------------------
-- Telling REAPER the window is open
-- ---------------------------------------------------------------------------
-- A toolbar button or menu entry for this action draws itself from the action's toggle
-- state, so without this it never looks pressed and there is no way to tell from the
-- toolbar whether the editor is already up.
--
-- get_action_context gives the section and command id of whatever is running this, so
-- it works however the script was installed and whatever command id it ended up with.
-- When it is run some other way than as an action, cmdID is 0 and this does nothing.
local _, _, actionSectionID, actionCmdID = reaper.get_action_context()

function setActionToggle(on)
    if not actionCmdID or actionCmdID == 0 then return end
    reaper.SetToggleCommandState(actionSectionID, actionCmdID, on)
    reaper.RefreshToolbar2(actionSectionID, actionCmdID)
end

setActionToggle(1)

-- The cache ceiling lives in the extension, which has no idea what was chosen last
-- session, so the stored figure has to be handed over on startup as well as on a change.
-- The extension holds it to a range and returns what took effect, so the slider shows
-- the value in force rather than the one that was asked for.
function vpApplyCacheBudget()
    if not reaper.VP_SetCacheBudget then return end
    local got = reaper.VP_SetCacheBudget(settings.cacheBudgetMB or 256)
    if got and got > 0 and got ~= settings.cacheBudgetMB then
        settings.cacheBudgetMB = got
        saveSettings()
    end
end

-- Hand the ffmpeg path over now that the extension is certainly loaded. On Windows the
-- extension cannot decode anything without it.
vpTellFfmpegPath()
vpApplyCacheBudget()

-- An italic face for asides -- notes about the tool rather than content of it.
-- CreateFont's second argument is flags, not a size: in this ReaImGui the size is given
-- at PushFont time, which is why every PushFont here passes one. Attached so it lives as
-- long as the context; without that it would be collected the moment nothing held it.
--
-- Guarded, because an italic face is not worth failing to start over: where the font
-- cannot be made, fontItalic stays nil and PushFont(ctx, nil, size) falls back to the
-- default face at that size, exactly as the rest of the script already does.
fontItalic = nil
if reaper.ImGui_CreateFont and reaper.ImGui_FontFlags_Italic then
    local ok, f = pcall(reaper.ImGui_CreateFont, 'sans-serif', reaper.ImGui_FontFlags_Italic())
    if ok and f then
        fontItalic = f
        reaper.ImGui_Attach(ctx, fontItalic)
    end
end


function extract_cut_data_fast(IP)
    local cutTextFilePathRaw = IP.cutTextFilePathRaw 
    local start_time = IP.item_area_to_analyze_start
    local f = io.open(cutTextFilePathRaw)
    if not f then return nil, "Could not open file" end
    local results = {}

    local entry = {}

    for line in f:lines() do
        local mafd = line:match("lavfi%.scd%.mafd=(%S+)")
        if mafd then
            entry.mafd = tonumber(mafd)
        end

        local score = line:match("lavfi%.scd%.score=(%S+)")
        if score then
            entry.score = tonumber(score) / 30 * 100
        end

        local time = line:match("lavfi%.scd%.time=(%S+)")
        if time then
            entry.time = tonumber(time) + start_time
        end
        -- Once we have all three, store and reset
        if entry.mafd and entry.score and entry.time then
            
            --entry.color = settings.defaultColor
            table.insert(results, entry)
            entry = {}
        end
    end

    f:close()

    return results
end



function get_cut_information_fast(file_path, cutTextFilePath, start_time, length) --, start_offset, length ) 
    local args = " "
    local detection_threshold = 1
    os.remove(cutTextFilePath)

    --if not reaper.file_exists(cutTextFilePath) then
    --reaper.ShowConsoleMsg("CreateFile")

    if start_offset ~= nil then
        args = args .. "-ss " .. string.format("%f", start_offset) .. " "
    end

    if length ~= nil then
        args = args .. "-t " .. string.format("%f", length) .. " "
    end

    args = args .. "-i \"" .. file_path .. "\" -filter:v " .. '"scdet=t=' ..
        string.format("%f", detection_threshold) ..
        ":s=1,metadata=print:" .. cutTextFilePath .. '"' .. " -f null -"                                             -- 2>/dev/null"

    args = ' -hide_banner'
    --if settings.analyseOnlyBetweenMarkers then
    --reaper.ShowConsoleMsg(start_time .. " - ".. end_time .. " hej\n")

    args = args .. ' -ss ' .. start_time .. ' -t ' .. length
    --end
    args = args .. ' -i "' .. file_path ..
        '" -filter:v "scdet=t='..string.format("%f", detection_threshold) ..':s=1,metadata=print:file=' .. cutTextFilePath .. '" -f null -'

    -- Define a temporary file path

    -- Use stdbuf to ensure line-buffered output
    local command = '"' .. ffmpeg_path .. '"' .. args   -- .. " > " .. '"' .. cutTextFilePath .. '"' --.. " 2>&1"

    reaper.CF_SetClipboard(command .. "\n")
    --reaper.ShowConsoleMsg(command)
    ffmpeg_read = reaper.ExecProcess(command, -1)
    --end
    
end



function get_cut_information_mac(file_path, cutTextFilePath, start_time, length, detection_threshold)
    detection_threshold = detection_threshold or 0.1
    os.remove(cutTextFilePath)
    
    -- Build FFmpeg arguments
    local args = {}
    
    table.insert(args, '"' .. ffmpeg_path .. '"') 
    
    table.insert(args, "-hide_banner")
    if start_time then table.insert(args, "-ss " .. string.format("%.6f", start_time)) end
    if length then table.insert(args, "-t " .. string.format("%.6f", length)) end

    table.insert(args, '-i "' .. file_path .. '"')
    
    -- ВАЖНО: Путь safe_cut_path содержит экранированное двоеточие (C\:)
    -- И мы оборачиваем его в одинарные кавычки
    table.insert(args, '-vf "select=gt(scene\\,' .. string.format("%.6f", detection_threshold) .. ")" ..  
    ',metadata=print:file=\'' .. cutTextFilePath .. '\'"' )
    table.insert(args, "-f null -")

    local command = table.concat(args, " ")
    --reaper.CF_SetClipboard(command .. "\n")
    
    reaper.ExecProcess(command, -1)
    
    return true
end


function get_cut_information_win(file_path, cutTextFilePath, start_time, length, detection_threshold)
    detection_threshold = detection_threshold or 0.1
    local is_windows = package.config:sub(1,1) == "\\"

    -- Remove previous output
    os.remove(cutTextFilePath)

    -- Build FFmpeg arguments
    local args = {}

    table.insert(args, "-hide_banner")

    if start_time then
        table.insert(args, "-ss " .. string.format("%.6f", start_time))
    end

    if length then
        table.insert(args, "-t " .. string.format("%.6f", length))
    end

    if is_windows then
       -- Normalize paths to forward slashes to avoid escaping issues in filter strings
       file_path = file_path:gsub("\\", "/")
       cutTextFilePath = cutTextFilePath:gsub("\\", "/")
    end

    table.insert(args, '-i "' .. file_path .. '"')

    -- Escape colon for filter path on Windows
    local filter_out_path = cutTextFilePath
    if is_windows then
        filter_out_path = filter_out_path:gsub(":", "\\:")
    end

    table.insert(args,
        '-vf "select=gt(scene\\,' ..
        string.format("%.6f", detection_threshold) .. ")" .. 
        ',metadata=print:file=\'' .. filter_out_path .. '\'"'
    )

    -- FFMPEG logging
    local log_path = cutTextFilePath:gsub("_cutsRaw.txt", "_ffmpeg_log.txt")
    
    table.insert(args, "-f null -")

    -- Sanitize ffmpeg_path
    ffmpeg_path = ffmpeg_path:gsub('"', '')

    if is_windows then
        -- Use WScript.Shell via a stable VBS file in the script directory
        -- This guarantees hidden execution without Temp file issues
        
        local cmd_ffmpeg = '"' .. ffmpeg_path .. '" ' .. table.concat(args, " ") .. ' > "' .. log_path .. '" 2>&1'
        local cmd_wrapper = 'cmd.exe /C "' .. cmd_ffmpeg .. '"'
        
        -- Use the script directory (upvalue script_path should be available)
        -- If script_path is nil (safeguard), fall back to a local relative path or Temp
        local vbs_dir = script_path
        if not vbs_dir then 
            vbs_dir = os.getenv("TEMP") or "." 
        end
        local vbs_path = vbs_dir .. "hosi_exec_hidden.vbs"
        
        local f = io.open(vbs_path, "w")
        if f then
            -- Escape double quotes for VBScript (" -> "")
            local vbs_cmd = cmd_wrapper:gsub('"', '""')
            
            f:write('Dim WshShell\n')
            f:write('Set WshShell = CreateObject("WScript.Shell")\n')
            -- Run hidden (0) and wait (True)
            f:write('WshShell.Run "' .. vbs_cmd .. '", 0, True\n') 
            f:close()
            
            -- Execute VBS
            reaper.ExecProcess('wscript.exe "' .. vbs_path .. '"', -1)
            
            -- Do NOT delete the VBS file immediately to avoid race conditions.
            -- It's small and reusable.
        else
            -- Fallback if cannot write to script dir
            local cmd_direct = '"' .. ffmpeg_path .. '" ' .. table.concat(args, " ") 
            reaper.ExecProcess(cmd_direct, -1)
        end
    else
        -- Unix/Mac
        local cmd_content = '"' .. ffmpeg_path .. '" ' .. table.concat(args, " ") .. ' 2> "' .. log_path .. '"'
        reaper.ExecProcess(cmd_content, -1)
    end
    
    -- Debug logs processing (optional, mainly for dev)
    -- local f = io.open(log_path, "r")
    -- if f then f:close() end
    
    -- Return based on file existence/size? Logic outside handles this.
    return true
end

-- Whether cuts come from the extension's framestore rather than the FFmpeg subprocess.
-- Falls back to FFmpeg if the extension is not loaded, so choosing it in the settings
-- cannot leave the tab unable to analyse anything.
function cutMethodIsExtension()
    if reaper.VP_Cuts == nil then return false end
    -- With no FFmpeg there is nothing to fall back to, so the extension is the only
    -- way cuts can be found at all.
    if not ffmpeg_available then return true end
    return settings.cut_method == "extension"
end

-- ---------------------------------------------------------------------------
-- The extension's analysis, per file rather than per item-property table
-- ---------------------------------------------------------------------------
-- This state used to live on the item-property table, which is where the FFmpeg path's
-- equivalent appears to live too. It does not: FFmpeg's state is a file on disk and the
-- table only holds the path to it, re-derived every time. The tables themselves are
-- rebuilt from scratch by getItemProperties whenever anything changes -- including on
-- every frame while an analysis is running, since analyseStartTime holds the refresh
-- guard true.
--
-- So a job handle put on one of them was gone by the next frame. The analysis started
-- and then ran to completion unobserved: never polled, never released, never reported.
-- From the outside the Analyse button did nothing at all.
--
-- Keyed by file path, it survives those rebuilds, and two tables pointing at the same
-- file share one job -- which is right, because there is only one framestore per file.
vpCutState = {}     -- [filePath] = { job, store, done, err }

function vpCutStateFor(IP)
    if not IP or not IP.filePath or IP.filePath == "" then return nil end
    local s = vpCutState[IP.filePath]
    if not s then
        s = {}
        vpCutState[IP.filePath] = s
    end
    return s
end

-- Starts the framestore the extension detects from. force=0, so a file that already has
-- one -- because it was analysed here before, or matched in the Compare tab -- skips
-- straight to detection.
function vpStartCutAnalysis(IP)
    local s = vpCutStateFor(IP)
    if not s then return end
    -- Already running for this file: starting a second job over the same store would
    -- have both writing it, and the first handle would be dropped unreleased.
    if s.job then return end
    s.done, s.err = nil, nil
    s.store = IP.filePath .. ".vpfs"
    s.job   = reaper.VP_Analyze(IP.filePath, s.store, 0)
    if not s.job or s.job == 0 then
        s.job = nil
        s.err = "the extension would not accept this file"
    end
end

-- Cuts from the framestore, in the shape the FFmpeg path produces, so everything
-- downstream -- the overview, thumbnails, markers, navigation, undo -- is untouched.
-- score is the jump as a percentage of the 64 bits available, which puts it on the same
-- 0..100 footing as the scdet score the rest of the script already reads.
function vpExtractCuts(IP)
    local s     = vpCutStateFor(IP)
    local store = (s and s.store) or (IP.filePath .. ".vpfs")
    local blob  = reaper.VP_Cuts(store, settings.cut_jump or 20,
                                 settings.cut_motion or 300, settings.cut_gap or 20)
    local out = {}
    if not blob or blob == "" or blob:sub(1, 1) ~= "C" then return out end

    local fps = reaper.VP_StoreFPS and reaper.VP_StoreFPS(store) or 0
    if not (fps > 0) then
        fps = (frames_per_second and frames_per_second > 0) and frames_per_second or 25
    end

    -- clipped to the stretch being analysed, which is what FFmpeg was given too
    local t0 = IP.item_area_to_analyze_start or 0
    local t1 = IP.item_area_to_analyze_length
               and (t0 + IP.item_area_to_analyze_length) or math.huge
    -- The fourth field is the timestamp the frame actually carries, which is the one to
    -- use: frame/fps is only right for constant-rate material whose rate was read
    -- correctly, and when it isn't, every cut slides and the late ones fall outside the
    -- window below and vanish. Older extensions emit three fields, so keep the division
    -- as the fallback rather than losing cuts to a version mismatch.
    for f, d, ms in blob:gmatch("K (%d+) (%d+) %d+ ?(%d*)") do
        local t = (ms ~= "" and tonumber(ms) / 1000) or (tonumber(f) / fps)
        if t >= t0 and t <= t1 then
            out[#out + 1] = { time = t, score = tonumber(d) / 64 * 100, mafd = tonumber(d) }
        end
    end
    return out
end

function get_cut_information(IP, detection_threshold)
    if cutMethodIsExtension() then
        return vpStartCutAnalysis(IP)
    end

    -- FFmpeg is the detector on this branch, and nothing guarantees a path for it any
    -- more: the startup prompt is gone, because the extension needs no setup and most
    -- people now never need FFmpeg at all. So ask here, which is the moment it is
    -- actually wanted, and stop with a plain message if there is still nothing -- rather
    -- than falling through to build a command line around a nil path, which is a script
    -- error in the middle of a button press.
    if not ensureFfmpegPath() then
        -- analyseStartTime is set by the button before this runs, and while it is set the
        -- refresh guard rebuilds every item's properties on every frame. It has to go.
        analyseStartTime, analyseEndTime = nil, nil
        analysing = false
        reaper.MB("Cut detection needs either the Video Cut Detection Editor extension or FFmpeg, and " ..
                  "neither was found.\n\n" ..
                  "The extension detects cuts and reads frames with nothing to install: " ..
                  "AVFoundation on macOS, Media Foundation on Windows. Otherwise, set an " ..
                  "FFmpeg path on the Settings page.",
                  "Cannot detect cuts", 0)
        return
    end

    local file_path = IP.filePath
    local cutTextFilePath = IP.cutTextFilePathRaw
    local start_time = IP.item_area_to_analyze_start
    local length = IP.item_area_to_analyze_length
    
    detection_threshold = detection_threshold and detection_threshold or (settings.extremeCutDetection and 0.01 or 0.1)
    
    local is_windows = package.config:sub(1, 1) == "\\"
    if is_windows then
        get_cut_information_win(file_path, cutTextFilePath, start_time, length, detection_threshold)
    else
        if fast then 
            get_cut_information_fast(file_path, cutTextFilePath, start_time, length, detection_threshold)
        else
            get_cut_information_mac(file_path, cutTextFilePath, start_time, length, detection_threshold)
        end
    end
end

function extract_cut_data(IP)  
    local cutTextFilePathRaw = IP.cutTextFilePathRaw 
    local start_time = IP.item_area_to_analyze_start
    local f = io.open(cutTextFilePathRaw)
    if not f then return nil, "Could not open file" end
    local results = {}
    
    local entry = {}
  
    for line in f:lines() do
      local frame, pts, time = line:match(
          "frame:(%d+)%s+pts:(%d+)%s+pts_time:([%d%.]+)"
      )
      if frame and pts and time then
          entry.frame = tonumber(frame)
          entry.pts   = tonumber(pts)
          entry.time  = tonumber(time) + start_time
      end
      
      local time = line:match("pts_time:(%S+)")
      if time then
          entry.time = tonumber(time) + start_time
          --reaper.ShowConsoleMsg(time .."\n")
      end
  
      local score = line:match("lavfi%.scene_score=(%S+)")
      
      if score then
        entry.score = 100 - tonumber(score) * 100
      end 
  
      -- Once we have all three, store and reset
      if entry.score and entry.time then
        --entry.color = settings.defaultColor
        table.insert(results, entry)
        entry = {}
      end
    end
  
    f:close()
    
    
    
    return results
end

-- Global throttling variable
local last_thumb_time = 0

local function createThumbnails_win(filePath, pngPath, itemStart, overwrite)
  -- Throttling to prevent potential load spam
  local now = reaper.time_precise()
  --if now - last_thumb_time < 0.2 then return false end
  last_thumb_time = now

  local is_windows = package.config:sub(1,1) == "\\"
  
  if overwrite or not reaper.file_exists(pngPath) then
    
    local ffmpeg_exec = ffmpeg_path:gsub('"', '') -- sanitize path
    local command = ""
    
    if is_windows then
        -- CD Strategy for Thumbnails (proven to fix FFMPEG path issues on Windows)
        -- Using ExecProcess (Hidden) instead of os.execute to prevent flickering
        
        -- Path normalization for CMD
        filePath = filePath:gsub("/", "\\")
        pngPath = pngPath:gsub("/", "\\")
        
        -- Extract folder and filename to CD into
        -- local work_dir, out_file = pngPath:match("(.*/)(.*)") -- this match needs forward slashes? No, we just converted.
        -- Regex for backslash is tricky. Let's use the one that worked before conversion or handle both.
        -- Actually, we just converted to backslashes. 
        local work_dir, out_file = pngPath:match("(.*\\)(.*)")
        
        if not work_dir then work_dir = ".\\" out_file = pngPath end
        
        -- Construct command: cmd /Q /C "cd /d "dir" & "ffmpeg" ... "outfile""
        local args =  ' -ss ' .. string.format("%.6f", itemStart) .. ' -y -i "'..filePath..'" -frames:v 1 "'..out_file ..'"'
        command = 'cmd.exe /Q /C "cd /d "' .. work_dir .. '" & "' .. ffmpeg_exec .. '"' .. args .. '" 2>&1'
        
    else
        -- Unix
        local args =  ' -ss ' .. string.format("%.6f", itemStart) .. ' -y -i "'..filePath..'" -frames:v 1 "'..pngPath ..'"' 
        command = '"' .. ffmpeg_exec .. '"' .. args .. ' 2>&1'
    end
    
    -- ExecProcess returns exit code (integer) and output (string).
    local ret_code, ret_output = reaper.ExecProcess(command, 0) -- Timeout 0 to avoid UI freeze. FFMPEG is fast.
    
    -- We can't immediately check file_exists if timeout is 0 (async-ish).
    -- But if we don't wait, the loop will retry.
    -- Let's give it a tiny budget? 100ms? 
    -- Or just rely on the next loop iteration to pick it up.
    -- If we use timeout 0, ret_output might be empty.
    -- Let's try 200ms constant wait. Ideally shouldn't lag much.
    ret_code, ret_output = reaper.ExecProcess(command, 200)
    
    if not reaper.file_exists(pngPath) then
        -- reaper.ShowConsoleMsg("\n--- THUMBNAIL ERROR ---\n")
        -- reaper.ShowConsoleMsg("CMD: " .. command .. "\n")
        -- reaper.ShowConsoleMsg("OUTPUT:\n" .. tostring(ret_output) .. "\n")
        
        -- Fallback to os.execute (visible) just to see if it works as a backup? 
        -- No, let's just debug direct first.
    end
    
    return ret_code
  end
end


local function createThumbnails_mac(filePath, pngPath, itemStart, overwrite, background, forceAsync)
  --local pngName = pngName(filePath,itemStart)
  --local pngPath = join_paths(filePath, pngName)
  if overwrite or not reaper.file_exists(pngPath) then 
    
    -- Build FFmpeg arguments
    local args = {}
    
    table.insert(args, '"' .. ffmpeg_path .. '"') 
    if background then table.insert(args, "-hide_banner") end
    
    table.insert(args, "-ss " .. string.format("%.6f", itemStart)) 
    table.insert(args, '-y')
    table.insert(args, '-i "' .. (filePath) .. '"')
    table.insert(args, '-frames:v 1')
    table.insert(args, '"' .. (pngPath) .. '"') 
    
    if background then table.insert(args, "-f null -") end
    
    local command = table.concat(args, " ")
    
    --reaper.ExecProcess(cmd, 0)
    --reaper.ExecProcess(cmd, 200)
    reaper.ExecProcess(command, -1) 
    --return io.popen(cmd, "r")
  end
end

-- (createThumbnails_windows removed: createThumbnails dispatches to
-- createThumbnails_win, which runs ffmpeg hidden through ExecProcess. The old
-- duplicate used io.popen, so had it ever been wired up it would have put a console
-- window on screen for every thumbnail.)


-- One frame to a file, through the extension's already-open decoder. The FFmpeg route
-- spawns a subprocess, opens the file, seeks and tears everything down again for each
-- thumbnail, and these are generated in bulk after every analysis.
--
-- Returns false if the extension cannot do it, so the caller falls back rather than
-- quietly producing nothing.
-- True while either preview is showing a stand-in for a frame still being decoded.
-- Both handles are asked: the two sides of the preview decode independently, so one can
-- be settled while the other is not.
function vpFrameIsPending(IP)
    if not reaper.VP_FramePending or not IP or not IP.filePath then return false end
    local a = vpGetHandleCut(IP.filePath)
    local b = vpGetHandle(IP.filePath)
    if a and reaper.VP_FramePending(a) == 1 then return true end
    if b and reaper.VP_FramePending(b) == 1 then return true end
    return false
end

-- A message shown briefly over the thumbnails, in place of a dialog.
--
-- For telling someone an action had nothing to do -- every cut already named, no cuts
-- found -- which is worth saying and not worth a modal they have to dismiss before
-- carrying on. Over the pictures because that is where the eye already is, and gone
-- again on its own.
TRANSIENT_SECONDS = 2
transientMessage  = nil        -- { text = ..., at = time_precise when set }

function setTransientMessage(text)
    transientMessage = { text = text, at = time_precise }
end

-- Once a frame, after the keys have been read.
function updateTransientMessage()
    local m = transientMessage
    if not m then return end
    -- Never on the frame it was set: the keystroke or click that caused the message is
    -- itself an action and would clear it before it was ever drawn. Belt and braces as
    -- things stand, since every caller sets a message while the interface draws, which
    -- is after this runs -- but it is the invariant that matters, not the current order
    -- of two lines a thousand apart.
    if time_precise <= m.at then return end
    if isMouseClick or isAnyKeyPressed or (time_precise - m.at) > TRANSIENT_SECONDS then
        transientMessage = nil
    end
end

-- Drawn across both pictures, centred, over a panel dark enough to read against any
-- frame. Fades over the last half second so it leaves rather than vanishes.
function drawTransientMessage(x, y, w, h)
    local m = transientMessage
    if not m then return end
    local fade = math.min(1.0, math.max(0.0,
                     (TRANSIENT_SECONDS - (time_precise - m.at)) / 0.5))
    local tw, th = reaper.ImGui_CalcTextSize(ctx, m.text)
    local cx = x + (w - tw) / 2
    local cy = y + (h - th) / 2
    local pad = 10
    -- Alpha composed here rather than through the withAlpha helper: that one is a local
    -- declared further down the file, so from up here it resolves as a global and is
    -- nil at call time. Colours are 0xRRGGBBAA, so the alpha is the low byte.
    local function fadedTo(col, alpha)
        return (col // 256) * 256 + math.floor(alpha * fade)
    end

    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    reaper.ImGui_DrawList_AddRectFilled(dl, cx - pad, cy - pad, cx + tw + pad, cy + th + pad,
                                        fadedTo(0x000000FF, 0xDD), 6)
    reaper.ImGui_DrawList_AddText(dl, cx, cy, fadedTo(colorWhite, 0xFF), m.text)
end

-- Whether the right-hand preview follows the playhead during playback, or stays on the
-- selected cut. On is the default: watching the video play is usually the point. Off is
-- for comparing a cut against what is actually under the playhead, where a picture that
-- keeps moving is no use.
function previewShowsLiveVideo()
    return settings.previewLiveVideo ~= false
end

function vpExtractToPng(filePath, pngPath, atTime)
    if not vp_available or not reaper.VP_ExtractFrame then return false end
    local h = vpGetHandle(filePath)
    if not h then return false end
    local w, hh = vpPreviewWH()
    return reaper.VP_ExtractFrame(h, atTime, w, hh, pngPath) == 1
end

local function createThumbnails(filePath, pngPath, itemStart, overwrite, background, forceAsync)
    if overwrite or not reaper.file_exists(pngPath) then
        if vpExtractToPng(filePath, pngPath, itemStart) then return end
    end
    if not ffmpeg_path then return end     -- nothing left to fall back to
    local is_windows = seperator == "\\"
    if not is_windows then
        createThumbnails_mac(filePath, pngPath, itemStart, overwrite)
    else
        createThumbnails_win(filePath, pngPath, itemStart, overwrite)
    end
end


-- Cut thumbnails are PNGs named after their time in the file, and nothing in the name
-- says which build decoded them -- so a thumbnail written by a version that picked the
-- wrong frame is trusted for good, and a fix to the decoder changes nothing on screen.
-- A marker in the folder records which generation wrote them; when it does not match,
-- the existing files are regenerated once instead of believed.
local THUMB_GENERATION = "2"
-- 2  (script 0.4.3 / extension 1.3.2) frames are chosen nearest to the time asked for,
--    and on Windows a seek no longer returns the keyframe before it
-- 1  everything earlier

local thumbGenHandled = {}

local function thumbnailsAreStale(directory)
    if thumbGenHandled[directory] then return false end
    thumbGenHandled[directory] = true        -- once per folder per session

    local marker = directory .. "thumbnail_generation.txt"
    local f = io.open(marker, "r")
    local have = f and f:read("*l") or nil
    if f then f:close() end
    if have == THUMB_GENERATION then return false end

    local w = io.open(marker, "w")
    if w then w:write(THUMB_GENERATION) w:close() end
    return true
end

function generateThumbnailsForCuts(IP, onlySpecific, secondary)
    local directory = IP.thumbnailPath
    local fileName = IP.fileName
    if not IP or not fileName then
        reaper.ShowMessageBox("Cannot generate thumbnails: Missing file information (Save the project or select a valid video item).", "Error", 0)
        return
    end

    if not reaper.file_exists(directory) then
        reaper.RecursiveCreateDirectory(directory,0)
        IP.thumbnailPath_exist = true
    end
    
    if not secondary then 
        generationQueue = {} -- Clear previous queue
    end

    -- Set once per folder per session, and then every thumbnail is rebuilt rather than
    -- reused, however many of them already exist.
    local stale = thumbnailsAreStale(directory)
    
    for _, c in ipairs(IP.cuts_making_threashold) do 
        
         if not c.exclude then 
             local cut = IP.cut_data[c.index]
             if cut then 
                 if not cut.pngPath then
                      local time_seconds_rounded = cut.time -- roundToFrame(cut.time, frames_per_second)
                      cut.pngPath = directory .. IP.fileName .. "_" .. math.floor(time_seconds_rounded * 1000 + 0.5) .. "ms.png" 
                 end
                 if not cut.pngPath_frame_before then
                      local time_seconds_rounded = cut.time -- roundToFrame(cut.time, frames_per_second)
                      local oneFrameEarlier = time_seconds_rounded - (1 / frames_per_second)
                      cut.pngPath_frame_before = directory .. fileName .. "_" .. math.floor(oneFrameEarlier * 1000 + 0.5) .. "ms.png"
                      cut.time_frame_before = oneFrameEarlier
                 end
                 
                 if stale or not reaper.file_exists(cut.pngPath) then 
                     -- Add tasks to queue instead of processing immediately
                     table.insert(generationQueue, {
                        filePath = IP.filePath, 
                        pngPath = cut.pngPath, 
                        time = cut.time, 
                        overwrite = true
                     })
                 end
                 if not onlySpecific then 
                    
                    if stale or not reaper.file_exists(cut.pngPath_frame_before) then 
                       table.insert(generationQueue, {
                          filePath = IP.filePath, 
                          pngPath = cut.pngPath_frame_before, 
                          time = cut.time_frame_before, 
                          overwrite = true
                       })
                    end
                end
             end
         end
    end
    totalGenerationCount = #generationQueue
    genratingThumbNails = true 
    
end

function processGenerationQueue()
    if #generationQueue > 0 then
        local task = table.remove(generationQueue, 1)
        local usedVP = false
        if vp_available and reaper.VP_ExtractFrame then
            local h = vpGetHandle(task.filePath)
            if h then
                if task.overwrite or not reaper.file_exists(task.pngPath) then
                    reaper.VP_ExtractFrame(h, task.time, 640, 360, task.pngPath)
                end
                usedVP = true
            end
        end
        if not usedVP then
            createThumbnails(task.filePath, task.pngPath, task.time, task.overwrite)
        end
        return true -- Processed something
    else
        if genratingThumbNails then
            genratingThumbNails = false
            -- Optional: Show completion message?
        end
        return false -- Nothing to process
    end
end


-- AI Description Queue
descriptionQueue = {}
totalDescriptionCount = 0
generatingDescriptions = false
descriptionLastError = nil

-- Video comparison state
ollamaStatus = "unknown" -- "unknown","not_installed","not_running","model_missing","ready"
ollamaInstalledModels = {}  -- full model names that are pulled, e.g. {["llava:7b"]=true, ["llava:13b"]=true}
ollamaModelCustomInput = ""

-- Returns true if modelName is in ollamaInstalledModels.
-- Exact match first; for tag-less names (e.g. "llava") also matches any "llava:*" variant.
function ollamaModelInstalled(modelName)
    if ollamaInstalledModels[modelName] then return true end
    if not modelName:find(":") then
        for k in pairs(ollamaInstalledModels) do
            if k:match("^([^:]+)") == modelName then return true end
        end
    end
    return false
end

local function get_png_base64(path)
    if not reaper.file_exists(path) then return nil end
    if is_windows then
        local tmpB64 = path .. ".b64tmp"
        -- Hidden, and without the redirect: os.execute gets a console window on
        -- Windows exactly as io.popen does, and this runs once per cut described.
        shellRead('certutil -encode "' .. path .. '" "' .. tmpB64 .. '"', 10000)
        local f = io.open(tmpB64, "r")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        os.remove(tmpB64)
        content = content:gsub("-----[^\r\n]+\r?\n", "")
        content = content:gsub("[\r\n]", "")
        return content
    else
        local handle = io.popen('base64 -i "' .. path .. '"')
        if not handle then return nil end
        local result = handle:read("*a")
        handle:close()
        return result:gsub("[\n\r]", "")
    end
end

-- Queues cuts on the timeline for a description. Shared by the button in the Extra
-- popup and by shift+D, so the two cannot drift apart. Returns true when work was
-- actually queued.
--
-- Cuts that already carry a name are left alone unless `overwrite` says otherwise. A
-- name is either one somebody typed or one a previous run fetched, and either way it is
-- worth more than the one about to replace it -- a model run is not deterministic, so
-- describing everything a second time would quietly reword the lot. An unnamed cut has
-- `name` nil and shows as "Cut N", which is what makes the two cases distinguishable.
function describeAllCuts(IP, overwrite)
    if not IP or not IP.filePath then
        setTransientMessage("No video file found")
        return false
    end
    descriptionQueue = {}
    descriptionLastError = nil
    local named, total = 0, 0
    for i, c in ipairs(IP.cuts_making_threashold or {}) do
        local cut = IP.cut_data and IP.cut_data[c.index]
        if not c.exclude and cut then
            total = total + 1
            local hasName = cut.name and cut.name ~= ""
            if hasName then named = named + 1 end
            if overwrite or not hasName then
                table.insert(descriptionQueue, { cutIndex = c.index, filePath = IP.filePath })
            end
        end
    end
    totalDescriptionCount = #descriptionQueue
    if totalDescriptionCount == 0 then
        -- Said over the thumbnails rather than in a dialog: there is nothing to decide,
        -- and a modal for "nothing to do" costs a click to get back to where you were.
        if total == 0 then
            setTransientMessage("No cuts detected on the timeline")
        else
            setTransientMessage(
                (named == 1 and "The cut is" or "All " .. named .. " cuts are") ..
                " already named  -  hold " .. MOD_ALT .. " to replace them")
        end
        return false
    end
    undo_redo.save_undo(IP.cut_data)
    generatingDescriptions = true
    popupItemProperties = IP
    return true
end

function processDescriptionQueue(IP)
    if not generatingDescriptions then return end
    if not IP then
        descriptionQueue = {}
        generatingDescriptions = false
        return
    end
    if #descriptionQueue == 0 then
        generatingDescriptions = false
        return
    end

    local task = table.remove(descriptionQueue, 1)
    local cut = IP.cut_data and IP.cut_data[task.cutIndex]

    if not cut then return end

    local function abortWithError(msg)
        descriptionLastError = msg
        descriptionQueue = {}
        generatingDescriptions = false
    end

    -- The frame to describe is the one ON the cut -- the right-hand thumbnail, the first
    -- frame of the incoming shot -- not the last frame of the one before it.
    --
    -- Two things were getting that wrong. The cut time from the detector does not have
    -- to sit on the frame grid, and the decoder is frame-accurate with zero tolerance,
    -- so asking for a time a fraction before a boundary returns the frame before it:
    -- the outgoing shot. The thumbnails never had that problem because they are built
    -- at roundToFrame(cut.time), which snaps onto the grid first.
    --
    -- So the cached thumbnail is used where there is one. That is not just cheaper than
    -- decoding again -- it is the only way to be certain the label describes the picture
    -- actually on screen, rather than a frame that merely ought to be the same one.
    local describeTime = roundToFrame(cut.time, frames_per_second)
    local framePng, isCachedThumb

    if cut.pngPath and reaper.file_exists(cut.pngPath) then
        framePng, isCachedThumb = cut.pngPath, true
    else
        framePng = script_path .. "Helpers" .. seperator .. "tmp_desc_frame.png"
        os.remove(framePng)

        -- The extension's decoder first, since it is already open on this file; FFmpeg
        -- only if it cannot be used.
        if not vpExtractToPng(task.filePath, framePng, describeTime) then
            if not ffmpeg_path then
                abortWithError("needs either the Video Cut Detection Editor extension or FFmpeg to read a frame")
                return
            end
            local ffmpegExec = ffmpeg_path:gsub('"', '')
            -- No 2>&1: shellRead runs this hidden, and a shell is what puts a console
            -- window on screen. Describing a run of cuts would flash one per cut.
            local ffmpegCmd = '"' .. ffmpegExec .. '" -ss ' .. string.format("%.6f", describeTime)
                .. ' -y -i "' .. task.filePath .. '" -frames:v 1 "' .. framePng .. '"'
            shellRead(ffmpegCmd, 20000)
        end

        if not reaper.file_exists(framePng) then
            abortWithError("could not extract a frame at " .. string.format("%.2f", describeTime) .. "s")
            return
        end
    end

    local name

    local b64 = get_png_base64(framePng)
    -- Only the temporary one is deleted: the other is the thumbnail the UI is drawing.
    if not isCachedThumb then os.remove(framePng) end
    if not b64 or b64 == "" then
        abortWithError("Failed to base64-encode the extracted frame.")
        return
    end

    local host = settings.ollama_host or "localhost:11434"
    local prompt = "Label this video frame in 2-4 words. Be specific and visual — describe what you actually see: the subject, action, or setting. Examples of good labels: Hand closeup, Woman in bed, Teeth closeup, Man talking, City street, Door opening, Coffee cup. Reply with ONLY the label. No punctuation, no explanation, no sentence."
    local requestJson = '{"model":"' .. (settings.ollama_model or "llava") .. '","prompt":"' .. prompt .. '","images":["' .. b64 .. '"],"stream":false}'

    local tmpReq = script_path .. "Helpers" .. seperator .. "tmp_desc_req.json"
    local f = io.open(tmpReq, "w")
    if not f then abortWithError("Could not write temp request file.") return end
    f:write(requestJson)
    f:close()

    local curl_cmd = 'curl -s --max-time 30 -H "content-type: application/json" -d @"' .. tmpReq .. '" http://' .. host .. '/api/generate'
    local content = shellRead(curl_cmd, 31000)
    os.remove(tmpReq)

    if not content or content == "" then
        abortWithError("No response from Ollama at " .. host .. ". Is it running? Check Settings > Ollama status.")
        return
    end

    -- No console dump of the raw reply: describing a run of cuts makes one request per
    -- cut, so it filled the console with JSON nobody had asked to read. What matters
    -- from a bad reply already reaches the UI through abortWithError below.
    -- decodeFromJson returns nil plus a reason on malformed input -- a proxy or a
    -- wrong port answers with HTML -- and the branches below already treat nil as an
    -- unexpected response.
    local response = json.decodeFromJson(content)
    local parsedDescriptions = {}
    -- Asked for one label, a model will sometimes answer with several lines, and often
    -- with the same label more than once -- restated, re-capitalised, or with a full
    -- stop added. The list is what the Describe button cycles through, so three copies
    -- of one answer makes that button look broken.
    --
    -- Compared on letters and digits only, lowercased, so "Hand closeup",
    -- "hand closeup." and "Hand Closeup" count as the same answer. The first spelling
    -- is the one kept, which is also the one that becomes the cut's name.
    local seenDescription = {}
    if response and type(response.response) == "string" and response.response ~= "" then
        local raw = response.response
        for line in (raw .. "\n"):gmatch("([^\n\r]*)\r?\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            line = line:gsub("^%*+%s*", "")
            line = line:gsub("^%d+[%.%d]*[%.%)%s]*", ""):gsub("^%s+", "")
            local afterColon = line:match("^[%u][%a%s]+:%s*(.+)$")
            if afterColon then
                line = afterColon:gsub("^%s+", ""):gsub("%s+$", "")
            elseif line:match("^[%u][%a%s]+:$") then
                line = ""
            end
            local lettersOnly = line:gsub("[^%a]", "")
            if line ~= "" and lettersOnly ~= "" then
                -- parenthesised: gsub also returns a count, and letting that through
                -- would make this two values rather than one key
                local key = (line:lower():gsub("[^%w]", ""))
                if not seenDescription[key] then
                    seenDescription[key] = true
                    table.insert(parsedDescriptions, line)
                end
            end
        end
        if #parsedDescriptions > 0 then
            name = parsedDescriptions[1]
        end
    elseif response and response.error then
        abortWithError("Ollama error: " .. tostring(response.error))
        return
    elseif not response or (response.response == nil and not response.done) then
        abortWithError("Unexpected Ollama response: " .. content:sub(1, 120))
        return
    end

    if name and name ~= "" then
        cut.name = name
        -- Store all parsed descriptions; cycle with Describe button
        cut.descriptions = (#parsedDescriptions > 0) and parsedDescriptions or { name }
        cut.descriptionIdx = 0
        cut.descriptionCycleComplete = false
        updateCutDataFile(IP)
    end

    if #descriptionQueue == 0 then
        generatingDescriptions = false
    end
end

-- ============================================================
-- Video comparison (SSIM-based cut matching)
-- ============================================================


-- Parse the blob VP_Match returns:
--   F <framesA> <framesB> <fpsA> <fpsB> <runCount>
--   R <aStart> <bStart> <len> <meanHam>     (ascending and non-overlapping in B)
function vpParseMatch(blob)
    if not blob or blob == "" then return nil, "no result from VP_Match" end
    local e = blob:match("^E (.+)")
    if e then return nil, e end

    local info, runs = {}, {}
    for line in blob:gmatch("[^\n]+") do
        local tag = line:sub(1, 1)
        if tag == "F" then
            local fa, fb, pa, pb = line:match("^F (%d+) (%d+) ([%d.]+) ([%d.]+)")
            if fa then
                info.framesA = tonumber(fa); info.framesB = tonumber(fb)
                info.fpsA    = tonumber(pa); info.fpsB    = tonumber(pb)
            end
        elseif tag == "R" then
            local a, b, l, h = line:match("^R (%d+) (%d+) (%d+) ([%d.]+)")
            if a then
                runs[#runs + 1] = {
                    aStart = tonumber(a), bStart = tonumber(b),
                    len = tonumber(l), meanHam = tonumber(h),
                }
            end
        end
    end
    if not info.framesA then return nil, "malformed VP_Match result" end
    info.runs = runs
    return info
end

-- Turn matched runs into the change list, by reading the gaps between them.
--
-- The matcher only says which stretches correspond; every edit is implied by what
-- sits between those stretches. Walking both versions with a cursor each:
--   old material skipped, new material covered  -> removed
--   new material appearing, old material intact -> added
--   both sides skipped at once                  -> swapped
--   a run reaching back behind the old cursor   -> moved (can't be a plain deletion)
--
-- Deliberately structural: these come from frame correspondence alone. Naming a
-- removal a "trim" needs shot boundaries, which is the cut data's job, so that
-- refinement belongs in a later pass rather than guessed at here.
function vpClassifyChanges(m)
    local runs    = m.runs or {}
    local framesA = m.framesA or 0
    local framesB = m.framesB or 0

    local changes = {}
    local function emit(t, aStart, aLen, bStart, bLen, extra)
        local c = { type = t, aStart = aStart, aLen = aLen, bStart = bStart, bLen = bLen }
        if extra then for k, v in pairs(extra) do c[k] = v end end
        changes[#changes + 1] = c
    end

    -- Which stretches of the old cut does some run actually consume? This has to be
    -- judged across all runs at once: material skipped at one point may simply turn up
    -- later, and a sequential walk would then report a relocated block as deleted *and*
    -- moved at the same time.
    local spans = {}
    for _, r in ipairs(runs) do spans[#spans + 1] = { r.aStart, r.aStart + r.len } end
    table.sort(spans, function(x, y) return x[1] < y[1] end)

    local aGaps, reach = {}, 0
    for _, s in ipairs(spans) do
        if s[1] > reach then aGaps[#aGaps + 1] = { reach, s[1] } end
        reach = math.max(reach, s[2])
    end
    if framesA > reach then aGaps[#aGaps + 1] = { reach, framesA } end

    -- Place each removal where it would have played: directly after the run whose old
    -- material runs up to it.
    local removalAt = {}
    for _, g in ipairs(aGaps) do
        local bPos, bestEnd = 0, -1
        for _, r in ipairs(runs) do
            local aEnd = r.aStart + r.len
            if aEnd <= g[1] and aEnd > bestEnd then
                bestEnd = aEnd
                bPos    = r.bStart + r.len
            end
        end
        local acc = removalAt[bPos]
        if acc then
            acc.aStart = math.min(acc.aStart, g[1])
            acc.aLen   = acc.aLen + (g[2] - g[1])
        else
            removalAt[bPos] = { aStart = g[1], aLen = g[2] - g[1] }
        end
    end

    local function emitGap(bPos, bGap, aNext)
        local rem = removalAt[bPos]
        removalAt[bPos] = nil
        if rem and bGap > 0 then
            -- old material drops out exactly where new material arrives: one
            -- replacement, not an independent delete and insert
            emit("swapped", rem.aStart, rem.aLen, bPos, bGap)
        elseif rem then
            emit("removed", rem.aStart, rem.aLen, bPos, 0)
        elseif bGap > 0 then
            emit("added", aNext, 0, bPos, bGap)
        end
    end

    local bCursor, aReach = 0, 0
    for _, r in ipairs(runs) do
        emitGap(bCursor, r.bStart - bCursor, r.aStart)
        -- a run reaching back behind everything already consumed cannot be explained
        -- by deletion alone, so the block was relocated
        emit(r.aStart < aReach and "moved" or "matched",
             r.aStart, r.len, r.bStart, r.len, { meanHam = r.meanHam })
        bCursor = r.bStart + r.len
        aReach  = math.max(aReach, r.aStart + r.len)
    end
    emitGap(bCursor, framesB - bCursor, framesA)

    -- anything that could not be anchored to a run junction
    for bPos, rem in pairs(removalAt) do
        emit("removed", rem.aStart, rem.aLen, bPos, 0)
    end

    return changes
end

-- Fraction of the new cut that is not carried over unchanged from the old one.
function vpDamage(m, changes)
    if not m.framesB or m.framesB == 0 then return 0 end
    local kept = 0
    for _, c in ipairs(changes) do
        if c.type == "matched" then kept = kept + c.bLen end
    end
    return 1 - (kept / m.framesB)
end

-- ---------------------------------------------------------------------------
-- Framestore conform
-- ---------------------------------------------------------------------------
-- Frame-accurate comparison of two versions, built on VP_Analyze + VP_Match. This
-- runs alongside the older SSIM cut comparison rather than replacing it, so the two
-- can be judged against each other on real footage before anything is retired.

conformJobA,   conformJobB   = nil, nil
conformAudJobA, conformAudJobB = nil, nil
conformAudStoreA, conformAudStoreB = nil, nil
conformStoreA, conformStoreB = nil, nil
conformResult      = nil   -- { info, changes, damage, matchMs }
conformStatus      = nil
conformError       = nil
conformSelectedIdx = nil
conformIP1, conformIP2 = nil, nil

conformColors = {
    matched = 0x4A7A52FF,   -- carried over unchanged
    moved   = 0x7A5FBEFF,   -- same material, relocated
    added   = 0xE5C07BFF,   -- new material with no source
    removed = 0xBE5046FF,   -- gone from the new cut
    swapped = 0xD98C40FF,   -- replaced by something else
}

local function withAlpha(col, a)
    return (col // 256) * 256 + a
end

function conformTC(frame, fps)
    if not fps or fps <= 0 then return "--:--:--:--" end
    local s = math.floor(frame / fps)
    return string.format("%02d:%02d:%02d:%02d",
        math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60, math.floor(frame % fps))
end

function conformAudioStorePath(IP)
    local src = conformAudioFor(IP)
    if not src or src == "" then src = IP and IP.filePath end
    if not src or src == "" then return nil end
    return src .. ".vpas"
end

function conformStorePath(IP)
    if not IP or not IP.filePath or IP.filePath == "" then return nil end
    return IP.filePath .. ".vpfs"
end

-- cur_pos_in_item is computed as (project time - item_pos + item_offset), so this
-- inverts that to put a frame of the source file back on the project timeline.
function conformFrameToTime(IP, frame, fps)
    if not IP or not fps or fps <= 0 then return nil end
    return (frame / fps) - (IP.item_offset or 0) + (IP.item_pos or 0)
end

-- keepResult: leave the existing overview on screen while the new one is worked out.
-- Used when only a threshold changed, so the window does not collapse to a status line
-- and spring back -- which, since the window is sized to its content every frame, reads
-- as the whole UI flickering.
function startConform(IP1, IP2, keepResult)
    if not keepResult then
        conformResult, conformSelectedIdx = nil, nil
        -- A fresh comparison replaces everything the stack described, so its steps
        -- would restore runs that belong to a result that no longer exists.
        conformClearUndo()
    end
    conformError = nil
    conformIP1, conformIP2 = IP1, IP2

    if not vp_available or not reaper.VP_Analyze then
        conformError = "Video Cut Detection Editor extension not loaded (needs VP_Analyze) — install it from ReaPack and restart REAPER."
        return
    end
    conformStoreA, conformStoreB = conformStorePath(IP1), conformStorePath(IP2)
    if not conformStoreA or not conformStoreB then
        conformError = "Both items need a video file on disk."
        return
    end
    if conformStoreA == conformStoreB then
        conformError = "Both items point at the same file."
        return
    end

    -- force=0: a store already matching the file's size and mtime is reused, so the
    -- decode cost is only paid the first time a version is seen.
    conformJobA = reaper.VP_Analyze(IP1.filePath, conformStoreA, 0)
    conformJobB = reaper.VP_Analyze(IP2.filePath, conformStoreB, 0)
    if conformJobA == 0 or conformJobB == 0 then
        conformError = "VP_Analyze would not accept these files."
        conformJobA, conformJobB = nil, nil
        return
    end

    conformAudJobA, conformAudJobB = nil, nil
    if settings.conform_use_audio and reaper.VP_AnalyzeAudio then
        conformAudStoreA = conformAudioStorePath(IP1)
        conformAudStoreB = conformAudioStorePath(IP2)
        local sA = conformAudioSource(IP1)
        local sB = conformAudioSource(IP2)
        if conformAudStoreA and conformAudStoreB and conformAudStoreA ~= conformAudStoreB then
            local a = reaper.VP_AnalyzeAudio(sA, conformAudStoreA, 0)
            local b = reaper.VP_AnalyzeAudio(sB, conformAudStoreB, 0)
            if a ~= 0 and b ~= 0 then
                conformAudJobA, conformAudJobB = a, b
            else
                if a ~= 0 then reaper.VP_AudioRelease(a) end
                if b ~= 0 then reaper.VP_AudioRelease(b) end
            end
        end
    end
    conformStatus = "Analysing..."
end

-- The matching stage on its own. Both stores already exist by the time this runs, so it
-- is pure computation -- tens of milliseconds for a twenty minute pair -- and can go
-- synchronously. Factored out of processConform so that changing a threshold re-runs
-- just this, without restarting analysis or clearing the screen.
-- A matched run's confidence as a percentage. meanHam is a Hamming distance in bits of
-- 64: genuine picture matches sit at 0.2-0.6, sound near 8, and unrelated material near
-- 32. 16 is taken as the floor because past a quarter of the bits a "match" carries no
-- information, so that is 0% and exact is 100%.
function conformRunConfidence(r)
    local h = r.meanHam or 0
    local c = 100 * (1 - h / 16)
    if c < 0 then return 0 end
    if c > 100 then return 100 end
    return c
end

function conformBuildResult(withAudio)
    local t0   = reaper.time_precise()
    local blob = reaper.VP_Match(conformStoreA, conformStoreB,
                                 settings.conform_ham or 4,
                                 settings.conform_min_run or 12)
    local m, err = vpParseMatch(blob)
    if not m then return nil, "Match failed: " .. tostring(err) end

    local audioAdded = 0
    -- Sound is matched by the same code on the same kind of store; only the unit of an
    -- index differs, hops rather than frames.
    if withAudio and conformAudStoreA and conformAudStoreB then
        local ablob = reaper.VP_Match(conformAudStoreA, conformAudStoreB,
                                      settings.conform_audio_ham or 8,
                                      settings.conform_audio_min_run or 100)
        local am = vpParseMatch(ablob)
        local hz = reaper.VP_AudioRate(conformAudStoreA)
        if am and hz and hz > 0 then
            local toFrames = ((m.fpsB > 0) and m.fpsB or 25) / hz
            m.runs, audioAdded = vpMergeAudioRuns(m.runs, am.runs, toFrames,
                                    m.framesA, m.framesB,
                                    settings.conform_min_run or 12)
        end
    end

    -- Confidence filter. meanHam is a distance, so it runs the other way from a
    -- confidence: 0 bits apart is certain, and past about a quarter of the 64 bits
    -- "still matching" stops meaning anything. Runs below the bar are dropped before
    -- classification, so the change list and the damage figure describe what is left
    -- rather than quietly including matches the user has rejected.
    local minConf = settings.conform_min_conf or 0
    if minConf > 0 then
        local kept = {}
        for _, r in ipairs(m.runs) do
            if conformRunConfidence(r) >= minConf then kept[#kept + 1] = r end
        end
        m.runs = kept
    end

    local changes = vpClassifyChanges(m)
    return {
        info       = m,
        changes    = changes,
        damage     = vpDamage(m, changes),
        matchMs    = (reaper.time_precise() - t0) * 1000,
        audioAdded = audioAdded,
    }
end

-- Re-runs only the matching stage against the stores already on disk. Nothing is
-- cleared first, so the overview swaps to the new result in the same frame.
function conformRematch(IP1, IP2)
    -- A first analysis still running will pick up the new thresholds when it finishes
    if conformJobA or conformJobB then return end
    if not conformStoreA or not conformStoreB then return end

    local wantAudio = settings.conform_use_audio and reaper.VP_AnalyzeAudio ~= nil
    if wantAudio and not (conformAudStoreA and conformAudStoreB
                          and (reaper.VP_AudioRate(conformAudStoreA) or 0) > 0
                          and (reaper.VP_AudioRate(conformAudStoreB) or 0) > 0) then
        -- sound has just been switched on and has not been fingerprinted yet, so this
        -- one does need the analysis pass
        startConform(IP1, IP2, true)
        return
    end

    local r, err = conformBuildResult(wantAudio)
    if r then
        conformResult, conformError = r, nil
        conformTouchState()
        -- The old selection was an index into a list that no longer exists. Re-deriving
        -- it from the playhead keeps the highlight on the block you are actually looking
        -- at, rather than on whatever now happens to be in that slot.
        conformSelectAtPlayhead()
    else
        conformError = err
    end
end

-- Progress for one side, and what it is working on. Picture and sound run as separate
-- jobs, so the slower of the two is what that side is actually waiting for.
function conformSideProgress(side)
    local pic = (side == "old") and conformJobA or conformJobB
    local aud = (side == "old") and conformAudJobA or conformAudJobB
    local p, what
    if pic then
        p, what = reaper.VP_AnalyzeProgress(pic), "picture"
    end
    if aud then
        local ap = reaper.VP_AudioProgress(aud)
        if not p or ap < p then p, what = ap, "sound" end
    end
    if not p then return "done", "" end
    return string.format("%.0f%%", p * 100), what
end

-- Stops everything in flight and leaves no job behind. The stores being written are
-- abandoned rather than finished, so the next run starts over -- which is why the
-- button says so.
function conformCancel()
    if conformJobA then reaper.VP_AnalyzeCancel(conformJobA) end
    if conformJobB then reaper.VP_AnalyzeCancel(conformJobB) end
    if conformAudJobA then reaper.VP_AudioCancel(conformAudJobA) end
    if conformAudJobB then reaper.VP_AudioCancel(conformAudJobB) end
    if conformJobA then reaper.VP_AnalyzeRelease(conformJobA) end
    if conformJobB then reaper.VP_AnalyzeRelease(conformJobB) end
    if conformAudJobA then reaper.VP_AudioRelease(conformAudJobA) end
    if conformAudJobB then reaper.VP_AudioRelease(conformAudJobB) end
    conformJobA, conformJobB = nil, nil
    conformAudJobA, conformAudJobB = nil, nil
    conformStatus, conformError = nil, nil
end

function processConform()
    if not conformJobA or not conformJobB then return end

    local sA = reaper.VP_AnalyzeState(conformJobA)
    local sB = reaper.VP_AnalyzeState(conformJobB)
    local aA = conformAudJobA and reaper.VP_AudioState(conformAudJobA) or 1
    local aB = conformAudJobB and reaper.VP_AudioState(conformAudJobB) or 1
    if sA == 0 or sB == 0 or aA == 0 or aB == 0 then
        local line = string.format("Picture   old %d%%    new %d%%",
            math.floor(reaper.VP_AnalyzeProgress(conformJobA) * 100),
            math.floor(reaper.VP_AnalyzeProgress(conformJobB) * 100))
        if conformAudJobA then
            line = line .. string.format("        Sound   old %d%%    new %d%%",
                math.floor(reaper.VP_AudioProgress(conformAudJobA) * 100),
                math.floor(reaper.VP_AudioProgress(conformAudJobB) * 100))
        end
        conformStatus = line
        return
    end

    if sA == 2 or sB == 2 then
        conformError = "Analysis failed: " ..
            (sA == 2 and tostring(reaper.VP_AnalyzeError(conformJobA))
                      or tostring(reaper.VP_AnalyzeError(conformJobB)))
    else
        local r, err = conformBuildResult(conformAudJobA and aA == 1 and aB == 1)
        if r then conformResult = r else conformError = err end
        conformTouchState()
    end

    conformStatus = nil
    reaper.VP_AnalyzeRelease(conformJobA)
    reaper.VP_AnalyzeRelease(conformJobB)
    conformJobA, conformJobB = nil, nil
    if conformAudJobA then reaper.VP_AudioRelease(conformAudJobA) end
    if conformAudJobB then reaper.VP_AudioRelease(conformAudJobB) end
    conformAudJobA, conformAudJobB = nil, nil
end

-- ---------------------------------------------------------------------------
-- Conform transport
-- ---------------------------------------------------------------------------
-- The compare tab drives its own playhead instead of REAPER's. The two versions sit
-- at different places on the project timeline, and the whole point is to watch
-- corresponding moments side by side, which a single project playhead cannot express.
--
-- One side holds focus and carries the playhead; the other follows through the match
-- map. Inside a matched run that correspondence is exact. Outside one there is nothing
-- to read, so the unfocused side carries on from the end of the last run at the same
-- rate: scrubbing through inserted material keeps both previews moving instead of
-- freezing one, and the moment a run begins again the other side snaps to where that
-- run puts it.

-- Focus is one of four rows, in the order they are stacked on screen: the old items
-- lane, the old video, the new video, the new items lane. Up and down walk that list,
-- so which row is driving is the same as where you are looking.
--
-- Almost everything only cares which *version* is being driven, and the two lanes
-- belong to a version just as the two bars do -- hence conformFocusSide rather than
-- four branches at every call site. What the lanes change is what the arrows step
-- through: item edges instead of match blocks.
CONFORM_ROWS = { "laneOld", "old", "new", "laneNew" }

conformFocus     = "new"    -- "laneOld" | "old" | "new" | "laneNew"

function conformFocusSide()
    return (conformFocus == "new" or conformFocus == "laneNew") and "new" or "old"
end

function conformFocusIsLane()
    return conformFocus == "laneOld" or conformFocus == "laneNew"
end

-- The rows that currently exist: the lanes only when there are items in them.
function conformFocusRows()
    if #conformTracks == 0 then return { "old", "new" } end
    return CONFORM_ROWS
end

function conformFocusStep(dir)
    local rows = conformFocusRows()
    local at
    for i, r in ipairs(rows) do if r == conformFocus then at = i end end
    if not at then return conformFocus end
    local n = at + dir
    if n < 1 then n = 1 end
    if n > #rows then n = #rows end
    return rows[n]
end
conformPlayhead  = 0        -- frame within the focused version; fractional while playing
conformPlaying   = false
conformLastTick  = nil
conformScrubbing = nil      -- side being dragged, while the mouse is held
conformScrubFrom  = nil     -- mouse x at the press, to tell a click from a drag
conformScrubMoved = false
-- How far the mouse has to travel before a press counts as a scrub rather than a
-- click. Small, but not zero: a click always carries a pixel or two of movement.
CONFORM_SCRUB_SLOP = 3

-- Has this press turned into a scrub? A press on its own is "play from here" and
-- leaves playback running; moving the mouse makes it a scrub, which takes the playhead
-- over and so has to stop playback.
--
-- Latching, deliberately: once it is a drag it stays one for the rest of the press.
-- Without that, dragging away and coming back within the slop would quietly restart
-- playback halfway through a gesture.
function conformScrubBecameDrag(mouseX)
    if conformScrubMoved then return true end
    if not conformScrubFrom then return false end
    if math.abs(mouseX - conformScrubFrom) > CONFORM_SCRUB_SLOP then
        conformScrubMoved = true
    end
    return conformScrubMoved
end
conformImg       = { old = nil, new = nil }
conformImgPath   = { old = nil, new = nil }

function conformFrameCounts(IP1, IP2)
    local R = conformResult
    if R then return R.info.framesA, R.info.framesB, R.info.fpsA, R.info.fpsB end
    -- No match yet: the two versions still line up end to end so they can be played
    -- against each other untouched.
    local fps = (frames_per_second and frames_per_second > 0) and frames_per_second or 25
    local function nf(IP)
        if not IP or not IP.filePath or IP.filePath == "" or not vp_available then return 0 end
        local h = vpGetHandle(IP.filePath)
        local dur = h and reaper.VP_GetDuration(h) or 0
        return math.floor(dur * fps + 0.5)
    end
    return nf(IP1), nf(IP2), fps, fps
end

-- Returns the corresponding frame on the other side, and whether it came from a real
-- match rather than being carried forward past the end of one.
function conformMap(frame, fromNew)
    local R = conformResult
    if not R then return frame, false end
    local bestStart, bestRun
    for _, r in ipairs(R.info.runs) do
        local fs = fromNew and r.bStart or r.aStart
        if frame >= fs and frame < fs + r.len then
            local os = fromNew and r.aStart or r.bStart
            return os + (frame - fs), true
        end
        if fs <= frame and (bestStart == nil or fs > bestStart) then
            bestStart, bestRun = fs, r
        end
    end
    if bestRun then
        local fe = (fromNew and bestRun.bStart or bestRun.aStart) + bestRun.len
        local oe = (fromNew and bestRun.aStart or bestRun.bStart) + bestRun.len
        return oe + (frame - fe), false
    end
    return frame, false
end

local function conformClamp(v, count)
    if count <= 0 then return 0 end
    if v < 0 then return 0 end
    if v > count - 1 then return count - 1 end
    return v
end

function conformPositions(framesA, framesB)
    local oldF, newF, matched
    if conformFocusSide() == "new" then
        newF = conformClamp(conformPlayhead, framesB)
        oldF, matched = conformMap(math.floor(newF), true)
        oldF = conformClamp(oldF, framesA)
    else
        oldF = conformClamp(conformPlayhead, framesA)
        newF, matched = conformMap(math.floor(oldF), false)
        newF = conformClamp(newF, framesB)
    end
    return math.floor(oldF), math.floor(newF), matched
end

-- ---------------------------------------------------------------------------
-- Separate audio per version
-- ---------------------------------------------------------------------------
-- A cut is often delivered with its audio as its own export, so the sound to match on
-- is not necessarily the one muxed into the video. Recorded per video path.


-- A DragInt that the wheel also drives while hovered. Dragging a 1-to-16 range through
-- a few pixels is fiddly, and these two get nudged a lot while judging a match.
-- Returns true only when the stored value actually moved.
conformWheelAccum = {}

function conformDragSetting(id, fmt, key, def, lo, hi, speed)
    reaper.ImGui_SetNextItemWidth(ctx, 82)
    local cur    = settings[key] or def
    local ch, v  = reaper.ImGui_DragInt(ctx, id, cur, speed, lo, hi, fmt)
    if reaper.ImGui_IsItemHovered(ctx) then
        if isOptionDown and isMouseClick then
            -- Applied after the slider has drawn, so the value jump ImGui already made
            -- from that same click is simply overwritten in the same frame.
            v, ch = def, true
            conformWheelAccum[key] = 0
        else
            -- Accumulated rather than taken by sign. A mouse notch reports 1.0 and
            -- steps once; a trackpad reports fractions over many frames, and stepping
            -- on each of those would run through the whole range in a flick.
            local acc = (conformWheelAccum[key] or 0) + (scrollVertical or 0)
            if math.abs(acc) >= 1 then
                local step = (acc > 0) and 1 or -1
                v, ch = cur + step, true
                acc = acc - step
            end
            conformWheelAccum[key] = acc
        end
    else
        conformWheelAccum[key] = 0
    end
    if not ch then return false end
    if v < lo then v = lo end
    if v > hi then v = hi end
    if v == cur then return false end
    settings[key] = v
    saveSettings()
    return true
end

function conformAudioFor(IP)
    if not IP or not IP.filePath then return nil end
    local t = settings.conform_audio
    return t and t[IP.filePath] or nil
end

-- How wide the video + audio pair will be, so the caller can centre it between the
-- timecodes without the two buttons having been drawn yet.
function conformSourceWidth(IP)
    local v = conformShorten((IP and IP.fileName) or "no video", 26)
    local w = reaper.ImGui_CalcTextSize(ctx, v) + 16 + 8
    if IP and IP.filePath and IP.filePath ~= "" then
        local cur = conformAudioFor(IP)
        local a   = conformShorten((cur and cur:match("([^/\\]+)$")) or "own audio", 22)
        w = w + reaper.ImGui_CalcTextSize(ctx, a) + 16
        if cur then w = w + reaper.ImGui_GetFrameHeight(ctx) end   -- the x, joined on
    end
    return w
end

function conformAudioButton(IP, side)
    if not IP or not IP.filePath or IP.filePath == "" then return end
    reaper.ImGui_SameLine(ctx)
    local cur   = conformAudioFor(IP)
    local shown = conformShorten(cur and cur:match("([^/\\]+)$") or "own audio", 22)
    if reaper.ImGui_Button(ctx, shown .. "##cfaud" .. side) then
        -- Same gesture as the video button: take what is selected in the arrange view.
        -- Only when nothing is selected does it fall back to asking for a file, since
        -- a mix export often is not in the project at all.
        local fn = conformSelectedItemSource()
        if not fn then
            local ok, picked = reaper.GetUserFileNameForRead(cur or IP.filePath,
                                   "Audio for the " .. side .. " version", "")
            fn = (ok and picked and picked ~= "") and picked or nil
        end
        if fn then
            settings.conform_audio = settings.conform_audio or {}
            settings.conform_audio[IP.filePath] = fn
            saveSettings()
        end
    end
    -- Cut to 22 characters here, so the same treatment as the video button beside it:
    -- a mix export's name is where the useful detail is.
    setToolTipWithName(cur and cur:match("([^/\\]+)$") or nil,
                   "Sound used for the " .. side .. " version, for both matching and playback.\n" ..
                   "Click to take the first item selected in the arrange view, or pick a file\n" ..
                   "when nothing is selected. A proper mix export matches far better than the\n" ..
                   "guide track inside the picture.")
    if cur then
        -- Joined to the button it clears: no spacing, and the same height, so the two
        -- read as one control rather than as a stray letter beside it.
        local h = reaper.ImGui_GetFrameHeight(ctx)
        reaper.ImGui_SameLine(ctx, 0, 0)
        if reaper.ImGui_Button(ctx, "x##cfaudclr" .. side, h, h) then
            settings.conform_audio[IP.filePath] = nil
            saveSettings()
        end
        setToolTipFunc("Go back to the audio inside the video file")
    end
end

-- Picture matching is far the more precise of the two: on this project matched picture
-- scores a mean Hamming of about 0.3, matched sound about 8. So picture runs are taken
-- as authoritative and sound is only allowed to explain the stretches picture could
-- not reach. Letting sound overrule picture anywhere would trade a precise answer for
-- a vague one.
--
-- Worth knowing how much this is expected to add: on v8 -> v11, where the mix was
-- redone between versions, sound lifts coverage of the new cut from 87.2% to 88.9%.
-- The gain depends entirely on the pair -- on a picture-locked conform, where the
-- sound is the stable element, it should be the other way round.
function vpMergeAudioRuns(pic, audioRuns, hopsToFrames, framesA, framesB, minRun)
    local merged = {}
    for _, r in ipairs(pic) do merged[#merged + 1] = r end

    -- stretches of the new cut that picture left unexplained
    local spans = {}
    for _, r in ipairs(pic) do spans[#spans + 1] = { r.bStart, r.bStart + r.len } end
    table.sort(spans, function(x, y) return x[1] < y[1] end)
    local gaps, reach = {}, 0
    for _, sp in ipairs(spans) do
        if sp[1] > reach then gaps[#gaps + 1] = { reach, sp[1] } end
        reach = math.max(reach, sp[2])
    end
    if framesB > reach then gaps[#gaps + 1] = { reach, framesB } end

    local added = 0
    for _, r in ipairs(audioRuns) do
        local aS = math.floor(r.aStart * hopsToFrames + 0.5)
        local bS = math.floor(r.bStart * hopsToFrames + 0.5)
        local ln = math.floor(r.len    * hopsToFrames + 0.5)
        for _, g in ipairs(gaps) do
            -- clip to the gap, since only the unexplained part is wanted
            local lo = math.max(bS, g[1])
            local hi = math.min(bS + ln, g[2])
            if hi - lo >= minRun then
                local off = lo - bS
                local aLo = aS + off
                if aLo >= 0 and aLo + (hi - lo) <= framesA then
                    merged[#merged + 1] = {
                        aStart = aLo, bStart = lo, len = hi - lo,
                        meanHam = r.meanHam, src = "audio",
                    }
                    added = added + 1
                end
            end
        end
    end
    table.sort(merged, function(x, y) return x.bStart < y.bStart end)
    return merged, added
end

-- ---------------------------------------------------------------------------
-- Audio playback
-- ---------------------------------------------------------------------------
-- Played through SWS's preview objects rather than REAPER's transport, because the
-- transport would move the project playhead and this tab deliberately keeps its
-- playhead to itself.
--
-- Sound follows whichever side has focus, so you hear the version you are driving.
-- While it plays, the picture is slaved to the preview's own position rather than to
-- wall-clock time: an audio clock cannot drift against the audio, which a frame
-- counter incremented per UI frame certainly can.

conformPreview     = nil   -- SWS CF_Preview object
conformPreviewPath = nil   -- file it was created from
conformPreviewSrc  = nil   -- the PCM source behind it, which is ours to destroy
conformPreviewSide = nil   -- side it belongs to

function conformAudioAvailable()
    return reaper.CF_CreatePreview ~= nil
end

-- A separate export when one has been chosen, since the sound delivered with a cut is
-- frequently not the track muxed into the picture. On this project the difference is
-- not cosmetic: matching the mix exports scores a mean Hamming of 8 where the muxed
-- guide audio scores 18.
function conformAudioSource(IP)
    if not IP then return nil end
    local a = conformAudioFor(IP)
    if a and a ~= "" then return a end
    return IP.filePath
end

-- Routing, after two failed attempts worth recording so they are not retried:
--
--   CF_Preview_SetOutputTrack to the master played *silence*. The doc line
--   "reads -1 when playing through a track" suggested it would work; it does not here.
--
--   I_OUTCHAN = 1024 does sum L+R, but 1024 is REAPER's "mono channel index"
--   convention, so the sum lands on one hardware channel -- the left speaker -- and
--   there is no value meaning "summed, to both of a pair".
--
-- So the default is -1, the plain default output, which is the only setting observed
-- to make sound. The full parameter list from the SWS plugin's own API strings has
-- nothing else that would help: B_LOOP, B_PPITCH, D_FADEIN/OUTLEN, D_LENGTH,
-- D_MEASUREALIGN, D_PAN, D_PITCH, D_PLAYRATE, D_POSITION, D_VOLUME, I_OUTCHAN,
-- I_PITCHMODE. Summed into both speakers would need a helper track whose send to the
-- master carries B_MONO, which means creating a track in the user's project.
function conformRoutePreview(pv)
    if not pv then return end
    -- -1 is "whatever the default output is", which is the only setting observed to
    -- actually make sound here. Routing to the master with CF_Preview_SetOutputTrack
    -- was tried and played silence, so it is not used. A mono fold (1024) reaches one
    -- hardware channel only, so it played out of the left speaker alone -- the control
    -- for it is gone rather than left offering something that does not work.
    reaper.CF_Preview_SetValue(pv, "I_OUTCHAN", -1)
end

-- ---------------------------------------------------------------------------
-- Driving REAPER instead of previewing
-- ---------------------------------------------------------------------------
-- With sync on, REAPER's transport is the clock and this tab follows it, so you hear
-- the session itself -- every track, every plugin -- rather than a preview of two
-- files. That is why the sound options go away: there is nothing here left to play.
--
-- On the old side there is nothing to do but follow: the session is cut to the old
-- version, so the project position already *is* the old position.
--
-- The new side is the interesting one. REAPER can only play the old timeline, so
-- playing the new cut means playing the old one in the order the new cut asks for:
-- inside a matched run the two advance together and REAPER is left alone, and at each
-- place the map jumps, REAPER is seeked to wherever that run continues from. That is
-- what makes it skip around.

function conformSyncEnabled()
    return settings.conform_sync == true
end

function conformProjToOldFrame(IP1, pos, fpsA)
    return (pos - (IP1.item_pos or 0) + (IP1.item_offset or 0)) * ((fpsA > 0) and fpsA or 25)
end

function conformSyncStart()
    if reaper.GetPlayState() & 1 == 0 then reaper.Main_OnCommand(1007, 0) end  -- play
end

function conformSyncStop()
    if reaper.GetPlayState() & 1 == 1 then reaper.Main_OnCommand(1016, 0) end  -- stop
end

-- Puts REAPER where the app's playhead says it should be. seekplay carries the
-- transport with it when it is already running.
function conformSyncSeek(IP1, fpsA)
    if not IP1 or not IP1.item then return end
    local oldF = (conformFocusSide() == "old") and conformPlayhead
                 or conformMap(math.floor(conformPlayhead), true)
    local pos  = conformFrameToTime(IP1, oldF, fpsA)
    if pos then
        reaper.SetEditCurPos(pos, false, true)
        -- Remembered so the follow-the-cursor pass does not read this back as REAPER
        -- having moved on its own and seek us somewhere in response to our own seek.
        conformSyncCur = pos
    end
end

-- The other direction, while stopped: moving REAPER's edit cursor brings this view
-- with it. With sync on, REAPER is the clock, and that should not only be true while
-- the transport happens to be rolling -- lining a cue up by eye in the arrange view and
-- having the two pictures follow is most of what this mode is for.
function conformSyncCursorFollow(IP1, framesA, framesB, fpsA)
    if not IP1 or not IP1.item then return end
    local cur = reaper.GetCursorPosition()
    if conformSyncCur and math.abs(cur - conformSyncCur) < 1e-9 then return end
    conformSyncCur = cur

    local oldF = conformProjToOldFrame(IP1, cur, fpsA)
    if conformFocusSide() == "old" then
        conformPlayhead = conformClamp(oldF, framesA)
    else
        conformPlayhead = conformClamp(conformMap(math.floor(oldF), false), framesB)
    end
    conformSelectAtPlayhead()
end

function conformSyncFollow(IP1, framesA, framesB, fpsA)
    if not conformPlaying or not IP1 or not IP1.item then return end
    local pos  = reaper.GetPlayPosition()
    local fps  = (fpsA > 0) and fpsA or 25
    local oldF = conformProjToOldFrame(IP1, pos, fpsA)
    local dt   = conformSyncPrev and (pos - conformSyncPrev) or 0
    conformSyncPrev = pos

    if conformFocusSide() == "old" then
        conformPlayhead = conformClamp(oldF, framesA)
        return
    end

    -- The new playhead advances by however far the transport actually moved, always,
    -- before anything else is decided. That is what makes a stall impossible: a seek
    -- that has not landed yet cannot leave the position where it was, because the
    -- position does not depend on the seek having worked.
    if dt > 0 and dt < 1 then
        conformPlayhead = conformClamp(conformPlayhead + dt * fps, framesB)
    end

    -- Which run the new position is in. Asked from the new side, because old material
    -- gets reused -- an old frame can sit in several runs, a new frame in at most one,
    -- and sitting in none is a real answer rather than a lookup failure.
    local cur, key
    local R = conformResult
    if R and R.info then
        for i, r in ipairs(R.info.runs) do
            if conformPlayhead >= r.bStart and conformPlayhead < r.bStart + r.len then
                cur, key = r, i
                break
            end
        end
    end

    if key ~= conformSyncRunKey then
        -- Crossing into a different run is the only thing that justifies a jump, and
        -- it justifies exactly one. Seeking whenever the two positions merely disagree
        -- was the freeze: the disagreement persists until the seek lands, so it asked
        -- again every frame and REAPER never got past the same moment.
        conformSyncRunKey = key
        if cur then
            local wantPos = conformFrameToTime(IP1,
                                cur.aStart + (conformPlayhead - cur.bStart), fpsA)
            if wantPos then
                reaper.SetEditCurPos(wantPos, false, true)
                conformSyncPrev = nil    -- the jump itself is not elapsed time
            end
        end
        -- With no run there is nothing to seek to: added or swapped material has no
        -- counterpart in the old cut, so the arrange view plays on and the new
        -- playhead rides along. That is also what making the cut would do -- the
        -- material gets copied as it lies.
    elseif cur and oldF >= cur.aStart and oldF < cur.aStart + cur.len then
        -- Settled inside the run we aligned to, so REAPER's own clock can carry the
        -- position and the two cannot drift apart.
        conformPlayhead = conformClamp(cur.bStart + (oldF - cur.aStart), framesB)
    end
end


-- Stops whatever is currently making sound, and in sync mode carries the project
-- transport with it -- but only when this tab was the thing that started it, so a
-- scrub here never stops a playback someone began in REAPER itself.
function conformHalt()
    if conformSyncEnabled() and conformPlaying then conformSyncStop() end
    conformPlaying = false
    conformStopPreview()
end

function conformStopPreview()
    -- the session items go quiet with the picture, not on their own schedule
    if conformStopItemPreviews then conformStopItemPreviews() end
    if conformPreview then
        reaper.CF_Preview_Stop(conformPreview)
        conformPreview = nil
    end
    -- The source is ours to free: CF_CreatePreview's own description says it "does not
    -- take ownership of the source (don't forget to destroy it unless it came from a
    -- take!)". Destroyed after the stop, never before, since the preview reads from it.
    if conformPreviewSrc then
        reaper.PCM_Source_Destroy(conformPreviewSrc)
        conformPreviewSrc = nil
    end
    conformPreviewPath, conformPreviewSide = nil, nil
end

-- Returns the preview, creating it when the file or the focused side has changed. A
-- freshly created preview is seeked to posSec; one already running is left alone so
-- playback is not restarted every frame.
function conformEnsurePreview(IP, side, posSec)
    if not conformAudioAvailable() then return nil end
    local path = conformAudioSource(IP)
    if not path or path == "" then return nil end

    if conformPreview and (conformPreviewPath ~= path or conformPreviewSide ~= side) then
        conformStopPreview()
    end
    if not conformPreview then
        local src = reaper.PCM_Source_CreateFromFile(path)
        if not src then return nil end
        conformPreview = reaper.CF_CreatePreview(src)
        if not conformPreview then
            reaper.PCM_Source_Destroy(src)
            return nil
        end
        -- Kept so conformStopPreview can free it: the preview does not own it.
        conformPreviewSrc = src
        conformPreviewPath, conformPreviewSide = path, side
        reaper.CF_Preview_SetValue(conformPreview, "B_LOOP", 0)
        reaper.CF_Preview_SetValue(conformPreview, "D_VOLUME", settings.conform_volume or 1.0)
        conformRoutePreview(conformPreview)
        if posSec then
            reaper.CF_Preview_SetValue(conformPreview, "D_POSITION", posSec)
        end
        reaper.CF_Preview_Play(conformPreview)
    end
    return conformPreview
end

function conformSeekPreview(posSec)
    if conformPreview and posSec then
        reaper.CF_Preview_SetValue(conformPreview, "D_POSITION", posSec)
    end
end

-- ---------------------------------------------------------------------------
-- Waveforms
-- ---------------------------------------------------------------------------
-- The level per hop is written into the audio store during analysis, so a waveform
-- costs no decode of its own: it is already on disk next to the hashes by the time
-- there is anything to draw. The hashes cannot supply it -- differencing across
-- frequency and time is exactly what makes them survive a level change, which means
-- they have thrown level away by construction.
--
-- Decimation happens in the extension, for the visible range only and at one bucket
-- per couple of pixels. Handing 120,000 numbers per file to Lua and reducing them here
-- would cost more than it saves, and it would have to be redone on every scroll step
-- anyway.

conformWaveJob   = {}   -- [side] = { src, store, job, done, err, progress }
conformWaveCache = {}   -- [side] = { key, peak = {}, mean = {} }

local WAVE_PX = 1       -- pixels per bucket: one draw call per bucket, so this is the
                        -- knob between waveform detail and calls per frame. At 2 the
                        -- strip was visibly coarser than REAPER's own display of the
                        -- same file, which draws a column per pixel.

function conformWaveAvailable()
    return reaper.VP_AudioPeaks ~= nil and reaper.VP_AnalyzeAudio ~= nil
end

-- Returns storePath, or nil plus a reason. Analysis is started here rather than only
-- by the match, because a waveform is wanted before anyone asks for a match -- and
-- once it exists, matching on sound costs nothing extra.
--
-- force=0 throughout: the extension decides whether a store needs rebuilding, which
-- keeps freshness logic in one place. A store written before peaks existed reads as
-- stale there, so it rebuilds itself rather than showing an empty strip.
function conformWaveStore(IP, side)
    if not conformWaveAvailable() then return nil, "extension too old" end
    local src = conformAudioSource(IP)
    if not src or src == "" then return nil, "no file" end
    local store = conformAudioStorePath(IP)
    if not store then return nil, "no file" end

    local w = conformWaveJob[side]
    if w and w.src ~= src then
        -- a different file is in play now: drop what was in flight for the old one
        if w.job then reaper.VP_AudioRelease(w.job) end
        w = nil
        conformWaveCache[side] = nil
    end
    if not w then
        w = { src = src, store = store }
        w.job = reaper.VP_AnalyzeAudio(src, store, 0)
        if not w.job or w.job == 0 then w.job, w.err = nil, "refused" end
        conformWaveJob[side] = w
    end

    if w.job then
        local st = reaper.VP_AudioState(w.job)
        if st == 1 then
            w.done = true
            reaper.VP_AudioRelease(w.job)
            w.job = nil
        elseif st == 2 then
            local e = reaper.VP_AudioError(w.job)
            w.err = (e and e ~= "") and e or "analysis failed"
            reaper.VP_AudioRelease(w.job)
            w.job = nil
        else
            w.progress = reaper.VP_AudioProgress(w.job)
        end
    end

    if w.err  then return nil, w.err end
    if w.done then return w.store end
    return nil, nil, w.progress or 0
end

function conformReleaseWaveJobs()
    for side, w in pairs(conformWaveJob) do
        if w.job then reaper.VP_AudioRelease(w.job) end
        conformWaveJob[side] = nil
    end
end

-- One entry per side. The key changes on every scroll and zoom step, so this only
-- saves the frames where nothing moved -- which, while simply looking at the result,
-- is most of them.
function conformPeaksFor(side, store, fromSec, toSec, buckets)
    if not store or not buckets or buckets < 1 then return nil end
    -- floored, not trusted: buckets comes from a pixel width, and Lua 5.4's %d throws
    -- on a float that has no exact integer value rather than rounding it
    buckets = math.floor(buckets)
    local key = string.format("%s|%.4f|%.4f|%d", store, fromSec, toSec, buckets)
    local c = conformWaveCache[side]
    if c and c.key == key then return c end

    local blob = reaper.VP_AudioPeaks(store, fromSec, toSec, buckets)
    local peak, mean = {}, {}
    if blob and blob ~= "" and blob:sub(1, 1) == "P" then
        local body = blob:match("\n(.*)$")
        if body then
            local i = 0
            for a, b in body:gmatch("(%d+) (%d+)") do
                i = i + 1
                peak[i] = tonumber(a) * 0.001
                mean[i] = tonumber(b) * 0.001
            end
        end
    end
    c = { key = key, peak = peak, mean = mean }
    conformWaveCache[side] = c
    return c
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

local function withAlpha2(col, a) return (col // 256) * 256 + a end

-- Material that carries over gets a colour per pair, cycling through this palette, so
-- the same block can be found on both rows at a glance. Colouring purely by change
-- type made every matched run look identical, which is exactly the information you
-- need when there are forty of them.
--
-- All cool hues on purpose: the change types that have no counterpart to pair with
-- (added, removed, swapped) keep the warm colours, so cool reads as "carried over" and
-- warm as "changed" before you look at anything else.
conformPairPalette = {
    0x61AFEFFF, 0x98C379FF, 0x56B6C2FF, 0xC678DDFF, 0x7FB3D5FF,
    0x52BE80FF, 0xA569BDFF, 0x48C9B0FF, 0x5DADE2FF, 0x9B8EC4FF,
}

-- Pair colours and numbers depend only on the match, so they are worked out once and
-- kept on the result rather than recomputed every frame.
function conformPairing(R)
    if not R or not R.changes then return end
    if R.pairColor then return end
    R.pairColor, R.pairIndex = {}, {}
    local n = 0
    for i, c in ipairs(R.changes) do
        -- matched and moved are the only genuine content correspondences; swapped is
        -- an adjacency ("this became that"), not the same material on both sides
        if c.type == "matched" or c.type == "moved" then
            n = n + 1
            R.pairIndex[i] = n
            R.pairColor[i] = conformPairPalette[((n - 1) % #conformPairPalette) + 1]
        end
    end
    R.pairCount = n
end

-- ---------------------------------------------------------------------------
-- Session lanes: what the conform would do to your own items
-- ---------------------------------------------------------------------------
-- The conform describes how the new cut was built from the old one. That is only half
-- the job: the other half is what happens to the session cut against the old one. An
-- item that spans a place where the new cut jumps gets cut in two, and for a subproject
-- that is destruction rather than editing.
--
-- So the tracks worth protecting are drawn as a lane above the old side, and what they
-- become after the conform is drawn as a lane below the new side. The second lane is
-- the point: it shows the damage before it happens.
--
-- Protection pins an item to one mapping instead of letting it be cut: pick a frame
-- inside it and the item follows the offset at that frame, outward in one or both
-- directions. The conform is then told to leave that stretch alone.

conformTracks    = {}     -- { { guid, name, track }, ... } in the order added
conformProtect   = {}     -- [itemGUID] = { mode = "both"|"left"|"right", at = oldFrame, d = offset }
conformShift     = {}     -- [itemGUID] = frames nudged by hand, new side only
-- Items deliberately left out of the conform. Not the same as muted, which is the
-- session's own state and none of this tool's business: this says "I have looked at
-- this one and it is not coming along", so it stops counting towards overlaps and the
-- edit plan while staying visible enough to be put back.
conformIgnore    = {}     -- [itemGUID] = true
conformLaneSel   = nil    -- item GUID under the cursor or last clicked
conformLaneCache = nil
conformLaneKey   = nil

local function trackGUID(tr)
    local ok, g = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
    return (ok and g ~= "") and g or nil
end

local function mediaItemGUID(it)
    local ok, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    return (ok and g ~= "") and g or nil
end

function conformAddSelectedTracks()
    local added = 0
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local tr = reaper.GetSelectedTrack(0, i)
        local g  = trackGUID(tr)
        if g then
            local dup = false
            for _, t in ipairs(conformTracks) do if t.guid == g then dup = true end end
            if not dup then
                local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
                if nm == "" then
                    nm = "Track " .. math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
                end
                -- "keep" is the default because that is why you add a track: the items
                -- must survive. "cut" is for material that is supposed to follow the
                -- picture -- sound design, a reused dialogue track -- where being cut
                -- at every change is correct rather than damage.
                conformTracks[#conformTracks + 1] = { guid = g, name = nm, track = tr,
                                                      mode = "keep" }
                added = added + 1
            end
        end
    end
    conformLaneKey = nil
    conformTouchState()
    return added
end

function conformRemoveTrack(i)
    table.remove(conformTracks, i)
    conformLaneKey = nil
    conformTouchState()
end

local function conformResolveTrack(t)
    if t.track and reaper.ValidatePtr2(0, t.track, "MediaTrack*") and trackGUID(t.track) == t.guid then
        return t.track
    end
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if trackGUID(tr) == t.guid then t.track = tr; return tr end
    end
    return nil
end

-- The items on those tracks, placed on the same frame axis as the old video. The old
-- video item sits somewhere on the project timeline with its own source offset, and
-- conformFrameToTime is the forward direction of exactly this conversion.
function conformLaneItems(IP1, fpsA)
    if not IP1 or not IP1.item then return {} end
    local key = string.format("%d|%s|%s|%.4f|%s", #conformTracks,
        tostring(IP1.item_pos), tostring(IP1.item_offset), fpsA,
        tostring(settings.conform_lane_muted))
    for _, t in ipairs(conformTracks) do key = key .. "|" .. (t.mode or "keep") end
    if conformLaneKey == key and conformLaneCache then return conformLaneCache end

    local out = {}
    local base = (IP1.item_pos or 0) - (IP1.item_offset or 0)
    for _, t in ipairs(conformTracks) do
        local tr = conformResolveTrack(t)
        if tr then
            for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
                local it = reaper.GetTrackMediaItem(tr, j)
                local muted = reaper.GetMediaItemInfo_Value(it, "B_MUTE") > 0.5
                if settings.conform_lane_muted or not muted then
                    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                    local tk  = reaper.GetActiveTake(it)
                    local nm  = ""
                    if tk then local _, n = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false); nm = n end
                    out[#out + 1] = {
                        guid  = mediaItemGUID(it),
                        name  = (nm ~= "") and nm or t.name,
                        track = t.name,
                        mode  = t.mode or "keep",
                        muted = muted,
                        s     = (pos - base) * fpsA,
                        e     = (pos + len - base) * fpsA,
                        -- what playing it back needs. The take's source is used as-is
                        -- and never destroyed: CF_CreatePreview's own note is "don't
                        -- forget to destroy it unless it came from a take".
                        take  = tk,
                        src   = tk and reaper.GetMediaItemTake_Source(tk) or nil,
                        offs  = tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0,
                        rate  = tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1,
                        vol   = reaper.GetMediaItemInfo_Value(it, "D_VOL")
                                * (tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1),
                    }
                end
            end
        end
    end
    table.sort(out, function(x, y) return x.s < y.s end)

    -- Overlapping items get their own row rather than being drawn on top of each
    -- other. Greedy packing over items already sorted by start: each goes in the first
    -- row whose last item has finished, which is the fewest rows that can hold them.
    local rowEnd = {}
    for _, it in ipairs(out) do
        it.row = nil
        for r = 1, #rowEnd do
            if it.s >= rowEnd[r] then it.row = r; rowEnd[r] = it.e; break end
        end
        if not it.row then rowEnd[#rowEnd + 1] = it.e; it.row = #rowEnd end
    end
    conformLaneRows = math.max(1, #rowEnd)

    conformLaneCache, conformLaneKey = out, key
    return out
end

-- ---------------------------------------------------------------------------
-- Hearing the session against either cut
-- ---------------------------------------------------------------------------
-- The lanes show where the items land. This plays them, which is the thing that
-- actually answers the question: with the old side driving you hear the session as it
-- is, and with the new side driving you hear it where the conform would put it --
-- against the new picture, before anything has been committed.
--
-- One preview per item currently under the playhead. They are started independently, so
-- each can begin up to one audio buffer late against the video's own sound; they then
-- run off the same device clock, so that offset stays put instead of growing.

conformItemPv = {}      -- [itemGUID] = CF_Preview

function conformStopItemPreviews()
    for g, pv in pairs(conformItemPv) do
        reaper.CF_Preview_Stop(pv)
        conformItemPv[g] = nil
    end
end

-- Where in an item's source the playhead currently is, or nil if it is not over it.
-- With the new side driving, the item is heard at its conformed position: the piece
-- under the new playhead says which old frame that is, and the source position follows
-- from there.
function conformItemSourcePos(it, breaks, oldF, newF, fpsA)
    local at
    if conformFocusSide() == "old" then
        if oldF >= it.s and oldF < it.e then at = oldF end
    else
        for _, pc in ipairs(conformItemPieces(it, breaks)) do
            if newF >= pc.newS and newF < pc.newS + pc.len then
                at = pc.oldS + (newF - pc.newS)
                break
            end
        end
    end
    if not at then return nil end
    local fps = (fpsA > 0) and fpsA or 25
    return (it.offs or 0) + ((at - it.s) / fps) * (it.rate or 1)
end

-- In sync mode this does nothing at all: REAPER is playing the session, so these items
-- are already being heard from their own tracks and previewing them too would double
-- every one of them a few milliseconds out.
function conformPlayItems(IP1, oldF, newF, fpsA)
    if not conformAudioAvailable() or not conformItemsAudible()
       or #conformTracks == 0 or not conformPlaying then
        if next(conformItemPv) then conformStopItemPreviews() end
        return
    end

    local items  = conformLaneItems(IP1, fpsA)
    local breaks = conformMapBreaks()
    local want   = {}

    for _, it in ipairs(items) do
        if it.src and not it.muted and not conformIgnore[it.guid] then
            local sp = conformItemSourcePos(it, breaks, oldF, newF, fpsA)
            if sp then
                want[it.guid] = true
                if not conformItemPv[it.guid] then
                    local pv = reaper.CF_CreatePreview(it.src)
                    if pv then
                        reaper.CF_Preview_SetValue(pv, "B_LOOP", 0)
                        reaper.CF_Preview_SetValue(pv, "D_VOLUME",
                            (it.vol or 1) * (settings.conform_volume or 1.0))
                        reaper.CF_Preview_SetValue(pv, "I_OUTCHAN", -1)
                        reaper.CF_Preview_SetValue(pv, "D_POSITION", sp)
                        reaper.CF_Preview_Play(pv)
                        conformItemPv[it.guid] = pv
                    end
                end
            end
        end
    end

    -- anything the playhead has left behind
    for g, pv in pairs(conformItemPv) do
        if not want[g] then
            reaper.CF_Preview_Stop(pv)
            conformItemPv[g] = nil
        end
    end
end

-- An item can only be cut where the mapping changes, and the mapping only changes at a
-- run boundary. So the boundaries are the whole story, and there is no need to ask the
-- map about every frame.
function conformMapBreaks()
    local R = conformResult
    if not R or not R.info then return {} end
    local b = {}
    for _, r in ipairs(R.info.runs) do
        b[#b + 1] = r.aStart
        b[#b + 1] = r.aStart + r.len
    end
    table.sort(b)
    return b
end

-- What one item becomes in the new cut: a list of pieces, each with where it came from
-- and where it lands. More than one piece means the conform would cut it.
function conformItemPieces(it, breaks)
    local R = conformResult
    if not R then
        local sh = conformShift[it.guid] or 0
        return { { oldS = it.s, oldE = it.e, newS = it.s + sh, len = it.e - it.s } }
    end

    local p = conformProtect[it.guid]
    local shift = conformShift[it.guid] or 0

    -- `d` is the offset the pin holds: the block you right-clicked stays exactly where
    -- it already sat, and the rest of the item extends rigidly out from it. It is
    -- recorded at pin time from the piece that was clicked rather than re-derived, so
    -- pinning an item that is already pinned does not quietly re-anchor it somewhere
    -- else. Records made from the keyboard have no piece, so they fall back to the map.
    local function rigid(from, to, at, pr)
        local d = (pr and pr.d) or (conformMap(math.floor(at), false) - math.floor(at))
        return { oldS = from, oldE = to, newS = from + d + shift,
                 len = to - from, prot = true }
    end

    if p and p.mode == "both" then
        return { rigid(it.s, it.e, p.at, p) }
    end

    -- the frames inside this item where the mapping jumps
    local cuts = { it.s }
    for _, b in ipairs(breaks) do
        if b > it.s and b < it.e then cuts[#cuts + 1] = b end
    end
    cuts[#cuts + 1] = it.e

    local pieces = {}
    for i = 1, #cuts - 1 do
        local a, b = cuts[i], cuts[i + 1]
        if b > a then
            local d = conformMap(math.floor(a), false) - math.floor(a)
            pieces[#pieces + 1] = { oldS = a, oldE = b, newS = a + d + shift, len = b - a }
        end
    end

    -- A one-sided protection replaces the pieces on that side with a single rigid one,
    -- and leaves the other side to be cut as it would have been.
    if p and (p.mode == "left" or p.mode == "right") then
        local keep = {}
        if p.mode == "left" then
            keep[#keep + 1] = rigid(it.s, p.at, p.at, p)
            for _, pc in ipairs(pieces) do if pc.oldS >= p.at then keep[#keep + 1] = pc end end
        else
            for _, pc in ipairs(pieces) do if pc.oldE <= p.at then keep[#keep + 1] = pc end end
            keep[#keep + 1] = rigid(p.at, it.e, p.at, p)
        end
        return keep
    end

    return pieces
end

-- ---------------------------------------------------------------------------
-- Remembering a comparison
-- ---------------------------------------------------------------------------
-- Everything done by hand to a conform -- healed and removed matches, pinned and
-- nudged items, which tracks were brought in and whether each is kept or follows the
-- picture -- is work, and losing it because the tab was closed would make people
-- reluctant to do it at all.
--
-- Stored beside the old video, the same place the fingerprints and the cut list live,
-- as one file per old version holding an entry per new version compared against it.
-- Keying on the new file's name rather than its full path means moving the pair to
-- another drive does not lose the work.
--
-- The matched runs are stored too, with enough of the match header to rebuild the
-- result from them. Reopening a pair therefore shows the conform as you left it
-- without re-matching, and Compare is still there to start over.

local CONFORM_STATE_VERSION = 1

function conformStatePath(IP1)
    if not IP1 or not IP1.filePath or IP1.filePath == "" then return nil end
    return IP1.filePath .. ".conform.json"
end

local function conformStateKey(IP2)
    local p = (IP2 and IP2.filePath) or ""
    return p:match("([^/\\]+)$") or p
end

local function conformReadAll(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local txt = f:read("*a")
    f:close()
    local ok, d = pcall(json.decodeFromJson, txt)
    return (ok and type(d) == "table") and d or {}
end

function conformSaveState(IP1, IP2)
    local path = conformStatePath(IP1)
    local key  = conformStateKey(IP2)
    if not path or key == "" then return end

    local tracks = {}
    for _, t in ipairs(conformTracks) do
        tracks[#tracks + 1] = { guid = t.guid, name = t.name, mode = t.mode or "keep" }
    end

    local R = conformResult
    local entry = {
        v       = CONFORM_STATE_VERSION,
        protect = conformProtect,
        shift   = conformShift,
        ignore  = conformIgnore,
        tracks  = tracks,
        audio   = {
            old = conformAudioFor(IP1),
            new = conformAudioFor(IP2),
        },
        params  = {
            ham      = settings.conform_ham,
            minRun   = settings.conform_min_run,
            conf     = settings.conform_min_conf,
            useAudio = settings.conform_use_audio and true or false,
        },
    }
    if R and R.info then
        entry.edited = R.edited and true or nil
        entry.info   = {
            framesA = R.info.framesA, framesB = R.info.framesB,
            fpsA    = R.info.fpsA,    fpsB    = R.info.fpsB,
            runs    = R.info.runs,
        }
    end

    local all = conformReadAll(path)
    all[key] = entry
    saveFile(path, json.encodeToJson(all))
end

-- Called when the pair changes. Returns true if anything was restored.
function conformLoadState(IP1, IP2)
    conformProtect, conformShift, conformTracks = {}, {}, {}
    conformIgnore  = {}
    conformLaneKey, conformLaneSel, conformLanePick = nil, nil, nil
    conformCutPlan = nil
    conformClearUndo()

    local path = conformStatePath(IP1)
    local key  = conformStateKey(IP2)
    if not path or key == "" then return false end
    local entry = conformReadAll(path)[key]
    if type(entry) ~= "table" then return false end

    conformProtect = entry.protect or {}
    conformShift   = entry.shift   or {}
    conformIgnore  = entry.ignore  or {}
    for _, t in ipairs(entry.tracks or {}) do
        -- the track pointer is resolved from the GUID on first use, so a reordered or
        -- reopened project still finds it
        conformTracks[#conformTracks + 1] = { guid = t.guid, name = t.name,
                                              mode = t.mode or "keep" }
    end

    -- A separate audio export is part of how the pair was compared, so it comes back
    -- with it rather than having to be found again.
    settings.conform_audio = settings.conform_audio or {}
    if entry.audio then
        if entry.audio.old and IP1 and IP1.filePath then
            settings.conform_audio[IP1.filePath] = entry.audio.old
        end
        if entry.audio.new and IP2 and IP2.filePath then
            settings.conform_audio[IP2.filePath] = entry.audio.new
        end
    end

    local p = entry.params
    if p then
        settings.conform_ham       = p.ham      or settings.conform_ham
        settings.conform_min_run   = p.minRun   or settings.conform_min_run
        settings.conform_min_conf  = p.conf     or settings.conform_min_conf
        settings.conform_use_audio = p.useAudio and true or false
    end

    -- Rebuilt from the stored runs rather than re-matched: the runs are what the
    -- matcher produced plus whatever was done to them by hand, and re-matching would
    -- throw the second half away.
    local i = entry.info
    if i and i.runs and #i.runs > 0 then
        local m = { framesA = i.framesA, framesB = i.framesB,
                    fpsA = i.fpsA, fpsB = i.fpsB, runs = i.runs }
        local changes = vpClassifyChanges(m)
        conformResult = {
            info    = m,
            changes = changes,
            damage  = vpDamage(m, changes),
            matchMs = 0,
            audioAdded = 0,
            edited  = entry.edited,
            restored = true,
        }
    end
    return true
end

-- Saves whenever the pair has one and something has changed. Called from the places
-- that change things rather than every frame, since this writes a file.
function conformTouchState()
    -- Any edit invalidates a plan worked out before it: the offsets it was built from
    -- have just changed, and stale markers over the lane would be worse than none.
    conformCutPlan = nil
    if conformIP1 and conformIP2 then conformSaveState(conformIP1, conformIP2) end
end


-- Items that have come to overlap on the new timeline. They did not overlap in the
-- session -- the lanes are built from real item positions -- so an overlap is always
-- the conform having moved two things onto each other, which is damage worth seeing.
--
-- Two items collide as soon as any piece of one shares timeline with any piece of the
-- other.
--
-- This used to compare each item's min..max span and only pairs from different tracks,
-- and both were wrong. The span counted the gap between two pieces as occupied, so it
-- reported collisions that were not there. The track test missed the commonest real
-- collision of all: a conform moves two items on the SAME track by different amounts
-- and they land on top of each other. In the original session they could not overlap,
-- which is what that test was reasoning from -- but the conformed result is not the
-- original session, and whether it can be committed is exactly the question being
-- asked.
function conformNewOverlaps(items, breaks)
    local spans = {}
    for _, it in ipairs(items) do
        if not it.muted and not conformIgnore[it.guid] then
            for _, pc in ipairs(conformItemPieces(it, breaks)) do
                if pc.len > 0 then
                    spans[#spans + 1] = { it = it, lo = pc.newS, hi = pc.newS + pc.len }
                end
            end
        end
    end

    local out, seen = {}, {}
    for i = 1, #spans do
        for j = i + 1, #spans do
            local a, b = spans[i], spans[j]
            -- Pieces of one item never collide with each other: they are one object cut
            -- up, and they are laid out end to end by construction.
            if a.it.guid ~= b.it.guid and a.lo < b.hi and b.lo < a.hi then
                local key = a.it.guid .. "\0" .. b.it.guid
                if not seen[key] then
                    seen[key] = true
                    seen[b.it.guid .. "\0" .. a.it.guid] = true
                    out[a.it.guid] = out[a.it.guid] or {}
                    out[b.it.guid] = out[b.it.guid] or {}
                    table.insert(out[a.it.guid], b.it)
                    table.insert(out[b.it.guid], a.it)
                end
            end
        end
    end
    return out
end

-- How far `it` would have to move so that it sits the same distance from `other` as it
-- did in the session. Restoring the original spacing is usually what is wanted: two
-- cues written against each other should stay against each other even if the picture
-- between them changed.
function conformAlignShift(it, other, breaks)
    local save = conformShift[it.guid]
    conformShift[it.guid] = 0
    local natural = conformItemPieces(it, breaks)[1]
    conformShift[it.guid] = save

    local otherPc = conformItemPieces(other, breaks)[1]
    if not natural or not otherPc then return 0 end

    local want = otherPc.newS + (it.s - other.s)   -- the session's own spacing
    return math.floor(want - natural.newS + 0.5)
end

-- ---------------------------------------------------------------------------
-- Working out the fewest cuts that will do
-- ---------------------------------------------------------------------------
-- Every item that must survive has to land at some offset from where it sits now.
-- Where two neighbouring items need the *same* offset, nothing between them has to
-- change. Where the offset changes, the old timeline needs one edit between them --
-- insert if the new cut is longer there, remove if shorter.
--
-- So the fewest edits that can work is one per change of offset, and putting each in
-- the gap between the two items means no item is cut to achieve it. On a small revision
-- most neighbours share an offset and the answer is a handful of edits rather than one
-- per match boundary, which is the whole point: a session should not be shredded to
-- absorb a change that moved three scenes.
--
-- Tracks set to follow the picture are left out: they are supposed to be cut.
function conformFindCuts(IP1, fpsA)
    local items  = conformLaneItems(IP1, fpsA)
    local breaks = conformMapBreaks()

    local keep = {}
    for _, it in ipairs(items) do
        -- Ignored items are deliberately not coming along, so they have no offset to
        -- satisfy and no say in where the edits go.
        if it.mode ~= "cut" and not it.muted and not conformIgnore[it.guid] then
            local pcs = conformItemPieces(it, breaks)
            if #pcs > 0 then
                keep[#keep + 1] = {
                    it = it, s = it.s, e = it.e,
                    d = pcs[1].newS - it.s,       -- the offset this item needs
                    split = #pcs > 1,             -- the conform would still cut it
                }
            end
        end
    end
    table.sort(keep, function(a, b) return a.s < b.s end)

    local cuts, problems = {}, {}
    local prev
    for _, k in ipairs(keep) do
        if k.split then
            problems[#problems + 1] = { kind = "split", a = k.it }
        end
        if prev then
            local delta = k.d - prev.d
            if delta ~= 0 then
                if k.s <= prev.e then
                    -- no room between them: the two need different offsets but there is
                    -- nowhere to put the edit without cutting one of them
                    problems[#problems + 1] = { kind = "nogap", a = prev.it, b = k.it,
                                                delta = delta }
                else
                    -- dPrev/dNext are the offsets either side of the edit. On the new
                    -- timeline the edit is not a point but the span between them: an
                    -- insert opens that much room, a removal closes it.
                    cuts[#cuts + 1] = {
                        at    = math.floor((prev.e + k.s) / 2),
                        delta = delta,
                        gapS  = prev.e, gapE = k.s,
                        dPrev = prev.d, dNext = k.d,
                        after = prev.it.name, before = k.it.name,
                    }
                end
            end
        end
        prev = k
    end
    return cuts, problems, #keep
end

-- ---------------------------------------------------------------------------
-- Making the cut
-- ---------------------------------------------------------------------------
-- Everything up to here describes; this is the one thing that writes to the session.
--
-- Each edit is a time insert or a time removal across the whole project, done through
-- REAPER's own time-selection actions rather than by moving items one at a time. That
-- is what keeps automation: those actions ripple envelope points with the items, and
-- reimplementing them item by item would have left every envelope behind.
--
-- Applied back to front. Each edit changes where every later position sits, so working
-- forwards would mean re-deriving the rest after every step; from the end, nothing
-- already applied can move what is still to come.
--
-- Items that get split are split. The point of pinning is to say "this one must not be
-- cut", so an unpinned item sitting across an edit is simply material the cut runs
-- through -- it becomes more pieces, which is what the lane has been showing all along.
local CUT_INSERT_TIME = 40200   -- Time selection: insert empty space, moving later items
local CUT_REMOVE_TIME = 40201   -- Time selection: remove contents, moving later items

function conformApplyCuts(IP1, fpsA, cuts)
    if not IP1 or not IP1.item or not cuts or #cuts == 0 then return 0, "nothing to apply" end
    local fps = (fpsA > 0) and fpsA or 25

    -- Back to front, on a copy: the plan on screen is not ours to reorder.
    local order = {}
    for _, c in ipairs(cuts) do order[#order + 1] = c end
    table.sort(order, function(a, b) return a.at > b.at end)

    -- Put the session back as it was found, so making a cut does not also lose the
    -- loop range or the cursor position someone was working from.
    local curPos = reaper.GetCursorPosition()
    local selS, selE = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local applied = 0
    for _, c in ipairs(order) do
        local pos = conformFrameToTime(IP1, c.at, fps)
        local dur = math.abs(c.delta) / fps
        if pos and dur > 0 then
            reaper.GetSet_LoopTimeRange(true, false, pos, pos + dur, false)
            reaper.Main_OnCommand(c.delta > 0 and CUT_INSERT_TIME or CUT_REMOVE_TIME, 0)
            applied = applied + 1
        end
    end

    reaper.GetSet_LoopTimeRange(true, false, selS, selE, false)
    reaper.SetEditCurPos(curPos, false, false)

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock(string.format("Conform session: %d edit%s",
                                       applied, applied == 1 and "" or "s"), -1)
    return applied
end


-- Zoom and scroll. Not persisted: a zoom level chosen while studying one pair of
-- versions means nothing for the next, and keypad repeat would otherwise write the
-- settings file several times a second.
conformZoom        = 1.0
conformScrollWant  = nil
conformScrollTries = 0
conformViewW       = 100

local CONFORM_ZOOM_MAX = 256

-- Asks for a scroll position. Applied for a couple of frames because ImGui's scroll
-- maximum lags the content size by one frame, so the first attempt after a zoom change
-- can be clamped against the old width.
function conformScrollTo(x)
    conformScrollWant  = x
    conformScrollTries = 3
end

-- Anchored on the focused playhead rather than the mouse: it is where attention
-- already is, and it keeps zooming from throwing the thing being looked at off screen.
function conformZoomBy(factor, framesA, framesB)
    local z = conformZoom * factor
    if z < 1 then z = 1 end
    if z > CONFORM_ZOOM_MAX then z = CONFORM_ZOOM_MAX end
    if z == conformZoom then return end

    local maxFrames  = math.max(framesA, framesB, 1)
    local oldF, newF = conformPositions(framesA, framesB)
    local f = (conformFocusSide() == "new") and newF or oldF
    conformZoom = z
    conformScrollTo((f / maxFrames) * conformViewW * z - conformViewW * 0.5)
end

-- Buttons and keypad zoom around the focused playhead; opt+scroll over the timeline
-- zooms around the cursor instead. Different anchors on purpose: a button press has no
-- position to speak of, so the playhead is the only sensible centre, while a wheel
-- gesture is already pointing at something.
-- Just the two buttons, at the far right of the transport row and over the timeline
-- they act on. No label and no readout: the timeline itself shows how far in you are,
-- and "fit" lives on opt+click rather than appearing and disappearing, which would move
-- the pair sideways every time the zoom left 1x.
function conformZoomButtons(framesA, framesB)
    local keys = not markerNameIsFocused
    -- matched to the sliders on the same row rather than SmallButton's shorter frame
    local h = reaper.ImGui_GetFrameHeight(ctx)

    local function zoom(factor)
        if isOptionDown then
            conformZoom = 1.0
            conformScrollTo(0)
        else
            conformZoomBy(factor, framesA, framesB)
        end
    end

    if reaper.ImGui_Button(ctx, "-##cfzoom", h, h) or (keys and isKeypadSubtract) then
        zoom(1 / 1.6)
    end
    setToolTipFunc("Zoom out, around the focused playhead.\n" .. MOD_ALT .. "+click shows both versions end to end again.",
                   "keypad -  /  " .. MOD_ALT .. "+scroll over the timeline")

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+##cfzoom", h, h) or (keys and isKeypadAdd) then
        zoom(1.6)
    end
    setToolTipFunc("Zoom in, around the focused playhead.\n" .. MOD_ALT .. "+click shows both versions end to end again.",
                   "keypad +  /  " .. MOD_ALT .. "+scroll over the timeline")
end

-- A slider that also takes the wheel while hovered and resets to its default on
-- opt+click. The reset runs after the slider has drawn, so the value jump ImGui already
-- made from that click is overwritten in the same frame.
function conformSliderSetting(id, key, def, lo, hi, fmt, width, logarithmic, onChange)
    reaper.ImGui_SetNextItemWidth(ctx, width)
    local cur = settings[key]
    if cur == nil then cur = def end
    local ch, v = reaper.ImGui_SliderDouble(ctx, id, cur, lo, hi, fmt,
                      logarithmic and reaper.ImGui_SliderFlags_Logarithmic() or 0)
    if reaper.ImGui_IsItemHovered(ctx) then
        if isOptionDown and isMouseClick then
            v, ch = def, true
        elseif scrollVertical and scrollVertical ~= 0 then
            -- a proportion of the range per notch, so one gesture covers a useful span
            -- whether the range is 0..1.5 or 1..20
            v, ch = cur + scrollVertical * (hi - lo) * 0.05, true
        end
    end
    if not ch then return false end
    if v < lo then v = lo end
    if v > hi then v = hi end
    if v == cur then return false end
    settings[key] = v
    saveSettings()
    if onChange then onChange(v) end
    return true
end

-- ---------------------------------------------------------------------------
-- What you hear, per row
-- ---------------------------------------------------------------------------
-- One speaker per timeline row, in the gutter to the left of the row it belongs to, so
-- "do I hear this" is answered where the thing itself is rather than in a legend of
-- checkboxes that have to be read against the stack.
--
-- There are four because there are four things that can make sound: each version's own
-- audio, and the session items as they sit in each version. Only the focused side is
-- playing at any moment, so the other two are showing what you would hear if you
-- switched -- which is worth setting up in advance.
CONFORM_SPEAKER_W = 22        -- gutter width; the sync button above it sets the column

-- Defaults to on, so adding a track starts audible rather than silently doing nothing.
function conformRowAudible(row)
    local m = settings.conform_row_mute
    return not (m and m[row])
end

function conformSetRowAudible(row, on)
    settings.conform_row_mute = settings.conform_row_mute or {}
    settings.conform_row_mute[row] = (not on) or nil
    saveSettings()
end

-- Whether the sound for the side currently driving should be heard at all. Sync takes
-- the whole question away: REAPER is playing the session itself, and previewing the
-- files on top of it would be two copies of the same material a few milliseconds apart.
function conformVideoAudible()
    if conformSyncEnabled() then return false end
    return conformRowAudible(conformFocusSide())
end

function conformItemsAudible()
    if conformSyncEnabled() then return false end
    return conformRowAudible(conformFocusIsLane() and conformFocus
                             or ((conformFocusSide() == "new") and "laneNew" or "laneOld"))
end

-- Filled in while the timeline draws, read by the gutter afterwards: the rows know
-- their own screen positions and the gutter does not, and the gutter has to be drawn
-- outside the scrolling child so it does not scroll away from them.
conformSpeakerRows = {}

CONFORM_ROW_LABEL = {
    laneOld = "the session items as they are now",
    old     = "the old version's own sound",
    new     = "the new version's own sound",
    laneNew = "the session items where the conform would put them",
}

-- The gutter itself. Hit tested by hand against the mouse rather than with ImGui
-- buttons: these have to line up with rows whose positions are only known from inside
-- the child, and placing real buttons at absolute positions afterwards would fight the
-- parent window's own layout.
function conformDrawSpeakerGutter(x, w)
    if #conformSpeakerRows == 0 then return end
    local mx, my = reaper.ImGui_GetMousePos(ctx)
    local inWin  = reaper.ImGui_IsWindowHovered(ctx)
                   and not reaper.ImGui_IsAnyItemHovered(ctx)
    local syncing = conformSyncEnabled()

    for _, r in ipairs(conformSpeakerRows) do
        if r.h >= 12 then
            local cy  = r.y + r.h / 2
            local hot = inWin and mx >= x and mx <= x + w
                        and my >= r.y and my <= r.y + r.h
            local on  = conformRowAudible(r.row) and not syncing

            conformDrawSpeaker(draw_list, x + w / 2, cy, on, hot)

            if hot then
                if syncing then
                    reaper.ImGui_SetTooltip(ctx,
                        "Nothing is previewed from here while sync is on: REAPER is playing\n" ..
                        "the session itself, so this would be the same material twice.")
                else
                    reaper.ImGui_SetTooltip(ctx, string.format("%s %s\n\n%s",
                        conformRowAudible(r.row) and "Playing" or "Muted",
                        CONFORM_ROW_LABEL[r.row] or r.row,
                        "Only the row driving playback is heard, so the other three are\n" ..
                        "set up in advance for when you switch to them."))
                    if reaper.ImGui_IsMouseClicked(ctx, 0) then
                        conformSetRowAudible(r.row, not conformRowAudible(r.row))
                        -- stop what is playing now so the change is heard immediately
                        -- rather than at the end of whatever is already in flight
                        if r.row == "old" or r.row == "new" then
                            conformStopPreview()
                        else
                            conformStopItemPreviews()
                        end
                    end
                end
            end
        end
    end
end

-- A speaker, drawn rather than labelled: a cone, and either waves or a cross.
function conformDrawSpeaker(dl, cx, cy, on, hot)
    local col = on and (hot and colorWhite or 0xFFFFFFBB) or (hot and 0xFFFFFF88 or 0xFFFFFF44)
    -- body
    reaper.ImGui_DrawList_AddRectFilled(dl, cx - 5, cy - 2.5, cx - 2, cy + 2.5, col, 1)
    -- cone
    reaper.ImGui_DrawList_AddTriangleFilled(dl, cx - 2, cy - 5.5, cx - 2, cy + 5.5,
                                            cx + 2, cy, col)
    if on then
        for i = 1, 2 do
            local r = 2.5 + i * 2.2
            reaper.ImGui_DrawList_AddCircle(dl, cx + 1, cy, r, col, 10, 1.2)
        end
    else
        reaper.ImGui_DrawList_AddLine(dl, cx + 3, cy - 4, cx + 9, cy + 4, col, 1.4)
        reaper.ImGui_DrawList_AddLine(dl, cx + 9, cy - 4, cx + 3, cy + 4, col, 1.4)
    end
end

-- How the comparison sounds. Zoom is not here: it belongs over the timeline it acts on,
-- at the far right of the same row. The waveform gain moved into the view menu, which is
-- where the rest of the display settings already were.
function conformViewControls()
    -- Sync first, because it decides whether anything after it applies. It also sets the
    -- left gutter column the speakers sit in, so it stays exactly where it is.
    local sych, syv = reaper.ImGui_Checkbox(ctx, "sync", settings.conform_sync == true)
    if sych then
        settings.conform_sync = syv
        saveSettings()
        conformStopPreview()        -- the previews have no job in sync mode
        conformPlaying = false
        conformSyncStop()
    end
    setToolTipFunc("Play REAPER's own transport instead of previewing the two files, so you\n" ..
                   "hear the session itself -- every track, every plugin.\n\n" ..
                   "Driving the old side just plays the timeline as it stands. Driving the new\n" ..
                   "side plays the old timeline in the order the new cut asks for, skipping to\n" ..
                   "wherever each matched run continues from.\n\n" ..
                   "Nothing is previewed from here while this is on, so the speakers beside\n" ..
                   "the rows switch off: you are hearing the session, not these files.")

    if conformAudioAvailable() then
        local syncing = conformSyncEnabled()
        if syncing then reaper.ImGui_BeginDisabled(ctx) end
        reaper.ImGui_SameLine(ctx)
        conformSliderSetting("##cfvol", "conform_volume", 1.0, 0.0, 1.5, "vol %.2f", 90, false,
            function(v)
                if conformPreview then
                    reaper.CF_Preview_SetValue(conformPreview, "D_VOLUME", v)
                end
            end)
        setToolTipFunc("Playback volume for the focused version",
                       "scroll, or " .. MOD_ALT .. "+click to reset")
        if syncing then reaper.ImGui_EndDisabled(ctx) end
    end
end

-- The view options that are not worth a permanent control each, behind one button next
-- to the zoom they sit with.
function conformViewMenu()
    if reaper.ImGui_Button(ctx, "view##cfview") then
        reaper.ImGui_OpenPopup(ctx, "##cfviewmenu")
    end
    setToolTipFunc("Waveforms and other display options")

    if reaper.ImGui_BeginPopup(ctx, "##cfviewmenu") then
        if conformWaveAvailable() then
            local wch, wv = reaper.ImGui_Checkbox(ctx, "show waveform",
                                                  settings.conform_wave ~= false)
            if wch then
                settings.conform_wave = wv
                saveSettings()
            end
            setToolTipFunc("Draw each version's sound beside its timeline. The level is\n" ..
                           "already stored with the fingerprints, so this costs no analysis.")
        end
        local sch, sv = reaper.ImGui_Checkbox(ctx, "show result",
                                              settings.conform_show_result or false)
        if sch then
            settings.conform_show_result = sv
            saveSettings()
        end
        setToolTipFunc("The match summary and the list of changes, below the timeline")

        -- Dialogue mixed at -30 dBFS is 3% of full scale, so at 1x it is a flat line in
        -- the strip: without this the waveform is unreadable on exactly the material
        -- being conformed. Display only -- the stored levels and the match are untouched.
        if conformWaveAvailable() then
            reaper.ImGui_Separator(ctx)
            conformSliderSetting("##cfpeak", "conform_peak_gain", 1.0, 1.0, 20.0,
                                 "peaks %.1fx", 140, true)
            setToolTipFunc("How tall the waveform peaks are drawn. Nothing about the sound,\n" ..
                           "the match or the stored levels changes.",
                           MOD_ALT .. "+shift+scroll over the timeline, scroll here, " .. MOD_ALT .. "+click to reset")
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- The two session lanes. The old one is the session as it stands; the new one is what
-- the conform would leave behind, with each item drawn as the pieces it becomes.
--
-- Colour carries the only question worth asking at a glance: green survives in one
-- piece, amber has been pinned by hand, red would be cut. Everything else is detail.
local LANE_WHOLE = 0x6FBF73FF    -- lands intact
local LANE_CUT   = 0xE06C75FF    -- would be cut into pieces
local LANE_PROT  = 0xE5C07BFF    -- pinned by hand
local LANE_MUTE  = 0x6E7681FF
local LANE_FOLLOW= 0x61AFEFFF    -- meant to follow the picture, so cuts are expected
local LANE_MOVED = 0xC678DDFF    -- nudged by hand, which nothing else would have done

CONFORM_LANE_ROW = 26            -- height of one row of items
-- A strip above the old lane's items where the cut tags sit, so they are beside the
-- items rather than over them. Only there when there is a plan to label.
function conformLaneHead()
    return conformCutPlan and 16 or 0
end

-- REAPER's own peak files, which already exist for anything in the project, rather
-- than fingerprinting every item: the peaks are built, cached and identical to what
-- the arrange view draws. buf comes back as maximums then minimums, interleaved per
-- channel, with the sample count in the low 20 bits of the return.
conformItemWave = {}

function conformItemPeaks(it, fromSec, lenSec, n)
    if not it.take or n < 1 or lenSec <= 0 or not reaper.GetMediaItemTake_Peaks then
        return nil
    end
    local key = string.format("%.4f|%.4f|%d", fromSec, lenSec, n)
    local c = conformItemWave[it.guid]
    if c and c.key == key then return c.peak end

    local ch  = 2
    local buf = reaper.new_array(n * ch * 2)
    buf.clear()
    local got = reaper.GetMediaItemTake_Peaks(it.take, n / lenSec, fromSec, ch, n, 0, buf)
    local cnt = got & 0xfffff
    local peak = {}
    if cnt > 0 then
        local t = buf.table(1, cnt * ch * 2)
        for i = 1, cnt do
            local v = 0
            for k = 0, ch - 1 do
                local mx = math.abs(t[(i - 1) * ch + k + 1] or 0)            -- maximums
                local mn = math.abs(t[cnt * ch + (i - 1) * ch + k + 1] or 0) -- minimums
                if mx > v then v = mx end
                if mn > v then v = mn end
            end
            peak[i] = v
        end
    end
    conformItemWave[it.guid] = { key = key, peak = peak }
    return peak
end

-- One item's waveform, inside the rectangle it occupies. Only the visible part is
-- asked for, so the cost does not grow with how far off screen the item runs.
local function laneWave(dl, it, x1, x2, y, h, srcFrom, srcLen, col)
    if x2 - x1 < 4 or h < 10 then return end
    local n = math.floor(x2 - x1)
    if n > 2000 then n = 2000 end
    local peak = conformItemPeaks(it, srcFrom, srcLen, n)
    if not peak or #peak == 0 then return end
    local mid, half = y + h / 2, h / 2 - 2
    local w = (x2 - x1) / #peak
    for i = 1, #peak do
        local v = peak[i]
        if v > 0.01 then
            if v > 1 then v = 1 end
            local xa = x1 + (i - 1) * w
            reaper.ImGui_DrawList_AddRectFilled(dl, xa, mid - v * half,
                                                xa + w + 0.5, mid + v * half, col)
        end
    end
end

-- Hit tested before anything is drawn, so the block under the cursor can be brought
-- forward and the rest pushed back in the same pass -- the same reason the match
-- ribbons do it, and the only way the correspondence is readable in a crowd.
function drawConformLanes(dl, items, laneOldY, laneNewY, laneH, fx, xf,
                          visLeft, viewW, maxFrames, fpsA)
    local rowH   = CONFORM_LANE_ROW
    local breaks = conformMapBreaks()
    local fps    = (fpsA > 0) and fpsA or 25
    local laneFocus = conformFocusIsLane()
    local headH  = conformLaneHead()
    conformOverlaps = conformNewOverlaps(items, breaks)

    -- The row holding focus is lifted out of the background, so which of the four is
    -- driving the arrows is visible without having to infer it from the playhead.
    reaper.ImGui_DrawList_AddRectFilled(dl, visLeft, laneOldY, visLeft + viewW,
        laneOldY + laneH + headH, conformFocus == "laneOld" and 0x1E2530FF or 0x00000055)
    reaper.ImGui_DrawList_AddRectFilled(dl, visLeft, laneNewY, visLeft + viewW,
        laneNewY + laneH, conformFocus == "laneNew" and 0x1E2530FF or 0x00000055)
    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)

    -- ---- pass one: geometry and what the cursor is over ---------------------
    local laid = {}
    local hoverItem, hoverFrame, hoverPiece, hoverLane
    for _, it in ipairs(items) do
        local pieces = conformItemPieces(it, breaks)
        local oy     = laneOldY + headH + (it.row - 1) * rowH
        local ny     = laneNewY + (it.row - 1) * rowH
        local x1, x2 = fx(it.s), fx(it.e)
        if x2 - x1 < 2 then x2 = x1 + 2 end
        laid[#laid + 1] = { it = it, pieces = pieces, oy = oy, ny = ny, x1 = x1, x2 = x2 }

        if mouseX >= x1 and mouseX <= x2 and mouseY >= oy and mouseY <= oy + rowH then
            hoverItem, hoverFrame, hoverLane = it, xf(mouseX), "old"
            -- on the old side, the block under the cursor is whichever piece draws
            -- its material, so the same tie can be shown from either lane
            for _, pc in ipairs(pieces) do
                if hoverFrame >= pc.oldS and hoverFrame < pc.oldE then hoverPiece = pc end
            end
        end
        for _, pc in ipairs(pieces) do
            local p1, p2 = fx(pc.newS), fx(pc.newS + pc.len)
            if p2 - p1 < 2 then p2 = p1 + 2 end
            if mouseX >= p1 and mouseX <= p2 and mouseY >= ny and mouseY <= ny + rowH then
                hoverItem, hoverFrame, hoverPiece, hoverLane = it, xf(mouseX), pc, "new"
            end
        end
    end

    conformLaneHit = hoverItem and { item = hoverItem, frame = hoverFrame,
                                     piece = hoverPiece, lane = hoverLane } or nil

    -- An open right-click menu holds the item it belongs to, so the thing being acted
    -- on stays lit while you read the options -- the mouse has moved off it onto the
    -- popup by then, and losing the highlight at exactly that moment is the opposite of
    -- helpful. Otherwise hover wins, and only until the mouse leaves; the clicked one
    -- is what remains when it does.
    -- The standing selection only shows while a lane is driving -- the mirror of the
    -- video blocks going unhighlighted when one is. Hovering still lights whatever is
    -- under the cursor whichever row has focus, because that is a question being asked
    -- right now rather than a selection being remembered.
    -- The standing selection lights its item whichever row has focus. It used to show
    -- only while a lane was driving, which meant clicking into the video rows lost
    -- track of the item you had just been working on.
    local menuFor = conformLaneMenuFor and conformLaneMenuFor.item
    local held    = conformLanePick
    local lit   = (menuFor and menuFor.guid)
                  or (hoverItem and hoverItem.guid)
                  or (held and held.guid)
    local litPc = (menuFor and conformLaneMenuFor.piece)
                  or hoverPiece
                  or (not hoverItem and held or nil)

    -- ---- pass two: draw -----------------------------------------------------
    for _, L in ipairs(laid) do
        local it, pieces = L.it, L.pieces
        local prot = conformProtect[it.guid]
        local col  = it.muted and LANE_MUTE
                     or (it.mode == "cut" and LANE_FOLLOW)
                     or (prot and LANE_PROT)
                     or ((#pieces > 1) and LANE_CUT or LANE_WHOLE)
        local ignored = conformIgnore[it.guid] and true or false
        local isLit   = (lit == it.guid)
        -- One dim level, not three. The alpha used to depend on whether anything at all
        -- was lit, so the lane looked brighter when focus was on a video row and the
        -- whole set of items appeared to change state when it had not. Now the only
        -- thing that brightens an item is hovering it or having it selected, which is
        -- the only thing that is actually different about it.
        local a  = isLit and 0xFF or 0x44
        local wv = isLit and 0x000000AA or 0x00000033
        -- Left out of the conform on purpose: faint enough to read as excluded, solid
        -- enough to find and click again.
        if ignored then
            a  = isLit and 0x55 or 0x1C
            wv = 0x00000018
        end

        -- old side: the item as it is
        reaper.ImGui_DrawList_AddRectFilled(dl, L.x1, L.oy + 2, L.x2, L.oy + rowH - 3,
                                            withAlpha2(col, a), 2)
        laneWave(dl, it, math.max(L.x1, visLeft), math.min(L.x2, visLeft + viewW),
                 L.oy + 2, rowH - 5,
                 (it.offs or 0) + math.max(0, xf(visLeft) - it.s) / fps * (it.rate or 1),
                 (math.min(L.x2, visLeft + viewW) - math.max(L.x1, visLeft))
                     / (L.x2 - L.x1) * (it.e - it.s) / fps * (it.rate or 1),
                 wv)
        if L.x2 - L.x1 > 30 then
            reaper.ImGui_DrawList_AddText(dl, L.x1 + 4, L.oy + 4,
                isLit and 0x000000EE or 0x000000BB,
                conformShorten(it.name, math.floor((L.x2 - L.x1) / 7)))
        end

        -- new side: the pieces it becomes, with the gaps between them left showing
        for _, pc in ipairs(pieces) do
            local p1, p2 = fx(pc.newS), fx(pc.newS + pc.len)
            if p2 - p1 < 2 then p2 = p1 + 2 end
            reaper.ImGui_DrawList_AddRectFilled(dl, p1, L.ny + 2, p2, L.ny + rowH - 3,
                                                withAlpha2(col, a), 2)
            laneWave(dl, it, math.max(p1, visLeft), math.min(p2, visLeft + viewW),
                     L.ny + 2, rowH - 5,
                     (it.offs or 0) + (pc.oldS - it.s) / fps * (it.rate or 1)
                         + math.max(0, xf(visLeft) - pc.newS) / fps * (it.rate or 1),
                     (math.min(p2, visLeft + viewW) - math.max(p1, visLeft))
                         / math.max(p2 - p1, 1) * pc.len / fps * (it.rate or 1),
                     wv)
            if pc.oldS > it.s then
                reaper.ImGui_DrawList_AddLine(dl, p1, L.ny + 1, p1, L.ny + rowH - 2,
                                              0x000000DD, 1)
            end

            -- Landed on top of something else. Drawn over the move outline, because
            -- a collision matters more than how the item got there.
            if conformOverlaps[it.guid] then
                reaper.ImGui_DrawList_AddRect(dl, p1 - 1, L.ny + 1, p2 + 1, L.ny + rowH - 2,
                                              0xE06C75FF, 2, 0, 2)
            end

            -- An item nudged by hand is outlined in its own colour: nothing in the
            -- conform would have put it there, so it should not look like something
            -- the conform decided.
            if (conformShift[it.guid] or 0) ~= 0 then
                reaper.ImGui_DrawList_AddRect(dl, p1, L.ny + 2, p2, L.ny + rowH - 3,
                                              withAlpha2(LANE_MOVED, isLit and 0xFF or 0xAA),
                                              2, 0, 2)
            end

            -- The tie from where material lands back to where it plays from. Shown for
            -- every item while a lane is driving -- that is when the question "what
            -- came from where" is the one being asked -- and only for the lit one
            -- otherwise, where it would just be clutter over the match ribbons.
            if laneFocus and not (isLit and litPc and pc.newS == litPc.newS) then
                local a1, a2 = fx(pc.oldS), fx(pc.oldS + pc.len)
                reaper.ImGui_DrawList_AddLine(dl, (a1 + a2) / 2, L.oy + rowH - 2,
                                              (p1 + p2) / 2, L.ny + 1,
                                              withAlpha2(col, 0x66), 2)
            end

            -- The piece being asked about, tied to the material it plays from. Both
            -- ends are outlined so it reads as one correspondence rather than two
            -- unrelated highlights.
            if isLit and litPc and pc.newS == litPc.newS then
                local a1, a2 = fx(litPc.oldS), fx(litPc.oldS + litPc.len)
                reaper.ImGui_DrawList_AddRect(dl, a1 - 1, L.oy + 1, a2 + 1, L.oy + rowH - 2,
                                              colorWhite, 2, 0, 2)
                reaper.ImGui_DrawList_AddRect(dl, p1 - 1, L.ny + 1, p2 + 1, L.ny + rowH - 2,
                                              colorWhite, 2, 0, 2)
                reaper.ImGui_DrawList_AddLine(dl, (a1 + a2) / 2, L.oy + rowH - 2,
                                              (p1 + p2) / 2, L.ny + 1, 0xFFFFFFDD, 3)
            end
        end

        if prot then
            local pa = (prot.mode == "right") and prot.at or it.s
            local pb = (prot.mode == "left")  and prot.at or it.e
            reaper.ImGui_DrawList_AddLine(dl, fx(pa), L.oy + rowH - 3,
                                          fx(pb), L.oy + rowH - 3, LANE_PROT, 2)
        end
        -- Shown whichever row has focus: it is what the buttons below are pointed at,
        -- so losing it on the way to pressing one of them was the wrong moment.
        if conformLaneSel == it.guid then
            reaper.ImGui_DrawList_AddRect(dl, L.x1 - 1, L.oy + 1, L.x2 + 1, L.oy + rowH - 2,
                                          withAlpha2(colorWhite, laneFocus and 0x99 or 0x55),
                                          2, 0, 1)
        end
    end

    -- ---- the edit plan, over the lane it would be applied to -----------------
    -- Drawn on the old side only, because that is the timeline being cut. The shaded
    -- span is the whole gap the edit could live in -- anywhere in it works, since no
    -- item occupies it -- and the line is where it would go if nothing says otherwise.
    if conformCutPlan then
        local itemsTop = laneOldY + headH   -- items start below the tags
        for _, c in ipairs(conformCutPlan.cuts) do
            local g1, g2 = fx(c.gapS), fx(c.gapE)
            reaper.ImGui_DrawList_AddRectFilled(dl, g1, itemsTop, g2, laneOldY + laneH,
                                                0xE5C07B26)
            local x = fx(c.at)
            reaper.ImGui_DrawList_AddLine(dl, x, itemsTop, x, laneOldY + laneH,
                                          0xE5C07BFF, 2)

            -- Where that edit lands on the new timeline. It is a span rather than a
            -- point: an insert opens the room between the two offsets, a removal
            -- closes it, and either way both edges are worth seeing.
            local n1 = fx(c.at + (c.dPrev or 0))
            local n2 = fx(c.at + (c.dNext or 0))
            if n2 < n1 then n1, n2 = n2, n1 end
            if n2 - n1 > 1 then
                reaper.ImGui_DrawList_AddRectFilled(dl, n1, laneNewY, n2, laneNewY + laneH,
                                                    0xE5C07B26)
            end
            reaper.ImGui_DrawList_AddLine(dl, n1, laneNewY, n1, laneNewY + laneH,
                                          0xE5C07BFF, 2)
            if n2 - n1 > 1 then
                reaper.ImGui_DrawList_AddLine(dl, n2, laneNewY, n2, laneNewY + laneH,
                                              0xE5C07BAA, 1)
            end

            -- Tied across while a lane is driving, for the same reason the item ties
            -- are: that is when the two timelines are being read against each other.
            if laneFocus then
                reaper.ImGui_DrawList_AddLine(dl, x, laneOldY + laneH,
                                              n1, laneNewY, 0xE5C07B88, 2)
            end

            local lbl = string.format("%+d", c.delta)
            local tw  = reaper.ImGui_CalcTextSize(ctx, lbl)
            reaper.ImGui_DrawList_AddRectFilled(dl, x - tw / 2 - 4, laneOldY + 1,
                                                x + tw / 2 + 4, laneOldY + headH - 2,
                                                0xE5C07BFF, 3)
            reaper.ImGui_DrawList_AddText(dl, x - tw / 2, laneOldY + 2, 0x000000DD, lbl)
        end
        -- the two kinds of problem, where they are, in red
        for _, pr in ipairs(conformCutPlan.problems) do
            local a, b
            if pr.kind == "nogap" then a, b = pr.a.e, pr.b.s else a, b = pr.a.s, pr.a.e end
            local x1, x2 = fx(a), fx(b)
            if x2 - x1 < 3 then x2 = x1 + 3 end
            reaper.ImGui_DrawList_AddRectFilled(dl, x1, laneOldY, x2, laneOldY + laneH,
                                                0xE06C7533)
            reaper.ImGui_DrawList_AddRect(dl, x1, laneOldY, x2, laneOldY + laneH,
                                          0xE06C75CC, 0, 0, 1)
        end
    end

    if not hoverItem then return end

    local pieces = conformItemPieces(hoverItem, breaks)
    local prot   = conformProtect[hoverItem.guid]
    local rows   = {
        hoverItem.name .. "   (" .. hoverItem.track .. ")",
        string.format("%s  to  %s", conformTC(hoverItem.s, fps), conformTC(hoverItem.e, fps)),
    }
    if hoverPiece then
        rows[#rows + 1] = string.format("plays from %s in the original",
                                        conformTC(hoverPiece.oldS, fps))
        if hoverLane == "new" then rows[#rows + 1] = "click to put the playhead there" end
    end
    local clash = conformOverlaps and conformOverlaps[hoverItem.guid]
    if clash then
        local names = {}
        for _, o in ipairs(clash) do names[#names + 1] = conformShorten(o.name, 18) end
        rows[#rows + 1] = "overlaps " .. table.concat(names, ", ")
        rows[#rows + 1] = "right click to line it up again"
    end
    local moved = conformShift[hoverItem.guid] or 0
    if moved ~= 0 then
        rows[#rows + 1] = string.format("moved by hand, %+d frames (%+.2fs)", moved, moved / fps)
    end
    if conformIgnore[hoverItem.guid] then
        rows[#rows + 1] = "left out of the conform  -  press Use to bring it back"
    elseif prot then
        rows[#rows + 1] = "pinned " .. prot.mode .. " from " .. conformTC(prot.at, fps)
        rows[#rows + 1] = "this stretch is protected from cuts"
    elseif #pieces > 1 then
        rows[#rows + 1] = string.format("the conform would cut this into %d pieces", #pieces)
        rows[#rows + 1] = "right click to pin it, or press h"
    else
        rows[#rows + 1] = "lands in one piece"
    end
    if hoverItem.muted then rows[#rows + 1] = "muted" end
    reaper.ImGui_SetTooltip(ctx, table.concat(rows, "\n"))
end


-- Opened from the timeline when an item is right clicked, and drawn from
-- drawConformSection so the popup is not inside the scrolling child.
function conformLaneMenu()
    if not conformLaneMenuFor then return end
    local it, at, d = conformLaneMenuFor.item, conformLaneMenuFor.at, conformLaneMenuFor.d
    if reaper.ImGui_BeginPopup(ctx, "##cflanemenu") then
        reaper.ImGui_TextColored(ctx, colorGrey, conformShorten(it.name, 34))
        reaper.ImGui_Separator(ctx)

        local function pin(mode, label, tip)
            if reaper.ImGui_Button(ctx, label .. "##cflane" .. mode) then
                conformPushUndo()
                conformProtect[it.guid] = { mode = mode, at = math.floor(at), d = d }
                conformLaneSel = it.guid
                conformTouchState()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            setToolTipFunc(tip)
        end
        pin("both",  "Use item from here, both directions",
            "The block you clicked stays exactly where it is, and the rest of the item\n" ..
            "extends rigidly out from it in both directions. Nothing inside it is cut.\n" ..
            "So pinning the block after an insert makes the item start later, by however\n" ..
            "much was added before it.")
        pin("left",  "Use item from here, to the left",
            "The block you clicked stays put and the item extends back from it; after\n" ..
            "this point it is still cut where the conform says.")
        pin("right", "Use item from here, to the right",
            "The block you clicked stays put and the item extends forward from it;\n" ..
            "before this point it is still cut where the conform says.")

        -- One entry per thing it has landed on, because which one to line up against
        -- is a judgement: two cues may both have moved, and only you know which is in
        -- the right place.
        local clash = conformOverlaps and conformOverlaps[it.guid]
        if clash and #clash > 0 then
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_TextColored(ctx, 0xE06C75FF, "overlapping")
            local breaks = conformMapBreaks()
            for n, other in ipairs(clash) do
                local want = conformAlignShift(it, other, breaks)
                local move = want - (conformShift[it.guid] or 0)
                local lbl  = string.format("Align to %s   (%+d frames)##cfalign%d",
                                           conformShorten(other.name, 20), move, n)
                if reaper.ImGui_Button(ctx, lbl) then
                    conformPushUndo()
                    conformShift[it.guid] = want
                    conformTouchState()
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                setToolTipFunc(string.format(
                    "Put this back the same distance from %s as it was in the session.\n" ..
                    "It moves %+d frames (%+.2fs). Keeping cues their original distance\n" ..
                    "apart is usually what is wanted, and it tends to need fewer cuts.",
                    conformShorten(other.name, 24), move, move / ((conformResult
                        and conformResult.info and conformResult.info.fpsA) or 25)))
            end
        end

        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Button(ctx, "Remove##cflanerm") then
            conformPushUndo()
            conformProtect[it.guid] = nil
            conformShift[it.guid]   = nil
            conformTouchState()
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        setToolTipFunc("Let the conform cut this item as it would have, and drop any nudge.")

        -- Read before the button, not after: the click clears it, and the tooltip below
        -- still runs on that same frame.
        local nudged = conformShift[it.guid] or 0
        if nudged ~= 0 then
            if reaper.ImGui_Button(ctx, "Reset position##cflaneshift") then
                conformPushUndo()
                conformShift[it.guid] = nil
                conformTouchState()
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            setToolTipFunc(string.format("Undo the %+d frame nudge, keeping the pin", nudged))
        end

        reaper.ImGui_EndPopup(ctx)
    else
        conformLaneMenuFor = nil
    end
end

-- Add tracks, list what has been added, and the muted-items toggle. Right clicking the
-- add button is where the toggle lives, as asked; it is also on the list row so it can
-- be found without knowing that.
function conformTrackControls()
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 8, 1)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Add tracks to overview##cflaneadd") then
        local n = conformAddSelectedTracks()
        conformLaneNote = (n > 0) and string.format("added %d", n)
                          or "select the tracks in the arrange view first"
    end
    setToolTipFunc("Show the items on the selected tracks against the conform, and what\n" ..
                   "would happen to them. Right click for options.")
    if reaper.ImGui_IsItemClicked(ctx, 1) then
        reaper.ImGui_OpenPopup(ctx, "##cflaneopts")
    end

    if reaper.ImGui_BeginPopup(ctx, "##cflaneopts") then
        local mch, mv = reaper.ImGui_Checkbox(ctx, "show muted items",
                                              settings.conform_lane_muted or false)
        if mch then
            settings.conform_lane_muted = mv
            saveSettings()
            conformLaneKey = nil
        end
        if #conformTracks > 0 then
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "keep whole / follow the picture")
            for i = #conformTracks, 1, -1 do
                local t = conformTracks[i]
                if reaper.ImGui_SmallButton(ctx, "x##cflanetr" .. i) then
                    conformRemoveTrack(i)
                else
                    reaper.ImGui_SameLine(ctx)
                    local keep = (t.mode or "keep") == "keep"
                    if reaper.ImGui_SmallButton(ctx,
                            (keep and "keep" or "cut") .. "##cflanemode" .. i) then
                        t.mode = keep and "cut" or "keep"
                        conformLaneKey = nil
                        conformTouchState()
                    end
                    setToolTipFunc(keep
                        and "Items here must survive: the conform is not allowed to cut them.\n" ..
                            "Click to let this track follow the picture instead."
                        or  "Items here follow the picture and are cut with it -- sound design,\n" ..
                            "a reused dialogue track. Click to protect them instead.")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_Text(ctx, t.name)
                end
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end

    if #conformTracks > 0 then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey,
            string.format("%d track%s", #conformTracks, #conformTracks == 1 and "" or "s"))
        setToolTipFunc("Right click the button to list them, set whether each is kept\n" ..
                       "whole or follows the picture, or remove one")

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Find cuts##cffind") then
            local fpsA = (conformResult and conformResult.info and conformResult.info.fpsA) or 25
            local c, p, n = conformFindCuts(conformIP1, fpsA)
            conformCutPlan = { cuts = c, problems = p, kept = n }
        end
        setToolTipFunc("Work out the fewest edits to the old timeline that put every kept\n" ..
                       "item where it needs to be. One edit per change of offset, each placed\n" ..
                       "in a gap so nothing has to be cut through.")

        -- Only once there is a plan: this applies that plan, and a button that first
        -- works out what to do and then does it would leave nothing to look at in
        -- between -- which is the one step worth looking at.
        if conformCutPlan and #conformCutPlan.cuts > 0 then
            -- Read before the button: pressing it clears the plan, and a tooltip built
            -- afterwards would be formatting a count that no longer exists.
            local nCuts = #conformCutPlan.cuts
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cut##cfcut") then
                local fpsA = (conformResult and conformResult.info and conformResult.info.fpsA) or 25
                local n = conformApplyCuts(conformIP1, fpsA, conformCutPlan.cuts)
                conformLaneNote = string.format("cut: %d edit%s applied", n, n == 1 and "" or "s")
                -- The session has moved under the lanes, so everything derived from item
                -- positions is stale. The plan goes too: it described a timeline that no
                -- longer exists, and so do the undo steps, which hold offsets measured
                -- against it.
                conformCutPlan = nil
                conformLaneKey = nil
                conformClearUndo()
            end
            setToolTipFunc(string.format(
                "Apply those %d edit%s to the session: insert or remove time at each one,\n" ..
                "rippling every track so automation moves with the items.\n\n" ..
                "Items sitting across an edit are cut into more pieces -- pin an item\n" ..
                "first if it must survive whole. One REAPER undo step covers the lot.",
                nCuts, nCuts == 1 and "" or "s"))
        end
    end

    if conformLaneNote then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, conformLaneNote)
    end
end


-- A peak envelope, drawn symmetrically about a centre line. Two values per bucket: the
-- peak as a dim outline and the mean of the peaks within it as a bright body. The peak
-- alone makes every busy passage look equally loud, since one transient fills the
-- strip; the mean is what separates sustained level from a spike.
local function drawWaveStrip(dl, x0, x1, y, h, env, gain, isFocus)
    local mid  = y + h * 0.5
    local half = h * 0.5 - 1
    reaper.ImGui_DrawList_AddRectFilled(dl, x0, y, x1, y + h, 0x00000055)
    if not env or #env.peak == 0 then
        reaper.ImGui_DrawList_AddLine(dl, x0, mid, x1, mid, 0xFFFFFF18, 1)
        return
    end

    -- One tone, not two. Drawing the peak and the mean as separate shades made the peak
    -- read as a glowing ghost hovering around a thin core rather than as a single
    -- waveform, and it cost two draw calls per pixel column. REAPER's own display of
    -- the same file is a single shape, and so is this now.
    local n     = #env.peak
    local w     = (x1 - x0) / n
    local col   = isFocus and 0x9DC4E4FF or 0x7FA3BE99
    local k     = gain
    local soft  = k > 1.0001
    local denom = soft and (1.0 - math.exp(-k)) or 1.0

    for i = 1, n do
        local v = env.peak[i]
        if v > 0 then
            -- Boosting used to be a multiply and a hard clamp, which turned every loud
            -- passage into a solid block flat against the ceiling -- the whole point of
            -- the gain is to see quiet dialogue, and that is exactly when the loud parts
            -- clip. A saturating curve instead: near-linear at the bottom, compressing
            -- towards the top, with full scale still landing at full height.
            local p = soft and ((1.0 - math.exp(-k * v)) / denom) or v
            if p > 0.004 then
                local xa = x0 + (i - 1) * w
                local xb = xa + w + 0.5    -- slight overlap, so buckets leave no seams
                reaper.ImGui_DrawList_AddRectFilled(dl, xa, mid - p * half, xb, mid + p * half, col)
            end
        end
    end
    reaper.ImGui_DrawList_AddLine(dl, x0, mid, x1, mid, 0xFFFFFF22, 1)
end

-- The same curve the strip uses, exposed so its behaviour can be checked without a UI.
function conformWaveScale(v, gain)
    if v <= 0 then return 0 end
    if gain <= 1.0001 then return v end
    return (1.0 - math.exp(-gain * v)) / (1.0 - math.exp(-gain))
end

-- Two timelines, old above and new below, with matched material drawn as ribbons
-- between them. The ribbons are the point: where they run straight the cut is
-- untouched, and every insert, deletion and relocation shows up where they skew,
-- pinch or stop. Drawn even before a match exists, so the versions can be played
-- against each other straight away.
--
-- Each version's sound sits on the far side of its own bar -- old above the old
-- timeline, new below the new one -- which leaves the two bars adjacent in the middle
-- where the ribbons need them, and puts each waveform next to the blocks it explains.
--
-- The whole stack lives in one horizontally scrolling child so that zooming keeps the
-- two versions on a single shared scale. Giving each bar its own scale would make them
-- fill the width equally and quietly destroy the one thing this view is for: seeing
-- where the new cut has drifted away from the old one.
function drawConformTimelines(IP1, IP2, framesA, framesB, fpsA, fpsB)
    local R       = conformResult
    local changes = R and R.changes or nil
    -- Same margin as the previews above, so the timeline, the frames and the timecodes
    -- all share one pair of vertical edges.
    -- A gutter on the left for the per-row speakers, directly under the sync button
    -- that decides whether any of them apply. It is taken out of the timeline's width
    -- rather than the page margin, so the timeline is inset from the previews above by
    -- this much -- the two were never on a shared axis anyway, since the previews are
    -- two slots with a gap and this is one continuous scale.
    local gut     = CONFORM_SPEAKER_W
    local viewW   = math.max(120, winW - 2 * CONFORM_MARGIN - gut)
    local barH    = 22
    -- Constant, not R and 54 or 20: the window is sized to its content every frame, so
    -- a height that changes when a match arrives reads as the whole UI jumping.
    local connH   = 54
    local waveOn  = conformWaveAvailable() and (settings.conform_wave ~= false)
    local wfH     = waveOn and 76 or 0
    local sbH     = 16                       -- room for the horizontal scrollbar
    local rulerH  = 13                       -- its own row, so labels never sit on a waveform
    local maxFrames = math.max(framesA, framesB, 1)
    -- Session lanes sit outside the waveforms: the old one above everything, the
    -- preview of what it becomes below everything, so each is next to the side it
    -- belongs to and the pair brackets the comparison.
    -- As many rows as it takes to show overlapping items side by side rather than one
    -- on top of the other. conformLaneItems works the packing out; it is read here from
    -- the previous pass, which is a frame stale only on the frame a track is added.
    local laneRowsH = (#conformTracks > 0)
                      and (math.max(1, conformLaneRows or 1) * CONFORM_LANE_ROW) or 0
    local laneH     = laneRowsH
    local laneOldH  = (laneRowsH > 0) and (laneRowsH + conformLaneHead()) or 0
    local stackH  = rulerH + laneOldH + wfH + barH + connH + barH + wfH + laneH
    conformViewW  = viewW

    -- Waveform stores. Analysis is kicked off here so the strips fill in by themselves,
    -- and what it writes is exactly what the sound matching stage reads, so nothing
    -- gets analysed twice.
    local waveStore, waveWait, waveErr = {}, {}, {}
    if waveOn then
        local sides = { old = IP1, new = IP2 }
        for _, side in ipairs({ "old", "new" }) do
            if sides[side] then
                local s, err, prog = conformWaveStore(sides[side], side)
                waveStore[side], waveErr[side], waveWait[side] = s, err, prog
            end
        end
    end

    reaper.ImGui_Dummy(ctx, 1, 12)
    reaper.ImGui_SameLine(ctx, CONFORM_MARGIN + gut)
    local gutterX = reaper.ImGui_GetCursorScreenPos(ctx) - gut
    conformSpeakerRows = {}
    -- NoScrollWithMouse so the wheel is ours to interpret: ImGui would otherwise spend
    -- it scrolling this child, and opt+wheel would both zoom and pan. The wheel it
    -- declines to use is forwarded to the parent window, which is harmless here because
    -- the parent is resized to its content every frame and so never has scroll of its
    -- own to move.
    if reaper.ImGui_BeginChild(ctx, "##conform_scroll", viewW, stackH + sbH, nil,
                               reaper.ImGui_WindowFlags_HorizontalScrollbar()
                             | reaper.ImGui_WindowFlags_NoScrollWithMouse()) then
        local dl       = reaper.ImGui_GetWindowDrawList(ctx)
        local contentW = viewW * conformZoom

        if conformScrollTries > 0 and conformScrollWant then
            local want = conformScrollWant
            local lim  = math.max(0, contentW - viewW)
            if want < 0   then want = 0 end
            if want > lim then want = lim end
            reaper.ImGui_SetScrollX(ctx, want)
            conformScrollTries = conformScrollTries - 1
            if conformScrollTries <= 0 then conformScrollWant = nil end
        end

        reaper.ImGui_InvisibleButton(ctx, "##conform_vis", contentW, stackH)
        local hovered = reaper.ImGui_IsItemHovered(ctx)
        local rx, ry  = reaper.ImGui_GetItemRectMin(ctx)
        local scrollX = reaper.ImGui_GetScrollX(ctx)

        local laneOldY = ry + rulerH
        local waveOldY = laneOldY + laneOldH
        local topY     = waveOldY + wfH
        local botY     = topY + barH + connH
        local waveNewY = botY + barH
        local laneNewY = waveNewY + wfH

        -- Each row's extent, for the speaker gutter to line up with once this child has
        -- closed. A version's bar and its waveform are one row: they are the same sound.
        conformSpeakerRows = {}
        if laneH > 0 then
            conformSpeakerRows[#conformSpeakerRows + 1] =
                { row = "laneOld", y = laneOldY, h = laneOldH }
        end
        conformSpeakerRows[#conformSpeakerRows + 1] = { row = "old", y = waveOldY, h = wfH + barH }
        conformSpeakerRows[#conformSpeakerRows + 1] = { row = "new", y = botY,     h = barH + wfH }
        if laneH > 0 then
            conformSpeakerRows[#conformSpeakerRows + 1] =
                { row = "laneNew", y = laneNewY, h = laneH }
        end

        -- One shared scale across both bars, so a shorter version visibly ends early
        -- instead of being stretched to fill the width.
        local function fx(f) return rx + (f / maxFrames) * contentW end
        local function xf(x) return (x - rx) / contentW * maxFrames end

        -- rx is the content's left edge, already shifted by the scroll, so this
        -- recovers where the visible window starts. Used for the range to ask the
        -- waveform for, and to pin the row labels so they do not scroll away.
        local visLeft = rx + scrollX
        local f0 = math.max(0, xf(visLeft))
        local f1 = math.min(maxFrames, xf(visLeft + viewW))

        reaper.ImGui_DrawList_AddRectFilled(dl, rx, topY, rx + contentW, topY + barH, colorReallyBlack)
        reaper.ImGui_DrawList_AddRectFilled(dl, rx, botY, rx + contentW, botY + barH, colorReallyBlack)
        if framesA < maxFrames then
            reaper.ImGui_DrawList_AddRectFilled(dl, fx(framesA), topY, rx + contentW, topY + barH, 0x00000044)
        end
        if framesB < maxFrames then
            reaper.ImGui_DrawList_AddRectFilled(dl, fx(framesB), botY, rx + contentW, botY + barH, 0x00000044)
        end

        -- Time grid: the first step whose spacing clears 90 px, so zooming in walks
        -- from half-hours down to seconds without ever crowding.
        local refFps = (fpsB > 0) and fpsB or ((fpsA > 0) and fpsA or 25)
        local pxPerSec = contentW / maxFrames * refFps
        local gstep
        for _, s in ipairs({ 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800 }) do
            if not gstep and s * pxPerSec >= 90 then gstep = s end
        end
        if gstep then
            local t = math.floor(f0 / refFps / gstep) * gstep
            while t <= f1 / refFps do
                local x = fx(t * refFps)
                -- minutes and seconds, not full timecode: at 90 px spacing the frame
                -- field would run into the next label, and frames are what the
                -- transport readout is for
                reaper.ImGui_DrawList_AddText(dl, x + 3, ry, 0xFFFFFF66,
                    string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60)))
                t = t + gstep
            end
        end

        -- Waveforms. Only the visible range is asked for, at one bucket per couple of
        -- pixels, so the cost does not grow with the length of the file.
        if waveOn then
            for _, side in ipairs({ "old", "new" }) do
                local y   = (side == "old") and waveOldY or waveNewY
                local fps = (side == "old") and fpsA or fpsB
                local lim = (side == "old") and framesA or framesB
                if not (fps > 0) then fps = 25 end

                local a  = math.max(0, math.min(f0, lim))
                local b  = math.max(a, math.min(f1, lim))
                local xa, xb = fx(a), fx(b)
                local store  = waveStore[side]

                if store and xb - xa >= 2 then
                    local nb  = math.max(1, math.floor((xb - xa) / WAVE_PX))
                    local env = conformPeaksFor(side, store, a / fps, b / fps, nb)
                    drawWaveStrip(dl, xa, xb, y, wfH, env,
                                  settings.conform_peak_gain or 1.0, conformFocusSide() == side)
                else
                    drawWaveStrip(dl, visLeft, visLeft + viewW, y, wfH, nil, 1, false)
                    local note
                    if waveErr[side] then
                        note = "no sound: " .. tostring(waveErr[side])
                    elseif waveWait[side] then
                        -- %.0f, not %d: progress is hops done over hops total, so times
                        -- 100 it is a number like 26.97, and Lua 5.4's %d rejects any
                        -- float that is not already a whole number rather than rounding
                        note = string.format("reading sound  %.0f%%", (waveWait[side] or 0) * 100)
                    end
                    if note then
                        reaper.ImGui_DrawList_AddText(dl, visLeft + 6, y + wfH / 2 - 7,
                                                      0xFFFFFF77, note)
                    end
                end
            end
        end

        -- Session lanes. Drawn before the blocks so the protected spans are known in
        -- time to grey the matches underneath them.
        local laneItems = {}
        if laneH > 0 then
            laneItems = conformLaneItems(IP1, fpsA)
            drawConformLanes(dl, laneItems, laneOldY, laneNewY, laneH, fx, xf,
                             visLeft, viewW, maxFrames, fpsA)
        end

        conformPairing(R)
        local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)

        -- With nothing compared yet, the band between the bars is where the answer
        -- would be, so that is where the invitation goes. It takes the whole width
        -- because it is the one thing to do, and it pulses only when both versions are
        -- actually there to compare -- a button that nags when it cannot act is noise.
        local bandY, bandH = topY + barH, connH
        conformBandHit = nil
        if not R then
            local ready = IP1 and IP2 and IP1.filePath and IP2.filePath
                          and IP1.filePath ~= "" and IP2.filePath ~= ""
                          and vp_available and reaper.VP_Analyze and not conformStatus
            local over  = hovered and mouseY >= bandY and mouseY <= bandY + bandH
            local col   = ready and (over and withAlpha2(theme.accent, 0xFF)
                                          or pulsatingColor(theme.accent, 3))
                                or 0xFFFFFF10
            reaper.ImGui_DrawList_AddRectFilled(dl, visLeft + 2, bandY + 2,
                                                visLeft + viewW - 2, bandY + bandH - 2, col, 4)
            -- Name the actual obstacle. This said "select a video for both sides"
            -- whatever the reason, so someone without the extension was sent looking
            -- for a selection problem they did not have. The label used to tell Windows
            -- users this could never work for them, the extension having been built on
            -- AVFoundation; it decodes through Media Foundation there now, so the only
            -- thing missing is the package itself, on either platform.
            local label
            if ready then
                label = "Compare"
            elseif not (vp_available and reaper.VP_Analyze) then
                label = "needs the Video Cut Detection Editor extension"
            elseif conformStatus then
                label = "analysing..."
            else
                label = "select a video for both sides"
            end
            reaper.ImGui_PushFont(ctx, font, 18)
            local tw = reaper.ImGui_CalcTextSize(ctx, label)
            reaper.ImGui_DrawList_AddText(dl, visLeft + (viewW - tw) / 2,
                                          bandY + bandH / 2 - 9,
                                          ready and 0x000000DD or 0xFFFFFF66, label)
            reaper.ImGui_PopFont(ctx)
            if ready and over then conformBandHit = true end
        end

        -- Wheel gestures. Zoom is anchored on the frame under the cursor rather than on
        -- the playhead: when the wheel is driving, the cursor is what you are pointing
        -- at, and keeping that frame still is what makes zooming feel like moving a
        -- loupe rather than being thrown around the timeline.
        if hovered and scrollVertical and scrollVertical ~= 0 then
            if isOptionDown and isShiftDown then
                local g = (settings.conform_peak_gain or 1.0) * (1.0 + 0.15 * scrollVertical)
                if g < 1.0  then g = 1.0  end
                if g > 20.0 then g = 20.0 end
                settings.conform_peak_gain = g
                saveSettings()
            elseif isOptionDown then
                local anchor = xf(mouseX)                 -- frame under the cursor
                local z = conformZoom * (1.0 + 0.2 * scrollVertical)
                if z < 1 then z = 1 end
                if z > CONFORM_ZOOM_MAX then z = CONFORM_ZOOM_MAX end
                if z ~= conformZoom then
                    conformZoom = z
                    -- solve fx(anchor) == mouseX for the new scroll, given that the
                    -- child's left edge stays where it is
                    conformScrollTo(visLeft + (anchor / maxFrames) * viewW * z - mouseX)
                end
            else
                local lim = math.max(0, contentW - viewW)
                local v   = scrollX - scrollVertical * (viewW * 0.12)
                if v < 0   then v = 0 end
                if v > lim then v = lim end
                conformScrollTo(v)
            end
        end

        local function blockColor(i, c)
            return (R and R.pairColor and R.pairColor[i]) or conformColors[c.type] or colorGrey
        end
        local function span(i, c, row)
            local st  = (row == "old") and c.aStart or c.bStart
            local len = (row == "old") and c.aLen   or c.bLen
            if len <= 0 then return nil end
            local x1, x2 = fx(st), fx(st + len)
            if x2 - x1 < 2 then x2 = x1 + 2 end
            return x1, x2
        end

        -- Hit test before drawing, so the block under the cursor can be emphasised and
        -- everything else pushed back in the same pass.
        local hoverIdx
        if changes and hovered then
            for i, c in ipairs(changes) do
                for _, row in ipairs({ "old", "new" }) do
                    local y = (row == "old") and topY or botY
                    if mouseY >= y and mouseY <= y + barH then
                        local x1, x2 = span(i, c, row)
                        if x1 and mouseX >= x1 - 1 and mouseX <= x2 + 1 then hoverIdx = i end
                    end
                end
            end
        end
        -- The playhead selects; the mouse only overrides while it is over the timeline.
        -- So scrubbing, playing or stepping highlights the block being looked at even
        -- when the cursor is nowhere near the ribbons.
        conformSelectedIdx = conformIdxAtPlayhead()
        -- While scrubbing, the playhead is the highlight. Letting the mouse take it back
        -- would mean the thing lit up was wherever the cursor happened to be rather than
        -- where you had dragged to, which is the opposite of what a scrub is for.
        local emph = (conformScrubbing and conformSelectedIdx)
                     or hoverIdx or conformSelectedIdx

        local laneDrives = conformFocusIsLane()

        if changes then
            -- Ribbons first so the block edges draw over them. When one pair is
            -- emphasised the rest drop right back, which is what makes a single
            -- correspondence readable in a crowd of them.
            for i, c in ipairs(changes) do
                if (c.type == "matched" or c.type == "moved") and c.aLen > 0 and c.bLen > 0 then
                    local a1, a2 = span(i, c, "old")
                    local b1, b2 = span(i, c, "new")
                    local alpha = laneDrives and 0x14
                                  or ((emph == i) and 0xCC or (emph and 0x10 or 0x3A))
                    reaper.ImGui_DrawList_AddQuadFilled(dl,
                        a1, topY + barH, a2, topY + barH, b2, botY, b1, botY,
                        withAlpha2(blockColor(i, c), alpha))
                end
            end

            for i, c in ipairs(changes) do
                local col  = blockColor(i, c)
                local isE  = (emph == i)
                local pi   = R.pairIndex and R.pairIndex[i]
                for _, row in ipairs({ "old", "new" }) do
                    local x1, x2 = span(i, c, row)
                    if x1 then
                        local y = (row == "old") and topY or botY
                        -- A swapped change has no counterpart: it is an adjacency,
                        -- "this became that", not the same material appearing on both
                        -- sides. So only the side being looked at comes forward --
                        -- fill as well as outline, since a bright block on the other
                        -- row claims the correspondence just as loudly as a border.
                        local lit  = isE and (c.type ~= "swapped" or row == conformFocusSide())
                        -- With a lane driving, the whole match view steps back: it is
                        -- context for what the items are doing rather than the thing
                        -- being worked on, and the same dimming already means exactly
                        -- that when one block is picked out from the others.
                        local fill = (laneDrives or (emph and not lit))
                                     and withAlpha2(col, 0x4C) or col
                        -- Pinning a session item deliberately does NOT grey the match
                        -- under it. The two are different timelines: where the session
                        -- gets cut is a separate question from where the picture
                        -- changed, and a cut can land somewhere the picture did not.
                        reaper.ImGui_DrawList_AddRectFilled(dl, x1, y, x2, y + barH, fill)
                        -- a dark edge so two blocks that happen to share a colour do not
                        -- read as one wider block
                        reaper.ImGui_DrawList_AddLine(dl, x1, y, x1, y + barH, 0x000000AA, 1)
                        if c.type == "moved" then
                            -- relocated material: outline it so it reads apart from
                            -- material that stayed where it was
                            reaper.ImGui_DrawList_AddRect(dl, x1, y, x2, y + barH,
                                withAlpha2(colorWhite, lit and 0xFF or 0x77), 0, 0, 1)
                        end
                        if lit then
                            reaper.ImGui_DrawList_AddRect(dl, x1 - 1, y - 2, x2 + 1, y + barH + 2,
                                                          colorWhite, 0, 0, 2)
                        end
                        -- the pair number pins the correspondence down where colour alone
                        -- repeats, and the palette eventually does repeat
                        if pi and (x2 - x1) > 15 then
                            reaper.ImGui_DrawList_AddText(dl, x1 + 3, y + 3, 0x00000099, tostring(pi))
                        end
                    end
                end
            end
        end

        -- Lane items take the click before the bars do, since they sit outside them.
        local overLaneOld = laneH > 0 and hovered
                            and mouseY >= laneOldY and mouseY < laneOldY + laneOldH
        local overLaneNew = laneH > 0 and hovered
                            and mouseY >= laneNewY and mouseY < laneNewY + laneH
        if conformLaneHit then
            if reaper.ImGui_IsItemClicked(ctx, 1) then
                conformLaneSel = conformLaneHit.item.guid
                -- Pins live in old-frame space, because that is where an item's own
                -- extent is measured. A right click in the NEW lane is a new frame, so
                -- it is converted through the piece under the cursor -- which also
                -- gives the offset that piece currently sits at, and that offset is
                -- what the pin holds.
                local pc  = conformLaneHit.piece
                local at  = conformLaneHit.frame
                local d
                if pc then
                    if conformLaneHit.lane == "new" then at = pc.oldS + (at - pc.newS) end
                    d = pc.newS - pc.oldS
                end
                conformLaneMenuFor = { item = conformLaneHit.item, at = at, d = d,
                                       piece = pc }
                conformLaneOpen    = true
            elseif reaper.ImGui_IsItemClicked(ctx, 0) then
                conformLaneSel = conformLaneHit.item.guid
                conformFocus   = (conformLaneHit.lane == "new") and "laneNew" or "laneOld"

                -- Either way the item becomes the selected one, with its tie shown:
                -- moving something is as much a way of pointing at it as clicking is.
                local pc0 = conformLaneHit.piece
                conformLanePick = pc0 and {
                    guid = conformLaneHit.item.guid,
                    oldS = pc0.oldS, newS = pc0.newS, len = pc0.len,
                } or nil

                if isOptionDown and conformLaneHit.lane == "new" then
                    -- opt begins a move rather than a scrub. Only on the new side:
                    -- the old lane is the session as it stands, which this tool does
                    -- not get to rewrite.
                    conformPushUndo()
                    conformLaneDrag = { guid = conformLaneHit.item.guid,
                                        from = conformLaneHit.frame,
                                        base = conformShift[conformLaneHit.item.guid] or 0 }
                else
                    -- Clicking an item takes focus into its lane, which changes what the
                    -- arrows step through and what the edit buttons act on. Scrubbing
                    -- then works here exactly as it does on the bars, including carrying
                    -- on playing from the new position when it was only a click.
                    conformScrubbing  = conformFocus
                    conformScrubFrom  = mouseX
                    conformScrubMoved = false
                end
            end
        elseif overLaneOld or overLaneNew then
            -- Anywhere in a lane scrubs it, not just on an item: the lane is a timeline
            -- like the bars are, and having to find an item first made it feel like a
            -- list of objects rather than a position in time.
            if reaper.ImGui_IsItemClicked(ctx, 0) then
                conformScrubbing  = overLaneNew and "laneNew" or "laneOld"
                conformFocus      = conformScrubbing
                conformScrubFrom  = mouseX
                conformScrubMoved = false
            end
        end

        if conformLaneDrag then
            if reaper.ImGui_IsMouseDown(ctx, 0) then
                conformShift[conformLaneDrag.guid] =
                    math.floor(conformLaneDrag.base + (xf(mouseX) - conformLaneDrag.from) + 0.5)
            else
                conformLaneDrag = nil
                conformTouchState()   -- once, at the end of the drag
            end
        end

        -- Scrubbing. Pressing on a side gives it focus and takes the playhead from the
        -- mouse; holding and dragging keeps doing so, which is what makes a drag scrub
        -- rather than just jump. A side's waveform counts as part of it, so the top
        -- half of the stack drives old and the bottom half new -- the ribbon band in
        -- between belongs to neither and stays inert.
        -- The band between the bars is split down the middle: its upper half belongs to
        -- the old version and its lower half to the new. It used to be inert, which
        -- wasted the tallest part of the view for pointing at a moment in time.
        local bandMid = topY + barH + connH / 2
        local overOld = hovered and mouseY >= waveOldY and mouseY < bandMid
        local overNew = hovered and mouseY >= bandMid  and mouseY <= waveNewY + wfH
        -- The band is the Compare button while it is one, so it takes the click before
        -- the scrub does.
        if conformBandHit and reaper.ImGui_IsItemClicked(ctx) then
            startConform(IP1, IP2)
        elseif reaper.ImGui_IsItemClicked(ctx) and (overOld or overNew) and not conformLaneHit then
            conformScrubbing  = overOld and "old" or "new"
            conformFocus      = conformScrubbing
            conformScrubFrom  = mouseX
            conformScrubMoved = false
            if hoverIdx then conformSelectedIdx = hoverIdx end
        end
        if conformScrubbing then
            if reaper.ImGui_IsMouseDown(ctx, 0) then
                conformFocus    = conformScrubbing
                -- the lanes scrub their own version, same as the bar above or below
                local newSide   = (conformScrubbing == "new" or conformScrubbing == "laneNew")
                local fpsSide   = newSide and fpsB or fpsA

                -- A press is "play from here"; only moving makes it a scrub. Dragging
                -- through the timeline while it plays would be two clocks fighting over
                -- the playhead, so the first real movement stops playback -- but a click
                -- that lands and stays put carries on from the new position.
                --
                -- conformHalt rather than clearing the flag: in sync mode the project
                -- transport has to come to a stop too, or REAPER carries on rolling
                -- underneath a playhead that is now being dragged by hand.
                if conformScrubBecameDrag(mouseX) and conformPlaying then conformHalt() end

                conformPlayhead = conformClamp(math.floor(xf(mouseX) + 0.5),
                                               newSide and framesB or framesA)
                if conformSyncEnabled() then
                    conformSyncSeek(IP1, fpsA)
                elseif conformPlaying then
                    -- Still rolling, so the sound has to be taken along: without this
                    -- the picture jumps and the audio carries on from where it was,
                    -- and the playhead then rides that stale audio clock straight back.
                    conformSeekPreview(conformPlayhead / ((fpsSide > 0) and fpsSide or 25))
                    conformStopItemPreviews()   -- rebuilt at the new position next pass
                    conformLastTick = nil
                end
            else
                conformScrubbing, conformScrubFrom, conformScrubMoved = nil, nil, false
            end
        end

        -- playheads: solid on the side holding focus, hollow on the one following it
        local oldF, newF = conformPositions(framesA, framesB)
        local function head(y, hh, f, isFocus)
            local x = fx(f)
            reaper.ImGui_DrawList_AddLine(dl, x, y, x, y + hh,
                                          isFocus and 0xFFFFFFFF or 0xFFFFFF77, isFocus and 2 or 1)
            if isFocus then
                reaper.ImGui_DrawList_AddRectFilled(dl, x - 3, y - 5, x + 3, y, colorWhite)
            end
        end
        -- Each playhead spans its own side, waveform included, so it reads as one
        -- position in that version rather than a mark on a bar.
        -- Each playhead spans its version's whole stack, lanes included, so scrubbing
        -- in a lane reads against the picture it belongs to.
        if laneH > 0 then
            head(laneOldY, laneOldH + wfH + barH, oldF, conformFocusSide() == "old")
            head(botY,     barH + wfH + laneH, newF, conformFocusSide() == "new")
        else
            head(waveOldY, wfH + barH, oldF, conformFocusSide() == "old")
            head(botY,     barH + wfH, newF, conformFocusSide() == "new")
        end

        -- Follow the focused playhead while playing, or it walks off screen the moment
        -- the view is zoomed in at all.
        if conformPlaying and conformScrollTries <= 0 then
            local pf = (conformFocusSide() == "new") and newF or oldF
            local px = (pf / maxFrames) * contentW
            if px < scrollX + viewW * 0.1 or px > scrollX + viewW * 0.9 then
                conformScrollTo(px - viewW * 0.5)
            end
        end

        -- Pinned to the visible left edge rather than to frame 0, so they stay readable
        -- at any scroll position.
        reaper.ImGui_DrawList_AddText(dl, visLeft + 4, topY + 4,
            conformFocusSide() == "old" and colorWhite or colorGrey, "old")
        reaper.ImGui_DrawList_AddText(dl, visLeft + 4, botY + 4,
            conformFocusSide() == "new" and colorWhite or colorGrey, "new")

        -- One SetTooltip call with the text assembled up front, matching how the rest of
        -- the script does tooltips. No Begin/End pair to get wrong.
        if hoverIdx and changes then
            local c    = changes[hoverIdx]
            local pi   = R.pairIndex and R.pairIndex[hoverIdx]
            local rows = { pi and ("pair " .. pi .. "  -  " .. c.type) or c.type }
            if c.aLen > 0 then
                rows[#rows + 1] = string.format("old   %s   %d frames", conformTC(c.aStart, fpsA), c.aLen)
            end
            if c.bLen > 0 then
                rows[#rows + 1] = string.format("new   %s   %d frames", conformTC(c.bStart, fpsB), c.bLen)
            end
            if c.bLen ~= c.aLen then
                rows[#rows + 1] = string.format("%+d frames (%+.2fs)", c.bLen - c.aLen, (c.bLen - c.aLen) / fpsB)
            end
            if c.meanHam then
                rows[#rows + 1] = string.format("confidence %.2f  %s", c.meanHam,
                    c.meanHam > 6 and "- doubtful, check this one"
                                  or (c.meanHam > 2 and "- fair" or "- strong"))
            end
            if c.src == "audio" then
                rows[#rows + 1] = "matched on sound, not picture"
            end
            reaper.ImGui_SetTooltip(ctx, table.concat(rows, "\n"))
        end

        reaper.ImGui_EndChild(ctx)
    end

    -- Outside the child, so it does not scroll with the timeline, but drawn from the
    -- row positions the child recorded so it still lines up with them.
    conformDrawSpeakerGutter(gutterX, gut)
end

local function conformFramePath(filePath, frame, fps, useCutHandle)
    if not vp_available or not filePath or filePath == "" then return nil end
    local h = useCutHandle and vpGetHandleCut(filePath) or vpGetHandle(filePath)
    if not h then return nil end
    local w, hh = vpPreviewWH()
    local p = reaper.VP_GetFrame(h, frame / ((fps > 0) and fps or 25), w, hh)
    return (p and p ~= "") and p or nil
end

-- Old on the left, new on the right, both at corresponding moments.
-- Which item each side uses, pinned per side. Without this the two sides are simply the
-- first and second selected items, so there is no way to say "compare this one against
-- that one" except by selecting them in the right order and then never touching the
-- selection again.
--
-- Pinned by GUID rather than by pointer: a pointer goes stale on undo or reload, and a
-- freed one can be handed back for a different item. The pointer is kept alongside as a
-- cache so the project is only scanned when it stops being valid.
conformPin = { old = nil, new = nil }   -- [side] = { guid = ..., item = ... }

local function itemGUID(it)
    local ok, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    return (ok and g ~= "") and g or nil
end

function conformResolvePin(side)
    local p = conformPin[side]
    if not p then return nil end
    if p.item and reaper.ValidatePtr2(0, p.item, "MediaItem*") and itemGUID(p.item) == p.guid then
        return p.item
    end
    for i = 0, reaper.CountMediaItems(0) - 1 do
        local it = reaper.GetMediaItem(0, i)
        if itemGUID(it) == p.guid then p.item = it; return it end
    end
    conformPin[side] = nil        -- the item is gone; fall back to the selection
    return nil
end

-- Binds a side to an item, without disturbing anything else. Used both by the buttons
-- and by the automatic pin that happens the first time a side is filled.
function conformPinItem(side, it)
    if not it then return false end
    local g = itemGUID(it)
    if not g then return false end
    conformPin[side] = { guid = g, item = it }
    return true
end

-- Takes the first item selected in the arrange view for this side. That is the gesture
-- the whole thing turns on: select it in the timeline, click the side you mean.
function conformPinSelected(side)
    local first = reaper.GetSelectedMediaItem(0, 0)
    if not first then return false end
    local g1 = itemGUID(first)
    if not g1 then return false end

    -- Two items selected takes both sides at once, in selection order, whichever of
    -- the buttons was clicked. Moving to a different pair of versions is the common
    -- case, and doing it in one click beats pinning each side separately.
    local second = reaper.GetSelectedMediaItem(0, 1)
    local g2 = second and itemGUID(second) or nil
    if second and g2 and g2 ~= g1 then
        conformPin.old = { guid = g1, item = first }
        conformPin.new = { guid = g2, item = second }
    else
        conformPin[side] = { guid = g1, item = first }
    end

    conformResult, conformSelectedIdx = nil, nil   -- the old match described other files
    conformStopPreview()
    return true
end

-- The source file behind the first selected item, so sound can be picked off the
-- timeline the same way picture is.
function conformSelectedItemSource()
    local it = reaper.GetSelectedMediaItem(0, 0)
    if not it then return nil end
    local tk = reaper.GetActiveTake(it)
    if not tk then return nil end
    local src = reaper.GetMediaItemTake_Source(tk)
    if not src then return nil end
    local fn = reaper.GetMediaSourceFileName(src, "")
    return (fn and fn ~= "") and fn or nil
end

-- Global rather than local: the button widths are measured from the audio section,
-- which sits above this one in the file.
function conformShorten(s, n)
    if #s > n then return s:sub(1, n - 2) .. ".." end
    return s
end

function conformVideoButton(IP, side)
    local full = (IP and IP.fileName) or nil
    local name = conformShorten(full or "no video", 26)
    if reaper.ImGui_Button(ctx, name .. "##cfvid" .. side) then
        if conformPinSelected(side) then
            conformError = nil
        else
            conformError = "Select the item you want as the " .. side ..
                           " version in the arrange view, then click this button."
        end
    end
    -- The label is cut to 26 characters, and version names are long and differ at the
    -- end -- "..._v16_uMusik" against "..._v16_uMusik_fix" -- so the full name is the
    -- first thing the tooltip says.
    setToolTipWithName(full,
                       "Video used as the " .. side .. " version.\n" ..
                       "Click to take the first item selected in the arrange view.")
end


-- One margin for everything in this tab: previews, timecodes and the timeline all line
-- up on the same two vertical edges, so the eye has one column to follow rather than
-- three slightly different ones.
CONFORM_MARGIN = 16
CONFORM_GAP    = 26     -- between the previews; the swap button fills it exactly
-- Black, so a frame that does not fill its slot is surrounded by the same nothing a
-- player would surround it with, rather than by a grey that reads as part of the UI.
conformSlotBg  = 0x000000FF

function conformMetrics()
    local m     = CONFORM_MARGIN
    local gap   = CONFORM_GAP
    local slotW = math.floor((winW - 2 * m - gap) / 2)
    return m, gap, slotW, m, m + slotW + gap
end

-- OLD and NEW at the outer edges with the matching controls between them. Plain, not
-- lit by focus: focus is already shown by the playheads and the timecodes, and having
-- the two largest words on screen change colour as you work was more movement than
-- information.
-- Just the two words, over the frames they label.
-- A line at the top of the tab saying what this is. Italic, because it is a note about
-- the tab rather than part of it, and dimmed because it is an invitation rather than a
-- warning -- the error line underneath is the red one.
--
-- The size comes from GetFontSize rather than a literal, so the notice matches whatever
-- the body text is: PushFont wants an unscaled base size and there is no call that
-- reports one, but a real pixel height is never going to render as nothing, which a
-- guessed 0 might. If fontItalic could not be made this pushes nil, which leaves the
-- face alone and simply draws it upright.
function conformDevNotice()
    reaper.ImGui_Dummy(ctx, 1, 2)
    reaper.ImGui_SameLine(ctx, CONFORM_MARGIN)
    reaper.ImGui_PushFont(ctx, fontItalic, reaper.ImGui_GetFontSize(ctx))
    reaper.ImGui_TextColored(ctx, 0xFFFFFF88,
        "This tab is still in development -- but do play around with it and test it.")
    reaper.ImGui_PopFont(ctx)
    setToolTipFunc("Comparing two cuts and conforming a session to the new one is the newest\n" ..
                   "part of this script. It can still get a conform wrong, so check what it\n" ..
                   "tells you before you cut anything you care about -- and say when it does.")
end

function conformHeaderRow()
    local m, gap, slotW, x0, x1 = conformMetrics()
    reaper.ImGui_PushFont(ctx, font, 21)
    local wNew = reaper.ImGui_CalcTextSize(ctx, "NEW")
    reaper.ImGui_Dummy(ctx, 1, 1)
    reaper.ImGui_SameLine(ctx, x0)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "OLD")
    reaper.ImGui_SameLine(ctx, x1 + slotW - wNew)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "NEW")
    reaper.ImGui_PopFont(ctx)
end

-- ---------------------------------------------------------------------------
-- Correcting the conform by hand
-- ---------------------------------------------------------------------------
-- Any automated conform is sometimes wrong, so the result has to be editable. These
-- work on the matched runs and then re-derive everything from them, which keeps the
-- change list, the damage figure and the ribbons consistent with each other -- they are
-- all views of the same run list and none of them is edited directly.

-- Undo for the timeline. Its own stack rather than the script's `undo_stack`, which
-- belongs to the Cut Detection tab's cut_data: sharing it would mean undo here reaching
-- back and renaming a cut over there.
--
-- Snapshots rather than inverse operations, because the two editable things -- the
-- matched runs and the item pins -- interact through the derived change list, and a
-- snapshot of both together means one stack covers everything you can do here in the
-- order you did it, regardless of which kind each step was.
conformUndoStack, conformRedoStack = {}, {}

function conformSnapshot()
    local R = conformResult
    return {
        runs   = (R and R.info) and deep_copy(R.info.runs) or nil,
        prot   = deep_copy(conformProtect or {}),
        shift  = deep_copy(conformShift or {}),
        ignore = deep_copy(conformIgnore or {}),
        edited = R and R.edited or nil,
    }
end

function conformPushUndo()
    conformUndoStack[#conformUndoStack + 1] = conformSnapshot()
    if #conformUndoStack > 64 then table.remove(conformUndoStack, 1) end
    conformRedoStack = {}
end

function conformClearUndo()
    conformUndoStack, conformRedoStack = {}, {}
end

local function conformRestoreSnapshot(s)
    conformProtect = deep_copy(s.prot or {})
    conformShift   = deep_copy(s.shift or {})
    conformIgnore  = deep_copy(s.ignore or {})
    conformLaneKey = nil                       -- the lanes are rebuilt from the pins
    if s.runs and conformResult and conformResult.info then
        conformApplyRuns(deep_copy(s.runs))
        conformResult.edited = s.edited        -- applyRuns sets it; the snapshot wins
    end
end

function conformUndo()
    if #conformUndoStack == 0 then return false end
    conformRedoStack[#conformRedoStack + 1] = conformSnapshot()
    conformRestoreSnapshot(table.remove(conformUndoStack))
    return true
end

function conformRedo()
    if #conformRedoStack == 0 then return false end
    conformUndoStack[#conformUndoStack + 1] = conformSnapshot()
    conformRestoreSnapshot(table.remove(conformRedoStack))
    return true
end

-- Puts a new run list in place and rebuilds what is derived from it.
function conformApplyRuns(runs)
    local R = conformResult
    if not R or not R.info then return end
    table.sort(runs, function(x, y) return x.bStart < y.bStart end)
    R.info.runs = runs
    R.changes   = vpClassifyChanges(R.info)
    R.damage    = vpDamage(R.info, R.changes)
    R.pairColor, R.pairIndex, R.pairCount = nil, nil, nil   -- recoloured on next draw
    R.edited    = true
    conformSelectAtPlayhead()
    conformTouchState()
end

-- The run the playhead is standing in, by index. Runs rather than changes, because the
-- change list is derived and these operations have to act on the thing it comes from.
function conformRunAtPlayhead()
    local R = conformResult
    if not R or not R.info then return nil end
    local f = math.floor(conformPlayhead)
    for i, r in ipairs(R.info.runs) do
        local st = (conformFocusSide() == "new") and r.bStart or r.aStart
        if f >= st and f < st + r.len then return i end
    end
    return nil
end

-- Two runs can be healed when they sit on the same diagonal: aStart - bStart equal
-- means the material between them corresponds too, so the split is the matcher having
-- given up in the middle rather than a real discontinuity.
--
-- The gap is capped. On an identical diagonal a long gap usually means the frames in
-- between genuinely differ -- a VFX shot dropped into an otherwise untouched stretch --
-- and healing across it would claim material that was never matched.
function conformHealGap()
    local v = settings.conform_heal_gap
    if v == nil then v = 50 end   -- frames; two seconds at 25
    return v
end

function conformCanHeal(a, b)
    if not a or not b then return false end
    if (a.aStart - a.bStart) ~= (b.aStart - b.bStart) then return false end
    local gap = b.bStart - (a.bStart + a.len)
    return gap >= 0 and gap <= conformHealGap()
end

function conformHealAt(i)
    local R = conformResult
    if not R or not R.info then return false end
    local runs = R.info.runs
    local a, b = runs[i], runs[i + 1]
    if not conformCanHeal(a, b) then return false end
    local out = {}
    for k, r in ipairs(runs) do
        if k == i then
            out[#out + 1] = {
                aStart = a.aStart, bStart = a.bStart,
                len    = (b.bStart + b.len) - a.bStart,
                -- the join is only as trustworthy as its weaker half
                meanHam = math.max(a.meanHam or 0, b.meanHam or 0),
                src = a.src,
            }
        elseif k ~= i + 1 then
            out[#out + 1] = r
        end
    end
    conformApplyRuns(out)
    return true
end

function conformHealAll()
    local R = conformResult
    if not R or not R.info then return 0 end
    local runs = {}
    for _, r in ipairs(R.info.runs) do runs[#runs + 1] = r end
    table.sort(runs, function(x, y) return x.bStart < y.bStart end)

    local out, n = {}, 0
    local cur = runs[1]
    for i = 2, #runs do
        if conformCanHeal(cur, runs[i]) then
            cur = {
                aStart = cur.aStart, bStart = cur.bStart,
                len    = (runs[i].bStart + runs[i].len) - cur.bStart,
                meanHam = math.max(cur.meanHam or 0, runs[i].meanHam or 0),
                src = cur.src,
            }
            n = n + 1
        else
            out[#out + 1] = cur
            cur = runs[i]
        end
    end
    if cur then out[#out + 1] = cur end
    if n > 0 then conformApplyRuns(out) end
    return n
end

function conformRemoveAt(i)
    local R = conformResult
    if not R or not R.info or not R.info.runs[i] then return false end
    local out = {}
    for k, r in ipairs(R.info.runs) do
        if k ~= i then out[#out + 1] = r end
    end
    conformApplyRuns(out)
    return true
end

-- ---------------------------------------------------------------------------
-- The same three operations, applied to a session item
-- ---------------------------------------------------------------------------
-- Remove, heal and heal-all mean something in a lane too, and it is near enough the
-- same thing that they share the buttons rather than growing a second set: remove
-- undoes what was done by hand, heal makes the item land in one piece, heal-all does
-- that to every item that needs it.

-- How far apart two pieces have to be before they are treated as different places in
-- the film rather than one shot the matcher split. Past this, averaging them would put
-- the item somewhere neither piece belongs.
function conformHealSpread()
    local v = settings.conform_heal_spread
    if v == nil then v = 5.0 end
    return v
end

function conformItemIsEdited(guid)
    return (conformShift[guid] or 0) ~= 0 or conformProtect[guid] ~= nil
end

-- Clears the hand edits from one item, leaving it to whatever the conform makes of it.
function conformClearItemEdits(guid)
    if not conformItemIsEdited(guid) then return false end
    conformShift[guid]   = nil
    conformProtect[guid] = nil
    conformLaneKey = nil
    conformTouchState()
    return true
end

-- The offset to pin an item at so it lands in one piece: the length-weighted average of
-- its pieces' offsets, counting only the pieces that belong together.
--
-- Averaging is the right answer rather than taking the first piece's offset, because a
-- shot that gained two frames in the middle leaves both halves slightly wrong and the
-- average splits the error instead of handing all of it to one end. Length-weighted so
-- a four-frame sliver does not drag the whole item.
--
-- Pieces further than conformHealSpread seconds from the rest are dropped first: part
-- of the film may have been moved somewhere else entirely, and a piece that landed
-- there is not evidence about where the item as a whole should go. The largest cluster
-- wins, since that is where most of the item's material actually is.
function conformItemHealOffset(it, breaks, fps)
    local pcs = conformItemPieces(it, breaks)
    if #pcs < 2 then return nil end

    local spread = conformHealSpread() * ((fps > 0) and fps or 25)

    -- group pieces whose offsets sit within `spread` of each other
    local sorted = {}
    for _, pc in ipairs(pcs) do
        sorted[#sorted + 1] = { d = pc.newS - pc.oldS, len = pc.len }
    end
    table.sort(sorted, function(a, b) return a.d < b.d end)

    local best, cur = nil, { sorted[1] }
    local function weigh(g)
        local w = 0
        for _, p in ipairs(g) do w = w + p.len end
        return w
    end
    for i = 2, #sorted do
        if (sorted[i].d - sorted[i - 1].d) <= spread then
            cur[#cur + 1] = sorted[i]
        else
            if not best or weigh(cur) > weigh(best) then best = cur end
            cur = { sorted[i] }
        end
    end
    if not best or weigh(cur) > weigh(best) then best = cur end

    local num, den = 0, 0
    for _, p in ipairs(best) do
        num = num + p.d * p.len
        den = den + p.len
    end
    if den <= 0 then return nil end
    return math.floor(num / den + 0.5), #pcs - #best
end

-- Pins one item at that average offset. Returns true when it changed something.
function conformHealItem(it, breaks, fps)
    local d = conformItemHealOffset(it, breaks, fps)
    if not d then return false end
    conformProtect[it.guid] = { mode = "both", at = math.floor((it.s + it.e) / 2), d = d }
    conformShift[it.guid]   = nil      -- the pin carries the position now
    conformLaneKey = nil
    return true
end

function conformHealAllItems(items, breaks, fps)
    local n = 0
    for _, it in ipairs(items) do
        if not it.muted and not conformIgnore[it.guid] and it.mode ~= "cut" then
            if conformHealItem(it, breaks, fps) then n = n + 1 end
        end
    end
    if n > 0 then conformTouchState() end
    return n
end

-- The lane item the buttons would act on, resolved from the standing selection.
function conformSelectedLaneItem()
    if not conformLaneSel then return nil end
    local R   = conformResult
    local fps = (R and R.info and R.info.fpsA > 0) and R.info.fpsA or 25
    for _, c in ipairs(conformLaneItems(conformIP1, fps)) do
        if c.guid == conformLaneSel then return c, fps end
    end
    return nil
end

-- The buttons, and the keys that do the same thing. Disabled rather than hidden when
-- they cannot act, so their positions do not move as the playhead crosses blocks.
--
-- One set of three, shared between the match view and the lanes, because they mean the
-- same three things in both: undo what is here, make this land in one piece, do that
-- everywhere. What they act on is whichever row has focus, which is why the row is
-- named just before them -- without that, the buttons silently changed meaning.
--
-- They are a fixed width for the same reason they are disabled rather than hidden: the
-- first one's label changes with what is selected, and a row that reflows every time
-- the selection changes cannot be used by muscle memory.
local CONFORM_BTN_W = 92

function conformEditButtons()
    local R = conformResult
    if not R then return end

    local laneCtx = conformFocusIsLane()
    local it, fps = conformSelectedLaneItem()
    local keys    = not markerNameIsFocused
    -- Built once: it rebuilds and re-sorts the run boundaries on every call, and the
    -- lane buttons want it up to three times in the same frame.
    local breaks  = laneCtx and conformMapBreaks() or nil

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Dummy(ctx, 8, 1)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "|")
    reaper.ImGui_SameLine(ctx)

    -- What the three buttons are pointed at right now.
    reaper.ImGui_AlignTextToFramePadding(ctx)
    local what = laneCtx and ((it and conformShorten(it.name, 16)) or "track items")
                 or "matches"
    reaper.ImGui_TextColored(ctx, laneCtx and LANE_WHOLE or colorGrey, what)
    setToolTipFunc(laneCtx
        and "These buttons are acting on the track items, because a lane has focus.\n" ..
            "Click a video row, or press up/down, to point them at the matches again."
        or  "These buttons are acting on the matches. Click a track item, or press\n" ..
            "up/down into a lane, to point them at the items instead.")
    reaper.ImGui_SameLine(ctx)

    local idx     = conformRunAtPlayhead()
    local canHeal = idx and conformCanHeal(R.info.runs[idx], R.info.runs[idx + 1])

    -- ---- first button: undo what is here, or take the item out of the conform ------
    -- In a lane the question has three states, and one button carries all three because
    -- they are the same decision at different stages: an item with hand edits offers to
    -- drop them, a clean one offers to be left out, and one already left out offers to
    -- come back.
    local mode   -- "removeRun" | "clearEdits" | "ignore" | "use"
    if not laneCtx then
        mode = "removeRun"
    elseif not it then
        mode = nil
    elseif conformIgnore[it.guid] then
        mode = "use"
    elseif conformItemIsEdited(it.guid) then
        mode = "clearEdits"
    else
        mode = "ignore"
    end

    local labels = { removeRun = "Remove", clearEdits = "Remove", ignore = "Ignore", use = "Use" }
    local tips = {
        removeRun = { "Drop the match the playhead is standing in, so that stretch reads as\n" ..
                      "new material instead.", "delete or backspace" },
        clearEdits = { "Drop the hand edits on this item -- the pin and any nudge -- and let\n" ..
                       "the conform place it again.", "delete or backspace" },
        ignore = { "Leave this item out of the conform. It stops counting towards overlaps\n" ..
                   "and towards the edits, and is drawn faint so it is still findable.",
                   "delete or backspace" },
        use = { "Bring this item back into the conform.", "delete or backspace" },
    }

    local act = (mode == "removeRun" and idx ~= nil) or (mode and mode ~= "removeRun")
    if not act then reaper.ImGui_BeginDisabled(ctx) end
    local pressed = reaper.ImGui_Button(ctx, (labels[mode] or "Remove") .. "##cfrm",
                                        CONFORM_BTN_W, 0)
    if (pressed or (keys and act and (isDelete or isBackspace))) and act then
        conformPushUndo()
        if mode == "removeRun" then
            conformRemoveAt(idx)
        elseif mode == "clearEdits" then
            conformClearItemEdits(it.guid)
        elseif mode == "ignore" then
            conformIgnore[it.guid] = true
            conformTouchState()
        elseif mode == "use" then
            conformIgnore[it.guid] = nil
            conformTouchState()
        end
    end
    if not act then reaper.ImGui_EndDisabled(ctx) end
    local tip = tips[mode] or tips.removeRun
    setToolTipFunc(tip[1], tip[2])

    -- ---- second button: make this one land in one piece ----------------------------
    reaper.ImGui_SameLine(ctx)
    local canHealItem = laneCtx and it and not conformIgnore[it.guid]
                        and conformItemHealOffset(it, breaks, fps) ~= nil
    local healOk = laneCtx and canHealItem or (not laneCtx and canHeal)
    if not healOk then reaper.ImGui_BeginDisabled(ctx) end
    if (reaper.ImGui_Button(ctx, "Heal##cfheal", CONFORM_BTN_W, 0)
        or (keys and healOk and isH and not isShiftDown)) and healOk then
        conformPushUndo()
        if laneCtx then
            conformHealItem(it, breaks, fps)
            conformTouchState()
        else
            conformHealAt(idx)
        end
    end
    if not healOk then reaper.ImGui_EndDisabled(ctx) end
    setToolTipFunc(laneCtx
        and ("Pin this item so it lands in one piece, at the average of the offsets its\n" ..
             "pieces currently sit at -- weighted by length, so a sliver does not drag it.\n" ..
             "Pieces further than " .. string.format("%.1f", conformHealSpread()) ..
             "s from the rest are left out of that average.")
        or  ("Join this match to the next one when they are the same material --\n" ..
             "same offset between the two versions, with only a short gap between.\n" ..
             "That is the matcher having given up mid-shot rather than a real cut."), "h")

    -- ---- third button: everywhere it applies ---------------------------------------
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Heal all##cfhealall", CONFORM_BTN_W + 20, 0)
       or (keys and isH and isShiftDown) then
        local before = conformSnapshot()
        local n
        if laneCtx then
            n = conformHealAllItems(conformLaneItems(conformIP1, fps or 25),
                                    breaks, fps or 25)
            conformEditNote = (n > 0) and string.format("pinned %d item%s", n, n == 1 and "" or "s")
                              or "nothing to heal"
        else
            n = conformHealAll()
            conformEditNote = (n > 0) and string.format("healed %d", n) or "nothing to heal"
        end
        -- only a step on the stack if it actually did something, so undo does not need
        -- pressing twice to get past a press that changed nothing
        if n > 0 then
            conformUndoStack[#conformUndoStack + 1] = before
            conformRedoStack = {}
        end
    end
    setToolTipFunc(laneCtx
        and "Pin every item that would be cut, each at its own average offset."
        or  "Do that everywhere it applies, in one pass.", "shift+h")

    -- ---- the thresholds those two work to ------------------------------------------
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "..##cfhealset", reaper.ImGui_GetFrameHeight(ctx), 0) then
        reaper.ImGui_OpenPopup(ctx, "##cfhealsetmenu")
    end
    setToolTipFunc("How far apart healing is willing to reach")
    if reaper.ImGui_BeginPopup(ctx, "##cfhealsetmenu") then
        reaper.ImGui_TextColored(ctx, colorGrey, "track items")
        conformSliderSetting("##cfspread", "conform_heal_spread", 5.0, 0.5, 30.0,
                             "piece spread %.1f s", 170, false, function() conformLaneKey = nil end)
        setToolTipFunc("Pieces of one item whose offsets sit further apart than this are not\n" ..
                       "averaged together: part of the film may have been moved somewhere\n" ..
                       "else entirely, and a piece that went with it says nothing about where\n" ..
                       "the item as a whole belongs. The largest group by length wins.",
                       "scroll, or " .. MOD_ALT .. "+click to reset")
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, "matches")
        conformSliderSetting("##cfhealgap", "conform_heal_gap", 50, 1, 300,
                             "match gap %.0f frames", 170, false)
        setToolTipFunc("Two matches on the same diagonal are joined when the gap between them\n" ..
                       "is no wider than this. Past it, the frames in between usually do differ\n" ..
                       "for real -- a VFX shot dropped into an untouched stretch -- and joining\n" ..
                       "across would claim material that was never matched.",
                       "scroll, or " .. MOD_ALT .. "+click to reset")
        reaper.ImGui_EndPopup(ctx)
    end

    -- Undo covers both kinds of edit, in the order they were made.
    local hasU, hasR = #conformUndoStack > 0, #conformRedoStack > 0
    reaper.ImGui_SameLine(ctx)
    if not hasU then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Undo##cfundo")
       or (keys and hasU and isSuperDown and not isShiftDown and isZ) then
        conformUndo()
    end
    if not hasU then reaper.ImGui_EndDisabled(ctx) end
    setToolTipFunc("Undo the last change to the matches or to a pinned item", MOD_CMD .. "+z")

    reaper.ImGui_SameLine(ctx)
    if not hasR then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Redo##cfredo")
       or (keys and hasR and isSuperDown and isShiftDown and isZ) then
        conformRedo()
    end
    if not hasR then reaper.ImGui_EndDisabled(ctx) end
    setToolTipFunc("Redo", "shift+" .. MOD_CMD .. "+z")

    if R.edited then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, 0xE5C07BFF, "edited by hand" ..
            (conformEditNote and ("  -  " .. conformEditNote) or ""))
        setToolTipFunc("Re-compare to go back to what the matcher found.")
    end
end

-- Below the timeline, on the left: this acts on the comparison as a whole, which is
-- what the timeline shows, so it sits under it rather than up among the sources.
function conformMatchRow(IP1, IP2)
    if not (vp_available and reaper.VP_Analyze) then return end

    local m = CONFORM_MARGIN
    reaper.ImGui_Dummy(ctx, 1, 2)
    reaper.ImGui_SameLine(ctx, m)

    -- One button, with the action and its four thresholds inside it. The thresholds are
    -- set once on an awkward pair and then left alone for the rest of the job, so they
    -- were spending the whole width of the row on a question nobody was asking. The
    -- empty band between the timelines is still the big invitation while there is no
    -- match, which is where the eye already is.
    if reaper.ImGui_Button(ctx, "Compare##cfcmp") then
        reaper.ImGui_OpenPopup(ctx, "##cfcmpmenu")
    end
    setToolTipFunc(conformResult
        and "Compare again, and the thresholds it uses"
        or  "Find which stretches of the new cut came from where in the old one,\n" ..
            "and the thresholds it uses")
    conformComparePopup(IP1, IP2)

    conformEditButtons()
    conformTrackControls()
end

function conformComparePopup(IP1, IP2)
    if not reaper.ImGui_BeginPopup(ctx, "##cfcmpmenu") then return end

    local ready = IP1 and IP2 and IP1.filePath and IP2.filePath
                  and IP1.filePath ~= "" and IP2.filePath ~= ""
    local label = conformResult and "Re-compare" or "Compare"

    if not ready then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, label .. "##cfmatch", 160, 0) and ready then
        startConform(IP1, IP2)
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    if not ready then reaper.ImGui_EndDisabled(ctx) end
    setToolTipFunc(ready
        and ("Fingerprints every frame of both files; the first run takes roughly 3 min\n" ..
             "per hour of footage, after which the result is cached next to the video.")
        or "Pick a video for both sides first")

    reaper.ImGui_Separator(ctx)

    local changed = false

    changed = conformDragSetting("##conform_ham", "seed: %d",
                  "conform_ham", 4, 1, 16, 0.2) or changed
    setToolTipFunc("How close two frames must be, in bits of 64, before a match may start there.\n" ..
        "4 is the tested default. Higher lets coincidental matches through; extension always rides looser.",
        "drag, scroll, or " .. MOD_ALT .. "+click to reset")

    changed = conformDragSetting("##conform_minrun", "min: %d",
                  "conform_min_run", 12, 2, 120, 0.5) or changed
    setToolTipFunc("Shortest run of frames reported as a match.\n" ..
        "Below about 12, brief coincidences start getting through as spurious changes.",
        "drag, scroll, or " .. MOD_ALT .. "+click to reset")

    changed = conformDragSetting("##conform_conf", "conf: %d%%",
                  "conform_min_conf", 0, 0, 99, 0.5) or changed
    setToolTipFunc("Drop matches below this confidence. A run's confidence comes from how\n" ..
        "far apart the two fingerprints are: exact is 100%, and a quarter of the 64 bits\n" ..
        "apart is 0%, since past that a match carries no information.\n" ..
        "At 0% nothing is dropped. The change list and the damage figure describe what\n" ..
        "is left, so this is a real filter rather than a display setting.",
        "drag, scroll, or " .. MOD_ALT .. "+click to reset")

    if reaper.VP_AnalyzeAudio then
        local uch, uv = reaper.ImGui_Checkbox(ctx, "use sound", settings.conform_use_audio or false)
        if uch then
            settings.conform_use_audio = uv
            saveSettings()
            changed = true
        end
        setToolTipFunc("Also match on sound, to explain stretches the picture cannot reach.\n" ..
            "Picture stays authoritative where it has a match, since it is much the more precise of the two.\n" ..
            "Costs about 30 s per file the first time, then cached. Pick a separate audio export below\n" ..
            "where you have one -- a proper mix matches far better than the guide track inside the picture.")
    end

    -- Any of those changes what the match means, so redo it rather than leaving a
    -- result on screen that no longer corresponds to the settings beside it. Only once a
    -- match exists: changing a threshold is not a request to start one.
    if changed and (conformResult or conformStatus) then
        conformRematch(IP1, IP2)
    end

    reaper.ImGui_EndPopup(ctx)
end

-- Source buttons with each version's timecode pinned to the outer edge beside them, and
-- the two previews with the swap between.
--
-- The timecode corners are reserved: a long file name pushes the buttons off centre
-- rather than running over the reading you are checking against.
function drawConformPreviews(IP1, IP2, oldF, newF, fpsA, fpsB, matched)
    local m, gap, slotW, x0, x1 = conformMetrics()
    local slotH = math.floor(slotW * 9 / 16)

    -- ---- timecodes and source buttons --------------------------------------
    local tcOld = (IP1 and IP1.filePath) and conformTC(oldF, fpsA) or "--:--:--:--"
    local tcNew = (IP2 and IP2.filePath) and conformTC(newF, fpsB) or "--:--:--:--"
    local wTcOld = reaper.ImGui_CalcTextSize(ctx, tcOld)
    local wTcNew = reaper.ImGui_CalcTextSize(ctx, tcNew)

    reaper.ImGui_Dummy(ctx, 1, 1)
    reaper.ImGui_SameLine(ctx, x0)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, conformFocusSide() == "old" and colorWhite or colorGrey, tcOld)

    local function sourceButtons(IP, side, xLo, xHi)
        local w = conformSourceWidth(IP)
        local at = math.max(xLo, math.min(xHi - w, (xLo + xHi - w) / 2))
        reaper.ImGui_SameLine(ctx, at)
        conformVideoButton(IP, side)
        conformAudioButton(IP, side)
    end
    sourceButtons(IP1, "old", x0 + wTcOld + 12, x0 + slotW)
    sourceButtons(IP2, "new", x1, x1 + slotW - wTcNew - 12)

    reaper.ImGui_SameLine(ctx, x1 + slotW - wTcNew)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, conformFocusSide() == "new" and colorWhite or colorGrey, tcNew)

    -- ---- the frames themselves ---------------------------------------------
    local paths = {
        old = (IP1 and IP1.filePath) and conformFramePath(IP1.filePath, oldF, fpsA, true) or nil,
        new = (IP2 and IP2.filePath) and conformFramePath(IP2.filePath, newF, fpsB, false) or nil,
    }
    for _, side in ipairs({ "old", "new" }) do
        local path = paths[side]
        if conformImgPath[side] ~= path then
            conformImg[side]     = nil
            conformImgPath[side] = path
        end
        if conformImg[side] and not reaper.ImGui_ValidatePtr(conformImg[side], 'ImGui_Image*') then
            conformImg[side] = nil
        end
        if not conformImg[side] and path and reaper.file_exists(path) then
            conformImg[side] = reaper.ImGui_CreateImage(path, reaper.ImGui_ImageFlags_NoErrors())
        end
    end

    local function slot(side, IP, x)
        reaper.ImGui_SameLine(ctx, x)
        DrawImageCentered(conformImg[side], slotW, slotH, "##cf_prev_" .. side)

        -- Clicking a picture drives that version. It is the most direct way to say
        -- "play me this one" -- the thing you want is right there on screen -- and it
        -- saves going to find the row in the timeline to click instead.
        --
        -- The matching lane keeps focus if it already had it, so switching version
        -- while working in the items does not throw you out of them.
        if reaper.ImGui_IsItemClicked(ctx) and conformFocusSide() ~= side then
            -- oldF and newF are this frame's corresponding positions, so the picture
            -- does not move across the switch: you keep looking at the same moment.
            conformFocus    = conformFocusIsLane()
                              and ((side == "new") and "laneNew" or "laneOld") or side
            conformPlayhead = (side == "new") and newF or oldF
            conformSelectAtPlayhead()
            -- The preview is bound to one side, so it has to be rebuilt for the other.
            conformStopPreview()
        end
        if reaper.ImGui_IsItemHovered(ctx) and conformFocusSide() ~= side then
            reaper.ImGui_SetTooltip(ctx, "Click to play this version instead")
        end

        -- A border around whichever version is driving. It also answers the question
        -- you have while listening -- which of the two am I hearing -- without having
        -- to look away from the picture to find out.
        if conformFocusSide() == side then
            local px, py = reaper.ImGui_GetItemRectMin(ctx)
            reaper.ImGui_DrawList_AddRect(draw_list, px, py, px + slotW, py + slotH,
                                          colorWhite, 4, 0, 2)
        end

        if IP and IP.filePath and IP.filePath ~= "" then return end
        -- Nothing picked for this side: say what to do, in the space the picture would
        -- have filled, so the layout is the same whether or not it is populated.
        local px, py = reaper.ImGui_GetItemRectMin(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, px, py, px + slotW, py + slotH, 0xFFFFFF18, 4)
        local lines = {
            (side == "old") and "no OLD version yet" or "no NEW version yet",
            "",
            "Select a video item in the arrange view,",
            "then click the button above this box.",
        }
        for i, t in ipairs(lines) do
            local tw = reaper.ImGui_CalcTextSize(ctx, t)
            reaper.ImGui_DrawList_AddText(draw_list, px + (slotW - tw) / 2,
                py + slotH / 2 - 34 + (i - 1) * 17, i == 1 and 0xFFFFFFAA or 0xFFFFFF66, t)
        end
    end

    -- A backdrop per slot, drawn before the frames. A 4:3 or anamorphic version does not
    -- fill a 16:9 slot, and without this the leftover showed the window through.
    --
    -- Two boxes rather than one band: the gap between them stays window background, so
    -- the two versions read as two separate pictures with the swap in the space between
    -- them, rather than as one wide area that happens to have a button in the middle.
    reaper.ImGui_Dummy(ctx, 1, 1)
    reaper.ImGui_SameLine(ctx, x0)
    local bx, by = reaper.ImGui_GetCursorScreenPos(ctx)
    local dx = x1 - x0                       -- offset from the old slot to the new one
    reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + slotW, by + slotH,
                                        conformSlotBg, 4)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, bx + dx, by, bx + dx + slotW, by + slotH,
                                        conformSlotBg, 4)

    slot("old", IP1, x0)

    -- Swap, filling the gap exactly so it touches both frames: an arrow pointing both
    -- ways says what it does without a word, and sits where the exchange happens.
    reaper.ImGui_SameLine(ctx, x0 + slotW)
    reaper.ImGui_InvisibleButton(ctx, "##cfswap", gap, slotH)
    if reaper.ImGui_IsItemClicked(ctx) then
        -- With sides pinned, swapping the pins is the whole job; swapItems would then
        -- swap them straight back. Without pins, swapItems is the only handle there is.
        if conformPin.old or conformPin.new then
            conformPin.old, conformPin.new = conformPin.new, conformPin.old
        else
            swapItems = not swapItems
        end
        conformResult, conformSelectedIdx = nil, nil
        conformStopPreview()
    end
    do
        local sx, sy = reaper.ImGui_GetItemRectMin(ctx)
        local sw, sh = reaper.ImGui_GetItemRectSize(ctx)
        local cx, cy = sx + sw / 2, sy + sh / 2
        local col = reaper.ImGui_IsItemHovered(ctx) and colorWhite or colorGrey
        local r   = math.min(11, sw / 2 - 2)
        reaper.ImGui_DrawList_AddLine(draw_list, cx - r, cy, cx + r, cy, col, 2)
        for _, d in ipairs({ -1, 1 }) do
            local tip = cx + d * r
            reaper.ImGui_DrawList_AddLine(draw_list, tip, cy, tip - d * 5, cy - 4, col, 2)
            reaper.ImGui_DrawList_AddLine(draw_list, tip, cy, tip - d * 5, cy + 4, col, 2)
        end
    end
    setToolTipFunc("Swap which version counts as the old one")

    slot("new", IP2, x1)

    -- While fingerprinting, the frames behind are stale and nothing can be done with
    -- them, so the progress goes over them rather than somewhere else on the page.
    -- The cancel is here too: it belongs with the thing it stops.
    if conformStatus then
        -- dimmed per slot too, so the gap between them stays as it is
        local bw = (x1 - x0) + slotW
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + slotW, by + slotH,
                                            0x000000C4, 4)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx + (x1 - x0), by,
                                            bx + (x1 - x0) + slotW, by + slotH, 0x000000C4, 4)
        -- Each side's own progress, centred in its own slot. Two files are being
        -- fingerprinted and they finish at different times, so one combined number said
        -- less -- and centring it across the pair would have run it over the gap.
        local function mid(text, at, dy, col, fnt)
            if fnt then reaper.ImGui_PushFont(ctx, font, fnt) end
            local tw = reaper.ImGui_CalcTextSize(ctx, text)
            reaper.ImGui_DrawList_AddText(draw_list, at + (slotW - tw) / 2,
                                          by + slotH / 2 + dy, col, text)
            if fnt then reaper.ImGui_PopFont(ctx) end
        end
        for _, s in ipairs({ { bx, "old" }, { bx + (x1 - x0), "new" } }) do
            local pct, what = conformSideProgress(s[2])
            mid(pct,  s[1], -34, 0xFFFFFFFF, 28)
            mid(what, s[1],   6, 0xFFFFFFAA)
        end

        -- The cursor is moved into the picture to place the button, then put straight
        -- back: everything below this lays itself out from wherever the cursor is, so
        -- leaving it in the middle of a video frame would drag the whole page up.
        local cx, cy = reaper.ImGui_GetCursorScreenPos(ctx)
        local bwid, bhei = 90, 24
        reaper.ImGui_SetCursorScreenPos(ctx, bx + (bw - bwid) / 2, by + slotH / 2 + 34)
        if reaper.ImGui_Button(ctx, "Cancel##cfcancel", bwid, bhei) then
            conformCancel()
        end
        setToolTipFunc("Stop fingerprinting. Whatever has been written so far is discarded,\n" ..
                       "so the next run starts over.")
        reaper.ImGui_SetCursorScreenPos(ctx, cx, cy)
    end
end


function drawConformChangeList(fpsA, fpsB)
    local R = conformResult
    if not R then return end
    local changes = R.changes

    reaper.ImGui_TextColored(ctx, colorGrey,
        "same colour and number on both rows is the same material  -  hover a block to isolate its pair")

    local counts = {}
    for _, c in ipairs(changes) do counts[c.type] = (counts[c.type] or 0) + 1 end
    local first = true
    for _, k in ipairs({ "matched", "moved", "added", "removed", "swapped" }) do
        if counts[k] then
            if not first then reaper.ImGui_SameLine(ctx) end
            first = false
            -- matched and moved are drawn in pair colours rather than one type colour,
            -- so the legend shows them in the palette instead of lying about the hue
            local swatch = (k == "matched" or k == "moved")
                           and conformPairPalette[1] or conformColors[k]
            reaper.ImGui_TextColored(ctx, swatch, string.format("%s %d", k, counts[k]))
            if k == "moved" then
                setToolTipFunc("Same material, relocated. Drawn in its pair colour with an outline.")
            elseif k == "matched" then
                setToolTipFunc("Carried over in place. Drawn in a colour per pair, cycling through the palette.")
            end
        end
    end
    reaper.ImGui_SameLine(ctx)
    local lm_ch, lm_v = reaper.ImGui_Checkbox(ctx, "list unchanged", settings.conform_list_matched or false)
    if lm_ch then settings.conform_list_matched = lm_v; saveSettings() end

    -- A list box rather than a child window: it gives the same scrolling region, and
    -- its End is only called when its Begin returned true, which is the convention
    -- every other ImGui Begin/End pair here follows.
    if reaper.ImGui_BeginListBox(ctx, "##conform_list", -1, 150) then
        for i, c in ipairs(changes) do
            if settings.conform_list_matched or c.type ~= "matched" then
                local delta = c.bLen - c.aLen
                local pi    = R.pairIndex and R.pairIndex[i]
                -- Row carries the pair number and the pair colour, so a row and the two
                -- blocks it refers to can be matched up without hunting.
                local label = string.format("%-4s %-8s  new %s   old %s   %+6d f  %+7.2fs",
                    pi and ("#" .. pi) or "", c.type,
                    conformTC(c.bStart, fpsB), conformTC(c.aStart, fpsA), delta, delta / fpsB)
                local col = (R.pairColor and R.pairColor[i]) or conformColors[c.type] or colorWhite
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), col)
                if reaper.ImGui_Selectable(ctx, label .. "##cf" .. i, conformSelectedIdx == i) then
                    conformSelectedIdx = i
                    -- jump to it on whichever side actually has material here: an
                    -- entry with nothing in the new cut has nothing to show there
                    if c.bLen > 0 then
                        conformFocus, conformPlayhead = "new", c.bStart
                    else
                        conformFocus, conformPlayhead = "old", c.aStart
                    end
                    conformPlaying = false
                end
                reaper.ImGui_PopStyleColor(ctx)
            end
        end
        reaper.ImGui_EndListBox(ctx)
    end
end

-- Where blocks begin on the focused side, in order. These stand in for the cut list
-- that the detection tab's transport steps through: here the meaningful landmarks are
-- the edges of matched and changed material, not detected cuts.
-- With a lane driving, the arrows step through the edges of the items in it -- every
-- start and every end -- rather than through match blocks. On the new side those are
-- the edges of the pieces the conform would leave, since that is what is drawn there.
function conformLaneEdges()
    local side  = conformFocusSide()
    local items = conformLaneItems(conformIP1, (conformResult and conformResult.info
                                                and conformResult.info.fpsA) or 25)
    local breaks = conformMapBreaks()
    local edges, seen = {}, {}
    local function add(v)
        v = math.floor(v)
        if not seen[v] then seen[v] = true; edges[#edges + 1] = v end
    end
    for _, it in ipairs(items) do
        if side == "old" then
            add(it.s); add(it.e)
        else
            for _, pc in ipairs(conformItemPieces(it, breaks)) do
                add(pc.newS); add(pc.newS + pc.len)
            end
        end
    end
    table.sort(edges)
    return edges
end

function conformBlockEdges()
    if conformFocusIsLane() then return conformLaneEdges() end
    local R = conformResult
    if not R then return {} end
    local edges, seen = {}, {}
    for _, c in ipairs(R.changes) do
        local st  = (conformFocusSide() == "new") and c.bStart or c.aStart
        local len = (conformFocusSide() == "new") and c.bLen   or c.aLen
        if len > 0 and not seen[st] then
            seen[st] = true
            edges[#edges + 1] = st
        end
    end
    -- Blocks are not in ascending order on the old side once material has been
    -- relocated, so this cannot rely on the change order.
    table.sort(edges)
    return edges
end

-- Which block the playhead is standing in. The playhead is the selector: scrubbing,
-- playing or stepping all move the selection with it, so whatever is being looked at
-- is always the thing that would be acted on. Hovering the timeline overrides it for
-- as long as the mouse is there, but does not change it.
function conformIdxAtPlayhead()
    local R = conformResult
    -- With a lane driving, the video blocks are not what is being looked at, so
    -- nothing there is emphasised: clicking an item takes the highlight away from the
    -- matches rather than lighting both at once.
    if conformFocusIsLane() then return nil end
    if not R then return nil end
    local f = math.floor(conformPlayhead)
    for i, c in ipairs(R.changes) do
        local st  = (conformFocusSide() == "new") and c.bStart or c.aStart
        local len = (conformFocusSide() == "new") and c.bLen   or c.aLen
        if len > 0 and f >= st and f < st + len then return i end
    end
    return nil
end

function conformSelectAtPlayhead()
    conformSelectedIdx = conformIdxAtPlayhead()
    if conformFocusIsLane() then conformLaneSelectAtPlayhead() end
end

-- Walking the arrows through a lane selects what you arrive at, so stepping to an
-- item's end leaves that item selected and ready for the keys that act on one.
function conformLaneSelectAtPlayhead()
    local side  = conformFocusSide()
    local fpsA  = (conformResult and conformResult.info and conformResult.info.fpsA) or 25
    local items = conformLaneItems(conformIP1, fpsA)
    local breaks = conformMapBreaks()
    local f = math.floor(conformPlayhead)

    for _, it in ipairs(items) do
        if side == "old" then
            -- the end of an item counts as being on it, so arriving at an edge selects
            -- the item that edge belongs to rather than nothing
            if f >= it.s and f <= it.e then
                conformLaneSel, conformLanePick = it.guid, nil
                return
            end
        else
            for _, pc in ipairs(conformItemPieces(it, breaks)) do
                if f >= pc.newS and f <= pc.newS + pc.len then
                    conformLaneSel  = it.guid
                    conformLanePick = { guid = it.guid, oldS = pc.oldS,
                                        newS = pc.newS, len = pc.len }
                    return
                end
            end
        end
    end
end

function conformJumpBlock(dir)
    local edges = conformBlockEdges()
    if #edges == 0 then return false end
    local cur = math.floor(conformPlayhead)
    if dir > 0 then
        for _, e in ipairs(edges) do
            if e > cur then conformPlayhead = e; return true end
        end
        conformPlayhead = edges[#edges]
    else
        for i = #edges, 1, -1 do
            if edges[i] < cur then conformPlayhead = edges[i]; return true end
        end
        conformPlayhead = edges[1]
    end
    return true
end

-- Same transport and shortcuts as the cut detection tab, except the inner buttons step
-- between block edges rather than cuts, and play drives the app's own playhead.
function conformTransportButtons(framesA, framesB, fpsA, fpsB)
    local limit = (conformFocusSide() == "new") and framesB or framesA
    local fps   = (conformFocusSide() == "new") and fpsB or fpsA
    if not (fps > 0) then fps = 25 end
    local keys = not markerNameIsFocused

    local function afterMove()
        conformSelectAtPlayhead()
        if conformSyncEnabled() then conformSyncSeek(conformIP1, fpsA) end
    end
    local function step(frames)
        conformPlaying  = false
        conformStopPreview()
        conformPlayhead = conformClamp(math.floor(conformPlayhead) + frames, limit)
        afterMove()
    end
    local function jump(dir)
        conformPlaying = false
        conformStopPreview()
        conformJumpBlock(dir)
        afterMove()
    end

    -- In a lane, shift+arrow does the same as arrow: there is nothing between one item
    -- edge and the next worth stepping a frame at a time for.
    local laneDriving = conformFocusIsLane()

    -- opt+arrow nudges the selected item instead of moving the playhead. New side only,
    -- for the same reason opt+drag is: the old lane is the session as it stands.
    local canMove = conformFocus == "laneNew" and conformLaneSel
    if keys and canMove and isOptionDown and (isLeftArrowReleased or isRightArrowReleased) then
        local by = isRightArrowReleased and 1 or -1
        if isSuperDown then by = by * math.floor(fps) end
        conformPushUndo()
        conformShift[conformLaneSel] = (conformShift[conformLaneSel] or 0) + by
        conformTouchState()
        return      -- the arrow moved the item, so it must not also move the playhead
    end

    if reaper.ImGui_Button(ctx, "<##cf", buttonSize, buttonSize)
       or (keys and isLeftArrowReleased and isShiftDown) then
        if laneDriving then jump(-1) else step(isSuperDown and -math.floor(fps) or -1) end
    end
    setToolTipFunc(laneDriving and "Go to the previous item edge"
                   or "Move 1 frame left (hold super for 1 second)", "shift+left")

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "l<##cf", buttonSize, buttonSize)
       or (keys and isLeftArrowReleased and not isShiftDown) then
        jump(-1)
    end
    setToolTipFunc("Go to the previous block on the focused side", "left arrow")

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "##cfplay", buttonSize, buttonSize) or (keys and isSpace) then
        conformPlaying  = not conformPlaying
        conformLastTick = nil
        if conformSyncEnabled() then
            if conformPlaying then
                conformSyncPrev, conformSyncRunKey = nil, nil   -- start from scratch
                conformSyncSeek(conformIP1, fpsA)
                conformSyncStart()
            else
                conformSyncStop()
            end
        elseif not conformPlaying then
            conformStopPreview()
        end
    end
    setToolTipFunc("Play or stop both previews. The focused side carries the playhead; the other\n" ..
                   "follows the match map and re-syncs each time a match begins", "space")
    local px, py = reaper.ImGui_GetItemRectMin(ctx)
    local sw, sh = reaper.ImGui_GetItemRectSize(ctx)
    reaper.ImGui_DrawList_AddRectFilled(draw_list, px, py, px + sw, py + sh,
        conformPlaying and colorIsPlaying or theme.button, 6)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, px + sw / 2 - 1, py + sh / 2, sw / 3,
        conformPlaying and colorWhite or colorTransparent, 3)
    reaper.ImGui_DrawList_AddCircle(draw_list, px + sw / 2 - 1, py + sh / 2, sw / 3,
        colorWhite, 3, 1)

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, ">l##cf", buttonSize, buttonSize)
       or (keys and isRightArrowReleased and not isShiftDown) then
        jump(1)
    end
    setToolTipFunc("Go to the next block on the focused side", "right arrow")

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, ">##cf", buttonSize, buttonSize)
       or (keys and isRightArrowReleased and isShiftDown) then
        if laneDriving then jump(1) else step(isSuperDown and math.floor(fps) or 1) end
    end
    setToolTipFunc(laneDriving and "Go to the next item edge"
                   or "Move 1 frame right (hold super for 1 second)", "shift+right arrow")

    -- Up takes the top bar, down the bottom one, following how they are drawn. The
    -- picture stays put across the switch: the playhead moves to wherever that side
    -- already was, so changing which version you drive does not also move you in time.
    -- Up and down walk the rows in the order they are stacked, so from the new items
    -- lane: up to the new video, up again to the old video, up again to the old items
    -- lane. The playhead only moves when the *version* changes, so stepping between a
    -- version's lane and its bar stays put in time.
    local dir = (keys and isUpArrow and -1) or (keys and isDownArrow and 1) or nil
    if dir then
        local want = conformFocusStep(dir)
        if want ~= conformFocus then
            local oldF, newF = conformPositions(framesA, framesB)
            local wasSide = conformFocusSide()
            conformFocus  = want
            if conformFocusSide() ~= wasSide then
                conformPlayhead = (conformFocusSide() == "new") and newF or oldF
            end
            conformSelectAtPlayhead()
        end
    end
end


function drawConformSection(IP1, IP2)
    -- A different pair is a different piece of work: load what was last done to it.
    -- Keyed on the two paths, so this fires once when the pair changes rather than
    -- every frame, and never while you are in the middle of the same comparison.
    local pairKey = (IP1 and IP1.filePath or "") .. "|" .. (IP2 and IP2.filePath or "")
    if conformPairLoaded ~= pairKey then
        conformPairLoaded = pairKey
        if IP1 and IP1.filePath and IP1.filePath ~= ""
           and IP2 and IP2.filePath and IP2.filePath ~= "" then
            conformLoadState(IP1, IP2)
        end
    end

    local framesA, framesB, fpsA, fpsB = conformFrameCounts(IP1, IP2)
    -- No early return when nothing is picked: the layout is drawn either way, with the
    -- empty side saying what to do, so filling it in does not reshape the window.

    -- Advance the internal playhead, from the audio clock where there is one.
    local fpsFocus = (conformFocusSide() == "new") and fpsB or fpsA
    if not (fpsFocus > 0) then fpsFocus = 25 end
    local limit = (conformFocusSide() == "new") and framesB or framesA

    -- Two transports rolling at once, out of step by construction. REAPER's is the one
    -- somebody just started deliberately, so this one yields rather than playing the
    -- same material a second time over the top of it.
    if conformPlaying and not conformSyncEnabled()
       and (reaper.GetPlayState() & 1) == 1 then
        conformPlaying = false
        conformStopPreview()
    end

    -- With sync on and nothing rolling, REAPER's edit cursor leads.
    if conformSyncEnabled() and not conformPlaying and not conformScrubbing then
        conformSyncCursorFollow(IP1, framesA, framesB, fpsA)
    end

    if conformPlaying and conformSyncEnabled() then
        conformSyncFollow(IP1, framesA, framesB, fpsA)
        if conformPlayhead >= limit - 1 then
            conformPlayhead = math.max(0, limit - 1)
            conformPlaying  = false
            conformSyncStop()
        end
    elseif conformPlaying then
        -- The focused row's speaker decides whether this version's own sound plays, and
        -- the side is what the preview is keyed on, not the row: a lane and the bar
        -- above it are the same version, so stepping between them must not restart it.
        local pv = conformVideoAudible()
                   and conformEnsurePreview((conformFocusSide() == "new") and IP2 or IP1,
                                            conformFocusSide(), conformPlayhead / fpsFocus)
                   or nil
        local gotAudio = false
        if pv then
            local ok, pos = reaper.CF_Preview_GetValue(pv, "D_POSITION")
            if ok and pos and pos > 0 then
                conformPlayhead = pos * fpsFocus
                gotAudio = true
            end
        end
        if not gotAudio then
            -- No audio to ride: fall back to wall clock, capped so a stalled frame
            -- does not launch the playhead down the timeline.
            local now = reaper.time_precise()
            local dt  = conformLastTick and math.min(now - conformLastTick, 0.25) or 0
            conformLastTick = now
            conformPlayhead = conformPlayhead + dt * fpsFocus
        end
        if conformPlayhead >= limit - 1 then
            conformPlayhead = math.max(0, limit - 1)
            conformPlaying  = false
            conformStopPreview()
        end
    else
        conformLastTick = nil
    end

    do  -- the session items that are under the playhead, heard on the driving side
        local a, b = conformPositions(framesA, framesB)
        conformPlayItems(IP1, a, b, fpsA)
    end

    local oldF, newF, matched = conformPositions(framesA, framesB)
    conformHeaderRow()
    drawConformPreviews(IP1, IP2, oldF, newF, fpsA, fpsB, matched)

    -- Transport and the controls that feed it sit above the timeline, leaving the space
    -- under it for the timeline's own tools. Playback belongs to the pictures it drives,
    -- and the timeline is what gets acted on.
    reaper.ImGui_Dummy(ctx, 1, 4)
    reaper.ImGui_SameLine(ctx, CONFORM_MARGIN)
    conformViewControls()
    reaper.ImGui_SameLine(ctx, winW / 2 - math.floor(buttonSize * 2.5))
    conformTransportButtons(framesA, framesB, fpsA, fpsB)
    local zw = 2 * reaper.ImGui_GetFrameHeight(ctx) + 8
    local vw = reaper.ImGui_CalcTextSize(ctx, "view") + 24
    reaper.ImGui_SameLine(ctx, winW - CONFORM_MARGIN - zw - vw)
    conformViewMenu()
    reaper.ImGui_SameLine(ctx)
    conformZoomButtons(framesA, framesB)

    drawConformTimelines(IP1, IP2, framesA, framesB, fpsA, fpsB)

    -- Opened from inside the scrolling timeline, but drawn out here: a popup belongs to
    -- the window it is drawn in, and one opened inside a child that scrolls would move
    -- with the content underneath it.
    if conformLaneOpen then
        reaper.ImGui_OpenPopup(ctx, "##cflanemenu")
        conformLaneOpen = false
    end
    conformLaneMenu()

    -- Under the timeline: what to do with the comparison, rather than how to play it.
    conformMatchRow(IP1, IP2)

    -- The result is off by default because most of the time the ribbons are the answer
    -- and the numbers are only wanted when something looks wrong.
    reaper.ImGui_Dummy(ctx, 1, 2)
    reaper.ImGui_SameLine(ctx, CONFORM_MARGIN)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "")

    -- Progress stays outside the tickbox: it is the one thing you need to see while
    -- waiting, whether or not you asked for the numbers.
    if conformStatus then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, "    " .. conformStatus)
    end

    -- The edit plan, when one has been asked for. Shown rather than applied: this says
    -- what would have to happen to the session, and nothing here touches it yet.
    if conformCutPlan then
        local P = conformCutPlan
        reaper.ImGui_Dummy(ctx, 1, 6)
        reaper.ImGui_SameLine(ctx, CONFORM_MARGIN)
        reaper.ImGui_TextColored(ctx, colorWhite, string.format(
            "%d edit%s to line up %d kept item%s",
            #P.cuts, #P.cuts == 1 and "" or "s", P.kept, P.kept == 1 and "" or "s"))
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "clear##cfplanclr") then conformCutPlan = nil end

        local fps = fpsA > 0 and fpsA or 25
        for i, c in ipairs(P.cuts) do
            if i <= 20 then
                -- Dummy first, SameLine second: a SameLine before the Dummy keeps it
                -- on the previous line, which stacked every entry on one row.
                reaper.ImGui_Dummy(ctx, 1, 1)
                reaper.ImGui_SameLine(ctx, CONFORM_MARGIN + 10)
                local lbl = string.format("%s   %+d frames (%+.2fs)   between %s and %s##cfp%d",
                    conformTC(c.at, fps), c.delta, c.delta / fps,
                    conformShorten(c.after, 18), conformShorten(c.before, 18), i)
                if reaper.ImGui_Selectable(ctx, lbl, false) then
                    conformFocus    = "old"
                    conformPlayhead = c.at
                    conformPlaying  = false
                    conformStopPreview()
                end
                setToolTipFunc(string.format(
                    "%s %d frames at this point, anywhere between %s and %s.\nClick to put the playhead there.",
                    c.delta > 0 and "Insert" or "Remove", math.abs(c.delta),
                    conformTC(c.gapS, fps), conformTC(c.gapE, fps)))
            end
        end
        if #P.cuts > 20 then
            reaper.ImGui_SameLine(ctx, CONFORM_MARGIN + 10)
            reaper.ImGui_TextColored(ctx, colorGrey, string.format("+%d more", #P.cuts - 20))
        end

        for _, pr in ipairs(P.problems) do
            reaper.ImGui_Dummy(ctx, 1, 1)
            reaper.ImGui_SameLine(ctx, CONFORM_MARGIN + 10)
            if pr.kind == "split" then
                reaper.ImGui_TextColored(ctx, 0xE06C75FF, string.format(
                    "%s would still be cut - pin it first", conformShorten(pr.a.name, 28)))
            else
                reaper.ImGui_TextColored(ctx, 0xE06C75FF, string.format(
                    "%s and %s need offsets %d frames apart with no gap between them",
                    conformShorten(pr.a.name, 20), conformShorten(pr.b.name, 20),
                    math.abs(pr.delta)))
            end
        end
    end

    if settings.conform_show_result then
        reaper.ImGui_Dummy(ctx, 1, 6)
        if not conformResult then
            reaper.ImGui_TextColored(ctx, colorGrey,
                "no match yet  -  the two versions are lined up end to end")
        else
            local R = conformResult
            reaper.ImGui_TextColored(ctx, colorGrey, string.format(
                "%d -> %d frames    %+.1fs    damage %.1f%%    %d runs %s%s",
                R.info.framesA, R.info.framesB,
                (R.info.framesB / fpsB) - (R.info.framesA / fpsA),
                R.damage * 100, #R.info.runs,
                R.restored and "restored from last time"
                           or string.format("matched in %.0f ms", R.matchMs),
                (R.audioAdded and R.audioAdded > 0)
                    and string.format("    (%d of them from sound)", R.audioAdded) or ""))
            drawConformChangeList(fpsA, fpsB)
        end
    end
end









-- Where to send output nobody wants to read.
--
-- cmd.exe cannot redirect to /dev/null: it resolves that as a relative path, finds no
-- `dev` directory, prints "The system cannot find the path specified" and then does not
-- run the command at all. So a POSIX redirect does not merely fail to silence anything
-- on Windows -- it stops the command working. That made the Ollama check come back
-- empty every time and report "not installed" on a machine where it was installed,
-- running and ready.
local function shellNull()
    return is_windows and "nul" or "/dev/null"
end

-- Runs a command and returns its output, without a console window appearing.
--
-- io.popen goes through a shell, and on Windows that shell gets a console window which
-- flashes up over REAPER every time. The Ollama probe runs one as soon as a cut is
-- selected, whether or not anyone intends to use Ollama, so the flicker turned up for
-- people who had nothing to do with it. reaper.ExecProcess runs hidden instead, which
-- is why the thumbnail path already uses it; its result is the exit code, a newline,
-- then the output. Commands passed here must therefore be a plain executable and its
-- arguments, with no shell redirection -- stderr is simply not captured, which is all
-- the discarded "2>nul" was ever for.
function shellRead(cmd, timeoutMs)
    local _, out = shellExec(cmd, timeoutMs)
    return out
end

-- The same, but giving the exit code as well.
--
-- Worth having separately: whether a command's error output is folded into what comes
-- back is not something to rely on, and "where" announces a miss on stderr while
-- exiting 1. Testing for empty output therefore reads a missing program as a present
-- one if that text is merged -- which is exactly how Ollama came to be reported as
-- installed but not running on a machine that did not have it, and how pressing Start
-- then produced Windows' own "cannot find ollama". The exit code says so plainly.
--
-- -1 means the command could not be run at all, which is distinct from a non-zero exit.
function shellExec(cmd, timeoutMs)
    if not is_windows then
        local h = io.popen(cmd)
        if not h then return -1, "" end
        local out = h:read("*a") or ""
        local ok, _, code = h:close()
        return ok and 0 or (code or 1), out
    end
    local raw = reaper.ExecProcess(cmd, timeoutMs or 3000)
    if not raw then return -1, "" end
    local nl = raw:find("\n")
    if not nl then return tonumber(raw) or -1, "" end
    return tonumber(raw:sub(1, nl - 1)) or -1, raw:sub(nl + 1)
end

-- Whether Ollama is on this machine at all, as distinct from running.
function ollamaBinaryFound()
    if is_windows then
        local code = shellExec('where ollama', 2000)
        return code == 0
    end
    if reaper.file_exists("/Applications/Ollama.app") then return true end
    return (shellExec('which ollama', 2000)) == 0
end

function checkOllamaStatus(timeoutSec)
    local host = settings.ollama_host or "localhost:11434"

    -- Check if the server is responding. The timeout is short for the automatic probe:
    -- Ollama is on this machine, so it either answers at once or is not listening, and
    -- a long wait would only stall the UI to learn the same thing.
    local t = timeoutSec or 2
    local result = shellRead('curl -s --max-time ' .. t ..
                             ' http://' .. host .. '/api/tags', (t + 1) * 1000)

    if result == "" then
        -- Server not responding: installed but idle, or not there at all. The
        -- difference decides whether the page offers Start or Download, so getting it
        -- wrong offers to start something that cannot be started.
        ollamaStatus = ollamaBinaryFound() and "not_running" or "not_installed"
        return
    end

    -- Server is up — populate installed model set and check selected model
    -- Store full names (e.g. "llava:7b", "llava:13b") so variants don't collide
    local tags = json.decodeFromJson(result)
    ollamaInstalledModels = {}
    if tags and tags.models then
        for _, m in ipairs(tags.models) do
            local fullName = (m.name or m.model or ""):gsub("%s+", "")
            if fullName ~= "" then
                ollamaInstalledModels[fullName] = true
            end
        end
        ollamaStatus = ollamaModelInstalled(settings.ollama_model or "llava") and "ready" or "model_missing"
    else
        ollamaStatus = "model_missing"
    end
end

-- Whether describing cuts can actually work right now.
--
-- Checked once, the first time something is about to offer it, rather than at startup:
-- Ollama is optional and most runs never touch it, so a probe on every launch would be
-- a cost paid by everyone for a feature few use. The Settings page's Check button
-- refreshes it after installing or starting Ollama.
--
-- "ready" is the bar rather than merely "running", because it also means the selected
-- model is pulled -- and a Describe that fails after a 30 second wait is worse than one
-- that was never offered.
local ollamaProbed = false

function ollamaAvailable()
    if not ollamaProbed then
        ollamaProbed = true
        checkOllamaStatus(1)
    end
    return ollamaStatus == "ready"
end

-- Says what to do about it, for the tooltip on a disabled Describe.
function ollamaWhyUnavailable()
    if ollamaStatus == "not_installed" then
        return "Ollama is not installed. Settings > Cut description has a download link."
    elseif ollamaStatus == "not_running" then
        return "Ollama is installed but not running. Start it from Settings > Cut description."
    elseif ollamaStatus == "model_missing" then
        return "The model is not pulled yet. Settings > Cut description will fetch it."
    end
    return "Ollama could not be reached. See Settings > Cut description."
end

function startOllamaPull()
    -- Reachable from the model list, which is drawn whatever the status is -- so this
    -- can be asked for on a machine with no Ollama at all. Pulling would then open a
    -- terminal only to report that the command does not exist.
    if not ollamaBinaryFound() then
        ollamaStatus = "not_installed"
        if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute("https://ollama.com/download")
        end
        return
    end
    local model = settings.ollama_model or "llava"
    if is_windows then
        local tmpBat = script_path .. "Helpers" .. seperator .. "tmp_pull.bat"
        local f = io.open(tmpBat, "w")
        if f then
            f:write('@echo off\necho Pulling ' .. model .. '...\nollama pull "' .. model .. '"\necho.\necho Done! Press any key to close.\npause >nul')
            f:close()
            -- Visible on purpose, unlike every other launch in this script: a model
            -- is gigabytes and takes minutes, so the terminal IS the progress bar.
            os.execute('start cmd /c "' .. tmpBat .. '"')
        end
    else
        local tmpSh = script_path .. "Helpers" .. seperator .. "tmp_pull.sh"
        local f = io.open(tmpSh, "w")
        if f then
            f:write('#!/bin/bash\necho "Pulling ' .. model .. '..."\nollama pull "' .. model .. '"\necho ""\necho "Done! Press any key to close."\nread -n 1')
            f:close()
            os.execute('chmod +x "' .. tmpSh .. '"')
            os.execute('open -a Terminal.app "' .. tmpSh .. '"')
        end
    end
end


--------------------------------------------------------
-----------------REAPER HELPERS-------------------------
--------------------------------------------------------


function getVideoItemFilePath(item)
    if item then
        local take = reaper.GetActiveTake(item)
        if take then
            local source = reaper.GetMediaItemTake_Source(take)
            local source_type = reaper.GetMediaSourceType(source, "")
            if source_type == "VIDEO" then
                local filename = reaper.GetMediaSourceFileName(source, "")
                -- we make sure to not match png files
                if filename:match(".png") == nil then 
                    return filename
                end
            else
                return nil
            end
        end
    else
        return nil
    end
end

function getItemRealtimeInfo(IP, proj)
    proj = proj and proj or 0
    
    
    -- Get item position in project
    if IP.item and reaper.ValidatePtr2(proj, IP.item, 'MediaItem*') then 
        local last_item_pos = IP.item_pos
        local last_item_length = IP.item_length
        local last_item_offset = IP.item_offset
    
        local item_pos = reaper.GetMediaItemInfo_Value(IP.item, "D_POSITION")
        
        local item_length = reaper.GetMediaItemInfo_Value(IP.item, "D_LENGTH")
        local item_offset = reaper.GetMediaItemTakeInfo_Value(IP.take, "D_STARTOFFS")
        local item_end = item_pos + item_length
         
        local start_time_in_item = start_time_sel - item_pos-- + item_offset
        local end_time_in_item = end_time_sel - item_pos --+ item_offset
        
        local overview_start_in_item
        local overview_length_in_item
        local overview_end_in_item 
        
        local item_area_to_analyze_start
        local item_area_to_analyze_length
        
        local overview_start_time
        local overview_length_time
        
        if settings.selectionType == "Video item" then 
            overview_start_in_item = item_offset
            overview_start_in_item_offset = item_offset
            overview_length_in_item = item_length
            
            item_area_to_analyze_start = overview_start_in_item
            item_area_to_analyze_length = item_length
            
            overview_start_time = item_pos
            overview_length_time = item_area_to_analyze_length
        elseif settings.selectionType == "Time selection" then 
            overview_start_in_item = start_time_sel - item_pos
            overview_start_in_item_offset = start_time_sel - item_pos + item_offset
            overview_length_in_item = item_end < end_time_sel and item_end - item_pos - overview_start_in_item or end_time_sel - item_pos - overview_start_in_item
            
            item_area_to_analyze_start = overview_start_in_item < 0 and item_offset or overview_start_in_item + item_offset
            item_area_to_analyze_length = overview_length_in_item + (overview_start_in_item < 0 and overview_start_in_item or 0) 
            
            overview_start_time = start_time_sel
            overview_length_time = length_time_sel
        elseif settings.selectionType == "Arrange view" then
            overview_start_in_item = start_time_arr - item_pos
            overview_start_in_item_offset = start_time_arr - item_pos + item_offset
            overview_length_in_item = item_end < end_time_arr and item_end - item_pos - overview_start_in_item or end_time_arr - item_pos - overview_start_in_item
            
            item_area_to_analyze_start = overview_start_in_item < 0 and item_offset or overview_start_in_item + item_offset
            item_area_to_analyze_length = overview_length_in_item + (overview_start_in_item < 0 and overview_start_in_item or 0)
            
            overview_start_time = start_time_arr
            overview_length_time = length_time_arr
        end
        
        
        local cur_pos_in_item = (item_pos and cur_pos - item_pos + item_offset or 0)                     --+ IP.overview_start_in_item
        
        local timeline_cur_pos_in_item = (item_pos and timeline_cur_pos - item_pos + item_offset or 0)   --+ IP.overview_start_in_item 
        
        if is_a_subproject then
            overview_start_in_item = subProj_item_pos
            overview_start_in_item_offset = subProj_item_pos
            overview_length_in_item = get_subproject_length()
            
            
            
            item_area_to_analyze_start = overview_start_in_item < 0 and item_offset or overview_start_in_item + item_offset
            item_area_to_analyze_length = overview_length_in_item + (overview_start_in_item < 0 and overview_start_in_item or 0)
            
            overview_start_time = overview_start_in_item
            overview_length_time = overview_length_in_item
            --cur_pos_in_item = cur_pos_in_item - subProj_item_pos
            --timeline_cur_pos_in_item = timeline_cur_pos_in_item - overview_start_in_item
            --reaper.ShowConsoleMsg(cur_pos_in_item .. "\n")
        end  
        
        overview_end_in_item = overview_start_in_item + overview_length_in_item
        
        --local item_area_to_analyze_start = overview_start_in_item < 0 and 0 or overview_start_in_item
        --local item_area_to_analyze_length = overview_length_in_item > item_length and item_length or overview_length_in_item
        
        
        
        
        if is_a_subproject then
            --
            
        end
        
        outsideBoundries = cur_pos_in_item > overview_start_in_item + overview_length_in_item or cur_pos_in_item < overview_start_in_item
        
        
        
        -- add/update realtime stuff to item 
        IP.item_pos = item_pos
        IP.item_offset = item_offset
        IP.item_length = item_length
        IP.item_end = item_end
        IP.item_pos_offset = item_pos --+ item_offset
        
        IP.item_area_to_analyze_start = item_area_to_analyze_start
        IP.item_area_to_analyze_length = item_area_to_analyze_length
        IP.cur_pos_in_item = cur_pos_in_item
        IP.timeline_cur_pos_in_item = timeline_cur_pos_in_item
        IP.outsideBoundries = outsideBoundries
        
        IP.overview_start_in_item = overview_start_in_item
        IP.overview_start_in_item_offset = overview_start_in_item_offset
        IP.overview_length_in_item = overview_length_in_item
        IP.overview_end_in_item = overview_end_in_item
        IP.start_time_in_item = start_time_in_item
        IP.end_time_in_item = end_time_in_item
        
        IP.overview_start_time = overview_start_time
        IP.overview_length_time = overview_length_time
        
        if (last_item_length and last_item_length ~= IP.item_length) or
          (last_item_pos and last_item_pos ~= IP.item_pos) or
          (last_item_offset and last_item_offset ~= IP.item_offset) then 
          find_cut_data(IP)
        end
        
    end
    
    -- we find values that are stored between defer rounds. We use IP.item as recognizer as this will work even when swapping items
    --if not last_cur_pos_in_item_array then last_cur_pos_in_item_array = {} end
    --IP.last_cur_pos_in_item = last_cur_pos_in_item_array[itemString]
    
    --pngPathA = pngPath_array[itemString].pngPathA
    --pngPathB = pngPath_array[itemString].pngPathB
    
    
    --[[
    IP.last_currentSelectedCut = IP.last_currentSelectedCut 
    
    IP.currentSelectedCut = IP.currentSelectedCut 
    ]]
end


function getItemProperties(item, itemNumber, proj)
    itemNumber = itemNumber or 0
    -- Get selected media item
    if not item then
        --reaper.ShowMessageBox("No item selected", "Error", 0)
        return {itemNumber = itemNumber}
    end

    -- Get active take
    local take = reaper.GetActiveTake(item)
    if not take or not reaper.TakeIsMIDI(take) then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_type = reaper.GetMediaSourceType(source, "")
        if source_type == "VIDEO" then
            local filePath = reaper.GetMediaSourceFileName(source, "")
            local directory = GetDirectoryFromPath(filePath)
            local fileName = GetFilenameNoExt(filePath)
            -- Get take offset (when source starts)
            -- Get media source
            local src = reaper.GetMediaItemTake_Source(take)
            local src_len = reaper.GetMediaSourceLength(source)
            
            
            local base = filePath:match("(.+)%.[^%.]+$") or ""
            local cutTextFilePathRaw = base .. "_cutsRaw.txt"  
            local cutTextFilePath = base .. "_cuts.txt"  
            
            local thumbnailPath = base .. seperator
            local thumbnailPath_exist = DirectoryExists(thumbnailPath)
            
            
            
            
            

            local itemInfo = {  
                      item = item, 
                      take = take, 
                      filePath = filePath, 
                      directory = directory, 
                      fileName = fileName, 
                      item_source_length = src_len, 
                      cutTextFilePathRaw = cutTextFilePathRaw, 
                      cutTextFilePath = cutTextFilePath, 
                      thumbnailPath = thumbnailPath, 
                      thumbnailPath_exist = thumbnailPath_exist,
                      itemNumber = itemNumber, 
            }
            
            
            getItemRealtimeInfo(itemInfo, proj)
            
            
            find_cut_data(itemInfo)
            
            return itemInfo
            
        else
           -- return {}
        end
    else
        --return {}
    end
end

function getSelectedVideoFile(index, proj) 

    local item = reaper.GetSelectedMediaItem(proj and proj or 0, index and index or 0)
    if getVideoItemFilePath(item) then
        return item
    end
end


function move_cursor_by_frames(frames)
    --local fps = reaper.TimeMap_curFrameRate(0)

    local tc_start = reaper.GetProjectTimeOffset(0, false)

    local time = reaper.GetCursorPosition()
    local current_frame = math.floor((time - tc_start) * frames_per_second + 0.5)
    local new_frame = current_frame + frames
    local new_time = tc_start + new_frame / frames_per_second

    reaper.SetEditCurPos(new_time, true, false)
end
--------------------------------------------------------
-----------------IMGUI HELPERS--------------------------
--------------------------------------------------------


function setToolTipFunc(text, shortcut, color)
    if settings.showToolTip and text and #tostring(text) > 0 and not isMouseDown then
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(), color and color or colorWhite)
        if shortcut then
            text = text .. ".\n - press ".. shortcut .. " to set with keyboard"
        end
        ImGui.SetItemTooltip(ctx, text)
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
end

-- Same as setToolTipFunc, with the full name of whatever is hovered as a first line in
-- italic grey above the description.
--
-- For the places where the label on screen is shortened to fit. The name is the thing
-- you are most likely hovering to read, so it goes first; italic grey so it reads as a
-- caption identifying the control rather than as part of the explanation.
--
-- Built with BeginItemTooltip rather than SetItemTooltip because the two lines are
-- styled differently, and SetItemTooltip takes one string under one pushed colour.
function setToolTipWithName(fullName, text, shortcut)
    if not settings.showToolTip or isMouseDown then return end
    if (not fullName or fullName == "") and (not text or text == "") then return end

    -- Pushed before Begin: the border colour applies to the tooltip window itself, and
    -- a style pushed after it has opened comes too late to affect it.
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
    if reaper.ImGui_BeginItemTooltip(ctx) then
        if fullName and fullName ~= "" then
            -- fontItalic is nil when the face could not be made, and PushFont then only
            -- sets the size, so this degrades to upright grey rather than failing.
            reaper.ImGui_PushFont(ctx, fontItalic, reaper.ImGui_GetFontSize(ctx))
            reaper.ImGui_TextColored(ctx, colorGrey, fullName)
            reaper.ImGui_PopFont(ctx)
        end
        if text and text ~= "" then
            local body = shortcut
                         and (text .. ".\n - press " .. shortcut .. " to set with keyboard")
                         or text
            reaper.ImGui_TextColored(ctx, colorWhite, body)
        end
        reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx)
end



local images = {}
local function imageFromCache(fn)
    local img = images[fn]
    if not img then
        img = {}
        images[fn] = img
    end

    if not ImGui.ValidatePtr(img.inst, 'ImGui_Image*') then
        if img.inst then images[img.inst] = nil end
        img.inst = reaper.ImGui_CreateImage(fn, reaper.ImGui_ImageFlags_NoErrors())
        local prev = images[img.inst]
        if prev and prev ~= img then prev.inst = nil end
        images[img.inst] = img
    end

    return img.inst
end



------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
function GetFirstVisibleVideoItemUnder(cursor_pos, proj)
    proj = proj and proj or 0
    --local cursor_pos = reaper.GetCursorPosition()
    local track_count = reaper.CountTracks(proj)
    local firstItem
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(proj, i)
        local track_muted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        if track_muted == 0 then
            local item_count = reaper.CountTrackMediaItems(track)
            for j = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(track, j)
                local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local item_end = item_pos + item_len

                if cursor_pos >= item_pos and cursor_pos <= item_end then
                    -- Check if item is visible and has video
                    local take = reaper.GetActiveTake(item)
                    if take and not reaper.TakeIsMIDI(take) then
                        local source = reaper.GetMediaItemTake_Source(take) 
                        local filename = reaper.GetMediaSourceFileName(source, "")
                        local source_type = reaper.GetMediaSourceType(source, "")
                        if (source_type == "VIDEO" or source_type == "VIDEOFF" or source_type == "MOV" or source_type == "MP4") and filename:match(".png") == nil then
                            -- Optional: check if the item is not hidden in video
                            local visible = reaper.GetMediaItemInfo_Value(item, "B_UISEL") -- or use a custom logic
                            
                            --if settings.compareVideoMode then  
                                if not firstItem then 
                                    firstItem = item
                                else
                                    return firstItem, item
                                end
                            --else 
                            --    return item
                            --end
                        end
                    end
                end
            end
        end
    end

    return firstItem -- nothing found
end

function convertColorToReaper(track)
    local color = reaper.GetTrackColor(track)
    -- shift 0x00RRGGBB to 0xRRGGBB00 then add 0xFF for 100% opacity
    return color & 0x1000000 ~= 0 and (reaper.ImGui_ColorConvertNative(color) << 8) | 0xFF or colorTransparent
end

--- APP SPECIFIC FUNCTION
function setArrangeviewArea()
    if settings.arrangeviewFollowsOverview then
        if settings.selectionType == "Time selection" then
            reaper.Main_OnCommand(40031, 0) --View: Zoom time selection
        else
            local item = GetFirstVisibleVideoItemUnder(cur_pos)
            if item then
                local IP = getItemProperties(item)
                
                local item_pos = IP.item_pos
                local item_offset = IP.take_offset
                local item_length = IP.item_length
                local item_end = IP.item_end
                local hwnd = reaper.GetMainHwnd()
                local arrange_view = reaper.JS_Window_FindChildByID(hwnd, 1000) -- 1000 = arrange view
                local retval, left, top, right, bottom = reaper.JS_Window_GetClientRect(arrange_view)
                local arrange_width_pixels = right - left
                local widthInPixelRelativeToItemLength = item_length / arrange_width_pixels
                local pixelMargin = widthInPixelRelativeToItemLength * 80

                reaper.GetSet_ArrangeView2(0, true, 0, 0, item_pos - pixelMargin, item_end + pixelMargin)
            end
        end
    end
end

function moveCursorToPos(pos)
    if pos and isSuperDown or settings.cursorFollowSelectedCut then
        if playState ~= 0 then
            reaper.Main_OnCommandEx(1016, 0,0) --Transport: Stop
        end
        if is_a_subproject then
            pos = pos - subProj_item_pos
        end
        reaper.SetEditCurPos2(0, pos, true, false)
        if playState ~= 0 then
            reaper.Main_OnCommandEx(1007, 0,0) --Transport: Play
        end
    end
end


function updateCutDataFile(IP)
    saveFile(IP.cutTextFilePath, json.encodeToJson(IP.cut_data))
end

-- Clears what the previous detector found, in memory and on disk, for whichever items
-- are loaded. The stored _cuts.txt is deleted rather than emptied, so the next analysis
-- starts from nothing instead of merging against a file full of the other detector's
-- answers.
function clearStoredCutsForMethodChange()
    for _, IP in ipairs({ itemProperties, item2Properties, conformIP1, conformIP2 }) do
        if IP and IP.filePath then
            IP.cut_data      = {}
            IP.analysisMade  = nil
            local s = vpCutStateFor(IP)
            if s then
                if s.job then
                    reaper.VP_AnalyzeCancel(s.job)
                    reaper.VP_AnalyzeRelease(s.job)
                end
                -- cleared rather than replaced, so the table the other IPs for this
                -- same file are holding is the one that gets emptied
                s.job, s.done, s.err = nil, nil, nil
            end
            if IP.cutTextFilePath    then os.remove(IP.cutTextFilePath) end
            if IP.cutTextFilePathRaw then os.remove(IP.cutTextFilePathRaw) end
        end
    end
    old_cut_data = {}
    analysing    = false
    update_cut_data = true   -- make the next frame rebuild from the empty state
end



function getCutData(IP)
    if not IP then return end
    local s = vpCutStateFor(IP)
    if s and s.done then
        IP.cut_data = vpExtractCuts(IP)
        return
    end
    if fast then
        IP.cut_data = extract_cut_data_fast(IP)
    else
        IP.cut_data = extract_cut_data(IP)
    end
end

function update_cut_data_on_all_items(IPS)
    for _ , IP in ipairs(IPS) do
        find_cut_data(IP)
    end
end

function find_cut_data(IP)
    if not IP then return end

    -- The derived collections, before anything can return without reaching the places
    -- further down that build them.
    --
    -- getItemProperties rebuilds the item-property table from scratch and then calls
    -- this, so whatever this function leaves unset is nil for the rest of the frame --
    -- and while an analysis is running it returns early, long before these are
    -- populated. The UI iterates and indexes all three without checking, so every frame
    -- of a first analysis raised "attempt to index a nil value". It worked on the second
    -- attempt only because by then a framestore existed and the early return was never
    -- taken.
    --
    -- Done here rather than at each return: there are several, and the next one added
    -- would have the same problem. cut_data is deliberately NOT in this list -- the
    -- fallback at the end of the function uses its being nil to tell "never loaded"
    -- from "no cuts found", so forcing it would stop stored cuts being read from disk.
    IP.cut_data_time_pos      = IP.cut_data_time_pos      or {}
    IP.cuts_within_selection  = IP.cuts_within_selection  or {}
    IP.cuts_making_threashold = IP.cuts_making_threashold or {}

    -- The extension's analysis is a background thread rather than a file appearing, so
    -- it is polled here and then feeds the same path: once the store is built, `done`
    -- stands in for the raw file the FFmpeg run would have written. The state is keyed
    -- by file path, not held on IP, because IP is rebuilt under us -- see vpCutState.
    local vs = vpCutStateFor(IP)
    if vs and vs.job then
        local st = reaper.VP_AnalyzeState(vs.job)
        if st == 0 then
            analysing = true
            analysingAmount = reaper.VP_AnalyzeProgress(vs.job)
            -- Empty rather than left alone, because this returns before the fallback at
            -- the end of the function that gives cut_data a value -- and the item
            -- properties are rebuilt from scratch every frame while an analysis runs, so
            -- without this every frame of a first analysis hands the rest of the UI a
            -- nil to index. Which it did: "attempt to index a nil value" the first time
            -- a new video was analysed.
            --
            -- Set here and not at the top of the function: the fallback distinguishes
            -- "no cuts yet" from "never loaded" by this being nil, and making it {}
            -- unconditionally would stop stored cuts ever being read back from disk.
            IP.cut_data = IP.cut_data or {}
            return
        end
        if st == 2 then
            vs.err = tostring(reaper.VP_AnalyzeError(vs.job))
        end
        reaper.VP_AnalyzeRelease(vs.job)
        vs.job  = nil
        vs.done = (st == 1) or nil
        analyseEndTime = time_precise
    end

    analyseRaw = (vs and vs.done)
                 or (IP.cutTextFilePathRaw and reaper.file_exists(IP.cutTextFilePathRaw))
    analysing = false
    if analyseRaw then

        if not IP.cut_data or #IP.cut_data == 0 then
            local fromExtension = vs and vs.done
            getCutData(IP)
            analysing = true
            analyseEndTime = time_precise

            -- A store that yields nothing would otherwise leave `analysing` set for
            -- good: on the FFmpeg path a missing file eventually ends it, but here
            -- nothing is going to appear.
            if fromExtension and #IP.cut_data == 0 then
                vs.done   = nil
                vs.err    = "no cuts found - try a lower Jump or Motion"
                analysing = false
                -- Cleared here too, because this path returns before the place that
                -- normally does it. Leaving it set holds the refresh guard true, which
                -- rebuilds every item's properties on every frame from then on.
                analyseStartTime, analyseEndTime = nil, nil
                return
            end

            if #IP.cut_data > 0 then
                analysing = false
                if fromExtension then
                    vs.done = nil           -- consumed; the store itself stays cached
                else
                    os.remove(IP.cutTextFilePathRaw)
                end
                local new_cuts_start = IP.item_area_to_analyze_start
                local new_cuts_length = IP.item_area_to_analyze_length
                local new_cuts_end = new_cuts_start + new_cuts_length
                --table.insert(IP.cut_data, 1, {time = IP.overview_start_in_item, special = "start"})
                table.insert(IP.cut_data, 1, { time = new_cuts_start, special = "start" })
                --table.insert(IP.cut_data, {time = IP.overview_start_in_item + IP.overview_length_in_item, special = "end"})
                table.insert(IP.cut_data, { time = new_cuts_end, special = "end" })

                if old_cut_data and #old_cut_data > 0 then
                    local analyseAreaStarted, newAreaStarted
                    local new_cut_data_table = {}
                    local newTableAdded = false

                    if new_cuts_start <= old_cut_data[1].time then
                        new_cut_data_table = cut_data
                        newTableAdded = true
                    end
                    
                    if new_cut_data_table then 
                        for _, t in ipairs(old_cut_data) do
                            if t.time < new_cuts_start or t.time > new_cuts_end then
                                if t.special == "start" then
                                    analyseAreaStarted = true
                                elseif t.special == "end" then
                                    analyseAreaStarted = false
                                end
                                table.insert(new_cut_data_table, t)
                            else
                                if t.special == "start" then
                                    -- in case the old area starts on top of an new area
                                    analyseAreaStarted = true
                                end
                                if not newTableAdded then
                                    newTableAdded = true
                                    for _, tn in ipairs(IP.cut_data) do
                                        if tn.special == "start" and analyseAreaStarted then
                                            analyseAreaStarted = false
                                            -- in case the new area starts on top of an old area
                                            -- we do not add the start
                                        elseif tn.special == "end" and analyseAreaStarted then
                                            -- in case the old area starts on top of an new area
                                            -- we do not add the end
                                        else
                                            table.insert(new_cut_data_table, tn)
                                        end
                                    end
                                end
                            end
                        end

                        if not newTableAdded then
                            for _, tn in ipairs(IP.cut_data) do
                                table.insert(new_cut_data_table, tn)
                            end
                        end
    
                        old_cut_data = {}
                        IP.cut_data = deep_copy(new_cut_data_table)
                    
                    end
                end

                updateCutDataFile(IP)
            end
        end
    end
    
    
    -- store analyze
    IP.analysisMade = IP.cutTextFilePath and reaper.file_exists(IP.cutTextFilePath)
    if not IP.cut_data and not analysing then
        if IP.analysisMade then
            -- A truncated or hand-edited cut file decodes to nil, which used to be
            -- assigned straight to cut_data. This runs every frame and only runs when
            -- cut_data is nil, so it then re-read and re-failed on the file forever.
            -- Anything unreadable is taken as no cuts instead.
            local storedCuts = json.decodeFromJson(readFile(IP.cutTextFilePath))
            IP.cut_data = (type(storedCuts) == "table") and storedCuts or {}
        else
            IP.cut_data = {}
        end
    end
    
    -- store analyze speed
    if IP.cut_data and #IP.cut_data > 0 then 
        if analyseEndTime and analyseStartTime and analyseEndTime > analyseStartTime then 
            -- FFmpeg's timings only. This figure has exactly one reader: the progress
            -- bar, which has to guess at FFmpeg's progress because FFmpeg reports none
            -- while it runs. The extension reports real progress, so it never consults
            -- this -- but it used to write to it, and the two are several times apart in
            -- wall time on the same file. A few extension runs dragged the average out,
            -- and FFmpeg's bar then crawled and reached the end long before the run did.
            if not cutMethodIsExtension() and (IP.item_area_to_analyze_length or 0) > 0 then
                local analyseSpeed = (analyseEndTime - analyseStartTime) / IP.item_area_to_analyze_length
                if analyseSpeed > 0 then 
                    analyseSpeed = math.floor(analyseSpeed * 1000) / 1000
                    settings.analyseSpeed = ((settings.analyseSpeed and settings.analyseSpeed or analyseSpeed) + analyseSpeed) / 2 
                    saveSettings() 
                end
            end
            -- Cleared either way, whichever detector ran and whether or not a speed was
            -- recorded: analyseStartTime holds the refresh guard true, and leaving it set
            -- rebuilds every item's properties on every frame from then on.
            analyseStartTime = nil
            analyseEndTime = nil
        end
    end
    
    
    --[[
        -- filter for frames that are right after another frame
        local filter_results = {}
        for i, e in ipairs(results) do
            local time = e.time --roundToFrame(e.time, frames_per_second)
            
            if not last_time or time - last_time > (1.1 / frames_per_second) then -- compareWithMargin(e.time, last_time, (1 / frames_per_second)) do
                 table.insert(filter_results, e)
            end
            last_time = time
        end 
    ]]
    
    
    IP.cut_data_time_pos = {} 
    if IP.thumbnailPath_exist then 
        for i, cutInfo in pairs(IP.cut_data) do
            local time_seconds_rounded = roundToFrame(cutInfo.time, frames_per_second)
            local pngPath = IP.thumbnailPath .. IP.fileName .. "_" .. math.floor(time_seconds_rounded * 1000 + 0.5) .. "ms.png" 
            IP.cut_data[i].pngPath = pngPath
            
            local oneFrameEarlier = time_seconds_rounded - (1 / frames_per_second)  
            local pngPath_frame_before = IP.thumbnailPath .. IP.fileName .. "_" .. math.floor(oneFrameEarlier * 1000 + 0.5) .. "ms.png" 
            IP.cut_data[i].pngPath_frame_before = pngPath_frame_before
            IP.cut_data[i].time_frame_before = oneFrameEarlier 
            --reaper.ShowConsoleMsg(time_seconds_rounded .. " - " .. oneFrameEarlier .. "\n")
            IP.cut_data_time_pos[time_seconds_rounded] = pngPath
            IP.cut_data_time_pos[oneFrameEarlier] = pngPath_frame_before
        end
    end

    
    IP.cuts_within_selection = {}
    IP.cuts_making_threashold = {}
    last_cut_time = -100000
    for i, cutInfo in pairs(IP.cut_data) do
        --local cut = {}
        -- reaper.SetEditCurPos(time+position, false, false)
        -- reaper.Main_OnCommandEx(40012,0,0)
        -- SPLIT: 40012
        local time = cutInfo.time 
        local exclude = cutInfo.exclude and cutInfo.exclude or false 
        --reaper.ShowConsoleMsg(tostring(IP.item_offset) .. "\n")
        if time >= IP.item_offset and time < IP.item_length + IP.item_offset and not cutInfo.special then 
            table.insert(IP.cuts_within_selection, { index = i, time = time, exclude = exclude })
            
            if (not settings.onlyShowCutsWithEditedName and 
                  (cutInfo.score and cutInfo.score <= settings.threshold and cutInfo.time >= IP.item_area_to_analyze_start and cutInfo.time <= IP.item_area_to_analyze_start + IP.item_area_to_analyze_length) 
                or (settings.alwaysShowCutsWithEditedName and (cutInfo.name or cutInfo.color)))
                or (settings.onlyShowCutsWithEditedName and (cutInfo.name or cutInfo.color)) then
                

                --itemEnd = roundToFrame(time + videoStart, frames_per_second)
                if settings.removeCutsWithinXFrames == 0 or (not last_cut_time or (time - last_cut_time) > ((settings.removeCutsWithinXFrames)/frames_per_second)) then 
                --if default_insideTime == 0 or itemStart >= start_time_sel and itemStart < end_time_sel then
                    table.insert(IP.cuts_making_threashold, { index = i, time = time, exclude = exclude }) --,itemEnd=itemEnd, videoStartOffset = videoStartOffset})
                    
                    last_cut_time = time    
                end
                    
                --if default_createThumbnails == 1 then
                -- createThumbnails(videoStartOffset)
                --end
                --reaper.AddProjectMarker(0, false, time + position, 0., "Cut: " .. line, n)
                --itemStart = itemEnd
                --videoStartOffset = roundToFrame(time + start_offset, frames_per_second)
                --end
            end
        end
    end
    
end




function settingsCheckBoxes(IP, IP2)
    --if start_time_sel ~= end_time_sel and start_time_sel < end_time_sel then
    --reaper.ImGui_SameLine(ctx)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Overview area from:")
    reaper.ImGui_SameLine(ctx)
    
    local selectionTypes = {"Video item", "Time selection", "Arrange view"}
    local selectionTypesShortcut = {isV, isT, isA}
    local selectionTypesShortcutText = {"v", "t", "a"}
    
    if is_a_subproject then  
        reaper.ImGui_Text(ctx, "Subproject")
    else
        for i, s in ipairs(selectionTypes) do
            if reaper.ImGui_RadioButton(ctx, s, settings.selectionType == s) or ((not markerNameIsFocused or isSuperDown) and selectionTypesShortcut[i]) then
                settings.selectionType = s
                saveSettings()
                update_cut_data_after_selectionType_change = true
            end
            setToolTipFunc("Use " .. s .. " for what the script overview should show", selectionTypesShortcutText[i])
            reaper.ImGui_SameLine(ctx)
            
            --reaper.ImGui_SameLine(ctx, _G["posX" .. i + 1])
        end 
        
        
        if (not markerNameIsFocused or isSuperDown) and isU then
            local found
            for i, s in ipairs(selectionTypes) do
                if settings.selectionType == s then
                    if isShiftDown then 
                        settings.selectionType = i == 1 and selectionTypes[#selectionTypes] or selectionTypes[i - 1]
                    else
                        settings.selectionType = i == #selectionTypes and selectionTypes[1] or selectionTypes[i + 1]
                    end
                    saveSettings()
                    update_cut_data_after_selectionType_change = true
                    break
                end
            end 
            --settings.analyseOnlyBetweenMarkers = not settings.analyseOnlyBetweenMarkers
            --setArrangeviewArea()
            --saveSettings()
            --update_cut_data = true
        end
    end
    
    
    if settings.selectionType == "Arrange view" then reaper.ImGui_BeginDisabled(ctx) end
    reaper.ImGui_SameLine(ctx, posX3)
    ret, settings.arrangeviewFollowsOverview = reaper.ImGui_Checkbox(ctx, "link arrange view", settings.arrangeviewFollowsOverview)
    if ret then
        setArrangeviewArea()
        saveSettings()
    end
    setToolTipFunc("Link arrange view to width of selection", "l")
    
    if (not markerNameIsFocused or isSuperDown) and isL then
        settings.arrangeviewFollowsOverview = not settings.arrangeviewFollowsOverview
        saveSettings()
        if settings.arrangeviewFollowsOverview then 
            setArrangeviewArea() 
        end
        --update_cut_data = true
        
        find_cut_data(IP)
        find_cut_data(IP2)
    end
    if settings.selectionType == "Arrange view" then reaper.ImGui_EndDisabled(ctx) end
    
    
    --[[
    if (not markerNameIsFocused or isSuperDown) and isL then
        settings.overviewFollowsArrangeview = not settings.overviewFollowsArrangeview
        saveSettings()
        --update_cut_data = true
        --setArrangeviewArea()
        
        find_cut_data(IP)
        find_cut_data(IP2)
    end


    reaper.ImGui_SameLine(ctx, posX2)
    if settings.analyseOnlyBetweenMarkers then
        ret, settings.arrangeviewFollowsOverview = reaper.ImGui_Checkbox(ctx, "link arrange view to overview",
            settings.arrangeviewFollowsOverview)
        if ret then
            setArrangeviewArea()
            saveSettings() 
            --update_cut_data = true
            
            find_cut_data(IP)
            find_cut_data(IP2)
        end
        setToolTipFunc("Link arrange view with the editor view", "l")

        if (not markerNameIsFocused or isSuperDown) and isL then
            settings.arrangeviewFollowsOverview = not settings.arrangeviewFollowsOverview
            saveSettings()
            setArrangeviewArea() 
            --update_cut_data = true
            
            find_cut_data(IP)
            find_cut_data(IP2)
        end
    else
        
    end
    
    ]]
    
    

    --reaper.ImGui_SameLine(ctx, posX3)
    ret, settings.cursorFollowSelectedCut = reaper.ImGui_Checkbox(ctx, "playhead follows selected cut", settings.cursorFollowSelectedCut)
    if ret then
        if settings.cursorFollowSelectedCut then
            moveCursorToPos(cur_pos)
        end

        saveSettings()
    end
    setToolTipFunc("Playhead will jump to selected cut position", "p")

    if (not markerNameIsFocused or isSuperDown) and isP then
        settings.cursorFollowSelectedCut = not settings.cursorFollowSelectedCut
        if settings.cursorFollowSelectedCut then
            moveCursorToPos(cur_pos)
        end

        saveSettings()
    end


    reaper.ImGui_SameLine(ctx, posX2)
    ret, settings.navigationFollowsPlayhead = reaper.ImGui_Checkbox(ctx, "selection follows playhead", settings.navigationFollowsPlayhead)
    if ret then
        saveSettings()
    end
    setToolTipFunc("Select cut marker when playhead passes", "s")

    if (not markerNameIsFocused or isSuperDown) and isS then
        settings.navigationFollowsPlayhead = not settings.navigationFollowsPlayhead
        saveSettings()
    end
    
    
    if settings.selectionType == "Time selection" then reaper.ImGui_BeginDisabled(ctx) end
    reaper.ImGui_SameLine(ctx, posX3)
    ret, settings.displayTimeSelection = reaper.ImGui_Checkbox(ctx, "display time selection", settings.displayTimeSelection)
    if ret then
        saveSettings()
    end
    setToolTipFunc("Display time selection in the overview area")
    if settings.selectionType == "Time selection" then reaper.ImGui_EndDisabled(ctx) end

end


function settingsCheckBoxesOLD(IP, IP2)
    --if start_time_sel ~= end_time_sel and start_time_sel < end_time_sel then
    --reaper.ImGui_SameLine(ctx)
    ret, settings.analyseOnlyBetweenMarkers = reaper.ImGui_Checkbox(ctx, "use area within time selection", settings.analyseOnlyBetweenMarkers)
    if ret then
        setArrangeviewArea()
        saveSettings()
        update_cut_data = true
    end
    setToolTipFunc("Only show area within reaper time selection", "u")
    --end

    if (not markerNameIsFocused or isSuperDown) and isU then
        settings.analyseOnlyBetweenMarkers = not settings.analyseOnlyBetweenMarkers
        setArrangeviewArea()
        saveSettings()
        update_cut_data = true
    end



    --[[


    if settings.analyseOnlyBetweenMarkers then
        reaper.ImGui_SameLine(ctx)
        ret, settings.overviewFollowsLoopSelection = reaper.ImGui_Checkbox(ctx, "overview to time selection link", settings.overviewFollowsLoopSelection)
        if ret then
            saveSettings()
        end
    end

    if isSuperDown and not isShiftDown and isO then
        settings.overviewFollowsLoopSelection = not settings.overviewFollowsLoopSelection
        saveSettings()
    end
   ]]


    reaper.ImGui_SameLine(ctx, posX2)
    if settings.analyseOnlyBetweenMarkers then
        ret, settings.arrangeviewFollowsOverview = reaper.ImGui_Checkbox(ctx, "link arrange view to overview",
            settings.arrangeviewFollowsOverview)
        if ret then
            setArrangeviewArea()
            saveSettings() 
            --update_cut_data = true
            
            find_cut_data(IP)
            find_cut_data(IP2)
        end
        setToolTipFunc("Link arrange view with the editor view", "l")

        if (not markerNameIsFocused or isSuperDown) and isL then
            settings.arrangeviewFollowsOverview = not settings.arrangeviewFollowsOverview
            saveSettings()
            setArrangeviewArea() 
            --update_cut_data = true
            
            find_cut_data(IP)
            find_cut_data(IP2)
        end
    else
        ret, settings.overviewFollowsArrangeview = reaper.ImGui_Checkbox(ctx, "link overview to arrange view", settings.overviewFollowsArrangeview)
        if ret then
            --setArrangeviewArea()
            saveSettings()
        end
        setToolTipFunc("Link arrange view to width of selection.\n- press " .. MOD_CMD .. "+l to set with keyboard")

        if (not markerNameIsFocused or isSuperDown) and isL then
            settings.overviewFollowsArrangeview = not settings.overviewFollowsArrangeview
            saveSettings()
            --update_cut_data = true
            --setArrangeviewArea()
            
            find_cut_data(IP)
            find_cut_data(IP2)
        end
    end

    reaper.ImGui_SameLine(ctx, posX3)
    ret, settings.cursorFollowSelectedCut = reaper.ImGui_Checkbox(ctx, "playhead follows selected cut", settings.cursorFollowSelectedCut)
    if ret then
        if settings.cursorFollowSelectedCut then
            moveCursorToPos(cur_pos)
        end

        saveSettings()
    end
    setToolTipFunc("Playhead will jump to selected cut position.\n- press " .. MOD_CMD .. "+p to set with keyboard")

    if (not markerNameIsFocused or isSuperDown) and isP then
        settings.cursorFollowSelectedCut = not settings.cursorFollowSelectedCut
        if settings.cursorFollowSelectedCut then
            moveCursorToPos(cur_pos)
        end

        saveSettings()
    end


    reaper.ImGui_SameLine(ctx, posX4)
    ret, settings.navigationFollowsPlayhead = reaper.ImGui_Checkbox(ctx, "selection follows playhead", settings.navigationFollowsPlayhead)
    if ret then
        saveSettings()
    end
    setToolTipFunc("Select cut marker when playhead passes.\n- press " .. MOD_CMD .. "+s to set with keyboard")

    if (not markerNameIsFocused or isSuperDown) and isS then
        settings.navigationFollowsPlayhead = not settings.navigationFollowsPlayhead
        saveSettings()
    end

    --reaper.ImGui_SameLine(ctx)
    
end


-- The two edited-name filters, shared by both detection modes: they are about which
-- cuts get shown, not about how cuts are found, so they belong to neither detector.
function cutEditedNameToggles(IP, IP2)
    
    reaper.ImGui_SameLine(ctx, posX3)
    ret, settings.onlyShowCutsWithEditedName = reaper.ImGui_Checkbox(ctx, "only show edited cuts", settings.onlyShowCutsWithEditedName)
    if ret then
        setArrangeviewArea()
        saveSettings()
        find_cut_data(IP)
        find_cut_data(IP2)
    end
    setToolTipFunc("Hide cuts that does not have an edited name.\n- press " .. MOD_CMD .. "+o to set with keyboard")

    if (not markerNameIsFocused or isSuperDown) and isO then
        settings.onlyShowCutsWithEditedName = not settings.onlyShowCutsWithEditedName
        saveSettings()
        find_cut_data(IP)
        find_cut_data(IP2)
    end


    reaper.ImGui_SameLine(ctx, posX4)
    ret, settings.alwaysShowCutsWithEditedName = reaper.ImGui_Checkbox(ctx, "never hide edited cuts", settings.alwaysShowCutsWithEditedName)
    if ret then
        setArrangeviewArea()
        saveSettings()
        find_cut_data(IP)
        find_cut_data(IP2)
    end
    setToolTipFunc( "Show cuts that have an edited name, even if they are outside threshold","n")

    if (not markerNameIsFocused or isSuperDown) and isN then
        settings.alwaysShowCutsWithEditedName = not settings.alwaysShowCutsWithEditedName
        saveSettings()
        find_cut_data(IP)
        find_cut_data(IP2)
    end
end

-- The extension detects on different quantities than scdet does, so it gets its own
-- three controls rather than being squeezed into sensitivity and cut frequency.
-- Re-detection is sub-millisecond once the store exists, so every change re-runs
-- immediately instead of waiting for a button.
local function cutShowingSettingsExtension(IP, IP2)
    -- opt+click puts a slider back to its factory value, and for that the slider must
    -- not see the click at all. Resetting after the fact was not enough: the slider had
    -- already taken the press and become the active item, so the value was set to the
    -- default and then dragged straight off it again by the same gesture.
    --
    -- So while opt is held these three are disabled, which makes them ignore the mouse
    -- entirely, and the reset is read from a hover test that still answers for a
    -- disabled item. Disabling needs no record of what was hovered last frame -- opt is
    -- not a modifier these sliders use for anything else -- and the dimming while it is
    -- held reads as "this will not drag now", which is true.
    --
    -- Typing a value is cmd+click, which is ImGui's own binding and not ours to set:
    -- it fires on ImGuiMod_Ctrl, and ReaImGui maps that to cmd on macOS -- the same key
    -- this script calls isSuperDown. Holding opt no longer interferes with it.
    local function slider(id, label, key, def, lo, hi, tip)
        reaper.ImGui_SetNextItemWidth(ctx, 120)
        local cur = settings[key] or def

        local optHeld = isOptionDown
        if optHeld then reaper.ImGui_BeginDisabled(ctx) end
        local ret, val = reaper.ImGui_SliderInt(ctx, id, cur, lo, hi, label)
        if optHeld then reaper.ImGui_EndDisabled(ctx) end

        if optHeld and isMouseClick
           and reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenDisabled()) then
            ret, val = true, def
        end
        if ret and val ~= cur then
            settings[key] = val
            saveSettings()
            -- The store is already built, so this is a re-detect, not a re-analysis.
            -- Only where one exists: otherwise this would announce an analysis that
            -- never happens and leave the tab showing progress forever.
            local function redetect(P)
                local s = vpCutStateFor(P)
                if not s then return end
                local store = s.store or (P.filePath .. ".vpfs")
                if not (reaper.VP_StoreFrames and reaper.VP_StoreFrames(store) > 0) then return end
                s.store, s.done, s.err = store, true, nil
                P.cut_data = {}
                find_cut_data(P)
            end
            redetect(IP)
            redetect(IP2)
        end
        -- setToolTipFunc renders the second argument as "press X to set with keyboard",
        -- so only the gesture that really types a value belongs there. It used to be
        -- given "opt+click to reset", which read as though opt were the way to type one.
        setToolTipFunc(tip .. "\n - " .. MOD_ALT .. "+click resets it to " .. def, MOD_CMD .. "+click")
    end

    slider("##cut_motion", "Motion %d%%", "cut_motion", 300, 0, 600,
        "How far the jump must stand out against the movement around it, as a percentage\n" ..
        "of the local median frame-to-frame distance. This is what separates a cut from\n" ..
        "fast motion. 0 turns it off, leaving a plain threshold.")

    reaper.ImGui_SameLine(ctx)
    slider("##cut_jump", "Jump %d", "cut_jump", 20, 4, 48,
        "How far the 64-bit frame fingerprint must move between two frames.\n" ..
        "Lower finds more, including more that are not cuts.")

    reaper.ImGui_SameLine(ctx)
    slider("##cut_gap", "Gap %d", "cut_gap", 20, 0, 100,
        "Frames. A weaker cut this close to a stronger one is dropped, so a flash frame\n" ..
        "or the two ends of a short dissolve report once rather than twice.")

    cutEditedNameToggles(IP, IP2)

    local errState = vpCutStateFor(IP)
    if errState and errState.err then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0xFF4444FF, errState.err)
    end
end

function cutShowingSettings(IP, IP2)
    if cutMethodIsExtension() then
        return cutShowingSettingsExtension(IP, IP2)
    end

    reaper.ImGui_SetNextItemWidth(ctx, 120)
    if settings.extremeCutDetection then
        ret, val = reaper.ImGui_SliderDouble(ctx, "##Cut threshold", settings.threshold, 1, 100, nil, reaper.ImGui_SliderFlags_NoInput())
    else
        ret, val = reaper.ImGui_SliderInt(ctx, "##Cut threshold", math.floor(settings.threshold + 0.5), 1, 100, nil, reaper.ImGui_SliderFlags_NoInput())
    end
    
    if ret then
        settings.threshold = val
        saveSettings()
        find_cut_data(IP)
        find_cut_data(IP2)
    end
    setToolTipFunc("Set the sensitivity for how likely there is a cut.\n - press keypad plus/minus to set with keyboard.\n - Hold down " .. MOD_CMD .. " for fine grained")
    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, "Sensitivity")
    
    if not isShiftDown and not markerNameIsFocused then 
        if isKeypadAdd then
            local newVal = settings.threshold + (isSuperDown and 0.01 or 1)
            if newVal > 100 then newVal = 100 end
            settings.threshold = newVal
            saveSettings() 
            find_cut_data(IP)
            find_cut_data(IP2)
        end
        
        if isKeypadSubtract then
            local newVal = settings.threshold -(isSuperDown and 0.01 or 1)
            if newVal < 1 then newVal = 1 end
            settings.threshold = newVal
            saveSettings()
            find_cut_data(IP)
            find_cut_data(IP2)
        end
    end
    
    
    reaper.ImGui_SetNextItemWidth(ctx, 120)
    reaper.ImGui_SameLine(ctx, posX2)
    ret, val = reaper.ImGui_SliderInt(ctx, "Cut frequency", settings.removeCutsWithinXFrames, 0, 100)
    if ret then 
        settings.removeCutsWithinXFrames = val
        saveSettings() 
        find_cut_data(IP)
        find_cut_data(IP2)
    end
    setToolTipFunc("Clean up the frequency of cuts or remove false detected cuts, that useually happens within 1 frame. This will remove cuts within X frames.\n - press shift+keypad plus/minus to set with keyboard")
    
    if isShiftDown and not markerNameIsFocused then 
        if isKeypadAdd then
            local newVal = settings.removeCutsWithinXFrames + 1
            if newVal > 100 then newVal = 100 end
            settings.removeCutsWithinXFrames = newVal
            saveSettings() 
            find_cut_data(IP)
            find_cut_data(IP2)
        end
        
        if isKeypadSubtract then
            local newVal = settings.removeCutsWithinXFrames - 1
            if newVal < 0 then newVal = 0 end
            settings.removeCutsWithinXFrames = newVal
            saveSettings()
            find_cut_data(IP)
            find_cut_data(IP2)
        end
    end

    cutEditedNameToggles(IP, IP2)
end




function cutColors(IP)
    -- COLORS
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorWhite)

    for i, col in ipairs(markerColors) do
        if i > 1 then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) - 6)
        end

        colSelected = (IP and IP.cut_data and IP.currentSelectedCut and IP.cut_data[IP.currentSelectedCut]) and (IP.cut_data[IP.currentSelectedCut].color and IP.cut_data[IP.currentSelectedCut].color or nil) or nil
        local colIsSelected = col == colSelected

        colButton = not colIsSelected and col & 0xFFFFFFFF55 or col


        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colButton)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colButton)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colButton)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colIsSelected and colorWhite or colorDarkGrey)
        local keyNumber = (i < 10 and i or 0)
        local key = reaper["ImGui_Key_" .. keyNumber]
        if reaper.ImGui_Button(ctx, "##markerColor" .. i, buttonSize, buttonSize) or (IP and IP.currentSelectedCut and (not markerNameIsFocused or isSuperDown) and not isCtrlDown and reaper.ImGui_IsKeyPressed(ctx, key())) then
            if isShiftDown or not IP.currentSelectedCut then
                undo_redo.save_undo(IP.cut_data)
                for _, c in ipairs(IP.cuts_making_threashold) do
                    IP.cut_data[c.index].color = col
                end
                updateCutDataFile(IP)
                --settings.defaultColor = col
                saveSettings()
            else
                if not IP.cut_data[IP.currentSelectedCut].color or IP.cut_data[IP.currentSelectedCut].color ~= col then
                    undo_redo.save_undo(IP.cut_data)
                    IP.cut_data[IP.currentSelectedCut].color = col
                    updateCutDataFile(IP)
                end
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 4)
        setToolTipFunc("Set marker color.\n- press " .. MOD_CMD .. "+" ..
        keyNumber .. " to set with keyboard\n- hold shift to set all markers")
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) - 6)

    function getRandomColor()
        return markerColors[math.floor(math.random() * #markerColors + 0.5)]
    end

    function getNextColor(color)
        nextIsTheColor = false
        for i, col in ipairs(markerColors) do
            if nextIsTheColor then
                return col
            end
            if col == color then
                nextIsTheColor = true
            end
        end
        return markerColors[1]
    end

    reaper.ImGui_PopStyleColor(ctx, 1)
    reaper.ImGui_PopStyleVar(ctx)

    if reaper.ImGui_Button(ctx, "C", buttonSize, buttonSize) or (IP and IP.currentSelectedCut and (not markerNameIsFocused or isSuperDown) and not isCtrlDown and isC) then
        if isShiftDown or not IP.currentSelectedCut then
            for i, c in ipairs(IP.cuts_making_threashold) do
                IP.cut_data[c.index].color = markerColors[((i - 1) % (#markerColors - 1)) + 1]
            end
            updateCutDataFile(IP)
            --settings.defaultColor = col
            saveSettings() 
            undo_redo.save_undo(IP.cut_data)
        else
            if not IP.cut_data[IP.currentSelectedCut].color or IP.cut_data[IP.currentSelectedCut].color ~= col then
                IP.cut_data[IP.currentSelectedCut].color = getNextColor(IP.cut_data[IP.currentSelectedCut].color)
                updateCutDataFile(IP)
                undo_redo.save_undo(IP.cut_data)
            end
        end
    end
    setToolTipFunc("Set cut to next color.\n- press " .. MOD_CMD .. "+c to set with keyboard\n- hold shift to set all markers")
end

function analyseButton(IP, btnName)
    -- Pulsing while nothing has been analysed: on a fresh video this is the one thing
    -- to do, and the page offers a great many buttons that are not it.
    local pulse = IP and IP.item and not IP.analysisMade
    if pulse then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), pulsatingColor(theme.accent, 3))
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), pulsatingColor(theme.accent, 3))
    end
    local clicked = reaper.ImGui_Button(ctx, btnName .. "##:" .. (IP.filePath or ""))
    if pulse then reaper.ImGui_PopStyleColor(ctx, 2) end
    if clicked then
        
        if analysing then
            os.remove(IP.cutTextFilePathRaw)
        else
            --os.remove(cutTextFilePath)
            if not isSuperDown and IP.cut_data and #IP.cut_data > 0 then
                old_cut_data = deep_copy(IP.cut_data)
            end
            IP.cut_data = {}
            --IP.cutTextFilePath = nil
            
            analyseStartTime = time_precise
            get_cut_information(IP)
            --if reaper.file_exists(cutTextFilePath) then
            --    cut_data = extract_cut_data(cutTextFilePath)
            --    updateCutDataFile(cutTextFilePath, cut_data)
            --end
            --find_cut_data(IP)
            
            --analysing = true
            --reaper.ImGui_OpenPopup(ctx, "Analysing Video")
            analysingAmount = 0 
            popupItemProperties = IP
        end 
    end
    
    setToolTipFunc("Click to analyse cut. Press escape on keyboard to stop analysing")
end


---- LAYOUT STUFF
function selectedItemButtons(IP)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), analysingColor)
    
    --reaper.ImGui_PopStyleColor(ctx)
        
    local itemNumber = IP and IP.itemNumber and IP.itemNumber or ""
    --local btnName = (IP.cutTextFilePath and reaper.file_exists(IP.cutTextFilePath)) and "Re-analyse video" or "Analyse video"
    reaper.ImGui_SameLine(ctx, posX4)
    analyseButton(IP, "Analyse video")
    --reaper.ImGui_SameLine(ctx)--, posX45)
    
   
    
    if IP.item then 
        --reaper.ImGui_SameLine(ctx, posX4 - 52) 
        reaper.ImGui_SameLine(ctx, posX45) 
        if reaper.ImGui_Button(ctx, "Extra##"..itemNumber) or (not markerNameIsFocused and isE) then
            reaper.ImGui_OpenPopup(ctx, "extra##"..itemNumber)
        end 
        setToolTipFunc("Click to see some extra options", "e")
        
        if (not markerNameIsFocused and isE) then
            local extraPosX, extraPosY = reaper.ImGui_GetItemRectMax(ctx) 
            reaper.ImGui_SetNextWindowPos(ctx,extraPosX - 10, extraPosY - 10)
        end
        
        if reaper.ImGui_BeginPopup(ctx, "extra##"..itemNumber) then 
            local closePopup = false
            if IP.analysisMade then 
                --if IP and (IP.cutTextFilePath and reaper.file_exists(IP.cutTextFilePath)) then
                --    analyseButton(IP, "Analyse video")
                --end
                

                if reaper.ImGui_Button(ctx, "Generate Thumbnails##"..itemNumber) then
                    generateThumbnailsForCuts(IP)
                end
                setToolTipFunc("Click to generate cut thumbnails to get instant navigation")

                if not IP.thumbnailPath_exist then reaper.ImGui_BeginDisabled(ctx) end
                if reaper.ImGui_Button(ctx, "Remove thumbnails") or isR then
                    local count = 0
                    local filePath = reaper.EnumerateFiles(IP.thumbnailPath,count)
                    while filePath do
                        os.remove(IP.thumbnailPath .. filePath)
                        count = count + 1
                        filePath = reaper.EnumerateFiles(IP.thumbnailPath,count)
                    end
                    os.remove(IP.thumbnailPath)
                    closePopup = true
                end
                setToolTipFunc("Click to remove generated thumbnails and the thumbnail folder", "r")
                if not IP.thumbnailPath_exist then reaper.ImGui_EndDisabled(ctx) end

                reaper.ImGui_Separator(ctx)

                local canDescribeAll = ollamaAvailable()
                if not canDescribeAll then reaper.ImGui_BeginDisabled(ctx) end
                if reaper.ImGui_Button(ctx, "Describe cuts##extra") then
                    -- Alt held while clicking replaces names that are already there,
                    -- the same as it does with the keyboard.
                    if describeAllCuts(IP, isOptionDown) then closePopup = true end
                end
                if not canDescribeAll then reaper.ImGui_EndDisabled(ctx) end
                setToolTipFunc(canDescribeAll
                    and ("Use Ollama to name each cut from a video frame.\n" ..
                         "Cuts that already have a name are left alone -- hold " .. MOD_ALT ..
                         " to replace those too.\nModel: " ..
                         (settings.ollama_model or "llava") .. "\nChange model in Settings.")
                    or ollamaWhyUnavailable(), "shift+d")

                if reaper.ImGui_Button(ctx, "Reset cut names##extra") then
                    for i, c in ipairs(IP.cuts_making_threashold) do
                        if IP.cut_data[c.index] then
                            IP.cut_data[c.index].name = nil
                        end
                    end
                    updateCutDataFile(IP)
                    closePopup = true
                end
                setToolTipFunc("Clear all cut names back to default (Cut 1, Cut 2, ...)")
            end
            
            if reaper.ImGui_Button(ctx, "Open video path") or isO then
                reaper.CF_ShellExecute(IP.directory)
                closePopup = true
            end
            setToolTipFunc("Click to remove generated thumbnails and the thumbnail folder", "o")
            
            if isEscape then
                closePopup = true
            end
            
            if closePopup then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            
            reaper.ImGui_EndPopup(ctx)
        end 
    end
end


function itemButton(IP)
    local itemNumber = IP and IP.itemNumber and IP.itemNumber or ""
    local fileName = (IP and IP.fileName) and IP.fileName or ("No video selected##1_" .. itemNumber)
    if reaper.ImGui_Button(ctx,  fileName) then
        if IP and IP.item then 
            reaper.Main_OnCommand(40289, 0) --Item: Unselect (clear selection of) all items 
            reaper.SetMediaItemSelected(IP.item, true)
            reaper.UpdateArrange()
        end
    end
    setToolTipFunc("Video loaded in editor. Click to select Media Item in timeline")
    
    
    
    if IP then  
        
        if IP and not analysing and IP.analysisMade and IP.cuts_making_threashold and #IP.cuts_making_threashold then 
            reaper.ImGui_SameLine(ctx)
            local cutsShown = IP.cuts_making_threashold and #IP.cuts_making_threashold or "NA"
            local cutsDetected = IP.cuts_within_selection and #IP.cuts_within_selection or "NA"
            local cutInfoText = IP.analysisMade and ("" .. cutsShown .. " cuts shown out of " .. cutsDetected .. " detected in selected video area") or "Video has not been analysed"
            reaper.ImGui_TextColored(ctx, colorGrey, cutInfoText)
        end
        
        -- A second Analyse button used to appear here, where the cut count goes, while
        -- the first one sat in its usual place a few pixels away -- two of the same
        -- button on screen at once. The pulse was the only thing this one added, so it
        -- moved into analyseButton itself and this went.
        selectedItemButtons(IP)
    end
end

--reaper.ImGui_SameLine(ctx)
function selectedCutInfoArea(IP)
    local itemNumber = IP and IP.itemNumber or ""
    reaper.ImGui_AlignTextToFramePadding(ctx)
    --reaper.ImGui_TextColored(ctx, colorGrey, "Video:")
    --reaper.ImGui_SameLine(ctx)
    itemButton(IP)
    
    if IP then  
        
        reaper.ImGui_Separator(ctx)
        --reaper.ImGui_SetCursorPosX(ctx, winW / 2 - itemNameW / 2)
        
        if not IP or not IP.currentSelectedCut then reaper.ImGui_BeginDisabled(ctx) end
        
        
        local addRemoveMarkerButtonWidth = IP and IP.currentSelectedCut and 64 or 68
        cutColors(IP)
        
        reaper.ImGui_SameLine(ctx)
        
        local markerName = ""
        if IP and IP.currentSelectedCut and IP.cut_data and IP.cut_data[IP.currentSelectedCut] then 
            if not IP.cut_data[IP.currentSelectedCut].name then 
                for i, c in ipairs(IP.cuts_making_threashold) do 
                    if IP.currentSelectedCut == c.index then
                        markerName = "Cut " .. i
                        break
                    end
                end
            else
                markerName = IP.cut_data[IP.currentSelectedCut].name
            end
        end
        
    
        --reaper.ImGui_AlignTextToFramePadding(ctx)
        --reaper.ImGui_Text(ctx, "Name:")
        --reaper.ImGui_SameLine(ctx)
    
    
        reaper.ImGui_SetNextItemWidth(ctx, posX4 - reaper.ImGui_GetCursorPosX(ctx) - 8)
        if not isSuperDown and isEnter and not markerNameIsFocused then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
        end
        colSelected = (IP and IP.currentSelectedCut and IP.cut_data and IP.cut_data[IP.currentSelectedCut]) and (IP.cut_data[IP.currentSelectedCut].color and IP.cut_data[IP.currentSelectedCut].color or colorBlue) or colorBlue
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), colSelected)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTextColorForBackground(colSelected))
        ret, markerTextInput = reaper.ImGui_InputText(ctx, "##Marker name", markerName, reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_NoUndoRedo())
        local newName = false
    
        reaper.ImGui_PopStyleColor(ctx, 2)
    
        markerNameIsFocused = reaper.ImGui_IsItemFocused(ctx)
    
        setToolTipFunc("Set marker name.\n- press enter to focus area, press enter again to select next marker\n- hold down shift to stay in name area")
    
        if ret and not isSuperDown and isEnter then
            if markerTextInput ~= markerName then
                undo_redo.save_undo(IP.cut_data)
                IP.cut_data[IP.currentSelectedCut].name = markerTextInput
                updateCutDataFile(IP)
            end
            if isShiftDown then
                reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
            else
                focusNavigation = true
            end
            findNextCut(IP)
        end
    
        if markerNameIsFocused and (isTab or isEscape) then
            focusNavigation = true
        end
            
        if not IP or not IP.currentSelectedCut then reaper.ImGui_EndDisabled(ctx) end
        
            
        reaper.ImGui_SameLine(ctx, posX4)
        
        
        if IP and IP.currentSelectedCut then 
            local isNotSelected = IP.currentSelectedCut and IP.cut_data and IP.cut_data[IP.currentSelectedCut] and IP.cut_data[IP.currentSelectedCut].exclude
            if reaper.ImGui_Checkbox(ctx, "Include", not isNotSelected) or (IP.currentSelectedCut and (not markerNameIsFocused or isSuperDown) and isI) then
                undo_redo.save_undo(IP.cut_data)
                IP.cut_data[IP.currentSelectedCut].exclude = not IP.cut_data[IP.currentSelectedCut].exclude
                updateCutDataFile(IP) 
                find_cut_data(IP)
            end
            
            setToolTipFunc( "Include marker in export. This way you can still show it but not include it", "i")
        
        
            reaper.ImGui_SameLine(ctx, posX45)
            if reaper.ImGui_Button(ctx, "Remove") or ((not markerNameIsFocused or isSuperDown) and isR) or (not markerNameIsFocused and (isBackspace or isDelete)) then
                undo_redo.save_undo(IP.cut_data)
                
                local next_cut_making_threashold
                for i, c in ipairs(IP.cuts_making_threashold) do
                    if IP.currentSelectedCut == c.index then
                        next_cut_making_threashold = i - 1
                        break
                    end
                end
                
                table.remove(IP.cut_data, IP.currentSelectedCut)
                updateCutDataFile(IP)
                -- update cut_data and cut_data_threshold 
                find_cut_data(IP)
                
                abc = next_cut_making_threashold
                IP.currentSelectedCut = next_cut_making_threashold and IP.cuts_making_threashold[next_cut_making_threashold] and IP.cuts_making_threashold[next_cut_making_threashold].index
                --IP.last_currentSelectedCut = nil
                findNextCut(IP, nil, false)
            end
    
            setToolTipFunc("Remove detected cut from timeline", "r/backspace/delete")

            reaper.ImGui_SameLine(ctx)
            local descCut   = IP.cut_data and IP.cut_data[IP.currentSelectedCut]
            local descDescs = descCut and descCut.descriptions
            local descCount = descDescs and #descDescs or 0
            local descIdx   = descCut and descCut.descriptionIdx  -- 0-based

            local descLabel = "Describe"
            if descCount > 1 and descIdx ~= nil then
                descLabel = "Describe (" .. (descIdx + 1) .. "/" .. descCount .. ")"
            end

            -- Only offered when it can actually work. Cycling through descriptions
            -- already fetched stays available either way: those are stored with the
            -- cut and need nothing running to read back.
            local canDescribe = ollamaAvailable()
            local canCycle    = descCount > 1
            local descOff     = not canDescribe and not canCycle
            if descOff then reaper.ImGui_BeginDisabled(ctx) end
            local descBtnClicked = reaper.ImGui_Button(ctx, descLabel)
            if descOff then reaper.ImGui_EndDisabled(ctx) end

            -- Right-click → description list popup
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then
                reaper.ImGui_OpenPopup(ctx, "desc_list##" .. itemNumber)
            end
            if reaper.ImGui_BeginPopup(ctx, "desc_list##" .. itemNumber) then
                -- Same gate as the button: this one also fetches.
                if reaper.ImGui_MenuItem(ctx, "Reanalyse", nil, false, canDescribe) then
                    if IP.filePath and descCut then
                        descCut.descriptions = nil
                        descCut.descriptionIdx = nil
                        descCut.descriptionCycleComplete = false
                        updateCutDataFile(IP)
                        undo_redo.save_undo(IP.cut_data)
                        descriptionQueue = {}
                        descriptionLastError = nil
                        table.insert(descriptionQueue, { cutIndex = IP.currentSelectedCut, filePath = IP.filePath })
                        totalDescriptionCount = 1
                        generatingDescriptions = true
                        popupItemProperties = IP
                    end
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                if descDescs and descCount > 0 then
                    reaper.ImGui_Separator(ctx)
                    for i, desc in ipairs(descDescs) do
                        if reaper.ImGui_MenuItem(ctx, desc, nil, descIdx == i - 1) then
                            descCut.descriptionIdx = i - 1
                            descCut.name = desc
                            descCut.descriptionCycleComplete = false
                            updateCutDataFile(IP)
                        end
                    end
                end
                reaper.ImGui_EndPopup(ctx)
            end

            -- d           describe this cut
            -- shift+d      describe every cut that has no name yet
            -- shift+alt+d  describe every cut, replacing names that are already there
            -- alt+d        step back through the descriptions already fetched
            --
            -- Stepping back was on shift+d until shift+d was wanted for the whole
            -- timeline. It moved rather than went: it is the only way back through
            -- descriptions already fetched, and those cost a model run each. It takes
            -- alt without shift, so shift+alt+d is free to mean "and overwrite".
            local isDescKey  = (not markerNameIsFocused or isSuperDown) and isD
            local isDescAll  = isDescKey and isShiftDown
            local isDescFwd  = descBtnClicked or (isDescKey and not isShiftDown and not isOptionDown)
            local isDescBack = isDescKey and isOptionDown and not isShiftDown

            -- Describing everything is its own action, not a variation on describing
            -- this one, so it is handled before the per-cut branches and on its own.
            if isDescAll then
                if canDescribe then describeAllCuts(IP, isOptionDown) end
                isDescFwd, isDescBack = false, false
            end

            if (isDescFwd or isDescBack) and IP.filePath and descCut then
                -- A new description has to be fetched when there is nothing stored, only
                -- one stored, or the stored ones have all been cycled through once.
                local wantNew = not descDescs or descCount == 0 or descCount == 1
                                or descCut.descriptionCycleComplete

                -- Fetching needs Ollama; stepping through what is already stored does
                -- not, since those are saved with the cut. So the two are gated apart.
                if wantNew and not canDescribe then
                    -- nothing to offer: cannot fetch, and nothing stored to step through
                elseif isDescFwd then
                    if wantNew then
                        descCut.descriptions = nil
                        descCut.descriptionIdx = nil
                        descCut.descriptionCycleComplete = false
                        updateCutDataFile(IP)
                        undo_redo.save_undo(IP.cut_data)
                        descriptionQueue = {}
                        descriptionLastError = nil
                        table.insert(descriptionQueue, { cutIndex = IP.currentSelectedCut, filePath = IP.filePath })
                        totalDescriptionCount = 1
                        generatingDescriptions = true
                        popupItemProperties = IP
                    else
                        local nextIdx = ((descIdx or (descCount - 1)) + 1) % descCount
                        descCut.descriptionIdx = nextIdx
                        descCut.name = descDescs[nextIdx + 1]
                        if nextIdx == 0 then descCut.descriptionCycleComplete = true end
                        updateCutDataFile(IP)
                    end
                elseif isDescBack and descDescs and descCount > 1 then
                    local prevIdx = ((descIdx or 0) - 1 + descCount) % descCount
                    descCut.descriptionIdx = prevIdx
                    descCut.name = descDescs[prevIdx + 1]
                    descCut.descriptionCycleComplete = false
                    updateCutDataFile(IP)
                end
            end

            local describeTip
            if not canDescribe then
                describeTip = ollamaWhyUnavailable()
                if canCycle then
                    describeTip = describeTip ..
                        "\n\nThe descriptions already fetched can still be stepped through.\n" ..
                        "alt+d steps back through them."
                end
            else
                describeTip = "Describe this cut using Ollama (" ..
                              (settings.ollama_model or "llava") .. ")\n" ..
                              "d: this cut  ·  shift+d: every cut without a name\n" ..
                              "shift+" .. MOD_ALT .. "+d: every cut, replacing names"
                if canCycle then
                    describeTip = describeTip ..
                                  "\nalt+d: back through the ones already fetched\n" ..
                                  "right-click: all descriptions"
                end
            end
            setToolTipFunc(describeTip)
        else
            --if not cursorOutsideArea then
                -- Pulsing, for the same reason Analyse does: with no cut selected this
                -- is what the page is offering, and it is one button among many.
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), pulsatingColor(theme.accent, 3))
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), pulsatingColor(theme.accent, 3))
                local insertClicked = reaper.ImGui_Button(ctx, "Insert marker")
                reaper.ImGui_PopStyleColor(ctx, 2)
                if insertClicked or ((not markerNameIsFocused or isSuperDown) and isI) then
                    local markerIndex = 0
                    for i, c in ipairs(IP.cut_data) do
                        if c.time > IP.cur_pos_in_item + subProj_item_pos then
                            markerIndex = i
                            break
                        end
                    end
                    undo_redo.save_undo(IP.cut_data)
                    table.insert(IP.cut_data, markerIndex, { score = 1, time = IP.cur_pos_in_item + subProj_item_pos })
                    updateCutDataFile(IP)
                    
                    find_cut_data(IP)
                end
    
                setToolTipFunc("Add a cut to the timeline", "i")
            --else
                --last_cur_pos = nil
            --end
        end
    end
    
end

-- OVERVIEW AREA
function overviewArea(IP, IP2)
    if not IP then return end
    if focusNavigation then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        focusNavigation = false
    end
    
    
    local timeLineW = winW - 8 * 2      -- (imageW * (16/9)) * 2 + 8 --
    local overviewArea_w = timeLineW
    local overviewArea_h = 38 * (compareVideos and 2 or 1)
    local itemAreaWidth = overviewArea_w
    
    if IP.itemNumber == 0 and IP.fileName then  
        local posYStart = reaper.ImGui_GetCursorPosY(ctx)
        if reaper.ImGui_Button(ctx, IP.fileName .. "##looparea", overviewArea_w, 4) then
            settings.displayTimeSelection = not settings.displayTimeSelection
            saveSettings()
        end
        overviewArea_x, overviewArea_y = reaper.ImGui_GetItemRectMin(ctx)
        --reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosY(ctx, posYStart + 6)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, overviewArea_x, 4 + overviewArea_y, overviewArea_x + overviewArea_w, 4 + overviewArea_y + overviewArea_h, colorReallyBlack)
    end
    
    
    
    -- set difference in length and start pos
    
    local overview_length_time = IP.overview_length_time 
    local overview_start_time = IP.overview_start_time
    local overview_start_in_item = IP.overview_start_in_item
    local overview_start_in_item_offset = IP.overview_start_in_item_offset
    if not overview_start_time or not overview_length_time then 
        return 
    end
    
    --if compareVideos then
    if settings.selectionType == "Video item" then 
        if compareVideos then 
            if IP and IP2 and IP.item_area_to_analyze_length and IP2.item_area_to_analyze_length then  
                --difference_in_length = IP.item_area_to_analyze_length >= IP2.item_area_to_analyze_length and IP.item_area_to_analyze_length - IP2.item_area_to_analyze_length or IP2.item_area_to_analyze_length - IP.item_area_to_analyze_length
                --difference_in_pos_start = IP.item_pos >= IP2.item_pos and IP.item_pos - IP2.item_pos or IP2.item_pos - IP.item_pos
                --largestFileLength = IP.item_area_to_analyze_length >= IP2.item_area_to_analyze_length and IP.item_area_to_analyze_length or IP2.item_area_to_analyze_length 
                
                local first_start_pos = IP.item_pos < IP2.item_pos and IP.item_pos or IP2.item_pos
                local last_end_pos = IP.item_end > IP2.item_end and IP.item_end or IP2.item_end
                local largestFileLength = last_end_pos - first_start_pos --IP.item_area_to_analyze_length >= IP2.item_area_to_analyze_length and IP.item_area_to_analyze_length or IP2.item_area_to_analyze_length 
                overview_length_time = largestFileLength
                --largestFileLength = largestFileLength + difference_in_pos_start
                itemAreaWidth = timeLineW / (largestFileLength) * IP.item_area_to_analyze_length 
                
                if IP.item_pos ~= IP2.item_pos then 
                    local difference_in_pos_start = IP.item_pos >= IP2.item_pos and IP.item_pos - IP2.item_pos or 0 
                    local posOfSmallerItem = reaper.ImGui_GetCursorPosX(ctx) + (timeLineW / largestFileLength) * difference_in_pos_start 
                    reaper.ImGui_SetCursorPosX(ctx, posOfSmallerItem)
                end
            end 
        end
    else
        
        if IP.overview_start_in_item < 0 then  
            local posOfSmallerItem = reaper.ImGui_GetCursorPosX(ctx) + (timeLineW / overview_length_time) * -IP.overview_start_in_item 
            reaper.ImGui_SetCursorPosX(ctx, posOfSmallerItem) 
        end
        
        itemAreaWidth = timeLineW / (overview_length_time) * (IP.overview_length_in_item + (IP.overview_start_in_item < 0 and IP.overview_start_in_item or 0) ) 
    end
    local item_in_view = true
    if itemAreaWidth <= 0 then 
        item_in_view = false
        itemAreaWidth = 200 
        reaper.ImGui_SetCursorPosX(ctx, 8)
    end
    
    
    if IP and IP.item then 
        reaper.ImGui_InvisibleButton(ctx, IP.fileName .. "##CutsOverview".. (IP.itemNumber and IP.itemNumber or "noitem"), itemAreaWidth, 30)
        
    else
        reaper.ImGui_Button(ctx, "No video selected##".. (IP and IP.itemNumber and IP.itemNumber or "noitem"), itemAreaWidth, 30)
    end
    
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local w, h = reaper.ImGui_GetItemRectSize(ctx)
    
    
    function withinOverviewArea(x)
        return x >= overviewArea_x and x <= overviewArea_w + overviewArea_x
    end
    
    function withinOverviewAreaY(y)
        return y >= overviewArea_y and y <= overviewArea_h + overviewArea_y
    end
    
    function withinOverviewArea_start(x)
        return x >= overviewArea_x
    end
    function withinOverviewArea_end(x)
        return x < overviewArea_w + overviewArea_x
    end
    
    -- LOOP AREA 
    if IP.itemNumber == 0 
        --and start_time_sel ~= end_time_sel and start_time_sel < end_time_sel
        --and (start_time_sel < IP.item_end and end_time_sel > IP.item_pos)
    then
        -- time selection
        if settings.displayTimeSelection and settings.selectionType ~= "Time selection" then 
            blockOutXStart = ((start_time_sel - overview_start_time) / overview_length_time) * overviewArea_w + overviewArea_x
            blockOutXStart2 = withinOverviewArea(blockOutXStart) and blockOutXStart or (withinOverviewArea_start(blockOutXStart) and overviewArea_x + overviewArea_w or overviewArea_x)
            blockOutXEnd = ((end_time_sel - overview_start_time) / overview_length_time) * overviewArea_w + overviewArea_x
            blockOutXEnd2 = withinOverviewArea(blockOutXEnd) and blockOutXEnd or (withinOverviewArea_end(blockOutXEnd) and overviewArea_x or overviewArea_x + overviewArea_w)
            aa = blockOutXStart2
            ab = blockOutXEnd2
            --if blockOutXStart2 ~= blockOutXEnd2 then --withinOverviewArea(blockOutXStart) or withinOverviewArea(blockOutXEnd) then 
                reaper.ImGui_DrawList_AddRectFilled(draw_list, blockOutXStart2, overviewArea_y, blockOutXEnd2, overviewArea_y+4, colorGreen, 0)
            --end
        end
        
        -- play cursor pos
        blockOutXStart = ((cur_pos - overview_start_time + subProj_item_pos) / overview_length_time) * overviewArea_w + overviewArea_x
        
        if withinOverviewArea(blockOutXStart) then 
            reaper.ImGui_DrawList_AddLine(draw_list, blockOutXStart, overviewArea_y+ 6, blockOutXStart, overviewArea_y + overviewArea_h - 4, colorWhite, 1)       --currentSelectedCut and colorMapLight or colorMap, 1)
        end
        
 
        --[[
        -- play cursor pos
        if not settings.cursorFollowSelectedCut 
        -- and IP.cur_pos_in_item >= (IP.overview_start_in_item - subProj_item_pos)
        -- and IP.cur_pos_in_item <= (IP.overview_start_in_item - subProj_item_pos) + IP.overview_length_in_item
        then
            local pos = IP.cur_pos_in_item 
            local timeX = (pos - (IP.overview_start_in_item - subProj_item_pos)) / IP.overview_length_in_item * w + minX
            --if (settings.cursorFollowSelectedCut and not IP.currentSelectedCut) or not settings.cursorFollowSelectedCut then
            reaper.ImGui_DrawList_AddLine(draw_list, timeX, minY - 5 + h / 2, timeX, maxY + 4, colorWhite, 1)       --currentSelectedCut and colorMapLight or colorMap, 1)
            --end
        end
        
        
        if (IP.timeline_cur_pos_in_item >= IP.overview_start_in_item - subProj_item_pos and IP.timeline_cur_pos_in_item <= (IP.overview_start_in_item - subProj_item_pos) + IP.overview_length_in_item) then
        
        --if (settings.cursorFollowSelectedCut and not IP.currentSelectedCut) or not settings.cursorFollowSelectedCut then
            local pos = IP.overview_start_in_item - subProj_item_pos
            local timeX = (IP.timeline_cur_pos_in_item - pos) / IP.overview_length_in_item * w + minX
            reaper.ImGui_DrawList_AddLine(draw_list, timeX, minY - 5, timeX, maxY + 4 - (not settings.cursorFollowSelectedCut and h / 2 or 0), colorWhite, 1)  --currentSelectedCut and colorMapLight or colorMap, 1)
            --end
        else
            cursorOutsideArea = true
        end
        ]]
        
        
        if withinOverviewArea(mouse_pos_x) and withinOverviewAreaY(mouse_pos_y) then
            if (scrollVertical ~= 0 or scrollHorizontal ~= 0) then
                local mousePosRelativeInOverviewArea = math.floor((mouse_pos_x - overviewArea_x) / w * 10 + 0.5) / 10 
                local scrollPrecision = 2
                local left, right
                local useTimeSelectionType = (settings.selectionType == "Time selection" and not isShiftDown) or (settings.selectionType == "Arrange view" and isShiftDown)
                aaa = useTimeSelectionType
                local leftVal = useTimeSelectionType and start_time_sel or start_time_arr
                local rightVal = useTimeSelectionType and end_time_sel or end_time_arr
                if scrollVertical ~= 0 then
                    local scrollIn = scrollVertical > 0
                    left = leftVal - (scrollVertical / scrollPrecision) * (scrollIn and mousePosRelativeInOverviewArea or 1 - mousePosRelativeInOverviewArea)  --(scrollVertical > 0 and 0 or -1))
                    right = rightVal - (scrollVertical / scrollPrecision) * (scrollIn and (mousePosRelativeInOverviewArea - 1) or -mousePosRelativeInOverviewArea)
                elseif scrollHorizontal ~= 0 then
                    left = leftVal - scrollHorizontal / scrollPrecision
                    right = rightVal - scrollHorizontal / scrollPrecision
                end
                if left < 0 then left = 0 end
                
                if useTimeSelectionType then 
                    reaper.GetSet_LoopTimeRange(true, true, left, right, false)
                end
                if not useTimeSelectionType then 
                    reaper.GetSet_ArrangeView2(0, true, 0, 0,left, right)
                elseif settings.arrangeviewFollowsOverview then
                    setArrangeviewArea()
                end
            end
        end
    end
    
    if not item_in_view then  
        reaper.ImGui_DrawList_AddText(draw_list, minX,minY + 4, colorGrey, IP.fileName .. " outisde overview area")
    else
        if compareVideos then 
            reaper.ImGui_DrawList_AddText(draw_list, minX + 6,minY + 6, colorLowGrey, IP.fileName) 
        end
        
        local overviewAreaFocused = (IP and compareVideos) and (overviewAreaFocus == IP.itemNumber and colorWhite or colorLowGrey) or (markerNameIsFocused and colorLowGrey or colorWhite)
        reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, overviewAreaFocused, 0, nil, 1)
    
    
        local margin = 4
        minX = minX + 1
        minY = minY + margin
        maxX = maxX - 1
        maxY = maxY - margin
        w = w - 3
    
        


        local mouseOutsideAnalysedAreaStart = false
        local mouseOutsideAnalysedAreaEnd = false
        cursorOutsideArea = false
        local mouseInsideUnanalysedArea = false

        local blockOutStartX = IP.overview_start_in_item
        local blockOutEndX = IP.overview_start_in_item + IP.overview_length_in_item
        local showBlockOutAtEnd = false
        local hoverUnanalyzedBlock = false

        -- NOT ANALYSED BLOCKS
        if lol then 
            for _, c in ipairs(IP.cut_data) do
                if c.special == "start" and c.time and c.time > blockOutStartX and c.time < blockOutEndX then
                    blockOutXStart = ((blockOutStartX - IP.overview_start_in_item) / IP.overview_length_in_item) * w + minX
                    blockOutXStart = blockOutXStart > minX and blockOutXStart or minX
                    blockOutXEnd = ((c.time - IP.overview_start_in_item) / IP.overview_length_in_item) * w + minX
                    blockOutXEnd = blockOutXEnd < maxX and blockOutXEnd or maxX
                    if mouse_pos_x > blockOutXStart and mouse_pos_x <= blockOutXEnd and mouse_pos_y >= minY and mouse_pos_y <= maxY then
                        mouseInsideUnanalysedArea = true
                        hoverUnanalyzedBlock = true
                    end
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, blockOutXStart, minY, blockOutXEnd, maxY,
                        hoverUnanalyzedBlock and colorDarkGrey or colorDarkGreyTransparent, 0)
    
                    showBlockOutAtEnd = false
                end
                if c.special == "end" and c.time and c.time < IP.overview_start_in_item + IP.overview_length_in_item then  --and c.time < IP.overview_start_in_item + overview_length_in_item then
                    blockOutStartX = c.time
                    showBlockOutAtEnd = true
                    hoverUnanalyzedBlock = false
                end
            end
        end

        if showBlockOutAtEnd then
            blockOutXStart = ((blockOutStartX - IP.overview_start_in_item) / IP.overview_length_in_item) * w + minX
            blockOutXStart = blockOutXStart > minX and blockOutXStart or minX
            if mouse_pos_x > blockOutXStart and mouse_pos_x <= maxX and mouse_pos_y >= minY and mouse_pos_y <= maxY then
                mouseInsideUnanalysedArea = true
                hoverUnanalyzedBlock = true
            end
            reaper.ImGui_DrawList_AddRectFilled(draw_list, blockOutXStart, minY, maxX, maxY, hoverUnanalyzedBlock and colorDarkGrey or colorDarkGreyTransparent, 0)
        end



        local timeX, hoverName, betweenCut, hoverIndex
        if reaper.ImGui_IsItemHovered(ctx) then
            -- blockOutXStart = ((cur_pos - overview_start_time) / overview_length_time) * overviewArea_w + overviewArea_x 
            local mouse_cursor_pos = ((mouse_pos_x - minX) / w * overview_length_time) + overview_start_time
            local mouse_cursor_pos_in_item = ((mouse_pos_x - overviewArea_x) / overviewArea_w * overview_length_time) + overview_start_in_item_offset --overview_start_time--overview_start_in_item_offset
            
            if isShiftDown or #IP.cuts_making_threashold == 0 then
                posX = mouse_cursor_pos_in_item
                betweenCut = true 
            else
                --if settings.cursorFollowSelectedCut then
                local closest = math.huge
                local use_cut
                for i, c in ipairs(IP.cuts_making_threashold) do
                    local dif = math.abs(mouse_cursor_pos_in_item - c.time)
                    if dif < closest then
                        use_cut = c
                        closest = dif
                        hoverName = IP.cut_data[c.index] and IP.cut_data[c.index].name and IP.cut_data[c.index].name or "Cut " .. i
                        hoverIndex = c.index
                    end
                end
                posX = use_cut.time
            end
            
            


            -- cursor
            if not mouseInsideUnanalysedArea then
                --if posX and posX >= overview_start_in_item_offset and posX <= overview_start_in_item_offset + overview_length_time then 
                    timeX = ((posX - overview_start_in_item_offset) / overview_length_time) * overviewArea_w + overviewArea_x
                    if betweenCut then
                        reaper.ImGui_DrawList_AddLine(draw_list, timeX, minY, timeX, maxY, colorWhite, 1)
                    end
                    local timeXInSeconds = posX - IP.item_offset + IP.item_pos - subProj_item_pos
                    setToolTipFunc((hoverName and (hoverName .. " | ") or "") .. reaper.format_timestr_pos(timeXInSeconds, "", 5))
                    --setToolTipFunc(hoverName and hoverName or "Click to select point")
                --end
            else
                setToolTipFunc("Area not analysed")
            end

            if isMouseClick then
                if not IP.last_cur_pos_in_item or posX ~= IP.last_cur_pos_in_item then
                    cur_pos = posX + IP.item_pos - IP.item_offset
                    --cur_pos_in_item = posX
                    --aa = posX
                    --ab = cur_pos
                end
                
                overviewAreaFocus = IP.itemNumber
                setCutSelection(IP, IP2, not isShiftDown and hoverIndex or nil) 

                -- Shift+click on empty timeline clears the selection, and has to say so
                -- loudly enough to survive the rest of this frame. cur_pos_in_item was
                -- worked out before the click and still holds the selected cut's own
                -- time, so the auto-select below would match that cut and put it
                -- straight back -- which is why it took a second click to let go.
                if isShiftDown and not hoverIndex then
                    IP.suppressCutAutoSelect = true
                end

                moveCursorToPos(cur_pos)
                
                if IP2 then
                    --IP2.last_currentSelectedCut = nil
                    --IP2.currentSelectedCut = nil
                end
               -- IP.last_currentSelectedCut = IP.currentSelectedCut 
               -- IP.currentSelectedCut = not isShiftDown and hoverIndex or nil
                
               -- last_currentSelectedCut_array[tostring(IP2.item)] = nil
               -- currentSelectedCut_array[tostring(IP2.item)] = nil
            end

        end

        
        -- draw cuts
        for _, c in ipairs(IP.cuts_making_threashold) do
            local timeX = (((c.time + IP.item_pos - IP.item_offset) - overview_start_time) / overview_length_time) * overviewArea_w + overviewArea_x
            --local col = c.exclude and colorGrey or (IP.cut_data[c.index].color and  IP.cut_data[c.index].color or colorBlue)
            local col = hoverIndex == c.index and colorWhite or (IP.cut_data[c.index] and IP.cut_data[c.index].color and IP.cut_data[c.index].color or colorLowGrey)
            if withinOverviewArea(timeX) then  
                reaper.ImGui_DrawList_AddLine(draw_list, timeX,
                    minY - (c.index == IP.currentSelectedCut and 5 or -2) + (c.exclude and 10 or 0), timeX,
                    maxY + (c.index == IP.currentSelectedCut and 4 or 0), col, c.index == IP.currentSelectedCut and 4 or 1)
            end
        end
    end
end


-- Helper function to draw image centered in a slot
function DrawImageCentered(image, slotW, slotH, label)
    local p = { reaper.ImGui_GetCursorScreenPos(ctx) }

    -- The slot is filled black first, across its whole width, as the Compare tab's
    -- slots are. A 16:9 picture in a slot of another shape leaves bars either side, and
    -- those used to be window background -- so the picture had no edge to it and the
    -- two thumbnails ran into the page. conformSlotBg is the same colour that tab uses.
    reaper.ImGui_DrawList_AddRectFilled(reaper.ImGui_GetWindowDrawList(ctx),
                                        p[1], p[2], p[1] + slotW, p[2] + slotH,
                                        conformSlotBg, 4)

    -- Draw background slot
    reaper.ImGui_InvisibleButton(ctx, label, slotW, slotH)       -- Invisible button as background/placeholder?
    -- actually Button draws a frame. We want a black box?
    -- The button serves as the "Loading" placeholder usually.
    -- But if we have an image, we want the image ON TOP of the slot area.
    -- Using Button establishes the layout space.

    if image and ImGui.ValidatePtr(image, 'ImGui_Image*') then
        local w, h = reaper.ImGui_Image_GetSize(image)
        local aspect = w / h
        local slotAspect = slotW / slotH

        local drawW, drawH
        if aspect > slotAspect then
            -- Image is wider (relative to slot), fit to width
            drawW = slotW
            drawH = drawW / aspect
        else
            -- Image is taller, fit to height
            drawH = slotH
            drawW = drawH * aspect
        end

        -- Center image
        local offX = (slotW - drawW) / 2
        local offY = (slotH - drawH) / 2

        -- We need to draw the image at specific coordinates
        -- Since we already advanced cursor with Button, we use DrawList or SetCursor?
        -- Using DrawList is smoother for overlays.
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_DrawList_AddImage(dl, image, p[1] + offX, p[2] + offY, p[1] + offX + drawW, p[2] + offY + drawH)
    else
        -- If no image (and not loading?), Button already shows label/loading text.
    end
end


function should_thumbnail_update(IP)
    if settings.navigationFollowsPlayhead and isPlaying then
        for i, c in ipairs(IP.cuts_making_threashold) do
            if IP.last_timeline_cur_pos_in_item and c.time - subProj_item_pos > IP.last_timeline_cur_pos_in_item and c.time - subProj_item_pos <= IP.timeline_cur_pos_in_item then
                IP.currentSelectedCut = c.index
                IP.cur_pos_in_item = c.time
                last_cur_pos = IP.cur_pos_in_item - IP.item_pos + IP.item_offset
                cur_pos = IP.cur_pos_in_item + IP.item_pos - IP.item_offset
    
                --lastSelectedCut = IP.currentSelectedCut
                break;
            end
        end
        IP.last_timeline_cur_pos_in_item = IP.timeline_cur_pos_in_item
        --last_timeline_cur_pos_in_item_array[itemString] = IP.timeline_cur_pos_in_item
    end 
    
    local updateThumbnails = false
    if IP.currentSelectedCut then

        if IP.currentSelectedCut ~= IP.last_currentSelectedCut then
            updateThumbnails = true
            IP.last_currentSelectedCut = IP.currentSelectedCut

            -- Derive cur_pos_in_item from the cut's stored time rather than from cur_pos.
            -- Using cur_pos here causes double-subtraction of subProj_item_pos when the
            -- button triggers previewSection in the next frame (where cur_pos is already
            -- adjusted by moveCursorToPos), while the click case works in the same frame
            -- before the cursor adjustment is reflected in cur_pos.
            for _, c in ipairs(IP.cuts_making_threashold) do
                if c.index == IP.currentSelectedCut then
                    IP.cur_pos_in_item = c.time - subProj_item_pos
                    break
                end
            end
        elseif isPlaying and previewShowsLiveVideo() then
            -- Cut unchanged but playing: advance cur_pos_in_item to live position so B updates
            IP.cur_pos_in_item = IP.timeline_cur_pos_in_item
            updateThumbnails = IP.last_cur_pos_in_item ~= IP.cur_pos_in_item
        end
    else

        if isPlaying and previewShowsLiveVideo() then
            IP.cur_pos_in_item = IP.timeline_cur_pos_in_item
            updateThumbnails = IP.last_cur_pos_in_item ~= IP.cur_pos_in_item
        else
            -- Which cut, if any, the cursor is sitting on.
            --
            -- Within half a frame, not exactly. A cut's time comes out of the analysis
            -- and has no reason to land on REAPER's frame grid, while the cursor always
            -- does -- so stepping one frame off a cut and back again put the cursor on
            -- the grid a fraction of a frame away from the cut, and an exact comparison
            -- then found nothing. Shift+left followed by shift+right left the cut
            -- unselected despite ending where it started.
            --
            -- Nearest wins rather than first, so two cuts less than a frame apart
            -- cannot both claim the cursor and the closer one takes it.
            if IP.cuts_making_threashold and not IP.suppressCutAutoSelect then
                local at   = IP.cur_pos_in_item + subProj_item_pos
                local tol  = 0.5 / ((frames_per_second and frames_per_second > 0)
                                    and frames_per_second or 25)
                local best, bestDiff
                for i, c in ipairs(IP.cuts_making_threashold) do
                    local diff = math.abs(c.time - at)
                    if diff <= tol and (not bestDiff or diff < bestDiff) then
                        best, bestDiff = c, diff
                    end
                end
                if best then
                    IP.last_currentSelectedCut = IP.currentSelectedCut
                    IP.currentSelectedCut = best.index
                    updateThumbnails = true
                end
            end
            -- Consumed here: the stale cursor position that made it necessary is only
            -- stale for the frame the click happened in.
            IP.suppressCutAutoSelect = nil

            if not updateThumbnails and IP.last_cur_pos_in_item ~= IP.cur_pos_in_item then
                updateThumbnails = true
            end
        end
    end
    
    --IP.last_cur_pos_in_item = IP.cur_pos_in_item
    
    return updateThumbnails
end


-- Returns true when it has drawn the thumbnails and their captions, so the caller knows
-- there is a row to put the transport on. With no item selected it draws nothing, and
-- the transport then needs a line of its own.
function previewSection(IP)      
    if not IP then return false end
    if not imageA_array then imageA_array = {} end
    if not imageB_array then imageB_array = {} end
    -- PREVIEW SECTION  
    
    -- A frame the extension could not produce yet is answered with a stand-in while it
    -- decodes elsewhere, and it only says so through VP_FramePending. Thumbnails are
    -- otherwise fetched when the playhead moves and not again until it moves once more,
    -- so without this the stand-in stays up until something else happens to prompt a
    -- refresh -- which is what "the image never updates until I leave the cut and come
    -- back" was.
    local updateThumbnails = (not analyseStartTime and IP)
                             and (should_thumbnail_update(IP) or vpFrameIsPending(IP))
    local itemNumber = IP and IP.itemNumber or 0
    local itemString = IP and tostring(IP.item) or 0
    --if not pngPath_array[itemString] then pngPath_array[itemString] = {} end
    
    pngPathA = IP and IP.pngPathA -- pngPath_array[itemString].pngPathA
    pngPathB = IP and IP.pngPathB -- pngPath_array[itemString].pngPathB
    --imageA =

    local filePath = IP and IP.filePath

    -- When the source file changes, flush all stale cached paths and images so the
    -- new file's frames are fetched immediately rather than showing the old stream.
    if filePath and filePath ~= IP.lastVPFilePath then
        pngPathA = nil
        pngPathB = nil
        IP.pngPathA = nil
        IP.pngPathB = nil
        IP.last_cur_pos_in_item = nil
        imageA_array[itemString] = nil
        imageB_array[itemString] = nil
        IP.lastVPFilePath = filePath
        updateThumbnails = true
    end

    if updateThumbnails and filePath then -- and not wait then
        local oneFrameEarlier = IP.last_cur_pos_in_item and compareWithMargin(IP.cur_pos_in_item, IP.last_cur_pos_in_item - (1 / frames_per_second))
        local oneFrameLater = IP.last_cur_pos_in_item and compareWithMargin(IP.cur_pos_in_item, IP.last_cur_pos_in_item + (1 / frames_per_second))
        local cur_pos_rounded_to_frame = roundToFrame(IP.cur_pos_in_item, frames_per_second)
        local cur_pos_rounded_to_frame_one_frame_ealier = cur_pos_rounded_to_frame - (1 / frames_per_second)
        --(IP.overview_start_in_item - subProj_item_pos)
        
        --pngPath = directory .. IP.fileName .. "_Cut" .. c.index .. "_" .. math.floor(c.time * 1000 + 0.5) .. "ms.png" 

        -- only update images if we change the position.
        -- make option to have session follow or not
        --if not IP.currentSelectedCut or IP.currentSelectedCut ~= lastSelectedCut then 
            --if not IP.last_cur_pos_in_item or IP.last_cur_pos_in_item ~= cur_pos_in_item then
            --if not settings.onlyShowThumbnailsForCuts or (settings.onlyShowThumbnailsForCuts and IP.currentSelectedCut) then 
                --if not IP.last_cur_pos_in_item then IP.last_cur_pos_in_item = cur_pos_in_item end
                
                
                if oneFrameLater then 
                    imageA_array[itemString] = file_exists_check(pngPathB) and imageB_array[itemString]
                    --reaper.ShowConsoleMsg("later\n")
                    if not imageA_array[itemString] then oneFrameLater = false end
                end
                if oneFrameEarlier then
                    imageB_array[itemString] = file_exists_check(pngPathA) and imageA_array[itemString]
                    --reaper.ShowConsoleMsg("earlier\n")
                    if not imageB_array[itemString] then oneFrameEarlier = false end
                end
                
                
                -- for stored thumbnails (skip during playback — live video takes priority for B)
                if not isPlaying and IP.currentSelectedCut and IP.thumbnailPath_exist then
                    if IP.cut_data_time_pos and IP.cut_data_time_pos[cur_pos_rounded_to_frame] and reaper.file_exists(IP.cut_data_time_pos[cur_pos_rounded_to_frame]) then 
                        pngPathB = IP.cut_data_time_pos[cur_pos_rounded_to_frame]
                        oneFrameLater = true
                        imageB_array[itemString] = nil
                    end
                    if IP.cut_data_time_pos and IP.cut_data_time_pos[cur_pos_rounded_to_frame_one_frame_ealier] and reaper.file_exists(IP.cut_data_time_pos[cur_pos_rounded_to_frame_one_frame_ealier]) then 
                        pngPathA = IP.cut_data_time_pos[cur_pos_rounded_to_frame_one_frame_ealier]
                        oneFrameEarlier = true
                        imageA_array[itemString] = nil
                    end
                end
                
                

                -- A: when playing with a cut selected, freeze A on the cut's own frame.
                -- When scrubbing (not playing), show the frame before the cursor as usual.
                if not oneFrameLater then
                    local tA
                    if isPlaying and previewShowsLiveVideo() and IP.currentSelectedCut and IP.cut_data and IP.cut_data[IP.currentSelectedCut] then
                        -- Frozen anchor: the frame at the cut point itself
                        tA = roundToFrame(IP.cut_data[IP.currentSelectedCut].time - subProj_item_pos, frames_per_second) + subProj_item_pos
                    elseif not isPlaying or not previewShowsLiveVideo() then
                        tA = cur_pos_rounded_to_frame_one_frame_ealier + subProj_item_pos
                    end
                    if tA then
                        local vpH = vpGetHandleCut(filePath)
                        if vpH then
                            local p = reaper.VP_GetFrame(vpH, tA, vpPreviewWH())
                            if p and p ~= "" and pngPathA ~= p then
                                pngPathA = p
                                imageA_array[itemString] = nil
                            end
                        else
                            pngPathA = join_paths(script_path, "tempA" .. itemNumber .. ".png")
                            os.remove(pngPathA)
                            createThumbnails(filePath, pngPathA, tA, true)
                            imageA_array[itemString] = nil
                        end
                    end
                end

                if not oneFrameEarlier then
                    -- B: during playback always use live timeline position, not cur_pos_in_item
                    local tB
                    if isPlaying and previewShowsLiveVideo() and IP.timeline_cur_pos_in_item then
                        tB = roundToFrame(IP.timeline_cur_pos_in_item, frames_per_second) + subProj_item_pos
                    else
                        tB = cur_pos_rounded_to_frame + subProj_item_pos
                    end
                    local vpH = vpGetHandle(filePath)
                    if vpH then
                        local p = reaper.VP_GetFrame(vpH, tB, vpPreviewWH())
                        if p and p ~= "" and pngPathB ~= p then
                            pngPathB = p
                            imageB_array[itemString] = nil
                        end
                    else
                        pngPathB = join_paths(script_path, "tempB" .. itemNumber .. ".png")
                        os.remove(pngPathB)
                        createThumbnails(filePath, pngPathB, tB, true)
                        imageB_array[itemString] = nil
                    end
                end
                
            --end
        --end
    else
        if not wait then wait = 0 end
        wait = wait + 1
        -- set higher in case of "premature end of file"
        if wait > 8 then
            wait = nil
        end

        --reaper.ShowConsoleMsg("WAIT\n")
    end
    
    if IP then 
        IP.last_cur_pos_in_item = IP.cur_pos_in_item
        IP.pngPathA = pngPathA
        IP.pngPathB = pngPathB
    end
    
    --last_cur_pos_in_item_array[itemString] = IP.cur_pos_in_item
    
    --pngPath_array[itemString].pngPathA = pngPathA
    --pngPath_array[itemString].pngPathB = pngPathB
    --pngPath_array[itemString] = {pngPathA = pngPathA, pngPathB = pngPathB}
    --end

    -- generate images
    -- Ensure images are valid, otherwise reset to nil so they can be re-created
    if imageA_array[itemString] and not reaper.ImGui_ValidatePtr(imageA_array[itemString], 'ImGui_Image*') then imageA_array[itemString] = nil end
    if imageB_array[itemString] and not reaper.ImGui_ValidatePtr(imageB_array[itemString], 'ImGui_Image*') then imageB_array[itemString] = nil end

    if not imageA_array[itemString] and pngPathA and reaper.file_exists(pngPathA) then
        imageA_array[itemString] = reaper.ImGui_CreateImage(pngPathA, reaper.ImGui_ImageFlags_NoErrors())
        --imageA = imageFromCache(pngPathA)
    end
    if imageA_array[itemString] and not imageB_array[itemString] and pngPathB and reaper.file_exists(pngPathB) then
        imageB_array[itemString] = reaper.ImGui_CreateImage(pngPathB, reaper.ImGui_ImageFlags_NoErrors())
        --imageB = imageFromCache(pngPathB)
    end

    -- Calculate Slot Dimensions (Half Width, 16:9)
    -- Make sure we match the logic used for imageW variable (which is Height)
    local slotW = (winW - 8 * 3) / 2
    local slotH = slotW * (9 / 16)
    -- Note: original imageW variable was Height. Let's use our new vars.

    local imageText = (isPlaying or (IP and IP.outsideBoundries) or settings.onlyShowCutsWithEditedName) and " " or "Loading image"
    
    imageAText = imageText
    imageBText = imageText
    imageATip = "Image before cut selection"
    imageBTip = "Image before cut selection"
    
    local isFirstImage = (IP and IP.cur_pos_in_item == 0)
    local isLastImage = IP and compareWithMargin(IP.cur_pos_in_item, item_length) -- to ensure we find it if there's some jitter on the pos
    
    if isFirstImage then 
        imageA_array[itemString] = nil
        imageAText = ""
        imageATip = ""
    end
    if isLastImage then
        imageB_array[itemString] = nil
        imageBText = ""
        imageBTip = ""
    end
    
    
    if analyseStartTime then 
        --imageA_array[itemString] = nil
        --imageB_array[itemString] = nil 
    end
    
    local slotsX = reaper.ImGui_GetCursorPosX(ctx)
    local slotsScreenX, slotsScreenY = reaper.ImGui_GetCursorScreenPos(ctx)

    DrawImageCentered(imageA_array[itemString], slotW, slotH, imageAText .. "##1_" .. itemNumber)
    setToolTipFunc(imageATip)

    reaper.ImGui_SameLine(ctx)
    local imageBText = (isLastImage and not isPlaying) and "" or imageText
    DrawImageCentered(imageB_array[itemString], slotW, slotH, imageBText .. "##2_" .. itemNumber)

    if not isLastImage then
        setToolTipFunc(isPlaying and "Live video" or "Image on cut selection")
    end

    -- Which frame each side is showing, under each picture. Without it the pair is two
    -- near-identical images and nothing says that the left one is the frame before the
    -- cut and the right one the cut itself -- which is the whole point of showing two.
    -- Italic grey, as a caption rather than part of the page.
    -- Over the finished pictures, before the captions below them.
    drawTransientMessage(slotsScreenX, slotsScreenY,
                         slotW * 2 + thumbnailGap(), slotH)

    local liveNow = isPlaying and previewShowsLiveVideo()
    local rightX  = slotsX + slotW + thumbnailGap()

    thumbnailCaption(slotsX, slotW, "before cut")
    reaper.ImGui_SameLine(ctx)
    -- "on playhead" while the right-hand picture is following playback, because that is
    -- what it is showing then -- it is only the cut's own frame when it is not.
    thumbnailCaption(rightX, slotW, liveNow and "on playhead" or "on cut")

    -- The toggle sits at the right edge of the picture it governs.
    reaper.ImGui_SameLine(ctx)
    local label = "Video"
    local tw    = reaper.ImGui_CalcTextSize(ctx, label)
    local inner = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemInnerSpacing()) or 4
    local boxW  = reaper.ImGui_GetFrameHeight(ctx) + inner + tw
    reaper.ImGui_SetCursorPosX(ctx, rightX + slotW - boxW)
    local movedLive, live = reaper.ImGui_Checkbox(ctx, label .. "##previewlive",
                                                  previewShowsLiveVideo())
    if movedLive then
        settings.previewLiveVideo = live
        saveSettings()
    end
    setToolTipFunc("On: the right-hand picture follows the playhead while playing.\n" ..
                   "Off: it stays on the selected cut, so the cut can be compared\n" ..
                   "with whatever is playing past it.")
    return true
end

-- The gap ImGui puts between the two slots, so a caption can be placed under the second
-- one without assuming a number.
function thumbnailGap()
    -- GetStyleVar hands back a Vec2 as two values, x first. Taking the second one got
    -- the vertical spacing, which is a different number entirely.
    local sx = reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing())
    return sx or 8
end

-- One caption, centred under a slot that starts at x and is slotW wide.
function thumbnailCaption(x, slotW, text)
    local tw = reaper.ImGui_CalcTextSize(ctx, text)
    reaper.ImGui_SetCursorPosX(ctx, x + (slotW - tw) / 2)
    -- The transport buttons share this row, and text is shorter than a button: without
    -- this the captions sit at the top of the row and the buttons hang below them.
    reaper.ImGui_AlignTextToFramePadding(ctx)
    if fontItalic then reaper.ImGui_PushFont(ctx, fontItalic, reaper.ImGui_GetFontSize(ctx)) end
    reaper.ImGui_TextColored(ctx, colorGrey, text)
    if fontItalic then reaper.ImGui_PopFont(ctx) end
end

-- NOT USED
function textOverlay()
    local imageMinX, imageMinY = reaper.ImGui_GetItemRectMin(ctx)
    local imageWidth, imageHeight = reaper.ImGui_GetItemRectSize(ctx)
    if settings.cursorFollowSelectedCut and playState ~= 0 then
        local textOverlayText = "No live preview of video"
        local textW, textH = reaper.ImGui_CalcTextSize(ctx, textOverlayText, 0, 0)
        local midX = imageMinX + imageWidth / 2
        local midY = imageMinY + imageHeight / 2
        reaper.ImGui_DrawList_AddRectFilled(draw_list, midX - textW / 2 - 4, midY - textH / 2 - 4,
            midX + textW / 2 + 4, midY + textH / 2 + 4, colorBlack)
        reaper.ImGui_DrawList_AddText(draw_list, midX - textW / 2, midY - textH / 2, colorWhite, textOverlayText)
    end
end
--textOverlay()


function addButtons(IP)
    --if #IP.cuts_making_threashold > 0 then
    --reaper.ImGui_AlignTextToFramePadding(ctx)
    --reaper.ImGui_TextColored(ctx, colorGrey, "Add:")
    --reaper.ImGui_SameLine(ctx)
    
    function insertMediaItem(track, pos, length, name, col, image_path)
        local newItem = reaper.AddMediaItemToTrack(track)
        
        -- Position and length
        reaper.SetMediaItemInfo_Value(newItem, "D_POSITION", pos)
        reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH", length)
        reaper.SetMediaItemInfo_Value(newItem, "I_CUSTOMCOLOR", (col >> 8) |16777216)
        
        local newTake = reaper.AddTakeToMediaItem(newItem) 
        reaper.GetSetMediaItemTakeInfo_String( newTake, "P_NAME", name, true )
        
        -- Assign source to item
        if image_path then 
            -- Create video source from image
            local source = reaper.PCM_Source_CreateFromFile(image_path)
            if not source then
              reaper.ShowMessageBox("Failed to load image.", "Error", 0)
              return
            end
            reaper.SetMediaItemTake_Source(newTake, source)
        end 
    end
    
    
    function findSelectedCutMakingThreshold()
        for i, c in ipairs(IP.cuts_making_threashold) do
            if c.index == IP.currentSelectedCut then
                return i, c
            end
        end
    end

    local function cutInView(c)
        return c.time >= IP.item_area_to_analyze_start and
               c.time <= IP.item_area_to_analyze_start + IP.item_area_to_analyze_length
    end
    
    function getNameColorAndPos(IP, index, c)
        if not index then
            index, c = findSelectedCutMakingThreshold()
        end
        time = c and c.time
        if index then 
            local name = IP.cut_data[c.index].name and IP.cut_data[c.index].name or "Cut " .. index
            local col = IP.cut_data[c.index].color and IP.cut_data[c.index].color or colorBlue
            local pos = time + IP.item_pos - IP.item_offset
            local endPos = (index < #IP.cuts_making_threashold and IP.cuts_making_threashold[index + 1].time or findNextSpecialEnd(IP)) + IP.item_pos - IP.item_offset
            if is_a_subproject then
                pos = pos - subProj_item_pos
                endPos = endPos - subProj_item_pos
            end
            return name, col, pos, endPos, c
        end
    end
    
    
    
    
    if reaper.ImGui_Button(ctx, "Markers") or 
      (isOptionDown and is1) or 
      (isSuperDown and isEnter and 
      ((not is_a_subproject and settings.useTypeForSingleInsert == "Markers") or
      (is_a_subproject and settings.useTypeForSingleInsertSubproject == "Markers"))) then
        reaper.Undo_BeginBlock()
        if isSuperDown then
            local name, col, pos, endPos = getNameColorAndPos(IP)
            if pos then 
                reaper.AddProjectMarker2(0, false, pos, 0, name, -1, (col >> 8) | 16777216)
            end
        else 
            for i, c in ipairs(IP.cuts_making_threashold) do
                if not c.exclude and cutInView(c) then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    reaper.AddProjectMarker2(0, false, pos, 0, name, -1, (col >> 8) | 16777216)
                end
            end
        end
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert markers from video cut detection", -1)
    end 
    setToolTipFunc("Insert markers with name and color for each cut.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to insert the selected cut only", MOD_ALT .. "+1")
    
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Regions") or 
      (isOptionDown and is2) or 
      (isSuperDown and isEnter and 
      ((not is_a_subproject and settings.useTypeForSingleInsert == "Regions") or
      (is_a_subproject and settings.useTypeForSingleInsertSubproject == "Regions"))) then
        reaper.Undo_BeginBlock()
        if isSuperDown then
            local name, col, pos, endPos = getNameColorAndPos(IP)
            if pos then 
                reaper.AddProjectMarker2(0, true, pos, endPos, name, -1, (col >> 8) |16777216)
            end
        else 
            for i, c in ipairs(IP.cuts_making_threashold) do
                if not c.exclude and cutInView(c) then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    reaper.AddProjectMarker2(0, true, pos, endPos, name, -1, (col >> 8) |16777216)
                end
            end
        end

        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert regions from video cut detection", -1)
    end
    setToolTipFunc("Insert Regions with name and color for each cut.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to insert the selected cut only", MOD_ALT .. "+2")
    
    reaper.ImGui_SameLine(ctx)
    
    if is_a_subproject then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Take markers") or 
      (isOptionDown and is3 and not is_a_subproject) or 
      (isSuperDown and isEnter and not is_a_subproject and settings.useTypeForSingleInsert == "Take markers") then
        reaper.Undo_BeginBlock()
        if isSuperDown then
            local name, col, pos, endPos, c = getNameColorAndPos(IP)
            if pos then 
                reaper.SetTakeMarker(reaper.GetActiveTake(IP.item), -1, name, c.time, (col >> 8) |16777216)
            end
        else 
            for i, c in ipairs(IP.cuts_making_threashold) do
                if not c.exclude and cutInView(c) then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    reaper.SetTakeMarker(reaper.GetActiveTake(IP.item), -1, name, c.time, (col >> 8) |16777216)
                end
            end
        end
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert take markers from video cut detection", -1)
    end 
    setToolTipFunc("Insert take markers with name and color for each cut.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to insert the selected cut only", MOD_ALT .. "+3")
    
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Thumbnails") 
    or (isOptionDown and is4 and not is_a_subproject) 
    or (isSuperDown and isEnter and not is_a_subproject and settings.useTypeForSingleInsert == "Thumbnails")
    or waitingForThumbnailsToBeCreated then
        
        if not waitingForThumbnailsToBeCreated then 
            generateThumbnailsForCuts(IP, true)
        end
        
        if generationQueue and #generationQueue > 0 then 
            waitingForThumbnailsToBeCreated = true
        else
            local track = reaper.GetMediaItemTrack(IP.item)
            reaper.Undo_BeginBlock()
            
            local track = reaper.GetMediaItemTrack(IP.item)
            if settings.insertItemsOnDedicatedTrack then
                track = GetOrCreateTrackBelow(track, IP.fileName .. "_Cuts")
            end
            if isSuperDown then
                local name, col, pos, endPos, c = getNameColorAndPos(IP)
                if pos then 
                    local len = endPos - pos 
                    local pngPath = IP.cut_data[c.index].pngPath 
                    insertMediaItem(track, pos, len, name, col, pngPath)
                end
            else 
                for i, c in ipairs(IP.cuts_making_threashold) do
                    if not c.exclude and cutInView(c) then
                        local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                        local len = endPos - pos
                        local pngPath = IP.cut_data[c.index].pngPath

                        insertMediaItem(track, pos, len, name, col, pngPath)
                    end
                end
            end
            waitingForThumbnailsToBeCreated = nil
            reaper.UpdateArrange()
        end
        
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert thumbnails from video cut detection", -1)
    end
    setToolTipFunc("Insert thumbnails with name and color for each cut.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to insert the selected cut only", MOD_ALT .. "+4")
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Empty items") 
    or (isOptionDown and is5 and not is_a_subproject) 
    or (isSuperDown and isEnter and not is_a_subproject and settings.useTypeForSingleInsert == "Empty items")
    then 
        
        reaper.Undo_BeginBlock() 
        local track = reaper.GetMediaItemTrack(IP.item)
        if settings.insertItemsOnDedicatedTrack then
            track = GetOrCreateTrackBelow(track, IP.fileName .. "_Cuts")
        end
        if isSuperDown then
            local name, col, pos, endPos, c = getNameColorAndPos(IP)
            if pos then 
                local len = endPos - pos 
                insertMediaItem(track, pos, len, name, col)
            end
        else 
            for i, c in ipairs(IP.cuts_making_threashold) do
                if not c.exclude and cutInView(c) then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    local len = endPos - pos
                    insertMediaItem(track, pos, len, name, col)
                end
            end
        end
        reaper.UpdateArrange()

        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert thumbnails from video cut detection", -1)
    end
    setToolTipFunc("Insert thumbnails with name and color for each cut.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to insert the selected cut only", MOD_ALT .. "+5")
    
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Split video item") 
    or (isOptionDown and is6 and not is_a_subproject) 
    or (isSuperDown and isEnter and not is_a_subproject and settings.useTypeForSingleInsert == "Split video item") then 
        reaper.Undo_BeginBlock()
        
        if isSuperDown then 
            index, c = findSelectedCutMakingThreshold()
            if index then 
                local new_item = reaper.SplitMediaItem(IP.item, c.time + IP.item_pos - IP.item_offset)
                if new_item then 
                    reaper.Main_OnCommand(40289, 0) --Item: Unselect (clear selection of) all items 
                    reaper.SetMediaItemSelected(new_item, true) 
                end
            end
        else 
            -- Sort cuts descending to split from right to left
            local cuts_to_split = {}
            for i, c in ipairs(IP.cuts_making_threashold) do
                if not c.exclude and cutInView(c) then
                    table.insert(cuts_to_split, {cut=c, original_index=i})
                end
            end
            table.sort(cuts_to_split, function(a,b) return a.cut.time > b.cut.time end)

            for _, entry in ipairs(cuts_to_split) do
                local c = entry.cut
                local idx = entry.original_index
                local new_item = reaper.SplitMediaItem(IP.item, c.time + IP.item_pos - IP.item_offset)
                if new_item then
                    local name = IP.cut_data[c.index].name and IP.cut_data[c.index].name or "Cut " .. idx
                    local take = reaper.GetActiveTake(new_item)
                    if take then
                        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
                    end

                    local col = IP.cut_data[c.index].color and IP.cut_data[c.index].color or 0
                    if col ~= 0 then
                        reaper.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", (col >> 8) | 16777216)
                    end
                end
            end
        end
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Split video items from video cut detection", -1)
        reaper.UpdateArrange()
    end
    setToolTipFunc("Split video at each cut and name each part with name and color.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to split on the selected cut only", MOD_ALT .. "+6")
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Split selected items") 
    or (isOptionDown and is7) 
    or (isSuperDown and isEnter and not is_a_subproject and settings.useTypeForSingleInsert == "Split video item") then 
        local selectedItemsAmount = reaper.CountSelectedMediaItems(0)
        if selectedItemsAmount > 0 then 
            reaper.Undo_BeginBlock() 
            
            local selectedItems = {}
            for i = 0, selectedItemsAmount - 1 do
                table.insert(selectedItems, reaper.GetSelectedMediaItem(0, i))
            end
            
            reaper.Main_OnCommand(40289, 0) --Item: Unselect (clear selection of) all items 
            for _, item in ipairs(selectedItems) do 
                if isSuperDown then 
                    index, c = findSelectedCutMakingThreshold()
                    if index then 
                        local new_item = reaper.SplitMediaItem(item, c.time + IP.item_pos - IP.item_offset)
                        if new_item then  
                            reaper.SetMediaItemSelected(new_item, true) 
                        end
                    end
                else
                    -- Sort cuts descending to split from right to left
                    local cuts_to_split = {}
                    for i, c in ipairs(IP.cuts_making_threashold) do
                        if not c.exclude and cutInView(c) then
                            table.insert(cuts_to_split, {cut=c, original_index=i})
                        end
                    end
                    table.sort(cuts_to_split, function(a,b) return a.cut.time > b.cut.time end)
                    
                    for i, entry in ipairs(cuts_to_split) do 
                        local c = entry.cut
                        local idx = entry.original_index
                        local new_item = reaper.SplitMediaItem(item, c.time + IP.item_pos - IP.item_offset)
                        if new_item then
                            if settings.setNameOnSplitItems then 
                                local name = IP.cut_data[c.index].name and IP.cut_data[c.index].name or "Cut " .. idx
                                local take = reaper.GetActiveTake(new_item)
                                if take then
                                    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
                                end
                            end
                            
                            if settings.setColorOnSplitItems then 
                                local col = IP.cut_data[c.index].color and IP.cut_data[c.index].color or 0
                                if col ~= 0 then
                                    reaper.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", (col >> 8) | 16777216)
                                end
                            end
                            
                            if i == 1 then 
                                reaper.SetMediaItemSelected(new_item, true) 
                            end
                        end 
                    end
                end 
            end
            undo_redo.save_undo({reaperAction = true})
            reaper.Undo_EndBlock("Split items from video cut detection", -1)
            reaper.UpdateArrange()
        end
    end
    setToolTipFunc("Split video at each cut and name each part with name and color.\n - Hold down " .. MOD_CMD .. " or press " .. MOD_CMD .. "+enter to split on the selected cut only", MOD_ALT .. "+7")
    
    
    
    
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_InvisibleButton(ctx, "dummy", 20, 20)

    if is_a_subproject then reaper.ImGui_EndDisabled(ctx) end
end


-- KEY NAVIGATION
function setCutSelection(IP, IP2, value) 
    if value then   
        IP.last_currentSelectedCut = IP.currentSelectedCut
    end 
    IP.currentSelectedCut = value
    
    if IP2 and settings.navigationFollowsPlayhead then
        IP2.currentSelectedCut = nil
        IP2.last_currentSelectedCut = nil
        --IP2.ignoreCutOnNextDefer = true
    end
end

function findPreviousCut(IP, IP2) 
    local newIndex
    for i = #IP.cuts_making_threashold, 1, -1 do
        local c = IP.cuts_making_threashold[i]
        if IP.currentSelectedCut then  
            if c.index == IP.currentSelectedCut then
                newIndex = IP.cuts_making_threashold[i - 1]
                break
            end
        else
            if c.time + 0.1 / frames_per_second < IP.cur_pos_in_item then
                newIndex = c
                break 
            end
        end
    end
    if newIndex then 
        cur_pos = newIndex.time + IP.item_pos - IP.item_offset
        setCutSelection(IP, IP2, newIndex.index)
        moveCursorToPos(cur_pos)
        return true
    end
end

function findNextCut(IP, IP2, doNotUpdateSelectedCutIndex)
    local newIndex
    for i, c in ipairs(IP.cuts_making_threashold) do 
        if IP.currentSelectedCut then 
            if c.index == IP.currentSelectedCut then
                newIndex = IP.cuts_making_threashold[i + 1]
                break
            end
        else
            if c.time - (0.1 / frames_per_second) > (IP.cur_pos_in_item + subProj_item_pos) then
                newIndex = c
                break 
            end
        end
        
    end
    
    if newIndex then 
        cur_pos = newIndex.time + IP.item_pos - IP.item_offset
        if not doNotUpdateSelectedCutIndex then 
            if not IP.last_cur_pos_in_item or posX ~= IP.last_cur_pos_in_item then
            --    cur_pos = posX + IP.item_pos - IP.item_offset
                --cur_pos_in_item = posX
                --aa = posX
                --ab = cur_pos
            end
            
            setCutSelection(IP, IP2, newIndex.index)
        end
        moveCursorToPos(cur_pos)
        return true
    end
end

function findNextSpecialEnd(IP, IP2)
    --[[for _, c in ipairs(IP.cut_data) do
        if c.special == "end" and (not IP.cur_pos_in_item or (IP.cur_pos_in_item < c.time)) then
            if c.time < IP.overview_start_in_item + IP.overview_length_in_item then
                return c.time
            else
                return IP.overview_start_in_item + IP.overview_length_in_item
            end
        end
    end
    return IP.overview_start_in_item + IP.overview_length_in_item
    ]]
    --return IP.item_area_to_analyze_start + IP.item_area_to_analyze_Length
    return IP.overview_start_in_item + IP.overview_length_in_item
end


function navigationButtons(IP, IP2)
    
    
    
    if reaper.ImGui_Button(ctx, "<", buttonSize, buttonSize) or (not markerNameIsFocused and isLeftArrowReleased and isShiftDown) then
        move_cursor_by_frames(isSuperDown and -frames_per_second or -1)
        IP.currentSelectedCut = nil 
        IP.last_currentSelectedCut = nil 
        --currentSelectedCut_array = {}
        --last_currentSelectedCut_array = {}
    end
    setToolTipFunc("Move 1 frame left (hold super for 1 second)","shift+left")
    
        
    reaper.ImGui_SameLine(ctx)
        
    if reaper.ImGui_Button(ctx, "l<", buttonSize, buttonSize) or (not markerNameIsFocused and isLeftArrowReleased and not isShiftDown) then
        if not findPreviousCut(IP, IP2) then
            cur_pos = IP.item_pos
            moveCursorToPos(cur_pos)
            setCutSelection(IP, IP2) 
        end
    end
    setToolTipFunc("Select previous cut","left arrow")
    
    
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "##play", buttonSize, buttonSize) or (not markerNameIsFocused and isSpace) then
        playStopReaper()
    end
    setToolTipFunc("Play/Stop project curser", "space")
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    local sizeW, sizeH = reaper.ImGui_GetItemRectSize(ctx)
    reaper.ImGui_DrawList_AddRectFilled(draw_list,posX, posY, posX + sizeW, posY + sizeH, isPlaying and colorIsPlaying or theme.button, 6) 
    reaper.ImGui_DrawList_AddCircleFilled(draw_list,posX + sizeW / 2- 1, posY + sizeH/2, sizeW/3, isPlaying and colorWhite or colorTransparent, 3) 
    reaper.ImGui_DrawList_AddCircle(draw_list,posX + sizeW / 2 - 1, posY + sizeH/2, sizeW/3, colorWhite, 3,1) 
    
    
    reaper.ImGui_SameLine(ctx) 
    if reaper.ImGui_Button(ctx, ">l", buttonSize, buttonSize) or (not markerNameIsFocused and isRightArrowReleased and not isShiftDown) then
        if not findNextCut(IP, IP2) then
            cur_pos = findNextSpecialEnd(IP, IP2) + IP.item_pos - IP.item_offset
            
            moveCursorToPos(cur_pos)
            setCutSelection(IP, IP2) 
        end
    end
    setToolTipFunc("Select next cut", "right arrow")
    
    
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, ">", buttonSize, buttonSize) or (not markerNameIsFocused and isRightArrowReleased and isShiftDown) then
        move_cursor_by_frames(isSuperDown and frames_per_second or 1)
        setCutSelection(IP, IP2) 
    end
    setToolTipFunc("Move 1 frame right (hold super for 1 second)", "shift+right arrow") 
    
end 

function undoRedoButtons(IP)
    local hasUndo = undo_stack and #undo_stack > 0
    if not hasUndo then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Undo") or (hasUndo and isSuperDown and not isShiftDown and isZ) then
        local addStep = undo_stack[#undo_stack].reaperAction and {reaperAction = true} or IP.cut_data
        undoData = undo_redo.undo(addStep)
        if undoData.reaperAction then
            reaper.Main_OnCommand(40029, 0) --Edit: Undo
        else
            IP.cut_data = undoData
            --update_cut_data = true
            updateCutDataFile(IP)
            find_cut_data(IP)
        end 
    end 
    setToolTipFunc("Undo last change to a cut", MOD_CMD .. "+z") 
    if not hasUndo then reaper.ImGui_EndDisabled(ctx) end

    reaper.ImGui_SameLine(ctx)
    local hasRedo = redo_stack and #redo_stack > 0
    if not hasRedo then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Redo") or (hasRedo and isShiftDown and isSuperDown and isZ) then
        
        local addStep = redo_stack[#redo_stack].reaperAction and {reaperAction = true} or IP.cut_data
        local undoData = undo_redo.redo(addStep)
        if undoData.reaperAction then
            reaper.Main_OnCommand(40030, 0) --Edit: Redo
        else
            IP.cut_data = undoData
            
            --update_cut_data = true
            updateCutDataFile(IP)
            find_cut_data(IP)
        end 
    end
    setToolTipFunc("Redo last undone change to a cut", MOD_CMD .. "+shift+z") 
    if not hasRedo then reaper.ImGui_EndDisabled(ctx) end
end

-- Grey explanatory text inside a settings column. The columns sit posX2 apart and
-- nothing stops a sentence running on into the next one, so wrap it at this column's
-- own right edge. Measured from the cursor rather than fixed, so it works in whichever
-- column it is called from -- and it replaces hand-splitting strings into short lines,
-- which only ever held for one font size and went stale the moment the wording changed.
-- Size of the extension's decoded-frame cache, polled rather than read per frame: each
-- read lists the cache folder, which holds thousands of files.
local vpCacheBytes, vpCacheFiles, vpCacheStatsAt = 0, 0, 0

function vpCacheStats(forceNow)
    if forceNow then vpCacheStatsAt = 0 end
    local now = reaper.time_precise()
    if (now - vpCacheStatsAt) > 3 and reaper.VP_CacheStats then
        local b, f = (reaper.VP_CacheStats() or ""):match("^(%d+) (%d+)$")
        vpCacheBytes = tonumber(b) or 0
        vpCacheFiles = tonumber(f) or 0
        vpCacheStatsAt = now
    end
    return vpCacheBytes, vpCacheFiles
end

function formatBytes(b)
    if b >= 1073741824 then return string.format("%.2f GB", b / 1073741824) end
    if b >= 1048576    then return string.format("%.1f MB", b / 1048576) end
    if b >= 1024       then return string.format("%.0f KB", b / 1024) end
    return string.format("%d bytes", b)
end

function settingsInfoText(txt, color)
    reaper.ImGui_PushTextWrapPos(ctx, reaper.ImGui_GetCursorPosX(ctx) + (posX2 or 220) - 16)
    reaper.ImGui_TextColored(ctx, color or 0xFFFFFF66, txt)
    reaper.ImGui_PopTextWrapPos(ctx)
end

function settingButtons(IP)
    
    --[[
    ret, settings.onlyShowThumbnailsForCuts = reaper.ImGui_Checkbox(ctx, "Only show thumbnails for cuts", settings.onlyShowThumbnailsForCuts)
    if ret then 
        saveSettings()
    end
    setToolTipFunc("Only show thumbnails for cuts is useful if you don't want thumbnail creation when the playhead is not on a cut")
    ]]
    -- What is actually running, script and extension, spanning the whole page above the
    -- columns: the two are separate ReaPack packages and update independently, so "have
    -- you got the latest" is otherwise a question nobody can answer from inside the app.
    -- Full width, so none of it has to be wrapped into a 220 px column.
    reaper.ImGui_TextColored(ctx, 0xFFFFFF66, "Script " .. scriptVersion)
    reaper.ImGui_SameLine(ctx)
    if reaper.VP_Version then
        reaper.ImGui_TextColored(ctx, 0xFFFFFF66, " -  Extension " .. reaper.VP_Version())
        setToolTipFunc("The two are separate ReaPack packages: \"Video Cut Detection Editor\"\n" ..
                       "and \"Video Cut Detection Editor extension\". Update both.")
    elseif vp_available then
        reaper.ImGui_TextColored(ctx, 0xFFAA44FF, " -  Extension too old to report its version")
        setToolTipFunc("Update the \"Video Cut Detection Editor extension\" package in ReaPack,\n" ..
                       "then restart REAPER.")
    else
        reaper.ImGui_TextColored(ctx, 0xFFAA44FF, " -  Extension not installed")
        setToolTipFunc("Install the \"Video Cut Detection Editor extension\" package in ReaPack for\n" ..
                       "cut detection without FFmpeg, and for the Compare Videos tab.\n" ..
                       "Restart REAPER afterwards.")
    end
    reaper.ImGui_Separator(ctx)

    reaper.ImGui_BeginGroup(ctx)
     
    -- Which detector runs comes first, and everything that applies to only one of them
    -- sits below it, shown only when that one is chosen. The FFmpeg path buttons and
    -- "Extreme cut detection" used to sit up here, above the choice, which offered
    -- FFmpeg's settings to someone who had picked the extension and was never going to
    -- run FFmpeg at all.
    if reaper.VP_Cuts then
        reaper.ImGui_TextColored(ctx, colorGrey, "Cut detection method")
        for _, m in ipairs({
            { "extension", "Extension",
              "Detects from the fingerprints the VP extension stores beside the video.\n" ..
              "The first run has to build that store, for much the same wall time as\n" ..
              "FFmpeg but a fraction of the CPU, since it decodes on the machine's\n" ..
              "video engine rather than across every core. After the store exists,\n" ..
              "re-detecting at a different sensitivity takes under a millisecond\n" ..
              "instead of another full pass. More controls, and better on fast motion,\n" ..
              "where it can tell a cut from a whip pan. Files already analysed in the\n" ..
              "Compare Videos tab have the store already. The default, and it needs\n" ..
              "nothing installed." },
            { "ffmpeg",    "FFmpeg",
              "The scdet filter in a subprocess. Decodes the whole file on every run,\n" ..
              "across all cores: about 17 s for the same file, so faster the first time\n" ..
              "but just as slow every time after. Needs FFmpeg on disk." },
        }) do
            if reaper.ImGui_RadioButton(ctx, m[2] .. "##cutmethod",
                                        (settings.cut_method or "extension") == m[1]) then
                -- Choosing FFmpeg is the point at which a path for it is worth asking
                -- for, rather than at startup. Without one there is nothing to switch
                -- to, so the choice does not take and the current detector stands.
                if m[1] == "ffmpeg" and not ensureFfmpegPath() then
                    reaper.MB("No FFmpeg was located, so the FFmpeg detector cannot be used.\n\n" ..
                              "The extension detector needs nothing installed and stays selected.",
                              "FFmpeg not found", 0)
                elseif (settings.cut_method or "extension") ~= m[1] then
                    cutMethodChangePending = m[1]
                else
                    settings.cut_method = m[1]
                    saveSettings()
                end
            end
            setToolTipFunc(m[3])
            reaper.ImGui_SameLine(ctx)
        end
        reaper.ImGui_NewLine(ctx)

        -- Switching detector makes every stored cut list stale: the two find different
        -- cuts, so leaving the old ones on screen would attribute one detector's
        -- results to the other. Confirmed rather than done silently, because the cuts
        -- being discarded may have been named and coloured by hand.
        -- The confirmation itself is a modal, drawn with the other modals rather than
        -- here: a modal has to keep being drawn to stay dismissable, and this tab stops
        -- drawing the moment you switch away from it, which would leave the dialog
        -- blocking input with nothing on screen to answer it.
        reaper.ImGui_NewLine(ctx)
    else
        -- No choice to offer, so say why rather than silently showing FFmpeg's settings
        -- and nothing else. This used to tell Windows users the extension was macOS
        -- only and always would be, which the Windows build has made untrue.
        reaper.ImGui_TextColored(ctx, colorGrey, "Cut detection method")
        settingsInfoText("FFmpeg. Install the Video Cut Detection Editor extension for the faster detector.")
        setToolTipFunc("The \"Video Cut Detection Editor extension\" package, in this same\n" ..
                       "repository, detects cuts without FFmpeg and is what the Compare\n" ..
                       "Videos tab runs on. There are macOS and Windows builds.\n" ..
                       "Restart REAPER after installing.")
        reaper.ImGui_NewLine(ctx)
    end

    -- The settings for whichever detector is in use. cutMethodIsExtension is the same
    -- answer the detection itself acts on, rather than reading settings.cut_method
    -- directly, so a chosen extension that is not actually loaded shows FFmpeg's
    -- settings -- which is what will run.
    local usingExtension = cutMethodIsExtension()

    -- Still reachable on Windows with the extension selected, but no longer because the
    -- extension depends on it: Media Foundation handles the common formats in-process.
    -- ffmpeg is the fallback for what Windows has no decoder for -- ProRes and DNxHD --
    -- which is worth being able to set without changing detector first.
    if not usingExtension or is_windows then
        reaper.ImGui_TextColored(ctx, colorGrey, "FFmpeg")
        if usingExtension and is_windows then
            settingsInfoText("Optional. The extension decodes H.264/HEVC itself; " ..
                             "ffmpeg covers ProRes and DNxHD, which Windows has no " ..
                             "decoder for.")
        end

        if reaper.ImGui_Button(ctx, "Open FFMPEG Path") then
            -- Asks for one where there is none, rather than only reporting its absence:
            -- this is the button someone presses when they want to sort FFmpeg out.
            if ensureFfmpegPath() then
                reaper.CF_ShellExecute(GetDirectoryFromPath(ffmpeg_path))
            end
        end
        setToolTipFunc(ffmpeg_path and ("Open the folder holding FFmpeg.\n" .. ffmpeg_path)
                       or "FFmpeg has not been located")

        if reaper.ImGui_Button(ctx, "Reset FFMPEG Path") then
            ffmpeg.ResetPath()
            reaper.MB("FFMPEG path has been reset. Please restart the script to select a new path.", "Reset Path", 0)
        end
        setToolTipFunc("Click to reset FFMPEG path if you selected the wrong one or moved the file.")

        -- FFmpeg-only, now that only FFmpeg's progress bar reads the figure: FFmpeg
        -- reports no progress of its own, so the bar is guessed from how long the last
        -- runs took. The extension reports real progress and never consults it.
        local speedUnset = not settings.analyseSpeed
        if speedUnset then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Reset analyze speed") then
            settings.analyseSpeed = nil
            saveSettings()
        end
        setToolTipFunc("Click to reset the analyze speed, the estimate FFmpeg's progress bar is\n" ..
                       "drawn from. " ..
                       (settings.analyseSpeed
                        and ("The current speed is: " .. string.format("%.4f", settings.analyseSpeed)
                             .. " s per second of footage.")
                        or "No speed measured. Analyze to set this"))
        if speedUnset then reaper.ImGui_EndDisabled(ctx) end

        -- Still FFmpeg-detector only: it sets the scdet threshold, which the extension
        -- does not use. Shown nested inside the FFmpeg section rather than beside the
        -- path, which is needed more widely.
        local showExtreme = not usingExtension
        if showExtreme then
        ret, settings.extremeCutDetection = reaper.ImGui_Checkbox(ctx, "Extreme cut detection", settings.extremeCutDetection)
        if ret then
            saveSettings()
        end
        setToolTipFunc("This will make a lot more cuts detected, and maybe not be useful, as a lot of falls cut might apear." ..
        "\nYou can hold down super while pressing keypad minus or plus for more gradual sensitivity." ..
        "\nEnabling this requires to re-analyse a video for more cuts to show up" ..
        "\n\nFFmpeg only: the extension has its own Motion, Jump and Gap sliders on the Cut Detection page.")
        end
    end

    -- The preview belongs to the extension, so its settings sit with it. Also shown
    -- when there is no choice of detector at all -- an extension old enough to have
    -- previews but no VP_Cuts -- since the previews still come from it either way.
    if vp_available and (usingExtension or not reaper.VP_Cuts) then
        reaper.ImGui_TextColored(ctx, colorGrey, "Preview resolution")
        local vpSizeLabels = {"640x360", "960x540", "1280x720"}
        for i, label in ipairs(vpSizeLabels) do
            if reaper.ImGui_RadioButton(ctx, label .. "##vpsize", settings.vp_preview_size == i) then
                settings.vp_preview_size = i
                saveSettings()
            end
        end
        setToolTipFunc("Resolution of the live video preview panels (tA / tB). Higher = sharper but uses more GPU memory.")
    end

    -- When the pictures are blank there is nothing on screen to say why: a wrong ffmpeg
    -- path, an unwritable temporary folder and a decode that runs but produces nothing
    -- all look the same from the outside. This asks the extension and prints what it
    -- found, so the answer can be read or pasted to someone who can act on it.
    reaper.ImGui_NewLine(ctx)
    if reaper.VP_Diag then
        if reaper.ImGui_Button(ctx, "Frame diagnostics") then
            local path = IP and IP.filePath or ""
            reaper.ShowConsoleMsg("")
            reaper.ShowConsoleMsg("--- Video Preview diagnostics ---\n")
            reaper.ShowConsoleMsg(reaper.VP_Diag(path) or "(no report)")
            -- The fingerprint store too, when there is one. Cut positions come out of
            -- the frame timestamps, so a timing complaint is answered by what the store
            -- recorded -- the measured frame rate and the gaps between frames -- and by
            -- nothing visible on screen. This prints it in a form that can be compared
            -- against the same file analysed on another machine.
            if reaper.VP_StoreInfo and path ~= "" then
                local store = path .. ".vpfs"
                if reaper.file_exists(store) then
                    reaper.ShowConsoleMsg("\n--- Framestore ---\n")
                    reaper.ShowConsoleMsg(reaper.VP_StoreInfo(store) or "(no report)")
                else
                    reaper.ShowConsoleMsg("\nNo framestore yet -- run Analyse to build one.\n")
                end
            end
            if path == "" then
                reaper.ShowConsoleMsg("\nSelect a video item first to test decoding a frame from it.\n")
            end
        end
        setToolTipFunc("Checks everything the preview pictures depend on -- where ffmpeg is,\n" ..
                       "whether the frame cache folder can be written, and whether a frame\n" ..
                       "actually decodes out of the selected item -- and prints the result\n" ..
                       "to the console, along with the fingerprint store's frame rate and\n" ..
                       "timing if the file has been analysed.")
    end

    -- Last in the column, because it undoes everything above it: a button that throws
    -- away every choice on this page does not belong at the top of it, where it sat
    -- next to the detector it has nothing to do with. It resets the script's settings,
    -- not FFmpeg's path -- there is a separate button for that.
    reaper.ImGui_NewLine(ctx)
    if reaper.ImGui_Button(ctx, "Reset all settings") then
        settings = deep_copy(defaultSettings)
        settings.tabSelection = 3
        saveSettings()
    end
    setToolTipFunc("Put every setting in this script back to its default -- the detector and\n" ..
                   "its thresholds, the preview resolution, the action settings, all of it.\n" ..
                   "The FFmpeg path is kept; there is a separate button for that.")

    reaper.ImGui_EndGroup(ctx)
    
    
    
    
    reaper.ImGui_SameLine(ctx, posX2)
    
    local typesForInsert = {"Markers", "Regions", "Take markers", "Thumbnails", "Empty items", "Split video item", "Split selected items"}
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "Use type for single actions")
    for _, t in ipairs(typesForInsert) do
        if reaper.ImGui_RadioButton(ctx, t .. "##SingleInsert",settings.useTypeForSingleInsert == t) then
            settings.useTypeForSingleInsert = t
            saveSettings()
        end
    end

    -- Preview frames and thumbnails are decoded to JPEGs in the system temporary
    -- folder and kept, because decoding them again is the expensive part. The cache
    -- keeps itself inside a budget, so this is not housekeeping anyone has to do --
    -- it is here to be able to see what it costs and take it back on demand.
    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "Cached preview images")
    if reaper.VP_CacheStats then
        if reaper.VP_SetCacheBudget then
            reaper.ImGui_SetNextItemWidth(ctx, 130)
            local movedBudget, mb = reaper.ImGui_SliderInt(
                ctx, "Max##cachebudget", settings.cacheBudgetMB or 256, 32, 4096, "%d MB")
            if movedBudget then
                settings.cacheBudgetMB = mb
                saveSettings()
                vpApplyCacheBudget()     -- lowering it evicts immediately
                vpCacheStats(true)       -- so the figure below follows at once
            end
            setToolTipFunc("How much disk the cached frames may use.\n" ..
                           "Bigger keeps more of a comparison warm, so scrubbing back\n" ..
                           "over ground already covered stays instant. Smaller costs\n" ..
                           "decode time when it evicts something still being looked at.\n" ..
                           "The prefetcher reads ahead about four seconds per video, so\n" ..
                           "below roughly 64 MB at a high preview resolution it can\n" ..
                           "start evicting its own frames before playback reaches them.")
        end
        local bytes, files = vpCacheStats()
        settingsInfoText(formatBytes(bytes) .. " in " ..
                         files .. (files == 1 and " file" or " files"))
        if reaper.ImGui_Button(ctx, "Clear cached images") then
            if reaper.VP_CacheClear then reaper.VP_CacheClear() end
            vpCacheStats(true)         -- so the figure updates on this very frame
        end
        setToolTipFunc("Deletes the decoded frames from the temporary folder.\n" ..
                       "Nothing is lost: they are rebuilt from the video as they\n" ..
                       "are needed again, which only costs the decode time.")

        local retCache
        retCache, settings.clearCacheOnExit =
            reaper.ImGui_Checkbox(ctx, "Clear when closing app", settings.clearCacheOnExit)
        if retCache then saveSettings() end
        setToolTipFunc("Empties the cache every time this script closes.\n" ..
                       "Leave it off to keep previews instant between sessions;\n" ..
                       "turn it on if the temporary folder needs to stay small.")
    else
        settingsInfoText("Needs the Video Cut Detection Editor extension.")
    end
    reaper.ImGui_EndGroup(ctx)
    
    reaper.ImGui_SameLine(ctx, posX3)
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "Use type for single insert in subprojects")
    for i, t in ipairs(typesForInsert) do
        if i == 1 or i == 2 or i == 7 then 
            if reaper.ImGui_RadioButton(ctx, t .. "##SingleInsertSubproject",settings.useTypeForSingleInsertSubproject == t) then
                settings.useTypeForSingleInsertSubproject = t
                saveSettings()
            end
        end
    end
    
    reaper.ImGui_NewLine(ctx) 
    reaper.ImGui_TextColored(ctx, colorGrey, "Action settings")
    ret, settings.insertItemsOnDedicatedTrack = reaper.ImGui_Checkbox(ctx, "Insert Thumbnails/Empty items on dedicated track", settings.insertItemsOnDedicatedTrack)
    if ret then 
        saveSettings()
    end
    setToolTipFunc("This will create a dedicated track below the track containing the video, using the video name, and insert thumbnails and empty items on here instead")
    
    
    ret, settings.setNameOnSplitItems = reaper.ImGui_Checkbox(ctx, "Set cut name when splitting items", settings.setNameOnSplitItems)
    if ret then 
        saveSettings()
    end
    setToolTipFunc("This will name the new items with cut name")
    
    ret, settings.setColorOnSplitItems = reaper.ImGui_Checkbox(ctx, "Set cut color when splitting items", settings.setColorOnSplitItems)
    if ret then
        saveSettings()
    end
    setToolTipFunc("This will color the new items with cut color")

    reaper.ImGui_NewLine(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "Cut description (Ollama):")

    do
        -- Model dropdown
        local ollamaModels = {
            { name = "llava",              label = "llava:7b — 7B  · good balance" },
            { name = "llava-phi3",         label = "llava-phi3 — 3.8B  · fast, good quality" },
            { name = "llava:13b",          label = "llava:13b — 13B  · high quality, slow" },
            { name = "minicpm-v",          label = "minicpm-v — 8B  · detailed descriptions" },
        }
        local currentModel = settings.ollama_model or "llava"
        local comboLabel = currentModel  -- fallback: show raw name if not in list
        for _, m in ipairs(ollamaModels) do
            if m.name == currentModel then comboLabel = m.label; break end
        end
        local installedMark = ollamaModelInstalled(currentModel) and "  ✓" or ""
        reaper.ImGui_SetNextItemWidth(ctx, 310)
        local comboOpened = reaper.ImGui_BeginCombo(ctx, "##ollamamodelcombo", comboLabel .. installedMark)
        if comboOpened then
            -- Refresh installed list when dropdown opens (quick, no UI block)
            if ollamaStatus ~= "not_installed" and ollamaStatus ~= "not_running" then
                checkOllamaStatus()
            end
            local modelToRemove = nil
            for _, m in ipairs(ollamaModels) do
                local selected  = (currentModel == m.name)
                local installed = ollamaModelInstalled(m.name)
                if installed then
                    if reaper.ImGui_SmallButton(ctx, "✕##rm_" .. m.name) then
                        modelToRemove = m.name
                    end
                    setToolTipFunc("Remove " .. m.name .. " from this computer")
                    reaper.ImGui_SameLine(ctx)
                else
                    if reaper.ImGui_SmallButton(ctx, "↓##pull_" .. m.name) then
                        settings.ollama_model = m.name
                        ollamaStatus = "unknown"
                        saveSettings()
                        reaper.ImGui_CloseCurrentPopup(ctx)
                        startOllamaPull()
                    end
                    setToolTipFunc("Download (pull) " .. m.name .. " — opens a terminal window")
                    reaper.ImGui_SameLine(ctx)
                end
                local rowLabel = m.label .. (installed and "  ✓" or "")
                if reaper.ImGui_Selectable(ctx, rowLabel .. "##sel_" .. m.name, selected) then
                    settings.ollama_model = m.name
                    saveSettings()
                    checkOllamaStatus()
                end
                if selected then reaper.ImGui_SetItemDefaultFocus(ctx) end
            end
            if modelToRemove then
                local host = settings.ollama_host or "localhost:11434"
                -- The body goes in a file rather than inline: single quotes are not
                -- quoting to cmd.exe, so curl was handed them literally and the JSON
                -- was rejected, which made Remove do nothing at all on Windows.
                local tmpDel = script_path .. "Helpers" .. seperator .. "tmp_del_req.json"
                local df = io.open(tmpDel, "w")
                if df then
                    df:write('{"model":"' .. modelToRemove .. '"}')
                    df:close()
                    shellRead('curl -s -X DELETE -H "Content-Type: application/json" -d @"' ..
                              tmpDel .. '" http://' .. host .. '/api/delete', 10000)
                    os.remove(tmpDel)
                end
                ollamaInstalledModels[modelToRemove] = nil
                if settings.ollama_model == modelToRemove then ollamaStatus = "model_missing" end
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_Separator(ctx)
            -- Custom entry
            reaper.ImGui_SetNextItemWidth(ctx, 200)
            if not ollamaModelCustomInput then ollamaModelCustomInput = "" end
            local customChanged, customVal = reaper.ImGui_InputText(ctx, "Custom##ollamamodelcustom", ollamaModelCustomInput)
            if customChanged then ollamaModelCustomInput = customVal end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_SmallButton(ctx, "Use") and ollamaModelCustomInput ~= "" then
                settings.ollama_model = ollamaModelCustomInput
                ollamaStatus = "unknown"
                saveSettings()
                ollamaModelCustomInput = ""
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndCombo(ctx)
        end
        setToolTipFunc("Select an Ollama vision model.\nLarger models give better descriptions but are slower and take more disk space.\n✕ removes the model from your computer, ↓ downloads it.")

        -- Status row
        local statusColor = colorGrey
        local statusText  = "Not checked"
        if ollamaStatus == "not_installed" then statusColor = 0xFF6666FF; statusText = "Ollama not installed"
        elseif ollamaStatus == "not_running"  then statusColor = 0xFFAA44FF; statusText = "Ollama not running"
        elseif ollamaStatus == "model_missing" then statusColor = 0xFFCC44FF; statusText = "Model not pulled"
        elseif ollamaStatus == "ready"         then statusColor = 0x66EE66FF; statusText = "Ready"
        end
        reaper.ImGui_TextColored(ctx, statusColor, "Status: " .. statusText)
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_SmallButton(ctx, "Check") then
            checkOllamaStatus(2)
            ollamaProbed = true
        end
        setToolTipFunc("Check whether Ollama is installed, running, and the model is pulled")

        -- Guided action buttons
        if ollamaStatus == "not_installed" then
            if reaper.ImGui_Button(ctx, "Download Ollama") then
                reaper.CF_ShellExecute("https://ollama.com/download")
            end
            setToolTipFunc("Opens ollama.com/download in your browser. After installing, click Check.")

        elseif ollamaStatus == "not_running" then
            if reaper.ImGui_Button(ctx, "Start Ollama") then
                -- Checked again here rather than trusted from the last probe. Starting
                -- something that is not installed is not a harmless no-op: Windows puts
                -- up its own "cannot find ollama", which says nothing about what to do
                -- about it. The download page does.
                if not ollamaBinaryFound() then
                    ollamaStatus = "not_installed"
                    if reaper.CF_ShellExecute then
                        reaper.CF_ShellExecute("https://ollama.com/download")
                    end
                elseif is_windows then
                    -- Through ExecProcess so no console appears; "start" is a cmd
                    -- builtin, hence the explicit shell, and -1 does not wait on a
                    -- server that is meant to keep running.
                    reaper.ExecProcess('cmd.exe /C start /B ollama serve', -1)
                else
                    -- Try the .app first; fall back to CLI serve in background
                    local appExists = reaper.file_exists("/Applications/Ollama.app")
                    if appExists then
                        os.execute('open -a "/Applications/Ollama.app"')
                    else
                        os.execute('nohup ollama serve >/dev/null 2>&1 &')
                    end
                end
            end
            setToolTipFunc("Starts the Ollama background service. Then click Check.\n" ..
                           "If it turns out not to be installed after all, this opens\n" ..
                           "the download page instead.")

        elseif ollamaStatus == "model_missing" then
            local model = settings.ollama_model or "llava"
            if reaper.ImGui_Button(ctx, 'Pull "' .. model .. '"') then
                startOllamaPull()
            end
            setToolTipFunc('Opens a terminal to download the model (~1-8 GB).\nWhen the download finishes, click Check.')
        end
    end -- ollama

    reaper.ImGui_EndGroup(ctx)



end

function store_itemProperties_that_exist_to_next_defer(IP)
    if IP then 
        --a1 = IP.last_currentSelectedCut
        --IP.currentSelectedCut = IP.currentSelectedCut 
        IP.last_currentSelectedCut = IP.currentSelectedCut 
    end 
end

function swapOverviewAreaFocus() 
    overviewAreaFocus = overviewAreaFocus == 0 and 1 or 0
end

function focusOverviewAreaKeycommands()
    if isUpArrow then
        overviewAreaFocus = 0
    end
    if isDownArrow then
        overviewAreaFocus = 1
    end
    if isTab then
        swapOverviewAreaFocus()
    end
    if isSuperPressed or isSuperReleased then
        swapOverviewAreaFocus()
    end
end

-- POPUPS


local compareMatchPalette = {
    0x61AFEFFF, 0x98C379FF, 0x56B6C2FF, 0xC678DDFF, 0xE5C07BFF, 0xD55FDEFF, 0xBE5046FF
}


function popupUpWindows(IP)

    -- Analysis runs on its own threads in the extension, so this only polls progress
    -- and picks up the result; it returns immediately when nothing is running.
    processConform()

    -- Process one thumbnail per frame
    if genratingThumbNails then
        processGenerationQueue()
        
        reaper.ImGui_OpenPopup(ctx, "Generating Thumbnails")
        -- Modal Notification
        local processed = totalGenerationCount - #generationQueue
        local progress = totalGenerationCount > 0 and (processed / totalGenerationCount) or 0
        
        
        -- Always center this window when appearing
        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        
        if reaper.ImGui_BeginPopupModal(ctx, 'Generating Thumbnails', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, string.format("Generating: %d / %d", processed, totalGenerationCount))
            reaper.ImGui_ProgressBar(ctx, progress, 300, 0, string.format("%d%%", math.floor(progress * 100)))
            
            if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or isEscape then 
                generationQueue = {}
                reaper.ImGui_CloseCurrentPopup(ctx) 
            end
            setToolTipFunc("Click or press escape on keyboard to stop generating thumbnails")
            reaper.ImGui_EndPopup(ctx)
        end
    end
    
    -- Process one analysing each defer
    if analysing then 
         
         --find_cut_data(IP)
         reaper.ImGui_OpenPopup(ctx, "Analysing Video")
         analysingAmount = analysingAmount and analysingAmount or 0
         -- The extension reports real progress, which find_cut_data has already put in
         -- analysingAmount. Only FFmpeg has to be guessed at from elapsed time.
         if not cutMethodIsExtension()
            and analyseEndTime and analyseStartTime and analyseEndTime > analyseStartTime then
             -- 0.025 is a magic number. We could possibly get real analyze progress by saving progress from FFMPEG
             local analyseSpeed = settings.analyseSpeed and settings.analyseSpeed or 0.1
             analysingAmount = (analyseEndTime - analyseStartTime) / IP.item_area_to_analyze_length / analyseSpeed
             if analysingAmount > 1 then analysingAmount = 1 end
         end
         
        -- Always center this window when appearing
        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        
        if reaper.ImGui_BeginPopupModal(ctx, "Analysing Video", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            
            
            -- Only meaningful for the guessed bar. The extension's progress is read
            -- from the job itself and is right the first time.
            if not settings.analyseSpeed and not cutMethodIsExtension() then 
                reaper.ImGui_Text(ctx, "This is the first time analyzing!\nAnalyze speed is not precise and probably too slow")
            end
            
            local analystingText = (math.floor(analysingAmount * 100) .. "%")
            reaper.ImGui_ProgressBar(ctx, analysingAmount, 300, 0, string.format("%d%%", math.floor(analysingAmount * 100)))
            
            if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or isEscape then  
                os.remove(IP.cutTextFilePathRaw)
                analyseStartTime = nil
                analyseEndTime = nil
                analysing = false
                IP.cut_data = nil
            end
            setToolTipFunc("Click or press escape on keyboard to stop analysing")
            reaper.ImGui_EndPopup(ctx)
        end
    end

    -- Confirming a change of cut detector. A modal, because it is a question that has
    -- to be answered before anything else makes sense: the cuts on screen belong to the
    -- detector being switched away from.
    --
    -- Drawn here with the other modals rather than in the Settings tab that raises it,
    -- so switching tab cannot leave it blocking input with nothing on screen to answer.
    if cutMethodChangePending then
        reaper.ImGui_OpenPopup(ctx, "Switch cut detector")

        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)

        if reaper.ImGui_BeginPopupModal(ctx, "Switch cut detector", nil,
                                        reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            local to = (cutMethodChangePending == "extension") and "Extension" or "FFmpeg"
            reaper.ImGui_Text(ctx, "Switch to " .. to .. "?")
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextColored(ctx, 0xE5C07BFF,
                "This clears the cuts already found for every item, including any")
            reaper.ImGui_TextColored(ctx, 0xE5C07BFF,
                "names and colours you have given them. They have to be analysed again.")
            reaper.ImGui_Spacing(ctx)

            -- Keys as well as buttons, and the keys are checked before the buttons are
            -- drawn so a press takes effect on the frame it happens.
            local confirm = isEnter and not markerNameIsFocused
            local cancel  = isEscape

            if reaper.ImGui_Button(ctx, "Switch and clear##cutmethodok", 160, 0) or confirm then
                settings.cut_method = cutMethodChangePending
                saveSettings()
                clearStoredCutsForMethodChange()
                cutMethodChangePending = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            setToolTipFunc("Click or press enter", "enter")

            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Keep as is##cutmethodno", 160, 0) or cancel then
                -- Cleared as well as closed: the popup is re-opened every frame while
                -- this is set, so leaving it would bring the dialog straight back.
                cutMethodChangePending = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            setToolTipFunc("Click or press escape to keep the current detector", "escape")

            reaper.ImGui_EndPopup(ctx)
        end
    end

    -- Process AI description queue (one per frame, each blocks briefly for API call)
    if generatingDescriptions or descriptionLastError then
        if generatingDescriptions then
            if not IP then
                descriptionQueue = {}
                generatingDescriptions = false
            else
                processDescriptionQueue(IP)
            end
        end

        reaper.ImGui_OpenPopup(ctx, "Describing Cuts")
        local processed = totalDescriptionCount - #descriptionQueue
        local progress = totalDescriptionCount > 0 and (processed / totalDescriptionCount) or 0

        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)

        if reaper.ImGui_BeginPopupModal(ctx, 'Describing Cuts', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            if descriptionLastError then
                reaper.ImGui_TextColored(ctx, 0xFF4444FF, "Error:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_Text(ctx, descriptionLastError)
                reaper.ImGui_Spacing(ctx)
                if reaper.ImGui_Button(ctx, 'OK', 120, 0) or isEscape then
                    descriptionLastError = nil
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
            else
                reaper.ImGui_Text(ctx, string.format("Describing: %d / %d", processed, totalDescriptionCount))
                reaper.ImGui_Text(ctx, "REAPER may pause briefly between cuts while calling the API.")
                reaper.ImGui_ProgressBar(ctx, progress, 300, 0, string.format("%d%%", math.floor(progress * 100)))

                if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or isEscape then
                    descriptionQueue = {}
                    generatingDescriptions = false
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
                setToolTipFunc("Click or press escape on keyboard to stop describing cuts")
            end
            reaper.ImGui_EndPopup(ctx)
        end
    end

end


function playStopReaper()
    local saxmandPlay = reaper.NamedCommandLookup("_RS63a69d4a35c6351d50b130cb5f9285c582ea5089")
    if saxmandPlay ~= 0 then 
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS63a69d4a35c6351d50b130cb5f9285c582ea5089"), 0) --Script: Saxmand, Transport Play:Stop (Return cursor to start point).lua
    else
        reaper.Main_OnCommand(40328, 0) --Transport: Play/stop (move edit cursor on stop)
    end
end



local showVideo = false
--local thumbnailPath
--local fps = reaper.TimeMap_curFrameRate(0)  -- returns frames per second

frames_per_second = reaper.TimeMap_curFrameRate(0)
local wait = nil
local run = 0
default_threshold = 1
local minSizeW = 220 * 4 + 8 + 80

compareVideos = settings.tabSelection == 2


local function exit()
    -- Let go of the toolbar: the button is lit while the window is open, so it has to
    -- go out when the script does -- including when REAPER closes it for us rather than
    -- the window being closed by hand.
    setActionToggle(0)

    -- a preview left running would keep playing after the script is gone
    conformStopPreview()
    -- and an analysis job left behind holds a thread open inside the extension
    conformReleaseWaveJobs()
    -- session item previews would keep playing after the script is gone
    conformStopItemPreviews()

    -- Off by default: the frames are what make previews instant next time, and the
    -- cache bounds itself anyway. On, for anyone who would rather the temporary folder
    -- did not hold a few hundred megabytes between sessions.
    if settings.clearCacheOnExit and reaper.VP_CacheClear then
        reaper.VP_CacheClear()
    end

    local i = 0
    
    while true do
        local file = reaper.EnumerateFiles(script_path, i)
        if not file then break end

        -- case-insensitive match
        local lower = file:lower()

        if lower:match("%.png$") and (lower:find("tempa", 1, true) or lower:find("tempb", 1, true)) then 
            os.remove(script_path .. seperator .. file)
        end

        i = i + 1
    end 
end

    
--if not currentSelectedCut_array then currentSelectedCut_array = {} end
--if not last_currentSelectedCut_array then last_currentSelectedCut_array = {} end
--if not last_timeline_cur_pos_in_item_array then last_timeline_cur_pos_in_item_array = {} end
--if not last_cur_pos_in_item_array then last_cur_pos_in_item_array = {} end
--if not pngPath_array then pngPath_array = {} end

local function loop()
    if lastPosY and (winH and lastPosY ~= winH or winW < minSizeW) then
        if winW < minSizeW then
            winW = minSizeW
        end
        reaper.ImGui_SetNextWindowSize(ctx, winW, lastPosY)
    end


    time_precise = reaper.time_precise()

    -- APPLY MODERN THEME STYLES
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 8)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 4)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 5) -- Comfy padding
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 6)
    
    

    -- Theme Colors
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, theme.bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, theme.border)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, theme.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, theme.button_hover)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, theme.button_active)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, theme.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, theme.button_hover)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, theme.button_active)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, theme.text)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, theme.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, theme.accent_hover)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, theme.accent_active)
    
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Tab(), theme.tab)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), theme.tab_hover)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), theme.tab_active)
    
    pushStyleColorAmount = 15
    
    
    reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_KeyRepeatDelay(), 0.5)

    -- Keyboard navigation off, and set every frame rather than once at startup.
    --
    -- With it on, Tab and the arrow keys move focus between widgets and space activates
    -- whichever holds it, so the keys this app binds -- stepping a frame, playing,
    -- nudging a cut -- are swallowed by whatever button happens to be focused. Dear
    -- ImGui enables it by default and REAPER has its own preference that can put it
    -- back, which is why this is not a one-off: one call a frame costs nothing and
    -- nothing downstream can quietly undo it.
    --
    -- Typing is unaffected. NavEnableKeyboard is navigation only, so an input field
    -- still takes text; ConfigFlags_NoKeyboard is the one that would break that, which
    -- is why it is not the flag used here. An earlier attempt at this sat commented out
    -- below for good reason: it passed the flag itself as the config variable, so it
    -- was writing 0 into whatever variable happens to share that number.
    local cfgFlags = ImGui.GetConfigVar(ctx, ImGui.ConfigVar_Flags)
    if (cfgFlags & ImGui.ConfigFlags_NavEnableKeyboard) ~= 0 then
        ImGui.SetConfigVar(ctx, ImGui.ConfigVar_Flags,
                           cfgFlags & ~ImGui.ConfigFlags_NavEnableKeyboard)
    end
    
    buttonSize = 25

    local colCount = 1

    -- ImGui.PushFont(ctx, font2)
    local visible, open = ImGui.Begin(ctx, 'Video Cut Detection Editor', true)


    if visible then
        winW, winH = ImGui.GetWindowSize(ctx)
        -- Ensure frames_per_second is defined
        frames_per_second = frames_per_second or reaper.TimeMap_curFrameRate(0)
        if not frames_per_second or frames_per_second == 0 then frames_per_second = 25 end
 
        --reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_MacOSXBehaviors(), 1) 

        local imageW = ((winW - 8 * 3) / 2) / (16 / 9) -- settings.windowSize --

        -- ImGui.PushFont(ctx, font)
        isMouseDown = ImGui.IsMouseDown(ctx, 0)
        isMouseClick = ImGui.IsMouseClicked(ctx, 0)

        isShiftDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
        -- The physical Ctrl key on every platform. It used to be Mod_Super throughout,
        -- which is Ctrl on macOS but the WINDOWS key elsewhere -- so the tab shortcuts
        -- became Win+1/2/3 on Windows, which the OS takes for itself and the script
        -- therefore never saw. On Windows the physical Ctrl is Mod_Ctrl; only macOS
        -- swaps them.
        isCtrlDown = ImGui.IsKeyDown(ctx, is_windows and ImGui.Mod_Ctrl or ImGui.Mod_Super)
        -- Opt on macOS, Alt elsewhere.
        isOptionDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)
        -- The primary shortcut modifier: Cmd on macOS, Ctrl elsewhere. Already right on
        -- both, since Mod_Ctrl is defined by that role rather than by the key cap.
        isSuperDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
        isSuperPressed = reaper.ImGui_IsKeyPressed(ctx, ImGui.Mod_Ctrl, false)
        isSuperReleased = reaper.ImGui_IsKeyReleased(ctx, ImGui.Mod_Ctrl)
        
        isLeftArrowReleased = reaper.ImGui_IsKeyPressed(ctx, ImGui.Key_LeftArrow, true)
        isRightArrowReleased = reaper.ImGui_IsKeyPressed(ctx, ImGui.Key_RightArrow, true)
        
        local alphabet = {"Space", "Backspace", "Escape", "Enter", "Tab", "Delete",
            "LeftArrow", "RightArrow", "UpArrow", "DownArrow", 
            "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "Y", "Z", "X", 
            "KeypadAdd", "KeypadSubtract", 
            "1", "2","3","4","5","6","7","8","9","0"}
            
        local repeatKeys = {
            ["KeypadAdd"] = true, 
            ["KeypadSubtract"] = true
            }
        -- Any key at all, for clearing a transient message: whatever someone does next
        -- is their acknowledgement of it.
        isAnyKeyPressed = false
        for _, letter in ipairs(alphabet) do
            local pressed = ImGui.IsKeyPressed(ctx, ImGui["Key_" .. letter], repeatKeys[letter])
            _G["is" .. letter] = pressed
            if pressed then isAnyKeyPressed = true end
        end
        updateTransientMessage()

        -- cmd+w closes the window, as it does everywhere else. Clearing `open` is the
        -- same thing the title bar's close button does: the loop stops deferring, and
        -- the atexit cleanup puts the toolbar button out and stops any preview.
        --
        -- isSuperDown is Mod_Ctrl, which ReaImGui maps to cmd on macOS. Checked here,
        -- right after the keys are read, so nothing downstream can swallow it first --
        -- and w is not bound to anything else in this script.
        if isSuperDown and isW then
            open = false
        end

        
        
        posX2 = 220
        posX3 = posX2 + posX2
        posX4 = posX3 + posX2
        posX45 = posX4 + posX2 / 2


        scrollVertical, scrollHorizontal = ImGui.GetMouseWheel(ctx)

        mouse_pos_x, mouse_pos_y = reaper.ImGui_GetMousePos(ctx)
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        playState = reaper.GetPlayState()
        isPlaying = playState ~= 0


        if not isPlaying then
            timeline_cur_pos = reaper.GetCursorPosition()
        else
            timeline_cur_pos = reaper.GetPlayPosition()
        end
        
        --if not last_cur_pos then --or settings.cursorFollowSelectedCut then
            cur_pos = timeline_cur_pos
        --end
        
        
        start_time_arr, end_time_arr = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0) 
        length_time_arr = end_time_arr - start_time_arr
        if settings.selectionType == "Arrange view" and ((not last_start_time_arr or last_start_time_arr ~= start_time_arr) or (not last_end_time_arr or last_end_time_arr ~= end_time_arr)) then
            last_start_time_arr = start_time_arr
            last_end_time_arr = end_time_arr
            update_cut_data_on_all_items({itemProperties, item2Properties})
        end
        
        start_time_sel, end_time_sel = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        length_time_sel = end_time_sel - start_time_sel
        
        if settings.selectionType == "Time selection" and ((not last_start_time_sel or last_start_time_sel ~= start_time_sel) or (not last_end_time_sel or last_end_time_sel ~= end_time_sel)) then
            last_start_time_sel = start_time_sel
            last_end_time_sel = end_time_sel 
            update_cut_data_on_all_items({itemProperties, item2Properties})
        end
        
        run = run + 1
        
        -- A side pinned from the Compare tab wins over selection order, so changing the
        -- arrange selection to pick the other side does not pull the first one away.
        local item = (compareVideos and conformResolvePin("old")) or getSelectedVideoFile()
        local item2
        if compareVideos then
            item2 = conformResolvePin("new") or getSelectedVideoFile(1)
            -- A side pins itself the moment it first gets a video. Without this, moving
            -- the cursor or changing the arrange selection silently swapped out what you
            -- were comparing -- the opposite of what a comparison wants. Once something
            -- is in a side it takes a deliberate click to change it.
            if item  and not conformPin.old then conformPinItem("old", item)  end
            if item2 and not conformPin.new then conformPinItem("new", item2) end
        end
        
        if not item or (not item2 and compareVideos) then 
            item, item2 = GetFirstVisibleVideoItemUnder(settings.selectionType == "Time selection" and (start_time_sel + (end_time_sel - start_time_sel) / 2) or timeline_cur_pos)   --reaper.GetSelectedMediaItem(0, 0)   
            
        end
        
        is_a_subproject = false
        subProj_item_pos = 0
        local mainProj = 0
        local subProj, subProj_item
        if not item then
            mainProj, subProj, subProj_item = isSubproject() 
            is_a_subproject = subProj and true or false
            if is_a_subproject then 
                subProj_item_pos = reaper.GetMediaItemInfo_Value(subProj_item, "D_POSITION")
                item = GetFirstVisibleVideoItemUnder(subProj_item_pos, mainProj)
                settings.compareVideoMode = false
                start_time_sel, end_time_sel = reaper.GetSet_LoopTimeRange2(subProj, false, false, 0, 0, false)
                start_time_sel = start_time_sel + subProj_item_pos
                end_time_sel = end_time_sel + subProj_item_pos
            end
            
        end
        
        
        if swapItems and compareVideos then
            local tempItem = item2
            item2 = item
            item = tempItem
        end
        
        if not item then
            -- item = {}
            last_cur_pos = nil
        end
        
        
        if itemProperties and itemProperties.item then 
            getItemRealtimeInfo(itemProperties, mainProj) 
        end 
        
        if compareVideos and item2Properties and item2Properties.item then
            getItemRealtimeInfo(item2Properties)
        end

        
        
        
        -- item2 is tracked as well as item. It was not, so anything that changed only
        -- the second side -- selecting a second item, or pinning a different one from
        -- the Compare tab -- never refreshed its properties and so appeared to do
        -- nothing at all.
        -- last_item/last_item2 are in the guard too, so clearing the selection
        -- refreshes once and then settles instead of leaving the old files on screen.
        if (item or item2 or last_item or last_item2) and (not last_item
            or last_item ~= item -- get properties when we change item selection
            or last_item2 ~= item2
            or settings.tabSelection ~= last_tabSelection_update -- update properties when we change tab
            or analyseStartTime -- get data_cut when we analyse a video
            or is_a_subproject ~= last_is_a_subproject -- get data_cut when we analyse a video
            or update_cut_data
            ) then

            if not update_cut_data then
                last_cur_pos = nil
                --IP.last_cur_pos_in_item = nil
                wait = false
                last_item = item
                last_item2 = item2
                last_is_a_subproject = is_a_subproject
                --IP.cut_data = nil
                undo_stack = {}
                redo_stack = {}
            end


            -- A conform result describes the pair it was run on, so selecting a
            -- different item makes it stale rather than merely out of date.
            if conformResult or conformError then
                local ip1Changed = conformIP1 and conformIP1.item ~= item
                local ip2Changed = conformIP2 and item2 and conformIP2.item ~= item2
                if ip1Changed or ip2Changed then
                    conformResult = nil
                    conformError = nil
                    conformSelectedIdx = nil
                    conformPlaying = false
                    conformStopPreview()
                end
            end
            
            update_cut_data = false

            -- One item used to blank both sides, which left the Compare tab stuck on
            -- "select two video items" with no way back: last_item had already been set
            -- to the real item, so the next frame saw no change and never refreshed.
            -- Now the first selection fills the old side and the second fills the new,
            -- and the tab draws its usual layout with the empty side marked as empty.
            itemProperties = getItemProperties(item, 0, mainProj)
            
            if compareVideos then 
                item2Properties = getItemProperties(item2, 1) 
            end
            
            last_tabSelection_update = settings.tabSelection
            --if settings.compareVideoMode then
            --end
            
        end
        
        
        if update_cut_data_after_selectionType_change then 
            if settings.selectionType == "Time selection" and settings.arrangeviewFollowsOverview then
                setArrangeviewArea()
            end
            update_cut_data_on_all_items({itemProperties, item2Properties})
            update_cut_data_after_selectionType_change = false
        end
        
        
        -- A rule across the width with a clickable label sitting on it, used to fold a
        -- section away without taking up a row of its own.
        function clickableSeparator(label, open, id)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFFFFF18)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFF30)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), open and colorWhite or colorGrey)
            local hit = reaper.ImGui_Button(ctx, (open and "v  " or ">  ") .. label .. "##sep" .. (id or label))
            reaper.ImGui_PopStyleColor(ctx, 4)

            local bx, by = reaper.ImGui_GetItemRectMax(ctx)
            local _,  ty = reaper.ImGui_GetItemRectMin(ctx)
            local lineY  = (ty + by) / 2
            reaper.ImGui_DrawList_AddLine(draw_list, bx + 4, lineY, winW - 10, lineY, 0xFFFFFF22, 1)
            return hit
        end

        -- The options are the controls this page is for -- the detector, its thresholds,
        -- what counts as an edited cut -- so they are always shown. They used to sit
        -- behind a collapsible "Options" header, which only ever cost a click to get at
        -- the thing you came for, and left the page looking empty when it was closed.
        function generalSettingButtons(IP, IP2)
            settingsCheckBoxes(IP, IP2)
            cutShowingSettings(IP, IP2)
            reaper.ImGui_Separator(ctx)
        end
        
        -- Tab 3 is Settings.
        local TAB_SETTINGS = 3

        function updateTabSelection(number)
            if last_tabSelection then 
                settings.tabSelection = number
                saveSettings()
                if last_tabSelection ~= number then
                    update_cut_data = true

                    -- Arriving at the settings page stops whatever this app was
                    -- playing. Every transport control lives on the other two tabs, so
                    -- sound that carries on here cannot be stopped without navigating
                    -- back to find the button -- and nothing on this page has anything
                    -- to do with playback. conformHalt is the same stop the button
                    -- performs, so in sync mode it carries the project transport with
                    -- it, and it leaves alone a playback that REAPER itself started.
                    if number == TAB_SETTINGS then conformHalt() end
                end
            end
            last_tabSelection = number 
        end
        
        function selectTab(number)
            local flags
            if (isCtrlDown and _G["is" .. number]) or (settings.tabSelection == number and (not last_tabSelection or settings.tabSelection ~= last_tabSelection)) then 
                flags = reaper.ImGui_TabItemFlags_SetSelected()  
                updateTabSelection(number)
            end
            return flags
        end
        
        if reaper.ImGui_BeginTabBar(ctx, "##tabs") then
            
            local flags = selectTab(1)
            cutDetection = reaper.ImGui_BeginTabItem(ctx, "Cut Detection", nil, flags)
            -- Straight after BeginTabItem, while the tab button is still the last
            -- submitted item. Set after EndTabItem instead, as these were, it attaches
            -- to the last widget drawn inside the tab -- so the tooltip worked on the
            -- tabs that were closed and, on the open one, turned up on whatever its
            -- content happened to end with.
            setToolTipFunc("Detect and name cuts in a video", MOD_CTRL .. "+1")
            
            if cutDetection then
                updateTabSelection(1) 
                
                generalSettingButtons(itemProperties)

                selectedCutInfoArea(itemProperties)
                
                overviewArea(itemProperties)
                local onCaptionRow = previewSection(itemProperties)
                
                -- The transport shares the row the thumbnail captions are on, centred
                -- between them: the gap between the two pictures is where it belongs,
                -- and it costs a row of height that was empty either side of it. With
                -- no item selected there are no captions and so no row to join, and it
                -- needs one of its own.
                if not onCaptionRow then reaper.ImGui_NewLine(ctx) end
                reaper.ImGui_SameLine(ctx, winW / 2 - math.floor(31*2.5)) 
                navigationButtons(itemProperties) 
                
                reaper.ImGui_Separator(ctx)
                addButtons(itemProperties) 

                -- Undo and Redo sit at the right-hand end of the row of actions, rather
                -- than up beside the navigation arrows where they used to be. They
                -- belong with the things that change the cuts, which is what they undo;
                -- next to the frame-stepping arrows they read as part of navigating.
                reaper.ImGui_SameLine(ctx, winW - 106)
                undoRedoButtons(itemProperties)
                
                
                
                reaper.ImGui_EndTabItem(ctx)
            end 
            
            local flags = selectTab(2)
            compareVideos = reaper.ImGui_BeginTabItem(ctx, "Compare Videos", nil, flags)
            -- Before the content; see the note on the first tab.
            setToolTipFunc("Compare 2 videos cut with each other", MOD_CTRL .. "+2")
            if compareVideos then
                updateTabSelection(2)
                -- The overview-area focus keys are not wired up here: the cut overviews
                -- they switched between are gone from this tab, and up/down now pick
                -- which version the conform transport drives.

                -- Drawn whether or not both sides are filled. The layout is the same
                -- either way, with the missing side saying what to do, so selecting
                -- items does not make the whole window jump between two shapes.

                -- Nothing in here touches REAPER's playhead or cut data: the two
                -- versions are compared against each other inside the app.
                conformIP1, conformIP2 = itemProperties, item2Properties

                -- The header row, source buttons, previews, timecodes and the
                -- matching controls all live in drawConformSection now, so that
                -- the whole comparison is laid out in one place rather than half
                -- here and half there.

                -- The section is always drawn, with any error shown above it rather
                -- than instead of it. Replacing it with a one-line message collapsed
                -- the window to that line and then sprang it open again, which is
                -- the flicker: the window is resized to its content every frame.
                -- Said plainly and at the top, in italics so it reads as a note about
                -- the tab rather than part of it: this is the newest thing here and it
                -- can still be wrong about a conform, which is worth knowing before
                -- anyone trusts one. Dimmed rather than coloured as a warning -- it is
                -- an invitation, not an error, and the error line below is red.
                conformDevNotice()

                if conformError then
                    reaper.ImGui_TextColored(ctx, 0xFF4444FF, conformError)
                end
                drawConformSection(itemProperties, item2Properties)
                
                --[[
                reaper.ImGui_SameLine(ctx, posX2)
                ret, settings.cursorFollowSelectedCut = reaper.ImGui_Checkbox(ctx, "Selection of cuts follow", settings.cursorFollowSelectedCut)
                if ret then
                    if settings.cursorFollowSelectedCut then
                        moveCursorToPos(cur_pos)
                    end
                
                    saveSettings()
                end
                setToolTipFunc("Playhead will jump to selected cut position.\n- press " .. MOD_CMD .. "+p to set with keyboard")
                ]]
                
                
                
                reaper.ImGui_EndTabItem(ctx)
                
            end
            
            local flags = selectTab(3)
            settingsShown = reaper.ImGui_BeginTabItem(ctx, "Settings", nil, flags)
            -- Before the content; see the note on the first tab.
            setToolTipFunc("Show app settings", MOD_CTRL .. "+3")
            if settingsShown then 
                updateTabSelection(3)
                
                settingButtons(itemProperties) 
                reaper.ImGui_EndTabItem(ctx) 
            end
            
            reaper.ImGui_EndTabBar(ctx)
        end
        
        
        
        
        popupUpWindows(popupItemProperties)
        
        
        lastPosY = reaper.ImGui_GetCursorPosY(ctx) + 4

        -- reaper.ImGui_PopFont(ctx)
        --
        reaper.ImGui_End(ctx)
    end

    --[[
          if isSuperDown and isZ then
              if isShiftDown then
                  cut_data = undo_redo.redo(cut_data)
              else
                  cut_data = undo_redo.undo(cut_data)
              end
          end]]


    --end
     
    -- reaper.ImGui_PopFont(ctx)
    -- Pop Style Vars (6 vars added) and Colors (12 colors added)
    ImGui.PopStyleVar(ctx, 6)
    ImGui.PopStyleColor(ctx, pushStyleColorAmount)
    
    
    
    -- Just stop deferring when the window closes. The cleanup is registered once at
    -- startup instead of here: registering it only on the way out meant it never ran if
    -- REAPER quit, or the script was terminated, with the window still open -- which
    -- left the toolbar button lit for an editor that was no longer running.
    if open then
        reaper.defer(loop)
    end
end


reaper.atexit(exit)
reaper.defer(loop)


