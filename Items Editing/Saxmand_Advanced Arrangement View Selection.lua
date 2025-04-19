-- @description Advanced Arrangment View Selection
-- @author saxmand
-- @version 0.3.2

--[[
Known issues:
- Selecting envelope points in automation items, only works, when a single item is at that specific point in the timeline.
  So if you have two items visually stacked, the automation points will not get selected properly.
- dragging beyond the start of the timeline can create a few unexpected results.

]]

if not reaper.JS_Mouse_GetState then
    reaper.ShowMessageBox("This script requires the js_ReaScriptAPI extension.\nPlease install it via ReaPack.", "Missing Extension", 0)
    return
end

------------ SCRIPT SETTINGS ------------
local AUTOMATION_ITEMS_ONLY_REPRESENTED_BY_BOTTOM_STRIP = false

local ALLOW_VALUE_CHANGE_OF_ENVLOPES = true
local ALLOW_TENSION_CHANGE_OF_ENVLOPES = true
local ONLY_MOVE_POINTS_ON_SHOWN_TRACKS = true

local ALLOW_MOVING_WITH_KEY_COMMANDS = true

local CHANGE_LENGTH_WITH_SCRIPT = true
local ALLOW_CHANGING_LENGTH_WITH_KEY_COMMANDS = true

local CHANGE_PLAYRATE_WITH_SCRIPT = true
local ALLOW_CHANGING_PLAYRATE_WITH_KEY_COMMANDS = true

local MOVE_AUTOMATION_ITEMS_WITH_SCRIPT = true
local MOVE_MEDIA_ITEMS_WITH_SCRIPT = true

local ALLOW_COPY_ITEMS_OF_SELECTION = true
local ALLOW_DELETE_ITEMS_OF_SELECTION = false

-- I'm not sure how to best copy the automation items. Now they do not retain their full length (in case they are shorter than what they were original created. Because of this the end points can be weird, so we can chose to add this. 
local INSERT_EDGE_POINTS_WHEN_COPYING_AUTOMATION_ITEMS = true

-- cycles through all tracks automation items
local COPY_AUTOMATION_ITEMS_WITH_NO_MEDIA_ITEMS_SELECTED_ON_THAT_TRACK = true

local MOUSE_DRAG_DETECTION_MS = 200

local ADD_TO_SELECTION_MOUSE_STATE_NUMBER = 8 -- Shift on mac
local INVERT_SELECTION_MOUSE_STATE_NUMBER = 4 -- Command on mac

    
local relativeTrack = 5
local relativePos = 1

-- Turn off move envelope points with media items as standard
if reaper.GetToggleCommandState(40070) == 1 then
    --®reaper.Main_OnCommand(40070, 0) --Options: Move envelope points with media items
end

local isWindows = reaper.GetOS():match("Win") ~= nil
local isApple = reaper.GetOS():match("macOS") ~= nil
local shift, ctrl, alt, super, mouseState
local undoName = "Saxmand_Advanced selection"
-----------------------------------------
------------ TOOLBAR SETTINGS -----------
-----------------------------------------
local _,_,_,cmdID = reaper.get_action_context()
-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end

------------------------------------------
-------------- FINISHED ------------------
------------------------------------------



-- Initialize variables to track mouse state and positions
local lastMouseState, mouseStartX, mouseStartY, mousePosX, mousePosY
local mouseStartOnItem --, startTrackIndex, startMouseRelativeToTrack
local selectedEnvelope, lastSelectedEnvelope, lastSelectedEnvelopePointIndex
local isMouseDown = false
local lastItemUnderMouseSelected = false
local envelopesState = {}
local selectedEnvelopePointsCountInEnvelope = 0
local lastSelectedEnvelopePointsCountInEnvelope = 0
local lastHoveredItem = nil
local lastSelectedEnvelopePointsInEnvelope = {}
local lastHooveredEnvelope = {}
local lastTimeOfClickedEnvelopePoint, lastValueOfClickedEnvelopePoint, lastTensionOfClickedEnvelopePoint


local main_hwnd = reaper.GetMainHwnd()
local arrange_hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000)




function convertScaledFaderValueToVisuelValue(value, range)
    return reaper.ScaleToEnvelopeMode( 1, value )/852.77445440699*range
end

function convertVisuelValueToScaledFaderValue(value, range)
    return reaper.ScaleFromEnvelopeMode( 1, value*852.77445440699/range )
end






function unselectAllAutomationItems(selectedEnvelope)
    -- Loop through all tracks
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local envCount = reaper.CountTrackEnvelopes(track)
        -- Loop through all envelopes on the track
        for j = 0, envCount - 1 do
            local envelope = reaper.GetTrackEnvelope(track, j)

            if (not selectedEnvelope or selectedEnvelope ~= envelope) then
                local numAutomationItems = reaper.CountAutomationItems( envelope )
                for k = 0, numAutomationItems - 1 do
                    if reaper.GetSetAutomationItemInfo( envelope, k, "D_UISEL", 0, false ) == 1 then
                        reaper.GetSetAutomationItemInfo( envelope, k, "D_UISEL", 0, true )
                    end
                end
                local point_count = reaper.CountEnvelopePoints(envelope)
                for i = 0, point_count - 1 do
                    reaper.SetEnvelopePoint(envelope, i, nil, nil, nil, nil, false, false) 
                end
                reaper.Envelope_SortPoints(envelope)
            end
        end
    end 
end



-- 🎯 Run and print results


-- Function to get the pixel position of a specific time in the arrange view
local function getPositionOfTimeFromPixelPos(pos)
    -- Get the dimensions of the arrange window
    local _, left, _, right, _ = reaper.JS_Window_GetRect(arrange_hwnd)

    -- Calculate the width of the arrange window
    local arrangeWidth = right - left

    -- Get the visible time range in the arrange view
    local viewStartTime, viewEndTime = reaper.GetSet_ArrangeView2(0, false, 0, 0)

    -- Calculate the duration of the visible time range
    local visibleDuration = viewEndTime - viewStartTime

    -- Normalize the time position to a range of [0, 1] based on the visible time range
    local normalizedPos = (pos - left) / arrangeWidth

    -- Calculate the pixel position in the arrange view
    local positionInTime = viewStartTime + (normalizedPos * visibleDuration)

    return positionInTime
