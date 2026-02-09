-- @noindex

local export = {}

function export.columnsToNotUseLanes()
    return {
        ["Title"] = true,
        ["Group"] = true,
        ["Notation"] = true,
        ["Layer"] = true,
        ["KT"] = true,
    }
end

function export.getNoteNumber(str)
    local n = str:match("^Note(%d+)$")
    if n then
        return tonumber(n)
    else
        return false
    end
end

function export.getCCNumber(str)
    local n = str:match("^CC(%d+)$")
    if n then
        return tonumber(n)
    else
        return false
    end
end

function export.getVisualColumnName(column_name)
    local visualColumnName
    if export.getNoteNumber(column_name) then
        visualColumnName = "Note"
    elseif column_name == "Delay" then
        visualColumnName = "N." .. column_name
    elseif column_name:match("FilterCount") ~= nil then
        visualColumnName = "F.N.Count"
    elseif column_name:match("Filter") ~= nil then
        visualColumnName = column_name:gsub("Filter", "F.")
    else
        visualColumnName = column_name
    end
    return visualColumnName
end

function export.createTableOrderFromUsedMappings(mapping)
    -- WE DO THIS TO FORCE THE ORDER in our table
    local mappingType = {}
    table.insert(mappingType, "Title")

    if mapping.Group then table.insert(mappingType, "Group") end


    if mapping.Notation then table.insert(mappingType, "Notation") end

    local noteMappings = {}
    local CCMappings = {}
    for k, v in pairs(mapping) do
        if v then
            local noteNumber = export.getNoteNumber(k)
            if noteNumber then
                table.insert(noteMappings, noteNumber)
            else
                local ccNumber = export.getCCNumber(k)
                if ccNumber then
                    table.insert(CCMappings, ccNumber)
                end
            end
        end
    end

    table.sort(noteMappings)
    for i, v in ipairs(noteMappings) do
        table.insert(mappingType, "Note" .. v)
    end

    table.sort(CCMappings)
    for i, v in ipairs(CCMappings) do
        table.insert(mappingType, "CC" .. v)
    end
    --[[
    for key, value in pairs(mapping.CC) do
        table.insert(mappingType, "CC" .. key)
    end



    for key, value in pairs(mapping.Note) do
        table.insert(mappingType, "Note" .. key)
        --table.insert(mappingType, "NoteM" .. key.."Velocity")
    end

    ]]

    if mapping.Layer then table.insert(mappingType, "Layer") end
    if mapping.Velocity then table.insert(mappingType, "Velocity") end
    if mapping.Channel then table.insert(mappingType, "Channel") end
    if mapping.Delay then table.insert(mappingType, "Delay") end
    if mapping.Pitch then table.insert(mappingType, "Pitch") end
    if mapping.Transpose then table.insert(mappingType, "Transpose") end
    if mapping.Interval then table.insert(mappingType, "Interval") end

    if mapping.Position then table.insert(mappingType, "Position") end
    if mapping.FilterChannel then table.insert(mappingType, "FilterChannel") end
    if mapping.FilterPitch then table.insert(mappingType, "FilterPitch") end
    if mapping.FilterVelocity then table.insert(mappingType, "FilterVelocity") end
    if mapping.FilterSpeed then table.insert(mappingType, "FilterSpeed") end
    if mapping.FilterInterval then table.insert(mappingType, "FilterInterval") end
    if mapping.FilterCount then table.insert(mappingType, "FilterCount") end

    if mapping.KeyboardTrigger then table.insert(mappingType, "KT") end

    if mapping.UIText then table.insert(mappingType, "UIText") end
    return mappingType
end

