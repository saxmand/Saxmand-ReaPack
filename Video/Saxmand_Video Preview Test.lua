-- Quick smoke test for the video_preview extension.
-- Run from REAPER: Actions → Load ReaScript, pick this file.
-- It will open the first selected media item's video and extract a frame.

local function test()
    -- Check extension is loaded
    if not reaper.VP_Open then
        reaper.ShowConsoleMsg("[VP Test] Extension not loaded — restart REAPER after building.\n")
        return
    end

    -- Find a video item
    local item = reaper.GetSelectedMediaItem(0, 0)
    if not item then
        reaper.ShowConsoleMsg("[VP Test] Select a video item first.\n")
        return
    end
    local take = reaper.GetActiveTake(item)
    local src  = take and reaper.GetMediaItemTake_Source(take)
    local path = src  and reaper.GetMediaSourceFileName(src)
    if not path or path == "" then
        reaper.ShowConsoleMsg("[VP Test] Could not get file path from selected item.\n")
        return
    end

    reaper.ShowConsoleMsg("[VP Test] Opening: " .. path .. "\n")

    local handle = reaper.VP_Open(path)
    if handle == 0 then
        reaper.ShowConsoleMsg("[VP Test] VP_Open failed.\n")
        return
    end

    local dur = reaper.VP_GetDuration(handle)
    reaper.ShowConsoleMsg(string.format("[VP Test] Duration: %.2f s\n", dur))

    -- Extract frame at 10% of the video
    local t0 = os.clock()
    local framePath = reaper.VP_GetFrame(handle, dur * 0.10, 320, 180)
    local elapsed = os.clock() - t0

    if framePath and framePath ~= "" then
        reaper.ShowConsoleMsg(string.format("[VP Test] Frame OK in %.1f ms: %s\n", elapsed * 1000, framePath))
    else
        reaper.ShowConsoleMsg("[VP Test] VP_GetFrame returned empty path.\n")
    end

    -- Second call to same position — should be instant (cached)
    local t1 = os.clock()
    local framePath2 = reaper.VP_GetFrame(handle, dur * 0.10, 320, 180)
    local elapsed2 = os.clock() - t1
    reaper.ShowConsoleMsg(string.format("[VP Test] Cached call: %.1f ms\n", elapsed2 * 1000))

    reaper.VP_Close(handle)
    reaper.ShowConsoleMsg("[VP Test] Done.\n")
end

test()
