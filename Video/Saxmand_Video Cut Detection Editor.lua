-- @description Find and edit cuts in videos using an editor and precise cut detection
-- @author saxmand
-- @version 0.1.1
-- @provides
--   Helpers/*.lua
-- @changelog
--   + windows does not show popup exec window now when navigating cuts, but makes it a bit slower. It does however on analyzing and thumbnails generation. This can be disabled, but it will look like it freezes the app. 

-------- Possible IDEAS TODO
-- add option to keep old cut information (eg. color and name)
-- add waveform
-- randomize all colors
-- have multiple videos for cross reference (idea by soundfield)
-- option to only show thumbnails on cuts (work sterted, but did not work properly)


package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'
local script_path = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
package.path = package.path .. ";" .. script_path .. "Helpers/?.lua"
local json = require("json")

local is_windows = package.config:sub(1, 1) == "\\"
seperator = package.config:sub(1, 1) -- path separator: '/' on Unix, '\\' on Windows


local ctx -- = ImGui.CreateContext('Video cut detection editor')

font = ImGui.CreateFont('Arial', 14)
font1 = ImGui.CreateFont('Arial', 15)
font2 = ImGui.CreateFont('Arial', 17)
font10 = ImGui.CreateFont('Arial', 10)
font11 = ImGui.CreateFont('Arial', 11)
font12 = ImGui.CreateFont('Arial', 12)
font13 = ImGui.CreateFont('Arial', 13)
stateName = "Saxmand_VideoCutDetectionEditor"
FFmpegPathKey = "FFMPEG_PATH"


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
    border        = reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.28, 1.00),
    success       = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.70, 0.40, 1.00),
    warning       = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.60, 0.10, 1.00),
    error         = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.20, 0.20, 1.00),
}

-- Mappings to existing variables (to keep script logic working)
colorTransparent           = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
colorWhite                 = theme.text
colorGrey                  = theme.text_dim
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

local markerColors = { colorRed, colorOrange, colorYellow, colorGreen, colorCyan, colorBlue, colorIndigo, colorViolet,
    colorPink, colorGrey }

--------------------------------------------------------
------------------SETTINGS------------------------------
--------------------------------------------------------
function deepcopy(orig, copies)
    copies = copies or {}
    if type(orig) ~= 'table' then
        return orig
    elseif copies[orig] then
        return copies[orig] -- handle circular references
    end

    local copy = {}
    copies[orig] = copy
    for k, v in next, orig, nil do
        copy[deepcopy(k, copies)] = deepcopy(v, copies)
    end
    setmetatable(copy, deepcopy(getmetatable(orig), copies))
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
    showToolTip = true,
    analyseOnlyBetweenMarkers = false,
    overviewFollowsLoopSelection = true,
    arrangeviewFollowsOverview = false,
    defaultColor = colorBlue,
    onlyShowCutsWithEditedName = false,
    alwaysShowCutsWithEditedName = false,

    cursorFollowSelectedCut = false,

    timecodeRelativeToSession = false, -- not implemented
    useOldMacMethod = true,
    showAnalyzeBar = true,
    
}

local function saveSettings()
    local settingsStr = json.encodeToJson(settings)
    reaper.SetExtState(stateName, "settings", settingsStr, true)
end



if reaper.HasExtState(stateName, "settings") then
    local settingsStr = reaper.GetExtState(stateName, "settings")
    settings = json.decodeFromJson(settingsStr)
else
    settings = deepcopy(defaultSettings)
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


function setToolTipFunc(text, color)
    if settings.showToolTip and text and #tostring(text) > 0 then
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(), color and color or colorWhite)
        ImGui.SetItemTooltip(ctx, text)
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
end

function pulsatingColor(colorIn, speed)
    local time = reaper.time_precise() * (speed and speed or 6)
    local pulsate = (math.sin(time * 2) + 1) / 2 -- range: 0 to 1
    local alpha = math.floor(0x55 + (0xFF - 0x55) * pulsate)
    return colorIn & (0xFFFFFF00 + alpha)        -- combine alpha and RGB
end

--------------------------------------------------------
--------------------------------------------------------
--------------------------------------------------------






function getPngName(itemStart, name)
    name = name and (name .. ".png") or ('thumbnail' .. math.floor(itemStart * 1000000) .. '.png')
    return name
end

function Get_FFMpeg_Path_Iachinhan()
    local is_windows = package.config:sub(1, 1) == "\\"

    local function test_ffmpeg(test_path)
        local cmd
        if is_windows then
            -- Windows hack: Wrap the entire command in extra quotes to satisfy cmd /c parsing with multiple quotes
            cmd = '""' .. test_path .. '" -t 1.0 -f lavfi -i "color=black" -filter:v "scdet=t=3.0" -f null NUL"'
        else
            cmd = test_path .. " -t 1.0 -f lavfi -i 'color=black' -filter:v 'scdet=t=3.0' -f null /dev/null"
        end

        return os.execute(cmd)
    end

    local path = nil
    if reaper.HasExtState(stateName, FFmpegPathKey) then
        -- path = reaper.GetExtState(stateName, FFmpegPathKey) -- Let's re-read cleanly
        path = reaper.GetExtState(stateName, FFmpegPathKey)
    else
        local retval = reaper.MB(
        "FFMpeg is required for this action, find the path to your FFmpeg executable now or click Cancel.", "Detect Cuts",
            1)
        if retval == 1 then
            retval, path = reaper.GetUserFileNameForRead(is_windows and "" or "/usr/local/bin/", "Find FFMpeg executable", "")
            if retval then
                reaper.SetExtState(stateName, FFmpegPathKey, path, true)
                return Get_FFMpeg_Path() -- tail call
            end
        else
            return nil
        end
    end

    if test_ffmpeg(path) then
        return path
    else
        reaper.MB("Working FFMpeg could not be found at " .. path .. ".", "Detect Cuts Error", 0)
        reaper.DeleteExtState(stateName, FFmpegPathKey, true)
        return Get_FFMpeg_Path() -- tail call
    end
end

function Get_FFMpeg_Path()
    local is_windows = package.config:sub(1, 1) == "\\"

    local function test_ffmpeg(test_path)
        if not test_path then return false end
        local cmd = string.format('"%s" -version', test_path)
        local result = reaper.ExecProcess(cmd, 1000)
        if result and (result:find("ffmpeg version") or result:find("configuration:")) then
            return true
        end
        return false
    end

    local path = nil
    if reaper.HasExtState(stateName, FFmpegPathKey) then
        path = reaper.GetExtState(stateName, FFmpegPathKey)
    else
        local retval = reaper.MB("FFMpeg is required for this action. Find the path to your FFmpeg executable now or click Cancel.", "Detect Cuts", 1)
        if retval == 1 then
            retval, path = reaper.GetUserFileNameForRead(is_windows and "" or "/usr/local/bin/", "Find FFMpeg executable", "ffmpeg.exe")
            if retval then
                reaper.SetExtState(stateName, FFmpegPathKey, path, true)
                return Get_FFMpeg_Path()
            end
        else
            return nil
        end
    end

    if test_ffmpeg(path) then
        return path
    else
        reaper.MB("FFmpeg check failed.\nThe file at:\n" .. tostring(path) .. "\n\ndid not respond to '-version' command correctly.\nPlease check if the file is valid.", "Detect Cuts Error", 0)
        reaper.DeleteExtState(stateName, FFmpegPathKey, true)
        return Get_FFMpeg_Path()
    end
end

local ffmpeg_path = Get_FFMpeg_Path()
if ffmpeg_path == nil then return else ffmpeg_path = ffmpeg_path end

-- Initialize ImGui Context AFTER blocking calls (Get_FFMpeg_Path) to avoid context invalidation error
ctx = ImGui.CreateContext('Video cut detection editor')

function extract_cut_data_manual(cutTextFilePathRaw, start_time)
    local f = io.open(cutTextFilePathRaw)
    local file_lines = {}
    local i = 1
    start = false
    for line in f:lines() do
        if line:find("%[scdet") then
            -- Extract the values using pattern matching
            local score = tonumber(line:match("lavfi%.scd%.score: ([%d%.]+)"))
            local time = tonumber(line:match("lavfi%.scd%.time: ([%d%.]+)"))

            -- If both values are found, store them in the table
            if score and time then
                table.insert(file_lines, { score = score, time = time, color = settings.defaultColor })
            end
        end
    end
    f:close()

    return file_lines
end

function extract_cut_data_fast(cutTextFilePathRaw, start_time)
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
            entry.score = tonumber(score)
        end

        local time = line:match("lavfi%.scd%.time=(%S+)")
        if time then
            entry.time = tonumber(time) + start_time
        end
        -- Once we have all three, store and reset
        if entry.mafd and entry.score and entry.time then
            entry.color = settings.defaultColor
            table.insert(results, entry)
            entry = {}
        end
    end

    f:close()

    return results
end

fast = false

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
        '" -filter:v "scdet=t=1.000000:s=1,metadata=print:file=' .. cutTextFilePath .. '" -f null -'

    -- Define a temporary file path

    -- Use stdbuf to ensure line-buffered output
    local command = '"' .. ffmpeg_path .. '"' .. args   -- .. " > " .. '"' .. cutTextFilePath .. '"' --.. " 2>&1"

    reaper.CF_SetClipboard(command .. "\n")
    --reaper.ShowConsoleMsg(command)
    ffmpeg_read = reaper.ExecProcess(command, -1)
    aa = ffmpeg_read
    --end
end

function get_cut_information_Iachinhan(
    file_path,
    cutTextFilePath,
    start_time,
    length,
    detection_threshold
)
    detection_threshold = detection_threshold or 0.1
    local is_windows = package.config:sub(1, 1) == "\\"

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
        local cmd_content = '"' .. ffmpeg_path .. '" ' .. table.concat(args, " ") --.. ' 2> "' .. log_path .. '"'
        --reaper.CF_SetClipboard(cmd_content .. "\n")
        reaper.ExecProcess(cmd_content, -1)
    end

    -- Debug logs processing (optional, mainly for dev)
    -- local f = io.open(log_path, "r")
    -- if f then f:close() end

    -- Return based on file existence/size? Logic outside handles this.
    return true
end

local function sanitize_path_for_ffmpeg_filter(path)
    if not path then return "" end
    -- 1. Меняем обратные слеши на прямые
    path = path:gsub("\\", "/")
    -- 2. Экранируем двоеточие (C: становится C\:)
    -- В Lua 'gsub' символ % используется для экранирования, а не \.
    -- Строка заменяется на \:
    path = path:gsub(":", "\\:")
    return path
end


function cmdWindowsWrapper(cmd_ffmpeg)
    --local cmd_ffmpeg = cmd .. ' > "' .. log_path .. '" 2>&1'
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
end


function runExecProcess(command, forceAsync) 
    local is_windows = package.config:sub(1, 1) == "\\"
    if is_windows and not forceAsync then
        reaper.ExecProcess(command, 0)
    else 
        reaper.ExecProcess(command, -1)
    end 
end


function get_cut_information(file_path, cutTextFilePath, start_time, length, detection_threshold)
    detection_threshold = detection_threshold or 0.1
    os.remove(cutTextFilePath)

    -- Исправление путей для фильтра
    local safe_cut_path = sanitize_path_for_ffmpeg_filter(cutTextFilePath)
    
    -- Build FFmpeg arguments
    local args = {}
    
    table.insert(args, '"' .. ffmpeg_path .. '"') 
    
    table.insert(args, "-hide_banner")
    if start_time then table.insert(args, "-ss " .. string.format("%.6f", start_time)) end
    if length then table.insert(args, "-t " .. string.format("%.6f", length)) end

    table.insert(args, '-i "' .. file_path .. '"')
    
    -- ВАЖНО: Путь safe_cut_path содержит экранированное двоеточие (C\:)
    -- И мы оборачиваем его в одинарные кавычки
    table.insert(args, '-vf "select=gt(scene\\,' .. string.format("%.6f", detection_threshold) .. ")" ..  ',metadata=print:file=\'' .. safe_cut_path .. '\'"' )
    table.insert(args, "-f null -")

    local command = table.concat(args, " ")
    --reaper.CF_SetClipboard(command .. "\n")
    
    runExecProcess(command, settings.showAnalyzeBar)
    
    return true
end


function extract_cut_data(cutTextFilePathRaw, start_time)
    local f = io.open(cutTextFilePathRaw)
    if not f then return nil, "Could not open file" end
    local results = {}

    local entry = {}

    for line in f:lines() do

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
            entry.color = settings.defaultColor
            table.insert(results, entry)
            entry = {}
        end
    end

    f:close()

    return results
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


-- Global throttling variable
local last_thumb_time = 0

local function createThumbnails_new_slower_all_platforms(filePath, pngPath, itemStart, overwrite)
    -- Throttling to prevent potential load spam
    local now = reaper.time_precise()
    --if now - last_thumb_time < 0.2 then return false end
    last_thumb_time = now

    local is_windows = seperator == "\\"

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
            local work_dir, out_file = pngPath:match("(.*/)(.*)") -- this match needs forward slashes? No, we just converted.
            -- Regex for backslash is tricky. Let's use the one that worked before conversion or handle both.
            -- Actually, we just converted to backslashes.
            work_dir, out_file = pngPath:match("(.*\\)(.*)")

            if not work_dir then
                work_dir = ".\\"
                out_file = pngPath
            end

            -- Construct command: cmd /Q /C "cd /d "dir" & "ffmpeg" ... "outfile""
            local args = ' -ss ' .. string.format("%.6f", itemStart) .. ' -y -i "' .. filePath .. '" -frames:v 1 "' .. out_file .. '"'
            command = 'cmd.exe /Q /C "cd /d "' .. work_dir .. '" & "' .. ffmpeg_exec .. '"' .. args .. '" 2>&1'
        else
            -- Unix
            local args = ' -ss ' .. string.format("%.6f", itemStart) .. ' -y -i "' .. filePath .. '" -frames:v 1 "' .. pngPath .. '"'
            command = '"' .. ffmpeg_exec .. '"' .. args --.. -' 2>&1' 
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
    --reaper.ExecProcess(cmd, -1)
    
    runExecProcess(command, forceAsync)
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
    --if settings.useOldMacMethod and not is_windows then
        createThumbnails_mac(filePath, pngPath, itemStart, overwrite, background, forceAsync)
    --else
    --    createThumbnails_windows(filePath, pngPath, itemStart, overwrite)
    --end
