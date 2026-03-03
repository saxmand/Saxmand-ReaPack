-- =============================================================================
-- MidiEditorCanvas.lua
-- Canvas library overlaid on the REAPER MIDI Editor using JS_Lice API.
-- Each VirtualBitmap is composited directly onto the MIDI Editor view.
--
-- Design intent: once VirtualBitmaps are positioned, the lib is fully passive.
-- JS_Composite is only re-called when position, size, or visibility changes.
-- Use setPosition() and setSize() — do NOT modify _x, _y, _w, _h directly.
-- =============================================================================

local MidiEditorCanvas = {}
MidiEditorCanvas.__index = MidiEditorCanvas

-- ---------------------------------------------------------------------------
-- VirtualBitmap
-- ---------------------------------------------------------------------------

local VirtualBitmap = {}
VirtualBitmap.__index = VirtualBitmap

--- Creates a new VirtualBitmap at position (x, y) with size (w, h).
-- Not visible and not allocated until attached to a canvas.
function VirtualBitmap.new(x, y, w, h)
  local self = setmetatable({}, VirtualBitmap)
  self._x      = x
  self._y      = y
  self._w      = w
  self._h      = h
  self.visible = false
  self.dirty   = false
  self.bitmap  = nil
  self.queue   = {}
  self._canvas = nil
  -- Cached composite rect (last registered with JS_Composite)
  self._c_dst_x = nil
  self._c_dst_y = nil
  self._c_dst_w = nil
  self._c_dst_h = nil
  self._c_src_x = nil
  self._c_src_y = nil
  return self
end

--- Sets the position of the VirtualBitmap. Marks it dirty.
function VirtualBitmap:setPosition(x, y)
  if x == self._x and y == self._y then return end
  self._x    = x
  self._y    = y
  self.dirty = true
end

--- Sets the size of the VirtualBitmap. Marks it dirty and resizes LICE bitmap.
function VirtualBitmap:setSize(w, h)
  local new_w = math.max(1, math.floor(w))
  local new_h = math.max(1, math.floor(h))
  if new_w == self._w and new_h == self._h then return end
  self._w    = new_w
  self._h    = new_h
  self.dirty = true
  if self.bitmap then
    reaper.JS_LICE_Resize(self.bitmap, self._w, self._h)
    reaper.JS_LICE_Clear(self.bitmap, 0x00000000)
    self:_replayQueue()
    self:_resetCompositeCache()
  end
end

-- Internal: replay all queued draw commands onto the bitmap.
function VirtualBitmap:_replayQueue()
  for _, cmd in ipairs(self.queue) do
    cmd(self.bitmap)
  end
end

-- Internal: allocate the LICE bitmap and replay the queue.
function VirtualBitmap:_allocate()
  if self.bitmap then return end
  self.bitmap = reaper.JS_LICE_CreateBitmap(true, self._w, self._h)
  reaper.JS_LICE_Clear(self.bitmap, 0x00000000)
  self:_replayQueue()
  self:_updateComposite()
  self.dirty = false
end

-- Internal: destroy the LICE bitmap and unlink JS_Composite.
function VirtualBitmap:_deallocate()
  if not self.bitmap then return end
  if self._canvas then
    pcall(function()
      reaper.JS_Composite_Unlink(self._canvas.hwnd_view, self.bitmap, true)
    end)
  end
  reaper.JS_LICE_DestroyBitmap(self.bitmap)
  self.bitmap = nil
  self.dirty  = false
  self:_resetCompositeCache()
end

-- Internal: clear cached composite coords (forces re-registration).
function VirtualBitmap:_resetCompositeCache()
  self._c_dst_x = nil
  self._c_dst_y = nil
  self._c_dst_w = nil
  self._c_dst_h = nil
  self._c_src_x = nil
  self._c_src_y = nil
end

-- Internal: update JS_Composite only when clipped rect has changed.
function VirtualBitmap:_updateComposite()
  if not self.bitmap then return end
  local src_x = math.floor(math.max(0, -self._x))
  local src_y = math.floor(math.max(0, -self._y))
  local dst_x = math.floor(math.max(0, self._x))
  local dst_y = math.floor(math.max(0, self._y))
  local dst_w = math.floor(math.min(self._w - src_x, self._canvas.w - dst_x))
  local dst_h = math.floor(math.min(self._h - src_y, self._canvas.h - dst_y))

  if dst_w <= 0 or dst_h <= 0 then return end

  if self._c_dst_x == dst_x and self._c_dst_y == dst_y and
     self._c_dst_w == dst_w and self._c_dst_h == dst_h and
     self._c_src_x == src_x and self._c_src_y == src_y then
    return
  end

  reaper.JS_Composite(self._canvas.hwnd_view,
                      dst_x, dst_y, dst_w, dst_h,
                      self.bitmap,
                      src_x, src_y, dst_w, dst_h, true)
  self._c_dst_x = dst_x
  self._c_dst_y = dst_y
  self._c_dst_w = dst_w
  self._c_dst_h = dst_h
  self._c_src_x = src_x
  self._c_src_y = src_y
end

--- Fully destroys the VirtualBitmap.
function VirtualBitmap:destroy()
  self:_deallocate()
  self.queue   = {}
  self._canvas = nil
end

