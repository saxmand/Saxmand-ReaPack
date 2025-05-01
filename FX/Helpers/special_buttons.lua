--@noindex

local buttons = {}
local colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
local colorGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 1)
local colorRedHidden = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 95 / 255, 88 / 255, 1)  -- 117 122 118
local colorGreen = reaper.ImGui_ColorConvertDouble4ToU32(39 / 255, 198 / 255, 65 / 255, 0.7)  -- 117 122 118
local colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
local colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)
local colorDarkDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.15, 0.15, 0.15, 1)
local colorBlack = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1)
local colorAlmostBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1)

function buttons.close(ctx, x, y, size, onlyXOnHover, id, textColor, textColorHover, backgroundColor,backgroundColorHover)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), size)
    if x and y then reaper.ImGui_SetCursorPos(ctx, x, y) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), backgroundColor and backgroundColor or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), backgroundColorHover and backgroundColorHover or colorRedHidden)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), backgroundColorHover and backgroundColorHover or colorRedHidden)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTransparent)
    reaper.ImGui_PushFont(ctx, closeTitle)

    local click = false
    if reaper.ImGui_Button(ctx, "##X" .. (id and id or ""), size + 1, size + 1) then
        click = true
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    --posX, posY = posX - 1, posY -1
    crop = size/4
    local isHovered = reaper.ImGui_IsItemHovered(ctx)
    if not onlyXOnHover or isHovered then 
        local crossColor = isHovered and (textColorHover and textColorHover or colorWhite) or (textColor and textColor or colorWhite)
        reaper.ImGui_DrawList_AddLine(draw_list, posX + crop, posY + crop, posX + size - crop, posY + size - crop, crossColor, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, posX + crop, posY + size - crop, posX + size - crop, posY + crop, crossColor, 2)
    end


    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx, 1)
    return click
end

function buttons.fullscreen(ctx, x, y, size)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), size)
    if x and y then reaper.ImGui_SetCursorPos(ctx, x, y) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorGreen)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorGreen)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTransparent)
    reaper.ImGui_PushFont(ctx, closeTitle)

    local click = false
    if reaper.ImGui_Button(ctx, "##fullscreen", size + 1, size + 1) then
        click = true
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    --posX, posY = posX - 1, posY -1
    crop = 3
    reaper.ImGui_DrawList_AddLine(draw_list, posX + crop, posY + size/2, posX + size - crop+1, posY + size/2, colorWhite, 2)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size/2, posY+ crop - 1, posX + size/2, posY - crop + size, colorWhite, 2)


    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx, 1)
    return click
end


function buttons.openClose(ctx, id, x, y, size, open)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), size)
    reaper.ImGui_SetCursorPos(ctx, x, y)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorGrey)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorGreen)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorGreen)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTransparent)
    reaper.ImGui_PushFont(ctx, closeTitle)

    local click = false
    if reaper.ImGui_Button(ctx, "##" .. id, size + 1, size + 1) then
        click = true
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    crop = 3
    reaper.ImGui_DrawList_AddLine(draw_list, posX + crop, posY + size/2, posX + size - crop+1, posY + size/2, colorWhite, 2)
    if not open then
        reaper.ImGui_DrawList_AddLine(draw_list, posX + size/2, posY+ crop - 1, posX + size/2, posY - crop + size, colorWhite, 2)
    end


    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx, 1)
    return click
end

function buttons.lock(ctx, id, size, lock, tooltipText, lockedColor, unlockedColor, background, hover, active, vertical, border)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),background)
    local clicked = false
    
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)

    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameBorderSize(),border and 1 or 0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),border and border or colorTransparent)
    
    if reaper.ImGui_Button(ctx,"##" .. id, size, size) then
        clicked = true
    end 

    reaper.ImGui_PopStyleVar(ctx)
    reaper.ImGui_PopStyleColor(ctx,1)


    if reaper.ImGui_IsItemHovered(ctx) and tooltipText then
        reaper.ImGui_SetTooltip(ctx,tooltipText)    
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    
    if vertical then
        reaper.ImGui_DrawList_AddRectFilled(draw_list, posX + size * 0.2, posY + size * 0.4, posX + size * 0.8, posY + size * 0.85, lock and lockedColor or unlockedColor, 2)
        reaper.ImGui_DrawList_PathArcTo(draw_list, posX + size * 0.5, posY + size * 0.35, size * 0.19, 3.141592 * 0.8, 3.141592 * (lock and 2.3 or 1.9))
        reaper.ImGui_DrawList_PathStroke(draw_list, lock and lockedColor or unlockedColor, reaper.ImGui_DragDropFlags_AcceptNoDrawDefaultRect(), 2)
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list, posX + size * 0.4, posY + size * 0.55, posX + size * 0.6, posY + size * 0.55, posX + size * 0.5, posY + size * 0.70, colorBlack)
    else
        reaper.ImGui_DrawList_AddRectFilled(draw_list, posX + size * 0.4, posY + size * 0.2, posX + size * 0.85, posY + size * 0.8, lock and lockedColor or unlockedColor, 2)
        reaper.ImGui_DrawList_PathArcTo(draw_list, posX + size * 0.35, posY + size * 0.5, size * 0.19, 3.141592 * 0.1, 3.141592 * (lock and 1.6 or 1.4))
        reaper.ImGui_DrawList_PathStroke(draw_list, lock and lockedColor or unlockedColor, reaper.ImGui_DragDropFlags_AcceptNoDrawDefaultRect(), 2)
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list, posX + size * 0.55, posY + size * 0.4, posX + size * 0.55, posY + size * 0.6, posX + size * 0.70, posY + size * 0.5, colorBlack)
    end
    
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx)
    
    return clicked 
