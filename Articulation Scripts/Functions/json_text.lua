-- @noindex

local export = {}

local function minifyJSON(json)
    local out = {}
    local in_string = false
    local escape = false

    for i = 1, #json do
        local c = json:sub(i,i)

        if in_string then
            out[#out+1] = c
            if escape then
                escape = false
            elseif c == "\\" then
                escape = true
            elseif c == '"' then
                in_string = false
            end
        else
            if c == '"' then
                in_string = true
                out[#out+1] = c
            elseif not c:match("%s") then
                out[#out+1] = c
            end
        end
    end

    return table.concat(out)
end

function export.clearForKeyswitchInfo(tableInfo)
    local tmp = {}
    for i, art in ipairs(tableInfo) do
        art.keyswitchInfo = nil
    end
end

function export.get(importer)    
    --reaper.ShowConsoleMsg(os.time().."\n")
    local genTime = os.time()
    local allSettings = {
        creatorVersion = importer and importer.creatorVersion or articulationScriptCreatorVersionNumber,
        genTime = importer and importer.genTime or genTime,
        mapName = importer and importer.mapName or mapName,
        modifierSettings = importer and importer.modifierSettings or modifierSettings, -- maybe we omit this..
        tableInfo = importer and importer.tableInfo or tableInfo,
        mapping = importer and importer.mapping or mapping,
        instrumentSettings = importer and importer.instrumentSettings or instrumentSettings,
        layerInfo = importer and importer.layerInfo or layerInfo,
    }
    --text = "//Exported from Articulation Map Creator version: " .. version
    return "//json:" .. minifyJSON(json.encodeToJson(allSettings))
end

function export.getSimple()
    local allSettings = {
        fromLibrary = true,
        creatorVersion = articulationScriptCreatorVersionNumber,
        genTime = os.time(),
        mapName = mapName,
        tableInfo = tableInfo,
        mapping = mapping,
        instrumentSettings = instrumentSettings,
        layerInfo = layerInfo,
    }
    --text = "//Exported from Articulation Map Creator version: " .. version
    return "//json:" .. minifyJSON(json.encodeToJson(allSettings))
end

return export
