-- @description Close all open FX windows
-- @author Saxmand
-- @version 1.0.1
-- @changelog
--   + works on all open tabs

-- Recursively close all floating FX windows inside an FX chain
function close_fx_chain_recursive(track, fx, is_take_fx, take)
    local takeOrTrackVar = is_take_fx and "Take" or "Track"
    local takeOrTrack = is_take_fx and take or track
    
    reaper[takeOrTrackVar .. "FX_Show"](takeOrTrack, fx, 0) -- non floating
    reaper[takeOrTrackVar .. "FX_Show"](takeOrTrack, fx, 2) -- hide floating
    
  
    local _, fx_type = reaper[takeOrTrackVar .. "FX_GetNamedConfigParm"](takeOrTrack, fx, "fx_type")
  
    if fx_type == "Container" then
        local _, container_fx_count = reaper[takeOrTrackVar .. "FX_GetNamedConfigParm"](takeOrTrack, fx, "container_count")
    
        container_fx_count = tonumber(container_fx_count)
        
        if container_fx_count then
            for i = 0, container_fx_count - 1 do 
                local _, sub_fx_index = reaper[takeOrTrackVar .. "FX_GetNamedConfigParm"](takeOrTrack, fx, "container_item." .. i) 
                close_fx_chain_recursive(track, sub_fx_index, is_take_fx, take) 
            end
        end
    end
end

function close_all_fx_windows()
  
  for p = 0, 99 do 
      local proj = reaper.EnumProjects(p)
      if not proj then
          break;
      else
          local num_tracks = reaper.CountTracks(proj)
        
          for i = 0, num_tracks - 1 do
            local track 
            if num_tracks == i then
                track = reaper.GetMasterTrack(proj)
            else
                track = reaper.GetTrack(proj, i)
            end
        
            -- Track FX
            local fx_count = reaper.TrackFX_GetCount(track)
            for fx = 0, fx_count - 1 do
                _, name = reaper.TrackFX_GetFXName(track, fx)
                close_fx_chain_recursive(track, fx, false, nil)
            end
            
            
            -- Take FX (in items on track)
            local item_count = reaper.CountTrackMediaItems(track)
            for j = 0, item_count - 1 do
              local item = reaper.GetTrackMediaItem(track, j)
              local take_count = reaper.CountTakes(item)
              for k = 0, take_count - 1 do
                local take = reaper.GetTake(item, k)
                if take then
                  local take_fx_count = reaper.TakeFX_GetCount(take)
                  for fx = 0, take_fx_count - 1 do
                    close_fx_chain_recursive(track, fx, true, take)
                  end
                end
              end
            end
          end
      end
  end
  -- Also ensure main floating chain window is closed (safe fallback)
  
  --reaper.Main_OnCommand(reaper.NamedCommandLookup("_S&M_WNCLS4"), 0) --SWS/S&M: Close all FX chain windows
end

reaper.Undo_BeginBlock()
close_all_fx_windows()
reaper.Undo_EndBlock("Close all FX windows (Track and Takes)", -1)


