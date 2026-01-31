-- @version 1.0
-- @noindex

local export = {}
local undo_stack = {}
local redo_stack = {}

local function deep_copy(orig, copies)
    copies = copies or {}
    if type(orig) ~= "table" then
        return orig
    end
    if copies[orig] then
        return copies[orig]
    end

    local copy = {}
    copies[orig] = copy
    for k, v in pairs(orig) do
        copy[deep_copy(k, copies)] = deep_copy(v, copies)
    end
    return setmetatable(copy, getmetatable(orig))
end

function export.commit(current)
    undo_stack[#undo_stack + 1] = deep_copy(current)
    redo_stack = {} -- invalidate redo history
end

function export.undo(current)
    if #undo_stack == 0 then return current end

    redo_stack[#redo_stack + 1] = deep_copy(current)
    local newCurrent = deep_copy(undo_stack[#undo_stack])
    table.remove(undo_stack, #undo_stack)
    return newCurrent
end

function export.redo(current)
    if #redo_stack == 0 then return current end

    undo_stack[#undo_stack + 1] = deep_copy(current)
    local newCurrent = deep_copy(redo_stack[#redo_stack])
    table.remove(redo_stack, #redo_stack)    
    return newCurrent
end

return export, undo_stack, redo_stack
