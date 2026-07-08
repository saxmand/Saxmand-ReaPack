-- @noindex

-- Live articulation switching: broadcasts the currently selected articulation of every
-- layer as Bank Select (CC0) + Program Change on one MIDI channel per layer (channel =
-- layer number), so a normal MIDI recording (or "Insert recent retroactive recorded midi")
-- captures which articulation was active. That data can then be converted back into the
-- same per-note articulation notation events change_articulation.lua writes.
--
-- Encoding: within a layer, articulation index N (0-based, position in triggerTableLayers)
-- is sent as CC0 = floor(N / 128), Program Change = N % 128, on MIDI channel = layer number
-- (1-16). This gives up to 16 layers of up to 128 x 128 articulations each.
--
-- When a layer actually changes, the layer it changed FROM is re-sent first (with a one
-- defer-tick gap so it lands at an earlier, distinct ppq position), followed by the layer it
-- changed TO. This lets the read-back side recover the articulation that was active before
-- the first captured change in a take, even though that earlier state was never announced
-- when it actually began (it may have been selected long before recording/buffering started).

local export = {}

-- (1) Build a lookup table of {channel, bank, program} for every articulation in every layer
-- of the currently read articulation script (triggerTableLayers, as returned by
-- readArticulationScript).
function export.buildArticulationMidiMap(triggerTableLayers)
    local byLayer = {}
    local byArticulation = {}

    for layer, artList in pairs(triggerTableLayers) do
        local indexed = {}
        for i, art in ipairs(artList) do
            local artIndex = i - 1
            local entry = {
                channel = layer,
                bank = math.floor(artIndex / 128),
                program = artIndex % 128,
                layer = layer,
                artIndex = artIndex,
                articulation = art.articulation,
            }
            indexed[artIndex] = entry
            byArticulation[art.articulation] = entry
        end
        byLayer[layer] = indexed
    end

    return { byLayer = byLayer, byArticulation = byArticulation }
end

local function sendPair(mode, channel, bank, program)
    local channelOffset = channel - 1
    reaper.StuffMIDIMessage(mode, 0xB0 + channelOffset, 0, bank)
    reaper.StuffMIDIMessage(mode, 0xC0 + channelOffset, program, 0)
end

-- (2) Send CC0 + Program Change for the currently selected articulation of every layer.
-- All layers are re-sent every time (not just the layer that changed), so the recording
-- always captures the full cross-layer state at the moment of any single change.
--
-- If changedLayer/fromIdx are given, that layer is sent as a from/to pair: the articulation
-- it changed FROM goes out now, and the one it changed TO goes out a defer-tick later, so a
-- recording captures both at distinct ppq positions.
function export.sendArticulationProgramChanges(track, artSliders, midiMap, changedLayer, fromIdx, mode)
    if not track or not artSliders or not midiMap then return end
    mode = mode or 0

    for _, slider in ipairs(artSliders) do
        local layerMap = midiMap.byLayer[slider.layer]
        if layerMap then
            local selectedIdx = math.floor(reaper.TrackFX_GetParam(track, slider.fxNumber, slider.param))
            local toEntry = layerMap[selectedIdx]
            if toEntry and toEntry.channel <= 16 then
                local fromEntry = slider.layer == changedLayer and fromIdx and fromIdx ~= selectedIdx
                    and layerMap[fromIdx]
                if fromEntry then
                    sendPair(mode, fromEntry.channel, fromEntry.bank, fromEntry.program)
                    reaper.defer(function()
                        sendPair(mode, toEntry.channel, toEntry.bank, toEntry.program)
                    end)
                else
                    sendPair(mode, toEntry.channel, toEntry.bank, toEntry.program)
                end
            end
        end
    end
end

-- returns the last item in a list sorted ascending by ppqpos whose ppqpos <= ppqpos
local function findLatestAtOrBefore(sortedList, ppqpos)
    local found
    for _, item in ipairs(sortedList) do
        if item.ppqpos <= ppqpos then
            found = item
        else
            break
        end
    end
    return found
end

