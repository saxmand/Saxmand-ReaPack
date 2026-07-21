-- @noindex

local export = {}

-- Module-level state: persists across frames via Lua's shared global namespace.
converterSelectedOriginal = converterSelectedOriginal or nil
converterOriginalNames    = converterOriginalNames    or {}  -- names NOT in current script
converterMatchingNames    = converterMatchingNames    or {}  -- names that ARE in current script (shown dimmed)
converterMappings         = converterMappings         or {}  -- {[origName] = convertedName}
converterLayerSelections  = converterLayerSelections  or {}  -- {[origName] = {[layerNum] = artIdx (1-based, non-live)}}
converterLastRefreshKey   = converterLastRefreshKey   or ""  -- track/take/focus change detection
converterLastFxName       = converterLastFxName       or nil -- detects script change so mappings can be rebuilt
converterHasUnmapped                = converterHasUnmapped                or false -- true if any original lacks a stored mapping
converterSelectedOriginals          = converterSelectedOriginals          or {}   -- {[name]=true} multi-select set
converterAnchorIdx                  = converterAnchorIdx                  or nil  -- shift-select anchor (1-based into allInputNames)
converterCursorIdx                  = converterCursorIdx                  or nil  -- keyboard navigation cursor
converterFocusedTable               = converterFocusedTable               or "input"
converterOutputFlatIdx              = converterOutputFlatIdx              or 1
converterOutputFocusedLayer         = converterOutputFocusedLayer         or 1
converterOutputLayerArtIdx          = converterOutputLayerArtIdx          or 1
converterPendingInputData           = converterPendingInputData           or nil
converterLayerSelectEnabled         = converterLayerSelectEnabled         or {}
converterLayerSelectFocused         = converterLayerSelectFocused         or 1
converterLayerSelectTrigger         = converterLayerSelectTrigger         or false
converterShowMappingsMode           = converterShowMappingsMode           or false
converterHasStoredMappings          = converterHasStoredMappings          or false
converterCachedScriptMappings       = converterCachedScriptMappings       or {}
converterStoredOnlyMappings         = converterStoredOnlyMappings         or {}
converterManualInputTriggerTableLayers  = converterManualInputTriggerTableLayers  or nil
converterManualInputMapName             = converterManualInputMapName             or nil
converterManualOutputTriggerTableLayers = converterManualOutputTriggerTableLayers or nil
converterManualOutputMapName            = converterManualOutputMapName            or nil
converterWindowHwnd                     = converterWindowHwnd                     or nil

local EXTSTATE_NS  = "articulationMap_converter"
local EXTSTATE_KEY = "mappings"

-- When the user picks an output script in the browser, use its layers instead of the track's.
local function effectiveLayers()
    return converterManualOutputTriggerTableLayers or triggerTableLayers
end

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

-- Returns true when every element of `needle` appears in `haystack` in order
-- (as a subsequence — extra elements in haystack between matches are allowed).
local function isSubsequence(needle, haystack)
    local ni = 1
    for _, h in ipairs(haystack) do
        if h == needle[ni] then
            ni = ni + 1
            if ni > #needle then return true end
        end
    end
    return false
end

-- Normalises a stored mapping value: old string format → new table format.
-- transpose_fixed: false = relative semitone offset (default), true = absolute MIDI pitch
-- velocity_fixed:  true  = absolute velocity (default), false = additive offset
local function normMapping(v)
    if type(v) == "string" then
        return {articulation = v, transpose = 0, transpose_fixed = false, velocity_fixed = false}
    end
    if type(v) == "table" then
        return {
            articulation    = v.articulation or "",
            transpose       = v.transpose or 0,
            transpose_fixed = v.transpose_fixed == true,
            velocity        = v.velocity,
            velocity_fixed  = v.velocity_fixed == true,
        }
    end
    return {articulation = "", transpose = 0, transpose_fixed = false, velocity_fixed = false}
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Name-building (depends on global triggerTableLayers)
-- ──────────────────────────────────────────────────────────────────────────────

-- Builds a per-layer lookup: {[layerNum] = {[articulationName] = true}}.
-- O(layers × arts) instead of the full Cartesian product.
local function buildLayerSets()
    local layers = effectiveLayers()
    if not layers or #layers == 0 then return nil end
    local sets = {}
    for layerNum, layer in ipairs(layers) do
        for _, art in ipairs(layer) do
            if not art.live then 
                if not sets[layerNum] then sets[layerNum] = {} end
                sets[layerNum][art.articulation] = true   
            end
        end
    end
    return sets
end

-- Returns true when every " / "-separated part of name matches its layer's non-live set.
local function isValidForLayers(name, layerSets)
    if not layerSets then return false end
    local parts = split_exact(name)
    if #parts ~= #layerSets then return false end
    for i, part in ipairs(parts) do
        if not layerSets[i][part] then return false end
    end
    return true
end

local function buildDefaultConvertedName()
    local layers = effectiveLayers()
    if not layers or #layers == 0 then return "" end
    local parts = {}
    for _, layer in ipairs(layers) do
        for _, art in ipairs(layer) do
            if not art.live then table.insert(parts, art.articulation); break end
        end
    end
    return table.concat(parts, " / ")
end

local function buildConvertedNameFromSelections(origName)
    local layers = effectiveLayers()
    if not layers or #layers == 0 then return "" end
    local sels, parts = converterLayerSelections[origName] or {}, {}
    for layerNum, layer in ipairs(layers) do
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
    local layers = effectiveLayers()
    if not convertedName or not layers then return end
    local parts = split_exact(convertedName)
    converterLayerSelections[origName] = {}
    for layerNum, layer in ipairs(layers) do
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
-- Fuzzy name matching
-- ──────────────────────────────────────────────────────────────────────────────

local function levenshtein(a, b)
    local m, n = #a, #b
    if m == 0 then return n end
    if n == 0 then return m end
    local prev = {}
    for j = 0, n do prev[j] = j end
    for i = 1, m do
        local curr = {[0] = i}
        local ai = a:sub(i, i)
        for j = 1, n do
            local cost = (ai == b:sub(j, j)) and 0 or 1
            curr[j] = math.min(curr[j-1] + 1, prev[j] + 1, prev[j-1] + cost)
        end
        prev = curr
    end
    return prev[n]
end

