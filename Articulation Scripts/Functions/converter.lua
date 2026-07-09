-- @noindex

local export = {}

-- Module-level state: persists across frames via Lua's shared global namespace.
converterSelectedOriginal = converterSelectedOriginal or nil
converterOriginalNames    = converterOriginalNames    or {}  -- names NOT in current script
converterMatchingNames    = converterMatchingNames    or {}  -- names that ARE in current script (shown dimmed)
converterMappings         = converterMappings         or {}  -- {[origName] = convertedName}
converterLayerSelections  = converterLayerSelections  or {}  -- {[origName] = {[layerNum] = artIdx (1-based, non-live)}}
converterLastRefreshKey   = converterLastRefreshKey   or ""  -- track/take/focus change detection

local EXTSTATE_NS  = "articulationMap_converter"
local EXTSTATE_KEY = "mappings"

-- ──────────────────────────────────────────────────────────────────────────────
-- Persistence
-- ──────────────────────────────────────────────────────────────────────────────

local function loadStoredMappings()
    local str = reaper.GetExtState(EXTSTATE_NS, EXTSTATE_KEY)
    if str and str ~= "" then return json.decodeFromJson(str) or {} end
    return {}
end

local function saveStoredMappings(data)
    reaper.SetExtState(EXTSTATE_NS, EXTSTATE_KEY, json.encodeToJson(data), true)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Name-building (depends on global triggerTableLayers)
-- ──────────────────────────────────────────────────────────────────────────────

local function buildValidSet()
    if not triggerTableLayers or #triggerTableLayers == 0 then return {} end
    local validSet = {}
    local function recurse(li, parts)
        if li > #triggerTableLayers then 
            validSet[table.concat(parts, " / ")] = true;             
            return             
        end
        for _, art in ipairs(triggerTableLayers[li]) do
            if not art.live then 
                parts[li] = art.articulation; 
            end
            recurse(li + 1, parts) 
        end
    end
    recurse(1, {})
    return validSet
end

local function buildDefaultConvertedName()
    if not triggerTableLayers or #triggerTableLayers == 0 then return "" end
    local parts = {}
    for _, layer in ipairs(triggerTableLayers) do
        for _, art in ipairs(layer) do
            if not art.live then table.insert(parts, art.articulation); break end
        end
    end
    return table.concat(parts, " / ")
end

local function buildConvertedNameFromSelections(origName)
    if not triggerTableLayers or #triggerTableLayers == 0 then return "" end
    local sels, parts = converterLayerSelections[origName] or {}, {}
    for layerNum, layer in ipairs(triggerTableLayers) do
        local target = sels[layerNum] or 1
        local count, chosen = 0, nil
        for _, art in ipairs(layer) do
            if not art.live then
                count = count + 1
                if count == target then chosen = art; break end
            end
        end
        if not chosen then for _, art in ipairs(layer) do if not art.live then chosen = art; break end end end
        if chosen then table.insert(parts, chosen.articulation) end
    end
    return table.concat(parts, " / ")
end

-- split_exact is a global from change_articulation.lua
local function initSelectionsFromName(origName, convertedName)
    if not convertedName or not triggerTableLayers then return end
    local parts = split_exact(convertedName)
    converterLayerSelections[origName] = {}
    for layerNum, layer in ipairs(triggerTableLayers) do
        local targetName = parts[layerNum]
        local count, found = 0, false
        for _, art in ipairs(layer) do
            if not art.live then
                count = count + 1
                if art.articulation == targetName then
                    converterLayerSelections[origName][layerNum] = count
                    found = true
                    break
                end
            end
        end
        if not found then converterLayerSelections[origName][layerNum] = 1 end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- MIDI scan (focus-aware)
-- ──────────────────────────────────────────────────────────────────────────────

local function getSysexValues(msg)
    return msg:match('^NOTE (%d+) (%d+) text%s+"?([^"]*)"?$')
end

