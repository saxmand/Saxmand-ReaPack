-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description PreDelayOverlay
-- Renders pre-delay indicators on the MIDI Editor for each articulated note.
-- For each note with a known delay, draws:
--   - A 1px horizontal line at mid-height, going left by delay_ms
--   - A 1px vertical bar at the delay position, note row height
--
-- Usage:
--   local overlay = PreDelayOverlay.new()       -- starts dormant
--   overlay:setME(me)                            -- attach to a MIDI Editor
--   overlay:setDelayMap({ ["Art"] = 300 })       -- provide delay map
--   overlay:setColors(0xFFFFFFFF, 0xFFFFFFFF)    -- optional
--   overlay:tick()                               -- call every frame
--   overlay:destroy()                            -- on shutdown

local CanvasLib         = require("pre_delay_lib.midi_editor_canvas")
local Watcher           = require("pre_delay_lib.midi_editor_state_watcher")
local Bounds            = require("pre_delay_lib.midi_editor_bounds")

-- ---------------------------------------------------------------------------

local PreDelayOverlay   = {}
PreDelayOverlay.__index = PreDelayOverlay

function PreDelayOverlay.new()
  local self      = setmetatable({}, PreDelayOverlay)
  self.me         = nil
  self.canvas     = nil
  self.bounds     = nil
  self.watcher    = nil
  self.delay_map  = {}
  self.line_color = 0xFFFFFFFF
  self.bar_color  = 0xFFFFFFFF
  self._h_lines   = {}
  self._v_bars    = {}
  self._pool_size = 0
  return self
end

--- Attaches the overlay to a MIDI Editor. Pass nil to detach.
function PreDelayOverlay:setME(me)
  if me == self.me then return end

  -- Tear down previous resources
  if self.watcher then
    self.watcher:implode(); self.watcher = nil
  end
  if self.canvas then
    self.canvas:destroy(); self.canvas = nil
  end
  self.bounds     = nil
  self._h_lines   = {}
  self._v_bars    = {}
  self._pool_size = 0
  self.me         = me

  if not me then return end

  -- Set up new resources
  local hwnd_view = reaper.JS_Window_FindChildByID(me, 1001)
  if not hwnd_view or hwnd_view == 0 then hwnd_view = me end

  self.canvas     = CanvasLib.Canvas.new(me)
  self.bounds     = Bounds:new(me)
  self.watcher    = Watcher:new(me, hwnd_view, nil)
  self.watcher.cb = function(reasons) self:_onChange(reasons) end

  self:_refreshFromME()
end

--- Called by the plugin to update the delay map.
function PreDelayOverlay:setDelayMap(map)
  self.delay_map = map or {}
  self:_redraw()
end

--- Sets an optional external callback, called on every state change.
function PreDelayOverlay:setOnChange(cb)
  self._on_change = cb
  if self.watcher then self.watcher.cb = function(r) self:_onChange(r) end end
end

--- Called by the plugin to update overlay colors.
function PreDelayOverlay:setColors(line_color, bar_color)
  self.line_color = line_color or self.line_color
  self.bar_color  = bar_color or self.bar_color
end

--- Main entry point — call every frame from the plugin's defer loop.
function PreDelayOverlay:tick()
  if not self.me then return end
  self.watcher:tick()
  self.canvas:update()
end

--- Release all resources.
function PreDelayOverlay:destroy()
  self:setME(nil)
end

-- ---------------------------------------------------------------------------
-- Private
-- ---------------------------------------------------------------------------

function PreDelayOverlay:_getOrCreatePair(idx)
  if not self._h_lines[idx] then
    local hl = CanvasLib.VirtualBitmap.new(0, 0, 1, 1)
    self.canvas:attach(hl)
    self._h_lines[idx] = hl
  end
  if not self._v_bars[idx] then
    local vb = CanvasLib.VirtualBitmap.new(0, 0, 1, 1)
    self.canvas:attach(vb)
    self._v_bars[idx] = vb
  end
  return self._h_lines[idx], self._v_bars[idx]
end

