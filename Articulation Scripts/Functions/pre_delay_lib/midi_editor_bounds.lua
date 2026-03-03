-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description MidiEditorBounds
-- Parses MIDI Editor layout info from an item chunk and exposes
-- pixel positions of note rows. Designed to work with a cached chunk
-- passed in from MidiEditorStateWatcher.

local MidiEditorBounds = {}
MidiEditorBounds.__index = MidiEditorBounds

--- Creates a new MidiEditorBounds instance.
-- @param me    HWND of the active MIDI Editor
-- @param chunk optional — if provided, refresh() is called immediately
function MidiEditorBounds:new(me, chunk)
  local instance = {}
  setmetatable(instance, self)
  instance:_initialize(me)
  if chunk then instance:refresh(chunk) end
  return instance
end

function MidiEditorBounds:_initialize(me)
  self.me   = me
  self.take = nil

  -- Parsed layout state (nil until first refresh)
  self.piano_roll_top    = nil
  self.piano_roll_hbt    = nil
  self.piano_roll_bottom = nil
  self.leftmost_tick     = nil
  self.hzoom             = nil
  self.timeBase          = nil
  self.noteRowsMode      = nil
  self.midi_view_width   = nil
  self.midi_view_height  = nil
  self.vellane_height    = nil
  self.visible_rows      = nil
  self.visible_rows_lookup = nil
end

--- Refreshes layout state from a (possibly new) chunk.
-- Should be called whenever MidiEditorStateWatcher detects a change.
function MidiEditorBounds:refresh(chunk)
  local me   = self.me
  local take = reaper.MIDIEditor_GetTake(me)
  if not take then return end

  self.take = take

  local item  = reaper.GetMediaItemTake_Item(take)
  local track = reaper.GetMediaItemTake_Track(take)
  if not item or not track then return end

  local take_guid = reaper.BR_GetMediaItemTakeGUID(take)

  -- Single pass over the chunk — collect CFGEDITVIEW, CFGEDIT and VELLANE
  local stack         = {}
  local curguid       = nil
  local found         = {}
  local vellane_height = 0

  for line in chunk:gmatch("%s*([^\n\r]*)[\r\n]?") do
    local tag = line:match("^<([^%s]+)")
    if tag then stack[#stack+1] = tag end
    if line:match("^>") then stack[#stack] = nil end

    if #stack == 1 then
      local guid = line:match("^GUID ([^%s]+)")
      if guid then curguid = guid end
    end

    if #stack == 2 then
      -- VELLANE: accumulate regardless of take (all vellanes contribute)
      local _, height = line:match('VELLANE (%S+) (%S+)')
      if height then vellane_height = vellane_height + tonumber(height) end

      if curguid == take_guid then
        local s1, s2, s3, s4 = line:match('CFGEDITVIEW (%S+) (%S+) (%S+) (%S+)')
        if s1 then
          found.leftmost_tick  = tonumber(s1)
          found.hzoom          = tonumber(s2)
          found.piano_roll_top = tonumber(s3)
          found.piano_roll_hbt = tonumber(s4)
        end

        local _, s2, s3 = line:match('CFGEDIT %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (%S+) (%S+)')
        if s2 then
          found.noteRowsMode = tonumber(s2)
          found.timeBase     = tonumber(s3)
        end
      end
    end
  end

  self.piano_roll_top = found.piano_roll_top or 0
  self.piano_roll_hbt = found.piano_roll_hbt or 10
  self.leftmost_tick  = found.leftmost_tick  or 0
  self.hzoom          = found.hzoom
  self.timeBase       = found.timeBase
  self.noteRowsMode   = found.noteRowsMode
  self.vellane_height = vellane_height

  -- Get view dimensions
  local midiview        = reaper.JS_Window_FindChildByID(me, 0x3E9)
  local _, vw, vh       = reaper.JS_Window_GetClientSize(midiview)
  self.midi_view_width  = vw
  self.midi_view_height = vh

  -- Compute ret_zoom (pixels per second)
  local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, math.floor(0.5 + self.leftmost_tick))
  local end_time
  if self.timeBase == 0 or self.timeBase == 4 then
    end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, self.leftmost_tick + vw / self.hzoom)
  else
    end_time = start_time + vw / self.hzoom
  end
  self.start_time = start_time
  self.end_time   = end_time
  self.ret_zoom   = vw / (end_time - start_time)

  -- Y layout: time ruler (64px) at top, vellanes at bottom
  self.piano_roll_y_offset = 64
  self.piano_roll_bottom   = self.midi_view_height - self.vellane_height

  -- Visible note rows
  self:_computeVisibleRows(track)
end

--- Computes visible note rows depending on noteRowsMode.
function MidiEditorBounds:_computeVisibleRows(track)
  local me           = self.me
  local visible_rows = {}
  local mode         = self.noteRowsMode

  if mode == 0 then
    for n = 0, 127 do visible_rows[n+1] = n end
  else
    local GetSetting = reaper.MIDIEditor_GetSetting_int
    local SetSetting = reaper.MIDIEditor_SetSetting_int
    local prev_row   = GetSetting(me, 'active_note_row')
    local highest    = -1
    for i = 0, 127 do
      SetSetting(me, 'active_note_row', i)
      local row = GetSetting(me, 'active_note_row')
      if row > highest then
        highest = row
        visible_rows[#visible_rows+1] = row
      end
    end
    SetSetting(me, 'active_note_row', prev_row)
  end

  self.visible_rows = visible_rows

  -- Reverse lookup: note → index from top (0-based)
  self.visible_rows_lookup = {}
  for i, n in ipairs(visible_rows) do
    self.visible_rows_lookup[n] = #visible_rows - i
  end
end

--- Returns the pixel position (top, bottom) of a note row, and whether it's in the field of view.
-- Returns nil if the note is not in the visible rows.
-- @param n  MIDI note number (0-127)
function MidiEditorBounds:notePixelPosition(n)
  if not self.visible_rows_lookup then return nil end
  local idx = self.visible_rows_lookup[n]
  if idx == nil then return nil end

  local offset = self.piano_roll_y_offset or 0
  local top    = offset + (idx - self.piano_roll_top) * self.piano_roll_hbt
  local bottom = top + self.piano_roll_hbt
  local in_fov = top >= offset and top < self.piano_roll_bottom and bottom > offset

  return top, bottom, in_fov
end

--- Converts a PPQ position to a pixel X position in the MIDI Editor view.
-- Returns nil if bounds are not ready.
function MidiEditorBounds:notePPQToPixelX(ppq)
  if not self.start_time or not self.end_time or not self.midi_view_width then return nil end
  if not self.take then return nil end

  local t_note = reaper.MIDI_GetProjTimeFromPPQPos(self.take, ppq)
  local soff   = (t_note - self.start_time) / (self.end_time - self.start_time)

  return math.floor(soff * self.midi_view_width + 0.5)
end

--- Returns the list of visible note rows (MIDI note numbers, top to bottom).
function MidiEditorBounds:visibleNotes()
  return self.visible_rows or {}
end

--- Returns true if the bounds have been computed at least once.
function MidiEditorBounds:isReady()
  return self.visible_rows ~= nil
end

return MidiEditorBounds