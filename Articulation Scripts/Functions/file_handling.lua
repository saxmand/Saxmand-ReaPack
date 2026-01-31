-- @version 1.0
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
return export