-- Collects unique type-15 articulation names from a single take.
-- selectedOnly=true → restrict to selected notes; falls back to all if nothing selected.
local function collectTextsFromTake(t, selectedOnly)
    if not t or not reaper.TakeIsMIDI(t) then return {} end

    local selectedPositions = nil
    if selectedOnly then
        local hasSelection = reaper.MIDI_EnumSelNotes(t, 0) ~= -1
        if hasSelection then
            selectedPositions = {}
            local _, noteCount = reaper.MIDI_CountEvts(t)
            for i = 0, noteCount - 1 do
                local ok, sel, _, ppq, _, ch, pitch = reaper.MIDI_GetNote(t, i)
                if ok and sel then
                    selectedPositions[ch .. "_" .. pitch .. "_" .. math.floor(ppq)] = true
                end
            end
        end
    end

    local seen, names = {}, {}
    local _, _, _, textCount = reaper.MIDI_CountEvts(t)
    for k = 0, textCount - 1 do
        local ok, _, _, ppq, _type, msg = reaper.MIDI_GetTextSysexEvt(t, k)
        if ok and _type == 15 then
            local ch, pitch, name = getSysexValues(msg)-- ('^NOTE (%d+) (%d+) text "(.+)"$')
            if name then
                local passFilter = (not selectedPositions)
                    or selectedPositions[ch .. "_" .. pitch .. "_" .. math.floor(ppq)]
                if passFilter and not seen[name] then
                    seen[name] = true
                    table.insert(names, name)
                end
            end
        end
    end
    return names
end

-- Returns unique articulation names per the current focus mode.
local function collectTextsForCurrentFocus()
    if focusIsOn == "track" then
        if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return {} end
        local seen, names = {}, {}
        for i = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            for j = 0, reaper.CountTakes(item) - 1 do
                local t = reaper.GetTake(item, j)
                if t and reaper.TakeIsMIDI(t) then
                    for _, name in ipairs(collectTextsFromTake(t, false)) do
                        if not seen[name] then seen[name] = true; table.insert(names, name) end
                    end
                end
            end
        end
        return names
    elseif focusIsOn == "editor" then
        return collectTextsFromTake(take, true)  -- selected, or all if nothing selected
    else  -- "take" or nil
        return collectTextsFromTake(take, false)
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Public: refresh original/matching name lists
-- ──────────────────────────────────────────────────────────────────────────────

function export.refreshOriginals()
    converterOriginalNames = {}
    converterMatchingNames = {}
    local validSet     = buildValidSet()
    local stored       = loadStoredMappings()
    local scriptStored = (fxName and stored[fxName]) or {}
    local defaultName  = buildDefaultConvertedName()

    for _, name in ipairs(collectTextsForCurrentFocus()) do
        if validSet[name] then
            -- Name already exists in script → show dimmed at bottom, identity default
            table.insert(converterMatchingNames, name)
            if not converterMappings[name] then
                converterMappings[name] = name
                initSelectionsFromName(name, name)
            end
        else
            -- Name not in script → needs conversion
            table.insert(converterOriginalNames, name)
            if scriptStored[name] then
                converterMappings[name] = scriptStored[name]
                initSelectionsFromName(name, scriptStored[name])
            elseif not converterMappings[name] then
                converterMappings[name] = defaultName
                initSelectionsFromName(name, defaultName)
            end
        end
    end

    if converterSelectedOriginal then
        local stillPresent = false
        for _, n in ipairs(converterOriginalNames) do
            if n == converterSelectedOriginal then stillPresent = true; break end
        end
        if not stillPresent then
            for _, n in ipairs(converterMatchingNames) do
                if n == converterSelectedOriginal then stillPresent = true; break end
            end
        end
        if not stillPresent then converterSelectedOriginal = nil end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Public: apply conversions
-- ──────────────────────────────────────────────────────────────────────────────

