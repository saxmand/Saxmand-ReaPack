-- Helpers
local function script_dir()
  local info = debug.getinfo(1, 'S')
  local src  = info.source:match('^@(.+)$') or ''
  return src:match('^(.+)[/\\]') or '.'
end

local function find_tesserect()
  local candidates = {
    '/opt/homebrew/bin/tesseract',
    '/usr/local/bin/tesseract',
    '/usr/bin/tesseract',
  }
  for _, path in ipairs(candidates) do
    local f = io.open(path, 'r')
    if f then f:close() return path end
  end
  return 'tesseract'
end



local export = {}

local function check_tesseract_mac()
  local tesseract = find_tesserect()
  
  -- If we only got the fallback name, it's not installed
  if tesseract == 'tesseract' then
    return false, "Tesseract not found. Install with: brew install tesseract"
  end
  
  -- Verify it actually runs and get version
  local handle = io.popen(tesseract .. ' --version 2>&1')
  if not handle then
    return false, "Tesseract found at " .. tesseract .. " but failed to execute"
  end
  
  local output = handle:read('*a')
  handle:close()
  
  -- Check the output contains "tesseract" to confirm it's really working
  if output:lower():find('tesseract') then
    local version = output:match('tesseract%s+([%d%.]+)')
    return true, version and ("Tesseract " .. version .. " found at " .. tesseract) or ("Tesseract found at " .. tesseract)
  end
  
  return false, "Tesseract found but returned unexpected output: " .. output
end

-- macOS Screen OCR Prototype
local function ocr_mac() 
    -- Example usage:
    local ok, msg = check_tesseract_mac()
    if not ok then
        reaper.ShowMessageBox(msg, "OCR Setup Required", 0)
        return {}
    end

    local img_path = script_dir() .. "/reaper_ocr_capture.png"-- tmp_dir .. "reaper_ocr_capture.png"
    
    -- 1. Capture interactive screen region
    local capture_cmd = 'screencapture -i "' .. img_path .. '"'
    os.execute(capture_cmd)
    
    -- Check if file was created
    local file = io.open(img_path, "rb")
    if not file then
        --reaper.ShowMessageBox("No image captured.", "OCR Cancelled", 0)
        return {}
    end
    file:close() 
    
    local tesseract = find_tesserect()
    
    -- 2. Run Tesseract OCR
    local ocr_cmd = tesseract .. ' "' .. img_path .. '" stdout 2>&1'
    
    local handle = io.popen(ocr_cmd)
    if not handle then
        reaper.ShowMessageBox("Failed to run Tesseract.", "OCR Error", 0)
        return
    end
    
    raw_text = handle:read("*a")
    handle:close()
    
    -- 3. Cleanup (optional)
    --os.remove(img_path)

    local lines = {}
    local is_first_line = true
    
    for line in raw_text:gmatch("[^\r\n]+") do
        -- Skip first line
        if is_first_line then
            is_first_line = false
        else 
            -- Trim whitespace first
            line = line:match("^%s*(.-)%s*$")
            
            if not line:match("^%s*Error") then
            
                -- Remove non-letters from start
                line = line:gsub("^[^%a]+", "")
                
                
                -- Conditional removal at end:
                -- If the last char is ) AND there is a ( somewhere earlier, keep it
                local has_open_paren = line:find("%(")
                local last_char = line:sub(-1)
                
                if last_char == ")" and (not has_open_paren or line:sub(1,-2):find("%(") == nil) then
                    -- Remove it if no matching (
                    line = line:sub(1, -2)
                    -- Also remove any other non-letter at end
                    line = line:gsub("[^%a]+$", "")
                else
                    -- Remove non-letter at end except allowed )
                    line = line:gsub("[^%a%)]+$", "")
                end
        
                -- Skip empty lines
                if line ~= "" then
                    table.insert(lines, line)
                end
            end
        end
    end
    return lines
end


function export.main()
    local os = reaper.GetOS()
    if os:find("OS") then
        return ocr_mac()
    else
        return {}
    end
end

return export