-- @noindex
--local os_separator = package.config:sub(1, 1)
--package.path = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]] .. "?.lua;"  -- GET DIRECTORY FOR REQUIRE
--require("Sexan_FX_Browser_ParserV7")

local fx_parser_list_filepath = reaper.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
local fx_parser_list_exist
if reaper.file_exists(fx_parser_list_filepath) then
    dofile(fx_parser_list_filepath)
    --fx_parser_list = require("fx_parser_list")
else    
    return false
end

local r = reaper
local ctx, TRACK, fxIndex --= r.ImGui_CreateContext('FX INI PARSER')

-- USE ONLY NON CHACHING OR CACHING! NOT BOTH AT THE SAME TIME

--NON CACHING -- USE IF YOU WANT RESCAN ON EVERY SCRIPT STARTUP
--local FX_LIST_TEST, CAT_TEST = GetFXTbl()

--CACHIN TO FILE - USE IF YOU WANT TO SCAN ONLY ONCE THEN USE THAT TXT FILE FOR FASTER LOADS
local FX_LIST_TEST, CAT_TEST = ReadFXFile()
if not FX_LIST_TEST or not CAT_TEST then
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
end
--CACHIN TO FILE

local function Lead_Trim_ws(s) return s:match '^%s*(.*)' end

local tsort = table.sort
function SortTable(tab, val1, val2)
    tsort(tab, function(a, b)
        if (a[val1] < b[val1]) then
            -- primary sort on position -> a before b
            return true
        elseif (a[val1] > b[val1]) then
            -- primary sort on position -> b before a
            return false
        else
            -- primary sort tied, resolve w secondary sort on rank
            return a[val2] < b[val2]
        end
    end)
end

local old_t = {}
local old_filter = ""
local function Filter_actions(filter_text)
    if old_filter == filter_text then return old_t end
    filter_text = Lead_Trim_ws(filter_text)
    local t = {}
    if filter_text == "" or not filter_text then return t end
    for i = 1, #FX_LIST_TEST do
        local name = FX_LIST_TEST[i]:lower()  --:gsub("(%S+:)", "")
        local found = true
        for word in filter_text:gmatch("%S+") do
            if not name:find(word:lower(), 1, true) then
                found = false
                break
            end
        end
        if found then t[#t + 1] = { score = FX_LIST_TEST[i]:len() - filter_text:len(), name = FX_LIST_TEST[i] } end
    end
    if #t >= 2 then
        SortTable(t, "score", "name")  -- Sort by key priority
    end
    old_t = t
    old_filter = filter_text
    return t
end

local function SetMinMax(Input, Min, Max)
    if Input >= Max then
        Input = Max
    elseif Input <= Min then
        Input = Min
    else
        Input = Input
    end
    return Input
end

local FILTER = ''
local function FilterBox()
    local MAX_FX_SIZE = 300
    r.ImGui_PushItemWidth(ctx, MAX_FX_SIZE)
    if r.ImGui_IsWindowAppearing(ctx) then r.ImGui_SetKeyboardFocusHere(ctx) end
    _, FILTER = r.ImGui_InputTextWithHint(ctx, '##input', "SEARCH FX", FILTER)
    local filtered_fx = Filter_actions(FILTER)
    local filter_h = #filtered_fx == 0 and 0 or (#filtered_fx > 40 and 20 * 17 or (17 * #filtered_fx))
    ADDFX_Sel_Entry = SetMinMax(ADDFX_Sel_Entry or 1, 1, #filtered_fx)
    if #filtered_fx ~= 0 then
        if r.ImGui_BeginChild(ctx, "##popupp", MAX_FX_SIZE, filter_h) then
            for i = 1, #filtered_fx do
                if r.ImGui_Selectable(ctx, filtered_fx[i].name, i == ADDFX_Sel_Entry) then
                    r.TrackFX_AddByName(TRACK, filtered_fx[i].name, false, fxIndex)
                    r.ImGui_CloseCurrentPopup(ctx)
                    LAST_USED_FX = filtered_fx[i].name
                end
            end
            r.ImGui_EndChild(ctx)
        end
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
            r.TrackFX_AddByName(TRACK, filtered_fx[ADDFX_Sel_Entry].name, false, fxIndex)
            LAST_USED_FX = filtered_fx[filtered_fx[ADDFX_Sel_Entry].name]
            ADDFX_Sel_Entry = nil
            FILTER = ''
            r.ImGui_CloseCurrentPopup(ctx)
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) then
            ADDFX_Sel_Entry = ADDFX_Sel_Entry - 1
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) then
            ADDFX_Sel_Entry = ADDFX_Sel_Entry + 1
        end
    end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        FILTER = ''
        r.ImGui_CloseCurrentPopup(ctx)
    end
    return #filtered_fx ~= 0
end

local function DrawFxChains(tbl, path)
    local extension = ".RfxChain"
    path = path or ""
    for i = 1, #tbl do
        if tbl[i].dir then
            if r.ImGui_BeginMenu(ctx, tbl[i].dir) then
                DrawFxChains(tbl[i], table.concat({ path, os_separator, tbl[i].dir }))
                r.ImGui_EndMenu(ctx)
            end
        end
        if type(tbl[i]) ~= "table" then
            if r.ImGui_Selectable(ctx, tbl[i]) then
                if TRACK then
                    r.TrackFX_AddByName(TRACK, table.concat({ path, os_separator, tbl[i], extension }), false,
                        fxIndex)
                end
            end
        end
    end