end


function getTimePositionOfCursor()
    local mousePosTimeline = reaper.BR_GetMouseCursorContext_Position()
    if mousePosTimeline == -1 then
        local mousePosX, mousePosY = reaper.GetMousePosition()
        mousePosTimeline = getPositionOfTimeFromPixelPos(mousePosX)
    end
    return mousePosTimeline ~= -1 and mousePosTimeline or nil
end

local function getPositionOfTrackY() 
    local _, mousePosY = reaper.GetMousePosition()
    local _, left, top, right, bottom = reaper.JS_Window_GetRect(arrange_hwnd)
    local track = nil--reaper.BR_GetMouseCursorContext_Track()
    if not track then
        local numTracks = reaper.CountTracks(0)
        
        -- Loop through all tracks
        for i = numTracks - 1, 0, -1 do
            track = reaper.GetTrack(0, i)
            local trackHeight = reaper.GetMediaTrackInfo_Value(track, "I_TCPH")
            local trackPosY = reaper.GetMediaTrackInfo_Value(track, "I_TCPY") 
            if isApple then 
                if (top - mousePosY) > trackPosY then
                    break;
                end
            else
                if mousePosY - top > trackPosY then
                    break;
                end
            end 
        end
    end
    if track then  
        local trackIndex = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") -1
        local trackPosY = reaper.GetMediaTrackInfo_Value(track, "I_TCPY")
        if isApple then 
            mouseRelativeToTrack = top - mousePosY - trackPosY
        else
            mouseRelativeToTrack = mousePosY - top - trackPosY
        end
        return trackIndex, mouseRelativeToTrack
        --return mouseRelativeValue
    end
end

local function orderValues(startTrackIndex, startMouseRelativeToTrack, startPosTimeline, endTrackIndex, endMouseRelativeToTrack, endPosTimeline)
    -- Define the selection area
    local minIndex, maxIndex = math.min(startTrackIndex, endTrackIndex), math.max(startTrackIndex, endTrackIndex)
    if minIndex ~= startTrackIndex or (minIndex == maxIndex and startMouseRelativeToTrack > endMouseRelativeToTrack) then 
        local tempRelative = startMouseRelativeToTrack
        startMouseRelativeToTrack = endMouseRelativeToTrack
        endMouseRelativeToTrack = tempRelative
    end
    local minPos, maxPos = math.min(startPosTimeline, endPosTimeline), math.max(startPosTimeline, endPosTimeline)
    
    return minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos
end



local function get_current_state()
    local state = {
        items = {},
        items_count = 0,
        automation_items = {},
        automation_items_count = 0,
        envelope_points = {},
        envelope_points_count = 0,
        selected_items = {},
        selected_automation_items = {},
        selected_envelope_points = {},
    }
    
    local first_envelope_lane_track_index = math.huge
    local first_envelope_lane_env_index = math.huge

    local item_count = reaper.CountMediaItems(0)
    for i = 0, item_count - 1 do 
        local item = reaper.GetMediaItem(0, i) 
        local selected = reaper.GetMediaItemInfo_Value(item, "B_UISEL") == 1
        if selected then
            local track = reaper.GetMediaItem_Track(item)
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local playrate = reaper.GetMediaItemInfo_Value(item, "D_PLAYRATE")
            table.insert(state.selected_items, {
                item = item,
                track = track,
                index = i,
                time = pos,
                length = len,
                playrate = playrate,
                selected = selected,
            })
        end
        state.items_count = state.items_count + 1
    end

    local track_count = reaper.CountTracks(0)
    for t = 0, track_count - 1 do
        local track = reaper.GetTrack(0, t)
        local env_count = reaper.CountTrackEnvelopes(track)
        for e = 0, env_count - 1 do
            local env = reaper.GetTrackEnvelope(track, e)
            local is_visible = reaper.GetEnvelopeInfo_Value(env, "I_TCPH") > 0 or reaper.GetEnvelopeInfo_Value(env, "I_TCPH_USED") > 0
            if is_visible then
                local ai_count = reaper.CountAutomationItems(env)
                for i = 0, ai_count - 1 do 
                    local selected = reaper.GetSetAutomationItemInfo(env, i, "D_UISEL", 0, false) == 1
                    if selected then
                        local pos = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
                        local len = reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false)
                        local playrate = reaper.GetSetAutomationItemInfo(env, i, "D_PLAYRATE", 0, false)
                        table.insert(state.selected_automation_items, {
                            env = env,
                            index = i,
                            track = track,
                            time = pos,
                            length = len,
                            playrate = playrate,
                            selected = selected
                        })
                        
                        if first_envelope_lane_track_index > t then 
                            first_envelope_lane_track_index = t 
                            if first_envelope_lane_env_index > e then 
                                first_envelope_lane_env_index = e
                                state.first_envelope_lane = env
                            end 
                        end
                    end
                    
                    state.automation_items_count = state.automation_items_count + 1
                    
                end

                local point_count = reaper.CountEnvelopePoints(env)
                for i = 0, point_count - 1 do
                    local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(env, i)
                    if selected then 
                        table.insert(state.selected_envelope_points , {
                            env = env,
                            index = i,
                            track = track,
                            time = time,
                            value = value,
                            shape = shape,
                            tension = tension,
                            selected = selected
                        })
                        if first_envelope_lane_track_index > t then 
                            first_envelope_lane_track_index = t 
                            if first_envelope_lane_env_index > e then 
                                first_envelope_lane_env_index = e
                                state.first_envelope_lane = env
                            end 
                        end
                    end 
                    state.envelope_points_count = state.envelope_points_count + 1 
                end
            end
        end 
    end

    return state
end

local function get_unique_key(entry, type)
    local track_str = tostring(entry.track or "")
    local env_str = tostring(entry.env or "")
    local index_str = tostring(entry.index or "")
    return type .. "::" .. track_str .. "::" .. env_str .. "::" .. index_str
