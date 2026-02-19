-- ============================================================
--  Reabank → Lua Table Converter  (multi-bank support)
--
--  Returns an ARRAY of instrument tables. Each entry:
--  {
--    mapName   = "...",
--    Vendor    = "...",
--    Product   = "...",
--    Info      = "...",   -- optional, from bank-level m=
--    tableInfo = { ... }  -- articulation entries
--  }
--
--  Usage inside REAPER:
--    dofile(reaper.GetResourcePath() .. "/Scripts/reabank_converter.lua")
--    local banks = ConvertReabank("/path/to/file.reabank")
--    for i, bank in ipairs(banks) do
--      reaper.ShowConsoleMsg("Bank " .. i .. ": " .. bank.mapName .. "\n")
--      reaper.ShowConsoleMsg(SerializeTable(bank) .. "\n")
--    end
--
--  Standalone:  lua reabank_converter.lua myfile.reabank
-- ============================================================

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function split(s, delim)
  local result = {}
  for part in s:gmatch("([^" .. delim .. "]+)") do
    result[#result + 1] = part
  end
  return result
end

-- Parse a //! line into a flat key=value table.
-- Handles  key=value,  key="quoted value",  and bare boolean keys.
local function parseAnnotation(line)
  line = line:match("^//!%s*(.-)%s*$") or ""
  local attrs = {}
  local i = 1
  while i <= #line do
    while i <= #line and line:sub(i,i):match("%s") do i = i + 1 end
    if i > #line then break end

    -- read key
    local keyStart = i
    while i <= #line and line:sub(i,i) ~= "=" and not line:sub(i,i):match("%s") do
      i = i + 1
    end
    local key = line:sub(keyStart, i - 1)
    if key == "" then i = i + 1 goto continue end

    if line:sub(i,i) ~= "=" then
      attrs[key] = true
      goto continue
    end
    i = i + 1  -- skip '='

    local value
    if line:sub(i,i) == '"' then
      i = i + 1
      local valStart = i
      while i <= #line and line:sub(i,i) ~= '"' do i = i + 1 end
      value = line:sub(valStart, i - 1)
      i = i + 1
    else
      local valStart = i
      while i <= #line and not line:sub(i,i):match("%s") do i = i + 1 end
      value = line:sub(valStart, i - 1)
    end

    attrs[key] = value
    ::continue::
  end
  return attrs
end

-- Parse o= output events string and write result keys into entry.
local function parseOutputEvents(oStr, entry)
  local noteCount = 0
  for _, ev in ipairs(split(oStr, "/")) do
    ev = ev:gsub("^%-", "")       -- strip leading '-' (non-routing prefix)
    ev = ev:gsub("%%[^/]*$", "")  -- strip %filter_program suffix
    ev = ev:gsub("@[^:]*", "")    -- strip @channel[.bus]

    local evType, argStr = ev:match("^([^:]+):?(.*)$")
    evType = evType and trim(evType) or ""
    argStr = argStr and trim(argStr) or ""

    local arg1, arg2
    if argStr ~= "" then
      local parts = split(argStr, ",")
      arg1 = tonumber(parts[1])
      arg2 = tonumber(parts[2])
    end

    if evType == "cc" then
      if arg1 then entry["CC" .. arg1] = arg2 end

    elseif evType == "note" then
      noteCount = noteCount + 1
      local key = "Note" .. noteCount
      entry[key] = arg1
      if arg2 then entry[key .. "Velocity"] = arg2 end

    elseif evType == "note-hold" then
      noteCount = noteCount + 1
      local key = "Note" .. noteCount
      entry[key]           = arg1
      entry[key .. "Held"] = true
      if arg2 then entry[key .. "Velocity"] = arg2 end

    elseif evType == "pitch" then
      entry["Pitchbend"] = arg1

    elseif evType == "art" then
      entry["Art"] = arg1

    elseif evType == "program" then
      entry["Program"] = arg1
    end
    -- @channel-only routing (evType == "") → silently ignored
  end
end

-- Build a fresh bank table from accumulated bank-level //! attrs.
local function makeBankTable(bankAttrs, bankLineName)
  local bank = { tableInfo = {} }

  -- mapName: n= overrides the name on the Bank line
  bank.mapName = bankAttrs["n"] or bankLineName

  -- Vendor / Product from g="Vendor/Product"
  if bankAttrs["g"] then
    local parts = split(bankAttrs["g"], "/")
    bank.Vendor  = parts[1] or ""
    bank.Product = parts[2] or ""
  else
    bank.Vendor  = ""
    bank.Product = ""
  end

  if bankAttrs["m"] then bank.Info = bankAttrs["m"] end

  return bank
end

--------------------------------------------------------------------------------
-- Main converter — returns an ARRAY of bank tables
--------------------------------------------------------------------------------

function ConvertReabank(filePath)
  local file, err = io.open(filePath, "r")
  if not file then error("Could not open file: " .. tostring(err)) end
  local lines = {}
  for line in file:lines() do lines[#lines + 1] = line end
  file:close()

  local banks        = {}   -- result array
  local currentBank  = nil  -- bank table currently being filled
  local pendingAttrs = {}   -- //! attrs waiting for their target line

  local function flushPending()
    local a = pendingAttrs
    pendingAttrs = {}
    return a
  end

  for _, rawLine in ipairs(lines) do
    local line = trim(rawLine)

    -- Blank lines are fine between articulations; leave pending attrs intact
    if line == "" then goto continue end

    -- Plain comments (not annotations)
    if line:match("^//[^!]") or line == "//" then goto continue end

    -- Annotation line — merge into pending
    if line:match("^//!") then
      local attrs = parseAnnotation(line)
      for k, v in pairs(attrs) do pendingAttrs[k] = v end
      goto continue
    end

    -- Bank declaration — starts a new instrument
    if line:match("^Bank%s") then
      local bankAttrs    = flushPending()
      local bankLineName = line:match("^Bank%s+%S+%s+%S+%s+(.+)$") or ""
      currentBank        = makeBankTable(bankAttrs, bankLineName)
      banks[#banks + 1]  = currentBank
      goto continue
    end

    -- Program (articulation) line
    if currentBank then
      local id, title = line:match("^(%d+)%s+(.+)$")
      if id and title then
        local attrs = flushPending()
        local entry = {
          Id    = tonumber(id),
          Title = trim(title),
        }

        if attrs["i"]         then entry["Icon"]      = attrs["i"]                   end
        if attrs["n"]         then entry["UIText"]    = attrs["n"]                   end
        if attrs["c"]         then entry["Color"]     = attrs["c"]                   end
        if attrs["g"]         then entry["Layer"]     = tonumber(attrs["g"])          end
        if attrs["m"]         then entry["Info"]      = attrs["m"]                   end
        if attrs["transpose"] then entry["Transpose"] = tonumber(attrs["transpose"])  end
        if attrs["velocity"]  then entry["Velocity"]  = tonumber(attrs["velocity"])   end

        if attrs["pitchrange"] then
          local lo, hi = attrs["pitchrange"]:match("^(%d+)-(%d+)$")
          if lo then
            entry["Pitch"]     = tonumber(lo)
            entry["Pitch2"]    = tonumber(hi)
            entry["PitchType"] = "Inside"
          end
        end

        if attrs["velrange"] then
          local lo, hi = attrs["velrange"]:match("^(%d+)-(%d+)$")
          if lo then
            entry["Velocity"]     = tonumber(lo)
            entry["Velocity2"]    = tonumber(hi)
            entry["VelocityType"] = "Inside"
          end
        end

        if attrs["o"] then parseOutputEvents(attrs["o"], entry) end

        currentBank.tableInfo[#currentBank.tableInfo + 1] = entry
      end
    end

    ::continue::
  end

  return banks
end

--------------------------------------------------------------------------------
-- Pretty-printer
--------------------------------------------------------------------------------

function SerializeTable(tbl, indent)
  indent = indent or 0
  local pad   = string.rep("  ", indent)
  local out   = { "{" }
  for k, v in pairs(tbl) do
    local keyStr = type(k) == "string" and (k .. " = ") or ("[" .. k .. "] = ")
    if type(v) == "table" then
      out[#out + 1] = pad .. "  " .. keyStr .. SerializeTable(v, indent + 1) .. ","
    elseif type(v) == "string" then
      out[#out + 1] = pad .. "  " .. keyStr .. string.format("%q", v) .. ","
    else
      out[#out + 1] = pad .. "  " .. keyStr .. tostring(v) .. ","
    end
  end
  out[#out + 1] = pad .. "}"
  return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
-- REAPER usage example (uncomment and adapt path):
--------------------------------------------------------------------------------

local banks = ConvertReabank("/Users/jesperankarfeldt/Downloads/reaticulate-master/banks/70-01-Cinematic_Series-Cinematic_Studio_Strings.reabank")
for i, bank in ipairs(banks) do
  reaper.ShowConsoleMsg("=== [" .. i .. "] " .. bank.mapName .. " ===\n")
  reaper.ShowConsoleMsg(SerializeTable(bank) .. "\n\n")
end

--[[
--------------------------------------------------------------------------------
-- Standalone entry point:  lua reabank_converter.lua myfile.reabank
--------------------------------------------------------------------------------
if arg and arg[1] then
  local ok, res = pcall(ConvertReabank, arg[1])
  if ok then
    print("-- " .. #res .. " bank(s) found\n")
    for i, bank in ipairs(res) do
      print("-- [" .. i .. "] " .. bank.mapName)
      print(SerializeTable(bank))
      print()
    end
  else
    print("ERROR: " .. res)
  end
end
]]
