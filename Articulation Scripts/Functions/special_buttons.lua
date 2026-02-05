local export = {}

function export.cogwheel(ctx, id, size, lock, tooltipText, lockedColor, unlockedColor, background, hover, active, centerColor)
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
    reaper.ImGui_DrawList_AddCircle(draw_list, posX + size * 0.52, posY + size * 0.5, size * 0.14, centerColor,nil, 2)
    
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx)
    
    return clicked 
end
return export