-- @noindex
function getVersionFromFile(filepath)
    local file = io.open(filepath, "r")
    if not file then
        reaper.ShowMessageBox("Could not open file: " .. filepath, "Error", 0)
        return nil
    end

    local version = nil
    for line in file:lines() do
        version = line:match("^%-%-%s*@version%s+(%S+)")
        if version then break end
    end

    file:close()
    return version
end

function getVersionNumber()

end

local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
resourcePath = reaper.GetResourcePath()
effectsPath = resourcePath .. seperator .. "Effects"
userEffectsPath = effectsPath --.. seperator .. "Jesper"
articulationScriptsPath = userEffectsPath .. seperator .. "Articulation Scripts"
stateName = "ArticulationScripts"

articulatioScriptsPath = resourcePath .. seperator .. "Scripts" .. seperator .. "Saxmand ReaPack" .. seperator .. "Articulation Scripts" .. seperator
local versionFilePath = articulatioScriptsPath .. "Saxmand_Articulation_Scripts.lua"
articulationScriptCreatorVersionText = getVersionFromFile(versionFilePath)
local a, b, c = articulationScriptCreatorVersionText:match("^(%d+)%.(%d+)%.(%d+)")
articulationScriptCreatorVersionNumber = tonumber((a and a or 0) .. "." .. b .. c)

--reaper.ShowConsoleMsg(tostring(articulationScriptCreatorVersionNumber > 1.6))