-- (3) Read Bank Select (CC0) / Program Change events out of a MIDI take, convert the ones
-- that match the take's track articulation script into per-note articulation notation events
-- (the same "NOTE ch pitch text "name"" events change_articulation.lua writes), applied to
-- every note that follows until the next matching change. The consumed CC0/Program Change
-- events are then removed from the take.
function export.convertProgramChangesToArticulations(take)
    if not take or not reaper.TakeIsMIDI(take) then return end

    local track = reaper.GetMediaItemTake_Track(take)
    if not track then return end

    local _, triggerTableLayers, _, artSliders = readArticulationScript(track)
    if not triggerTableLayers or not next(triggerTableLayers) then return end

    local midiMap = export.buildArticulationMidiMap(triggerTableLayers)

    -- Collect Bank Select (CC0) and Program Change events, grouped by MIDI channel (=layer).
    local banksByChannel = {}
    local programsByChannel = {}

    local _, noteCount, ccCount = reaper.MIDI_CountEvts(take)
    for i = 0, ccCount - 1 do
        local retval, _, _, ppqpos, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, i)
        if retval then
            local channel = chan + 1
            if chanmsg == 0xB0 and msg2 == 0 then
                banksByChannel[channel] = banksByChannel[channel] or {}
                table.insert(banksByChannel[channel], { ppqpos = ppqpos, value = msg3, idx = i })
            elseif chanmsg == 0xC0 then
                programsByChannel[channel] = programsByChannel[channel] or {}
                table.insert(programsByChannel[channel], { ppqpos = ppqpos, value = msg2, idx = i })
            end
        end
    end

    -- For each layer, turn its bank/program events into a sorted list of articulation changes,
    -- keeping track of which CC events were actually matched against the script.
    local changesByLayer = {}
    local ccIndicesToDelete = {}

    for layer in pairs(triggerTableLayers) do
        local programs = programsByChannel[layer]
        if programs then
            local banks = banksByChannel[layer] or {}
            table.sort(programs, function(a, b) return a.ppqpos < b.ppqpos end)
            table.sort(banks, function(a, b) return a.ppqpos < b.ppqpos end)

            local changes = {}
            for _, prg in ipairs(programs) do
                local bank = findLatestAtOrBefore(banks, prg.ppqpos)
                local artIndex = (bank and bank.value or 0) * 128 + prg.value
                local entry = midiMap.byLayer[layer] and midiMap.byLayer[layer][artIndex]
                if entry then
                    table.insert(changes, { ppqpos = prg.ppqpos, articulation = entry.articulation })
                    ccIndicesToDelete[prg.idx] = true
                    if bank then ccIndicesToDelete[bank.idx] = true end
                end
            end

            if #changes > 0 then
                changesByLayer[layer] = changes
            end
        end
    end

    if not next(changesByLayer) then return end

    -- Fallback for a layer with NO captured change anywhere in the take: use the FX's current
    -- slider selection, same as change_articulation.lua does for notes with no text yet.
    local function fallbackArticulation(layer)
        for _, slider in ipairs(artSliders) do
            if slider.layer == layer then
                local idx = math.floor(reaper.TrackFX_GetParam(track, slider.fxNumber, slider.param))
                local artList = triggerTableLayers[layer]
                return artList and artList[idx + 1] and artList[idx + 1].articulation
            end
        end
    end

    local layerNumbers = {}
    for layer, layerArts in pairs(triggerTableLayers) do
        if layerArts[1] and not layerArts[1].live then
            table.insert(layerNumbers, layer)
        end
    end
    table.sort(layerNumbers)

    for n = 0, noteCount - 1 do
        local retval, selected, muted, notePpqpos, _, noteChannel, notePitch = reaper.MIDI_GetNote(take, n)
        if retval then
            local arts = {}
            for _, layer in ipairs(layerNumbers) do
                local changes = changesByLayer[layer]
                local articulation
                if changes then
                    -- note is before the earliest captured change for this layer: look
                    -- backwards and use that earliest entry rather than the live FX state,
                    -- since it may have been selected long before this take started.
                    local active = findLatestAtOrBefore(changes, notePpqpos)
                    articulation = (active or changes[1]).articulation
                else
                    articulation = fallbackArticulation(layer)
                end
                table.insert(arts, articulation or "")
            end
            local newName = table.concat(arts, " / ")
            if newName ~= "" then
                local text = "NOTE " .. noteChannel .. " " .. notePitch .. " text " .. '"' .. newName .. '"'
                reaper.MIDI_InsertTextSysexEvt(take, selected, muted, notePpqpos, 15, text, true)
            end
        end
    end

    reaper.MIDI_Sort(take)

    -- delete highest index first so earlier indices stay valid
    local idxs = {}
    for idx in pairs(ccIndicesToDelete) do table.insert(idxs, idx) end
    table.sort(idxs, function(a, b) return a > b end)
    for _, idx in ipairs(idxs) do
        reaper.MIDI_DeleteCC(take, idx)
    end
end

return export