end




local function selectMediaItems(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos)
    for i = 0, trackCount do
        local track = reaper.GetTrack(0, i)
        if track then
            local item_count = reaper.CountTrackMediaItems(track)
            for j = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(track, j) 
                local selected = reaper.GetMediaItemInfo_Value(item, "B_UISEL") == 1
                
                if i >= minIndex and i <= maxIndex then
                    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local endPos = pos + len
    
                    local yPosition = reaper.GetMediaItemInfo_Value(item, "I_LASTY")
                    local height = reaper.GetMediaItemInfo_Value(item, "I_LASTH")
                    local topY = yPosition
                    local bottomY = yPosition + height
    
                    local isInTimeRange = (pos >= minPos and pos <= maxPos) or (pos <= minPos and endPos >= minPos)
                    local isInTrackRange = (
                        (i > minIndex and i < maxIndex) or
                        (minIndex == maxIndex and bottomY >= startMouseRelativeToTrack and topY <= endMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == minIndex and bottomY >= startMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == maxIndex and topY <= endMouseRelativeToTrack)
                    )
                    
                    local itemIsInSelection = isInTimeRange and isInTrackRange
                    local selectItem = not super and true or not selected
                    if itemIsInSelection then 
                        reaper.SetMediaItemSelected(item, selectItem)
                    elseif not shift and selected then
                        reaper.SetMediaItemSelected(item, false) 
                    end
                else
                    if not shift and selected then
                        reaper.SetMediaItemSelected(item, false) 
                    end
                end
            end
        end
    end
end


local function selectEnvelopePoints(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos, automationItem)
    local ai = automationItem and automationItem or -1
    for i = 0, trackCount do
        local track = reaper.GetTrack(0, i)
        if track then
            local env_count = reaper.CountTrackEnvelopes(track)
            for e = 0, env_count - 1 do
                local envelope = reaper.GetTrackEnvelope(track, e)
                local isVisible = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED") > 0

                if isVisible and (not selectedEnvelope or selectedEnvelope ~= envelope) then
                    local point_count = reaper.CountEnvelopePointsEx(envelope, ai)
                    
                    if i >= minIndex and i <= maxIndex then
                        local envHeight = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED")
                        local envY = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPY") 
                        local _, name = reaper.GetEnvelopeName(envelope)
    
                        local br_env = reaper.BR_EnvAlloc(envelope, false)
                        local _, _, _, _, _, _, minValue, maxValue, _, _, faderScaling = reaper.BR_EnvGetProperties(br_env)
                        local range = maxValue - minValue 
                        
                        local scaling = reaper.GetEnvelopeScalingMode(envelope)
                        
                        
                        for p = 0, point_count - 1 do
                            --local _, time, value, shape, selected, bezier = reaper.BR_EnvGetPoint(br_env, p) 
                            
                            local retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx( envelope, ai, p ) 
                            local value = reaper.ScaleFromEnvelopeMode(scaling, value)
                            local relativeValue = value
                            
                            if scaling == 1 then
                                relativeValue = convertScaledFaderValueToVisuelValue(value, range)
                            end
                            if relativeValue > maxValue then relativeValue = maxValue end
                            if relativeValue < minValue then relativeValue = minValue end
                            
                            local normalized = (relativeValue - minValue) / range
                            local yInEnvelope = envHeight * (1 - normalized)
                            local yPosition = envY + yInEnvelope
    
                            local isInTimeRange = (time >= minPos and time <= maxPos)
                            local isInTrackRange = (
                                (i > minIndex and i < maxIndex) or
                                (minIndex == maxIndex and yPosition >= startMouseRelativeToTrack and yPosition <= endMouseRelativeToTrack) or
                                (minIndex ~= maxIndex and i == minIndex and yPosition >= startMouseRelativeToTrack) or
                                (minIndex ~= maxIndex and i == maxIndex and yPosition <= endMouseRelativeToTrack)
                            )
                            
                            local itemIsInSelection = isInTimeRange and isInTrackRange
        
                            if itemIsInSelection then 
                                local selectItem = not super and true or not selected
                                if selectItem then
                                
                                --reaper.ShowConsoleMsg(minValue .. " - " .. maxValue .. " - " .. value .. " - " .. relativeValue .. "\n")
                                
                                end
                                reaper.SetEnvelopePointEx(envelope, ai, p, nil, nil, nil, nil, selectItem, false)
                            elseif not shift and selected then 
                                reaper.SetEnvelopePointEx(envelope, ai, p, nil, nil, nil, nil, false, false) 
                            end
                        end 
                        
                        reaper.BR_EnvFree(br_env, true)
                        reaper.Envelope_SortPointsEx(envelope, ai)
                    else 
                        for p = 0, point_count - 1 do
                            reaper.SetEnvelopePointEx(envelope, ai, p, nil, nil, nil, nil, false, false)
                        end  
                        reaper.Envelope_SortPointsEx(envelope, ai)
                    end
                end
            end
        end
    end
end

