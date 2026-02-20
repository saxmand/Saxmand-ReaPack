-- @noindex

-- ============================================================
--  Reabank → Lua Table Converter  (multi-bank support)
--
--  Returns an ARRAY of instrument tables. Each entry:
--  {
--    mapName            = "...",
--    instrumentSettings = {
--      Vendor   = "...",
--      Product  = "...",
--      Patch    = "...",
--      Info     = "...",    -- from bank-level m=
--      Creator  = "...",    -- from "Creator/CREATOR:" header comment
--      Source   = "...",    -- from "Source:" header comment
--      Notes    = "...",    -- from "Note/Notes/NOTE/NOTES:" header comments (joined)
--      From     = "reabank"
--    },
--    tableInfo = { ... }    -- articulation entries
--  }
--
--  Usage inside REAPER:
--    local conv  = dofile(reaper.GetResourcePath() .. "/Scripts/reabank_converter.lua")
--    local banks = conv.ConvertReabank("/path/to/file.reabank")
--    for i, bank in ipairs(banks) do
--      reaper.ShowConsoleMsg(bank.mapName .. "\n")
--    end
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
local function parseAnnotation(line)
  line = line:match("^//!%s*(.-)%s*$") or ""
  local attrs = {}
  local i = 1
  while i <= #line do
    while i <= #line and line:sub(i,i):match("%s") do i = i + 1 end
    if i > #line then break end

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
    i = i + 1

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
    ev = ev:gsub("^%-", "")
    ev = ev:gsub("%%[^/]*$", "")
    ev = ev:gsub("@[^:]*", "")

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
  end
end

-- Append a note sentence to an existing notes string.
local function appendNote(existing, newText)
  newText = trim(newText)
  if newText == "" then return existing end
  if existing == "" then return newText end
  return existing .. ".\n" .. newText
end

-- Build a fresh bank table from accumulated pending state.
local function makeBankTable(bankAttrs, headerMeta, bankLineName)
  local bank = {
    mapName            = "",
    instrumentSettings = {},
    tableInfo          = {},
  }
  for k, v in pairs(require("default_settings").InstrumentSettings) do
      bank.instrumentSettings[k] = v
  end
  instrumentSettings.ConvertedFrom = "reabank"

  bank.mapName = bankAttrs["n"] or bankLineName

  --local s = bank.instrumentSettings

  if bankAttrs["g"] then
    local parts = split(bankAttrs["g"], "/")
    bank.instrumentSettings.Vendor  = parts[1] or ""
    bank.instrumentSettings.Product = parts[2] or bankLineName
  else
    bank.instrumentSettings.Vendor  = ""
    bank.instrumentSettings.Product = ""
  end

  bank.instrumentSettings.Patch = bankAttrs["n"] or bankLineName

  if bankAttrs["m"] then bank.instrumentSettings.Info = bankAttrs["m"] end

  if headerMeta.Creator ~= "" then bank.instrumentSettings.Creator = headerMeta.Creator end
  if headerMeta.Source  ~= "" then bank.instrumentSettings.Source  = headerMeta.Source  end
  if headerMeta.Notes   ~= "" then bank.instrumentSettings.Notes   = headerMeta.Notes   end

  return bank
end

--------------------------------------------------------------------------------
-- Main converter
--------------------------------------------------------------------------------

local export = {}

function export.ConvertReabank(filePath)
  local file, err = io.open(filePath, "r")
  if not file then error("Could not open file: " .. tostring(err)) end
  local lines = {}
  for line in file:lines() do lines[#lines + 1] = line end
  file:close()

  local banks        = {}
  local currentBank  = nil
  local pendingAttrs = {}
  local headerMeta   = { Creator = "", Source = "", Notes = "" }

  local function flushPending()
    local a, h = pendingAttrs, headerMeta
    pendingAttrs = {}
    headerMeta   = { Creator = "", Source = "", Notes = "" }
    return a, h
  end

  local function tryParseHeaderComment(raw)
    -- Strip the leading "//" to get the comment content
    local content = raw:match("^//%s*(.-)%s*$")
    if not content then return end

    -- Separator line (//-----) resets the header accumulator for a clean block
    if content:match("^%-%-%-") then
      headerMeta = { Creator = "", Source = "", Notes = "" }
      return
    end

    -- Creator / CREATOR:
    local val = content:match("^[Cc][Rr][Ee][Aa][Tt][Oo][Rr]%s*:%s*(.+)$")
    if val then headerMeta.Creator = trim(val) ; return end

    -- Source:
    val = content:match("^[Ss][Oo][Uu][Rr][Cc][Ee]%s*:%s*(.+)$")
    if val then headerMeta.Source = trim(val) ; return end

    -- Note / Notes / NOTE / NOTES:
    val = content:match("^[Nn][Oo][Tt][Ee][Ss]?%s*:%s*(.+)$")
    if val then headerMeta.Notes = appendNote(headerMeta.Notes, val) ; return end
  end

  for _, rawLine in ipairs(lines) do
    local line = trim(rawLine)

    if line == "" then goto continue end

    -- Annotation line (//!)
    if line:match("^//!") then
      local attrs = parseAnnotation(line)
      for k, v in pairs(attrs) do pendingAttrs[k] = v end
      goto continue
    end

    -- Plain comment line (//)
    if line:match("^//") then
      tryParseHeaderComment(line)
      goto continue
    end

    -- Bank declaration — start a new instrument
    if line:match("^Bank%s") then
      local bankAttrs, hMeta = flushPending()
      local bankLineName     = line:match("^Bank%s+%S+%s+%S+%s+(.+)$") or ""
      currentBank            = makeBankTable(bankAttrs, hMeta, bankLineName)
      --banks[#banks + 1]      = currentBank
      table.insert(banks, currentBank)
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

        table.insert(currentBank.tableInfo, entry)
        --currentBank.tableInfo[#currentBank.tableInfo + 1] = entry
      end
    end

    ::continue::
  end

  return banks
end

return export

--[[
--------------------------------------------------------------------------------
-- Pretty-printer (useful for debugging in the REAPER console)
--------------------------------------------------------------------------------

local function SerializeTable(tbl, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local out = { "{" }
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

-- REAPER usage example:
local conv  = dofile(reaper.GetResourcePath() .. "/Scripts/reabank_converter.lua")
local banks = conv.ConvertReabank("/path/to/file.reabank")
for i, bank in ipairs(banks) do
  reaper.ShowConsoleMsg("=== [" .. i .. "] " .. bank.mapName .. " ===\n")
  reaper.ShowConsoleMsg(SerializeTable(bank) .. "\n\n")
end
--]]