function export.getTableSizes(fontSize, tableSizeTitle, tableSizeGroup)
    local tableSizes = {}
    tableSizes.Play = math.ceil(fontSize / 100 * 20)
    tableSizes.Title = math.ceil(fontSize / 100 * tableSizeTitle)
    tableSizes.Group = math.ceil(fontSize / 100 * tableSizeGroup)
    tableSizes.Others = math.ceil(fontSize / 100 * 90)
    tableSizes.CC = reaper.ImGui_CalcTextSize(ctx, "CC127 X", 0, 0)
    tableSizes.KT = reaper.ImGui_CalcTextSize(ctx, "KT X", 0, 0)
    tableSizes.Notation = reaper.ImGui_CalcTextSize(ctx, "Notation     X", 0, 0)
    tableSizes.UIText = reaper.ImGui_CalcTextSize(ctx, "UIText  X", 0, 0)
    tableSizes.Delay = reaper.ImGui_CalcTextSize(ctx, "N.Delay  X", 0, 0)
    tableSizes.Channel = reaper.ImGui_CalcTextSize(ctx, "Channel X", 0, 0)
    tableSizes.Pitch = reaper.ImGui_CalcTextSize(ctx, "Pitch X", 0, 0)
    tableSizes.Layer = reaper.ImGui_CalcTextSize(ctx, "Layer  X", 0, 0)
    tableSizes.Position = reaper.ImGui_CalcTextSize(ctx, "Position   X", 0, 0)
    tableSizes.Transpose = reaper.ImGui_CalcTextSize(ctx, "Traspose   X", 0, 0)
    tableSizes.Interval = reaper.ImGui_CalcTextSize(ctx, "Interval   X", 0, 0)
    tableSizes.FilterChannel = reaper.ImGui_CalcTextSize(ctx, "F.Channel  X", 0, 0)
    tableSizes.FilterPitch = reaper.ImGui_CalcTextSize(ctx, "F.Pitch  X", 0, 0)
    tableSizes.FilterVelocity = reaper.ImGui_CalcTextSize(ctx, "F.Velocity  X", 0, 0)
    tableSizes.FilterSpeed = reaper.ImGui_CalcTextSize(ctx, "F.Speed  X", 0, 0)
    tableSizes.FilterInterval = reaper.ImGui_CalcTextSize(ctx, "F.Interval  X", 0, 0)
    tableSizes.FilterCount = reaper.ImGui_CalcTextSize(ctx, "F.Note Count  X", 0, 0)
    -- added for extra space or something??
    tableSizes.FilterVelocity = tableSizes.FilterVelocity + math.ceil(fontSize / 100 * 10)
    tableSizes.Pitch = tableSizes.FilterVelocity
    tableSizes.FilterPitch = tableSizes.FilterVelocity
    tableSizes.Velocity = tableSizes.FilterVelocity
    tableSizes.Note = reaper.ImGui_CalcTextSize(ctx, "Note (M)     X", 0, 0)

    local tableWidth = 0
    for _, mappingName in ipairs(mappingType) do
        if mappingName == "Title" then
            tableWidth = tableWidth + tableSizes.Title
            --elseif mappingName == "PlayArticulation" then
            --    tableWidth = tableWidth + tableSizes.Group
        elseif mappingName == "Group" then
            tableWidth = tableWidth + tableSizes.Group
        elseif export.getCCNumber(mappingName) then
            tableWidth = tableWidth + tableSizes.CC
        elseif mappingName == "KT" then
            tableWidth = tableWidth + tableSizes.KT
        elseif mappingName == "Notation" then
            tableWidth = tableWidth + tableSizes.Notation
        elseif mappingName == "UIText" then
            tableWidth = tableWidth + tableSizes.UIText
        elseif mappingName == "Delay" then
            tableWidth = tableWidth + tableSizes.Delay
        elseif mappingName == "Pitch" then
            tableWidth = tableWidth + tableSizes.Pitch
        elseif mappingName == "Velocity" then
            tableWidth = tableWidth + tableSizes.Velocity
        elseif mappingName == "Channel" then
            tableWidth = tableWidth + tableSizes.Channel
        elseif mappingName == "Layer" then
            tableWidth = tableWidth + tableSizes.Layer
        elseif mappingName == "Transpose" then
            tableWidth = tableWidth + tableSizes.Transpose
        elseif mappingName == "Interval" then
            tableWidth = tableWidth + tableSizes.Interval
        elseif mappingName == "Position" then
            tableWidth = tableWidth + tableSizes.Position
        elseif mappingName == "FilterChannel" then
            tableWidth = tableWidth + tableSizes.FilterChannel
        elseif mappingName == "FilterPitch" then
            tableWidth = tableWidth + tableSizes.FilterPitch
        elseif mappingName == "FilterVelocity" then
            tableWidth = tableWidth + tableSizes.FilterVelocity
        elseif mappingName == "FilterSpeed" then
            tableWidth = tableWidth + tableSizes.FilterSpeed
        elseif mappingName == "FilterInterval" then
            tableWidth = tableWidth + tableSizes.FilterInterval
        elseif mappingName == "FilterCount" then
            tableWidth = tableWidth + tableSizes.FilterCount
        elseif export.getNoteNumber(mappingName) then
            tableWidth = tableWidth + tableSizes.Note
        else
            tableWidth = tableWidth + tableSizes.Others
        end
    end
    return tableWidth, tableSizes
end

function export.getMainLaneRow(tableInfo, columnName, row)
    if tableInfo[row].isLane and export.columnsToNotUseLanes()[columnName] then
        for r = row, 1, -1 do
            if not tableInfo[r].isLane then
                return r
            end
        end
    end
end

return export
