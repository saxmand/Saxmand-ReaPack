-- @noindex
-- NKI Importer: imports the queued .nki files (ExtState "dropQueue").
-- Started by the NKI Importer extension after a drop, or by the "Import selected NKI files in
-- Finder" action - no need to run it yourself. While it runs it keeps picking up new files;
-- with more than one file it shows a progress window (gfx).

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")
if not C.checkRequirements() then return end
if not C.ensureKontakt() then
  reaper.DeleteExtState(C.section, "dropQueue", false)
  return
end

local LINGER = 1.5 -- seconds the window stays after everything loaded fine
local WIDTH = 440
local MAX_ROWS = 14

local STATES = {
  waiting = { "waiting", { 0.55, 0.55, 0.55 } },
  loading = { "loading", { 0.88, 0.69, 0.25 } },
  done = { "done", { 0.38, 0.75, 0.38 } },
  failed = { "failed", { 0.88, 0.38, 0.38 } },
  skipped = { "skipped", { 0.55, 0.55, 0.55 } },
}

-- Tells the extension a run is in progress, so new drops are only queued.
reaper.SetExtState(C.section, "busy", "1", false)
reaper.atexit(function()
  reaper.DeleteExtState(C.section, "busy", false)
  gfx.quit()
end)

local items = {} -- { path, name, state, step, error }
local working = false
local stopRequested = false
local showGui = false
local gfxOpen = false
local finishedAt