end

function extract_thumbnail(video_path, time_seconds, output_path)
    local timecode = string.format("%02d:%02d:%04.1f",
        math.floor(time_seconds / 3600),
        math.floor((time_seconds % 3600) / 60),
        time_seconds % 60)

    local cmd = string.format(ffmpeg_path .. ' -ss %s -i "%s" -frames:v 1 -q:v 2 "%s"', timecode, video_path, output_path)
end

function generateThumbnailsForCuts(cut_data, cuts_making_threashold, directory, itemProperties)
    if not reaper.file_exists(directory) then
        reaper.RecursiveCreateDirectory(directory,0)
    end
    for _, c in ipairs(cuts_making_threashold) do 
        if not c.exclude then 
            cut = cut_data[c.index]
            if cut then 
                --pngPath = directory .. itemProperties.fileName .. "_Cut" .. c.index .. "_" .. math.floor(c.time * 1000 + 0.5) .. "ms.png" 
                createThumbnails(itemProperties.filePath, cut.pngPath, cut.time, nil, true, settings.showAnalyzeBar)
                createThumbnails(itemProperties.filePath, cut.pngPath_frame_before, cut.time_frame_before, nil, true, settings.showAnalyzeBar)
                --reaper.ShowConsoleMsg(pngPath .. "\n")
            end
        end
    end
    genratingThumbNails = true
end

function checkForGenerateThumbnails(cut_data, cuts_making_threashold) 
    local countGeneratedThumbNails = 0
    for _, c in ipairs(cuts_making_threashold) do 
        if not c.exclude then 
            cut = cut_data[c.index]
            if cut then  
                if reaper.file_exists(cut.pngPath) and reaper.file_exists(cut.pngPath_frame_before) then
                    countGeneratedThumbNails = countGeneratedThumbNails + 1
                end
            end
        end
    end
    if countGeneratedThumbNails == #cuts_making_threashold then 
        genratingThumbNails = false
    end
    return countGeneratedThumbNails
end


local function GetDirectoryFromPath(path)
  return path:match("^(.*)[/\\]")
end

function GetFilenameFromPath(path)
  if not path or path == "" then return nil end
  return path:match("([^/\\]+)$")
end
function GetFilenameNoExt(path)
  local filename = GetFilenameFromPath(path)
  if not filename then return nil end
  return filename:match("^(.*)%.")
end

function getVideoItemFilePath(item)
    if item then
        local take = reaper.GetActiveTake(item)
        if take then
            local source = reaper.GetMediaItemTake_Source(take)
            local source_type = reaper.GetMediaSourceType(source, "")

            if source_type == "VIDEO" then
                local filename = reaper.GetMediaSourceFileName(source, "")
                return filename
            else
                return nil
            end
        end
    else
        return nil
    end
end

function getItemProperties(item)
    -- Get selected media item
    if not item then
        --reaper.ShowMessageBox("No item selected", "Error", 0)
        return {}
    end

    -- Get item position in project
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")

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
            local take_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            -- Get media source
            local src = reaper.GetMediaItemTake_Source(take)
            local src_len = reaper.GetMediaSourceLength(source)

            return { filePath = filePath, directory = directory,fileName = fileName, item_pos = item_pos, take_offset = take_offset, item_length = src_len }
        else
            return {}
        end
    else
        return {}
    end
end

function getSelectedVideoFile()
    local item = reaper.GetSelectedMediaItem(0, 0)
end

function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
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

function file_exists_check(path)
    local f = io.open(path, "rb")
    if f then
        local size = f:seek("end")
        f:close()

        return size and size > 0
    end
    return false
end

function DirectoryExists(path)
  if not path or path == "" then return false end

  -- Try to enumerate subdirectories
  local subdir = reaper.EnumerateSubdirectories(path, 0)
  if subdir then return true end

  -- Try to enumerate files
  local file = reaper.EnumerateFiles(path, 0)
  if file then return true end

  return false
end

function compareWithMargin(a, b, marg)
    marg = marg or 100000000
    difference = (math.abs(a * marg - b * marg))
    if difference < 1 then
        --reaper.ShowConsoleMsg(difference .. " diff\n")
    end
    return difference < 1
end

function roundToFrame(time_pos_seconds)
    -- Get the project time position in seconds

    -- Get the current project's time base (frames per second)
    --frames_per_second = reaper.TimeMap_curFrameRate(0)

    -- Convert the time position to frames
    time_pos_frames = time_pos_seconds * frames_per_second

    -- Round the frame value
    rounded_frame = math.floor(time_pos_frames + 0.5)

    -- Convert the rounded frame value back to seconds
    local rounded_time_pos_seconds = rounded_frame / frames_per_second
    return rounded_time_pos_seconds
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

