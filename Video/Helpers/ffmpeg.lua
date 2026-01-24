--@noindex
local export = {}
local FFmpegPathKey = "FFMPEG_PATH"
local ffmpegSectionName = "FFMPEG_STATE"

-- Remove at some point
local function backwardsCompatabilityForVideoCutDetector()
    if stateName == "Saxmand_VideoCutDetectionEditor" and reaper.HasExtState(stateName, FFmpegPathKey) then
        reaper.SetExtState(ffmpegSectionName, FFmpegPathKey, reaper.GetExtState(stateName, FFmpegPathKey), true)
    end
end

function export.Get_Path()
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

    backwardsCompatabilityForVideoCutDetector()
    local path = nil
    if reaper.HasExtState(ffmpegSectionName, FFmpegPathKey) then
        path = reaper.GetExtState(ffmpegSectionName, FFmpegPathKey)
    else
        local retval = reaper.MB("FFMpeg is required for this action. Find the path to your FFmpeg executable now or click Cancel.", "Detect Cuts", 1)
        if retval == 1 then
            retval, path = reaper.GetUserFileNameForRead(is_windows and "" or "/usr/local/bin/", "Find FFMpeg executable", is_windows and "ffmpeg.exe" or "")
            if retval then
                reaper.SetExtState(ffmpegSectionName, FFmpegPathKey, path, true)
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
        reaper.DeleteExtState(ffmpegSectionName, FFmpegPathKey, true)
        return Get_FFMpeg_Path()
    end
end

function export.ResetPath()                    
    reaper.DeleteExtState(ffmpegSectionName, FFmpegPathKey, true)
end

return export