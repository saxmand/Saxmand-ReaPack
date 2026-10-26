-- @noindex
-- NKI Importer: imports the queued Kontakt files (ExtState "dropQueue": .nki/.nkm files and
-- folders). Started by the NKI Importer extension after a drop, or by the "Import selected NKI
-- files" actions - no need to run it yourself.
--   * Files load right away, one at a time - unless collect mode is on ("Collect files before
--     loading"): then they wait in the list window until you press Load.
--   * Folders always wait in the list, so you can check what they hold. On Load, their files
--     go into folder tracks named after the folders.
-- The list window takes drops itself too, and new files are picked up while it runs.

local script_dir = debug.getinfo(1, "S").source:match("^@?(.*[/\\])")
local C = dofile(script_dir .. "nki_common.lua")
if not C.checkRequirements() then return end
if not C.ensureKontakt() then
  reaper.DeleteExtState(C.section, "dropQueue", false)
  return
end

local LINGER = 1.5 -- seconds the window stays after everything loaded fine
local WIDTH = 480
local MAX_ROWS = 18
local ROW_H = 18
local INDENT = 14

local STATES = {
  held = { "", { 0.55, 0.55, 0.55 } },
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

-- { path, name, group (folder names, outermost first), state, step, error, placer }
-- state "held" = in the list, waiting for Load
local items = {}
local working = false
local stopRequested = false
local showGui = false
local gfxOpen = false
local finishedAt
local collectMode = C.get("collectMode")
local placer -- folder-aware track inserter, one per run (C.trackPlacer)

local function count(state)
  local n = 0
  for _, item in ipairs(items) do
    if item.state == state then n = n + 1 end
  end
  return n
end

-- A Kontakt file, or a folder (its Kontakt files, always held for review).
local function addPath(path, hold)
  path = path:gsub("[/\\]+$", "")
  if C.isKontaktFile(path) then
    items[#items + 1] = { path = path, name = C.nameFromPath(path), group = {},
      state = (hold or collectMode) and "held" or "waiting" }
  else
    for _, found in ipairs(C.expandFolder(path)) do
      items[#items + 1] = { path = found.path, name = C.nameFromPath(found.path), group = found.group, state = "held" }
    end
  end
end

local function pullQueue()
  local pending = reaper.GetExtState(C.section, "dropQueue")
  if pending == "" then return end
  reaper.DeleteExtState(C.section, "dropQueue", false)
  for path in pending:gmatch("[^\n]+") do addPath(path, false) end
end

local function removeHeld(match)
  for i = #items, 1, -1 do
    if items[i].state == "held" and match(items[i]) then table.remove(items, i) end
  end
end

local function inFolder(item, prefix)
  for i, name in ipairs(prefix) do
    if item.group[i] ~= name then return false end
  end
  return true
end

local function loadHeld()
  placer = placer or C.trackPlacer(C.insertIndexBelowSelection())
  for _, item in ipairs(items) do
    if item.state == "held" then
      item.state = "waiting"
      item.placer = placer
    end
  end
  stopRequested = false
end

-- Escape pressed anywhere in REAPER since the last check. While loading, Kontakt's window
-- and its Load dialog have the keyboard, not the list window, so gfx.getchar can't see it.
local escapeCheckedAt = reaper.time_precise()
local function escapePressed()
  if not reaper.JS_VKeys_GetDown then return false end
  local since = escapeCheckedAt
  escapeCheckedAt = reaper.time_precise()
  return (reaper.JS_VKeys_GetDown(since):byte(0x1B) or 0) ~= 0
end

local function startNext()
  for _, item in ipairs(items) do
    if item.state == "waiting" then
      if stopRequested then
        item.state = "skipped"
      else
        item.state = "loading"
        working = true
        local insert = item.placer and function(name) return item.placer.insert(name, item.group) end
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
        end, insert)
        return
      end
    end
  end
end

---------------------------------------------------------------- gfx window

local scale = 1
local lastMouseCap = 0
local scroll = 0 -- rows scrolled past the top
local windowRows -- rows the window was last sized for

-- The list as rows: a header for each folder level where the group changes, then the file,
-- plus a detail line for the current step or an error.
local function buildRows()
  local rows, previous = {}, {}
  for _, item in ipairs(items) do
    local group = item.group
    local shared = 0
    while shared < #group and shared < #previous and group[shared + 1] == previous[shared + 1] do
      shared = shared + 1
    end
    for level = shared + 1, #group do
      rows[#rows + 1] = { folder = group[level], depth = level - 1, prefix = { table.unpack(group, 1, level) } }
    end
    previous = group
    rows[#rows + 1] = { item = item, depth = #group }
    if (item.state == "loading" and item.step) or (item.state == "failed" and item.error) then
      rows[#rows + 1] = { detail = item, depth = #group }
    end
  end
  return rows
end

local function windowHeight(rows)
  return 10 + 20 + 14 + math.max(3, math.min(rows, MAX_ROWS)) * ROW_H + 12 + 26 + 10
end

local function fit(text, maxWidth)
  if gfx.measurestr(text) <= maxWidth then return text end
  while #text > 1 and gfx.measurestr(text .. "...") > maxWidth do text = text:sub(1, -2) end
  return text .. "..."
end

local function hovering(x, y, w, h)
  return gfx.mouse_x >= x and gfx.mouse_x < x + w and gfx.mouse_y >= y and gfx.mouse_y < y + h
end

local function clicked(x, y, w, h)
  return hovering(x, y, w, h) and lastMouseCap & 1 == 1 and gfx.mouse_cap & 1 == 0
end

-- Draws a button, returns true when clicked (released inside).
local function button(label, x, y, w, h)
  local shade = hovering(x, y, w, h) and 0.32 or 0.25
  gfx.set(shade, shade, shade)
  gfx.rect(x, y, w, h, 1)
  gfx.set(0.9, 0.9, 0.9)
  local tw, th = gfx.measurestr(label)
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - th) / 2
  gfx.drawstr(label)
  return clicked(x, y, w, h)
end

local function openWindow(rows)
  gfx.ext_retina = 1
  -- top-left corner of REAPER's main window (on macOS y grows upwards, so "top" > "bottom")
  local _, left, top, _, bottom = reaper.JS_Window_GetRect(reaper.GetMainHwnd())
  local margin = 60
  local y = top > bottom and top - margin or top + margin
  windowRows = math.min(#rows, MAX_ROWS)
  gfx.init("NKI Importer", WIDTH, windowHeight(#rows), 0, left + 10, y)
  scale = gfx.ext_retina > 0 and gfx.ext_retina or 1
  gfx.setfont(1, "Arial", 14 * scale)
  gfx.setfont(2, "Arial", 12 * scale)
  gfx.setfont(3, "Arial", 14 * scale, "b")
  gfxOpen = true
end

local function plural(n, word)
  return string.format("%d %s%s", n, word, n == 1 and "" or "s")
end

-- Returns "load", "clear" or "close" for the button/key the user used, if any.
local function drawWindow(rows, allDone)
  if math.min(#rows, MAX_ROWS) ~= windowRows then
    windowRows = math.min(#rows, MAX_ROWS)
    gfx.init("", WIDTH, windowHeight(#rows))
  end

  local s = scale
  local pad = 10 * s
  local rowH = ROW_H * s
  gfx.set(0.16, 0.16, 0.16)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  -- header + progress bar
  local held = count("held")
  local total = #items - held
  local finished = count("done") + count("failed") + count("skipped")
  local loading = working or count("waiting") > 0
  local title
  if total == 0 then
    title = held == 0 and "Drop .nki/.nkm files or folders here"
      or plural(held, "file") .. " ready - drop more files or folders here"
  elseif loading then
    title = string.format("Loading NKI files: %d / %d", finished, total)
  else
    title = string.format("Loaded %d / %d", count("done"), total)
  end
  if total > 0 and held > 0 then title = title .. string.format("  (+%d ready)", held) end
  gfx.setfont(1)
  gfx.set(0.9, 0.9, 0.9)
  gfx.x, gfx.y = pad, pad
  gfx.drawstr(fit(title, gfx.w - 2 * pad))
  local barY = pad + 20 * s
  if total > 0 then
    gfx.set(0.25, 0.25, 0.25)
    gfx.rect(pad, barY, gfx.w - 2 * pad, 6 * s, 1)
    gfx.set(0.38, 0.75, 0.38)
    gfx.rect(pad, barY, (gfx.w - 2 * pad) * finished / total, 6 * s, 1)
  end

  -- rows: the mouse wheel scrolls; while loading, the current file stays in view
  local listY = barY + 14 * s
  local footerY = gfx.h - pad - 22 * s
  local visible = math.max(1, math.floor((footerY - 12 * s - listY) / rowH))
  if gfx.mouse_wheel ~= 0 then
    scroll = scroll - math.floor(gfx.mouse_wheel / 120 * 3 + 0.5)
    gfx.mouse_wheel = 0
  end
  if working then
    for r, row in ipairs(rows) do
      if row.item and row.item.state == "loading" then
        if r <= scroll then scroll = r - 1 end
        if r + 1 > scroll + visible then scroll = r + 1 - visible end -- + its detail line
        break
      end
    end
  end
  scroll = math.max(0, math.min(scroll, #rows - visible))

  local removeX, removeW = gfx.w - pad - 14 * s, 14 * s
  for r = scroll + 1, math.min(#rows, scroll + visible) do
    local row = rows[r]
    local y = listY + (r - scroll - 1) * rowH
    local x = pad + row.depth * INDENT * s
    local removable
    if row.folder then
      gfx.setfont(3)
      gfx.set(0.55, 0.7, 0.9)
      gfx.x, gfx.y = x, y
      gfx.drawstr(fit(row.folder .. "/", removeX - x - 4 * s))
      for _, item in ipairs(items) do
        if item.state == "held" and inFolder(item, row.prefix) then removable = row break end
      end
    elseif row.item then
      local item = row.item
      local label, color = table.unpack(STATES[item.state])
      local nameX = x
      if label ~= "" then
        gfx.setfont(2)
        gfx.set(table.unpack(color))
        gfx.x, gfx.y = x, y + 2 * s
        gfx.drawstr(label)
        nameX = x + 60 * s
      end
      gfx.setfont(1)
      gfx.set(0.9, 0.9, 0.9)
      gfx.x, gfx.y = nameX, y
      gfx.drawstr(fit(item.name, removeX - nameX - 4 * s))
      if item.state == "held" then removable = row end
    else
      local item = row.detail
      gfx.setfont(2)
      gfx.set(table.unpack(item.state == "failed" and STATES.failed[2] or { 0.6, 0.6, 0.6 }))
      gfx.x, gfx.y = x + 60 * s, y
      gfx.drawstr(fit(item.state == "failed" and item.error or item.step, gfx.w - x - 60 * s - pad))
    end

    if removable then -- x: take the file, or every held file of the folder, off the list
      gfx.setfont(1)
      local hot = hovering(removeX, y, removeW, rowH)
      gfx.set(hot and 0.95 or 0.5, hot and 0.4 or 0.5, hot and 0.4 or 0.5)
      gfx.x, gfx.y = removeX + 3 * s, y
      gfx.drawstr("x")
      if clicked(removeX, y, removeW, rowH) then
        if removable.folder then
          removeHeld(function(item) return inFolder(item, removable.prefix) end)
        else
          removeHeld(function(item) return item == removable.item end)
        end
      end
    end
  end
  if #rows > visible then -- scroll position
    local trackH = visible * rowH
    gfx.set(0.3, 0.3, 0.3)
    gfx.rect(gfx.w - 4 * s, listY + trackH * scroll / #rows, 2 * s, math.max(8 * s, trackH * visible / #rows), 1)
  end

  -- footer: Clear / Stop on the left, Load / Close on the right
  local bw, bh = 170 * s, 22 * s
  local rightX = gfx.w - pad - bw
  local result
  gfx.setfont(1)
  if held > 0 then
    if button("Load " .. plural(held, "file"), rightX, footerY, bw, bh) then result = "load" end
  elseif allDone and total > 0 then
    if button("Close", rightX, footerY, bw, bh) then result = "close" end
  end
  if loading then
    if stopRequested then
      gfx.set(0.6, 0.6, 0.6)
      gfx.x, gfx.y = pad, footerY + 4 * s
      gfx.drawstr("Stopping after current file...")
    elseif button("Stop after current (Esc)", pad, footerY, bw, bh) then
      stopRequested = true
    end
  elseif held > 0 then
    if button("Clear", pad, footerY, 80 * s, bh) then result = "clear" end
  end

  lastMouseCap = gfx.mouse_cap
  local char = gfx.getchar()
  gfx.update()
  if char < 0 or (char == 27 and not loading) then result = "close" end
  if char == 27 and loading then stopRequested = true end
  if char == 13 and held > 0 then result = "load" end
  return result
end

---------------------------------------------------------------- main loop

local function loop()
  pullQueue()
  if gfxOpen then -- files and folders dropped onto the list window itself
    local i = 0
    while true do
      local ok, file = gfx.getdropfile(i)
      if not ok or ok == 0 then break end
      addPath(file, true)
      i = i + 1
    end
    if i > 0 then gfx.getdropfile(-1) end
  end
  if #items > 1 or count("held") > 0 then showGui = true end

  -- open the window between files only: it takes focus, which would disturb the
  -- clicks/keys going to Kontakt mid-load
  if showGui and not gfxOpen and not working then openWindow(buildRows()) end
  -- Escape while files are still waiting = "Stop after current" (checked every cycle, so an
  -- old press never counts); once nothing is left to load, later files load normally again
  if escapePressed() and count("waiting") > 0 then stopRequested = true end
  if not working and count("waiting") == 0 then stopRequested = false end
  if not working then startNext() end

  if gfxOpen then
    local action = drawWindow(buildRows(), not working and count("waiting") == 0 and count("held") == 0)
    if action == "load" then
      loadHeld()
    elseif action == "clear" then
      removeHeld(function() return true end)
    elseif action == "close" then
      gfx.quit()
      gfxOpen = false
      showGui = false
      removeHeld(function() return true end)
      -- closing mid-run: finish the current file, skip the rest
      if working or count("waiting") > 0 then stopRequested = true end
    end
  end

  local allDone = not working and count("waiting") == 0 and count("held") == 0
  if allDone then
    finishedAt = finishedAt or reaper.time_precise()
  else
    finishedAt = nil
  end
  -- an open window stays: after failures, on an empty list (waiting for drops), and briefly
  -- after everything loaded
  local keepWindow = allDone and gfxOpen and (count("failed") > 0 or #items == 0
    or reaper.time_precise() - finishedAt < LINGER)
  if allDone and not keepWindow then
    -- clear "busy" in the same cycle as the last queue check, so no drop can slip between
    reaper.DeleteExtState(C.section, "busy", false)
    return
  end
  reaper.defer(loop)
end

loop()