function export.applyConversionToTake(t, conversions, selectedOnly)
    if not t or not reaper.TakeIsMIDI(t) then return false end

    local noteFilter = nil
    if selectedOnly then
        local hasSelection = reaper.MIDI_EnumSelNotes(t, 0) ~= -1
        if hasSelection then
            noteFilter = {}
            local _, noteCount = reaper.MIDI_CountEvts(t)
            for i = 0, noteCount - 1 do
                local ok, sel, _, ppq, _, ch, pitch = reaper.MIDI_GetNote(t, i)
                if ok and sel then
                    noteFilter[ch .. "_" .. pitch .. "_" .. math.floor(ppq)] = true
                end
            end
        end
    end

    local _, _, _, textCount = reaper.MIDI_CountEvts(t)
    local modified = false
    for k = textCount - 1, 0, -1 do
        local ok, selected, muted, ppqpos, _type, msg = reaper.MIDI_GetTextSysexEvt(t, k)
        if ok and _type == 15 then
            local ch, pitch, name = getSysexValues(msg)
            -- Skip identity mappings (name already equals the target)
            if name and conversions[name] and conversions[name] ~= name then
                local passFilter = (not noteFilter)
                    or noteFilter[ch .. "_" .. pitch .. "_" .. math.floor(ppqpos)] == true
                if passFilter then
                    local newMsg = string.format('NOTE %s %s text "%s"', ch, pitch, conversions[name])
                    reaper.MIDI_DeleteTextSysexEvt(t, k)
                    reaper.MIDI_InsertTextSysexEvt(t, selected, muted, ppqpos, _type, newMsg, true)
                    modified = true
                end
            end
        end
    end
    if modified then
        reaper.MIDI_Sort(t)
        mirror_notation_to_unique_text_events(t)
    end
    return modified
end

-- Focus-aware apply used by the window buttons.
local function applyConversionsForCurrentFocus(conversions)
    if not conversions then return end
    reaper.Undo_BeginBlock()
    if focusIsOn == "track" then
        if track then
            for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                for j = 0, reaper.CountTakes(item) - 1 do
                    export.applyConversionToTake(reaper.GetTake(item, j), conversions, false)
                end
            end
        end
    elseif focusIsOn == "editor" then
        export.applyConversionToTake(take, conversions, true)
    else
        export.applyConversionToTake(take, conversions, false)
    end
    reaper.Undo_EndBlock("Convert articulation names", -1)
    export.refreshOriginals()
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Store helper (shared between both store buttons)
-- ──────────────────────────────────────────────────────────────────────────────

local function storeCurrentMappings()
    if not fxName then return end
    local stored   = loadStoredMappings()
    local validSet = buildValidSet()
    stored[fxName] = stored[fxName] or {}
    for origName, convertedName in pairs(converterMappings) do
        -- Only store mappings for names that are NOT already in the script
        if not validSet[origName] then
            stored[fxName][origName] = convertedName
        end
    end
    saveStoredMappings(stored)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Shared rendering helpers
-- ──────────────────────────────────────────────────────────────────────────────

