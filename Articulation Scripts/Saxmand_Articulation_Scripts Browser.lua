-- @noindex

local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()

seperator = package.config:sub(1, 1) -- path separator: '/' on Unix, '\\' on Windows
scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
scriptPathSubfolder = scriptPath .. "Functions" .. seperator

local functionsFilePath = ""
local functionsFileExtension = ""
local devMode = scriptPath:match("jesperankarfeldt") ~= nil
if devMode then
    local devFilesPath = reaper.GetResourcePath() .. "/Scripts/Saxmand-ReaPack-Private/Articulation Scripts/Functions/"
    package.path = package.path .. ";" .. devFilesPath .. "?.lua"
else
    package.path = package.path .. ";" .. scriptPathSubfolder .. "?.dat"
end
package.path = package.path .. ";" .. scriptPathSubfolder .. "?.lua"
package.path = package.path .. ";" .. scriptPathSubfolder .. "Helpers" .. seperator .. "?.lua"


local ctx = reaper.ImGui_CreateContext('Articulation_Script_Browser')

local addMapToInstruments = require("add_script_to_instrument").addMapToInstruments
local modern_ui = require("modern_ui")

-- Load pathes
require("pathes")
-- load list of articulation scripts
local get_articulation_scripts = require("get_articulation_scripts").get_articulation_scripts
local articulation_scripts_list = get_articulation_scripts(articulationScriptsPath)
local file_handling = require("file_handling")
local mapping_handling = require("mapping_handling")
local midi_note_names = require("midi_note_names")
json = require("json")
local export = require("export")
require("imgui_colors")
local articulation_scripts_library = require("articulation_scripts_library")
local listOverviewSurface = require("list_overview")
local export = require("export")

track_depending_on_selection = require("track_depending_on_selection")
default_settings = require("default_settings")

appSettings = default_settings.getAppSettings()
saveAppSettings = default_settings.saveAppSettings



local columnsToNotUseLanes = mapping_handling.columnsToNotUseLanes()

local articulation_scripts_list_currentVersion = {}

local function date_string_to_seconds(str)
    local year, month, day, hour, min, sec = str:match("(%d+)%.(%d+)%.(%d+) (%d+):(%d+):(%d+)")
    if not year then return nil end
    return os.time({
        year  = tonumber(year),
        month = tonumber(month),
        day   = tonumber(day),
        hour  = tonumber(hour),
        min   = tonumber(min),
        sec   = tonumber(sec)
    })
end

function readLocalScripts()
    articulation_scripts_list_currentVersion = {}
    for i, script in ipairs(articulation_scripts_list) do
        local jsonString = file_handling.readFileForJsonLine(script.path)
        if jsonString then
            local foundJson, tbl = file_handling.importJsonString(jsonString)
            if foundJson then -- file_handling.importJsonString(jsonString) then
                --[[local s = {instrumentSettings = tbl.instrumentSettings}
                s.mapName = script.name
                s.path = script.path
                s.index = #articulation_scripts_list_currentVersion + 1
                s.json = "//json:" .. jsonString

                s.name = mapName or " "
                s.creator = s.instrumentSettings.Creator or " "
                s.vendor = s.instrumentSettings.Vendor or " "
                if s.mapName == "test 3 layers" then
                    reaper.ShowConsoleMsg(s.mapName)
                    aa = tbl
                end
                s.time = tbl.time or " "
                s.id = s.index]]
                tbl.path = script.path

                -- testing if performance is better not having tableInfo loaded
                tbl.tableInfo = nil

                if not tbl.genTime then
                    ret, _, _, modifiedTime = reaper.JS_File_Stat(script.path)
                    if ret then
                        tbl.genTime = date_string_to_seconds(modifiedTime)
                    end
                end


                tbl.index = #articulation_scripts_list_currentVersion + 1
                tbl.json = "//json:" .. jsonString

                tbl.name = tbl.mapName or ""
                tbl.creator = tbl.instrumentSettings.Creator or ""
                tbl.vendor = tbl.instrumentSettings.Vendor or ""
                tbl.product = tbl.instrumentSettings.Product or ""
                tbl.time = tbl.genTime and tostring(tbl.genTime) or "0"
                table.insert(articulation_scripts_list_currentVersion, tbl)
            end
        end
    end
end

local database_path = scriptPath .. "articulation_scripts_library.txt"
local database_articulation_scripts = {}

