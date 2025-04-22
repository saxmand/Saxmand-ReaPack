-- @description Add subtitles to video from srt file using video processor
-- @author saxmand
-- @version 1.0.2

function getTimecodeInputOffsetInFrames(fps)
    -- Labels for each timecode component
    local title = "Enter timecode offset for video"
    local num_fields = 4
    local fields = "Hours,Minutes,Seconds,Frames"
    local lastValues = reaper.HasExtState("AddSubtitleOverlayToVideoPlugin","Offset") and reaper.GetExtState("AddSubtitleOverlayToVideoPlugin","Offset") or "00,00,00,00"  -- values for each component
    
    -- Prompt the user for timecode input
    local retval, userInput = reaper.GetUserInputs(title, num_fields, fields, lastValues)
    
    if not retval then
        return 0  -- Return 0 if the user canceled
    end
    
    reaper.SetExtState("AddSubtitleOverlayToVideoPlugin","Offset", userInput, true)
    
    -- Split the input into individual components
    local hours, minutes, seconds, frames = userInput:match("([^,]+),([^,]+),([^,]+),([^,]+)")

    -- Convert components to numbers for further processing if needed
    hours = tonumber(hours) or 0
    minutes = tonumber(minutes) or 0
    seconds = tonumber(seconds) or 0
    frames = tonumber(frames) or 0
    
    return tonumber((hours * 3600 * fps) + (minutes * 60 * fps) + (seconds * fps) + frames)
end

-- Function to convert SRT timecode to absolute frames
local function timecodeToFrames(timecode, fps) 
    -- Split the timecode into components
    local hours, minutes, seconds, milliseconds = timecode:match("(%d+):(%d+):(%d+),(%d+)")
    -- Convert hours and minutes to total seconds
    local totalSeconds = (tonumber(hours) * 3600) + (tonumber(minutes) * 60) + seconds + (milliseconds/1000)

    -- Convert total seconds to frames
    return math.floor(totalSeconds * fps)  -- Round to the nearest frame
end

-- Function to read the SRT file and create an array
local function parseSRT(filePath)
    local srtArray = {}
    local file = io.open(filePath, "r")

    if not file then
        reaper.ShowMessageBox("Could not open the file: " .. filePath, "Error", 0)
        return nil
    end

    --local fps = 0
    local fps = reaper.TimeMap_curFrameRate(-1)  -- Pass 0 to get the FPS of the current project


    -- Read the SRT file line by line
    local index = 1
    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")  -- Trim whitespace
        if line and line ~= "" then
            -- Check for timecode lines (the second line of each block)
            if index == 2 then
                local startTime, endTime = line:match("(%d+:%d+:%d+,%d+)%s+-->%s+(%d+:%d+:%d+,%d+)")
                if startTime and endTime then
                    local startFrame = timecodeToFrames(startTime, fps)
                    local endFrame = timecodeToFrames(endTime, fps)

                    -- Add to array
                    table.insert(srtArray, {startFrame = startFrame, endFrame = endFrame, text = ""})
                end
            elseif index == 3 then
                -- This line contains the text
                if #srtArray > 0 then
                    srtArray[#srtArray].text = line  -- Add text to the last entry
                end
            end
            index = index < 3 and index + 1 or 1
        end
    end

    file:close()
    return srtArray
end

local function pluginText()
  return [[ 
// Plugin Parameters    
//@param1:size 'text height' 0.05 0.01 0.2 0.1 0.001
//@param2:ypos 'y position' 0.95 0 1 0.5 0.01
//@param3:xpos 'x position' 0.5 0 1 0.5 0.01
//@param4:border 'bg pad' 0.22 0 1 0.5 0.01
//@param5:fgc 'text bright' 1.0 0 1 0.5 0.01
//@param6:fga 'text alpha' 1.0 0 1 0.5 0.01
//@param7:bgc 'bg bright' 0 0 1 0.5 0.01
//@param8:bga 'bg alpha' 0.36 0 1 0.5 0.01
//@param9:bgfit 'fit bg to text' 1 1 1 0.5 1
//@param10:ignoreinput 'ignore input' 0 0 1 0.5 1


// Input handling
input = ignoreinput ? -2 : 0;
project_wh_valid === 0 ? input_info(input, project_w, project_h);
gfx_a2 = 0;
gfx_blit(input, 1);
gfx_setfont(size * project_h, font);

t = floor((project_time + project_timeoffs) * framerate + 0.0000001) - videoOffset;
messages[t] ? sprintf(#text,messages[t]);

gfx_str_measure(#text, txtw, txth);
b = (border * txth) | 0;
yt = ((project_h - txth - b * 2) * ypos) | 0;
xp = (xpos * (project_w - txtw)) | 0;
gfx_set(bgc, bgc, bgc, bga);
bga > 0 ? gfx_fillrect(bgfit ? xp - b : 0, yt, bgfit ? txtw + b * 2 : project_w, txth + b * 2);
gfx_set(fgc, fgc, fgc, fga);
gfx_str_draw(#text, xp, yt + b);  
]]
end

-- Main function
local function main(srtFilePath) 
    local fps = reaper.TimeMap_curFrameRate(-1)  -- Pass 0 to get the FPS of the current project
    local timecodeOffsetInFrames = getTimecodeInputOffsetInFrames(fps)
    
    local bakeTimecode = reaper.ShowMessageBox("Have offset as seperate value", "Add Subtitle to video",3)
    -- Set the path to your SRT file
    --local srtFilePath = "/Volumes/Projects/Humanlike/Misc/HUMANLIKE 0-30 min.srt" -- reaper.GetOS():match("Windows") and "C:\\path\\to\\your\\file.srt" or "/path/to/your/file.srt"
    local srtArray = parseSRT(srtFilePath)
    local minimumSubtitleSeconds = 3
    local mimumumSuttitleInFrames = math.floor(minimumSubtitleSeconds * fps)

    if bakeTimecode == 6 then 
        textArray = {"videoOffset = " .. timecodeOffsetInFrames .. ";", "// timecodes and messages"}
        offset = 0
    elseif bakeTimecode == 7 then  
        textArray = {"videoOffset = " .. 0 .. ";", "// timecodes and messages"}
        offset = timecodeOffsetInFrames
    end
    if bakeTimecode ~= 2 then
        if  srtArray then
            for _, entry in ipairs(srtArray) do
                counter = (lastEndFrame and lastEndFrame >= entry.startFrame) and #textArray or #textArray + 1
                textArray[counter] = "messages[" .. entry.startFrame + offset ..'] = "' .. entry.text .. '";'
                -- stop subtitle, make sure it stays at least minimumSubtitleSeconds
                lastEndFrame = (entry.endFrame - entry.startFrame < mimumumSuttitleInFrames and entry.startFrame + mimumumSuttitleInFrames or entry.endFrame)
                textArray[counter+1] = "messages[" .. lastEndFrame + offset  ..'] = "";'
            end
        end
        text = table.concat(textArray, "\n")
        
        text = text .. pluginText()
        reaper.CF_SetClipboard(text)
        
        reaper.ShowMessageBox("Plugin is in the clipboard.\n\nCreate a video processor on your the top most video track and paste the plugin","Create Subtitles Plugin",0)
    end
end

local projectPath = reaper.GetProjectPath()
local retval, srtFilePath = reaper.GetUserFileNameForRead(projectPath, "Select a file", ".srt")

if retval then
  main(srtFilePath)
end