end

local function LoadTemplate(template, replace)
    local track_template_path = r.GetResourcePath() .. "/TrackTemplates" .. template
    if replace then
        local chunk = GetFileContext(track_template_path)
        r.SetTrackStateChunk(TRACK, chunk, true)
    else
        r.Main_openProject(track_template_path)
    end
end

local function DrawTrackTemplates(tbl, path)
    local extension = ".RTrackTemplate"
    path = path or ""
    for i = 1, #tbl do
        if tbl[i].dir then
            if r.ImGui_BeginMenu(ctx, tbl[i].dir) then
                local cur_path = table.concat({ path, os_separator, tbl[i].dir })
                DrawTrackTemplates(tbl[i], cur_path)
                r.ImGui_EndMenu(ctx)
            end
        end
        if type(tbl[i]) ~= "table" then
            if r.ImGui_Selectable(ctx, tbl[i]) then
                if TRACK then
                    local template_str = table.concat({ path, os_separator, tbl[i], extension })
                    LoadTemplate(template_str)        -- ADD NEW TRACK FROM TEMPLATE
                    LoadTemplate(template_str, true)  -- REPLACE CURRENT TRACK WITH TEMPLATE
                end
            end
        end
    end
end

local function DrawItems(tbl, main_cat_name)
    for i = 1, #tbl do
        if r.ImGui_BeginMenu(ctx, tbl[i].name) then  --
            for j = 1, #tbl[i].fx do
                if tbl[i].fx[j] then
                    local name = tbl[i].fx[j]
                    if main_cat_name == "ALL PLUGINS" and tbl[i].name ~= "INSTRUMENTS" then
                        -- STRIP PREFIX IN "ALL PLUGINS" CATEGORIES EXCEPT INSTRUMENT WHERE THERE CAN BE MIXED ONES
                        name = name:gsub("^(%S+:)", "")
                    elseif main_cat_name == "DEVELOPER" then
                        -- STRIP SUFFIX (DEVELOPER) FROM THESE CATEGORIES
                        name = name:gsub(' %(' .. Literalize(tbl[i].name) .. '%)', "")
                    end
                    if r.ImGui_Selectable(ctx, name) then
                        if TRACK then
                            if name:find(".RfxChain") then
                                r.TrackFX_AddByName(TRACK, table.concat({ os_separator, tbl[i].fx[j] }), false,
                                    fxIndex)
                            else
                                r.TrackFX_AddByName(TRACK, tbl[i].fx[j], false,
                                    fxIndex)
                            end
                            LAST_USED_FX = tbl[i].fx[j]
                        end
                    end
                end
            end
            r.ImGui_EndMenu(ctx)
        end
    end
end
local function prettifyString(str)
    -- Step 1: Insert space before capital letter, unless preceded by another capital
      local newStr = str:lower():gsub("^%s*(%l)", string.upper)
      if str:sub(0,2) == "FX" then
        newStr = "FX" .. newStr:sub(3)
      end
      return newStr
  end
  
function Frame()
    local search = FilterBox()
    if search then return end
    for i = 1, #CAT_TEST do
        if r.ImGui_BeginMenu(ctx, prettifyString(CAT_TEST[i].name)) then
            if CAT_TEST[i].name == "FX CHAINS" then
                DrawFxChains(CAT_TEST[i].list)
            elseif CAT_TEST[i].name == "TRACK TEMPLATES" then
                DrawTrackTemplates(CAT_TEST[i].list)
            else
                DrawItems(CAT_TEST[i].list, CAT_TEST[i].name)
            end
            r.ImGui_EndMenu(ctx)
        end
    end
    --[[
    if r.ImGui_Selectable(ctx, "Container") then
        r.TrackFX_AddByName(TRACK, "Container", false,
            -1000 - r.TrackFX_GetCount(TRACK))
        LAST_USED_FX = "Container"
    end
    if r.ImGui_Selectable(ctx, "Video processor") then
        r.TrackFX_AddByName(TRACK, "Video processor", false,
            -1000 - r.TrackFX_GetCount(TRACK))
        LAST_USED_FX = "Video processor"
    end
    ]]
    if LAST_USED_FX then
        if r.ImGui_Selectable(ctx, "Recent: " .. LAST_USED_FX) then
            r.TrackFX_AddByName(TRACK, LAST_USED_FX, false,
            fxIndex)
        end
    end
end

local fx_parser_list = {}
function fx_parser_list.Main(ctxFromOutside, trackFromOutside, fxIndexFromOutside, textColorRescan)
    ctx = ctxFromOutside
    TRACK = trackFromOutside
    fxIndex = fxIndexFromOutside
    --UPDATE FX CHAINS (WE DONT NEED TO RESCAN EVERYTHING IF NEW CHAIN WAS CREATED BY SCRIPT)
    if WANT_REFRESH then
        WANT_REFRESH = nil
        UpdateChainsTrackTemplates(CAT)
    end
    Frame()            
    -- RESCAN FILE LIST
                            
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColorRescan)
    if r.ImGui_Button(ctx, "[Rescan plugin list]") then
        FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    end                            
    reaper.ImGui_PopStyleColor(ctx,1)
end
return fx_parser_list
