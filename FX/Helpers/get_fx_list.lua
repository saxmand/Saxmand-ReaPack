local list = { _version = "0.2" }

function parse_fx_tags_file(path)
    local category_map = {}
    local developer_map = {}
    local section = nil

    local file = io.open(path, "r")
    if not file then return nil, "Cannot open file" end

    for line in file:lines() do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed == "[category]" then
            section = "category"
        elseif trimmed == "[developer]" then
            section = "developer"
        elseif trimmed ~= "" and not trimmed:match("^%[") then
            local key, value = trimmed:match("^(.-)=(.+)$")
            if key and value then
                if section == "category" then
                    category_map[key] = value
                elseif section == "developer" then
                    developer_map[key] = value
                end
            end
        end
    end
    file:close()

    local combined = {}

    local function normalize_name(raw_id, dev)
        -- Remove extension
        local name, plugin_type = raw_id:match("^(.-)%.([%w_]+)$")
        if not name then
            name = raw_id; plugin_type = ""
        end

        -- Replace underscores with spaces
        name = name:gsub("_", " ")

        -- Remove developer prefix like "FabFilter: ..."
        if dev and name:match("^" .. dev .. ":") then
            name = name:gsub("^" .. dev .. ":%s*", "")
        end

        return name, plugin_type
    end

    -- Collect unique entries by name+type key
    for fx_id in pairs(category_map) do
        local dev = developer_map[fx_id]
        local name, plugin_type = normalize_name(fx_id, dev)
        local key = name .. "|" .. plugin_type

        combined[key] = combined[key] or {
            name = name,
            type = plugin_type,
            category = category_map[fx_id],
            developer = dev,
            id = fx_id
        }

        -- If entry already exists, fill in missing info
        if not combined[key].category then combined[key].category = category_map[fx_id] end
        if not combined[key].developer and dev then combined[key].developer = dev end
    end

    for fx_id in pairs(developer_map) do
        local dev = developer_map[fx_id]
        local name, plugin_type = normalize_name(fx_id, dev)
        local key = name .. "|" .. plugin_type

        combined[key] = combined[key] or {
            name = name,
            type = plugin_type,
            category = category_map[fx_id],
            developer = dev,
            id = fx_id
        }

        if not combined[key].developer then combined[key].developer = dev end
        if not combined[key].category then combined[key].category = category_map[fx_id] end
    end

    -- Convert to array
    local result = {}
    for _, data in pairs(combined) do
        table.insert(result, data)
    end

    return result
end

function parse_jsfx_file(path)
    local results = {}

    for line in io.lines(path) do
        -- Only process lines starting with "NAME"
        if line:match("^NAME") then
            -- Capture the tag, path, and title (both quoted or unquoted path)
            local _, _, path, title = line:find([[^NAME%s+("?[^"]+"?)%s+"(.-)"]])
            if path and title then
                -- Remove quotes from path if present
                path = path:gsub('^"(.-)"$', '%1')

                -- Extract category from path (first directory)
                local category = path:match("([^/\\]+)")

                -- Extract developer from title if present in parentheses
                local developer = title:match("%((.-)%)")
                title = title:gsub("JS:%s*", "")         -- Remove "JS: "
                title = title:gsub("%s*%b()", "")         -- Remove "(developer)"
                title = title:match("^%s*(.-)%s*$")       -- Trim whitespace

                table.insert(results, {
                    name = title,
                    type = "JS",
                    category = category,
                    developer = developer,
                    id = title
                })
            end
        end
    end

    return results
end


function list.getFXList()    

    local path = reaper.GetResourcePath() .. "/reaper-fxtags.ini"
    local obj1 = parse_fx_tags_file(path)

    local path = reaper.GetResourcePath() .. "/reaper-jsfx.ini"
    local obj2 = parse_jsfx_file(path)

    local results = {}
    for _, t in ipairs(obj1) do
        table.insert(results, t)
    end
    for _, t in ipairs(obj2) do
        table.insert(results, t)
    end

    return results
    
end

return list