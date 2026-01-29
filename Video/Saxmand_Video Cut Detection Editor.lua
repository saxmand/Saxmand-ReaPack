-- @description Find and edit cuts in videos using an editor and precise cut detection
-- @author saxmand
-- @version 0.2.4
-- @provides
--   Helpers/*.lua
--   Helpers/hosi_exec_hidden.vbs
-- @changelog
--   + fixed exit error, to clean any temp image from script folder


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
    showSettingsBoxes = true,
    tabSelection = 1,
    
    arrangeviewFollowsOverview = true,
    displayTimeSelection = true,
    selectionType = "Video item",
    useTypeForSingleInsert = "Markers",
    useTypeForSingleInsertSubproject = "Markers",
    
    setNameOnSplitItems = true, 
    setColorOnSplitItems = true,
}

local function saveSettings()
    local settingsStr = json.encodeToJson(settings)
    reaper.SetExtState(stateName, "settings", settingsStr, true)
end



if reaper.HasExtState(stateName, "settings") then
    local settingsStr = reaper.GetExtState(stateName, "settings")
    settings, errorMsg = json.decodeFromJson(settingsStr)
    if not settings then
        reaper.ShowConsoleMsg("There was an error loading ext state: "..errorMsg.."\n")
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


local ffmpeg_path = ffmpeg.Get_Path()
if ffmpeg_path == nil then return else ffmpeg_path = ffmpeg_path end

-- Initialize ImGui Context AFTER blocking calls (Get_FFMpeg_Path) to avoid context invalidation error
ctx = ImGui.CreateContext('Video cut detection editor')


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

function get_cut_information(IP, detection_threshold) 
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

local function createThumbnails_windows(filePath, pngPath, itemStart, overwrite)
  if overwrite or not reaper.file_exists(pngPath) then
    -- Бронебойный вариант запуска для Windows (с двойными кавычками)
    local cmd = '""' .. ffmpeg_path .. '" -ss ' .. itemStart .. ' -y -i "'..filePath..'" -frames:v 1 "'..pngPath ..'"'
    return io.popen(cmd, "r")
  end
end

local function createThumbnails(filePath, pngPath, itemStart, overwrite, background, forceAsync) 
    local is_windows = seperator == "\\"
    if not is_windows then
        createThumbnails_mac(filePath, pngPath, itemStart, overwrite)
    else
        createThumbnails_win(filePath, pngPath, itemStart, overwrite)
    end
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
                 
                 if not reaper.file_exists(cut.pngPath) then 
                     -- Add tasks to queue instead of processing immediately
                     table.insert(generationQueue, {
                        filePath = IP.filePath, 
                        pngPath = cut.pngPath, 
                        time = cut.time, 
                        overwrite = true
                     })
                 end
                 if not onlySpecific then 
                    
                    if not reaper.file_exists(cut.pngPath_frame_before) then 
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
        createThumbnails(task.filePath, task.pngPath, task.time, task.overwrite)
        return true -- Processed something
    else
        if genratingThumbNails then
            genratingThumbNails = false
            -- Optional: Show completion message?
        end
        return false -- Nothing to process
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
        
        if is_a_subproject then
            overview_start_in_item = subProj_item_pos
            overview_start_in_item_offset = subProj_item_pos
            overview_length_in_item = get_subproject_length()
            
            
            
            item_area_to_analyze_start = overview_start_in_item < 0 and item_offset or overview_start_in_item + item_offset
            item_area_to_analyze_length = overview_length_in_item + (overview_start_in_item < 0 and overview_start_in_item or 0)
            
            overview_start_time = overview_start_in_item
            overview_length_time = overview_length_in_item
        end  
        
        overview_end_in_item = overview_start_in_item + overview_length_in_item
        
        --local item_area_to_analyze_start = overview_start_in_item < 0 and 0 or overview_start_in_item
        --local item_area_to_analyze_length = overview_length_in_item > item_length and item_length or overview_length_in_item
        
        local cur_pos_in_item = (item_pos and cur_pos - item_pos + item_offset or 0)                     --+ IP.overview_start_in_item
        
        timeline_cur_pos_in_item = (item_pos and timeline_cur_pos - item_pos + item_offset or 0)   --+ IP.overview_start_in_item 
        
        if is_a_subproject then
            --timeline_cur_pos_in_item = timeline_cur_pos_in_item - overview_start_in_item
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
            reaper.Main_OnCommand(1016, 0) --Transport: Stop
        end
        if is_a_subproject then
            pos = pos - subProj_item_pos
        end
        reaper.SetEditCurPos(pos, true, false)
        if playState ~= 0 then
            reaper.Main_OnCommand(1007, 0) --Transport: Play
        end
    end
end


function updateCutDataFile(IP)
    saveFile(IP.cutTextFilePath, json.encodeToJson(IP.cut_data))
end



function getCutData(IP)
    if not IP then return end
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
    analyseRaw = IP.cutTextFilePathRaw and reaper.file_exists(IP.cutTextFilePathRaw)
    analysing = false
    if analyseRaw then
    
        if not IP.cut_data or #IP.cut_data == 0 then
            getCutData(IP)
            analysing = true
            analyseEndTime = time_precise
            
            if #IP.cut_data > 0 then
                analysing = false
                os.remove(IP.cutTextFilePathRaw)
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
            IP.cut_data = json.decodeFromJson(readFile(IP.cutTextFilePath)) 
        else
            IP.cut_data = {}
        end
    end
    
    -- store analyze speed
    if IP.cut_data and #IP.cut_data > 0 then 
        if analyseEndTime and analyseStartTime and analyseEndTime > analyseStartTime then 
            local analyseSpeed = (analyseEndTime - analyseStartTime) / IP.item_area_to_analyze_length
            if analyseSpeed > 0 then 
                analyseSpeed = math.floor(analyseSpeed * 1000) / 1000
                settings.analyseSpeed = ((settings.analyseSpeed and settings.analyseSpeed or analyseSpeed) + analyseSpeed) / 2 
                saveSettings() 
            end
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
    setToolTipFunc("Display time selection in the overview area", "d")
    
    if (not markerNameIsFocused or isSuperDown) and isD then
        settings.displayTimeSelection = not settings.displayTimeSelection
        saveSettings()
    end
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
        setToolTipFunc("Link arrange view to width of selection.\n- press cmd/ctrl+l to set with keyboard")

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
    setToolTipFunc("Playhead will jump to selected cut position.\n- press cmd/ctrl+p to set with keyboard")

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
    setToolTipFunc("Select cut marker when playhead passes.\n- press cmd/ctrl+s to set with keyboard")

    if (not markerNameIsFocused or isSuperDown) and isS then
        settings.navigationFollowsPlayhead = not settings.navigationFollowsPlayhead
        saveSettings()
    end

    --reaper.ImGui_SameLine(ctx)
    
end


function cutShowingSettings(IP, IP2)

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
    setToolTipFunc("Set the sensitivity for how likely there is a cut.\n - press keypad plus/minus to set with keyboard.\n - Hold down super for fine grained")
    
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
    
    
    reaper.ImGui_SameLine(ctx, posX3)
    ret, settings.onlyShowCutsWithEditedName = reaper.ImGui_Checkbox(ctx, "only show edited cuts", settings.onlyShowCutsWithEditedName)
    if ret then
        setArrangeviewArea()
        saveSettings()
        find_cut_data(IP)
        find_cut_data(IP2)
    end
    setToolTipFunc("Hide cuts that does not have an edited name.\n- press cmd/ctrl+o to set with keyboard")

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
        setToolTipFunc("Set marker color.\n- press cmd/ctrl+" ..
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
    setToolTipFunc("Set cut to next color.\n- press cmd/ctrl+c to set with keyboard\n- hold shift to set all markers")
end

function analyseButton(IP, btnName)
    if reaper.ImGui_Button(ctx, btnName) or isA then
        
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
    
    setToolTipFunc("Click to analyse cut. Press escape on keyboard to stop analysing", "a")
end


---- LAYOUT STUFF
function selectedItemButtons(IP)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), analysingColor)
    
    --reaper.ImGui_PopStyleColor(ctx)
        
    local itemNumber = IP and IP.itemNumber and IP.itemNumber or ""
    --local btnName = (IP.cutTextFilePath and reaper.file_exists(IP.cutTextFilePath)) and "Re-analyse video" or "Analyse video"
    --analyseButton(IP, "Analyse video")
    --reaper.ImGui_SameLine(ctx)--, posX45)
    
   
    if IP.analysisMade then 
        reaper.ImGui_SameLine(ctx, posX4) 
        if reaper.ImGui_Button(ctx, "Generate Thumbnails##"..itemNumber) then
            generateThumbnailsForCuts(IP)
        end
        setToolTipFunc("Click to generate cut thumbnails to get instant navigation")
    end 
    
    
    if IP.item then 
        --reaper.ImGui_SameLine(ctx, posX4 - 52) 
        reaper.ImGui_SameLine(ctx) 
        if reaper.ImGui_Button(ctx, "Extra##"..itemNumber) or (not markerNameIsFocused and isE) then
            reaper.ImGui_OpenPopup(ctx, "extra")
        end 
        setToolTipFunc("Click to see some extra options", "e")
        
        if (not markerNameIsFocused and isE) then
            local extraPosX, extraPosY = reaper.ImGui_GetItemRectMax(ctx) 
            reaper.ImGui_SetNextWindowPos(ctx,extraPosX - 10, extraPosY - 10)
        end
        
        if reaper.ImGui_BeginPopup(ctx, "extra") then 
            local closePopup = false
            if IP.analysisMade then 
                if IP and (IP.cutTextFilePath and reaper.file_exists(IP.cutTextFilePath)) then
                    analyseButton(IP, "Analyse video")
                end
            
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
        
        if not IP.analysisMade and IP.item then  
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_Button(), pulsatingColor(theme.accent, 3))
            reaper.ImGui_PushStyleColor(ctx,reaper.ImGui_Col_ButtonHovered(), pulsatingColor(theme.accent, 3))
            analyseButton(IP, "Analyse video##" .. itemNumber)
            reaper.ImGui_PopStyleColor(ctx,2)
            reaper.ImGui_SameLine(ctx, posX4)
        end
        
        selectedItemButtons(IP)
    end
end

--reaper.ImGui_SameLine(ctx)
function selectedCutInfoArea(IP)
    reaper.ImGui_AlignTextToFramePadding(ctx)
    --reaper.ImGui_TextColored(ctx, colorGrey, "Video:")
    --reaper.ImGui_SameLine(ctx)
    itemButton(IP)
    
    if IP then  
    
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
        else
            --if not cursorOutsideArea then
                if reaper.ImGui_Button(ctx, "Insert marker") or ((not markerNameIsFocused or isSuperDown) and isI) then
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
                
                setCutSelection(IP, IP2, not isShiftDown and hoverIndex or nil) 
                moveCursorToPos(cur_pos)
                overviewAreaFocus = IP.itemNumber
                
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
local function DrawImageCentered(image, slotW, slotH, label)
    local p = { reaper.ImGui_GetCursorScreenPos(ctx) }

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
            
            IP.cur_pos_in_item = (IP.item_pos and (cur_pos - IP.item_pos + IP.item_offset) or 0) 
        end
    else
    
        if isPlaying then
        
        else
            if IP.cuts_making_threashold then-- and not IP.ignoreCutOnNextDefer then 
                for i, c in ipairs(IP.cuts_making_threashold) do
                    --reaper.ShowConsoleMsg(cur_pos_to_check
                    if compareWithMargin(c.time, IP.cur_pos_in_item + subProj_item_pos) then
                        IP.last_currentSelectedCut = IP.currentSelectedCut
                        IP.currentSelectedCut = c.index
                        updateThumbnails = true 
                        break;
                    end
                end
            end
            --IP.ignoreCutOnNextDefer = nil
            
            if not updateThumbnails and IP.last_cur_pos_in_item ~= IP.cur_pos_in_item then
                updateThumbnails = true
            end
        end
    end
    
    --IP.last_cur_pos_in_item = IP.cur_pos_in_item
    
    return updateThumbnails
end


function previewSection(IP)      
    if not IP then return end
    if not imageA_array then imageA_array = {} end
    if not imageB_array then imageB_array = {} end
    -- PREVIEW SECTION  
    
    local updateThumbnails = (not analyseStartTime and IP) and should_thumbnail_update(IP)
    local itemNumber = IP and IP.itemNumber or 0
    local itemString = IP and tostring(IP.item) or 0
    --if not pngPath_array[itemString] then pngPath_array[itemString] = {} end
    
    pngPathA = IP and IP.pngPathA -- pngPath_array[itemString].pngPathA
    pngPathB = IP and IP.pngPathB -- pngPath_array[itemString].pngPathB
    --imageA = 
    
    local filePath = IP and IP.filePath
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
                
                
                -- for stored thumbnails
                if IP.currentSelectedCut and IP.thumbnailPath_exist then
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
                
                

                if not oneFrameLater then
                    --reaper.ShowConsoleMsg(cur_pos_in_item - (IP.last_cur_pos_in_item - (1/fps)) .. " - " .. run .."\n")
                    pngPathA = join_paths(script_path, "tempA" .. itemNumber .. ".png")
                    os.remove(pngPathA)
                    imageCreatedA = createThumbnails(filePath, pngPathA, cur_pos_rounded_to_frame_one_frame_ealier + subProj_item_pos, true)
                    imageA_array[itemString] = nil
                    --reaper.ShowConsoleMsg("load A\n")
                end

                if not oneFrameEarlier then
                    pngPathB = join_paths(script_path, "tempB" .. itemNumber .. ".png")
                    os.remove(pngPathB)
                    imageCreatedB = createThumbnails(filePath, pngPathB, cur_pos_rounded_to_frame + subProj_item_pos, true)
                    imageB_array[itemString] = nil
                    --reaper.ShowConsoleMsg("load B\n")
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
    
    DrawImageCentered(imageA_array[itemString], slotW, slotH, imageAText .. "##1_" .. itemNumber) 
    setToolTipFunc(imageATip)

    
    
    reaper.ImGui_SameLine(ctx)
    local imageBText = isLastImage and "" or imageText
    DrawImageCentered(imageB_array[itemString], slotW, slotH, imageBText .. "##2_" .. itemNumber)
    
    if not isLastImage then
        setToolTipFunc("Image on cut selection")
    end
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
                if not c.exclude then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    reaper.AddProjectMarker2(0, false, pos, 0, name, -1, (col >> 8) | 16777216)
                end
            end
        end
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert markers from video cut detection", -1)
    end 
    setToolTipFunc("Insert markers with name and color for each cut.\n - Hold down super or press super+enter to insert the selected cut only", "option+1")
    
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
                if not c.exclude then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    reaper.AddProjectMarker2(0, true, pos, endPos, name, -1, (col >> 8) |16777216)
                end
            end
        end 
        
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert regions from video cut detection", -1)
    end
    setToolTipFunc("Insert Regions with name and color for each cut.\n - Hold down super or press super+enter to insert the selected cut only", "option+2")
    
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
                if not c.exclude then
                    local name, col, pos, endPos = getNameColorAndPos(IP, i, c)
                    reaper.SetTakeMarker(reaper.GetActiveTake(IP.item), -1, name, c.time, (col >> 8) |16777216)
                end
            end
        end 
        undo_redo.save_undo({reaperAction = true})
        reaper.Undo_EndBlock("Insert take markers from video cut detection", -1)
    end 
    setToolTipFunc("Insert take markers with name and color for each cut.\n - Hold down super or press super+enter to insert the selected cut only", "option+3")
    
    
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
                    if not c.exclude then
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
    setToolTipFunc("Insert thumbnails with name and color for each cut.\n - Hold down super or press super+enter to insert the selected cut only", "option+4")
    
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
                if not c.exclude then
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
    setToolTipFunc("Insert thumbnails with name and color for each cut.\n - Hold down super or press super+enter to insert the selected cut only", "option+5")
    
    
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
                if not c.exclude then 
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
    setToolTipFunc("Split video at each cut and name each part with name and color.\n - Hold down super or press super+enter to split on the selected cut only", "option+6")
    
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
                        if not c.exclude then 
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
    setToolTipFunc("Split video at each cut and name each part with name and color.\n - Hold down super or press super+enter to split on the selected cut only", "option+7")
    
    
    
    
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
    setToolTipFunc("Undo last change to a cut", "super+z") 
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
    setToolTipFunc("Redo last undone change to a cut", "super+shift+z") 
    if not hasRedo then reaper.ImGui_EndDisabled(ctx) end
end

function settingButtons(IP)
    
    --[[
    ret, settings.onlyShowThumbnailsForCuts = reaper.ImGui_Checkbox(ctx, "Only show thumbnails for cuts", settings.onlyShowThumbnailsForCuts)
    if ret then 
        saveSettings()
    end
    setToolTipFunc("Only show thumbnails for cuts is useful if you don't want thumbnail creation when the playhead is not on a cut")
    ]]
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "Settings")
     
    if reaper.ImGui_Button(ctx, "Reset Settings") then
        settings = deep_copy(defaultSettings)
        settings.tabSelection = 3
        saveSettings()
    end
    setToolTipFunc("Click to reset FFMPEG path if you selected the wrong one or moved the file.")
    
    
    local isDisabled = not settings.analyseSpeed
    if isDisabled then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Reset analyze speed") then
        settings.analyseSpeed = nil
        saveSettings()
    end
    setToolTipFunc("Click to reset the analyze speed. " .. (settings.analyseSpeed and ("The current speed is: " ..  string.format("%.4f", settings.analyseSpeed)) or "No speed measured. Analyze to set this"))
    if isDisabled  then reaper.ImGui_EndDisabled(ctx) end
    
    if reaper.ImGui_Button(ctx, "Open FFMPEG Path") then
        reaper.CF_ShellExecute(GetDirectoryFromPath(ffmpeg_path)) 
    end
    
    
    if reaper.ImGui_Button(ctx, "Reset FFMPEG Path") then
        ffmpeg.ResetPath()
        reaper.MB("FFMPEG path has been reset. Please restart the script to select a new path.", "Reset Path", 0)
    end
    setToolTipFunc("Click to reset FFMPEG path if you selected the wrong one or moved the file.")
    
    ret, settings.extremeCutDetection = reaper.ImGui_Checkbox(ctx, "Extreme cut detection", settings.extremeCutDetection)
    if ret then 
        saveSettings()
    end
    setToolTipFunc("This will make a lot more cuts detected, and maybe not be useful, as a lot of falls cut might apear." .. 
    "\nYou can hold down super while pressing keypad minus or plus for more gradual sensitivity." ..
    "\nEnabling this requires to re-analyse a video for more cuts to show up")
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


function popupUpWindows(IP)
        
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
         if analyseEndTime and analyseStartTime and analyseEndTime > analyseStartTime then
             -- 0.025 is a magic number. We could possibly get real analyze progress by saving progress from FFMPEG
             local analyseSpeed = settings.analyseSpeed and settings.analyseSpeed or 0.1
             analysingAmount = (analyseEndTime - analyseStartTime) / IP.item_area_to_analyze_length / analyseSpeed 
             if analysingAmount > 1 then analysingAmount = 1 end
         end
         
        -- Always center this window when appearing
        local center_x, center_y = reaper.ImGui_Viewport_GetCenter(reaper.ImGui_GetWindowViewport(ctx))
        reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        
        if reaper.ImGui_BeginPopupModal(ctx, "Analysing Video", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            
            
            if not settings.analyseSpeed then 
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
local minSizeW = 220 * 4 + 8

compareVideos = settings.tabSelection == 2


local function exit()
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
        --reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigFlags_NavEnableKeyboard(), 0)

        local imageW = ((winW - 8 * 3) / 2) / (16 / 9) -- settings.windowSize --

        -- ImGui.PushFont(ctx, font)
        isMouseDown = ImGui.IsMouseDown(ctx, 0)
        isMouseClick = ImGui.IsMouseClicked(ctx, 0)

        isShiftDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
        isCtrlDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Super)
        isOptionDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)
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
        for _, letter in ipairs(alphabet) do
            _G["is" .. letter] = ImGui.IsKeyPressed(ctx, ImGui["Key_" .. letter], repeatKeys[letter])
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
        
        local item = getSelectedVideoFile() 
        local item2
        if compareVideos then 
            item2 = getSelectedVideoFile(1) 
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
        
        
        
        if item and (not last_item 
            or last_item ~= item -- get properties when we change item selection
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
                last_is_a_subproject = is_a_subproject
                --IP.cut_data = nil
                undo_stack = {}
                redo_stack = {}
            end
            
            update_cut_data = false
            
            if compareVideos and not item2 then 
                item = nil
                item2 = nil
            end
            
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
        
        
        function generalSettingButtons(IP, IP2)            
            if settings.showSettingsBoxes then 
                settingsCheckBoxes(IP, IP2)
                --reaper.ImGui_Separator(ctx)
                
                cutShowingSettings(IP, IP2)
                
                reaper.ImGui_Separator(ctx)
            end
        end
        
        function updateTabSelection(number)
            if last_tabSelection then 
                settings.tabSelection = number
                saveSettings()
                if last_tabSelection ~= number then
                    update_cut_data = true
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
            
            if cutDetection then
                updateTabSelection(1) 
                
                generalSettingButtons(itemProperties)
                
                
                selectedCutInfoArea(itemProperties)
                
                overviewArea(itemProperties)
                previewSection(itemProperties)
                
                reaper.ImGui_NewLine(ctx)
                reaper.ImGui_SameLine(ctx, winW / 2 - math.floor(31*2.5)) 
                
                
                
                navigationButtons(itemProperties) 
                
                reaper.ImGui_SameLine(ctx, winW - 106) 
                undoRedoButtons(itemProperties)
                
                
                reaper.ImGui_Separator(ctx)
                addButtons(itemProperties) 
                
                
                
                reaper.ImGui_EndTabItem(ctx)
            end 
            setToolTipFunc("Detect and name cuts in a video", "ctrl+1")
            
            local flags = selectTab(2)
            compareVideos = reaper.ImGui_BeginTabItem(ctx, "Compare Videos", nil, flags)
            if compareVideos then 
                updateTabSelection(2)
                if not overviewAreaFocus then overviewAreaFocus = 0 end
                focusOverviewAreaKeycommands()
                
                generalSettingButtons(itemProperties, item2Properties)
                
                    
                if itemProperties and item2Properties and itemProperties.item and item2Properties.item then 
                    
                    
                    --if not item2Properties then item2Properties = {} end
                    local navigationFocusIP1 = overviewAreaFocus == itemProperties.itemNumber and itemProperties or item2Properties
                    local navigationFocusIP2 = overviewAreaFocus == itemProperties.itemNumber and item2Properties or itemProperties
                    
                    itemButton(itemProperties)
                    
                    if reaper.ImGui_InvisibleButton(ctx, "arrow", buttonSize, buttonSize) then 
                        swapItems = not swapItems
                    end
                    local arrowX, arrowY = reaper.ImGui_GetItemRectMin(ctx)
                    local arrowW, arrowH = reaper.ImGui_GetItemRectSize(ctx)
                    local posX = arrowX + arrowW/2
                    local posX1 = arrowX + arrowW/4
                    local posX2 = arrowX + arrowW/4 * 3
                    local posY1 = arrowY + 2
                    local posY2 = arrowY + arrowH - 2
                    local posY3 = arrowY + arrowH / 5 * 3
                    reaper.ImGui_DrawList_AddLine(draw_list,posX , posY1, posX, posY2, colorWhite, 1)
                    reaper.ImGui_DrawList_AddLine(draw_list,posX, posY2, posX1, posY3, colorWhite, 1)
                    reaper.ImGui_DrawList_AddLine(draw_list,posX, posY2, posX2, posY3, colorWhite, 1)
                    
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "Swap") then
                        swapItems = not swapItems
                    end
                    
                    if devMode then 
                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_Button(ctx, "Compare") then
                            
                        end
                    end
                    
                    itemButton(item2Properties)
                    
                    
                    overviewArea(itemProperties, item2Properties) 
                    overviewArea(item2Properties, itemProperties)
                    
                    
                    previewSection(itemProperties) 
                    
                    previewSection(item2Properties)
                    
                    
                    reaper.ImGui_NewLine(ctx)
                    reaper.ImGui_SameLine(ctx, winW / 2 - math.floor(31*2.5)) 
                    
        
                    navigationButtons(navigationFocusIP1, navigationFocusIP2)  
                else
                
                    --reaper.ImGui_Text(ctx, "Please select 2 video items to compare")
                    reaper.ImGui_PushFont(ctx, font, 30) 
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
                    reaper.ImGui_Button(ctx, "Please select 2 video items to compare", winW-16, 400)
                    reaper.ImGui_PopStyleColor(ctx, 3)
                    reaper.ImGui_PopFont(ctx)
                end
                
                --[[
                reaper.ImGui_SameLine(ctx, posX2)
                ret, settings.cursorFollowSelectedCut = reaper.ImGui_Checkbox(ctx, "Selection of cuts follow", settings.cursorFollowSelectedCut)
                if ret then
                    if settings.cursorFollowSelectedCut then
                        moveCursorToPos(cur_pos)
                    end
                
                    saveSettings()
                end
                setToolTipFunc("Playhead will jump to selected cut position.\n- press cmd/ctrl+p to set with keyboard")
                ]]
                
                
                
                reaper.ImGui_EndTabItem(ctx)
                
            end
            setToolTipFunc("Compare 2 videos cut with each other", "ctrl+2")
            
            local flags = selectTab(3)
            if reaper.ImGui_BeginTabItem(ctx, "Settings", nil, flags) then 
                updateTabSelection(3)
                
                settingButtons(itemProperties) 
                reaper.ImGui_EndTabItem(ctx) 
            end
            setToolTipFunc("Show app settings","ctrl+3")
            
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Tab(), colorTransparent)
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), colorTransparent)
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), colorTransparent)
            if reaper.ImGui_TabItemButton(ctx, "##EMPTY", flags)  then 
            end
            
            
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Tab(), theme.button)
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), theme.button_hover)
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), theme.button_active)
            
            
            if (isCtrlDown and is4) or reaper.ImGui_TabItemButton(ctx, (settings.showSettingsBoxes and "Hide" or "Show") .. " options")  then 
                settings.showSettingsBoxes = not settings.showSettingsBoxes
                saveSettings()
            end 
            setToolTipFunc("Show buttons for what to select in clip", "ctrl+4")
            
            reaper.ImGui_PopStyleColor(ctx, 6)
            
            
            
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
    
    
    
    if open then
        reaper.defer(loop)
    else
        reaper.atexit(exit)
    end
end


reaper.defer(loop)