local function pullQueue()
  local pending = reaper.GetExtState(C.section, "dropQueue")
  if pending == "" then return end
  reaper.DeleteExtState(C.section, "dropQueue", false)
  for path in pending:gmatch("[^\n]+") do
    items[#items + 1] = { path = path, name = C.nameFromPath(path), state = "waiting" }
  end
  if #items > 1 then showGui = true end
end

local function startNext()
  for _, item in ipairs(items) do
    if item.state == "waiting" then
      if stopRequested then
        item.state = "skipped"
      else
        item.state = "loading"
        working = true
        C.importFile(item.path, function(line)
          item.step = line:match("^STEP (.-)%s+%[") or item.step
        end, function(ok, message, track, fx)
          item.state = ok and "done" or "failed"
          item.error = message and message:match("^[^\n]*")
          working = false
          -- batch: don't leave a Kontakt window open per file
          if ok and #items > 1 then reaper.TrackFX_Show(track, fx, 2) end
          if not ok and not showGui then
            reaper.ShowMessageBox("Loading " .. item.name .. " failed:\n\n" .. message, "NKI Importer", 0)
          end
        end)
        return
      end
    end
  end
end

local function count(state)
  local n = 0
  for _, item in ipairs(items) do
    if item.state == state then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------- gfx window

local scale = 1
local lastMouseCap = 0

-- Item rows shown: all of them, or a window that keeps the active item in view.
local function visibleRange()
  if #items <= MAX_ROWS then return 1, #items end
  local active = #items
  for i, item in ipairs(items) do
    if item.state == "loading" or item.state == "waiting" then active = i break end
  end
  local first = math.max(1, math.min(active - 3, #items - MAX_ROWS + 1))
  return first, first + MAX_ROWS - 1
end

local function rowLines(item)
  return ((item.state == "loading" and item.step) or (item.state == "failed" and item.error)) and 2 or 1
end

local function windowHeight()
  local first, last = visibleRange()
  local lines = 0
  for i = first, last do lines = lines + rowLines(items[i]) end
  return 10 + 20 + 14 + lines * 18 + 12 + 26 + 10
end

local function fit(text, maxWidth)
  if gfx.measurestr(text) <= maxWidth then return text end
  while #text > 1 and gfx.measurestr(text .. "...") > maxWidth do text = text:sub(1, -2) end
  return text .. "..."
end

-- Draws a button, returns true when clicked (released inside).
local function button(label, x, y, w, h)
  local hover = gfx.mouse_x >= x and gfx.mouse_x < x + w and gfx.mouse_y >= y and gfx.mouse_y < y + h
  gfx.set(hover and 0.32 or 0.25, hover and 0.32 or 0.25, hover and 0.32 or 0.25)
  gfx.rect(x, y, w, h, 1)
  gfx.set(0.9, 0.9, 0.9)
  local tw, th = gfx.measurestr(label)
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - th) / 2
  gfx.drawstr(label)
  return hover and lastMouseCap & 1 == 1 and gfx.mouse_cap & 1 == 0
end

local function openWindow()
  gfx.ext_retina = 1
  -- top-left corner of REAPER's main window (on macOS y grows upwards, so "top" > "bottom")
  local _, left, top, _, bottom = reaper.JS_Window_GetRect(reaper.GetMainHwnd())
  local margin = 60
  local y = top > bottom and top - margin or top + margin
  gfx.init("NKI Importer", WIDTH, windowHeight(), 0, left + 10, y)
  scale = gfx.ext_retina > 0 and gfx.ext_retina or 1
  gfx.setfont(1, "Arial", 14 * scale)
  gfx.setfont(2, "Arial", 12 * scale)
  gfxOpen = true
end

-- Returns "close" when the window was closed or the Close button pressed.
local function drawWindow(allDone)
  local wantHeight = windowHeight()
  if math.abs(gfx.h / scale - wantHeight) > 1 then gfx.init("", WIDTH, wantHeight) end

  local s = scale
  local pad = 10 * s
  gfx.set(0.16, 0.16, 0.16)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  -- header + progress bar
  local finished = count("done") + count("failed") + count("skipped")
  gfx.setfont(1)
  gfx.set(0.9, 0.9, 0.9)
  gfx.x, gfx.y = pad, pad
  gfx.drawstr(string.format("Loading NKI files: %d / %d", finished, #items))
  local barY = pad + 20 * s
  gfx.set(0.25, 0.25, 0.25)
  gfx.rect(pad, barY, gfx.w - 2 * pad, 6 * s, 1)
  gfx.set(0.38, 0.75, 0.38)
  gfx.rect(pad, barY, (gfx.w - 2 * pad) * finished / #items, 6 * s, 1)

  -- item rows
  local y = barY + 14 * s
  local first, last = visibleRange()
  for i = first, last do
    local item = items[i]
    local label, color = table.unpack(STATES[item.state])
    gfx.setfont(2)
    gfx.set(table.unpack(color))
    gfx.x, gfx.y = pad, y + 2 * s
    gfx.drawstr(label)
    gfx.setfont(1)
    gfx.set(0.9, 0.9, 0.9)
    gfx.x, gfx.y = pad + 60 * s, y
    gfx.drawstr(fit(item.name, gfx.w - 70 * s - pad))
    y = y + 18 * s
    if rowLines(item) == 2 then
      gfx.setfont(2)
      gfx.set(table.unpack(item.state == "failed" and color or { 0.6, 0.6, 0.6 }))
      gfx.x, gfx.y = pad + 60 * s, y
      gfx.drawstr(fit(item.state == "failed" and item.error or item.step, gfx.w - 70 * s - pad))
      y = y + 18 * s
    end
  end

  -- footer button
  local bw, bh = 140 * s, 22 * s
  local bx, by = gfx.w - pad - bw, gfx.h - pad - bh
  gfx.setfont(1)
  local result
  if allDone then
    if button("Close", bx, by, bw, bh) then result = "close" end
  elseif not stopRequested then
    if button("Stop after current", bx, by, bw, bh) then stopRequested = true end
  else
    gfx.set(0.6, 0.6, 0.6)
    gfx.x, gfx.y = pad, by + 4 * s
    gfx.drawstr("Stopping after current file...")
  end

  lastMouseCap = gfx.mouse_cap
  local char = gfx.getchar()
  gfx.update()
  if char < 0 or char == 27 then result = "close" end
  return result
end

---------------------------------------------------------------- main loop

local function loop()
  pullQueue()

  -- open the window between files only: it takes focus, which would disturb the
  -- clicks/keys going to Kontakt mid-load
  if showGui and not gfxOpen and not working then openWindow() end
  if not working then startNext() end

  local allDone = not working and count("waiting") == 0
  if allDone then
    finishedAt = finishedAt or reaper.time_precise()
  else
    finishedAt = nil
  end

  local closed = false
  if gfxOpen then
    closed = drawWindow(allDone) == "close"
    if closed then
      gfx.quit()
      gfxOpen = false
      showGui = false
      -- closing mid-run: finish the current file, skip the rest
      if not allDone then stopRequested = true end
    end
  end

  if allDone and not (gfxOpen and (count("failed") > 0 or reaper.time_precise() - finishedAt < LINGER)) then
    -- clear "busy" in the same cycle as the last queue check, so no drop can slip between
    reaper.DeleteExtState(C.section, "busy", false)
    return
  end
  reaper.defer(loop)
end

loop()
