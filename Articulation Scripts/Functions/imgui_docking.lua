-- @noindex

local export = {}

local function DockName(dock_id)
  if dock_id == 0 then
    return 'Floating'
  elseif dock_id > 0 then
    return ('ImGui docker %d'):format(dock_id)
  end

  -- reaper.DockGetPosition was added in v6.02
  local positions = {
    [0]='Bottom', [1]='Left', [2]='Top', [3]='Right', [4]='Floating'
  }
  local position = reaper.DockGetPosition and
    positions[reaper.DockGetPosition(~dock_id)] or 'Unknown'
  return ('REAPER docker %d (%s)'):format(-dock_id, position)
end

function export.dropdown(ctx) 
    --current_dock_id = reaper.ImGui_GetWindowDockID(ctx) -- should be at end of window
    local dock_id = current_dock_id
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, 'Dock:')
    reaper.ImGui_SameLine(ctx)
    --reaper.ImGui_SetNextItemWidth(ctx, 170)
    if reaper.ImGui_BeginCombo(ctx, '##docker', DockName(dock_id)) then
      if reaper.ImGui_Selectable(ctx, 'Floating', dock_id == 0) then
        set_dock_id = 0
      end
      for id = -1, -16, -1 do
        if reaper.ImGui_Selectable(ctx, DockName(id), dock_id == id) then
          set_dock_id = id
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
end

function export.setCurrent(ctx)
    current_dock_id = reaper.ImGui_GetWindowDockID(ctx)
end

function export.update(ctx)
    if set_dock_id then
        
        reaper.ImGui_SetNextWindowDockID(ctx, set_dock_id)
        set_dock_id = nil
    end
end

return export
