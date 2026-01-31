local export = {}

function export.getKeyboardTables()
    -- Define the arrays for the keys
    local numericKeys = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "+", "´"    }
    local letters1 = {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Å", "¨"}
    local letters2 = {"A", "S", "D", "F", "G", "H", "J", "K", "L", "Æ", "Æ", "'"}
    local letters3 = {"<", "Z", "X", "C", "V", "B", "N", "M", ",", "."} -- Omitted "<"
    local keyboardTable = {numericKeys, letters1, letters2, letters3}    
    local keyboardTableKeys = {}
    local keyboardTableKeysOrder = {}
    local keyboardTableXY = {}
    local counter = 1
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