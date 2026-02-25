-- ===============================
-- REAPER Lua: Fully Bundled OCR
-- ===============================

local os_name = reaper.GetOS():lower() -- "osx64", "win64", "linux64"
local tmp_dir = os.getenv("TMPDIR") or "/tmp/"
local img_path = tmp_dir .. "reaper_ocr_capture.png"

-- ===== Step 1: Select screen region =====
if os_name:find("osx") then
    os.execute('screencapture -i "' .. img_path .. '"')
elseif os_name:find("win") then
    -- Windows: assumes ShareX portable or custom capture exe bundled
    local capture_exe = reaper.GetResourcePath() .. "\\Scripts\\MyOCR\\capture.exe"
    os.execute('"' .. capture_exe .. '" "' .. img_path .. '"')
elseif os_name:find("linux") then
    os.execute('maim -s "' .. img_path .. '"')
end

-- Check if file exists
local f = io.open(img_path, "rb")
if not f then
    reaper.ShowMessageBox("No screenshot captured.", "OCR Cancelled", 0)
    return
end
f:close()

-- ===== Step 2: Call bundled Tesseract =====
local tesseract_bin
local script_dir = reaper.GetResourcePath() .. "/Scripts/MyOCR/"
if os_name:find("osx") then
    tesseract_bin = '"' .. script_dir .. 'tesseract-mac"'
elseif os_name:find("win") then
    tesseract_bin = '"' .. script_dir .. 'tesseract-win.exe"'
elseif os_name:find("linux") then
    tesseract_bin = '"' .. script_dir .. 'tesseract-linux"'
end

-- OCR command, output to stdout, English only
local ocr_cmd = tesseract_bin .. ' "' .. img_path .. '" stdout -l eng 2>/dev/null'

-- Capture OCR result
local handle = io.popen(ocr_cmd)
local raw_text = handle:read("*a")
handle:close()

-- Cleanup temporary image
os.remove(img_path)

-- ===== Step 3: Clean text =====
local result = {}
for line in raw_text:gmatch("[^\r\n]+") do
    -- Trim
    line = line:match("^%s*(.-)%s*$")

    -- Skip empty lines and OCR error lines
    if line ~= "" and not line:match("^Error in") then
        -- Remove non-letter at start
        line = line:gsub("^[^%a]+", "")

        -- Remove non-letter at end except closing parenthesis if matched opening exists
        local has_open = line:find("%(")
        local last_char = line:sub(-1)
        if last_char == ")" and (not has_open or line:sub(1,-2):find("%(") == nil) then
            line = line:sub(1,-2)
            line = line:gsub("[^%a]+$", "")
        else
            line = line:gsub("[^%a%)]+$", "")
        end

        if line ~= "" then
            table.insert(result, line)
        end
    end
end

-- ===== Step 4: Output =====
reaper.ShowConsoleMsg("---- OCR Result Table ----\n")
for i,v in ipairs(result) do
    reaper.ShowConsoleMsg(i .. ": " .. v .. "\n")
end