-- @noindex

local export = {}

function export.createMidiNotesMap()
    local midiNotesMap = {}
    local noteNamesSharp = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
    local noteNamesFlat = { 'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B' }

    local noteIndex = 0

    for i = -2, 9 do -- MIDI note range spans from C-1 to G9
        for j = 1, #noteNamesSharp do
            local noteSharp = noteNamesSharp[j] .. i
            local noteFlat = noteNamesFlat[j] .. i

            if noteIndex <= 127 then
                midiNotesMap[noteSharp] = noteIndex
                midiNotesMap[noteFlat] = noteIndex
                noteIndex = noteIndex + 1
            end
        end
    end

    return midiNotesMap
end

function export.createAllMidiNotesArray()
    local notes = {}
    local noteNames = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
    for i = 0, 11 do
        for _, noteName in ipairs(noteNames) do
            table.insert(notes, noteName .. (i - 2))
        end
    end
    local limitedNotes = {}
    for i = 1, 128 do limitedNotes[i - 1] = notes[i] end
    return limitedNotes
end


function export.createAllWhiteMidiNotesArray()
    local notes = {}
    local noteNames = { 'C', '-', 'D', '-', 'E', 'F', '-', 'G', '-', 'A', '-', 'B' }
    for i = 0, 11 do
        for _, noteName in ipairs(noteNames) do
            if noteName == '-' then
                table.insert(notes, false)
            else
                table.insert(notes, noteName .. (i - 2))
            end
        end
    end
    local limitedNotes = {}
    for i = 1, 128 do limitedNotes[i - 1] = notes[i] end
    return limitedNotes
end


return export