local buttons = {}
local colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
local colorGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.4, 0.4, 0.4, 1)
local colorRedHidden = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 95 / 255, 88 / 255, 1)  -- 117 122 118
local colorGreen = reaper.ImGui_ColorConvertDouble4ToU32(39 / 255, 198 / 255, 65 / 255, 0.7)  -- 117 122 118
local colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
local colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)
local colorBlack = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1)

function buttons.close(ctx, x, y, size, onlyXOnHover, id)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), size)
    if x and y then reaper.ImGui_SetCursorPos(ctx, x, y) end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorRedHidden)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorRedHidden)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTransparent)
    reaper.ImGui_PushFont(ctx, closeTitle)

    local click = false
    if reaper.ImGui_Button(ctx, "##X" .. (id and id or ""), size + 1, size + 1) then
        click = true
    end
    local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
    --posX, posY = posX - 1, posY -1
    crop = size/4
    
    if not onlyXOnHover or reaper.ImGui_IsItemHovered(ctx) then 
        reaper.ImGui_DrawList_AddLine(draw_list, posX + crop, posY + crop, posX + size - crop, posY + size - crop, colorWhite,
            2)
        reaper.ImGui_DrawList_AddLine(draw_list, posX + crop, posY + size - crop, posX + size - crop, posY + crop, colorWhite,
            2)
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

function buttons.lock(ctx, id, size, lock, tooltipText, lockedColor, unlockedColor, background, hover, active, vertical)
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

return buttons