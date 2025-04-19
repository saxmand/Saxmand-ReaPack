-- @description FX Modulator Linking
-- @author saxmand
-- @version 0.1.0
-- @provides
--   [nomain] Helpers/*.lua
--   [effect] FX Modulator Linking/*.jsfx


package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'
local stateName = "ModulationLinking"
local ctx = ImGui.CreateContext('Modulation Linking')
font = reaper.ImGui_CreateFont('Arial', 14)
font1 = reaper.ImGui_CreateFont('Arial', 15)
font2 = reaper.ImGui_CreateFont('Arial', 17)
-- imgui_font
reaper.ImGui_Attach(ctx, font)
reaper.ImGui_Attach(ctx, font1)
reaper.ImGui_Attach(ctx, font2)
reaper.ImGui_SetConfigVar(ctx,reaper.ImGui_ConfigVar_MacOSXBehaviors(),0)


function reaper_do_file(file) local info = debug.getinfo(1,'S'); local path = info.source:match[[^@?(.*[\/])[^\/]-$]]; dofile(path .. file); end
reaper_do_file('Helpers/json.lua')
-----------------------------------------
------------ TOOLBAR SETTINGS -----------
-----------------------------------------
local _,_,_,cmdID = reaper.get_action_context()
-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end

-----------------
---- HELPERS ----
-----------------

function splitString(inputstr)
    local t = {}
    for str in string.gmatch(inputstr, "([^, ]+)") do
        table.insert(t, str)
    end
    return t
end

function searchName(name, search)
    name = name:lower()
    search_parts = splitString(search)

    for _, part in ipairs(search_parts) do
        if not string.find(name, part:lower()) then
            return false
        end
    end
    return true
end


--------------------------------------------------------------------------------
-- Pickle table serialization - Steve Dekorte, http://www.dekorte.com, Apr 2000
--------------------------------------------------------------------------------
function pickle(t) return Pickle:clone():pickle_(t) end
--------------------------------------------------------------------------------
Pickle = {
    clone = function(t)
        local nt = {}
        for i, v in pairs(t) do nt[i] = v end
        return nt
    end
}
--------------------------------------------------------------------------------
function Pickle:pickle_(root)
    if type(root) ~= "table" then
        error("can only pickle tables, not " .. type(root) .. "s")
    end
    self._tableToRef = {}
    self._refToTable = {}
    local savecount = 0
    self:ref_(root)
    local s = ""
    while #self._refToTable > savecount do
        savecount = savecount + 1
        local t = self._refToTable[savecount]
        s = s .. "{\n"
        for i, v in pairs(t) do
            s = string.format("%s[%s]=%s,\n", s, self:value_(i), self:value_(v))
        end
        s = s .. "},\n"
    end
    return string.format("{%s}", s)
end
--------------------------------------------------------------------------------
function Pickle:value_(v)
    local vtype = type(v)
    if vtype == "string" then
        return string.format("%q", v)
    elseif vtype == "number" then
        return v
    elseif vtype == "boolean" then
        return tostring(v)
    elseif vtype == "table" then
        return "{" .. self:ref_(v) .. "}"
    else
        error("pickle a " .. type(v) .. " is not supported")
    end
end
--------------------------------------------------------------------------------
function Pickle:ref_(t)
    local ref = self._tableToRef[t]
    if not ref then
        if t == self then error("can't pickle the pickle class") end
        table.insert(self._refToTable, t)
        ref = #self._refToTable
        self._tableToRef[t] = ref
    end
    return ref
end
--------------------------------------------------------------------------------
-- unpickle
--------------------------------------------------------------------------------
function unpickle(s)
    if type(s) ~= "string" then
        error("can't unpickle a " .. type(s) .. ", only strings")
    end
    local gentables = load("return " .. s)
    local tables = gentables()
    for tnum = 1, #tables do
        local t = tables[tnum]
        local tcopy = {}
        for i, v in pairs(t) do tcopy[i] = v end
        for i, v in pairs(tcopy) do
            local ni, nv
            if type(i) == "table" then
                ni = tables[i[1]]
            else
                ni = i
            end
            if type(v) == "table" then
                nv = tables[v[1]]
            else
                nv = v
            end
            t[i] = nil
            t[ni] = nv
        end
    end
    return tables[1]
end

--------------------------------------------------------------------------
------------------------------ VERTICAL TEXT -----------------------------
--------------------------------------------------------------------------


-- Define vector shapes for the full alphabet (A-Z)
local char_shapes = {
    A = {{0.0, 1.0, 0.4, 0.0}, {0.85, 1.0}, {0.15, 0.6, 0.7, 0.6}}, -- "A"
    B = {{0.0, 1.0, 0.0, 0.0}, {0.4, 0.0}, {0.60, 0.1}, {0.65, 0.3}, {0.5, 0.45}, {0.7, 0.65}, {0.7, 0.8}, {0.65, 0.9}, {0.45, 1.0}, {0.0, 1.0}, {0.0, 0.45, 0.5, 0.45}}, -- "B"
    C = {{0.8, 0.65, 0.7, 0.85}, {0.5, 1.0}, {0.35, 1.0}, {0.2, 0.95}, {0.05, 0.75}, {0.0, 0.55}, {0.0, 0.4}, {0.1, 0.15}, {0.3, 0.0}, {0.5, 0.0}, {0.65, 0.05}, {0.8, 0.25}}, -- "C"
    D = {{0.0, 1.0, 0.0, 0.0}, {0.4, 0.0}, {0.65, 0.1}, {0.75, 0.35}, {0.75, 0.6}, {0.7, 0.8}, {0.4, 1.0}, {0.0, 1.0}}, -- "D"
    E = {{0.7, 1.0, 0.0, 1.0}, {0.0, 0.0}, {0.65, 0.0}, {0.0, 0.5, 0.6, 0.5}}, -- "E"
    F = {{0.0, 1.05, 0.0, 0.05}, {0.65, 0.05}, {0.0, 0.5, 0.55, 0.5}}, -- "F"
    G = {{0.5, 0.5, 0.85, 0.5}, {0.85, 0.8}, {0.55, 1.0}, {0.3, 1.0}, {0.1, 0.85}, {0.0, 0.6}, {0.0, 0.4}, {0.1, 0.15}, {0.35, 0.0}, {0.55, 0.0}, {0.75, 0.1}, {0.85, 0.25}}, -- "G"
    H = {{0.0, 1.0, 0.0, 0.0}, {0.0, 0.5, 0.7, 0.5}, {0.7, 0.0, 0.7, 1.0}}, -- "H"
    I = {{0, 0, 0, 1}}, -- "I"
    J = {{0.0, 0.7, 0.1, 0.9}, {0.25, 1.0}, {0.4, 0.9}, {0.5, 0.75}, {0.5, 0.0}}, -- "J"
    K = {{0.0, 0.0, 0.0, 1.0}, {0.0, 0.6, 0.6, 0.0}, {0.25, 0.35}, {0.7, 1.0}}, -- "K"
    L = {{0.55, 1.0, 0.0, 1.0}, {0.0, 0.0}}, -- "L"
    M = {{0.0, 1.0, 0.0, 0.0}, {0.1, 0.0}, {0.45, 0.9}, {0.8, 0.0}, {0.9, 0.0}, {0.9, 1.0}}, -- "M"
    N = {{0.0, 1.0, 0.0, 0.0}, {0.7, 1.0}, {0.7, 0.0}}, -- "N"
    O = {{0.35, 1.0, 0.15, 0.9}, {0.0, 0.6}, {0.0, 0.4}, {0.1, 0.2}, {0.35, 0.05}, {0.55, 0.05}, {0.8, 0.2}, {0.9, 0.4}, {0.9, 0.6}, {0.8, 0.8}, {0.6, 1.0}, {0.35, 1.0}}, -- "O"
    P = {{0.0, 1.0, 0.0, 0.0}, {0.45, 0.0}, {0.65, 0.1}, {0.7, 0.25}, {0.7, 0.35}, {0.6, 0.5}, {0.45, 0.55}, {0.0, 0.55}}, -- "P"
    Q = {{0.35, 1.0, 0.1, 0.85}, {0.0, 0.6}, {0.0, 0.4}, {0.1, 0.15}, {0.35, 0.0}, {0.55, 0.0}, {0.8, 0.15}, {0.9, 0.4}, {0.9, 0.6}, {0.8, 0.8}, {0.55, 1.0}, {0.35, 1.0}, {0.45, 0.75, 0.65, 0.8}, {0.75, 0.9}, {0.9, 1.0}}, -- "Q"
    R = {{0.0, 1.0, 0.0, 0.0}, {0.5, 0.0}, {0.7, 0.15}, {0.7, 0.35}, {0.6, 0.45}, {0.4, 0.5}, {0.6, 0.65}, {0.8, 1.0}, {0.0, 0.5, 0.4, 0.5}}, -- "R"
    S = {{0.0, 0.65, 0.1, 0.85}, {0.3, 1.0}, {0.45, 1.0}, {0.65, 0.85}, {0.7, 0.7}, {0.65, 0.55}, {0.45, 0.45}, {0.2, 0.4}, {0.05, 0.3}, {0.05, 0.15}, {0.25, 0.0}, {0.45, 0.0}, {0.6, 0.1}, {0.65, 0.25}}, -- "S"
    T = {{0.0, 0.0, 0.7, 0.0}, {0.35, 0.0, 0.35, 1.0}}, -- "T"
    U = {{0.0, 0.0, 0.0, 0.65}, {0.1, 0.85}, {0.3, 1.0}, {0.45, 1.0}, {0.65, 0.85}, {0.75, 0.65}, {0.75, 0.0}}, -- "U"
    V = {{0.0, 0.0, 0.4, 1.0}, {0.8, 0.0}}, -- "V"
    W = {{0.0, 0.0, 0.3, 1.0}, {0.6, 0.0}, {0.9, 1.0}, {1.2, 0.0}}, -- "W"
    X = {{0.0, 1.0, 0.8, 0.0}, {0.05, 0.0, 0.85, 1.0}}, -- "X"
    Y = {{0.0, 0.0, 0.4, 0.55}, {0.8, 0.0}, {0.4, 0.55, 0.4, 1.0}}, -- "Y"
    Z = {{0.1, 0.0, 0.7, 0.0}, {0.0, 1.0}, {0.7, 1.0}}, -- "Z"
    
    -- Lowercase letters
    ["a"] = {{0.05, 0.45, 0.2, 0.3}, {0.4, 0.3}, {0.55, 0.45}, {0.55, 0.8}, {0.6, 1.0}, {0.55, 0.75, 0.4, 0.9}, {0.2, 1.0}, {0.05, 0.9}, {0.0, 0.75}, {0.15, 0.6}, {0.35, 0.6}, {0.55, 0.5}}, -- "a"
    ["b"] = {{0.0, 1.0, 0.0, 0.0}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.35}, {0.55, 0.55}, {0.55, 0.7}, {0.45, 0.85}, {0.3, 1.0}, {0.15, 0.9}, {0.0, 0.7}}, -- "b"
    ["c"] = {{0.55, 0.45, 0.4, 0.3}, {0.2, 0.3}, {0.05, 0.45}, {0.0, 0.6}, {0.0, 0.7}, {0.05, 0.85}, {0.2, 1.0}, {0.40, 1.0}, {0.5, 0.85}, {0.55, 0.75}}, -- "c"
    ["d"] = {{0.55, 0.55, 0.4, 0.35}, {0.25, 0.3}, {0.1, 0.35}, {0.0, 0.55}, {0.0, 0.7}, {0.1, 0.9}, {0.25, 1.0}, {0.4, 0.9}, {0.55, 0.7}, {0.55, 1.0, 0.55, 0.0}}, -- "d"
    ["e"] = {{0.0, 0.6, 0.6, 0.6}, {0.55, 0.45}, {0.45, 0.35}, {0.3, 0.3}, {0.15, 0.35}, {0.05, 0.45}, {0.0, 0.6}, {0.05, 0.8}, {0.15, 0.9}, {0.3, 1.0}, {0.5, 0.9}, {0.6, 0.75}}, -- "e"
    ["f"] = {{0.0, 0.35, 0.4, 0.35}, {0.20, 1.05, 0.20, 0.15}, {0.25, 0.0}, {0.45, 0.05}}, -- "f"
    ["g"] = {{0.55, 0.55, 0.45, 0.35}, {0.3, 0.3}, {0.15, 0.35}, {0.05, 0.5}, {0.0, 0.65}, {0.05, 0.8}, {0.15, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.55, 0.75}, {0.55, 0.3, 0.55, 1.1}, {0.45, 1.25}, {0.3, 1.3}, {0.15, 1.25}, {0.05, 1.1}}, -- "g"
    ["h"] = {{0.0, 0.0, 0.0, 1.0}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.35}, {0.55, 0.55}, {0.55, 1.0}}, -- "h"
    ["i"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.15, 0.0, 0.05}}, -- "i"
    ["j"] = {{0.15, 0.05, 0.15, 0.15}, {0.15, 0.3, 0.15, 1.15}, {0.1, 1.25}, {0.0, 1.3}}, -- "j"
    ["k"] = {{0.0, 1.0, 0.0, 0.0}, {0.0, 0.7, 0.45, 0.3}, {0.2, 0.55, 0.5, 1.0}}, -- "k"
    ["l"] = {{0.0, 1.0, 0.0, 0.0}}, -- "l"
    ["m"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.4}, {0.45, 1.0}, {0.45, 0.45, 0.65, 0.3}, {0.85, 0.40}, {0.9, 0.55}, {0.9, 1.0}}, -- "m"
    ["n"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.40, 0.35}, {0.5, 0.5}, {0.5, 1.0}}, -- "n"
    ["o"] = {{0.0, 0.55, 0.1, 0.4}, {0.25, 0.3}, {0.4, 0.3}, {0.55, 0.4}, {0.6, 0.55}, {0.6, 0.7}, {0.55, 0.85}, {0.4, 1.0}, {0.25, 1.0}, {0.1, 0.9}, {0.0, 0.7}, {0.0, 0.55}}, -- "o"
    ["p"] = {{0.0, 1.25, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.3, 0.3}, {0.45, 0.35}, {0.55, 0.5}, {0.55, 0.7}, {0.5, 0.9}, {0.35, 1.0}, {0.2, 0.95}, {0.1, 0.85}, {0.0, 0.7}}, -- "p"
    ["q"] = {{0.55, 0.3, 0.55, 1.25}, {0.55, 0.7, 0.45, 0.9}, {0.35, 1.0}, {0.2, 1.0}, {0.05, 0.85}, {0.0, 0.7}, {0.0, 0.55}, {0.05, 0.4}, {0.2, 0.3}, {0.35, 0.3}, {0.5, 0.4}, {0.55, 0.55}}, -- "q"
    ["r"] = {{0.0, 1.0, 0.0, 0.3}, {0.0, 0.55, 0.15, 0.35}, {0.25, 0.3}, {0.35, 0.4}}, -- "r"
    ["s"] = {{0.0, 0.75, 0.1, 0.9}, {0.25, 1.0}, {0.45, 0.9}, {0.55, 0.8}, {0.45, 0.65}, {0.1, 0.55}, {0.0, 0.45}, {0.1, 0.35}, {0.25, 0.3}, {0.45, 0.35}, {0.5, 0.45}}, -- "s"
    ["t"] = {{0.0, 0.3, 0.3, 0.3}, {0.15, 0.05, 0.15, 0.85}, {0.2, 1.0}, {0.35, 0.9}}, -- "t"
    ["u"] = {{0.0, 0.3, 0.0, 0.8}, {0.1, 0.9}, {0.25, 1.0}, {0.4, 0.9}, {0.5, 0.75}, {0.5, 0.3, 0.5, 1.0}}, -- "u"
    ["v"] = {{0.0, 0.3, 0.3, 1.0}, {0.6, 0.3}}, -- "v"
    ["w"] = {{0.0, 0.3, 0.25, 1.0}, {0.45, 0.3}, {0.65, 1.0}, {0.9, 0.3}}, -- "w"
    ["x"] = {{0.0, 0.3, 0.6, 1.0}, {0.0, 1.0, 0.6, 0.3}}, -- "x"
    ["y"] = {{0.0, 0.3, 0.3, 1.05}, {0.55, 0.3, 0.3, 1.05}, {0.2, 1.25}, {0.05, 1.2}}, -- "y"
    ["z"] = {{0.0, 0.3, 0.55, 0.3}, {0.0, 1.0}, {0.6, 1.0}}, -- "z"



    -- Numbers
    ["0"] = {{0.0, 0.35, 0.0, 0.65}, {0.1, 0.85}, {0.25, 1.0}, {0.4, 1.0}, {0.5, 0.85}, {0.6, 0.65}, {0.6, 0.35}, {0.5, 0.15}, {0.35, 0.05}, {0.25, 0.05}, {0.1, 0.15}, {0.0, 0.35}}, -- "0"
    ["1"] = {{0.0, 0.3, 0.15, 0.2}, {0.3, 0.05}, {0.3, 1.05}}, -- "1"
    ["2"] = {{0.05, 0.3, 0.15, 0.1}, {0.3, 0.05}, {0.5, 0.15}, {0.55, 0.35}, {0.15, 0.75}, {0.0, 1.0}, {0.6, 1.0}}, -- "2"
    ["3"] = {{0.0, 0.7, 0.1, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.55, 0.75}, {0.55, 0.6}, {0.4, 0.45}, {0.25, 0.45}, {0.4, 0.4}, {0.5, 0.25}, {0.45, 0.1}, {0.3, 0.05}, {0.15, 0.05}, {0.05, 0.15}, {0.0, 0.25}}, -- "3"
    ["4"] = {{0.6, 0.7, 0.0, 0.7}, {0.45, 0.05}, {0.45, 1.0}}, -- "4"
    ["5"] = {{0.0, 0.75, 0.15, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.6, 0.7}, {0.6, 0.55}, {0.45, 0.4}, {0.3, 0.35}, {0.05, 0.5}, {0.15, 0.05}, {0.55, 0.05}}, -- "5"
    ["6"] = {{0.0, 0.6, 0.15, 0.45}, {0.3, 0.35}, {0.45, 0.4}, {0.55, 0.6}, {0.5, 0.8}, {0.35, 1.0}, {0.15, 0.9}, {0.05, 0.8}, {0.0, 0.55}, {0.05, 0.25}, {0.15, 0.1}, {0.3, 0.05}, {0.5, 0.1}, {0.55, 0.25}}, -- "6"
    ["7"] = {{0.0, 0.05, 0.6, 0.05}, {0.3, 0.4}, {0.2, 0.7}, {0.2, 1.0}}, -- "7"
    ["8"] = {{0.25, 0.05, 0.35, 0.05}, {0.5, 0.15}, {0.55, 0.3}, {0.45, 0.4}, {0.25, 0.45}, {0.05, 0.55}, {0.0, 0.7}, {0.1, 0.9}, {0.25, 1.0}, {0.4, 1.0}, {0.55, 0.9}, {0.6, 0.7}, {0.55, 0.55}, {0.35, 0.45}, {0.15, 0.4}, {0.05, 0.3}, {0.1, 0.15}, {0.25, 0.05}}, -- "8"
    ["9"] = {{0.05, 0.75, 0.15, 0.9}, {0.3, 1.0}, {0.45, 0.9}, {0.55, 0.75}, {0.6, 0.45}, {0.55, 0.2}, {0.4, 0.05}, {0.2, 0.05}, {0.05, 0.2}, {0.0, 0.35}, {0.1, 0.55}, {0.25, 0.6}, {0.45, 0.55}, {0.58, 0.4}}, -- "9"

    -- Symbols
    ["'"] = {{0.0, 0.0, 0.0, 0.3}, {0.25, 0.0, 0.25, 0.3}}, -- Single quote
    ['"'] = {{0.3, 0, 0.3, 0.5}, {0.7, 0, 0.7, 0.5}}, -- Double quote
    [","] = {{0.05, 1.0, 0.0, 1.0}, {0.0, 0.9}, {0.05, 0.9}, {0.05, 1.1}, {0.0, 1.2}}, -- Comma
    ["."] = {{0.05, 1.0, 0.0, 1.0}, {0.0, 0.9}, {0.05, 0.9}, {0.05, 1.0}}, -- Period
    [";"] = {{0.05, 1.0, 0.0, 1.0}, {0.0, 0.9}, {0.05, 0.9}, {0.05, 1.1}, {0.0, 1.2}, {0.0, 0.35, 0.05, 0.35}, {0.05, 0.4}, {0.0, 0.4}, {0.0, 0.35}}, -- Semicolon
    [":"] = {{0.0, 0.9, 0.05, 0.9}, {0.05, 1.0}, {0.0, 1.0}, {0.0, 0.9}, {0.0, 0.35, 0.05, 0.35}, {0.05, 0.4}, {0.0, 0.4}, {0.0, 0.35}}, -- Colon
    ["("] = {{0.25, 0.0, 0.1, 0.25}, {0.0, 0.5}, {0.0, 0.75}, {0.1, 1.05}, {0.25, 1.25}}, -- Left parenthesis
    [")"] = {{0.0, 1.25, 0.15, 1.05}, {0.25, 0.75}, {0.25, 0.5}, {0.15, 0.25}, {0.0, 0.0}}, -- Right parenthesis
    ["/"] = {{0.0, 1.0, 0.3, 0.0}}, -- Forward slash
    ["\\"] = {{0.0, 0.0, 0.3, 1.0}}, -- Backslash
    ["?"] = {{0.0, 0.25, 0.15, 0.05}, {0.3, 0.0}, {0.5, 0.1}, {0.55, 0.3}, {0.4, 0.45}, {0.3, 0.6}, {0.3, 0.7}, {0.3, 0.9, 0.3, 1.0}}, -- Question mark
    ["!"] = {{0.1, 1.0, 0.1, 0.9}, {0.1, 0.7, 0.1, 0.0}}, -- Exclamation mark
    ["="] = {{0.0, 0.65, 0.6, 0.65}, {0.0, 0.35, 0.6, 0.35}}, -- Equals sign
    ["-"] = {{0.0, 0.6, 0.35, 0.6}}, -- Dash
    ["_"] = {{0.0, 1, 0.7, 1}}, -- Underscore
    ["<"] = {{0.6, 0.85, 0.0, 0.5}, {0.6, 0.25}}, -- Less than
    [">"] = {{0.0, 0.25, 0.6, 0.5}, {0.0, 0.85}}, -- Greater than
    ["+"] = {{0.0, 0.5, 0.6, 0.5}, {0.3, 0.2, 0.3, 0.8}}, -- Greater than
    [" "] = {0,0.3},
    ["*"] = {{0.25, 0.0, 0.25, 1.0}, {0.0, 0.65, 0.25, 1.0}, {0.5, 0.65}},
    ["["] = {{0.25, 1.25, 0.0, 1.25}, {0.0, 0.0}, {0.25, 0.0}},
    ["]"] = {{0.0, 1.25, 0.25, 1.25}, {0.25, 0.0}, {0.0, 0.0}},
}


-- Convert text into vertical drawing points with customizable alignment
function textToPointsVertical(text, x, y, size, thickness)
    local points = {} 
    
    local lastPos = 0
    for i = #text, 1, -1  do 
        local char = text:sub(i, i)
        local shape = char_shapes[char] and char_shapes[char] or char_shapes["?"] -- Fallback for undefined characters
        
        local offset = lastPos > 0 and lastPos + 0.35*size or y
        if char == " " then 
            lastPos = offset + 0.25*size 
        else
            largestVal = 0
            for j = 1, #shape do
                val = #shape[j] == 4 and math.max(shape[j][1], shape[j][3]) or shape[j][1]
                if val > largestVal then largestVal = val end
            end
            for j = 1, #shape do 
                val1 = #shape[j] == 4 and shape[j][1] or shape[j-1][#shape[j-1]-1]
                val2 = #shape[j] == 4 and shape[j][2] or shape[j-1][#shape[j-1]]
                val3 = #shape[j] == 4 and shape[j][3] or shape[j][1]
                val4 = #shape[j] == 4 and shape[j][4] or shape[j][2]
            
                x1 = x + (val2) * size
                y1 = offset + (largestVal- val1) * size
                x2 = x + (val4) * size
                y2 = offset + (largestVal- val3) * size
                table.insert(points, {x1, y1, x2, y2})
            end 
            lastPos = offset + (largestVal) * size
        end
    end
    return points, lastPos    
end

-----------------
-- ACTIONS ------

function renameModulatorNames(track, modulationContainerPos)
    local ret, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
    if fxAmount == "0" then
        reaper.TrackFX_Delete(track, modulationContainerPos)
    end 
    
    function goTroughNames(counterArray, savedArray)
        for c = 0, fxAmount -1 do  
            local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c) 
            local renamed, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'renamed_name')
            local nameWithoutNumber = fxName:gsub(" %[%d+%]$", "")
            if not renamed or fxName == "" then
                _, nameWithoutNumber = reaper.TrackFX_GetFXName(track,fxIndex)
            end
            idCounter = "_" .. nameWithoutNumber -- enables to use modules starting with a number
            if not counterArray[idCounter] then 
                counterArray[idCounter] = 1
            else
                counterArray[idCounter] = counterArray[idCounter] + 1
            end
            if savedArray then
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'renamed_name',  nameWithoutNumber .. (savedArray[idCounter] > 1 and " [" .. counterArray[idCounter] .. "]" or "") )
            end
        end 
    end
    -- we go through names twice, first to see if there's more than 1 of a name, and if not we don't add a number
    local countNames = {}
    goTroughNames(countNames)
    local namesExtension = {}
    goTroughNames(namesExtension, countNames) 
end

function getModulatorModulesNameCount(track, modulationContainerPos, name, returnName)
    local _, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
    local nameCount = 0
    for c = 0, fxAmount -1 do  
        local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c) 
        local _, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'fx_name')
        if fxName:match(name) then
            nameCount = nameCount + 1
        end
    end
    return returnName and (name .. " " .. nameCount) or nameCount
end


function getModulationContainerPos(track)
    if track then
        local modulatorsPos = reaper.TrackFX_GetByName( track, "Modulators", false )
        if modulatorsPos ~= -1 then
            return modulatorsPos
        end
    end
    return false
end

-- add container and move it to the first slot and rename to modulators
function addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local modulatorsPos = reaper.TrackFX_GetByName( track, "Modulators", false )
    if modulatorsPos == -1 then
        --modulatorsPos = reaper.TrackFX_GetByName( track, "Container", true )
        modulatorsPos = reaper.TrackFX_AddByName( track, "Container", 0, 1 )
        --modulatorsPos = TrackFX_AddByName( track, "Container", modulatorsPos, -1 ) 
        ret, rename = reaper.TrackFX_SetNamedConfigParm( track, modulatorsPos, 'renamed_name', "Modulators" )
    end
    return modulatorsPos
end

function deleteModule(track, fxIndex, modulationContainerPos)
    if fxIndex and reaper.TrackFX_Delete(track, fxIndex) then
        renameModulatorNames(track, modulationContainerPos)
        selectedModule = false
    end
end

function mapModulatorActivate(fxIndex, sliderNum, fxInContainerIndex, name)
    if not fxIndex or map == fxIndex then 
        map = false
        sliderNumber = false
    else 
        map = fxIndex
        mapName = name
        sliderNumber = sliderNum
        fxContainerIndex = fxInContainerIndex
    end
end

function renameModule(track, modulationContainerPos, fxIndex, newName)
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'renamed_name',  newName)
    renameModulatorNames(track, modulationContainerPos)
end

--[[
function insertLfoFxAndAddContainerMapping(track)
    reaper.Undo_BeginBlock()
    local modulatorsPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = select(2, reaper.TrackFX_GetNamedConfigParm(track, modulatorsPos, 'container_count')) + 1
    local parent_FX_count = reaper.TrackFX_GetCount(track)
    local position_of_container = modulatorsPos+1
    
     insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
     lfo_param = reaper.TrackFX_AddByName( track, 'LFO Modulator', false, insert_position )
     ret, rename = reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'renamed_name', "LFO " .. (lfo_param + 1) )
     
     if fxnumber < 0x2000000 then
        ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulatorsPos, 'container_map.add.'..tostring(lfo_param)..'.1' )
     else
        outputPos = 1
     end 
     reaper.TrackFX_SetOpen(track,fxnumber,true)
     
     
     reaper.Undo_EndBlock("Add modulator plugin",-1)
     return outputPos
end
]]

function insertContainerAddPluginAndRename(track, name, newName)
    reaper.Undo_BeginBlock()
    local modulationContainerPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = select(2, reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')) + 1
    local parent_FX_count = reaper.TrackFX_GetCount(track)
    local position_of_container = modulationContainerPos+1
    
    local insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
    local fxPosition = reaper.TrackFX_AddByName( track, name, false, insert_position )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'renamed_name', newName)--getModulatorModulesNameCount(track, modulationContainerPos, newName, true) )
    renameModulatorNames(track, modulationContainerPos)
    --[[if not paramNumber then paramNumber = 1 end
    if fxnumber < 0x2000000 then
       ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..tostring(fxPosition)..'.' .. paramNumber )
    else
       outputPos = paramNumber
    end ]]
    return modulationContainerPos, insert_position
end


function insertLocalLfoFxAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'LFO Native Modulator', "LFO Native")
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.dir', 0)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertACSAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'ACS Native Modulator', "ACS Native")
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dir', 0)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dblo', -60)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dbhi', 12)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.chan', 2)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.stereo', 1)
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.visible', 1)
    
    reaper.TrackFX_SetNamedConfigParm( track, modulationContainerPos, 'container_nch', 4)
    reaper.TrackFX_SetNamedConfigParm( track, modulationContainerPos, 'container_nch_in', 4)
    --reaper.TrackFX_SetOpen(track,fxnumber,true)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertFXAndAddContainerMapping(track, name, newName, paramNumber)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, name, newName)
    reaper.TrackFX_SetOpen(track,fxnumber,true) -- return to original focus 
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertGenericParamFXAndAddContainerMapping(track, fxIndex, newName, paramNumber, fxInContainerIndex)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, "Generic Parameter Modulator", newName)
    
    reaper.TrackFX_SetOpen(track,fxnumber,true) -- return to original focus 
    p = 1
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.mod.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.mod.baseline', 0 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.offset',0 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.scale',1 )
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.effect',fxInContainerIndex ) -- skal nok være relativ i container
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.param', paramNumber )
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end



function getModulatorNames(track, modulationContainerPos)
    if modulationContainerPos then
        local _, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
        local containerData = {}
        allIsCollabsed = true
        allIsNotCollabsed = true
        
        for c = 0, fxAmount -1 do  
            local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c)  
            local _, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'original_name')
            local renamed, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'renamed_name')
            
            if not renamed or fxName == "" or fxName == nil then 
                fxName = fxOriginalName
            end
            --if not nameCount[fxName] then nameCount[fxName] = 1 else nameCount[fxName] = nameCount[fxName] + 1 end
            --table.insert(containerData, {name = fxName .. " " .. nameCount[fxName], fxIndex = tonumber(fxIndex)})
            table.insert(containerData, {name = fxName, fxIndex = tonumber(fxIndex), fxInContainerIndex = c, fxName = fxOriginalName})
            local isCollabsed = collabsModules[tonumber(fxIndex)]
            if not isCollabsed then allIsCollabsed = false end
            if isCollabsed then allIsNotCollabsed = false end
        end
        return containerData
    end
end

function getParameterLinkValues(track, fxnumber, paramnumber)
    local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline')
    local ret, scale = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.scale')
    local ret, offset = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.offset')
    return baseline, scale, offset
end

function disableParameterLink(track, fxnumber, paramnumber, newValue) 
    local baseline, scale, offset = getParameterLinkValues(track, fxnumber, paramnumber)
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.active',0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.active',0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.effect',-1 )
    if newValue == "CurrentValue" then
    
    elseif newValue == "MaxValue" then
        reaper.TrackFX_SetParam(track,fxnumber,paramnumber,baseline + scale + offset)
    else
        reaper.TrackFX_SetParam(track,fxnumber,paramnumber,baseline)-- + offset)
    end
end

function setParameterToBaselineValue(track, fxnumber, paramnumber) 
    local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline')
    reaper.TrackFX_SetParam(track,fxnumber,paramnumber,baseline)
end

function setBaselineToParameterValue(track, fxnumber, paramnumber) 
    local value, min, max = reaper.TrackFX_GetParam(track,fxnumber,paramnumber)
    local range = max - min
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline', value/range)
    
end


function setParamaterToLastTouched(track, modulationContainerPos,fxIndex, fxnumber, paramnumber, value, offset, scale)
    if fxnumber < 0x2000000 then
       ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. sliderNumber )
    else
       -- could this be done in a better way? -- I need to get the position of the FX inside the container
       outputPos = sliderNumber -- this is the paramater in the lfo plugin 
       modulationContainerPos = fxContainerIndex
    end 
    retParam, currentOutputPos = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.param')
    retEffect, currentModulationContainerPos = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.effect')
    if (retParam and outputPos ~= currentOutputPos) or (retEffect and modulationContainerPos ~= currentModulationContainerPos) then 
        local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline')
        local ret, offset = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.offset')
        local ret, scale = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.scale')
        useOffset = offset
        useScale = scale
        value = tonumber(baseline) + tonumber(offset)
    end
    
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline', value )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.offset',useOffset and useOffset or 0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.scale',useScale and useScale or 1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.effect',modulationContainerPos )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.param', outputPos )
    
end


---------------------------------
----- AB SLIDER FUNCTIONS -------
---------------------------------
function disableAllParameterModulationMappingsByName(name, newValue)
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local params = {}
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxnumber, "") 
        -- Iterate through all parameters for the current FX
        local param_count = reaper.TrackFX_GetNumParams(track, fxnumber)
        for p = 0, param_count - 1 do 
            _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            isParameterLinkActive = parameterLinkActive == "1"
            
            if isParameterLinkActive then
                _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then
                    _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline')
                    _, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
                    _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
                    _, containerItemFxId = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkEffect, 'container_item.'..parameterLinkParam )
                    _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                    if parameterLinkName:match(name) then
                        disableParameterLink(track, fxIndex, p, newValue) 
                    end
                end 
            end
            
        end
    end
end

function parameterWithNameIsMapped(name)
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        -- Iterate through all parameters for the current FX
        local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
        
        for p = 0, param_count - 1 do 
            local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local isParameterLinkActive = parameterLinkActive == "1"
            
            if isParameterLinkActive then
                _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then
                    _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
                    _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                    if parameterLinkName:match(name) then
                        return true
                    end
                end 
            end
            
        end
    end
    return false
end


function getTrackPluginValues(track)
    -- Table to store plugin parameter values
    local plugin_values = {}
    
    function removeBeforeColon(input_string)
        -- Find the position of ": " in the string
        local colon_pos = string.find(input_string, ": ")
        if colon_pos then
            -- Return the substring starting after ": "
            return string.sub(input_string, colon_pos + 2)
        else
            -- If ": " is not found, return the original string
            return input_string
        end
    end
    
    -- Iterate through all FX on the track
    local fx_count = reaper.TrackFX_GetCount(track)
    for fx_number = 0, fx_count - 1 do
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fx_number, "") 
        if not fx_name:match("^Modulators") then 
            local fx_name_simple = removeBeforeColon(fx_name)
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = reaper.TrackFX_GetNumParams(track, fx_number)
            for param = 0, param_count - 1 do
                _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fx_number, 'param.'..param..'.plink.active')
                isParameterLinkActive = parameterLinkActive == "1"
                -- we ignore values that have parameter link activated
                if not isParameterLinkActive then
                    local _, param_name = reaper.TrackFX_GetParamName(track, fx_number, param, "")
                    local value, min, max = reaper.TrackFX_GetParam(track, fx_number, param)
            
                    -- Save parameter details
                    table.insert(params, {
                        name = param_name,
                        number = param,
                        value = value,
                        min = min,
                        max = max
                    })
                end
            
                -- Save FX details
                plugin_values[fx_number + 1] = {
                    name = fx_name_simple,
                    number = fx_number,
                    parameters = params
                }
            end
        end 
    end
    return plugin_values
end

-- Function to compare two arrays of plugin values and log changes
function comparePluginValues(a_trackPluginStates, b_trackPluginStates, track, modulationContainerPos, fxIndex) 
    sliderNumber = 0
    local foundParameters = false
    -- Iterate over the plugins in the current values
    for fx, b_plugin in pairs(b_trackPluginStates) do
        local fx_number = b_plugin.number
        local a_plugin = a_trackPluginStates[fx]

        -- Check if plugin exists in both arrays
        if a_plugin then
            -- Compare plugin names
            if a_plugin.name == b_plugin.name then 
                --reaper.ShowConsoleMsg("2\n")
                -- Compare parameters
                for param, b_param in ipairs(b_plugin.parameters) do
                    local param_number = b_param.number
                    local a_param = a_plugin.parameters[param]
                    
                    -- Check if parameter exists in both plugins
                    if a_param then
                        --reaper.ShowConsoleMsg("3\n")
                        if b_param.value ~= a_param.value then
                            local max = a_param.max
                            local min = a_param.min
                            local range = (min and max) and max - min or 1 
                            setParamaterToLastTouched(track, modulationContainerPos, fxIndex, fx_number, param_number, a_param.value/range, 0, (b_param.value - a_param.value)/range)
                            foundParameters = true
                        end
                    end
                end
                
            end
        end
    end
    return foundParameters
end
        
        
        
        
-------------------------------------------
-------------------------------------------
-------------------------------------------




margin = 8
previousWasCollabsed = false

shape = 0
width = 0.5
steps = 4
inputTest = 0
n = 4
lastSelected = nil
map = false
follow = true

timeType = 0
noteTempo = 5
noteTempoValue = 1
hertz = 1
lfoWidth = 100
partsWidth = 188
collabsWidth = 20

--hasModuleState, modulesState = reaper.GetProjExtState(0, stateName, "collabsModules")
--reaper.ShowConsoleMsg(hasModuleState  .. " - " .. modulesState)
--collabsModules = hasModuleState == 1 and unpickle(modulesState) or {}

parametersBaseline = {}
randomPoints = {25,3,68,94,45,70}
 
collabsModules = {}
modulatorNames = {}
lastCollabsModules = {}
sliderNumber = 0

vertical = reaper.GetExtState(stateName, "vertical") == "1"
sortAsType = true
last_vertical = vertical
    
hidePlugins = reaper.GetExtState(stateName, "hidePlugins") == "1"
hideParameters = reaper.GetExtState(stateName, "hideParameters") == "1"
hideModules = reaper.GetExtState(stateName, "hideModules") == "1"
partsHeight = tonumber(reaper.GetExtState(stateName, "partsHeight")) or 250

openSelected = true
showModulationContainer = true
trackSelectionFollowFocus = reaper.GetExtState(stateName, "trackSelectionFollowFocus") == "1"
showToolTip = reaper.GetExtState(stateName, "showToolTip") == "1"
sortAsType = reaper.GetExtState(stateName, "sortAsType") == "1"

-------------------------------------------
-- KEY COMMANDS 
local function EachEnum(enum)
    local cache = {}
    
    local enum_cache = {}
    cache[enum] = enum_cache

    for func_name, func in pairs(reaper) do
      local enum_name = func_name:match(('^ImGui_%s_(.+)$'):format(enum))
      if enum_name then
        --table.insert(enum_cache, { func(), enum_name })
        enum_cache[func()] = enum_name
      end
    end
   -- table.sort(enum_cache, function(a, b) return a[1] < b[1] end)

    return enum_cache
end

local tableOfAllKeys = EachEnum('Key')

-- KEY COMMANDS 
local keyCommandSettingsDefault = {
    {name = "Undo", commands  = {"Super+Z"}},
    {name = "Redo", commands  = {"Super+Shift+Z"}},
    {name = "Delete", commands  = {"Super+BACKSPACE", "DELETE"}}, 
    {name = "Close", commands  = {"Super+W", "Alt+M"}},
  }

local keyCommandSettings = keyCommandSettingsDefault
if reaper.HasExtState(stateName,"keyCommandSettings") then
    keyCommandSettings = unpickle(reaper.GetExtState(stateName,"keyCommandSettings"))
end


local function checkKeyPress() 
    local text = ""
    for key, keyName in pairs(tableOfAllKeys) do
      if ImGui.IsKeyDown(ctx, key) then
        if keyName:find("Left") == nil and keyName:find("Right") == nil then
            text = isSuperPressed and text .. "Super+" or text
            text = isCtrlPressed and text .. "Ctrl+" or text
            text = isShiftPressed and text .. "Shift+" or text
            text = isAltPressed and text .. "Alt+" or text
            text = text .. string.upper(keyName)
            addKey = nil 
            return text
        end
      end
    end
end

local function addKeyCommand(index)
    local color = (reaper.time_precise()*10)%10 < 5 and colorOrange or colorGrey
    reaper.ImGui_TextColored(ctx, color, "Press Command")
    if reaper.ImGui_IsItemClicked(ctx) then addKey = nil end
    local newKeyPressed = checkKeyPress() 
    if newKeyPressed then
        table.insert(keyCommandSettings[index].commands, newKeyPressed)
        local keyCommandsAsStrings = getKeyCommandsAsStrings(keyCommandSettings) 
        reaper.SetExtState(stateName,"keyCommandSettings", pickle(keyCommandSettings), true)
    end
end

--test = ((((steps + 1) * (n - (n|0)))|0) / steps * 2 - 1)

local function getAllDataFromParameter(track,fxIndex,p)
    local _, valueName = reaper.TrackFX_GetFormattedParamValue(track,fxIndex,p)
    local _, name = reaper.TrackFX_GetParamName(track,fxIndex,p)
    local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
    local isParameterLinkActive = parameterLinkActive == "1"
    
    local _, parameterModulationActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.active')
    local parameterModulationActive = parameterModulationActive == "1"
    
    local baseline = false
    local width = 0
    local offset = 0
    if isParameterLinkActive then
        _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
        if parameterLinkEffect ~= "" then 
            _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline')
            _, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.offset')
            _, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
            _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
            
            if tonumber(fxIndex) < 0x200000 then 
                _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                local colon_pos = parameterLinkName:find(":")
                if colon_pos then
                    parameterLinkName = parameterLinkName:sub(1, colon_pos - 1)
                end
            else
               ret, parameterLinkFXIndex = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_item.' .. parameterLinkEffect )
               --reaper.ShowConsoleMsg(tostring(ret) .. " - " ..name .. " - " .. parameterLinkFXIndex .. "\n")
               if ret then
                  _, parameterLinkName = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkFXIndex, 'renamed_name' )
               end
            end 
        end 
    else
        parameterLinkEffect = false
    end
    
    local trackEnvelope = reaper.GetFXEnvelope(track,fxIndex,p,false)
    if trackEnvelope then
        pointCount = reaper.CountEnvelopePoints(trackEnvelope)
        usesEnvelope = pointCount > 0
        if usesEnvelope then
            retval, envelopeValue, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate( trackEnvelope, playPos, 0, 0 )
        end
    else
        envelopeValue = false
        usesEnvelope = false
    end
    
    local value, min, max = reaper.TrackFX_GetParam(track,fxIndex,p)
    
    
    return {number = p, name = name, value = value, min = min, max = max, baseline = tonumber(baseline), width = tonumber(width), offset = tonumber(offset),
    valueName = valueName, fxIndex = fxIndex, 
    parameterModulationActive = parameterModulationActive, isParameterLinkActive = isParameterLinkActive, parameterLinkEffect = parameterLinkEffect,containerItemFxId = tonumber(containerItemFxId),
    usesEnvelope = usesEnvelope, envelopeValue = envelopeValue, parameterLinkParam = parameterLinkParam, parameterLinkName = parameterLinkName,
    }
end

local function getAllParametersFromTrackFx(track, fxIndex)
    local data = {} 
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        for p = 0, paramCount do
            table.insert(data, getAllDataFromParameter(track,fxIndex,p))
        end
    end
    return data
end

local function findParentContainer(fxContainerIndex)
    for i, container in ipairs(containers) do 
        if container.fxIndex == fxContainerIndex then
            if container.fxContainerIndex then
                return findParentContainer(container.fxContainerIndex)
            else  
                return fxContainerIndex
            end
        end
    end 
end

-- Function to get all plugins on a track, including those within containers
function getAllTrackFXOnTrack(track)
    local plugins = {} -- Table to store plugin information
    local containersFetch = {} -- Table to store plugin information
    -- Helper function to get plugins recursively from containers
    local function getPluginsRecursively(track, fxContainerIndex, indent, fxCount, isModulator, fxContainerName)
        if fxCount then 
            for subFxIndex = 0, fxCount - 1 do
                local ret, fxIndex = reaper.TrackFX_GetNamedConfigParm( track, fxContainerIndex, "container_item." .. subFxIndex )
                local retval, fxName = reaper.TrackFX_GetFXName(track, fxIndex, "") -- Get the FX name'
                local retval, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "fx_name") -- Get the FX name
                local retval, container_count = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "container_count" )
                local isContainer = fxOriginalName == "Container" -- Check if FX is a container 
                local isEnabled = reaper.TrackFX_GetEnabled(track, fxIndex)
                
                table.insert(plugins, {number = fxIndex, name = fxName, isModulator = isModulator, indent = indent, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, isContainer = isContainer, base1Index = subFxIndex + 1, isEnabled = isEnabled})
                if isContainer then
                    table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, isContainer = isContainer, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = subFxIndex + 1, indent = indent, isEnabled = isEnabled})
                end
                
                if isContainer then
                    indent = indent + 1
                    getPluginsRecursively(track, fxIndex, indent, tonumber(container_count), fxName)
                end
            end
        end
    end

    if track then
        -- Total number of FX on the track
        local totalFX = reaper.TrackFX_GetCount(track)
    
        -- Iterate through each FX
        for fxIndex = 0, totalFX - 1 do
            local retval, fxName = reaper.TrackFX_GetFXName(track, fxIndex, "") -- Get the FX name'
            local retval, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "fx_name") -- Get the FX name'
            local retval, container_count = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "container_count" )
            local isContainer = fxOriginalName == "Container" -- Check if FX is a container 
            local isModulator = fxName == "Modulators"
            local isEnabled = reaper.TrackFX_GetEnabled(track, fxIndex)
    
            -- Add the plugin information
            table.insert(plugins, {number = fxIndex, name = fxName, isContainer = isContainer, isModulator = isModulator, fxContainerName = "ROOT", base1Index = fxIndex + 1, indent = 0, isEnabled = isEnabled})
            if isContainer then
                table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, isContainer = isContainer, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = fxIndex + 1, indent = indent, isEnabled = isEnabled})
            end
            -- If the FX is a container, recursively check its contents
            if isContainer then
                local indent = 1 
                getPluginsRecursively(track, fxIndex, indent, tonumber(container_count), isModulator, fxName)
            end
        end
    end
    
    return plugins
        
end


local function getAllTrackFXOnTrackSimple(track)
    local fxCount = reaper.TrackFX_GetCount(track)
    local data = {}
    for f = 0, fxCount do
       _, name = reaper.TrackFX_GetFXName(track,f)
       table.insert(data, {number = f, name = name})
    end
    return data
end

function mapPlotColor()
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),colorMap)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),colorMap)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),colorMap)
end



function setToLastKnownValue(array)
    local result = reaper.new_array(plotAmount)
    for i = 1, #result do
        result[i] = array[#array]
    end
    return result
end



local function drawFaderFeedback(sizeW, sizeH, fxIndex, param, min, max)
    isCollabsed = collabsModules[fxIndex]
    
    if not inputPlots then inputPlots = {}; time = {}; offset = {} end
    --aaa = lastCollabsModules
    --reaper.ShowConsoleMsg(tostring(isCollabsed) .. " - " .. fxIndex .. " - " .. tostring(lastCollabsModules[fxIndex]) .. "\n")
    --if not sizeW then 
        sizeW = isCollabsed and 20 or buttonWidth
        sizeH = isCollabsed and 20 or buttonWidth/2
        plotAmount = isCollabsed and 50 or 200
        --if inputPlots and inputPlots[trackId] and inputPlots[trackId][fxIndex] and lastCollabsModules[fxIndex] ~= isCollabsed then
        if lastCollabsModules[fxIndex] ~= isCollabsed then
            array = inputPlots[fxIndex] and inputPlots[fxIndex] or reaper.new_array(plotAmount)
            inputPlots[fxIndex] = setToLastKnownValue(array)
            offset[fxIndex] = 1
            lastCollabsModules[fxIndex] = isCollabsed
        end
    --end
    
    --if not inputPlots[trackId] then inputPlots[trackId] = {}; time[trackId] = {}; offset[trackId] = {}; phase[trackId] = {} end
    if not inputPlots[fxIndex] then inputPlots[fxIndex] = reaper.new_array(plotAmount) end
    if not time[fxIndex] then time[fxIndex] = ImGui.GetTime(ctx) end
    if not offset[fxIndex] then offset[fxIndex] = 1 end
    --if not phase[fxIndex] then phase[fxIndex] = 0 end
    
    
    -- ret, value = reaper.TrackFX_GetNamedConfigParm( track, modulatorsPos, 'container_map.get.' .. fxIndex .. '.2' )
    value = reaper.TrackFX_GetParam(track,fxIndex,param)
    --reaper.ShowConsoleMsg(fxIndex .. "\n")
    
    while time[fxIndex] < ImGui.GetTime(ctx) do -- Create data at fixed 60 Hz rate
      inputPlots[fxIndex][offset[fxIndex]] = value
      offset[fxIndex] = (offset[fxIndex] % plotAmount) + 1
      time[fxIndex] = time[fxIndex] + (1.0 / 60.0)
    end
    
    local posX, posY = reaper.ImGui_GetCursorPos(ctx)
    if map == fxIndex then mapPlotColor() end
    reaper.ImGui_PlotLines(ctx, '##'..fxIndex, inputPlots[fxIndex], offset[fxIndex] - 1, nil, min, max, sizeW, sizeH)
    if map == fxIndex then reaper.ImGui_PopStyleColor(ctx, 3) end
    
    clicked = reaper.ImGui_IsItemClicked(ctx)
    reaper.ImGui_SetCursorPos(ctx, posX, posY) 
    
    --reaper.ImGui_SetNextItemAllowOverlap(ctx)
    reaper.ImGui_Button(ctx, ((reaper.ImGui_IsItemHovered(ctx, reaper.ImGui_HoveredFlags_DelayNone()) or map == fxIndex) and (isCollabsed and "M" or "Map") or "") ..  "##plotLinesButton" .. fxIndex ,sizeW,sizeH)
    if showToolTip then ImGui.SetItemTooltip(ctx, map and (map ~= fxIndex and ("Click to map " .. mapName .. "\nPress escape to stop mapping") or "Click or press escape to stop mapping") or "Click to map output") end
    return clicked
end

-- Function to add newlines after spaces, ensuring no line exceeds chunk_size
function addNewlinesAtSpaces(input_string, chunk_size)
    local result = {}
    local current_line = ""
    
    for word in input_string:gmatch("%S+") do
        -- Add the word to the current line
        if #current_line + #word + 1 <= chunk_size then
            -- Append word to current line (with space if it's not empty)
            current_line = current_line .. (current_line ~= "" and " " or "") .. word
        else
            -- Add current line to result and start a new line
            table.insert(result, current_line)
            current_line = word
        end
    end
    
    -- Add the last line
    if current_line ~= "" then
        table.insert(result, current_line)
    end
    
    -- Concatenate the lines with "\n"
    return table.concat(result, "\n")
end

function modulePartButton(name, tooltipText, sizeW, bigText, background, textSize)
    if vertical then
        return titleButtonStyle(name, tooltipText, sizeW, bigText, background)
    else 
        return verticalButtonStyle(name, tooltipText, sizeW, bigText, background, textSize)
    end
end


function titleButtonStyle(name, tooltipText, sizeW, bigText, background)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),menuGreyHover)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),menuGreyActive)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and menuGrey or colorTransparent)
    local clicked = false
    if bigText then reaper.ImGui_PushFont(ctx, font2) end
    
        reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    if verticalName then
        name = name:upper():gsub(".", "%0\n")
    end
    
    if reaper.ImGui_Button(ctx,name, sizeW) then
        clicked = true
    end 
    if reaper.ImGui_IsItemHovered(ctx) and showToolTip then
        reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26) )  
    end
    reaper.ImGui_PopStyleColor(ctx,3)
    reaper.ImGui_PopStyleVar(ctx)
    if bigText then reaper.ImGui_PopFont(ctx) end
    if background then 
        local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
        local endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , endPosX, endPosY, colorGrey,4)
    end
    return clicked 
end


function verticalButtonStyle(name, tooltipText, sizeW, verticalName, background, textSize)
    --ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),background and menuGreyHover or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),background and menuGreyHover or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),background and menuGreyActive or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and menuGrey or colorTransparent)
    local clicked = false 
    
    reaper.ImGui_PushFont(ctx, font2)
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    
    local points, lastPos = textToPointsVertical(name,0, 0, textSize and textSize or 11, 3)
    
    if reaper.ImGui_Button(ctx, "##"..name,textSize and textSize +9 or 20, sizeW and sizeW or lastPos + 14) then
        clicked = true
    end 
    
    local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
    local text_pos_x = startPosX +4
    local text_pos_y = startPosY +6
    
    for _, line in ipairs(points) do
        reaper.ImGui_DrawList_AddLine(draw_list, text_pos_x + line[1], text_pos_y +line[2],  text_pos_x + line[3],text_pos_y+ line[4], 0xffffffff, 1.2)
    end 
    
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26) )  
    end
    reaper.ImGui_PopStyleColor(ctx,3)
    
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleVar(ctx)
    if background then
        
        startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
        endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , endPosX, endPosY, colorGrey,4)
    end
    return clicked 
end

function setToolTipFunc(text, color)
    if showToolTip then  
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorWhite) 
        ImGui.SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx)
    end
end

function setToolTipFunc2(text,color)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorWhite)  
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx,addNewlinesAtSpaces(text,26))
    reaper.ImGui_EndTooltip(ctx)
    reaper.ImGui_PopStyleColor(ctx)
end

function lastItemClickAndTooltip(tooltipText)
    if reaper.ImGui_IsItemHovered(ctx) then
        if showToolTip then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26)) end
        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
            clicked = "right"
        end
        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
            clicked = "left"
        end
    end
    return clicked
end


function titleTextStyle(name, tooltipText, sizeW, background)
    if background then
        reaper.ImGui_PushFont(ctx, font2)
    end
    local clicked = false
    if not sizeW then sizeW = reaper.ImGui_CalcTextSize(ctx,name, 0,0) end
    reaper.ImGui_Text(ctx, name)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
    if mouseX >= minX - margin and mouseX <= minX + sizeW - margin and mouseY >= minY and mouseY <= maxY then
         if showToolTip then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26)) end
         if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
             clicked = "right"
         end
         if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
             clicked = "left"
         end
    end

    if background then
        reaper.ImGui_PopFont(ctx)
    end
    return clicked 
end

function getCollabsModulesStateOnTrack()
    local saved, collabsModulesStr = reaper.GetSetMediaTrackInfo_String( track, "P_EXT:" .. stateName .. "collabsModules", "", false )
    local newCollabsStates = (saved and collabsModulesStr ~= "") and unpickle(collabsModulesStr) or {}
    collabsModules = newCollabsStates
    --lastCollabsModules = newCollabsStates
    return newCollabsStates
end

function saveCollabsModulesStateOnTrack()
     reaper.GetSetMediaTrackInfo_String( track, "P_EXT:" .. stateName .. "collabsModules", pickle(collabsModules), true )
    --for _, m in ipairs(modulatorNames) do
   --     reaper.GetSetMediaTrackInfo_String( track, "P_EXT:" .. stateName .. ":collabsModule:" .. m.fxIndex, collabsModules[m.fxIndex] and "1" or "0", true )
    --end
end

function hideShowEverything(newState)
    
    if modulatorNames  then
        for _, m in ipairs(modulatorNames) do collabsModules[m.fxIndex] = newState end  
        saveCollabsModulesStateOnTrack()
    end
    
    hidePlugins = newState
    hideParameters = newState
    hideModules = newState
    
    reaper.SetExtState(stateName, "hidePlugins", newState and "1" or "0", true )
    reaper.SetExtState(stateName, "hideParameters", newState and "1" or "0", true)
    reaper.SetExtState(stateName, "hideModules", newState and "1" or "0", true)
end

colorMap = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,1)
colorMapLight = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.65,0.65,1)
colorMapLightest = reaper.ImGui_ColorConvertDouble4ToU32(0.95,0.75,0.75,1)
colorMapLightTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.65,0.65,0.5)
colorMapLittleTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.9)
colorMapSemiTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.7)
colorMapMoreTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.4)
colorGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.4,0.4,1)
colorLightGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.6,0.6,0.6,1)
colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1,1)
colorAlmostWhite = reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8,1)
colorBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.4,0.8,1)
colorLightBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.4,0.8,0.5)
colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0,0)
semiTransparentGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3,0.2)
littleTransparentGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3,0.4)
menuGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.14,0.14,0.14,1)
menuGreyHover = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.30,0.30,1)
menuGreyActive = reaper.ImGui_ColorConvertDouble4ToU32(0.45,0.45,0.45,1)

function buttonTransparent(name, width,height) 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
    reaper.ImGui_Button(ctx,name, width,height)
    reaper.ImGui_PopStyleColor(ctx,3)
end

function mapButtonColor()
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMapSemiTransparent)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMap)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorMapLittleTransparent)
end

local function loop() 
  playPos = reaper.GetPlayPosition() 
  moduleWidth = partsWidth - 16
  dropDownSize = moduleWidth -30--/ 2
  buttonWidth = dropDownSize / 2
  
  retvaltouch, trackidx_fromtouch, itemidx_fromtouch, takeidx_fromtouch, fxnumber_fromtouch, paramnumber_fromtouch = reaper.GetTouchedOrFocusedFX( 0 )
  --retvalfocus, trackidx_fromfocus, itemidx_fromfocus, takeidx_fromfocus, fxnumber_fromfocus, paramnumber_fromfocus = reaper.GetTouchedOrFocusedFX( 1 )

  
  
  firstSelectedTrack = reaper.GetSelectedTrack(0,0)
  if lastFirstSelected and lastFirstSelected ~= firstSelectedTrack then 
      retvaltouch = false
      retvalfocus = false
  end
  lastFirstSelected = firstSelectedTrack  
  
  isAltPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
  isCtrlPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
  isShiftPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
  isSuperPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
  isMouseDown = reaper.ImGui_IsMouseDown(ctx,reaper.ImGui_MouseButton_Left())
  isMouseReleased = reaper.ImGui_IsMouseReleased(ctx,reaper.ImGui_MouseButton_Left())
  --isMouseReleased = reaper.JS_Mouse_GetState(1)
  isMouseDragging = reaper.ImGui_IsMouseDragging(ctx,reaper.ImGui_MouseButton_Left()) 
  click_pos_x, click_pos_y = ImGui.GetMouseClickedPos(ctx, 0) 
  mouse_pos_x, mouse_pos_y = ImGui.GetMousePos(ctx)
  
  local scrollFlags = isAltPressed and reaper.ImGui_WindowFlags_NoScrollWithMouse() or reaper.ImGui_WindowFlags_None()



  if retvaltouch then
      if map then
          if ((last_fxnumber_fromtouch and last_fxnumber_fromtouch ~= fxnumber_fromtouch) or ( last_paramnumber_fromtouch and last_paramnumber_fromtouch ~= paramnumber_fromtouch)) then
              mapNewlyTouched = true
          end
      end
      
      if (not last_fxnumber_fromtouch or last_fxnumber_fromtouch ~= fxnumber_fromtouch) then
          last_fxnumber_fromtouch = fxnumber_fromtouch
          fxnumber = fxnumber_fromtouch
          last_paramnumber_fromtouch = nil -- ensure to reset scroll focus
          if doNotChangeOnlyMapped then
              doNotChangeOnlyMapped = false
          else
              onlyMapped = false
          end
          
          scrollPlugin = fxnumber
      end 
      
      --fxnumberSelectedFromScript PROBABLY DOESN*T WORK. TRYING TO MAKE SURE THAT NOT CONTAINER IS SELECTED WHEN SELECTING VIA SCRIPT!!
      if not fxnumberSelectedFromScript and retvalfocus and fxnumber_fromfocus > -1 and (not last_fxnumber_fromfocus or last_fxnumber_fromfocus ~= fxnumber_fromfocus) then 
          last_fxnumber_fromfocus = fxnumber_fromfocus
          fxnumber = fxnumber_fromfocus
          --last_paramnumber_fromtouch = nil -- ensure to reset scroll focus
          if doNotChangeOnlyMapped then
              doNotChangeOnlyMapped = false
          else
              onlyMapped = false
          end
          
          scrollPlugin = fxnumber
      end 
      fxnumberSelectedFromScript = false
      
      if not last_paramnumber_fromtouch or last_paramnumber_fromtouch ~= paramnumber_fromtouch then
          last_paramnumber_fromtouch = paramnumber_fromtouch
          paramnumber = paramnumber_fromtouch
          if not ignoreScroll then
              scroll = paramnumber
          end
          ignoreScroll = nil
          if doNotChangeOnlyMapped then
              doNotChangeOnlyMapped = false
          else
              onlyMapped = false
          end
      end
      
      if mapNewlyTouched then 
          setParamaterToLastTouched(track, modulationContainerPos, map, fxnumber, paramnumber, reaper.TrackFX_GetParam(track,fxnumber, paramnumber))
          mapNewlyTouched = false
      end
      
      if not last_trackidx_fromtouch or last_trackidx_fromtouch ~= trackidx_fromtouch then
          --last_trackidx_fromtouch = trackidx_fromtouch
          --track = reaper.GetTrack(0,trackidx_fromtouch)
      end 
      if firstSelectedTrack and track ~= firstSelectedTrack and trackSelectionFollowFocus then
          track = firstSelectedTrack
          reaper.SetOnlyTrackSelected(track)
      end
  else 
      if not track or firstSelectedTrack ~= track then 
          track = firstSelectedTrack 
          mapModulatorActivate(nil)
      end
  end
  
  if not fxnumber then fxnumber = 0 end
  if not paramnumber then paramnumber = 0 end
  --if not track then track = reaper.GetTrack(0,0) end
  if track then
      _, trackName = reaper.GetTrackName(track)
      trackId = reaper.GetTrackGUID(track) 
      
      if not lastTrack or lastTrack ~= track then  
          getCollabsModulesStateOnTrack()--{}--unpickle(modulesState)
          
          _, trackName = reaper.GetTrackName(track)
          lastTrack = track
      end
      
      --if not collabsModules then collabsModules =  getCollabsModulesStateOnTrack() end
      --if not lastCollabsModules then lastCollabsModules = {} end 
  else
      --trackName = "Select a track or touch a plugin parameter"
      trackName = "No track selected"
  end
  
  --trackGuid = reaper.GetTrackGUID(track)
  
  if resetWindowSize then
      winW, winH = reaper.ImGui_GetWindowSize(ctx)
      --if winW > 1000
      resetWindowSize = false
  end
  
  if last_vertical ~= vertical then 
      reaper.ImGui_SetNextWindowSize(ctx, vertical and partsWidth+margin*3 or 1500, vertical and 0 or 450,nil)
      last_vertical = vertical
      resetWindowSize = true
  end
  
  
  reaper.ImGui_PushFont(ctx, font)
  local visible, open = ImGui.Begin(ctx, 'Modulation Linking',true, 
  reaper.ImGui_WindowFlags_TopMost() | 
  --reaper.ImGui_WindowFlags_NoCollapse() | 
  --reaper.ImGui_WindowFlags_MenuBar() |
  reaper.ImGui_WindowFlags_HorizontalScrollbar()
  | scrollFlags
  )
  if visible then
      winW, winH = reaper.ImGui_GetWindowSize(ctx)
  
      local dock_id = reaper.ImGui_GetWindowDockID(ctx)
      local is_docked = reaper.ImGui_IsWindowDocked(ctx)
      if not last_dock_id or last_dock_id ~= dock_id then
        if dock_id == -1 or dock_id == -2 then
            vertical = true
        elseif dock_id == -4 or dock_id == -3 then
            vertical = false
        end
        reaper.SetExtState(stateName, "vertical", vertical and "1" or "0", true)
        last_dock_id = dock_id  
      end
      
      
      --if track then 
      
        
        
        
        modulationContainerPos = getModulationContainerPos(track)
        local focsuedTrackFXNames = getAllTrackFXOnTrack(track)
        local focusedTrackFXParametersData = getAllParametersFromTrackFx(track, fxnumber) 
        
        if not lastTouchedParam or lastTouchedParam ~= paramnumber or focusedFxNumber ~= fxnumber then
            --lastSelected = focusedTrackFXParametersData[paramnumber+1]
            if not lastTouchedParam or lastTouchedParam ~= paramnumber then 
                focusedParamNumber = tonumber(paramnumber)
                lastTouchedParam = paramnumber 
            end
            if not focusedFxNumber or focusedFxNumber ~= fxnumber then
                if firstRunDone then
                    if follow and focusedFxNumber then 
                        --[[local floating = reaper.TrackFX_GetFloatingWindow( track, fileInfo.fxIndex ) ~= nil
                        local floatingContainer = focusedMapping and fileInfo.fxContainerIndex and reaper.TrackFX_GetFloatingWindow( track, fileInfo.fxContainerIndex ) ~= nil
                        local isInTheRoot = not fileInfo.fxContainerIndex
                        local topContainerFxIndex = focusedMapping and fileInfo.fxContainerIndex and findParentContainer(fileInfo.fxContainerIndex) or fileInfo.fxIndex
                        local fxWindowOpen = focusedMapping and topContainerFxIndex and reaper.TrackFX_GetOpen( track, topContainerFxIndex )
                        if not fileInfo.fxContainerIndex and floatingSampler then fxWindowOpen = false end
                        ]]
                        
                        if tonumber(fxnumber) > 0x200000 then
                            reaper.TrackFX_SetOpen(track,fxnumber,true)
                            --reaper.TrackFX_SetOpen(track,0,true)
                            --reaper.TrackFX_Show(track,fxnumber,1)
                        else
                            reaper.TrackFX_SetOpen(track,fxnumber,true)
                        end
                    end
                    
                    focusedFxNumber = fxnumber
                    firstRunDone = false
                end
                firstRunDone = true
            end
        end
        
      
      
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)
        --reaper.slider(ctx,wi,v,0,1,
        --ret, shape = ImGui.Combo(ctx, 'Shape', shape, 'Sin\0Square\0Saw L\0Saw R\0Triangle\0Random\0Steps\0')
        
        --ret, width = ImGui.SliderDouble(ctx, 'Width', width, 0, 1)
        --ret, steps = ImGui.SliderInt(ctx, 'Steps', steps, 2, 16)
        
        
        --do
          --ImGui.PlotLines(ctx, 'Lines', widgets.plots.plot1.data, widgets.plots.plot1.offset - 1, overlay, -1.0, 1.0, 0, 80.0)
        
        --end
        
        function scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, nativeParameter, dropDownValue)
            if reaper.ImGui_IsItemHovered(ctx) and isAltPressed then 
                mouseWheelValue = reaper.ImGui_GetMouseWheel(ctx)
                if mouseWheelValue ~= 0 then
                    if nativeParameter then
                        if dropDownValue then 
                            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, nativeParameter, currentValue)
                        else
                            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, nativeParameter, currentValue - (mouseWheelValue * divide/100 ))
                        end
                    else
                        if dropDownValue then
                            setParameterButReturnFocus( track, fxIndex, paramIndex, currentValue - (mouseWheelValue > 0 and dropDownValue or -1*dropDownValue))
                        else
                            setParameterButReturnFocus(track, fxIndex, paramIndex, currentValue - (mouseWheelValue * divide/100 )) 
                        end
                    end
                end
            end
        end
        
        function pluginParameterSlider(buttonId, sliderValue,min,max,sliderFlags)
            return reaper.ImGui_SliderDouble(ctx,"##val" .. buttonId , sliderValue, min, max, "") 
        end
        
        function pluginParameterName(name, valueName, number)
            reaper.ImGui_Text(ctx,name .. "\n" .. valueName) 
            if not map and ImGui.IsItemClicked(ctx) then paramnumber = number end 
        end
        
        
        
        function parameterNameAndSliders(func1, func2, p, focusedParamNumber, infoModulationSlider, sizeArray) 
            local isParameterLinkActive = p.isParameterLinkActive
            local parameterModulationActive = p.parameterModulationActive
            local containerItemFxId = p.containerItemFxId
            local fxIndex = p.fxIndex
            local number = p.number
            local value = p.value
            local valueName = p.valueName
            local min = p.min
            local max = p.max
            local usesEnvelope = p.usesEnvelope
            local parameterLinkEffect = p.parameterLinkEffect
            local parameterLinkName = p.parameterLinkName
            local name = p.name
            local envelopeValue = p.envelopeValue
            local baseline = p.baseline
            local offset = p.offset
            local width = p.width
            local buttonId = fxIndex .. ":" .. number
            
            
            local mapVariable = false
            if map and (not isParameterLinkActive or (isParameterLinkActive and map ~= containerItemFxId)) then
                mapVariable = true 
                ImGui.SetNextItemAllowOverlap(ctx)
            end 
            local textSize = reaper.ImGui_CalcTextSize(ctx, "Offset", 0,0) + 10 
            local itemWidth = (sizeArray and sizeArray.faderWidth) and sizeArray.faderWidth or moduleWidth - 2 - textSize 
            local areaWidth = infoModulationSlider and moduleWidth-30 or moduleWidth - 2
            local faderWidth =  (sizeArray and sizeArray.faderWidth) and sizeArray.faderWidth or moduleWidth
            local parameterMappingWidth = (sizeArray and sizeArray.parameterMapSize) and sizeArray.parameterMapSize or itemWidth
            
            if ImGui.BeginPopup(ctx, 'popup##' .. buttonId, nil) then
                if isParameterLinkActive then
                    if reaper.ImGui_Button(ctx,"Remove ".. '"' ..  parameterLinkName .. '"' .. " modulator mapping##remove" .. buttonId) then
                        disableParameterLink(track, fxIndex, number)
                        doNotChangeOnlyMapped = true
                        ImGui.CloseCurrentPopup(ctx)
                    end 
                    if reaper.ImGui_Button(ctx,"Open ".. '"' .. parameterLinkName .. '"' .. " modulator plugin##open" .. buttonId) then 
                        reaper.TrackFX_SetOpen(track,fxnumber,true)   
                        ImGui.CloseCurrentPopup(ctx)
                    end 
                    if reaper.ImGui_Button(ctx,"Show "..'"' .. name ..'"' .. " parameter modulation/link window##show" .. buttonId) then 
                        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..number..'.mod.visible',1 )
                        ImGui.CloseCurrentPopup(ctx)
                    end
                end
                ImGui.EndPopup(ctx)
            end
            
            ImGui.BeginGroup(ctx)  
            local parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
            
            local startPosX, startPosY = reaper.ImGui_GetCursorPos(ctx)
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 2) 
            if infoModulationSlider then 
                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(), parameterModulationActive and colorMapLightest or colorWhite)
            else
                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(), number == focusedParamNumber and colorWhite or (parameterModulationActive and colorMapLightest or colorGrey))
            end
            
            if func1 then 
                func1(name, valueName, number)
            end
            
            local posX, posY = reaper.ImGui_GetCursorPos(ctx)
            
            
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),semiTransparentGrey)
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),semiTransparentGrey)
            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),semiTransparentGrey) 
            
            
            
            
            -- oscilation param
            if isParameterLinkActive and parameterModulationActive then 
                ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab,reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,1))
                ImGui.SetNextItemAllowOverlap(ctx)
                ImGui.SetNextItemWidth(ctx, faderWidth)
                if mapVariable then ImGui.SetNextItemAllowOverlap(ctx) end -- in order for the overlapping map button to take focus
                reaper.ImGui_SliderDouble(ctx,"##oci" .. buttonId ,value, min, max, "",reaper.ImGui_SliderFlags_NoInput())
                reaper.ImGui_PopStyleColor(ctx)
                reaper.ImGui_SetCursorPos(ctx, posX, posY)
            end
            

            
            local sliderValue = usesEnvelope and envelopeValue or ((parameterLinkEffect and parameterModulationActive) and baseline or value) 
            if mapVariable then ImGui.SetNextItemAllowOverlap(ctx) end -- in order for the overlapping map button to take focus
            
            --if isAltPressed and sliderValue ~= 0 then reaper.ShowConsoleMsg(value .. " - "sliderValue .. "\n") end
            
            ImGui.SetNextItemWidth(ctx, faderWidth)
            if infoModulationSlider then
                ret, newValue = func2(track,fxIndex, infoModulationSlider, sliderValue)
                parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
            else
                ret, newValue = func2(buttonId, sliderValue,min,max)
                ImGui.SetItemTooltip(ctx, 'Set parameter bassline') 
            end
            
            
            if ret and number > -1 then
                if usesEnvelope then
                -- write automation
                -- first read automation state
                -- then set to touch
                elseif parameterLinkEffect and parameterModulationActive then
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..number..'.mod.baseline', newValue ) 
                else 
                    reaper.TrackFX_SetParam(track, fxIndex, number, newValue)
                end
            end 
            
            if usesEnvelope then
                
            elseif parameterLinkEffect and parameterModulationActive then
                scrollHoveredItem(track, fxIndex, nil, sliderValue, 1, 'param.'.. number..'.mod.baseline', nil)
            else
                scrollHoveredItem(track, fxIndex, number, sliderValue, 1, nil, nil)
            end
            
            
            if not map and ImGui.IsItemClicked(ctx) then ignoreScroll = true end
            if not map and ImGui.IsItemClicked(ctx) then paramnumber = number end
            
            if isParameterLinkActive then 
                local linkName = parameterLinkName 
                --ImGui.SetNextItemWidth(ctx, itemWidth - textSize) 
                --reaper.ImGui_SetCursorPos(ctx, posX, posY)
                ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab,colorMap)
                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(),colorMap)
                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(),colorMap)
                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),parameterModulationActive and colorMapLight or colorMapLightTransparent)
                if mapVariable then ImGui.SetNextItemAllowOverlap(ctx) end -- in order for the overlapping map button to take focus                          
                
                if not parameterModulationActive then reaper.ImGui_BeginDisabled(ctx) end
                
                local ret, newValue = reaper.ImGui_Checkbox(ctx, linkName .. "##enable" .. buttonId, parameterModulationActive)
                if parameterModulationActive then setToolTipFunc('Disable parameter modulation of ' .. linkName) end 
                    if ret and number > -1 then
                      reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..number..'.mod.active', newValue and 1 or 0 )
                      setParameterToBaselineValue(track, fxIndex, number) 
                    end 
                    local minX, minY = reaper.ImGui_GetItemRectMin(ctx) 
                    
                    ImGui.SetNextItemWidth(ctx, parameterMappingWidth) 
                    if mapVariable then ImGui.SetNextItemAllowOverlap(ctx) end -- in order for the overlapping map button to take focus
                    local ret, newValue = reaper.ImGui_SliderInt(ctx, "Offset##offset" .. buttonId ,math.floor(offset*100), -100, 100, "%d", sliderFlags)
                    if reaper.ImGui_IsItemClicked(ctx, 0) then -- reset value
                        ret, newValue = true, 0
                    end
                    if parameterModulationActive then setToolTipFunc('Set modulation offset of ' .. linkName .. ".\nClick Offset to reset") end
                    if ret and number > -1 then
                      reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. number..'.plink.offset', newValue / 100 )
                    end
                    scrollHoveredItem(track, fxIndex, nil, offset, 1, 'param.'.. number..'.plink.offset', nil)
                    
                    ImGui.SetNextItemWidth(ctx, parameterMappingWidth) 
                    if mapVariable then ImGui.SetNextItemAllowOverlap(ctx) end -- in order for the overlapping map button to take focus
                    local ret, newValue = reaper.ImGui_SliderInt(ctx, "Width##width" .. buttonId ,math.floor(width*100), -100, 100, "%d", sliderFlags)
                    if reaper.ImGui_IsItemClicked(ctx, 0) then -- reset value
                        ret, newValue = true, 100
                    end 
                    if parameterModulationActive then setToolTipFunc('Set modulation width of ' .. linkName .. ".\nClick Width to reset") end
                    if ret and number > -1 then
                      reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. number..'.plink.scale', newValue / 100 )
                    end 
                    scrollHoveredItem(track, fxIndex, nil, width, 1, 'param.'.. number..'.plink.scale', nil)
                    
                if not parameterModulationActive then reaper.ImGui_EndDisabled(ctx) end
                local _, maxY = reaper.ImGui_GetItemRectMax(ctx)
                local maxX = minX + areaWidth
                reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, colorMapLightTransparent,4,nil,1)
                local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx) 
                -- parameter mapping hoover
                if not parameterModulationActive and mouseX >= minX and mouseX <= maxX and mouseY >= minY and mouseY <= maxY then
                    setToolTipFunc2('Enable parameter modulation of ' .. linkName)
                    if reaper.ImGui_IsMouseReleased(ctx,reaper.ImGui_MouseButton_Left()) then 
                         setBaselineToParameterValue(track, fxIndex, number) 
                         reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..number..'.mod.active', 1 )
                    end
                end

                reaper.ImGui_PopStyleColor(ctx,4)
            end
            
            reaper.ImGui_PopStyleColor(ctx,4) 
            ImGui.PopStyleVar(ctx)
            
            
            endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
            
            
            if map and (not isParameterLinkActive or (isParameterLinkActive and mapName ~= parameterLinkName)) then
                reaper.ImGui_SetCursorPos(ctx, startPosX,startPosY)
                mapButtonColor()
                reaper.ImGui_Button(ctx,  "Map " .. name .. "##map" .. buttonId,  areaWidth, endPosY - startPosY - 4)
                if ImGui.IsItemClicked(ctx) then
                    --paramnumber = number
                    --ignoreScroll = true
                    setParamaterToLastTouched(track, modulationContainerPos, map, fxIndex, number, value)
                end
                reaper.ImGui_PopStyleColor(ctx,3) 
            end
            
            local parEndPosX, parEndPosY = reaper.ImGui_GetItemRectMax(ctx)
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            
            -- Check if the mouse is within the button area
            if mouse_x >= parStartPosX and mouse_x <= parStartPosX + areaWidth and
               mouse_y >= parStartPosY and mouse_y <= parEndPosY then
              if  isParameterLinkActive and reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
                  ImGui.OpenPopup(ctx, 'popup##' .. buttonId) 
              end
              
              if reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
                  paramnumber = number
              end
            end
            --
            
            reaper.ImGui_EndGroup(ctx)
            
        end
        
        function placingOfNextElement()
            if vertical then
                reaper.ImGui_Spacing(ctx)
                --reaper.ImGui_Separator(ctx)
                --reaper.ImGui_Spacing(ctx)
            else
                reaper.ImGui_SameLine(ctx)
            end
        end
        
        --fxIndex = 3
        
        --oneData = getAllParametersFromTrackFx(track, fxIndex)
        
        --if not lastSelected then lastSelected = focusedTrackFXParametersData[1] end
        
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 5.0)
        
        local title = trackName 
        everythingsIsNotMinimized = ((allIsNotCollabsed == nil or allIsNotCollabsed) and not hidePlugins and not hideParameters and not hideModules)
        

        if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything",vertical and partsWidth or pansHeight, true,false ) then 
            hideShowEverything(everythingsIsNotMinimized)
        end
        
        
        placingOfNextElement()
        
        if not track then
            reaper.ImGui_BeginDisabled(ctx)
        end
        
        
        ImGui.BeginGroup(ctx)
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        modulatorsW = vertical and partsWidth or (winW-x-30)
        pansHeight = winH-y-30
        
        local title = "PLUGINS"
        click = false
        
        
        ImGui.BeginGroup(ctx)
        if hidePlugins then
            if modulePartButton(title .. "", not hidePlugins and "Minimize plugins" or "Maximize plugins", vertical and partsWidth or nil, true,true ) then 
                click = true
            end
        
        else
            local visible = reaper.ImGui_BeginChild(ctx, 'PluginsChilds', partsWidth, vertical and partsHeight or pansHeight-50, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY(), reaper.ImGui_WindowFlags_MenuBar() | scrollFlags)
            if visible then
                if reaper.ImGui_BeginMenuBar(ctx) then 
                     if titleButtonStyle(title, not hidePlugins and "Minimize plugins" or "Maximize plugins",vertical and partsWidth or nil, true,not vertical and hidePlugins ) then 
                         click = true
                     end
                    reaper.ImGui_EndMenuBar(ctx)
                end
                for _, f in ipairs(focsuedTrackFXNames) do 
                    if (showModulationContainer) or (not showModulationContainer and (not f.isModulator)) then
                        local name = f.name
                        if f.isContainer then name = name .. ":" end
                        if f.indent then name = string.rep("     ", f.indent) .. name end
                        local isFocused = tonumber(focusedFxNumber) == tonumber(f.number)
                        
                        if reaper.ImGui_Selectable(ctx, name .. '##' .. f.number,isFocused ,nil) then 
                           fxnumber = f.number
                           paramnumber = 0 
                           fxnumberSelectedFromScript = fxnumber
                        end
                        
                        if scrollPlugin and tonumber(f.number) == tonumber(scrollPlugin) then
                            reaper.ImGui_SetScrollHereY(ctx, 0)
                            scrollPlugin = nil
                        end
                        
                    end
                end
                ImGui.EndChild(ctx)
            end
            reaper.ImGui_Indent(ctx, margin)
            ret, follow = reaper.ImGui_Checkbox(ctx,"Open selected",follow)
            setToolTipFunc("Automatically open the selected plugin FX window")
            ret, showModulationContainer = reaper.ImGui_Checkbox(ctx,"Show Modulators",showModulationContainer) 
            setToolTipFunc("Show Modulators container in the plugin list")
            
            
        end
        if click then 
            hidePlugins = not hidePlugins  
            reaper.SetExtState(stateName, "hidePlugins", hidePlugins and "1" or "0", true)
        end
        
        ImGui.EndGroup(ctx)
        ImGui.EndGroup(ctx)
            
        placingOfNextElement()
        
        
        ------------------------
        -- PARAMETERS ----------
        ------------------------
        
        ImGui.BeginGroup(ctx) 
        if not vertical then
            --reaper.ImGui_Indent(ctx)
        end
        click = false
        title = "PARAMETERS" --.. (hideParameters and "" or (" (" .. (focusedParamNumber + 1) .. "/" .. #focusedTrackFXParametersData .. ")"))
        if hideParameters then  
            if modulePartButton(title .. "", not hideParameters and "Minimize parameters" or "Maximize parameters",vertical and partsWidth or nil, true, true ) then 
                click = true
            end
        else
                
            local visible = ImGui.BeginChild(ctx, 'Parameters', partsWidth, vertical and partsHeight or pansHeight-50, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY(),reaper.ImGui_WindowFlags_MenuBar() | scrollFlags)
            if visible then
                if reaper.ImGui_BeginMenuBar(ctx) then
                     title = "PARAMETERS" --.. (hideParameters and "" or (" (" .. (focusedParamNumber + 1) .. "/" .. #focusedTrackFXParametersData .. ")"))
                     if titleButtonStyle(title, not hideParameters and "Minimize parameters" or "Maximize parameters",vertical and partsWidth or nil, true, (not vertical and hideParameters)) then 
                         click = true
                     end
                    reaper.ImGui_EndMenuBar(ctx)
                end
                size = nil
                for _, p in ipairs(focusedTrackFXParametersData) do 
                    --if p.number == focusedParamNumber then 
                    --posX, posY = reaper.ImGui_GetCursorPos(ctx) 
                    --end
                    --if not size then startPosY = reaper.ImGui_GetCursorPosY(ctx) end
                    if not onlyMapped or (onlyMapped and p.isParameterLinkActive) then
                        if not search or search == "" or searchName(p.name, search) then
                            parameterNameAndSliders(pluginParameterName, pluginParameterSlider,p, focusedParamNumber)
                        --if not size then size = reaper.ImGui_GetCursorPosY(ctx) - startPosY end
                            reaper.ImGui_Separator(ctx)
                            if scroll and p.number == scroll then
                                ImGui.SetScrollHereY(ctx,  p.isParameterLinkActive and 0.45 or 0.3)
                                scroll = nil
                            end
                        end
                    end
                    --if p.number == focusedParamNumber then
                     --   reaper.ImGui_DrawList_AddRect(draw_list, windowPosX + posX, windowPosY+ posY, windowPosX+ posX+10, windowPosY +posY+10,colorBlue)
                    --end
                end
                
                ImGui.EndChild(ctx)
            end 
            
            local textSize = reaper.ImGui_CalcTextSize(ctx, "Search", 0,0)
            reaper.ImGui_SetNextItemWidth(ctx, moduleWidth - textSize - 10)
            ret, search = reaper.ImGui_InputText(ctx,"Search", search) 
            if ret then
                onlyMapped = false
            end
            ret, onlyMapped = reaper.ImGui_Checkbox(ctx,"Only mapped",onlyMapped)
            if ret then
                search = ""
            end 
            
        end
        if click then 
            hideParameters = not hideParameters  
            reaper.SetExtState(stateName, "hideParameters", hideParameters and "1" or "0", true) 
        end
        
        ImGui.EndGroup(ctx)
        
        placingOfNextElement()
        

        
        ImGui.BeginGroup(ctx) 
        if not vertical then
            --reaper.ImGui_Indent(ctx)
        end
        
        if hideModules then
          if modulePartButton("MODULES", not hideModules and "Minimize modules" or "Maximize modules",vertical and partsWidth or nil, true,true ) then 
              hideModules = not hideModules 
              reaper.SetExtState(stateName, "hideModules", hideModules and "1" or "0", true) 
          end 
        else
            local visible = reaper.ImGui_BeginChild(ctx, "Modules", partsWidth, vertical and partsHeight or pansHeight-50, reaper.ImGui_ChildFlags_Border() ,reaper.ImGui_WindowFlags_MenuBar() )
            if visible then
                if reaper.ImGui_BeginMenuBar(ctx) then
                     if titleButtonStyle("MODULES", not hideModules and "Minimize modules" or "Maximize modules",vertical and partsWidth or nil, true, (not vertical and hideModules)) then 
                         hideModules = not hideModules
                     end
                    reaper.ImGui_EndMenuBar(ctx)
                end
        
                if titleButtonStyle("+ LFO Native    ","Add an LFO modulator that uses the build in Reaper LFO which is sample accurate",nil) then
                    --insertLfoFxAndAddContainerMapping(track)
                    insertLocalLfoFxAndAddContainerMapping(track)
                end 
                if titleButtonStyle("+ ACS Native    ", "Add an Audio Control Signal (sidechain) modulator which uses the build in Reaper ACS") then
                    insertACSAndAddContainerMapping(track)
                end
                if titleButtonStyle("+ ADSR-1 (tilr) ", "Add an ADSR that uses the plugin created by tilr") then 
                    insertFXAndAddContainerMapping(track, "ADSR-1", "ADSR")
                end  
                if titleButtonStyle("+ MSEG-1 (tilr) ", "Add a multi-segment LFO / Envelope generator that uses the plugin created by tilr") then
                    insertFXAndAddContainerMapping(track, "MSEG-1", "MSEG")
                end 
                if titleButtonStyle("+ MIDI Fader    ", "Use a MIDI fader as a modulator") then 
                    insertFXAndAddContainerMapping(track, "MIDI Fader Modulator", "MIDI Fader")
                end 
                if titleButtonStyle("+ AB Slider     ", "Map two positions A and B of plugin parameters on the selected track. Only parameters changed will be mapped") then
                    insertFXAndAddContainerMapping(track, "AB Slider Modulator", "AB Slider")
                end
                if titleButtonStyle("+ 4-in-1-out ", "Map 4 inputs to 1 output") then
                    insertFXAndAddContainerMapping(track, "4-in-1-out", "4-in-1-out")
                end
                
            
                ImGui.EndChild(ctx)
            end 
            
            ret, sortAsType = reaper.ImGui_Checkbox(ctx,"Sort as type",sortAsType)
            if ret then
                reaper.SetExtState(stateName, "sortAsType", sortAsType and "1" or "0", true)
            end
        end
        
        
        
        ImGui.EndGroup(ctx)
        
        placingOfNextElement()
        --modulesAdd() 
        
        
        modulatorNames = getModulatorNames(track, modulationContainerPos)
        
        ImGui.BeginGroup(ctx) 
        if not vertical then
           -- reaper.ImGui_Indent(ctx)
        end
        
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        modulatorsW = vertical and partsWidth or (winW-x-30)
        --modulatorsH = winH-y-30
        local visible = ImGui.BeginChild(ctx, 'ModulatorsChilds', modulatorsW, vertical and 0 or pansHeight, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()| reaper.ImGui_ChildFlags_AutoResizeX(),reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_HorizontalScrollbar())
        --local visible = reaper.ImGui_BeginTable(ctx, 'ModulatorsChilds', vertical and 1 or #modulatorNames,nil, modulatorsW)
        if visible then
            if reaper.ImGui_BeginMenuBar(ctx) then 
                if titleButtonStyle("MODULATORS", allIsNotCollabsed and "Minimize all modulators" or "Maximize all modulators",vertical and partsWidth or nil,true,false ) then 
                    if allIsNotCollabsed then
                        for _, m in ipairs(modulatorNames) do collabsModules[m.fxIndex] = true end
                    else
                        for _, m in ipairs(modulatorNames) do collabsModules[m.fxIndex] = false end
                    end 
                    saveCollabsModulesStateOnTrack()
                    --reaper.SetProjExtState(0, stateName, "collabsModules", pickle(collabsModules))
                end
                reaper.ImGui_EndMenuBar(ctx)
            end


             --
            
            function setParameterButReturnFocus(track, fxIndex, param, value) 
                reaper.TrackFX_SetParam(track, fxIndex, param, value)
                -- focus last focused
                reaper.TrackFX_SetParam(track,fxnumber,paramnumber,reaper.TrackFX_GetParam(track,fxnumber,paramnumber))
                return value
            end
            
            
            
            ------ LFO -----------
            
            
            function fixWidth(fxIndex, startPosX)
                --mapButton(fxIndex, name)
                endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                if (not fxIndex or not collabsModules[fxIndex]) and endPosX - startPosX < moduleWidth - 17 then
                    dummyWidth = moduleWidth - (endPosX - startPosX) - 17
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
                    endPosX = startPosX + moduleWidth - 17
                end
                return endPosX, endPosY
            end
            
            
            
            function mapButton(fxIndex, name)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), map == fxIndex and colorMap or colorGrey)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorMapSemiTransparent)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), map == fxIndex and colorMap or colorGrey)
                if reaper.ImGui_Button(ctx, "MAP##" .. fxIndex, 45,45) then 
                     mapModulatorActivate(fxIndex, 0, name)
                end 
                reaper.ImGui_PopStyleColor(ctx,3)
            end
            
            
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 5.0)
            
            if modulationContainerPos then
                
                --[[
                function lfoModulatorJsfx(name, modulatorsPos, fxIndex)
                    
                    noteTempos = {"32/1","16/1","8/1","4/1","2/1","1/1","1/2","1/4","1/8","1/16","1/32"}
                    noteTemposDropdownText = ""
                    for _, t in ipairs(noteTempos) do
                        noteTemposDropdownText = noteTemposDropdownText .. t .. "\0" 
                    end
                    timeTypes = {"Hertz", "Beats","Beats (triplets)","Beats (dotted)"}
                    timeTypeDropDownText = ""
                    for _, t in ipairs(timeTypes) do
                        timeTypeDropDownText = timeTypeDropDownText .. t .. "\0" 
                    end 
                    poles = {"Positive","Centered", "Negative"}
                    polesDropDownText = ""
                    for _, t in ipairs(poles) do
                        polesDropDownText = polesDropDownText .. t .. "\0" 
                    end
                    
                    focusedShape = reaper.TrackFX_GetParam(track, fxIndex, 2)
                    local startPosX, startPosY = beginModulator(name, fxIndex)
                    
                    
                    
                    timeType = createSlider(track,fxIndex,3,"Mode",nil,nil,nil,timeTypeDropDownText,nil)
    
                    if timeType == 0 then
                        createSlider(track,fxIndex,4,"Hz",0.01,8,nil,nil,reaper.ImGui_SliderFlags_Logarithmic())
                    else  
                        createSlider(track,fxIndex,5,"Speed",nil,nil,nil,noteTemposDropdownText,nil)
                    end
                    createSlider(track,fxIndex,6,"Width",-100,100,100,nil,nil)
                    createSlider(track,fxIndex,7,"Phase",-100,100,100,nil,nil)
                    createSlider(track,fxIndex,8,"Pole",nil,nil,nil,polesDropDownText,nil)
                    createSlider(track,fxIndex,9,"Jitter",0,100,100,nil,nil)
                    if focusedShape == 1 then
                        createSlider(track,fxIndex,10,"Tilt",0,100,100,nil,nil)
                    end
                    if focusedShape == 5 then
                        createSlider(track,fxIndex,11,"Steps",2,16,1,nil,nil)
                    end 
                    if focusedShape == 6 then
                        createSlider(track,fxIndex,12,"Smooth",0,500,1,nil,nil)
                    end
                    
                    mapButton(fxIndex, name)
                    reaper.ImGui_SameLine(ctx)
                    
                    drawFaderFeedback(45, fxIndex, 1, -1, 1)
                    
                    endPosY = reaper.ImGui_GetCursorPosY(ctx)
                    ImGui.EndGroup(ctx)
                    reaper.ImGui_SameLine(ctx)
                    
                    
                    ImGui.BeginGroup(ctx) 
                    reaper.ImGui_Text(ctx,"Shape" )
                    
                    function createShapesPlots()
                        plotAmount = 99
                        local shapes = {
                          function(n) return math.sin((n)*2 * math.pi) end, -- sin
                          function(n) return n < width and -1 or (n> width and 1 or 0) end, --square
                          function(n) return (n * -2 + 1) end, -- saw L
                          function(n) return (n * 2 - 1) end, -- saw R
                          function(n) return (math.abs(n - math.floor(n + 0.5)) * 4 - 1) end, -- triangle
                          function(n) return (((steps) * (n)) // 1) / (steps-1) * 2 - 1 end, -- steps
                          function(n) return randomPoints[math.floor(n*(#randomPoints-1))+1] / 50 -1 end, -- random
                        }
                        local shapeNames = {"Sin", "Square", "Saw L", "Saw R", "Triangle", "Steps", "Random"}
                        
                        shapesPlots = {}
                        for i = 0, #shapes-1 do 
                            plots = reaper.new_array(plotAmount+1)
                            for n = 0, plotAmount do
                                plots[n+1] = shapes[i+1](n/plotAmount)
                            end
                            table.insert(shapesPlots,plots)
                        end 
                        
                        return shapesPlots, shapeNames
                    end
                    
                    buttonSizeH = 22
                    buttonSizeW = buttonSizeH * 1.5
                    
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
                    
                    if not shapesPlots then shapesPlots, shapeNames = createShapesPlots() end 
                    
                    for i, plots in ipairs(shapesPlots) do
                        local posX, posY = reaper.ImGui_GetCursorPos(ctx)
                        ImGui.SetNextItemAllowOverlap(ctx)
                        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),focusedShape == i-1 and colorBlue or semiTransparentGrey )
                        
                        ImGui.PlotLines(ctx, '', plots, 0, nil, -1.0, 1.0, buttonSizeW, buttonSizeH)
                        
                        reaper.ImGui_PopStyleColor(ctx)
                        
                        reaper.ImGui_SetCursorPos(ctx, posX, posY)
                        if reaper.ImGui_Button(ctx, "##shape" .. i .. ":" .. fxIndex, buttonSizeW,buttonSizeH) then
                            shape = i -1
                            setParameterButReturnFocus(track, fxIndex, 2, shape)
                        end
                        ImGui.SetItemTooltip(ctx, shapeNames[i])
                        
                    end  
                    reaper.ImGui_PopStyleColor(ctx,3) 
                    --reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_Spacing(ctx)
                    --reaper.ImGui_SetCursorPos(ctx, endPosX+8, endPosY)
                    
                    endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                    
                    endModulator(name, startPosX, startPosY, endPosX, endPosY, fxIndex)
                end
                ]]
                
                function createSliderForNativeLfoSettings(track,fxnumber,paramnumber,name,min,max,sliderFlag)
                    reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)
                    _, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.lfo.' .. name) 
                    ret, value = reaper.ImGui_SliderDouble(ctx, name.. '##lfo' .. name .. fxnumber, currentValue, min, max, nil, sliderFlag)
                    if ret then 
                        reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.lfo.' .. name, value) 
                    end
                end
                
                
                function createSlider2(track,fxIndex, info, currentValue, setSize) 
                    local _type = info._type
                    local paramIndex = info.paramIndex
                    local name = info.name
                    local min = info.min
                    local max = info.max
                    local divide = info.divide
                    local valueFormat = info.valueFormat
                    local sliderFlag = info.sliderFlag
                    local checkboxFlipped = info.sliderFlag
                    local dropDownText = info.dropDownText
                    local dropdownOffset = info.dropdownOffset
                    local tooltip = info.tooltip
                    
                    
                    currentValue = currentValue and currentValue or reaper.TrackFX_GetParam(track, fxIndex, paramIndex)
                    if _type == "SliderDoubleLogarithmic" then 
                        currentValue2 = reaper.TrackFX_GetParam(track, fxIndex, paramIndex)
                    end
                    
                    if currentValue then
                        --buttonTransparent(name, dropDownSize )
                        visualName = name
                        scrollValue = nil
                        if setSize then reaper.ImGui_SetNextItemWidth(ctx,setSize) end
                        if _type == "SliderInt" then 
                            ret, val = reaper.ImGui_SliderInt(ctx,visualName.. '##slider' .. name .. fxIndex, math.floor(currentValue * divide), min, max, valueFormat) 
                            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val/divide) end
                        elseif _type == "SliderDouble" then --"%d"
                            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, currentValue, min, max, valueFormat, sliderFlag)
                            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
                        elseif _type == "SliderDoubleLogarithmic" then --"%d"
                            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, math.floor(min * 2.7183^currentValue), min, max, valueFormat, sliderFlag)
                            if ret then 
                            
                            --reaper.ShowConsoleMsg(name .. " - " .. currentValue .. " - " .. currentValue2 .. " - " .. val ..  "\n")
                            setParameterButReturnFocus(track, fxIndex, paramIndex, math.log(val/min)) end
                        elseif _type == "SliderDoubleLogarithmic2" then --"%d"
                            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, (2.7183^currentValue), min, max, valueFormat, sliderFlag)
                            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, math.log(val)) end
                        elseif _type == "SliderName" then --"%d"
                            local hasSliderValueName, sliderValueName = reaper.TrackFX_FormatParamValue(track,fxIndex,paramIndex,currentValue)
                            valueFormat = hasSliderValueName and sliderValueName or valueFormat
                            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, currentValue, min, max, valueFormat, sliderFlag)
                            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
                        elseif _type == "Combo" then
                            ret, val = reaper.ImGui_Combo(ctx, visualName.. '##slider' .. name .. fxIndex, math.floor(currentValue)+dropdownOffset, dropDownText)
                            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val - dropdownOffset) end
                            scrollValue = 1
                        elseif _type == "Checkbox" then
                            ret, val = reaper.ImGui_Checkbox(ctx, visualName.. '##slider' .. name .. fxIndex, currentValue == (checkboxFlipped and 0 or 1)) 
                            if ret then   
                                val = checkboxFlipped and (val and 0 or 1) or (val and 1 or 0)
                                setParameterButReturnFocus(track, fxIndex, paramIndex, val) 
                            end
                            scrollValue = 1
                        elseif _type == "ButtonToggle" then
                            if reaper.ImGui_Button(ctx, name.. '##slider' .. name .. fxIndex,dropDownSize,buttonSizeH) then
                                setParameterButReturnFocus(track, fxIndex, paramIndex, currentValue == 1 and 0 or 1) 
                            end
                            
                        end 
                        --scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, nil, scrollValue)
                        if val == true then val = 1 end
                        if val == false then val = 0 end
                        if tooltip and showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end 
                        return ret, val
                    end
                end
                
                -- wrap slider in to mapping function
                function createSlider(track,fxIndex, _type,paramIndex,name,min,max,divide, valueFormat,sliderFlag, checkboxFlipped, dropDownText, dropdownOffset,tooltip, widthArray)  
                    local info = {_type = _type,paramIndex =paramIndex,name = name,min = min,max =max,divide=divide, valueFormat = valueFormat,sliderFlag = sliderFlag, checkboxFlipped =checkboxFlipped, dropDownText = dropDownText, dropdownOffset = dropdownOffset,tooltip =tooltip}
                    widthArray = widthArray or {faderWidth = buttonWidth}
                    if _type == "Combo" or _type == "Checkbox" or _type == "ButtonToggle" then
                        createSlider2(track,fxIndex, info,nil, buttonWidth) 
                    else  
                        parameterNameAndSliders(nil, createSlider2, getAllDataFromParameter(track,fxIndex,paramIndex), focusedParamNumber, info, widthArray) 
                    end
                end
                
                function createModulationLFOParameter(track, fxIndex,  _type, paramName, visualName, min, max, divide, valueFormat, sliderFlags, checkboxFlipped, dropDownText, dropdownOffset,tooltip) 
                    local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)
                    if ret and currentValue then 
                        scrollValue = nil
                        --reaper.ImGui_Text(ctx,visualName)
                        --visualName = ""
                        reaper.ImGui_SetNextItemWidth(ctx,buttonWidth)
                        if _type == "Checkbox" then
                            ret, newValue = reaper.ImGui_Checkbox(ctx, visualName .. "##" .. paramName .. fxIndex, currentValue == (checkboxFlipped and "0" or "1"))
                            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue and (checkboxFlipped and "0" or "1") or (not checkboxFlipped and "0" or "1")) end
                            scrollValue = 1
                        elseif _type == "SliderDouble" then 
                            ret, newValue = reaper.ImGui_SliderDouble(ctx, visualName .. '##' .. paramName .. fxIndex, currentValue*divide, min, max, valueFormat, sliderFlags)
                            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue/divide) end  
                        elseif _type == "Combo" then 
                            ret, newValue = reaper.ImGui_Combo(ctx, visualName .. '##' .. paramName .. fxIndex, tonumber(currentValue)+dropdownOffset, dropDownText )
                            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue-dropdownOffset) end
                            scrollValue = divide
                        end
                        if tooltip and showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end
                        scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, 'param.'..paramOut..'.' .. paramName, scrollValue)
                        
                    end
                    return newValue and newValue or currentValue
                end
                
                function openGui(track, fxIndex, name, gui, extraIdentifier) 
                    if gui then 
                        local _, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible' )
                        fxIsShowing = currentValue == "1"
                    else
                        fxIsShowing = reaper.TrackFX_GetOpen(track,fxIndex)
                        fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                    end
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), fxIsShowing and colorBlue or semiTransparentGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorLightGrey)
                    sizeW = collabsModules[(extraIdentifier and extraIdentifier or fxIndex)] and 20 or (moduleWidth-dropDownSize-margin*4)
                    sizeH = collabsModules[(extraIdentifier and extraIdentifier or fxIndex)] and 20 or dropDownSize/4
                    if gui then
                        title = collabsModules[fxIndex] and (fxIsShowing and "CG" or "OG") or (fxIsShowing and "Close\n Gui" or " Open\n Gui")
                    else
                        title = collabsModules[(extraIdentifier and extraIdentifier or fxIndex)] and (fxIsShowing and "CP" or "OP") or (fxIsShowing and "Close\nPlugin" or " Open\nPlugin")
                    end
                    if reaper.ImGui_Button(ctx,title .."##"..fxIndex .. (extraIdentifier and extraIdentifier or ""), sizeW,sizeH) then
                        if gui then
                            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible',fxIsShowing and 0 or 1  )
                        else
                            if fxIsShowing and fxIsFloating == nil then
                                reaper.TrackFX_SetOpen(track,fxIndex, false)
                            else
                                reaper.TrackFX_Show(track, fxIndex, fxIsShowing and 2 or 3)  
                            end
                        end
                    end 
                    if showToolTip then
                        reaper.ImGui_SetItemTooltip(ctx, "Open " .. name .. " as floating")
                    end
                    reaper.ImGui_PopStyleColor(ctx,3)
                end
                
                
                function nlfoModulator(name, modulatorsPos, fxIndex, fxInContainerIndex)
                    
                    local noteTempos = {
                        {name = "32 D", value = 48},
                        {name = "32", value = 32},
                    
                        {name = "16 D", value = 24},
                        {name = "32 T", value = 21.3333},
                        {name = "16", value = 16},
                    
                        {name = "8 D", value = 12},
                        {name = "16 T", value = 10.6667},
                        {name = "8", value = 8},
                    
                        {name = "4 D", value = 6},
                        {name = "8 T", value = 5.3333},
                        {name = "4", value = 4},
                    
                        {name = "2 D", value = 3},
                        {name = "4 T", value = 2.6667},
                        {name = "2", value = 2},
                    
                        {name = "1 D", value = 1.5},
                        {name = "2 T", value = 1.3333},
                        {name = "1", value = 1},
                    
                        {name = "1/2 D", value = 0.75},
                        {name = "1 T", value = 0.6667},
                        {name = "1/2", value = 0.5},
                    
                        {name = "1/4 D", value = 0.375},
                        {name = "1/2 T", value = 0.3333},
                        {name = "1/4", value = 0.25},
                    
                        {name = "1/8 D", value = 0.1875},
                        {name = "1/4 T", value = 0.1667},
                        {name = "1/8", value = 0.125},
                    
                        {name = "1/16 D", value = 0.09375},
                        {name = "1/8 T", value = 0.0833},
                        {name = "1/16", value = 0.0625},
                    
                        {name = "1/32 D", value = 0.046875},
                        {name = "1/16 T", value = 0.0417},
                        {name = "1/32", value = 0.03125},
                        
                        {name = "1/64 D", value = 0.0234375},
                        {name = "1/32 T", value = 0.0208},
                        {name = "1/64", value = 0.015625},
                    }
                    paramOut = "1"
                    
                    --{"32/1","16/1","8/1","4/1","2/1","1/1","1/2","1/4","1/8","1/16","1/32"}
                    noteTempoNamesToValues = {}
                    noteTemposDropdownText = ""
                    for _, t in ipairs(noteTempos) do
                        noteTemposDropdownText = noteTemposDropdownText .. t.name .. "\0" 
                    end
                    
                    timeTypes = {"Hertz", "Beats","Beats (triplets)","Beats (dotted)"}
                    timeTypeDropDownText = ""
                    for _, t in ipairs(timeTypes) do
                        timeTypeDropDownText = timeTypeDropDownText .. t .. "\0" 
                    end 
                    direction = {"Negative","Centered", "Positive"}
                    directionDropDownText = ""
                    for _, t in ipairs(direction) do
                        directionDropDownText = directionDropDownText .. t .. "\0" 
                    end
                    phaseResetDropDownText = "Free-running\0On seek/loop\0"
                    
                    
                    --| reaper.ImGui_ChildFlags_AutoResizeY()
                    
                
                        --local startPosX, startPosY = beginModulator(name, fxIndex)
                        
                        
                        function createShapesPlots()
                            plotAmount = 99
                            local shapes = {
                              function(n) return math.sin((n)*2 * math.pi) end, -- sin
                              function(n) return n < width and -1 or (n> width and 1 or 0) end, --square
                              function(n) return (n * -2 + 1) end, -- saw L
                              function(n) return (n * 2 - 1) end, -- saw R
                              function(n) return (math.abs(n - math.floor(n + 0.5)) * 4 - 1) end, -- triangle
                              function(n) return randomPoints[math.floor(n*(#randomPoints-1))+1] / 50 -1 end, -- random
                            }
                            local shapeNames = {"Sin", "Square", "Saw L", "Saw R", "Triangle", "Random"}
                            
                            shapesPlots = {}
                            for i = 0, #shapes-1 do 
                                plots = reaper.new_array(plotAmount+1)
                                for n = 0, plotAmount do
                                    plots[n+1] = shapes[i+1](n/plotAmount)
                                end
                                table.insert(shapesPlots,plots)
                            end 
                            
                            return shapesPlots, shapeNames
                        end
                        
                        function createShapes() 
                            ------------ SHAPE -----------
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
                            
                            if not shapesPlots then shapesPlots, shapeNames = createShapesPlots() end  
                            local _, focusedShape = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. "shape")  
                        
                            if not hovered then hovered = {} end
                            if not hovered[fxIndex]  then hovered[fxIndex] = {} end
                            for i, plots in ipairs(shapesPlots) do
                                --ImGui.SetNextItemAllowOverlap(ctx)
                                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),focusedShape == tostring(i-1) and colorBlue or (hovered and hovered[fxIndex][i]) and colorLightBlue or semiTransparentGrey )
                                
                                reaper.ImGui_PlotLines(ctx, '', plots, 0, nil, -1.0, 1.0, buttonSizeW, buttonSizeH)
                                reaper.ImGui_PopStyleColor(ctx)
                                
                                if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then
                                    shape = i -1
                                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. "Shape", shape) 
                                end
                                
                                hovered[fxIndex][i] = reaper.ImGui_IsItemHovered(ctx)
                                    
                                
                                ImGui.SetItemTooltip(ctx, "Set shape to: " .. shapeNames[i]) 
                                
                                if i < #shapesPlots then
                                    reaper.ImGui_SameLine(ctx)--, buttonSizeW * i) 
                                    posX, posY = reaper.ImGui_GetCursorPos(ctx)
                                    reaper.ImGui_SetCursorPos(ctx, posX-8, posY)
                                end
                            end  
                            
                            reaper.ImGui_PopStyleColor(ctx,3) 
                        end
                        
                        buttonSizeW = dropDownSize/6
                        buttonSize = 20
                        
                        
                        if collabsModules[fxIndex] and vertical then 
                            reaper.ImGui_SameLine(ctx)
                        end
                        if drawFaderFeedback(nil,nil, fxIndex, 0, 0, 1) then
                            mapModulatorActivate(fxIndex,0, fxInContainerIndex, name)
                        end 
                        
                        if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                        if not collabsModules[fxIndex] then openGui(track, fxIndex, name, true) end
                        reaper.ImGui_TableNextColumn(ctx)
                        
                        
                        if not collabsModules[fxIndex] then
                            
                            createShapes()
                            
                            --reaper.ImGui_Spacing(ctx)
                            --reaper.ImGui_Spacing(ctx)
                            --reaper.ImGui_NewLine(ctx)
                            
                            --createSlider(track,fxIndex,"SliderDouble",2,"Baseline",0,1,1,"%0.2f",nil,nil,nil)
                            --createModulationLFOParameter(track, fxIndex, "SliderDouble", "mod.baseline", "Baseline", 0, 1,1, "%0.2f") 
                            isTempoSync = createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.temposync", "Tempo sync",nil,nil,1)
                            
                        
                            local paramName = "Speed"
                            if tonumber(isTempoSync) == 0 then
                                createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.speed", "Speed",0.0039, 16,1, "%0.4f Hz", reaper.ImGui_SliderFlags_Logarithmic())
                            else  
                                -- speed drop down menu
                                reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)
                                local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName) 
                                if ret then
                                    local smallest_difference = math.huge  -- Start with a large number
                                
                                    for i, division in ipairs(noteTempos) do
                                        local difference = math.abs(division.value - currentValue)
                                        
                                        if difference < smallest_difference then
                                            smallest_difference = difference
                                            closest_index = i 
                                        end
                                    end
                                    local ret, value = reaper.ImGui_Combo(ctx, "" .. '##lfo' .. paramName .. fxIndex, closest_index - 1, noteTemposDropdownText )
                                    if ret then  
                                        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName, noteTempos[value + 1].value) 
                                    end
                                    local mouseWheelValue = reaper.ImGui_GetMouseWheel(ctx)
                                    local newScrollValue = (#noteTempos > closest_index + mouseWheelValue and 1 < closest_index + mouseWheelValue and mouseWheelValue ~= 0) and (mouseWheelValue > 0 and noteTempos[closest_index+1].value or noteTempos[closest_index-1].value) or noteTempos[closest_index].value
                                    scrollHoveredItem(track, fxIndex, paramIndex, newScrollValue, 1, 'param.'..paramOut..'.lfo.' .. paramName,1 )
                                end
                            end
                            
                            --createSlider(track,fxIndex,"SliderDouble",3,"Strength",0,100,1,"%0.1f %%",nil,nil,nil)
                            --createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.strength", "Strength", 0, 100,100, "%0.1f %%") 
                            
                            createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.phase", "Phase", 0, 1,1, "%0.2f")
                            --createSlider(track, fxIndex, "Combo", 4, "Direction", nil,nil,nil,nil,nil,nil,directionDropDownText, 1) 
                            --createModulationLFOParameter(track, fxIndex, "Combo", "lfo.dir", "Direction", nil,nil,nil,nil,nil,nil,directionDropDownText, 1) 
                            createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.free", "Seek/loop", nil,nil,1,nil,nil,true)
                            
                            
                            createSlider(track,fxIndex,"SliderDouble",2,"Offset",0,1,1,"%0.2f",nil,nil,nil)
                            createSlider(track,fxIndex,"SliderDouble",3,"Width",-1,1,1,"%0.2f",nil,nil,nil)
                            
                            
                        end
                        
                        --mapButton(fxIndex, name)
                        -- incase the module is to small
                        --[[if not collabsModules[fxIndex] and endPosX - startPosX < moduleWidth - 17 then
                            dummyWidth = moduleWidth - (endPosX - startPosX) - 17
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
                            endPosX = startPosX + moduleWidth - 17
                        end]]
                        
                        
                        --endPosX = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                        
                        --endModulator(name, startPosX, startPosY, fxIndex)
                    
                end
                
                
                
                
                function acsModulator(name, modulatorsPos, fxIndex, fxInContainerIndex) 
                    paramOut = "1"
                    direction = {"Negative","Centered", "Positive"}
                    directionDropDownText = ""
                    for _, t in ipairs(direction) do
                        directionDropDownText = directionDropDownText .. t .. "\0" 
                    end
                    
                    --local startPosX, startPosY = beginModulator(name, fxIndex)
                     
                    buttonSizeH = 22
                    buttonSizeW = buttonSizeH * 1.25
                    
                    
                    if collabsModules[fxIndex] and vertical then 
                        reaper.ImGui_SameLine(ctx)
                    end
                    if drawFaderFeedback(nil,nil, fxIndex, 0, 0, 1) then
                        mapModulatorActivate(fxIndex,0, fxInContainerIndex, name)
                    end 
                    
                    if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    
                    if not collabsModules[fxIndex] then openGui(track, fxIndex, name, true) end
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    if not collabsModules[fxIndex] then
                        
                        --createSlider(track,fxIndex,"SliderDouble",3,"Strength",0,100,1,"%0.1f %%",nil,nil,nil)
                        --createSlider(track, fxIndex, "Combo", 4, "Direction", nil,nil,nil,nil,nil,nil,directionDropDownText, 1) 
                        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "lfo.strength", "Strength", 0, 100,100, "%0.1f %%") 
                        
                        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.strength", "Strength N", 0, 100,100, "%0.2f %%")
                        createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.attack", "Attack", 0, 1000,1, "%0.0f ms")
                        createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.release", "Release", 0, 1000,1, "%0.0f ms")
                        createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.dblo", "Min Volume", -60, 12,1, "%0.2f dB")
                        createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.dbhi", "Max Volume", -60, 12,1, "%0.2f dB")
                        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.x2", "X pos", 0, 1,1, "%0.2f")
                        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.y2", "Y pos", 0, 1,1, "%0.2f")
                        
                        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.chan", "Channel", 0, 2,1, "%0.2f")
                        --createModulationLFOParameter(track, fxIndex, "SliderDouble", "acs.stereo", "Stereo", 0, 1,1, "%0.2f")
                        
                        createSlider(track,fxIndex,"SliderDouble",2,"Offset",0,1,1,"%0.2f",nil,nil,nil)  
                        createSlider(track,fxIndex,"SliderDouble",3,"Width",-1,1,1,"%0.2f",nil,nil,nil,nil)
                    end
                    
                    
                    --mapButton(fxIndex, name)
                    
                    --endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                    -- incase the module is to small
                    --[[if not collabsModules[fxIndex] and endPosX - startPosX < moduleWidth - 17 then
                        dummyWidth = moduleWidth - (endPosX - startPosX) - 17
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
                        endPosX = startPosX + moduleWidth - 17
                    end]]
                    
                    
                    --endPosX = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                    
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                function midiCCModulator(name, modulatorsPos, fxIndex, fxInContainerIndex)
                    typeDropDownText = "Select\0"
                    for i = 1, 127 do
                        typeDropDownText = typeDropDownText .. "CC" .. i .. "\0" 
                    end 
                    typeDropDownText = typeDropDownText .. "Pitchbend" .. "\0" 
                    channelDropDownText = "All\0"
                    for i = 1, 16 do
                        channelDropDownText = channelDropDownText .. "" .. i .. "\0" 
                    end 
                    
                    --local startPosX, startPosY = beginModulator(name, fxIndex)
                    local drawFaderSize = collabsModules[fxIndex] and 20 or 45
                    if collabsModules[fxIndex] and vertical then 
                        reaper.ImGui_SameLine(ctx)
                    end
                    if drawFaderFeedback(nil, nil, fxIndex,0, 0, 1) then
                        mapModulatorActivate(fxIndex, 0, fxInContainerIndex, name)
                    end 
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    if not collabsModules[fxIndex] then
                        --reaper.ImGui_NewLine(ctx)
                        createSlider(track,fxIndex,"Combo",1,"Fader",nil,nil,1,nil,nil,nil,typeDropDownText,0,"Select CC or pitchbend to control the output")
                        createSlider(track,fxIndex,"Combo",2,"Channel",nil,nil,1,nil,nil,nil,channelDropDownText,0,"Select which channel to use") 
                
                        isListening = reaper.TrackFX_GetParam(track, fxIndex, 3) == 1
                        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),isListening and colorMapLittleTransparent or colorMap )
                        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),isListening and colorMapLittleTransparent or colorMap )
                        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMap or semiTransparentGrey )
                        createSlider(track,fxIndex,"ButtonToggle",3,isListening and "Stop" or "Listen",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input") 
                        reaper.ImGui_PopStyleColor(ctx,3)
                        createSlider(track,fxIndex,"Checkbox",7,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil)
                        
                        local faderSelection = reaper.TrackFX_GetParam(track, fxIndex, 1)
                        if faderSelection > 0 then
                            createSlider(track,fxIndex,"SliderDouble",6,"Scale",-4,4,1,"%0.2f",nil,nil,nil,nil)
                            createSlider(track,fxIndex,"SliderDouble",4,"Offset",0,1,1,"%0.2f",nil,nil,nil,nil)
                            createSlider(track,fxIndex,"SliderDouble",5,"Width",-1,1,1,"%0.2f",nil,nil,nil,nil)
                        end
                    end
                    
                    
                    
                    
                    --mapButton(fxIndex, name)
                    --[[endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                    if not collabsModules[fxIndex] and endPosX - startPosX < moduleWidth - 17 then
                        dummyWidth = moduleWidth - (endPosX - startPosX) - 17
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
                        endPosX = startPosX + moduleWidth - 17
                    end]]
                    
                    --reaper.ImGui_Spacing(ctx)
                    
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                function abSliderModulator(name, modulatorsPos, fxIndex, fxInContainerIndex) 
                    --local startPosX, startPosY = beginModulator(name, fxIndex) 
                    local sliderIsMapped = parameterWithNameIsMapped(name) 
                    if not a_trackPluginStates then a_trackPluginStates = {}; b_trackPluginStates = {} end
                    local hasBothValues = a_trackPluginStates[fxIndex] and b_trackPluginStates[fxIndex]
                    local clearName = sliderIsMapped
                    
                    if collabsModules[fxIndex] and hasBothValues then 
                        if vertical then reaper.ImGui_SameLine(ctx) end
                        drawFaderFeedback(nil, nil, fxIndex,0, 0, 1)
                    elseif collabsModules[fxIndex] then
                        reaper.ImGui_InvisibleButton(ctx,"1",20,1)
                    end
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    if not collabsModules[fxIndex] then  
                        local buttonName = clearName and "Clear! Values to A" or (a_trackPluginStates[fxIndex] and "A values are saved" or "Set A values")
                        local clearType = nil 
                        
                        --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
                        if reaper.ImGui_Button(ctx, buttonName, dropDownSize) then
                            if clearName then
                                clearType = "MinValue" 
                            else 
                                if a_trackPluginStates[fxIndex] then
                                    a_trackPluginStates[fxIndex] = nil
                                else
                                    a_trackPluginStates[fxIndex] = getTrackPluginValues(track)
                                end
                            end
                            if b_trackPluginStates[fxIndex] then
                                if not comparePluginValues(a_trackPluginStates[fxIndex], b_trackPluginStates[fxIndex], track, modulationContainerPos, fxIndex) then
                                    a_trackPluginStates[fxIndex] = nil
                                    showTextField = true
                                end
                            end
                        end
                        reaper.ImGui_Spacing(ctx)
                        
                        --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
                        local buttonName = clearName and "Clear! Values to B" or (b_trackPluginStates[fxIndex] and "B values are saved" or "Set B values")
                        if reaper.ImGui_Button(ctx, buttonName, dropDownSize) then
                            if clearName then
                                clearType =  "MaxValue"
                            else  
                                if b_trackPluginStates[fxIndex] then
                                    b_trackPluginStates[fxIndex] = nil
                                else
                                    b_trackPluginStates[fxIndex] = getTrackPluginValues(track)
                                end
                            end
                            if a_trackPluginStates[fxIndex] then
                                if not comparePluginValues(a_trackPluginStates[fxIndex], b_trackPluginStates[fxIndex], track, modulationContainerPos, fxIndex) then
                                    b_trackPluginStates[fxIndex] = nil
                                    showTextField = true
                                end
                            end
                        end
                        reaper.ImGui_Spacing(ctx)
                        if showTextField then
                            if not showTextFieldTimerStart then showTextFieldTimerStart = reaper.time_precise() end
                            if reaper.time_precise() - showTextFieldTimerStart > 3 then showTextField = false; showTextFieldTimerStart = nil end
                            reaper.ImGui_Text(ctx, "Values are the same!")
                        end
                        
                        if clearName then
                        
                            if reaper.ImGui_Button(ctx, "Clear! Leave values", dropDownSize) then
                                clearType = "CurrentValue"
                            end 
                            reaper.ImGui_Spacing(ctx)
                            
                            
                            function sliderAB(track, fxIndex, info, currentValue)
                                local paramIndex = info.paramIndex
                                local min = info.min
                                local max = info.max
                                --ImGui.AlignTextToFramePadding(ctx)
                                
                                --reaper.ImGui_Text(ctx,"A")
                                --reaper.ImGui_SameLine(ctx)
                                --reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)   
                                
                                currentValue = currentValue and currentValue or reaper.TrackFX_GetParam(track, fxIndex, paramIndex)
                                --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(),4, 4)
                                ret, val = reaper.ImGui_SliderDouble(ctx,'##slider' .. name .. fxIndex,currentValue, min, max, "%0.2f", nil)
                                --reaper.ImGui_PopStyleVar(ctx)
                                if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
                                
                                --reaper.ImGui_SameLine(ctx)
                                --reaper.ImGui_Text(ctx,"B")
                            end
                            
                            --parameterNameAndSliders(nil, sliderAB, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, {paramIndex = 0, min = 0, max = 1}, ) 
                            createSlider(track,fxIndex,"SliderDouble",0,"",0,1,1,"%0.2f",nil,nil,nil,nil,nil,{faderWidth = dropDownSize, parameterMapSize = buttonWidth})
                            
                            reaper.ImGui_Spacing(ctx)
                            
                            if reaper.ImGui_Button(ctx, "Show controlled values", dropDownSize) then
                                
                            end 
                            
                            
                        end
                        
                        if clearType then
                            disableAllParameterModulationMappingsByName(name, clearType)
                            a_trackPluginStates = nil
                            b_trackPluginStates = nil
                        end
                    end
                    
                    
                    
                        
                    
                    
                    --[[endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)--reaper.ImGui_GetCursorPosX(ctx)
                    if not collabsModules[fxIndex] and endPosX - startPosX < moduleWidth - 17 then
                        dummyWidth = moduleWidth - (endPosX - startPosX) - 17
                        reaper.ImGui_SameLine(ctx)
                        reaper.ImGui_InvisibleButton(ctx,"dummy", dummyWidth,10)
                        endPosX = startPosX + moduleWidth - 17
                    end]]
                     
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                
                
                function adsrModulator(name, modulatorsPos, fxIndex, fxInContainerIndex)
                    local drawFaderSize = collabsModules[fxIndex] and 20 or 45
                    if collabsModules[fxIndex] and vertical then 
                        reaper.ImGui_SameLine(ctx)
                    end
                    if drawFaderFeedback(nil, nil, fxIndex,10, 0, 1) then
                        mapModulatorActivate(fxIndex,10, fxInContainerIndex, name)
                    end 
                    if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    if not collabsModules[fxIndex] then openGui(track, fxIndex, name, false) end
                    reaper.ImGui_TableNextColumn(ctx)
                    --local startPosX, startPosY = beginModulator(name, fxIndex)
                    
                    if not collabsModules[fxIndex] then
                        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 0)
                        local _, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 0)
                        createSlider(track,fxIndex,"SliderDouble",0,"Attack",min,max,0,math.floor(tonumber(visuelValue)) .. " ms",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",7,"A.Tension",-1,1,1,"%0.2f",nil,nil,nil,nil)
                        --createSlider(track,fxIndex,"SliderDoubleLogarithmic",1,"Decay",1,5000,0,"%0.0f ms",reaper.ImGui_SliderFlags_Logarithmic(),nil,nil,nil)
                        
                        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 1)
                        local _, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 1)
                        createSlider(track,fxIndex,"SliderDouble",1,"Decay",min,max,0,math.floor(tonumber(visuelValue)) .. " ms", nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",8,"D.Tension",-1,1,1,"%0.2f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",2,"Sustain",0,100,1,"%0.0f",nil,nil,nil,nil)
                        
                        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 3)
                        local _, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 3)
                        createSlider(track,fxIndex,"SliderDouble",3,"Release",min,max,0,math.floor(tonumber(visuelValue)) .. " ms",nil,nil,nil,nil)  
                        createSlider(track,fxIndex,"SliderDouble",9,"R.Tension",-1,1,1,"%0.2f",nil,nil,nil,nil)
                        
                        createSlider(track,fxIndex,"SliderDouble",4,"Min",0,100,1,"%0.0f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",5,"Max",0,100,1,"%0.0f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",6,"Smooth",0,100,1,"%0.0f",nil,nil,nil,nil)
                    end
                    
                    
                    --if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    
                    
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                
                
                
                function msegModulator(name, modulatorsPos, fxIndex, fxInContainerIndex)
                    
                    --local startPosX, startPosY = beginModulator(name, fxIndex)
                    
                    local drawFaderSize = collabsModules[fxIndex] and 20 or 45
                    if collabsModules[fxIndex] and vertical then 
                        reaper.ImGui_SameLine(ctx)
                    end
                    if drawFaderFeedback(nil, nil, fxIndex,10, 0, 1) then
                        mapModulatorActivate(fxIndex,10, fxInContainerIndex, name)
                    end 
                    if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    if not collabsModules[fxIndex] then openGui(track, fxIndex, name, false) end
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    
                    --reaper.ImGui_TableNextRow(ctx)
                    if not collabsModules[fxIndex] then
                        
                        local triggers = {"Sync","Free", "MIDI", "Manual"}
                        local triggersDropDownText = ""
                        for _, t in ipairs(triggers) do
                            triggersDropDownText = triggersDropDownText .. t .. "\0" 
                        end
                        
                        local tempoSync = {"Off","1/16", "1/8", "1/4", "1/2","1/1", "2/1","4/1","1/16 T", "1/8 T", "1/4 T", "1/2 T","1/1 T","1/16 D", "1/8 D", "1/4 D", "1/2 D","1/1 D"}
                        local tempoSyncDropDownText = ""
                        for _, t in ipairs(tempoSync) do
                            tempoSyncDropDownText = tempoSyncDropDownText .. t .. "\0" 
                        end
                        
                        createSlider(track,fxIndex,"SliderDouble",0,"Pattern",1,12,100,"%0.0f",nil,nil,nil,nil) 
                        createSlider(track,fxIndex,"Combo",1,"Trigger",nil,nil,1,nil,nil,nil,triggersDropDownText,0,"Select how to trigger pattern")
                        createSlider(track,fxIndex,"Combo",2,"Tempo Sync",nil,nil,1,nil,nil,nil,tempoSyncDropDownText,0,"Select if the tempo should sync")
                        
                        
                        syncOff = reaper.TrackFX_GetParam(track, fxIndex, 2) == 0 
                        if syncOff then 
                          reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)
                          local currentValue = reaper.TrackFX_GetParam(track, fxIndex, 3)
                          --if currentValue then
                          --[[ -4.6051701859881
                          -- 4.9416424226093
                              reaper.ShowConsoleMsg(currentValue .. " - " ..  (2.7183^currentValue) .. "\n")
                              ret, val= reaper.ImGui_SliderDouble(ctx,"Rate".. '##slider' .. "Rate" .. fxIndex,  (2.7183^currentValue), 0.01, 140, "%0.2f Hz", reaper.ImGui_SliderFlags_Logarithmic())
                              if ret then setParameterButReturnFocus(track, fxIndex, 3, math.log(val)) end
                              
                          end]]
                          createSlider(track,fxIndex,"SliderDoubleLogarithmic2",3,"Rate",0.01,140,1,"%0.2f Hz",reaper.ImGui_SliderFlags_Logarithmic(),nil,nil,nil)
                        end
                        
                        createSlider(track,fxIndex,"SliderDouble",4,"Phase",0,1,1,"%0.02f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",5,"Min",0,100,100,"%0.0f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",6,"Max",0,100,100,"%0.0f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",7,"Smooth",0,100,100,"%0.0f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",8,"Att. Smooth",0,100,100,"%0.0f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",9,"Rel. Smooth",0,100,100,"%0.0f",nil,nil,nil,nil)
                        
                        createSlider(track,fxIndex,"SliderDouble",13,"Retrigger",0,1,1,"%0.0f",nil,nil,nil,nil)
                        --createSlider(track,fxIndex,"SliderDouble",14,"Vel Modulation",0,1,1,"%0.2f",nil,nil,nil,nil)
                    end
                    
                    
                    --mapButton(fxIndex, name)
                    --endPosX, endPosY = fixWidth(fxIndex, startPosX)
                    
                    --reaper.ImGui_Spacing(ctx)
                    
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                
                
                
                function _4in1Out(name, modulatorsPos, fxIndex, fxInContainerIndex)
                    
                    local drawFaderSize = collabsModules[fxIndex] and 20 or 45
                    if collabsModules[fxIndex] and vertical then 
                        reaper.ImGui_SameLine(ctx)
                    end
                    if drawFaderFeedback(nil, nil, fxIndex,0, 0, 1) then
                        mapModulatorActivate(fxIndex,0, fxInContainerIndex, name)
                    end 
                    if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    --if not collabsModules[fxIndex] then openGui(track, fxIndex, name, false) end
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    --local startPosX, startPosY = beginModulator(name, fxIndex)
                    
                    if not collabsModules[fxIndex] then 
                        createSlider(track,fxIndex,"SliderDouble",1,"Input 1",0,1,1,"%0.02f",nil,nil,nil,nil) 
                        createSlider(track,fxIndex,"SliderDouble",2,"Input 2",0,1,1,"%0.02f",nil,nil,nil,nil) 
                        createSlider(track,fxIndex,"SliderDouble",3,"Input 3",0,1,1,"%0.02f",nil,nil,nil,nil) 
                        createSlider(track,fxIndex,"SliderDouble",4,"Input 4",0,1,1,"%0.02f",nil,nil,nil,nil)  
                    end
                    
                    
                end
                
                
                
                
                function genericModulator(name, modulationContainerPos, fxIndex, fxInContainerIndex)
                    
                    --local startPosX, startPosY = beginModulator(name, fxIndex)
                    
                    --if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    
                    
                    if not collabsModules[fxIndex] then
                        local buttonName = (mapGeneric and mapGeneric[fxIndex]) and " Stop\nmapping" or "Map slider\nas output"
                        if reaper.ImGui_Button(ctx,buttonName .."##" .. fxIndex, dropDownSize, dropDownSize/2) then
                            if not mapGeneric then mapGeneric = {} end
                            mapGeneric[fxIndex] = not mapGeneric[fxIndex]
                        end
                        reaper.ImGui_SameLine(ctx)
                    end
                    
                    --if collabsModules[fxIndex] and vertical then reaper.ImGui_SameLine(ctx) end
                    if not collabsModules[fxIndex] then openGui(track, fxIndex, name, false) 
                    end
                    
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    if not collabsModules[fxIndex] then
                        numParams = reaper.TrackFX_GetNumParams(track,fxIndex)
                        for p = 0, numParams -1 do
                            if mapGeneric and mapGeneric[fxIndex] then
                                reaper.ImGui_SetNextItemAllowOverlap(ctx)
                            end  
                            
                            x, y = reaper.ImGui_GetCursorPos(ctx)
                            _, paramName = reaper.TrackFX_GetParamName(track,fxIndex, p)
                            value, minVal, maxVal = reaper.TrackFX_GetParam(track,fxIndex, p) 
                            createSlider(track,fxIndex,"SliderName",p,paramName,minVal,maxVal,1,"%0.02f",nil,nil,nil,nil)
                            
                            if mapGeneric and mapGeneric[fxIndex] then
                                reaper.ImGui_SetCursorPos(ctx,x, y)
                                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMapSemiTransparent)
                                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapMoreTransparent)
                                ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorMapMoreTransparent)
                                if reaper.ImGui_Button(ctx,"##" .. p .. "-".. fxIndex, moduleWidth) then
                                    insertGenericParamFXAndAddContainerMapping(track, fxIndex, name .. " - " .. paramName .. " (Generic mapping)", p, fxInContainerIndex)
                                end 
                                reaper.ImGui_PopStyleColor(ctx,3)
                            end  
                            
                        end
                        
                        --if drawFaderFeedback(nil, nil, fxIndex,10, 0, 1) then
                        --    mapModulatorActivate(fxIndex,10, fxInContainerIndex, name)
                        --end 
                    end
                    
                    
                    if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end 
                     
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                function genericMappingModulator(name, modulationContainerPos, fxIndex, fxInContainerIndex) 
                    --local startPosX, startPosY = beginModulator(name:gsub(" %(Generic mapping%)", ""), fxIndex)
                    
                    if not collabsModules[fxIndex] and parameterLinkFxIndex ~= "" then
                        local _, mappedFxName = reaper.TrackFX_GetFXName(track, tostring(parameterLinkFxIndex)) 
                        openGui(track, parameterLinkFxIndex, mappedFxName, false, fxIndex) 
                        if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    else
                       -- reaper.TrackFX_Delete(track,fxIndex)
                    end
                    
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    if not collabsModules[fxIndex] then 
                        createSlider(track,fxIndex,"SliderDouble",2,"Offset",0,1,1,"%0.2f",nil,nil,nil,nil)
                        createSlider(track,fxIndex,"SliderDouble",3,"Width",-1,1,1,"%0.2f",nil,nil,nil,nil) 
                    end
                    
                    local drawFaderSize = collabsModules[fxIndex] and 20 or 45
                    if collabsModules[fxIndex] and vertical then 
                        reaper.ImGui_SameLine(ctx)
                    end
                    if drawFaderFeedback(nil, nil, fxIndex,0, 0, 1) then
                        mapModulatorActivate(fxIndex, 0, fxInContainerIndex, name)
                    end 
                    
                    if vertical or not collabsModules[fxIndex] then reaper.ImGui_SameLine(ctx) end
                    
                    -- find the name and fxIndex of the mapped parameter
                    local _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.. 1 ..'.plink.effect' )
                    local _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.. 1 ..'.plink.param' )
                    local _, parameterLinkFxIndex = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_item.'.. parameterLinkEffect )
                    
                    
                    
                    
                    --endModulator(name, startPosX, startPosY, fxIndex)
                end
                
                
                function partsWrapper(name)
                    local visible = reaper.ImGui_BeginChild(ctx, "Modulators", 0, 0, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeX() | reaper.ImGui_ChildFlags_AutoResizeY(),reaper.ImGui_WindowFlags_MenuBar() )
                    if visible then
                        if reaper.ImGui_BeginMenuBar(ctx) then
                            --if reaper.ImGui_BeginMenu(ctx, name) then
                             if  titleTextStyle("Modulators", "toolTipText", false, true) then
                                click = true
                             end
                             
                            --  reaper.ImGui_EndMenu(ctx)
                            --end
                            reaper.ImGui_EndMenuBar(ctx)
                        end
                    
                    
                        ImGui.EndChild(ctx)
                    end
                end
                
                function modulatorWrapper(func, name, modulationContainerPos, fxIndex, fxIndContainerIndex)
                    reaper.ImGui_BeginGroup(ctx)
                    
                    isCollabsed = collabsModules[fxIndex]
                    toolTipText = (isCollabsed and "Maximize " or "Minimize ") .. name 
                    --windowFlag = isCollabsed and reaper.ImGui_WindowFlags_NoTitleBar() or reaper.ImGui_WindowFlags_MenuBar()
                    --width = isCollabsed and 20 or moduleWidth
                    click = false 
                    height = vertical and 0 or  pansHeight-50
                    local minX, minY, maxX, maxY = false, false, false, false
                    
                    local borderColor = selectedModule == fxIndex and (map == fxIndex and colorMap or colorWhite) or colorGrey
                    
                    local flags = reaper.ImGui_TableFlags_BordersOuter()
                    flags = not isCollabsed and flags or flags | reaper.ImGui_TableFlags_NoPadOuterX() --| reaper.ImGui_TableFlags_RowBg()
                    flags = not vertical and flags | reaper.ImGui_TableFlags_ScrollY() or (flags)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderStrong(), borderColor)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), menuGrey)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableHeaderBg(), menuGrey)
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableRowBg(), menuGrey)
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableRowBgAlt(), menuGrey)
                    
                    
                    collabsOffsetY = not vertical and 20 or 0
                    collabsOffsetX = vertical and 28 or 0
                    
                    local modulatorStartPosX, modulatorStartPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                    
                    if isCollabsed then 
                        if vertical then 
                            local modulatorStartPosX, modulatorStartPosY = reaper.ImGui_GetCursorPos(ctx)
                            
                            
                            
                            if not vertical then
                                func(name, modulationContainerPos, fxIndex, fxIndContainerIndex)  
                                minX, minY = reaper.ImGui_GetItemRectMin(ctx)
                            end
                            
                            
                            
                            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),menuGreyHover)
                            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),menuGrey)
                            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),menuGrey)
                            
                            reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
                            
                            
                            reaper.ImGui_SetCursorPos(ctx, modulatorStartPosX,modulatorStartPosY+collabsOffsetY)
                            if reaper.ImGui_Button(ctx,"##bgbutton"..name..fxIndex, vertical and moduleWidth - collabsOffsetX or collabsOffsetY, vertical and 20 or height-collabsOffsetY) then 
                                click = true
                            end 
                            
                            
                            if reaper.ImGui_IsItemHovered(ctx) and showToolTip then
                                reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(toolTipText,26) )  
                            end
                            
                            
                            reaper.ImGui_PopStyleVar(ctx)
                            reaper.ImGui_PopStyleColor(ctx,3)
                             
                            
                            startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
                            endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx) 
                            maxX, maxY = endPosX, endPosY
                            
                            if vertical then 
                                func(name, modulationContainerPos, fxIndex, fxIndContainerIndex) 
                            end
                            
                            
                            if vertical then 
                                reaper.ImGui_DrawList_AddRectFilled(draw_list, startPosX, startPosY , startPosX+moduleWidth-20, endPosY, menuGrey,0)
                                reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , startPosX+moduleWidth, endPosY, colorGrey,0)
                                maxX = startPosX+moduleWidth
                            else
                                reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY-collabsOffsetY , endPosX, startPosY+height-collabsOffsetY, colorGrey,0)
                            end
                            
                            reaper.ImGui_SetCursorPos(ctx, modulatorStartPosX,modulatorStartPosY+collabsOffsetY)
                            
                            
                            --func(name, modulationContainerPos, fxIndex, fxIndContainerIndex)
                            --reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
                            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorTransparent)
                            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorTransparent)
                            --ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMap)
                            ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
                             
                            -- = name:gsub(".", "%0\n")
                            if vertical then
                                
                                reaper.ImGui_PushFont(ctx, font1)
                                if reaper.ImGui_Button(ctx,name) then
                                    click = true
                                end  
                                reaper.ImGui_PopFont(ctx)
                                reaper.ImGui_Spacing(ctx)
                                --reaper.ImGui_Text(ctx, name)
                                
                                --startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
                            else 
                                verticalButtonStyle(name, toolTipText,nil,false,false,9.5) 
                            end
                            
                            reaper.ImGui_PopStyleColor(ctx,3)
                            --reaper.ImGui_PopStyleVar(ctx)
                            foundPos = false
                        else
                            local tableWidth = isCollabsed and not vertical and 22 or moduleWidth
                            local visible = reaper.ImGui_BeginTable(ctx, name .. fxIndex,1, flags, tableWidth, vertical and 0 or -4 )
                            if visible then
                                reaper.ImGui_DrawList_AddRectFilled(draw_list, modulatorStartPosX, modulatorStartPosY , modulatorStartPosX+ winH, modulatorStartPosY+winH, menuGrey,0)
                                
                                reaper.ImGui_TableNextColumn(ctx)
                                
                                func(name, modulationContainerPos, fxIndex, fxIndContainerIndex)
                                
                                click = verticalButtonStyle(name, toolTipText, nil,false,false,9.5)
                                
                                reaper.ImGui_EndTable(ctx)
                                
                                if reaper.ImGui_IsItemClicked(ctx) then
                                    click = true
                                end
                                if reaper.ImGui_IsItemHovered(ctx) and toolTipText then
                                    --reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(toolTipText,26) )  
                                end
                            end   
                        end
                        
                        
                    else
                        --local visible = reaper.ImGui_BeginChild(ctx, name .. fxIndex, moduleWidth, height, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY(),reaper.ImGui_WindowFlags_MenuBar() | scrollFlags )
                        local tableWidth = isCollabsed and not vertical and 22 or moduleWidth
                        local visible = reaper.ImGui_BeginTable(ctx, name .. fxIndex,1, flags, tableWidth, vertical and 0 or -4 )
                        if visible then
                            reaper.ImGui_PushFont(ctx, font1)
                            reaper.ImGui_TableSetupColumn(ctx, name)
                            
                            reaper.ImGui_TableSetupScrollFreeze(ctx,1,2)
                            --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_TableAngledHeadersAngle(), 0)
                            --reaper.ImGui_TableAngledHeadersRow(ctx)
                            reaper.ImGui_TableHeadersRow(ctx)
                            reaper.ImGui_PopFont(ctx)
                            --reaper.ImGui_SameLine(ctx)
                            --if reaper.ImGui_BeginMenuBar(ctx) then
                                --clickType = titleTextStyle(name, toolTipText, moduleWidth, false)
                                clickType = lastItemClickAndTooltip(toolTipText)
                                
                                 click = false
                                  if clickType == "right" then 
                                      ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                                  elseif clickType == "left" then 
                                      click = true
                                  end
                                  
                                 --if vertical and isCollabsed then
                                    
                                  --  func(name, modulationContainerPos, fxIndex, fxIndContainerIndex)
                                --end
                               -- reaper.ImGui_EndMenuBar(ctx)
                            --end
                            --reaper.ImGui_PopStyleVar(ctx)
                            --reaper.ImGui_TableNextRow(ctx)
                            reaper.ImGui_TableNextColumn(ctx)
                            --if not isCollabsed then
                                func(name, modulationContainerPos, fxIndex, fxIndContainerIndex)
                            --end
                        end
                        
                        
                        reaper.ImGui_EndTable(ctx)
                        --reaper.ImGui_EndChild(ctx)
                        
                        
                        
                        reaper.ImGui_Spacing(ctx)
                        
                        
                    end
                    
                    reaper.ImGui_PopStyleColor(ctx,3)
                    
                    if click then
                        collabsModules[fxIndex] = not collabsModules[fxIndex] 
                        saveCollabsModulesStateOnTrack()
                        --reaper.SetProjExtState(0, stateName, "collabsModules", pickle(collabsModules))
                        selectedModule = fxIndex
                    end
                    
                    
                    if not minX then minX, minY = reaper.ImGui_GetItemRectMin(ctx) end
                    if not maxX then maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) end
                    --reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, selectedModule == fxIndex and (map == fxIndex and colorMap or colorWhite) or colorGrey,4)
                    local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
                    
                    -- module hoover
                    if mouseX >= minX and mouseX <= maxX and mouseY >= minY and mouseY <= maxY then
                        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
                            selectedModule = fxIndex
                            --ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                        end
                        if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
                            selectedModule = fxIndex
                        end
                    end
                          
                        
                    
                    if ImGui.BeginPopup(ctx, 'popup##' .. fxIndex, nil) then
                        if reaper.ImGui_Button(ctx,"Remove " .. name .."##" .. fxIndex) then
                            deleteModule(track, fxIndex, modulationContainerPos)
                            ImGui.CloseCurrentPopup(ctx)
                        end
                        if reaper.ImGui_Button(ctx,"Rename " .. name .."##" .. fxIndex) then
                            ImGui.CloseCurrentPopup(ctx)
                            openRename = true 
                        end
                        ImGui.EndPopup(ctx)
                    end 
                    
                    if openRename then
                          ImGui.OpenPopup(ctx, 'rename##' .. fxIndex) 
                          openRename = false
                    end
                    
                    if reaper.ImGui_BeginPopup(ctx, 'rename##' .. fxIndex, nil) then
                        reaper.ImGui_Text(ctx, "Rename " .. name)
                        reaper.ImGui_SetKeyboardFocusHere(ctx)
                        local ret, newName = reaper.ImGui_InputText(ctx,"##" .. fxIndex, name,nil,nil)
                        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                            renameModule(track, modulationContainerPos, fxIndex, newName)
                        end
                        ImGui.EndPopup(ctx)
                    end 
                    
                    --modulatorEndPosX, modulatorEndPosY = reaper.ImGui_GetCursorPos(ctx)
                    --reaper.ImGui_SetCursorPos(ctx, modulatorEndPosX, modulatorStartPosY)
                    --
                    reaper.ImGui_EndGroup(ctx)
                    --reaper.ImGui_SameLine(ctx)
                    --func(name, modulationContainerPos, fxIndex, fxIndContainerIndex)
                    
                    if not vertical then reaper.ImGui_SameLine(ctx) end
                end
                    
                
                
                
                if sortAsType then 
                    local modulatorsByNames = {}
                    local allNames = {}
                    local sortedNames = {}
                    for pos, m in ipairs(modulatorNames) do
                        local simpleName = m.name:match("^(.-)%d*$")
                        if not modulatorsByNames[simpleName] then modulatorsByNames[simpleName] = {} end
                        table.insert(modulatorsByNames[simpleName], m)
                        if not allNames[simpleName] then allNames[simpleName] = true; table.insert(sortedNames, simpleName) end
                    end
                    table.sort(sortedNames)
                    modulatorNames = {}
                    for _, nameType in ipairs(sortedNames) do
                        for _, m in pairs(modulatorsByNames[nameType]) do
                            table.insert(modulatorNames, m)
                        end
                    end
                end
                
                for pos, m in ipairs(modulatorNames) do
                    if m.fxName:match("LFO Native") then
                        modulatorWrapper(nlfoModulator, m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex) 
                    elseif m.fxName:match("ADSR") then
                        modulatorWrapper(adsrModulator,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    elseif m.fxName:match("MSEG") then
                        modulatorWrapper(msegModulator,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    elseif m.fxName:match("MIDI Fader Modulator") then
                        modulatorWrapper(midiCCModulator,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    elseif m.fxName:match("AB Slider") then
                        modulatorWrapper(abSliderModulator,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    elseif m.fxName:match("ACS Native") then
                        modulatorWrapper(acsModulator,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    elseif m.fxName:match("4%-in%-1%-out") then
                        modulatorWrapper(_4in1Out,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    elseif m.fxName:match("(Generic mapping)") then
                        modulatorWrapper(genericMappingModulator,m.name:gsub(" %(Generic mapping%)", ""),modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    else 
                        modulatorWrapper(genericModulator,m.name,modulationContainerPos, m.fxIndex, m.fxInContainerIndex)
                    end
                end 
                
                --end
            end
        
            reaper.ImGui_PopStyleVar(ctx)
            --reaper.ImGui_EndTable(ctx)
            ImGui.EndChild(ctx)
        end
        
        --[[
        ImGui.BeginGroup(ctx)
        reaper.ImGui_SameLine(ctx)
        
        if modulationContainerPos then
            if not vertical then
                reaper.ImGui_Indent(ctx)
            end
        end
        
        if reaper.ImGui_Button(ctx, "+ LFO Native ") then
            --insertLfoFxAndAddContainerMapping(track)
            insertLocalLfoFxAndAddContainerMapping(track)
        end
        if reaper.ImGui_Button(ctx, "+ ADSR-1 ") then 
            insertADSR1FXAndAddContainerMapping(track)
        end 
        if reaper.ImGui_Button(ctx, "+ MIDI Fader ") then
            insertMidiCCFXAndAddContainerMapping(track)
        end 
        if reaper.ImGui_Button(ctx, "+ AB Slider ") then
            insertABSliderAndAddContainerMapping(track)
        end
        
        
        
        ImGui.EndGroup(ctx)
        ]]
        reaper.ImGui_Text(ctx,"")
        ImGui.EndGroup(ctx)
        
        ImGui.PopStyleVar(ctx) 
        
        if not track then
            reaper.ImGui_EndDisabled(ctx)
        end
    --else
    --    reaper.ImGui_Text(ctx,"SELECT A TRACK OR TOUCH A TRACK PARAMETER")
    --end
    
    
    
    
    if ImGui.BeginPopup(ctx, 'popup##general', nil) then 
        ret, vertical = reaper.ImGui_Checkbox(ctx,"Vertical",vertical)
        if ret then 
            reaper.SetExtState(stateName, "vertical", vertical and "1" or "0", true)
           -- reaper.ImGui_CloseCurrentPopup(ctx) 
        end
        
        ret, showToolTip = reaper.ImGui_Checkbox(ctx,"Show tips",showToolTip)
        if ret then 
            reaper.SetExtState(stateName, "showToolTip", showToolTip and "1" or "0", true)
        end
                
        
         
        ret, trackSelectionFollowFocus = reaper.ImGui_Checkbox(ctx,"Auto select track on plugin click", trackSelectionFollowFocus)
        if ret then 
            reaper.SetExtState(stateName, "trackSelectionFollowFocus", trackSelectionFollowFocus and "1" or "0", true)
        end
        
        everythingsIsNotMinimized = (allIsNotCollabsed and not hidePlugins and not hideParameters and not hideModules)
        if reaper.ImGui_Button(ctx, (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything") then
            hideShowEverything(everythingsIsNotMinimized) 
        end
        
        ret, partsWidth = reaper.ImGui_SliderInt(ctx, "Modules width",partsWidth,100,300)
        if ret then
            if not is_docked and vertical then  
                --reaper.ImGui_SetNextWindowSize(ctx, 0, winH) 
                --last_vertical = 1
            end 
            reaper.SetExtState(stateName, "partsWidth", partsWidth, true)
        end
        ret, partsHeight = reaper.ImGui_SliderInt(ctx, "Modules height (only vertical)",partsHeight,80,550)
        if ret then
            reaper.SetExtState(stateName, "partsHeight", partsHeight, true)
        end
        
        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        ImGui.EndPopup(ctx)
    end
    
    if reaper.ImGui_IsWindowHovered(ctx) then
      --  reaper.ShowConsoleMsg(tostring(reaper.ImGui_IsAnyItemHovered(ctx)) .. "\n")
    end
    
    if reaper.ImGui_IsMouseClicked(ctx,1) and reaper.ImGui_IsWindowHovered(ctx)   then
        
        ImGui.OpenPopup(ctx, 'popup##general') 
    end
    
    ImGui.End(ctx)
  end
  
  reaper.ImGui_PopFont(ctx)
  
  if (reaper.ImGui_IsKeyDown(ctx,reaper.ImGui_Mod_Super()) and  reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Backspace())) or reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Delete()) then
      deleteModule(track, selectedModule, modulationContainerPos)
  end
  
  if isAltPressed and reaper.ImGui_IsKeyDown(ctx,reaper.ImGui_Key_M()) then
     -- open = false
  end
  
  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
     if map then 
        map = false
     end
     
  end 
  
  --------------- KEY COMMANDS ----------------
  
  local time = reaper.time_precise()
  local newKeyPressed = checkKeyPress()  
  if not newKeyPressed then lastKeyPressedTime = nil; lastKeyPressedTimeInitial = nil end
  if not lastKeyPressed or lastKeyPressed ~= newKeyPressed then 
      for _, info in ipairs(keyCommandSettings) do 
          local name = info.name
          for _, command in ipairs(info.commands) do
              if command == newKeyPressed then
                  if name == "Close" then 
                      open = false
                  elseif name == "Undo" then
                      reaper.Main_OnCommand(40029, 0) --Edit: Undo
                  elseif name == "Redo" then
                      reaper.Main_OnCommand(40030, 0) --Edit: Redo    
                  end  
              end 
          end
      end 
      
      lastKeyPressed = newKeyPressed
      lastKeyPressedTimeInitial = lastKeyPressedTimeInitial and lastKeyPressedTimeInitial or time
  else
      -- hardcoded repeat values
      if lastKeyPressedTimeInitial and time - lastKeyPressedTimeInitial > 0.5 then
          if lastKeyPressedTime and time - lastKeyPressedTime > 0.2 then 
              lastKeyPressed = nil
          else 
              lastKeyPressed = nil
          end 
          lastKeyPressedTime = time 
      end
  end
  
  ----------------------
  -- toolbar settings --
  ----------------------
  if not toolbarSet then 
      setToolbarState(true) 
      toolbarSet = true
  end
  reaper.atexit(exit)
  ---------------
  -- FINISHED ---
  ---------------
  
  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