function PreDelayOverlay:_hidePair(idx)
  if self._h_lines[idx] then
    self._h_lines[idx]:setPosition(-100, -100)
    self._h_lines[idx].dirty = true
  end
  if self._v_bars[idx] then
    self._v_bars[idx]:setPosition(-100, -100)
    self._v_bars[idx].dirty = true
  end
end

function PreDelayOverlay:_onChange(reasons)
  self:_refreshFromME()
  if self._on_change then self._on_change(reasons) end
end

function PreDelayOverlay:_refreshFromME()
  if not self.me then return end
  local take = reaper.MIDIEditor_GetTake(self.me)
  if not take then return end
  local item = reaper.GetMediaItemTake_Item(take)
  if not item then return end
  local _, chunk = reaper.GetItemStateChunk(item, "", false)
  self.bounds:refresh(chunk)
  self:_redraw()
end

function PreDelayOverlay:_redraw()
  local bounds = self.bounds
  if not bounds or not bounds:isReady() then return end

  local take = bounds.take
  if not take then return end

  local _, notecnt = reaper.MIDI_CountEvts(take)

  -- Pass 1: index notation events by PPQ+chan+pitch
  local text_by_ppq_pitch = {}
  local ti = 0
  while true do
    local ok, _, _, ppq, _, evtype, _ = reaper.MIDI_GetTextSysexEvt(take, ti)
    if not ok then break end
    --[[ local chan, pitch, text = tostring(evtype):match('NOTE (%d+) (%d+) text "(.+)"$')
    if chan and pitch and text then
      text_by_ppq_pitch[ppq .. "_" .. chan .. "_" .. pitch] = text
    end ]]

    local eventType, channel, pitch, articulation = evtype:match('(%S+) (%d+) (%d+) text%s+"?([^"]+)"?')
    if eventType == "NOTE" and tonumber(channel) and tonumber(ppq) and tonumber(pitch) then
      text_by_ppq_pitch[ppq .. "_" .. channel .. "_" .. pitch] = articulation
    end

    ti = ti + 1
  end

  function split_exact(str, sep)
    if not str then return {} end
    sep = sep or " / "
    local t = {}
    local pattern = "(.-)" .. sep:gsub("(%p)", "%%%1") -- escape special chars
    local last_end = 1
    local s, e, cap = str:find(pattern, 1)
    while s do
      table.insert(t, cap)
      last_end = e + 1
      s, e, cap = str:find(pattern, last_end)
    end
    table.insert(t, str:sub(last_end))

    if t[#t] == "" then t[#t] = nil end

    return t
  end

  -- Pass 2: notes
  local used = 0

  local last_pitch, last_chan, last_endppq, last_startppq, last_vel, last_last_endppq
  local filterCount = 0
  for i = 0, notecnt - 1 do
    -- add sustain pedal
    local ok, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
    if ok and not muted then
      local note_x              = bounds:notePPQToPixelX(startppq)
      local top, bottom, in_fov = bounds:notePixelPosition(pitch)

      if not last_last_endppq then
        filterCount = filterCount + 1
      elseif last_last_endppq > startppq then
        filterCount = filterCount + 1
      else
        filterCount = filterCount - 1
      end

      if note_x and top and in_fov then
        local text = text_by_ppq_pitch[startppq .. "_" .. chan .. "_" .. pitch]
        local arts = split_exact(text)
        local delay_ms

        local function isWithinType(art, _type, val)
          if art[_type] and art[_type] ~= "" then --and art.Position ~= "First" then
            if not art[_type .. "Type"] or art[_type .. "Type"] == "Fixed" or art[_type .. "Type"] == "" then
              if val == art[_type] then return true end
            elseif art[_type .. "Type"] == "Minimum" then
              if val >= art[_type] then return true end
            elseif art[_type .. "Type"] == "Maximum" then
              if val <= art[_type] then return true end
            elseif art[_type .. "Type"] == "Within" and art[_type .. "2"] then
              local val2 = (art[_type .. "2"] and art[_type .. "2"] ~= "") and art[_type .. "2"] or 127
              if val >= art[_type] and val <= art[_type .. "2"] then return true end
            elseif art[_type .. "Type"] == "Outside" and art[_type .. "2"] then
              if val < art[_type] and val > art[_type .. "2"] then return true end
            end
          else
            return true
          end
        end

        for i, a in ipairs(arts) do
          if self.delay_map[a] then
            for _, art in ipairs(self.delay_map[a]) do
              if art.Delay then
                -- position
                local Position = art.Position
                local sustainPedal = false
                local distanceBetweenLastEndAndNewStart = last_endppq and
                math.floor((reaper.MIDI_GetProjTimeFromPPQPos(take, last_endppq) - reaper.MIDI_GetProjTimeFromPPQPos(take, startppq)) * 1000) + max_time_to_reset_legato or nil
                if (not Position or Position == "Any" or Position == "")
                    or (Position == "First" and (not distanceBetweenLastEndAndNewStart or (distanceBetweenLastEndAndNewStart < 0 and not sustainPedal)))
                    or (Position == "Repeated" and (last_pitch and last_pitch == pitch and (distanceBetweenLastEndAndNewStart >= 0 or sustainPedal)))
                    or (Position == "First+Repeated" and ((not distanceBetweenLastEndAndNewStart or (distanceBetweenLastEndAndNewStart <= 0 and not sustainPedal)) or (last_pitch and last_pitch == pitch and (distanceBetweenLastEndAndNewStart >= 0 or sustainPedal))))
                    or (Position == "Legato" and (last_pitch and last_pitch ~= pitch and (distanceBetweenLastEndAndNewStart >= 0 or sustainPedal)))
                then
                  if Position == "First+Repeated" and (not distanceBetweenLastEndAndNewStart or (distanceBetweenLastEndAndNewStart <= 0 and not sustainPedal)) then
                    Position = "First"
                  end
                  -- interval
                  if (Position == "First") or (not last_pitch or isWithinType(art, "FilterInterval", math.abs(last_pitch - pitch))) then
                    --reaper.ShowConsoleMsg(pitch .. " - " .. tostring(Position) .. " - "  .. tostring(distanceBetweenLastEndAndNewStart) .. "\n")
                    -- speed
                    if not last_startppq or isWithinType(art, "FilterSpeed", math.floor((reaper.MIDI_GetProjTimeFromPPQPos(take, startppq) - reaper.MIDI_GetProjTimeFromPPQPos(take, last_startppq)) * 1000)) then
                      -- velocity
                      if isWithinType(art, "FilterVelocity", vel) then
                        -- count
                        if isWithinType(art, "FilterCount", filterCount) then
                          --reaper.ShowConsoleMsg(pitch .. " - " .. Position .. " - " .. art.Delay .. " - FilterInterval: " .. tostring(art.FilterInterval) .. " - FilterIntervalType: " .. tostring(art.FilterIntervalType) .. " - distanceBetweenLastEndAndNewStart: " .. tostring(distanceBetweenLastEndAndNewStart) .. "\n")
                          delay_ms = art.Delay
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        if delay_ms then
          local predelay_px = math.floor(delay_ms / 1000.0 * bounds.ret_zoom)
          local row_h       = math.max(1, math.floor(bottom - top))
          local mid_y       = math.floor(top + row_h / 2)
          local bar_x       = note_x - predelay_px

          used              = used + 1
          local hl, vb      = self:_getOrCreatePair(used)

          hl.queue          = {}
          hl:setSize(predelay_px, 1)
          hl:setPosition(bar_x, mid_y)
          hl:fillRect(0, 0, predelay_px, 1, self.line_color)
          hl.dirty = true

          vb.queue = {}
          vb:setSize(1, row_h)
          vb:setPosition(bar_x, math.floor(top))
          vb:fillRect(0, 0, 1, row_h, self.bar_color)
          vb.dirty = true
        end
      end
      last_pitch = pitch
      last_chan = chan
      last_vel = vel
      last_endppq = endppq
      last_startppq = startppq
      if not last_last_endppq or last_last_endppq < last_endppq then
        last_last_endppq = last_endppq
      else
        filterCount = filterCount - 1
      end
    end
  end

  for idx = used + 1, self._pool_size do self:_hidePair(idx) end
  self._pool_size = math.max(self._pool_size, used)
end

return PreDelayOverlay
