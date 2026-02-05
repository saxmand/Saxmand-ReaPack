-- @noindex

local export = {}
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


return export