local function readCloudDatabase()
    local lines = file_handling.readFileLines(database_path, "//json:")
    database_articulation_scripts = {}
    if lines then
        for _, line in ipairs(lines) do
            local foundJson, tbl = file_handling.importJsonString(line)
            if foundJson then
                tbl.index = #database_articulation_scripts + 1
                tbl.json = "//json:" .. line

                tbl.name = tbl.mapName or ""
                tbl.creator = tbl.instrumentSettings.Creator or ""
                tbl.vendor = tbl.instrumentSettings.Vendor or ""
                tbl.product = tbl.instrumentSettings.Product or ""
                tbl.time = tbl.genTime and tostring(tbl.genTime) or "0"
                table.insert(database_articulation_scripts, tbl)
            end
        end
    end
end

function redoFilter()
    focusedScriptIndex = nil
    searchForPatches = true
    patchesFound = nil
    focusedScript = nil
end

function updateCloudLibrary()
    local text = articulation_scripts_library.readSharedText()
    export.writeFile(database_path, text)
    database_articulation_scripts = {}
    readCloudDatabase()
    redoFilter()
end

--if reaper.file_exists(database_path) then
--updateCloudLibrary()
readCloudDatabase()
--end

-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end

function formatSearchStringForAnyNonLetters(string)
    return string:gsub(" %- ", ' , '):gsub("+", ',')
end

function searchThroughString(search, string)
    if not search or search == "" then
        return true
    end
    if search:find("%[") then search = "" end
    if #search > 0 then
        for word in search:gmatch("[^,]+") do
            if word:sub(1, 1) == "-" then
                if string:upper():find(word:sub(2):upper()) then
                    --reaper.ShowConsoleMsg(string .. " -- " .. word .. "\n")
                    return false
                end
            else
                if not string:upper():find(word:upper()) then
                    --reaper.ShowConsoleMsg(string .. " !! " .. word .. "\n")
                    return false
                end
            end
        end
    end
    return true
end

local columnsTbl = { "Patch", "Creator", "Vendor", "Product" }
function findPatchesMatching(patchesObject)
    local patchesMatching = {}
    for patchNumber = 1, #patchesObject do
        local tbl = patchesObject[patchNumber]
        local allFieldsText = ""
        local columnText = {}
        for i, v in ipairs(columnsTbl) do
            if i == 1 then
                allFieldsText = allFieldsText .. tbl.mapName
                columnText[v] = tbl.mapName
            else
                allFieldsText = allFieldsText .. (tbl.instrumentSettings[v] and (" " .. tbl.instrumentSettings[v]) or "")
                columnText[v] = (tbl.instrumentSettings[v] and (" " .. tbl.instrumentSettings[v]) or "")
            end
        end

        local isInSearchAll = searchThroughString(searchFieldAll, allFieldsText)
        --local isInSearchPatch = searchThroughString(searchFieldPatch,patch)
        --local isInSearchCompany = searchThroughString(searchFieldCompany,currentCompany)
        --local isInSearchLibrary = searchThroughString(searchFieldLibrary,currentLibrary)
        --local isInSearchTags = searchThroughString(searchFieldTags,currentTagsStr)
        --local isInSearchInstruments = searchThroughString(searchFieldInstruments,currentInstrumentsStr)
        --if not searchIncludeFolders and currentIsFolder then includeFolder = false else includeFolder = true end
        --if not searchIncludePresets and currentIsPreset then includePreset = false else includePreset = true end
        --reaper.ShowConsoleMsg(tostring(isInSearchAll) .. " - " .. allFieldsText .. "\n")
        if isInSearchAll
        --[[and isInSearchPatch and
    isInSearchCompany and
    isInSearchLibrary and
    isInSearchTags and
    isInSearchInstruments and
    includeFolder and
    includePreset]]
        then
            table.insert(patchesMatching, tbl)
        end
    end
    return patchesMatching
end

colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0)
colorBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.0, 0, 0, 1)
colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)
colorGrey = theme.text_dim -- reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.4,0.4,1)
colorLightGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.6, 0.6, 0.6, 1)
colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
colorBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 1, 1)
colorAlmostWhite = reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8, 1)


function setToolTipFunc(text, color)
    if text then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), color and color or colorWhite)
        reaper.ImGui_SetItemTooltip(ctx, text)
        reaper.ImGui_PopStyleColor(ctx)
    end
end

local database_focus = "Local"
if not appSettings.scriptBrowser_database_focus then
    appSettings.scriptBrowser_database_focus = database_focus
    saveAppSettings()
end
local clearSearch = true
local reloadLocalScript = true
local reloadLocalScript_count = 10