local function selectEnvelopePointsBR(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos, selectedEnvelope)
    local _, _, top, _, _ = reaper.JS_Window_GetRect(arrange_hwnd)
    local isShiftPressed = reaper.JS_Mouse_GetState(ADD_TO_SELECTION_MOUSE_STATE_NUMBER) == ADD_TO_SELECTION_MOUSE_STATE_NUMBER

    for i = minIndex, maxIndex do
        local track = reaper.GetTrack(0, i)
        if track then
            local env_count = reaper.CountTrackEnvelopes(track)
            for e = 0, env_count - 1 do
                local envelope = reaper.GetTrackEnvelope(track, e)
                local isVisible = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED") > 0

                if isVisible and (not selectedEnvelope or selectedEnvelope ~= envelope) then
                    local envHeight = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED")
                    local envY = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPY")

                    local br_env = reaper.BR_EnvAlloc(envelope, false)
                    local _, _, _, _, _, _, minValue, maxValue, _, _, faderScaling = reaper.BR_EnvGetProperties(br_env)
                    local range = maxValue - minValue
                    local point_count = reaper.CountEnvelopePoints(envelope)

                    for p = 0, point_count - 1 do
                        local _, time, value, shape, selected, bezier = reaper.BR_EnvGetPoint(br_env, p)
                        local relativeValue = value

                        if faderScaling then
                            relativeValue = convertScaledFaderValueToVisuelValue(value, range)
                        end

                        local normalized = (relativeValue - minValue) / range
                        local yInEnvelope = envHeight * (1 - normalized)
                        local yPosition = envY + yInEnvelope

                        local isInTimeRange = (time >= minPos and time <= maxPos)
                        local isInTrackRange = (
                            (i > minIndex and i < maxIndex) or
                            (minIndex == maxIndex and yPosition >= startMouseRelativeToTrack and yPosition <= endMouseRelativeToTrack) or
                            (minIndex ~= maxIndex and i == minIndex and yPosition >= startMouseRelativeToTrack) or
                            (minIndex ~= maxIndex and i == maxIndex and yPosition <= endMouseRelativeToTrack)
                        )
                        
                        local itemIsInSelection = isInTimeRange and isInTrackRange
    
                        if itemIsInSelection then 
                            local selectItem = not super and true or not selected
                            reaper.BR_EnvSetPoint(br_env, p, time, value, shape, selectItem, bezier)
                        elseif not shift and selected then
                            reaper.BR_EnvSetPoint(br_env, p, time, value, shape, false, bezier)
                        end
                    end

                    reaper.BR_EnvSortPoints(br_env)
                    reaper.BR_EnvFree(br_env, true)
                end
            end
        end
    end
end


local function selectAutomationItems(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos)
    for i = 0, trackCount do
        local track = reaper.GetTrack(0, i)
        if track then
            local env_count = reaper.CountTrackEnvelopes(track) 
            for e = 0, env_count - 1 do
                local env = reaper.GetTrackEnvelope(track, e)

                -- Only consider visible envelopes
                local envVisible = reaper.GetEnvelopeInfo_Value(env, "I_TCPH_USED") > 0
                if envVisible then
                    local ai_count = reaper.CountAutomationItems(env)
                    if i >= minIndex and i <= maxIndex then
                        local envHeight = reaper.GetEnvelopeInfo_Value(env, "I_TCPH")
                        local envY = reaper.GetEnvelopeInfo_Value(env, "I_TCPY")
                        
                        if AUTOMATION_ITEMS_ONLY_REPRESENTED_BY_BOTTOM_STRIP then
                            local offset = reaper.GetEnvelopeInfo_Value(env, "I_TCPH_USED")
                            envHeight = envHeight - offset
                            envY = envY + offset
                        end
                        
                        
                        for ai = 0, ai_count - 1 do
                            local pos = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
                            local len = reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
                            local selected = reaper.GetSetAutomationItemInfo(env, ai, "D_UISEL", 0, false) == 1
                            local endPos = pos + len
    
                            local topY = envY
                            local bottomY = envY + envHeight
    
                            local isInTimeRange = (pos >= minPos and pos <= maxPos) or (pos <= minPos and endPos >= minPos) --or (pos <= maxPos and endPos <= maxPos)
                            local isInTrackRange = (
                                (i > minIndex and i < maxIndex) or
                                (minIndex == maxIndex and bottomY >= startMouseRelativeToTrack and topY <= endMouseRelativeToTrack) or
                                (minIndex ~= maxIndex and i == minIndex and bottomY >= startMouseRelativeToTrack) or
                                (minIndex ~= maxIndex and i == maxIndex and topY <= endMouseRelativeToTrack)
                            )
                            
                            local itemIsInSelection = isInTimeRange and isInTrackRange
                            local selectItem = not super and true or not selected
    
                            if itemIsInSelection then
                                if (not selected and selectItem) or (selected and not selectItem) then
                                    reaper.GetSetAutomationItemInfo(env, ai, "D_UISEL", selectItem and 1 or 0, true)
                                end
                                -- this selects envelope points inside the automation item 
                            elseif not shift and not super and selected then
                                reaper.GetSetAutomationItemInfo(env, ai, "D_UISEL", 0, true)
                            end
                            selectEnvelopePoints(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos, ai)
                        end
                    else 
                        for ai = 0, ai_count - 1 do 
                            local selected = reaper.GetSetAutomationItemInfo(env, ai, "D_UISEL", 0, false) == 1
                            if not shift and not super and selected then
                                reaper.GetSetAutomationItemInfo(env, ai, "D_UISEL", 0, true)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function automationItemUnderMouse(minIndex, startMouseRelativeToTrack, minPos, onlyBottom)
    local i = minIndex
    local maxIndex = minIndex
    local endMouseRelativeToTrack = startMouseRelativeToTrack
    local track = reaper.GetTrack(0, i)
    if track then
        local env_count = reaper.CountTrackEnvelopes(track)
        for e = 0, env_count - 1 do
            local env = reaper.GetTrackEnvelope(track, e)

            -- Only consider visible envelopes
            local envVisible = reaper.GetEnvelopeInfo_Value(env, "I_TCPH_USED") > 0
            if envVisible then
                local envHeight = reaper.GetEnvelopeInfo_Value(env, "I_TCPH")
                local envY = reaper.GetEnvelopeInfo_Value(env, "I_TCPY")
                
                local offset = reaper.GetEnvelopeInfo_Value(env, "I_TCPH_USED")
                local envHeightTop = offset
                local envHeightBottom = envHeight - offset
                local envYBottom = envY + offset
                
                --if AUTOMATION_ITEMS_ONLY_REPRESENTED_BY_BOTTOM_STRIP or onlyBottom then
                    
                --end

                local ai_count = reaper.CountAutomationItems(env)
                for ai = 0, ai_count - 1 do
                    local pos = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
                    local len = reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
                    local selected = reaper.GetSetAutomationItemInfo(env, ai, "D_UISEL", 0, false) == 1
                    local endPos = pos + len

                    local topY = envY
                    local bottomY = envY + envHeight
                    local bottomYTop = envY + envHeightTop
                    
                    local topYBottom = envYBottom
                    local bottomYBottom = topYBottom + envHeightBottom

                    local isInTimeRange = (pos <= minPos and endPos >= minPos) --or (pos <= maxPos and endPos <= maxPos)
                    local isInTrackRange = (
                        (i > minIndex and i < maxIndex) or
                        (minIndex == maxIndex and bottomY >= startMouseRelativeToTrack and topY <= endMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == minIndex and bottomY >= startMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == maxIndex and topY <= endMouseRelativeToTrack)
                    )
                    local isInAutomationTop = (
                        (i > minIndex and i < maxIndex) or
                        (minIndex == maxIndex and bottomYTop >= startMouseRelativeToTrack and topY <= endMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == minIndex and bottomYTop >= startMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == maxIndex and topY <= endMouseRelativeToTrack)
                    )
                    local isInAutomationBottom = (
                        (i > minIndex and i < maxIndex) or
                        (minIndex == maxIndex and bottomYBottom >= startMouseRelativeToTrack and topYBottom <= endMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == minIndex and bottomYBottom >= startMouseRelativeToTrack) or
                        (minIndex ~= maxIndex and i == maxIndex and topYBottom <= endMouseRelativeToTrack)
                    )
                    
                    local itemIsUnderMouse = isInTimeRange and isInTrackRange
                    if itemIsUnderMouse then
                        return itemIsUnderMouse, isInAutomationTop, isInAutomationBottom, ai
                    end
                end
            end
        end
    end
    return false