end

function buttons.cogwheel(ctx, id, size, lock, tooltipText, lockedColor, unlockedColor, background, hover, active, vertical)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),background)
    local clicked = false
    
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    if reaper.ImGui_Button(ctx,"##" .. id, size, size) then
        clicked = true
    end 
    if reaper.ImGui_IsItemHovered(ctx) and tooltipText then
        reaper.ImGui_SetTooltip(ctx,tooltipText)    
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    
    local lineThickness = 2
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.5), posY + size * 0.15, posX + size * (0.5), posY + size * 0.85, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.15), posY + size * 0.5, posX + size * (0.85), posY + size * 0.5, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.25), posY + size * 0.25, posX + size * (0.75), posY + size * 0.75, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddLine(draw_list, posX + size * (0.25), posY + size * 0.75, posX + size * (0.75), posY + size * 0.25, lock and lockedColor or unlockedColor, lineThickness)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, posX + size * 0.52, posY + size * 0.5, size * 0.25, lock and lockedColor or unlockedColor)
    reaper.ImGui_DrawList_AddCircle(draw_list, posX + size * 0.52, posY + size * 0.5, size * 0.14, colorAlmostBlack,nil, 2)
    
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx)
    
    return clicked 
end


function buttons.knob(ctx, id, relativePosX, relativePosY, size, amount, textOnTop, outerCircleColor, thickness, centerOffset, staticColor, outerColor)
    winPosX, windPosY = reaper.ImGui_GetCursorScreenPos(ctx)
    x = winPosX + relativePosX
    y = windPosY + relativePosY

    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + size, y + size, colorDarkGrey, size, nil)
    

    local center_x = x + size / 2
    local center_y = y + size / 2
    local radius = size / 2 * (outerCircleColor and 1 or 0.8) -- Scale down a bit for aesthetic reasons

    -- Map 'amount' from [0, 1] to [-135, 135] degrees
    local startPosAngle = - 246
    local angle = (startPosAngle + amount * 310) * (math.pi / 180)
    local leftAngle = startPosAngle * (math.pi / 180)
    local centerAngle = (startPosAngle + (0.5) * 310) * (math.pi / 180)
    local rightAngle = (startPosAngle + (1) * 310) * (math.pi / 180)
    
    -- draw shade of non availble pos
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, size / 4, leftAngle + math.pi*2, rightAngle)
    reaper.ImGui_DrawList_PathStroke(draw_list, colorDarkDarkGrey, reaper.ImGui_DrawFlags_None(), size/2) 
    -- Calculate end point (p2_x, p2_y)
    local p2_x = center_x + math.cos(angle) * radius
    local p2_y = center_y + math.sin(angle) * radius

    if outerCircleColor then 
        if centerOffset then
            local amountLeft = 0.5 - amount/2 + centerOffset
            if amountLeft < 0 then amountLeft = 0 end
            local amountRight = amount/2 + 0.5 + centerOffset
            if amountRight > 1 then amountRight = 1 end
            
            local centerAngleLeft = (startPosAngle + amountLeft * 310) * (math.pi / 180)
            local centerAngleRight = (startPosAngle + amountRight * 310) * (math.pi / 180) 
            
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, size / 2 - thickness / 2, centerAngleLeft, centerAngleRight)
            reaper.ImGui_DrawList_PathStroke(draw_list, outerCircleColor, reaper.ImGui_DrawFlags_None(), thickness) 
            reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, center_x + math.cos(centerAngle) * radius, center_y + math.sin(centerAngle) * radius, colorBlack, 1)
        else 
            local amountRight = (startPosAngle + (staticColor and staticColor or amount) * 310) * (math.pi / 180)   
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, size / 2 - thickness / 2, centerAngle, amountRight)
            reaper.ImGui_DrawList_PathStroke(draw_list, outerCircleColor, reaper.ImGui_DrawFlags_None(), thickness) 
            reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, colorWhite, 1)
        end
    else
        reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, colorWhite, 1)
        reaper.ImGui_DrawList_AddRect(draw_list, x + 1, y + 1, x + size - 1, y + size - 1, outerColor and outerColor or colorGrey, size, nil, 1)
    end
    reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + size, y + size, colorBlack, size, nil, 1)


    if dragKnob and dragKnob == id and textOnTop then
        reaper.ImGui_DrawList_AddRectFilled(draw_list, x - 2, y - 2, x + size + 3, y + size + 3, colorAlmostBlack, 0, nil)
        --reaper.ImGui_SetCursorPos(ctx, curPosX + relativePosX, curPosY + relativePosY - 4)
        reaper.ImGui_PushFont(ctx, font10)            
        reaper.ImGui_DrawList_AddText(draw_list, x, y, colorWhite, textOnTop)
        --reaper.ImGui_Text(ctx, textOnTop)
        reaper.ImGui_PopFont(ctx)
    end

    local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
    reaper.ImGui_SetCursorPos(ctx, curPosX + relativePosX, curPosY + relativePosY)
    
    
    reaper.ImGui_InvisibleButton(ctx, id, size, size)
    if reaper.ImGui_IsItemHovered(ctx) then -- and isMouseClick then
        return true
    end
end

return buttons