local function stringSimilarity(a, b)
    a, b = a:lower(), b:lower()
    if a == b then return 1 end
    local maxLen = math.max(#a, #b)
    if maxLen == 0 then return 1 end
    return 1 - levenshtein(a, b) / maxLen
end

-- For each layer in the current script, finds the non-live articulation whose name
-- is most similar to the corresponding part of origName (split by " / ").
-- Uses the layer's first non-live articulation when the best similarity is below
-- threshold or when origName has fewer parts than the script has layers.
local function buildBestConvertedName(origName, threshold)
    local layers = effectiveLayers()
    if not layers or #layers == 0 then return "" end
    local parts = split_exact(origName)
    local result = {}
    for layerNum, layer in ipairs(layers) do
        local origPart = parts[layerNum] or ""
        local bestSim, bestArt, defaultArt = -1, nil, nil
        for _, art in ipairs(layer) do
            if not art.live then
                if not defaultArt then defaultArt = art end
                if origPart ~= "" then
                    local sim = stringSimilarity(origPart, art.articulation)
                    if sim > bestSim then bestSim = sim; bestArt = art end
                end
            end
        end
        local chosen = (origPart ~= "" and bestSim >= threshold) and bestArt or defaultArt
        if chosen then table.insert(result, chosen.articulation) end
    end
    return table.concat(result, " / ")
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
    if converterShowMappingsMode then
        local stored = loadStoredMappings()
        local scriptStored = (fxName and stored[fxName]) or {}
        local names = {}
        for name in pairs(scriptStored) do table.insert(names, name) end
        table.sort(names)
        return names
    end
    -- When a manual input script is selected, enumerate all its non-live name combinations.
    if converterManualInputTriggerTableLayers then
        local inputLayers = converterManualInputTriggerTableLayers
        local seen, names = {}, {}
        local function recurse(li, parts)
            if li > #inputLayers then
                local name = table.concat(parts, " / ")
                if not seen[name] then seen[name] = true; table.insert(names, name) end
                return
            end
            for _, art in ipairs(inputLayers[li]) do
                if not art.live then
                    parts[li] = art.articulation
                    recurse(li + 1, parts)
                end
            end
        end
        recurse(1, {})
        table.sort(names)
        return names
    end
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
    converterOriginalNames     = {}
    converterMatchingNames     = {}
    converterHasUnmapped       = false
    converterSelectedOriginal  = nil
    converterSelectedOriginals = {}
    converterCursorIdx         = nil
    converterAnchorIdx         = nil
    converterFocusedTable      = "input"

    -- When the articulation script itself changes, discard all in-session mappings
    -- so defaults are rebuilt for the new script. When only take/focus changes within
    -- the same script, keep any user edits that haven't been stored yet.
    if fxName ~= converterLastFxName then
        converterLastFxName      = fxName
        converterMappings        = {}
        converterLayerSelections = {}
        converterSelectedOriginal = nil
        converterShowMappingsMode = false
    end

    local layerSets    = buildLayerSets()
    local stored       = loadStoredMappings()
    local scriptStored = (fxName and stored[fxName]) or {}
    converterHasStoredMappings = next(scriptStored) ~= nil
    converterCachedScriptMappings = {}
    for k, v in pairs(scriptStored) do converterCachedScriptMappings[k] = v end
    converterStoredOnlyMappings = {}

    for _, name in ipairs(collectTextsForCurrentFocus()) do
        if isValidForLayers(name, layerSets) then
            -- Name already exists in script → show dimmed at bottom, identity default
            table.insert(converterMatchingNames, name)
            if not converterMappings[name] then
                converterMappings[name] = {articulation = name, transpose = 0}
                initSelectionsFromName(name, name)
            end
        else
            -- Name not in script → needs conversion
            table.insert(converterOriginalNames, name)
            if scriptStored[name] then
                local m = normMapping(scriptStored[name])
                converterMappings[name] = m
                converterStoredOnlyMappings[name] = m
                initSelectionsFromName(name, m.articulation)
            else
                local parts = split_exact(name)
                local confirmed = false
                local needsMapping = not converterMappings[name]

                -- 1. Component match: every part has its own stored mapping
                local compParts, allMatched = {}, #parts > 1
                for _, part in ipairs(parts) do
                    if scriptStored[part] then
                        table.insert(compParts, normMapping(scriptStored[part]).articulation)
                    else
                        allMatched = false
                        break
                    end
                end
                if allMatched then
                    local compName = table.concat(compParts, " / ")
                    local compMapping = {articulation = compName, transpose = 0}
                    if needsMapping then
                        converterMappings[name] = compMapping
                        initSelectionsFromName(name, compName)
                    end
                    converterStoredOnlyMappings[name] = compMapping
                    confirmed = true
                else
                    -- 2. Subsequence match: a stored multi-part key whose parts appear in order
                    --    as a subsequence of this name's parts. Prefer the longest match.
                    local subseqMapping = nil
                    local subseqLen = 0
                    for storedKey, storedVal in pairs(scriptStored) do
                        local storedParts = split_exact(storedKey)
                        if #storedParts >= 2 and #storedParts < #parts
                           and #storedParts > subseqLen
                           and isSubsequence(storedParts, parts) then
                            subseqMapping = normMapping(storedVal)
                            subseqLen = #storedParts
                        end
                    end
                    if subseqMapping then
                        if needsMapping then
                            converterMappings[name] = subseqMapping
                            initSelectionsFromName(name, subseqMapping.articulation)
                        end
                        converterStoredOnlyMappings[name] = subseqMapping
                        confirmed = true
                    else
                        -- 3. Single-part match: any part has a stored mapping or is valid in output
                        local partMapping = nil
                        for _, part in ipairs(parts) do
                            if scriptStored[part] then
                                partMapping = normMapping(scriptStored[part])
                                break
                            end
                        end
                        if not partMapping then
                            for _, part in ipairs(parts) do
                                if isValidForLayers(part, layerSets) then
                                    partMapping = {articulation = part, transpose = 0}
                                    break
                                end
                            end
                        end
                        if partMapping then
                            if needsMapping then
                                converterMappings[name] = partMapping
                                initSelectionsFromName(name, partMapping.articulation)
                            end
                            converterStoredOnlyMappings[name] = partMapping
                            confirmed = true
                        else
                            -- 4. Fuzzy guess: not confirmed — user must review
                            if needsMapping then
                                local threshold = settings and settings.converter_fuzzy_threshold or 0.4
                                local bestName = buildBestConvertedName(name, threshold)
                                converterMappings[name] = {articulation = bestName, transpose = 0}
                                initSelectionsFromName(name, bestName)
                            end
                        end
                    end
                end
                if not confirmed then converterHasUnmapped = true end
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

    -- Remove stale names from multi-selection
    for name in pairs(converterSelectedOriginals) do
        local found = false
        for _, n in ipairs(converterOriginalNames) do if n == name then found = true; break end end
        if not found then
            for _, n in ipairs(converterMatchingNames) do if n == name then found = true; break end end
        end
        if not found then converterSelectedOriginals[name] = nil end
    end
    -- Auto-select the first item when nothing is selected so the converter is ready to navigate
    if not converterSelectedOriginal and #converterOriginalNames > 0 then
        converterSelectedOriginal = converterOriginalNames[1]
        converterSelectedOriginals = {[converterOriginalNames[1]] = true}
        converterCursorIdx = 1
        converterAnchorIdx = 1
    elseif not converterSelectedOriginal and #converterMatchingNames > 0 then
        converterSelectedOriginal = converterMatchingNames[1]
        converterSelectedOriginals = {[converterMatchingNames[1]] = true}
        converterCursorIdx = 1
        converterAnchorIdx = 1
    end

    -- Primary selection is always included in the multi-select set
    --if converterSelectedOriginal then
    --    converterSelectedOriginals[converterSelectedOriginal] = true
    --end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Public: apply conversions
-- ──────────────────────────────────────────────────────────────────────────────

function export.applyConversionToTake(t, conversions, selectedOnly, refresh)
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
    local toModify = {}
    for k = textCount - 1, 0, -1 do
        local ok, selected, muted, ppqpos, _type, msg = reaper.MIDI_GetTextSysexEvt(t, k)
        if ok and _type == 15 then
            local ch, pitch, name = getSysexValues(msg)
            if name and conversions[name] then
                local m = normMapping(conversions[name])
                local isIdentity = (m.articulation == name and (m.transpose or 0) == 0 and not m.velocity)
                if not isIdentity then
                    local passFilter = (not noteFilter)
                        or noteFilter[ch .. "_" .. pitch .. "_" .. math.floor(ppqpos)] == true
                    if passFilter then
                        table.insert(toModify, {
                            k=k, sel=selected, mut=muted, ppq=ppqpos,
                            ch=ch, pitch=tonumber(pitch), m=m
                        })
                    end
                end
            end
        end
    end

    local modified = #toModify > 0
    if modified then

        -- Apply pitch/velocity changes to the corresponding MIDI notes
        local _, noteCount = reaper.MIDI_CountEvts(t)
        for _, e in ipairs(toModify) do
            local transpose       = e.m.transpose or 0
            local transposeFixed  = e.m.transpose_fixed == true
            local velocityVal     = e.m.velocity
            local velocityFixed   = e.m.velocity_fixed == true
            if transpose ~= 0 or velocityVal then
                for i = 0, noteCount - 1 do
                    local ok, sel, mut, ppq, endppq, ch, pitch, vel = reaper.MIDI_GetNote(t, i)
                    if ok and ch == tonumber(e.ch) and pitch == e.pitch and math.floor(ppq) == math.floor(e.ppq) then
                        local newPitch = transposeFixed
                            and math.max(0, math.min(127, transpose))
                            or  math.max(0, math.min(127, pitch + transpose))
                        local newVel
                        if velocityVal then
                            if velocityFixed then
                                newVel = math.min(127, math.max(1, velocityVal))
                            else
                                newVel = math.min(127, math.max(1, vel + velocityVal))
                            end
                        else
                            newVel = vel
                        end
                        reaper.MIDI_SetNote(t, i, sel, mut, ppq, endppq, ch, newPitch, newVel, true)
                        break
                    end
                end
            end
        end

        -- Rewrite sysex events (already reversed so indices stay valid)
        for _, e in ipairs(toModify) do
            local t_val = e.m.transpose or 0
            local newPitch = e.m.transpose_fixed
                and math.max(0, math.min(127, t_val))
                or  math.max(0, math.min(127, e.pitch + t_val))
            local newMsg = string.format('NOTE %s %s text "%s"', e.ch, newPitch, e.m.articulation)
            reaper.MIDI_DeleteTextSysexEvt(t, e.k)
            reaper.MIDI_InsertTextSysexEvt(t, e.sel, e.mut, e.ppq, 15, newMsg)
        end

        reaper.MIDI_Sort(t)
        mirror_notation_to_unique_text_events(t)
        if refresh then
            export.refreshOriginals()
        end
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
-- Store / delete helpers (shared between buttons and keyboard shortcuts)
-- ──────────────────────────────────────────────────────────────────────────────

local function deleteSelectedMappings()
    if not fxName then return end
    local stored = loadStoredMappings()
    if not stored[fxName] then return end
    for name in pairs(converterSelectedOriginals) do
        stored[fxName][name] = nil
    end
    if not next(stored[fxName]) then stored[fxName] = nil end
    saveStoredMappings(stored)
    converterShowMappingsMode = false
    export.refreshOriginals()
    -- Reactivate show-mappings only if there are still stored mappings
    if converterHasStoredMappings then
        converterShowMappingsMode = true
        export.refreshOriginals()
    end
end

local function storeCurrentMappings()
    if not fxName then return end
    local stored   = loadStoredMappings()
    local layerSets = buildLayerSets()
    stored[fxName] = stored[fxName] or {}
    converterStoredOnlyMappings = {}
    for origName, mapping in pairs(converterMappings) do
        -- Only store mappings for names that are NOT already in the script
        if not isValidForLayers(origName, layerSets) then
            local m = normMapping(mapping)
            -- Omit keys that are nil or equal to their defaults to keep JSON clean
            local entry = {articulation = m.articulation, transpose = m.transpose}
            if m.transpose_fixed then entry.transpose_fixed = true end
            if m.velocity then entry.velocity = m.velocity end
            if m.velocity_fixed then entry.velocity_fixed = true end
            stored[fxName][origName] = entry
            converterStoredOnlyMappings[origName] = entry
        end
    end
    saveStoredMappings(stored)
    converterHasStoredMappings = true
    converterCachedScriptMappings = {}
    for k, v in pairs(stored[fxName]) do converterCachedScriptMappings[k] = v end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Shared rendering helpers
-- ──────────────────────────────────────────────────────────────────────────────

-- Renders the Original+Converted 4-column table (Input, Output, T, V) inside an already-begun child.
-- allInputNames is the flat ordered list used for shift/arrow range selection.
local function renderPairTable(ctx, allInputNames)
    local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
    local cmd   = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())

    local DRAG_W      = 32
    local BTN_SZ      = 16
    local COL_W       = DRAG_W + 1 + BTN_SZ
    local grayCol     = 0x888888FF
    local whiteCol    = 0xFFFFFFFF
    local frameBgGray = 0x2E2E2EFF

    local showT   = settings.converter_show_transpose_column == true
    local showV   = settings.converter_show_velocity_column  == true
    local tColIdx = showT and 2 or nil
    local vColIdx = showV and (showT and 3 or 2) or nil
    local numCols = 2 + (showT and 1 or 0) + (showV and 1 or 0)

    local fixedFlag = reaper.ImGui_TableColumnFlags_WidthFixed()
    local tblFlags  = reaper.ImGui_TableFlags_BordersInnerV()
    if not reaper.ImGui_BeginTable(ctx, "##convTbl", numCols, tblFlags) then return end

    reaper.ImGui_TableSetupColumn(ctx, "Input text:",   0)
    reaper.ImGui_TableSetupColumn(ctx, "Output text:",  0)
    if showT then reaper.ImGui_TableSetupColumn(ctx, "Pitch",    fixedFlag, COL_W) end
    if showV then reaper.ImGui_TableSetupColumn(ctx, "Velocity", fixedFlag, COL_W) end
    reaper.ImGui_TableHeadersRow(ctx)

    local defaultName = buildDefaultConvertedName()

    -- Shared click handler for the left (input) column
    local function handleInputClick(origName, flatIdx)
        converterFocusedTable     = "input"
        converterSelectedOriginal = origName
        if shift and converterAnchorIdx then
            local lo = math.min(converterAnchorIdx, flatIdx)
            local hi = math.max(converterAnchorIdx, flatIdx)
            converterSelectedOriginals = {}
            for i = lo, hi do
                if allInputNames[i] then converterSelectedOriginals[allInputNames[i]] = true end
            end
            converterCursorIdx = flatIdx
        elseif cmd then
            if converterSelectedOriginals[origName] then
                converterSelectedOriginals[origName] = nil
                if converterSelectedOriginal == origName then
                    converterSelectedOriginal = nil
                end
            else
                converterSelectedOriginals[origName] = true
                converterAnchorIdx = flatIdx
                converterCursorIdx = flatIdx
            end
        else
            converterSelectedOriginals = {[origName] = true}
            converterAnchorIdx = flatIdx
            converterCursorIdx = flatIdx
        end
    end

    -- Renders T and V columns for a single row.  uid must be unique per row.
    local function renderTVCells(origName, m, uid, tIdx, vIdx)
        local function dragThenF(colIdx, value, isFixed, minVal, dragId, btnId, tip)
            reaper.ImGui_TableSetColumnIndex(ctx, colIdx)
            -- DragInt: gray frame, gray 1 px border, 30 px wide

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),  (not isFixed and value == 0) and grayCol or whiteCol)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),      grayCol)
            reaper.ImGui_PushStyleVar(ctx,   reaper.ImGui_StyleVar_FrameBorderSize(), 1)
            reaper.ImGui_SetNextItemWidth(ctx, DRAG_W)
            local changed, newVal = reaper.ImGui_DragInt(ctx, dragId, value, 1, minVal, 127)
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_PopStyleColor(ctx, 2)
            setToolTipFunc(tip)

            -- F button: border only (gray=off, white=on), no background push
            reaper.ImGui_SameLine(ctx, 0, 1)
            local borderCol = isFixed and whiteCol or grayCol
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), borderCol)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),   borderCol)
            reaper.ImGui_PushStyleVar(ctx,   reaper.ImGui_StyleVar_FrameBorderSize(), 1)
            local clicked = reaper.ImGui_Button(ctx, "F" .. btnId, BTN_SZ, 20)
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_PopStyleColor(ctx, 2)
            setToolTipFunc(tip)
            return changed, newVal, clicked
        end

        -- Propagates a mutation function to all selected originals except origName itself.
        local function propagate(fn)
            for selName in pairs(converterSelectedOriginals) do
                if selName ~= origName then
                    converterMappings[selName] = fn(normMapping(converterMappings[selName]))
                end
            end
        end

        -- T column
        local tFixed = m.transpose_fixed == true
        local tMin   = tFixed and 0 or -127
        local tChanged, newT, tClicked
        if tIdx then
            tChanged, newT, tClicked = dragThenF(
                tIdx, m.transpose or 0, tFixed, tMin,
                "##T" .. uid, "##TF" .. uid,
                tFixed and "Fixed pitch: sets exact MIDI note. Click F for relative (semitone offset)."
                        or "Relative: semitone offset applied to original pitch. Click F for fixed pitch.")
        end
        if tClicked then
            local newFixed = not tFixed
            m.transpose_fixed = newFixed
            if newFixed then m.transpose = math.max(0, math.min(127, m.transpose or 0)) end
            converterMappings[origName] = m
            propagate(function(s)
                s.transpose_fixed = newFixed
                if newFixed then s.transpose = math.max(0, math.min(127, s.transpose or 0)) end
                return s
            end)
        elseif tChanged then
            local newTranspose = math.max(tMin, math.min(127, newT))
            m.transpose = newTranspose
            converterMappings[origName] = m
            propagate(function(s)
                local sMin = s.transpose_fixed and 0 or -127
                s.transpose = math.max(sMin, math.min(127, newTranspose))
                return s
            end)
        end

        -- V column
        local vFixed = m.velocity_fixed == true
        local vMin   = vFixed and 0 or -127
        local vChanged, newV, vClicked
        if vIdx then
            vChanged, newV, vClicked = dragThenF(
                vIdx, m.velocity or 0, vFixed, vMin,
                "##V" .. uid, "##VF" .. uid,
                vFixed and "Fixed velocity: sets exact value (0 = keep original). Click F for relative (additive offset)."
                        or "Relative: offset added to original velocity. Click F for fixed velocity.")
        end
        if vClicked then
            local newFixed = not vFixed
            m.velocity_fixed = newFixed
            if newFixed and m.velocity then
                m.velocity = math.max(0, math.min(127, m.velocity))
                if m.velocity == 0 then m.velocity = nil end
            end
            converterMappings[origName] = m
            propagate(function(s)
                s.velocity_fixed = newFixed
                if newFixed and s.velocity then
                    s.velocity = math.max(0, math.min(127, s.velocity))
                    if s.velocity == 0 then s.velocity = nil end
                end
                return s
            end)
        elseif vChanged then
            local newVel = math.max(vMin, math.min(127, newV))
            m.velocity = newVel ~= 0 and newVel or nil
            converterMappings[origName] = m
            propagate(function(s)
                local sMin = s.velocity_fixed and 0 or -127
                local sv = math.max(sMin, math.min(127, newVel))
                s.velocity = sv ~= 0 and sv or nil
                return s
            end)
        end
    end

    -- Non-matching names (normal color)
    for idx, origName in ipairs(converterOriginalNames) do
        local flatIdx    = idx
        local isSelected = converterSelectedOriginals[origName] == true
        local m          = normMapping(converterMappings[origName] or defaultName)

        reaper.ImGui_TableNextRow(ctx)

        reaper.ImGui_TableSetColumnIndex(ctx, 0)
        if reaper.ImGui_Selectable(ctx, origName .. "##orig" .. idx, isSelected, 0) then
            handleInputClick(origName, flatIdx)
        end

        reaper.ImGui_TableSetColumnIndex(ctx, 1)
        if reaper.ImGui_Selectable(ctx, m.articulation .. "##conv" .. idx, nil, 0) then
            if converterSelectedOriginal and converterSelectedOriginal ~= origName then
                -- Copy all settings from this row to all selected originals
                for name in pairs(converterSelectedOriginals) do
                    converterMappings[name] = {
                        articulation    = m.articulation,
                        transpose       = m.transpose,
                        transpose_fixed = m.transpose_fixed,
                        velocity        = m.velocity,
                        velocity_fixed  = m.velocity_fixed,
                    }
                    initSelectionsFromName(name, m.articulation)
                end
            else
                handleInputClick(origName, flatIdx)
            end
        end
        setToolTipFunc("Copy output to selected inputs")

        renderTVCells(origName, m, idx, tColIdx, vColIdx)
    end

    -- Matching names (dimmed; T/V still editable)
    if #converterMatchingNames > 0 and settings.converter_show_matching then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
        local offset = #converterOriginalNames
        for idx, origName in ipairs(converterMatchingNames) do
            local flatIdx    = offset + idx
            local i          = flatIdx
            local isSelected = converterSelectedOriginals[origName] == true
            local m          = normMapping(converterMappings[origName] or origName)

            reaper.ImGui_TableNextRow(ctx)

            reaper.ImGui_TableSetColumnIndex(ctx, 0)
            if reaper.ImGui_Selectable(ctx, origName .. "##orig" .. i, isSelected, 0) then
                handleInputClick(origName, flatIdx)
            end

            reaper.ImGui_TableSetColumnIndex(ctx, 1)
            if reaper.ImGui_Selectable(ctx, m.articulation .. "##conv" .. i, false, 0) then
                if converterSelectedOriginal and converterSelectedOriginal ~= origName then
                    for name in pairs(converterSelectedOriginals) do
                        local existing = normMapping(converterMappings[name])
                        converterMappings[name] = {
                            articulation    = m.articulation,
                            transpose       = m.transpose,
                            transpose_fixed = m.transpose_fixed,
                            velocity        = m.velocity,
                            velocity_fixed  = m.velocity_fixed,
                        }
                        initSelectionsFromName(name, m.articulation)
                    end
                else
                    handleInputClick(origName, flatIdx)
                end
            end
            setToolTipFunc("Copy output to selected inputs")

            renderTVCells(origName, m, "m" .. i, tColIdx, vColIdx)
        end
        reaper.ImGui_PopStyleColor(ctx)
    end

    reaper.ImGui_EndTable(ctx)