-- Renders the Original+Converted 2-column table inside an already-begun child.
local function renderPairTable(ctx)
    local tblFlags = reaper.ImGui_TableFlags_BordersInnerV()
                   | reaper.ImGui_TableFlags_SizingStretchSame()
    if not reaper.ImGui_BeginTable(ctx, "##convTbl", 2, tblFlags) then return end

    reaper.ImGui_TableSetupColumn(ctx, "Original:")
    reaper.ImGui_TableSetupColumn(ctx, "New:")
    reaper.ImGui_TableHeadersRow(ctx)

    -- Non-matching names (normal color)
    for idx, origName in ipairs(converterOriginalNames) do
        local isSelected    = converterSelectedOriginal == origName
        local convertedName = converterMappings[origName] or buildDefaultConvertedName()
        reaper.ImGui_TableNextRow(ctx)

        reaper.ImGui_TableSetColumnIndex(ctx, 0)
        if reaper.ImGui_Selectable(ctx, origName .. "##orig" .. idx, isSelected, 0) then
            converterSelectedOriginal = origName
        end

        reaper.ImGui_TableSetColumnIndex(ctx, 1)
        if reaper.ImGui_Selectable(ctx, convertedName .. "##conv" .. idx, nil, 0) then
            if converterSelectedOriginal and converterSelectedOriginal ~= origName then
                converterMappings[converterSelectedOriginal] = convertedName
                initSelectionsFromName(converterSelectedOriginal, convertedName)
            else
                converterSelectedOriginal = origName
            end
        end
    end


    -- Matching names (dimmed, identity defaults)
    if #converterMatchingNames > 0 then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
        local offset = #converterOriginalNames
        for idx, origName in ipairs(converterMatchingNames) do
            local i = offset + idx
            local isSelected    = converterSelectedOriginal == origName
            local convertedName = converterMappings[origName] or origName
            reaper.ImGui_TableNextRow(ctx)

            reaper.ImGui_TableSetColumnIndex(ctx, 0)
            if reaper.ImGui_Selectable(ctx, origName .. "##orig" .. i, isSelected, 0) then
                converterSelectedOriginal = origName
            end

            reaper.ImGui_TableSetColumnIndex(ctx, 1)
            if reaper.ImGui_Selectable(ctx, convertedName .. "##conv" .. i, isSelected, 0) then
                if converterSelectedOriginal and converterSelectedOriginal ~= origName then
                    converterMappings[converterSelectedOriginal] = convertedName
                    initSelectionsFromName(converterSelectedOriginal, convertedName)
                else
                    converterSelectedOriginal = origName
                end
            end
        end
        reaper.ImGui_PopStyleColor(ctx)
    end

    reaper.ImGui_EndTable(ctx)
end

-- Renders the Available list inside an already-begun child.
local function renderAvailableList(ctx)
    local layers = triggerTableLayers or {}
    for layerNumber, layer in ipairs(layers) do
        if #layers > 1 and not layer[1].live then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
            reaper.ImGui_SeparatorText(ctx, "Layer " .. layerNumber)
            reaper.ImGui_PopStyleColor(ctx)
        end
        local nonLiveIdx = 0
        for _, art in ipairs(layer) do
            if not art.live then
                nonLiveIdx = nonLiveIdx + 1
                local artIdx  = nonLiveIdx
                local curSels = converterSelectedOriginal
                    and converterLayerSelections[converterSelectedOriginal]
                local isSel   = curSels and curSels[layerNumber] == artIdx
                if reaper.ImGui_Selectable(ctx,
                        art.articulation .. "##avail" .. layerNumber .. "_" .. artIdx,
                        isSel and true or false) then
                    if converterSelectedOriginal then
                        converterLayerSelections[converterSelectedOriginal] =
                            converterLayerSelections[converterSelectedOriginal] or {}
                        converterLayerSelections[converterSelectedOriginal][layerNumber] = artIdx
                        converterMappings[converterSelectedOriginal] =
                            buildConvertedNameFromSelections(converterSelectedOriginal)
                    end
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Public: ImGui window
-- ──────────────────────────────────────────────────────────────────────────────

