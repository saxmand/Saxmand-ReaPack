-- @noindex

local export = {}

--------------------------------------------------------
------------------COLOURS-------------------------------
--------------------------------------------------------
local function getColorFromReaperTheme(tx, alpha)
    return reaper.ImGui_ColorConvertNative(reaper.GetThemeColor(tx) << 8) | (alpha and alpha or 0xFF)
end

local function getColorFromReaperTheme2(key, alpha)
    local col = reaper.GetThemeColor(key)
    if col < 0 then return 0,0,0,1 end

    local r = col & 0xFF
    local g = (col >> 8) & 0xFF
    local b = (col >> 16) & 0xFF

    return r/255, g/255, b/255, alpha or 1.0
end

function export.ApplyReaperThemeToImGui()

    -- Window / base
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), getColorFromReaperTheme("col_main_bg2"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), getColorFromReaperTheme("col_main_bg2"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), getColorFromReaperTheme("col_main_bg2"))
    
    -- Text
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), getColorFromReaperTheme("col_main_text2"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextDisabled(), getColorFromReaperTheme("col_main_textshadow"))
    
    -- Frames (inputs, sliders, checkboxes)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), getColorFromReaperTheme("col_main_editbk"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), getColorFromReaperTheme("col_seltrack2"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), getColorFromReaperTheme("col_seltrack"))
    
    -- Buttons
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), getColorFromReaperTheme("col_main_editbk"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), getColorFromReaperTheme("col_seltrack2"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), getColorFromReaperTheme("col_seltrack"))
    
    -- Headers (trees, selects, menus)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), getColorFromReaperTheme("genlist_selbg"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), getColorFromReaperTheme("genlist_hilite"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), getColorFromReaperTheme("genlist_selbg"))
    
    -- Tabs
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), getColorFromReaperTheme("docker_unselface"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), getColorFromReaperTheme("docker_selface"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), getColorFromReaperTheme("docker_selface"))
    
    -- Borders / separators
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), getColorFromReaperTheme("col_main_3dsh"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), getColorFromReaperTheme("col_main_3dhl"))
    
    -- Scrollbars
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), getColorFromReaperTheme("tcp_list_scrollbar"))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), getColorFromReaperTheme("tcp_list_scrollbar_mouseover"))
    
    -- Selection highlight
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(), getColorFromReaperTheme("col_tl_bgsel"))--, 0.35))
    --[[
    ]]
end

function export.ApplyReaperThemeToImGui_end()
    reaper.ImGui_PopStyleColor(ctx, 22) -- number you pushed
end


-- MODERN THEME PALETTE
theme2 = {
    --bg            = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.11, 1.00),  -- Very dark grey (VSCode-like)
    bg            = getColorFromReaperTheme("tcp_pinned_track_gap"),  -- Very dark grey (VSCode-like)
    panel_bg      = reaper.ImGui_ColorConvertDouble4ToU32(0.16, 0.16, 0.18, 1.00),
    accent        = reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.50, 0.95, 1.00),  -- Modern Blue
    accent_hover  = reaper.ImGui_ColorConvertDouble4ToU32(0.35, 0.60, 0.98, 1.00),
    accent_active = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.40, 0.85, 1.00),
    text          = getColorFromReaperTheme("col_stretchmarker_text"),--genlist_selfg--reaper.ImGui_ColorConvertDouble4ToU32(0.80, 0.80, 0.80, 1.00),
    text_dim      = getColorFromReaperTheme("col_toolbar_text"),
    button        = getColorFromReaperTheme("col_toolbar_frame"),-- reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    button_hover  = getColorFromReaperTheme("io_3dhl"),-- reaper.ImGui_ColorConvertDouble4ToU32(0.28, 0.28, 0.32, 1.00),
    button_active = getColorFromReaperTheme("col_toolbar_text"),-- reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.20, 1.00),
    tab_text      = getColorFromReaperTheme("col_main_text"),--reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    tab_text_active = getColorFromReaperTheme("col_toolbar_text_on"),--reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    tab           = getColorFromReaperTheme("col_toolbar_frame", 0x77),--reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    tab_hover     = getColorFromReaperTheme("col_toolbar_text_on", 0x77),--reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.32, 0.50, 1.00),
    tab_active    = getColorFromReaperTheme("toolbararmed_color", 0x77),--reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.40, 0.70, 1.00),
    border        = getColorFromReaperTheme("col_trans_fg"),--reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.28, 1.00),
    table_border_light        = getColorFromReaperTheme("col_trans_fg", 0x80),--reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.28, 1.00),
    success       = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.70, 0.40, 1.00),
    warning       = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.60, 0.10, 1.00),
    error         = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.20, 0.20, 1.00),
}
theme = {
    bg            = reaper.ImGui_ColorConvertDouble4ToU32(0.14, 0.14, 0.15, 1.00), 
    menu_bg       = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.23, 1.00), 
    panel_bg      = reaper.ImGui_ColorConvertDouble4ToU32(0.16, 0.16, 0.17, 1.00),
    panel_bg_active = reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.20, 1.00),
    accent        = reaper.ImGui_ColorConvertDouble4ToU32(0.40, 0.40, 0.44, 1.00), 
    accent_hover  = reaper.ImGui_ColorConvertDouble4ToU32(0.48, 0.48, 0.52, 1.00),
    accent_active = reaper.ImGui_ColorConvertDouble4ToU32(0.30, 0.30, 0.34, 1.00),
    text          = reaper.ImGui_ColorConvertDouble4ToU32(0.80, 0.80, 0.80, 1.00),
    text_dim      = reaper.ImGui_ColorConvertDouble4ToU32(0.60, 0.60, 0.60, 1.00),
    button        = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    button_hover  = reaper.ImGui_ColorConvertDouble4ToU32(0.28, 0.28, 0.32, 1.00),
    button_active = reaper.ImGui_ColorConvertDouble4ToU32(0.18, 0.18, 0.20, 1.00),
    tab_text      = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    tab_text_active = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 1.00),
    tab           = reaper.ImGui_ColorConvertDouble4ToU32(0.22, 0.22, 0.25, 0.60),
    tab_hover     = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.32, 0.50, 0.60),
    tab_active    = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.40, 0.70, 0.60),
    border        = reaper.ImGui_ColorConvertDouble4ToU32(0.40, 0.40, 0.43, 1.00),
    table_border_light = reaper.ImGui_ColorConvertDouble4ToU32(0.25, 0.25, 0.28, 1),
    success       = reaper.ImGui_ColorConvertDouble4ToU32(0.20, 0.70, 0.40, 1.00),
    warning       = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.60, 0.10, 1.00),
    error         = reaper.ImGui_ColorConvertDouble4ToU32(0.90, 0.20, 0.20, 1.00),
    overlay         = reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0.0, 0.0, 0.6),
    rounding         = 4,
}

