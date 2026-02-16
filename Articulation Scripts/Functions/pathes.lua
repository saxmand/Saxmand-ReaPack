-- @noindex

local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
resourcePath = reaper.GetResourcePath()
effectsPath = resourcePath .. seperator .. "Effects"
userEffectsPath = effectsPath --.. seperator .. "Jesper"
articulationScriptsPath = userEffectsPath .. seperator .. "Articulation Scripts"