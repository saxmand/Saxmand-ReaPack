-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description PreDelayEngine
-- Manages one PreDelayOverlay per MIDI Editor.
-- Overlays are created lazily when a ME becomes active, and cleaned up
-- when the ME is no longer valid.
--
-- Usage:
--   local engine = PreDelayEngine.new()
--   engine:setOnChange(function(overlay, reasons) ... end)
--   engine:tick()    -- call every frame
--   engine:destroy() -- on shutdown

local PreDelayOverlay = require("pre_delay_lib.pre_delay_overlay")

-- ---------------------------------------------------------------------------

local PreDelayEngine = {}
PreDelayEngine.__index = PreDelayEngine

function PreDelayEngine.new()
  local self = setmetatable({}, PreDelayEngine)
  self._overlays   = {}   -- address → PreDelayOverlay
  self._delay_maps = {}   -- address → delay_map
  self._provider   = nil
  return self
end

--- Sets the delay map for a specific ME.
-- @param me   HWND of the MIDI Editor
-- @param map  table: title (string) → delay_ms (number)
function PreDelayEngine:setDelayMapForME(me, map)
  local address = reaper.JS_Window_AddressFromHandle(me)
  self._delay_maps[address] = map or {}
  local overlay = self._overlays[address]
  if overlay then overlay:setDelayMap(self._delay_maps[address]) end
end

--- Sets a provider called when a ME needs a fresh delay map.
-- @param provider  function(track) → table: title (string) → delay_ms (number)
function PreDelayEngine:setDelayMapProvider(provider)
  self._provider = provider
  for _, overlay in pairs(self._overlays) do
    self:_wireCallback(overlay)
  end
end

--- Forces a delay map refresh for all MEs whose active take is on the given track.
-- Useful when the plugin detects an external change (e.g. articulation edited).
function PreDelayEngine:triggerDelayMapRefreshForTrack(track)
  if not self._provider then return end
  for address, overlay in pairs(self._overlays) do
    local take = reaper.MIDIEditor_GetTake(overlay.me)
    if take then
      local t = reaper.GetMediaItemTake_Track(take)
      if t == track then
        local map = self._provider(track)
        self:setDelayMapForME(overlay.me, map)
      end
    end
  end
end

--- Sets colors for all current and future overlays.
function PreDelayEngine:setColors(line_color, bar_color)
  self._line_color = line_color
  self._bar_color  = bar_color
  for _, overlay in pairs(self._overlays) do
    overlay:setColors(line_color, bar_color)
  end
end

--- Main entry point — call every frame from the plugin's defer loop.
function PreDelayEngine:tick()
  -- Ensure the active ME has an overlay
  local me = reaper.MIDIEditor_GetActive()
  if me and me ~= 0 then
    self:_getOrCreateOverlay(me)
  end

  -- Cleanup closed MEs
  self:_cleanupObsolete()

  -- Tick all visible overlays
  for _, overlay in pairs(self._overlays) do
    if reaper.JS_Window_IsVisible(overlay.me) then
      overlay:tick()
    end
  end
end

--- Release all resources.
function PreDelayEngine:destroy()
  for _, overlay in pairs(self._overlays) do
    overlay:destroy()
  end
  self._overlays = {}
end

-- ---------------------------------------------------------------------------
-- Private
-- ---------------------------------------------------------------------------

function PreDelayEngine:_getOrCreateOverlay(me)
  local address = reaper.JS_Window_AddressFromHandle(me)
  if self._overlays[address] then return self._overlays[address] end

  local overlay = PreDelayOverlay.new()
  overlay:setME(me)
  if self._delay_maps[address] then
    overlay:setDelayMap(self._delay_maps[address])
  end
  if self._line_color or self._bar_color then
    overlay:setColors(self._line_color, self._bar_color)
  end
  self:_wireCallback(overlay)
  self._overlays[address] = overlay
  return overlay
end

function PreDelayEngine:_wireCallback(overlay)
  if not self._provider then return end
  overlay:setOnChange(function(reasons)
    local take = reaper.MIDIEditor_GetTake(overlay.me)
    if not take then return end
    local track = reaper.GetMediaItemTake_Track(take)
    if not track then return end
    local map = self._provider(track)
    self:setDelayMapForME(overlay.me, map)
  end)
end

function PreDelayEngine:_cleanupObsolete()
  local torem = {}
  for address, overlay in pairs(self._overlays) do
    if not reaper.ValidatePtr(overlay.me, "HWND") then
      torem[address] = true
    end
  end
  for address, _ in pairs(torem) do
    self._overlays[address]:destroy()
    self._overlays[address]  = nil
    self._delay_maps[address] = nil
  end
end

return PreDelayEngine