function export.converterSurface(_)
    local close = false
    EnsureValidContext(ctx)

    -- Only refresh when track, take, or focus mode changes (saves scanning resources)
    local refreshKey = tostring(track) .. "_" .. tostring(take) .. "_" .. tostring(focusIsOn)
    if refreshKey ~= converterLastRefreshKey then
        converterLastRefreshKey = refreshKey
        export.refreshOriginals()
    end

    modern_ui.apply(ctx)

    reaper.ImGui_PushFont(ctx, fontFat, 13)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    reaper.ImGui_SetNextWindowSize(ctx, 480, 540, reaper.ImGui_Cond_FirstUseEver())
    docking.update(ctx)

    local visible, open = reaper.ImGui_Begin(ctx, "Articulation Converter", true,
        reaper.ImGui_WindowFlags_TopMost()
        | reaper.ImGui_WindowFlags_NoFocusOnAppearing()
        | reaper.ImGui_WindowFlags_MenuBar()
    )
    reaper.ImGui_PopFont(ctx)

    if visible then
        -- ── Menu bar ──
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 1)
        reaper.ImGui_PushFont(ctx, font, 13)
        if reaper.ImGui_BeginMenuBar(ctx) then
            if reaper.ImGui_BeginMenu(ctx, "File") then
                -- Horizontal layout toggle
                local horizChanged
                horizChanged, settings.converter_horizontal_layout =
                    reaper.ImGui_MenuItem(ctx, "Horizontal layout",
                        nil, settings.converter_horizontal_layout)
                if horizChanged then saveSettings() end

                reaper.ImGui_Separator(ctx)

                if reaper.ImGui_MenuItem(ctx, "Export all stored settings...") then
                    local defaultPath = reaper.GetResourcePath() .. "/Scripts/"
                    local filepath = reaper.JS_Dialog_BrowseForSaveFile(
                        "Export Converter Settings", defaultPath,
                        "converter_settings", "JSON\0*.json\0All files\0*.*\0")
                    if filepath and filepath ~= "" then
                        if not filepath:match("%.json$") then filepath = filepath .. ".json" end
                        local f = io.open(filepath, "w")
                        if f then f:write(json.encodeToJson(loadStoredMappings())); f:close() end
                    end
                end
                if reaper.ImGui_MenuItem(ctx, "Import stored settings...") then
                    local defaultPath = reaper.GetResourcePath() .. "/Scripts/"
                    local filepath = reaper.JS_Dialog_BrowseForOpenFiles(
                        "Import Converter Settings", defaultPath, "",
                        "JSON\0*.json\0All files\0*.*\0", false)
                    if filepath and filepath ~= "" then
                        local f = io.open(filepath, "r")
                        if f then
                            local content = f:read("*a"); f:close()
                            local imported = json.decodeFromJson(content)
                            if imported and type(imported) == "table" then
                                local existing = loadStoredMappings()
                                for scriptName, mappings in pairs(imported) do
                                    existing[scriptName] = existing[scriptName] or {}
                                    for orig, conv in pairs(mappings) do
                                        existing[scriptName][orig] = conv
                                    end
                                end
                                saveStoredMappings(existing)
                                export.refreshOriginals()
                            end
                        end
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end
            reaper.ImGui_EndMenuBar(ctx)
        end
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_PopStyleVar(ctx)

        modern_ui.bypassed_begin(ctx)
        reaper.ImGui_PushFont(ctx, font, 13)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), 1)

        -- Script name header
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
        reaper.ImGui_Text(ctx, fxName or "[No articulation script]")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Separator(ctx)

        -- Import-from-previous dropdown
        local storedAll     = loadStoredMappings()
        local storedScripts = {}
        for scriptName in pairs(storedAll) do
            if scriptName ~= fxName then table.insert(storedScripts, scriptName) end
        end
        table.sort(storedScripts)

        if #storedScripts > 0 then
            local validSet = buildValidSet()
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            if reaper.ImGui_BeginCombo(ctx, "##importFrom", "Import from previous stored settings...") then
                for _, scriptName in ipairs(storedScripts) do
                    if reaper.ImGui_Selectable(ctx, scriptName, false) then
                        local sourceMap = storedAll[scriptName] or {}
                        for origName, convertedName in pairs(sourceMap) do
                            if validSet[convertedName] then
                                for _, n in ipairs(converterOriginalNames) do
                                    if n == origName then
                                        converterMappings[origName] = convertedName
                                        initSelectionsFromName(origName, convertedName)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
            reaper.ImGui_Separator(ctx)
        end

        local hasOriginals = #converterOriginalNames > 0

        -- ── Height calculations ──
        local _, totalH  = reaper.ImGui_GetContentRegionAvail(ctx)
        local frameH     = reaper.ImGui_GetFrameHeight(ctx)
        local lineH      = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
        local childBorder = reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders() or 1
        local horizLayout = settings.converter_horizontal_layout

        local footerH, bodyH, pairH, availH, availLabelH
        availLabelH = lineH + 4
        if horizLayout then
            -- Footer is one line: checkboxes + buttons side by side
            footerH = frameH + 20
            bodyH   = math.max(60, totalH - footerH - 8)
            pairH   = bodyH
            availH  = math.max(40, bodyH - availLabelH - 4)
        else
            -- Footer is two lines: checkbox row + button row
            footerH = frameH * 2 + 24
            local body2H = math.max(60, totalH - footerH - availLabelH - 10)
            pairH   = math.floor(body2H * 0.5)
            availH  = body2H - pairH
        end

        -- ── Main content area ──
        if horizLayout then
            -- Side-by-side: pair left, available right
            local layoutFlags = reaper.ImGui_TableFlags_SizingStretchSame()
            if reaper.ImGui_BeginTable(ctx, "##hlayout", 2, layoutFlags) then
                reaper.ImGui_TableNextRow(ctx)

                -- Left column: Original + Converted
                reaper.ImGui_TableSetColumnIndex(ctx, 0)
                if reaper.ImGui_BeginChild(ctx, "##origConv", 0, pairH, childBorder) then
                    renderPairTable(ctx)
                    reaper.ImGui_EndChild(ctx)
                end

                -- Right column: Available
                reaper.ImGui_TableSetColumnIndex(ctx, 1)
                reaper.ImGui_Text(ctx, "Articulations")
                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_BeginChild(ctx, "##avail", 0, availH, childBorder) then
                    renderAvailableList(ctx)
                    reaper.ImGui_EndChild(ctx)
                end

                reaper.ImGui_EndTable(ctx)
            end
        else
            -- Stacked: pair on top, available below
            if reaper.ImGui_BeginChild(ctx, "##origConv", 0, pairH, childBorder) then
                renderPairTable(ctx)
                reaper.ImGui_EndChild(ctx)
            end
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, "Articulations")
            --reaper.ImGui_Separator(ctx)
            if reaper.ImGui_BeginChild(ctx, "##avail", 0, availH, childBorder) then
                renderAvailableList(ctx)
                reaper.ImGui_EndChild(ctx)
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ── Footer: checkboxes + buttons (same line in horizontal mode) ──
        if reaper.ImGui_Checkbox(ctx, "Auto convert", settings.converter_auto_convert) then
            settings.converter_auto_convert = not settings.converter_auto_convert
            saveSettings()
        end
        setToolTipFunc("Auto convert articulations when possible.")
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Checkbox(ctx, "Auto open", settings.converter_auto_open) then
            settings.converter_auto_open = not settings.converter_auto_open
            saveSettings()
        end
        setToolTipFunc("Auto open the converter window when a MIDI file has articulations not matching the articulation script.")
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Checkbox(ctx, "Close when applying", settings.converter_close_when_applying) then
            settings.converter_close_when_applying = not settings.converter_close_when_applying
            saveSettings()
        end

        -- In vertical mode, buttons go on a new line; in horizontal mode, continue on same line
        if not horizLayout then reaper.ImGui_Spacing(ctx) end
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, "Apply") then
            applyConversionsForCurrentFocus(converterMappings)
            if settings.converter_close_when_applying then close = true end
        end
        setToolTipFunc("Apply conversion to articulations, without storing them.")
        reaper.ImGui_SameLine(ctx)

        if not hasOriginals then reaper.ImGui_BeginDisabled(ctx) end

        if reaper.ImGui_Button(ctx, "Store settings") then
            storeCurrentMappings()
        end
        setToolTipFunc("Store conversion settings for this articulation script.")
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, "Store settings and apply") then
            storeCurrentMappings()
            applyConversionsForCurrentFocus(converterMappings)
            if settings.converter_close_when_applying then close = true end
        end
        setToolTipFunc("Store conversion settings for this articulation script and apply.")

        if not hasOriginals then reaper.ImGui_EndDisabled(ctx) end

        if not open or (reaper.ImGui_IsWindowFocused(ctx) and escape) then
            close = true
        end

        reaper.ImGui_PopStyleVar(ctx)
        modern_ui.bypassed_end(ctx)
        reaper.ImGui_PopFont(ctx)
        docking.setCurrent(ctx)
        reaper.ImGui_End(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx)
    modern_ui.ending(ctx)
    return close
end

return export