function export.apply(ctx)
    -- APPLY MODERN THEME STYLES
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 6)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), 4)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowTitleAlign(), 0.5, 0.5)
    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 5) -- Comfy padding
    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 6)
    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    

    -- Theme Colors
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), theme.panel_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), theme.panel_bg_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), theme.panel_bg)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), theme.bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), theme.menu_bg)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), theme.bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), theme.border)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), theme.button)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), theme.button_hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), theme.button_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), theme.button)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), theme.button_hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), theme.button_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), theme.text)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), theme.accent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), theme.accent_hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), theme.accent_active)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderStrong(), theme.text_dim)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderLight(), theme.table_border_light)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), theme.panel_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), theme.button)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), theme.button_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), theme.button_hover)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), theme.tab)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), theme.tab_hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), theme.tab_active)


    
end

function export.ending(ctx)
    reaper.ImGui_PopStyleVar(ctx, 5)
    reaper.ImGui_PopStyleColor(ctx, 26)
end

function export.bypassed_begin(ctx)
    if fx_is_bypassed then 
        reaper.ImGui_BeginDisabled(ctx)  
    end
end

function export.bypassed_end(ctx)
    if fx_is_bypassed then 
        reaper.ImGui_EndDisabled(ctx) 
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ButtonTextAlign(), 0.5,0.5)
        reaper.ImGui_PushFont(ctx, font,  20)
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        local winX, winY = reaper.ImGui_GetWindowPos(ctx)
        local mouseHover = reaper.ImGui_IsWindowHovered(ctx)
        local text = "Articulation Script Bypassed"--mouseHover and "Enable FX" or "FX Bypassed"
        reaper.ImGui_DrawList_AddRectFilled(draw_list, winX, winY, winX + winW, winY+ winH, 0x00000077)
        local textW, textH = reaper.ImGui_CalcTextSize(ctx, text, 0, 0, true, winW)
        reaper.ImGui_DrawList_AddTextEx(draw_list, font, 20, winX + winW/2-textW/2, winY+ winH/2-textH/2, 0xFFFFFFFF, text, winW) 
        reaper.ImGui_PopFont(ctx)

        reaper.ImGui_PushFont(ctx, font,  14)
        text = "(click to enable)"
        local textW2, textH2 = reaper.ImGui_CalcTextSize(ctx, text, 0, 0, nil, winW)
        reaper.ImGui_DrawList_AddTextEx(draw_list, font, 14, winX + winW/2-textW2/2, winY+ winH/2 -textH2/2 + textH, 0x666666FF, text, winW) 
        if mouseHover and reaper.ImGui_IsMouseClicked(ctx, 0) and fxNumber then 
            reaper.TrackFX_SetEnabled(track, fxNumber, true)
        end
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_PopStyleVar(ctx)
    end
end

function export.getTrackColor(track)
    local color  = reaper.GetTrackColor(track) 
    --reaper.ShowConsoleMsg(tostring((reaper.ImGui_ColorConvertNative(color) << 8) | 0xFF) .. "\n")

     -- shift 0x00RRGGBB to 0xRRGGBB00 then add 0xFF for 100% opacity
    return color & 0x1000000 ~= 0 and (reaper.ImGui_ColorConvertNative(color) << 8) | 0xFF or colorTransparent 
end

return export