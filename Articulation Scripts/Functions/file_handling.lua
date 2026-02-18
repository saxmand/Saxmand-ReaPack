-- @noindex

local export = {}

function export.readFileLines(path, remove)
    local lines = {}

    local f = io.open(path, "r")
    if not f then
        return nil, "Could not open file: " .. path
    end

    for line in f:lines() do
        lines[#lines+1] = line:gsub(remove and remove or "", "")
    end

    f:close()
    return lines
end

function export.readFileForJsonLine(filePath)
    local file = io.open(filePath)
    if not file then
        return false
    end
    local jsonString = nil
    for line in file:lines() do
        if line:match "//json:" then
            jsonString = line:gsub("//json:", "") 
            break
        end
    end 
    file:close()
    return jsonString
end

function export.get_last_path_component(path)
    if not path or path == "" then return nil end

    -- normalize Windows backslashes to forward slashes
    path = path:gsub("\\", "/")

    -- remove trailing slash(es)
    path = path:gsub("/+$", "")

    -- extract everything after last slash
    local last = path:match("([^/]+)$")

    return last
end

local function common_prefix(strings)
    local prefix = strings[1]
    for i = 2, #strings do
        local s = strings[i]
        local j = 1
        local max = math.min(#prefix, #s)
        while j <= max and prefix:sub(j,j) == s:sub(j,j) do
            j = j + 1
        end
        prefix = prefix:sub(1, j-1)
        if prefix == "" then break end
    end
    return prefix
end

local function common_suffix(strings)
    local suffix = strings[1]
    for i = 2, #strings do
        local s = strings[i]
        local j = 0
        local max = math.min(#suffix, #s)
        while j < max and
              suffix:sub(-j-1, -j-1) == s:sub(-j-1, -j-1) do
            j = j + 1
        end
        suffix = suffix:sub(-j)
        if suffix == "" then break end
    end
    return suffix
end

function export.strip_common_parts(strings)
    if #strings < 2 then return strings end

    local prefix = common_prefix(strings)
    local suffix = common_suffix(strings)

    local out = {}

    for i, s in ipairs(strings) do
        local start = #prefix + 1
        local finish = #s - #suffix
        out[i] = s:sub(start, finish)
    end

    return out, prefix, suffix
end

function export.path_is_directory(path)
    local ok = reaper.EnumerateFiles(path, 0)
    if ok then return true end

    ok = reaper.EnumerateSubdirectories(path, 0)
    if ok then return true end

    return false
end


function export.importJsonString(jsonString)
    local luaTable, error = json.decodeFromJson(jsonString)
    if not luaTable then 
        reaper.ShowConsoleMsg("json parsing error: " .. error .. "\n")
    else
        articulationMapCreatorVersion = luaTable.articulationMapCreatorVersion and tonumber(luaTable.articulationMapCreatorVersion) or 0
        mapName = luaTable.mapName
        if mapName then 
            if articulationMapCreatorVersion < 0.4 then
                mapping = {}
                mapping.NoteM = {}
                mapping.NoteH = {}
                mapping.CC = {}
            end
            if articulationMapCreatorVersion > 0 and articulationMapCreatorVersion < 0.2 then 
                modifierSettings = luaTable.modifierSettings or defaultModifierSettings
                --mappingType = luaTable.mappingType or {}
                --mapping.CC = luaTable.mapping.CC or {}
                --mapping.NoteH = luaTable.mapping.NoteH or {}
                --mapping.NoteM = luaTable.mapping.NoteM or {}
                --mapping.Velocity = luaTable.mapping.Velocity or false
                --mapping.Channel = luaTable.mapping.Channel or false
                --mapping.Delay = luaTable.mapping.Delay or false
                --aaa = luaTable.tableInfo.NoteM2
                local noteCount = 0
                for key, value in pairs(luaTable.tableInfo) do
                    
                    --reaper.ShowConsoleMsg(key .. "\n")
                    --
                    if key:match("Note") ~= nil then
                        if key:match("NoteM") ~= nil and key:match("Velocity") == nil then
                            local anyValues = false
                            for k, v in pairs(value) do
                                if v and v ~= "" then 
                                    anyValues = true
                                    break
                                end
                            end 
                            if not anyValues then
                                luaTable.tableInfo[key] = nil
                            else
                                noteCount = noteCount + 1
                                mapping["Note" .. noteCount] = true
                            end
                        elseif key:match("NoteH") ~= nil and key:match("Velocity") == nil  then
                            local anyValues = false
                            for k, v in pairs(value) do
                                if v and v ~= "" then 
                                    anyValues = true
                                    break
                                end
                            end 
                            if not anyValues then
                                luaTable.tableInfo[key] = nil
                            else
                                noteCount = noteCount + 1
                                mapping["Note" .. noteCount] = true
                            end
                        end
                    elseif key:match("CC") ~= nil then
                        local anyValues = false
                        for k, v in pairs(value) do
                            if v and v ~= "" then 
                                anyValues = true
                                break
                            end
                        end 
                        if not anyValues then
                            luaTable.tableInfo[key] = nil
                        else
                            mapping[key] = true
                        end
                    else
                        local anyValues = false
                        for k, v in pairs(value) do
                            if v and v ~= "" then 
                                anyValues = true
                                break
                            end
                        end 
                        if anyValues then
                            if key:match("Velocity") ~= nil and key:match("FilterVelocity") == nil then mapping.Velocity = true end
                            if key:match("Channel") ~= nil then mapping.Channel = true end
                            if key:match("Subtitle") ~= nil then mapping.Group = true end
                            if key:match("KT") ~= nil then mapping.KeyboardTrigger = true end
                            if key:match("Notation") ~= nil then mapping.Notation = true end
                            if key:match("UI Text") ~= nil then mapping.UIText = true end
                            if key:match("Delay") ~= nil then mapping.Delay = true end
                            if key:match("Pitch") ~= nil then mapping.Pitch = true end
                            if key:match("Layer") ~= nil or key:match("Group") ~= nil then mapping.Layer = true end
                            if key:match("Position") ~= nil then mapping.Position = true end
                            if key:match("Transpose") ~= nil then mapping.Transpose = true end
                            if key:match("FilterVelocity") ~= nil then mapping.FilterVelocity = true end
                            if key:match("FilterSpeed") ~= nil then mapping.FilterSpeed = true end
                            if key:match("Interval") ~= nil then mapping.Interval = true end
                        end
                    end
                end
                
                tableInfo = {} 
                for key, value in pairs(luaTable.tableInfo) do                   
                    for k, v in pairs(value) do                    
                        if not tableInfo[k] then tableInfo[k] = {} end
                        tableInfo[k][key] = v 
                        if key == "Title" and tostring(v):match("!!Lane:") ~= nil then
                            tableInfo[k].isLane = true
                        end
                    end                    
                end
                
                --tableInfo = luaTable.tableInfo
            elseif articulationMapCreatorVersion == 0.25 then 
                tableInfo = luaTable.tableInfo
                if luaTable.mapping then
                    mapping = luaTable.mapping
                else
                    local usedNoteMapping = {}
                    for _, a in ipairs(tableInfo) do
                        for k, v in pairs(a) do 
                            if v and v ~= "" then 
                                if k:match("NoteM") ~= nil and k:match("Velocity") == nil then
                                    if not usedNoteMapping[k] then 
                                        table.insert(mapping.NoteM, true)
                                        usedNoteMapping[k] = true
                                    end
                                elseif k:match("NoteH") ~= nil and k:match("Velocity") == nil  then
                                    if not usedNoteMapping[k] then 
                                        table.insert(mapping.NoteH, true)
                                            usedNoteMapping[k] = true
                                        end 
                                elseif k:match("CC") ~= nil then
                                    mapping.CC[key:gsub("CC", "")] = true
                                else
                                    if k:match("KT") ~= nil then 
                                        mapping.KeyboardTrigger = true 
                                    else
                                        mapping[k] = true
                                    end
                                end
                            end
                        end
                    end
                end
            elseif articulationMapCreatorVersion == 0.2 then   
                tableInfo = luaTable.tableInfo
                if luaTable.mapping then
                    mapping = luaTable.mapping
                end
                --if mapping.NoteM or mapping.NoteH then
                    mapping.NoteM = nil
                    mapping.NoteH = nil
                    mapping.Note = {}
                    local usedNoteMapping = {}
                    local newTable = {}
                    for i, a in ipairs(tableInfo) do
                        if not newTable[i] then newTable[i] = {} end
                        for k, v in pairs(a) do 
                            if v and v ~= "" then
                                if k:match("Note") ~= nil and k:match("Velocity") == nil and k:match("Held") == nil then
                                    if not usedNoteMapping[k] then 
                                        table.insert(mapping.Note, #mapping.Note + 1)
                                        usedNoteMapping[k] = #mapping.Note
                                    end 
                                    
                                    newTable[i]["Note" .. usedNoteMapping[k]] = v 
                                elseif k:match("Note") ~= nil and k:match("Velocity") ~= nil then
                                    newTable[i][k:gsub("M", ""):gsub("M", "")] = v 
                                elseif k:match("CC") ~= nil then
                                    local ccNumberClean = k:gsub("CC", "")
                                    if tonumber(ccNumberClean) and not mapping.CC[tonumber(ccNumberClean)]  then 
                                        mapping.CC[tonumber(ccNumberClean)] = true
                                    end
                                    newTable[i][k] = v
                                else
                                    newTable[i][k] = v
                                    if k:match("KT") ~= nil then 
                                        mapping.KeyboardTrigger = true 
                                    else
                                        mapping[k] = true
                                    end
                                end
                            end
                        end
                    end
                    tableInfo = newTable
                --end
            elseif articulationMapCreatorVersion == 0.3 then   
                tableInfo = luaTable.tableInfo
                if luaTable.mapping then 
                    mapping = {}
                    for k, v in pairs(luaTable.mapping) do
                        if (k == "Note" or k == "CC") then
                            for i, v2 in ipairs(v) do
                                mapping[k .. i] = true -- k .. i
                            end
                        else
                            mapping[k] = v
                        end
                    end 
                end 
            elseif articulationMapCreatorVersion >= 0.4 then   
                tableInfo = luaTable.tableInfo
                if luaTable.mapping then
                    if articulationMapCreatorVersion < 0.7 then 
                        if luaTable.mapping.KeyboardTrigger then 
                            --luaTable.mapping.KeyboardTrigger = nil
                            luaTable.mapping.KT = true
                        end
                    end

                    mapping = luaTable.mapping
                end
            else
                --reaper.ShowConsoleMsg("Script not supported from version: " .. tostring(articulationMapCreatorVersion) .. "\n")
                return false, ("Script not supported from version: " .. tostring(articulationMapCreatorVersion))
            end
            
            -- for backwards compatability
            if articulationMapCreatorVersion <= 0.4 then   
                for i, t in ipairs(tableInfo) do
                    if t.Delay then
                        tableInfo[i].Delay = math.abs(t.Delay)
                    end
                end
            end

            --#tableInfo = #tableInfo -- luaTable.tableInfo.Title and #luaTable.tableInfo.Title or 0
            instrumentSettings = luaTable.instrumentSettings and luaTable.instrumentSettings or instrumentSettingsDefault
            return true, {tableInfo = tableInfo, mapping = mapping, instrumentSettings = instrumentSettings, mapName = mapName, articulationMapCreatorVersion = articulationMapCreatorVersion}
        end
    end
end

return export