--- Clears all draw commands and resets the bitmap to transparent.
function VirtualBitmap:clear()
  self.queue = {}
  if self.bitmap then
    reaper.JS_LICE_Clear(self.bitmap, 0x00000000)
    self.dirty = true
  end
end

-- ---------------------------------------------------------------------------
-- Draw commands
-- ---------------------------------------------------------------------------

-- Internal: registers and immediately executes a draw command.
function VirtualBitmap:_addCmd(cmd)
  table.insert(self.queue, cmd)
  if self.bitmap then cmd(self.bitmap); self.dirty = true end
end

function VirtualBitmap:fillRect(x, y, w, h, color)
  self:_addCmd(function(bmp)
    reaper.JS_LICE_FillRect(bmp, x, y, w, h, color, 1.0, "COPY")
  end)
end

function VirtualBitmap:line(x1, y1, x2, y2, color, aa)
  self:_addCmd(function(bmp)
    reaper.JS_LICE_Line(bmp, x1, y1, x2, y2, color, 1.0, "COPY", aa ~= false)
  end)
end

function VirtualBitmap:circle(cx, cy, r, color, filled)
  self:_addCmd(function(bmp)
    if filled then
      reaper.JS_LICE_FillCircle(bmp, cx, cy, r, color, 1.0, "COPY", true)
    else
      reaper.JS_LICE_Circle(bmp, cx, cy, r, color, 1.0, "COPY", true)
    end
  end)
end

function VirtualBitmap:drawText(text, x, y, font, color)
  self:_addCmd(function(bmp)
    reaper.JS_LICE_DrawText(bmp, font, text, #text, x, y, x + self._w, y + self._h)
  end)
end

-- ---------------------------------------------------------------------------
-- MidiEditorCanvas
-- ---------------------------------------------------------------------------

function MidiEditorCanvas.new(hwnd_midi_editor)
  local self = setmetatable({}, MidiEditorCanvas)
  self.hwnd_editor = hwnd_midi_editor or reaper.MIDIEditor_GetActive()
  if not self.hwnd_editor or self.hwnd_editor == 0 then
    error("MidiEditorCanvas: no active MIDI Editor found.")
  end
  self.hwnd_view = self:_findMidiView(self.hwnd_editor)
  self.w, self.h = 1, 1
  self:_resizeIfNeeded()
  self.virtual_bitmaps = {}
  return self
end

function MidiEditorCanvas:_findMidiView(hwnd_editor)
  local child = reaper.JS_Window_FindChildByID(hwnd_editor, 1001)
  if child and child ~= 0 then return child end
  return hwnd_editor
end

function MidiEditorCanvas:_resizeIfNeeded()
  local ok, cw, ch = reaper.JS_Window_GetClientSize(self.hwnd_view)
  if not ok then return end
  local nw = math.max(1, cw)
  local nh = math.max(1, ch)
  if nw == self.w and nh == self.h then return end
  self.w, self.h = nw, nh
  for _, vb in ipairs(self.virtual_bitmaps or {}) do
    vb:_resetCompositeCache()
    vb.dirty = true
  end
end

-- ---------------------------------------------------------------------------
-- Attachment API
-- ---------------------------------------------------------------------------

function MidiEditorCanvas:attach(vb)
  for _, v in ipairs(self.virtual_bitmaps) do
    if v == vb then return vb end
  end
  vb._canvas = self
  table.insert(self.virtual_bitmaps, vb)
  self:_updateVisibility(vb)
  return vb
end

function MidiEditorCanvas:detach(vb, destroy)
  for i, v in ipairs(self.virtual_bitmaps) do
    if v == vb then
      table.remove(self.virtual_bitmaps, i)
      vb:_deallocate()
      if destroy then vb:destroy() end
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------------

function MidiEditorCanvas:_updateVisibility(vb)
  local was_visible = vb.visible
  vb.visible = (vb._x < self.w  and vb._x + vb._w > 0 and
                vb._y < self.h  and vb._y + vb._h > 0)

  if vb.visible and not was_visible then
    vb:_allocate()
  elseif not vb.visible and was_visible then
    vb:_deallocate()
  elseif vb.visible then
    vb:_updateComposite()
    vb.dirty = false
  end
end

function MidiEditorCanvas:_updateAllVisibility()
  for _, vb in ipairs(self.virtual_bitmaps) do
    if vb.dirty or
       (vb.visible and not vb.bitmap) or
       (not vb.visible and vb.bitmap) then
      self:_updateVisibility(vb)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Update / destroy
-- ---------------------------------------------------------------------------

--- Main update — call this every defer() frame.
-- Fully passive if nothing has changed.
function MidiEditorCanvas:update()
  self:_resizeIfNeeded()
  self:_updateAllVisibility()
end

--- Frees all resources.
function MidiEditorCanvas:destroy()
  for _, vb in ipairs(self.virtual_bitmaps) do
    vb:_deallocate()
  end
  self.virtual_bitmaps = {}
end

function MidiEditorCanvas:getSize()     return self.w, self.h end
function MidiEditorCanvas:getViewHWND() return self.hwnd_view end

-- ---------------------------------------------------------------------------
-- Public exports
-- ---------------------------------------------------------------------------

return {
  Canvas        = MidiEditorCanvas,
  VirtualBitmap = VirtualBitmap,
}