end


local function envelopePointUnderMouse(minIndex, startMouseRelativeToTrack, minPos, automationItem)
    local maxIndex = minIndex
    local endMouseRelativeToTrack = startMouseRelativeToTrack + relativeTrack
    local startMouseRelativeToTrack = startMouseRelativeToTrack - relativeTrack
    local maxPos = minPos + relativePos
    local minPos = minPos - relativePos
    local ai = automationItem and automationItem or -1
    local track = reaper.GetTrack(0, minIndex)
    if track then
        local env_count = reaper.CountTrackEnvelopes(track)
        for e = 0, env_count - 1 do
            local envelope = reaper.GetTrackEnvelope(track, e)
            local isVisible = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED") > 0

            if isVisible and (not selectedEnvelope or selectedEnvelope ~= envelope) then
                local point_count = reaper.CountEnvelopePointsEx(envelope, ai)
                
                local envHeight = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED")
                local envY = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPY") 
                local _, name = reaper.GetEnvelopeName(envelope)

                local br_env = reaper.BR_EnvAlloc(envelope, false)
                local _, _, _, _, _, _, minValue, maxValue, _, _, faderScaling = reaper.BR_EnvGetProperties(br_env)
                local range = maxValue - minValue  
                reaper.BR_EnvFree(br_env, true)
                
                local scaling = reaper.GetEnvelopeScalingMode(envelope)
                
                
                for p = 0, point_count - 1 do
                    --local _, time, value, shape, selected, bezier = reaper.BR_EnvGetPoint(br_env, p) 
                    
                    local retval, time, value, shape, tension, selected = reaper.GetEnvelopePointEx( envelope, ai, p ) 
                    local value = reaper.ScaleFromEnvelopeMode(scaling, value)
                    local relativeValue = value
                    
                    if scaling == 1 then
                        relativeValue = convertScaledFaderValueToVisuelValue(value, range)
                    end
                    if relativeValue > maxValue then relativeValue = maxValue end
                    if relativeValue < minValue then relativeValue = minValue end
                    
                    local normalized = (relativeValue - minValue) / range
                    local yInEnvelope = envHeight * (1 - normalized)
                    local yPosition = envY + yInEnvelope

                    local isInTimeRange = time >= minPos and time <= maxPos
                    local isInTrackRange = yPosition >= startMouseRelativeToTrack and yPosition <= endMouseRelativeToTrack
                    
                    local itemIsUnderMouse = isInTimeRange and isInTrackRange

                    if itemIsUnderMouse then 
                        return true
                    end
                end  
            end
        end
    end
    return false
end


local function automationUnderMouse(minIndex, startMouseRelativeToTrack, minPos)
end



-- Function to get the visibility and selection state of envelopes
local function deleteAllSelectedEvents(state)
    
    -- We ensure that it's only when a new undo state is created, eg pressing delete
    local undo_string = reaper.Undo_CanUndo2(0)
    if undo_string == "Delete items" or undo_string == "Delete automation items" or undo_string:match("Delete envelope points") ~= nil then 
        reaper.Undo_DoUndo2(0)
    end 
    
    reaper.Undo_BeginBlock()
    --[[
    local c = state.selected_items
    if #c > 0 then
        for i = #c, 1, -1 do 
            reaper.DeleteTrackMediaItem(c[i].track, c[i].item)
        end 
    end
    ]]
    reaper.Main_OnCommand(42086, 0) --Envelope: Delete automation items
    local c = state.selected_envelope_points
    for i = #c, 1, -1 do
        reaper.DeleteEnvelopePointEx(c[i].env, -1, c[i].index)
    end
    current_state = get_current_state() 
    
    --[[
    -- delete all selected envelopes
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1 then
            local envCount = reaper.CountTrackEnvelopes(track)
            for j = 0, envCount - 1 do
                local envelope = reaper.GetTrackEnvelope(track, j)
                local envVisible = reaper.GetEnvelopeInfo_Value(envelope, "I_TCPH_USED")
                if envVisible > 0 then
                    local numPoints = reaper.CountEnvelopePoints(envelope)
                    for k = numPoints - 1, 0, -1 do 
                        local _, _, _, _, _, selected = reaper.GetEnvelopePoint(envelope, k)
                        if selected then 
                            reaper.DeleteEnvelopePointEx(envelope,-1,k)
                        end
                    end 
                end
            end 
        end
    end
    -- delete all selected Automation Items
    reaper.Main_OnCommand(42086, 0) --Envelope: Delete automation items
    ]]
    
    -- delete all selected media items
    for i = reaper.CountSelectedMediaItems(0) - 1, 0, -1 do
        local selMediaItem = reaper.GetSelectedMediaItem(0, i)
        reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(selMediaItem),selMediaItem)
    end
    current_state = get_current_state() 
    
    
    reaper.Undo_EndBlock("Advanced selection script delete", -1)
