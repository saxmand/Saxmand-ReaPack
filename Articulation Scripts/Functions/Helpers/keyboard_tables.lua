--@noindex
local export = {}

function export.defaultKeyboardTable_DA()
    local numericKeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "+", "´"}
    local letters1 = {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Å", "¨"}
    local letters2 = {"A", "S", "D", "F", "G", "H", "J", "K", "L", "Æ", "Ø", "'"}
    local letters3 = {"<", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "-"} 
    local keyboardTable = {numericKeys, letters1, letters2, letters3}    
    return keyboardTable
end
function export.defaultKeyboardTable_US()
    local numericKeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="}
    local letters1 = {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "p", "[", "]"}
    local letters2 = {"A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", [[\]]}
    local letters3 = {"`", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"} 
    local keyboardTable = {numericKeys, letters1, letters2, letters3}    
    return keyboardTable
end
function export.defaultKeyboardTable_AZERTY()
    local numericKeys = {"&", "é", '"', "'", "(", "§", "è", "!", "ç", "à", ")", "-"}
    local letters1 = {"a", "z", "e", "r", "t", "y", "u", "i", "o", "p", "^", "$"}
    local letters2 = {"q", "s", "d", "f", "g", "h", "j", "k", "l", "m", "ù", "`"}
    local letters3 = {"<", "w", "x", "c", "v", "b", "n", ",", ";", ":", "="} 
    local keyboardTable = {numericKeys, letters1, letters2, letters3}    
    return keyboardTable
end

function export.resetKeyboard(country)
    local keyboardTable = export["defaultKeyboardTable_" .. country]()
    for y, table in ipairs(keyboardTable) do
        for x, value in ipairs(table) do
            reaper.SetExtState(contextName, "keyboardTable:" .. y .. ":" .. x, value:upper(), true)            
        end
    end
end

local contextName = "Articulation_Scripts"

function export.getKeyboardTables()
    -- Define the arrays for the keys
    local keyboardTable = export.defaultKeyboardTable_US()
    local keyboardTableKeys = {}
    local keyboardTableKeysOrder = {}
    local keyboardTableXY = {}
    local counter = 1

    for y, table in ipairs(keyboardTable) do
        for x, value in ipairs(table) do
            if reaper.HasExtState(contextName, "keyboardTable:" .. y .. ":" .. x) then
                keyboardTable[y][x] = reaper.GetExtState(contextName, "keyboardTable:" .. y .. ":" .. x)
            end
        end
    end

    for y, table in ipairs(keyboardTable) do
        for x, value in ipairs(table) do            
            keyboardTableXY[value] = {x = x, y = y}    
            keyboardTableKeys[value] = counter
            keyboardTableKeysOrder[counter] = value
            counter = counter + 1
        end
    end

    return {table = keyboardTable, keys = keyboardTableKeys, keysOrder = keyboardTableKeysOrder, xy = keyboardTableXY}
end

return export