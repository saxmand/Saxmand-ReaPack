-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description MidiEditorStateWatcher
-- Watches for layout changes in the MIDI Editor (scroll, zoom, resize, take change).
-- Calls the provided callback when something changes.
--
-- Detection strategy:
-- - Take change, resize : every frame (cheap)
-- - Chunk poll : adaptive throttle based on mouse position in view
--   - Mouse in view  → every CHUNK_INTERVAL_ACTIVE frames (~50ms)
--   - Mouse out      → every CHUNK_INTERVAL_IDLE frames (~500ms)

local MidiEditorStateWatcher = {}
MidiEditorStateWatcher.__index = MidiEditorStateWatcher

local CHUNK_INTERVAL_ACTIVE = 3   -- frames when mouse is in view
local CHUNK_INTERVAL_IDLE   = 30  -- frames when mouse is outside

function MidiEditorStateWatcher:new(me, hwnd_view, cb)
  local instance = {}
  setmetatable(instance, self)
  instance:_initialize(me, hwnd_view, cb)
  return instance
end

function MidiEditorStateWatcher:_initialize(me, hwnd_view, cb)
  self.me          = me
  self.hwnd_view   = hwnd_view
  self.cb          = cb
  self.take        = nil
  self.chunk       = nil
  self.view_l      = nil
  self.view_t      = nil
  self.view_r      = nil
  self.view_b      = nil
  self.frame_count = 0
  self._wheel_active_frames = 0
  self._last_wheel_time     = nil
  self._last_hwheel_time    = nil
  self._me_l     = nil
  self._me_r     = nil
  self._me_y_min = nil
  self._me_y_max = nil
  self:_refreshMERect()

  reaper.JS_WindowMessage_Intercept(hwnd_view, "WM_MOUSEWHEEL", true)
  reaper.JS_WindowMessage_Intercept(hwnd_view, "WM_MOUSEHWHEEL", true)
end

function MidiEditorStateWatcher:_refreshMERect()
  local ok, me_l, me_t, me_r, me_b = reaper.JS_Window_GetRect(self.me)
  if ok then
    self._me_l     = me_l
    self._me_r     = me_r
    self._me_y_min = math.min(me_t, me_b)
    self._me_y_max = math.max(me_t, me_b)
  end
end

function MidiEditorStateWatcher:implode()
  reaper.JS_WindowMessage_Release(self.hwnd_view, "WM_MOUSEWHEEL")
  reaper.JS_WindowMessage_Release(self.hwnd_view, "WM_MOUSEHWHEEL")
end

function MidiEditorStateWatcher:_readChunk(reason)
  local take = self.take
  if not take then return nil end
  local item = reaper.GetMediaItemTake_Item(take)
  if not item then return nil end
  local _, chunk = reaper.GetItemStateChunk(item, "", false)
  if chunk ~= self.chunk then
    self.chunk = chunk
    return reason
  end
  return nil
end

function MidiEditorStateWatcher:tick()
  local reasons    = {}
  self.frame_count = self.frame_count + 1

  -- 1. Take change — very cheap, pointer comparison
  local take = reaper.MIDIEditor_GetTake(self.me)
  if not (take == self.take) then
    reasons[#reasons+1] = "take"
    self.take  = take
    self.chunk = nil
  end

  -- 2. View bounds — catches resize
  -- Note: on macOS, JS_Window_GetRect returns inverted Y (view_b < view_t)
  local ok, vl, vt, vr, vb = reaper.JS_Window_GetRect(self.hwnd_view)
  if ok then
    if not (vl == self.view_l and vt == self.view_t and
            vr == self.view_r and vb == self.view_b) then
      reasons[#reasons+1] = "resize"
      self.view_l = vl
      self.view_t = vt
      self.view_r = vr
      self.view_b = vb
    end
  end

  -- 3. WM_MOUSEWHEEL peek — boosts throttle for a few frames after scroll
  local wok, _, _, wtime, _   = reaper.JS_WindowMessage_Peek(self.hwnd_view, "WM_MOUSEWHEEL")
  local hwok, _, _, hwtime, _ = reaper.JS_WindowMessage_Peek(self.hwnd_view, "WM_MOUSEHWHEEL")
  local new_wheel = (wok and wtime ~= self._last_wheel_time) or
                    (hwok and hwtime ~= self._last_hwheel_time)
  if wok  and wtime  ~= self._last_wheel_time  then self._last_wheel_time  = wtime  end
  if hwok and hwtime ~= self._last_hwheel_time then self._last_hwheel_time = hwtime end
  if new_wheel then
    self._wheel_active_frames = 10
  elseif self._wheel_active_frames > 0 then
    self._wheel_active_frames = self._wheel_active_frames - 1
  end

  -- 4. Adaptive chunk throttle based on mouse position in ME window (includes piano roll)
  local mx, my = reaper.GetMousePosition()
  local mouse_in_view = false
  if self._me_l then
    mouse_in_view = (mx >= self._me_l and mx <= self._me_r and
                     my >= self._me_y_min and my <= self._me_y_max)
  end

  -- Refresh ME rect cache every 30 frames (window rarely moves)
  if self.frame_count % 30 == 0 then self:_refreshMERect() end

  local interval = (self._wheel_active_frames > 0 or mouse_in_view)
    and CHUNK_INTERVAL_ACTIVE or CHUNK_INTERVAL_IDLE

  -- 5. Chunk poll — throttled
  if self.frame_count % interval == 0 then
    local r = self:_readChunk("chunk(poll)")
    if r then reasons[#reasons+1] = r end
  end

  if #reasons > 0 then
    if self.cb then self.cb(reasons) end
    return reasons
  end

  return nil
end

return MidiEditorStateWatcher