end

-- Renders the Available list inside an already-begun child.
-- All layers show their current mapping highlighted simultaneously.
-- The layer matching converterOutputFocusedLayer (when output is focused) gets a white header
-- and uses converterOutputLayerArtIdx as the keyboard cursor instead of the stored mapping.
local function renderAvailableList(ctx)
    local layers = effectiveLayers() or {}
    for layerNumber, layer in ipairs(layers) do
        local isLayerFocused = converterFocusedTable == "output"
            and layerNumber == converterOutputFocusedLayer
        if #layers > 1 and not layer[1].live then
            local headerColor = isLayerFocused and 0xFFFFFFFF or 0xAAAAAAFF
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), headerColor)
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
                -- Focused layer: show keyboard cursor; other layers: show stored mapping.
                local showSel = isLayerFocused
                    and (artIdx == converterOutputLayerArtIdx)
                    or  (not isLayerFocused and isSel == true)
                if reaper.ImGui_Selectable(ctx,
                        art.articulation .. "##avail" .. layerNumber .. "_" .. artIdx,
                        showSel) then
                    converterFocusedTable       = "output"
                    converterOutputFocusedLayer = layerNumber
                    converterOutputLayerArtIdx  = artIdx
                    local targets = next(converterSelectedOriginals) ~= nil
                        and converterSelectedOriginals
                        or (converterSelectedOriginal and {[converterSelectedOriginal] = true} or {})
                    for name in pairs(targets) do
                        converterLayerSelections[name] = converterLayerSelections[name] or {}
                        converterLayerSelections[name][layerNumber] = artIdx
                        local artName  = buildConvertedNameFromSelections(name)
                        local existing = normMapping(converterMappings[name])
                        existing.articulation = artName
                        converterMappings[name] = existing
                    end
                end
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Public: manual script selection (called by Background Server from ExtState data)
-- ──────────────────────────────────────────────────────────────────────────────