function findPatchIndex(idx, prev)
    if not idx then return patchesFound[1].index end
    local closest
    for i, p in ipairs(patchesFound) do
        if p.index == idx then
            if i == #patchesFound and not prev then
                return patchesFound[1].index
            elseif i == 1 and prev then
                return patchesFound[#patchesFound].index
            else
                if prev then
                    return patchesFound[i - 1].index
                else
                    return patchesFound[i + 1].index
                end
            end
        end
    end
end

function findPatchMatching(patch)
    for i, p in ipairs(patchesFound) do
        if p.name == patch.name and patch.time == p.time then
            return p.index
        end
    end
end

function findPrevPath(idx, prev)
    if not idx then return patchesFound[1].index end
    local closest
    for i, p in ipairs(patchesFound) do
        if p.index == idx then
            if i == #patchesFound and not prev then
                return patchesFound[1].index
            elseif i == 1 and prev then
                return patchesFound[#patchesFound].index
            else
                if prev then
                    return patchesFound[i - 1].index
                else
                    return patchesFound[i + 1].index
                end
            end
        end
    end
end

--reaper.parse_timestr(
--local focusedScript, focusedScriptIndex
------------------------------------------------------------
-- UI loop
------------------------------------------------------------
local function loop()
    if reloadLocalScript then
        searchForPatches = true
        readLocalScripts()
        reloadLocalScript = nil
        if deletedScript then
            --focusedScriptIndex = nil
            --focusedScriptIndex = findPatchIndex(focusedScriptIndex, true)
            --focusedScriptIndex = findPatchIndex(focusedScriptIndex, true)
            deletedScript = nil
            findPrevIndex = true
        end
        --[[
            if reloadLocalScript_count >= 4 then
                reloadLocalScript = false
                reloadLocalScript_count = 0
            else
                reloadLocalScript_count = reloadLocalScript_count + 1
            end
            ]]
    end

    modern_ui.apply(ctx)
    reaper.ImGui_SetNextWindowSize(ctx, 600, 456, reaper.ImGui_Cond_FirstUseEver())

    local windowFlags = reaper.ImGui_WindowFlags_TopMost()
    --| reaper.ImGui_WindowFlags_AlwaysAutoResize()

    local visible, open = reaper.ImGui_Begin(ctx, 'Articulation Scripts Browser Window', true, windowFlags


    --| reaper.ImGui_WindowFlags_NoCollapse()
    )
    if visible then
        windowW, windowH = reaper.ImGui_GetWindowSize(ctx)
        isWindowFocused = reaper.ImGui_IsWindowFocused(ctx)
        if isWindowFocused then
            focused_hwnd = reaper.JS_Window_GetForeground()
        end

        ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
        cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
        alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
        shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
        enterDown = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Enter())
        enter = reaper.ImGui_IsKeyReleased(ctx, reaper.ImGui_Key_Enter())
        escape = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)
        delete = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(), false)
        mouseDown = reaper.ImGui_IsAnyMouseDown(ctx)
        isDoubleClick = reaper.ImGui_IsMouseDoubleClicked(ctx, 0)
        mouseReleased = reaper.ImGui_IsMouseReleased(ctx, 0)
        mousePosX, mousePosY = reaper.ImGui_GetMousePos(ctx)

        popupOpen = reaper.ImGui_IsPopupOpen(ctx, "Delete articulation script")

        searchFieldAll = appSettings.scriptBrowserSearch

        modifierSettings = nil
        --local isEscape = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())

        if ((escape and not popupOpen) and (searchFieldAll == "")) or (cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_W(), false)) then
            open = false
        end

        local btns = { "Local", "Database" }
        local btnsNames = { "Local", "Database" }
        database_focus = appSettings.scriptBrowser_database_focus
        for i, b in ipairs(btns) do
            if reaper.ImGui_RadioButton(ctx, btnsNames[i], database_focus == b) or (cmd and reaper.ImGui_IsKeyPressed(ctx, reaper["ImGui_Key_" .. i](), false)) then
                database_focus = b
                redoFilter()
                appSettings.scriptBrowser_database_focus = b
                saveAppSettings()

                if b == "Database" and appSettings.scriptBrowser_auto_update_cloud then
                    updateCloudLibrary()
                end
                -- reload scripts overview
                if b == "Local" then
                    articulation_scripts_list = get_articulation_scripts(articulationScriptsPath)
                    readLocalScripts()
                end
            end
            setToolTipFunc("Press cmd+" .. i .. " to select")

            if b == "Local" then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "open folder") or (cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_O(), false)) then
                    file_handling.openFolderInExplorer(articulationScriptsPath)
                end
                setToolTipFunc("Open articulation scripts folder.\n - Press cmd+o to update")
            end

            if database_focus == "Database" and b == "Database" then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "update database") or (cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_U(), false)) then
                    updateCloudLibrary()
                end
                setToolTipFunc("Update to latest online database.\n - Press cmd+u to update")

                reaper.ImGui_SameLine(ctx)
                ret, val = reaper.ImGui_Checkbox(ctx, "auto update", appSettings.scriptBrowser_auto_update_cloud)
                if ret then
                    appSettings.scriptBrowser_auto_update_cloud = val
                    saveAppSettings()
                end
                setToolTipFunc("Auto update the cloud whenever you open the browser.")
            end

            if i < #btns then reaper.ImGui_SameLine(ctx) end
        end

        if windowW then
            reaper.ImGui_AlignTextToFramePadding(ctx)
            reaper.ImGui_SameLine(ctx, windowW - 44)
            reaper.ImGui_TextColored(ctx, colorGrey, "(" .. tostring(articulationScriptCreatorVersionText) .. ")")
        end

        local isLocal = database_focus == "Local"
        local scripts_to_use = isLocal and articulation_scripts_list_currentVersion or database_articulation_scripts
        if not patchesFound then
            patchesFound = findPatchesMatching(scripts_to_use)
            sort_manually = true
        end
        --if focusedScriptIndex and scripts_to_use[focusedScriptIndex]
        --if not focusedScriptIndex and not searchForPatches and  patchesFound[1] then focusedScriptIndex = patchesFound[1].index end

        if focusedScriptIndex and scripts_to_use[focusedScriptIndex] then
            focusedScript = scripts_to_use[focusedScriptIndex]
            -- on local we only read the file if we have it selected
            if database_focus == "Local" then
                local jsonString = file_handling.readFileForJsonLine(scripts_to_use[focusedScriptIndex].path)

                if jsonString then
                    local foundJson, tbl = file_handling.importJsonString(jsonString)
                    if foundJson then
                        focusedScript.tableInfo = tbl.tableInfo
                    end
                end
            end
            --end
            focusedScriptJson = scripts_to_use[focusedScriptIndex].json or ""
        end

        if focusedScript then
            mapping = focusedScript.mapping
            tableInfo = focusedScript.tableInfo
            instrumentSettings = focusedScript.instrumentSettings
            mapName = focusedScript.mapName
            genTime = focusedScript.genTime
        end

        reaper.ImGui_Separator(ctx)


        reaper.ImGui_SetNextFrameWantCaptureKeyboard(ctx, 1)
        retval, unicode_char = reaper.ImGui_GetInputQueueCharacter(ctx, 0)

        --if not mouseDown and mousePosX then
        if (retval or mouseReleased or clearSearch) and not popupOpen then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            clearSearch = nil
        end

        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, colorGrey, "Search")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, 300 - 20)

        inputAll, filterAll = reaper.ImGui_InputText(ctx, "##All", searchFieldAll)
        if inputAll then --or #filterAll == 0 then
            searchFieldAll = filterAll
            --reaper.SetExtState("Sound Browser", "searchFieldAll", searchFieldAll,true)
            searchForPatches = true
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) - 8)


        --reaper.ImGui_SetCursorPos(ctx, posX, posY)
        if reaper.ImGui_Button(ctx, "X") or (searchFieldAll and searchFieldAll ~= "" and escape and not popupOpen) then
            searchFieldAll = ""
            --reaper.SetExtState("Sound Browser", "searchFieldAll", "",true)
            searchForPatches = true
            clearSearch = true
            escape = false
        end
        setToolTipFunc("Clear search.\n - Press escape to clear")

        function addScript()
            addMapToInstruments(mapName, nil, { genTime = genTime })
            if not isLocal then
                --  reloadLocalScript = true
            end

            --reaper.ImGui_SetWindowFocus(ctx)
            setFocusAfterAdding = true
            if focused_hwnd then
                reaper.JS_Window_SetFocus(focused_hwnd)
            end
            if not cmd then
                open = false
            end
        end

        --reaper.ImGui_SameLine(ctx)
        if not focusedScript then reaper.ImGui_BeginDisabled(ctx) end
        local addMap = false

        local hasTrackSelection = reaper.CountSelectedTracks(0) > 0
        if not hasTrackSelection then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Add to selected tracks") or (enter and not popupOpen and focusedScript and hasTrackSelection) then
            addScript()
        end
        if not hasTrackSelection then reaper.ImGui_EndDisabled(ctx) end

        setToolTipFunc(
        "Press enter to add selected articulation script to selected tracks\n - Add cmd to keep Browser window open")

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Edit Articulation script") or (cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_E(), false) and not popupOpen and focusedScript) then
            listOverviewSurface.openCreatorWindow()

            reaper.SetExtState("articulationMap", "openJson", focusedScriptJson, false)
        end
        setToolTipFunc("Press cmd+e to open selected articulation script in the Script Creator")

        reaper.ImGui_SameLine(ctx)
        if isLocal then
            if reaper.ImGui_Button(ctx, "Delete script") or (cmd and delete and not popupOpen and focusedScript) then
                reaper.ImGui_OpenPopup(ctx, "Delete articulation script")
            end
        else
            if reaper.ImGui_Button(ctx, "Import script") or (cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_I()) and not popupOpen and focusedScript) then
                export.createObjectForExport()
                --reloadLocalScript = true
            end
        end
        setToolTipFunc("Import script to harddrive. This will use the latest creator version.\n - press cmd+i to import")

        if not focusedScript then reaper.ImGui_EndDisabled(ctx) end
        reaper.ImGui_Separator(ctx)



        reaper.ImGui_BeginGroup(ctx)

        local txt = "ARTICULATION SCRIPTS " ..
        (isLocal and "LOCAL" or "DATABASE") .. "  (" .. #patchesFound .. "/" .. #scripts_to_use .. ")"
        if posXOfScriptsTable then
            local textW = reaper.ImGui_CalcTextSize(ctx, txt)
            local startPos = posXOfScriptsTable / 2 - textW / 2 - 8
            if startPos > 8 then
                reaper.ImGui_NewLine(ctx)
                reaper.ImGui_SameLine(ctx, startPos)
            end
        end

        reaper.ImGui_TextColored(ctx, colorGrey, txt)
        reaper.ImGui_Separator(ctx)



        function compareTableItems(a, b)
            for next_id = 0, math.huge do
                local ok, col_idx, col_user_id, sort_direction = reaper.ImGui_TableGetColumnSortSpecs(ctx, next_id)
                if not ok then break end

                -- Here we identify columns using the ColumnUserID value that we ourselves passed to TableSetupColumn()
                -- We could also choose to identify columns based on their index (col_idx), which is simpler!
                local key
                if col_user_id == tableId_Name then
                    key = 'mapName'
                elseif col_user_id == tableId_Creator then
                    key = 'creator'
                elseif col_user_id == tableId_Vendor then
                    key = 'vendor'
                elseif col_user_id == tableId_Product then
                    key = 'product'
                elseif col_user_id == tableId_Time then
                    key = 'time'
                    --elseif col_idx == 3 then -- col_user_id == tableId_Library then
                    --  key = 'library'
                    --elseif col_idx == 4 then -- col_user_id == tableId_Instruments then
                    --  key = 'instrumentsStr'
                else
                    error('unknown user column ID' .. col_user_id)
                end

                local is_ascending = sort_direction == reaper.ImGui_SortDirection_Ascending()

                --if a[key] and b[key] then
                if a[key]:lower() < b[key]:lower() then
                    return is_ascending
                elseif a[key]:lower() > b[key]:lower() then
                    return not is_ascending
                end
                --else
                --    aa = a
                --   reaper.ShowConsoleMsg(tostring(sort_direction) .. " - " .. tostring(col_user_id) .. " - " .. tableId_Vendor .. "\n")
                --end
            end

            -- table.sort is unstable so always return a way to differentiate items.
            -- Your own compare function may want to avoid fallback on implicit sort specs e.g. a Name compare if it wasn't already part of the sort specs.
            return a.index < b.index
        end

        local columns = 3
        local columnsTbl = { "Name", "Creator", "Vendor", "Product", "Time" }

        for i, v in ipairs(columnsTbl) do
            _G["tableId_" .. v] = i - 0
        end

        local childFlags = reaper.ImGui_ChildFlags_ResizeX()
        if reaper.ImGui_BeginChild(ctx, "Script name", 300, nil, childFlags) then
            tableFlags = reaper.ImGui_TableFlags_ScrollX()      |
                reaper.ImGui_TableFlags_ScrollY()      |
                reaper.ImGui_TableFlags_RowBg()        |
                reaper.ImGui_TableFlags_BordersOuter() |
                reaper.ImGui_TableFlags_BordersV()     |
                reaper.ImGui_TableFlags_Resizable()    |
                reaper.ImGui_TableFlags_Reorderable()  |
                reaper.ImGui_TableFlags_Sortable()        |
                reaper.ImGui_TableFlags_SortMulti()       |
                reaper.ImGui_TableFlags_Hideable()
            freeze_cols = 1
            freeze_rows = 1
            if reaper.ImGui_BeginTable(ctx, 'scriptsTbl', #columnsTbl, tableFlags) then
                reaper.ImGui_TableSetupScrollFreeze(ctx, freeze_cols, freeze_rows)
                for i, v in ipairs(columnsTbl) do
                    local flags
                    if v == "Name" then
                        flags = reaper.ImGui_TableColumnFlags_NoHide() | reaper.ImGui_TableColumnFlags_DefaultSort()
                    end

                    reaper.ImGui_TableSetupColumn(ctx, v, flags, 0.0, _G["tableId_" .. v])
                end

                reaper.ImGui_TableHeadersRow(ctx)


                showPatches = {}
                patchesShowing = 0
                librariesShowing = {}
                companiesShowing = {}


                local specs_dirty, has_specs = reaper.ImGui_TableNeedSort(ctx)
                if specs_dirty or sort_manually then
                    table.sort(patchesFound, compareTableItems)
                    sort_manually = nil
                end

                for patchNumber = 1, #patchesFound do
                    reaper.ImGui_TableNextRow(ctx)
                    --for column = 0, columns-1 do
                    reaper.ImGui_TableNextColumn(ctx)
                    --for i, tbl in ipairs(scripts_to_use) do
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x222222FF )
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x000000FF)
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0x000000FF)
                    local tbl = patchesFound[patchNumber]
                    for i, v in ipairs(columnsTbl) do
                        local index = tbl.index
                        local isFocused = focusedScriptIndex == index
                        if v == "Name" then
                            local name = tbl.mapName -- database_focus == "Local"  and tbl.name or tbl.mapName
                            if reaper.ImGui_Selectable(ctx, name .. "##" .. patchNumber .. "column1", isFocused) then
                                focusedScriptIndex = index

                                --scriptAdded = addMapToInstruments(script)
                            end

                            if reaper.ImGui_IsItemHovered(ctx) and isDoubleClick then
                                addScript()
                            end
                        elseif v == "Time" then
                            reaper.ImGui_TableNextColumn(ctx)
                            local readable_time = tbl.genTime and tbl.genTime ~= " " and
                            os.date("%Y-%m-%d %H:%M:%S", tbl.genTime) or ""
                            --readable_time = tbl.time
                            if reaper.ImGui_Selectable(ctx, readable_time .. "##" .. patchNumber .. "column1", isFocused) then
                                focusedScriptIndex = index
                                --scriptAdded = addMapToInstruments(script)
                            end

                            if reaper.ImGui_IsItemHovered(ctx) and isDoubleClick then
                                addScript()
                            end
                        else
                            reaper.ImGui_TableNextColumn(ctx)
                            local name = tbl.instrumentSettings[v] or
                            ""                                            --database_focus == "Local" and tbl.name or tbl.instrumentSettings.Vendor
                            if reaper.ImGui_Selectable(ctx, name .. "##" .. patchNumber .. v, isFocused) then
                                focusedScriptIndex = index
                                if name ~= "" then
                                    --search[v] = formatSearchStringForAnyNonLetters(name)
                                    if searchFieldAll and searchThroughString(formatSearchStringForAnyNonLetters(name), searchFieldAll) then
                                        searchFieldAll = ""
                                    else
                                        searchFieldAll = formatSearchStringForAnyNonLetters(name)
                                    end
                                    searchForPatches = true
                                end
                                --scriptAdded = addMapToInstruments(script)
                            end
                        end
                    end

                    --reaper.ImGui_PopStyleColor(ctx,4)
                end
                reaper.ImGui_EndTable(ctx)
            end

            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_EndGroup(ctx)





        if searchForPatches then
            appSettings.scriptBrowserSearch = searchFieldAll
            saveAppSettings()
            patchesFound = findPatchesMatching(scripts_to_use)
            searchForPatches = false
            sort_manually = true
            if focusedScriptIndex then
                --findPatchIndex(focusedScriptIndex, false)
            end
        end



        reaper.ImGui_SameLine(ctx)
        posXOfScriptsTable = reaper.ImGui_GetCursorPosX(ctx)
        local widthOfChild = windowW - posXOfScriptsTable - 8

        if reaper.ImGui_BeginChild(ctx, "preview name", widthOfChild) then
            --reaper.ImGui_BeginGroup(ctx)

            local textW = reaper.ImGui_CalcTextSize(ctx, "PREVIEW")
            reaper.ImGui_SameLine(ctx, widthOfChild / 2 - textW / 2 - 8)
            reaper.ImGui_TextColored(ctx, colorGrey, "PREVIEW")
            if focusedScript then
                local mapping = focusedScript.mapping
                local tableInfo = focusedScript.tableInfo
                local instrumentSettings = focusedScript.instrumentSettings
                local mapName = focusedScript.mapName
                local creatorVersion = focusedScript.creatorVersion
                local time = focusedScript.genTime
                --reaper.ShowConsoleMsg(tostring(time) .. "\n")
                local readable_time = time and time ~= " " and os.date("%Y-%m-%d %H:%M:%S", time) or ""

                function infoButtons(value, forceText)
                    reaper.ImGui_TextColored(ctx, colorGrey, value .. ":")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextWrapped(ctx,
                        forceText and forceText or (instrumentSettings and instrumentSettings[value]))
                end

                reaper.ImGui_AlignTextToFramePadding(ctx)

                --reaper.ImGui_Separator(ctx)
                local tblFlags = nil --reaper.ImGui_TableFlags_SizingFixedFit()
                local previewNames = { "Name", "Creator", "Vendor", "Product", "Patch", "Info", "Creator Version", "Date" }
                if reaper.ImGui_BeginTable(ctx, 'tablenames', 2, tblFlags, widthOfChild) then
                    reaper.ImGui_TableSetupColumn(ctx, 'name', reaper.ImGui_TableColumnFlags_WidthFixed())
                    for column, name in ipairs(previewNames) do
                        local forceText
                        if name == "Name" then
                            forceText = mapName
                        end
                        if name == "Creator Version" then
                            forceText = creatorVersion
                        end
                        if name == "Date" then
                            forceText = readable_time
                        end

                        reaper.ImGui_TableNextRow(ctx)

                        reaper.ImGui_TableNextColumn(ctx)

                        reaper.ImGui_TextColored(ctx, colorGrey, name .. ":")
                        reaper.ImGui_TableNextColumn(ctx)
                        reaper.ImGui_TextWrapped(ctx,
                            forceText and forceText or (instrumentSettings and instrumentSettings[name]))
                    end
                    reaper.ImGui_EndTable(ctx)
                end
                --[[
                infoButtons("Name", mapName)
                infoButtons("Creator")
                infoButtons("Vendor")
                infoButtons("Product")
                infoButtons("Patch")
                infoButtons("Info")
                ]]

                mappingType = mapping_handling.createTableOrderFromUsedMappings(mapping)
                local columnAmount = #mappingType
                totalItemAmount = (#tableInfo) * (columnAmount)

                local totalArticulations = 0
                local totalLayers = 0
                local layersUsed = {}
                -- WE COULD ADD FILTERS, KEYSWITCHES ETC HERE
                for _, t in ipairs(tableInfo) do
                    if t.Layer and not layersUsed[t.Layer] then
                        layersUsed[t.Layer] = true
                        totalLayers = totalLayers + 1
                    elseif not layersUsed[1] then
                        layersUsed[1] = true
                        totalLayers = totalLayers + 1
                    end
                    if not t.isLane then
                        totalArticulations = totalArticulations + 1
                    end
                end


                --reaper.ImGui_TextColored(ctx, colorGrey, "Articulations: " .. totalArticulations .. " / Layers: " .. totalLayers)

                --if reaper.ImGui_BeginChild(ctx, "tablechild2") then

                tableFlags = --

                    reaper.ImGui_TableFlags_RowBg()
                    | reaper.ImGui_TableFlags_ScrollX()
                    | reaper.ImGui_TableFlags_ScrollY()
                    | reaper.ImGui_TableFlags_Borders()
                    | reaper.ImGui_TableFlags_NoHostExtendX()
                    | reaper.ImGui_TableFlags_NoHostExtendY()
                --| reaper.ImGui_TableFlags_SizingFixedFit()
                --| reaper.ImGui_TableFlags_Resizable()

                if reaper.ImGui_BeginTable(ctx, 'table1', columnAmount, tableFlags) then
                    reaper.ImGui_TableSetupScrollFreeze(ctx, 1, 1)

                    for _, mappingName in ipairs(mappingType) do
                        local tbSize = _G["tableSize" .. mappingName]
                        if not tbSize then
                            if mapping_handling.getNoteNumber(mappingName) then
                                tbSize = tableSizeNote
                            elseif mapping_handling.getCCNumber(mappingName) then
                                tbSize = tableSizeCC
                                --else
                                --    tbSize = tableSizeOthers
                            end
                        end

                        --reaper.ImGui_TableSetupColumn(ctx, mappingName, reaper.ImGui_TableColumnFlags_WidthFixed(), tbSize)
                    end


                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), colorGrey)
                    reaper.ImGui_TableNextRow(ctx) --, reaper.ImGui_TableRowFlags_Headers())
                    --reaper.ImGui_TableHeadersRow(ctx)
                    for column = 1, columnAmount do
                        reaper.ImGui_TableSetColumnIndex(ctx, column - 1)
                        local column_name = mappingType[column]

                        visualColumnName = mapping_handling.getVisualColumnName(column_name)

                        reaper.ImGui_Text(ctx, visualColumnName)
                        reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_CellBg(), colorDarkGrey)
                    end

                    --reaper.ImGui_PopStyleColor(ctx)

                    for row = 1, #tableInfo do
                        --reaper.ImGui_TableNextRow(ctx)

                        reaper.ImGui_TableNextRow(ctx)
                        for column = 1, columnAmount do
                            reaper.ImGui_TableSetColumnIndex(ctx, column - 1)
                            local columnName = mappingType[column]
                            local text = tableInfo[row][columnName]
                            if tostring(text):match("!!Lane") ~= nil then
                                if columnsToNotUseLanes[columnName] then
                                    local mainLaneRow = mapping_handling.getMainLaneRow(tableInfo, columnName, row)
                                    if tableInfo[mainLaneRow][columnName] then
                                        reaper.ImGui_TextColored(ctx, colorGrey, tableInfo[mainLaneRow][columnName])
                                    end
                                end
                            else
                                reaper.ImGui_Text(ctx, text)
                            end
                        end
                    end



                    reaper.ImGui_EndTable(ctx)
                    --end
                    --reaper.ImGui_EndChild(ctx)
                end
            end

            reaper.ImGui_EndChild(ctx)
        end

        --reaper.ImGui_EndGroup(ctx)
        local viewport = false --reaper.ImGui_GetWindowViewport(ctx)
        if viewport then
            local center_x, center_y = reaper.ImGui_Viewport_GetCenter(viewport)
            reaper.ImGui_SetNextWindowPos(ctx, center_x, center_y, reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
        end

        if reaper.ImGui_BeginPopupModal(ctx, "Delete articulation script", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_TextColored(ctx, colorGrey, "This will remove:")
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, scripts_to_use[focusedScriptIndex].name)
            reaper.ImGui_Text(ctx, "Are you sure? This can not be undone")
            reaper.ImGui_Separator(ctx)

            --static int unused_i = 0;
            --ImGui.Combo("Combo", &unused_i, "Delete\0Delete harder\0");

            --ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
            --rv,popups.modal.dont_ask_me_next_time =
            --  ImGui.Checkbox(ctx, "Don't ask me next time", popups.modal.dont_ask_me_next_time)
            --ImGui.PopStyleVar(ctx)

            if reaper.ImGui_Button(ctx, 'OK', 120, 0) or enter then
                os.remove(scripts_to_use[focusedScriptIndex].path)
                local focusedScriptIndexAfterDeleting = findPatchIndex(focusedScriptIndex, false)
                scriptAfterDeleting = scripts_to_use[focusedScriptIndexAfterDeleting]
                table.remove(scripts_to_use, focusedScriptIndex)
                reloadLocalScript = true
                deletedScript = true
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_SetItemDefaultFocus(ctx)
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or escape then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end


        --reaper.ImGui_PopStyleColor(ctx,3)

        reaper.ImGui_End(ctx)
    end

    modern_ui.ending(ctx)


    if not popupOpen then
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then
            focusedScriptIndex = findPatchIndex(focusedScriptIndex, true)
        end

        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
            focusedScriptIndex = findPatchIndex(focusedScriptIndex, false)
        end

        if scriptAfterDeleting then 
            focusedScriptIndex = findPatchMatching(scriptAfterDeleting)
            scriptAfterDeleting = nil
        end
    end

    if not toolbarSet then
        setToolbarState(true)
        toolbarSet = true
    end
    reaper.atexit(exit)


    if open then
        reaper.defer(loop)
    end
end

loop()
