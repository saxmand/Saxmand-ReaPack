-- @noindex
local export = {}

local function isWindows()
    return reaper.GetOS():match("Win")
end

local function urlencode(str)
    return (str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
local function urldecode(str)
    str = str:gsub("+", " ")
    return str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
end


function export.appendSharedLibrary(text)
    local url = "https://ankarfeldt.dk/write_articulation_scripts_library.php"
    local secret = "SAXMAND2026"

    local data = "key=" .. urlencode(secret) .. "&text=" .. urlencode(text)

    local cmd

    if isWindows() then
        cmd = string.format(
            'powershell -NoProfile -WindowStyle Hidden -Command "Invoke-WebRequest -Uri \'%s\' -Method POST -Headers @{\'User-Agent\'=\'Mozilla/5.0\'} -Body \'%s\'; $response.Content"',
            url,
            data:gsub("'", "''")
        )
    else
        cmd = string.format(
            'curl -s -A "Mozilla/5.0" -X POST -d "%s" "%s"',
            data,
            url
        )
    end

    local f = io.popen(cmd)
    local response = f:read("*a") or ""
    f:close()

    return response:match("^%s*(.-)%s*$") == "OK"
end

function export.appendSharedLibraryInChunks(text)
    local CHUNK = 4000

    for i = 1, #text, CHUNK do
        local part = text:sub(i, i+CHUNK-1)
        export.appendSharedLibrary(part)
    end

    export.appendSharedLibrary("__END__")
end


function export.readSharedText()
    local url = "https://ankarfeldt.dk/read_articulation_scripts_library.php"
    local cmd

    if isWindows() then
        cmd = string.format(
            'powershell -NoProfile -Command "(Invoke-WebRequest -Uri \'%s\' -Headers @{\'User-Agent\'=\'Mozilla/5.0\'}).Content"',
            url
        )
    else
        cmd = string.format(
            'curl -s -A "Mozilla/5.0" "%s"',
            url
        )
    end

    local f = io.popen(cmd)
    local result = f:read("*a")
    f:close()

    return urldecode(result)
end

return export