function export.setManualInput(data)
    if data then
        converterManualInputTriggerTableLayers = data.triggerTableLayers
        converterManualInputMapName            = data.mapName
    else
        converterManualInputTriggerTableLayers = nil
        converterManualInputMapName            = nil
    end
    converterLastFxName = nil
    export.refreshOriginals()
end

function export.setManualOutput(data)
    if data then
        converterManualOutputTriggerTableLayers = data.triggerTableLayers
        converterManualOutputMapName            = data.mapName
    else
        converterManualOutputTriggerTableLayers = nil
        converterManualOutputMapName            = nil
    end
    converterLastFxName = nil
    export.refreshOriginals()
end

-- Called by Background Server when a multi-layer script is picked for input.
-- Shows a layer selection popup before loading, so the user can choose which
-- layers form the input combinations (avoids the Cartesian product blowup).
function export.setPendingInputData(data)
    converterPendingInputData   = data
    converterLayerSelectEnabled = {}
    converterLayerSelectFocused = 1
    for layerNum in pairs(data.triggerTableLayers) do
        converterLayerSelectEnabled[layerNum] = true
    end
    converterLayerSelectTrigger = true
end

-- Renders the modal popup for choosing which layers to include from a pending input script.
local function renderLayerSelectPopup(ctx)
    if converterLayerSelectTrigger then
        reaper.ImGui_OpenPopup(ctx, "Choose Input Layers##converter")
        converterLayerSelectTrigger = false
    end

    if not reaper.ImGui_BeginPopupModal(ctx, "Choose Input Layers##converter", nil,
            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        return
    end

    local data = converterPendingInputData
    if not data then
        reaper.ImGui_CloseCurrentPopup(ctx)
        reaper.ImGui_EndPopup(ctx)
        return
    end

    local layerNums = {}
    for k in pairs(data.triggerTableLayers) do table.insert(layerNums, k) end
    table.sort(layerNums)

    local arrowUp   = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow(),   true)
    local arrowDown = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow(), true)
    local space     = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space(),     false)
    local enter     = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(),     false)
    local escape    = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(),    false)

    if arrowUp   then converterLayerSelectFocused = math.max(1, converterLayerSelectFocused - 1) end
    if arrowDown then converterLayerSelectFocused = math.min(#layerNums, converterLayerSelectFocused + 1) end
    if space then
        local layerNum = layerNums[converterLayerSelectFocused]
        if layerNum then converterLayerSelectEnabled[layerNum] = not converterLayerSelectEnabled[layerNum] end
    end

    reaper.ImGui_Text(ctx, 'Opening "' .. (data.mapName or "Script") .. '"')
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_BeginChild(ctx, "##layerSelectList", 320, 300, 0) then
        for i, layerNum in ipairs(layerNums) do
            local layer   = data.triggerTableLayers[layerNum]
            local enabled = converterLayerSelectEnabled[layerNum] == true
            local focused = i == converterLayerSelectFocused
            local label   = (enabled and "[x] " or "[ ] ") .. "Layer " .. layerNum
            if reaper.ImGui_Selectable(ctx, label, focused) then
                converterLayerSelectFocused         = i
                converterLayerSelectEnabled[layerNum] = not enabled
            end
            reaper.ImGui_Indent(ctx)
            local shown = 0
            for _, art in ipairs(layer) do
                if not art.live then
                    shown = shown + 1
                    if shown <= 20 then
                        reaper.ImGui_TextDisabled(ctx, art.articulation)
                    end
                end
            end
            if shown > 20 then
                reaper.ImGui_TextDisabled(ctx, "... and " .. (shown - 20) .. " more")
            end
            reaper.ImGui_Unindent(ctx)
        end
        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_Separator(ctx)

    local count, anyEnabled = 1, false
    for _, layerNum in ipairs(layerNums) do
        if converterLayerSelectEnabled[layerNum] then
            local nonLive = 0
            for _, art in ipairs(data.triggerTableLayers[layerNum]) do
                if not art.live then nonLive = nonLive + 1 end
            end
            count      = count * math.max(1, nonLive)
            anyEnabled = true
        end
    end
    if not anyEnabled then count = 0 end
    reaper.ImGui_Text(ctx, "with " .. count .. " articulation variation" .. (count == 1 and "" or "s"))

    if not anyEnabled then reaper.ImGui_BeginDisabled(ctx) end
    if reaper.ImGui_Button(ctx, "Open") or (enter and anyEnabled) then
        local filteredLayers, newIdx = {}, 1
        for _, layerNum in ipairs(layerNums) do
            if converterLayerSelectEnabled[layerNum] then
                filteredLayers[newIdx] = data.triggerTableLayers[layerNum]
                newIdx = newIdx + 1
            end
        end
        data.triggerTableLayers = filteredLayers
        export.setManualInput(data)
        converterPendingInputData = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    if not anyEnabled then reaper.ImGui_EndDisabled(ctx) end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel") or escape then
        converterPendingInputData = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
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

    if reaper.GetExtState("articulationMapConverter", "converterShouldFocus") == "1" then
        reaper.SetExtState("articulationMapConverter", "converterShouldFocus", "", false)
        reaper.ImGui_SetNextWindowFocus(ctx)
        if converterWindowHwnd then reaper.JS_Window_SetFocus(converterWindowHwnd) end
    end

    local visible, open = reaper.ImGui_Begin(ctx, "Articulation Converter", true,
        reaper.ImGui_WindowFlags_TopMost()
        | reaper.ImGui_WindowFlags_MenuBar()
    )
    reaper.ImGui_PopFont(ctx)

    if visible then
        if reaper.ImGui_IsWindowFocused(ctx) then
            converterWindowHwnd = reaper.JS_Window_GetForeground()
        end

        -- Snapshot BEFORE rendering so closing-frame keys stay blocked in the main window.
        local popupIsOpen = reaper.ImGui_IsPopupOpen(ctx, "Choose Input Layers##converter")
        renderLayerSelectPopup(ctx)
        popupIsOpen = popupIsOpen or reaper.ImGui_IsPopupOpen(ctx, "Choose Input Layers##converter")
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

                local transpChanged
                transpChanged, settings.converter_show_transpose_column =
                    reaper.ImGui_MenuItem(ctx, "Show pitch column",
                        nil, settings.converter_show_transpose_column)
                if transpChanged then saveSettings() end

                local velChanged
                velChanged, settings.converter_show_velocity_column =
                    reaper.ImGui_MenuItem(ctx, "Show velocity column",
                        nil, settings.converter_show_velocity_column)
                if velChanged then saveSettings() end

                reaper.ImGui_Separator(ctx)

                if reaper.ImGui_MenuItem(ctx, "Export all stored settings...") then
                    local defaultPath = reaper.GetResourcePath() .. "/Scripts/"
                    local _, filepath = reaper.JS_Dialog_BrowseForSaveFile(
                        "Export Converter Settings", defaultPath,
                        "articulation_converter_settings", "JSON\0*.json\0All files\0*.*\0")
                    if filepath and filepath ~= "" then
                        if not filepath:match("%.json$") then filepath = filepath .. ".json" end
                        local f = io.open(filepath, "w")
                        if f then f:write(json.encodeToJson(loadStoredMappings())); f:close() end
                    end
                end
                if reaper.ImGui_MenuItem(ctx, "Import stored settings...") then
                    local defaultPath = reaper.GetResourcePath() .. "/Scripts/"
                    local _, filepath = reaper.JS_Dialog_BrowseForOpenFiles(
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

                -- Import-from-previous dropdown
                local storedAll     = loadStoredMappings()
                local storedScripts = {}
                for scriptName in pairs(storedAll) do
                    --if scriptName ~= fxName then 
                        table.insert(storedScripts, scriptName)     
                    --end
                end
                table.sort(storedScripts)

                
                if #storedScripts > 0 then
                    local layerSets = buildLayerSets()
                    reaper.ImGui_SetNextItemWidth(ctx, 200)
                    if reaper.ImGui_BeginCombo(ctx, "##importFrom", "Import from a stored mapping") then
                        for _, scriptName in ipairs(storedScripts) do
                            if reaper.ImGui_Selectable(ctx, scriptName, false) then
                                local sourceMap = storedAll[scriptName] or {}
                                for origName, storedVal in pairs(sourceMap) do
                                    local m = normMapping(storedVal)
                                    if isValidForLayers(m.articulation, layerSets) then
                                        for _, n in ipairs(converterOriginalNames) do
                                            if n == origName then
                                                converterMappings[origName] = m
                                                initSelectionsFromName(origName, m.articulation)
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end 
                    setToolTipFunc("Import any matching mappings from a stored mapping.\nThis is useful if have made a new version of a previously made map.")
                end

                reaper.ImGui_SetNextItemWidth(ctx, 80)
                local threshChanged, newThresh = reaper.ImGui_DragDouble(ctx, "Match precision##fuzzyThresh",
                    settings.converter_fuzzy_threshold or 0.4, 0.01, 0.0, 1.0, "%.2f")
                if threshChanged then
                    settings.converter_fuzzy_threshold = math.max(0.0, math.min(1.0, newThresh))
                    saveSettings()
                    converterLastFxName = nil  -- force mappings to rebuild with new threshold
                    export.refreshOriginals()
                end
                setToolTipFunc("Minimum similarity (0–1) to auto-match to a script articulation. Falls back to the script's first articulation if no match qualifies.")

                if reaper.ImGui_BeginMenu(ctx, "Help") then
                    
                    reaper.ImGui_SeparatorText(ctx, "Focus")
                    reaper.ImGui_Text(ctx, "Use arrow left/right to move between input and output table (and layers in the output table).\n - Hold shift to go backwards. ")
                    reaper.ImGui_SeparatorText(ctx, "Input table")
                    reaper.ImGui_Text(ctx, "Use arrow up/down to select and focus a specific input text")
                    reaper.ImGui_Text(ctx, " - Hold shift to select multiple.")
                    reaper.ImGui_Text(ctx, " - If clicking with mouse hold down super to toggle specific ones.")
                    reaper.ImGui_Text(ctx, "Click an output button in the table to set the selected input to this articulation")
                    reaper.ImGui_Text(ctx, "If showing the selected output scripts mappings, use delete or backspace to remove selected mappings")
                    reaper.ImGui_SeparatorText(ctx, "Output table")
                    reaper.ImGui_Text(ctx, "Use arrow up and down to select articulations in the focused layer.")
                    reaper.ImGui_Text(ctx, "Use arrow left/right to go through the layers.")
                    reaper.ImGui_SeparatorText(ctx, "Buttons")
                    reaper.ImGui_Text(ctx, "Press I to select a specific articulation script as input")
                    reaper.ImGui_Text(ctx, "Press M to toggle showing matching articulation")
                    reaper.ImGui_Text(ctx, "Press O to select a specific articulation script as output")
                    reaper.ImGui_Text(ctx, "Press S to show selected output scripts mappings")
                    reaper.ImGui_SeparatorText(ctx, "Choose input layer popup")
                    reaper.ImGui_Text(ctx, "Use arrow up/down to select layer")
                    reaper.ImGui_Text(ctx, "Use space to toggle selected layer")
                    reaper.ImGui_Text(ctx, "Use enter to open with the enabled layers")
                    reaper.ImGui_Text(ctx, "Use escape to cancel")
                    reaper.ImGui_SeparatorText(ctx, "Execution")
                    reaper.ImGui_Text(ctx, "Press Enter to apply and/or store settings")
                    reaper.ImGui_Text(ctx, "Press escape to close the converter window")
                    reaper.ImGui_SeparatorText(ctx, "Browser window")
                    reaper.ImGui_Text(ctx, "Navigate the browser window as normal")
                    reaper.ImGui_Text(ctx, "Press Enter to open the selected articulation script")
                    reaper.ImGui_Text(ctx, "Press escape to abort selecting an articulation script")                   

                    reaper.ImGui_EndMenu(ctx)
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



        local hasOriginals = #converterOriginalNames > 0

        -- ── Navigation lists (used for arrow keys and shift/range selection) ──
        local allInputNames = {}
        for _, n in ipairs(converterOriginalNames) do table.insert(allInputNames, n) end
        if settings.converter_show_matching then
            for _, n in ipairs(converterMatchingNames) do table.insert(allInputNames, n) end
        end

        local effLayers    = effectiveLayers() or {}
        local numOutLayers = #effLayers

        -- Clamp focused layer in case the output script changed to one with fewer layers.
        if converterFocusedTable == "output" and converterOutputFocusedLayer > numOutLayers then
            converterOutputFocusedLayer = math.max(1, numOutLayers)
        end

        local anyInputActive = reaper.ImGui_IsAnyItemActive(ctx)
        local navShift  = not popupIsOpen and not anyInputActive and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        local arrowUp   = not popupIsOpen and not anyInputActive and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow(),   true)
        local arrowDown = not popupIsOpen and not anyInputActive and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow(), true)

        -- ── Keyboard navigation ──
        -- Right/Left: cycle input → layer 1 → layer 2 → … → layerN → input
        local navRight = not popupIsOpen and not anyInputActive and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow(), false)
        local navLeft  = not popupIsOpen and not anyInputActive and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow(),  false)
        if navRight or navLeft then
            local goBack = navLeft
            if converterFocusedTable == "input" then
                if numOutLayers > 0 then
                    converterFocusedTable       = "output"
                    converterOutputFocusedLayer = goBack and numOutLayers or 1
                    local sel = converterLayerSelections[converterSelectedOriginal or ""] or {}
                    converterOutputLayerArtIdx = sel[converterOutputFocusedLayer] or 1
                end
            else
                local nextLayer = converterOutputFocusedLayer + (goBack and -1 or 1)
                if nextLayer < 1 or nextLayer > numOutLayers then
                    converterFocusedTable = "input"
                else
                    converterOutputFocusedLayer = nextLayer
                    local sel = converterLayerSelections[converterSelectedOriginal or ""] or {}
                    converterOutputLayerArtIdx = sel[converterOutputFocusedLayer] or 1
                end
            end
        end

        if converterFocusedTable == "input" and #allInputNames > 0 and (arrowUp or arrowDown) then
            -- Seed cursor from primary selection on first press
            if not converterCursorIdx then
                for i, n in ipairs(allInputNames) do
                    if n == converterSelectedOriginal then converterCursorIdx = i; break end
                end
                if not converterCursorIdx then converterCursorIdx = 1 end
            end
            local newIdx = converterCursorIdx + (arrowDown and 1 or -1)
            newIdx = math.max(1, math.min(#allInputNames, newIdx))
            converterCursorIdx        = newIdx
            converterSelectedOriginal = allInputNames[newIdx]
            if navShift then
                local anchor = converterAnchorIdx or newIdx
                local lo = math.min(anchor, newIdx)
                local hi = math.max(anchor, newIdx)
                converterSelectedOriginals = {}
                for i = lo, hi do
                    if allInputNames[i] then converterSelectedOriginals[allInputNames[i]] = true end
                end
            else
                converterSelectedOriginals = {[allInputNames[newIdx]] = true}
                converterAnchorIdx         = newIdx
            end
        end

        if converterFocusedTable == "output" and (arrowUp or arrowDown) then
            local focusedLayer = effLayers[converterOutputFocusedLayer]
            if focusedLayer then
                local maxArtIdx = 0
                for _, art in ipairs(focusedLayer) do
                    if not art.live then maxArtIdx = maxArtIdx + 1 end
                end
                if maxArtIdx > 0 then
                    local newArtIdx = converterOutputLayerArtIdx + (arrowDown and 1 or -1)
                    newArtIdx = math.max(1, math.min(maxArtIdx, newArtIdx))
                    converterOutputLayerArtIdx = newArtIdx
                    local targets = next(converterSelectedOriginals) ~= nil
                        and converterSelectedOriginals
                        or (converterSelectedOriginal and {[converterSelectedOriginal] = true} or {})
                    for name in pairs(targets) do
                        converterLayerSelections[name] = converterLayerSelections[name] or {}
                        converterLayerSelections[name][converterOutputFocusedLayer] = newArtIdx
                        local artName  = buildConvertedNameFromSelections(name)
                        local existing = normMapping(converterMappings[name])
                        existing.articulation = artName
                        converterMappings[name] = existing
                    end
                end
            end
        end

        -- ── Button shortcut keys (I / M / O / S / Delete) ──
        if not popupIsOpen then
            -- Delete / Backspace: remove selected mappings when in show-mappings mode
            if converterFocusedTable == "input" and converterShowMappingsMode and next(converterSelectedOriginals) ~= nil then
                local isDel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(),    false)
                           or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace(), false)
                if isDel then deleteSelectedMappings() end
            end
            -- I: Input button / clear
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_I(), false) then
                if converterManualInputMapName then
                    export.setManualInput(nil)
                elseif converterShowMappingsMode then
                    converterShowMappingsMode = false
                    export.refreshOriginals()
                else
                    openBrowserForConverterMode("input")
                end
            end
            -- M: Toggle "Show matching"
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_M(), false) then
                settings.converter_show_matching = not settings.converter_show_matching
                saveSettings()
            end
            -- O: Output button / clear
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_O(), false) then
                if converterManualOutputMapName then
                    export.setManualOutput(nil)
                elseif converterShowMappingsMode then
                    converterShowMappingsMode = false
                    export.refreshOriginals()
                else
                    openBrowserForConverterMode("output")
                end
            end
            -- S: Show mappings / clear (mirrors the Show button)
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S(), false) then
                if converterShowMappingsMode then
                    converterShowMappingsMode = false
                    export.refreshOriginals()
                elseif converterHasStoredMappings then
                    converterShowMappingsMode = true
                    export.refreshOriginals()
                end
            end
        end

        -- ── Height calculations ──
        local _, totalH  = reaper.ImGui_GetContentRegionAvail(ctx)
        local frameH     = reaper.ImGui_GetFrameHeight(ctx)
        local lineH      = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
        local childBorder = reaper.ImGui_ChildFlags_Borders and reaper.ImGui_ChildFlags_Borders() or 1
        local horizLayout = settings.converter_horizontal_layout

        local footerH, bodyH, pairH, availH, availLabelH
        availLabelH = lineH + 4
        if horizLayout then
            -- Footer is two lines: checkboxes+threshold row, then buttons row
            footerH = frameH * 2 + 14
            bodyH   = math.max(60, totalH - footerH - 8)
            pairH   = bodyH
            availH  = math.max(40, bodyH - availLabelH - 4)
        else
            -- Footer is three lines: checkboxes, threshold, buttons
            footerH = frameH * 3 + 24
            local body2H = math.max(60, totalH - footerH - availLabelH - 10)
            pairH   = math.floor(body2H * 0.5)
            availH  = body2H - pairH
        end

        -- ── Main content area ──
        -- Snapshot focus state before rendering children: clicks inside can change
        -- converterFocusedTable, causing mismatched PushStyleColor/PopStyleColor pairs.
        local inputTableFocused  = converterFocusedTable == "input"
        local outputTableFocused = converterFocusedTable == "output"
        local inputLabel = converterShowMappingsMode and "selected script mappings"
            or (converterManualInputMapName or ("selected " .. focusIsOn))
        local outputLabel = (converterManualOutputMapName and (converterManualOutputMapName) or (fxName and fxName or "No articulation script in focus"))
        if horizLayout then
            -- Side-by-side: pair left, available right
            local layoutFlags = reaper.ImGui_TableFlags_SizingStretchSame()
            if reaper.ImGui_BeginTable(ctx, "##hlayout", 2, layoutFlags) then
                reaper.ImGui_TableNextRow(ctx)

                -- Left column: Original + Converted
                reaper.ImGui_TableSetColumnIndex(ctx, 0)
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "Input:")
                if converterManualInputMapName then
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "x##clearInputH") then
                        export.setManualInput(nil)
                    end
                    setToolTipFunc("Reset to active take input.")
                elseif converterShowMappingsMode then
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "x##clearMappingsH") then
                        converterShowMappingsMode = false
                        export.refreshOriginals()
                    end
                    setToolTipFunc("Reset to active take input.")
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, inputLabel .. "##inputBtnH") then
                    openBrowserForConverterMode("input")
                end
                setToolTipFunc("Click to select an articulation script as input. All its articulations will be listed for conversion. Resets when focus changes.")
                
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Checkbox(ctx, "Show matching##showmatch", settings.converter_show_matching) then
                    settings.converter_show_matching = not settings.converter_show_matching
                    saveSettings()
                end
                setToolTipFunc("Show articulations that are matching articulations in the output script.")
                if inputTableFocused then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFFFFFFFF) end
                if reaper.ImGui_BeginChild(ctx, "##origConv", 0, availH, childBorder) then
                    renderPairTable(ctx, allInputNames)
                    reaper.ImGui_EndChild(ctx)
                end
                if inputTableFocused then reaper.ImGui_PopStyleColor(ctx) end

                -- Right column: Available
                reaper.ImGui_TableSetColumnIndex(ctx, 1)
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, "Output:")
                if converterManualOutputMapName then
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "x##clearOutputH") then
                        export.setManualOutput(nil)
                    end
                    setToolTipFunc("Reset to active script output.")
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, outputLabel .. "##outputBtnH") then
                    openBrowserForConverterMode("output")
                end
                setToolTipFunc("Click to select an articulation script as converter output source.\nThis will be reset if track or take selection changes.")
                reaper.ImGui_SameLine(ctx)
                local showMappingsDisabledH = not converterHasStoredMappings or converterShowMappingsMode
                if showMappingsDisabledH then reaper.ImGui_BeginDisabled(ctx) end
                if reaper.ImGui_Button(ctx, "Show##H") then
                    converterShowMappingsMode = true
                    export.refreshOriginals()
                end
                if showMappingsDisabledH then reaper.ImGui_EndDisabled(ctx) end
                setToolTipFunc(converterShowMappingsMode
                    and "Already showing stored mappings."
                    or (converterHasStoredMappings
                        and "Load all stored mappings for the current script as input for reviewing and editing."
                        or "No mapping made for the selected articulation script."))

                if outputTableFocused then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFFFFFFFF) end
                if reaper.ImGui_BeginChild(ctx, "##avail", 0, availH, childBorder) then
                    renderAvailableList(ctx)
                    reaper.ImGui_EndChild(ctx)
                end
                if outputTableFocused then reaper.ImGui_PopStyleColor(ctx) end

                reaper.ImGui_EndTable(ctx)
            end
        else
            -- Stacked: pair on top, available below
            reaper.ImGui_AlignTextToFramePadding(ctx)
            reaper.ImGui_Text(ctx, "Input:")
            if converterManualInputMapName then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "x##clearInputV") then
                    export.setManualInput(nil)
                end
                setToolTipFunc("Reset to active take input.")
            elseif converterShowMappingsMode then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "x##clearMappingsV") then
                    converterShowMappingsMode = false
                    export.refreshOriginals()
                end
                setToolTipFunc("Reset to active take input.")
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, inputLabel .. "##inputBtnV") then
                openBrowserForConverterMode("input")
            end
            setToolTipFunc("Click to select an articulation script as input. All its articulations will be listed for conversion. Resets when focus changes.")
            
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Checkbox(ctx, "Show matching##showmatch", settings.converter_show_matching) then
                settings.converter_show_matching = not settings.converter_show_matching
                saveSettings()
            end
            setToolTipFunc("Show articulations that are matching articulations from script.")
            if inputTableFocused then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFFFFFFFF) end
            if reaper.ImGui_BeginChild(ctx, "##origConv", 0, pairH, childBorder) then
                renderPairTable(ctx, allInputNames)
                reaper.ImGui_EndChild(ctx)
            end
            if inputTableFocused then reaper.ImGui_PopStyleColor(ctx) end
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, "Output:")
            if converterManualOutputMapName then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "x##clearOutputV") then
                    export.setManualOutput(nil)
                end
                setToolTipFunc("Reset to active script output.")
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, outputLabel .. "##outputBtnV") then
                openBrowserForConverterMode("output")
            end
            setToolTipFunc("Click to select an articulation script as converter output source.\nThis will be reset if track or take selection changes.")
            reaper.ImGui_SameLine(ctx)
            local showMappingsDisabledV = not converterHasStoredMappings or converterShowMappingsMode
            if showMappingsDisabledV then reaper.ImGui_BeginDisabled(ctx) end
            if reaper.ImGui_Button(ctx, "Show##V") then
                converterShowMappingsMode = true
                export.refreshOriginals()
            end
            if showMappingsDisabledV then reaper.ImGui_EndDisabled(ctx) end
            setToolTipFunc(converterShowMappingsMode
                and "Already showing stored mappings."
                or (converterHasStoredMappings
                    and "Load all stored mappings for the current script as input for reviewing and editing."
                    or "No mapping made for the selected articulation script."))

            if outputTableFocused then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFFFFFFFF) end
            if reaper.ImGui_BeginChild(ctx, "##avail", 0, availH, childBorder) then
                renderAvailableList(ctx)
                reaper.ImGui_EndChild(ctx)
            end
            if outputTableFocused then reaper.ImGui_PopStyleColor(ctx) end
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

        -- Match threshold: same row as checkboxes in horizontal mode, new row in vertical
        --if horizLayout then reaper.ImGui_SameLine(ctx) end

        -- Buttons: always on their own row
        --if not horizLayout then reaper.ImGui_Spacing(ctx) end
        --reaper.ImGui_SameLine(ctx)

        local inputIsExternal = converterManualInputTriggerTableLayers ~= nil or converterShowMappingsMode

        if inputIsExternal then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Apply") then
            applyConversionsForCurrentFocus(converterMappings)
            if settings.converter_close_when_applying then close = true end
        end
        if inputIsExternal then reaper.ImGui_EndDisabled(ctx) end
        setToolTipFunc(inputIsExternal
            and "Cannot apply when using a script or stored mappings as input."
            or "Apply conversion to articulations, without storing them.")
        reaper.ImGui_SameLine(ctx)

        local mappingsMatchStored = converterShowMappingsMode and (function()
            for k, v in pairs(converterMappings) do
                local c = converterCachedScriptMappings[k]
                if c then
                    local m1 = normMapping(v)
                    local m2 = normMapping(c)
                    if m1.articulation ~= m2.articulation
                    or (m1.transpose or 0) ~= (m2.transpose or 0)
                    or m1.velocity ~= m2.velocity then
                        return false
                    end
                end
            end
            for k in pairs(converterCachedScriptMappings) do
                if converterMappings[k] == nil then
                    return false
                end
            end
            return true
        end)()
        local canStore = hasOriginals and not mappingsMatchStored
        if not canStore then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Store settings") then
            storeCurrentMappings()
        end
        setToolTipFunc("Store conversion settings for this articulation script.")
        reaper.ImGui_SameLine(ctx)
        if not canStore then reaper.ImGui_EndDisabled(ctx) end

        if inputIsExternal or not hasOriginals then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Store settings and apply") then
            storeCurrentMappings()
            applyConversionsForCurrentFocus(converterMappings)
            if settings.converter_close_when_applying then close = true end
        end
        if inputIsExternal or not hasOriginals then reaper.ImGui_EndDisabled(ctx) end
        setToolTipFunc(inputIsExternal
            and "Cannot apply when using a script or stored mappings as input."
            or "Store conversion settings for this articulation script and apply.")

        if not anyInputActive and not popupIsOpen and not reaper.ImGui_IsAnyItemActive(ctx) and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false) then
            if hasOriginals or inputIsExternal then
                storeCurrentMappings()
            end
            if not inputIsExternal then
                applyConversionsForCurrentFocus(converterMappings)
                if settings.converter_close_when_applying then close = true end
            end
        end

        if not anyInputActive and not open or (not popupIsOpen and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)) then
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
    if close then
        reaper.SetExtState("articulationMapConverter", "browserMode", "", false)
    end
    return close
end

return export
