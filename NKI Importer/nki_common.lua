-- @noindex
-- NKI Importer - shared code (macOS and Windows).
-- Usage: local C = dofile(script_dir .. "nki_common.lua")
--
-- Loading an .nki (instrument) or .nkm (multi) = clicking Kontakt's File > Load... and filling
-- in its open dialog:
--   macOS:   nki_helper.js (JXA) in the background - real clicks, System Events for the dialog
--   Windows: js_ReaScriptAPI from a defer loop - Kontakt (Qt) takes posted mouse messages as
--            long as the real cursor is on the target, and the dialog is a standard #32770

local C = {}

C.dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
C.helper = C.dir .. "nki_helper.js"
C.section = "Saxmand_NKI_Importer"
C.workDir = (os.getenv("TMPDIR") or "/tmp/") .. "nki_importer/"
C.isMac = reaper.GetOS():match("OSX") ~= nil or reaper.GetOS():match("macOS") ~= nil
C.isWindows = reaper.GetOS():match("Win") ~= nil

-- Tells the extension where the import script lives (ReaPack may install it anywhere).
do
  local importScript = C.dir .. "Saxmand_NKI Importer - Import dropped files.lua"
  if reaper.GetExtState(C.section, "importScript") ~= importScript then
    reaper.SetExtState(C.section, "importScript", importScript, true)
  end
end

-- Persistent settings (ExtState), with defaults.
C.defaults = {
  fxName = "", -- chosen on first use (C.ensureKontakt)
  -- Fallback click offsets for a Kontakt without its own (see C.getOffset):
  clickX = 180, -- Kontakt "Files" icon, relative to the floating FX window's top-left (incl. title bar)
  clickY = 74,
  loadX = -1, -- "Load..." item in the Files menu, same reference; -1 = use menuKeys instead (macOS)
  loadY = -1,
  menuKeys = "125,36", -- macOS key codes sent after the click: down, return ("Load...")
  menuDelay = 0.25, -- Windows: seconds between clicking Files and Load...
  dialogTitle = "Load",
  openButton = "Open",
  guiDelay = 0, -- extra seconds to let Kontakt's GUI settle before clicking
  closeWindowAfter = false,
}

function C.get(key)
  local default = C.defaults[key]
  if not reaper.HasExtState(C.section, key) then return default end
  local v = reaper.GetExtState(C.section, key)
  if type(default) == "number" then return tonumber(v) or default end
  if type(default) == "boolean" then return v == "true" end
  return v
end

function C.set(key, value)
  reaper.SetExtState(C.section, key, tostring(value), true)
end

---------------------------------------------------------------- Kontakt version

-- Click offsets per platform and Kontakt major version, used until calibrated ("Calibrate Kontakt clicks").
C.kontaktOffsets = {
  mac = {
    ["7"] = { clickX = 176, clickY = 77, loadX = 182, loadY = 105 },
    ["8"] = { clickX = 176, clickY = 77, loadX = 182, loadY = 128 }, -- estimated from a screenshot
  },
  win = { -- measured at 100% display scaling
    ["7"] = { clickX = 181, clickY = 75, loadX = 183, loadY = 104 },
    ["8"] = { clickX = 181, clickY = 75, loadX = 183, loadY = 127 }, -- estimated from macOS
  },
}

local function offsetKey(name)
  return name .. "_" .. C.get("fxName"):gsub("[^%w]", "")
end

-- clickX/clickY/loadX/loadY for the chosen Kontakt: calibrated > version default > global.
function C.getOffset(name)
  local key = offsetKey(name)
  if reaper.HasExtState(C.section, key) then return tonumber(reaper.GetExtState(C.section, key)) end
  local platform = C.kontaktOffsets[C.isMac and "mac" or "win"]
  local defaults = platform[C.get("fxName"):match("Kontakt (%d+)") or ""]
  if defaults then return defaults[name] end
  return C.get(name)
end

