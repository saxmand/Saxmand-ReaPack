-- @noindex
local function getScreenSize()
    local osname = reaper.GetOS()
    if osname:find("OSX") or osname:find("macOS") then apple = true end

    if not reaper.JS_Window_MonitorFromRect then
        reaper.ShowConsoleMsg(
        'Please Install js_ReaScriptAPI extension.\nhttps://forum.cockos.com/showthread.php?t=212174\n')
    else
        local screen_left, screen_top, screen_right, screen_bottom = reaper.JS_Window_MonitorFromRect(0, 0, 0, 0, false)

        if apple then
            screen_bottom, screen_top = screen_top, screen_bottom
        end
        return screen_left, screen_top, screen_right, screen_bottom
    end
end

return getScreenSize()
