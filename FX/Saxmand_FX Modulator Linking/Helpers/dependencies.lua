--@noindex
local checkDependcies = {}
function checkDependcies.main()
    
    -- Check js_ReaScriptAPI
    if not reaper.JS_Dialog_BrowseForSaveFile then
    reaper.ShowMessageBox(
        "Missing required extension: js_ReaScriptAPI\n\n" ..
        "Install it via this ReaPack link:\n" ..
        "https://github.com/ReaTeam/Extensions/raw/master/index.xml",
        "Missing Dependency", 0)
    return false
    end

    -- Check ReaImGui
    --local ok, reaper_imgui = pcall(require, 'imgui')

    if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox(
        "Missing required extension: ReaImGui (ReaScript binding for Dear ImGui)\n\n" ..
        "Install it via this ReaPack link:\n" ..
        "https://github.com/ReaTeam/Extensions/raw/master/index.xml",
        "Missing Dependency", 0)
    return false
    end

    return true
end
return checkDependcies