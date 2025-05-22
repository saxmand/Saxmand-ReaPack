-- @description FX Modulator Linking
-- @author Saxmand
-- @version 0.8.1
-- @provides
--   [effect] ../FX Modulator Linking/*.jsfx
--   Helpers/*.lua
--   Color sets/*.txt
-- @changelog
--   + fixed an issue where the envelope lane of the first parameter of the first instrument was shown without it being pressed
--   + Added Button Modulator
--   + Added Macro Modulator
--   + Added Midi Out Modulator

local version = "0.8.1"

local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*"..seperator..")")
package.path = package.path .. ";" .. scriptPath .. "Helpers/?.lua"
local json = require("json")
local specialButtons = require("special_buttons")
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3.3'
local stateName = "ModulationLinking"
local appName = "FX Modulator Linking"

            
local colorFolderName = "Color sets"

local ctx
font = reaper.ImGui_CreateFont('Arial', 14)
font1 = reaper.ImGui_CreateFont('Arial', 15)
font2 = reaper.ImGui_CreateFont('Arial', 17)
font10 = reaper.ImGui_CreateFont('Arial', 10)
font11 = reaper.ImGui_CreateFont('Arial', 11)
font12 = reaper.ImGui_CreateFont('Arial', 12)
font13 = reaper.ImGui_CreateFont('Arial', 13)
function initializeContext()
    ctx = ImGui.CreateContext(appName)
    -- imgui_font
    reaper.ImGui_Attach(ctx, font)
    reaper.ImGui_Attach(ctx, font1)
    reaper.ImGui_Attach(ctx, font2)
    reaper.ImGui_Attach(ctx, font10)
    reaper.ImGui_Attach(ctx, font11)
    reaper.ImGui_Attach(ctx, font12)
    reaper.ImGui_Attach(ctx, font13)
end
initializeContext()

reaper.ImGui_SetConfigVar(ctx,reaper.ImGui_ConfigVar_MacOSXBehaviors(),0)
local isApple = reaper.GetOS():match("mac")
local isWin= reaper.GetOS():lower():match("win")

function checkIfPluginIsInstalled(name)
     function jsfx_exists(name)
       local i = 0
       while true do
         local ret, fx = reaper.EnumInstalledFX(i)
         if not ret or not fx then break end
         if ret and fx:lower():find(name:lower(), 1, true) then
           return true
         end
         i = i + 1
       end
       return false
     end
    
    -- Example
    return jsfx_exists(name) 
end

local isAdsr1Installed = checkIfPluginIsInstalled("JS: ADSR-1")
local isMseg1Installed = checkIfPluginIsInstalled("JS: MSEG-1")
local isReaLearnInstalled = checkIfPluginIsInstalled("Helgobox")
--function reaper_do_file(file) local info = debug.getinfo(1,'S'); local path = info.source:match[[^@?(.*[\/])[^\/]-$]]; dofile(path .. file); end
--reaper_do_file('Helpers/json.lua')
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
-----------------------------------------
-----------------------------------------
-----------------------------------------

function deepcopy(orig, copies)
  copies = copies or {}
  if type(orig) ~= 'table' then
    return orig
  elseif copies[orig] then
    return copies[orig]  -- handle circular references
  end

  local copy = {}
  copies[orig] = copy
  for k, v in next, orig, nil do
    copy[deepcopy(k, copies)] = deepcopy(v, copies)
  end
  setmetatable(copy, deepcopy(getmetatable(orig), copies))
  return copy
end

local function prettifyString(str)
  -- Step 1: Insert space before each capital letter (except first)
  local with_spaces = str:gsub("(%u)", " %1")
  -- Step 2: Trim and capitalize first character
  with_spaces = with_spaces:gsub("^%s*(%l)", string.upper)
  return with_spaces
end

local function saveFile(data, fileName, subfolder)  
    local target_dir = scriptPath .. (subfolder and (subfolder .. seperator) or "")
    local save_path = target_dir .. fileName .. ".txt"
    -- Make sure subfolder exists (cross-platform)
    os.execute( (seperator == "/" and "mkdir -p \"" or "mkdir \"" ) .. target_dir .. "\"")
    
    -- Save a file
    local file = io.open(save_path, "w")
    if file then
      file:write(data)
      file:close()
    end
end

function readFile(fileName, subfolder) 
  if not fileName then return nil end
  local target_dir = scriptPath .. (subfolder and (subfolder .. seperator) or "")
  local target_path = target_dir .. fileName .. ".txt"
  local file = io.open(target_path, "r") -- "r" for read mode
  if not file then
    return nil
  end
  

  local content = file:read("*a") -- read entire file
  file:close()
  -- remove possible no index
  content = content:gsub("--@noindex\n", "")
  return content
end

function open_folder(subfolder)
    local target_dir = scriptPath .. (subfolder and (subfolder .. seperator) or "")
    -- Normalize slashes
    target_dir = target_dir:gsub("\\", "/")
  
    -- Detect OS and run the appropriate command
    if reaper.GetOS():find("Win") then
        os.execute('start "" "' .. target_dir .. '"')
    elseif reaper.GetOS():find("mac") then
        os.execute('open "' .. target_dir .. '"')
    else
        os.execute('xdg-open "' .. target_dir .. '"')
    end
end


function get_files_in_folder(subfolder) 
    target_dir = scriptPath .. (subfolder and (subfolder .. seperator) or "")
    target_dir = target_dir:gsub("\\", "/")
    local names = {}
    local i = 0
    while true do 
        local file = reaper.EnumerateFiles(target_dir, i)
        if not file then break end
        if file:match(".txt") ~= nil then
            local name = file:match("(.+)%..+$") or file  -- remove extension
            table.insert(names, name)
        end 
        i = i + 1
    end
    return names
end
-----------------------------------------
-----------------------------------------
-----------------------------------------
-----------------------------------------
-----------------------------------------





local focusedTrackFXNames = {}
local parameterLinks = {}
local focusedTrackFXParametersData = {}
local modulatorNames = {}
local modulatorFxIndexes = {}
modulationContainerPos = nil
local buttonHovering = {}
-- xy pad
local sendXyValues = {}
local showLargeXyPad = {}

                    
local directions = {"Downwards", "Bipolar", "Upwards"}

local margin = 8
local minWidth
local trackSettings
local automation, isAutomationRead


colorMap = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,1)
colorMapDark = reaper.ImGui_ColorConvertDouble4ToU32(0.7,0.2,0.2,1)
colorMapLight = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.65,0.65,1)
colorMapLightest = reaper.ImGui_ColorConvertDouble4ToU32(0.95,0.75,0.75,1)
colorMapLightTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.65,0.65,0.5)
colorMapLittleTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.9)
colorMapSemiTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.7)
colorMapMoreTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.9,0.4,0.4,0.4)
colorGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.4,0.4,1)
colorMidGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.5,0.5,0.5,1)
colorLightGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.6,0.6,0.6,1)
colorWhite = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1,1)
colorAlmostWhite = reaper.ImGui_ColorConvertDouble4ToU32(0.8, 0.8, 0.8,1)
colorBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.4,0.8,1)
colorBrightBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,1)
colorBrightBlueTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,0.8)
colorBrightBlueOverlay = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,0.3)
colorBlueTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.4,0.6,1,0.5)
colorLightBlue = reaper.ImGui_ColorConvertDouble4ToU32(0.2,0.4,0.8,0.5)
colorTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0,0,0,0)
semiTransparentGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3,0.2)
littleTransparentGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.3,0.3,0.4)
menuGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.14,0.14,0.14,1)
menuGreyHover = reaper.ImGui_ColorConvertDouble4ToU32(0.3,0.30,0.30,1)
menuGreyActive = reaper.ImGui_ColorConvertDouble4ToU32(0.45,0.45,0.45,1)

colorBlack = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1)
colorAlmostBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1)
colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)

colorYellowMinimzed = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 188 / 255, 46 / 255, 0.7) -- 117 122 118
colorRedHidden = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 95 / 255, 88 / 255, 1)  -- 117 122 118
colorRedTransparent = reaper.ImGui_ColorConvertDouble4ToU32(254 / 255, 95 / 255, 88 / 255, 0.3)  -- 117 122 118
colorGreen = reaper.ImGui_ColorConvertDouble4ToU32(39 / 255, 198 / 255, 65 / 255, 0.7)  -- 117 122 118
colorGreenTransparent = reaper.ImGui_ColorConvertDouble4ToU32(39 / 255, 198 / 255, 65 / 255, 0.3)  -- 117 122 118
colorDarkGreen = reaper.ImGui_ColorConvertDouble4ToU32(20 / 255, 100 / 255, 32 / 255, 0.7)  -- 117 122 118

colorOrange = reaper.ImGui_ColorConvertDouble4ToU32(1,0.2,0.2,1)


function rgbColor(r,g,b, a)
   return reaper.ImGui_ColorConvertDouble4ToU32(r / 255, g / 255, b / 255, a and a or 1)
end
colorTrimRead = rgbColor(92,93,93)   -- 117 122 118
colorRead = rgbColor(42,254,190)   -- 117 122 118
colorTouch = rgbColor(254,180,37)   -- 117 122 118
colorWrite = rgbColor(254,38,116)   -- 117 122 118
colorLatch = rgbColor(172,38,254)   -- 117 122 118
colorLatchPreview = rgbColor(36,176,254)   -- 117 122 118
            

local defaultSettings = {
    -- settings not available in menu
    floatingParameterShowMappings = false,
    floatingParameterShowModulator = true,
    
    
    openSelectedFx = false,
    includeModulators = false, 
    showParametersForAllPlugins = false,
    trackSelectionFollowFocus = true,
    focusFollowsFxClicks = false,
    showToolTip = true,
    modulesHeightVertically = 250,
    limitModulatorHeightToModulesHeight = true,
    vertical = false,
    allowCollapsingMainWindow = false,
    
    onlyMapped = false,
    search = "", 
    partsWidth = 188,
    wwVertical = 180 + margin *4,
    whVertical = 900,
    xVertical = 300,
    yVertical = 300,
    wwHorizontal = 1500,
    whHorizontal = 450, 
    xHorizontal = 300, 
    yHorizontal = 300, 
    showBuildin = true,
    showUser = true,
    showPreset = true,
    showExtra = true,
    
    userModulators = {},
    
    -- Visual settings
      -- Name
    trackColorAroundLock = true,
    showTrackColorLine = false,
    trackColorLineSize = 2,
    
      -- others
    useAutomationColorOnEnvelopeButton = false,
    
      -- Plugins 
    showPluginsPanel = true,
    showContainers = true,
    colorContainers = true,
    indentsAmount = 3,
    allowHorizontalScroll = false,
    hidePluginTypeName = false,
    
    showOpenAll = true, 
    showAddTrackFX = true,
    showPluginOptionsOnTop = true,
    
      -- Parameters
    searchClearsOnlyMapped = false,
    showParametersPanel = true,
    showSearch = true,
    showOnlyMapped = true,
    showLastClicked = true,
    showParameterOptionsOnTop = true,
    maxParametersShown = 0, 
    showRemoveCrossParameter = true,
    showExtraLineInParameters = false,
    
    showEnableInParameters = true,
    showWidthInParameters = true,
    showBipolarInParameters = true,
    
      -- Modules 
    showModulesPanel = true, 
    
    -- Modulators
    showMapOnceModulator = true,
    showSortByNameModulator = true,
    sortAsType = false,
    mapOnce = false,
    
    showRemoveCrossModulator = true, 
    visualizerSize = 2,
    showAddModulatorButton = true,
    showAddModulatorButtonBefore = false,
    
    showRemoveCrossMapping = true,
    showEnableInMappings = true,
    showWidthInMappings = true,
    showBipolarInMappings = true,
    openMappingsPanelPos = "Right",
    openMappingsPanelPosFixedCoordinates = {}, -- not in settings
    
    
    -- Experimental
    forceMapping = false,
    -- floating mapper
      useFloatingMapper = false,
      keepWhenClickingInAppWindow = true,
      onlyKeepShowingWhenClickingFloatingWindow = false,
      openFloatingMapperRelativeToWindow = false,
      openFloatingMapperRelativeToWindowPos = 15,
      openFloatingMapperRelativeToMouse = true,
      openFloatingMapperRelativeToMousePos = {x= 50, y=50},
    -- envelopes  
      showEnvelope = true,
      hideEnvelopesWithNoPoints = true,
      hideEnvelopesWithPoints = false,
      showClickedInMediaLane = false,
      insertEnvelopeBeforeAddingNewEnvelopePoint = true,
      insertEnvelopePointsAtTimeSelection = true,
    
    usePreviousMapSettingsWhenOverwrittingMapping = false,
    pulsateMappingButton = true,
    pulsateMappingButtonsMapped = true,
    pulsateMappingColorSpeed = 6,
    
    mappingModeBipolar = true,
    defaultMappingWidth = 0,
    defaultMappingWidthLFO = 0,
    defaultBipolarLFO = true,
    defaultBipolar = false,
    mappingWidthOnlyPositive = false,
    defaultDirection = 3,
    defaultLFODirection = 2,
    
    defaultAcsTrackAudioChannelInput = 5,
    
    --defaultDirection = 3,
    --defaultLFODirection = 2,
    
    --lastFocusedSettingsTab = "Layout",
    passAllUnusedShortcutThrough = false,
    
    
    dockIdVertical = {},
    
    
    colors = {
      appBackground = colorBlack,
      modulesBackground = colorBlack, 
      modulatorsModuleBackground = colorBlack,
      
      modulesBorder = colorGrey,
      text = colorWhite,
      textDimmed = colorGrey,
      
      modulatorOutput = colorWhite,
      modulatorOutputBackground = colorLightBlue,
      modulatorBorder = colorGrey,
      modulatorBorderSelected = colorWhite,
      
      mapping = colorMap,
      selectOverlay = colorBlue,
      
      buttons = colorDarkGrey,
      buttonsActive = colorMidGrey,
      buttonsHover = colorGrey,
      buttonsBorder = colorLightGrey,
      
      buttonsSpecial = colorDarkGrey,
      buttonsSpecialActive = colorMidGrey,
      buttonsSpecialHover = colorGrey,
      
      pluginOpen = colorLightBlue,
      pluginOpenInContainer = colorDarkGrey,
      
      sliderBackground = colorAlmostBlack,
      sliderBaseline = colorBrightBlue,
      sliderOutput = colorMapLightTransparent,
      sliderWidth = colorBlueTransparent,
      sliderWidthNegative = colorMapLightTransparent,
      
      boxBackground = colorAlmostBlack,
      boxBackgroundHover = colorDarkGrey,
      boxBackgroundActive = colorDarkGrey,
      boxTick = colorAlmostWhite,
      
      menuBar = colorDarkGrey,
      menuBarHover = menuGreyActive,
      menuBarActive = menuGreyActive,
      
      removeCross = colorWhite,
      removeCrossHover = colorRedHidden,
      
      envelopeButtonBackground = colorDarkGrey,
    },
    selectedColorSet = "Dark",
    
    -- Key commands
    useVerticalScrollToScrollModulatorsHorizontally = false,
    onlyScrollVerticalHorizontalScrollWithModifier = false,
    onlyScrollVerticalHorizontalOnTopOrBottom = false,
    modifierEnablingScrollVerticalHorizontal = {["Super"] = true},
    scrollingSpeedOfVerticalHorizontalScroll = 15,  
    
    scrollModulatorsHorizontalAnywhere = false,
    scrollingSpeedOfHorizontalScroll = 15,  
    
    fineAdjustAmount = 10,
    scrollValueSpeed = 50,
    -- options for modifier keys
    modifierOptions = {
        scrollValue = {["Alt"] = true},
        fineAdjust = {["Shift"] = true},
        adjustWidth = {["Ctrl"] = true},
        changeBipolar = {["Super"] = true},
        },
}

local defaultTrackSettings = {
    hideModules = false,
    hideParameters = false,
    hidePlugins = false,
    collabsModules = {},
    showMappings = {},
    renamed = {},
    bigWaveform = {},
    hideParametersFromModulator = {},
}

local function saveSettings()
    local settingsStr = json.encodeToJson(settings)
    reaper.SetExtState(stateName,"settings", settingsStr, true) 
end



if reaper.HasExtState(stateName, "settings") then 
    local settingsStr = reaper.GetExtState(stateName,"settings") 
    settings = json.decodeFromJson(settingsStr)
else    
    settings = deepcopy(defaultSettings)
    saveSettings()
end

--settings = {}

-- BACKWARDS COMPATABILITY
for key, value in pairs(defaultSettings) do
    if type(value) == "table" then 
        if settings[key] == nil then
            settings[key] = {}
        end
        
        for subKey, subValue in pairs(value) do
            if settings[key][subKey] == nil then
                settings[key][subKey] = subValue
            end
        end
    else  
        if settings[key] == nil then
            settings[key] = value
        end
    end
end


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
    --{name = "Delete", commands  = {"Super+BACKSPACE", "DELETE"}}, 
    {name = "Close", commands  = {"Super+W", "Alt+M"}},
    {name = "Map current toggle", commands  = {"Super+M"}},
    {name = "Open Settings", commands = {"F2"}},
  }

local keyCommandSettings = keyCommandSettingsDefault
if reaper.HasExtState(stateName,"keyCommandSettings") then
    keyCommandSettingsStr = reaper.GetExtState(stateName,"keyCommandSettings")
    keyCommandSettings = json.decodeFromJson(keyCommandSettingsStr)
end


-- BACKWARDS COMPATABILITY
for key, value in pairs(keyCommandSettingsDefault) do
    if type(value) == "table" then 
        if keyCommandSettings[key] == nil then
            keyCommandSettings[key] = {}
        end
        
        for subKey, subValue in pairs(value) do
            if keyCommandSettings[key][subKey] == nil then
                keyCommandSettings[key][subKey] = subValue
            end
        end
    else  
        if keyCommandSettings[key] == nil then
            keyCommandSettings[key] = value
        end
    end
end


local function checkKeyPress() 
    local altKey
    for next_id = 0, math.huge do
        local rv, c = ImGui.GetInputQueueCharacter(ctx, next_id)
        if not rv then break end
        altKey = utf8.char(c)
    end
    local text = "" 
    local modifierText = (isSuperPressed and "Cmd+" or "") .. (isAltPressed and "Opt+" or "") .. (isShiftPressed and "Shift+" or "") .. (isCtrlPressed and "Control+" or "")
    for key, keyName in pairs(tableOfAllKeys) do
      if ImGui.IsKeyDown(ctx, key) then
        if keyName:find("Left") == nil and keyName:find("Right") == nil then
            --text = isSuperPressed and text .. "Super+" or text
            --text = isCtrlPressed and text .. "Ctrl+" or text
            --text = isShiftPressed and text .. "Shift+" or text
            --text = isAltPressed and text .. "Alt+" or text
            text = modifierText.. textConvert(keyName)
            addKey = nil 
            return text, altKey
        end
      end
    end
    return altKey
end



local function addKeyCommand(index)
    local color = (reaper.time_precise()*10)%10 < 5 and colorOrange or colorGrey
    reaper.ImGui_TextColored(ctx, color, "Press Command")
    if reaper.ImGui_IsItemClicked(ctx) then addKey = nil end
    local newKeyPressed = checkKeyPress() 
    if newKeyPressed then
        local addCommand = true
        for i, info in ipairs(keyCommandSettings) do 
            for ci, c in ipairs(info.commands) do 
                if c == newKeyPressed then
                    if i == index then
                        addCommand = false
                    else
                        local input = reaper.ShowMessageBox(" Do you want to overwrite asign it here instead", "Shortcut already used", 1)
                        if input == 1 then
                            table.remove(keyCommandSettings[i].commands,ci)
                        else
                            addCommand = false
                        end
                    end
                end
            end
        end
        if addCommand then
            table.insert(keyCommandSettings[index].commands, newKeyPressed)
            reaper.SetExtState(stateName,"keyCommandSettings", json.encodeToJson(keyCommandSettings), true)
        end
    end
end

function textConvert(name)

  local textConverts = {
  ["Escape"]= "ESC",
  ["Enter"]= "Return",
  ["DownArrow"]= "Down",
  ["UpArrow"]= "Up",
  ["LeftArrow"]= "Left",
  ["RightArrow"]= "Right",
  ["Comma"]= ",",
  ["Period"]= ".",
  ["Keypad0"]= "NumPad 0",
  ["Keypad1"]= "NumPad 1",
  ["Keypad2"]= "NumPad 2",
  ["Keypad3"]= "NumPad 3",
  ["Keypad4"]= "NumPad 4",
  ["Keypad5"]= "NumPad 5",
  ["Keypad6"]= "NumPad 6",
  ["Keypad7"]= "NumPad 7",
  ["Keypad8"]= "NumPad 8",
  ["Keypad9"]= "NumPad 9",
  ["KeypadDecimal"]= "NumPad .",
  ["KeypadEnter"]= "Return",
  ["KeypadAdd"]= "NumPad +",
  ["KeypadSubtract"]= "NumPad -",
  ["KeypadDivide"]= "NumPad /",
  ["KeypadMultiply"]= "NumPad *",
  ["NumLock"]= "Clear",
  };
  
  if textConverts[name] then
    return textConverts[name]
  else
    return name
  end
end

function GetCommandByShortcut(section_id, shortcut)
    -- Check REAPER version
    local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
    if version < 6.71 then return end
    -- On MacOS, replace Ctrl with Cmd etc.
    --[[local is_macos = reaper.GetOS():match('OS')
    if is_macos then
        shortcut = shortcut:gsub('Ctrl%+', 'Cmd+', 1)
        shortcut = shortcut:gsub('Alt%+', 'Opt+', 1)
    end]]
    -- Go through all actions of the section
    local sec = reaper.SectionFromUniqueID(section_id)
    local i = 0
    repeat
        local cmd, stringName = reaper.kbd_enumerateActions(sec, i)
        if cmd ~= 0 then
            -- Go through all shortcuts of each action
            for n = 0, reaper.CountActionShortcuts(sec, cmd) - 1 do
                -- Find the action that matches the given shortcut
                local _, desc = reaper.GetActionShortcutDesc(sec, cmd, n, '')
                if desc == shortcut then return cmd, n, stringName end
            end
        end
        i = i + 1
    until cmd == 0
end


function lookForShortcutWithShortcut(shortcut)
    section_id = 0
    action_id, n, stringName = GetCommandByShortcut(section_id, shortcut)
    if action_id then
        action_name = reaper.kbd_getTextFromCmd(action_id, section_id) 
        extensionName = reaper.ReverseNamedCommandLookup(action_id)
        local isExternal = false
        if extensionName and #extensionName > 0 then
            action_id = extensionName
            isExternal = true
        end
        local addCommand = true
        for index, info in ipairs(passThroughKeyCommands) do 
            if info.name == action_name then 
                addCommand = false
            end
        end
        --if addCommand then 
        return {name = action_name, key = lastChar, scriptKeyPress = scriptKeyPress, command = action_id, external = isExternal} 
    end
end

--[[
function findAnyShortCut(shortCut)
    section_id = 0
    action_id, n, stringName = GetCommandByShortcut(section_id, shortCut)
    if action_id then
      action_name = reaper.kbd_getTextFromCmd(action_id, section_id) 
      extensionName = reaper.ReverseNamedCommandLookup(action_id)
      local isExternal = false
      if extensionName and #extensionName > 0 then
          action_id = extensionName
          isExternal = true
      end
      return action_id, isExternal
    end
end
]]

function getPressedShortcut()
    local altKey
    for next_id = 0, math.huge do
        local rv, c = ImGui.GetInputQueueCharacter(ctx, next_id)
        if not rv then break end
        altKey = utf8.char(c)
    end
    
    local modifierText = (isSuperPressed and "Cmd+" or "") .. (isAltPressed and "Opt+" or "") .. (isShiftPressed and "Shift+" or "") .. (isCtrlPressed and "Control+" or "")
    for key, name in pairs(tableOfAllKeys) do
      if reaper.ImGui_IsKeyDown(ctx, key) then 
        if name:match("Left") ~= nil or name:match("Right") ~= nil then
        else
          fullChar = modifierText.. textConvert(name)
          if not lastChar or lastChar ~= fullChar then lastChar = fullChar end
        end
      end
    end
    if not lastChar then lastChar = altKey end
    return lastChar
end

function listeningForKeyCommand()
    lastChar = getPressedShortcut()
    if lastChar then 
        section_id = 0
        action_id, n, stringName = GetCommandByShortcut(section_id, lastChar)
        if action_id then
          action_name = reaper.kbd_getTextFromCmd(action_id, section_id) 
          extensionName = reaper.ReverseNamedCommandLookup(action_id)
          local isExternal = false
          if extensionName and #extensionName > 0 then
              action_id = extensionName
              isExternal = true
          end
          local addCommand = true
          for index, info in ipairs(passThroughKeyCommands) do 
              if info.name == action_name then 
                  addCommand = false
              end
          end
          if addCommand then 
              scriptKeyPress = checkKeyPress() 
              table.insert(passThroughKeyCommands, {name = action_name, key = lastChar, scriptKeyPress = scriptKeyPress, command = action_id, external = isExternal}) 
              reaper.SetExtState(stateName,"passThroughKeyCommands", json.encodeToJson(passThroughKeyCommands), true)
          end
          lastChar = nil
      end
    end
end



if reaper.HasExtState(stateName,"passThroughKeyCommands") then
    passThroughKeyCommandsStr = reaper.GetExtState(stateName,"passThroughKeyCommands")
    passThroughKeyCommands = json.decodeFromJson(passThroughKeyCommandsStr)
else
    passThroughKeyCommands = {}
end


function validateTrack(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return true
    end
end

local function saveTrackSettings(track)
    if validateTrack(track) then
        local trackSettingsStr = json.encodeToJson(trackSettings)
        reaper.GetSetMediaTrackInfo_String(track, "P_EXT" .. ":" .. stateName, trackSettingsStr, true)
    end
end

local function loadTrackSettings(track)
    trackSettings = {}
    if track then
        local hasSavedState, savedTrackStates = reaper.GetSetMediaTrackInfo_String(track, "P_EXT" .. ":" .. stateName, "{}", false)
        if hasSavedState then        
            trackSettings = json.decodeFromJson(savedTrackStates)
            
            for key, value in pairs(defaultTrackSettings) do
                if trackSettings[key] == nil then
                    trackSettings[key] = value
                end
            end
        else
            trackSettings = defaultTrackSettings
            saveTrackSettings(track)
        end 
    end
    return trackSettings
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

function openWebpage(url)
    if reaper.GetOS():match("Win") then
      os.execute('start "" "' .. url .. '"')
    elseif reaper.GetOS():match("mac") then
      os.execute('open "' .. url .. '"')
    else -- Assume Linux
      os.execute('xdg-open "' .. url .. '"')
    end
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
    fxAmount = tonumber(fxAmount)
    if not fxAmount then return end
    if fxAmount == 0 then
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
        modulatorsPos = reaper.TrackFX_AddByName( track, "Container", 0, -1 )
        --modulatorsPos = TrackFX_AddByName( track, "Container", modulatorsPos, -1 ) 
        ret, rename = reaper.TrackFX_SetNamedConfigParm( track, modulatorsPos, 'renamed_name', "Modulators" )
    end
    return modulatorsPos
end

function deleteModule(track, fxIndex, modulationContainerPos, fx)
    if fxIndex then 
        if map == fxIndex then 
            stopMapping()
        end
        
        local mappings = (parameterLinks and parameterLinks[tostring(fxIndex)]) and parameterLinks[tostring(fxIndex)] or {} 
        for i, map in ipairs(mappings) do  
            local mapFxIndex = map.fxIndex
            local mapParam = map.param
            disableParameterLink(track, mapFxIndex, mapParam) 
        end
        
        
        local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
        if trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[guid] then 
            trackSettings.hideParametersFromModulator[guid] = nil
        end
        
        if reaper.TrackFX_Delete(track, fxIndex) then
            selectedModule = false
                
            renameModulatorNames(track, modulationContainerPos)
        end
    end
end

function stopMapping()
    map = false
    sliderNumber = false
end

function mapModulatorActivate(fx, sliderNum, name, fromKeycommand, simple)
    if fx and (not fromKeycommand and isSuperPressed) and trackSettings then
        local newStart = false
        local newVal
        if not trackSettings.bigWaveform[fx.guid] then 
            newVal = settings.visualizerSize + 1
        else
            if trackSettings.bigWaveform[fx.guid] == settings.visualizerSize then
                newVal = nil
            else
                newVal = trackSettings.bigWaveform[fx.guid] + 1
            end
        end
        
        if newVal and newVal > 3 then newVal = 1 end
        trackSettings.bigWaveform[fx.guid] = newVal
        saveTrackSettings(track) 
    else
        if not fx or (map == fx.fxIndex and sliderNumber == sliderNum) then 
            stopMapping()
        else  
            --parameterTouched = nil
            lastParameterTouched = nil
            --fxIndexTouched = nil
            lastFxIndexTouched = nil
            hideParametersFromModulator = nil
            map = fx.fxIndex
            mapName = simple and fx.name or fx.mappingNames[sliderNum]
            sliderNumber = sliderNum
            fxContainerIndex = fx.fxInContainerIndex 
        end
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
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'JS: LFO Native Modulator', "LFO Native")
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.dir', 0)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertACSAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'JS: ACS Native Modulator', "ACS Native")
    
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dir', 0)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dblo', -60)
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dbhi', 12)
    
    local value = settings.defaultAcsTrackAudioChannelInput
    if value < 4 then
        reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.' .. "acs.chan", value)   
    else
        reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.' .. "acs.chan", value == 4 and 0 or 2)
    end 
    reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.' .. "acs.stereo", value < 4 and 0 or 1)
    
    --reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.chan', 2)
    --reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.stereo', 1)
    
    --reaper.TrackFX_SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.visible', 1)
    
    reaper.TrackFX_SetNamedConfigParm( track, modulationContainerPos, 'container_nch', 4)
    reaper.TrackFX_SetNamedConfigParm( track, modulationContainerPos, 'container_nch_in', 4)
    --reaper.TrackFX_SetOpen(track,fxnumber,true)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertFXAndAddContainerMapping(track, name, newName, paramNumber)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, name, newName)
    -- I think we do not want to open the "original", as it opens the fx randomly on add
    --reaper.TrackFX_SetOpen(track,fxnumber,true) -- return to original focus 
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

function movePluginToContainer(track, originalIndex)
    local modulationContainerPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = select(2, reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')) + 1
    local parent_FX_count = reaper.TrackFX_GetCount(track)
    local position_of_container = modulationContainerPos+1
    
    local insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
    
    reaper.TrackFX_CopyToTrack(track, originalIndex, track, insert_position, true)
    
    
    
    return modulationContainerPos, insert_position
end

function getOutputAndInfoForGenericModulator(track,fxIndex,modulationContainerPos)
    local numParams = reaper.TrackFX_GetNumParams(track,fxIndex) 
    local output = {}
    -- make possible to have multiple outputs
    local genericModulatorInfo = {outputParam = -1, indexInContainerMapping = -1}
    for p = 0, numParams -1 do
        --retval, buf = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "param." .. p .. ".container_map.hint_id" )
        -- we would have to enable multiple outputs here later
        retval, buf = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, "container_map.get." .. fxIndex .. "." .. p )
        if retval then
            table.insert(output, p)
            genericModulatorInfo = {outputParam = p, indexInContainerMapping = tonumber(buf)}
            break
        end
    end
    return output, genericModulatorInfo
end

function getOutputArrayForModulator(track, fxName, fxIndex, modulationContainerPos)
    if fxName:match("LFO Native Modulator") then
        return {0}
    elseif fxName:match("ADSR%-1") then
        return {10}
    elseif fxName:match("MSEG%-1") then
        return {10}
    elseif fxName:match("MIDI Fader Modulator") then
        return {0}
    elseif fxName:match("AB Slider Modulator") then
        return {0}
    elseif fxName:match("ACS Native Modulator") then
        return {0}
    elseif fxName:match("4%-in%-1%-out Modulator") then
        return {0}
    elseif fxName:match("Keytracker Modulator") then
        return {0}
    elseif fxName:match("Note Velocity Modulator") then
        return {0} 
    elseif fxName:match("XY Modulator") then
        return {0, 1} 
    elseif fxName:match("Button Modulator") then
        return {0} 
    elseif fxName:match("Macro Modulator") then
        return {0} 
    elseif fxName:match("Macro 4 Modulator") then
        return {0, 4, 8, 12}
    else  
        return getOutputAndInfoForGenericModulator(track,fxIndex,modulationContainerPos)
    end
end


function getModulatorNames(track, modulationContainerPos, parameterLinks)
    if modulationContainerPos then
        local _, fxAmount = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_count')
        local containerData = {}
        local fxIndexs = {}
        allIsCollabsed = true
        allIsNotCollabsed = true
        
        for c = 0, fxAmount -1 do  
            local _, fxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c)  
            local _, fxOriginalName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'original_name')
            local renamed, fxName = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, 'renamed_name')
            local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
            if not renamed or fxName == "" or fxName == nil then 
                fxName = fxOriginalName
            end
            
            local mappings = (parameterLinks and parameterLinks[tostring(fxIndex)]) and parameterLinks[tostring(fxIndex)] or {}
            local output = getOutputArrayForModulator(track, fxOriginalName, fxIndex, modulationContainerPos)
            
            local mappingNames = {}
             
            for _, out in ipairs(output) do
                _, paramName = reaper.TrackFX_GetParamName(track, fxIndex, out)
                local mappingName = fxName 
                if #output > 1 then 
                    mappingName = mappingName .. ": " .. paramName
                end
                mappingNames[out] = mappingName
            end
            
            local isCollabsed = trackSettings.collabsModules[guid]
            --if not nameCount[fxName] then nameCount[fxName] = 1 else nameCount[fxName] = nameCount[fxName] + 1 end
            --table.insert(containerData, {name = fxName .. " " .. nameCount[fxName], fxIndex = tonumber(fxIndex)})
            table.insert(containerData, {name = fxName, fxIndex = tonumber(fxIndex), guid = guid, fxInContainerIndex = c, fxName = fxOriginalName, mappings = mappings, output = output, mappingNames = mappingNames})
            fxIndexs[fxIndex] = true
            if not isCollabsed then allIsCollabsed = false end
            if isCollabsed then allIsNotCollabsed = false end
        end
        return containerData, fxIndexs
    end
end

function getParameterLinkValues(track, fxIndex, param)
    local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.baseline')
    local ret, scale = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale')
    local ret, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.offset')
    return tonumber(baseline), tonumber(scale), tonumber(offset)
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
    local value = reaper.TrackFX_GetParam(track,fxnumber,paramnumber)
    --local range = max - min
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline', value)
    
end

function toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, newValue)
    if not newValue then
        setParameterToBaselineValue(track, fxIndex, param)  
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', 0 )
    else
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', 1 )
        setBaselineToParameterValue(track, fxnumber, param)  
    end
end

function mapParameterToContainer(track, modulationContainerPos, fxIndex, param)
    reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. param )
end

function deleteParameterFromContainer(track, modulationContainerPos, fxIndex, param)
    reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'param.' .. param .. '.container_map.delete' )
end

function setParamaterToLastTouched(track, modulationContainerPos,fxIndex, fxnumber, param, value, offsetForce, scaleForce, valueForce)
    if tonumber(fxnumber) < 0x2000000 then
       ret, outputPos = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. sliderNumber )
    else
       -- could this be done in a better way? -- I need to get the position of the FX inside the container
       outputPos = sliderNumber -- this is the paramater in the lfo plugin 
       modulationContainerPos = fxContainerIndex
    end 
    local retParam, currentOutputPos = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.param')
    local retEffect, currentModulationContainerPos = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.effect')
    if (retParam and outputPos ~= currentOutputPos) or (retEffect and modulationContainerPos ~= currentModulationContainerPos) then 
        local ret, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.baseline')
        local _, isModActive = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.active') 
        isModActive = isModActive == "1"
        if settings.usePreviousMapSettingsWhenOverwrittingMapping and isModActive then
            
            local ret, offset = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.offset')
            local ret, scale = reaper.TrackFX_GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.scale')
            offsetForce = offset
            scaleForce = scale
        end
        value = tonumber(baseline) --+ tonumber(offset)
    end
    useOffset = offsetForce and offsetForce or useOffset
    useScale = scaleForce and scaleForce or useScale
    value = valueForce and valueForce or value
     
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.baseline', value )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.active',1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.offset',useOffset and useOffset or 0 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.scale',useScale and useScale or 1 )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.effect',modulationContainerPos )
    reaper.TrackFX_SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.param', outputPos )
    
end


---------------------------------
----- AB SLIDER FUNCTIONS -------
---------------------------------
function disableAllParameterModulationMappingsByName(name, newValue)
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local params = {}
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        -- Iterate through all parameters for the current FX
        local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
        for p = 0, param_count - 1 do 
            _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local parameterLinkActive = parameterLinkActive == "1"
            
            if parameterLinkActive then
                local _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then
                    local _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline')
                    local _, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
                    local _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )
                    local _, containerItemFxId = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkEffect, 'container_item.'..parameterLinkParam )
                    local _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                    
                    if parameterLinkName:match(name) then
                        --reaper.ShowConsoleMsg(newValue .. " - disabel " .. parameterLinkName .. " on " .. fx_name .. " param: " .. p .. "\n")
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
            local parameterLinkActive = parameterLinkActive == "1"
            
            if parameterLinkActive then
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

function getTrackPluginsParameterLinkValues(name, clearType) 
    local plugin_values = {}
    local fx_count = reaper.TrackFX_GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
        if not fx_name:match("^Modulators") then 
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
            for param = 0, param_count - 1 do
                _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active')
                parameterLinkActive = parameterLinkActive == "1"
                -- we ignore values that have parameter link activated
                if parameterLinkActive then
                    _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.effect' )
                    if parameterLinkEffect ~= "" then
                        _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.param' )
                        _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)
                        if parameterLinkName:match(name) then
                            local baseline, scale, offset = getParameterLinkValues(track, fxIndex, param) 
                            
                            valueNormalized = clearType == "MinValue" and baseline + scale + offset or baseline + offset
                            table.insert(params, {
                                valueNormalized = valueNormalized
                            })
                        end
                    end
                else
                    local valueNormalized = reaper.TrackFX_GetParamNormalized(track, fxIndex, param)
                    --reaper.ShowConsoleMsg(param_name .. "\n")
                    -- Save parameter details
                    table.insert(params, {
                        valueNormalized = valueNormalized,
                        param = param,
                    })
                end
            
                -- Save FX details
                plugin_values[guid] = {
                    number = fxIndex,
                    parameters = params
                }
            end
        end 
    end
    return plugin_values
end

-- TODO: Support folders as well
function getTrackPluginValues(track, fx)
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
    for fxIndex = 0, fx_count - 1 do
        local fx_name_ret, fx_name = reaper.TrackFX_GetFXName(track, fxIndex, "") 
        local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
        if not fx_name:match("^Modulators") then 
            local fx_name_simple = removeBeforeColon(fx_name)
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
            for param = 0, param_count - 1 do
                _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active')
                parameterLinkActive = parameterLinkActive == "1"
                -- we ignore values that have parameter link activated
                if not parameterLinkActive then
                    local valueNormalized = reaper.TrackFX_GetParamNormalized(track, fxIndex, param)
                    --reaper.ShowConsoleMsg(param_name .. "\n")
                    -- Save parameter details
                    table.insert(params, {
                        valueNormalized = valueNormalized,
                        param = param,
                    })
                end
            
                -- Save FX details
                plugin_values[guid] = {
                    name = fx_name_simple,
                    number = fxIndex,
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
    for fx, b_plugin in pairs(a_trackPluginStates) do
        local fx_number = b_plugin.number
        local a_plugin = b_trackPluginStates[fx]

        -- Check if plugin exists in both arrays
        if a_plugin then
            -- Compare plugin names
            if a_plugin.number == b_plugin.number then 
                --reaper.ShowConsoleMsg("2\n")
                -- Compare parameters
                for i, b_states in ipairs(b_plugin.parameters) do 
                    local b_param = b_states.param
                    local a_states = a_plugin.parameters[i]
                    local a_value = a_states.valueNormalized
                    local b_value = b_states.valueNormalized
                    -- Check if parameter exists in both plugins
                    if a_states then
                        --reaper.ShowConsoleMsg("3\n")
                        if a_value ~= b_value then
                        
                            local range = b_value - a_value
                            --reaper.ShowConsoleMsg(a_states.name  .. " - " .. b_param .. " - " .. tostring(a_value) .. " - " .. tostring(b_value) .. " - " .. range .. "\n")
                            --local max = a_states.max
                            --local min = a_states.min
                            --local range = (min and max) and max - min or 1 
                            setParamaterToLastTouched(track, modulationContainerPos, fxIndex, fx_number, b_param, a_value, 0, range, a_value)
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
collabsWidth = 20



--hasModuleState, modulesState = reaper.GetProjExtState(0, stateName, "trackSettings.collabsModules")
--reaper.ShowConsoleMsg(hasModuleState  .. " - " .. modulesState)
--trackSettings.collabsModules = hasModuleState == 1 and unpickle(modulesState) or {}

parametersBaseline = {}
randomPoints = {25,3,68,94,45,70}
 
modulatorNames = {}
lastCollabsModules = {}
sliderNumber = 0

--sortAsType = true
--last_vertical = vertical

--vertical = reaper.GetExtState(stateName, "vertical") == "1"
--hidePlugins = reaper.GetExtState(stateName, "hidePlugins") == "1"
--hideParameters = reaper.GetExtState(stateName, "hideParameters") == "1"
--hideModules = reaper.GetExtState(stateName, "hideModules") == "1"
--modulesHeightVertically = tonumber(reaper.GetExtState(stateName, "modulesHeightVertically")) or 250

--openSelected = true
--includeModulators = true
--trackSelectionFollowFocus = reaper.GetExtState(stateName, "trackSelectionFollowFocus") == "1"
--showToolTip = reaper.GetExtState(stateName, "showToolTip") == "1"
--sortAsType = reaper.GetExtState(stateName, "sortAsType") == "1"


--test = ((((steps + 1) * (n - (n|0)))|0) / steps * 2 - 1)

local function getAllTrackFxParamValues(track,fxIndex)
    local data = {} 
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        for p = 0, paramCount do 
            local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local parameterLinkActive = parameterLinkActive == "1"
            if parameterLinkActive then
                _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then  
                    _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline') 
                    --_, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.offset')
                    --_, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
                    table.insert(data, baseline)
                end
            else 
                local value = reaper.TrackFX_GetParam(track,fxIndex,p)
                table.insert(data, value)
            end
        end
    end
    return data
end

local function setAllTrackFxParamValues(track,fxIndex, settings)
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        for p, val in ipairs(settings) do 
            local value = reaper.TrackFX_SetParam(track,fxIndex,p - 1, val)
        end
    end
end

local nativeLfoList = {"active","dir","phase","speed","strength","temposync","free","shape"}
local function getNativeLFOParamSettings(track,fxIndex) 
    local data = {} 
    for _, l in ipairs(nativeLfoList) do 
        local _, val = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.lfo.' .. l) 
        data[l] = val
    end 
    return data
end

local function setNativeLFOParamSettings(track,fxIndex, settings)  
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.baseline', 0.5)
    for key, val in pairs(settings) do 
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.lfo.' .. key, tonumber(val))  
    end 
end


    
local nativeAcsList = {"active","dir","strength","attack","release","dblo","dbhi","chan","stereo","x2","y2"}
local function getNativeACSParamSettings(track,fxIndex) 
    local data = {} 
    for _, l in ipairs(nativeAcsList) do 
        local _, val = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.acs.' .. l) 
        data[l] = val
    end 
    return data
end

local function setNativeACSParamSettings(track,fxIndex, settings) 
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.active', 1)
    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.baseline', 0.5) 
    for key, val in pairs(settings) do 
        reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.acs.' .. key, tonumber(val))  
    end 
end

local function getAllDataFromParameter(track,fxIndex,p) 
    local fx_name_ret, fxName = reaper.TrackFX_GetFXName(track, fxIndex, "") 
    local retValueName, valueName = reaper.TrackFX_GetFormattedParamValue(track,fxIndex,p)
    local _, name = reaper.TrackFX_GetParamName(track,fxIndex,p)
    local _, parameterLinkActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
    parameterLinkActive = parameterLinkActive == "1" 
    local guid = reaper.TrackFX_GetFXGUID( track, fxIndex )
    
    -- special setting, to rename for nicer view in parameters
    if fxName == "Track controls" then
        name = name:gsub("^Main p%d+:%s*", "")
    end 
    
    local _, parameterModulationActive = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.active')
    parameterModulationActive = parameterModulationActive == "1"
    local mappingName
    local baseline = false
    local width = 0
    local offset = 0
    local direction = 0
    local bipolar = false
    if parameterLinkActive and modulationContainerPos then
        _, parameterLinkEffect = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
        if parameterLinkEffect ~= "" then 
            _, baseline = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.mod.baseline') 
            _, offset = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.offset')
            _, width = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
            _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' ) 
            bipolar = tonumber(offset) == -0.5
            
            if tonumber(width) >= 0 then
                direction = offset * 2 + 1
            else
                direction = math.abs(offset * 2) - 1
            end
            
            -- TODO: we should find the actual fxindex and param within the modulation container, and then gather name etc from there
            if tonumber(fxIndex) < 0x200000 then 
                _, parameterLinkName = reaper.TrackFX_GetParamName(track, parameterLinkEffect, parameterLinkParam)  
                ret, parameterLinkFXIndex = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'param.'..parameterLinkParam..'.container_map.fx_index' )
                -- overwrite the parameter to be the parameter that's within the modulation container
                _, parameterLinkParam = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'param.'..parameterLinkParam..'.container_map.fx_parm' )
                parameterLinkParam = tonumber(parameterLinkParam)
                local _, originalName = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkFXIndex, 'fx_name' )
                
                local outputsForLinkedModulator = getOutputArrayForModulator(track,originalName, parameterLinkFXIndex, modulationContainerPos)
                
                local colon_pos = parameterLinkName:find(":")
                --reaper.ShowConsoleMsg(tostring(parameterLinkName) .. "1\n")
                if #outputsForLinkedModulator == 1 and colon_pos then
                    parameterLinkName = parameterLinkName:sub(1, colon_pos - 1) 
                end
                --reaper.ShowConsoleMsg(tostring(parameterLinkFXIndex) ..  " - " .. parameterLinkEffect .. " - " .. parameterLinkParam .. " - "..#outputsForLinkedModulator  .. " - " .. parameterLinkName .. "\n")
            else
               ret, parameterLinkFXIndex = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, 'container_item.' .. parameterLinkEffect )
               
               if ret then
                  _, parameterLinkName = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkFXIndex, 'renamed_name' )
                  local _, originalName = reaper.TrackFX_GetNamedConfigParm( track, parameterLinkFXIndex, 'fx_name' )
                  local outputsForLinkedModulator = getOutputArrayForModulator(track,originalName, parameterLinkFXIndex, modulationContainerPos)
                  
                  if not parameterLinkName then
                      _, parameterLinkName = reaper.TrackFX_GetFXName(track, parameterLinkIndex)
                  end
                   
                   --reaper.ShowConsoleMsg(tostring(parameterLinkFXIndex) ..  " - " .. parameterLinkEffect .. " - " .. parameterLinkParam .. " - "..#outputsForLinkedModulator  .. " - " .. parameterLinkName .. " - ".. originalName .. "\n")
                  if #outputsForLinkedModulator > 1 then
                      _, paramName = reaper.TrackFX_GetParamName(track, parameterLinkFXIndex, parameterLinkParam)
                      parameterLinkName = parameterLinkName .. ": " .. paramName
                      
                  end
                  --reaper.ShowConsoleMsg(tostring(parameterLinkFXIndex) ..  " - " .. parameterLinkEffect .. " - " .. parameterLinkParam .. " - "..#outputsForLinkedModulator  .. " - " .. parameterLinkName .. "\n")
                  
               end 
            end 
        end 
    else
        parameterLinkEffect = false
    end
    
    local parameterModulationActive = parameterLinkActive and parameterModulationActive -- and parameterLinkEffect
    
    local envelopePointCount, singleEnvelopePointAtStart, usesEnvelope, firstEnvelopeValue, envelopeValueAtPos
    local trackEnvelope = reaper.GetFXEnvelope(track,fxIndex,p,false)
    local usesEnvelope = false
    if trackEnvelope then
        envelopePointCount = reaper.CountEnvelopePoints(trackEnvelope)
        --_, envelopeActive = reaper.GetSetEnvelopeInfo_String(envelope, "ACTIVE", "", false)
        
        usesEnvelope = envelopePointCount > 0-- and envelopeActive == "1"
        if usesEnvelope then
            local playState = reaper.GetPlayState()
            local target_time
            if playState == 0 then --not lastEnvelopeInsertPos or lastEnvelopeInsertPos ~= playPos then
                target_time = reaper.GetCursorPosition()
            else
                target_time = playPos
            end
            
            retval, envelopeValueAtPos, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate( trackEnvelope, target_time, 0, 0 )
            if envelopePointCount == 1 then
                local ret, time, firstEnvelopeValue = reaper.GetEnvelopePoint(trackEnvelope, 0)
                if ret and time == 0 then
                    singleEnvelopePointAtStart = true
                end
            end
        end
    end
    
    local value, min, max = reaper.TrackFX_GetParam(track,fxIndex,p)
    
    local range = max - min
    local valueNormalized = reaper.TrackFX_GetParamNormalized(track, fxIndex, p)
    if min ~= 0 or max ~= 1 and parameterLinkActive then
        --_, fxName = reaper.TrackFX_GetFXName(track, fxIndex)
        
        --reaper.ShowConsoleMsg(fxName .. " : " .. name .. " : " .. min .. " : ".. max .. " : " .. tostring(baseline) .."\n")
        
    end
    local currentValue = value
    if parameterModulationActive and not usesEnvelope and baseline then
        currentValue = tonumber(baseline)
    elseif singleEnvelopePointAtStart and firstEnvelopeValue then
        currentValue = firstEnvelopeValue
    elseif usesEnvelope and envelopeValueAtPos then
        currentValue = envelopeValueAtPos
    end
    
    local currentValueNormalized = (currentValue - min) / range
    --local visualValueNormalized = currentValueNormalized + offset + 
    return {param = p, name = name, currentValue = currentValue, currentValueNormalized = currentValueNormalized,  value = value, valueNormalized = valueNormalized, min = min, max = max, range = range, baseline = tonumber(baseline), width = tonumber(width), offset = tonumber(offset), bipolar = bipolar, direction = direction,
    valueName = valueName, fxIndex = fxIndex, guid = guid,
    parameterModulationActive = parameterModulationActive, parameterLinkActive = parameterLinkActive, parameterLinkEffect = parameterLinkEffect,containerItemFxId = tonumber(containerItemFxId),
    envelope = trackEnvelope, usesEnvelope = usesEnvelope, singleEnvelopePointAtStart = singleEnvelopePointAtStart, envelopeValue = envelopeValueAtPos, parameterLinkParam = parameterLinkParam, parameterLinkName = parameterLinkName,
    fxName = fxName,
    }
end



function hideShowAllTrackEnvelopes(track, ignoreEnvelope, show, onlyActive)
    if not track then return end
  
    local envCount = reaper.CountTrackEnvelopes(track)
    for i = 0, envCount - 1 do
        local envelope = reaper.GetTrackEnvelope(track, i)
        if envelope and envelope ~= ignoreEnvelope then   
            _, envelopeActive = reaper.GetSetEnvelopeInfo_String(envelope, "ACTIVE", "", false)
            envelopeActive = envelopeActive == "1"
            if show then 
                if not onlyActive or envelopeActive then
                    reaper.GetSetEnvelopeInfo_String(envelope, "VISIBLE", "1", true)
                end
            else 
                local singleEnvelopePoint = reaper.CountEnvelopePoints(envelope) == 1
                if singleEnvelopePoint then
                    reaper.DeleteEnvelopePointEx(envelope,-1,0)
                else
                    reaper.GetSetEnvelopeInfo_String(envelope, "VISIBLE", "0", true)
                end
            end
        end
    end
  
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end



function hideTrackEnvelopesUsingSettings(track, ignoreEnvelope)
    if not track then return end
  
    local envCount = reaper.CountTrackEnvelopes(track)
    for i = 0, envCount - 1 do
        local envelope = reaper.GetTrackEnvelope(track, i)
        if envelope and envelope ~= ignoreEnvelope then   
            local envelopePointsCount = reaper.CountEnvelopePoints(envelope)
                
            if settings.hideEnvelopesWithNoPoints and envelopePointsCount == 1 then
                reaper.DeleteEnvelopePointEx(envelope,-1,0)
            else
                if settings.hideEnvelopesWithPoints and envelopePointsCount > 1 then
                    reaper.GetSetEnvelopeInfo_String(envelope, "VISIBLE", "0", true)
                end
            end
        end
    end
  
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

function showAllEnvelopesInTheirLanesOrNot(track, ignoreEnvelope, mediaLane)
    if not track then return end
  
    local envCount = reaper.CountTrackEnvelopes(track)
    for i = 0, envCount - 1 do
        local envelope = reaper.GetTrackEnvelope(track, i)
        if envelope and envelope ~= ignoreEnvelope then 
            reaper.GetSetEnvelopeInfo_String(envelope, "SHOWLANE", mediaLane and "0" or "1", true)
        end
    end
  
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

function armAllVisibleTrackEnvelopes(track, visible, disarm)
    if not track then return end
  
    local envCount = reaper.CountTrackEnvelopes(track)
    for i = 0, envCount - 1 do
        local envelope = reaper.GetTrackEnvelope(track, i)
        if envelope then 
            local isVisible = reaper.GetSetEnvelopeInfo_String(envelope, "SHOWLANE", "1", false)
            isVisible = isVisible == "1"
            if not visibile or isVisible then 
                reaper.GetSetEnvelopeInfo_String(envelope, "ARM", disarm and "0" or "1", true)
            end
        end
    end
  
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end


local function getAllParametersFromTrackFx(track, fxIndex)
    local data = {} 
    if track and fxIndex then
        local paramCount = reaper.TrackFX_GetNumParams(track, fxIndex) - 1
        local pc = settings.maxParametersShown == 0 and paramCount or math.min(paramCount, settings.maxParametersShown)
        for p = 0, pc do
            table.insert(data, getAllDataFromParameter(track,fxIndex,p))
        end
    end
    return data
end


-------------------------------------------
----------CONTAINER FUNCTIONS--------------
-------------------------------------------

function get_fx_id_from_container_path(tr, idx1, ...) -- returns a fx-address from a list of 1-based IDs
  local sc,rv = reaper.TrackFX_GetCount(tr)+1, 0x2000000 + idx1
  for i,v in ipairs({...}) do
    local ccok, cc = reaper.TrackFX_GetNamedConfigParm(tr, rv, 'container_count')
    if ccok ~= true then return nil end
    rv = rv + sc * v
    sc = sc * (1+tonumber(cc))
  end
  return rv
end

function get_container_path_from_fx_id(tr, fxidx) -- returns a list of 1-based IDs from a fx-address
  if fxidx & 0x2000000 then
    local ret = { }
    local n = reaper.TrackFX_GetCount(tr)
    local curidx = (fxidx - 0x2000000) % (n+1)
    local remain = math.floor((fxidx - 0x2000000) / (n+1))
    if curidx < 1 then return nil end -- bad address

    local addr, addr_sc = curidx + 0x2000000, n + 1
    while true do
      local ccok, cc = reaper.TrackFX_GetNamedConfigParm(tr, addr, 'container_count')
      if not ccok then return nil end -- not a container
      ret[#ret+1] = curidx
      n = tonumber(cc)
      if remain <= n then if remain > 0 then ret[#ret+1] = remain end return ret end
      curidx = remain % (n+1)
      remain = math.floor(remain / (n+1))
      if curidx < 1 then return nil end -- bad address
      addr = addr + addr_sc * curidx
      addr_sc = addr_sc * (n+1)
    end
  end
  return { fxid+1 }
end


function fx_map_parameter(tr, fxidx, parmidx) -- maps a parameter to the top level parent, returns { fxidx, parmidx }
  local path = get_container_path_from_fx_id(tr, fxidx)
  if not path then return nil end
  while #path > 1 do
    fxidx = path[#path]
    table.remove(path)
    local cidx = get_fx_id_from_container_path(tr,table.unpack(path))
    if cidx == nil then return nil end
    local i, found = 0, nil
    while true do
      local rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_index",i))
      if not rok then break end
      if tonumber(r) == fxidx - 1 then
        rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_parm",i))
        if not rok then break end
        if tonumber(r) == parmidx then found = true parmidx = i break end
      end
      i = i + 1
    end
    if not found then
      -- add a new mapping
      local rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,"container_map.add")
      if not rok then return nil end
      r = tonumber(r)
      reaper.TrackFX_SetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_index",r),tostring(fxidx - 1))
      reaper.TrackFX_SetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_parm",r),tostring(parmidx))
      parmidx = r
    end
  end
  return fxidx, parmidx
end

--[[

-- example use
track = reaper.GetTrack(0,0);
id = get_fx_id_from_container_path(track, 2, 1, 2, 1) -- test hierarchy
fxidx,fxparm = fx_map_parameter(track,id,5)
env = reaper.GetFXEnvelope(track,fxidx,fxparm,true)
reaper.TrackList_AdjustWindows(true)

]]
-------------------------------------------
-------------------------------------------

function CheckFXParamsMapping(pLinks, track, fxIndex, isModulator)
    local numParams = reaper.TrackFX_GetNumParams(track, fxIndex)
    _, fxName = reaper.TrackFX_GetFXName(track, fxIndex)
    for p = 0, numParams - 1 do
        local _, linkActive = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "param." .. p .. ".plink.active")
        local _, modActive  = reaper.TrackFX_GetNamedConfigParm(track, fxIndex, "param." .. p .. ".mod.active") 
        local isLinkActive = linkActive == "1"
        local isModActive  = modActive == "1"
        if isLinkActive and modulationContainerPos then 
            local _, linkFx = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' ) -- index of the fx that's linked. if outside modulation folder, it will be modulation folder index
            local _, linkParam = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.param' )  -- parameter of the fx that's linked. 
            local _, fxIndexInContainer = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'param.' .. linkParam .. '.container_map.fx_index')
            --local _, linkFxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'param.' .. linkParam .. '.container_map.hint_id')
            if isModulator then 
                linkFxIndex = tostring(get_fx_id_from_container_path(track, modulationContainerPos+1, linkFx + 1)) -- test hierarchy
            else
                _, linkFxIndex = reaper.TrackFX_GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. fxIndexInContainer)
            end
            _, parameterLinkName = reaper.TrackFX_GetParamName(track, isModulator and tonumber(linkFxIndex) or tonumber(modulationContainerPos), tonumber(linkParam))
          
            local _, linkedName = reaper.TrackFX_GetParamName(track, fxIndex, p)
            if not pLinks[linkFxIndex] then pLinks[linkFxIndex] = {} end
            --if not parameterLinks[linkFx][linkParam][fxIndex] then 
              --  parameterLinks[linkFx][linkParam] = 0
            --end
            --parameterLinks[linkFx][linkParam] = parameterLinks[linkFx][linkParam] + 1 
            table.insert(pLinks[linkFxIndex], {fxIndex = fxIndex, param = p})
            
            --reaper.ShowConsoleMsg(pLinks[linkFxIndex][1].fxIndex .. " - " .. linkFxIndex .. " llo\n")
                
            --reaper.ShowConsoleMsg(fxName .. " - " ..parameterLinkName .. " -> " .. linkedName .. " - " .. linkFxIndex .. " - link FX index: " .. linkFx .. " - link FX param: " .. linkParam .. " - FX index in container: " .. fxIndexInContainer .. " - from mod con: " .. tostring(isModulator) .. "\n")
        end
    end 
    return pLinks
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
    
    --reaper.ShowConsoleMsg("\n\n")
    local plugins = {} -- Table to store plugin information
    local containersFetch = {} -- Table to store plugin information
    local pLinks = {} -- table to store all link parameters
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
                local isOpen = reaper.TrackFX_GetOpen(track,fxIndex)
                local isFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                
                pLinks = CheckFXParamsMapping(pLinks, track, fxIndex, isModulator)
                
                table.insert(plugins, {fxIndex = fxIndex, name = fxName, isModulator = isModulator, indent = indent, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, isContainer = isContainer, base1Index = subFxIndex + 1, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
                if isContainer then
                    table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, isContainer = isContainer, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = subFxIndex + 1, indent = indent, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
                end
                
                if isContainer then
                    indent = indent + 1
                    getPluginsRecursively(track, fxIndex, indent, tonumber(container_count), isModulator, fxName)
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
            local isOpen = reaper.TrackFX_GetOpen(track,fxIndex)
            local isFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
            
            pLinks = CheckFXParamsMapping(pLinks, track, fxIndex)
    
            -- Add the plugin information
            table.insert(plugins, {fxIndex = fxIndex, name = fxName, isContainer = isContainer, isModulator = isModulator, fxContainerName = "ROOT", base1Index = fxIndex + 1, indent = 0, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
            if isContainer then
                table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, isContainer = isContainer, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = fxIndex + 1, indent = indent, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating})
            end
            -- If the FX is a container, recursively check its contents
            if isContainer then
                local indent = 1 
                getPluginsRecursively(track, fxIndex, indent, tonumber(container_count), isModulator, fxName)
            end
        end
    end
    
    return plugins, pLinks
        
end



local function getAllMappingsOnTrack(track, modulationContainerPos)
    local data = {}
    if track then
        local numFX = reaper.TrackFX_GetCount(track) 
        for fxIndex = 0, numFX - 1 do
            data[fxIndex] = {}
            --CheckFXParams(data, track, fxIndex, parentFXIndex)
        end
    end
end


local function getAllTrackFXOnTrackSimple(track)
    local fxCount = reaper.TrackFX_GetCount(track)
    local data = {}
    for f = 0, fxCount-1 do
       _, name = reaper.TrackFX_GetFXName(track,f)
       table.insert(data, {fxIndex = f, name = name})
    end
    return data
end

function mapPlotColor()
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),colorMapDark)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),colorMapDark)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),colorMapDark)
end



function setToLastKnownValue(array)
    local result = reaper.new_array(plotAmount)
    for i = 1, #result do
        result[i] = array[#array]
    end
    return result
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

function modulePartButton(name, tooltipText, sizeW, bigText, background, textSize, hover, buttonW, sizeH)
    if settings.vertical then
        return titleButtonStyle(name, tooltipText, sizeW, bigText, background, sizeH)
    else 
        return verticalButtonStyle(name, tooltipText, sizeW, bigText, background, textSize,hover, buttonW)
    end
end


function titleButtonStyle(name, tooltipText, sizeW, bigText, background, sizeH)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),settings.colors.menuBarHover)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),settings.colors.menuBarActive)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and settings.colors.menuBar or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),colorText)
    local clicked = false
    if bigText then reaper.ImGui_PushFont(ctx, font2) end
    
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    if verticalName then
        name = name:upper():gsub(".", "%0\n")
    end
    if reaper.ImGui_Button(ctx,name, sizeW, sizeH) then
        clicked = true
    end 
    
    if bigText then reaper.ImGui_PopFont(ctx) end
    
    if reaper.ImGui_IsItemHovered(ctx) and settings.showToolTip and tooltipText and tooltipText ~= "" then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorText)
        reaper.ImGui_SetTooltip(ctx,tooltipText )  
        reaper.ImGui_PopStyleColor(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx,4)
    reaper.ImGui_PopStyleVar(ctx)
    if background then 
        local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
        local endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , endPosX, endPosY, colorGrey,4)
    end
    return clicked 
end


function verticalButtonStyle(name, tooltipText, sizeW, verticalName, background, textSize, hover, buttonW)
    --ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),background and menuGreyHover or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),(background or hover) and settings.colors.menuBarHover or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),background and  settings.colors.menuBarActive or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and  settings.colors.menuBar or colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),colorText)
    local clicked = false 
    
    reaper.ImGui_PushFont(ctx, font2)
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    
    local points, lastPos = textToPointsVertical(name,0, 0, textSize and textSize or 11, 3)
    
    
    reaper.ImGui_PopFont(ctx)
    
    if reaper.ImGui_Button(ctx, "##"..name,buttonW and buttonW or (textSize and textSize +9 or 20), sizeW and sizeW or lastPos + 14) then
        clicked = true
    end 
    
    local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
    local text_pos_x = startPosX +4
    local text_pos_y = startPosY +6
    
    for _, line in ipairs(points) do
        reaper.ImGui_DrawList_AddLine(draw_list, text_pos_x + line[1], text_pos_y +line[2],  text_pos_x + line[3],text_pos_y+ line[4], colorText, 1.2)
    end 
    
    if tooltipText and reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx,tooltipText )  
    end
    reaper.ImGui_PopStyleColor(ctx,4)
    
    reaper.ImGui_PopStyleVar(ctx)
    if background then
        
        startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx) 
        endPosX, endPosY = reaper.ImGui_GetItemRectMax(ctx)
        reaper.ImGui_DrawList_AddRect(draw_list, startPosX, startPosY , endPosX, endPosY, colorGrey,4)
    end
    return clicked 
end

function setToolTipFunc(text, color)
    if settings.showToolTip and text and #tostring(text) > 0 then  
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Border(),colorTextDimmed) 
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorText) 
        ImGui.SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx,2)
    end
end


function setToolTipFunc3(text1, text2, text3)
    if settings.showToolTip and text1 and #text1 > 0 then  
        --ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorText) 
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Border(),colorTextDimmed) 
        reaper.ImGui_BeginTooltip(ctx)
        
        reaper.ImGui_TextColored(ctx, colorText, text1)
        if text2 then
            reaper.ImGui_TextColored(ctx, colorTextDimmed, text2)
        end
        if text3 then
            reaper.ImGui_TextColored(ctx, colorText, text3)
        end
        reaper.ImGui_EndTooltip(ctx)
        --ImGui.SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx)
    end
end


function setToolTipFunc2(text,color)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorText)  
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx,addNewlinesAtSpaces(text,26))
    reaper.ImGui_EndTooltip(ctx)
    reaper.ImGui_PopStyleColor(ctx)
end

function lastItemClickAndTooltip(tooltipText)
    local clicked
    if reaper.ImGui_IsItemHovered(ctx) then
        if settings.showToolTip and tooltipText then reaper.ImGui_SetTooltip(ctx,tooltipText) end
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
         if settings.showToolTip then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces(tooltipText,26)) end
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

------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------
----------------------------------CUSTOM SLIDERS------------------------------------------------
------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------

local sliderGrabWidth = 2 
local sliderHeight = 20


function safePow(base, exp)
    -- Prevent issues with negative or zero base when using fractional exponents
    if base < 0 then return 0 end
    if base == 0 then return 0 end
    return base ^ exp
end

function getLogPosition(value, min, max, curve)
    local log_min = math.log(min)
    local log_max = math.log(max)
    local log_value = math.log(value)
    local position = (log_value - log_min) / (log_max - log_min)
    return position ^ (1 / (curve or 1))  -- Use ^ instead of math.pow
end

function scaleLog(position, min, max, curve)
    local log_min = math.log(min)
    local log_max = math.log(max)
    local curved = safePow(position, curve or 1)
    local log_value = log_min + (log_max - log_min) * curved
    local newVal = math.exp(log_value)
    --reaper.ShowConsoleMsg(tonumber(newVal) .. " - " .. curved .. "\n")
    
    return newVal --math.max(min, math.min(max, newVal))
end

function getPosXForLine(posXOffset, sliderWidthAvailable, value, sliderFlags, min, max)
    local relativeValue = (value - min) / (max - min)
    local logValue = sliderFlags and ((math.log(1 + 3999 * relativeValue) / math.log(4000))) or relativeValue
    --if logValue < min then logValue = min end
    --if logValue > max then logValue = max end
    local val = posXOffset +  logValue * sliderWidthAvailable
    if val < posXOffset then val = posXOffset end
    if val > posXOffset + sliderWidthAvailable then val = posXOffset + sliderWidthAvailable end
    return val
end

function getPosXForLineNormalized(posXOffset, sliderWidthAvailable, value)
    --if logValue < min then logValue = min end
    --if logValue > max then logValue = max end
    local val = posXOffset + value * sliderWidthAvailable
    if val < posXOffset then val = posXOffset end
    if val > posXOffset + sliderWidthAvailable then val = posXOffset + sliderWidthAvailable end
    return val
end


function nativeReaperModuleParameter(track, fxIndex, paramOut,  _type, paramName, visualName, min, max, divide, valueFormat, sliderFlags, checkboxFlipped, dropDownText, dropdownOffset,tooltip, width, resetValue) 
    local buttonId = fxIndex .. paramName .. "native"
    local faderWidth = width / 2  
    local nameOnSideWidth = faderWidth - 8
    local range = max - min
    local faderResolution = faderWidth / range
    local sliderWidthAvailable = (faderWidth - (sliderGrabWidth) - 4) 
    local colorPos = colorSliderBaseline
    local valueColor = colorText
    local textColor = colorText
    local name = visualName
    
    
    local ret, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)    
    if ret and tonumber(currentValue) then
        currentValue = tonumber(currentValue)
        --local currentValueNormalized = p.currentValueNormalized
        valueFormat = (ret and tonumber(currentValue * divide)) and string.format(valueFormat, tonumber(currentValue * divide)) or ""
        
    --function nativeReaperModuleParameter(nameOnSide, buttonId, currentValue,  min, max, divide, valueFormat, sliderFlags, width, _type, colorPos, p, resetValue)
        
        reaper.ImGui_InvisibleButton(ctx, "slider" .. buttonId, faderWidth > 0 and faderWidth or 1, sliderHeight) 
        
        if reaper.ImGui_IsItemHovered(ctx) then
            if not dragKnob then 
                dragKnob = buttonId
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y
                if not isMouseDown then 
                    setToolTipFunc("Set " .. name .. "\n - press Shift for fine resolution")
                end
            end  
        end
         
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local posXOffset = minX + sliderGrabWidth /2 + 2 
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
        
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        if not canBeMapped then
            reaper.ImGui_SameLine(ctx)
            if textButtonNoBackgroundClipped(visualName, textColor,nameOnSideWidth) and resetValue then 
                if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, resetValue/divide) end 
            end
        end
        
        endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
        parEndPosX, parEndPosY = reaper.ImGui_GetItemRectMax(ctx)
        
        drawCustomSlider(valueFormat, valueColor, colorPos, currentValue, posXOffset, minX, minY, maxX, maxY, sliderWidthAvailable, sliderFlags,  min, max, sliderGrabWidth)
        
        --[[
        if dragKnob and dragKnob == buttonId then
            local amount
            local changeResolution = isFineAdjust and faderResolution * settings.fineAdjustAmount or faderResolution
            if isMouseDown then 
                if reaper.ImGui_IsMouseClicked(ctx, 0) and nameOnSide then
                    --reaper.ShowConsoleMsg(faderResolution .. "\n")
                end
                mouseDragWidth = (mouse_pos_x - mouseDragStartX) - (dragKnob:match("Window") ~= nil and (mouse_pos_y - mouseDragStartY) * (isApple and -1 or 1) or 0)
                amount = currentValueNormalized + mouseDragWidth / changeResolution
                if sliderFlags then
                    local curve = 0.5 
                    amount = scaleLog(amount, min, max, curve)
                end
                    
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y
            elseif isScrollValue and scrollVertical and scrollVertical ~= 0 then
                amount = currentValueNormalized - ((scrollVertical * ((settings.scrollValueSpeed+50)/100)) / changeResolution)
            else
                --dragKnob = nil
                -- TRIED DISABLING THESE, SO SCROLL ALSO WORKS WITH FINE VALUES
                --missingOffset = nil
                --lastAmount = nil
            end
            if amount then 
                if amount < 0 then amount = 0 end
                if amount > 1 then amount = 1 end 
                if amount ~= currentValueNormalized then  
                    
                    local addOffset = missingOffset and missingOffset or 0 -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference
                    local newVal = (amount + addOffset) * range + min
                    
                    if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newVal) end  
                    _, newAmount = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)
                    newAmount = tonumber(newAmount)
                     
                    newAmountRelative = newAmount and (newAmount - min) / range or 0
                    -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference to the next time
                    if lastAmount and lastAmount == amount then
                        missingOffset = amount - newAmountRelative + (missingOffset and missingOffset or 0)
                    else
                    --reaper.ShowConsoleMsg(tostring(lastAmount) .. " == " .. amount .. "reset\n")
                        missingOffset = 0
                    end
                    lastAmount = amount
                    -----
                end
            end 
        end
        ]]
        if dragKnob and dragKnob == buttonId then
            local amount
            local changeResolution = isFineAdjust and faderResolution * settings.fineAdjustAmount or faderResolution
            if isMouseDown then  
                mouseDragWidth = (mouse_pos_x - mouseDragStartX) - (dragKnob:match("Window") ~= nil and (mouse_pos_y - mouseDragStartY) * (isApple and -1 or 1) or 0)
                valueChange = mouseDragWidth / changeResolution
                if sliderFlags then
                    local curve = 0.5 
                    local valueNormalized = getLogPosition(currentValue, min, max, curve)
                    local changeRelative = (valueChange * 4) / sliderWidthAvailable
                    local newVal = valueNormalized + changeRelative
                    amount = scaleLog(newVal, min, max, curve)
                else
                    amount = currentValue + ((mouse_pos_x - mouseDragStartX)) / changeResolution
                end 
                
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y
            elseif isScrollValue and scrollVertical and scrollVertical ~= 0 then
                amount = currentValue - (scrollVertical * ((settings.scrollValueSpeed+50)/100)) / changeResolution
            else
                dragKnob = nil
            end
            if amount then 
                
                if amount < min then amount = min end
                if amount > max then amount = max end 
                if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, amount) end  
            end
            
            ignoreScrollHorizontal = true
        end
        
    end
    
    --[[
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
            -- this could probably be unified
            if useFineFaders then
                ret, newValue = pluginParameterSlider(currentValue, fxIndex .. paramName, visualName, min, max, divide, valueFormat, sliderFlags, buttonWidth, "Double", {})
            else
            -- was the usual slider.
                reaper.ImGui_PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 2) 
            ret, newValue = reaper.ImGui_SliderDouble(ctx, visualName .. '##' .. paramName .. fxIndex, currentValue*divide, min, max, valueFormat, sliderFlags)
                reaper.ImGui_PopStyleVar(ctx)
            end
            
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue/divide) end  
        elseif _type == "Combo" then 
            ret, newValue = reaper.ImGui_Combo(ctx, visualName .. '##' .. paramName .. fxIndex, tonumber(currentValue)+dropdownOffset, dropDownText )
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue-dropdownOffset) end
            scrollValue = divide
        end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end
        scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, 'param.'..paramOut..'.' .. paramName, scrollValue)
        
    end
    return newValue and newValue or currentValue
    ]]
end

function drawCustomSlider(valueFormat, valueColor, colorPos ,currentValue, posXOffset, minX, minY, maxX, maxY, sliderWidthAvailable, sliderFlags, min, max, sliderGrabWidth,hasLink, linkValue, linkWidth, baseline, offset)
    -- background
    reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, minY, maxX, maxY, settings.colors.sliderBackground, 2) 
    
    local posX = getPosXForLine(posXOffset, sliderWidthAvailable, currentValue, sliderFlags, min, max)
    -- baseline value
    reaper.ImGui_DrawList_AddLine(draw_list, posX, minY+2, posX, maxY-2, colorPos,sliderGrabWidth)
    
    if hasLink then  
        local widthColor = linkWidth >= 0 and settings.colors.sliderWidth or settings.colors.sliderWidthNegative
        local initialValue = baseline + (offset * linkWidth) + (linkWidth < 0 and linkWidth or 0)  -- (direction == -1 and - math.abs(linkWidth) or (direction == 0 and - math.abs(linkWidth)/2 or 0))
        
        local posX1 = getPosXForLineNormalized(posXOffset, sliderWidthAvailable, initialValue)
        local posX2 = getPosXForLineNormalized(posXOffset, sliderWidthAvailable, initialValue + math.abs(linkWidth)) --getPosXForLine(posXOffset, sliderWidthAvailable, initialValue + linkWidthAsValue, sliderFlags, min, max)
        -- width bar below
        reaper.ImGui_DrawList_AddLine(draw_list, posX1, maxY-2, posX2, maxY-2, widthColor,2)
        
        
        local posX = getPosXForLine(posXOffset, sliderWidthAvailable, linkValue, sliderFlags, min, max)
        -- playing value
        reaper.ImGui_DrawList_AddLine(draw_list, posX, minY+2, posX, maxY-2, settings.colors.sliderOutput,sliderGrabWidth)
    end
    
    
    local textW = reaper.ImGui_CalcTextSize(ctx, valueFormat, 0, 0)
    -- value text
    reaper.ImGui_DrawList_AddText(draw_list, posXOffset + sliderWidthAvailable/2 - textW/2, minY+2, valueColor, valueFormat)
end

function textButtonNoBackgroundClipped(text, color, width, id)
    local click = false
    id = id and id or ""
    if reaper.ImGui_InvisibleButton(ctx, "##".. text .. id,width > 0 and width or 1, 20) then
        click = true
    end 
    local p0_x, p0_y = ImGui.GetItemRectMin(ctx)
    local p1_x, p1_y = ImGui.GetItemRectMax(ctx)
    ImGui.PushClipRect(ctx, p0_x, p0_y, p1_x, p1_y, true)
    reaper.ImGui_DrawList_AddText(draw_list, p0_x, p0_y+2, color, text) 
    ImGui.PopClipRect(ctx) 
    return click
end

 
function changeDirection(track, p)
    if p.direction == -1 then
        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset',  -0.5)
    elseif p.direction == 1 then
        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset',  p.width < 0 and 0 or -1)
    else 
        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset',  p.width < 0 and -1 or 0)
    end 
end
    
function envelopeHasPointAtTime(envelope, target_time, time_tolerance)
  local point_count = reaper.CountEnvelopePoints(envelope)
  for i = 0, point_count - 1 do
    local retval, time = reaper.GetEnvelopePoint(envelope, i)
    if retval and math.abs(time - target_time) <= time_tolerance then
      return i -- Found a point close enough
    end
  end
  return false
end

function setEnvelopePointAdvanced(track, p, amount)
    if p.singleEnvelopePointAtStart and isAutomationRead then
        reaper.SetEnvelopePoint(p.envelope,0, 0, amount, nil,nil,nil)
    elseif not isAutomationRead then
        reaper.TrackFX_SetParam(track, p.fxIndex, p.param, amount)
        return reaper.TrackFX_GetParam(track, p.fxIndex, p.param)
    end
    
    -- this seems not necisarry as it's handled by reaper through write types
    if lol then
        if p.singleEnvelopePointAtStart then
            reaper.SetEnvelopePoint(p.envelope,0, 0, amount, nil,nil,nil)
        else
            local playState = reaper.GetPlayState() 
            local stopped = playState == 0
            local target_time
            if stopped then --not lastEnvelopeInsertPos or lastEnvelopeInsertPos ~= playPos then
                target_time = reaper.GetCursorPosition()
            else
                target_time = playPos
            end
            
            
            function insertOrEditEnvelopePoint(playState, pointAtPos, target_time, insertAfter)
                if not pointAtPos then 
                    if settings.insertEnvelopeBeforeAddingNewEnvelopePoint and (playState == 0 or playState == 2) then 
                        reaper.InsertEnvelopePoint(p.envelope, target_time + (insertAfter and 0.0005 or - 0.0005), amount, 0, 0, true)
                    end
                    reaper.InsertEnvelopePoint(p.envelope, target_time, amount, 0, 0, true)
                else 
                    reaper.SetEnvelopePoint(p.envelope,pointAtPos, target_time, amount, nil,nil,nil)
                end
            end
            
            if stopped then
                local loopStart, loopEnd, pointAtPos
                if settings.insertEnvelopePointsAtTimeSelection and stopped then
                    loopStart, loopEnd = reaper.GetSet_LoopTimeRange(false, false, 0,0,false)
                    if loopStart < loopEnd then
                        reaper.SetEditCurPos(loopStart, false, false)
                        
                        pointAtPosStart = envelopeHasPointAtTime(p.envelope, loopStart, 0.0001) 
                        insertOrEditEnvelopePoint(playState, pointAtPosStart, loopStart, false)
                        pointAtPosEnd = envelopeHasPointAtTime(p.envelope, loopEnd, 0.0001)
                        insertOrEditEnvelopePoint(playState, pointAtPosEnd, loopEnd, true)
                    else 
                        pointAtPos = envelopeHasPointAtTime(p.envelope, target_time, 0.0001)
                        insertOrEditEnvelopePoint(playState, pointAtPos, target_time)
                    end
                else 
                    pointAtPos = envelopeHasPointAtTime(p.envelope, target_time, 0.0001)
                    insertOrEditEnvelopePoint(playState, pointAtPos, target_time)
                end
            end
            
        end
    end
end

function setParameterFromFxWindowParameterSlide(track, p)
    if p.usesEnvelope then
        if p.parameterLinkActive then
            momentarilyDisabledParameterLink = true
            reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.active', "0")
        end
        setEnvelopePointAdvanced(track, p, p.value)
    elseif p.parameterLinkActive then 
        momentarilyDisabledParameterLink = true
        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.active', "0")
        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline', p.value) 
        --reaper.TrackFX_SetParam(track, p.fxIndex, p.param, p.value)
    else 
        reaper.TrackFX_SetParam(track, p.fxIndex, p.param, p.value)
    end
end

function setParam(track, p, amount)
    
    ignoreFocusBecauseOfUiClick = true
    ignoreThisIndex = p.fxIndex
    ignoreThisParameter = p.param
    
    if p.param and p.param > -1 then
        updateVisibleEnvelopes(track, p)
        if p.usesEnvelope then 
            return setEnvelopePointAdvanced(track, p, amount)
        elseif p.parameterLinkEffect and p.parameterModulationActive then
            reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline', amount ) 
            local ret, newVal = reaper.TrackFX_GetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline') 
            return newVal 
            
        else 
            reaper.TrackFX_SetParam(track, p.fxIndex, p.param, amount)
            return reaper.TrackFX_GetParam(track, p.fxIndex, p.param)
        end
        
    end 
end

function setParameterValuesViaMouse(track, buttonId, moduleId, p, range, min, currentValue, faderResolution) 
    local currentValueNormalized = p.currentValueNormalized
    local linkWidth = p.width or 1
    
    
    function setWidthValue(track, p)
        local amount
        local grains = (isFineAdjust and 100 * settings.fineAdjustAmount or 100)
        if isMouseDown then 
            amount = p.width + ((mouse_pos_x - mouseDragStartX) - (mouse_pos_y - mouseDragStartY) * (isApple and -1 or 1)) / grains
            mouseDragStartX = mouse_pos_x
            mouseDragStartY = mouse_pos_y
        elseif isScrollValue and scrollVertical and scrollVertical ~= 0 then
            amount = p.width - (scrollVertical * ((settings.scrollValueSpeed+50)/100)) / grains
        else
            dragKnob = nil
        end
        if amount and amount ~= p.width then  
            if amount < minWidth then amount = minWidth end
            if amount > 1 then amount = 1 end 
            
            if not settings.mappingModeBipolar then
                if amount < 0 then 
                    if p.direction == -1 and linkOffset ~= 0 then 
                        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', 0 )
                    elseif p.direction == 1 and linkOffset ~= -1 then 
                        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', -1 )
                    end
                elseif amount >= 0 then
                    if p.direction == -1 and linkOffset ~= -1 then 
                        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', -1 )
                    elseif p.direction == 1 and linkOffset ~= 0 then 
                        reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', 0 )
                    end 
                end
            end
            
            
            reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.scale', amount )
            --reaper.ImGui_SetTooltip(ctx, parameterLinkName .. " width:\n" .. linkWidth * 100 .. "%")
        end
        
        ignoreScrollHorizontal = true
    end
    
    
    
    if p.parameterLinkActive then 
        if dragKnob and dragKnob == "width" .. buttonId .. moduleId then
            setWidthValue(track, p, linkWidth)
        end
    end
    
    
    if isMouseWasReleased then
        -- tried putting them here
        missingOffset = nil
        lastAmount = nil
        dragKnob = nil
        lastDragKnob = nil
        
        if p.usesEnvelope and undoStarted then
            --reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param ..'.plink.active',1 )
            reaper.Undo_EndBlock("Inserting envelope points", 0)
            undoStarted = false
        end
    end
    
    if isMouseDown and dragKnob and dragKnob ~= lastDragKnob and dragKnob:match("Window") == nil then 
        lastDragKnob = dragKnob
        -- we reset values whenever we focus a new area
        missingOffset = nil
        lastAmount = nil
        dragKnob = nil
        if p.usesEnvelope then
            reaper.Undo_BeginBlock() 
            --reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param ..'.plink.active',0 )
            undoStarted = true
        end
    end
    
    
    if dragKnob and dragKnob == "baseline" .. buttonId .. moduleId then
         if isChangeBipolar and reaper.ImGui_IsMouseClicked(ctx,0) then 
            if settings.mappingModeBipolar then
                toggleBipolar(track, p.fxIndex, p.param, p.bipolar)
            else
                changeDirection(track, p)
            end
        elseif (isAdjustWidth and not map) or (not isAdjustWidth and map) then
            if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then 
            else
                setWidthValue(track, p, linkWidth)
            end
        else 
            local amount
            local changeResolution = isFineAdjust and faderResolution * settings.fineAdjustAmount or faderResolution
            if isMouseDown then 
                if reaper.ImGui_IsMouseClicked(ctx, 0) and nameOnSide then
                    --reaper.ShowConsoleMsg(faderResolution .. "\n")
                end
                mouseDragWidth = (mouse_pos_x - mouseDragStartX) - (dragKnob:match("Window") ~= nil and (mouse_pos_y - mouseDragStartY) * (isApple and -1 or 1) or 0)
                amount = currentValueNormalized + mouseDragWidth / changeResolution
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y
            elseif isScrollValue and scrollVertical and scrollVertical ~= 0 then
                amount = currentValueNormalized - ((scrollVertical * ((settings.scrollValueSpeed+50)/100)) / changeResolution)
            else
                --dragKnob = nil
                -- TRIED DISABLING THESE, SO SCROLL ALSO WORKS WITH FINE VALUES
                --missingOffset = nil
                --lastAmount = nil
            end
            if amount then 
                if amount < 0 then amount = 0 end
                if amount > 1 then amount = 1 end 
                if amount ~= currentValueNormalized then  
                    
                    local addOffset = missingOffset and missingOffset or 0 -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference
                    local newVal = (amount + addOffset) * range + min
                    newAmount = setParam(track, p, newVal)
                     
                    newAmountRelative = newAmount and (newAmount - min) / range or 0
                    -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference to the next time
                    if lastAmount and lastAmount == amount then
                        missingOffset = amount - newAmountRelative + (missingOffset and missingOffset or 0)
                    else
                    --reaper.ShowConsoleMsg(tostring(lastAmount) .. " == " .. amount .. "reset\n")
                        missingOffset = 0
                    end
                    lastAmount = amount
                    -----
                end
            end
            
            ignoreScrollHorizontal = true
        end
    end
    
    
end

function pluginParameterSlider(moduleId,nameOnSide, divide, valueFormat, sliderFlags, width, _type, p, showingMappings, resetValue, genericModulatorOutput, parametersWindow, dontShowName, doNotSetFocus)
    
    if not p or not p.fxIndex then return end
    
    ImGui.BeginGroup(ctx)  
    
    local min = p.min or 0
    local max = p.max or 1
    local divide = divide or 1
    local range = max - min
    
    local parameterLinkActive = p.parameterLinkActive
    local parameterModulationActive = p.parameterModulationActive
    local hasLink = parameterLinkActive and parameterModulationActive
    
    local parameterLinkEffect = p.parameterLinkEffect
    
    local linkValue = p.valueNormalized -- p.value 
    local linkOffset = p.offset
    local linkWidth = p.width or 1
    local fxIndex = p.fxIndex
    local param = p.param
    local valueName = p.valueName
    local parameterLinkName = p.parameterLinkName 
    local name = p.name and p.name or "NA"
    
    local buttonId = fxIndex .. ":" .. param
    
    width = width < 20 and 20 or width
    
    local areaWidth = width - 2
    local faderWidth = nameOnSide and areaWidth / 2 or areaWidth
    local sliderWidthAvailable = (faderWidth - (sliderGrabWidth) - 4)
    local nameOnSideWidth = faderWidth - 8
    
    local valueNormalized = p.valueNormalized
    local direction = p.direction
    
    
    local parStartPosX, parStartPosY, parEndPosX, parEndPosY
    
    local startPosX, startPosY = reaper.ImGui_GetCursorPos(ctx)
    -- we move elements slightly to make sure they are not covered by the line around
    reaper.ImGui_SetCursorPos(ctx, startPosX + 1, startPosY)
    local faderResolution = sliderWidthAvailable --/ range
    
    --local currentValue = p.usesEnvelope and p.envelopeValue or ((parameterLinkEffect and parameterModulationActive) and p.baseline or p.value) 
    --currentValue = currentValue or 0
    local currentValueNormalized = p.currentValueNormalized -- (p.currentValue - min) / range
    
    local baseline = currentValueNormalized--(p.baseline and p.baseline or currentValue ) / range
    
    local canBeMapped = map and (not parameterLinkActive or (parameterLinkActive and mapName ~= parameterLinkName)) 
    -- if we map from a generic modulator
    local isGenericOutput = param == genericModulatorOutput
    local mapOutput = genericModulatorOutput == -1
    -- we check if any overlay is active
    local overlayActive = canBeMapped or mapOutput or (hideParametersFromModulator == p.guid)
    
    
    local bgColor = isMapping and colorMapping or settings.colors.modulatorOutputBackground
    if settings.pulsateMappingButton and isMapping then 
        padColor = colorMappingPulsating
    end
    local mappedColorOnMappingParam = (not map or not settings.pulsateMappingButtonsMapped or canBeMapped) and colorMapping or colorMappingPulsating
    local padColor = parameterModulationActive and mappedColorOnMappingParam or colorMappingLight
    
    local textColor = overlayActive and colorTextDimmed or colorText
    local valueColor = textColor
    if (paramnumber ~= param and not nameOnSide and parametersWindow) then
        --textColor = colorTextDimmed
    end
    
    -- we overwrite text and value color if it's a generic modulator output
    if isGenericOutput then
        valueColor = colorBlue
        textColor = colorBlue
        overlayActive = false
    end
    local colorPos = colorSliderBaseline
    
    if name == "Phase" then 
        --reaper.ShowConsoleMsg(tostring(p.baseline) .. "\n")
    end
    
    
    
    -- for hiding parameters
    if hideParametersFromModulator and hideParametersFromModulator == p.guid then
        if not trackSettings.hideParametersFromModulator then trackSettings.hideParametersFromModulator = {} end
        if not trackSettings.hideParametersFromModulator[p.guid] then trackSettings.hideParametersFromModulator[p.guid] = {} end
    end
    
    local showName = type(nameOnSide) == "string" and nameOnSide or name
    
    function toggleBipolar(track, fxIndex, param, bipolar)
        if bipolar then
            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  0)
        else 
            reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  -0.5)
        end 
    end
    
    function drawModulatorDirection(size, p, track, fxIndex, param, buttonId, offsetX, offsetY, color, toolTip) 
        local pad = 4
        local bipolar = p.bipolar
        local direction = p.direction
        local width = p.width
        local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
        reaper.ImGui_SetCursorPos(ctx, curPosX + offsetX, curPosY + offsetY)
        local click = false
        if reaper.ImGui_InvisibleButton(ctx, "##direction" .. buttonId, size - pad*2,size) then
            click = true
        end
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
        minX = minX + pad / 2
        minY = minY + pad - 1
        size = size - pad * 2
        local angle = 4
        --local color = color and color obipolar and (colorOn and colorOn or colorMapping) or colorTextDimmed
        -- vertical line
        reaper.ImGui_DrawList_AddLine(draw_list, minX + size/2, minY, minX + size/2, minY+size, color)
        -- top arrow 
        if settings.mappingModeBipolar and (bipolar or width >= 0) or (direction >= 0) then
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size/angle, minY + size / angle, minX + size/2, minY, color)
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size-size/angle, minY + size / angle, minX + size/2, minY, color)
        end
        
        -- bottom arrow
        if settings.mappingModeBipolar and (bipolar or width < 0) or (direction <= 0) then
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size/angle, minY + size - size / angle, minX + size/2, minY+size, color)
            reaper.ImGui_DrawList_AddLine(draw_list, minX+size-size/angle, minY + size - size / angle, minX + size/2, minY + size, color)
        end
        
        if not overlayActive then  
            local toolTipTextHere
            if not settings.mappingModeBipolar then
                local curDir = directions[p.direction+2]
                -- TODO: maybe make a relative pos or find closest
                toolTipTextHere = "Direction: " .. curDir .. "\nClick to change"
            else
                local toolTipTextHere = (bipolar and "Modulation is bipolar" or "Modulation is not bipolar") .. "\nClick to change"
            end
            if parameterModulationActive then
                toolTip = toolTipTextHere
            end
            toolTip = toolTip and toolTip or toolTipeTextHere
            
            setToolTipFunc(toolTip)
        end
        return click
    end
    
    function modulatorMappingItems()
        if showingMappings or (not showingMappings and settings.showExtraLineInParameters) then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
            if parameterLinkActive then
                local nameForText = showingMappings and p.name or parameterLinkName
                local toolTipText = (parameterModulationActive and 'Disable' or 'Enable') .. ' "' .. parameterLinkName .. '" parameter modulation of ' .. p.name 
                local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
                local posXOffset = 1 + (showingMappings and 0 or 1)
                local posYOffset = 1
                
                if showingMappings then 
                     parStartPosX, parStartPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                end
                
                reaper.ImGui_SetCursorPos(ctx, curPosX + posXOffset, curPosY + posYOffset)
                
                if (not showingMappings and settings.showEnableInParameters) or (showingMappings and settings.showEnableInMappings) then
                    
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), padColor)
                    local ret, newValue = reaper.ImGui_Checkbox(ctx, "##enable" .. buttonId, parameterModulationActive)
                    if ret and param > -1 then
                        toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, newValue)
                        ignoreScroll = true
                    end 
                    reaper.ImGui_PopStyleColor(ctx)
                    if not overlayActive then setToolTipFunc(toolTipText) end
                    
                    posXOffset = posXOffset + 22
                    
                    --reaper.ImGui_SameLine(ctx)
                end
                
                
                if not overlayActive or (overlayActive and not showingMappings) then
                    
                    --if parameterModulationActive then
                        if (not showingMappings and settings.showWidthInParameters) or (showingMappings and settings.showWidthInMappings) then
                             
                            reaper.ImGui_SetCursorPos(ctx, curPosX + posXOffset, curPosY + posYOffset)
                            
                            local overlayText = isMouseDown and "Width\n" .. math.floor(linkWidth * 100) .. "%"
                            if specialButtons.knob(ctx, "width" .. buttonId .. moduleId, 0, 0, 20,minWidth == 0 and linkWidth or linkWidth / 2 + 0.5, overlayText,  parameterModulationActive and colorText or colorTextDimmed, settings.colors.buttons, padColor, settings.colors.buttonsActive) then
                                
                                if not dragKnob then
                                    dragKnob = "width" .. buttonId .. moduleId
                                    mouseDragStartX = mouse_pos_x
                                    mouseDragStartY = mouse_pos_y
                                    if not isMouseDown then  
                                        if not overlayActive then setToolTipFunc("Width: " .. math.floor(linkWidth * 100) .. "%") end
                                        --reaper.ImGui_SetTooltip(ctx, parameterLinkName .. " width: " ..)
                                    end
                                elseif not parameterModulationActive then
                                    if isMouseDown then   
                                        toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, not parameterModulationActive)
                                    end
                                    setToolTipFunc(toolTipText)
                                end
                            end
                            
                            posXOffset = posXOffset + 22
                            
                        end
                         
                        if (not showingMappings and settings.showBipolarInParameters) or (showingMappings and settings.showBipolarInMappings) then
                            
                            reaper.ImGui_SetCursorPos(ctx, curPosX + posXOffset, curPosY + posYOffset)
                            if drawModulatorDirection(20, p, track, fxIndex, param, buttonId, -2,0, not settings.mappingModeBipolar and colorMapping or (p.bipolar and colorMapping or colorMappingLight), toolTipText)  then
                                if parameterModulationActive then
                                    if settings.mappingModeBipolar then
                                        toggleBipolar(track, p.fxIndex, p.param, p.bipolar)
                                    else
                                        changeDirection(track, p)
                                    end
                                else   
                                    toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, not parameterModulationActive)
                                end
                            end
                            
                            posXOffset = posXOffset + 13
                        end
                    --end
                    
                    
                    
                    reaper.ImGui_SetCursorPos(ctx, curPosX + posXOffset + (posXOffset < 4 and 4 or 2), curPosY + posYOffset)
                    
                    local cutX = reaper.ImGui_GetCursorPos(ctx) --+ (showingMappings and 8 or 0)
                    local showingWidth = areaWidth - 20 > cutX and areaWidth - cutX - 16 or 20
                    if reaper.ImGui_InvisibleButton(ctx,"##" .. nameForText .. buttonId, showingWidth, 20 + (showingMappings and 0 or 1)) then
                        toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, not parameterModulationActive)
                        ignoreScroll = true
                    end
                    local p0_x, p0_y = ImGui.GetItemRectMin(ctx)
                    local p1_x, p1_y = ImGui.GetItemRectMax(ctx)
                    ImGui.PushClipRect(ctx, p0_x-2, p0_y, p1_x, p1_y, true)
                    reaper.ImGui_DrawList_AddText(draw_list, p0_x + ((not showingMappings or settings.showBipolarInMappings) and -2 or 2), p0_y+2, padColor, nameForText) 
                    ImGui.PopClipRect(ctx)
                    if not overlayActive then setToolTipFunc(toolTipText) end
                    
                end
            end
            reaper.ImGui_PopStyleVar(ctx)
        end
    end
    
    
    if overlayActive then reaper.ImGui_BeginDisabled(ctx) end
    
    if showingMappings then
        modulatorMappingItems()
    else
        if not nameOnSide and not dontShowName then   
            reaper.ImGui_SetNextItemAllowOverlap(ctx)
            textButtonNoBackgroundClipped(not overlayActive and (" " .. showName) or "  ", textColor, faderWidth)
            if reaper.ImGui_IsItemClicked(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then 
                toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, not parameterModulationActive)
            end
            parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        end
    end
    
    reaper.ImGui_InvisibleButton(ctx, "slider" .. buttonId .. moduleId, faderWidth, sliderHeight)
    if not nameOnSide and dontShowName then 
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
    end
    
    
    if reaper.ImGui_IsItemHovered(ctx) then
        if not dragKnob then 
            dragKnob = "baseline" .. buttonId .. moduleId
            mouseDragStartX = mouse_pos_x
            mouseDragStartY = mouse_pos_y
            if not isMouseDown and not anyModifierIsPressed then 
                local toolTip1 = "Drag to set baseline of " .. name .. "\n - hold Shift for fine resolution\n - right click for more options"
                local toolTip2 = parameterLinkActive and "-- " .. parameterLinkName .. " --"
                local toolTip3 = parameterLinkActive and " - hold Ctrl to change width\n - hold Alt and scroll to change value\n - hold Super to turn bipolar " .. (p.bipolar and "off" or "on")
                
                setToolTipFunc3(toolTip1, toolTip2, toolTip3)
            end
        end  
    end
    
    
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local posXOffset = minX + sliderGrabWidth /2 + 2
    
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    
    if nameOnSide and not dontShowName then
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        if not overlayActive then
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_SetNextItemAllowOverlap(ctx)
            if textButtonNoBackgroundClipped(showName, textColor, nameOnSideWidth) and resetValue then
            --if reaper.ImGui_Button(ctx, showName, nameOnSideWidth) and resetValue then
                setParam(track, p, resetValue)
                ignoreFocusBecauseOfUiClick = true
                ignoreScroll = true
            end
        end
    end

    
    if not showingMappings then
        modulatorMappingItems()
    end
    
    
    endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
    parEndPosX, parEndPosY = reaper.ImGui_GetItemRectMax(ctx)
    
    
    --local ret, newValue = reaper.ImGui_DragInt(ctx, visualName .. '##' .. buttonId, currentValue*divide, (max - min) / width, min, max, valueFormat, sliderFlags)
    
    
    drawCustomSlider(valueFormat, valueColor, colorPos,currentValueNormalized, posXOffset, minX, minY, maxX, maxY, sliderWidthAvailable, sliderFlags, 0, 1, sliderGrabWidth,hasLink, linkValue, linkWidth, baseline, linkOffset)
    
    -- Check if the mouse is within the button area
    if parStartPosX and mouse_pos_x_imgui >= parStartPosX and mouse_pos_x_imgui <= parStartPosX + areaWidth and
       mouse_pos_y_imgui >= parStartPosY and mouse_pos_y_imgui <= parEndPosY then
      if reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then  --parameterLinkActive and 
          reaper.ImGui_OpenPopup(ctx, 'popup##' .. buttonId)  
          popupAlreadyOpen = true
      end
      
      if moduleId:match("Floating") == nil and moduleId:match("modulator") == nil and not nameOnSide and reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
          --reaper.ShowConsoleMsg(moduleId .. " - ".."hej\n")
          if not doNotSetFocus then
              paramnumber = param
              -- THIS DOESN*T WORK YET I THINK
              --if not showingMappings then
              if moduleId:match("parameter") == nil then
                  --reaper.ShowConsoleMsg(moduleId .. "\n")
                  ignoreScroll = true
                  ignoreFocusBecauseOfUiClick = true
              end
          end
          --end
      end
      
      
      if parameterLinkActive then
          local hideCloseButton = false
          --if not isMouseDown then
          if dragKnob and isAnyMouseDown then
              hideCloseButton = true
          end
          
          if settings.showRemoveCrossMapping then
              if not hideCloseButton and not overlayActive then
                  if specialButtons.close(ctx,startPosX + areaWidth-18,startPosY,16,false,"removemapping" .. buttonId, settings.colors.removeCross, settings.colors.removeCrossHover,colorTransparent, colorTransparent) then
                      
                      disableParameterLink(track, fxIndex, param)
                  end
                  setToolTipFunc("Remove mapping")
              end
          end
          --end
          --if settings.showToolTip and reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx,addNewlinesAtSpaces("Remove mapping",26)) end
          
          
        end
    end
    
    
    if not popupOpen then popupOpen = {}; popupStartPos = {}; end
    popupOpen[buttonId] = reaper.ImGui_IsPopupOpen(ctx, 'popup##' .. buttonId)
    if popupOpen[buttonId] then 
        local movePopupToX, movePopupToY
        if settings.openMappingsPanelPos == "Right" then
            movePopupToX = parStartPosX + areaWidth + 2
            movePopupToY = parStartPosY - 1
        elseif settings.openMappingsPanelPos == "Left" then
            local largestText = "Show "..'"' .. name ..'"' .. " parameter modulation/link window"
            local largestSizeW = reaper.ImGui_CalcTextSize(ctx, largestText, 0,0)
            movePopupToX = parStartPosX - (largestSizeW- 16)
            movePopupToY = parStartPosY - 1
        elseif settings.openMappingsPanelPos == "Below" then
            movePopupToX = parStartPosX - 1
            movePopupToY = parEndPosY +1
        elseif settings.openMappingsPanelPos == "Fixed" and settings.openMappingsPanelPosFixedCoordinates.x then
            movePopupToX = settings.openMappingsPanelPosFixedCoordinates.x
            movePopupToY = settings.openMappingsPanelPosFixedCoordinates.y
        end
        
        if settings.openMappingsPanelPos ~= "Fixed" or settings.openMappingsPanelPosFixedCoordinates.x then
            reaper.ImGui_SetNextWindowPos(ctx,movePopupToX, movePopupToY, reaper.ImGui_Cond_Appearing())
        end
        
        if not popupStartPos[buttonId] then
            popupStartPos[buttonId] = {x = parStartPosX, y = parStartPosY}
        end
        
        
        if popupStartPos[buttonId] and (popupStartPos[buttonId].x ~= parStartPosX or popupStartPos[buttonId].y ~= parStartPosY) then
            popupStartPos[buttonId] = nil
        end 
    else
        --popupStartPos[buttonId] = nil
    end
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTextDimmed)
    if reaper.ImGui_BeginPopup(ctx, 'popup##' .. buttonId) then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorText)
        if parameterLinkActive then
            --[[
            for i, dir in ipairs(directions) do
                if reaper.ImGui_RadioButton(ctx, dir, p.direction == - (i - 2)) then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  linkWidth >= 0 and -(i - 1) / 2 or  (i - 3) / 2)
                end
            end
            ]]
            local popupPosX, popupPosY = reaper.ImGui_GetWindowPos(ctx)
            settings.openMappingsPanelPosFixedCoordinates.x = popupPosX
            settings.openMappingsPanelPosFixedCoordinates.y = popupPosY
            
            local toolTipText = (parameterModulationActive and 'Disable' or 'Enable') .. ' "' .. parameterLinkName .. '" parameter modulation of ' .. p.name
            local ret, newValue = reaper.ImGui_Checkbox(ctx, "##enable" .. buttonId, parameterModulationActive)
            if ret and param > -1 then
                toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, newValue)
                ignoreScroll = true
            end  
            setToolTipFunc(toolTipText)  
            reaper.ImGui_SameLine(ctx)
            local overlayText = isMouseDown and "Width\n" .. math.floor(linkWidth * 100) .. "%"
            if specialButtons.knob(ctx, "width" .. buttonId .. moduleId, 0, 0, 20,minWidth == 0 and linkWidth or linkWidth / 2 + 0.5, overlayText, settings.colors.text, settings.colors.buttons, settings.colors.buttonsBorder, settings.colors.buttonsActive) then
                if not dragKnob then
                    dragKnob = "width" .. buttonId .. moduleId
                    mouseDragStartX = mouse_pos_x
                    mouseDragStartY = mouse_pos_y
                end 
                if not isMouseDown then  
                    toolTipText = "Width: " .. math.floor(linkWidth * 100) .. "%"
                    setToolTipFunc(toolTipText)
                end
            end 
            
            reaper.ImGui_SameLine(ctx)
            if drawModulatorDirection(20, p, track, fxIndex, param, buttonId, 0,0, not settings.mappingModeBipolar and colorText or (p.bipolar and colorText or colorTextDimmed)) then
                toggleBipolar(track, fxIndex, param, p.bipolar) 
            end
            
            reaper.ImGui_SameLine(ctx)
            
            
            if reaper.ImGui_Button(ctx, parameterLinkName) then 
                local p
                for _, p1 in ipairs(modulatorNames) do
                    if p1.name == parameterLinkName then
                        p = p1 
                        break;
                    end
                end
                --fxInContainerIndex
                --reaper.ShowConsoleMsg(tostring(p.output[1]) .. "\n")
                mapModulatorActivate(p, p.output[1], p.name, nil, #p.output == 1)
            end
            
            setToolTipFunc("Click to start mapping with " .. parameterLinkName)
            
            reaper.ImGui_Spacing(ctx)
            local close = false
            if reaper.ImGui_Button(ctx,"Remove mapping##remove" .. buttonId) then
                disableParameterLink(track, fxIndex, param)
                doNotChangeOnlyMapped = true
                close = true
            end 
            
            local _, isModVisible = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.visible')
            isModVisible = isModVisible == "1"
            local toggleText = isModVisible and "Hide" or "Show"
            if reaper.ImGui_Button(ctx,toggleText .. " parameter modulation/link window##show" .. buttonId) then 
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.visible', isModVisible and 0 or 1 )
                close = true
            end 
        end 
        
        
        if reaper.ImGui_Button(ctx, "Set MIDI learn for parameter") then  
            reaper.ImGui_CloseCurrentPopup(ctx)
            openSetMidiLearnForLastTouchedFXParameter = true
            
            --if fxIndex ~= fxnumber and param ~= paramnumber then  
                reaper.TrackFX_SetParam(track,fxIndex,param, reaper.TrackFX_GetParam(track,fxIndex,param))
            --end
            
            reaper.Main_OnCommand(41144, 0) --FX: Set MIDI learn for last touched FX parameter
            
        end 
        setToolTipFunc("Map a MIDI input to the parameter")
        
            
        fxIsShowing = reaper.TrackFX_GetOpen(track,fxIndex)
        fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
        local isShowing = (fxIsShowing or fxIsFloating) 
        
        local toggleName = (not isShowing and "Open " or "Close ")
        if buttonSelect(ctx, toggleName .. " FX##" .. name .. fxIndex, nil, isShowing, nil, 0, colorButtonsBorder, colorButtons, colorButtonsHover, colorButtonsActive, settings.colors.pluginOpen) then
            openCloseFx(track, fxIndex, not isShowing) 
            --close = true
        end
        
        function getEnvelopeState(envelope) 
            if envelope then
                _, envelopeVisible = reaper.GetSetEnvelopeInfo_String(envelope, "VISIBLE", "", false)
                _, envelopeActive = reaper.GetSetEnvelopeInfo_String(envelope, "ACTIVE", "", false)
                _, envelopeArm = reaper.GetSetEnvelopeInfo_String(envelope, "ARM", "", false)
                _, envelopeLane = reaper.GetSetEnvelopeInfo_String(envelope, "SHOWLANE", "", false)
                return {visible = envelopeVisible == "1", active = envelopeActive == "1", arm = envelopeArm == "1", showLane = envelopeLane == "1"}
            else
                return {visible = false, active = false, arm = false, showLane = true}
            end
        end
        
        function clearEnvelopeLane(envelope)
            if envelope then 
                -- Remove all points
                local pointCount = reaper.CountEnvelopePoints(envelope) 
                for i = pointCount-1, 0, -1 do
                    reaper.DeleteEnvelopePointEx(envelope,-1,i)
                end
                reaper.TrackList_AdjustWindows(false)
                reaper.UpdateArrange()
                --reaper.GetSetEnvelopeInfo_String(envelope, "VISIBLE", "0", true)
            end 
        end
        
        reaper.ImGui_TextColored(ctx, colorTextDimmed, "Envelope lane")
        if not p.usesEnvelope then 
            if reaper.ImGui_Checkbox(ctx, "Visible", false) then 
                reaper.GetFXEnvelope(track, fxIndex, param, true) 
            end
        else
            local envelopeStates = getEnvelopeState(p.envelope) 
            local types = {"visible","active","arm", "showLane"}
            --local types = {"Show","Activate","Arm"}
            for i, t in ipairs(types) do 
                if reaper.ImGui_Checkbox(ctx, prettifyString(t), envelopeStates[t]) then 
                --if buttonSelect(ctx, t.. "##Envelope" .. t .. buttonId, nil, envelopeStates[t], nil, 0, colorButtonsBorder, colorButtons, colorButtonsHover, colorButtonsActive, settings.colors.pluginOpen) then
                --if reaper.ImGui_Button(ctx,"Show track envelope##show" .. buttonId) then 
                    reaper.GetSetEnvelopeInfo_String(p.envelope, t:upper(), envelopeStates[t] and "0" or "1", true)
                    
                    if t == "visible" or t == "showLane" then
                        reaper.TrackList_AdjustWindows(false)
                        reaper.UpdateArrange()
                    end
                end
                if i < #types then reaper.ImGui_SameLine(ctx) end
                
            end
            
            if reaper.ImGui_Button(ctx, "Clear and hide envelope lane") then
                clearEnvelopeLane(p.envelope)
            end
        end
            
        
        if not popupStartPos[buttonId] or close then
            reaper.ImGui_CloseCurrentPopup(ctx)
            popupStartPos[buttonId] = nil
        end
        reaper.ImGui_PopStyleColor(ctx)
        
        ImGui.EndPopup(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx)
    
    
    
    local padW = 1
    local padH = 0
    if parameterLinkActive then 
        reaper.ImGui_DrawList_AddRect(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, padColor,4,nil,1)
    end
    --
    
    
    
    setParameterValuesViaMouse(track, buttonId, moduleId, p, range, min, p.currentValue, faderResolution)
    
    
    -- MAPPING OVRELAY
    if overlayActive then  reaper.ImGui_EndDisabled(ctx) end
    
    if p.guid and overlayActive then  
        local borderColor = (canBeMapped and not mapOutput) and colorMapping or colorSelectOverlay
        
        
        reaper.ImGui_SetCursorPos(ctx, startPosX,startPosY)
        local visualName = ("Use " .. name)
        if (canBeMapped and not mapOutput) then visualName = name end --("Map " .. name) end
        if (hideParametersFromModulator == p.guid) then 
            local hidden = trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[p.guid] and trackSettings.hideParametersFromModulator[p.guid][p.param]
            visualName = (hidden and "Hidding "  or "Showing ") .. name 
            if hidden then
                borderColor = colorRedHidden
            else
                borderColor = colorGreen
            end 
        end
        -- transparent version of border
        local overlayColor = borderColor & 0xFFFFFFFF55
        
        reaper.ImGui_InvisibleButton(ctx,  visualName .. "##map" .. buttonId,  areaWidth, endPosY - startPosY - 4)
        local mapToolTip
        if ImGui.IsItemClicked(ctx) then
            paramnumber = param
            ignoreScroll = true
            
            if (canBeMapped and not mapOutput) then
                local isLFO = mapName:match("LFO") ~= nil
                local setWidth = (isLFO and settings.defaultMappingWidthLFO or settings.defaultMappingWidth) / 100
                local setOffset = (isLFO and (settings.mappingModeBipolar and (settings.defaultBipolarLFO and -0.5 or 0) or (settings.defaultLFODirection - 3)/2) or ((settings.mappingModeBipolar and settings.defaultBipolar and -0.5 or 0) or (settings.defaultDirection - 3) / 2))
                setParamaterToLastTouched(track, modulationContainerPos, map, fxIndex, param, p.value, setOffset, setWidth)
                if settings.mapOnce then stopMappingOnRelease = true end
                mapToolTip = "Click to map " .. name
            elseif mapOutput then 
                mapParameterToContainer(track, modulationContainerPos, fxIndex, param)
            elseif hideParametersFromModulator == p.guid then
                trackSettings.hideParametersFromModulator[p.guid][p.param] = not trackSettings.hideParametersFromModulator[p.guid][p.param]
                saveTrackSettings(track)
            end
        end
        setToolTipFunc(mapToolTip)
        if parStartPosX then
            reaper.ImGui_DrawList_AddRectFilled(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, overlayColor,4,nil)
            reaper.ImGui_DrawList_AddRect(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, borderColor,4,nil,1)
            
            
            local textW = reaper.ImGui_CalcTextSize(ctx, visualName, 0, 0)
            -- value text
            ImGui.PushClipRect(ctx, parStartPosX, parStartPosY, parStartPosX + areaWidth, parEndPosY, true)
            reaper.ImGui_DrawList_AddText(draw_list, posXOffset + areaWidth/2 - textW/2, parStartPosY+2, colorText, visualName)
        end ImGui.PopClipRect(ctx) 
    end
    
    if stopMappingOnRelease and isMouseReleased then map = false; sliderNumber = false; stopMappingOnRelease = nil end
    
    if nameOnSide and parameterLinkActive then
        
        reaper.ImGui_SetCursorPos(ctx, endPosX, endPosY)
        reaper.ImGui_Spacing(ctx)
    end
    
    
    reaper.ImGui_EndGroup(ctx)
    --return ret, newValue
end




function hideShowEverything(track, newState)
    
    if modulatorNames  then
        for _, m in ipairs(modulatorNames) do trackSettings.collabsModules[m.guid] = newState end   
    end
    
    trackSettings.hidePlugins = newState
    trackSettings.hideParameters = newState
    trackSettings.hideModules = newState
    
    saveTrackSettings(track)
end

function buttonTransparent(name, width,height) 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorTransparent)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
    reaper.ImGui_Button(ctx,name, width,height)
    reaper.ImGui_PopStyleColor(ctx,3)
end

function mapButtonColor()
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping)
  ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorMapLight)
end

local function waitForWindowToClose(browserHwnd, callback)  
    -- we need this to ensure we cancel even if window is not "destroyed", eg. FX Browser seems to still be there after closing
    local visible = reaper.JS_Window_IsVisible(browserHwnd) 
    if (browserHwnd and visible) then 
        reaper.defer(function() waitForWindowToClose(browserHwnd, callback) end) 
    else
        callback()
        return true
    end
end



function findWindowParentWithName(name1, name2, name3)
    local hwnd = reaper.JS_Window_GetFocus()
    local originalHwnd = hwnd
  
    while hwnd ~= nil and reaper.JS_Window_IsWindow(hwnd) do
        local title = reaper.JS_Window_GetTitle(hwnd)
        if title and (name1 and title:match(name1) ~= nil) or (name2 and title:match(name2) ~= nil) or (name3 and title:match(name3) ~= nil) then
            return hwnd, originalHwnd, title
        end
        hwnd = reaper.JS_Window_GetParent(hwnd)
    end
  
    return false, false, ""
end




local function openFxBrowserOnSpecificTrack()
    local index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local trackTitleIndex = "Track " .. math.floor(index)
    local ret, name = reaper.GetTrackName(track)
    local addFXToTrackWindowName = "Add FX to " .. trackTitleIndex .. (name == trackTitleIndex and "" or (' "' .. name .. '"'))
    reaper.SetOnlyTrackSelected(track, true)
    
    
    -- check if window is already open, if it is we start by closing it
    --local hwnd = reaper.JS_Window_Find(addFXToTrackWindowName, true) 
    --local visible = reaper.JS_Window_IsVisible(hwnd)  
    --if (hwnd and visible) then
    --    reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
    --end
    
    reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
    local browserHwnd, browserSearchFieldHwnd, title = findWindowParentWithName("FX Browser", addFXToTrackWindowName)
    
    if not browserHwnd then 
        reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
        browserHwnd, browserSearchFieldHwnd, title = findWindowParentWithName("FX Browser", addFXToTrackWindowName)
    end
    
    --local isDocked = title == "FX Browser (docked)"
    
    return browserHwnd, browserSearchFieldHwnd, isDocked
end

function openCloseFx(track, fxIndex, open)  
    function closeParentContainerRecursive(track, fxIndex)
        if reaper.TrackFX_GetOpen(track,fxIndex) then
            local retval, parFxIndex = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "parent_container" )
            if retval and parFxIndex then 
                local fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,tonumber(parFxIndex))
                if fxIsFloating then
                    reaper.TrackFX_SetOpen(track,tonumber(parFxIndex),false)
                else
                    closeParentContainerRecursive(track, tonumber(parFxIndex))
                end
            else 
                local fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                if fxIsFloating then
                    reaper.TrackFX_SetOpen(track,fxIndex,false)
                else 
                    reaper.TrackFX_Show(track,fxIndex,0)   
                end
            end 
        end
    end
    if open then 
        -- opens floating window
        reaper.TrackFX_SetOpen(track,fxIndex,open)
    else 
        local fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
        if fxIsFloating then
            -- closes floating window
            reaper.TrackFX_SetOpen(track,fxIndex,open)
        else 
            -- check if window is in a container
            retval, parFxIndex = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "parent_container" )
            if retval and parFxIndex then
                -- if in container we try to close that one instead
                closeParentContainerRecursive(track, tonumber(parFxIndex))
            else
                -- else we close the window as we know it's the FX window
                reaper.TrackFX_Show(track,fxIndex,0)   
            end
        end
    end
    
end

function addVolumePanAndSendControlPlugin(track)
    
    local nameOpened = "Track controls" 
    local fxPosition = reaper.TrackFX_AddByName( track, nameOpened, false, 1 )
    if fxPosition == -1 then
        fxPosition = reaper.TrackFX_AddByName( track, "Helgobox", false, 1 )
        reaper.TrackFX_SetNamedConfigParm( track, fxPosition, 'renamed_name', nameOpened)
    end
    return fxPosition
end

function setVolumePanAndSendControlPluginParams(track, fxPosition) 
    -- mappings for volume and pan
    local mappings = [[
  "mappings": [
    {
      "name": "Volume",
      "source": {
        "category": "reaper",
        "reaperSourceType": "realearn-parameter",
        "parameterIndex": 0
      },
      "mode": {
      },
      "target": {
        "type": 2,
        "fxAnchor": "id"
      }
    },
    {
      "name": "Pan",
      "source": {
        "category": "reaper",
        "reaperSourceType": "realearn-parameter",
        "parameterIndex": 1
      },
      "mode": {
      },
      "target": {
        "type": 4
      }
    },
    {
      "name": "Pan width",
      "source": {
        "category": "reaper",
        "reaperSourceType": "realearn-parameter",
        "parameterIndex": 2
      },
      "mode": {
      },
      "target": {
        "type": 17
      }
    }]]
        
    -- parameter slider for volume and pan
    local params = [[,
  "parameters": {
    "0": {
      "name": "Volume",
      "value": 0.5
    },
    "1": {
      "name": "Pan",
      "value": 0.5
    },
    "2": {
      "name": "Pan width",
      "value": 0.5
    }]]
        
    -- mappings and parameter for sends
    for i = 1, 16 do
        mappings = mappings .. [[,
    {
      "name": "Send ]] .. i ..[[ volume",
      "source": {
        "category": "reaper",
        "reaperSourceType": "realearn-parameter",
        "parameterIndex": ]] .. i * 2 + 1 ..[[
        
      },
      "mode": {
      },
      "target": {
        "type": 3,
        "sendIndex": ]] .. i - 1 ..[[
        
      }
    },
    {
      "name": "Send ]] .. i ..[[ pan",
      "source": {
        "category": "reaper",
        "reaperSourceType": "realearn-parameter",
        "parameterIndex": ]] .. i * 2 + 2 ..[[
        
      },
      "mode": {
      },
      "target": {
        "type": 9,
        "sendIndex": ]] .. i - 1 ..[[
        
      }
    }]]
          
        params = params .. [[,
    "]] .. i * 2 + 1 ..[[": {
      "name": "Send ]] .. i ..[[ volume",
      "value": 0.5
    },
    "]] .. i * 2 + 2 ..[[": {
      "name": "Send ]] .. i ..[[ pan",
      "value": 0.5
    }]]
    end
    
    mappings = mappings .. "\n  ]"
    params = params .. "\n  }"
    
    local state = "{\n" .. mappings .. params .. "\n}" 
    
    reaper.TrackFX_SetNamedConfigParm(track, fxPosition, "set-state", state)
end

function scrollHoveredDropdown(currentValue, track,fxIndex,paramIndex, dropDownList, native, min, max)
    if reaper.ImGui_IsItemHovered(ctx) then
        if scrollVertical ~= 0 and isScrollValue then
            local newIndexValue = currentValue + (scrollVertical > 0 and -1 or 1) 
            newIndexValue = math.min(math.max(newIndexValue, min and min or 1), max and max or #dropDownList)
            local newScrollValue = dropDownList[1].value and dropDownList[newIndexValue].value or (newIndexValue)
            if native then
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, native, newScrollValue) 
            else
                reaper.TrackFX_SetParam( track, fxIndex, paramIndex, newScrollValue) 
            end
        end
    end
end

        
function scrollHoveredItem(track, fxIndex, paramIndex, currentValue, divide, nativeParameter, dropDownValue, min, max)
    if reaper.ImGui_IsItemHovered(ctx) and isScrollValue then 
        if scrollVertical ~= 0 then
            local newValue = dropDownValue and (nativeParameter and currentValue or (currentValue - (scrollVertical > 0 and dropDownValue or -1*dropDownValue))) or ( currentValue - (scrollVertical * divide/100 ))
            if newValue < min then newValue = min end
            if newValue > max then newValue = max end
            if nativeParameter then
                if dropDownValue then 
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, nativeParameter, newValue)
                else
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, nativeParameter,newValue)
                end
            else
                if dropDownValue then
                    setParameterNormalizedButReturnFocus( track, fxIndex, paramIndex, newValue)
                else
                    setParameterNormalizedButReturnFocus(track, fxIndex, paramIndex, newValue) 
                end
            end
        end
    end
end



function pluginParameterName(name, valueName, number)
    reaper.ImGui_Text(ctx,name ) -- .. "\n" .. valueName) 
    if not map and ImGui.IsItemClicked(ctx) then paramnumber = number end 
end



function parameterNameAndSliders(moduleId, func2, p, focusedParamNumber, doNotSetFocus, excludeName, showingMappings, nameOnSide, sizeOfFader, resetValue, valueAsString, genericModulatorOutput, parametersWindow) 
    local valueNameInput = (p.valueName and p.valueName ~= "") and p.valueName or 0 -- got an error so this is a quick fix
    
    local valueName = valueAsString and ((valueAsString:match("%%") and tonumber(valueNameInput)) and string.format(valueAsString, tonumber(valueNameInput)) or valueAsString) or valueNameInput
    
    
    
    local scrollBarOffset = 14
    
    local faderWidth = sizeOfFader and sizeOfFader or moduleWidth - scrollBarOffset --(sizeArray and sizeArray.faderWidth) and sizeArray.faderWidth or moduleWidth - scrollBarOffset

    
    
    pluginParameterSlider(moduleId, nameOnSide,nil, valueName, nil, faderWidth, "Double", p, showingMappings, resetValue, genericModulatorOutput, parametersWindow, excludeName, doNotSetFocus)  
end

function placingOfNextElement()
    if settings.vertical then
        reaper.ImGui_Spacing(ctx)
        --reaper.ImGui_Separator(ctx)
        --reaper.ImGui_Spacing(ctx)
    else
        reaper.ImGui_SameLine(ctx)
    end
end

---------------------------------------------------------------------------------------------------------------
-------------------------------------MODULES-------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

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
            --ret, val = reaper.ImGui_SliderInt(ctx,visualName.. '##slider' .. name .. fxIndex, math.floor(currentValue * divide), min, max, valueFormat) 
            ret, val = pluginParameterSlider(visualName, '##slider' ..name .. fxIndex,min,max, nil,valueFormat, sliderFlags, setSize, "Int", {})
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val/divide) end
        elseif _type == "SliderDouble" then --"%d"
            --ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, currentValue, min, max, valueFormat, sliderFlag)
            ret, val = pluginParameterSlider(visualName, '##slider' .. name .. fxIndex, min, max, nil, valueFormat, sliderFlag, setSize, "Double", {})
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
        elseif _type == "SliderDoubleLogarithmic" then --"%d"
        -- NOT USED AT THE MOMENT
            ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, math.floor(min * 2.7183^currentValue), min, max, valueFormat, sliderFlag)
            if ret then 
            
            --reaper.ShowConsoleMsg(name .. " - " .. currentValue .. " - " .. currentValue2 .. " - " .. val ..  "\n")
            setParameterNormalizedButReturnFocus(track, fxIndex, paramIndex, math.log(val/min)) end
        elseif _type == "SliderDoubleLogarithmic2" then --"%d"
            --ret, val= reaper.ImGui_SliderDouble(ctx,visualName.. '##slider' .. name .. fxIndex, (2.7183^currentValue), min, max, valueFormat, sliderFlag)
            --if ret then setParameterNormalizedButReturnFocus(track, fxIndex, paramIndex, math.log(val)) end
            ret, val = pluginParameterSlider(visualName, '##slider' .. name .. fxIndex, min, max, nil, valueFormat, sliderFlag, setSize, "Double", {})
            if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val) end
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
            if reaper.ImGui_Button(ctx, name.. '##slider' .. name .. fxIndex,setSize and setSize or dropDownSize,buttonSizeH) then
                setParameterButReturnFocus(track, fxIndex, paramIndex, currentValue == 1 and 0 or 1) 
            end
            
        end 
        if val == true then val = 1 end
        if val == false then val = 0 end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end 
        return ret, val
    end
end

-- wrap slider in to mapping function
function createSlider(track,fxIndex, _type,paramIndex,name,min,max,divide, valueFormat,sliderFlag, checkboxFlipped, dropDownText, dropdownOffset,tooltip, width)  
    local info = {_type = _type,paramIndex =paramIndex,name = name,min = min,max =max,divide=divide, valueFormat = valueFormat,sliderFlag = sliderFlag, checkboxFlipped =checkboxFlipped, dropDownText = dropDownText, dropdownOffset = dropdownOffset,tooltip =tooltip}
    local sizeW = width and width or buttonWidth
    if _type == "Combo" or _type == "Checkbox" or _type == "ButtonToggle" then
        createSlider2(track,fxIndex, info,nil, sizeW) 
    --else  
    --    parameterNameAndSliders(createSlider2, getAllDataFromParameter(track,fxIndex,paramIndex), focusedParamNumber, info, widthArray) 
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
            -- this could probably be unified
            if useFineFaders then
                ret, newValue = pluginParameterSlider(currentValue, fxIndex .. paramName, visualName, min, max, divide, valueFormat, sliderFlags, buttonWidth, "Double", {})
            else
            -- was the usual slider.
                reaper.ImGui_PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 2) 
            ret, newValue = reaper.ImGui_SliderDouble(ctx, visualName .. '##' .. paramName .. fxIndex, currentValue*divide, min, max, valueFormat, sliderFlags)
                reaper.ImGui_PopStyleVar(ctx)
            end
            
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue/divide) end  
        elseif _type == "Combo" then 
            ret, newValue = reaper.ImGui_Combo(ctx, visualName .. '##' .. paramName .. fxIndex, tonumber(currentValue)+dropdownOffset, dropDownText )
            if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue-dropdownOffset) end
            scrollValue = divide
        end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end
        
    end
    return newValue and newValue or currentValue
end






function nlfoModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    local noteTempos = {
        {name = "32 D", value = 4*32*1.5},    -- 0.1875
        {name = "32", value = 4*32},          -- 0.125
    
        {name = "16 D", value = 4*16*1.5},    -- 0.375
        {name = "32 T", value = 4*32/1.5},    -- 0.083333...
        {name = "16", value = 4*16},          -- 0.25
    
        {name = "8 D", value = 4*8*1.5},      -- 0.75
        {name = "16 T", value = 4*16/1.5},    -- 0.166666...
        {name = "8", value = 4*8},            -- 0.5
    
        {name = "4 D", value = 4*4*1.5},      -- 1.5
        {name = "8 T", value = 4*8/1.5},      -- 0.333333...
        {name = "4", value = 4*4},            -- 1
    
        {name = "2 D", value = 4*2*1.5},      -- 3
        {name = "4 T", value = 4*4/1.5},      -- 0.666666...
        {name = "2", value = 4*2},            -- 2
    
        {name = "1 D", value = 4*1*1.5},      -- 6
        {name = "2 T", value = 4*2/1.5},      -- 1.333333...
        {name = "1", value = 4*1},            -- 4
    
        {name = "1/2 D", value = 4*0.5*1.5},  -- 3
        {name = "1 T", value = 4*1/1.5},      -- 2.666666...
        {name = "1/2", value = 4*0.5},        -- 2
    
        {name = "1/4 D", value = 4*0.25*1.5}, -- 1.5
        {name = "1/2 T", value = 4*0.5/1.5},  -- 1.333333...
        {name = "1/4", value = 4*0.25},       -- 1
    
        {name = "1/8 D", value = 4*0.125*1.5},-- 0.75
        {name = "1/4 T", value = 4*0.25/1.5}, -- 0.666666...
        {name = "1/8", value = 4*0.125},      -- 0.5
    
        {name = "1/16 D", value = 4*0.0625*1.5}, -- 0.375
        {name = "1/8 T", value = 4*0.125/1.5},   -- 0.333333...
        {name = "1/16", value = 4*0.0625},       -- 0.25
    
        {name = "1/32 D", value = 4*0.03125*1.5}, -- 0.1875
        {name = "1/16 T", value = 4*0.0625/1.5},  -- 0.166666...
        {name = "1/32", value = 4*0.03125},       -- 0.125
    
        {name = "1/64 D", value = 4*0.015625*1.5}, -- 0.09375
        {name = "1/32 T", value = 4*0.03125/1.5},  -- 0.083333...
        {name = "1/64", value = 4*0.015625},       -- 0.0625
    }
    
    paramOut = "1"
    
    noteTempoNamesToValues = {}
    noteTemposDropdownText = ""
    for _, t in ipairs(noteTempos) do
        noteTemposDropdownText = noteTemposDropdownText .. t.name .. "\0" 
    end
    
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
    
    reaper.ImGui_TableNextColumn(ctx) 
        
    createShapes()
    
    isTempoSync = createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.temposync", "Tempo sync",nil,nil,1)
    

    local paramName = "Speed"
    if tonumber(isTempoSync) == 0 then
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "lfo.speed", "Speed", 0.0039, 16,1, "%0.4f Hz", reaper.ImGui_SliderFlags_Logarithmic(), nil, nil, nil, nil,buttonWidth*2, 1)
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
            
            scrollHoveredDropdown(closest_index, track,fxIndex,nil, noteTempos, 'param.'..paramOut..'.lfo.' .. paramName)
        end
    end
    
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "lfo.phase", "Phase", 0, 1, 1, "%0.2f", nil, nil, nil, nil, nil,buttonWidth*2, 0)
    
    createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.free", "Seek/loop", nil,nil,1,nil,nil,true)  
end

local acsTrackAudioChannel = {"1","2","3","4","1+2","3+4"}
local acsTrackAudioChannelDropDownText = ""
for _, t in ipairs(acsTrackAudioChannel) do
    acsTrackAudioChannelDropDownText = acsTrackAudioChannelDropDownText .. t .. "\0" 
end
    
function acsModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    paramOut = "1"
     
    buttonSizeH = 22
    buttonSizeW = buttonSizeH * 1.25
    
    reaper.ImGui_TableNextColumn(ctx)
    
    
    if not isCollabsed then 
        
        local ret1, chan = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.chan")  
        local ret2, stereo = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.stereo")
        if ret1 and ret2 then
            local dropDownSelect = tonumber(stereo) < 1 and tonumber(chan) or (tonumber(chan) == 0 and 4 or 5)
            
            reaper.ImGui_SetNextItemWidth(ctx,dropDownSize/2)
            local ret, value = reaper.ImGui_Combo(ctx, "" .. 'Channel##acsModulator' .. fxIndex, dropDownSelect, acsTrackAudioChannelDropDownText )
            if ret then  
                if value < 4 then
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.chan", value)   
                else
                    reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.chan", value == 4 and 0 or 2)
                end
                    
                reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.stereo", value < 4 and 0 or 1)
                
            end 
        end
        
        --if ret then reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, amount) end 
        
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.attack", "Attack", 0, 1000, 1, "%0.0f ms", nil, nil, nil, nil, nil,buttonWidth*2, 300)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.release", "Release", 0, 1000, 1, "%0.0f ms", nil, nil, nil, nil, nil,buttonWidth*2, 300)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.dblo", "Min Volume", -60, 12,1, "%0.2f dB", nil, nil, nil, nil, nil,buttonWidth*2, -60)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.dbhi", "Max Volume", -60, 12,1, "%0.2f dB", nil, nil, nil, nil, nil,buttonWidth*2, 12)
        nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.strength", "Strength", 0, 1,100, "%0.1f %%", nil, nil, nil, nil, nil,buttonWidth*2, 100)
        -- THESE ARE NOT RELEVANT TO SEE
        
        
        --nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.x2", "X pos", 0, 1,1, "%0.2f dB", nil, nil, nil, nil, nil,buttonWidth*2, 0.5)
        --nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.y2", "Y pos", 0, 1,1, "%0.2f dB", nil, nil, nil, nil, nil,buttonWidth*2, 0.5)
        --nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.chan", "Channel", 0, 2, 1, "%0.1f", nil, nil, nil, nil, nil,buttonWidth*2, 2)
        --nativeReaperModuleParameter(track, fxIndex, paramOut, "SliderDouble", "acs.stereo", "Stereo", 0, 1, 1, "%0.1f", nil, nil, nil, nil, nil,buttonWidth*2, 1)
         
        
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    end
end

function midiCCModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    typeDropDownText = "Select\0"
    for i = 1, 127 do
        typeDropDownText = typeDropDownText .. "CC" .. i .. "\0" 
    end 
    typeDropDownText = typeDropDownText .. "Pitchbend" .. "\0" 
    channelDropDownText = "All\0"
    for i = 1, 16 do
        channelDropDownText = channelDropDownText .. "" .. i .. "\0" 
    end 
    
    
    reaper.ImGui_TableNextColumn(ctx)
    
    if not isCollabsed then
        --reaper.ImGui_NewLine(ctx)
        createSlider(track,fxIndex,"Combo",1,"Fader",nil,nil,1,nil,nil,nil,typeDropDownText,0,"Select CC or pitchbend to control the output")
        createSlider(track,fxIndex,"Combo",2,"Channel",nil,nil,1,nil,nil,nil,channelDropDownText,0,"Select which channel to use") 

        isListening = reaper.TrackFX_GetParam(track, fxIndex, 3) == 1
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorMapping )
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorMappingLight )
        ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
        createSlider(track,fxIndex,"ButtonToggle",3,isListening and "Stop" or "Listen",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input") 
        reaper.ImGui_PopStyleColor(ctx,3)
        createSlider(track,fxIndex,"Checkbox",7,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil)
        
        local faderSelection = reaper.TrackFX_GetParam(track, fxIndex, 1)
        if faderSelection > 0 then
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
            
        end
    end
end

function keytrackerModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    local list = {"Off","Smooth", "Constant"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    createSlider(track,fxIndex,"Combo",1,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Set the timer mode for changing the value")

    local useTimer = reaper.TrackFX_GetParam(track, fxIndex, 1) > 0
    if useTimer then
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    end
    
    
    local isListening = reaper.TrackFX_GetParam(track, fxIndex, 9) == 1
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",9,isListening and "Stop" or "Set minimum",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set minimum key range", dropDownSize)   
    
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    reaper.ImGui_PopStyleColor(ctx,3)
    
    local isListening = reaper.TrackFX_GetParam(track, fxIndex, 10) == 1
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",10,isListening and "Stop" or "Set maximum",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set maximum key range", dropDownSize)  
    reaper.ImGui_PopStyleColor(ctx,3)
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 127) 
    
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,7), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    
    createSlider(track,fxIndex,"Checkbox",8,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil) 
end

function noteVelocityModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    local list = {"Off","Smooth", "Constant"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    createSlider(track,fxIndex,"Combo",1,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Set the timer mode for changing the value")

    local useTimer = reaper.TrackFX_GetParam(track, fxIndex, 1) > 0
    if useTimer then
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    end
    
    
    local isListening = reaper.TrackFX_GetParam(track, fxIndex, 9) == 1 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",9,isListening and "Stop" or "Set minimum",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set minimum key range", dropDownSize)   
    
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    reaper.ImGui_PopStyleColor(ctx,3)
    
    local isListening = reaper.TrackFX_GetParam(track, fxIndex, 10) == 1 
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",10,isListening and "Stop" or "Set maximum",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set maximum key range", dropDownSize)  
    reaper.ImGui_PopStyleColor(ctx,3)
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 127) 
    
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,7), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    
    createSlider(track,fxIndex,"Checkbox",8,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil) 
end

function xyPad(name, id, padSize, track, fxIndex, xParam, yParam,pX, pY, padSizeH, ignoreInput)
    
    
    local click = false
    local xyName = showLargeXyPad[fxIndex] and "Large XY pad open" or ""
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed)
    --reaper.ShowConsoleMsg(xyName .. "\n")
    if reaper.ImGui_Button(ctx, xyName .. "##xypad" .. id, padSize, padSizeH and padSizeH or padSize) then
        click = true
    end
    reaper.ImGui_PopStyleColor(ctx, 4)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    local w = maxX - minX
    local h = maxY - minY
    
    reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, minY, maxX, maxY, colorButtons, 0)
    reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, colorTextDimmed, 0) 
    
    reaper.ImGui_PushFont(ctx, font2)
    local textW, textH = reaper.ImGui_CalcTextSize(ctx, name, 0, 0)
    reaper.ImGui_DrawList_AddText(draw_list, minX + w / 2 - textW/2, minY + h / 2 - textH / 2, colorTextDimmed, name)
    reaper.ImGui_PopFont(ctx)
    
    
    local offset = 7
    local minX = minX + offset
    local minY = minY + offset
    local maxX = maxX - offset
    local maxY = maxY - offset
    local sizeW = maxX - minX
    local sizeH = maxY - minY
    
    
    reaper.ImGui_DrawList_AddCircle(draw_list, minX + pX.currentValueNormalized * sizeW, maxY - pY.currentValueNormalized * sizeH, 6, colorText)
    
    if not ignoreInput then
        if mouse_pos_x_imgui>= minX and mouse_pos_x_imgui <= maxX and mouse_pos_y_imgui>= minY and mouse_pos_y_imgui <= maxY then
            if isMouseDown then
                sendXyValues[id] = true
            end
        end 
        
        if isMouseReleased then
            sendXyValues[id] = false
        end
        
        if sendXyValues[id] then
            local valX = (mouse_pos_x_imgui - minX) / sizeW
            local valY = (maxY - mouse_pos_y_imgui) / sizeH
            if valX < 0 then valX = 0 end
            if valX > 1 then valX = 1 end
            if valY < 0 then valY = 0 end
            if valY > 1 then valY = 1 end
            setParam(track, getAllDataFromParameter(track,fxIndex,xParam), valX)
            setParam(track, getAllDataFromParameter(track,fxIndex,yParam), valY)
            
        end
    end
    return click
end

function largeXyPad(name, id, track, fxIndex, pX, pY)
    
    reaper.ImGui_SetNextWindowSize(ctx, 500,500, reaper.ImGui_Cond_FirstUseEver())
    reaper.ImGui_SetNextWindowPos(ctx, mouse_pos_x_imgui - 250, mouse_pos_y_imgui - 250, reaper.ImGui_Cond_FirstUseEver())
    
    
    local rv, open = reaper.ImGui_Begin(ctx, 'Large XY Pad##'..id, true, reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() ) 
    if not rv then return open end
    local winW, winH = reaper.ImGui_GetWindowSize(ctx)
    local winX, winY = reaper.ImGui_GetWindowPos(ctx)
    
    xyPad(name, id, winW-16, track, fxIndex, 0, 1, pX, pY, winH-36)
    
    reaper.ImGui_End(ctx)
    return open
end

function xyModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    pX = getAllDataFromParameter(track,fxIndex,0)
    pY = getAllDataFromParameter(track,fxIndex,1)
    parameterNameAndSliders("modulator",pluginParameterSlider, pX, focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, pY, focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    
    local padSize = buttonWidth * 2
    if xyPad(name, tostring(track) .. id, padSize, track, fxIndex, 0, 1,pX, pY, nil, isCtrlPressed) then
        if isCtrlPressed then
            showLargeXyPad[id] = not showLargeXyPad[id]
        end
    end
    
    if showLargeXyPad[id] then
        showLargeXyPad[id] = largeXyPad(name, tostring(track) .. fxIndex .. "large", track, fxIndex, pX, pY)
    end
    setToolTipFunc("Click to send XY output.\n - Hold down Ctrl to open large pad")
end

function buttonModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    p = getAllDataFromParameter(track,fxIndex,0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    if reaper.ImGui_Button(ctx, "Button", buttonWidth*2, 40) then 
        reaper.TrackFX_SetParam(track, fxIndex, 1, p.currentValue > 0.5 and 0 or 1)
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
end


function macroModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, false, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
end


function macroModulator4(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    for i = 0, 3 do 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1 + i * 4), focusedParamNumber, nil, nil, nil, false, buttonWidth*2, 0) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2 + i * 4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3 + i * 4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    end
end

function midiOutModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    -- msg type
    --parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    
    local list = {"Note Off","Note On","Polyphonic Aftertouch","Control Change","Program Change","Channel Aftertouch","Pitch Bend"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    local p = getAllDataFromParameter(track,fxIndex,0)
    local midiType = list[p.value + 1]
    createSlider(track,fxIndex,"Combo",0,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Select MIDI output type")
    -- msg2
    if p.value < 5 then
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 0) 
    else 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    end
    -- msg3
    -- channel
    parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, true, buttonWidth*2, 1) 
    -- pb
end



function abSliderModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    --local startPosX, startPosY = beginModulator(name, fxIndex) 
    local sliderIsMapped = parameterWithNameIsMapped(name) 
    if not a_trackPluginStates then a_trackPluginStates = {}; b_trackPluginStates = {} end
    local hasBothValues = a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid]
    local clearName = sliderIsMapped
    
    if isCollabsed and hasBothValues then 
        
    elseif isCollabsed then
        reaper.ImGui_InvisibleButton(ctx,"1",20,1)
    end
    reaper.ImGui_TableNextColumn(ctx)
    
    if not isCollabsed then  
        local buttonName = clearName and "Clear! Values to A" or (a_trackPluginStates[fx.guid] and "A values are saved" or "Set A values")
        local clearType = nil 
        --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
        if reaper.ImGui_Button(ctx, buttonName, dropDownSize) then
            if clearName then
                clearType = "MinValue" 
                if not b_trackPluginStates[fx.guid] then
                    b_trackPluginStates[fx.guid] = getTrackPluginsParameterLinkValues(name, clearType) 
                end
            else 
                if a_trackPluginStates[fx.guid] then
                    a_trackPluginStates[fx.guid] = nil
                else
                    a_trackPluginStates[fx.guid] = getTrackPluginValues(track, fx)
                end
            end
            if a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid] then
                if not comparePluginValues(b_trackPluginStates[fx.guid], a_trackPluginStates[fx.guid], track, modulationContainerPos, fxIndex) then
                    a_trackPluginStates[fx.guid] = nil
                    showTextField = true
                end
            end
        end
        reaper.ImGui_Spacing(ctx)
        
        --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
        local buttonName = clearName and "Clear! Values to B" or (b_trackPluginStates[fx.guid] and "B values are saved" or "Set B values")
        if reaper.ImGui_Button(ctx, buttonName, dropDownSize) then
            if clearName then
                clearType =  "MaxValue" 
                if not a_trackPluginStates[fx.guid] then
                    a_trackPluginStates[fx.guid] = getTrackPluginsParameterLinkValues(name, clearType)
                end
            else  
                if b_trackPluginStates[fx.guid] then
                    b_trackPluginStates[fx.guid] = nil
                else
                    b_trackPluginStates[fx.guid] = getTrackPluginValues(track)
                end
            end
            if a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid] then
                if not comparePluginValues(a_trackPluginStates[fx.guid], b_trackPluginStates[fx.guid], track, modulationContainerPos, fxIndex) then
                    b_trackPluginStates[fx.guid] = nil
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
            
            -- AB SLIDER
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, true, false, false, buttonWidth*2, 0, "%0.2f") 
            
            --reaper.ImGui_Spacing(ctx)
        end
        
        if clearType then
            disableAllParameterModulationMappingsByName(name, "CurrentValue")
            if clearType ~= "MaxValue" then
                a_trackPluginStates[fx.guid] = nil
            end
            if clearType ~= "MinValue" then
                b_trackPluginStates[fx.guid] = nil
            end
            
        end
    end
end



function adsrModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    if not isCollabsed then
        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 0)
        local ret, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 0) 
        if ret and tonumber(visualValue) then 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, nil, nil, "Attack", buttonWidth*2, 5.01, math.floor(tonumber(visualValue)) .. " ms") 
        end
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,7), focusedParamNumber, nil, nil, nil, "A.Tension", buttonWidth*2, 0, "%0.2f") 
        
        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 1)
        local ret, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 1) 
        if ret and tonumber(visualValue) then 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, "Decay", buttonWidth*2, 5.3, math.floor(tonumber(visualValue)) .. " ms")
        end
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,8), focusedParamNumber, nil, nil, nil, "D.Tension", buttonWidth*2, 0, "%0.2f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, "Sustain", buttonWidth*2, 80, "%0.0f") 
 
        local _, min, max = reaper.TrackFX_GetParam(track, fxIndex, 3)
        local ret, visuelValue = reaper.TrackFX_GetFormattedParamValue(track, fxIndex, 3) 
        if ret and tonumber(visualValue) then 
            parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, "Release", buttonWidth*2, 6.214, math.floor(tonumber(visualValue)) .. " ms")
        end
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,9), focusedParamNumber, nil, nil, nil, "R.Tension", buttonWidth*2, 0, "%0.2f") 
        
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, "Min", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, "Max", buttonWidth*2, 100, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, "Smooth", buttonWidth*2, 0, "%0.0f") 
    end
end




function msegModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx)
    
    reaper.ImGui_TableNextColumn(ctx)
     
    
    --reaper.ImGui_TableNextRow(ctx)
    if not isCollabsed then
        
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
        
        --createSlider(track,fxIndex,"SliderDouble",0,"Pattern",1,12,100,"%0.0f",nil,nil,nil,nil) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,0), focusedParamNumber, nil, nil, nil, "Pattern", buttonWidth*2, 0, "%0.0f") 
        
        createSlider(track,fxIndex,"Combo",1,"Trigger",nil,nil,1,nil,nil,nil,triggersDropDownText,0,"Select how to trigger pattern")
        scrollHoveredDropdown(reaper.TrackFX_GetParam(track, fxIndex, 1), track,fxIndex, 1, triggers,nil, 0, #triggers-1)
        
        createSlider(track,fxIndex,"Combo",2,"Tempo Sync",nil,nil,1,nil,nil,nil,tempoSyncDropDownText,0,"Select if the tempo should sync")
        scrollHoveredDropdown(reaper.TrackFX_GetParam(track, fxIndex, 2), track,fxIndex, 2, tempoSync,nil, 0, #tempoSync-1)
        
        local syncOff = reaper.TrackFX_GetParam(track, fxIndex, 2)
        if math.floor(syncOff) == 0  then 
          parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, "Rate", buttonWidth*2, 0, "%0.2f Hz") 
        end
        
        
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, "Phase", buttonWidth*2, 0, "%0.2f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,5), focusedParamNumber, nil, nil, nil, "Min", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,6), focusedParamNumber, nil, nil, nil, "Max", buttonWidth*2, 100, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,7), focusedParamNumber, nil, nil, nil, "Smooth", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,8), focusedParamNumber, nil, nil, nil, "Att. Smooth", buttonWidth*2, 0, "%0.0f") 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,9), focusedParamNumber, nil, nil, nil, "Rel. Smooth", buttonWidth*2, 0, "%0.0f") 
        
        -- RETRIGGER DOES NOT WORK. PROBABLY CAUSE IT*S A SLIDER WITH 1 STEP ONLY.
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,13), focusedParamNumber, nil, nil, nil, "Retrigger", buttonWidth*2, 0, "%0.0f") 
        --createSlider(track,fxIndex,"SliderDouble",13,"Retrigger",0,1,1,"%0.0f",nil,nil,nil,nil)
        --createSlider(track,fxIndex,"SliderDouble",14,"Vel Modulation",0,1,1,"%0.2f",nil,nil,nil,nil)
    end
    
    
    --mapButton(fxIndex, name)
    
    --reaper.ImGui_Spacing(ctx)
    
    --endModulator(name, startPosX, startPosY, fxIndex)
end




function _4in1Out(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx) 
    
    --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end
    reaper.ImGui_TableNextColumn(ctx)
    
    if not isCollabsed then 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,1), focusedParamNumber, nil, nil, nil, "Input 1", buttonWidth*2, 1) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,2), focusedParamNumber, nil, nil, nil, "Input 2", buttonWidth*2, 1) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,3), focusedParamNumber, nil, nil, nil, "Input 3", buttonWidth*2, 1) 
        parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,4), focusedParamNumber, nil, nil, nil, "Input 4", buttonWidth*2, 1) 
    end
    
    
end




function genericModulator(id, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo)
    
    -- make it possible to have it multi output. Needs to change genericModulatorInfo everywhere.
    local numParams = reaper.TrackFX_GetNumParams(track,fxIndex) 
    local isMapped = genericModulatorInfo and genericModulatorInfo.outputParam ~= -1
    
    
    if not isCollabsed and not isMapped then
        reaper.ImGui_TextWrapped(ctx, "Select parameters to use as output") 
    end 
    
    
    if not isCollabsed then
        for p = 0, numParams -1 do
            
            
            --x, y = reaper.ImGui_GetCursorPos(ctx)
            hide = hideParametersFromModulator ~= fx.guid and trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] and trackSettings.hideParametersFromModulator[fx.guid][p]
            
            if not hide then
                if genericModulatorInfo.outputParam == p then reaper.ImGui_BeginDisabled(ctx) end
                parameterNameAndSliders("modulator",pluginParameterSlider, getAllDataFromParameter(track,fxIndex,p), focusedParamNumber, nil, nil, nil, false, buttonWidth*2, 1, nil, genericModulatorInfo.outputParam) 
                if genericModulatorInfo.outputParam == p then reaper.ImGui_EndDisabled(ctx) end
                
                reaper.ImGui_Spacing(ctx)
            end
             
        end
        
        --if drawFaderFeedback(nil, nil, fxIndex,10, 0, 1, isCollabsed, fx) then
        --    mapModulatorActivate(fxIndex,10, fxInContainerIndex, name)
        --end 
    end
    
    
    --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end 
     
    --endModulator(name, startPosX, startPosY, fxIndex)
    return genericModulatorInfo
end


function getColorSetsAndSelectedIndex() 
    local allColorSets = get_files_in_folder(colorFolderName) 
    local selectedColorSetIndex = 0
    for i, colorSetName in ipairs(allColorSets) do  
        if settings.selectedColorSet == colorSetName then
            selectedColorSetIndex = i
            break;
        end
    end 
    return allColorSets, selectedColorSetIndex
end

function setColorSet(index, allColorSets)
    settings.selectedColorSet = allColorSets[index]
    local currentSettingsStr = readFile(settings.selectedColorSet, colorFolderName)
    settings.colors = currentSettingsStr and json.decodeFromJson(currentSettingsStr) or {}
    
    -- BACKWARDS COMPATABILITY
    for key, value in pairs(defaultSettings.colors) do
        if settings.colors[key] == nil then
            settings.colors[key] = value
        end
    end
    -- BACKWARDS COMPATABILITY
    for key, value in pairs(settings.colors) do
        if defaultSettings.colors[key] == nil then
            settings.colors[key] = nil
        end
    end
    
    defaultSettings.colors = deepcopy(settings.colors)
    saveSettings()
end

local function colorButton(title, textColor, buttonColor, activeColor, hoverColor, toolTipText, toolTipTextColor, sizeW)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), buttonColor)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), activeColor)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hoverColor)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)
    local click = reaper.ImGui_Button(ctx, title, sizeW) 
    if toolTipText and reaper.ImGui_IsItemHovered(ctx) then 
        if toolTipTextColor then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), toolTipTextColor) end
        reaper.ImGui_SetTooltip(ctx,toolTipText)
        if toolTipTextColor then reaper.ImGui_PopStyleColor(ctx) end
    end
    reaper.ImGui_PopStyleColor(ctx,4)
    return click
end


---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

function floatingMapperSettings()



    local ret, val = reaper.ImGui_Checkbox(ctx,"Use floating mapper##",settings.useFloatingMapper) 
    if ret then 
        settings.useFloatingMapper = val
        saveSettings()
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    setToolTipFunc("Enable this to show a floating mapper when mapping parameters")
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"Hide when clicking outside floating window##",settings.onlyKeepShowingWhenClickingFloatingWindow) 
    if ret then 
        settings.onlyKeepShowingWhenClickingFloatingWindow = val
        saveSettings()
    end
    setToolTipFunc("Hide when clicking anything that's not the floating window")
    
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"Keep when clicking in app window##",settings.keepWhenClickingInAppWindow) 
    if ret then 
        settings.keepWhenClickingInAppWindow = val
        saveSettings()
    end
    setToolTipFunc("Do not hide when clicking the FX Modulator Linking app") 
    
    
    --reaper.ImGui_TextColored(ctx, colorGrey, "Open floating mapper relative to mouse")
    
    reaper.ImGui_TextColored(ctx, colorGrey, "Open floating mapper relative to")
    local ret = reaper.ImGui_RadioButton(ctx,"FX window##",settings.openFloatingMapperRelativeToWindow) 
    if ret then 
        settings.openFloatingMapperRelativeToMouse = false
        settings.openFloatingMapperRelativeToWindow = true
        saveSettings()
    end
    setToolTipFunc("If this is enabled, the below will be the position of the floating mapper") 
    
    reaper.ImGui_SameLine(ctx)
    
    local ret = reaper.ImGui_RadioButton(ctx,"mouse click##",settings.openFloatingMapperRelativeToMouse) 
    if ret then 
        settings.openFloatingMapperRelativeToMouse = true
        settings.openFloatingMapperRelativeToWindow = false
        saveSettings()
    end
    setToolTipFunc("If this is enabled, the below will be the position of the floating mapper") 
    
    local sizeOfChooser = 156
    
    --reaper.ImGui_BeginGroup(ctx)
    if settings.openFloatingMapperRelativeToWindow then
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) +8)
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) +8)
        
        reaper.ImGui_BeginGroup(ctx)
        for i = 1, 25 do 
            
            local ignore = i == 1 or i == 5 or i == 21 or i == 25 or i == 7 or i == 8 or i == 9 or i == 12 or i == 13 or i == 14 or i == 17 or i == 18 or i == 19
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), ignore and colorTransparent or colorMapping)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), ignore and colorTransparent or colorMappingLight)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), ignore and colorTransparent or colorMappingLight)
            
            if reaper.ImGui_Selectable(ctx, "##relativeToWindow" .. i, settings.openFloatingMapperRelativeToWindowPos == i, nil, sizeOfChooser/5, sizeOfChooser/5) and not ignore then
                settings.openFloatingMapperRelativeToWindowPos = i
                saveSettings()
            end 
            
            if i == 1 then minX, minY = reaper.ImGui_GetItemRectMin(ctx) end
            if i == 25 then maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) end
            if i%5 ~= 0 then 
                reaper.ImGui_SameLine(ctx)
            end
            
            
            reaper.ImGui_PopStyleColor(ctx,3)
        end
        local w = maxX - minX
        local h = maxY - minY
        
        
        
        --local textW, textH = reaper.ImGui_CalcTextSize(ctx, "Mapper", 0,0)
        --reaper.ImGui_DrawList_AddText(draw_list, minX + w/2-textW/2, minY + h/2 - textH/2,colorText, "Mapper")
        
        --reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY,colorText, 0, nil, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX + w/5, minY, minX + w/5, maxY,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX + w/5*2, minY, minX + w/5*2, maxY,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX + w/5*3, minY, minX + w/5*3, maxY,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX + w/5*4, minY, minX + w/5*4, maxY,colorText, 2)
        
        reaper.ImGui_DrawList_AddLine(draw_list, minX, minY + h/5, maxX, minY + h/5,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX, minY + h/5*2, maxX, minY + h/5*2,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX, minY + h/5*3, maxX, minY + h/5*3,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX, minY + h/5*4, maxX, minY + h/5*4,colorText, 2)
        
        reaper.ImGui_DrawList_AddLine(draw_list, minX + w/5, minY, minX + w/5*4, minY,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX + w/5, maxY, minX + w/5*4, maxY,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, minX, minY + h/5, minX, minY + h/5*4,colorText, 2)
        reaper.ImGui_DrawList_AddLine(draw_list, maxX, minY + h/5, maxX, minY + h/5*4,colorText, 2)
        
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, minX + w / 5+1, minY + h/5+1, minX + w/5*4, minY + h/5*4,colorButtons, 0)
        
        local textW, textH = reaper.ImGui_CalcTextSize(ctx, "Plugin", 0,0)
        reaper.ImGui_DrawList_AddText(draw_list, minX + w/2-textW/2, minY + h/2 - textH/2,colorText, "Plugin")
        
        reaper.ImGui_EndGroup(ctx)
    end
    
    if settings.openFloatingMapperRelativeToMouse then
        
        reaper.ImGui_InvisibleButton(ctx, "##floatingmapperpos", sizeOfChooser, sizeOfChooser)
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
        local w, h = reaper.ImGui_GetItemRectSize(ctx) 
        reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY,colorText, 0, nil, 2)
        local dotSize = 4
        local centerX = minX + w/2
        local centerY = minY + h/2
        local multiply = 4
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, centerX - dotSize/ 2, centerY - dotSize/ 2, centerX + dotSize/ 2, centerY + dotSize/ 2,colorText, 10)
        
        local mappedDotPos = {x = centerX + settings.openFloatingMapperRelativeToMousePos.x/multiply, y =  centerY + (settings.openFloatingMapperRelativeToMousePos.y * (isApple and -1 or 1))/multiply}
        if math.abs(settings.openFloatingMapperRelativeToMousePos.x) <= sizeOfChooser/2 * multiply and math.abs(settings.openFloatingMapperRelativeToMousePos.y) <= sizeOfChooser/2 * multiply then
            reaper.ImGui_DrawList_AddRectFilled(draw_list, mappedDotPos.x - dotSize/ 2, mappedDotPos.y - dotSize/ 2, mappedDotPos.x + dotSize/ 2, mappedDotPos.y + dotSize/ 2,colorMapping, 10)
        end
        
        if mouse_pos_x_imgui >= minX and mouse_pos_x_imgui <= maxX and mouse_pos_y_imgui >= minY and mouse_pos_y_imgui <= maxY then
            if isMouseDownImgui then
                settings.openFloatingMapperRelativeToMousePos = {x = (mouse_pos_x_imgui - centerX) * multiply, y = (not isApple and (mouse_pos_y_imgui - centerY) or (centerY - mouse_pos_y_imgui)) * multiply}
                saveSettings()
            end 
        end
        --reaper.ImGui_EndGroup(ctx)
        
        --reaper.ImGui_SameLine(ctx)
        --reaper.ImGui_BeginGroup(ctx)
        --local posText = "Postion relative to mouse" 
        --reaper.ImGui_TextColored(ctx, colorText, posText)
        reaper.ImGui_SetNextItemWidth(ctx, 100)
        local ret, val = reaper.ImGui_InputInt(ctx, "pixels " .. (settings.openFloatingMapperRelativeToMousePos.x >= 0 and "right" or "left"), settings.openFloatingMapperRelativeToMousePos.x, 2) 
        if ret then
            --if val > 100 then val = 100 end
            --if val < -100 then val = -100 end
            settings.openFloatingMapperRelativeToMousePos.x = val
        end
        
        reaper.ImGui_SetNextItemWidth(ctx, 100)
        local ret, val = reaper.ImGui_InputInt(ctx, "pixels " .. (settings.openFloatingMapperRelativeToMousePos.y >= 0 and "above" or "below"), settings.openFloatingMapperRelativeToMousePos.y, 2)
        if ret then
            --if val > 100 then val = 100 end
            --if val < -100 then val = -100 end
            settings.openFloatingMapperRelativeToMousePos.y = val
        end
        --posText = "of clicked position"
        --reaper.ImGui_TextColored(ctx, colorTextDimmed, posText) 
    end
    local ret, val = reaper.ImGui_Checkbox(ctx,"Force mapping##",settings.forceMapping) 
    if ret then 
        settings.forceMapping = val
        saveSettings()
    end
    setToolTipFunc("This will ensure that you always map a parameter if you click on it.\nThe downside is that that the last touched FX parameter will always be the delta value for the focused FX, in order to ensure this behavior.") 
    
    --reaper.ImGui_EndGroup(ctx)
end

function envelopeSettings()
    local ret, val = reaper.ImGui_Checkbox(ctx,"Show envelope of focused parameter##",settings.showEnvelope) 
    if ret then 
        settings.showEnvelope = val
        saveSettings()
    end
    setToolTipFunc("Show the envelope when focusing on a new parameter")
    
    if not settings.showEnvelope then reaper.ImGui_BeginDisabled(ctx) end
        local ret, val = reaper.ImGui_Checkbox(ctx,"Show envelope in media lane##",settings.showClickedInMediaLane) 
        if ret then 
            settings.showClickedInMediaLane = val
            saveSettings()
        end
        setToolTipFunc("Show the focused parameter envelope in the media lane, instead of it's own lane, to easily find it")
         
        local ret, val = reaper.ImGui_Checkbox(ctx,"Hide envelopes without no points##",settings.hideEnvelopesWithNoPoints) 
        if ret then 
            settings.hideEnvelopesWithNoPoints = val
            saveSettings()
        end
        setToolTipFunc("Hide envelopes with no envelope points when focusing an a new envelope")  
        
        local ret, val = reaper.ImGui_Checkbox(ctx,"Hide envelopes with points##",settings.hideEnvelopesWithPoints) 
        if ret then 
            settings.hideEnvelopesWithPoints = val
            saveSettings()
        end
        setToolTipFunc("Hide envelopes with envelope points when focusing an a new envelope") 
        
    
    if not settings.showEnvelope then reaper.ImGui_EndDisabled(ctx) end
    
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Show all active track envelopes") then
        hideShowAllTrackEnvelopes(track, nil, true, true)
    end
    
    if reaper.ImGui_Button(ctx, "Hide all track envelopes") then
        hideShowAllTrackEnvelopes(track, nil, false)
    end
    
    if reaper.ImGui_Button(ctx, "Arm all visible track envelopes") then
        armAllVisibleTrackEnvelopes(track, true, false)
    end
    
    if reaper.ImGui_Button(ctx, "Disam all track envelopes") then
        armAllVisibleTrackEnvelopes(track, false, true)
    end
    
    if reaper.ImGui_Button(ctx, "Show all visible track envelopes in envelope lanes") then
        showAllEnvelopesInTheirLanesOrNot(track, nil, false)
    end
    
    if reaper.ImGui_Button(ctx, "Show all visible track envelopes in media lanes") then
        showAllEnvelopesInTheirLanesOrNot(track, nil, true)
    end 
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx, colorTextDimmed, "Track automation mode:")
    
    automationRadioSelect(track)
    --[[
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"Add additional point before newly inserted envelopes##",settings.insertEnvelopeBeforeAddingNewEnvelopePoint) 
    if ret then 
        settings.insertEnvelopeBeforeAddingNewEnvelopePoint = val
        saveSettings()
    end
    setToolTipFunc("When not playing and inserting an envelope point via a the script, insert a envelope point just before to make it jump to the new value") 
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"If time selection, add envelopes points on there##",settings.insertEnvelopePointsAtTimeSelection) 
    if ret then 
        settings.insertEnvelopePointsAtTimeSelection = val
        saveSettings()
    end
    setToolTipFunc("When not playing and a time selection is made, inserting envelope points at start and end of the time selection") 
    ]]
end

function appSettingsWindow() 
    local rv, open = reaper.ImGui_Begin(ctx, appName .. ' Settings', true, reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() ) 
    if not rv then return open end
    
    
    local menuWidth = 200
    function sliderInMenu(name, tag, width, min, max, toolTip, double) 
        toolTip = toolTip and toolTip or nil
        reaper.ImGui_SetNextItemWidth(ctx, width / 2)
        if double then
            ret, val = reaper.ImGui_SliderDouble(ctx, "##" .. name .. tag, settings[tag],min,max)
        else
            ret, val = reaper.ImGui_SliderInt(ctx, "##" .. name .. tag, settings[tag],min,max)
        end
        if ret then
            settings[tag] = val
            if not is_docked and settings.vertical then  
                --reaper.ImGui_SetNextWindowSize(ctx, 0, winH) 
                --last_vertical = 1
            end  
            saveSettings()
        end
        setToolTipFunc(toolTip)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, name)
        setToolTipFunc(toolTip)
        if reaper.ImGui_IsItemClicked(ctx) then
            settings[tag] = defaultSettings[tag]
            saveSettings()
        end
        return ret 
    end
    
    function inputInMenu(name, tag, width, toolTip, double, min, max) 
        toolTip = toolTip and toolTip or nil
        reaper.ImGui_SetNextItemWidth(ctx, width / 2)
        if double then
            ret, val = reaper.ImGui_InputDouble(ctx, "##" .. name .. tag, settings[tag], nil, nil, "%0.0f")
        else
            ret, val = reaper.ImGui_InputInt(ctx, "##" .. name .. tag, settings[tag])
        end
        if ret then
            if min and val < min then val = min end
            if max and val > max then val = max end
            settings[tag] = val
            saveSettings()
        end
        setToolTipFunc(toolTip)
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, name)
        setToolTipFunc(toolTip)
        if reaper.ImGui_IsItemClicked(ctx) then
            settings[tag] = defaultSettings[tag]
            saveSettings()
        end
        return ret 
    end
    
    
    function modifiersSettingsModule(tag, preTag)
        local modifiers = {"Super", "Ctrl","Shift",  "Alt"}
        for i, mod in ipairs(modifiers) do 
            local isEnabled 
            if preTag then 
                isEnabled  = settings[preTag] and settings[preTag][tag] and settings[preTag][tag][mod]
            else 
                isEnabled = settings[tag] and settings[tag][mod]
            end
            
            if reaper.ImGui_Checkbox(ctx, mod .."##" .. tag, isEnabled) then 
                if preTag then
                    settings[preTag][tag][mod] = not isEnabled
                else
                    settings[tag][mod] = not isEnabled
                end
                saveSettings()
            end 
            if i < #modifiers then
                reaper.ImGui_SameLine(ctx)
            end
        end
    end
    
    local ret, vertical = reaper.ImGui_Checkbox(ctx,"Vertical layout",settings.vertical)
    if ret then 
        settings.vertical = vertical 
        saveSettings()
       -- reaper.ImGui_CloseCurrentPopup(ctx) 
    end
    reaper.ImGui_SameLine(ctx)
    local ret, showToolTip = reaper.ImGui_Checkbox(ctx,"Show tooltips",settings.showToolTip)
    if ret then 
        settings.showToolTip = showToolTip
        saveSettings()
    end
    
    reaper.ImGui_SameLine(ctx)
    local ret, focusFollowsFxClicks = reaper.ImGui_Checkbox(ctx,"Focus follows click on FX", settings.focusFollowsFxClicks)
    if ret then 
        settings.focusFollowsFxClicks = focusFollowsFxClicks
        saveSettings()
    end 
    setToolTipFunc("When touching a FX parameter, change the track focus (if the FX is from another track)")  
    
    if settings.focusFollowsFxClicks then
        
        reaper.ImGui_SameLine(ctx)
        local ret, trackSelectionFollowFocus = reaper.ImGui_Checkbox(ctx,"Select track on focus change", settings.trackSelectionFollowFocus)
        if ret then 
            settings.trackSelectionFollowFocus = trackSelectionFollowFocus
            saveSettings()
        end
        setToolTipFunc("Select the specific when touching a FX parameter that's from another track")
    end
    
    reaper.ImGui_SameLine(ctx)
    local ret, val = reaper.ImGui_Checkbox(ctx,"Allow collapsing",settings.allowCollapsingMainWindow)
    if ret then 
        settings.allowCollapsingMainWindow = val 
        saveSettings()
       -- reaper.ImGui_CloseCurrentPopup(ctx) 
    end
    setToolTipFunc("Allow collapsing app window")
    
    
    reaper.ImGui_NewLine(ctx)
    local menus = {}
    function menus.Layout()
        local set = {}
        function set.general()
            reaper.ImGui_TextColored(ctx, colorGrey, "Panels/Modules")
            
            if sliderInMenu("Panels width", "partsWidth", menuWidth, 140, 400, "Set the max width of panels. ONLY in horizontal mode") then 
                setWindowWidth = true
            end
            
            sliderInMenu("Panels height", "modulesHeightVertically", menuWidth, 80, 550, "Set the max height of panels. ONLY in vertical mode") 
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Limit module height in vertical mode",settings.limitModulatorHeightToModulesHeight) 
            if ret then 
                settings.limitModulatorHeightToModulesHeight = val
                saveSettings()
            end
            setToolTipFunc("Limit modulators height to panels height set above in vertical mode")  
            
            
            --reaper.ImGui_NewLine(ctx)
            
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Track coloring")
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Track color around lock",settings.trackColorAroundLock) 
            if ret then 
                settings.trackColorAroundLock = val
                saveSettings()
            end
            setToolTipFunc("Have track color shown as a border around the lock")  
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Track color as line",settings.showTrackColorLine) 
            if ret then 
                settings.showTrackColorLine = val
                saveSettings()
            end
            setToolTipFunc("Have track color as a line on the left in horizontal mode or on top in vertical mode") 
            
            sliderInMenu("Track color line size", "trackColorLineSize", menuWidth, 1, 6, "Set the size of the color line") 
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Others")
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Automation color on envelope button",settings.useAutomationColorOnEnvelopeButton) 
            if ret then 
                settings.useAutomationColorOnEnvelopeButton = val
                saveSettings()
            end
            setToolTipFunc("Show the automation color on the envelope button drawing. Set the background in color settings for better visibility") 
        end
        
        
        --reaper.ImGui_TableNextRow(ctx)
        --reaper.ImGui_TableNextColumn(ctx)
        function set.plugins()
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show panel##plugins",settings.showPluginsPanel) 
            if ret then 
                settings.showPluginsPanel = val
                saveSettings()
            end
            setToolTipFunc("Show or hide the plugins panel")  
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Hide plugin type from name",settings.hidePluginTypeName) 
            if ret then 
                settings.hidePluginTypeName = val
                saveSettings()
            end
            setToolTipFunc("Hide plugin type from name")  
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Allow horizontal scrolling",settings.allowHorizontalScroll) 
            if ret then 
                settings.allowHorizontalScroll = val
                saveSettings()
            end
            setToolTipFunc("Allow to scroll horizontal in the plugin list, when namas are too big for module") 
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Panel Controls")
            
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show at top of panel##plugins",settings.showPluginOptionsOnTop) 
            if ret then 
                settings.showPluginOptionsOnTop = val
                saveSettings()
            end
            setToolTipFunc("Show Open All and Add Track FX at the top of the plugins panel")  
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Open all" button',settings.showOpenAll) 
            if ret then 
                settings.showOpenAll = val
                saveSettings()
            end
            setToolTipFunc("Show Open all button in plugins area")  
            
            local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Add FX" button',settings.showAddTrackFX) 
            if ret then 
                settings.showAddTrackFX = val
                saveSettings()
            end
            setToolTipFunc("Show a button that will allow to add track fx (not a modulator) in the plugins panel")  
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Containers")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show containers",settings.showContainers) 
            if ret then 
                settings.showContainers = val
                saveSettings()
            end
            setToolTipFunc("Show FX container in the plugin list")  
            
            if settings.showContainers then
                local ret, val = reaper.ImGui_Checkbox(ctx,"Color containers",settings.colorContainers) 
                if ret then 
                    settings.colorContainers = val
                    saveSettings()
                end
                setToolTipFunc("Color FX container grey in the plugin list")  
            end
             
            
            sliderInMenu("Indent size for containers", "indentsAmount", menuWidth, 0, 8, "Set how large a visual indents size is shown for container content in the plugin list")
        end 
         
        
        
        function set.parameters()
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show panel##parameters",settings.showParametersPanel) 
            if ret then 
                settings.showParametersPanel = val
                saveSettings()
            end
            setToolTipFunc("Show or hide the parameters panel")  
            
            
            
            inputInMenu("Max parameters shown", "maxParametersShown", 100, "Will only fetch X amount of parameters from focused FX. 0 will show all.\nIf you have problems with performance reduce the amount might help", true, 0, nil) 
            
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Panel Controls")
            
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show at top of panel##parameters",settings.showParameterOptionsOnTop) 
            if ret then 
                settings.showParameterOptionsOnTop = val
                saveSettings()
            end
            setToolTipFunc("Show search field, only mapped and last clicked parameter on top of the mappings panel")  
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show search field",settings.showSearch) 
            if ret then 
                settings.showSearch = val
                saveSettings()
            end
            setToolTipFunc("Show search field in parameters panel")  
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Searching disables only mapped##",settings.searchClearsOnlyMapped) 
            if ret then 
                settings.searchClearsOnlyMapped = val
                saveSettings()
            end
            setToolTipFunc('When enabled this will disable to "Only mapped" toggle, when searching') 
            
            local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Only mapped" button',settings.showOnlyMapped) 
            if ret then 
                settings.showOnlyMapped = val
                saveSettings()
            end
            setToolTipFunc("Show only mapped toggle in parameters panel")  
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show last clicked parameter##",settings.showLastClicked) 
            if ret then 
                settings.showLastClicked = val
                saveSettings()
            end
            setToolTipFunc("Show the last clicked parameter below the search field")  
            
            
            
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "Mapping area buttons")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show remove button (x)##parameters",settings.showRemoveCrossParameter) 
            if ret then 
                settings.showRemoveCrossParameter = val
                saveSettings()
            end
            setToolTipFunc('Show "X" when hovering map parameter to remove mapping')
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show extra controls when mapped##",settings.showExtraLineInParameters) 
            if ret then 
                settings.showExtraLineInParameters = val
                saveSettings()
            end
            setToolTipFunc("When a parameter is mapped, show an extra line containing enable/disable, knob for width, polarity and mapped modulator name.\nThese functions are also accesible through modifiers or right click")
            
            
            if not settings.showExtraLineInParameters then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed) end
                reaper.ImGui_Indent(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show enable/disable checkbox##parameters",settings.showEnableInParameters) 
                if ret then 
                    settings.showEnableInParameters = val
                    saveSettings()
                end
                setToolTipFunc("Show enable/disable check box on mapped parameters") 
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show bipolar toggle/mode switch##parameters",settings.showBipolarInParameters) 
                if ret then 
                    settings.showBipolarInParameters = val
                    saveSettings()
                end
                setToolTipFunc("Show bipolar button or mode switch on mapped parameters") 
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show width knob##parameters",settings.showWidthInParameters) 
                if ret then 
                    settings.showWidthInParameters = val
                    saveSettings()
                end
                setToolTipFunc("Show width knob on mapped parameters") 
                reaper.ImGui_Unindent(ctx)
                
            if not settings.showExtraLineInParameters then reaper.ImGui_PopStyleColor(ctx) end
        end    
        
        
        function set.modules()
        
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show panel##modules",settings.showModulesPanel) 
            if ret then 
                settings.showModulesPanel = val
                saveSettings()
            end
            setToolTipFunc("Show or hide the modules panel")  
        end
        
        function set.modulators()
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Panel")
            
            
             
            local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Sort by name" on panel',settings.showSortByNameModulator) 
            if ret then 
                settings.showSortByNameModulator = val
                saveSettings()
            end
            setToolTipFunc('Show "Sort by name" switch on modulators panel') 
            
            reaper.ImGui_Indent(ctx)
            
            local ret, sortAsType = reaper.ImGui_Checkbox(ctx,"Sort by name",settings.sortAsType)
            if ret then
                settings.sortAsType = sortAsType
                saveSettings()
            end 
            
            reaper.ImGui_Unindent(ctx)
            
             
            local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Map once" on panel',settings.showMapOnceModulator) 
            if ret then 
                settings.showMapOnceModulator = val
                saveSettings()
            end
            setToolTipFunc('Show "Map once" switch on modulators panel')  
            
            
            reaper.ImGui_Indent(ctx)
            local ret, mapOnce = reaper.ImGui_Checkbox(ctx,"Map once",settings.mapOnce)
            if ret then
                settings.mapOnce = mapOnce
                saveSettings()
            end
            
            reaper.ImGui_Unindent(ctx)
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show add button (+) at start##mappings",settings.showAddModulatorButtonBefore) 
            if ret then 
                settings.showAddModulatorButtonBefore = val
                saveSettings()
            end
            setToolTipFunc('Show a small "+" before the first modulator, that you can click to add a new modulator') 
             
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show add button (+) at end##mappings",settings.showAddModulatorButton) 
            if ret then 
                settings.showAddModulatorButton = val
                saveSettings()
            end
            setToolTipFunc('Show a small "+" after the last modulator, that you can click to add a new modulator') 
             
            reaper.ImGui_NewLine(ctx) 
            reaper.ImGui_TextColored(ctx, colorGrey, "Modules")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show remove button (x)##modulator",settings.showRemoveCrossModulator) 
            if ret then 
                settings.showRemoveCrossModulator = val
                saveSettings()
            end
            setToolTipFunc('Show "X" when hovering modulator to remove modulator') 
            
             
            sliderInMenu("Default visualizer size", "visualizerSize", menuWidth, 1, 3, "Set the size of the visualizer (output) for modulators")  
             
            
        end
        
        function set.mappings()
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show remove button (x)##mappings",settings.showRemoveCrossMapping) 
            if ret then 
                settings.showRemoveCrossMapping = val
                saveSettings()
            end
            setToolTipFunc('Show "X" when hovering mapping to remove mapping') 
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show enable/disable checkbox##",settings.showEnableInMappings) 
            if ret then 
                settings.showEnableInMappings = val
                saveSettings()
            end
            setToolTipFunc("Show enable/disable check box on mappings") 
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show bipolar toggle/mode switch##",settings.showBipolarInMappings) 
            if ret then 
                settings.showBipolarInMappings = val
                saveSettings()
            end
            setToolTipFunc("Show bipolar button or mode switch on mappings") 
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show width knob##",settings.showWidthInMappings) 
            if ret then 
                settings.showWidthInMappings = val
                saveSettings()
            end
            setToolTipFunc("Show width knob on mappings") 
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "Open mappings options popup")
            
            local pos = {"Left", "Below", "Right", "Fixed"}
            for i, p in ipairs(pos) do
                if reaper.ImGui_RadioButton(ctx, p, settings.openMappingsPanelPos == p) then
                    settings.openMappingsPanelPos = p
                    saveSettings()
                end
                --if i < #pos then
                    reaper.ImGui_SameLine(ctx)
                --end
            end 
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "clicked mapping")
        
        end
                
        local groups = {"General", "Plugins", "Parameters", "Modules", "Modulators","Mappings" }
        
        
        if reaper.ImGui_BeginTabBar(ctx, '##layouttab') then
            for i, g in ipairs(groups) do
                
                
                
                if reaper.ImGui_BeginTabItem(ctx, g) then
                if reaper.ImGui_BeginChild(ctx, "layoutchild" .. g,nil,nil,nil, reaper.ImGui_WindowFlags_HorizontalScrollbar()) then
                
                    set[g:lower()]()
                    reaper.ImGui_EndChild(ctx)
                end
                
                ImGui.EndTabItem(ctx) 
                
                end
            end
            
            ImGui.EndTabBar(ctx)
        end
        --reaper.ImGui_PopStyleVar(ctx)
            
    end 
    
    --if ImGui.BeginTabItem(ctx, 'Mapping') then
    
    function menus.Mapping()
        
        local set = {}
        
        local ret, val = reaper.ImGui_Checkbox(ctx,"Bipolar mapping mode##LFO",settings.mappingModeBipolar) 
        if ret then 
            settings.mappingModeBipolar = val
            saveSettings()
        end
        setToolTipFunc("If enabled mapping a modulator will either be bipolar or not. If disable you have downwards, bipolar and upwards")  
        
        
        function set.General()
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"New mapping uses previous mapping's width and direction",settings.usePreviousMapSettingsWhenOverwrittingMapping) 
            if ret then 
                settings.usePreviousMapSettingsWhenOverwrittingMapping = val
                saveSettings()
            end
            setToolTipFunc("If enabled when mapping an already mapped parameter, the new mapping will optain the previous mappings width and direction")
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Visual")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Pulsate mapping button",settings.pulsateMappingButton) 
            if ret then 
                settings.pulsateMappingButton = val
                saveSettings()
            end
            setToolTipFunc("If enabled the mapping output from a modulator will pulsate when mapping")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Pulsate mapped parameters border",settings.pulsateMappingButtonsMapped) 
            if ret then 
                settings.pulsateMappingButtonsMapped = val
                saveSettings()
            end
            setToolTipFunc("If enabled the border of mapped parameters that have been mapped with the active mapping output, will pulsate when mapping")
            
            
            sliderInMenu("Pulsating speed", "pulsateMappingColorSpeed", menuWidth, 1, 10, "Set how fast the pulsating of the mapping button should be")
            
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Experimental")
            local ret, val = reaper.ImGui_Checkbox(ctx,"Mapping width only positive",settings.mappingWidthOnlyPositive) 
            if ret then 
                settings.mappingWidthOnlyPositive = val
                saveSettings()
            end
            setToolTipFunc("If enabeled the mapped parameter width will only be from 0 to 1, so never negative")  
            
            
        end
        
        
        
        function set.FloatingMapper()
            floatingMapperSettings()
        end
        
        function set.Envelope() 
            envelopeSettings()
        end
        
        
        function set.Defaults()
        
        
            reaper.ImGui_TextColored(ctx, colorGrey, "Mapping mode for modulators")
            sliderInMenu("Width", "defaultMappingWidth", menuWidth, -100, 100, "Set the default width when mapping a parameter") 
             
            if settings.mappingModeBipolar then
                local ret, val = reaper.ImGui_Checkbox(ctx,"Bipolar##others",settings.defaultBipolar) 
                if ret then 
                    settings.defaultBipolar = val
                    saveSettings()
                end
                setToolTipFunc("Set default bipolar state when mapping a parameter")  
            else
                --reaper.ImGui_TextColored(ctx, colorGrey, "Direction")
                for i = 1, #directions, 1 do
                    dir = directions[i]
                    if reaper.ImGui_RadioButton(ctx, dir, i == settings.defaultDirection) then 
                        settings.defaultDirection = i
                        saveSettings()
                    end
                    if i < #directions then reaper.ImGui_SameLine(ctx) end
                end
            end
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Mapping mode for modulators with LFO in the name")
            
            sliderInMenu("Width", "defaultMappingWidthLFO", menuWidth, -100, 100, "Set the default width when mapping a parameter") 
            
            if settings.mappingModeBipolar then
                local ret, val = reaper.ImGui_Checkbox(ctx,"Bipolar##LFO",settings.defaultBipolarLFO) 
                if ret then 
                    settings.defaultBipolarLFO = val
                    saveSettings()
                end
                setToolTipFunc("Set default bipolar state when mapping a parameter")  
            else
                --reaper.ImGui_TextColored(ctx, colorGrey, "Direction for modulators with LFO in the name")
                for i = 1, #directions, 1 do
                    dir = directions[i]
                    if reaper.ImGui_RadioButton(ctx, dir, i == settings.defaultLFODirection) then 
                        settings.defaultLFODirection = i
                        saveSettings()
                    end 
                    if i < #directions then reaper.ImGui_SameLine(ctx) end
                end
            end
            
            reaper.ImGui_NewLine(ctx)
            
            reaper.ImGui_TextColored(ctx, colorGrey, "ACS track audio channel input")
            reaper.ImGui_SetNextItemWidth(ctx,100)
            
            local ret, value = reaper.ImGui_Combo(ctx, "" .. 'Channel##defaultacsModulator', settings.defaultAcsTrackAudioChannelInput, acsTrackAudioChannelDropDownText )
            if ret then  
                settings.defaultAcsTrackAudioChannelInput = value
                saveSettings() 
            end 
        end
        
        local groups =  {"General", "Floating Mapper", "Defaults", "Envelope"}
        local groupsWidth =  {245, 270, 250, 100, 250}
        
        
        if reaper.ImGui_BeginTabBar(ctx, '##layouttab') then
            for i, g in ipairs(groups) do 
                
                if reaper.ImGui_BeginTabItem(ctx, g) then
                if reaper.ImGui_BeginChild(ctx, "layoutchild" .. g,nil,nil,nil, reaper.ImGui_WindowFlags_HorizontalScrollbar()) then
                
                    local setter =g:gsub(" ", "") 
                    set[setter]()
                    reaper.ImGui_EndChild(ctx)
                end
                
                ImGui.EndTabItem(ctx) 
                
                end
            end
            
            ImGui.EndTabBar(ctx)
        end
        
    end
    
    
    function menus.Colors()
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, colorTextDimmed, "Color sets:")
        reaper.ImGui_SameLine(ctx)
        
        
        local allColorSets, selectedColorSetIndex = getColorSetsAndSelectedIndex() 
        
        reaper.ImGui_SetNextItemWidth(ctx, 160)
        ret, val = reaper.ImGui_Combo(ctx, "##ColorSetsSelection", selectedColorSetIndex - 1, table.concat(allColorSets, "\0") .. "\0")
        if ret then 
            setColorSet(tonumber(val) + 1, allColorSets)
        end
        
        
        
        reaper.ImGui_SameLine(ctx)
        if not someValuesAreDifferent then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, "Reset all colors to current color set") then  
            for key in pairs(settings.colors) do
                settings.colors[key] = deepcopy(defaultSettings.colors[key])
            end
            --saveSettings()
        end  
        if not someValuesAreDifferent then reaper.ImGui_EndDisabled(ctx) end
        
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Open color set folder") then  
            open_folder(colorFolderName)
        end 
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Save new color set") then  
            ImGui.OpenPopup(ctx, 'Save color set') 
        end 
        
        reaper.ImGui_Separator(ctx)
        
        if ImGui.BeginPopupModal(ctx, 'Save color set', nil , reaper.ImGui_WindowFlags_AlwaysAutoResize() ) then
          reaper.ImGui_TextColored(ctx, colorTextDimmed, 'Name:') 
          
          reaper.ImGui_SetNextItemWidth(ctx, 248)
          if not tempName then 
              tempName = settings.selectedColorSet 
              reaper.ImGui_SetKeyboardFocusHere(ctx)
          end
          ret, tempName = reaper.ImGui_InputText(ctx, "##nameColorSet", tempName) 
          
          
          local disableSave = tempName == "Light" or tempName == "Dark"
          local nameExists = false
          
          if not disableSave then
              for _, name in ipairs(allColorSets) do
                  if name == tempName then
                      nameExists = true
                  end 
              end
          end
          
          local addToFile = disableSave and "--@noindex\n" or ""
          --if disableSave then reaper.ImGui_BeginDisabled(ctx) end
          if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or (saveWithKeyCommand or reaper.ImGui_Button(ctx, 'Save', 120, 0)) then  
              if tempName then
                  saveFile(addToFile .. json.encodeToJson(settings.colors), tempName, colorFolderName) 
                  settings.selectedColorSet = tempName
                  saveSettings()
                  tempName = nil
              end
              reaper.ImGui_CloseCurrentPopup(ctx) 
          end
          --if disableSave then reaper.ImGui_EndDisabled(ctx) end
          
          ImGui.SameLine(ctx)
          if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) or ImGui.Button(ctx, 'Cancel', 120, 0) then 
              tempName = nil
              reaper.ImGui_CloseCurrentPopup(ctx) 
          end
          local infoLine = (not disableSave and nameExists) and 
              "Name exist, saving will overwrite the set" or 
              (disableSave and tempName) and
              (tempName .. " is a factory set and gets overwritten on updates")
              or "  "
          
          reaper.ImGui_TextColored(ctx,colorTextDimmed, infoLine)
          
          
          ImGui.EndPopup(ctx)
        end
        
        
        
        if ImGui.BeginChild(ctx, '##colors', 0, 0) then
          local inner_spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
          -- Extract the keys
          local colorsOrder = {}
          for key in pairs(settings.colors) do
            table.insert(colorsOrder, key)
          end
          -- Sort alphabetically
          table.sort(colorsOrder)
          
          someValuesAreDifferent = false
          for i, name in pairs(colorsOrder) do
              local formattedName = prettifyString(name)
              color = settings.colors[name]
              
              local isDifferent = settings.colors[name] == defaultSettings.colors[name]
              if isDifferent then reaper.ImGui_BeginDisabled(ctx) else
                  someValuesAreDifferent = true
              end
              
              if reaper.ImGui_Button(ctx, "Reset##resetcolor".. name) then 
                  settings.colors[name] = defaultSettings.colors[name]
                  saveSettings()
              end 
              if isDifferent then reaper.ImGui_EndDisabled(ctx) end
              
              
              reaper.ImGui_SameLine(ctx,0,1)
              
              if reaper.ImGui_Button(ctx, "Copy##".. name) then 
                  clipboardColor = color
              end 
              setToolTipFunc('Copy "' .. formattedName .. '" color to paste buttons')
              
              
              if not clipboardColor then reaper.ImGui_BeginDisabled(ctx) end
              
              
              ImGui.SameLine(ctx, 0.0, 1)
              
              
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorText)
              reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), clipboardColor and clipboardColor or settings.colors.buttons)
              if reaper.ImGui_Button(ctx, "##paste".. name, 20) then 
                  settings.colors[name] = clipboardColor
                  saveSettings()
              end 
              reaper.ImGui_PopStyleColor(ctx, 2)
              reaper.ImGui_PopStyleVar(ctx)
              
              
              if not clipboardColor then reaper.ImGui_EndDisabled(ctx) end
              
              
              setToolTipFunc('Paste color to "' .. formattedName .. '"' )
              
              ImGui.SameLine(ctx, 0.0, inner_spacing)
              
              rv, settings.colors[name] = reaper.ImGui_ColorEdit4(ctx, '##color' .. name, settings.colors[name])
              if rv then
                  saveSettings()
                --ImGui.SameLine(ctx, 0.0, inner_spacing)
                --if ImGui.Button(ctx, 'Save') then
                --  app.style_editor.ref.colors[i] = app.style_editor.style.colors[i]
                --end
                --ImGui.SameLine(ctx, 0.0, inner_spacing)
                --if ImGui.Button(ctx, 'Revert') then
                --  app.style_editor.style.colors[i] = app.style_editor.ref.colors[i]
                --end
              end
              ImGui.SameLine(ctx, 0.0, inner_spacing)
              ImGui.Text(ctx, formattedName) 
          end
          ImGui.EndChild(ctx)
        end

    end
    
    function menus.MouseAndKeyboard()
        local set = {}
        
        function set.MousewheelScrolling()
            reaper.ImGui_TextColored(ctx, colorGrey, "Horizontal scroll in modulators area")
            sliderInMenu("Scrolling speed", "scrollingSpeedOfHorizontalScroll", menuWidth, -100, 100, "Set how fast to scroll the horizontal scroll") 
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Scroll horizontal anywhere",settings.scrollModulatorsHorizontalAnywhere) 
            if ret then 
                settings.scrollModulatorsHorizontalAnywhere = val
                saveSettings()
            end
            setToolTipFunc("With this enabled you can scroll the modulators area horizontally anywhere on the app.\nWith this on you should disable Allow scrolling in the plugins area")   
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Vertical scroll in modulators area")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Use vertical scroll to scroll horizontal",settings.useVerticalScrollToScrollModulatorsHorizontally) 
            if ret then 
                settings.useVerticalScrollToScrollModulatorsHorizontally = val
                saveSettings()
            end
            setToolTipFunc("With this enabled you can scroll the modulators area horizontally with vertical mouse scroll")   
            
            if settings.useVerticalScrollToScrollModulatorsHorizontally then
                local ret, val = reaper.ImGui_Checkbox(ctx,"Only scroll on top or bottom (making a deadzone in the middle)",settings.onlyScrollVerticalHorizontalOnTopOrBottom) 
                if ret then 
                    settings.onlyScrollVerticalHorizontalOnTopOrBottom = val
                    saveSettings()
                end
                setToolTipFunc("This will only allow scrolling when on top or bottom of the modulators area")   
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Only scroll horizontal with modifier",settings.onlyScrollVerticalHorizontalScrollWithModifier) 
                if ret then 
                    settings.onlyScrollVerticalHorizontalScrollWithModifier = val
                    saveSettings()
                end
                setToolTipFunc("Will only scroll when holding down the selected modifier")   
                
                if settings.onlyScrollVerticalHorizontalScrollWithModifier then
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorText, "Modifiers to use:")
                    reaper.ImGui_SameLine(ctx)
                    modifiersSettingsModule("modifierEnablingScrollVerticalHorizontal")
                end
                
                
                sliderInMenu("Scrolling speed of vertical horizontal scroll", "scrollingSpeedOfVerticalHorizontalScroll", menuWidth, -100, 100, "Set how fast to scroll the horizontal vertical scroll") 
            end 
        end
        
        function set.ModifierSettings()
            if reaper.ImGui_BeginTable(ctx, "modifierTable", 2,  reaper.ImGui_TableFlags_SizingFixedFit() | reaper.ImGui_TableFlags_NoHostExtendX()) then
                local i = 0
                local modifiersOptionsAlphabetic = {}
                for name, _ in pairs(settings.modifierOptions) do
                    table.insert(modifiersOptionsAlphabetic, name)
                end
                table.sort(modifiersOptionsAlphabetic)
                for i, name in ipairs(modifiersOptionsAlphabetic) do
                    local value = settings.modifierOptions[name]
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorText, prettifyString(name))
                    reaper.ImGui_TableNextColumn(ctx) 
                    modifiersSettingsModule(name, "modifierOptions")
                    
                    if name == "fineAdjust" then
                        sliderInMenu("Fine adjust amount", "fineAdjustAmount", menuWidth, 2, 200, "Set how fine the fine adjust key should be. Higher is finer") 
                    end
                    
                    if name == "scrollValue" then
                        sliderInMenu("Scroll value speed", "scrollValueSpeed", menuWidth, 1, 100, "Set how much scrolling value, will change the value") 
                    end
                    
                    if i < #modifiersOptionsAlphabetic then
                        reaper.ImGui_TableNextRow(ctx)
                    end
                    
                end
                
                reaper.ImGui_NewLine(ctx)
                
                
                reaper.ImGui_EndTable(ctx)
                
            end
            
            if modifierStr ~= "" then
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "(Modifier pressed: " .. modifierStr .. ")")
            end
        end
        
        
        
        
        function set.KeyCommands()
            commandWithMostKeys = 0
            for index, info in ipairs(keyCommandSettings) do 
                if commandWithMostKeys < #info.commands then
                    commandWithMostKeys = #info.commands 
                end
            end
            
            
            
            
            if ImGui.BeginTable(ctx, 'keyCommandsTable', commandWithMostKeys+2, reaper.ImGui_TableFlags_NoHostExtendX() | reaper.ImGui_TableFlags_SizingFixedFit()) then
                for index = 1, #keyCommandSettings do
                    local info = keyCommandSettings[index]
                    local name = info.name
                    local commands = info.commands
                    ImGui.TableNextRow(ctx)
                    ImGui.TableSetColumnIndex(ctx, 0)
                    reaper.ImGui_TextColored(ctx,colorGrey, name .. ":")
                    for column = 1, commandWithMostKeys+1 do 
                        ImGui.TableSetColumnIndex(ctx, column)
                        command = commands[column]
                        if command then
                            if colorButton(command .. "##"..name..column,colorText,colorButtons,colorButtons,colorOrange,"Remove key command", colorOrange) then 
                                table.remove(commands,column)
                                reaper.SetExtState(stateName,"keyCommandSettings", json.encodeToJson(keyCommandSettings), true)
                            end
                        elseif column == #commands + 1 then
                            if addKey == name then
                                if isEscape then
                                    addKey = nil
                                    isAnyPopupOpen = true
                                else
                                    addKeyCommand(index)
                                end
                            else
                                if colorButton("add new##"..name,colorBlue,colorButtons,colorButtons,colorButtonsBorder,"Add key command") then
                                    addKey = name
                                end
                            end
                        end 
                    end
                end
                ImGui.EndTable(ctx)
            end
            if colorButton("Reset to default", colorOrange,colorButtons,colorButtons, colorButtonsHover) then
                keyCommandSettings = keyCommandSettingsDefault
                reaper.SetExtState(stateName,"keyCommandSettings", json.encodeToJson(keyCommandSettings), true)
            end
            
            reaper.ImGui_NewLine(ctx)
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Pass through all shortcuts",settings.passAllUnusedShortcutThrough) 
            if ret then 
                settings.passAllUnusedShortcutThrough = val
                saveSettings()
            end
            setToolTipFunc("This will pass through all shortcuts (that can be recognized by imgui) to reapers main section")  
            
            if not settings.passAllUnusedShortcutThrough then
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_TextColored(ctx, listenForPassthroughKeyCommands and colorMappingPulsating or colorTextDimmed, "Pass through shortcuts")
                
                if isEscapeKey then
                    listenForPassthroughKeyCommands = false
                end
                 
                if listenForPassthroughKeyCommands then
                    listeningForKeyCommand()
                end
                
                reaper.ImGui_SameLine(ctx)
                if colorButton((listenForPassthroughKeyCommands and "Listening" or "Listen") .. "##forpassthroughshortcuts", listenForPassthroughKeyCommands and colorMappingPulsating or colorMapping, colorButtons,colorButtons, colorButtonsBorder) then
                    listenForPassthroughKeyCommands = not listenForPassthroughKeyCommands 
                end
                
                --reaper.ImGui_SameLine(ctx)
                --if colorButton("Manuel lookup" .. "##forpassthroughshortcuts", colorText, colorButtons,colorButtons, colorButtonsBorder) then
                --    reaper.ImGui_OpenPopup(ctx, "Manuel Lookup")
                --end
                
                    
                local center_x, center_y = ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx))
                ImGui.SetNextWindowPos(ctx, center_x, center_y, ImGui.Cond_Appearing, 0.5, 0.5)
                
                --[[
                if ImGui.BeginPopupModal(ctx,  "Manuel Lookup", nil, ImGui.WindowFlags_AlwaysAutoResize) then
                  ImGui.Text(ctx, 'All those beautiful files will be deleted.\nThis operation cannot be undone!')
                  ImGui.Separator(ctx)
                  
                  local shortCutSearch = reaper.ImGui_InputText(ctx, "Write short cut as written in action window","")
                  --static int unused_i = 0;
                  --ImGui.Combo("Combo", &unused_i, "Delete\0Delete harder\0");
            
                  
                  if ImGui.Button(ctx, 'OK', 120, 0) then ImGui.CloseCurrentPopup(ctx) end
                  ImGui.SetItemDefaultFocus(ctx)
                  ImGui.SameLine(ctx)
                  if ImGui.Button(ctx, 'Cancel', 120, 0) or isEscapeKey then ImGui.CloseCurrentPopup(ctx) end
                  ImGui.EndPopup(ctx)
                end
                ]]
                
                
                local longestKeyW = 0
                for index, info in ipairs(passThroughKeyCommands) do 
                    local keyW = reaper.ImGui_CalcTextSize(ctx, info.key)
                    if longestKeyW < keyW + 16 then longestKeyW = keyW + 16 end
                end
                
                if ImGui.BeginTable(ctx, 'passThroughKeyCommands', 3, reaper.ImGui_TableFlags_NoHostExtendX() | reaper.ImGui_TableFlags_SizingFixedFit()) then
                    
                    for index, info in ipairs(passThroughKeyCommands) do 
                        local name = info.name
                        local key = info.key
                        
                        
                        ImGui.TableNextRow(ctx)
                        ImGui.TableSetColumnIndex(ctx, 0)
                        if colorButton(key .. "##passthrough"..name .. index,colorText,colorButtons,colorButtons,colorOrange,"Remove passthrough shortcut of " .. key, colorOrange, longestKeyW) then 
                            table.remove(passThroughKeyCommands,index)
                            reaper.SetExtState(stateName,"passThroughKeyCommands", json.encodeToJson(passThroughKeyCommands), true)
                        end  
                        
                        reaper.ImGui_AlignTextToFramePadding(ctx)
                        reaper.ImGui_TableNextColumn(ctx)
                        reaper.ImGui_TextColored(ctx,colorGrey, name)
                        
                    end
                    ImGui.EndTable(ctx)
                end
            end
            
            reaper.ImGui_NewLine(ctx)
            
            
        end
            
       --if reaper.ImGui_BeginChild(ctx, "keycommands",nil,nil,nil, reaper.ImGui_WindowFlags_HorizontalScrollbar()) then
        
        if reaper.ImGui_BeginTabBar(ctx, '##SettingsTabsKeyboard') then
            local groups =  {"Mousewheel Scrolling", "Modifier Settings", "Key Commands"}
            for i, g in ipairs(groups) do
                
                    if reaper.ImGui_BeginTabItem(ctx, g) then
                    
                    local setter =g:gsub(" ", "") 
                    set[setter]()
                
                    ImGui.EndTabItem(ctx) 
                end 
            end 
            ImGui.EndTabBar(ctx)
        end
            --reaper.ImGui_EndChild(ctx)
    end
    
    function menus.About()
        reaper.ImGui_TextColored(ctx, colorGrey, "Version " .. version) 
        reaper.ImGui_NewLine(ctx)
        local appreaciationText = ""
        appreaciationText  = appreaciationText  .. "Thanks to all the early adopters/testers for giving feedback, finding bugs and help shape the script.\n"
        appreaciationText  = appreaciationText  .. "Here I should mention especially:\n - "
        local users = {"Seventh Sam", "Vagelis", "Digitt", "93Nb", "deeb", "tonalstates", "Khron Studio", "AndreiMir", "MCJ"}
        appreaciationText  = appreaciationText  .. table.concat(users, "\n - ")
        
        appreaciationText  = appreaciationText  .. "\n"
        appreaciationText  = appreaciationText  .. "\n"
        appreaciationText  = appreaciationText  .. "This script took many month to complete. So many moving parts.\n"
        appreaciationText  = appreaciationText  .. "If you use it and like it, consider donating a bit for all the time spend.\n"
        --appreaciationText  = appreaciationText  .. "r\n"
        reaper.ImGui_TextColored(ctx, colorGrey, appreaciationText) 
        if reaper.ImGui_Button(ctx, "DONATE") then
            openWebpage("https://www.paypal.com/paypalme/saxmand")
        end
    end
    
    
    
    function menus.Developer()
        if reaper.ImGui_Button(ctx, "Reset track settings") then
            trackSettings = defaultTrackSettings
            saveTrackSettings(tracK)
        end
         
        if reaper.ImGui_Button(ctx, "Reset track settings on all tracks") then
            for i = 0, reaper.CountTracks(0) - 1 do
                local tr = reaper.GetTrack(0, i) 
                local trackSettingsStr = json.encodeToJson(defaultTrackSettings)
                reaper.GetSetMediaTrackInfo_String(tr, "P_EXT" .. ":" .. stateName, trackSettingsStr, true)
            end 
            trackSettings = defaultTrackSettings
            saveTrackSettings(tracK)
        end 
        
        if reaper.ImGui_Button(ctx, "Reset app settings") then
            settings = defaultSettings
            saveSettings()
        end
        
    end
    
    local menusOrder = {"Layout", "Mapping", "Mouse And Keyboard", "Colors", "About", "Developer"}
    if reaper.ImGui_BeginTabBar(ctx, '##SettingsTabs') then
        for i, g in ipairs(menusOrder) do 
            local name = g
            if name == "Mouse And Keyboard" then
                name = "Mouse & Keyboard"
            end
            if reaper.ImGui_BeginTabItem(ctx, name) then
                local setter = g:gsub(" ", "") 
                menus[setter]()
            
                reaper.ImGui_EndTabItem(ctx) 
            end 
        end 
        reaper.ImGui_EndTabBar(ctx)
    end
        
    reaper.ImGui_End(ctx)
    
    return open
end

    
local automationTypes = {"Trim/Read", "Read", "Touch", "Write", "Latch", "Latch Preview"}
local automationTypesShort = {"Te", "Re", "To", "Wr", "La", "Lp"}
local automationTypesDescription = {"Envelopes are active but faders are all for time", "Play faders with armed envelopes", "Record fader movements to armed envelopes", "Record fader movements after first movement", "Allow adjusting parameters but do not apply to envelopes", "Record fader positions to armed envelopes"}
local automationTypesColors = {colorsAutomationButton and colorTrimRead or colorAlmostWhite, colorRead, colorTouch, colorWrite, colorLatch, colorLatchPreview}

function automationButton(track)
    --centerText("Timebase", colorLightGrey, posXOffset, widthWithPadding, 0, posYOffset) 
    --posYOffset = posYOffset + 16 
    local automation = reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE')
    local automationString = automationTypes[automation+1]
    local color = automationTypesColors[automation+1]
    
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorBlack)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorText)
        
    
    if reaper.ImGui_Button(ctx, automationString .. "##" .. tostring(track), widthWithPadding) then
        --reaper.ImGui_OpenPopup(ctx, "timebasePopup")
        local newValue = automation + 1 < #automationStrings and automation + 1 or 0
        setTrackValuesLink("I_AUTOMODE", newValue, 0, true)
    end 
    
    reaper.ImGui_PopStyleColor(ctx, colorsAutomationButton and 5 or 1)
    
    if reaper.ImGui_IsItemHovered(ctx) and isMouseRightDown then
        reaper.ImGui_OpenPopup(ctx, "automation")
    end
    
    if reaper.ImGui_BeginPopup(ctx, 'automation') then 
        if track == selectedTracks[1] then 
            for i, name in ipairs(automationTypes) do 
                if reaper.ImGui_Button(ctx,name) then
                    reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", i - 1)
                end
            end
            shown = true
        end
        --setWindowsToTop = false
        reaper.ImGui_EndPopup(ctx)
    end 
end

function automationRadioSelect(track)
    local automation = reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE')
    for i, a in ipairs(automationTypes) do
        automationColor = automationTypesColors[i]
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), automationColor)
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), automationColor)
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), automationColor)
        if reaper.ImGui_RadioButton(ctx, a .. " (" .. automationTypesDescription[i]:lower() .. ")", i - 1 == automation) then 
            reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", i - 1)
        end
        setToolTipFunc()
        --reaper.ImGui_PopStyleColor(ctx, 3)
    end
end


function smallAutomationButton(track, id, size)
    
    local automation = reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE')
    local name = automationTypesShort[automation+1]
    local color = automationTypesColors[automation+1]
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorDarkGrey)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorDarkGrey)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorDarkGrey)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorText)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
        
    if reaper.ImGui_Button(ctx, name .. "##smallautomation" .. id .. tostring(track), size, size) then
        --reaper.ImGui_OpenPopup(ctx, "timebasePopup")
        local newValue = automation + 1 < #automationTypes and automation + 1 or 0
        reaper.SetMediaTrackInfo_Value(track, "I_AUTOMODE", newValue, 0, true)
    end 
    setToolTipFunc(automationTypesDescription[automation + 1])
    
    reaper.ImGui_PopStyleColor(ctx, 5)
    reaper.ImGui_PopStyleVar(ctx)
end

function addingAnyModuleWindow(hwnd) 
    local ret, x, y = reaper.JS_Window_GetClientRect(hwnd)
    local ret, w, h = reaper.JS_Window_GetClientSize(hwnd)
    local _, avTop, _, avBottom = reaper.JS_Window_GetViewportFromRect(0, 0, 0, 0, false)
    local avHeight = avTop
    if isApple then
        y = avHeight - y + 4
    else
        y = y + 4
    end    
    local topbar = 36
    y = y - topbar
    
    
    local text = "Adding FX to Modulator container - Click to stop"
    --reaper.ImGui_SetCursorPos(ctx, 0, h - 20)
    
    reaper.ImGui_PushFont(ctx, font1)
    local textW = reaper.ImGui_CalcTextSize(ctx, text, 0, 0)
    local windowW = textW  + 24
    --if isDocked then
        reaper.ImGui_SetNextWindowPos(ctx, x + w/2 - windowW / 2, y)
        reaper.ImGui_SetNextWindowSize(ctx, windowW, topbar)
    --else
    --    reaper.ImGui_SetNextWindowPos(ctx, x + w - windowW - 160, y + h - 4)
    --    reaper.ImGui_SetNextWindowSize(ctx, windowW, topbar)
    --end
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), isApple and colorTransparent or colorText)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), isApple and colorTransparent or colorMapping)
    local rv, open = reaper.ImGui_Begin(ctx, appName .. 'AddingAnyModule', true, reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoDecoration() | reaper.ImGui_WindowFlags_NoMove()) 
    if not rv then return open end
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 4)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorMapping)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorButtonsHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorButtonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorText)
    if reaper.ImGui_Button(ctx, text, textW+ 8) then
        open = false
    end
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleColor(ctx,5)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_End(ctx)
    
    reaper.ImGui_PopStyleColor(ctx,2)
    return open
end

function isFXWindowUnderMouse()
    local x, y = reaper.GetMousePosition()
    local hwnd = reaper.JS_Window_FromPoint(x, y)
  
    while hwnd ~= nil and reaper.JS_Window_IsWindow(hwnd) do
        local title = reaper.JS_Window_GetTitle(hwnd)
        if title and (title:match("FX:") ~= nil or title:match("VST") ~= nil or title:match("JS:") ~= nil or title:match("Clap:") ~= nil) then
        --if title and title:match(" - Track") ~= nil then
          return true, title, hwnd
        end
        hwnd = reaper.JS_Window_GetParent(hwnd)
    end
  
    return false, ""
end

    
function updateVisibleEnvelopes(track, p)
    if settings.showEnvelope and fxnumber and paramnumber then 
        if settings.hideEnvelopesWithNoPoints or settings.hideEnvelopesWithPoints then
             hideTrackEnvelopesUsingSettings(track, p.envelope)
        end
        
        if not p.envelope then 
            p.envelope = reaper.GetFXEnvelope(track, fxnumber, paramnumber, true) 
        else
            reaper.GetSetEnvelopeInfo_String(p.envelope, "VISIBLE", "1", true)
        end 
        
        if p.envelope then
            if settings.showClickedInMediaLane then 
                showAllEnvelopesInTheirLanesOrNot(track, p.envelope)
                reaper.GetSetEnvelopeInfo_String(p.envelope, "SHOWLANE", "0", true)
            else
                reaper.GetSetEnvelopeInfo_String(p.envelope, "SHOWLANE", "1", true)
            end
        end
        
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
    end
end

function updateMapping()
    local p = getAllDataFromParameter(track,fxIndexTouched,parameterTouched) 
    local canBeMapped = map and (not p.parameterLinkActive or (p.parameterLinkActive and mapName ~= p.parameterLinkName)) 
    
    if canBeMapped then
        local isLFO = mapName:match("LFO") ~= nil
        setParamaterToLastTouched(track, modulationContainerPos, map, fxnumber, paramnumber, reaper.TrackFX_GetParam(track,fxnumber, paramnumber), (isLFO and (settings.defaultBipolarLFO and -0.5 or 0) or (settings.defaultBipolar and -0.5 or 0)), (isLFO and settings.defaultMappingWidthLFO or settings.defaultMappingWidth) / 100)
        if settings.mapOnce then stopMappingOnRelease = true end
    end
    
    if scrollToParameter and (lastFxNumber ~= fxnumber or lastParamNumber ~= paramnumber) then
        scroll = paramnumber 
        scrollToParameter = false
    end
    
    lastFxNumber = fxnumber
    lastParamNumber = paramnumber
    --lastFxIndexTouched = nil
    --lastParameterTouched = nil
    --track = trackTouched
    if p then
        updateVisibleEnvelopes(track, p)
    end
end

local _, lastTrackIndexTouched, lastItemIndexTouched, lastTakeIndexTouched, lastFxIndexTouched, lastParameterTouched = reaper.GetTouchedOrFocusedFX( 0 ) 
local fxWindowClicked, clickedHwnd, parameterFound, parameterChanged, focusDelta, projectStateOnRelease, projectStateOnClick, timeClick, fxWindowClickedParameterNotFound
local lastParameterTouchedMouse, lastFxIndexTouchedMouse, lastTrackIndexTouchedMouse 
function updateTouchedFX()
    local parameterUpdated = false
    function setTouchedValues(trackidx, itemidx, takeidx, fxidx, param, trackTemp, deltaParam, val, lastValTouched)
        if settings.forceMapping then
            if deltaParam ~= param then 
                parameterFound = true 
                parameterUpdated = true
            end
        else
            -- lastval touched not working, so will try to think of something else. Some left over code still there
            if (lastParameterTouched ~= param or lastFxIndexTouched ~= fxidx or lastTrackIndexTouched ~= trackidx or (projectStateOnRelease and projectStateOnClick ~= projectStateOnRelease)) then --or (lastValTouched and lastValTouched ~= val) then 
                parameterFound = true 
                parameterUpdated = true 
                --if lastValTouched and lastValTouched ~= val then
                --    reaper.ShowConsoleMsg( lastValTouched .. "~=" .. val .. " lastval dif\n")
                --end
                --reaper.ShowConsoleMsg(tostring(lastParameterTouched) .."~=".. param .. " - ".. tostring(lastFxIndexTouched) .."~=".. fxidx .. " - ".. tostring(lastTrackIndexTouched) .."~=".. trackidx .. "\n")
            end
        end
        
        if parameterFound then 
            if settings.useFloatingMapper then
                showFloatingMapper = true
            end
            
            trackIndexTouched = trackidx
            fxIndexTouched = fxidx
            parameterTouched = param
            trackTouched = trackTemp
            
            fxnumber = fxIndexTouched
            paramnumber = parameterTouched 
            

            updateMapping()
            --scrollToParameter = true
            
            -- we always set these though they are only used when not in force mapping mode
            lastParameterTouched = parameterTouched
            lastFxIndexTouched = fxIndexTouched
            lastTrackIndexTouched = trackIndexTouched
            
            if lastParameterTouchedMouse ~= lastParameterTouched or lastFxIndexTouchedMouse ~= lastFxIndexTouched or lastTrackIndexTouchedMouse ~= lastTrackIndexTouched then
                mousePosOnTouchedParam = {x = mouse_pos_x, y = mouse_pos_y_correct}
                lastParameterTouchedMouse = lastParameterTouched
                lastFxIndexTouchedMouse = lastFxIndexTouched 
                lastTrackIndexTouchedMouse = lastTrackIndexTouched
            end
            hwndWindowOnTouchParam = clickedHwnd
            --hwndWindowOnTouchParam = reaper.JS_Window_GetFocus() 
        end
    end
    
    
    local retval, trackidx, itemidx, takeidx, fxidx, param = reaper.GetTouchedOrFocusedFX( 0 ) 
    
    if retval and trackidx then
        local trackTemp = reaper.GetTrack(0,trackidx)   
        --reaper.ShowConsoleMsg(val .. " - " .. tostring(dragKnob) .. "\n")
        if trackTemp then 
            local p = getAllDataFromParameter(trackTemp,fxidx,param) 
            
            local deltaParam = reaper.TrackFX_GetNumParams(trackTemp, fxidx) - 1  
            if isMouseDown then  
                if isMouseClick then 
                    fxWindowClicked, _, clickedHwnd = isFXWindowUnderMouse() 
                    -- trying to catch the clicked modulator when not using force, through project state change count
                    projectStateOnClick = reaper.GetProjectStateChangeCount(0)
                    projectStateOnRelease = nil
                    fxWindowClickedParameterNotFound = nil
                end
                if fxWindowClicked then 
                    focusDelta = false
                    if not parameterFound then 
                        setTouchedValues(trackidx, itemidx, takeidx, fxidx, param, trackTemp, deltaParam, val, lastValTouched)
                        lastValTouched = val
                    else 
                        -- changing parameter
                        if not settings.forceMapping or param ~= deltaParam then 
                            if p.parameterLinkActive or p.usesEnvelope then
                                
                                
                                if not parameterChanged then 
                                    if not dragKnob then 
                                        dragKnob = "baselineWindow"
                                        mouseDragStartX = mouse_pos_x
                                        mouseDragStartY = mouse_pos_y
                                    end
                                    
                                    parameterChanged = true
                                end  
                                
                                local range = p.max - p.min
                                if map then -- (isAdjustWidth and not map) or (not isAdjustWidth and map) then
                                    setParameterValuesViaMouse(trackTouched, "Window", "", p, range, p.min, p.currentValue, 100)
                                else
                                    setParameterFromFxWindowParameterSlide(track, p)
                                end
                                
                            end
                        end
                    end
                end
            else  
                if momentarilyDisabledParameterLink then
                    reaper.TrackFX_SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.active', "1")
                    momentarilyDisabledParameterLink = false
                end
                -- we keep checking that delta is set, so we are ready for next click
                -- set a timer to only look for updated project state count for less than the a sec
                if not timeReleaseStart then 
                    timeReleaseStart = reaper.time_precise()
                end
                -- check for the release project state for x seconds
                if fxWindowClickedParameterNotFound and timeReleaseStart and (reaper.time_precise() - timeReleaseStart < 0.6) then
                    projectStateOnRelease = reaper.GetProjectStateChangeCount(0)
                else
                    -- after x seconds we stop looking
                    fxWindowClickedParameterNotFound = nil
                    timeReleaseStart = nil 
                end
                -- if we are looking and the project state is higher than the click we found the value again
                if fxWindowClickedParameterNotFound and projectStateOnClick < projectStateOnRelease then
                    setTouchedValues(trackidx, itemidx, takeidx, fxidx, param, trackTemp, deltaParam)
                    -- we update the project state on click to not repeat this
                    projectStateOnClick = projectStateOnRelease
                    -- we remove the looking tag
                    fxWindowClickedParameterNotFound = nil
                end
                 
                
                -- if we have not found the parameter (like clicking Rea plugins) we find it on release
                if fxWindowClicked and (not parameterFound and (not settings.forceMapping) or (settings.forceMapping and not focusDelta)) then  
                    setTouchedValues(trackidx, itemidx, takeidx, fxidx, param, trackTemp, deltaParam)
                    -- if we still didn't find the parameter then we will look through the release timer
                    if not parameterFound then
                        fxWindowClickedParameterNotFound = true
                    end
                end 
                
                -- only used for force mapping
                if settings.forceMapping and param ~= deltaParam then    
                    -- sets the Delta value to it's current value, to clear the last touched or focused fx
                    local deltaVal = reaper.TrackFX_GetParam(trackTemp, fxidx, deltaParam)
                    reaper.TrackFX_SetParam(trackTemp, fxidx, deltaParam, deltaVal) 
                    -- we store that we have focused delta, so we do not find parameter twice on release above
                    focusDelta = true
                end
                
                -- we remove the variables for next click
                parameterChanged = nil
                parameterFound = nil
                fxWindowClicked = nil
                dragKnob = nil
                lastValTouched = nil
                clickedHwnd = nil
                --hwndWindowOnTouchParam = nil
            end
        end
    end
    
    return parameterUpdated
end

    
    
function getTrackColor(track)
    local color  = reaper.GetTrackColor(track)
     -- shift 0x00RRGGBB to 0xRRGGBB00 then add 0xFF for 100% opacity
    return color & 0x1000000 ~= 0 and (reaper.ImGui_ColorConvertNative(color) << 8) | 0xFF or colorTransparent 
end

function buttonSelect(ctx, name, toolTip, isShowing, width,  borderSize, colorBorder, colorButton, colorHover, colorActive, colorSelected)
    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 6)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), borderSize)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorBorder)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), isShowing and colorSelected or colorButton)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorActive)
    
    --reaper.ImGui_SetCursorPosX(ctx, curPosX - 2)
    local click = false
    if reaper.ImGui_Button(ctx, name, width) then
        click = true
    end
    setToolTipFunc(toolTip)
    reaper.ImGui_PopStyleColor(ctx,4)
    reaper.ImGui_PopStyleVar(ctx, 1)
    return click
end 

-- before looping script we ensure we have the correct loaded color set 
local allColorSets, selectedColorSetIndex =  getColorSetsAndSelectedIndex() 
setColorSet(selectedColorSetIndex, allColorSets)

function compareTwoTables(tb1, tb2)
   -- reaper.ShowConsoleMsg(#tb1 .. " - " .. #tb2 .. "\n")
    local same = true
    local noTable = true
    for key, val in pairs(tb1) do
        if val then
            noTable = false
            if not tb2[key] then
                same = false
            end
        end
    end 
    for key, val in pairs(tb2) do
        if val then  
            noTable = false
            if not tb1[key] then
                same = false
            end
        end
    end
    
    if noTable then return false else return same end
end

function mergeTables(tb1, tb2)
    local temp = {}
    for k, v in pairs(tb1) do
        if v then
            temp[k] = v
        end
    end
    for k, v in pairs(tb2) do
      if v then
          temp[k] = v
      end
    end
    return temp
end

    
_, screenHeight, screenWidth = reaper.JS_Window_GetViewportFromRect( 0, 0, 1, 1, false)
local fx_before, fx_after, firstBrowserHwnd
local dock_id, is_docked
local runs = -1
local function loop() 
    playPos = reaper.GetPlayPosition() 
    runs = runs + 1
    popupAlreadyOpen = false
    
    minWidth = settings.mappingWidthOnlyPositive and 0 or -1
    
    state                    = reaper.JS_Mouse_GetState(-1)
    isShiftPressed           = (state & 0x08) ~= 0
    isSuperPressed           = (state & (isWin and 0x20 or 0x04)) ~= 0
    isAltPressed             = (state & 0x10) ~= 0
    isCtrlPressed            = (state & (isWin and 0x04 or 0x20)) ~= 0
    isMouseDown              = (state & 0x01) ~= 0
    isMouseReleased          = (state & 0x01) == 0
    isMouseRightDown         = (state & 0x02) ~= 0
    
    isEscapeKey = reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false)
    
    
    isMouseClick = isMouseDown and not isMouseDownStart
    if isMouseDown then isMouseDownStart = true end
    if isMouseReleased then  
        isMouseWasReleased = false
        if isMouseDownStart then  
            isMouseWasReleased = true 
        end
        isMouseDownStart = false
    end
    
    isAnyMouseDown = isMouseDown or isMouseRightDown
    
    modifierTable = {}
    modifierStr = ""
    if isSuperPressed then modifierTable.Super = true; modifierStr = modifierStr .. "Super+" end
    if isCtrlPressed then modifierTable.Ctrl = true; modifierStr = modifierStr .. "Ctrl+" end
    if isShiftPressed then modifierTable.Shift = true; modifierStr = modifierStr .. "Shift+" end
    if isAltPressed then modifierTable.Alt = true; modifierStr = modifierStr .. "Alt+" end
    modifierStr = modifierStr:sub(0,-2)
    
    -- SET ALL MODIFIER OPTIONS
    isScrollValue = compareTwoTables(modifierTable, settings.modifierOptions.scrollValue) 
    isFineAdjust = compareTwoTables(modifierTable, settings.modifierOptions.fineAdjust)
    isAdjustWidth = compareTwoTables(modifierTable, settings.modifierOptions.adjustWidth)
    isChangeBipolar = compareTwoTables(modifierTable, settings.modifierOptions.changeBipolar)
    
    scrollFine = mergeTables(settings.modifierOptions.scrollValue, settings.modifierOptions.fineAdjust)
    if compareTwoTables(modifierTable, scrollFine) then
        isScrollValue = true
        isFineAdjust = true
    end 
    
    scrollWidth = mergeTables(settings.modifierOptions.scrollValue, settings.modifierOptions.adjustWidth)
    if compareTwoTables(modifierTable, scrollWidth) then
        isScrollValue = true
        isAdjustWidth = true
    end 
    
    fineWidth = mergeTables(settings.modifierOptions.fineAdjust, settings.modifierOptions.adjustWidth)
    if compareTwoTables(modifierTable, fineWidth) then
        isFineAdjust = true
        isAdjustWidth = true
    end
     
    scrollFineWidth = mergeTables(scrollFine, settings.modifierOptions.adjustWidth)
    if compareTwoTables(modifierTable, scrollFineWidth) then
        isScrollValue = true
        isFineAdjust = true
        isAdjustWidth = true
    end
    
    
    
    anyModifierIsPressed = isAltPressed or isCtrlPressed or isShiftPressed or isSuperPressed
    --isAltPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
    --isCtrlPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
    --isShiftPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
    --isSuperPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
    isMouseDownImgui = reaper.ImGui_IsMouseDown(ctx,reaper.ImGui_MouseButton_Left())
    isMouseDownRightImgui = reaper.ImGui_IsMouseDown(ctx,reaper.ImGui_MouseButton_Right())
    isMouseReleasedImgui = reaper.ImGui_IsMouseReleased(ctx,reaper.ImGui_MouseButton_Left())
    --isMouseReleased = reaper.JS_Mouse_GetState(1)
    isMouseDragging = reaper.ImGui_IsMouseDragging(ctx,reaper.ImGui_MouseButton_Left()) 
    click_pos_x, click_pos_y = ImGui.GetMouseClickedPos(ctx, 0) 
    
    --[[if not ignoreImguiMousePos then
        mouse_pos_x, mouse_pos_y = reaper.ImGui_GetMousePos(ctx)
    end
    if mouse_pos_x < -1000000 then 
        if isMouseDown and not ignoreImguiMousePos then 
            ignoreImguiMousePos = true
        end
        mouse_pos_x, mouse_pos_y = reaper.GetMousePosition()
    end]]
    
    mouse_pos_x_imgui, mouse_pos_y_imgui = reaper.ImGui_GetMousePos(ctx)
    
    mouse_pos_x, mouse_pos_y = reaper.GetMousePosition()
    
    mouse_pos_y_correct = mouse_pos_y
    if isApple then
        --local _, screenHeight = reaper.JS_Window_ScreenToClient()  -- Gets main screen size (not always perfect for multi-monitor setups)
       mouse_pos_y_correct = screenHeight - mouse_pos_y_correct
    end
    
    if isMouseReleased then
        ignoreImguiMousePos = false
    end
    
    scrollVertical, scrollHorizontal = reaper.ImGui_GetMouseWheel(ctx)
    
    local scrollFlags = isScrollValue and reaper.ImGui_WindowFlags_NoScrollWithMouse() or reaper.ImGui_WindowFlags_None()
    
    
    
    
    
  
    
    -- remove lock if we change project
    currentProject = reaper.EnumProjects(-1)
    if not lastCurrentProject or lastCurrentProject ~= currentProject then
        lastCurrentProject = currentProject
        --track = nil
        locked = false
    end
        
    
    firstSelectedTrack = reaper.GetSelectedTrack(0,0)
    if not track or (firstSelectedTrack ~= track and not locked) then 
        track = firstSelectedTrack 
        
        mapModulatorActivate(nil)
    end
    
    
    
    
    if updateTouchedFX() then
        if settings.focusFollowsFxClicks and trackTouched and track ~= trackTouched and validateTrack(trackTouched) then
            if settings.trackSelectionFollowFocus then
                reaper.SetOnlyTrackSelected(trackTouched)
            end
            track = trackTouched
        end
    end
     
    
    
    
    -- stop mapping
    if stopMappingOnRelease and isMouseReleased then map = false; sliderNumber = false; stopMappingOnRelease = nil end
    
    
    --if not track then track = reaper.GetTrack(0,0) end
    if track then
        _, trackName = reaper.GetTrackName(track)
        trackId = reaper.GetTrackGUID(track) 
        
        if not lastTrack or lastTrack ~= track then  
            -- store the current focused plugin for when changing tracks
            if trackSettings then
                trackSettings.fxnumber = fxnumber
                trackSettings.paramnumber = paramnumber
                -- TODO: check if project is still open
                saveTrackSettings(lastTrack)
            end
            
            loadTrackSettings(track)
            
            
            
            -- load last focused fx if possible 
            fxnumber = trackSettings.fxnumber ~= modulationContainerPos and trackSettings.fxnumber or nil
            paramnumber = trackSettings.fxnumber ~= modulationContainerPos and trackSettings.paramnumber or nil 
            
            _, trackName = reaper.GetTrackName(track)
            --lastTrack = track
        end
        
        
        --if not fxnumber then fxnumber = 0 end
        --if not paramnumber then paramnumber = 0 end
        --if not lastCollabsModules then lastCollabsModules = {} end 
    else
        --trackName = "Select a track or touch a plugin parameter"
        trackName = "No track selected"
        trackSettings = {}
        lastTrack = nil
    end
    
    
    if track then 
        modulationContainerPos = getModulationContainerPos(track)
        
        focusedTrackFXNames, parameterLinks = getAllTrackFXOnTrack(track)
        
        if modulationContainerPos then
            modulatorNames, modulatorFxIndexes = getModulatorNames(track, modulationContainerPos, parameterLinks)
        end
        
        automation = reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE')
        isAutomationRead = automation < 2
        
        if fxnumber and modulationContainerPos ~= fxnumber and not modulatorFxIndexes[fxnumber] then
            --focusedTrackFXParametersData = getAllParametersFromTrackFx(track, fxnumber) 
        else
            for i, f in ipairs(focusedTrackFXNames) do
                if not f.isModulator then
                    fxnumber = f.fxIndex
                end
            end
        end 
    else 
        fxnumber = nil
        focusedTrackFXNames = {}
        parameterLinks = {}
        focusedTrackFXParametersData = {}
        modulatorNames = {}
        modulatorFxIndexes = {}
        modulationContainerPos = nil
        buttonHovering = {} 
    end
    
    
    
    
    if last_vertical ~= settings.vertical then 
        if not dock_id and settings.dock_id then
            reaper.ImGui_SetNextWindowDockID(ctx, settings.dock_id, nil) 
            last_dock_id = settings.dock_id
        end
        
        local ww = settings.vertical and settings.wwVertical or settings.wwHorizontal
        local wh = settings.vertical and settings.whVertical or settings.whHorizontal 
        local x = settings.vertical and settings.xVertical or settings.xHorizontal 
        local y = settings.vertical and settings.yVertical or settings.yHorizontal 
        
        if (dock_id and (dock_id == 1 or dock_id == 0)) or (not dock_id and (settings.dock_id == 1 or settings.dock_id == 0)) then 
            reaper.ImGui_SetNextWindowSize(ctx,ww ,wh ,nil)
            reaper.ImGui_SetNextWindowPos(ctx,x ,y ,nil)
        end
        
        if dock_id and dock_id ~= 1 and dock_id ~= 0 then
            settings.dockIdVertical["id" .. tostring(dock_id)] = settings.vertical and "1" or "0"
            saveSettings()
        end
        
        last_vertical = settings.vertical 
        resetWindowSize = true
    end
    --trackGuid = reaper.GetTrackGUID(track)
    
    if resetWindowSize then
        --winW, winH = reaper.ImGui_GetWindowSize(ctx)
        --if winW > 1000
        --resetWindowSize = false
    end
    
    
    
    if setWindowWidth and settings.vertical and not reaper.ImGui_IsWindowDocked(ctx) then
        --reaper.ImGui_SetNextWindowSize(ctx,settings.partsWidth+margin*4, 0,nil)
        --setWindowWidth = nil
    end
    
    
    reaper.ImGui_PushFont(ctx, font)
    --[[
    partsWidth = settings.partsWidth
    if partsWidth >= 180 then
        reaper.ImGui_PushFont(ctx, font)
    elseif partsWidth < 180 and partsWidth >= 160 then
        reaper.ImGui_PushFont(ctx, font13)
    elseif partsWidth < 160 and partsWidth >= 140 then
        reaper.ImGui_PushFont(ctx, font12)
    end
    ]]
    
    colorMapping = settings.colors.mapping
    colorMappingLight = colorMapping & 0xFFFFFFFF55
    colorMappingPulsating = colorMapping
    if settings.pulsateMappingButton then 
        local time = reaper.time_precise() * settings.pulsateMappingColorSpeed
        local pulsate = (math.sin(time * 2) + 1) / 2  -- range: 0 to 1
        local alpha = math.floor(0x55 + (0xFF - 0x55) * pulsate)
        colorMappingPulsating = colorMapping & (0xFFFFFF00 + alpha) -- combine alpha and RGB
    end
    
    colorSelectOverlay = settings.colors.selectOverlay
    
    colorButtons = settings.colors.buttons
    colorButtonsActive = settings.colors.buttonsActive
    colorButtonsHover = settings.colors.buttonsHover
    colorButtonsBorder = settings.colors.buttonsBorder
    colorText = settings.colors.text
    colorTextDimmed = settings.colors.textDimmed
    colorTextDimmedLight = colorTextDimmed & 0xFFFFFFFF55
    colorSliderBaseline = settings.colors.sliderBaseline
    colorSliderOutput = settings.colors.sliderOutput
    colorSliderWidth = settings.colors.sliderWidth
    colorSliderWidthNegative = settings.colors.sliderWidthNegative
    colorMenuBar = settings.colors.menuBar
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), settings.colors.appBackground)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), settings.colors.menuBar)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), settings.colors.menuBar)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), settings.colors.menuBar)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), settings.colors.buttons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), settings.colors.buttonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), settings.colors.buttonsHover)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.appBackground)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), settings.colors.modulesBackground)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorText)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorButtonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorButtonsHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), colorTextDimmed)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), colorMenuBar)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), colorButtonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), colorButtonsHover)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), settings.colors.boxBackground)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), settings.colors.boxBackgroundActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), settings.colors.boxBackgroundHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), settings.colors.boxTick)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), colorTextDimmed)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), colorButtonsActive)
    
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), colorButtonsHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), colorButtonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), colorButtons)
    
    local colorsPush = 27
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8) 
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 5.0)
    local varPush = 3
    
    
    --- COLOR STUFF
    local automationColor
    local fillEnvelopeButton
    if track and settings.useAutomationColorOnEnvelopeButton then
        local automation = reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE') 
        automationTypesColors = {colorText, colorRead, colorTouch, colorWrite, colorLatch, colorLatchPreview}
        automationColor = automationTypesColors[automation+1]
        fillEnvelopeButton = settings.colors.envelopeButtonBackground
    end
    --------
    
    local mainFlags = reaper.ImGui_WindowFlags_TopMost()
    if not settings.allowCollapsingMainWindow then
        mainFlags = mainFlags | reaper.ImGui_WindowFlags_NoCollapse()
    end
    
    local visible, open = reaper.ImGui_Begin(ctx, appName,true, 
     mainFlags |
    --reaper.ImGui_WindowFlags_MenuBar() |
    --reaper.ImGui_WindowFlags_HorizontalScrollbar() |
    scrollFlags
    )
    if visible then
        
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), settings.colors.modulesBackground)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.modulesBackground)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.modulesBackground)
        
        local colorsPush2 = 2
        
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        local winX, winY = reaper.ImGui_GetWindowPos(ctx) 
        is_docked = reaper.ImGui_IsWindowDocked(ctx)
        
        mouseInsideAppWindow = mouse_pos_x_imgui >= winX and mouse_pos_x_imgui <= winX + winW and mouse_pos_y_imgui >= winY and mouse_pos_y_imgui <= winY + winH
        --[[clickingApp = false
        if  then 
            if isAnyMouseDown  then
                clickingApp = true
            end
        end]]
        
        
        local childFlags = reaper.ImGui_ChildFlags_Border()
        
        if settings.vertical then
            partsWidth = winW - margin * 4
            childFlags = childFlags | reaper.ImGui_ChildFlags_AutoResizeY()
        else
            partsWidth = settings.partsWidth
        end
        
        
        moduleWidth = partsWidth - 16
        
    
        if not last_dock_id or last_dock_id ~= dock_id then
          if settings.dockIdVertical["id" .. tostring(dock_id)] then
              settings.vertical = tostring(settings.dockIdVertical["id" .. tostring(dock_id)]) == "1"
          end 
          settings.dock_id = dock_id 
          
          saveSettings()
          last_dock_id = dock_id  
        end
        
        dock_id = reaper.ImGui_GetWindowDockID(ctx)
        
        
        if not reaper.ImGui_IsWindowDocked(ctx) and 
            (settings.vertical and (settings.wwVertical ~= winW or settings.whVertical ~= winH or settings.xVertical ~= winX or settings.yVertical ~= winY))
          or 
            (not settings.vertical and (settings.wwHorizontal ~= winW or settings.whHorizontal ~= winH or settings.xHorizontal ~= winX or settings.yHorizontal ~= winY))
        then
            if settings.vertical then
                settings.wwVertical = winW
                settings.whVertical = winH
                settings.xVertical = winX
                settings.yVertical = winY
            else
                settings.wwHorizontal = winW
                settings.whHorizontal = winH
                settings.xHorizontal = winX
                settings.yHorizontal = winY 
            end
            saveSettings()
        end
        
        
          
          
          
          
          
        if not lastTouchedParam or lastTouchedParam ~= paramnumber or focusedFxNumber ~= fxnumber then
            --lastSelected = focusedTrackFXParametersData[paramnumber+1]
            if not lastTouchedParam or lastTouchedParam ~= paramnumber then 
                focusedParamNumber = tonumber(paramnumber)
                lastTouchedParam = paramnumber 
            end
            if not focusedFxNumber or focusedFxNumber ~= fxnumber then
                if firstRunDone then
                    --if settings.openSelectedFx and focusedFxNumber then 
                        --[[local floating = reaper.TrackFX_GetFloatingWindow( track, fileInfo.fxIndex ) ~= nil
                        local floatingContainer = focusedMapping and fileInfo.fxContainerIndex and reaper.TrackFX_GetFloatingWindow( track, fileInfo.fxContainerIndex ) ~= nil
                        local isInTheRoot = not fileInfo.fxContainerIndex
                        local topContainerFxIndex = focusedMapping and fileInfo.fxContainerIndex and findParentContainer(fileInfo.fxContainerIndex) or fileInfo.fxIndex
                        local fxWindowOpen = focusedMapping and topContainerFxIndex and reaper.TrackFX_GetOpen( track, topContainerFxIndex )
                        if not fileInfo.fxContainerIndex and floatingSampler then fxWindowOpen = false end
                        ]]
                        --openCloseFx(track, fxnumber, true) 
                    --end
                    
                    --focusedFxNumber = fxnumber
                    firstRunDone = false
                end
                firstRunDone = true
            end
        end
        
      
      
        draw_list = reaper.ImGui_GetWindowDrawList(ctx)
        local windowPosX, windowPosY = reaper.ImGui_GetWindowPos(ctx)
        
        
        
        --fxIndex = 3
        
        --oneData = getAllParametersFromTrackFx(track, fxIndex)
        
        --if not lastSelected then lastSelected = focusedTrackFXParametersData[1] end
        
        
        local title = trackName 
        local everythingsIsNotMinimized = ((allIsNotCollabsed == nil or allIsNotCollabsed) and not trackSettings.hidePlugins and not trackSettings.hideParameters and not trackSettings.hideModules)
        
        
        ImGui.BeginGroup(ctx)
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        local modulatorsW = settings.vertical and partsWidth or (winW-x-30)
        local pansHeight = winH-y-8
        --reaper.ImGui_SameLine(ctx)
        
        local trackColor = colorTransparent
        if track and settings.trackColorAroundLock then  
            trackColor = getTrackColor(track)
        end
        
        
        
        
        function clickFloatingMapperButton()
            if reaper.ImGui_IsItemClicked(ctx, 1) then 
                reaper.ImGui_OpenPopup(ctx, "floatingMapperButton") 
            elseif reaper.ImGui_IsItemClicked(ctx) then  
                settings.useFloatingMapper = not settings.useFloatingMapper 
                saveSettings()
            end 
            
            if reaper.ImGui_BeginPopup(ctx, "floatingMapperButton") then 
                floatingMapperSettings() 
                reaper.ImGui_EndPopup(ctx)
            end
            
        end
        
        function clickEnvelopeSettings()
            if reaper.ImGui_IsItemClicked(ctx, 1) then 
                reaper.ImGui_OpenPopup(ctx, "envelopeSettings") 
            elseif reaper.ImGui_IsItemClicked(ctx) then  
                settings.showEnvelope = not settings.showEnvelope
                saveSettings()
            end 
            
            if reaper.ImGui_BeginPopup(ctx, "envelopeSettings") then 
                envelopeSettings() 
                reaper.ImGui_EndPopup(ctx)
            end
            
        end
        
        local widthOfTrackName = settings.vertical and partsWidth - 24 * 4 or pansHeight - 24 *5 - 8
        if not settings.vertical then
            if specialButtons.lock(ctx, "lock", 24, locked, (locked and "Unlock from track" or "Lock to selected track"), colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, trackColor, settings.vertical) then
                locked = not locked and track or false 
                --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
            end
            
            local offset = 22
            reaper.ImGui_SetCursorPos(ctx, x, y + offset)
            
            specialButtons.floatingMapper(ctx, "floatingMapper", 24, settings.useFloatingMapper, (settings.useFloatingMapper and "Disable" or "Enable") .. " floating mapper\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, settings.vertical)
            clickFloatingMapperButton()
            offset = offset + 24
            
            reaper.ImGui_SetCursorPos(ctx, x, y + offset)
            specialButtons.envelopeSettings(ctx, "envelopeSettings", 24, settings.showEnvelope, (settings.showEnvelope and "Disable" or "Enable") .. " showing envelope on parameter click\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, settings.vertical, automationColor, automationColor, fillEnvelopeButton)
            clickEnvelopeSettings()
            offset = offset + 24 + 8
            
            reaper.ImGui_SetCursorPos(ctx, x, y + offset)
            if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything", widthOfTrackName, true,false,nil,true,24 ) then 
                hideShowEverything(track, everythingsIsNotMinimized)
            end
            
            reaper.ImGui_SetCursorPos(ctx, x, y + pansHeight - 20 -24)
            if specialButtons.cogwheel(ctx, "settings", 24, settingsOpen, "Show app settings", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground) then
                settingsOpen = not settingsOpen
            end
        end
        
        
        
        if settings.vertical then
            if specialButtons.cogwheel(ctx, "settings", 24, settingsOpen, "Show app settings", colorText, colorTextDimmed,colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground) then
                settingsOpen = not settingsOpen
            end 
            local offset = 24
            reaper.ImGui_SameLine(ctx, offset) 
            
            if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything", widthOfTrackName, true,false,nil,true,24 ) then 
                hideShowEverything(track, everythingsIsNotMinimized)
            end
            
            offset = widthOfTrackName + offset
            reaper.ImGui_SameLine(ctx, offset) 
            
            
            
            specialButtons.envelopeSettings(ctx, "envelopeSettings", 24, settings.showEnvelope, (settings.showEnvelope and "Disable" or "Enable") .. " floating mapper\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, settings.vertical, automationColor, automationColor, fillEnvelopeButton)
            clickEnvelopeSettings()
            offset = offset + 24
            reaper.ImGui_SameLine(ctx, offset) 
            
            specialButtons.floatingMapper(ctx, "floatingMapper", 24, settings.useFloatingMapper, (settings.showEnvelope and "Disable" or "Enable") .. " showing envelope on parameter click\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, settings.vertical)
            clickFloatingMapperButton()
            
            offset = offset + 24
            reaper.ImGui_SameLine(ctx, offset) 
            if specialButtons.lock(ctx, "lock", 24, locked, "Lock to selected track", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, trackColor, settings.vertical) then
                locked = not locked and track or false 
                --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
            end
        end
        
        
        
        
        --reaper.ImGui_SetCursorPos(ctx, x +20, y + 20)
        reaper.ImGui_EndGroup(ctx)
        
        
        
        
        placingOfNextElement()
        
        if not track then
            reaper.ImGui_BeginDisabled(ctx)
        end
        
        
        
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        modulatorsW = settings.vertical and partsWidth or (winW-x-30)
        pansHeight = winH-y-28
        
        local height = settings.vertical and (isCollabsed and 22 or settings.modulesHeightVertically) or pansHeight
        local tableWidth = partsWidth
        
        if settings.showPluginsPanel then
        
            ImGui.BeginGroup(ctx)
            
            local title = "PLUGINS"
            click = false
        
        
            ImGui.BeginGroup(ctx)
            if trackSettings.hidePlugins then
                if modulePartButton(title .. "", not trackSettings.hidePlugins and "Minimize plugins" or "Maximize plugins", settings.vertical and partsWidth or nil, true,true ) then 
                    click = true
                end        
            else 
                reaper.ImGui_SetNextWindowSizeConstraints(ctx, 40, 60, tableWidth, height)
                if reaper.ImGui_BeginChild(ctx, 'PluginsChilds', nil, nil, childFlags, reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_NoScrollbar()) then -- | scrollFlags)
                
                --if visible then
                    if reaper.ImGui_BeginMenuBar(ctx) then 
                         if titleButtonStyle(title, not trackSettings.hidePlugins and "Minimize plugins" or "Maximize plugins",settings.vertical and partsWidth or nil, true, false ) then 
                             click = true
                         end
                        reaper.ImGui_EndMenuBar(ctx)
                    end
                    
                    function openAllAddTrackFX() 
                        if settings.showOpenAll == true or settings.showAddTrackFX then
                            local allIsClosed = true
                            for _, f in ipairs(focusedTrackFXNames) do 
                                if not f.isModulator and f.isOpen then
                                    allIsClosed = false
                                    break
                                end
                            end
                            
                            if settings.showPluginOptionsOnTop == false then 
                                reaper.ImGui_Separator(ctx)
                            end
                            
                            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorDarkGrey)
                            
                            if settings.showOpenAll then
                                local textState = (not allIsClosed and "Close " or "Open ")
                                if reaper.ImGui_Button(ctx, textState .. ' all##FXOpenall', tableWidth / 2 - 8) then 
                                    for _, f in ipairs(focusedTrackFXNames) do 
                                        if not f.isModulator then
                                            openCloseFx(track, tonumber(f.fxIndex), allIsClosed)
                                        end
                                    end
                                end  
                                setToolTipFunc(textState .. "all FX windows")
                            end
                            
                            if settings.showAddTrackFX then
                                if settings.showOpenAll then
                                    reaper.ImGui_SameLine(ctx)
                                end
                                
                                if reaper.ImGui_Button(ctx, "Add FX##add", tableWidth / 2 - 16) then  
                                    openFxBrowserOnSpecificTrack() 
                                end
                                setToolTipFunc("Add new FX to track")
                            end
                            
                            
                            --reaper.ImGui_PopStyleColor(ctx)
                            
                            if settings.showPluginOptionsOnTop then 
                                reaper.ImGui_Separator(ctx)
                            end
                        end
                    end
                    
                    if settings.showPluginOptionsOnTop then
                        openAllAddTrackFX()
                    end
                    
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), colorAlmostBlack)
                    
                    local pluginFlags = reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_NoPadOuterX()
                    if settings.allowHorizontalScroll then
                        pluginFlags = pluginFlags | reaper.ImGui_TableFlags_ScrollX()
                    end
                    
                    local offset = settings.showOpenAll or settings.showAddTrackFX
                    if reaper.ImGui_BeginTable(ctx, 'PluginsTable',2,pluginFlags, 0, 0) then -- (offset and (height -  64) or 0)) then
                        
                        --ImGui.TableHeadersRow(ctx)
                        
                        ImGui.TableSetupColumn(ctx, 'one', reaper.ImGui_TableColumnFlags_WidthFixed(), 16)--settings.partsWidth-60) -- Default to 100.0
                        --ImGui.TableSetupColumn(ctx, 'two', ImGui.TableColumnFlags_WidthFixed, 20.0) -- Default to 200.0
                        reaper.ImGui_TableSetupScrollFreeze(ctx, 1,0)
                        
                        reaper.ImGui_TableNextColumn(ctx)
                        local count = 0
                        for i, f in ipairs(focusedTrackFXNames) do 
                            --if (settings.includeModulators) or (not settings.includeModulators and (not f.isModulator)) then
                            if not f.isModulator and (settings.showContainers or (not settings.showContainers and not f.isContainer)) then
                                count  = count  + 1
                                local name = f.name
                                if settings.hidePluginTypeName then
                                    name = name:gsub("^[^:]+: ", "")
                                end
                                if f.isContainer then name = name .. ":" end
                                local indentStr = string.rep(" ", settings.indentsAmount)
                                if f.indent then name = string.rep(indentStr, f.indent) .. name end
                                
                                local isFocused = tonumber(fxnumber) == tonumber(f.fxIndex)
                                if isFocused then
                                    --name = "> " .. name
                                end
                                
                                reaper.ImGui_TableNextRow(ctx)
                                 
                                
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), f.isFloating and settings.colors.pluginOpen or settings.colors.pluginOpenInContainer)
                                reaper.ImGui_TableNextColumn(ctx)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), isFocused and colorText or colorTextDimmed)
                                if reaper.ImGui_Selectable(ctx, (isFocused and ">" or count) .. '##' .. f.fxIndex, f.isOpen ,nil) then 
                                    
                                    openCloseFx(track, f.fxIndex, not f.isOpen)
                                end  
                                setToolTipFunc((not f.isOpen and "Open " or "Close ") .. f.name .. " window")
                                reaper.ImGui_PopStyleColor(ctx)
                                
                                reaper.ImGui_PopStyleColor(ctx, 1)
                                reaper.ImGui_TableNextColumn(ctx)
                                
                                --if reaper.ImGui_Checkbox(ctx, "##FXOpen" ..i, f.isOpen) then 
                                --    openCloseFx(track, f.fxIndex, not f.isOpen)
                                --end
                                
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), (settings.colorContainers and f.isContainer) and colorTextDimmed or colorText)
                                if reaper.ImGui_Selectable(ctx, name .. '##' .. f.fxIndex, isFocused ,reaper.ImGui_SelectableFlags_AllowDoubleClick()) then 
                                   fxnumber = f.fxIndex
                                   paramnumber = 0 
                                   focusedFxNumber = f.fxIndex 
                                   if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                      openCloseFx(track, f.fxIndex, not f.isOpen)
                                   end
                                end 
                                
                                reaper.ImGui_PopStyleColor(ctx, 1)
                                setToolTipFunc("Click to focus on " .. f.name .. " parameters\n- Double click to open or close")
                                
                                if scrollPlugin and tonumber(f.param) == tonumber(scrollPlugin) then
                                    reaper.ImGui_SetScrollHereY(ctx, 0)
                                    scrollPlugin = nil
                                end
                                
                            end
                        end
                         
                        
                        reaper.ImGui_EndTable(ctx)
                    end  
                    
                    
                    if not settings.showPluginOptionsOnTop then
                        openAllAddTrackFX()
                    end
                    
                    ImGui.EndChild(ctx)
                end
                
                --[[ 
                reaper.ImGui_Indent(ctx, margin)
                local ret, openSelectedFx = reaper.ImGui_Checkbox(ctx,"Open selected",settings.openSelectedFx)
                if ret then 
                    settings.openSelectedFx = openSelectedFx
                    saveSettings()
                end
                setToolTipFunc("Automatically open the selected plugin FX window")
                
                
                local ret, showParametersForAllPlugins = reaper.ImGui_Checkbox(ctx,"Show all parameters",settings.showParametersForAllPlugins) 
                if ret then 
                    settings.showParametersForAllPlugins = showParametersForAllPlugins
                    saveSettings()
                end
                setToolTipFunc("Show parameters for all plugins") 
                 ]]
                --[[
                local ret, includeModulators = reaper.ImGui_Checkbox(ctx,"Include Modulators",settings.includeModulators) 
                if ret then 
                    settings.includeModulators = includeModulators
                    saveSettings()
                end
                setToolTipFunc("Show Modulators container in the plugin list") 
                ]]
            end
            
            if click then 
                trackSettings.hidePlugins = not trackSettings.hidePlugins  
                saveTrackSettings(track)
            end
            
            ImGui.EndGroup(ctx)
            ImGui.EndGroup(ctx)
                
            placingOfNextElement()
        end
        
        ------------------------
        -- PARAMETERS ----------
        ------------------------
        
        function drawSearchIcon(size, buttonId, offsetX, offsetY, color, toolTip) 
            local pad = 4
            local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPos(ctx, curPosX + offsetX, curPosY + offsetY)
            local click = false
            if reaper.ImGui_Button(ctx, "##searchIcon" .. buttonId, size,size) then
                click = true
            end
            local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
            local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
            minX = minX + pad / 2
            minY = minY + pad - 1
            size = size - pad * 2
            local angle = 4
            
            -- vertical line
            reaper.ImGui_DrawList_AddCircle(draw_list, minX + size/2, minY + size/2, size/2.5, color)
            
            reaper.ImGui_DrawList_AddLine(draw_list, minX + size/4*3, minY + size/4*3, minX + size, minY+size, color)
            
            
            if not overlayActive then 
                setToolTipFunc(toolTip)
            end
            return click
        end
        
        if settings.showParametersPanel then
            function searchAndOnlyMapped()
                if settings.showOnlyMapped or settings.showSearch then
                    if not settings.showParameterOptionsOnTop then 
                        reaper.ImGui_Separator(ctx)
                    end
                    
                    if settings.showOnlyMapped then
                        ret, onlyMapped = reaper.ImGui_Checkbox(ctx,(settings.showSearch and "" or "Only mapped") .. "##Only mapped",settings.onlyMapped)
                        if ret then
                            settings.search = ""
                            settings.onlyMapped = onlyMapped
                            saveSettings()
                        end 
                        setToolTipFunc("Show only mapped parameters")
                        if settings.showSearch then
                            reaper.ImGui_SameLine(ctx)
                        end
                    end
                    
                    
                    if settings.showSearch then  
                        local posX = reaper.ImGui_GetCursorPosX(ctx) - 4
                        reaper.ImGui_SameLine(ctx, posX)
                        local searchWidth = moduleWidth - posX - 4
                        reaper.ImGui_SetNextItemAllowOverlap(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, searchWidth)
                        if focusSearchParameters then
                            reaper.ImGui_SetKeyboardFocusHere(ctx)
                            focusSearchParameters = nil
                        end
                        ret, search = reaper.ImGui_InputText(ctx,"##SearchParameter", settings.search) 
                        if ret then
                            settings.search = search
                            if settings.searchClearsOnlyMapped then
                                settings.onlyMapped = false
                            end
                            saveSettings()
                        end
                        reaper.ImGui_SameLine(ctx, posX + searchWidth-8)
                        local hasSearch = settings.search and settings.search ~= ""
                        if drawSearchIcon(20, "parameter", 0, 0, colorWhite, hasSearch and "Clear search" or "Search for parameters") then
                            if hasSearch then
                                settings.search = ""
                                saveSettings()
                            end
                            focusSearchParameters = true
                        end
                    end
                    if settings.showLastClicked then
                        p = paramnumber and focusedTrackFXParametersData[paramnumber + 1] or {}
                        parameterNameAndSliders("parameter",pluginParameterSlider,p , focusedParamNumber,nil,nil,nil,nil,moduleWidth,nil,nil,nil,true)
                        hasExtraLine = settings.showExtraLineInParameters
                        if hasExtraLine and not p.parameterLinkActive then
                            reaper.ImGui_InvisibleButton(ctx, "extraline dummy", 22,22)
                        end
                    end
                    
                    if settings.showParameterOptionsOnTop then 
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), colorText & 0xFFFFFFFF88)
                        reaper.ImGui_Separator(ctx)
                        reaper.ImGui_Separator(ctx)
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                end
            end
            
            if validateTrack(track) and fxnumber then 
                focusedTrackFXParametersData = getAllParametersFromTrackFx(track, fxnumber) 
            end
            
            
            ImGui.BeginGroup(ctx) 
            if not settings.vertical then
                --reaper.ImGui_Indent(ctx)
            end
            click = false
            title = "PARAMETERS" --.. (trackSettings.hideParameters and "" or (" (" .. (focusedParamNumber + 1) .. "/" .. #focusedTrackFXParametersData .. ")"))
            if trackSettings.hideParameters then  
                if modulePartButton(title .. "", not trackSettings.hideParameters and "Minimize parameters" or "Maximize parameters",settings.vertical and partsWidth or nil, true, true ) then 
                    click = true
                end
            else 
                reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 60, tableWidth, height)
                local visible = reaper.ImGui_BeginChild(ctx, 'Parameters', nil, nil, childFlags,reaper.ImGui_WindowFlags_MenuBar() | scrollFlags)
                if visible then
                    if reaper.ImGui_BeginMenuBar(ctx) then
                         title = "PARAMETERS" --.. (trackSettings.hideParameters and "" or (" (" .. (focusedParamNumber + 1) .. "/" .. #focusedTrackFXParametersData .. ")"))
                         if titleButtonStyle(title, not trackSettings.hideParameters and "Minimize parameters" or "Maximize parameters",settings.vertical and partsWidth or nil, true, (not settings.vertical and trackSettings.hideParameters)) then 
                             click = true
                         end
                        reaper.ImGui_EndMenuBar(ctx)
                    end
                    
                    if settings.showParameterOptionsOnTop then
                        searchAndOnlyMapped()
                    end
                    
                    size = nil
                    
                    
                    -- check if any parameters links a active
                    local someAreActive = false
                    if settings.onlyMapped then
                        for _, p in ipairs(focusedTrackFXParametersData) do 
                            if p.parameterLinkActive then someAreActive = true; break end
                        end
                        --if not someAreActive then settings.onlyMapped = false; saveTrackSettings(track) end
                    end
                    
                    local curPosY = (settings.showOnlyMapped or settings.showSearch or settings.showLastClicked) and (50 + ((settings.showOnlyMapped or settings.showSearch) and 24 or 0) + (settings.showLastClicked and (48 + (hasExtraLine and 24 or 0)) or 0)) or 40--reaper.ImGui_GetCursorPosY(ctx)
                    
                    local _, startPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                    --reaper.ImGui_SetNextWindowSizeConstraints(ctx, tableWidth-16, 40, tableWidth-16, height-curPosY)
                    if reaper.ImGui_BeginChild(ctx, "parametersForFocused", tableWidth-16, height-curPosY, nil,scrollFlags) then
                        for i, p in ipairs(focusedTrackFXParametersData) do 
                            --if p.param == focusedParamNumber then 
                            --posX, posY = reaper.ImGui_GetCursorPos(ctx) 
                            --end
                            --if not size then startPosY = reaper.ImGui_GetCursorPosY(ctx) end
                            local pMappedShown = not settings.showOnlyMapped or not someAreActive or not settings.onlyMapped or (settings.onlyMapped and p.parameterLinkActive)
                            local pSearchShown = not settings.showSearch or not settings.search or settings.search == "" or searchName(p.name, settings.search)
                            
                            local pTrackControlShown = true
                            if p.fxName == "Track controls" and i > 35 then
                                pTrackControlShown = false
                            end 
                            
                            if pMappedShown and pSearchShown and pTrackControlShown then
                                --reaper.ImGui_Text(ctx, "")
                                reaper.ImGui_Spacing(ctx) 
                                local doNotSetFocus = startPosY > mouse_pos_y_imgui
                                parameterNameAndSliders("parameter",pluginParameterSlider,p, focusedParamNumber,doNotSetFocus,nil,nil,nil,nil,nil,nil,nil,true)
                            --if not size then size = reaper.ImGui_GetCursorPosY(ctx) - startPosY end
                                
                                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), colorTextDimmedLight)
                                --reaper.ImGui_Separator(ctx)
                                --reaper.ImGui_PopStyleColor(ctx)
                                
                                --reaper.ImGui_NewLine(ctx)
                                
                                --if scroll and p.param == scroll then
                                --    ImGui.SetScrollHereY(ctx,  p.parameterLinkActive and 0.22 or 0.13) 
                                --    removeScroll = true
                                --end
                            end
                            --if p.param == focusedParamNumber then
                             --   reaper.ImGui_DrawList_AddRect(draw_list, windowPosX + posX, windowPosY+ posY, windowPosX+ posX+10, windowPosY +posY+10,colorBlue)
                            --end
                        end
                        reaper.ImGui_EndChild(ctx)
                    end
                    
                    if not settings.showParameterOptionsOnTop then
                        searchAndOnlyMapped()
                    end
                    
                    reaper.ImGui_EndChild(ctx)
                end 
                
                
                
            end
            if click then 
                trackSettings.hideParameters = not trackSettings.hideParameters  
                saveTrackSettings(track)
            end
            
            ImGui.EndGroup(ctx)
            
            placingOfNextElement()
        end

        
        
        ------------------------
        -- MODULES -------------
        ------------------------
        
        local factoryModules = {
            { 
              name = "AB Slider",
              tooltip = "Map two positions A and B of plugin parameters on the selected track. Only parameters changed will be mapped",
              func = "general",
              insertName = "JS: AB Slider Modulator"
            },
            { 
              name = "ACS Native",
              tooltip = "Add an Audio Control Signal (sidechain) modulator which uses the build in Reaper ACS",
              func = "ACS" 
            },
            { 
              name = "ADSR-1 (tilr)",
              rename = "ADSR",
              tooltip = "Add an ADSR that uses the plugin created by tilr",
              func = "general",
              insertName = "JS: ADSR-1",
              required = isAdsr1Installed,
              website = "https://forum.cockos.com/showthread.php?t=286951",
              requiredToolTip = 'Install the ReaPack by "tilr" first.\nClick to open webpage' 
            },
            { 
              name = "Button",
              tooltip = "A button toggle",
              func = "general",
              insertName = "JS: Button Modulator"
            },
            { 
              name = "Keytracker",
              tooltip = "Use the pitch of notes as a modulator",
              func = "general",
              insertName = "JS: Keytracker Modulator"
            },
            { 
              name = "LFO Native",
              tooltip = "Add an LFO modulator that uses the build in Reaper LFO which is sample accurate",
              func = "LFO" 
            },
            { 
              name = "Macro",
              tooltip = "A slider for control multiple parameter",
              func = "general",
              insertName = "JS: Macro Modulator"
            }, 
            { 
              name = "Macro 4",
              tooltip = "4 sliders for control multiple parameter",
              func = "general",
              insertName = "JS: Macro 4 Modulator"
            },
            { 
              name = "MSEG-1 (tilr)",
              rename = "MSEG",
              tooltip = "Add a multi-segment LFO / Envelope generator\nthat uses the plugin created by tilr",
              func = "general",
              insertName = "JS: MSEG-1",
              required = isAdsr1Installed,
              website = "https://forum.cockos.com/showthread.php?t=286951",
              requiredToolTip = 'Install the ReaPack by "tilr" first.\nClick to open webpage' 
            },
            { 
              name = "MIDI Fader",
              tooltip = "Use a MIDI fader as a modulator",
              func = "general",
              insertName = "JS: MIDI Fader Modulator"
            },
            { 
              name = "Note velocity",
              tooltip = "Use note velocity as a modulator",
              func = "general",
              insertName = "JS: Note velocity Modulator"
            },
            { 
              name = "4-in-1-out",
              tooltip = "Map 4 inputs to 1 output",
              func = "general",
              insertName = "JS: 4-in-1-out Modulator"
            },
            
            { 
              name = "XY",
              tooltip = "XY pad to control two parameters",
              func = "general",
              insertName = "JS: XY Modulator"
            },
            
          } 
          
          
            
                
          function modulesPanel()
              
                  
              function menuHeader(text, variable, tooltip)
                  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorButtonsHover)
                  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorButtonsActive)
                  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed)
                  local textState = (not settings[variable] and "Show" or "Hide") 
                  if reaper.ImGui_Button(ctx, text, partsWidth- 32) then  
                      settings[variable] = not settings[variable]
                      saveSettings()
                  end
                  
                  reaper.ImGui_PopStyleColor(ctx,4)
                  setToolTipFunc(textState .. " " .. tooltip)  
              end
              
              function moduleButton(text, tooltip)
                  local click = false
                  
                  if reaper.ImGui_Selectable(ctx, text, false) then 
                      click = true
                  end 
                  
                  setToolTipFunc(tooltip)  
                  
                  reaper.ImGui_Spacing(ctx)
                  return click
              end
              
              
              
              
              local click = false
              local curPosY = reaper.ImGui_GetCursorPosY(ctx)
              if reaper.ImGui_BeginChild(ctx, "modules list", tableWidth-16, height-curPosY-16, nil,scrollFlags) then
                  local currentFocus 
                  local nameOpened
                  local containerPos, insert_position
                  
                  
                  menuHeader("Factory [" .. 8 .."]", "showBuildin", "factory modulators")
                  if settings.showBuildin then 
                      
                      for _, val in ipairs(factoryModules) do
                          local notInstalled = (val.requiredToolTip and not val.required)
                          local tooltip = notInstalled and val.requiredToolTip or val.tooltip
                          
                          if notInstalled then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed) end
                          
                          if moduleButton("+ " .. val.name, tooltip) then
                              if val.func ~= "Any" then
                                  currentFocus = reaper.JS_Window_GetFocus()
                              end
                              if val.func == "general" then 
                                  if notInstalled then
                                      openWebpage(val.website)
                                  else
                                      containerPos, insert_position = insertFXAndAddContainerMapping(track, val.insertName, val.rename and val.rename or val.name) 
                                  end
                              elseif val.func == "ACS" then 
                                  containerPos, insert_position = insertACSAndAddContainerMapping(track)
                              elseif val.func == "LFO" then 
                                  containerPos, insert_position = insertLocalLfoFxAndAddContainerMapping(track)
                              elseif val.func == "Any" then 
                                  browserHwnd, browserSearchFieldHwnd = openFxBrowserOnSpecificTrack() 
                                  fx_before = getAllTrackFXOnTrackSimple(track)  
                              end
                              click = true
                          end 
                          
                          if notInstalled then reaper.ImGui_PopStyleColor(ctx) end
                      end   
                  end
  
                  
                  reaper.ImGui_Separator(ctx)
                  --[[
                  local count = settings.userModulators and #settings.userModulators or 0
                  menuHeader("User [" .. count .."]", "showUser", "user modulators")
                  if settings.showUser and count > 0 then 
                      for i, module in ipairs( settings.userModulators) do
                          local visualName = module.name and module.name or module.fxName
                          if moduleButton("+ " .. visualName .. "##" .. i, module.description) then
                              currentFocus = reaper.JS_Window_GetFocus()
                              nameOpened = visualName
                              containerPos, insert_position = insertFXAndAddContainerMapping(track, module.fxName, visualName)
                              mapParameterToContainer(track, containerPos, insert_position, module.outputParam)
                          end 
                          if reaper.ImGui_IsItemClicked(ctx, 1) then 
                              removeCustomModule = i 
                              removeCustomModuleName = visualName
                              openRemoveCustomModule = true
                          end
                      end 
                  end
                  
                  reaper.ImGui_Separator(ctx)
                  ]]
                  
                  local count = #settings.userModulators + 1
                  menuHeader("User [" .. count .."]", "showPreset", "modulator presets")
                  if settings.showPreset then  
                      if moduleButton("+ [ANY]", "Add any FX as a modulator") then 
                          browserHwnd, browserSearchFieldHwnd = openFxBrowserOnSpecificTrack() 
                          fx_before = getAllTrackFXOnTrackSimple(track) 
                          click = true
                      end 
                      
                      for i, module in ipairs( settings.userModulators) do
                          local visualName = module.name and module.name or module.fxName
                          if moduleButton("+ " .. visualName .. "##" .. i, module.description) then
                              currentFocus = reaper.JS_Window_GetFocus()
                              nameOpened = visualName
                              containerPos, insert_position = insertFXAndAddContainerMapping(track, module.fxName, visualName)
                              
                              if module.outputParam then
                                  mapParameterToContainer(track, containerPos, insert_position, module.outputParam)
                              end
                              
                              if module.params then
                                  setAllTrackFxParamValues(track,insert_position, module.params)
                              end
                              
                              if module.nativeLfo then
                                  setNativeLFOParamSettings(track,insert_position, module.nativeLfo)
                              end
                              if module.nativeAcs then
                                  setNativeACSParamSettings(track,insert_position, module.nativeAcs)
                              end
                              if module.hideParams then 
                                  local guid = reaper.TrackFX_GetFXGUID( track, insert_position )
                                  trackSettings.hideParametersFromModulator[guid] = module.hideParams
                                  saveTrackSettings(track)
                              end
                              click = true
                          end 
                          if reaper.ImGui_IsItemClicked(ctx, 1) then 
                              removeCustomModule = i 
                              removeCustomModuleName = visualName
                              openRemoveCustomModule = true
                              click = false
                          end
                      end 
                      
                  end
                  
                  
                  reaper.ImGui_Separator(ctx)
                  
                  
                  menuHeader("Extra [" .. 2 .."]", "showExtra", "extra functions")
                  if settings.showExtra then  
                  
                      -- set realearn params on the run after the first one
                      if setTrackControlParamsOnIndex then
                          setVolumePanAndSendControlPluginParams(track, setTrackControlParamsOnIndex) 
                          setTrackControlParamsOnIndex = nil
                      end
                      
                      local tooltip = not isReaLearnInstalled and 'Install Helgobox to have ReaLearn installed first.\nClick to open webpage' or "Control you volume, pan and send with modulators.\n[This is not a modulator and have to be placed outside the modulator folder]"
                      if not isReaLearnInstalled then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
                      if moduleButton("+ Track controls", tooltip) then
                          if not isReaLearnInstalled then
                              openWebpage("https://www.helgoboss.org/projects/realearn")
                          else 
                              currentFocus = reaper.JS_Window_GetFocus()
                              insert_position = addVolumePanAndSendControlPlugin(track)  
                              setTrackControlParamsOnIndex = insert_position
                          end
                          click = true
                      end  
                      if not isReaLearnInstalled then reaper.ImGui_PopStyleColor(ctx) end
                      
                      if moduleButton("+ MIDI Out", "Output a midi message") then
                          containerPos, insert_position = insertFXAndAddContainerMapping(track, "JS: MIDI Out Modulator", "Midi Out")  
                          currentFocus = reaper.JS_Window_GetFocus()
                          click = true
                      end
                  end
                  
                  reaper.ImGui_Separator(ctx)
                  
                  
                  if currentFocus then 
                      --reaper.ShowConsoleMsg(modulationContainerPos .. " - ".. insert_position .. "\n")
                      --openCloseFx(track, insert_position, false)
                      
                      fxIsShowing = reaper.TrackFX_GetOpen(track,insert_position)
                      fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,insert_position)
                      if fxIsShowing then
                          reaper.TrackFX_Show(track, insert_position, fxIsFloating and 2 or 0) 
                      end
                      
                      if containerPos then
                          containerIsShowin = reaper.TrackFX_GetOpen(track,containerPos)
                          containerIsFloating = reaper.TrackFX_GetFloatingWindow(track,containerPos)
                          if containerIsShowin then
                              reaper.TrackFX_Show(track, containerPos, containerIsFloating and 2 or 0) 
                          end
                      end
                      
                      --local newFocus = reaper.JS_Window_GetFocus() 
                      --if newFocus ~= currentFocus and reaper.JS_Window_GetTitle(newFocus):match(nameOpened) ~= nil then 
                       --   reaper.JS_Window_Show(newFocus, "HIDE") 
                      --end
                  end
          
                  ImGui.EndChild(ctx)
              end 
              
              return click
          end
          
          
          
          if browserHwnd and track and track == lastTrack then 
              firstBrowserHwnd = firstBrowserHwnd and firstBrowserHwnd + 1 or 0 
              
              fx_after = getAllTrackFXOnTrackSimple(track)
              if #fx_after > #fx_before then
                  local newFxIndex
                  local fxName
                  for i, fx in ipairs(fx_after) do
                      if not fx_before[i] or fx.name ~= fx_before[i].name then
                          newFxIndex = fx.fxIndex
                          fxName = fx.name
                          break;
                      end
                  end
                  -- An FX was added
                  openCloseFx(track, newFxIndex, false) 
                  reaper.TrackFX_SetNamedConfigParm( track, newFxIndex, 'renamed_name', fxName:gsub("^[^:]+: ", "")) 
                  modulationContainerPos, insert_position = movePluginToContainer(track, newFxIndex )
                  renameModulatorNames(track, modulationContainerPos)
                  browserHwnd = nil
              end
               
              if not addingAnyModuleWindow(browserHwnd) then
                  browserHwnd = nil
              end
              
              -- first time after creating overlay we focus browser and search field
              if firstBrowserHwnd == 1 and browserSearchFieldHwnd then
                  reaper.JS_Window_SetFocus(browserHwnd)
                  reaper.JS_Window_SetFocus(browserSearchFieldHwnd)
              end
              
              local visible = reaper.JS_Window_IsVisible(browserHwnd) 
              if not browserHwnd or not visible then   
                  browserHwnd = nil
              end
          else
              -- we clear for next time
              fx_before = nil
              fx_after = nil
              firstBrowserHwnd = nil
              browserSearchFieldHwnd = nil
              browserHwnd = nil
          end  
              
               
              
          
          
          function removeCustomModulePopup()
              if openRemoveCustomModule then
                  ImGui.OpenPopup(ctx, 'Remove custom module') 
                  openRemoveCustomModule = false
              end
              if reaper.ImGui_BeginPopup(ctx, 'Remove custom module') then
                  if reaper.ImGui_Button(ctx, "Remove " .. removeCustomModuleName) or reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                      table.remove(settings.userModulators, removeCustomModule)
                      saveSettings()
                      reaper.ImGui_CloseCurrentPopup(ctx)
                  end
                  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                      reaper.ImGui_CloseCurrentPopup(ctx)
                  end
                  ImGui.EndPopup(ctx)
              end 
          end
          
          
          if settings.showModulesPanel then
              
              ImGui.BeginGroup(ctx) 
              if not settings.vertical then
                  --reaper.ImGui_Indent(ctx)
              end
              click = false
              if trackSettings.hideModules then
                if modulePartButton("MODULES", not trackSettings.hideModules and "Minimize modules" or "Maximize modules",settings.vertical and partsWidth or nil, true,true ) then 
                    click = true
                end 
              else 
                  local height = settings.vertical and settings.modulesHeightVertically or pansHeight
                  reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 30, partsWidth, height)
                  if reaper.ImGui_BeginChild(ctx, "Modules", 0.0, 0.0, childFlags , reaper.ImGui_WindowFlags_MenuBar() ) then
                      if reaper.ImGui_BeginMenuBar(ctx) then
                           if titleButtonStyle("MODULES", not trackSettings.hideModules and "Minimize modules" or "Maximize modules",settings.vertical and partsWidth or nil, true, (not settings.vertical and trackSettings.hideModules)) then 
                               click = true
                           end
                          reaper.ImGui_EndMenuBar(ctx)
                      end
                      modulesPanel()
                      removeCustomModulePopup()
                      
                      reaper.ImGui_EndChild(ctx)
                  
                  end
                  
              end
              
              ImGui.EndGroup(ctx)
              
              
              if click then
                  trackSettings.hideModules = not trackSettings.hideModules
                  saveTrackSettings(track)
              end
              
              placingOfNextElement()
              --modulesAdd() 
          end
          
          
          
          
          
          ------------------------
          -- MODULATORS ----------
          ------------------------
          
          
              
              
                  
                  
              
          function mapAndShow(track, fx, sliderNum, fxInContainerIndex, name) 
              reaper.ImGui_BeginGroup(ctx)
              local isCollabsed = trackSettings.collabsModules[fx.guid]
              local h = isCollabsed and 20 or buttonWidth/(not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 2 or 3)
              local w = buttonWidth * (not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 1 or 2)
              
              local isShowing = trackSettings.showMappings[fx.guid] 
              local isMapping = map == fx.fxIndex 
              
              ImGui.PushStyleColor(ctx, reaper.ImGui_Col_Button(),isMapping and settings.colors.mapping or settings.colors.buttons)
              ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),isMapping and settings.colors.mapping or colorButtonsHover)
              ImGui.PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),isMapping and settings.colors.mapping or colorButtonsActive)
              
              if reaper.ImGui_Button(ctx, isMapping and "MAPPING" or "MAP", w, h) then 
                  mapModulatorActivate(fx.fxIndex,sliderNum, fx.fxInContainerIndex, name)
              end
              
              reaper.ImGui_PopStyleColor(ctx, 3) 
               
              local text = (map and (not isMapping and ("Click to map " .. mapName .. "\nPress escape to stop mapping") or "Click or press escape to stop mapping") or "Click to map output")
              if settings.showToolTip then
                  reaper.ImGui_SetItemTooltip(ctx, text)
              end 
              
              reaper.ImGui_EndGroup(ctx)
          end
          
          function openGui(track, fxIndex, name, gui, extraIdentifier, isCollabsed, sizeW, sizeH, visualizerSize) 
              if gui then 
                  local _, currentValue = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible' )
                  fxIsShowing = currentValue == "1"
              else
                  fxIsShowing = reaper.TrackFX_GetOpen(track,fxIndex)
                  fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
              end
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), fxIsShowing and settings.colors.pluginOpen or settings.colors.buttons)
              --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
              --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorLightGrey)
              sizeW = sizeW and sizeW or (isCollabsed and 20 or buttonWidth * 2 + 8) --(moduleWidth-dropDownSize-margin*4)
              sizeH = sizeH and sizeH or (isCollabsed and 20 or 20)
              if gui then
                  title = isCollabsed and (fxIsShowing and "CG" or "OG") or ((fxIsShowing and "Close" or "Open") .. (visualizerSize == 2 and "\n" or " ") .. "Gui")
              else
                  title = isCollabsed and (fxIsShowing and "CP" or "OP") or ((fxIsShowing and "Close" or "Open") .. (visualizerSize == 2 and "\n" or " ") .. "Plugin")
              end
              if reaper.ImGui_Button(ctx,title .."##"..fxIndex .. (extraIdentifier and extraIdentifier or ""), sizeW,sizeH) then
                  if gui then
                      reaper.TrackFX_SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible',fxIsShowing and 0 or 1  )
                  else
                      --[[if fxIsShowing and fxIsFloating == nil then
                          reaper.TrackFX_SetOpen(track,fxIndex, false)
                      else
                          reaper.TrackFX_Show(track, fxIndex, fxIsShowing and 2 or 3)  
                      end]]
                      openCloseFx(track, fxIndex, not fxIsShowing) 
                  end
              end 
              if settings.showToolTip then
                  reaper.ImGui_SetItemTooltip(ctx, "Open " .. name .. " as floating")
              end
              reaper.ImGui_PopStyleColor(ctx,1)
          end
          
          function openCloseMappings(fx, fxIndex, mappings, floating)
              local isShowing = floating and settings.floatingParameterShowMappings  or trackSettings.showMappings[fx.guid] 
              local colorBg = isShowing and colorLightGrey or colorDarkGrey
              reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
              reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 20)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),isShowing and colorMapping or colorMappingLight)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), settings.colors.buttonsSpecial)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),settings.colors.buttonsSpecialHover)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),settings.colors.buttonsSpecialActive)
              local tv = #mappings -- (isShowing and ">" or "^")
              
              reaper.ImGui_PushFont(ctx, font11) 
              
              if reaper.ImGui_Button(ctx,  "##" .. fxIndex, 15,15) then
                  if floating then
                      settings.floatingParameterShowMappings = not settings.floatingParameterShowMappings
                      saveSettings()
                  else
                      trackSettings.showMappings[fx.guid] = not isShowing 
                      saveTrackSettings(track)
                  end
              end 
              
              
              local bX, bY = reaper.ImGui_GetItemRectMin(ctx)
              local textW, textH = reaper.ImGui_CalcTextSize(ctx, tv, 0,0)
              reaper.ImGui_DrawList_AddText(draw_list, bX - textW / 2 + 8, bY - textH/ 2 + 8,colorMapping, tv)
              reaper.ImGui_PopStyleColor(ctx, 4)
              reaper.ImGui_PopStyleVar(ctx,2)
              
              reaper.ImGui_PopFont(ctx)
              
              setToolTipFunc((isShowing and "Hide" or "Show" ) .. " " .. #mappings .." mappings")
          end
          
          
          
          
          local function drawFaderFeedback(sizeW, sizeH, fxIndex, param, min, max, isCollabsed, fx)
              local sizeId =  4-- isCollabsed and (settings.vertical and 1 or 2) or ((trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 4 or 3)
              
              local sizeId = isCollabsed and 1 or (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
              
              local waveFormSize = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid])
              if not inputPlots then inputPlots = {}; time = {}; offset = {}; phase = {} end
              --aaa = lastCollabsModules
              --reaper.ShowConsoleMsg(tostring(isCollabsed) .. " - " .. fxIndex .. " - " .. tostring(lastCollabsModules[fxIndex]) .. "\n")
              --if not sizeW then 
              --local sizeW, sizeH, plotAmount
              
              --local visualizerSize = settings.visualizerSize
              
              local valuesForPlotting = {
                  {
                    w = 20,
                    h = 20, 
                    p = 100
                  },{
                    w = buttonWidth,
                    h = buttonWidth/2, 
                    p = 200
                  },{
                    w = buttonWidth*2,
                    h = buttonWidth, 
                    p = 400
                  }, 
              }
              if isCollabsed then
                  plotAmount = 50
              else
                  --sizeW = sizeW --/ 4 * visualizerSize
                  --sizeH = sizeW
                  plotAmount = (sizeW / 20) * 50
              end
              
              -- ret, value = reaper.TrackFX_GetNamedConfigParm( track, modulatorsPos, 'container_map.get.' .. fxIndex .. '.2' )
              local value = reaper.TrackFX_GetParamNormalized(track,fxIndex,param)
              for i = 1, #valuesForPlotting do 
                  local idTimer = fx.guid.. i  .. param
                  local timerPlotAmount = valuesForPlotting[i].p
                  
                  if not inputPlots[idTimer] then 
                      inputPlots[idTimer] = reaper.new_array(timerPlotAmount); 
                      for t = 1, timerPlotAmount do 
                          inputPlots[idTimer][t] = value
                      end
                  end
                  if not time[idTimer] then time[idTimer] = ImGui.GetTime(ctx) end
                  if not offset[idTimer] then offset[idTimer] = 1 end
                  if not phase[idTimer] then phase[idTimer] = 0 end
                  
                  while time[idTimer] < ImGui.GetTime(ctx) do -- Create data at fixed 60 Hz rate
                      inputPlots[idTimer][offset[idTimer]] = value -- math.cos(phase[idTimer])--value
                      offset[idTimer] = (offset[idTimer] % timerPlotAmount) + 1
                      --phase[idTimer] = phase[idTimer] + (offset[idTimer] * 0.1)
                      time[idTimer] = time[idTimer] + (1.0 / 120.0)
                  end
              end
              
              local isMapping = map == fxIndex and sliderNumber == param
              
              nameOverlay = ""
              nameForMapping = fx.name
              if #fx.output > 1 then
                  _, paramName = reaper.TrackFX_GetParamName(track, fxIndex, param)
                  nameForMapping = nameForMapping .. ": " .. paramName
                  nameOverlay = paramName
              end
              --end
              local posX, posY = reaper.ImGui_GetCursorPos(ctx) 
              local toolTip = (map and (not isMapping and ("Click to map " .. nameForMapping .. "\nPress escape to stop mapping " .. mapName) or "Click or press escape to stop mapping") or "Click to map " .. nameForMapping .."\n - hold Super to change size" )
              --local toolTip = (sizeId == 1 or sizeId == 2) and "Click to map output" or (sizeId == 4 and "Click to make waveform small" or "Click to make waveform big")
              local mappingW = reaper.ImGui_CalcTextSize(ctx, "MAPPING", 0 , 0)
              --local nameOverlay = "" -- (map and isMapping) and ((isCollabsed or sizeW < mappingW) and "M" or "MAPPING") or ""
              clicked = reaper.ImGui_Button(ctx, nameOverlay .. "##plotLinesButton" .. fxIndex .. param ,sizeW,sizeH)
              local lineX, lineY = reaper.ImGui_GetItemRectMin(ctx)
              if settings.showToolTip then setToolTipFunc(toolTip) end
              
              
              local id = fx.guid .. sizeId .. param
              --[[
              -- attempt to write my own plotting, but gives the same result
              for i = 1, plotAmount do 
                  local ip = inputPlots[id][i]
                  local valRelative = sizeH * ip
                  local timeRelative = sizeW * (i / plotAmount)
                  local x1 = lineX + timeRelative
                  local y1 = lineY + valRelative
                  local x2 = x1
                  local y2 = y2
                  reaper.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2,colorWhite, 1)
              end
              ]]
              
              reaper.ImGui_SetCursorPos(ctx, posX, posY) 
              
              local bgColor = isMapping and colorMapping or settings.colors.modulatorOutputBackground
              if settings.pulsateMappingButton and isMapping then 
                  bgColor = colorMappingPulsating
              end
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), bgColor)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotLines(), settings.colors.modulatorOutput)
              
              reaper.ImGui_PlotLines(ctx, '##'..fxIndex, inputPlots[id], offset[id] - 1, nil, 0, 1, sizeW, sizeH)
              
              
              reaper.ImGui_PopStyleColor(ctx,2)
              --clicked = reaper.ImGui_IsItemClicked(ctx)
              local textW, textH = reaper.ImGui_CalcTextSize(ctx, nameOverlay, 0,0)
              reaper.ImGui_DrawList_AddText(draw_list, lineX + sizeW/2 - textW/2, lineY + sizeH/2 - textH/2,  settings.colors.modulatorOutput, nameOverlay)
               
              --if reaper.ImGui_IsItemHovered(ctx) then
              --    reaper.ImGui_SetTooltip(ctx,toolTip)
              --end
              
              
              --
          
              return clicked
          end
          
          function modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, func, name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx, genericModulatorInfo, outputArray)
              dropDownSize = modulatorWidth -30--/ 2
              buttonWidth = dropDownSize / 2
              
              reaper.ImGui_BeginGroup(ctx)
              local valuesFromModulator
              
              local mappings = fx.mappings
              
              toolTipText = ((isCollabsed and "Maximize " or "Minimize ") .. name .. "\n - right click for more options")
              
              click = false 
              
              local minX, minY, maxX, maxY = false, false, false, false
              
              local borderColor = selectedModule == fxIndex and (map == fxIndex and colorMapping or settings.colors.modulatorBorderSelected) or settings.colors.modulatorBorder
              
              --local flags = reaper.ImGui_TableFlags_BordersOuter()
              --flags = not isCollabsed and flags or flags | reaper.ImGui_TableFlags_NoPadOuterX() --| reaper.ImGui_TableFlags_RowBg()
              -- ignore scroll if alt is pressed
              --flags = not vertical and flags | reaper.ImGui_TableFlags_ScrollY() or flags
               
              
              collabsOffsetY = not vertical and 20 or 0
              collabsOffsetX = vertical and 28 or 0 
              
              local modulatorStartPosX, modulatorStartPosY = reaper.ImGui_GetCursorScreenPos(ctx)
              
              local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
              
              
              local openPopupForModule = false
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), floating and settings.colors.modulatorBorder or borderColor)
              if isCollabsed then  
                  
                  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.menuBar)
                  --reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 20, tableWidth, height)
                  if reaper.ImGui_BeginChild(ctx, name .. fxIndex, modulatorWidth, modulatorHeight, childFlags,  reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()) then
                      
                      
                      local offsetX = 0
                      if settings.showRemoveCrossModulator and not floating then
                          local removePosOffsetX = vertical and 0 or 2
                          local removePosOffsetY = vertical and 2 or modulatorHeight - 20
                          if mouse_pos_x_imgui >= screenPosX and mouse_pos_x_imgui <= screenPosX + modulatorWidth and mouse_pos_y_imgui >= screenPosY and mouse_pos_y_imgui <= screenPosY + modulatorHeight then
                              if specialButtons.close(ctx,removePosOffsetX, removePosOffsetY,16,false,"remove" .. fxIndex, settings.colors.removeCross, settings.colors.removeCrossHover,colorTransparent, colorTransparent) then
                                  deleteModule(track, selectedModule, modulationContainerPos, fx)
                              end
                              setToolTipFunc("Remove modulator") 
                              ignoreRightClick = true
                          end 
                          offsetX = offsetX + 8
                      end
                      
                      if not vertical then
                          reaper.ImGui_SetCursorPosY(ctx, 4)
                          reaper.ImGui_SetCursorPosX(ctx, 4)
                          openCloseMappings(fx, fxIndex, mappings, floating)
                          
                          
                          reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-7, reaper.ImGui_GetCursorPosY(ctx))
                          
                          -- TODO: when adding modules with more outputs than 4 then make another solutiong
                          for i, output in ipairs(outputArray) do 
                              if i > 1 then 
                                  reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-7, reaper.ImGui_GetCursorPosY(ctx)-4)
                              end
                              
                              if drawFaderFeedback(20,20, fxIndex, output, 0, 1, isCollabsed, fx) then 
                                  mapModulatorActivate(fx,output, name, nil, #outputArray == 1)
                              end   
                          end
                          -- dummy button for modules without an output area
                          if #outputArray == 0 then
                              reaper.ImGui_InvisibleButton(ctx, "dummy", 1,1)
                          end
                          
                          
                          reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-6, reaper.ImGui_GetCursorPosY(ctx))
                          
                          
                          
                          click = verticalButtonStyle(name, toolTipText, nil,false,false,9.5, true)
                          
                          local clickType = lastItemClickAndTooltip(toolTipText)
                          
                          click = false 
                          if clickType == "right" then 
                              openPopupForModule = true
                          elseif clickType == "left" then 
                              click = true
                          end
                          
                      else
                          reaper.ImGui_SetCursorPosY(ctx, 0)
                          reaper.ImGui_SetCursorPosX(ctx,settings.showRemoveCrossModulator and 16 or 0)
                          
                          reaper.ImGui_PushFont(ctx, font1) 
                          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),settings.colors.menuBarHover)
                          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),settings.colors.menuBarActive)
                          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
                          
                          local widthForButton = modulatorWidth - 20 * (#outputArray) - 24 - 16
                          
                          reaper.ImGui_Button(ctx, "##" .. fxIndex, widthForButton)
                          local buttonX, buttonY = reaper.ImGui_GetItemRectMin(ctx)
                          reaper.ImGui_DrawList_AddText(draw_list, buttonX+4, buttonY+3, colorText, name)
                          
                          reaper.ImGui_PopFont(ctx)
                          reaper.ImGui_PopStyleColor(ctx, 3)
                          
                          local clickType = lastItemClickAndTooltip(toolTipText)
                          
                          click = false 
                          if clickType == "right" then 
                              openPopupForModule = true
                          elseif clickType == "left" then 
                              click = true
                          end
                          
                          reaper.ImGui_SetCursorPosY(ctx, 1)
                          
                          for i, output in ipairs(outputArray) do  
                              reaper.ImGui_SameLine(ctx)
                              reaper.ImGui_SetCursorPosX(ctx, modulatorWidth - (20 * (#outputArray - i)) - 44)
                              
                              if drawFaderFeedback(20,20, fxIndex, output, 0, 1, isCollabsed, fx) then 
                                  mapModulatorActivate(fx,output, name, nil, #outputArray == 1)
                              end   
                          end 
                          
                          reaper.ImGui_SetCursorPosY(ctx, 4)
                          reaper.ImGui_SetCursorPosX(ctx, modulatorWidth - 20)
                          openCloseMappings(fx, fxIndex, mappings, floating)
                          
                      end
                      
                      
                      
                      reaper.ImGui_EndChild(ctx)
                  end 
                  
                  reaper.ImGui_PopStyleColor(ctx,1)
                  
              else
                  if modulatorHeight then
                  end
                  local useFlags = childFlags
                  if floating  or (vertical and not settings.limitModulatorHeightToModulesHeight) then 
                      useFlags = reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()
                  else
                      reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 20, modulatorWidth, modulatorHeight)
                  end
                  
                  
                  if reaper.ImGui_BeginChild(ctx, name .. fxIndex, modulatorWidth, 0, useFlags, reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_NoScrollbar() | scrollFlags) then
                   
                      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
                      
                      if reaper.ImGui_BeginMenuBar(ctx) then 
                          local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
                          
                          local offsetX = 0
                          if settings.showRemoveCrossModulator and not floating then
                              if mouse_pos_x_imgui >= screenPosX and mouse_pos_x_imgui <= screenPosX + modulatorWidth and mouse_pos_y_imgui >= screenPosY and mouse_pos_y_imgui <= screenPosY + modulatorHeight then
                                  if specialButtons.close(ctx,0,2,16,false,"remove" .. fxIndex, settings.colors.removeCross, settings.colors.removeCrossHover,colorTransparent, colorTransparent) then
                                      deleteModule(track, selectedModule, modulationContainerPos, fx)
                                  end
                                  setToolTipFunc("Remove modulator")
                                  ignoreRightClick = true
                              end
                              offsetX = offsetX + 8
                          end
                          
                          reaper.ImGui_PushFont(ctx, font1) 
                          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),settings.colors.menuBarHover)
                          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),settings.colors.menuBarActive)
                          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
                          
                          reaper.ImGui_SetCursorPos(ctx, curPosX + offsetX, curPosY)
                          
                          reaper.ImGui_Button(ctx, name .. "##" .. fxIndex)
                          
                          reaper.ImGui_PopFont(ctx)
                          reaper.ImGui_PopStyleColor(ctx, 3)
                          
                          local clickType = lastItemClickAndTooltip(toolTipText)
                          
                          click = false
                          if clickType == "right" then  
                              openPopupForModule = true
                          elseif clickType == "left" then 
                              click = true
                          end 
                          
                          
                          reaper.ImGui_SetCursorPos(ctx, curPosX + modulatorWidth - 28, curPosY+4)
                          
                          
                          openCloseMappings(fx, fxIndex, mappings, floating)
                          
                          
                          reaper.ImGui_EndMenuBar(ctx)
                      end
                      
                      if not isCollabsed then 
                          local isMapped = not genericModulatorInfo or genericModulatorInfo.outputParam ~= -1
                          
                          if fx.fxName:match("AB Slider") == nil and isMapped then
                              if hideParametersFromModulator == fx.guid then
                                  if reaper.ImGui_Button(ctx, "Stop editing", modulatorWidth-16) then
                                      hideParametersFromModulator = nil
                                  end
                                  local allIsShown = true 
                                  local param_count = reaper.TrackFX_GetNumParams(track, fxIndex)
                                  for p = 0, param_count - 1 do 
                                      if trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] and trackSettings.hideParametersFromModulator[fx.guid][p] then
                                          allIsShown = false
                                          break;
                                      end
                                  end
                                  if reaper.ImGui_Button(ctx, allIsShown and "Hide all" or "Show all", modulatorWidth-16) then
                                      for p = 0, param_count - 1 do 
                                          trackSettings.hideParametersFromModulator[fx.guid][p] = allIsShown
                                          saveTrackSettings(track)
                                      end
                                  end
                              else
                                  if (trackSettings.bigWaveform) then
                                     -- reaper.ShowConsoleMsg(tostring((trackSettings.bigWaveform[fx.guid])) .. "\n")
                                  end
                                  visualizerSize = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
                                  reversedVisualizerSize = 4 - (visualizerSize == 1 and 0 or visualizerSize)
                                  
                                  size = buttonWidth * 2 / reversedVisualizerSize
                                  if visualizerSize == 1 and #outputArray > 1 then
                                      size = size - 3
                                  elseif visualizerSize == 2 then
                                      size = size + 2
                                  elseif visualizerSize == 3 then
                                      size = size + 12
                                  end
                                  
                                  for i, output in ipairs(outputArray) do 
                                      if drawFaderFeedback( size,20*visualizerSize, fxIndex, output, 0, 1, isCollabsed, fx) then  
                                          mapModulatorActivate(fx, output, name, nil, #outputArray == 1)
                                          --trackSettings.bigWaveform[fx.guid] = not trackSettings.bigWaveform[fx.guid]
                                          --saveTrackSettings(track)
                                      end 
                                      
                                      if i < #outputArray then 
                                          if visualizerSize == 1 and (i)%4 > 0 then
                                              reaper.ImGui_SameLine(ctx)
                                          elseif visualizerSize == 2 and (i)%2 > 0 then
                                              reaper.ImGui_SameLine(ctx)
                                          end
                                      end
                                      
                                      --if not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) then reaper.ImGui_SameLine(ctx); end
                                      --mapAndShow(track, fx, output, fxInContainerIndex, name, true) 
                                  end
                              end
                          end
                          
                          
                          local hasGui = fx.fxName:match("ACS Native Modulator") ~= nil
                          local fxName = fx.fxName
                          if hideParametersFromModulator ~= fx.guid and 
                            (fxName:match("ADSR%-1") ~= nil 
                            or fxName:match("MSEG%-1") ~= nil 
                            or fxName:match("ACS Native Modulator") ~= nil 
                            or genericModulatorInfo )
                              then
                              
                              local sizeW = buttonWidth * 2 + 12
                              local sizeH = 20
                              visualizerSize = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
                              
                              if #outputArray % 4 * visualizerSize < 3 then
                              --(#outputArray < 4 and #outputArray % 2 == 1) or (#outputArray > 4 and #outputArray % 4 == 1) then
                                  
                                  reaper.ImGui_SameLine(ctx)
                                  
                                  if (#outputArray % 4) * visualizerSize == 1 then
                                      sizeW = buttonWidth /2 * 3 + 4
                                      --sizeH = 2 * 20 
                                  end
                                  if (#outputArray % 4) * visualizerSize == 2 then
                                      sizeW = buttonWidth + 4
                                      sizeH = 2 * 20 
                                  end
                                  
                              end
                              
                              openGui(track, fxIndex, name, hasGui, "", false, sizeW, sizeH, visualizerSize)
                          end
                          
                          if #outputArray > 0 then
                              reaper.ImGui_Separator(ctx)
                          end
                          
                          local curPosY = reaper.ImGui_GetCursorPosY(ctx)
                          
                          local paramsHeight = modulatorHeight and (modulatorHeight-curPosY-16) or nil
                          
                          useWindowFlags = scrollFlags
                          
                          useFlags = reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeY()
                          if floating or (vertical and not settings.limitModulatorHeightToModulesHeight) then 
                              --useFlags = reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeY()
                              --useWindowFlags = reaper.ImGui_WindowFlags_re()
                          else 
                              reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 40, modulatorWidth, paramsHeight)
                          end
                          local id = "params" .. name .. fxIndex .. (floating and "floating" or "normal")
                          if reaper.ImGui_BeginChild(ctx, id, modulatorWidth-16, nil, useFlags,useWindowFlags) then 
                              valuesFromModulator = func(id, name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx, genericModulatorInfo)
                              reaper.ImGui_EndChild(ctx)
                          end
                      end
                      
                      -----------------
                      -----REMOVE------
                      -----------------
                      --[[
                      local isHovered = buttonHovering["delete" .. fxIndex]
                      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
                      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
                      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), isHovered and colorRedHidden or colorGrey)
                      
                      if reaper.ImGui_Button(ctx, "Delete module##delete" .. fxIndex) then
                          deleteModule(track, selectedModule, modulationContainerPos)
                      end
                      buttonHovering["delete" .. fxIndex] = reaper.ImGui_IsItemHovered(ctx) 
                      reaper.ImGui_PopStyleColor(ctx, 4)
                      ]]
                      -----------------
                      -----------------
                      -----------------
                      
                      reaper.ImGui_PopStyleColor(ctx,1)
                      --reaper.ImGui_EndTable(ctx)
                      reaper.ImGui_EndChild(ctx)
                  end
                  
                  --
                  
                  
                  
                  reaper.ImGui_Spacing(ctx)
                  
                  
              end
              
              reaper.ImGui_PopStyleColor(ctx,1)
              
              
              if click then
                  if floating then
                      settings.floatingParameterShowModulator = not settings.floatingParameterShowModulator
                      saveSettings()
                  else
                      trackSettings.collabsModules[fx.guid] = not trackSettings.collabsModules[fx.guid]
                      saveTrackSettings(track)
                      selectedModule = fxIndex
                  end
              end
              
              
              if not minX then minX, minY = reaper.ImGui_GetItemRectMin(ctx) end
              if not maxX then maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) end
              --reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, selectedModule == fxIndex and (map == fxIndex and colorMap or colorWhite) or colorGrey,4)
              local mouseX, mouseY = reaper.ImGui_GetMousePos(ctx)
              
              -- module hoover
              if mouseX >= minX and mouseX <= maxX and mouseY >= minY and mouseY <= maxY then
                  if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then 
                      selectedModule = fxIndex
                      --openPopupForModule = true
                      --ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                  end
                  if  reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
                      selectedModule = fxIndex
                  end
              end
              
              if openPopupForModule and not popupAlreadyOpen then
                  ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
              end
                  
              
              if ImGui.BeginPopup(ctx, 'popup##' .. fxIndex, nil) then
                  if reaper.ImGui_Button(ctx,"Delete##" .. fxIndex) then
                      deleteModule(track, fxIndex, modulationContainerPos, fx)
                      ImGui.CloseCurrentPopup(ctx)
                  end
                  if reaper.ImGui_Button(ctx,"Rename##" .. fxIndex) then
                      ImGui.CloseCurrentPopup(ctx)
                      openRename = true 
                  end
                  originalName = trackSettings.renamed[fx.guid]
                  if originalName and originalName ~= name then
                      if reaper.ImGui_Button(ctx,"Revert to original name##" .. fxIndex) then
                          renameModule(track, modulationContainerPos, fxIndex, originalName)
                          ImGui.CloseCurrentPopup(ctx) 
                      end
                  end
                  
                  if reaper.ImGui_Button(ctx,"Store as preset##" .. fxIndex) then
                      ImGui.CloseCurrentPopup(ctx)
                      addUserModulator = true 
                      addModulatorPreset = true 
                  end
                  setToolTipFunc("This will store the FX as a preset including all it's settings")
                  
                  local genericHasMapping = valuesFromModulator and valuesFromModulator.outputParam ~= - 1
                  if genericHasMapping then
                      reaper.ImGui_NewLine(ctx)
                      reaper.ImGui_TextColored(ctx, colorGrey, "User modulator:")
                      if reaper.ImGui_Button(ctx,"Change modulator output##" .. fxIndex) then
                          deleteParameterFromContainer(track, modulationContainerPos, fxIndex, valuesFromModulator.indexInContainerMapping)
                          ImGui.CloseCurrentPopup(ctx)
                      end
                      reaper.ImGui_TextColored(ctx, colorRedHidden, "This will break any mappings!!")
                      
                      
                      if reaper.ImGui_Button(ctx,"Hide parameters from modulator##" .. fxIndex) then
                          ImGui.CloseCurrentPopup(ctx)
                          hideParametersFromModulator = fx.guid
                      end 
                      setToolTipFunc("This will store the FX as a preset with the FX's standard settings")
                      
                      if reaper.ImGui_Button(ctx,"Add module as preset##" .. fxIndex) then
                          ImGui.CloseCurrentPopup(ctx)
                          addUserModulator = true 
                      end 
                      setToolTipFunc("This will store the FX as a preset with the FX's standard settings") 
                  end
                  
                  
                  ImGui.EndPopup(ctx)
              end 
              
              
              function storeCustomModulator(name, description, fx, outputParam, preset) 
                      
                  local obj = {fxName = fx.fxName, name = name, outputParam = outputParam, description = description, params = params}
                   
                  if preset then
                      local params = getAllTrackFxParamValues(track,fx.fxIndex)
                      obj.params = params
                  end
                  
                  if fx.fxName:match("LFO Native Modulator") ~= nil then
                      obj.nativeLfo = getNativeLFOParamSettings(track,fxIndex) 
                  elseif fx.fxName:match("ACS Native Modulator") ~= nil then
                      obj.nativeAcs = getNativeACSParamSettings(track,fxIndex) 
                  end
                  
                  if trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] then
                      obj.hideParams = trackSettings.hideParametersFromModulator[fx.guid]
                  end
                  
                  table.insert(settings.userModulators, obj) 
                  
                  saveSettings()
              end
              
              
              if openRename then
                    ImGui.OpenPopup(ctx, 'rename##' .. fxIndex) 
                    openRename = false
              end
              
              if reaper.ImGui_BeginPopup(ctx, 'rename##' .. fxIndex, nil) then
                  reaper.ImGui_Text(ctx, "Rename " .. name)
                  reaper.ImGui_SetKeyboardFocusHere(ctx)
                  local originalName = name
                  local ret, newName = reaper.ImGui_InputText(ctx,"##" .. fxIndex, name,nil,nil)
                  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                      reaper.ImGui_CloseCurrentPopup(ctx)
                  end
                  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                      if not trackSettings.renamed then trackSettings.renamed = {} end
                      if trackSettings.renamed[fx.guid] == nil then trackSettings.renamed[fx.guid] = originalName end
                      if newName == "" then newName = trackSettings.renamed[fx.guid] end -- ; trackSettings.renamed[fx.guid] = nil end
                      renameModule(track, modulationContainerPos, fxIndex, newName)
                      reaper.ImGui_CloseCurrentPopup(ctx)
                  end
                  ImGui.EndPopup(ctx)
              end 
              
              if addUserModulator then
                  ImGui.OpenPopup(ctx, 'addModulatorPreset##' .. fxIndex)  
              end
              
              if reaper.ImGui_BeginPopup(ctx, 'addModulatorPreset##' .. fxIndex, nil) then
                  reaper.ImGui_Text(ctx, "Add modulator settings as preset to MODULES")
                  if addUserModulator then
                      reaper.ImGui_SetKeyboardFocusHere(ctx)
                  end 
                  addUserModulator = false
                  
                  reaper.ImGui_Spacing(ctx)
                  reaper.ImGui_TextColored(ctx, colorGrey, "Preset name")
                  if not renamingCustomModule then renamingCustomModule = name end
                  local ret, newName = reaper.ImGui_InputText(ctx,"##name" .. fxIndex, renamingCustomModule,nil,nil)
                  renamingCustomModule = newName
                  
                  reaper.ImGui_TextColored(ctx, colorGrey, "Preset description")
                  if not descriptionCustomModule then descriptionCustomModule = "" end
                  local ret, description = reaper.ImGui_InputText(ctx,"##description" .. fxIndex, descriptionCustomModule,nil,nil)
                  descriptionCustomModule = description
                  
                  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
                      reaper.ImGui_CloseCurrentPopup(ctx)
                      renamingCustomModule = nil
                      descriptionCustomModule = nil
                      addModulatorPreset = nil
                  end
                  
                  if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
                      storeCustomModulator(newName, description, fx, valuesFromModulator and valuesFromModulator.outputParam, not addUserModulator)
                      reaper.ImGui_CloseCurrentPopup(ctx)
                      renamingCustomModule = nil
                      descriptionCustomModule = nil
                      addModulatorPreset = nil
                  end
                  
                  ImGui.EndPopup(ctx)
              end 
              
              reaper.ImGui_EndGroup(ctx)
              
              function fixMissingIndentOnCollabsModule(isCollabsed)
                  if isCollabsed then 
                      local curX, curY = reaper.ImGui_GetCursorPos(ctx)
                      reaper.ImGui_SetCursorPos(ctx, curX+ 4, curY)
                  end
              end
              
          end
                  
                  
          function mappingsArea(mappingWidth, mappingHeight, m, vertical, floating, isCollabsed, ignoreFxIndex, ignoreParam)   
              local name = m.name
              local fxIndex = m.fxIndex
              local mappings = m.mappings
              local guid = m.guid
              
              local filteredMappings = {}
              
              if not vertical or (floating and settings.floatingParameterShowModulator) then 
                  reaper.ImGui_SameLine(ctx) 
                  
                  reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx)-7)
              else 
                  if floating then
                      reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) -3) 
                  else
                      reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + (isCollabsed and -3 or -7)) 
                  end
              end
              reaper.ImGui_BeginGroup(ctx) 
              
              --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderStrong(), colorMap)
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorMapping)
              
              
              --local useFlags = childFlags
              --useFlags = reaper.ImGui_ChildFlags_Border()
              useFlags = reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeY()
              if not vertical then 
                  reaper.ImGui_SetNextWindowSizeConstraints(ctx, 40, 60, mappingWidth, mappingHeight)
                  --mappingHeight = nil
              else 
                  reaper.ImGui_SetNextWindowSizeConstraints(ctx, 40, 60, mappingWidth, mappingHeight)
                  mappingHeight = nil
              end
                  
              
              
              local visible = reaper.ImGui_BeginChild(ctx, "mappings" .. name .. fxIndex, mappingWidth, mappingHeight, useFlags ,reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_HorizontalScrollbar())
              if visible then
                  --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorDarkGrey)
                  reaper.ImGui_PushFont(ctx, font1)
                  --reaper.ImGui_TableSetupColumn(ctx, "< Mappings")
                  
                  --reaper.ImGui_TableSetupScrollFreeze(ctx,1,2) 
                  --reaper.ImGui_TableHeadersRow(ctx)
                  if reaper.ImGui_BeginMenuBar(ctx) then 
                      
                      --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),menuGreyHover)
                      --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),menuGreyActive)
                      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
                      --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),colorMap)
                      reaper.ImGui_Button(ctx, "Mappings" .. (#mappings> 0 and (" (" .. #mappings .. ")") or ""))
                      reaper.ImGui_PopStyleColor(ctx, 1)
                      reaper.ImGui_EndMenuBar(ctx)
                  end
                  reaper.ImGui_PopFont(ctx)
                  
                  
                  local clickType = lastItemClickAndTooltip("Hide mapped parameters")
                  if clickType then
                      if floating then
                          settings.floatingParameterShowMappings = false
                      else
                          trackSettings.showMappings[guid] = false
                      end
                  end
                  
                  reaper.ImGui_TableNextColumn(ctx)
                  
                  local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
                  local faderWidth = mappingWidth - 32--(floating and 16 or 32)
                  local alreadyShowing = {}
                  
                  
                  for i, map in ipairs(mappings) do  
                      local fxIndex = map.fxIndex
                      local _, name = reaper.TrackFX_GetFXName(track, fxIndex)
                      
                      if not alreadyShowing[fxIndex] and (not ignoreFxIndex or (ignoreFxIndex ~= fxIndex)) then 
                          
                          --fixMissingIndentOnCollabsModule(isCollabsed)
                          
                          
                          fxIsShowing = reaper.TrackFX_GetOpen(track,fxIndex)
                          fxIsFloating = reaper.TrackFX_GetFloatingWindow(track,fxIndex)
                          local isShowing = (fxIsShowing or fxIsFloating)
                          
                          
                          local toolTip = (not isShowing and "Open " or "Close ") .. name .. " plugin"
                          if buttonSelect(ctx, name .. "##" .. name .. fxIndex, toolTip, isShowing, faderWidth, 1, colorButtonsBorder, colorButtons, colorButtonsHover, colorButtonsActive, settings.colors.pluginOpen) then
                              openCloseFx(track, fxIndex, not isShowing) 
                          end
                          
                          --if i > 1 then 
                          --    reaper.ImGui_Spacing(ctx)
                          --end
                          alreadyShowing[fxIndex] = true
                          
                      end
                      
                      --fixMissingIndentOnCollabsModule(isCollabsed)
                      parameterNameAndSliders("mappings" .. (floating and "Floating" or ""),pluginParameterSlider,getAllDataFromParameter(track,fxIndex,map.param), focusedParamNumber, nil, nil, true, false, faderWidth)
                  
                      --reaper.ImGui_Spacing(ctx)
                      --reaper.ImGui_Separator(ctx)
                      if scroll and map.param == scroll then
                          ImGui.SetScrollHereY(ctx,  0.22)
                          removeScroll = true
                      end
                  end
                  --reaper.ImGui_SameLine(ctx)
                  --if reaper.ImGui_BeginMenuBar(ctx) then
                      --clickType = titleTextStyle(name, toolTipText, moduleWidth, false)
                       --local clickType = lastItemClickAndTooltip(toolTipText)
                      
                       click = false
                       if clickType == "right" then 
                           ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
                       elseif clickType == "left" then 
                           click = true
                       end
                        
                       --if settings.vertical and isCollabsed then
                          
                        --  func(name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx)
                      --end
                     -- reaper.ImGui_EndMenuBar(ctx)
                  --end
                  --reaper.ImGui_PopStyleVar(ctx)
                  --reaper.ImGui_TableNextRow(ctx)
                  reaper.ImGui_TableNextColumn(ctx)
                  
                  --reaper.ImGui_PopStyleColor(ctx,1)
                  --reaper.ImGui_EndTable(ctx)
                  reaper.ImGui_EndChild(ctx)
              end
              
              
              reaper.ImGui_PopStyleColor(ctx,1)
              
              reaper.ImGui_EndGroup(ctx)
          end
              
              
              
              
              
          
        function modulatorsWrapped(modulatorWidth, modulatorHeight, m, isCollabsed, vertical, floating)    
            local fxIndex = m.fxIndex
            local fxName = m.fxName
            local name = m.name
            local fxInContainerIndex = m.fxInContainerIndex
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.modulesBackground)
            
            
            if fxName:match("LFO Native Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, nlfoModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m, nil, m.output) 
            elseif fxName:match("ADSR%-1") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, adsrModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil, m.output)
            elseif fxName:match("MSEG%-1") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, msegModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("MIDI Fader Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, midiCCModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("AB Slider Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, abSliderModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("ACS Native Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, acsModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("4%-in%-1%-out Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, _4in1Out, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("Keytracker Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, keytrackerModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("Note Velocity Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, noteVelocityModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output) 
            elseif fxName:match("XY Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, xyModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            
            elseif fxName:match("Button Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, buttonModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output) 
            elseif fxName:match("Macro Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, macroModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            elseif fxName:match("Macro 4 Modulator") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, macroModulator4, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
                    
                
            elseif fxName:match("MIDI Out") then
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, midiOutModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
                
            else 
                
                local numParams = reaper.TrackFX_GetNumParams(track,fxIndex) 
                local output = {}
                -- make possible to have multiple outputs
                local genericModulatorInfo = {outputParam = -1, indexInContainerMapping = -1}
                for p = 0, numParams -1 do
                    --retval, buf = reaper.TrackFX_GetNamedConfigParm( track, fxIndex, "param." .. p .. ".container_map.hint_id" )
                    -- we would have to enable multiple outputs here later
                    retval, buf = reaper.TrackFX_GetNamedConfigParm( track, modulationContainerPos, "container_map.get." .. fxIndex .. "." .. p )
                    if retval then
                        table.insert(output, p)
                        genericModulatorInfo = {outputParam = p, indexInContainerMapping = tonumber(buf)}
                        break
                    end
                end
                
                -- FETCH genericModulator INFO HERE
                modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, genericModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m, genericModulatorInfo,output)
            end
            
            
            reaper.ImGui_PopStyleColor(ctx, 1)
        end
        
              
                  
        ImGui.BeginGroup(ctx) 
        if not settings.vertical then
           -- reaper.ImGui_Indent(ctx)
        end
        
        function optionsForModulators()
            if settings.showSortByNameModulator then
                local ret, sortAsType = reaper.ImGui_Checkbox(ctx,"Sort by name",settings.sortAsType)
                if ret then
                    settings.sortAsType = sortAsType
                    saveSettings()
                end
            end
            
            if settings.showMapOnceModulator then
                ret, mapOnce = reaper.ImGui_Checkbox(ctx,"Map once",settings.mapOnce)
                if ret then
                    settings.mapOnce = mapOnce
                    saveSettings()
                end
            end 
        end
        
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.modulatorsModuleBackground)
        
        local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
        local x,y = reaper.ImGui_GetCursorPos(ctx)
        local modulatorsW = settings.vertical and partsWidth or (winW-x-8)
        local modulatorsH = settings.vertical and 0 or pansHeight
        --modulatorsH = winH-y-30
        local visible = ImGui.BeginChild(ctx, 'ModulatorsChilds', modulatorsW, modulatorsH, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()| reaper.ImGui_ChildFlags_AutoResizeX(),reaper.ImGui_WindowFlags_MenuBar() | reaper.ImGui_WindowFlags_HorizontalScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse())
        --local visible = reaper.ImGui_BeginTable(ctx, 'ModulatorsChilds', settings.vertical and 1 or #modulatorNames,nil, modulatorsW)
        if visible then 
            
            local mouseInsideModulatorsArea = mouse_pos_x_imgui >= screenPosX and mouse_pos_x_imgui <= screenPosX + modulatorsW and mouse_pos_y_imgui >= screenPosY and mouse_pos_y_imgui <= screenPosY + modulatorsH
            local allowAnyScroll = not isScrollValue
            allowAnyScroll = allowAnyScroll and mouseInsideModulatorsArea
            local allowScroll = (allowAnyScroll and not settings.vertical and settings.useVerticalScrollToScrollModulatorsHorizontally)
            allowScroll = allowScroll and mouseInsideModulatorsArea 
            allowScroll = (allowScroll and not settings.onlyScrollVerticalHorizontalOnTopOrBottom) or (allowScroll and (mouse_pos_y_imgui < screenPosY + 80 or mouse_pos_y_imgui > screenPosY + modulatorsH - 30))
            allowScroll = (allowScroll and not settings.onlyScrollVerticalHorizontalScrollWithModifier) or (allowScroll and compareTwoTables(modifierTable, settings.modifierEnablingScrollVerticalHorizontal))
            
             
            local scroll_x = reaper.ImGui_GetScrollX(ctx)
            local scroll_max_x = reaper.ImGui_GetScrollMaxX(ctx)
            if allowScroll then
                if scrollVertical ~= 0 then
                    local newScroll = scroll_x - (scrollVertical * settings.scrollingSpeedOfVerticalHorizontalScroll)
                    if newScroll < 0 then newScroll = 0 end
                    if newScroll > scroll_max_x then newScroll = scroll_max_x end
                    reaper.ImGui_SetScrollX(ctx, newScroll)
                end
            end
            
            if not isScrollValue and settings.scrollModulatorsHorizontalAnywhere and mouseInsideAppWindow then
                allowAnyScroll = true
            end
            
            if allowAnyScroll and scrollHorizontal ~= 0 then
                local newScroll = scroll_x - (scrollHorizontal * settings.scrollingSpeedOfHorizontalScroll)
                if newScroll < 0 then newScroll = 0 end
                if newScroll > scroll_max_x then newScroll = scroll_max_x end
                reaper.ImGui_SetScrollX(ctx, newScroll)
            end
            
            if reaper.ImGui_BeginMenuBar(ctx) then 
                if titleButtonStyle("MODULATORS", allIsNotCollabsed and "Minimize all modulators" or "Maximize all modulators",settings.vertical and partsWidth or nil,true,false ) then 
                    if modulatorNames and #modulatorNames > 0 then
                        if allIsNotCollabsed then
                            for _, m in ipairs(modulatorNames) do trackSettings.collabsModules[m.guid] = true end
                        else
                            for _, m in ipairs(modulatorNames) do trackSettings.collabsModules[m.guid] = false end
                        end 
                        saveTrackSettings(track)
                    end
                end
                
                if not settings.vertical then 
                    optionsForModulators()
                end
                
                
                reaper.ImGui_EndMenuBar(ctx)
            end
            
            
            if settings.vertical then 
                --optionsForModulators()
            end
        
             --
            
            function setParameterNormalizedButReturnFocus(track, fxIndex, param, value) 
                reaper.TrackFX_SetParamNormalized(track, fxIndex, param, value)
                -- focus last focused
                reaper.TrackFX_SetParamNormalized(track,fxnumber,paramnumber,reaper.TrackFX_GetParamNormalized(track,fxnumber,paramnumber))
                return value
            end
            
            function setParameterButReturnFocus(track, fxIndex, param, value) 
                reaper.TrackFX_SetParam(track, fxIndex, param, value)
                -- focus last focused
                -- TODO: do we need this anymore, passed out for now
                --reaper.TrackFX_SetParam(track,fxnumber,paramnumber,reaper.TrackFX_GetParam(track,fxnumber,paramnumber))
                return value
            end
        
          
            if settings.sortAsType then 
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
            
            local tableWidthCollabsed = 22
            local tableHeightHorizontal = winH- reaper.ImGui_GetCursorPosY(ctx) - 54 - 8
            
            local addNewModulatorHeight = settings.vertical and tableWidthCollabsed or tableHeightHorizontal 
            local addNewModulatorWidth = settings.vertical and moduleWidth or tableWidthCollabsed 
            
            
            if settings.showAddModulatorButtonBefore then
                if titleButtonStyle("+", "Add new modulator", addNewModulatorWidth,true,false, addNewModulatorHeight ) then 
                    reaper.ImGui_OpenPopup(ctx, 'Add new modulator')  
                end
                if not settings.vertical then reaper.ImGui_SameLine(ctx) end
            end
            
            if modulationContainerPos then 
                ignoreRightClick = false
                for pos, m in ipairs(modulatorNames) do   
                    local isCollabsed = trackSettings.collabsModules[m.guid] 
                    local smallHeader = isCollabsed and not settings.vertical
                    local modulatorWidth = settings.vertical and moduleWidth or (isCollabsed and tableWidthCollabsed or moduleWidth)
                    local modulatorHeight = settings.vertical and (isCollabsed and tableWidthCollabsed or settings.modulesHeightVertically) or tableHeightHorizontal
                    modulatorsWrapped(modulatorWidth, modulatorHeight, m, isCollabsed, settings.vertical)
                    
                    local mappingHeight = vertical and settings.modulesHeightVertically or tableHeightHorizontal
                    if trackSettings.showMappings[m.guid] then 
                        mappingsArea(moduleWidth, mappingHeight, m, settings.vertical,false, isCollabsed)   
                    end 
                    
                    if not settings.vertical then reaper.ImGui_SameLine(ctx) end
                end  
            end
         
         
            --if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything", widthOfTrackName, true,false,nil,true,24,  settings.colors.buttonsSpecialHover ) then 
            if settings.showAddModulatorButton then
                if titleButtonStyle("+", "Add new modulator", addNewModulatorWidth,true,false, addNewModulatorHeight ) then 
                    reaper.ImGui_OpenPopup(ctx, 'Add new modulator')  
                end
            end
            
            if reaper.ImGui_BeginPopup(ctx, 'Add new modulator') then 
                
                --if reaper.ImGui_BeginChild(ctx, "child of floating modules", nil, nil, reaper.ImGui_ChildFlags_AutoResizeX()| reaper.ImGui_ChildFlags_AutoResizeY() | reaper.ImGui_ChildFlags_AlwaysAutoResize()) then
                    if modulesPanel() then 
                        if not isSuperPressed then
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                --    reaper.ImGui_EndChild(ctx) 
                --end
                
                
                --[[ 
                local ret, val = reaper.ImGui_Checkbox(ctx,"Close after add",settings.closeModulesPopupOnAdd) 
                if ret then 
                    settings.closeModulesPopupOnAdd = val
                    saveSettings()
                end
                setToolTipFunc("Close modules popup when adding a modulator") 
                ]]
                removeCustomModulePopup()
                reaper.ImGui_EndPopup(ctx)
            end
            
            
            --reaper.ImGui_EndTable(ctx)
            ImGui.EndChild(ctx)
        end
        
        reaper.ImGui_PopStyleColor(ctx, 1)
        
        -- TODO: Do we need this?
        reaper.ImGui_Text(ctx,"")
        ImGui.EndGroup(ctx)
        
        local startOfModulatorsPanelX, startOfModulatorsPanelY = reaper.ImGui_GetItemRectMin(ctx)
        local endOfModulatorsPanelX, endOfModulatorsPanelY = reaper.ImGui_GetItemRectMax(ctx)
        if not ignoreRightClick and reaper.ImGui_IsMouseHoveringRect(ctx, startOfModulatorsPanelX, startOfModulatorsPanelY, endOfModulatorsPanelX, endOfModulatorsPanelY) and isMouseDownRightImgui then
            openFloatingModulesWindow = not openFloatingModulesWindow 
        end
        
        
        if not track then
            reaper.ImGui_EndDisabled(ctx)
        end
        --else
        --    reaper.ImGui_Text(ctx,"SELECT A TRACK OR TOUCH A TRACK PARAMETER")
        --end
        
        
        
        if reaper.ImGui_IsWindowHovered(ctx) then
          --  reaper.ShowConsoleMsg(tostring(reaper.ImGui_IsAnyItemHovered(ctx)) .. "\n")
        end
        
            
        if track and settings.showTrackColorLine then 
            local trackColor = getTrackColor(track)
            local thickness = settings.trackColorLineSize
            local lineWidth = settings.vertical and winW or 0
            local lineHeight = settings.vertical and 0 or winH
            local offsetX = settings.vertical and 0 or thickness / 2
            local offsetY = settings.vertical and thickness / 2 or 0
            reaper.ImGui_DrawList_AddLine(draw_list, windowPosX + offsetX, windowPosY + offsetY, windowPosX + offsetX + lineWidth, windowPosY + offsetY + lineHeight, trackColor,thickness)
        end
        
        
        
        reaper.ImGui_PopStyleColor(ctx, colorsPush2)
        ImGui.End(ctx)
    end
    
    
    function floatingModulesWindow()
        local rv, open = reaper.ImGui_Begin(ctx, "MODULES", true, reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse()) 
        if not rv then return open end
        modulesPanel()
        reaper.ImGui_End(ctx)
        return open 
    end
    
    if openFloatingModulesWindow then
        --openFloatingModulesWindow = floatingModulesWindow()
    end
    
    --settingsOpen = true
    if settingsOpen then
       settingsOpen = appSettingsWindow()
    end
    
    function floatingMappedParameterWindow(trackTouched, fxIndexTouched, parameterTouched)
        
        
        
        if hwndWindowOnTouchParam and reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) and floatingMapperWin and mousePosOnTouchedParam and settings.openFloatingMapperRelativeToMouse and settings.openFloatingMapperRelativeToMousePos then 
            local x, y
            if settings.openFloatingMapperRelativeToMousePos.x == 0 then x = mousePosOnTouchedParam.x + settings.openFloatingMapperRelativeToMousePos.x - floatingMapperWin.w/2 end
            if settings.openFloatingMapperRelativeToMousePos.x < 0 then x = mousePosOnTouchedParam.x + settings.openFloatingMapperRelativeToMousePos.x - floatingMapperWin.w end
            if settings.openFloatingMapperRelativeToMousePos.x > 0 then x = mousePosOnTouchedParam.x + settings.openFloatingMapperRelativeToMousePos.x end
            if settings.openFloatingMapperRelativeToMousePos.y == 0 then y = mousePosOnTouchedParam.y + settings.openFloatingMapperRelativeToMousePos.y * (isApple and -1 or 1) - floatingMapperWin.h/2 end
            if settings.openFloatingMapperRelativeToMousePos.y > 0 then y = mousePosOnTouchedParam.y + settings.openFloatingMapperRelativeToMousePos.y * (isApple and -1 or 1) - floatingMapperWin.h end
            if settings.openFloatingMapperRelativeToMousePos.y < 0 then y = mousePosOnTouchedParam.y + settings.openFloatingMapperRelativeToMousePos.y * (isApple and -1 or 1) end
            mousePosOnTouchedParam = nil
            reaper.ImGui_SetNextWindowPos(ctx, x,y,reaper.ImGui_Cond_Always())
        end
        if hwndWindowOnTouchParam and reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) and floatingMapperWin and settings.openFloatingMapperRelativeToWindowPos and settings.openFloatingMapperRelativeToWindow then  
            local _, left, top, right, bottom = reaper.JS_Window_GetRect(hwndWindowOnTouchParam)

            if isApple then top = screenHeight - top; bottom = screenHeight - bottom end
            local width = right - left
            local height = bottom - top
            
            local pos = settings.openFloatingMapperRelativeToWindowPos
            local x, y
            
            if pos % 5 == 0 then x = right end
            if pos % 5 == 1 then x = left - floatingMapperWin.w end
            if pos % 5 == 2 then x = left end
            if pos % 5 == 3 then x = left + width / 2 - floatingMapperWin.w/2 end
            if pos % 5 == 4 then x = right - floatingMapperWin.w end
            if math.floor(pos / 5.1) == 1 then y = top end
            if math.floor(pos / 5.1) == 2 then y = top + height/2 - floatingMapperWin.h/2  end
            if math.floor(pos / 5.1) == 3 then y = bottom - floatingMapperWin.h  end
            if pos < 5 then y = top - floatingMapperWin.h end
            if pos > 20 then y = bottom end
                
            reaper.ImGui_SetNextWindowPos(ctx, x,y,reaper.ImGui_Cond_Always())
        end
        
        local rv, open = reaper.ImGui_Begin(ctx, "Floating mapper", true, reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoTitleBar()) 
        if not rv then return open end
        if not trackTouched or not fxIndexTouched or not parameterTouched then return false end
        
        if not reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) then  
            --hwndWindowOnTouchParam = reaper.TrackFX_GetFloatingWindow(track, fxIndexTouched)
            --if not reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) then 
                open = false
            --end
        end
        
        if reaper.ImGui_BeginMenuBar(ctx) then
            
            
            reaper.ImGui_EndMenuBar(ctx)
        end
        
        
        
        
        local p = getAllDataFromParameter(trackTouched, fxIndexTouched, parameterTouched)
        
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        local winX, winY = reaper.ImGui_GetWindowPos(ctx) 
        floatingMapperWin = {w = winW, h = winH}
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, winX,winY,winX+winW,winY+ 16, settings.colors.boxBackground, 8)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, winX,winY + 10,winX+winW,winY+ 24, settings.colors.boxBackground, 0)
        reaper.ImGui_DrawList_AddLine(draw_list, winX,winY + 24,winX+winW,winY+ 24, settings.colors.textDimmed, 1)
        
        
        reaper.ImGui_SetCursorPos(ctx, 3, 3)
        if specialButtons.lock(ctx, "lock", 20, locked, (locked and "Unlock from track" or "Lock to selected track"), colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, trackColor, true) then
            locked = not locked and track or false 
            --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
        end
        
        
        --local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
        
        
        reaper.ImGui_SetCursorPos(ctx, 3+20, 3)
        specialButtons.envelopeSettings(ctx, "envelopeSettings", 20, settings.showEnvelope, (settings.showEnvelope and "Disable" or "Enable") .. " showing envelope on parameter click\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, true, automationColor, automationColor, fillEnvelopeButton)
        clickEnvelopeSettings()
        
        --[[
        reaper.ImGui_SetCursorPos(ctx, 3+40, 3)
        specialButtons.floatingMapper(ctx, "floatingMapper", 20, settings.useFloatingMapper, "Click for floating mapper settings", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.appBackground, true)
        if reaper.ImGui_IsItemClicked(ctx) then 
            reaper.ImGui_OpenPopup(ctx, "floatingMapperButton")  
        end ]]
        --reaper.ImGui_SetCursorPos(ctx, 3+40, 3)
        --smallAutomationButton(track, "floating", 16)
        
        local headerW = reaper.ImGui_CalcTextSize(ctx, "Mapper", 0,0)
        --reaper.ImGui_SetCursorPos(ctx, (winW) / 2 - headerW / 2, 4)
        reaper.ImGui_SetCursorPos(ctx, 3+40, 0)
        local posX = reaper.ImGui_GetCursorPosX(ctx)
        
        reaper.ImGui_PushFont(ctx, font2)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
        --reaper.ImGui_Text(ctx, "Mapper")
        reaper.ImGui_Button(ctx, "Mapper", winW - posX - 22)
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_PopStyleColor(ctx, 3)
        setToolTipFunc("Click for floating mapper settings")
        if reaper.ImGui_IsItemClicked(ctx) then 
            reaper.ImGui_OpenPopup(ctx, "floatingMapperButton") 
        end 
        
        
        if reaper.ImGui_BeginPopup(ctx, "floatingMapperButton") then 
            floatingMapperSettings() 
            reaper.ImGui_EndPopup(ctx)
        end
        
        if (not lastWinW or lastWinW == winW) and specialButtons.close(ctx,winW-22,6,12,false,"closeFloatingMapper", colorTransparent, colorBlack,colorTextDimmed, settings.colors.removeCrossHover) then 
            open = false
        end
        lastWinW = winW
        
        setToolTipFunc("Close floating mapper")
        
        reaper.ImGui_Spacing(ctx)
        
        
        if mouse_pos_x_imgui >= winX and mouse_pos_x_imgui <= winX + winW and mouse_pos_y_imgui >= winY and mouse_pos_y_imgui <= winY + winH then 
            
            if isAnyMouseDown then
                clickedInFloatingWindow = true 
            end
            if isMouseReleased then
                clickedInFloatingWindow = false
            end
            
        end
        
        
        
        local partsWidth = settings.partsWidth
        local sizeW = partsWidth -- winW - margin * 4
        dropDownSize = moduleWidth -30--/ 2
        buttonWidth = dropDownSize / 2
        
        parameterNameAndSliders("parameterFloating",pluginParameterSlider,p, focusedParamNumber,nil,nil,nil,nil,sizeW,nil,nil,nil,true)
        
        local sizeH = not settings.floatingParameterShowModulator and 22 or 22--60--(winH - reaper.ImGui_GetCursorPosY(ctx) - margin*2)
        
        if p.parameterLinkActive then
            local m = nil
            if modulationContainerPos then 
                for pos, mt in ipairs(modulatorNames) do  
                    a = mt
                    if p.parameterLinkName == mt.mappingNames[p.parameterLinkParam] then
                        m = mt
                        break;
                    end
                end  
            end
            if m then 
                --childFlags = reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()
                local curStartY = reaper.ImGui_GetCursorPosY(ctx)
                modulatorsWrapped(sizeW, sizeH, m, not settings.floatingParameterShowModulator, true, true) 
                local sizeModulatorH = reaper.ImGui_GetCursorPosY(ctx) - curStartY - 8
                if settings.floatingParameterShowMappings then 
                    if not settings.floatingParameterShowModulator then
                        sizeModulatorH = settings.modulesHeightVertically
                        
                    end
                    mappingsArea(sizeW, sizeModulatorH, m, true, true, settings.floatingParameterShowModulator, p.fxIndex, p.param)   
                end 
            end
        end
        
        reaper.ImGui_End(ctx)
        return open 
    end
    
    
    if not settings.useFloatingMapper then
        showFloatingMapper = false
    end
    --[[
    if showFloatingMapper and track  and track == trackTouched and fxnumber and paramnumber then
        showFloatingMapper = floatingMappedParameterWindow(track, fxnumber, paramnumber) 
    end ]]
    if showFloatingMapper and validateTrack(track) and track == trackTouched and fxIndexTouched and parameterTouched then
        showFloatingMapper = floatingMappedParameterWindow(trackTouched, fxIndexTouched, parameterTouched) 
    end 
    
    
    
    if isAnyMouseDown then
        local alreadyHidden = not showFloatingMapper
        if settings.onlyKeepShowingWhenClickingFloatingWindow and not isFXWindowUnderMouse() then
            showFloatingMapper = false
        end
        if not alreadyHidden and reaper.ImGui_IsMousePosValid(ctx) and (settings.keepWhenClickingInAppWindow or (not settings.keepWhenClickingInAppWindow and clickedInFloatingWindow)) then
            showFloatingMapper = true
        end
    end
    
    reaper.ImGui_PopStyleColor(ctx, colorsPush)
    reaper.ImGui_PopStyleVar(ctx, varPush)
    reaper.ImGui_PopFont(ctx)
    
    
    
    --if (reaper.ImGui_IsKeyDown(ctx,reaper.ImGui_Mod_Super()) and  reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Backspace())) or reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Delete()) then
    --    deleteModule(track, selectedModule, modulationContainerPos)
    --end
    if isAltPressed and reaper.ImGui_IsKeyDown(ctx,reaper.ImGui_Key_M()) then
       -- open = false
    end
    
    if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
       if map then 
          map = false
       end
       if hideParametersFromModulator then
          hideParametersFromModulator = nil
       end
       
    end 
    
    if removeScroll then
        scroll = nil
        removeScroll = false
    end
    
    if track and (not lastTrack or lastTrack ~= track) then  
        lastTrack = track
    end
    --------------- KEY COMMANDS ----------------
    
    local time = reaper.time_precise()
    local newKeyPressed, altKeyPressed = checkKeyPress()  
    
    if not newKeyPressed or not altKeyPressed then 
        lastKeyPressedTime = nil; 
        --lastKeyPressedTimeInitial = nil 
    end
    if (not lastKeyPressed) or ((newKeyPressed  and lastKeyPressed ~= newKeyPressed) or (altKeyPressed and lastAltKeyPressed ~= altKeyPressed)) then 
        local alreadyUsed = false
        for _, info in ipairs(keyCommandSettings) do 
            local name = info.name
            for _, command in ipairs(info.commands) do
                if command == newKeyPressed or command == altKeyPressed then
                --reaper.ShowConsoleMsg("hej\n")
                    alreadyUsed = true
                    if name == "Close" then 
                        open = false
                    elseif name == "Undo" then
                        reaper.Main_OnCommand(40029, 0) --Edit: Undo
                    elseif name == "Redo" then
                        reaper.Main_OnCommand(40030, 0) --Edit: Redo    
                    elseif name == "Map current toggle" then
                        if modulationContainerPos and selectedModule then 
                            for pos, m in ipairs(modulatorNames) do  
                                if selectedModule == m.fxIndex then 
                                    mapModulatorActivate(m,m.output[1], m.name, true, nil, #m.output == 1) 
                                    break;
                                end
                            end  
                        end
                    elseif name == "Open Settings" then
                        settingsOpen = not settingsOpen
                    end
                    lastKeyPressedTimeInitial = time
                end 
            end
        end 
        --local shortCut 
        if not alreadyUsed then
            shortCut = getPressedShortcut()
            if settings.passAllUnusedShortcutThrough then
                local s = lookForShortcutWithShortcut(newKeyPressed)
                if not s then 
                    s = lookForShortcutWithShortcut(altKeyPressed)
                end
                if s then
                    if s.external then
                        reaper.Main_OnCommand(reaper.NamedCommandLookup('_' .. s.command), 0)
                    else
                        reaper.Main_OnCommand(s.command, 0)
                    end
                    lastKeyPressedTimeInitial = time
                end
            else 
                for _, s in ipairs(passThroughKeyCommands) do
                    
                    if s.scriptKeyPress == newKeyPressed or s.scriptKeyPress == altKeyPressed then
                        if s.external then
                            reaper.Main_OnCommand(reaper.NamedCommandLookup('_' .. s.command), 0)
                        else
                            reaper.Main_OnCommand(s.command, 0)
                        end
                        lastKeyPressedTimeInitial = time
                    end
                end
            end
        end
        
        
        
        lastKeyPressed = newKeyPressed
        lastAltKeyPressed = altKeyPressed
    else
        -- hardcoded repeat values
        if lastKeyPressedTimeInitial and time - lastKeyPressedTimeInitial > 0.1 then
            if lastKeyPressedTime and time - lastKeyPressedTime > 0.2 then 
                lastKeyPressed = nil
                lastAltKeyPressed = nil
            --else 
            end 
            
            lastKeyPressed = nil
            lastAltKeyPressed = nil
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

