--@noindex
local export = {}



function export.deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for key, value in next, orig, nil do
            copy[deep_copy(key)] = deep_copy(value)
        end
        setmetatable(copy, deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function export.save_undo(data)
    table.insert(undo_stack, deep_copy(data))
    redo_stack = {} -- clear redo stack on new change
end

function export.undo(data)
    if #undo_stack > 0 then
        table.insert(redo_stack, deep_copy(data))
        local prev = table.remove(undo_stack)
        return deep_copy(prev)
    end
    return data -- no change
end

function export.redo(data)
    if #redo_stack > 0 then
        table.insert(undo_stack, deep_copy(data))
        local next_state = table.remove(redo_stack)
        return deep_copy(next_state)
    end
    return data
end

return export