end

local function selectAutomationItemUnderMouse(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
    local undo_string = reaper.Undo_CanUndo2(0)
    if undo_string:match("Select automation item") ~= nil then  
        -- we undo the marque select to have our function do all the selection and only having one undo point
        reaper.Undo_DoUndo2(0) 
    end 
    
    reaper.Undo_BeginBlock()
    local minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos = orderValues(startTrackIndex, startMouseRelativeToTrack, startPosTimeline, startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
    selectAutomationItems(minIndex, startMouseRelativeToTrack-relativeTrack, minPos - relativePos, maxIndex, endMouseRelativeToTrack + relativeTrack, maxPos + relativePos)
    
    reaper.Undo_EndBlock(undoName, 1)
end

local function selectEventsInArea(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
    local undo_string = reaper.Undo_CanUndo2(0)
    if undo_string == "Marquee item selection" or undo_string:match("Marquee envelope point selection") ~= nil then  
        -- we undo the marque select to have our function do all the selection and only having one undo point
        reaper.Undo_DoUndo2(0)
    
    end 
        
    reaper.Undo_BeginBlock()
    -- SELECTION
    local endTrackIndex, endMouseRelativeToTrack = getPositionOfTrackY()
    local endPosTimeline = getTimePositionOfCursor()
    local minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos = orderValues(startTrackIndex, startMouseRelativeToTrack, startPosTimeline, endTrackIndex, endMouseRelativeToTrack, endPosTimeline)
    
    if not shift then
        --reaper.SelectAllMediaItems(0, false)
        --reaper.Main_OnCommand(40289, 0) -- Unselect all items
    end
    
    selectEnvelopePoints(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos, nil)
    selectMediaItems(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos)
    selectAutomationItems(minIndex, startMouseRelativeToTrack, minPos, maxIndex, endMouseRelativeToTrack, maxPos) 
    reaper.UpdateArrange()
    --reaper.UpdateTimeline()
    reaper.Undo_EndBlock(undoName, 1)
    return true
    
    
end

local function was_selected_and_deleted(old, new) 
    if old.items_count > new.items_count or old.automation_items_count > new.automation_items_count or old.envelope_points_count > new.envelope_points_count then
        return true
    end
    return false
end

function roundValue(val)
    return math.floor(val * 1000000000) / 1000000000
end

local function somethingWasMoved(start, old, new, onlyCheckThis, usingKeyboard) 
    for t, val in pairs(old) do 
        if type(val) == "table" and t:match("selected_") ~= nil then
            local s = start[t]
            local n = new[t]
            local o = old[t]
            if #s == #n and #o == #n then
                for i = 1, #s do 
                    if not onlyCheckThis or (onlyCheckThis.env == s[i].env and onlyCheckThis.t == t) then 
                        if not usingKeyboard or (n[i].index == o[i].index) then
                            local roundedValueRelative = roundValue(n[i].time - o[i].time)
                            if math.abs(roundedValueRelative) > 0.0001 then
                                local roundedValue = roundValue(n[i].time - s[i].time)
                                return {move = roundedValue, relative = roundedValueRelative, env = n[i].env, t = t}
                            end
                        end
                    end
                end 
            end
        end
    end
    return onlyCheckThis
end


local function moveNonMoved(start, new, moveChange, lengthChange)
    local undo_string = false --reaper.Undo_CanRedo2(0)
    local lastEnv = nil
    local relativeMove = moveChange and moveChange.move or 0
    local relativeLength = lengthChange and lengthChange.move or 0
    local change = (moveChange and moveChange.relative ~= 0) or (lengthChange and lengthChange.relative ~= 0) 
    local accending = moveChange and moveChange.relative > 0
    
    if not undo_string then
        for t, val in pairs(start) do  
            if type(val) == "table" and t:match("selected_") ~= nil then
                local ignoreMove = moveChange and moveChange.t == t 
                local ignoreLength = lengthChange and lengthChange.t == t
                local s = start[t]
                local n = new[t] 
                if #s == #n then
                    for c = 1, #s do  
                        if change then
                            i = accending and (#s - (c-1)) or c
                            local newPos = s[i].time + relativeMove
                            if newPos < 0 and n[i].time > 0 then relativeLength = relativeLength + newPos; newPos = 0 end
                            local newLength = s[i].length and (s[i].length + relativeLength) or 0
                            if newLength < 0 then newLength = 0 end
                            
                            if newPos >= 0 and newLength >= 0 then
                                if t == "selected_items" then-- and o[i].item == n[i].item then -- just adding item for safety
                                    if relativeMove and not ignoreMove then reaper.SetMediaItemInfo_Value(n[i].item, "D_POSITION", newPos) end
                                    if relativeLength and not ignoreLength then reaper.SetMediaItemInfo_Value(n[i].item, "D_LENGTH", newLength) end
                                elseif t == "selected_automation_items" then 
                                    if relativeMove and not ignoreMove then reaper.GetSetAutomationItemInfo(n[i].env, n[i].index, "D_POSITION", newPos, true) end
                                    if relativeLength and not ignoreLength then reaper.GetSetAutomationItemInfo(n[i].env, n[i].index, "D_LENGTH", newLength, true) end 
                                elseif not lengthChange and t == "selected_envelope_points" and (not ignoreMove or (moveChange and moveChange.env ~= n[i].env)) then 
                                    reaper.SetEnvelopePoint(n[i].env, n[i].index, newPos, s[i].value, s[i].shape, s[i].tension, true, false)
                                    
                                    sortEnvelopes = true
                                    local env = n[i].env
                                    if lastEnv and lastEnv ~= env then
                                        reaper.Envelope_SortPoints(lastEnv)
                                    end
                                    lastEnv = env
                                    if i == 1 then 
                                        reaper.Envelope_SortPoints(lastEnv)
                                    end
                                    
                                end
                            end
                        end
                    end 
                end
            end
        end
    end
    return false
end

local function aLengthWasChanged(start, old, new, onlyCheckThis, usingKeyboard) 
    for t, val in pairs(old) do 
        if type(val) == "table" and (t == "selected_items" or t == "selected_automation_items") then
            local s = start[t]
            local n = new[t]
            local o = old[t]
            if #s == #n and #o == #n then
                for i = 1, #s do 
                    if not onlyCheckThis or (onlyCheckThis.env == s[i].env and onlyCheckThis.t == t) then 
                        if not usingKeyboard or (n[i].index == o[i].index) then
                            local roundedValueRelative = roundValue(n[i].length - o[i].length)
                            if math.abs(roundedValueRelative) > 0.0001 then 
                                local roundedValue = roundValue(n[i].length - s[i].length)
                                local posChange = s[i].time ~= n[i].time 
                                return {move = roundedValue, relative = roundedValueRelative, posChange = posChange, env = n[i].env, t = t}
                            end
                        end
                    end
                end 
            end
        end
    end
    return onlyCheckThis
end


local function changeLengthOnNonChanged(start, new, obj)
    local undo_string = false --reaper.Undo_CanRedo2(0)
    local lastEnv = nil
    local relative = obj.move
    local ignore = obj.t
    
    if not undo_string then
        for t, val in pairs(start) do  
            if type(val) == "table" and (t == "selected_items" or t == "selected_automation_items") then
                local s = start[t]
                local n = new[t] 
                if #s == #n then
                    for c = 1, #s do 
                        i = obj.relative > 0 and (#s - (c-1)) or c
                        if obj.relative ~= 0 then
                            if t == "selected_items" and obj.t ~= t then-- and o[i].item == n[i].item then -- just adding item for safety
                                reaper.SetMediaItemInfo_Value(n[i].item, "D_LENGTH", s[i].length + relative)
                            elseif t == "selected_automation_items" and obj.t ~= t then
                                reaper.GetSetAutomationItemInfo(n[i].env, n[i].index, "D_LENGTH", s[i].length + relative, true) 
                            end
                        end
                    end 
                end
            end
        end
    end
    return false
end


local function unselectionWasMade(start, new) 
    for t, val in pairs(start) do 
        if type(val) == "table" and t:match("selected_") ~= nil then
            local s = start[t]
            local n = new[t]
            if #s > #n or (t == "selected_automation_items" and #s >= #n) then
                return true
            end
        end
    end
    return false
end


-- Check if we click somewhere
function anyElementUnderMouse(itemUnderMouse, startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
    local clickElement = itemUnderMouse
    if not clickElement then
        clickElement = automationItemUnderMouse(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
    end
    if not clickElement then
        clickElement = envelopePointUnderMouse(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
    end
    return clickElement
end


local isWindows = reaper.GetOS():find("win")


local lastItems = {}
local lastAutoItems = {}
local lastPoints = {}

local last_state = nil
--local current_state

-- Function to check mouse state and select envelope points
local function checkMouse()
    trackCount = reaper.CountTracks(0) - 1
    current_state = get_current_state() 
    local redo_string = reaper.Undo_CanRedo2(0)
    local undo_string = reaper.Undo_CanUndo2(0)
    
    local mouseStates = reaper.JS_Mouse_GetState(-1)
    local mouseState = mouseStates & 1
    local isControlPressed = isWindows and mouseStates & 4 == 4 or mouseStates & 32 == 32 
    local isShiftPressed = mouseStates & 8 == 8
    local isAltPressed = mouseStates & 16 == 16
    local isSuperPressed = isWindows and mouseStates & 32 == 32 or mouseStates & 4 == 4 
    
    local mouseCursor = tostring(reaper.JS_Mouse_GetCursor()) 
    local mousePosX, mousePosY = reaper.GetMousePosition()
    local time = reaper.BR_PositionAtMouseCursor(true)
    --local trackCount = reaper.CountTracks(0)
    
    mouseState               = reaper.JS_Mouse_GetState(-1)
    shift                    = (mouseState & 0x08) ~= 0
    super                    = isWindows and (mouseState & 0x20) ~= 0 or (mouseState & 0x04) ~= 0
    alt                      = (mouseState & 0x10) ~= 0
    ctrl                     = isWindows and (mouseState & 0x04) ~= 0 or (mouseState & 0x20) ~= 0
    isMouseDown              = (mouseState & 0x01) ~= 0
    isMouseReleased          = (mouseState & 0x01) == 0
    isMouseRightDown         = (mouseState & 0x02) ~= 0 
    
    local cursorContext = reaper.GetCursorContext()
    
    
    
    cursorWindow, cursorSegment, cursorDetails = reaper.BR_GetMouseCursorContext()
    --local trackEnvelope, takeEnvelope = reaper.BR_GetMouseCursorContext_Envelope()
    local cursorInArrWindow = cursorWindow == "arrange" 
    local emptySpotOnTrack = cursorSegment == "track" and cursorDetails == "empty"
    local itemUnderMouse = cursorSegment == "track" and cursorDetails == "item"
    local emptyAreaInArrView = cursorSegment == "empty" and cursorDetails == ""
    local mouseOnEnvelopeLane = cursorSegment == "envelope"
    
    
    isMouseClick = isMouseDown and not isMouseDownStart
    if isMouseDown then isMouseDownStart = true end
    
    
    selectionChange = false
    if isMouseClick and cursorInArrWindow then
        start_x, start_y = mousePosX, mousePosY
        startTrackIndex, startMouseRelativeToTrack = getPositionOfTrackY()
        startPosTimeline = getTimePositionOfCursor()
        state_on_start = current_state
        
        clickElement = anyElementUnderMouse(itemUnderMouse, startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
      
         
         
        if undo_string == "Change media item selection" or 
            undo_string:match("Change envelope point selection") ~= nil or 
            undo_string:match("Select automation item") ~= nil 
            then  
            -- we undo the marque select to have our function do all the selection and only having one undo point
            --reaper.Undo_DoUndo2(0)
            --reaper.ShowConsoleMsg(undo_string.."\n")
            --selectionChange = true
            --current_state = get_current_state() 
        end 
    end
    
    
    
    
    
    if newSelectionMade then
        -- focus on envelope lane if no items is selected
        if cursorContext == 1 and #current_state.selected_items == 0 and current_state.first_envelope_lane and (#current_state.selected_automation_items > 0 or #current_state.selected_envelope_points > 0) then
            -- could consider make it depending on mouse release
            reaper.SetCursorContext(2, current_state.first_envelope_lane)
        end
        newSelectionMade = false
    end 
    
    
    
    
    
    if not selectionChange then
        
        -- LENGTH 
        if clickElement then
            changeLength = state_on_start and aLengthWasChanged(state_on_start, last_state, current_state, changeLength) or false
            if changeLength then
                if changeLength.relative ~= 0 then
                    --isDragging = false
                    --reaper.ShowConsoleMsg(changeLength.t .. " - " .. changeLength.relative .. " - " .. changeLength.move .. " length\n")
                end 
                --changeLengthOnNonChanged(state_on_start, current_state, changeLength) 
            end 
        else
            if ALLOW_CHANGING_LENGTH_WITH_KEY_COMMANDS then
                changeLengthWithKeyboard = last_state and aLengthWasChanged(last_state, last_state, current_state, nil, true) or false
                if changeLength then
                    if changeLength.relative ~= 0 then
                        --isDragging = false
                        --reaper.ShowConsoleMsg(changeLength.t .. " - " .. changeLength.relative .. " - " .. changeLength.move .. " length\n")
                    end 
                    --changeLengthOnNonChanged(last_state, current_state, changeLength)  
                    --current_state = get_current_state() 
                end 
            end
        end
        
        -- MOVE
        -- Aparently undos are not created when moving the items, so we do not need to do anything with that
        if clickElement then
            moveThings = (state_on_start and last_state) and somethingWasMoved(state_on_start, last_state, current_state, moveThings) or false
            if moveThings or changeLength then
                --if moveThings.relative ~= 0 then
                    --isDragging = false
                    --reaper.ShowConsoleMsg(moveThings.t .. " - " .. moveThings.relative .. " - " .. moveThings.move .. " move\n")
                --end
                --if changeLength then
                    --reaper.ShowConsoleMsg(changeLength.move .. "HEEE\n")
                --end
                moveNonMoved(state_on_start, current_state, moveThings, changeLength) 
            end 
        else
            if ALLOW_MOVING_WITH_KEY_COMMANDS then
                moveThingsWithKeyboard = last_state and somethingWasMoved(last_state, last_state, current_state, nil, true) or false
                if not state_on_start and (moveThingsNotWithMouse or changeLengthWithKeyboard) then
                    moveNonMoved(last_state, current_state, moveThingsWithKeyboard, changeLengthWithKeyboard) 
                    current_state = get_current_state() 
                    moveThingsWithKeyboard = false
                    changeLengthWithKeyboard = false
                end
            end
        end 
    end
    
    if isMouseDown then
        if cursorInArrWindow and not dragRegistered then
            if (start_x ~= mousePosX or start_y ~= mousePosY) then
                isDragging = true
                dragRegistered = true
            end
        end
    else 
        if isDragging then 
            doNotMakeNewSelection = (undo_string:match("Edit envelope") ~= nil or undo_string:match("Draw envelope") ~= nil or undo_string:match("Add points to envelope") ~= nil)
            if not clickElement and not doNotMakeNewSelection then
                newSelectionMade = selectEventsInArea(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
            end
        else 
            -- releasing a not drag mouse click
            if isMouseDownStart and not dragRegistered then
                if cursorInArrWindow then 
                    local itemIsUnderMouse, isInAutomationTop, isInAutomationBottom = (mouseOnEnvelopeLane and automationItemUnderMouse(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)) or false
                    if not shift and not super and (emptySpotOnTrack or emptyAreaInArrView or (mouseOnEnvelopeLane and not itemIsUnderMouse)) then
                        unselectAllAutomationItems(nil)
                    elseif mouseOnEnvelopeLane and itemIsUnderMouse then 
                        
                        --((not AUTOMATION_ITEMS_ONLY_REPRESENTED_BY_BOTTOM_STRIP and itemIsInSelection) or (AUTOMATION_ITEMS_ONLY_REPRESENTED_BY_BOTTOM_STRIP and isInAutomationBottom)) then
                        if not shift and not super then
                            --unselectAllAutomationItems(nil)
                        end
                        doNotMakeNewSelection = (undo_string:match("Delete envelope point") ~= nil or undo_string:match("Add points to envelope") ~= nil)
                        
                        --if isInAutomationTop and ctrl or cmd then
                            -- allows for drawing or inserting points. Needs setting for other users
                        --else
                        if not doNotMakeNewSelection then
                            selectAutomationItemUnderMouse(startTrackIndex, startMouseRelativeToTrack, startPosTimeline)
                        end
                        --end
                    end
                    
                end
            end
        end
        
        if not dragRegistered then
            -- DELETE
            if last_state and last_redo_string == redo_string then 
                if was_selected_and_deleted(last_state, current_state) then 
                    --reaper.ShowConsoleMsg("Delete\n")
                    deleteAllSelectedEvents(last_state)
                end
            end 
        end
        
        
        isDragging = false
        moveThings = false
        changeLength = false
        dragRegistered = false
        state_on_start = false 
        clickElement = false
    end  
    
    last_redo_string = redo_string
    last_state = current_state
    
    
    
    --local backspaceIsPressed = reaper.JS_VKeys_GetState(0):byte(8) == 1
    --local deleteIsPressed = reaper.JS_VKeys_GetState(0):byte(46) == 1
    
        
     
    ----------------------
    -- toolbar settings --
    ----------------------
    if not toolbarSet then 
        setToolbarState(true) 
        toolbarSet = true
    end
    reaper.atexit(exit)
    ---------------
    -- FINISHED ---
    ---------------
    
    
    if isMouseReleased then isMouseDownStart = false end
    
    reaper.defer(checkMouse)
end

-- Start checking the mouse state
checkMouse()

