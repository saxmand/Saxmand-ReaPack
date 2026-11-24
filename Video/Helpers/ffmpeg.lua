--@noindex
local export = {}
local FFmpegPathKey = "FFMPEG_PATH"
local ffmpegSectionName = "FFMPEG_STATE"

-- Remove at some point

-- quiet: look for a stored path and verify it, but never ask for one. The cut detection
-- editor calls it this way at startup, because FFmpeg is no longer required there -- the
-- video_preview extension detects cuts and reads frames on its own -- so demanding a
-- path before the window has even opened asks for something most people now never need.
-- Call it without the flag from somewhere FFmpeg genuinely is the thing being set up.
function export.Get_Path(quiet)
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
    if reaper.HasExtState(ffmpegSectionName, FFmpegPathKey) then
        path = reaper.GetExtState(ffmpegSectionName, FFmpegPathKey)
    elseif quiet then
        return nil
    else
        local retval = reaper.MB("FFMpeg is required for this action. Find the path to your FFmpeg executable now or click Cancel.", "Detect Cuts", 1)
        if retval == 1 then
            retval, path = reaper.GetUserFileNameForRead(is_windows and "" or "/usr/local/bin/", "Find FFMpeg executable", is_windows and "exe" or "")
            if retval then
                reaper.SetExtState(ffmpegSectionName, FFmpegPathKey, path, true)
                return export.Get_Path(quiet)
            end
        else
            return nil
        end
    end

    if test_ffmpeg(path) then
        return path
    else
        -- A stored path that no longer works is dropped either way, but in quiet mode
        -- that is reported by returning nil rather than by a message box: the caller
        -- did not ask for FFmpeg and may never need it.
        reaper.DeleteExtState(ffmpegSectionName, FFmpegPathKey, true)
        if quiet then return nil end
        reaper.MB("FFmpeg check failed.\nThe file at:\n" .. tostring(path) .. "\n\ndid not respond to '-version' command correctly.\nPlease check if the file is valid.", "Detect Cuts Error", 0)
        return export.Get_Path(quiet)
    end
end

function export.ResetPath()                    
    reaper.DeleteExtState(ffmpegSectionName, FFmpegPathKey, true)
end

return export