function C.setOffset(name, value)
  reaper.SetExtState(C.section, offsetKey(name), tostring(value), true)
end

-- Installed Kontakt instruments as TrackFX_AddByName names, VST3 preferred.
function C.installedKontakts()
  local all, vst3, seen = {}, {}, {}
  local i = 0
  while true do
    local ok, name = reaper.EnumInstalledFX(i)
    if not ok then break end
    i = i + 1
    name = name:gsub("%s*%(%d+ out%)$", "")
    if name:match("^%w+i: Kontakt") and not seen[name] then
      seen[name] = true
      all[#all + 1] = name
      if name:match("^VST3i:") then vst3[#vst3 + 1] = name end
    end
  end
  local list = #vst3 > 0 and vst3 or all
  table.sort(list)
  return list
end

-- Popup menu at the mouse to pick the Kontakt to use. Returns false when cancelled.
function C.chooseKontakt()
  local list = C.installedKontakts()
  if #list == 0 then
    reaper.ShowMessageBox("No Kontakt instrument plug-in found.", "NKI Importer", 0)
    return false
  end
  local current = C.get("fxName")
  local menu = { "#Which Kontakt should NKI Importer use?", "" }
  for _, name in ipairs(list) do menu[#menu + 1] = (name == current and "!" or "") .. name end

  local x, y = reaper.GetMousePosition()
  gfx.init("", 0, 0, 0, x, y)
  gfx.x, gfx.y = 0, 0
  -- the grayed header counts as item 1, the separator doesn't count
  local choice = gfx.showmenu(table.concat(menu, "|")) - 1
  gfx.quit()
  if choice < 1 then return false end
  C.set("fxName", list[choice])
  return true
end

-- Makes sure a Kontakt is chosen: picks the only one installed, or asks once.
function C.ensureKontakt()
  if C.get("fxName") ~= "" then return true end
  local list = C.installedKontakts()
  if #list == 1 then
    C.set("fxName", list[1])
    return true
  end
  return C.chooseKontakt()
end

function C.checkRequirements()
  if not C.isMac and not C.isWindows then
    reaper.ShowMessageBox("NKI Importer runs on macOS and Windows only.", "NKI Importer", 0)
    return false
  end
  if not reaper.JS_Window_GetTitle then
    reaper.ShowMessageBox("Requires js_ReaScriptAPI (ReaPack).", "NKI Importer", 0)
    return false
  end
  return true
end

---------------------------------------------------------------- macOS helper process

local function shellQuote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function jsonString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function jsonEncode(t)
  local parts = {}
  for k, v in pairs(t) do
    local value = type(v) == "string" and jsonString(v) or tostring(v)
    parts[#parts + 1] = jsonString(k) .. ":" .. value
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function writeFile(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

local runCounter = 0

-- Runs the JXA helper in the background and polls its status file via defer.
-- onLine(line) is called for each new status line, onDone(ok, lines) once at the end.
function C.runHelper(mode, job, onLine, onDone, timeoutSec)
  reaper.RecursiveCreateDirectory(C.workDir, 0)
  runCounter = runCounter + 1
  local base = C.workDir .. string.format("%s_%d_%d", mode, os.time(), runCounter)
  local jobPath, statusPath, errPath = base .. ".json", base .. ".status", base .. ".err"
  writeFile(jobPath, jsonEncode(job))

  os.execute(string.format("/usr/bin/osascript -l JavaScript %s %s %s %s > %s 2>&1 &",
    shellQuote(C.helper), mode, shellQuote(jobPath), shellQuote(statusPath), shellQuote(errPath)))

  local started = reaper.time_precise()
  local seen = 0
  local lines = {}

  local function finish(ok)
    os.remove(jobPath)
    os.remove(statusPath)
    os.remove(errPath)
    onDone(ok, lines)
  end

  local function poll()
    local text = readFile(statusPath) or ""
    local i = 0
    for line in text:gmatch("[^\n]+") do
      i = i + 1
      if i > seen then
        seen = i
        lines[#lines + 1] = line
        if onLine then onLine(line) end
        if line == "DONE" then return finish(true) end
        if line:match("^ERROR") then return finish(false) end
      end
    end
    -- osascript itself failed (syntax error, killed, ...)
    local err = readFile(errPath)
    if err and err:match("%S") then
      lines[#lines + 1] = "ERROR: osascript: " .. err
      return finish(false)
    end
    if reaper.time_precise() - started > (timeoutSec or 60) then
      lines[#lines + 1] = "ERROR: timed out waiting for helper"
      return finish(false)
    end
    reaper.defer(poll)
  end
  reaper.defer(poll)
end

-- Turns helper error numbers into something actionable.
function C.permissionHint(lines)
  local all = table.concat(lines, "\n")
  if all:match("%-1743") then
    return "\n\nREAPER is not allowed to control System Events.\nSystem Settings > Privacy & Security > Automation > REAPER > System Events."
  end
  if all:match("%-1719") or all:match("%-25211") or all:match("AXIsProcessTrusted false")
    or all:match("PostEventAccess false") or all:match("Mouse events are blocked") then
    return "\n\nREAPER needs Accessibility access.\nSystem Settings > Privacy & Security > Accessibility > add/enable REAPER, then restart REAPER."
  end
  return ""
end

---------------------------------------------------------------- Windows automation

-- Posted click: Kontakt (Qt) only accepts it with the real cursor on the target.
local function winClick(fxHwnd, x, y)
  reaper.JS_Window_SetForeground(fxHwnd) -- in front of anything covering the spot
  local target = reaper.JS_Window_FromPoint(x, y)
  local cx, cy = reaper.JS_Window_ScreenToClient(target, x, y)
  reaper.JS_Mouse_SetPosition(x, y)
  reaper.JS_Window_SetFocus(target)
  reaper.JS_WindowMessage_Post(target, "WM_MOUSEMOVE", 0, 0, cx, cy)
  reaper.JS_WindowMessage_Post(target, "WM_LBUTTONDOWN", 1, 0, cx, cy)
  reaper.JS_WindowMessage_Post(target, "WM_LBUTTONUP", 0, 0, cx, cy)
  return target
end

local function winHandles(list)
  local result = {}
  for address in list:gmatch("[^,]+") do
    result[#result + 1] = reaper.JS_Window_HandleFromAddress(tonumber(address))
  end
  return result
end

local function winFindDialog(title)
  local _, list = reaper.JS_Window_ListAllTop()
  for _, hwnd in ipairs(winHandles(list)) do
    if reaper.JS_Window_IsVisible(hwnd) and reaper.JS_Window_GetClassName(hwnd) == "#32770"
      and reaper.JS_Window_GetTitle(hwnd):find(title, 1, true) then
      return hwnd
    end
  end
end

-- The "File name" field of the standard open dialog: the Edit with ID 1148 (cmb13).
-- (The address bar is also an Edit inside a ComboBox, ID 41477.)
local function winFileNameEdit(dialog)
  local _, list = reaper.JS_Window_ListAllChild(dialog)
  for _, hwnd in ipairs(winHandles(list)) do
    if reaper.JS_Window_GetClassName(hwnd) == "Edit" and reaper.JS_Window_GetLong(hwnd, "ID") == 1148 then
      return hwnd
    end
  end
end

-- Runs a defer-driven step function until it returns true (done) or a string (error).
-- Same reporting as C.runHelper: onLine(line) per status line, onDone(ok, lines).
local function winRun(steps, onLine, onDone, timeoutSec)
  local lines = {}
  local started = reaper.time_precise()
  local step, stepStart = 1, started
  local mouseX, mouseY = reaper.GetMousePosition()

  local ctx = {}
  function ctx.status(line)
    if line:match("^STEP") then line = line .. string.format("  [%.2fs]", reaper.time_precise() - started) end
    lines[#lines + 1] = line
    if onLine then onLine(line) end
  end
  function ctx.elapsed() return reaper.time_precise() - stepStart end
  function ctx.restoreMouse() reaper.JS_Mouse_SetPosition(mouseX, mouseY) end

  local function finish(ok, err)
    lines[#lines + 1] = ok and "DONE" or "ERROR: " .. err
    if onLine then onLine(lines[#lines]) end
    onDone(ok, lines)
  end

  local function poll()
    local result = steps[step](ctx)
    if type(result) == "string" then return finish(false, result) end
    if result then
      step = step + 1
      stepStart = reaper.time_precise()
      if not steps[step] then return finish(true) end
    end
    if reaper.time_precise() - started > timeoutSec then return finish(false, "timed out") end
    reaper.defer(poll)
  end
  poll()
end

local function winLoad(job, fxHwnd, onLine, onDone, timeoutSec)
  local _, left, top = reaper.JS_Window_GetRect(fxHwnd)
  local dialog
  winRun({
    function(ctx)
      if ctx.elapsed() < job.guiDelay then return false end
      if job.loadX < 0 then return "No position for \"Load...\" - run \"Calibrate Kontakt clicks\" for this Kontakt first" end
      ctx.status(string.format("STEP click Files button (offset %d,%d)", job.clickX, job.clickY))
      local target = winClick(fxHwnd, left + job.clickX, top + job.clickY)
      if not reaper.JS_Window_IsChild(fxHwnd, target) then
        ctx.status("STEP warning: something covers Kontakt at that spot")
      end
      return true
    end,
    function(ctx)
      if ctx.elapsed() < job.menuDelay then return false end
      ctx.status(string.format("STEP click Load... (offset %d,%d)", job.loadX, job.loadY))
      winClick(fxHwnd, left + job.loadX, top + job.loadY)
      ctx.restoreMouse()
      ctx.status('STEP wait for dialog containing "' .. job.dialogTitle .. '"')
      return true
    end,
    function(ctx)
      dialog = winFindDialog(job.dialogTitle)
      if not dialog then
        return ctx.elapsed() > 10 and "Load dialog did not appear - run \"Calibrate Kontakt clicks\""
      end
      local edit = winFileNameEdit(dialog)
      if not edit then return "File name field not found in the Load dialog" end
      ctx.status("STEP open file")
      reaper.JS_Window_SetTitle(edit, job.path)
      reaper.JS_WindowMessage_Post(dialog, "WM_COMMAND", 1, 0, 0, 0) -- IDOK
      return true
    end,
    function(ctx)
      -- Kontakt loads the instrument on REAPER's main thread, so this resumes after loading
      if not reaper.JS_Window_IsWindow(dialog) or not reaper.JS_Window_IsVisible(dialog) then return true end
      if ctx.elapsed() > 5 then
        reaper.JS_WindowMessage_Post(dialog, "WM_COMMAND", 2, 0, 0, 0) -- IDCANCEL
        return "Load dialog did not accept the file"
      end
      return false
    end,
  }, onLine, onDone, timeoutSec)
end

-- Same lines as the macOS helper: COUNTDOWN <Files|Load> <n>, OFFSET <files|load> <x> <y>.
local function winCalibrate(fxHwnd, countdown, onLine, onDone)
  local target
  local function offset(ctx, which)
    local x, y = reaper.GetMousePosition()
    local _, left, top = reaper.JS_Window_GetRect(fxHwnd)
    ctx.status(string.format("OFFSET %s %d %d", which, x - left, y - top))
    return x, y
  end
  local function counter(label)
    local shown
    return function(ctx)
      local left = math.ceil(countdown - ctx.elapsed())
      if left > 0 then
        if left ~= shown then
          shown = left
          ctx.status(string.format("COUNTDOWN %s %d", label, left))
        end
        return false
      end
      return true
    end
  end
  winRun({
    counter("Files"),
    function(ctx)
      target = winClick(fxHwnd, offset(ctx, "files"))
      return true
    end,
    counter("Load"),
    function(ctx)
      offset(ctx, "load")
      -- close the menu again
      reaper.JS_WindowMessage_Post(target, "WM_KEYDOWN", 0x1B, 0, 1, 0)
      reaper.JS_WindowMessage_Post(target, "WM_KEYUP", 0x1B, 0, 1, 0xC000)
      return true
    end,
  }, onLine, onDone, countdown * 2 + 30)
end

---------------------------------------------------------------- REAPER side

-- Kontakt files NKI Importer loads: instruments (.nki) and multis (.nkm).
function C.isKontaktFile(path)
  local ext = path:lower():match("%.(%w+)$")
  return ext == "nki" or ext == "nkm"
end

function C.nameFromPath(path)
  return path:match("([^/\\]+)%.[nN][kK][iImM]$") or path:match("([^/\\]+)$")
end

-- Inserts a track with Kontakt, floats the plugin window.
-- Returns track, fxIndex, window title, window  -or-  nil, error message.
function C.createKontaktTrack(name)
  reaper.Undo_BeginBlock()
  reaper.Main_OnCommand(40001, 0) -- Track: Insert new track
  local track = reaper.GetSelectedTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

  local fxName = C.get("fxName")
  local fx = reaper.TrackFX_AddByName(track, fxName, false, -1)
  if fx < 0 then
    reaper.Undo_EndBlock("NKI Importer: insert track", -1)
    return nil, "Could not add FX: " .. fxName
  end

  reaper.Undo_EndBlock("NKI Importer: insert " .. name, -1)

  reaper.TrackFX_Show(track, fx, 3)
  local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
  if not hwnd then return nil, "Plugin window did not open" end
  return track, fx, reaper.JS_Window_GetTitle(hwnd), hwnd
end

function C.loadJob(path, fxTitle)
  return {
    path = path,
    fxTitle = fxTitle,
    clickX = C.getOffset("clickX"),
    clickY = C.getOffset("clickY"),
    loadX = C.getOffset("loadX"),
    loadY = C.getOffset("loadY"),
    menuKeys = C.get("menuKeys"),
    menuDelay = C.get("menuDelay"),
    dialogTitle = C.get("dialogTitle"),
    openButton = C.get("openButton"),
    guiDelay = C.get("guiDelay"),
    restoreMouse = true,
  }
end

-- Clicks File > Load... in the floating Kontakt window and opens job.path.
-- onLine(line) gets progress, onDone(ok, lines) is called at the end.
function C.runLoad(job, fxHwnd, onLine, onDone)
  if C.isMac then
    C.runHelper("load", job, onLine, onDone, 180)
  else
    winLoad(job, fxHwnd, onLine, onDone, 180)
  end
end

-- Measures the Files button and "Load..." item while the user hovers them (the "Calibrate Kontakt clicks" action).
function C.calibrate(fxTitle, fxHwnd, countdown, onLine, onDone)
  if C.isMac then
    C.runHelper("calibrate", { fxTitle = fxTitle, countdown = countdown }, onLine, onDone, countdown * 2 + 30)
  else
    winCalibrate(fxHwnd, countdown, onLine, onDone)
  end
end

-- Imports one file: new track with Kontakt, then File > Load... with the .nki/.nkm.
-- onLine(line) gets progress, onDone(ok, message, track, fx) is called at the end; on
-- failure message is the error plus a permission hint where one applies.
function C.importFile(path, onLine, onDone)
  local track, fx, title, hwnd = C.createKontaktTrack(C.nameFromPath(path))
  if not track then return onDone(false, fx) end

  C.runLoad(C.loadJob(path, title), hwnd, onLine, function(ok, lines)
    if not ok then return onDone(false, lines[#lines] .. C.permissionHint(lines), track, fx) end
    if C.get("closeWindowAfter") then reaper.TrackFX_Show(track, fx, 2) end
    onDone(true, nil, track, fx)
  end)
end

-- Imports the files one by one, logging progress. onDone(ok) is called when finished or on
-- the first failure.
function C.importFiles(files, log, onDone)
  local index = 0
  local startTime = reaper.time_precise()

  local function nextFile()
    index = index + 1
    local path = files[index]
    if not path then
      log(string.format("All done (%d files, %.1fs)", #files, reaper.time_precise() - startTime))
      return onDone(true)
    end

    local name = C.nameFromPath(path)
    log(string.format("[%d/%d] %s", index, #files, name))
    C.importFile(path, function(line)
      log("  " .. line)
    end, function(ok, message)
      if not ok then
        reaper.ShowMessageBox("Loading " .. name .. " failed:\n\n" .. message, "NKI Importer", 0)
        return onDone(false)
      end
      nextFile()
    end)
  end

  nextFile()
end

-- Adds files to the import queue (same one the extension fills on drops). Returns true when
-- the import script is already running and will pick them up.
function C.enqueue(files)
  local queue = reaper.GetExtState(C.section, "dropQueue")
  for _, path in ipairs(files) do
    queue = queue == "" and path or queue .. "\n" .. path
  end
  reaper.SetExtState(C.section, "dropQueue", queue, false)
  return reaper.GetExtState(C.section, "busy") == "1"
end

-- Lists the selection of every open Explorer window into a UTF-8 file (console output would
-- go through the OEM code page and mangle non-ASCII paths).
local EXPLORER_PS1 = [==[
param([string]$out)
$paths = @()
$shell = New-Object -ComObject Shell.Application
foreach ($w in $shell.Windows()) {
  try { foreach ($i in $w.Document.SelectedItems()) { $paths += $i.Path } } catch {}
}
[IO.File]::WriteAllLines($out, [string[]]$paths)
]==]

-- Paths of the Kontakt files selected in Finder (macOS) or in open Explorer windows (Windows).
-- Also returns what the Finder/Explorer query printed, for diagnosing an empty result.
function C.selectedKontaktFiles()
  local text, output
  if C.isMac then
    output = reaper.ExecProcess("/usr/bin/osascript -e " .. shellQuote([[
tell application "Finder" to set sel to selection as alias list
set out to ""
repeat with f in sel
  set out to out & POSIX path of f & linefeed
end repeat
return out]]), 10000) or ""
    text = output
  else
    local temp = os.getenv("TEMP") or C.dir
    local ps1, outFile = temp .. "\\nki_importer_explorer.ps1", temp .. "\\nki_importer_explorer.txt"
    writeFile(ps1, EXPLORER_PS1)
    os.remove(outFile)
    output = reaper.ExecProcess(string.format(
      'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%s" "%s"', ps1, outFile), 15000) or ""
    text = readFile(outFile) or ""
    os.remove(outFile)
  end

  local files = {}
  -- (on macOS the ExecProcess output starts with the exit code line - not a path)
  for line in text:gmatch("[^\r\n]+") do
    if C.isKontaktFile(line) then files[#files + 1] = line end
  end
  return files, output
end

-- The "Import selected NKI files in Finder/Explorer" actions: queue the selection and run
-- the import script (or let the already running one pick the files up).
function C.importSelectedFiles()
  local files, output = C.selectedKontaktFiles()
  if #files == 0 then
    local where = C.isMac and "Finder" or "Explorer"
    local msg = "No .nki or .nkm files selected in " .. where .. "."
    if output:match("%S") and not output:match("^%s*0%s*$") then
      msg = msg .. "\n\n" .. where .. " query returned:\n" .. output:sub(1, 1000)
    end
    reaper.ShowMessageBox(msg, "NKI Importer", 0)
    return
  end
  if C.enqueue(files) then return end
  dofile(C.dir .. "Saxmand_NKI Importer - Import dropped files.lua")
end

return C
