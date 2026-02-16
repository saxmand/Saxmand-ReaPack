-- @noindex

local export = {}

version = 0.6

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

function export.get()
    local allSettings = {
        articulationMapCreatorVersion = version,
        mapName = mapName,
        modifierSettings = modifierSettings, -- maybe we omit this..
        tableInfo = tableInfo,
        mapping = mapping,
        instrumentSettings = instrumentSettings,
        layerInfo = layerInfo
    }
    --text = "//Exported from Articulation Map Creator version: " .. version
    return "//json:" .. minifyJSON(json.encodeToJson(allSettings))
end

function export.getSimple()
    local allSettings = {
        fromLibrary = true,
        articulationMapCreatorVersion = version,
        mapName = mapName,
        tableInfo = tableInfo,
        mapping = mapping,
        instrumentSettings = instrumentSettings,
        layerInfo = layerInfo
    }
    --text = "//Exported from Articulation Map Creator version: " .. version
    return "//json:" .. minifyJSON(json.encodeToJson(allSettings))
end

return export