function readFile(filePath)
    local file = io.open(filePath, "r") -- "r" for read mode
    if not file then
        return nil
    end

    local content = file:read("*a") -- read entire file
    file:close()
    -- remove possible no index
    return content
end

------------------------------------------------------------
----------------------UNDO REDO-----------------------------
------------------------------------------------------------
local undo_stack = {}
local redo_stack = {}
function deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for key, value in next, orig, nil do
            copy[deep_copy(key)] = deep_copy(value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function save_undo(data)
    table.insert(undo_stack, deep_copy(data))
    redo_stack = {} -- clear redo stack on new change
end

function undo(data)
    if #undo_stack > 0 then
        table.insert(redo_stack, deep_copy(data))
        local prev = table.remove(undo_stack)
        return deep_copy(prev)
    end
    return data -- no change
end

function redo(data)
    if #redo_stack > 0 then
        table.insert(undo_stack, deep_copy(data))
        local next_state = table.remove(redo_stack)
        return deep_copy(next_state)
    end
    return data
end

------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
function GetFirstVisibleVideoItemUnder(cursor_pos)
    --local cursor_pos = reaper.GetCursorPosition()
    local track_count = reaper.CountTracks(0)

    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
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
                        local source_type = reaper.GetMediaSourceType(source, "")
                        if source_type == "VIDEO" or source_type == "VIDEOFF" or source_type == "MOV" or source_type == "MP4" then
                            -- Optional: check if the item is not hidden in video
                            local visible = reaper.GetMediaItemInfo_Value(item, "B_UISEL") -- or use a custom logic
                            return item, take, track
                        end
                    end
                end
            end
        end
    end

    return nil -- nothing found
end

function convertColorToReaper(track)
    local color = reaper.GetTrackColor(track)
    -- shift 0x00RRGGBB to 0xRRGGBB00 then add 0xFF for 100% opacity
    return color & 0x1000000 ~= 0 and (reaper.ImGui_ColorConvertNative(color) << 8) | 0xFF or colorTransparent
end

--- APP SPECIFIC FUNCTION
function setArrangeviewArea()
    if settings.arrangeviewFollowsOverview then
        if settings.analyseOnlyBetweenMarkers then
            reaper.Main_OnCommand(40031, 0) --View: Zoom time selection
        else
            local item = GetFirstVisibleVideoItemUnder(cur_pos)
            if item then
                local itemProperties = getItemProperties(item)
                local item_pos = itemProperties.item_pos
                local item_offset = itemProperties.take_offset
                local item_length = itemProperties.item_length
                local item_end = item_pos + item_length
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
    if isSuperDown or settings.cursorFollowSelectedCut then
        if playState ~= 0 then
            reaper.Main_OnCommand(1016, 0) --Transport: Stop
        end
        reaper.SetEditCurPos(pos, true, false)
        if playState ~= 0 then
            reaper.Main_OnCommand(1007, 0) --Transport: Play
        end
    end
end

--local cut_data
local showVideo = false
--local thumbnailPath
--local fps = reaper.TimeMap_curFrameRate(0)  -- returns frames per second

frames_per_second = reaper.TimeMap_curFrameRate(0)
local wait = nil
local run = 0
default_threshold = 1
local margin = 4

local old_cut_data = {}
local cut_data = {}
local cuts_making_threashold = {}
local minSizeW = 220 * 4 + 8

local function exit()
    -- clean up generated images
    os.remove(pngPathA)
    os.remove(pngPathB)
end

local function loop()
    if lastPosY and (winH and lastPosY ~= winH or winW < minSizeW) then
        if winW < minSizeW then
            winW = minSizeW
        end
        reaper.ImGui_SetNextWindowSize(ctx, winW, lastPosY)
    end


    local time = reaper.time_precise()

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
    
    local buttonSize = 25

    colCount = 1
    varCount = 1

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
        local timeLineW = winW - 8 * 2      -- (imageW * (16/9)) * 2 + 8 --

        -- ImGui.PushFont(ctx, font)
        isMouseDown = ImGui.IsMouseDown(ctx, 0)
        isMouseClick = ImGui.IsMouseClicked(ctx, 0)

        isShiftDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
        isCtrlDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Super)
        isSuperDown = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
        isLeftArrowReleased = reaper.ImGui_IsKeyPressed(ctx, ImGui.Key_LeftArrow, false)
        isRightArrowReleased = reaper.ImGui_IsKeyPressed(ctx, ImGui.Key_RightArrow, false)
        
        local alphabet = {"Space", "Backspace", "Escape", "Enter", "Tab", "LeftArrow", "RightArrow", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "Y", "Z", "X", "KeypadAdd", "KeypadSubtract"}
        for _, letter in ipairs(alphabet) do
            _G["is" .. letter] = ImGui.IsKeyPressed(ctx, ImGui["Key_" .. letter])
        end
        
        
        
        posX2 = 220
        posX3 = posX2 + posX2
        posX4 = posX3 + posX2


        scrollVertical, scrollHorizontal = ImGui.GetMouseWheel(ctx)

        if not markerNameIsFocused then
            if isSpace then 
                local saxmandPlay = reaper.NamedCommandLookup("_RS63a69d4a35c6351d50b130cb5f9285c582ea5089")
                if saxmandPlay ~= 0 then 
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS63a69d4a35c6351d50b130cb5f9285c582ea5089"), 0) --Script: Saxmand, Transport Play:Stop (Return cursor to start point).lua
                else
                    reaper.Main_OnCommand(40328, 0) --Transport: Play/stop (move edit cursor on stop)
                end
            end
        end



        mouse_pos_x, mouse_pos_y = reaper.ImGui_GetMousePos(ctx)
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        --reaper.ImGui_Text(ctx, "Video cut detection")

        playState = reaper.GetPlayState()
        isPlaying = playState ~= 0
        if not isPlaying then
            timeline_cur_pos = reaper.GetCursorPosition()
            if not last_timeline_cur_pos_edit or last_timeline_cur_pos_edit ~= timeline_cur_pos then
                last_cur_pos = nil
            end
            last_timeline_cur_pos_edit = timeline_cur_pos
        else
            timeline_cur_pos = reaper.GetPlayPosition()
        end

        if not last_cur_pos then --or settings.cursorFollowSelectedCut then
            cur_pos = timeline_cur_pos
        end

        local start_time_sel, end_time_sel = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

        run = run + 1
        local item = GetFirstVisibleVideoItemUnder(settings.analyseOnlyBetweenMarkers and
        (start_time_sel + (end_time_sel - start_time_sel) / 2) or cur_pos)   --reaper.GetSelectedMediaItem(0, 0)
        if not item then
            -- item = {}
            last_cur_pos = nil
        end
        if item and not last_item or last_item ~= item then
            last_cur_pos = nil
            last_cur_pos_in_item = nil
            wait = false
            last_item = item
            cut_data = nil
            undo_stack = {}
            redo_stack = {}
            frames_per_second = reaper.TimeMap_curFrameRate(0)
        end

        --if item then
        itemProperties = getItemProperties(item)
        filePath = itemProperties.filePath or ""
        local base = filePath:match("(.+)%.[^%.]+$") or ""
        cutTextFilePathRaw = base .. "_cutsRaw.txt"  
        cutTextFilePath = base .. "_cuts.txt"  
        
        thumbnailPath = base .. seperator
        thumbnailPath_exist = DirectoryExists(thumbnailPath)
        
        
        
        item_pos = itemProperties.item_pos or 0
        item_offset = itemProperties.take_offset or 0
        item_length = itemProperties.item_length or 0
        item_end = item_pos + item_length

        local start_time_in_item = start_time_sel - item_pos + item_offset
        local end_time_in_item = end_time_sel - item_pos + item_offset

        overview_start_in_item = 0
        overview_length_in_item = item_length
        if settings.analyseOnlyBetweenMarkers then
            overview_start_in_item = start_time_in_item
            overview_length_in_item = end_time_in_item - start_time_in_item
        elseif settings.overviewFollowsArrangeview then
            local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0)
            overview_start_in_item = start_time - item_pos + item_offset
            overview_length_in_item = end_time - start_time + item_offset
        end

        item_area_to_analyze_start = overview_start_in_item < 0 and 0 or overview_start_in_item
        item_area_to_analyze_length = overview_length_in_item > item_length and item_length or overview_length_in_item

        cur_pos_in_item = (item_pos and cur_pos - item_pos + item_offset or 0)                     --+ overview_start_in_item

        timeline_cur_pos_in_item = (item_pos and timeline_cur_pos - item_pos + item_offset or 0)   --+ overview_start_in_item

        outsideBoundries = cur_pos_in_item > overview_start_in_item + overview_length_in_item or
        cur_pos_in_item < overview_start_in_item

        outsideBoundries = cur_pos_in_item > overview_start_in_item + overview_length_in_item or
        cur_pos_in_item < overview_start_in_item

        function updateCutDataFile(cutTextFilePath, cut_data)
            saveFile(cutTextFilePath, json.encodeToJson(cut_data))
        end
        
        

        local analysingColor = analysing and pulsatingColor(colorBlue, 6) or  theme.button
        local generatingColor = genratingThumbNails and pulsatingColor(colorBlue, 6) or  theme.button
        
        
        function appButtons()
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), analysingColor)
            
            if reaper.ImGui_Button(ctx, reaper.file_exists(cutTextFilePath) and (analysing and "Analyzing video, please wait. Click to cancel" or "Re-analyze video") or "Analyze video") then
                if analysing then
                    os.remove(cutTextFilePathRaw)
                else
                    os.remove(cutTextFilePath)
                    if not isSuperDown and cut_data and #cut_data > 0 then
                        old_cut_data = deep_copy(cut_data)
                    end
                    cut_data = {}
                    analyseStartTime = time
                    if fast then
                        get_cut_information_fast(filePath, cutTextFilePathRaw, item_area_to_analyze_start,
                            item_area_to_analyze_length)
                    else
                        get_cut_information(filePath, cutTextFilePathRaw, item_area_to_analyze_start, item_area_to_analyze_length)
                    end
                    --if reaper.file_exists(cutTextFilePath) then
                    --    cut_data = extract_cut_data(cutTextFilePath)
                    --    updateCutDataFile(cutTextFilePath, cut_data)
                    --end
                end
            end
            reaper.ImGui_PopStyleColor(ctx)

            setToolTipFunc("Click to analyze cut. Press escape on keyboard to stop analyzing")

            if analysing and isEscape then
                os.remove(cutTextFilePathRaw)
                analyseStartTime = nil
            end
            
            local generateName = "Generate Thumbnails"
            local nameW = reaper.ImGui_CalcTextSize(ctx, generateName, 0, 0) 
            if genratingThumbNails then  
                countGeneratedThumbNails = checkForGenerateThumbnails(cut_data, cuts_making_threashold)
                generateName = "Generating: " .. countGeneratedThumbNails .. "/" .. #cuts_making_threashold
            end
             
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), generatingColor) 
            --reaper.ImGui_SameLine(ctx)
            
            reaper.ImGui_SameLine(ctx)
            local posX = reaper.ImGui_GetCursorPosX(ctx)
            if reaper.ImGui_Button(ctx, generateName) then
                generateThumbnailsForCuts(cut_data, cuts_making_threashold, thumbnailPath, itemProperties)
            end
            setToolTipFunc("Click to generate cut thumbnails to get instant navigation")
             
            reaper.ImGui_PopStyleColor(ctx)
            
            
            --reaper.ImGui_SameLine(ctx, posX + nameW + 24)
            
            
            reaper.ImGui_SameLine(ctx, winW - 50) 
            if reaper.ImGui_Button(ctx, "Extra") then
                reaper.ImGui_OpenPopup(ctx, "extra")
            end
            
            if reaper.ImGui_BeginPopup(ctx, "extra") then 
                
                --[[
                ret, settings.onlyShowThumbnailsForCuts = reaper.ImGui_Checkbox(ctx, "Only show thumbnails for cuts", settings.onlyShowThumbnailsForCuts)
                if ret then 
                    saveSettings()
                end
                setToolTipFunc("Only show thumbnails for cuts is useful if you don't want thumbnail creation when the playhead is not on a cut")
                ]]
                
                if not thumbnailPath_exist then reaper.ImGui_BeginDisabled(ctx) end
                if reaper.ImGui_Button(ctx, "Remove thumbnails") then
                    
                    local count = 0
                    local filePath = reaper.EnumerateFiles(thumbnailPath,count)
                    while filePath do
                        os.remove(thumbnailPath .. filePath)
                        count = count + 1
                        filePath = reaper.EnumerateFiles(thumbnailPath,count)
                    end
                    os.remove(thumbnailPath)
                end
                setToolTipFunc("Click to remove generated thumbnails and the thumbnail folder.")
                if not thumbnailPath_exist then reaper.ImGui_EndDisabled(ctx) end
                
                if reaper.ImGui_Button(ctx, "Open video path") then
                    reaper.CF_ShellExecute(itemProperties.directory)
                end
                setToolTipFunc("Click to remove generated thumbnails and the thumbnail folder.")
                
                if is_windows then 
                    ret, settings.showAnalyzeBar = reaper.ImGui_Checkbox(ctx, "Show analyze bar", settings.showAnalyzeBar)
                    if ret then 
                        saveSettings()
                    end
                    setToolTipFunc("Windows only. In order to show the analyze bar we need to show the popup exec window, to make the process async") 
                end
                
                if reaper.ImGui_Button(ctx, "Reset analyze speed") then
                    settings.analyzeSpeed = nil
                    saveSettings()
                end
                setToolTipFunc("Click to reset the analyze speed. " .. (settings.analyzeSpeed and ("The current speed is: " ..  string.format("%.4f", settings.analyzeSpeed)) or "No speed measured. Analyze to set this"))
                
                if reaper.ImGui_Button(ctx, "Reset FFMPEG Path") then
                    reaper.DeleteExtState(stateName, FFmpegPathKey, true)
                    reaper.MB("FFMPEG path has been reset. Please restart the script to select a new path.", "Reset Path", 0)
                end
                setToolTipFunc("Click to reset FFMPEG path if you selected the wrong one or moved the file.")
                
                reaper.ImGui_EndPopup(ctx)
            end
        end
        
        appButtons()
        
        function settingsCheckBoxes()
            --if start_time_sel ~= end_time_sel and start_time_sel < end_time_sel then
            --reaper.ImGui_SameLine(ctx)
            ret, settings.analyseOnlyBetweenMarkers = reaper.ImGui_Checkbox(ctx, "use area within time selection",
                settings.analyseOnlyBetweenMarkers)
            if ret then
                setArrangeviewArea()
                saveSettings()
            end
            setToolTipFunc("Only show area within reaper time selection.\n- press cmd/ctrl+w to set with keyboard")
            --end

            if (not markerNameIsFocused or isSuperDown) and isU then
                settings.analyseOnlyBetweenMarkers = not settings.analyseOnlyBetweenMarkers
                setArrangeviewArea()
                saveSettings()
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
                end
                setToolTipFunc("Link arrange view with the editor view.\n- press cmd/ctrl+l to set with keyboard")

                if (not markerNameIsFocused or isSuperDown) and isL then
                    settings.arrangeviewFollowsOverview = not settings.arrangeviewFollowsOverview
                    saveSettings()
                    setArrangeviewArea()
                end
            else
                ret, settings.overviewFollowsArrangeview = reaper.ImGui_Checkbox(ctx, "link overview to arrange view",
                    settings.overviewFollowsArrangeview)
                if ret then
                    --setArrangeviewArea()
                    saveSettings()
                end
                setToolTipFunc("Link arrange view to width of selection.\n- press cmd/ctrl+l to set with keyboard")

                if (not markerNameIsFocused or isSuperDown) and isL then
                    settings.overviewFollowsArrangeview = not settings.overviewFollowsArrangeview
                    saveSettings()
                    --setArrangeviewArea()
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
            ret, settings.navigationFollowsPlayhead = reaper.ImGui_Checkbox(ctx, "selection follows playhead",
                settings.navigationFollowsPlayhead)
            if ret then
                saveSettings()
            end
            setToolTipFunc("Select cut marker when playhead passes.\n- press cmd/ctrl+s to set with keyboard")

            if (not markerNameIsFocused or isSuperDown) and isS then
                settings.navigationFollowsPlayhead = not settings.navigationFollowsPlayhead
                saveSettings()
            end




            if analysing and analyseEndTime and analyseStartTime then
                -- 0.025 is a magic number. We could possibly get real analyze progress by saving progress from FFMPEG
                local analyzeSpeed = settings.analyzeSpeed and settings.analyzeSpeed or 0.1
                analysingAmount = (analyseEndTime - analyseStartTime) / item_area_to_analyze_length / analyzeSpeed 
                if analysingAmount > 1 then analysingAmount = 1 end
            end


            --reaper.ImGui_SameLine(ctx)
            
        end
        
        
        reaper.ImGui_Separator(ctx)
        
        settingsCheckBoxes()


        analyseRaw = reaper.file_exists(cutTextFilePathRaw)
        analysing = false
        if analyseRaw then
            if not cut_data or #cut_data == 0 then
                if fast then
                    cut_data = extract_cut_data_fast(cutTextFilePathRaw, item_area_to_analyze_start)
                else
                    cut_data = extract_cut_data(cutTextFilePathRaw, item_area_to_analyze_start)
                end
                analysing = true
                analyseEndTime = time
                --
                --
                if #cut_data > 0 then
                    analysing = false
                    os.remove(cutTextFilePathRaw)
                    local new_cuts_start = item_area_to_analyze_start
                    local new_cuts_length = item_area_to_analyze_length
                    local new_cuts_end = new_cuts_start + new_cuts_length
                    --table.insert(cut_data, 1, {time = overview_start_in_item, special = "start"})
                    table.insert(cut_data, 1, { time = new_cuts_start, special = "start" })
                    --table.insert(cut_data, {time = overview_start_in_item + overview_length_in_item, special = "end"})
                    table.insert(cut_data, { time = new_cuts_end, special = "end" })

                    if old_cut_data and #old_cut_data > 0 then
                        local analyseAreaStarted, newAreaStarted
                        local new_cut_data_table = {}
                        local newTableAdded = false

                        if new_cuts_start <= old_cut_data[1].time then
                            new_cut_data_table = cut_data
                            newTableAdded = true
                        end

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
                                    for _, tn in ipairs(cut_data) do
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
                            for _, tn in ipairs(cut_data) do
                                table.insert(new_cut_data_table, tn)
                            end
                        end

                        old_cut_data = {}
                        cut_data = deep_copy(new_cut_data_table)
                    end

                    updateCutDataFile(cutTextFilePath, cut_data)
                end
            end
        end
        analysisMade = reaper.file_exists(cutTextFilePath)
        if not cut_data and not analysing then
            if analysisMade then
                cut_data = json.decodeFromJson(readFile(cutTextFilePath))
                
            else
                cut_data = {}
            end
        end
        
        if cut_data and #cut_data > 0 then 
            if analyseEndTime and analyseStartTime then 
                analyzeSpeed = (analyseEndTime - analyseStartTime) / item_area_to_analyze_length
                settings.analyzeSpeed = ((settings.analyzeSpeed and settings.analyzeSpeed or analyzeSpeed) + analyzeSpeed) / 2
                saveSettings()
                analyseStartTime = nil
            end
        end


        function cutColors(currentSelectedCut)
            -- COLORS
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorWhite)

            for i, col in ipairs(markerColors) do
                if i > 1 then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) - 6)
                end

                colSelected = currentSelectedCut and
                (cut_data[currentSelectedCut].color and cut_data[currentSelectedCut].color or colorGrey) or nil
                local colIsSelected = col == colSelected

                colButton = not colIsSelected and col & 0xFFFFFFFF55 or col


                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colButton)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colButton)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colButton)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colIsSelected and colorWhite or colorDarkGrey)
                local keyNumber = (i < 10 and i or 0)
                local key = reaper["ImGui_Key_" .. keyNumber]
                if reaper.ImGui_Button(ctx, "##markerColor" .. i, buttonSize, buttonSize) or (currentSelectedCut and (not markerNameIsFocused or isSuperDown) and reaper.ImGui_IsKeyPressed(ctx, key())) then
                    if isShiftDown or not currentSelectedCut then
                        save_undo(cut_data)
                        for _, c in ipairs(cuts_making_threashold) do
                            cut_data[c.index].color = col
                        end
                        updateCutDataFile(cutTextFilePath, cut_data)
                        --settings.defaultColor = col
                        saveSettings()
                    else
                        if not cut_data[currentSelectedCut].color or cut_data[currentSelectedCut].color ~= col then
                            save_undo(cut_data)
                            cut_data[currentSelectedCut].color = col
                            updateCutDataFile(cutTextFilePath, cut_data)
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

            if reaper.ImGui_Button(ctx, "C", buttonSize, buttonSize) or (currentSelectedCut and (not markerNameIsFocused or isSuperDown) and isC) then
                if isShiftDown or not currentSelectedCut then
                    save_undo(cut_data)
                    for i, c in ipairs(cuts_making_threashold) do
                        cut_data[c.index].color = markerColors[((i - 1) % (#markerColors - 1)) + 1]
                    end
                    updateCutDataFile(cutTextFilePath, cut_data)
                    --settings.defaultColor = col
                    saveSettings()
                else
                    if not cut_data[currentSelectedCut].color or cut_data[currentSelectedCut].color ~= col then
                        save_undo(cut_data)
                        cut_data[currentSelectedCut].color = getNextColor(cut_data[currentSelectedCut].color)
                        updateCutDataFile(cutTextFilePath, cut_data)
                    end
                end
            end
            setToolTipFunc(
            "Set cut to next color.\n- press cmd/ctrl+c to set with keyboard\n- hold shift to set all markers")
        end

        if analysing then reaper.ImGui_BeginDisabled(ctx) end
        if not analysisMade then reaper.ImGui_BeginDisabled(ctx) end

        --if item then
        if not last_cur_pos then
            updateThumbnails = true
        else
            updateThumbnails = not last_cur_pos or last_cur_pos == cur_pos
            updateThumbnails = updateThumbnails and (not last_item_pos or last_item_pos == item_pos)
            updateThumbnails = updateThumbnails and (not last_item_offset or last_item_offset == item_offset)
        end
        last_item_pos = item_pos
        last_cur_pos = cur_pos
        last_item_offset = item_offset

        
        cut_data_time_pos = {} 
        --if thumbnailPath_exist then 
            for i, cutInfo in pairs(cut_data) do
                local time_seconds_rounded = roundToFrame(cutInfo.time)
                local pngPath = thumbnailPath .. itemProperties.fileName .. "_" .. math.floor(time_seconds_rounded * 1000 + 0.5) .. "ms.png" 
                cut_data[i].pngPath = pngPath
                
                local oneFrameEarlier = time_seconds_rounded - (1 / frames_per_second)  
                local pngPath_frame_before = thumbnailPath .. itemProperties.fileName .. "_" .. math.floor(oneFrameEarlier * 1000 + 0.5) .. "ms.png" 
                cut_data[i].pngPath_frame_before = pngPath_frame_before
                cut_data[i].time_frame_before = oneFrameEarlier 
                --reaper.ShowConsoleMsg(time_seconds_rounded .. " - " .. oneFrameEarlier .. "\n")
                cut_data_time_pos[time_seconds_rounded] = pngPath
                cut_data_time_pos[oneFrameEarlier] = pngPath_frame_before
            end
        --end


        cuts_making_threashold = {}
        for i, cutInfo in pairs(cut_data) do
            --local cut = {}
            -- reaper.SetEditCurPos(time+position, false, false)
            -- reaper.Main_OnCommandEx(40012,0,0)
            -- SPLIT: 40012
            if settings.alwaysShowCutsWithEditedName and cutInfo.name or (not settings.onlyShowCutsWithEditedName and cutInfo.score and cutInfo.score <= settings.threshold and cutInfo.time >= overview_start_in_item and cutInfo.time <= overview_start_in_item + overview_length_in_item) or (settings.onlyShowCutsWithEditedName and cutInfo.name) then
                time = cutInfo.time

                --itemEnd = roundToFrame(time + videoStart)

                --if default_insideTime == 0 or itemStart >= start_time_sel and itemStart < end_time_sel then
                local exclude = cutInfo.exclude and cutInfo.exclude or false 
                table.insert(cuts_making_threashold, { index = i, time = time, exclude = exclude, pngPath = pngPath }) --,itemEnd=itemEnd, videoStartOffset = videoStartOffset})
                --if default_createThumbnails == 1 then
                -- createThumbnails(videoStartOffset)
                --end
                --reaper.AddProjectMarker(0, false, time + position, 0., "Cut: " .. line, n)
                --itemStart = itemEnd
                --videoStartOffset = roundToFrame(time + start_offset)
                --end
            end
        end

        --currentSelectedCut = currentSelectedCut and currentSelectedCut or lastSelectedCut
        --currentSelectedCutInThreshold = currentSelectedCutInThreshold and currentSelectedCutInThreshold or lastSelectedCutInThreshold
        local currentSelectedCut
        local currentSelectedCutInThreshold

        if not settings.navigationFollowsPlayhead or not isPlaying then
            for i, c in ipairs(cuts_making_threashold) do
                --reaper.ShowConsoleMsg(cur_pos_to_check
                if compareWithMargin(c.time, cur_pos_in_item) then
                    currentSelectedCut = c.index
                    currentSelectedCutInThreshold = i
                    break;
                end
            end
        end


        if settings.navigationFollowsPlayhead and isPlaying then
            local fpsMargin = (10 / frames_per_second)
            currentSelectedCut = currentSelectedCut and currentSelectedCut or lastSelectedCut
            currentSelectedCutInThreshold = currentSelectedCutInThreshold and currentSelectedCutInThreshold or lastSelectedCutInThreshold
            for i, c in ipairs(cuts_making_threashold) do
                if c.time - fpsMargin / frames_per_second < timeline_cur_pos_in_item and c.time + fpsMargin / frames_per_second > timeline_cur_pos_in_item then
                    currentSelectedCut = c.index
                    currentSelectedCutInThreshold = i
                    cur_pos_in_item = c.time
                    last_cur_pos = cur_pos_in_item - item_pos + item_offset
                    --cur_pos = cur_pos_in_item - item_pos + item_offset
                    cur_pos = cur_pos_in_item + item_pos - item_offset

                    lastSelectedCut = currentSelectedCut
                    lastSelectedCutInThreshold = currentSelectedCutInThreshold
                    break;
                end
            end
        end
        --end

        --[[
              reaper.ImGui_AlignTextToFramePadding(ctx)
              reaper.ImGui_Text(ctx, "Window size:")
              reaper.ImGui_SameLine(ctx)
              reaper.ImGui_SetNextItemWidth(ctx, 100)
              ret, val = reaper.ImGui_SliderInt(ctx, "##Image size", settings.windowSize, 100, 1000, nil, reaper.ImGui_SliderFlags_NoInput())
              if ret then
                  settings.windowSize = val
                  saveSettings()
              end
              setToolTipFunc("Set the sensitivity for likely there is a cut")
              ]]




        if not analysisMade then reaper.ImGui_EndDisabled(ctx) end



        --[[

              if not markerNameIsFocused and isShiftDown then
                  if isLeftArrow then
                      move_cursor_by_frames(-1)
                      --cur_pos_in_item = timeline_cur_pos_in_item
                      --currentSelectedCut = nil
                      --currentSelectedCutInThreshold = nil
                  elseif isRightArrow then
                      move_cursor_by_frames(1)
                      --cur_pos_in_item = timeline_cur_pos_in_item
                      --currentSelectedCut = nil
                      --currentSelectedCutInThreshold = nil
                  end
              end
              ]]

        --reaper.ImGui_PushFont(ctx, font2)
        -- NAVIGATION

        
        
        if not analysisMade then reaper.ImGui_BeginDisabled(ctx) end
        
        --reaper.ImGui_AlignTextToFramePadding(ctx)
        --reaper.ImGui_Text(ctx, "Sensitivity:")
        --reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 120)
        ret, val = reaper.ImGui_SliderInt(ctx, "##Cut threshold", settings.threshold, 1, 100, nil,
            reaper.ImGui_SliderFlags_NoInput())
        if ret then
            settings.threshold = val
            saveSettings()
        end
        setToolTipFunc("Set the sensitivity for how likely there is a cut.\n- press cmd/ctrl+keypad plus or keypad minus to set with keyboard")
        
        if isKeypadAdd then
            local newVal = settings.threshold + 1
            if newVal > 100 then newVal = 100 end
            settings.threshold = newVal
            saveSettings()
        end
        
        if isKeypadSubtract then
            local newVal = settings.threshold - 1
            if newVal < 1 then newVal = 1 end
            settings.threshold = newVal
            saveSettings()
        end
        
        if not analysing then 
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "(" .. #cuts_making_threashold .. " cuts shown out of " .. #cut_data - 2 .. " detected)")
        end
        
        if not analysisMade then reaper.ImGui_EndDisabled(ctx) end
        
        
        reaper.ImGui_SameLine(ctx, posX3)
        ret, settings.onlyShowCutsWithEditedName = reaper.ImGui_Checkbox(ctx, "only show cuts with edited name", settings.onlyShowCutsWithEditedName)
        if ret then
            setArrangeviewArea()
            saveSettings()
        end
        setToolTipFunc("Hide cuts that does not have an edited name.\n- press cmd/ctrl+o to set with keyboard")

        if (not markerNameIsFocused or isSuperDown) and isO then
            settings.onlyShowCutsWithEditedName = not settings.onlyShowCutsWithEditedName
            saveSettings()
        end


        reaper.ImGui_SameLine(ctx, posX4)
        ret, settings.alwaysShowCutsWithEditedName = reaper.ImGui_Checkbox(ctx, "always show cuts with edited name", settings.alwaysShowCutsWithEditedName)
        if ret then
            setArrangeviewArea()
            saveSettings()
        end

        setToolTipFunc( "Show cuts that have an edited name, even if they are outside threshold.\n- press cmd/ctrl+n/t to set with keyboard")

        if not markerNameIsFocused and isA or ((not markerNameIsFocused or isSuperDown) and isT) then
            settings.alwaysShowCutsWithEditedName = not settings.alwaysShowCutsWithEditedName
            saveSettings()
        end
        
        reaper.ImGui_Separator(ctx)

        --reaper.ImGui_SameLine(ctx)

        if not currentSelectedCut then reaper.ImGui_BeginDisabled(ctx) end
        
        local addRemoveMarkerButtonWidth = currentSelectedCut and 64 or 86
        cutColors(currentSelectedCut)
        
            reaper.ImGui_SameLine(ctx)
            local markerName = currentSelectedCut and (cut_data[currentSelectedCut].name and cut_data[currentSelectedCut].name or "Cut " .. currentSelectedCutInThreshold) or ""


            --reaper.ImGui_AlignTextToFramePadding(ctx)
            --reaper.ImGui_Text(ctx, "Name:")
            --reaper.ImGui_SameLine(ctx)


            reaper.ImGui_SetNextItemWidth(ctx, posX4 - reaper.ImGui_GetCursorPosX(ctx) - 4 - addRemoveMarkerButtonWidth)
            if isEnter and not markerNameIsFocused then
                reaper.ImGui_SetKeyboardFocusHere(ctx)
            end
            colSelected = currentSelectedCut and (cut_data[currentSelectedCut].color and cut_data[currentSelectedCut].color or colorGrey) or colorBlue
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), colSelected)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), GetTextColorForBackground(colSelected))
            ret, markerTextInput = reaper.ImGui_InputText(ctx, "##Marker name", markerName,
                reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll() |
                reaper.ImGui_InputTextFlags_NoUndoRedo())
            local newName = false

            reaper.ImGui_PopStyleColor(ctx, 2)

            markerNameIsFocused = reaper.ImGui_IsItemFocused(ctx)

            setToolTipFunc("Set marker name.\n- press enter to focus area, press enter again to select next marker")

            if ret and isEnter then
                if markerTextInput ~= markerName then
                    save_undo(cut_data)
                    cut_data[currentSelectedCut].name = markerTextInput
                    updateCutDataFile(cutTextFilePath, cut_data)
                end
                if isSuperDown then
                    reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
                else
                    focusNavigation = true
                end
                findNextCut()
            end

            if markerNameIsFocused and (isTab or isEscape) then
                focusNavigation = true
            end
            
        if not currentSelectedCut then reaper.ImGui_EndDisabled(ctx) end

            
        if currentSelectedCut then
            reaper.ImGui_SameLine(ctx, posX4 -addRemoveMarkerButtonWidth)
            if reaper.ImGui_Button(ctx, "Remove") or ((not markerNameIsFocused or isSuperDown) and isR) then
                save_undo(cut_data)
                table.remove(cut_data, currentSelectedCut)
                updateCutDataFile(cutTextFilePath, cut_data)
                findNextCut()
            end

            setToolTipFunc("Remove detected cut from timeline.\n- press cmd/ctrl+r to set with keyboard")
        else
            if not cursorOutsideArea then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Add marker") or ((not markerNameIsFocused or isSuperDown) and isM) then
                    local markerIndex = 0
                    for i, c in ipairs(cut_data) do
                        if c.time > cur_pos_in_item then
                            markerIndex = i
                            break
                        end
                    end
                    save_undo(cut_data)
                    table.insert(cut_data, markerIndex, { score = 1, time = cur_pos_in_item })
                    updateCutDataFile(cutTextFilePath, cut_data)
                end

                setToolTipFunc("Add a cut to the timeline.\n- press cmd/ctrl+m to set with keyboard")
            else
                last_cur_pos = nil
            end
        end
        
        
        if not currentSelectedCut then reaper.ImGui_BeginDisabled(ctx) end
        reaper.ImGui_SameLine(ctx, posX4)
        local isNotSelected = currentSelectedCut and cut_data[currentSelectedCut].exclude
        if reaper.ImGui_Checkbox(ctx, "Include", not isNotSelected) or (currentSelectedCut and (not markerNameIsFocused or isSuperDown) and isI) then
            save_undo(cut_data)
            cut_data[currentSelectedCut].exclude = not cut_data[currentSelectedCut].exclude
            updateCutDataFile(cutTextFilePath, cut_data)
        end
        
        setToolTipFunc( "Include marker in export. This way you can still show it but not include it.\n- press cmd/ctrl+i to set with keyboard")
        
        if not currentSelectedCut then reaper.ImGui_EndDisabled(ctx) end



        --reaper.ImGui_SameLine(ctx)

        --reaper.ImGui_SameLine(ctx)

        if focusNavigation then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            focusNavigation = false
        end

        function findPreviousCut()
            for i = #cuts_making_threashold, 1, -1 do
                c = cuts_making_threashold[i]
                if c.time + 0.1 / frames_per_second < cur_pos_in_item then
                    cur_pos = c.time + item_pos - item_offset
                    moveCursorToPos(cur_pos)
                    return true
                end
            end
        end
        
        function findNextCut()
            for _, c in ipairs(cuts_making_threashold) do
                if c.time - 0.1 / frames_per_second > cur_pos_in_item then
                    cur_pos = c.time + item_pos - item_offset
                    moveCursorToPos(cur_pos)
                    return true
                end
            end
        end
        
        function findNextSpecialEnd(startPos)
            for _, c in ipairs(cut_data) do
                if c.special == "end" and (not startPos or (startPos < c.time)) then
                    if c.time < overview_start_in_item + overview_length_in_item then
                        return c.time
                    else
                        return overview_start_in_item + overview_length_in_item
                    end
                end
            end
            return overview_start_in_item + overview_length_in_item
        end
        
        

        --reaper.ImGui_SameLine(ctx)
        --reaper.ImGui_AlignTextToFramePadding(ctx)
        --reaper.ImGui_TextColored(ctx, colorGrey, "(ITEM | " .. reaper.format_timestr_pos(cur_pos_in_item, "", 5) .. " - SESSION | " .. reaper.format_timestr_pos(cur_pos, "", 5) .. ")")


        -- OVERVIEW AREA

        reaper.ImGui_InvisibleButton(ctx, "CutsOverview", timeLineW, 30)
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
        local w, h = reaper.ImGui_GetItemRectSize(ctx)


        reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, markerNameIsFocused and colorGrey or colorWhite,
            0, nil, 1)
        minX = minX + 1
        minY = minY + margin
        maxX = maxX - 2
        maxY = maxY - margin
        w = w - 3



        -- analysing bar
        if analysing and analysingAmount then
            analysingX = minX + analysingAmount * w
            reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, minY, analysingX, maxY, analysingColor, 0)
            local analystingText = math.floor(analysingAmount * 100) .. "%"
            local textW, textH = reaper.ImGui_CalcTextSize(ctx, analystingText)
            reaper.ImGui_DrawList_AddText(draw_list, analysingX - textW - 4, minY + (maxY - minY) / 2 - textH / 2, colorWhite, analystingText)
        else
            -- LOOP AREA
            if not settings.analyseOnlyBetweenMarkers and start_time_sel ~= end_time_sel and start_time_sel < end_time_sel
                and start_time_sel < item_end and end_time_sel > item_pos
            then
                posX = start_time_in_item
                blockOutXStart = ((start_time_in_item - overview_start_in_item) / overview_length_in_item) * w + minX
                blockOutXStart = blockOutXStart > minX and blockOutXStart or minX
                blockOutXEnd = ((end_time_in_item - overview_start_in_item) / overview_length_in_item) * w + minX
                blockOutXEnd = blockOutXEnd < maxX and blockOutXEnd or maxX

                reaper.ImGui_DrawList_AddRectFilled(draw_list, blockOutXStart, minY - 2, blockOutXEnd, minY, colorGreen, 0)
            end


            local mouseOutsideAnalysedAreaStart = false
            local mouseOutsideAnalysedAreaEnd = false
            cursorOutsideArea = false
            local mouseInsideUnanalysedArea = false

            local blockOutStartX = overview_start_in_item
            local blockOutEndX = overview_start_in_item + overview_length_in_item
            local showBlockOutAtEnd = false
            local hoverUnanalyzedBlock = false

            -- NOT ANALYSED BLOCKS
            for _, c in ipairs(cut_data) do
                if c.special == "start" and c.time and c.time > blockOutStartX and c.time < blockOutEndX then
                    blockOutXStart = ((blockOutStartX - overview_start_in_item) / overview_length_in_item) * w + minX
                    blockOutXStart = blockOutXStart > minX and blockOutXStart or minX
                    blockOutXEnd = ((c.time - overview_start_in_item) / overview_length_in_item) * w + minX
                    blockOutXEnd = blockOutXEnd < maxX and blockOutXEnd or maxX
                    if mouse_pos_x > blockOutXStart and mouse_pos_x <= blockOutXEnd and mouse_pos_y >= minY and mouse_pos_y <= maxY then
                        mouseInsideUnanalysedArea = true
                        hoverUnanalyzedBlock = true
                    end
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, blockOutXStart, minY, blockOutXEnd, maxY,
                        hoverUnanalyzedBlock and colorDarkGrey or colorDarkGreyTransparent, 0)

                    showBlockOutAtEnd = false
                end
                if c.special == "end" and c.time and c.time < overview_start_in_item + overview_length_in_item then  --and c.time < overview_start_in_item + overview_length_in_item then
                    blockOutStartX = c.time
                    showBlockOutAtEnd = true
                    hoverUnanalyzedBlock = false
                end
            end

            if showBlockOutAtEnd then
                blockOutXStart = ((blockOutStartX - overview_start_in_item) / overview_length_in_item) * w + minX
                blockOutXStart = blockOutXStart > minX and blockOutXStart or minX
                if mouse_pos_x > blockOutXStart and mouse_pos_x <= maxX and mouse_pos_y >= minY and mouse_pos_y <= maxY then
                    mouseInsideUnanalysedArea = true
                    hoverUnanalyzedBlock = true
                end
                reaper.ImGui_DrawList_AddRectFilled(draw_list, blockOutXStart, minY, maxX, maxY,
                    hoverUnanalyzedBlock and colorDarkGrey or colorDarkGreyTransparent, 0)
            end



            local timeX, hoverName, betweenCut, hoverIndex
            if reaper.ImGui_IsItemHovered(ctx) then
                local mouse_cursor_pos_in_item = ((mouse_pos_x - minX) / w * overview_length_in_item) + overview_start_in_item
                local mousePosRelativeInOverviewArea = math.floor((mouse_pos_x - minX) / w * 10 + 0.5) / 10

                if isShiftDown or #cuts_making_threashold == 0 then
                    posX = mouse_cursor_pos_in_item
                    betweenCut = true
                else
                    --if settings.cursorFollowSelectedCut then
                    local closest = math.huge
                    local use_cut
                    for i, c in ipairs(cuts_making_threashold) do
                        local dif = math.abs(mouse_cursor_pos_in_item - c.time)
                        if dif < closest then
                            use_cut = c
                            closest = dif
                            hoverName = cut_data[c.index] and cut_data[c.index].name and cut_data[c.index].name or
                            "Cut " .. i
                            hoverIndex = c.index
                        end
                    end
                    posX = use_cut.time
                    --else
                    --   posX = posX
                    --   reaper.ShowConsoleMsg("hej\n")
                    --end
                end


                -- cursor
                if not mouseInsideUnanalysedArea then
                    if posX and posX >= overview_start_in_item and posX <= overview_start_in_item + overview_length_in_item then
                        timeX = ((posX - overview_start_in_item) / overview_length_in_item) * w + minX
                        if betweenCut then
                            reaper.ImGui_DrawList_AddLine(draw_list, timeX, minY, timeX, maxY, colorWhite, 1)
                        end
                        local timeXInSeconds = ((timeX / w) * overview_length_in_item + overview_start_in_item)

                        setToolTipFunc((hoverName and (hoverName .. " | ") or "") ..
                        reaper.format_timestr_pos(timeXInSeconds, "", 5))
                    end
                else
                    setToolTipFunc("Area not analysed")
                end

                if isMouseClick then
                    if not last_cur_pos_in_item or posX ~= last_cur_pos_in_item then
                        cur_pos = posX + item_pos - item_offset
                        --cur_pos_in_item = posX
                        --aa = posX
                        --ab = cur_pos
                    end
                    moveCursorToPos(cur_pos)
                end


                if (scrollVertical ~= 0 or scrollHorizontal ~= 0) then
                    local scrollPrecision = 2
                    local left, right
                    if scrollVertical ~= 0 then
                        local scrollIn = scrollVertical > 0
                        left = start_time_sel -
                        (scrollVertical / scrollPrecision) *
                        (scrollIn and mousePosRelativeInOverviewArea or 1 - mousePosRelativeInOverviewArea)  --(scrollVertical > 0 and 0 or -1))
                        right = end_time_sel -
                        (scrollVertical / scrollPrecision) *
                        (scrollIn and (mousePosRelativeInOverviewArea - 1) or -mousePosRelativeInOverviewArea)
                    elseif scrollHorizontal ~= 0 then
                        left = start_time_sel - scrollHorizontal / scrollPrecision

                        right = end_time_sel - scrollHorizontal / scrollPrecision
                    end
                    if left < 0 then left = 0 end

                    reaper.GetSet_LoopTimeRange(true, true, left, right, false)
                    if settings.arrangeviewFollowsOverview then
                        setArrangeviewArea()
                    end
                end
            end

            -- play cursor pos
            if not settings.cursorFollowSelectedCut and cur_pos_in_item >= overview_start_in_item and cur_pos_in_item <= overview_start_in_item + overview_length_in_item then
                local timeX = (cur_pos_in_item - overview_start_in_item) / overview_length_in_item * w + minX
                --if (settings.cursorFollowSelectedCut and not currentSelectedCut) or not settings.cursorFollowSelectedCut then
                reaper.ImGui_DrawList_AddLine(draw_list, timeX, minY - 5 + h / 2, timeX, maxY + 4, colorWhite, 1)       --currentSelectedCut and colorMapLight or colorMap, 1)
                --end
            end

            if timeline_cur_pos_in_item >= overview_start_in_item and timeline_cur_pos_in_item <= overview_start_in_item + overview_length_in_item then
                local timeX = (timeline_cur_pos_in_item - overview_start_in_item) / overview_length_in_item * w + minX
                --if (settings.cursorFollowSelectedCut and not currentSelectedCut) or not settings.cursorFollowSelectedCut then
                reaper.ImGui_DrawList_AddLine(draw_list, timeX, minY - 5, timeX,
                    maxY + 4 - (not settings.cursorFollowSelectedCut and h / 2 or 0), colorWhite, 1)  --currentSelectedCut and colorMapLight or colorMap, 1)
                --end
            else
                cursorOutsideArea = true
            end

            -- draw cuts
            for _, c in ipairs(cuts_making_threashold) do
                if c.time >= overview_start_in_item and c.time <= overview_start_in_item + overview_length_in_item then
                    local timeX = ((c.time - overview_start_in_item) / overview_length_in_item) * w + minX
                    --local col = c.exclude and colorGrey or (cut_data[c.index].color and  cut_data[c.index].color or colorBlue)
                    local col = hoverIndex == c.index and colorWhite or
                    (cut_data[c.index] and cut_data[c.index].color and cut_data[c.index].color or colorGrey)
                    reaper.ImGui_DrawList_AddLine(draw_list, timeX,
                        minY - (c.index == currentSelectedCut and 5 or -2) + (c.exclude and 10 or 0), timeX,
                        maxY + (c.index == currentSelectedCut and 4 or 0), col, c.index == currentSelectedCut and 4 or 1)
                end
            end
        end


        -- PREVIEW SECTION
        isLastImage = cur_pos_in_item == item_length
        
        
        --updateThumbnails = true
        -- Check if we have our video file.
        -- Update to auto get it
        --if not settings.cursorFollowSelectedCut or playState == 0 then
        if filePath and updateThumbnails and not wait then
            
            
            oneFrameEarlier = last_cur_pos_in_item and compareWithMargin(cur_pos_in_item, last_cur_pos_in_item - (1 / frames_per_second))
            oneFrameLater = last_cur_pos_in_item and compareWithMargin(cur_pos_in_item, last_cur_pos_in_item + (1 / frames_per_second))
            cur_pos_rounded_to_frame = roundToFrame(cur_pos_in_item)
            cur_pos_rounded_to_frame_one_frame_ealier = cur_pos_rounded_to_frame - (1 / frames_per_second)
            
            
            
            --pngPath = directory .. itemProperties.fileName .. "_Cut" .. c.index .. "_" .. math.floor(c.time * 1000 + 0.5) .. "ms.png" 

            -- only update images if we change the position.
            -- make option to have session follow or not
            if not last_cur_pos_in_item or last_cur_pos_in_item ~= cur_pos_in_item then
                --if not settings.onlyShowThumbnailsForCuts or (settings.onlyShowThumbnailsForCuts and currentSelectedCut) then 
                    if not last_cur_pos_in_item then last_cur_pos_in_item = cur_pos_in_item end
                    
                    
                    if oneFrameLater then 
                        imageA = file_exists_check(pngPathB) and imageB
                        --reaper.ShowConsoleMsg("later\n")
                        if not imageA then oneFrameLater = false end
                    end
                    if oneFrameEarlier then
                        imageB = file_exists_check(pngPathA) and imageA
                        --reaper.ShowConsoleMsg("earlier\n")
                        if not imageB then oneFrameEarlier = false end
                    end
                    
                    
                    -- for stored thumbnails
                    if currentSelectedCut and thumbnailPath_exist then
                        if reaper.file_exists(cut_data_time_pos[cur_pos_rounded_to_frame]) then 
                            pngPathB = cut_data_time_pos[cur_pos_rounded_to_frame]
                            oneFrameLater = true
                            imageB = nil
                        end
                        if reaper.file_exists(cut_data_time_pos[cur_pos_rounded_to_frame_one_frame_ealier]) then 
                            pngPathA = cut_data_time_pos[cur_pos_rounded_to_frame_one_frame_ealier]
                            oneFrameEarlier = true
                            imageA = nil
                        end
                    end
                    
                    
    
                    if not oneFrameLater then
                        --reaper.ShowConsoleMsg(cur_pos_in_item - (last_cur_pos_in_item - (1/fps)) .. " - " .. run .."\n")
                        pngPathA = join_paths(script_path, "tempA.png")
                        os.remove(pngPathA)
                        imageCreatedA = createThumbnails(filePath, pngPathA, cur_pos_in_item - (1 / frames_per_second), true)
                        imageA = nil
                        --reaper.ShowConsoleMsg("load A\n")
                    end
    
                    if not oneFrameEarlier then
                        pngPathB = join_paths(script_path, "tempB.png")
                        os.remove(pngPathB)
                        imageCreatedB = createThumbnails(filePath, pngPathB, cur_pos_in_item, true)
                        imageB = nil
                        --reaper.ShowConsoleMsg("load B\n")
                    end
                    last_cur_pos_in_item = cur_pos_in_item
                --end
            end
        else
            if not wait then wait = 0 end
            wait = wait + 1
            -- set higher in case of "premature end of file"
            if wait > 8 then
                wait = nil
            end

            --reaper.ShowConsoleMsg("WAIT\n")
        end
        --end

        -- generate images
        -- Ensure images are valid, otherwise reset to nil so they can be re-created
        if imageA and not ImGui.ValidatePtr(imageA, 'ImGui_Image*') then imageA = nil end
        if imageB and not ImGui.ValidatePtr(imageB, 'ImGui_Image*') then imageB = nil end

        if not imageA and pngPathA and reaper.file_exists(pngPathA) then
            imageA = reaper.ImGui_CreateImage(pngPathA, reaper.ImGui_ImageFlags_NoErrors())
            --imageA = imageFromCache(pngPathA)
        end
        if imageA and not imageB and pngPathB and reaper.file_exists(pngPathB) then
            imageB = reaper.ImGui_CreateImage(pngPathB, reaper.ImGui_ImageFlags_NoErrors())
            --imageB = imageFromCache(pngPathB)
        end

        -- Helper function to draw image centered in a slot
        local function DrawImageCentered(image, slotW, slotH, label)
            local p = { reaper.ImGui_GetCursorScreenPos(ctx) }

            -- Draw background slot
            reaper.ImGui_Button(ctx, label, slotW, slotH)       -- Invisible button as background/placeholder?
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
                reaper.ImGui_DrawList_AddImage(dl, image, p[1] + offX, p[2] + offY, p[1] + offX + drawW,
                    p[2] + offY + drawH)
            else
                -- If no image (and not loading?), Button already shows label/loading text.
            end
        end

        -- Calculate Slot Dimensions (Half Width, 16:9)
        -- Make sure we match the logic used for imageW variable (which is Height)
        local slotW = (winW - 8 * 3) / 2
        local slotH = slotW * (9 / 16)
        -- Note: original imageW variable was Height. Let's use our new vars.

        local imageText = (isPlaying or outsideBoundries or settings.onlyShowCutsWithEditedName) and " " or "Loading image"

        DrawImageCentered(imageA, slotW, slotH, imageText .. "##1")

        setToolTipFunc("Image before cut selection")

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

        if not isLastImage then
            reaper.ImGui_SameLine(ctx)
            DrawImageCentered(imageB, slotW, slotH, imageText .. "##2")
            setToolTipFunc("Image on cut selection")
        end
        --textOverlay()
        --textOverlay()


        --if #cuts_making_threashold > 0 then

        if reaper.ImGui_Button(ctx, "Add markers") then
            reaper.Undo_BeginBlock()
            for i, c in ipairs(cuts_making_threashold) do
                if not c.exclude then
                    local name = cut_data[c.index].name and cut_data[c.index].name or "Cut " .. i
                    local col = cut_data[c.index].color and cut_data[c.index].color or 0
                    reaper.AddProjectMarker2(0, false, c.time + item_pos - item_offset, 0, name, -1, (col >> 8) |
                    16777216)
                end
            end
            reaper.Undo_EndBlock("Insert markers from video cut detection", -1)
        end
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, "Add regions") then
            reaper.Undo_BeginBlock()
            for i, c in ipairs(cuts_making_threashold) do
                if not c.exclude then
                    local name = cut_data[c.index].name and cut_data[c.index].name or "Cut " .. i
                    local endPos = i < #cuts_making_threashold and cuts_making_threashold[i + 1].time or
                    findNextSpecialEnd(c.time)
                    local col = cut_data[c.index].color and cut_data[c.index].color or 0
                    reaper.AddProjectMarker2(0, true, c.time + item_pos - item_offset, endPos + item_pos - item_offset,
                        name, -1, (col >> 8) |16777216)
                end
            end
            reaper.Undo_EndBlock("Insert markers from video cut detection", -1)
        end
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, "Add take markers") then
            reaper.Undo_BeginBlock()
            for i, c in ipairs(cuts_making_threashold) do
                if not c.exclude then
                    local name = cut_data[c.index].name and cut_data[c.index].name or "Cut " .. i
                    local col = cut_data[c.index].color and cut_data[c.index].color or 0
                    reaper.SetTakeMarker(reaper.GetActiveTake(item), -1, name, c.time, (col >> 8) |16777216)
                end
            end
            reaper.Undo_EndBlock("Insert markers from video cut detection", -1)
        end
        --end

        
        reaper.ImGui_SameLine(ctx, winW / 2 - 62)
        if reaper.ImGui_Button(ctx, "l<", buttonSize, buttonSize) or (not markerNameIsFocused and isLeftArrowReleased and not isShiftDown) then
            if not findPreviousCut() then
                cur_pos = overview_start_in_item
                moveCursorToPos(cur_pos)
            end
        end
        setToolTipFunc("Select previous cut.\n- press left arrow to set with keyboard")
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "<", buttonSize, buttonSize) or (not markerNameIsFocused and isLeftArrowReleased and isShiftDown) then
            move_cursor_by_frames(-1)
        end
        setToolTipFunc("Move 1 frame left.\n- press shift+left arrow to set with keyboard")
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, ">", buttonSize, buttonSize) or (not markerNameIsFocused and isRightArrowReleased and isShiftDown) then
            move_cursor_by_frames(1)
        end
        setToolTipFunc("Move 1 frame right.\n- press shift+right arrow to set with keyboard")
        
        reaper.ImGui_SameLine(ctx) 
        if reaper.ImGui_Button(ctx, ">l", buttonSize, buttonSize) or (not markerNameIsFocused and isRightArrowReleased and not isShiftDown) then
            if not findNextCut() then
                cur_pos = findNextSpecialEnd(cur_pos_in_item) + item_pos - item_offset
                moveCursorToPos(cur_pos)
            end
        end
        setToolTipFunc("Select next cut.\n- press right arrow to set with keyboard")
        
        
        
        function undoRedo()
            local hasUndo = #undo_stack > 0
            if not hasUndo then reaper.ImGui_BeginDisabled(ctx) end
            if reaper.ImGui_Button(ctx, "Undo") or (isSuperDown and isZ) then
                cut_data = undo(cut_data)
            end
            if not hasUndo then reaper.ImGui_EndDisabled(ctx) end
        
            reaper.ImGui_SameLine(ctx)
            local hasRedo = #redo_stack > 0
            if not hasRedo then reaper.ImGui_BeginDisabled(ctx) end
            if reaper.ImGui_Button(ctx, "Redo") or (isShiftDown and isSuperDown and isZ) then
                cut_data = redo(cut_data)
            end
            if not hasRedo then reaper.ImGui_EndDisabled(ctx) end
        end
        
        reaper.ImGui_SameLine(ctx, winW - 104) 
        undoRedo()

        if analysing then reaper.ImGui_EndDisabled(ctx) end

        lastPosY = reaper.ImGui_GetCursorPosY(ctx) + 4

        -- reaper.ImGui_PopFont(ctx)
        --
        reaper.ImGui_End(ctx)
    end

    --[[
          if isSuperDown and isZ then
              if isShiftDown then
                  cut_data = redo(cut_data)
              else
                  cut_data = undo(cut_data)
              end
          end]]


    --end
    -- reaper.ImGui_PopFont(ctx)
    -- Pop Style Vars (6 vars added) and Colors (12 colors added)
    ImGui.PopStyleVar(ctx, 6)
    ImGui.PopStyleColor(ctx, 12)

    if open then
        reaper.defer(loop)
    else
        reaper.atexit(exit)
    end
end


reaper.defer(loop)

