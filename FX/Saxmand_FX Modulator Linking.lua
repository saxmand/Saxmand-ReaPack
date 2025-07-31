-- @description FX Modulator Linking
-- @author Saxmand
-- @version 1.3.3
-- @provides
--   [effect] ../FX Modulator Linking/*.jsfx
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/*.jsfx
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/LFO (SNJUK2)/*.jsfx
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/LFO (SNJUK2)/*.jsfx-inc
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/MIDI Envelope Modulator (SNJUK2)/*.jsfx
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/MIDI Envelope Modulator (SNJUK2)/*.jsfx-inc
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/Steps Modulator (SNJUK2)/*.jsfx
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/Steps Modulator (SNJUK2)/*.jsfx-inc
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/Curve (SNJUK2)/*.jsfx
--   [effect] ../FX Modulator Linking/SNJUK2 Modulators/Curve (SNJUK2)/*.jsfx-inc
--   [effect] ../FX Modulator Linking/Curve Mapped Modulation/*.jsfx
--   [effect] ../FX Modulator Linking/Curve Mapped Modulation/*.jsfx-inc
--   Saxmand_FX Modulator Linking/Helpers/*.lua
--   Saxmand_FX Modulator Linking/Color sets/*.txt
-- @changelog
--   + added option to rename parameters

local version = "1.3.3"

local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*"..seperator..")")
local scriptPathSubfolder = scriptPath .. "Saxmand_FX Modulator Linking" .. seperator         

package.path = package.path .. ";" .. scriptPathSubfolder .. "Helpers/?.lua"

if not require("dependencies").main() then return end

local json = require("json")
local specialButtons = require("special_buttons")
local getFXList = require("get_fx_list").getFXList


package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3.3'
local stateName = "ModulationLinking"
local appName = "FX Modulator Linking"

local colorFolderName = "Color sets"
local settingsFolderName = "Exported Settings"
local pluginsFolderName = "Plugin Settings"

local ctx
font = reaper.ImGui_CreateFont('Arial', 14)
font1 = reaper.ImGui_CreateFont('Arial', 15)
font2 = reaper.ImGui_CreateFont('Arial', 17)
font8 = reaper.ImGui_CreateFont('Arial', 8)
font9 = reaper.ImGui_CreateFont('Arial', 9)
font10 = reaper.ImGui_CreateFont('Arial', 10)
font11 = reaper.ImGui_CreateFont('Arial', 11)
font12 = reaper.ImGui_CreateFont('Arial', 12)
font13 = reaper.ImGui_CreateFont('Arial', 13)
font14 = reaper.ImGui_CreateFont('Arial', 14)
font15 = reaper.ImGui_CreateFont('Arial', 15)
font16 = reaper.ImGui_CreateFont('Arial', 16)
font60 = reaper.ImGui_CreateFont('Arial', 60)

function initializeContext()
    ctx = ImGui.CreateContext(appName)
    -- imgui_font
    reaper.ImGui_Attach(ctx, font)
    reaper.ImGui_Attach(ctx, font1)
    reaper.ImGui_Attach(ctx, font2)
    reaper.ImGui_Attach(ctx, font8)
    reaper.ImGui_Attach(ctx, font9)
    reaper.ImGui_Attach(ctx, font10)
    reaper.ImGui_Attach(ctx, font11)
    reaper.ImGui_Attach(ctx, font12)
    reaper.ImGui_Attach(ctx, font13)
    reaper.ImGui_Attach(ctx, font14)
    reaper.ImGui_Attach(ctx, font15)
    reaper.ImGui_Attach(ctx, font16)
    reaper.ImGui_Attach(ctx, font60)
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
  -- Step 1: Insert space before capital letter, unless preceded by another capital
    local with_spaces = str:gsub("(%l)(%u)", "%1 %2")  -- word boundary
    -- Step 2: Trim and capitalize first character
    with_spaces = with_spaces:gsub("^%s*(%l)", string.upper)
    return with_spaces
end

local function saveFile(data, fileName, subfolder, save_path)  
    local target_dir
    if not save_path then
        target_dir = scriptPathSubfolder .. (subfolder and (subfolder .. seperator) or "")
        save_path = target_dir .. fileName .. ".txt"
    else
        target_dir = save_path:match("^(.*)[/\\][^/\\]+$")
    end
    -- Make sure subfolder exists (cross-platform)
    os.execute( (seperator == "/" and "mkdir -p \"" or "mkdir \"" ) .. target_dir .. "\"")
    
    -- Save a file
    local file = io.open(save_path, "w")
    if file then
      file:write(data)
      file:close()
    end
end

function readFile(fileName, subfolder, target_path) 
  if not fileName then return nil end
  if not target_path then
      local target_dir = scriptPathSubfolder .. (subfolder and (subfolder .. seperator) or "")
      target_path = target_dir .. fileName .. ".txt"
  end
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
    local target_dir = scriptPathSubfolder .. (subfolder and (subfolder .. seperator) or "")
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

function folder_exists(path)
  local ok, err, code = os.rename(path, path)
  return ok ~= nil or code == 13  -- 13 = permission denied (folder exists but not accessible)
end

-- Recursively delete a folder and its contents
function delete_folder_recursive(path)
  -- Delete files
  local i = 0
  while true do
    local file = reaper.EnumerateFiles(path, i)
    if not file then break end
    os.remove(path .. file)
    i = i + 1
  end

  -- Delete subfolders recursively
  local j = 0
  while true do
    local subdir = reaper.EnumerateSubdirectories(path, j)
    if not subdir then break end
    delete_folder_recursive(path .. subdir)
    j = j + 1
  end

  -- Delete the folder itself
  os.remove(path:gsub("\\", "/"))
end

function move_folder_contents(src, dest)
  -- Create destination if it doesn't exist
  reaper.RecursiveCreateDirectory(dest, 0)

  local i = 0
  while true do
    local file = reaper.EnumerateFiles(src, i)
    if not file then break end

    local src_file = src .. file
    local dest_file = dest .. file

    -- Rename (move) file
    os.rename(src_file, dest_file)

    i = i + 1
  end

--[[
  -- Optionally handle subdirectories too
  local j = 0
  while true do
    local subdir = reaper.EnumerateSubdirectories(src, j)
    if not subdir then break end

    local src_sub = src .. "/" .. subdir
    local dest_sub = dest .. "/" .. subdir

    move_folder_contents(src_sub, dest_sub) -- recursive
    os.remove(src_sub) -- try to remove the empty folder after move

    j = j + 1
  end
  ]]

  -- Remove original folder if empty
  os.remove(src:gsub("\\", "/"))
end

function get_files_in_folder(subfolder, nameAsKey) 
    target_dir = scriptPathSubfolder .. (subfolder and (subfolder .. seperator) or "")
    target_dir = target_dir:gsub("\\", "/")
    local names = {}
    local i = 0
    while true do 
        local file = reaper.EnumerateFiles(target_dir, i)
        if not file then break end
        if file:match(".txt") ~= nil then
            local name = file:match("(.+)%..+$") or file  -- remove extension
            if nameAsKey then
                names[name] = json.decodeFromJson(readFile(name, subfolder))
            else
                table.insert(names, name)
            end
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


-- new structure clean up of old folders. Can be deleted later
local previousColorFolder = scriptPath .. colorFolderName .. seperator
local previousHelpFolder = scriptPath .. "Helpers" .. seperator
local newColorFolder = scriptPathSubfolder .. colorFolderName .. seperator
if not folder_exists(newColorFolder) then 
    move_folder_contents(previousColorFolder, newColorFolder)
    if isApple then 
        delete_folder_recursive(newColorFolder)
        delete_folder_recursive(previousHelpFolder)
    end
end
----------------------


local _, lastTrackIndexTouched, lastItemIndexTouched, lastTakeIndexTouched, lastFxIndexTouched, lastParameterTouched = reaper.GetTouchedOrFocusedFX( 0 ) 
local fxWindowClicked, clickedHwnd, parameterFound, parameterChanged, focusDelta, projectStateOnRelease, projectStateOnClick, timeClick, fxWindowClickedParameterNotFound
local lastParameterTouchedMouse, lastFxIndexTouchedMouse, lastTrackIndexTouchedMouse 
local renameFxIndex = ""
local beginFxDragAndDropIndexRelease, beginFxDragAndDropName, beginFxDragAndDrop, HideToolTipTemp, beginFxDragAndDropFX 
local factoryModules, indentColors
local customPluginSettings

local fx_before, fx_after, firstBrowserHwnd, all_fx_last

local focusedTrackFXNames = {}
local parameterLinks-- = {}
local reloadParameterLinkCatch = true
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
local padding = margin
local minWidth
local trackSettings
local automation, isAutomationRead
local menuSliderWidth = 200

                        
local projectStateOnClick = 0
-- ADVANCED MAPPER
local selected_position_tab = nil 
local selected_selection_tab = nil 

            
local headerSizeW = 20
local headerSizeWM = headerSizeW - 1


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
colorBlackSemiTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 0.5)
colorAlmostBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.1, 1)
colorAlmostAlmostBlack = reaper.ImGui_ColorConvertDouble4ToU32(0.05, 0.05, 0.05, 1)
colorDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.2, 0.2, 0.2, 1)
colorLightDarkGrey = reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1)
colorLightDarkGreySemiTransparent = reaper.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 0.5)

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
    
    parameterContextShowMappings = false,
    parameterContextShowModulator = true,
    
    
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
    searchParameters = {}, 
    partsWidth = 188,
    floatingMapperParameterWidth = 188,
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
    showInsertOptionsWhenNoTrackIsSelected = false,
    
    preferHorizontalHeaders = false,
    
      -- Plugins 
    showPluginsList = true,
    showPluginsPanel = true,
    pluginsHeight = 400,
    pluginsWidth = 200,
    pluginsPanelWidthFixedSize = false,
    pluginsPanelWidth = 600,
    pluginsPanelHeight = 600,
    allow = 200,
    alwaysUsePluginsHeight = true,
    showPluginsListGlobal = true,
    showPluginsList = true,
    
    
    showContainers = true,
    colorContainers = true,
    indentsAmount = 3,
    identsType = false,
    allowHorizontalScroll = false,
    hidePluginTypeName = true,
    hideDeveloperName = true,
    showParallelIndicationInName = true,
    showPluginNumberInPluginOverview = true,
    showPluginNumberColumn = true,
    openPluginWhenClickingName = false,
    
    showOpenAll = false, 
    showAddTrackFX = true,
    showAddContainer = false,
    showAddTrackFXDirectly = true,
    showPluginOptionsOnTop = true,
    closeFxWindowAfterBeingAdded = false,
    
      -- Parameters
    PluginParameterColumnAmount = 1,
    
    showWetKnobOnPlugins = true,
    --useKnobsPlugin = false,
    --useNarrowPlugin = false,
    searchClearsOnlyMapped = false,
    showPluginsGlobal = true,
    showPlugins = true,
    showOnlyFocusedPlugin = true,
    showAddPluginsList = false,
    parametersHeight = 250,
    parametersWidth = 200,
    alwaysUseParametersHeight = true,
    showOnlyMappedAndSearchOnFocusedPlugin = true,
    showParametersOptionOnAllPlugins = true,
    showLastClicked = true,
    showParameterOptionsOnTop = true,
    --maxParametersShown = 0, 
    alignParameterKnobToTheRight = true,
    showBaselineInsteadOfModulatedValue = false,
    showValueOnNamePos = false,
    
    openMappingsPanelPos = "Right",
    openMappingsPanelPosFixedCoordinates = {}, -- not in settings
    
    midiNoteNamesMiddleC = 3,
    showMidiNoteNames = true,
    
    -- mapping general layout
    useKnobs = false,
    allowSliderVerticalDrag = false,
    changeKnobValueOnVerticalDrag = true,
    changeKnobValueOnHorizontalDrag = true,
    changeSliderValueOnVerticalDrag = false,
    changeSliderValueOnHorizontalDrag = true,
    heightOfSliderBackground = 5,
    showWidthInParameters = true,
    showWidthValueWhenChanging = true,
    showEnableAndBipolar = true,
    showMappedModulatorNameBelow = true, 
    showSeperationLineBeforeMappingName = true,
    alignModulatorMappingNameRight = true, 
    showEnvelopeIndicationInName = true,
    
    -- slider design
    bigSliderMoving = true,
    thicknessOfBigValueSlider = 4,
    thicknessOfSmallValueSlider = 1,
    
    thicknessOfBigValueKnob = 2,
    thicknessOfSmallValueKnob = 1,
    
    
    
    
    widthBetweenWidgets = 5,
      -- Modules 
    showModulatorsList = true, 
    modulesHeight = 250,
    modulesPopupHeight = 250,
    modulesWidth = 188,
    modulatorsWidthContext = 188,
    
    modulatorsPanelWidthFixedSize = false,
    modulatorsPanelWidth = 600,
    modulatorsPanelHeight = 600,
    
    showOnlyFocusedModulator = false,
    
    -- Modulators
    showAddModulatorsList = true,
    ModulatorParameterColumnAmount = 1,
    showModulatorsPanel = true,
    showModulatorsGlobal = true,
    showModulators = true,
    showOnlyFocusedModulators = true,
    modulatorsHeight = 250,
    modulatorsWidth = 188,
    addModulatorContainerToBeginningOfChain = true,
    showMapOnceModulator = true,
    showSortByNameModulator = true,
    sortAsType = false,
    mapOnce = false,
    
    showRemoveCrossModulator = true, 
    visualizerSize = 2,
    showAddModulatorButton = false,
    showAddModulatorButtonAfter = true,
    showAddModulatorButtonBefore = false,
    
    
    
    
    -- Experimental
    forceMapping = false,
    allowClickingParameterInFXWindowToChangeBaseline = true,
    makeItEasierToChangeParametersThatHasSteps = true,
    maxAmountOfStepsForStepSlider = 50,
    movementNeededToChangeStep = 5,
    scrollTimeRelease = 1000,
    
    -- Performance
    useParamCatch = true,
    useSemiStaticParamCatch = false,
    useStaticParamCatch = true,
    checkSemiStaticParamsEvery = 1000, 
    limitAmountOfDrawnParametersInPlugin = false,
    limitAmountOfDrawnParametersInPluginAmount = 100,
    filterParamterThatAreMostLikelyNotWanted = true,
    buildParamterFilterDataBase = true,
    limitParameterLinkLoading = true,
    
    -- floating mapper
      useFloatingMapper = false,
      keepWhenClickingInAppWindow = true,
      keepWhenClickingInOtherFxWindow = false,
      onlyKeepShowingWhenClickingFloatingWindow = false,
      openFloatingMapperRelativeToWindow = true,
      openFloatingMapperRelativeToWindowPos = 10,
      openFloatingMapperRelativeToMouse = false,
      openFloatingMapperRelativeToMousePos = {x= 50, y=50},
    -- envelopes  
      showEnvelope = false,
      hideEnvelopesIfLastTouched = true,
      hideEnvelopesWithNoPoints = true,
      hideEnvelopesWithPoints = false,
      showClickedInMediaLane = false,
      insertEnvelopeBeforeAddingNewEnvelopePoint = true,
      insertEnvelopePointsAtTimeSelection = true,
    
    usePreviousMapSettingsWhenOverwrittingMapping = true,
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
    
    --- ADVANCED FLOATING MAPPER
    initialMappedOverlaySize = 20, 
    
    --defaultDirection = 3,
    --defaultLFODirection = 2,
    
    --lastFocusedSettingsTab = "Layout",
    passAllUnusedShortcutThrough = false,
    allowPassingKeyboardShortcutsFromThisPage = true,
    
    
    dockIdVertical = {},
    
    
    colors = {
      backgroundWindow = colorDarkGrey,
      backgroundModules = colorAlmostAlmostBlack,  
      backgroundModulesBorder = colorGrey,  
      backgroundModulesHeader = colorDarkGrey,  
      backgroundWidgets = colorBlack,
      backgroundWidgetsBorder = colorGrey,
      backgroundWidgetsHeader = colorDarkGrey,
      
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
      
      sliderAreaBackground = colorAlmostAlmostBlack,
      sliderBackground = colorDarkGrey,
      sliderBackgroundHover = colorLightDarkGrey,
      sliderBaseline = colorBrightBlue,
      sliderOutput = colorWhite,
      sliderWidth = colorBlue,
      sliderWidthNegative = colorMap,
      
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
      modulators = colorBlue,
      plugins = colorGreen,
      
      containerLayer1 = colorRead, 
      containerLayer2 = colorTouch, 
      containerLayer3 = colorWrite,
    },
    selectedColorSet = "Dark",
    
    -- Key commands
    useVerticalScrollToScrollModulatorsHorizontally = false,
    onlyScrollVerticalHorizontalScrollWithModifier = false,
    onlyScrollVerticalHorizontalOnTopOrBottom = false,
    modifierEnablingScrollVerticalHorizontal = {["Super"] = true},
    
    modifierEnablingScrollVerticalVertical = {["Super"] = true},
    scrollingSpeedOfVerticalHorizontalScroll = 15,  
    
    scrollModulatorsHorizontalAnywhere = false,
    scrollingSpeedOfHorizontalScroll = 15,  
    
    fineAdjustAmount = 10,
    scrollValueSpeed = 50,
    scrollValueInverted = false,
    -- options for modifier keys
    modifierOptionsParameter = {
        scrollValue = {Alt = true},
        fineAdjust = {Shift = true},
        adjustWidth = {Ctrl = true},
        },
    modifierOptionsParameterClick = {
        changeBipolar = {Super = true}, 
        removeMapping = {Alt = true, Super = true, Ctrl = true}, 
        flipWidth = {Super = true, Shift = true}, 
        bypassMapping = {Alt = true}, 
        openCurve = {Ctrl = true}, 
        --setParameterValue = {Ctrl = true}, 
        resetValue = {Ctrl = true, Shift = true}, 
        closeColorSelectionOnClick = {Super = true},
    },
    modifierOptionFx = {
        copyFX = { Super = true},
        removeFX = { Alt = true},
        bypassFX = { Shift = true},
        offlineFX = { Super = true, Shift = true},
        renameFX = { Ctrl = true},
        openFolder = { Super = true},
        changeParallel = { Super = true, Alt = true},
        addFXAsLast = { Super = true},
    },
    modifierOptionsModulatorHeaderClick = {
        --removeMapping = {Alt = true, Super = true, Ctrl = true}, 
        --openPlugin = {Ctrl = true},  
    },
}

local defaultTrackSettings = {
    hideModules = false,
    hideParameters = false,
    showOnlyFocusedPlugin = true,
    showOnlyFocusedModulator = false,
    hidePluginSearchParameters = {},
    searchParameters = {},
    onlyMapped = {},
    focusedParam = {},
    hidePlugins = false,
    collabsModules = {},
    showMappings = {},
    renamed = {},
    bigWaveform = {},
    hideParametersFromModulator = {},
    showAbSliderMappings = {},
    containerColors = {},
    closeFolderVisually = {},
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

-- overwrite
settings.useParamCatch = true
settings.useSemiStaticParamCatch = false
--settings.useStaticParamCatch = false
settings.filterParamterThatAreMostLikelyNotWanted = true
settings.buildParamterFilterDataBase = true
--settings.limitParameterLinkLoading = true
settings.maxParametersShown = 0

-- for safety, as it was in there earlier as a table. Can remove at some point
if type(settings.onlyMapped) == "table" then
    settings.onlyMapped = false
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


local reaper_sections = {
    ["Main"] = 0,
    ["MIDI Editor"] = 32060,
    ["MIDI Event List Editor"] = 32061,
    ["MIDI Inline Editor"] = 32062,
    ["Media Explorer"] = 32063,
    ["MIDI Event Filter"] = 32064
}

local last_focused_reaper_section_name = "Main"
local last_focused_reaper_section_id = reaper_sections["Main"]

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
    section_id = last_focused_reaper_section_id or 0
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

function listeningForKeyCommand(addToPassthroughCommands)
    lastChar = getPressedShortcut()
    if lastChar then 
        -- TODO: Add multiple section_id's
        section_id = last_focused_reaper_section_id or 0
        action_id, n, stringName = GetCommandByShortcut(section_id, lastChar)
        if action_id then
          action_name = reaper.kbd_getTextFromCmd(action_id, section_id) 
          extensionName = reaper.ReverseNamedCommandLookup(action_id)
          local isExternal = false
          if extensionName and #extensionName > 0 then
              action_id = extensionName
              isExternal = true
          end
          
          scriptKeyPress = checkKeyPress() 
          commandTbl = {name = action_name, key = lastChar, scriptKeyPress = scriptKeyPress, command = action_id, external = isExternal, section_id = section_id}
          if scriptKeyPressed then
              
              if addToPassthroughCommands then
                  local addCommand = true
                  for index, info in ipairs(passThroughKeyCommands) do 
                      if info.name == action_name then 
                          addCommand = false
                      end
                  end
                  
                  if addCommand then 
                      table.insert(passThroughKeyCommands, commandTbl) 
                      reaper.SetExtState(stateName,"passThroughKeyCommands", json.encodeToJson(passThroughKeyCommands), true)
                  end 
              end  
          end
          lastChar = nil
        end 
        
        return commandTbl
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


function midi_status_to_text(byte1, byte2, doNotShowChan)
  local msg_type = byte1 & 0xF0
  local channel = (byte1 & 0x0F) + 1

  if msg_type == 0x80 then
    return "Note Off " .. byte2 .. (doNotShowChan and "" or ", Ch " .. channel)
  elseif msg_type == 0x90 then
    return "Note On " .. byte2 .. (doNotShowChan and "" or", Ch " .. channel)
  elseif msg_type == 0xA0 then
    return "Poly Aftertouch" .. byte2 .. (doNotShowChan and "" or ", Ch " .. channel)
  elseif msg_type == 0xB0 then
    return "CC" .. byte2 .. (doNotShowChan and "" or", Ch " .. channel)
  elseif msg_type == 0xC0 then
    return "Program Change" .. (doNotShowChan and "" or ", Ch " .. channel)
  elseif msg_type == 0xD0 then
    return "Channel Aftertouch" .. (doNotShowChan and "" or ", Ch " .. channel)
  elseif msg_type == 0xE0 then
    return "Pitchbend" .. (doNotShowChan and "" or ", Ch " .. channel)
  else
    return "Unknown MIDI Message (" .. byte1 .. ", " .. byte2 .. ")"
  end
end


local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

-- Map middle C name to octave offset
local middle_c_offsets = {
  C0 = -5, C1 = -4, C2 = -3, C3 = -2, C4 = -1, C5 = 0, C6 = 1
}
local middle_c_offsetsStr = {"C0", "C1", "C2", "C3", "C4","C5", "C6"}
local middle_c_offsetsVal = { -5, -4, -3, -2, -1, 0, 1}

function getNoteName(note_number, middle_c_val)
  local name = note_names[(note_number % 12) + 1]

  local base_octave = 4 -- default for C4 = MIDI 60
  local offset = middle_c_offsetsVal[middle_c_val] or -1
  local octave = math.floor(note_number / 12) + offset

  return name .. tostring(octave)
end



function getListOfFilesInResourceFolderIncludingSubFolders(folder, fileNameExtension)
    local function scan_folder(folder_path, file_list, base_path)
      local i = 0
      while true do
        local file = reaper.EnumerateFiles(folder_path, i)
        if not file then break end
        if file:match(fileNameExtension) then
            -- Extract first subfolder label
            local relative_path = folder_path:sub(#base_path + 2)
            local subfolder = relative_path:match("([^/\\]+)") or folder
            local fileName = file:gsub("%." .. fileNameExtension .. "$", "")
            
            table.insert(file_list, {
              name = fileName,
              path = folder_path .. "/" .. file,
              folder = subfolder,
              id = file,
            })
        end
    
        i = i + 1
      end
    
      local j = 0
      while true do
        local subfolder = reaper.EnumerateSubdirectories(folder_path, j)
        if not subfolder then break end
        local full_subfolder_path = folder_path .. "/" .. subfolder
        scan_folder(full_subfolder_path, file_list, base_path) -- recursive call
        j = j + 1
      end
    end
    
    -- Start from FXChains folder
    local resource_path = reaper.GetResourcePath()
    local fxchain_path = resource_path .. "/" .. folder 
    
    local all_files = {}
    scan_folder(fxchain_path, all_files, fxchain_path)
    return all_files
end

----- PRESETS AND TEMPLATES
------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------
------------- SEARCH -----------------
-- Helper function to split a string by a separator (comma or space)
function splitString(inputstr)
    local t = {}
    for str in string.gmatch(inputstr, "([^, ]+)") do
        table.insert(t, str)
    end
    return t
end

-- Helper function to check if all parts of the search string are found in the track name
function allPartsMatch(name, search_parts)
    name = name:lower()

    for _, part in ipairs(search_parts) do
        if not string.find(name, part:lower()) then
            return false
        end
    end
    return true
end

-- Helper function to match part of the string character by character
function partialMatch(name, search_parts)
    name = name:lower()
    local parts = splitString(name)
    local match = true
    
    for _, part in ipairs(search_parts) do  
        partMatch = false
        for _, p in ipairs(parts) do 
            local copy = p
            for i = 1, #part do
                local char = part:sub(i, i)
                local found = string.find(copy, char, 1, true)
                if found then
                    copy = copy:sub(found + 1)
                    if i == #part then 
                        partMatch = true
                        break
                    end
                else 
                  break
                end
            end
        end
        if not partMatch then 
            return false
        end
    end

    return true
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------

fxChainPresetsFiles = getListOfFilesInResourceFolderIncludingSubFolders("FXChains", "RfxChain")

trackTemplateFiles = getListOfFilesInResourceFolderIncludingSubFolders("TrackTemplates", "RTrackTemplate")

        
fxListFiles = getFXList()

function centerText(text, color, posX, width, offsetX, posY) 
    textSizeW = reaper.ImGui_CalcTextSize(ctx, text, 0,0) 
    reaper.ImGui_SetCursorPos(ctx, posX + width / 2 - textSizeW / 2, posY ) 
    reaper.ImGui_TextColored(ctx,color, text)
end


function sort_file_list(tbl, sort_key, ascending)
  table.sort(tbl, function(a, b)
    local valA = a[sort_key]
    local valB = b[sort_key]

    -- Handle nil values safely
    if valA == nil then return false end
    if valB == nil then return true end

    if ascending then
      return valA < valB
    else
      return valA > valB
    end
  end)
end


function insertFXOnSelectedTracks(file, track, index, rename)
    reaper.Undo_BeginBlock()
    if not track then  
        reaper.Main_OnCommand(40001, 0) --Track: Insert new track 
        track = reaper.GetSelectedTrack(0,0)
    end
    index = index and index +1 or 999
    reaper.TrackFX_AddByName(track, file.name,false,-1000 - index)
    if rename then
        reaper.GetSetMediaTrackInfo_String(track,"P_NAME",file.name,true)
    end
    
    reaper.Undo_EndBlock("Insert FX", -1)
end



function replace_fx_in_track(rpp_text, new_fx_block)
  local modified_rpp = {}
  local in_track = false
  local in_fxchain = false
  local buffer = {}
  local fxchain_start = false
  local bypass_found = false

  for line in rpp_text:gmatch("[^\r\n]+") do
    --if line:match("^<TRACK") then
    --  in_track = true
    --elseif in_track and line:match("^>") then
    --  in_track = false
    --end
      local fxChainAdded = false
    --if in_track then
      if line:match("^<FXCHAIN") then
          in_fxchain = true
          fxchain_start = true
          table.insert(buffer, line)
      elseif in_fxchain then
          if fxchain_start and line:match("^BYPASS") then
              -- Found BYPASS, start replacing until the closing >
              bypass_found = true
              table.insert(buffer, new_fx_block)
              fxchain_start = false
          elseif bypass_found then
              if line:match("^>") then
                  -- End of FXCHAIN
                  table.insert(buffer, line)
                  in_fxchain = false
                  bypass_found = false
                  fxchain_start = false
              end
              -- skip lines until we hit >
          else 
              if line:match("^>") then
                  -- No BYPASS found, insert new FX just before this line
                  table.insert(buffer, new_fx_block)
                  table.insert(buffer, line)
                  in_fxchain = false
                  fxchain_start = false
              else 
                  table.insert(buffer, line)
              end
          end
      else
          if line:match("^>") and not fxChainAdded then
              -- insert missing fx chain info and fx block
              table.insert(buffer, "<FXCHAIN")
              table.insert(buffer, "WNDRECT 32 654 724 393")
              table.insert(buffer, "SHOW 0")
              table.insert(buffer, "LASTSEL 0")
              table.insert(buffer, "DOCKED 0new_fx_block")
              table.insert(buffer, new_fx_block) 
              table.insert(buffer, ">")
          end 
          table.insert(buffer, line)
      end
    --else
    --  table.insert(buffer, line)
    --end
  end

  return table.concat(buffer, "\n")
end


function insertFXChainPresetOld(file) 
    local openFile = io.open(file.path, "r")
    local fx_chunk = openFile:read("*a")
    openFile:close() 
    
    reaper.Undo_BeginBlock()
    
    if newTrack then
        reaper.Main_OnCommand(40001, 0) --Track: Insert new track 
        local track = reaper.GetSelectedTrack(0,0)
        local _, chunk = reaper.GetTrackStateChunk(track, "", false) 
        local new_chunk = replace_fx_in_track(chunk, fx_chunk)
        reaper.SetTrackStateChunk(track, new_chunk, false) 
        reaper.GetSetMediaTrackInfo_String(track,"P_NAME",file.name,true)
    else
        for trackIndex, track in ipairs(selectedTracks) do
            local _, chunk = reaper.GetTrackStateChunk(track, "", false)
            local new_chunk = replace_fx_in_track(chunk, fx_chunk)
            reaper.SetTrackStateChunk(track, new_chunk, false) 
        end 
    end
    
    reaper.Undo_EndBlock("Load FX Chain", -1)
end


function insertFXChainPreset(file, track, index, rename)
    reaper.Undo_BeginBlock()
    if not track then  
        reaper.Main_OnCommand(40001, 0) --Track: Insert new track 
        track = reaper.GetSelectedTrack(0,0)
    end
    index = index and index+1 or 999
    reaper.TrackFX_AddByName(track, file.id,false,-1000 - index)
    if rename then
        reaper.GetSetMediaTrackInfo_String(track,"P_NAME",file.name,true)
    end
    
    reaper.Undo_EndBlock("Load FX Chain", -1)
end

function insertTrackTemplate(file, track)
    reaper.Undo_BeginBlock()
    
    -- Insert a new track at the bottom
    if not track and reaper.CountTracks(0) > 0 then
        track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        reaper.SetOnlyTrackSelected(track)
    end
    -- Select the new track
    
    -- Insert the template on the selected track
    reaper.Main_openProject(file.path) -- this inserts the track template
    
    
    reaper.Undo_EndBlock("Load Track Template", -1)
end

function tableWithFilterAndText(text, table, filterVariable, width, height, functionToDo, tableKeys, newTrack) 
    local startX, startY = reaper.ImGui_GetCursorPos(ctx)
    reaper.ImGui_BeginGroup(ctx)
    centerText(text, colorWhite, startX, width, 0, startY)
    local click = false
    --if reaper.ImGui_Button(ctx, text, width) then
    --    click = true
    --end
    reaper.ImGui_Spacing(ctx)
    
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), settings.colors.buttonsHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), settings.colors.buttonsActive)
    
    local offsetX, offsetY = reaper.ImGui_GetItemRectMax(ctx) 
    
    local flags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg() | reaper.ImGui_TableFlags_ScrollY() | 
    reaper.ImGui_TableFlags_Sortable() | reaper.ImGui_TableFlags_ScrollX() | reaper.ImGui_TableFlags_Resizable() -- | reaper.ImGui_TableFlags_SizingFixedFit()
    
    local filterTable = {}
    local count = 1
    for i, file in ipairs(table) do
        local include = true
        local allFields = ""
        for key, value in pairs(file) do 
            for _, tblKey in ipairs(tableKeys) do 
                if key == tblKey:lower() then
                    local fullFilter = filterVariable .. key
                    local filterParts = settings[fullFilter] and splitString(settings[fullFilter]:lower())
                    if filterParts and #filterParts > 0 and value then 
                        if not partialMatch(value, filterParts) then
                            include = false 
                        end
                    end
                    allFields = allFields .. value .. " "
                end 
            end
        end  
        
        local filterParts = settings[filterVariable] and splitString(settings[filterVariable]:lower())
        if filterParts and #filterParts > 0 and allFields then 
            if not partialMatch(allFields, filterParts) then
                include = false 
            end
        end
        
        if include then filterTable[#filterTable + 1] = file end 
    end
    
    local hasFilter =  settings[filterVariable] and #settings[filterVariable] > 0
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 0)
    reaper.ImGui_TextColored(ctx, colorGrey, "Filter all")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx,-52+ width + (hasFilter and -20 or 0) )
    local ret, filter = reaper.ImGui_InputText(ctx, "##" .. filterVariable, settings[filterVariable])
    if reaper.ImGui_IsItemFocused(ctx) then 
        ignoreKeypress = true
    end
    if settings[filterVariable] ~= filter then settings[filterVariable] = filter; saveSettings() end 
    if hasFilter then
        --reaper.ImGui_SameLine(ctx)
        --local closeX, closeY = reaper.ImGui_GetCursorPos(ctx)
        --if closeButton(closeX - 4, closeY, 13) then settings[filterVariable] = nil end 
    end
    reaper.ImGui_PopStyleVar(ctx)
    
    -- FX CHAINS
    if reaper.ImGui_BeginTable(ctx, text, #tableKeys, flags, width, height) then
        for i, name in ipairs(tableKeys) do
            reaper.ImGui_TableSetupColumn(ctx, name, i == 1 and reaper.ImGui_TableColumnFlags_DefaultSort() or  reaper.ImGui_TableColumnFlags_None(), 0) 
        end
        reaper.ImGui_TableSetupScrollFreeze(ctx, 1, 1) -- Make row always visible
        
        reaper.ImGui_TableNextRow(ctx, reaper.ImGui_TableRowFlags_Headers())
        for column = 0, #tableKeys-1 do
          reaper.ImGui_TableSetColumnIndex(ctx, column)
          local column_name = reaper.ImGui_TableGetColumnName(ctx, column) -- Retrieve name passed to TableSetupColumn()
          reaper.ImGui_PushID(ctx, column)
          reaper.ImGui_TableHeader(ctx, column_name)
          
          local offX = reaper.ImGui_CalcTextSize(ctx, column_name)
          if not settings.vertical then
              reaper.ImGui_SameLine(ctx, offX + padding, (reaper.ImGui_GetStyleVar(ctx, reaper.ImGui_StyleVar_ItemInnerSpacing())))
          end
          
          reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 0, 0)
          local fullFilter = filterVariable .. string.lower(column_name)
          
          if settings[fullFilter] and #settings[fullFilter] > 0 then
              
              --local closeX, closeY = reaper.ImGui_GetCursorPos(ctx)
              --if closeButton(closeX - 4, closeY, 13) then settings[fullFilter] = nil end 
              --reaper.ImGui_SameLine(ctx)
          end 
          
          local ret, filter = reaper.ImGui_InputText(ctx, "##" .. fullFilter, settings[fullFilter])
          if settings[fullFilter] ~= filter then settings[fullFilter] = filter; saveSettings() end 
          if reaper.ImGui_IsItemFocused(ctx) then 
              ignoreKeypress = true
          end
          
          reaper.ImGui_PopStyleVar(ctx)
          
          reaper.ImGui_PopID(ctx)
        end
        
        
        -- Sort our data if sort specs have been changed!
        if reaper.ImGui_TableNeedSort(ctx) then 
            local ok, col_idx, col_user_id, sort_direction = reaper.ImGui_TableGetColumnSortSpecs(ctx, 0) 
            --table.sort(table, CompareTableItems)
            local sortKey = tableKeys[col_user_id+1]:lower()
            sort_file_list(table, sortKey, sort_direction == 1)
        end
    
        for row, file in ipairs(filterTable) do
            reaper.ImGui_TableNextRow(ctx)
            for column = 0, #tableKeys-1 do
                reaper.ImGui_TableSetColumnIndex(ctx, column) 
                if reaper.ImGui_Button(ctx, file[tableKeys[column+1]:lower()]) then 
                    functionToDo(file, newTrack, nil, true) 
                end
            end
        end
        reaper.ImGui_EndTable(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx, 4)
    
    reaper.ImGui_EndGroup(ctx)
    return click
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

function threeDots()
    points, lastPos = textToPointsVertical("...", 0, 0, size, thickness)
end

local function insertAtStart(t, value)
  for i = #t, 1, -1 do
    t[i + 1] = t[i]
  end
  t[1] = value
end

-- Convert text into vertical drawing points with customizable alignment
-- THIS VERSION DOES CROPPING, 23-06-25
function textToPointsVertical(text, x, y, size, thickness, maxSize)
    local textPoints = {} 
    local points = {}
    
    local lastPos = 0
    for i = #text, 1, -1  do 
    --for i = 1, #text  do 
        local charPoints = {}
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
                
                table.insert(charPoints, {x1, y1, x2, y2})
            end 
            lastPos = offset + (largestVal) * size
        end
         
        table.insert(textPoints, charPoints)
    end
    
    if maxSize and lastPos > maxSize then 
        local dotPoints, sizeOfDots = textToPointsVertical("..", 0,0, size, thickness)  
        local firstPoint = maxSize
        for _, charPoints in ipairs(textPoints) do  
            local tempCharPoints = {}
            local includeChar = true
            for _, p in ipairs(charPoints) do  
                local largestPosInChar = math.max(p[2], p[4])
                if lastPos - largestPosInChar < maxSize - sizeOfDots  then
                    local offset = lastPos - maxSize
                    table.insert(tempCharPoints, {p[1], p[2] - offset, p[3], p[4] - offset}) 
                else
                    includeChar = false
                end
            end
            if includeChar then
                for _, p in ipairs(tempCharPoints) do  
                    -- we only add characters if they are within the max size
                    table.insert(points,p)
                    local smallestPosInChar = math.min(p[2], p[4])
                    -- we fidn the first pos every to use for aligning dots
                    if firstPoint > smallestPosInChar then 
                        firstPoint = smallestPosInChar - 4
                    end
                end
            end 
        end
        
        -- we add the dots 
        if firstPoint then
            for _, p in ipairs(dotPoints) do 
                table.insert(points, {p[1], firstPoint + p[2] - sizeOfDots , p[3], firstPoint + p[4] - sizeOfDots })
            end
        end
    else
        -- if the size of the text is not bigger than max size we just add all of the
        for _, charPoints in ipairs(textPoints) do 
            for _, p in ipairs(charPoints) do 
                table.insert(points, p)
            end
        end 
    end 
    
    
    
    for _, charPoints in ipairs(textPoints) do 
        for _, p in ipairs(charPoints) do 
  --          table.insert(points, {p[1], p[2], p[3], p[4]})
        end
    end
    
    return points, lastPos, isCropping    
end

-----------------
-- ACTIONS ------

---------------------------------------------------
-- Tools for analyzing performance ----------------
---------------------------------------------------

local paramsReadCount = 0
local paramsReadCountSemiStatic = 0
local paramsSetCount = 0
local last_paramTableCatch = {}
local paramTableCatch = {}
local guidTableCatch = {}


--[[
function GetFXGUID(track, index, doNotUseCatch)
    local tableStr = "GetFXGUID"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        paramsReadCount = paramsReadCount + 1
        local val = reaper.TrackFX_GetFXGUID(track, index)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end]]

-- Guid has it's own catch as we need this for every FX 
function GetFXGUID(track, index, doNotUseCatch)
    if not index or tonumber(index) == nil then return "" end 
    local catch = guidTableCatch[tostring(track) .. index]  
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        paramsReadCount = paramsReadCount + 1
        local val = reaper.TrackFX_GetFXGUID(track, index)  
        guidTableCatch[tostring(track) .. index] = val
        return val
    end 
end

function getFxIndexFromGuid(track, guid)
    local trackFx = getAllTrackFXOnTrack(track, true)
    for _, fx in ipairs(trackFx) do
        if fx.guid == guid then
            return fx.fxIndex
        end
    end
end

local listOfStaticParams = {
    "FXName",
    "ParamName",
    "ParameterStepSizes",
    "fx_name",
    "GetNumParams",
    "original_name", 
    "GetTrackGuid",
}

local listOfSemiStaticParams = {
    "renamed_name",
    "learn.midi1",
    "learn.midi2",
    "learn.osc", 
    "GetFXOffline",
    "GetFXEnabled",
    "GetEnabled", 
    "container_count",
}

function getStringForCatch(track, index)
    local guid = GetFXGUID(track, index)
    local str = tostring(track) .. ":" .. index ..  ":" ..tostring(guid) 
    return str
end

function getParameterTableCatch(track, index, tableStr, _type)
    if settings.useParamCatch and index then 
        local str = getStringForCatch(track, index) .. "::" .. tableStr
        
        -- we ensure the catch str is available
        --if not paramTableCatch[str] then 
        --    paramTableCatch[str] = {} 
        --end
        
        local wasAStaticValue = false
        -- we check for catched static. If the index has changed the guid and therefor "str" is not the same, and we will not catch it
        if settings.useStaticParamCatch and _type == 1 then
            --for _, staticName in ipairs(listOfStaticParams) do
            --    if tableStr:match(staticName) ~= nil then 
                    if last_paramTableCatch[str] ~= nil then 
                        --reaper.ShowConsoleMsg(tableStr .. "\n")
                        paramTableCatch[str] = last_paramTableCatch[str]
                        return paramTableCatch[str]
                    end
            --        wasAStaticValue = true
            --        break
            --    end
            --end
        end
        
        -- for semi static params we check every X ms or when triggered, for instance when renaming
        if settings.useSemiStaticParamCatch and not check_semi_static_params and _type == 2 then 
            
            --for _, staticName in ipairs(listOfSemiStaticParams) do
             --   if tableStr:match(staticName) ~= nil then 
                    if last_paramTableCatch[str] ~= nil then 
                        paramTableCatch[str] = last_paramTableCatch[str]
                        paramsReadCountSemiStatic = paramsReadCountSemiStatic + 1
                        return paramTableCatch[str]
                    end
             --   end
            --end
        end
        
        -- we know we will be reading the catch so we just count it here, cause I get a different result in the "catch == nil"
        if settings.useSemiStaticParamCatch and _type == 2 then
            --for _, staticName in ipairs(listOfSemiStaticParams) do
            --    if tableStr:match(staticName) ~= nil then
                    wasAStaticValue = true
                    paramsReadCountSemiStatic = paramsReadCountSemiStatic + 1
            --        return nil
            --    end
            --end
        end
        
        -- we try and get our regular catch
        local catch = paramTableCatch[str]
        
        -- if nothing is catched we count that we will be reading it, 
        if catch == nil then 
            -- but only if it's not semi static, as semi static has it's own counter
            if not wasAStaticValue then 
            --reaper.ShowConsoleMsg(tableStr .. "\n")
                paramsReadCount = paramsReadCount + 1
            end
        end
        
        return catch
    end
end

function setParameterTableCatch(track, index, tableStr, val)
    if index then 
        local str = getStringForCatch(track, index) .. "::" .. tableStr
        paramTableCatch[str] = val 
    end
end

function GetNamedConfigParm(track, index, str, doNotUseCatch, _type)
    if not index or not str then return end
    local tableStr = str .. "::GetNamedConfigParm"
    local catch = getParameterTableCatch(track, index, tableStr, _type)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return true, catch 
    else   
        --if index then
            local ret, val = reaper.TrackFX_GetNamedConfigParm(track, index, str)
            setParameterTableCatch(track, index, tableStr, val)
            return ret, val
        --end
    end
end

-- SHORT CUT FUNCTIONS

function getPlinkActive(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active'))) == 1 
end

function getModActive(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active'))) == 1
end

function getModBassline(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.baseline') ))
end

function getPlinkOffset(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.offset')))
end

function getPlinkScale(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale')))
end

function getPlinkParam(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.param' )))
end

function getPlinkMidiBus(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_bus' )))
end

function getPlinkMidiChan(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_chan' )))
end

local function getPlinkMidiMsg(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_msg' )))
end

local function getPlinkMidiMsg2(track,fxIndex,param)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_msg2' )))
end

function getPlinkParamInContainer(track,containerFxIndex,param, doNotUseCatch)
    return tonumber(select(2, GetNamedConfigParm( track, containerFxIndex, 'param.'..param..'.container_map.fx_parm', doNotUseCatch )))
end

function getFXParallelProcess(track,fxIndex,doNotGetStatus) -- 0=non, 1=process plug-in in parallel with previous, 2=process plug-in parallel and merge MIDI
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'parallel',doNotGetStatus )))
end

function getPlinkEffect(track,fxIndex, param)
    local val = select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.effect' ))
    if val == "" then
        return false 
    else
        return tonumber(val)
    end
end

function getRenamedFxName(track,fxIndex, doNotUseCatch)
    return select(2, GetNamedConfigParm( track, fxIndex, 'renamed_name', doNotUseCatch, 2))
end

function getOriginalFxName(track,fxIndex, doNotUseCatch)
    return select(2, GetNamedConfigParm( track, fxIndex, 'fx_name', doNotUseCatch, 1))
end



function getContainerCount(track,fxIndex, doNotUseCatch)
    return tonumber(select(2, GetNamedConfigParm( track, fxIndex, "container_count", doNotUseCatch, 2)))
end

function getPlinkFxIndex(track,containerFxIndex, parameterLinkEffect,doNotGetStatus)
    if parameterLinkEffect then
        local ret, val = GetNamedConfigParm( track, containerFxIndex, 'container_item.' .. parameterLinkEffect,doNotGetStatus)
        return ret and tonumber(val) or false
    end
end

function getPlinkFxIndexInContainer(track,containerFxIndex, param, doNotUseCatch)
    if param then
        local ret, val = GetNamedConfigParm( track, containerFxIndex, 'param.'..param..'.container_map.fx_index', doNotUseCatch )
        return ret and tonumber(val) or false
    end
end

function getPlinkParentContainer(track, fxIndex, doNotUseCatch)
    local ret, val = GetNamedConfigParm( track, fxIndex, "parent_container", doNotUseCatch, 1 )
    return ret and tonumber(val) or false
end

function fxSimpleName(title, force)
    if settings.hidePluginTypeName or force then
        title  = title:gsub("^[^:]+: ", "")
    end
    if settings.hideDeveloperName or force then
        title  = title:gsub("%s*%b()", "") 
    end

    return title
end

function GetFXName(track, index, doNotUseCatch)
    if not track or not index then return end
    local tableStr = "::GetFXName"
    local catch = getParameterTableCatch(track, index, tableStr, 1)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local ret, val = reaper.TrackFX_GetFXName(track, index) 
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end
end


function GetParamNameFromCustomSetting(track, index, param, version, doNotUseCatch)
    --if not customPluginSettings then doNotUseCatch = true end
    local tableStr = param .. "::GetParamNameCustom"..version
    local catch = getParameterTableCatch(track, index, tableStr, 1)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then  
        return catch 
    else  
        local fxName = GetFXName(track, index) 
        local simpleName = fxName and fxSimpleName(fxName, true) 
        --local currentStr = readFile(simpleName, pluginsFolderName) 
        --pluginObj = currentStr and json.decodeFromJson(currentStr) or {}
        
        if customPluginSettings and customPluginSettings[simpleName] and customPluginSettings[simpleName][param] and customPluginSettings[simpleName][param][version] then
            return customPluginSettings[simpleName][param][version]
        else
            local ret, val = reaper.TrackFX_GetParamName(track, index, param) 
            setParameterTableCatch(track, index, tableStr, val)
            return val
        end
    end 
end

function GetParamName(track, index, param, doNotUseCatch)
    local tableStr = param .. "::GetParamName"
    local catch = getParameterTableCatch(track, index, tableStr, 1)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local ret, val = reaper.TrackFX_GetParamName(track, index, param) 
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end   
end

function GetNumParams(track, index, doNotUseCatch)
    if not index then return -1 end
    local tableStr = "::GetNumParams"
    local catch = getParameterTableCatch(track, index, tableStr, 1)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetNumParams(track, index) 
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end


function GetParamNormalized(track, index, param, doNotUseCatch) 
    local tableStr = param .. "::GetParamNormalized"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetParamNormalized(track, index, param)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end

function GetParam(track, index, param, doNotUseCatch)
    local tableStr = param .. "::GetParam"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch.val, catch.min, catch.max
    else 
        local val, min, max = reaper.TrackFX_GetParam(track, index, param)  
        setParameterTableCatch(track, index, tableStr, {val = val, min = min, max = max})
        return val, min, max
    end  
end

function GetFormattedParamValue(track, index, param, doNotUseCatch)
    local tableStr = param .. "::GetFormattedParamValue"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local _, val = reaper.TrackFX_GetFormattedParamValue(track, index, param)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end

function FormatParamValue(track, index, param, val, doNotUseCatch)
    local tableStr = param .. "::FormatParamValue"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return true, catch 
    else 
        local ret, val = reaper.TrackFX_FormatParamValue(track, index, param, val)
        setParameterTableCatch(track, index, tableStr, val)
        return ret, val
    end  
end

function GetParameterStepSizes(track, index, param, doNotUseCatch)
    local tableStr = param .. "::GetParameterStepSizes"
    local catch = getParameterTableCatch(track, index, tableStr, 1)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch.hasSteps, catch.step, catch.smallStep, catch.largeStep, catch.isToggle
    else 
        local hasSteps, step, smallStep, largeStep, isToggle = reaper.TrackFX_GetParameterStepSizes(track, index, param)  
        setParameterTableCatch(track, index, tableStr, {hasSteps = hasSteps, step = step, smallStep = smallStep, largeStep = largeStep, isToggle = isToggle})
        return hasSteps, step, smallStep, largeStep, isToggle
    end 
end

function GetEnabled(track, index, doNotUseCatch)
    local tableStr = "::GetEnabled"
    local catch = getParameterTableCatch(track, index, tableStr, 2)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetEnabled(track, index)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end

function GetOpen(track, index, doNotUseCatch)
    local tableStr = "::GetOpen"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetOpen(track, index)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end

function GetFloatingWindow(track, index, doNotUseCatch)
    local tableStr = "::GetFloatingWindow"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetFloatingWindow(track, index)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end  
end

function GetChainVisible(track)
    local tableStr = "::GetChainVisible"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetChainVisible(track, index)  
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end 
end

function getFXWindowOpen(track)
    return GetChainVisible(track) ~= -1
end


function GetContainerPath(track, index, doNotUseCatch)
    local tableStr = "::GetContainerPath"
    local catch = getParameterTableCatch(track, index, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = get_container_path_from_fx_id(track, index, doNotUseCatch)
        setParameterTableCatch(track, index, tableStr, val)
        return val
    end  
end



function GetByName(track, str, instantiate, doNotUseCatch) 
    local tableStr = "::GetByName" 
    local catch = getParameterTableCatch(track, str, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetByName(track, str, instantiate)
        setParameterTableCatch(track, str, tableStr, val)
        return val
    end 
end


local paramterFilterDataBase = {}
local function filterParametersThatAreMostLikelyNotWanted(param, track, fxIndex, name)
    if not settings.filterParamterThatAreMostLikelyNotWanted then return true end
    
    local originalName = track and getOriginalFxName(track,fxIndex)
    originalName = originalName and originalName:gsub("^[^:]+: ", "")
    if settings.buildParamterFilterDataBase and originalName then
        -- hide plugin type
        -- hide developer
        --originalName = originalName:gsub("%s*%b()", "")
        
        if not paramterFilterDataBase[originalName] then 
            paramterFilterDataBase[originalName] = {}
        else
            if paramterFilterDataBase[originalName][param] ~= nil then
                return paramterFilterDataBase[originalName][param]
            end
        end
    end 
    
    local paramName = GetParamName(track,fxIndex,param)
    
    -- MAYBE THERE COULD BE ANOTHER METHOD.
    if not string.match(paramName, "^CC%d+") and 
    paramName:lower():match("midi cc") == nil and 
    paramName:lower() ~= "internal"  and 
    paramName:lower():match("(disabled)") == nil then -- and valueName ~= "-" then 
        if originalName and paramterFilterDataBase[originalName] then paramterFilterDataBase[originalName][param] = true end
        return true
    else
        if originalName and paramterFilterDataBase[originalName] then paramterFilterDataBase[originalName][param] = false end
        return false
    end
end

function getFxParamsThatAreNotFiltered(track, fxIndex, doNotUseCatch) 
    local tbl = {}
    local param_count = GetNumParams(track, fxIndex, doNotUseCatch)
    for param = 0, param_count - 1 do 
        if param == param_count - 3 then
            -- we don't want the bypass knob as part of the parameters
        elseif param == param_count - 2 then 
            -- we don't want the wet param as part of the parameters
        elseif param == param_count - 1 then
            -- we don't want the delta param as part of the parameters
        else
            if filterParametersThatAreMostLikelyNotWanted(param, track, fxIndex) then
                --if #tbl < 100 then
                    table.insert(tbl, param)
                --else
                --    return tbl
                --end
            end
        end
    end
    return tbl 
end



--- ENVELOPES


function GetFXEnvelope(track,fxIndex,param, doNotUseCatch)
    local tableStr = param .. "::GetFXEnvelope"
    local catch = getParameterTableCatch(track, fxIndex, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.GetFXEnvelope(track,fxIndex,param,false) 
        setParameterTableCatch(track, fxIndex, tableStr, val)
        return val
    end 
end

function GetEnvelopeInfo_String(track,fxIndex, param, str)
    local tableStr = param .. ":" .. str .. "::GetEnvelopeInfo_String"
    local catch = getParameterTableCatch(track, fxIndex, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else  
        local envelope = GetFXEnvelope(track,fxIndex,param)
        local ret, val = reaper.GetSetEnvelopeInfo_String(envelope, str, "", false)
        setParameterTableCatch(track, fxIndex, tableStr, val)
        return val
    end
end

function CountEnvelopePoints(track,fxIndex,param) 
    local tableStr = param .. "::CountEnvelopePoints"
    local catch = getParameterTableCatch(track, fxIndex, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local envelope = GetFXEnvelope(track,fxIndex,param)
        local val = reaper.CountEnvelopePoints(envelope) 
        setParameterTableCatch(track, fxIndex, tableStr, val)
        return val
    end 
end

function Envelope_Evaluate( envelope, time, sampleRate,samplesRequest)
    local retval, envelopeValueAtPos, dVdS, ddVdS, dddVdS = reaper.Envelope_Evaluate(envelope, time,sampleRate,samplesRequest)
    if retval then
        return envelopeValueAtPos, dVdS, ddVdS, dddVdS 
    end
end

function getEnvelopeValueAndPos(track,fxIndex,param, time)
    local tableStr = param .. "::EnvelopeValueAndPos"
    local catch = getParameterTableCatch(track, fxIndex, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local envelope = GetFXEnvelope(track,fxIndex,param)
        local val = Envelope_Evaluate(envelope, time, 0,0)
        setParameterTableCatch(track, fxIndex, tableStr, val)
        return val
    end 
end


function GetEnvelopePoint(track,fxIndex,param, ptidx, doNotUseCatch)
    local tableStr = param .. ":" .. ptidx .. "::EnvelopeValueAndPos"
    local catch = getParameterTableCatch(track, fxIndex, tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch.time, catch.value 
    else 
        local envelope = GetFXEnvelope(track,fxIndex,param)
        local ret, time, value = reaper.GetEnvelopePoint(envelope, ptidx)
        setParameterTableCatch(track, fxIndex, tableStr, {time, value})
        return time, value
    end 
end

function envelopeIsVisible(track,fxIndex,param)
    return tonumber(GetEnvelopeInfo_String(track,fxIndex,param, "VISIBLE")) == 1
end

function envelopeIsActive(track,fxIndex,param) 
    return tonumber(GetEnvelopeInfo_String(track,fxIndex,param, "ACTIVE")) == 1
end

function envelopeIsArmed(track,fxIndex,param)
    return tonumber(GetEnvelopeInfo_String(track,fxIndex,param, "ARM")) == 1
end

function envelopeIsInLane(track,fxIndex,param)
    return tonumber(GetEnvelopeInfo_String(track,fxIndex,param, "SHOWLANE")) == 1
end

function getEnvelopeState(track,fxIndex,param) 
    if track and fxIndex and param then
        return {visible = envelopeIsVisible(track,fxIndex,param), active = envelopeIsActive(track,fxIndex,param), arm = envelopeIsArmed(track,fxIndex,param), envelopeIsInLane(track,fxIndex,param)}
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

------- FX
    
function GetFXEnabled(track, fxIndex)
    local tableStr = "::GetFXEnabled"
    local catch = getParameterTableCatch(track, fxIndex, tableStr, 2)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else  
        local val = reaper.TrackFX_GetEnabled(track, fxIndex)
        setParameterTableCatch(track, fxIndex, tableStr, val)
        return val
    end
end
 
function GetFXOffline(track, fxIndex)
    local tableStr = "::GetFXOffline"
    local catch = getParameterTableCatch(track, fxIndex, tableStr, 2)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetOffline(track, fxIndex)
        setParameterTableCatch(track, fxIndex, tableStr, val)
        return val
    end
end
-------- track


function GetCount(track, doNotUseCatch)
    local tableStr = "::GetCount"
    local catch = getParameterTableCatch(track, "track", tableStr)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.TrackFX_GetCount(track) 
        setParameterTableCatch(track, "track", tableStr, val)
        return val
    end 
end


function GetTrackGuid(track, doNotUseCatch)
    local tableStr = "::GetTrackGuid"
    local catch = getParameterTableCatch(track, "track", tableStr, 1)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = reaper.GetTrackGUID(track) 
        setParameterTableCatch(track, "track", tableStr, val)
        return val
    end 
end
 
function GetMuted(track)
    local tableStr = "::GetMuted"
    local catch = getParameterTableCatch(track, "track", tableStr, 2)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch 
    else 
        local val = math.floor(reaper.GetMediaTrackInfo_Value( track, "B_MUTE" )) == 1
        setParameterTableCatch(track, "track", tableStr, val)
        return val
    end
end

function setMuted(track, val)
    val = val == nil and not GetMuted(track) or val
    reaper.SetMediaTrackInfo_Value( track, "B_MUTE", val and 1 or 0)
end
-------------------------
-------------------------
---- SET ----------------

function SetNamedConfigParm(track, index, str, val)
    paramsSetCount = paramsSetCount + 1
    if track and index and str and val then
        return reaper.TrackFX_SetNamedConfigParm(track, index, str, val)
    end
end

function SetOpen(track, index, open, inWindow)
    paramsSetCount = paramsSetCount + 1
    if track and index and open ~= nil then
        return reaper.TrackFX_Show(track, index, open and (inWindow and 1 or 3) or (inWindow and 0 or 2))--reaper.TrackFX_SetOpen(track, index, open)
    end
end

function fxShow(track, index, showFlag)
    paramsSetCount = paramsSetCount + 1
    if track and index and open then
        return reaper.TrackFX_Show(track, index, showFlag)
    end
end


function SetParam(track, index, param, val)
    paramsSetCount = paramsSetCount + 1
    if track and index and param and val then
        return reaper.TrackFX_SetParam(track, index, param, val)
    end
end

function SetParamNormalized(track, index, param, val)
    paramsSetCount = paramsSetCount + 1
    if track and index and param and val then
        return reaper.TrackFX_SetParamNormalized(track, index, param, val)
    end
end

-- SHORT CUT FUNCTIONS

function setPlinkMidiBus(track,fxIndex,param, val)
    return SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_bus', val )
end

function setPlinkMidiChan(track,fxIndex,param, val)
    return SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_chan', val )
end

local function setPlinkMidiMsg(track,fxIndex,param, val)
    return SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_msg', val )
end

local function setPlinkMidiMsg2(track,fxIndex,param, val)
    return SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.midi_msg2', val )
end

function setPlinkEffect(track,fxIndex, param, val)
    SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.effect', val) 
end

function setPlinkActive(track,fxIndex, param, val)
    SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active', val and "1" or "0") 
end

function setPlinkScale(track,fxIndex, param, val)
    SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale', val) 
end

function setPlinkOffset(track,fxIndex, param, val)
    SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.offset', val) 
end

function setModActive(track,fxIndex, param, val)
    SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', val and "1" or "0") 
end

function setFXParallelProcess(track,fxIndex)
    local parallel = getFXParallelProcess(track,fxIndex)
    local newValue = parallel == 0 and 1 or (parallel == 1 and 2 or 0)
    SetNamedConfigParm( track, fxIndex, 'parallel', newValue) 
end

----- Others
function showFX(track, fxIndex, show)
    return reaper.TrackFX_Show(track, fxIndex, show)
end

function DeleteFX(track, fxIndex)
    mapModulatorActivate(nil)
    reloadParameterLinkCatch = true
    check_semi_static_params = true
    reloadSelector = true
    return reaper.TrackFX_Delete(track, fxIndex)
end

function AddByNameFX(track, fxname, recFX, instantiate)
    return reaper.TrackFX_AddByName(track, fxname, recFX, instantiate)
end

function CopyToTrackFX(src_track, src_fx, dest_track, dest_fx, move)
    reloadSelector = true
    reloadParameterLinkCatch = true
    check_semi_static_params = true
    return reaper.TrackFX_CopyToTrack(src_track, src_fx, dest_track, dest_fx, move)
end

                                    
function BypassFX(track, fxIndex)  
    reaper.TrackFX_SetEnabled(track, fxIndex, not GetFXEnabled(track, fxIndex))
end
                              
function OfflineFX(track, fxIndex)  
    reaper.TrackFX_SetOffline(track, fxIndex, not GetFXOffline(track, fxIndex))
end

function openCloseFolder(track, fxIndex)
    guid = GetFXGUID(track,fxIndex)
    if not trackSettings.closeFolderVisually then trackSettings.closeFolderVisually = {} end
    trackSettings.closeFolderVisually[guid] = not trackSettings.closeFolderVisually[guid]
    saveTrackSettings(track)
end

function getFxFloatAuto()
    local val = reaper.SNM_GetIntConfigVar("fxfloat_focus", -1)
    local isSet = val & 4 == 4
    return isSet
end

function toggleFxFloatAuto()
    local val = reaper.SNM_GetIntConfigVar("fxfloat_focus", -1)
    local isSet = val & 4 == 4
    reaper.SNM_SetIntConfigVar("fxfloat_focus", val + (isSet and -4 or 4))
end    

function setFxFloatAutoToTrue()
    local isFxOpen = track and getFXWindowOpen(track)
    
    if not getFxFloatAuto() and not isFxOpen then
        toggleFxFloatAuto()
        return false
    else
        return true
    end
end


-- Avarage update for params read count
local time = reaper.time_precise()
local last_time = time
local elapsed = 0
local times = {}
local sample_size = 20
local scriptPerformanceText = ""
function update_avg(elapsed)
    table.insert(times, elapsed)
    if #times > sample_size then table.remove(times, 1) end 
    local sum = 0
    for i = 1, #times do sum = sum + times[i] end
    return #times == sample_size and sum / #times or 0
end

---------------------------------------------------
---------------------------------------------------



-------------------------------------------
----------CONTAINER FUNCTIONS--------------
-------------------------------------------

function get_fx_id_from_container_path(tr, idx1, ...) -- returns a fx-address from a list of 1-based IDs
  local sc,rv = GetCount(tr, true)+1, 0x2000000 + idx1
  for i,v in ipairs({...}) do
    local ccok, cc = reaper.TrackFX_GetNamedConfigParm(tr, rv, 'container_count')
    if ccok ~= true then return nil end
    rv = rv + sc * v
    sc = sc * (1+tonumber(cc))
  end
  return rv
end

function get_container_path_from_fx_id(tr, fxidx, doNotUseCatch) -- returns a list of 1-based IDs from a fx-address
  if fxidx & 0x2000000 then
    local ret = { }
    local n = GetCount(tr, doNotUseCatch)
    local curidx = (fxidx - 0x2000000) % (n+1)
    local remain = math.floor((fxidx - 0x2000000) / (n+1))
    if curidx < 1 then return nil end -- bad address

    local addr, addr_sc = curidx + 0x2000000, n + 1
    while true do
      local ccok, cc = reaper.TrackFX_GetNamedConfigParm(tr, addr, 'container_count') -- getContainerCount(tr, addr)--
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
  local path = get_container_path_from_fx_id(tr, fxidx, true)
  if not path then return nil end
  local rootContainerPos = #path > 1 and path[1] - 1 or false
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
      SetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_index",r),tostring(fxidx - 1))
      SetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_parm",r),tostring(parmidx))
      parmidx = r
    end
  end
  return rootContainerPos, parmidx
end


function fx_get_mapped_parameter(tr, fxidx, parmidx) -- gets a parameter at the top level parent, returns { fxidx, parmidx }
  local path = get_container_path_from_fx_id(tr, fxidx)
  if not path then return nil end
  local rootContainerPos = #path > 1 and path[1] - 1 or false
  while #path > 1 do
    fxidx = path[#path]
    table.remove(path)
    local cidx = get_fx_id_from_container_path(tr,table.unpack(path))
    if cidx == nil then return nil end
    local i, found = 0, nil
    while true do
      
      local r = getPlinkFxIndexInContainer(tr, cidx, i)--reaper.TrackFX_GetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_index",i))
      if not r then break end
      if tonumber(r) == fxidx - 1 then
        r = getPlinkParamInContainer(tr, cidx, i) -- reaper.TrackFX_GetNamedConfigParm(tr,cidx,string.format("param.%d.container_map.fx_parm",i))
        if not r then break end
        if tonumber(r) == parmidx then found = true; parmidx = i; break end
      end
      i = i + 1
    end
    if not found then
      return false, false
        -- add a new mapping
        --local rok, r = reaper.TrackFX_GetNamedConfigParm(tr,cidx,"container_map.add")
        --if not rok then return nil end
        --r = tonumber(r)
        --parmidx = r
    end
  end
  return rootContainerPos, parmidx
end

function fx_get_mapped_parameter_with_catch(track, fxIndex, param, doNotUseCatch)
    local tableStr = param .. "::fx_get_mapped_parameter"
    local catch = getParameterTableCatch(track, fxIndex, tableStr, 2)
    if settings.useParamCatch and not doNotUseCatch and catch ~= nil then 
        return catch.rootContainerPos, catch.parmidx
    else 
        local rootContainerPos, parmidx = fx_get_mapped_parameter(track, fxIndex, param)
        setParameterTableCatch(track, fxIndex, tableStr, {rootContainerPos = rootContainerPos, parmidx = parmidx})
        return rootContainerPos, parmidx
    end
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


function renameModulatorNames(track, modulationContainerPos)
    local fxAmount = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_count', true)))
    if not fxAmount then return end
    if fxAmount == 0 then
        --DeleteFX(track, modulationContainerPos)
    end 
    
    function goTroughNames(counterArray, savedArray)
        for c = 0, fxAmount -1 do  
            local fxIndex = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c, true)))            
            local renamed, fxName = GetNamedConfigParm(track, fxIndex, 'renamed_name', true)
            local nameWithoutNumber = fxName:gsub(" %[%d+%]$", "")
            if not renamed or fxName == "" then
                nameWithoutNumber = GetFXName(track,fxIndex, true)
            end
            idCounter = "_" .. nameWithoutNumber -- enables to use modules starting with a number
            if not counterArray[idCounter] then 
                counterArray[idCounter] = 1
            else
                counterArray[idCounter] = counterArray[idCounter] + 1
            end
            if savedArray then
                SetNamedConfigParm( track, fxIndex, 'renamed_name',  nameWithoutNumber .. (savedArray[idCounter] > 1 and " [" .. counterArray[idCounter] .. "]" or "") )
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
    local fxAmount = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_count')))
    local nameCount = 0
    for c = 0, fxAmount -1 do  
        local fxIndex = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c)))
        local fxName = getOriginalFxName(track,fxIndex)
        if fxName:match(name) then
            nameCount = nameCount + 1
        end
    end
    return returnName and (name .. " " .. nameCount) or nameCount
end


function getModulationContainerPos(track)
    if track then
        local modulatorsPos = GetByName( track, "Modulators", false )
        if modulatorsPos ~= -1 then
            return modulatorsPos
        end
    end
    return false
end

function moveFx(track, oldIndex, newIndex)
    if track and oldIndex and newIndex then
        reaper.TrackFX_CopyToTrack(track, oldIndex, track, newIndex, true)
    end
end

function getPositionAfterFxIndex(track, fxIndex) 
    local isContainer = GetNamedConfigParm( track, fxIndex, "container_count", true)
    if fxIndex > 0x2000000 then 
        local path = get_container_path_from_fx_id(track, fxIndex, true)
        
        for i, p in ipairs(path) do 
            path[i] = p + 1
        end
        if isContainer then
            --path[#path + 1] = 1
        end
        local newIndex = get_fx_id_from_container_path(track, table.unpack(path)) 
        return newIndex
    else
        if isContainer then
            local newFxIndex = get_fx_id_from_container_path(track, fxIndex + 1, 1) 
            return newFxIndex 
        else
            return fxIndex + 1
        end
    end
end

function getPathForNextFxIndex(track, fxIndex, notInsideContainer) 
    if not fxIndex or not track then return false end
    local isContainer = not notInsideContainer and GetNamedConfigParm( track, fxIndex, "container_count", true) or false
    if fxIndex > 0x2000000 then 
        local path = get_container_path_from_fx_id(track, fxIndex, true)
        if not path then return false end
        for i, p in ipairs(path) do 
            --path[i] = p + 1
        end
        --path[1] = path[1] + 1
        if isContainer then
            path[#path + 1] = 1
        else
            path[#path] = path[#path] + 1
        end 
        return path
    else
        if isContainer then
            return {fxIndex + 1, 1}
        else
            return {fxIndex + 1} -- for some reason it needs to be two to get on the other side of the selected
        end
    end
end

function moveFxIfNeeded(pathForNextIndex, oldIndex)
    if pathForNextIndex and #pathForNextIndex > 1 then 
        local newIndex = get_fx_id_from_container_path(track, table.unpack(pathForNextIndex)) 
        moveFx(track, oldIndex, newIndex) 
        return get_fx_id_from_container_path(track, table.unpack(pathForNextIndex)) 
    else
        return oldIndex
    end
end

function addFxAfterSelection(track, fxIndex, fxName, notInsideContainer)  
    local pathForNextIndex = not isAddFXAsLast and getPathForNextFxIndex(track, fxIndex, notInsideContainer) or false
    local addIndex = (pathForNextIndex and #pathForNextIndex < 2) and pathForNextIndex[1] or 999
    local wasSetToFloatingAuto = setFxFloatAutoToTrue()
    local newFxIndex = reaper.TrackFX_AddByName( track, fxName, false, -1000 - addIndex) 
    newFxIndex = moveFxIfNeeded(pathForNextIndex, newFxIndex)
    if not wasSetToFloatingAuto then toggleFxFloatAuto() end
    return newFxIndex
end



-- add container and move it to the first slot and rename to modulators
function addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local modulatorsPos = GetByName( track, "Modulators", false, true )
    local modulatorContainerExist = true
    if modulatorsPos == -1 then
        --modulatorsPos = GetByName( track, "Container", true )
        
        modulatorsPos = addFxAfterSelection(track, settings.addModulatorContainerToBeginningOfChain and -1 or 999, "Container", true)
        
        --modulatorsPos = TrackFX_AddByName( track, "Container", modulatorsPos, -1 ) 
        rename = SetNamedConfigParm( track, modulatorsPos, 'renamed_name', "Modulators" )
        modulatorContainerExist = false
    end
    return modulatorsPos, modulatorContainerExist
end

function deleteModule(track, fxIndex, modulationContainerPos, fx)
    if fxIndex then 
        if mapActiveFxIndex == fxIndex then 
            stopMapping()
        end
        
        local mappings = (parameterLinks and parameterLinks[fxIndex]) and parameterLinks[fxIndex] or {} 
        for i, map in ipairs(mappings) do  
            local mapFxIndex = map.fxIndex
            local mapParam = map.param
            disableParameterLink(track, mapFxIndex, mapParam) 
        end
        
        
        local guid = GetFXGUID( track, fxIndex )
        if trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[guid] then 
            trackSettings.hideParametersFromModulator[guid] = nil
        end
        
        if DeleteFX(track, fxIndex) then
            selectedModule = false
            renameModulatorNames(track, modulationContainerPos)
        end
    end
end

function stopMapping()
    mapActiveFxIndex = false
    mapActiveParam = false
end

function mapModulatorActivate(fx, mapParam, name, fromKeycommand, simple)
    reloadParameterLinkCatch = true
    -- used for visulizer size. Should be it's own action probably
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
        
        if newVal and newVal > 3 then newVal = 0 end
        trackSettings.bigWaveform[fx.guid] = newVal
        saveTrackSettings(track) 
    else
        if not fx or (mapActiveFxIndex == fx.fxIndex and mapActiveParam == mapParam) then 
            stopMapping()
        else  
            
            --parameterTouched = nil
            lastParameterTouched = nil
            --fxIndexTouched = nil
            lastFxIndexTouched = nil
            hideParametersFromModulator = nil
            mapActiveFxIndex = fx.fxIndex
            mapActiveName = simple and fx.name or fx.mappingNames[mapParam]
            mapActiveParam = mapParam
            fxContainerIndex = fx.fxInContainerIndex 
        end
    end
end

function renameModule(track, modulationContainerPos, fxIndex, newName) 
    SetNamedConfigParm( track, fxIndex, 'renamed_name',  newName)
    if modulationContainerPos then
        renameModulatorNames(track, modulationContainerPos)
    end
end

--[[
function insertLfoFxAndAddContainerMapping(track)
    reaper.Undo_BeginBlock()
    local modulatorsPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = select(2, GetNamedConfigParm(track, modulatorsPos, 'container_count')) + 1
    local parent_FX_count = GetCount(track)
    local position_of_container = modulatorsPos+1
    
     insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
     lfo_param = AddByNameFX( track, 'LFO Modulator', false, insert_position )
     ret, rename = SetNamedConfigParm( track, insert_position, 'renamed_name', "LFO " .. (lfo_param + 1) )
     
     if fxnumber < 0x2000000 then
        ret, outputPos = GetNamedConfigParm( track, modulatorsPos, 'container_map.add.'..tostring(lfo_param)..'.1' )
     else
        outputPos = 1
     end 
     SetOpen(track,fxnumber,true)
     
     
     reaper.Undo_EndBlock("Add modulator plugin",-1)
     return outputPos
end
]]

function insertContainerAddPluginAndRename(track, name, newName)
    reaper.Undo_BeginBlock() 
    local modulationContainerPos,modulationContainerExist = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_count', true)))
    --if position_of_FX_in_container == 0 then position_of_FX_in_container = 1 end
    local parent_FX_count = GetCount(track) + 1
    local position_of_container = modulationContainerPos + 1
    
    local insert_position = get_fx_id_from_container_path(track, modulationContainerPos + 1, position_of_FX_in_container + 1)--
    
    -- not sure why this fix is needed but it seems to work when there were no container
    --if position_of_FX_in_container == 0 and not modulationContainerExist then insert_position = insert_position + 1 end
    
    local fxPosition = AddByNameFX( track, name, false, insert_position )
    SetNamedConfigParm( track, insert_position, 'renamed_name', newName)--getModulatorModulesNameCount(track, modulationContainerPos, newName, true) )
    
    local fxAmount = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_count', true)))
    -- 
    --if fxAmount > 1 then
        renameModulatorNames(track, modulationContainerPos)
    --end
    --[[if not paramNumber then paramNumber = 1 end
    if fxnumber < 0x2000000 then
       ret, outputPos = GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..tostring(fxPosition)..'.' .. paramNumber )
    else
       outputPos = paramNumber
    end ]]
    return modulationContainerPos, insert_position
end


function insertLocalLfoFxAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'JS: LFO Native Modulator', "LFO Native")
    
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.active', 1)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.lfo.dir', 0)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertACSAndAddContainerMapping(track)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, 'JS: ACS Native Modulator', "ACS Native")
    
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.active', 1)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.baseline', 0.5)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.active', 1)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dir', 0)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dblo', -60)
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.dbhi', 12)
    
    local value = settings.defaultAcsTrackAudioChannelInput
    if value < 4 then
        SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.' .. "acs.chan", value)   
    else
        SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.' .. "acs.chan", value == 4 and 0 or 2)
    end 
    SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.' .. "acs.stereo", value < 4 and 0 or 1)
    
    --SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.chan', 2)
    --SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.acs.stereo', 1)
    
    --SetNamedConfigParm( track, insert_position, 'param.'.."1"..'.mod.visible', 1)
    
    SetNamedConfigParm( track, modulationContainerPos, 'container_nch', 4)
    SetNamedConfigParm( track, modulationContainerPos, 'container_nch_in', 4)
    --SetOpen(track,fxnumber,true)
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertFXAndAddContainerMapping(track, name, newName)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, name, newName)
    -- I think we do not want to open the "original", as it opens the fx randomly on add
    --SetOpen(track,fxnumber,true) -- return to original focus 
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function insertGenericParamFXAndAddContainerMapping(track, fxIndex, newName, paramNumber, fxInContainerIndex)
    modulationContainerPos, insert_position = insertContainerAddPluginAndRename(track, "Generic Parameter Modulator", newName)
    
    SetOpen(track,fxnumber,true) -- return to original focus 
    p = 1
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.mod.active',1 )
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.mod.baseline', 0 )
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.active',1 )
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.offset',0 )
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.scale',1 )
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.effect',fxInContainerIndex ) -- skal nok være relativ i container
    SetNamedConfigParm( track, insert_position, 'param.'.. p ..'.plink.param', paramNumber )
    
    reaper.Undo_EndBlock("Add modulator plugin",-1)
    return modulationContainerPos, insert_position
end

function movePluginToContainer(track, originalIndex)
    local modulationContainerPos = addContainerAndRenameToModulatorsOrGetModulatorsPos(track)
    local position_of_FX_in_container = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_count', true))) + 1
    local parent_FX_count = GetCount(track, true)
    local position_of_container = modulationContainerPos+1
    
    local insert_position = 0x2000000 + position_of_FX_in_container * (parent_FX_count + 1) + position_of_container
    
    CopyToTrackFX(track, originalIndex, track, insert_position, true)
    
    
    
    return modulationContainerPos, insert_position
end

function getModulatorInfo(track, fxIndex, doNotUseCatch)
    local fxOriginalName = getOriginalFxName(track,fxIndex,doNotUseCatch)--GetNamedConfigParm(track, fxIndex, 'original_name', doNotUseCatch)
    local isCurver = fxOriginalName == "JS: Curve Mapped Modulation"
    
    
    
    -- not needed here.
    local curveName, curveFxIndex
    local mappingGuid
    if isCurved then
        local parameterLinkEffectOnCurve = getPlinkEffect(track,fxIndex, 0) 
        --parameterLinkParamForCurve = getPlinkParam(track,parameterLinkFXIndex,0)
        local parameterLinkFXIndexOnCurve = getPlinkFxIndex(track, modulationContainerPos, parameterLinkEffectOnCurve) 
         --
        _, curveName = GetNamedConfigParm(track, fxIndex, 'renamed_name', doNotUseCatch)
        fxOriginalName = getOriginalFxName(track, parameterLinkFXIndexOnCurve, doNotUseCatch)
        
        --mappingGuid = GetFXGUID( track, fxIndex,doNotUseCatch)
        --parameterLinkName
        --reaper.ShowConsoleMsg(originalName .. " - " .. parameterLinkFXIndex .. "\n")
        
        --parameterLinkFXIndexForCurve = parameterLinkFXIndex
        curveFxIndex = fxIndex
        fxIndex = parameterLinkFXIndexOnCurve
        --parameterLinkEffect = parameterLinkEffectOnCurve
    end
    
    local renamed, fxName = GetNamedConfigParm(track, fxIndex, 'renamed_name', doNotUseCatch)
    local guid = GetFXGUID( track, fxIndex,doNotUseCatch)
    if not renamed or fxName == "" or fxName == nil then 
        fxName = fxOriginalName
    end
    --if not mappingGuid then mappingGuid = guid end
    
    local mappings = (parameterLinks and parameterLinks[fxIndex]) and parameterLinks[fxIndex] or {}
    local output, genericModulatorInfo = getOutputArrayForModulator(track, fxOriginalName, fxIndex, modulationContainerPos)
    local outputNames = getOutputNameArrayForModulator(track, fxOriginalName, fxIndex, modulationContainerPos)
    
    local mappingNames = {}
    --local mappingGuids = {}
     
    for i, out in ipairs(output) do
        paramName = GetParamName(track, fxIndex, out, doNotUseCatch)
        local mappingName = fxName 
        if #output > 1 then 
            if outputNames then
                mappingName = mappingName .. ": " .. outputNames[i]
            else
                mappingName = mappingName .. ": " .. paramName
            end
        end
        mappingNames[out] = mappingName
        --mappingGuids[out] = mappingGuid
    end
    
    if not isCurver then
        --reaper.ShowConsoleMsg(fxOriginalName .. " - " .. mappingNames[output[1]].. "\n") 
    end
    
    return {name = fxName, fxIndex = fxIndex, guid = guid, fxName = fxOriginalName, mappings = mappings, output = output, mappingNames = mappingNames, outputNames = outputNames, genericModulatorInfo = genericModulatorInfo, 
    isCurver = isCurver, --mappingGuids = mappingGuids--, isCurved = isCurved, curveName = curveName, curveFxIndex = curveFxIndex,
    }
end


function getModulatorNames(track, modulationContainerPos, parameterLinks, doNotUseCatch)
    if modulationContainerPos then
        local fxAmount = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_count', doNotUseCatch)))
        local containerData = {}
        local fxIndexs = {}
        allIsCollabsed = true
        allIsNotCollabsed = true
        
        for c = 0, fxAmount -1 do  
            local fxIndex = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c, doNotUseCatch) ))
            if fxIndex then
                local obj = getModulatorInfo(track, fxIndex)
                if obj and obj.fxIndex then
                    obj.fxInContainerIndex = c
                    --local fxIndex = tonumber(select(2, GetNamedConfigParm(track, modulationContainerPos, 'container_item.' .. c, doNotUseCatch) ))
                    if obj.curveName then
                      --  reaper.ShowConsoleMsg(c .. " - " .. obj.name .. " - " .. obj.curveName .. "\n")
                    end
                    
                    local isCollabsed = trackSettings.collabsModules[obj.guid]
                    --if not nameCount[fxName] then nameCount[fxName] = 1 else nameCount[fxName] = nameCount[fxName] + 1 end
                    --table.insert(containerData, {name = fxName .. " " .. nameCount[fxName], fxIndex = tonumber(fxIndex)})
                    table.insert(containerData, obj)
                    fxIndexs[obj.fxIndex] = true
                    if not isCollabsed then allIsCollabsed = false end
                    if isCollabsed then allIsNotCollabsed = false end
                end
            end
        end
        return containerData, fxIndexs
    end
end

function getParameterLinkValues(track, fxIndex, param)
    local baseline = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.baseline')))
    local scale = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale')))
    local offset = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.offset')))
    return baseline, scale, offset
end

function disableParameterLink(track, fxnumber, paramnumber, newValue) 
    local baseline, scale, offset = getParameterLinkValues(track, fxnumber, paramnumber)
    SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.active',0 )
    SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.active',0 )
    SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.plink.effect',-1 )
    if newValue == "CurrentValue" then
    
    elseif newValue == "MaxValue" then
        SetParam(track,fxnumber,paramnumber,baseline + scale + offset)
    else
        SetParam(track,fxnumber,paramnumber,baseline)-- + offset)
    end
    reloadParameterLinkCatch = true
end

function setParameterToBaselineValue(track, fxnumber, paramnumber) 
    local baseline = tonumber(select(2, GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline')))
    SetParam(track,fxnumber,paramnumber,baseline)
end

function setBaselineToParameterValue(track, fxnumber, paramnumber) 
    local value = GetParam(track,fxnumber,paramnumber)
    --local range = max - min
    SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.mod.baseline', value)
    
end

function flipWidthValue(track, fxIndex, param) 
    local scale = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale')))
    SetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.scale', - scale)
end

function resetParameterValue(track, fxIndex, param, resetValue, p) 
    if resetValue then
        if p.parameterLinkActive then 
            SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.baseline', resetValue)
        else
            SetParam(track,fxIndex,param,resetValue)
        end
    end
end

function resetNativeParameterValue(track, resetValue, p) 
    if resetValue then 
        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.paramOut..'.' .. p.paramName, resetValue)
    end
end

function toggleBipolar(track, fxIndex, param, bipolar)
    if bipolar then
        SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  0)
    else 
        SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  -0.5)
    end 
end

function toggleeModulatorAndSetBaselineAcordingly(track, fxIndex, param, newValue)
    if not newValue then
        setParameterToBaselineValue(track, fxIndex, param)  
        SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', 0 )
    else
        SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.active', 1 )
        setBaselineToParameterValue(track, fxIndex, param)  
    end
end

function mapParameterToContainer(track, modulationContainerPos, fxIndex, param)
    GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. param )
end

function deleteParameterFromContainer(track, modulationContainerPos, param)
    GetNamedConfigParm( track, modulationContainerPos, 'param.' .. param .. '.container_map.delete' )
end

function insertCurveForMapping(track, p)
    local wasSetToFloatingAuto = setFxFloatAutoToTrue()
    
    local curveName = "Curve_" .. p.guid .."_" .. p.param
    -- insert curver
    modulationContainerPos, insert_position = insertFXAndAddContainerMapping(track, "Curve Mapped Modulation", curveName) 
    
    -- assign curver
    local fxIndex = insert_position
    local curver = getModulatorInfo(track, fxIndex, true)
    mapModulatorActivate(curver, 1, curver.name, true, true)
    setParamaterToLastTouched(track, modulationContainerPos, insert_position, p.fxIndex, p.param, p.baseline, p.offset, p.width, p.baseline) 
    mapModulatorActivate(nil)
    
    -- assign previous mapping to curver, with full width 
    local originalModulator = getModulatorInfo(track, p.parameterLinkFXIndex, true)
    mapModulatorActivate(originalModulator, p.parameterLinkParam, originalModulator.name, true, true)
    setParamaterToLastTouched(track, modulationContainerPos, p.parameterLinkFXIndex, fxIndex, 0, 0, 0, 1, 0) 
    mapModulatorActivate(nil) 
    
    if not wasSetToFloatingAuto then toggleFxFloatAuto() end
    
    reloadParameterLinkCatch = true
end

function removeCurveForMapping(track, p)
    reaper.Undo_BeginBlock()
    -- assign original mod
    local fxIndex = p.parameterLinkFXIndex
    local modObj = getModulatorInfo(track, fxIndex, true)
    ac = p.parameterLinkParam
    
    mapModulatorActivate(modObj, p.parameterLinkParam, modObj.name, true, true)
    
    setParamaterToLastTouched(track, modulationContainerPos, fxIndex, p.fxIndex, p.param, p.baseline, p.offset, p.width, p.baseline) 
    mapModulatorActivate(nil)
    
    DeleteFX(track, p.parameterLinkFXIndexForCurve)
    
    reaper.Undo_EndBlock("Remove curver for " .. p.name .. " - " .. p.fxName, -1)
    reloadParameterLinkCatch = true
    
end


function setParamaterToLastTouched(track, modulationContainerPos, fxIndex, fxnumber, param, value, offsetForce, scaleForce, valueForce)
    if not track or not modulationContainerPos or not fxIndex or not fxnumber or not param then return end
    local outputPos
    
    if not param then
        reaper.ShowConsoleMsg(appName .. ":\nThere was an issue with a missing parameter. Report this full text to developer:\nMod container pos: " .. tostring(modulationContainerPos) .. "fxIndex: " .. tostring(fxIndex) .. ", , fxnumber: " .. tostring(fxnumber) .. ", param: " .. tostring(param))
        return
    end
    if tonumber(fxnumber) < 0x2000000 then
        -- map from fx in the root
        outputPos = tonumber(select(2, GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. mapActiveParam, true )))
    else
        
        -- we map a thing specifically from within the folder
        if tonumber(modulationContainerPos) > 0x2000000 and modulationContainerPos == fxIndex then
            outputPos = mapActiveParam  
            local mappingFxContainerPath = get_container_path_from_fx_id(track, modulationContainerPos)
            modulationContainerPos = mappingFxContainerPath[#mappingFxContainerPath] - 1
        else
            local containerPath = get_container_path_from_fx_id(track, fxnumber)
        
            if containerPath and containerPath[1] == modulationContainerPos + 1 then 
                -- map a modulator from within the modulator folder
                -- could this be done in a better way? -- I need to get the position of the FX inside the container
                outputPos = mapActiveParam -- this is the paramater in the lfo plugin 
                
                local mappingFxContainerPath = get_container_path_from_fx_id(track, mapActiveFxIndex)
                modulationContainerPos = mappingFxContainerPath[#mappingFxContainerPath] - 1
                --modulationContainerPos = fxContainerIndex -- mappingFxContainerPath[#mappingFxContainerPath] - 1 -- mapActiveFxIndex--
            else
                -- map a fx in a container
                new_fxnumber, new_param = fx_map_parameter(track, fxnumber, param) 
                if not new_param then
                    reaper.ShowConsoleMsg(appName .. ":\nThere was an issue finding the pos of the parameter. Report this to developer:\nMod container pos: " .. tostring(modulationContainerPos) .. ", fxIndex: " .. tostring(fxIndex) .. ", fxnumber: " .. tostring(fxnumber) .. ", param: " .. tostring(param))
                    return
                end
                fxnumber = new_fxnumber
                param = new_param
                outputPos = tonumber(select(2, GetNamedConfigParm( track, modulationContainerPos, 'container_map.add.'..fxIndex..'.' .. mapActiveParam, true )))
            end
        end
    end 
    
    local retParam, currentOutputPos = GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.param', true)
    local retEffect, currentModulationContainerPos = GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.effect', true)
    --local retActive, isPlinkActive = GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.active')
    
    if (retParam and outputPos ~= tonumber(currentOutputPos)) or (retEffect and modulationContainerPos ~= tonumber(currentModulationContainerPos)) then 
        local ret, baseline = GetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.baseline', true)
        local isModActive = tonumber(select(2, GetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.active', true))) == 1        
        if isModActive then
            if settings.usePreviousMapSettingsWhenOverwrittingMapping then
                
                local ret, offset = GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.offset', true)
                local ret, scale = GetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.scale', true)
                offsetForce = offset
                scaleForce = scale
            end
            value = tonumber(baseline) --+ tonumber(offset)
        end 
    end
    useOffset = offsetForce and offsetForce or useOffset
    useScale = scaleForce and scaleForce or useScale
    value = valueForce and valueForce or value 
     
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.active',1 )
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.mod.baseline', value )
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.active',1 )
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.offset',useOffset and useOffset or 0 )
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.scale',useScale and useScale or 1 )
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.effect',modulationContainerPos )
    SetNamedConfigParm( track, fxnumber, 'param.'..param..'.plink.param', outputPos )
    reloadParameterLinkCatch = true
end


---------------------------------
----- AB SLIDER FUNCTIONS -------
---------------------------------
-- this might not work
function disableAllParameterModulationMappingsByName(name, newValue)
    local fx_count = GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local params = {}
        
        local fx_name = GetFXName(track, fxIndex) 
        -- Iterate through all parameters for the current FX
        local param_count = GetNumParams(track, fxIndex)
        for p = 0, param_count - 1 do 
            _, parameterLinkActive = GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.active')
            local parameterLinkActive = parameterLinkActive == "1"
            
            if parameterLinkActive then
                local _, parameterLinkEffect = GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.effect' )
                if parameterLinkEffect ~= "" then
                    local baseline = getModBassline(track, fxIndex, p)
                    local width = getPlinkScale(track, fxIndex, p)
                    local parameterLinkParam = getPlinkParam(track, fxIndex, p )
                    local containerItemFxId = getPlinkFxIndex( track, parameterLinkEffect, parameterLinkParam )
                    local parameterLinkName = GetParamName(track, parameterLinkEffect, parameterLinkParam)
                    
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
    local fx_count = GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local fx_name = GetFXName(track, fxIndex) 
        -- Iterate through all parameters for the current FX
        local param_count = GetNumParams(track, fxIndex)
        
        for p = 0, param_count - 1 do 
            if filterParametersThatAreMostLikelyNotWanted(p, track, fxIndex) then
                local parameterLinkActive = getPlinkActive(track, fxIndex, p) 
                
                if parameterLinkActive then
                    parameterLinkEffect = getPlinkEffect(track, fxIndex, p )
                    if parameterLinkEffect then
                        parameterLinkParam = getPlinkParam(track, fxIndex, p)
                        
                        parameterLinkName = GetParamName(track, parameterLinkEffect, parameterLinkParam)
                        if parameterLinkName:match(name) then
                            return true
                        end
                    end 
                end
            end
            
        end
    end
    return false
end

function getTrackPluginsParameterLinkValues(name, clearType) 
    local plugin_values = {}
    local fx_count = GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        
        local fx_name = GetFXName(track, fxIndex) 
        local guid = GetFXGUID( track, fxIndex)
        if not fx_name:match("^Modulators") then 
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = GetNumParams(track, fxIndex)
            for param = 0, param_count - 1 do
                if filterParametersThatAreMostLikelyNotWanted(param, track, fxIndex) then
                    local parameterLinkActive = getPlinkActive(track, fxIndex, param)
                    
                    -- we ignore values that have parameter link activated
                    if parameterLinkActive then
                        local parameterLinkEffect = getPlinkEffect(track, fxIndex, param )
                        if parameterLinkEffect then
                            local parameterLinkParam = getPlinkParam(track, fxIndex, param)
                            local parameterLinkName = GetParamName(track, parameterLinkEffect, parameterLinkParam) 
                            if parameterLinkName:match(name) then
                                local baseline, scale, offset = getParameterLinkValues(track, fxIndex, param) 
                                
                                valueNormalized = clearType == "MinValue" and baseline + scale + offset or baseline + offset
                                table.insert(params, {
                                    valueNormalized = valueNormalized
                                })
                            end
                        end
                    else
                        local valueNormalized = GetParamNormalized(track, fxIndex, param)
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
    local fx_count = GetCount(track)
    for fxIndex = 0, fx_count - 1 do
        local fx_name = GetFXName(track, fxIndex) 
        local guid = GetFXGUID( track, fxIndex )
        if not fx_name:match("^Modulators") then 
            local fx_name_simple = removeBeforeColon(fx_name)
            local params = {}
        
            -- Iterate through all parameters for the current FX
            local param_count = GetNumParams(track, fxIndex)
            for param = 0, param_count - 1 do
                if filterParametersThatAreMostLikelyNotWanted(param, track, fxIndex) then
                    local parameterLinkActive = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.plink.active'))) == 1 
                    local value, min, max = GetParam(track,fxIndex,param)
                    -- we ignore values that have parameter link activated
                    if not parameterLinkActive then
                        local valueNormalized = GetParamNormalized(track, fxIndex, param)
                        --reaper.ShowConsoleMsg(param_name .. "\n")
                        -- Save parameter details
                        table.insert(params, {
                            valueNormalized = valueNormalized,
                            param = param,
                            min = min, 
                            max = max, 
                            value = value,
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
    end
    return plugin_values
end

function unnormalizeValue(value, min, max) 
    local notNormalizedRange = max - min
    return value * notNormalizedRange + min 
end

-- Function to compare two arrays of plugin values and log changes
function comparePluginValues(a_trackPluginStates, b_trackPluginStates, track, modulationContainerPos, fxIndex) 
    mapActiveParam = 0
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
                        
                            local range = a_value - b_value
                            --reaper.ShowConsoleMsg(a_states.name  .. " - " .. b_param .. " - " .. tostring(a_value) .. " - " .. tostring(b_value) .. " - " .. range .. "\n")
                            local range_converted = unnormalizeValue(range, a_states.min, a_states.max) 
                            local a_value_converted = unnormalizeValue(b_value, a_states.min, a_states.max) 
                            local value = b_value
                            
                            setParamaterToLastTouched(track, modulationContainerPos, fxIndex, fx_number, b_param, a_value_converted, 0, range, a_value_converted)
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
mapActiveFxIndex = false
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
mapActiveParam = 0

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
        local paramCount = GetNumParams(track, fxIndex) - 1
        for p = 0, paramCount do 
            if filterParametersThatAreMostLikelyNotWanted(p, track, fxIndex) then
                local parameterLinkActive = getPlinkActive(track, fxIndex, p )
                if parameterLinkActive then
                    local parameterLinkEffect = getPlinkEffect(track, fxIndex, p)
                    if parameterLinkEffect then  
                        baseline = getModBassline(track, fxIndex, p)
                        --_, offset = GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.offset')
                        --_, width = GetNamedConfigParm( track, fxIndex, 'param.'..p..'.plink.scale')
                        table.insert(data, baseline)
                    end
                else 
                    local value = GetParam(track,fxIndex,p)
                    table.insert(data, value)
                end
            end
        end
    end
    return data
end

local function setAllTrackFxParamValues(track,fxIndex, settings)
    if track and fxIndex then
        local paramCount = GetNumParams(track, fxIndex) - 1
        for p, val in ipairs(settings) do 
            local value = SetParam(track,fxIndex,p - 1, val)
        end
    end
end

local nativeLfoList = {"active","dir","phase","speed","strength","temposync","free","shape"}
local function getNativeLFOParamSettings(track,fxIndex) 
    local data = {} 
    for _, l in ipairs(nativeLfoList) do 
        local val = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.lfo.' .. l) ))
        data[l] = val
    end 
    return data
end

local function setNativeLFOParamSettings(track,fxIndex, settings)  
    SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.active', 1)
    SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.baseline', 0.5)
    for key, val in pairs(settings) do 
        SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.lfo.' .. key, tonumber(val))  
    end 
end


    
local nativeAcsList = {"active","dir","strength","attack","release","dblo","dbhi","chan","stereo","x2","y2"}
local function getNativeACSParamSettings(track,fxIndex) 
    local data = {} 
    for _, l in ipairs(nativeAcsList) do 
        local val = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.acs.' .. l) ))
        data[l] = val
    end 
    return data
end

local function setNativeACSParamSettings(track,fxIndex, settings) 
    SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.active', 1)
    SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.baseline', 0.5) 
    for key, val in pairs(settings) do 
        SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.acs.' .. key, tonumber(val))  
    end 
end


local function getAllDataFromParameter(track,fxIndex,param, ignoreFilter) 
    if not track or not validateTrack(track) then return {} end
    if not fxIndex or not param then return {} end
    
    
    --local name = GetParamName(track,fxIndex,param)
    local name = GetParamName(track, fxIndex, param)
    local rename = GetParamNameFromCustomSetting(track, fxIndex, param, "rename")
    
    local valueName = GetFormattedParamValue(track,fxIndex,param)
    -- we filter internal and midi parameters from plugin parameter list
    if ignoreFilter or filterParametersThatAreMostLikelyNotWanted(param, track, fxIndex) then  
        local fxName = GetFXName(track, fxIndex)
        local fxNameSimple = fxSimpleName(fxName, true)
        local root_fxIndex, root_param = fx_get_mapped_parameter_with_catch(track, fxIndex, param)
        --local containerPath = GetContainerPath(track, fxIndex)
        --local modulated_fxIndex = fxIndex
        --local modulated_param = p
        local original_param = param
        
        local fromWithinFolder = false
        local parameterLinkActive
        if modulationContainerPos and root_fxIndex and root_fxIndex ~= modulationContainerPos then 
            if root_fxIndex and root_param then 
                --reaper.ShowConsoleMsg(name .. " - fxIndex: " .. fxIndex .. " - param: " .. param .. " - Root index: " .. root_fxIndex .. " - Root param: " .. root_param .. "\n")
                parameterLinkActive = getPlinkActive(track, root_fxIndex, root_param)
                if parameterLinkActive then
                    --modulated_fxIndex = root_fxIndex - 1
                    --modulated_param = root_param
                    fxIndex = root_fxIndex
                    param = root_param
                end
            end
        else 
            
            parameterLinkActive = getPlinkActive(track,fxIndex,param)
            if parameterLinkActive then
                
                local path = get_container_path_from_fx_id(track, fxIndex)
                if path then 
                    
                    if path[1] == modulationContainerPos then
                        --root_fxIndex = modulationContainerPos
                        reaper.ShowConsoleMsg("Unsure of when this is mapped. Report to Jesper Ankarfeldt\n")
                        reaper.ShowConsoleMsg(name .. " - fxIndex: " .. fxIndex .. " - param: " .. param .. " - Root index: " .. tostring(root_fxIndex) .. " - Root param: " .. tostring(root_param) .. "\n")
                        
                        --local posInContainer = getPlinkEffect(track, fxIndex, param)
                        --root_param = getPlinkFxIndexInContainer(track,root_fxIndex, posInContainer)
                        
                        --aa = root_param
                        
                    else
                        fromWithinFolder = true
                        --root_fxIndex = path[#path-1] --get_fx_id_from_container_path(track, table.unpack(path))
                        --root_fxIndex = modulationContainerPos
                        root_fxIndex = path[#path-1] and path[#path-1] - 1 or false
                        
                        --reaper.ShowConsoleMsg(name .. " - fxIndex: " .. fxIndex .. " - param: " .. param .. " - Root index: " .. tostring(path[#path-1]) .. " - Root param: " .. tostring(root_fxIndex) .. "  2\n")
                    end
                end
            end
        end
        
        
        --local parameterLinkActive = getPlinkActive(track,fxIndex,param)
        local guid = GetFXGUID(track, fxIndex)
        
        local parameterModulationActive = getModActive(track,fxIndex,param)
        local mappingName
        local baseline = false
        local width = 0
        local offset = 0
        local direction = 0
        local bipolar = false
        local parameterLinkName = "" 
        local isCurved = false
        local isCurver = false
        local parameterLinkEffectForCurve, parameterLinkFXIndexForCurve, parameterLinkNameForCurve, parameterLinkParamForCurve, parameterLinkCurverOpen
        
        local midiMsg, midiMsg2, midiBus, midiChan, linkFromMidiText
        
        
        function findSettingsIfCurver()
            local retName, originalName = GetNamedConfigParm( track, parameterLinkFXIndex, 'fx_name' )
            isCurver = originalName == "JS: Curve Mapped Modulation"
            if isCurver then
                --local curvePath = get_container_path_from_fx_id(track, parameterLinkFXIndex)
                local parameterLinkEffectOnCurve = getPlinkEffect(track,parameterLinkFXIndex, 0) 
                --parameterLinkParamForCurve = getPlinkParam(track,parameterLinkFXIndex,0)
                local parameterLinkFXIndexOnCurve = getPlinkFxIndex(track, modulationContainerPos, parameterLinkEffectOnCurve) 
                
                --parameterLinkNameForCurve = parameterLinkName
                --parameterLinkNameForCurve = simplifyParameterNameName(parameterLinkNameForCurve, 1)
                parameterLinkName =  getRenamedFxName(track, parameterLinkFXIndexOnCurve)
                parameterLinkParamForCurve = parameterLinkParam
                
                --
                originalName = getOriginalFxName( track, parameterLinkFXIndexOnCurve )
                --parameterLinkName
                --reaper.ShowConsoleMsg(originalName .. " - " .. parameterLinkFXIndex .. "\n")
                
                parameterLinkParam = getPlinkParam(track,parameterLinkFXIndex,0)
                parameterLinkFXIndexForCurve = parameterLinkFXIndex
                parameterLinkFXIndex = parameterLinkFXIndexOnCurve
                parameterLinkEffect = parameterLinkEffectOnCurve
                parameterLinkCurverOpen = GetOpen(track, parameterLinkFXIndexForCurve)
            end
        end
        
        if parameterLinkActive then
            parameterLinkEffect = getPlinkEffect(track, fxIndex, param)
            
            if parameterLinkEffect then
                baseline = getModBassline(track,fxIndex,param)
                offset = getPlinkOffset(track,fxIndex,param)
                width = getPlinkScale(track,fxIndex,param)
                parameterLinkParam = getPlinkParam(track,fxIndex,param)
                bipolar = offset == -0.5
                
                if offset then
                    if width and width >= 0 then
                        direction = offset * 2 + 1
                    else
                        direction = math.abs(offset * 2) - 1
                    end
                end
            end
            if parameterLinkEffect and parameterLinkEffect >= 0 then   
                
                if modulationContainerPos and root_fxIndex == modulationContainerPos then
                    
                    parameterLinkFXIndex = getPlinkFxIndex(track, modulationContainerPos, parameterLinkEffect)
                   
                    if parameterLinkFXIndex then
                         parameterLinkName =  getRenamedFxName(track, parameterLinkFXIndex)
                         
                         local originalName = getOriginalFxName(track, parameterLinkFXIndex)
                         local outputsForLinkedModulator = getOutputArrayForModulator(track, originalName, parameterLinkFXIndex, modulationContainerPos)
                        
                         --if not parameterLinkName and parameterLinkIndex then
                         --    parameterLinkName = GetFXName(track, parameterLinkIndex)
                         --end
                         
                         -- reaper.ShowConsoleMsg(tostring(parameterLinkFXIndex) ..  " - pLinkEfx: " .. parameterLinkEffect .. " - pLinkParam: " .. parameterLinkParam .. " - outputsAmount: "..#outputsForLinkedModulator  .. " - pLinkName: " .. parameterLinkName .. " - ".. originalName .. "\n")
                         if #outputsForLinkedModulator > 1 then
                             paramName = GetParamName(track, parameterLinkFXIndex, parameterLinkParam)
                             parameterLinkName = parameterLinkName .. ": " .. paramName 
                         end
                         
                         findSettingsIfCurver()
                         --reaper.ShowConsoleMsg(tostring(parameterLinkFXIndex) ..  " - " .. parameterLinkEffect .. " - " .. parameterLinkParam .. " - "..#outputsForLinkedModulator  .. " - " .. parameterLinkName .. "\n")
                        
                     end 
                     --reaper.ShowConsoleMsg(fxIndex .. " - " .. p .. " - " .. parameterLinkName .. " test\n")
                else
                    local parameterLinkFXIndexInContainer
                    if fromWithinFolder and root_fxIndex then 
                        parameterLinkEffect = getPlinkFxIndex(track,root_fxIndex, parameterLinkEffect) 
                    else 
                        parameterLinkFXIndexInContainer = modulationContainerPos and getPlinkFxIndexInContainer(track,modulationContainerPos, parameterLinkParam)
                    end
                    
                    
                    parameterLinkName = GetParamName(track, parameterLinkEffect, parameterLinkParam)  
                    
                    --reaper.ShowConsoleMsg(name .. " - " .. tostring(parameterLinkName)  .. " - " .. tostring(parameterLinkParam) .. "\n")
                    -- 1234
                    
                    --reaper.ShowConsoleMsg(parameterLinkName .. " - " .. name .. "\n")
                    --if fxOriginalName == "Container" then
                    
                    --else
                    function simplifyParameterNameName(parameterLinkName, outputsForLinkedModulatorAmount)
                        local colon_pos = parameterLinkName and parameterLinkName:find(":")
                        if outputsForLinkedModulatorAmount == 1 and colon_pos then
                            parameterLinkName = parameterLinkName:sub(1, colon_pos - 1) 
                        end
                        return parameterLinkName
                    end
                    
                    
                    
                    if parameterLinkFXIndexInContainer then
                        parameterLinkFXIndex = getPlinkFxIndex( track, modulationContainerPos, parameterLinkFXIndexInContainer)
                        
                        if parameterLinkFXIndex then
                            
                            -- overwrite the parameter to be the parameter that's within the modulation container
                            parameterLinkParam = getPlinkParamInContainer(track,modulationContainerPos,parameterLinkParam) 
                            if parameterLinkParam then
                                
                                findSettingsIfCurver()
                                
                                local outputsForLinkedModulator = getOutputArrayForModulator(track, originalName, parameterLinkFXIndex, modulationContainerPos)
                                
                                parameterLinkName = simplifyParameterNameName(parameterLinkName, #outputsForLinkedModulator)
                            end
                        end
                        --local mappings = (parameterLinks and parameterLinks[fxIndex]) and parameterLinks[fxIndex] or {}
                        --modulatorNames
                    end 
                    --end
                end
            elseif parameterLinkEffect == -100 then
                midiMsg = getPlinkMidiMsg(track, fxIndex, param)
                midiMsg2 = getPlinkMidiMsg2(track, fxIndex, param)
                midiBus = getPlinkMidiBus(track, fxIndex, param)
                midiChan = getPlinkMidiChan(track, fxIndex, param)
                
                if midiMsg2 < 128 then
                    linkFromMidiText = "Link: " .. midi_status_to_text(midiMsg + (midiChan > 0 and midiChan - 1 or 0), midiMsg2, midiChan == 0)
                    if midiBus > 0 then
                        linkFromMidiText = linkFromMidiText .. " (Bus " .. midiBus + 1 .. ")"
                    end
                elseif midiMsg == 176 then
                    linkFromMidiText = "Link MIDI: " .. (midiMsg2 - 128) .. "/" .. (midiMsg2 - 96) .. " 14-bit"
                end
            end 
        else
            
        end
         
        local parameterModulationActive = parameterLinkActive and parameterModulationActive -- and parameterLinkEffect
        
        
        local midiLearnText
        if not parameterModulationActive then -- settings.showMidiLearnIfNoParameterModulation then
            local learnMidi1 = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.midi1', nil, 2)))
            local learnMidi2 = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.midi2', nil, 2)))
            local learnOsc = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.osc', nil, 2)))
            local somethingIsLearned = (learnMidi1 and learnMidi1 ~= 0) or learnOsc
            if somethingIsLearned then
                if learnMidi1 then
                    midiLearnText = "Learn: " .. midi_status_to_text(learnMidi1, learnMidi2)
                elseif learnOsc then
                    midiLearnText = "Learn " .. "OSC msg: ".. learnOsc
                end
            end
        end
        
        
        
        
        local envelopePointCount, usesEnvelope, firstEnvelopeValue, envelopeValueAtPos, hasEnvelopePoints, envTime, singleEnvelopePointAtStart
        local trackEnvelope = GetFXEnvelope(track,fxIndex,param,false)
        
        if trackEnvelope then
            envelopePointCount = CountEnvelopePoints(track,fxIndex,param)
            envelopeActive = envelopeIsActive(track,fxIndex,param) 
            
            hasEnvelopePoints = envelopePointCount > 0
            usesEnvelope = envelopeActive and envelopePointCount > 0-- and envelopeActive == "1"
            if usesEnvelope then
                local playState = reaper.GetPlayState()
                local target_time
                if playState == 0 then --not lastEnvelopeInsertPos or lastEnvelopeInsertPos ~= playPos then
                    target_time = reaper.GetCursorPosition()
                else
                    target_time = playPos2 
                end
                --local _, block_size = reaper.GetAudioDeviceInfo("BSIZE")
                --local _, sample_rate = reaper.GetAudioDeviceInfo("SRATE")
                envelopeValueAtPos = getEnvelopeValueAndPos(track,fxIndex,param, target_time)
                if envelopePointCount == 1 then
                    envTime, firstEnvelopeValue = GetEnvelopePoint(track,fxIndex,param, 0)
                    
                    -- for some reason this does not work as expected, but this is a fix, to not check envTime
                    --if envTime ~= nil then -- and tonumber(envTime) == 0 then
                        singleEnvelopePointAtStart = true
                    --end
                end
            end
        end
        
        
        local value, min, max = GetParam(track,fxIndex,param)
        local hasSteps, step, smallStep, largeStep, isToggle = GetParameterStepSizes(track, fxIndex, param)
        
        local isInverted = max < min
        if isInverted then
            local temp = min
            min = max
            max = temp
        end 
        local range = math.abs(max - min)
        
        
        if hasSteps and not isToggle then
            --reaper.ShowConsoleMsg(fxName .. " - ".. name .. " - " .. step .. " - " .. range/step .. " - "  .. tostring(isToggle) .. "\n")
        end
        
        local valueNormalized = GetParamNormalized(track, fxIndex, param)
        if min ~= 0 or max ~= 1 and parameterLinkActive then
            --fxName = GetFXName(track, fxIndex)
            
            --reaper.ShowConsoleMsg(fxName .. " : " .. name .. " : " .. min .. " : ".. max .. " : " .. tostring(baseline) .."\n")
            
        end
        local currentValue = value
        if not automation then
            automation = math.floor(reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE'))
        end
        
        if automation == 5 and not parameterModulationActive then
        elseif parameterModulationActive and (not usesEnvelope or automation == 5) and baseline then
            currentValue = tonumber(baseline)
        elseif singleEnvelopePointAtStart and firstEnvelopeValue and automation ~= 5 then
            currentValue = firstEnvelopeValue
        elseif usesEnvelope and envelopeValueAtPos and not scrollTime then 
            -- not write, latch, latch preview
            if (not isMouseDragging and (automation < 3 or automation == 5)) or 
            (isMouseDragging and (automation < 2)) 
            then-- or automation < 3 then --not automationTypes[automation+1] ~= "Write" then
            
            --reaper.ShowConsoleMsg(tostring(automation) .. " a\n")
            -- we do not need to use the envelope value here it seems, as it will not make it change properly
                currentValue = envelopeValueAtPos
            end
        end
        -- 123
        --if valueName == "-" then
            --reaper.ShowConsoleMsg(tostring(valueName) .. " a\n")
        --end
        local currentValueNormalized = (currentValue - min) / range
        --local visualValueNormalized = currentValueNormalized + offset + 
        return {param = param, name = name, rename = rename, currentValue = currentValue, currentValueNormalized = currentValueNormalized,  value = value, valueNormalized = valueNormalized, min = min, max = max, range = range, baseline = tonumber(baseline), width = tonumber(width), offset = tonumber(offset), bipolar = bipolar, direction = direction,
        valueName = valueName, fxIndex = fxIndex, guid = guid, fxNameSimple = fxNameSimple,
        parameterModulationActive = parameterModulationActive, parameterLinkActive = parameterLinkActive, parameterLinkEffect = parameterLinkEffect,containerItemFxId = tonumber(containerItemFxId),
        envelope = trackEnvelope, hasEnvelopePoints = hasEnvelopePoints, usesEnvelope = usesEnvelope, envelopeActive = envelopeActive, envelopePointCount = envelopePointCount, singleEnvelopePointAtStart = singleEnvelopePointAtStart, envelopeValue = envelopeValueAtPos, 
        parameterLinkFXIndex = parameterLinkFXIndex, parameterLinkParam = parameterLinkParam, parameterLinkName = parameterLinkName,
        fxName = fxName, parallel = parallel,
        hasSteps = hasSteps, step = step, smallStep = smallStep, largeStep = largeStep, isToggle = isToggle, 
        containerPath = containerPath,
        midiLearnText = midiLearnText,
        midiMsg = midiMsg, midiMsg2 = midiMsg2, midiBus = midiBus, midiChan = midiChan, linkFromMidiText = linkFromMidiText,
        isCurver = isCurver, isCurved = isCurved, parameterLinkEffectForCurve = parameterLinkEffectForCurve, parameterLinkFXIndexForCurve = parameterLinkFXIndexForCurve, parameterLinkNameForCurve = parameterLinkNameForCurve, parameterLinkParamForCurve = parameterLinkParamForCurve, parameterLinkCurverOpen = parameterLinkCurverOpen
        }
    end
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



function hideTrackEnvelopesUsingSettings(track, p)
    local ignoreEnvelope = p.envelope
    if not track then return end
    
    if lastFocusedEnvelope and ignoreEnvelope == nil then
        --lastFocusedEnvelope = nil
    end
  
  
    local envCount = reaper.CountTrackEnvelopes(track)
    for i = 0, envCount - 1 do
        local envelope = reaper.GetTrackEnvelope(track, i)
        if envelope and envelope ~= ignoreEnvelope then   
             
            local envelopePointsCount = reaper.CountEnvelopePoints(envelope)
                
            if envelopePointsCount == 1 and ((settings.hideEnvelopesIfLastTouched and lastFocusedEnvelope and lastFocusedEnvelope == envelope) or settings.hideEnvelopesWithNoPoints) then 
                if ignoreEnvelope ~= nil then
                    reaper.DeleteEnvelopePointEx(envelope,-1,0)
                end
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
        local paramCount = GetNumParams(track, fxIndex) - 1
        local pc = settings.maxParametersShown == 0 and paramCount or math.min(paramCount, settings.maxParametersShown)
        for p = 0, pc-1 do
            if filterParametersThatAreMostLikelyNotWanted(p, track, fxIndex) then
                tbl = getAllDataFromParameter(track,fxIndex,p)
                if tbl then
                    --data[p] = tbl
                    table.insert(data, tbl)
                end    
            end
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

function getIsContainer(track, fxIndex, doNotGetStatus) 
    local fxOriginalName = getOriginalFxName(track, fxIndex,doNotGetStatus)
    return fxOriginalName == "Container" -- Check if FX is a container 
end

function getIsSelector(track,fxIndex,doNotGetStatus) 
    local fxName = GetFXName(track, fxIndex,doNotGetStatus) -- Get the FX name'
    local fxOriginalName = getOriginalFxName(track, fxIndex,doNotGetStatus)
    return fxOriginalName == "JS: Container Selector Expansion" and fxName == "Selector" -- Check if FX is a container 
end

function getNameAndOtherInfo(track, fxIndex, doNotGetStatus) 
    local fxName = GetFXName(track, fxIndex,doNotGetStatus) -- Get the FX name'
    local fxOriginalName = getOriginalFxName(track, fxIndex,doNotGetStatus)
    local containerCount = getContainerCount(track,fxIndex,doNotGetStatus)
    local isContainer = fxOriginalName == "Container" -- Check if FX is a container 
    local isSelector = not isContainer and fxOriginalName == "JS: Container Selector Expansion" and fxName == "Selector" -- Check if FX is a container 
    local isCurver = not isContainer and fxOriginalName == "JS: Curve Mapped Modulation" -- Check if FX is a container 

    local isEnabled = not doNotGetStatus and GetEnabled(track, fxIndex,doNotGetStatus)
    local isOpen = not doNotGetStatus and GetOpen(track,fxIndex,doNotGetStatus)
    local isFloating = not doNotGetStatus and GetFloatingWindow(track,fxIndex,doNotGetStatus) 
    local parallel = not doNotGetStatus and (settings.showParralelIndicationInName and getFXParallelProcess(track, fxIndex,doNotGetStatus) or 0)
    local guid = GetFXGUID(track,fxIndex,doNotGetStatus)
    return fxName, fxOriginalName, guid, containerCount, isContainer, isSelector, isCurver, isEnabled, isOpen, isFloating
end

function getFxInfoAsObject(track, fxIndex,doNotGetStatus)
    if track and fxIndex then
        local fxName, fxOriginalName, guid, containerCount, isContainer, isSelector, isCurver, isEnabled, isOpen, isFloating, parallel = getNameAndOtherInfo(track, fxIndex,doNotGetStatus) 
        return {fxIndex = fxIndex, fxName = fxName, guid = guid,isContainer = isContainer, isSelector = isSelector, isCurver = isCurver, containerCount = containerCount, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating, parallel = parallel}
    else
        return {fxName = "No FX on track", fxIndex = -1}
    end
end


-- Function to get all plugins on a track, including those within containers
function getAllTrackFXOnTrack(track,doNotGetStatus)
    
    --reaper.ShowConsoleMsg("\n\n")
    local plugins = {} -- Table to store plugin information
    local containersFetch = {} -- Table to store plugin information
    --local pLinks = {} -- table to store all link parameters
    -- Helper function to get plugins recursively from containers
    local function getPluginsRecursively(track, fxContainerIndex, containerGuid, indent, fxCount, isModulator, fxContainerName)
        if fxCount then 
            --local parentIsSelectorFxIndex = false
            local parentIsSelectorIndex = false
            local selectorFxIndex = false
            local selectorFxIndexNumbers = {}
            for subFxIndex = 0, fxCount - 1 do
                local fxIndex = getPlinkFxIndex(track, fxContainerIndex, subFxIndex,doNotGetStatus)
                
                if fxIndex then
                    local fxName, fxOriginalName, guid, containerCount, isContainer, isSelector, isCurver, isEnabled, isOpen, isFloating, parallel = getNameAndOtherInfo(track, fxIndex,doNotGetStatus) 
                    
                    if parentIsSelectorIndex then
                        table.insert(plugins[parentIsSelectorIndex].selectorChildren, fxIndex) 
                        --table.insert(selectorFxIndexNumbers, fxIndex)
                    end 
                    
                    if isSelector then
                        
                        selectorFxIndex = fxIndex
                        for i, p in ipairs(plugins) do
                            -- we find the container
                            if p.fxIndex == fxContainerIndex then
                                plugins[i].isSelectorContainer = true    
                                plugins[i].isSelectorIndexForParent = fxIndex
                                --parentIsSelectorFxIndex = fxContainerIndex
                                parentIsSelectorIndex = i
                            elseif parentIsSelectorIndex then
                                if p.fxContainerIndex == fxContainerIndex then
                                    plugins[i].isSelectorIndex = selectorFxIndex
                                    --plugins[i].isSelectorIndex = fxIndex
                                    table.insert(selectorFxIndexNumbers, p.fxIndex)
                                    plugins[i].isSelectorIndexNumber = #selectorFxIndexNumbers 
                                else
                                    break
                                end
                            end
                        end 
                        if parentIsSelectorIndex then
                            plugins[parentIsSelectorIndex].selectorChildren = selectorFxIndexNumbers
                        end
                    end
                    
                    --1234
                    --pLinks = CheckFXParamsMapping(pLinks, track, fxIndex, isModulator)
                    
                    table.insert(plugins, {fxIndex = fxIndex, name = fxName, guid = guid, isModulator = isModulator, indent = indent, fxContainerIndex = fxContainerIndex, containerGuid = containerGuid, fxContainerName = fxContainerName, containerCount = containerCount, isContainer = isContainer, base1Index = subFxIndex + 1, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating, parallel = parallel, 
                    isCurver = isCurver, isSelector = isSelector, isSelectorIndex = selectorFxIndex, isSelectorIndexNumber = #selectorFxIndexNumbers, 
                    })
                    if isContainer then
                        table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, guid = guid, isContainer = isContainer, containerCount = containerCount, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = subFxIndex + 1, indent = indent, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating, parallel = parallel})
                    end
                    
                    if isContainer then
                        getPluginsRecursively(track, fxIndex, guid, indent + 1, containerCount, isModulator, fxName)
                    end
                end
            end
        end
    end

    if track then
        -- Total number of FX on the track
        local totalFX = GetCount(track)
        
        -- Iterate through each FX
        for fxIndex = 0, totalFX - 1 do
            local fxName, fxOriginalName, guid, containerCount, isContainer, isSelector, isCurver, isEnabled, isOpen, isFloating, parallel = getNameAndOtherInfo(track, fxIndex,doNotGetStatus)  
            local isModulator = isContainer and fxName == "Modulators"
            --pLinks = CheckFXParamsMapping(pLinks, track, fxIndex)
    
            -- Add the plugin information
            table.insert(plugins, {fxIndex = fxIndex, name = fxName, guid = guid, isContainer = isContainer, isSelector = isSelector, containerCount = containerCount, isModulator = isModulator, indent = 0, fxContainerName = "ROOT", base1Index = fxIndex + 1, indent = 0, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating, parallel = parallel, isCurver = isCurver})
            if isContainer then
                table.insert(containersFetch, {fxIndex = fxIndex, fxName = fxName, guid = guid, isContainer = isContainer, containerCount = containerCount, fxContainerIndex = fxContainerIndex, fxContainerName = fxContainerName, base1Index = fxIndex + 1, indent = 0, isEnabled = isEnabled, isOpen = isOpen, isFloating = isFloating, parallel = parallel})
            end
            -- If the FX is a container, recursively check its contents
            if isContainer then
                local indent = 1 
                getPluginsRecursively(track, fxIndex, guid, indent, containerCount, isModulator, fxName)
            end
        end
    end
    
    return plugins--, pLinks
        
end


function getLinkFxIndex(fxIndex, p, isModulator) 
    local linkFxIndex
    local linkFx = getPlinkEffect(track, fxIndex, p) -- index of the fx that's linked. if outside modulation folder, it will be modulation folder index
    local linkParam = getPlinkParam(track, fxIndex, p)  -- parameter of the fx that's linked. 
    if modulationContainerPos then  
        --local _, linkFxIndex = GetNamedConfigParm(track, modulationContainerPos, 'param.' .. linkParam .. '.container_map.hint_id')
        if isModulator then 
            linkFxIndex = tonumber(get_fx_id_from_container_path(track, modulationContainerPos+1, linkFx + 1)) -- test hierarchy
        else  
            local fxIndexInContainer = getPlinkFxIndexInContainer(track, modulationContainerPos, linkParam )
            if fxIndexInContainer then 
                linkFxIndex = getPlinkFxIndex(track, modulationContainerPos, fxIndexInContainer)  
            end
        end
        return linkFxIndex
    end
end


function CheckFXParamsMapping(pLinks, track, fxIndex, isModulator, isSelector)
    local numParams = GetNumParams(track, fxIndex)
    for p = 0, numParams - 1 do 
        local param = p
        if filterParametersThatAreMostLikelyNotWanted(p, track, fxIndex) then
            
            local isLinkActive = getPlinkActive(track, fxIndex, param )
            
            if isLinkActive then
                --if modulationContainerPos then 
                -- TODO: STILL MORE WORK TO DO HERE.
                -- Here we would get modulators if allowed outside of folder as well
                
                local linkFxIndex = getLinkFxIndex(fxIndex, param, isModulator)
                
                -- we check the name if the link is a curver
                local fxOriginalName = getOriginalFxName(track, linkFxIndex,doNotGetStatus)
                local isCurved = fxOriginalName == "JS: Curve Mapped Modulation"
                -- if the param mapping is curved, we use the curved fx index instead
                if isCurved then 
                    linkFxIndexCurved = linkFxIndex
                    --param = 1
                    linkFxIndex = getLinkFxIndex(linkFxIndex, 0, isModulator)
                end
                
                
                if linkFxIndex then 
                    if not pLinks[linkFxIndex] then pLinks[linkFxIndex] = {} end
                    
                    table.insert(pLinks[linkFxIndex], {fxIndex = fxIndex, param = param, isCurved = isCurved, linkFxIndexCurved = linkFxIndexCurved})
                end
                
                        
                -- Clean up any selector mapping that could have been moved outside
                if linkFx and linkParam and getIsContainer(track, linkFx)  then 
                    
                    containerIndex = getPlinkFxIndexInContainer(track,linkFx,linkParam)
                    
                    if containerIndex then 
                        containerFxIndex = getPlinkFxIndex(track, linkFx, containerIndex)
                        if containerFxIndex and getIsSelector(track, containerFxIndex) then
                            disableParameterLink(track, fxIndex, p, "MaxValue") 
                            deleteParameterFromContainer(track, containerIndex, linkParam)
                        end
                    else
                        -- fx link is inside the selector container I think
                        containerIndex = getPlinkFxIndexInContainer(track,fxIndex,p)
                        if containerIndex then -- I belive this is the same as p, but we just check to make sure it's a mapping, and not a build in value
                            local parentContainer = getPlinkParentContainer(track, fxIndex)
                            if parentContainer then
                                containerFxIndex = getPlinkFxIndex(track, parentContainer, linkFx)
                                if containerFxIndex and getIsSelector(track, containerFxIndex) then  
                                    disableParameterLink(track, fxIndex, p, "MaxValue")  
                                    deleteParameterFromContainer(track, fxIndex, p)
                                    reloadSelector = GetFXGUID(track, containerFxIndex)
                                    --reaper.ShowConsoleMsg(tostring(parentContainer) .. " - " .. tostring(GetFXName(track, containerFxIndex)) .. " -- " .. tostring(GetParamName(track, fxIndex, p)) .. " - " .. linkFx .. " - " .. linkParam .. " - " .. p .. "\n")
                                    
                                end
                            end
                        end 
                    end
                    
                end
                 
                 
            end
            
        end
    end 
    return pLinks
end

function getAllParameterModulatorMappings(track)
    local pLinks = {}
    
    local function getRecursively(track, fxContainerIndex, indent, fxCount, isModulator, fxContainerName)
        if fxCount then 
            for subFxIndex = 0, fxCount - 1 do
                local fxIndex = getPlinkFxIndex(track, fxContainerIndex, subFxIndex)
                if fxIndex then 
                    local fxName, fxOriginalName, guid, container_count, isContainer, isSelector, isCurver = getNameAndOtherInfo(track, fxIndex, true) 
                    
                    if not isCurver then
                        pLinks = CheckFXParamsMapping(pLinks, track, fxIndex, isModulator, isSelector)
                    end
                    
                    if isContainer then
                        getRecursively(track, fxIndex, indent + 1, tonumber(container_count), isModulator, fxName)
                    end
                end
            end
        end
    end
    
    if track then
        -- Total number of FX on the track
        local totalFX = GetCount(track)
    
        -- Iterate through each FX
        for fxIndex = 0, totalFX - 1 do 
            local fxName, fxOriginalName, guid, container_count, isContainer, isSelector, isCurver = getNameAndOtherInfo(track, fxIndex, true) 
            
            local isModulator = modulationContainerPos and isContainer and fxName == "Modulators"
            
            if not isCurver then
                pLinks = CheckFXParamsMapping(pLinks, track, fxIndex)
            end
            
            -- If the FX is a container, recursively check its contents
            if isContainer then
                local indent = 1 
                getRecursively(track, fxIndex, indent, container_count, isModulator, fxName)
            end
        end
    end
    return pLinks
end



local function getAllMappingsOnTrack(track, modulationContainerPos)
    local data = {}
    if track then
        local numFX = GetCount(track) 
        for fxIndex = 0, numFX - 1 do
            data[fxIndex] = {}
            --CheckFXParams(data, track, fxIndex, parentFXIndex)
        end
    end
end


local function getAllTrackFXOnTrackSimple(track)
    local fxCount = GetCount(track)
    local data = {}
    for f = 0, fxCount-1 do
       local name = GetFXName(track,f)
       table.insert(data, {fxIndex = f, name = name})
    end
    return data
end


function compareTrackFxArray(fx_before, fx_after)
    if #fx_after ~= #fx_before then return false end
    for i, fx in ipairs(fx_after) do
        if not fx_before[i] or fx.name ~= fx_before[i].name then
            return false
        end
    end
    return true
end



local function getAllTrackFXOnTrackSimpleRecursively(track)
    
    local data = {}
    local function recusively(track, count, fxContainerIndex)
        
        for f = 0, count-1 do
           fxIndex = f
           if fxContainerIndex then
              fxIndex = getPlinkFxIndex(track, fxContainerIndex, f, doNotGetStatus)
           end
              
           local name = GetFXName(track,fxIndex)
           local nameSimple = fxSimpleName(name, true)
           table.insert(data, {fxIndex = fxIndex, name = name, nameSimple = nameSimple})
           
           local fxOriginalName = getOriginalFxName(track, fxIndex,doNotGetStatus)
           local containerCount = getContainerCount(track,fxIndex,doNotGetStatus)
           local isContainer = fxOriginalName == "Container" -- Check if FX is a container 
           if isContainer then
              recusively(track, containerCount, fxIndex)
           end
        end
    end 
    local fxCount = GetCount(track)
    recusively(track, fxCount)
    
    return data
end

function mapPlotColor()
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),colorMapDark)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),colorMapDark)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),colorMapDark)
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
        return verticalButtonStyle(name, tooltipText, sizeW, bigText, background, textSize,hover, buttonW, sizeH)
    end
end


function titleButtonStyle(name, tooltipText, sizeW, bigText, background, sizeH)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),settings.colors.menuBarHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),settings.colors.menuBarActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and settings.colors.menuBar or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),colorText)
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


function verticalButtonStyle(name, tooltipText, sizeW, verticalName, background, textSize, hover, buttonW, fullHeight)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),background and menuGreyHover or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),(background or hover) and (not hover and settings.colors.menuBar  or settings.colors.menuBarHover) or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),background and (not hover and settings.colors.menuBar or settings.colors.menuBarActive) or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),background and  settings.colors.menuBar or colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),colorText)
    local clicked = false 
    
    reaper.ImGui_PushFont(ctx, font2)
    reaper.ImGui_PushStyleVar(ctx,reaper.ImGui_StyleVar_FrameRounding(),5)
    
    
    local points, lastPos = textToPointsVertical(name,0, 0, textSize and textSize or 11, 3, sizeW and sizeW - 12 or nil)
    
    
    reaper.ImGui_PopFont(ctx)
    
    if reaper.ImGui_Button(ctx, "##"..name,buttonW and buttonW or (textSize and textSize +9 or 20), sizeW and sizeW or lastPos + 14) then
        clicked = true
    end 
    
    local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
    local text_pos_x = startPosX +4
    local text_pos_y = startPosY +6
    
    -- if fullHeight is added we align to the middle, until there's no more space
    local offset = fullHeight and fullHeight - sizeW or 0
    -- makes it centered
    if fullHeight and sizeW - offset > lastPos then
        --text_pos_y = startPosY + sizeW / 2 - textW / 2
        text_pos_y = startPosY - (offset) + fullHeight / 2 - lastPos / 2
    end
    
    
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

local function draw_clipped_text(draw_list, text, x, y, color, max_width)
  local displayed = ""
  local truncated = false
  local margin = 0
  
  local text_width = reaper.ImGui_CalcTextSize(ctx, text)
  if text_width <= max_width - margin then 
      reaper.ImGui_DrawList_AddText(draw_list, x, y, color, text)
  else  
      local dots = ".."
      local dots_width = reaper.ImGui_CalcTextSize(ctx, dots)
      local truncatedText = ""
      for i = 1, #text do
        local char = text:sub(i, i)
        local char_width = reaper.ImGui_CalcTextSize(ctx, displayed .. char .. dots)
        
        displayed = displayed .. char
        if char_width > max_width - dots_width/2 then 
            break
        end 
        
      end
      if displayed:sub(-1) == " " then displayed = displayed:sub(0,-2) end
      reaper.ImGui_DrawList_AddText(draw_list, x, y, color, displayed .. dots)
  end
end


function calculateSizeOfHeaderText(name, vertical)
    local lastPos
    if vertical then 
        lastPos = reaper.ImGui_CalcTextSize(ctx, name, 0,0) + 5  
    else 
        _, lastPos = textToPointsVertical(name,0, 0, 9.5, 3, maxTextW)
    end 
    return lastPos
end

            
function getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)

    local headerAreaRemove = math.max(headerAreaRemoveTop, headerAreaRemoveBottom)
    local headerAreaRemoveTotal = headerAreaRemoveTop + headerAreaRemoveBottom
    
    
    local headerTextX = screenPosX + (vertical and headerAreaRemove or 0)
    local headerTextY = screenPosY + (vertical and 0 or headerAreaRemove)
    local headerTextW = headerW - (vertical and headerAreaRemove * 2 or 0)
    local headerTextH = headerH - (vertical and 0 or headerAreaRemove * 2)  
    -- ensure the background takes up the full space
    local headerBgX
    local headerBgY
    local headerBgW
    local headerBgH 
    
    local headerTextWidth = calculateSizeOfHeaderText(title, vertical)  
    local align = "Center"
     
    -- could add a minimum text width size instead of the actual text width
    if (vertical and headerW or headerH) - headerAreaRemoveTotal < headerTextWidth then 
        align = "LeftLimit" 
        headerTextX = screenPosX + (vertical and headerAreaRemoveBottom or 0)
        headerTextY = screenPosY + (vertical and 0 or headerAreaRemoveTop)
        headerTextW = (vertical and headerW - headerAreaRemoveTotal or headerW)
        headerTextH = (vertical and headerH or headerH - headerAreaRemoveTotal)
    elseif (vertical and headerW or headerH) - headerAreaRemove * 2 < headerTextWidth then
        if headerAreaRemoveTop > headerAreaRemoveBottom then
            align = "Right"
            headerTextX = screenPosX + (vertical and headerAreaRemoveBottom or 0)
            headerTextY = screenPosY + (vertical and 0 or headerAreaRemoveTop)
            headerTextW = (vertical and headerW - headerAreaRemoveTotal or headerW)
            headerTextH = (vertical and headerH or headerH - headerAreaRemoveTotal)
        else 
            headerTextX = screenPosX + (vertical and headerAreaRemoveBottom or 0)
            headerTextY = screenPosY + (vertical and 0 or headerAreaRemoveTop)
            headerTextW = (vertical and headerW - headerAreaRemoveTotal or headerW)
            headerTextH = (vertical and headerH or headerH - headerAreaRemoveTotal)
            align = "Left"
        end 
    else
    end
    
    if vertical then 
        headerBgX = screenPosX + headerAreaRemoveBottom
        headerBgW = headerW - headerAreaRemoveTotal
    else 
        headerBgX = screenPosY + headerAreaRemoveTop
        headerBgW = headerH - headerAreaRemoveTotal
    end
    
    return headerTextX, headerTextY, headerTextW, headerTextH, align, headerBgX, headerBgW
end


function drawHeaderText(title, x, y, w, h, vertical, textMargin, color, align, thickness, textSize) 
    --drawInvisibleDummyButtonAtScreenPos(x,y,w,h) 
    local maxTextW = (vertical and w or h)
    local textMargin = textMargin and textMargin or 8
    -- add text margin
    local maxTextW = (vertical and w or h) - textMargin * 2
    x = x + (vertical and textMargin or 4)
    y = y + (vertical and 2 or textMargin)
    color = color and color or colorText
    
    reaper.ImGui_PushFont(ctx, textSize and _G["font"..textSize] or font15) 
    local lastPos, points
    if vertical then 
        lastPos = reaper.ImGui_CalcTextSize(ctx, title, 0,0)  
    else 
        points, lastPos = textToPointsVertical(title,0, 0, textSize and textSize * 0.633 or 9.5, 3, maxTextW)
    end 
    
    local text_pos_x = x
    local text_pos_y = y
    
    -- if there's enough room we put the text centered
    if not align or align == "Center" and maxTextW > lastPos then
        if vertical then 
            text_pos_x = x + maxTextW / 2 - lastPos / 2
        else
            text_pos_y = y + maxTextW / 2 - lastPos / 2
        end
    elseif align == "Right" then
        if vertical then 
            text_pos_x = x + maxTextW - lastPos
        else
            text_pos_y = y
        end
    elseif align == "Left" then
        if vertical then 
            text_pos_x = x
        else
            text_pos_y = y + maxTextW - lastPos
        end
    elseif align == "Left" then
        if vertical then 
            text_pos_x = x
        else
            text_pos_y = y
        end
    end
    
    --text_pos_x = text_pos_x + (vertical and textMargin or 5)
    --text_pos_y = text_pos_y + (vertical and 2 or textMargin)
    
    if vertical then   
        draw_clipped_text(draw_list, title, text_pos_x, text_pos_y, color, maxTextW)
    else 
        for _, line in ipairs(points) do
            reaper.ImGui_DrawList_AddLine(draw_list, text_pos_x + line[1], text_pos_y +line[2],  text_pos_x + line[3],text_pos_y+ line[4], color, thickness and thickness or 1.2)
        end 
    end
    reaper.ImGui_PopFont(ctx)
end

            
function drawInvisibleDummyButtonAtScreenPos(x,y,w,h) 
    w = w > 0 and w or 20
    h = h > 0 and h or 20
    reaper.ImGui_SetCursorScreenPos(ctx, x, y)
    reaper.ImGui_InvisibleButton(ctx,"dummy", w, h)
end

function drawHeaderTextAndGetHover(title, x, y, w, h, isCollabsed, vertical, textMargin, toolTipText, color, align, bgX, bgW)  
    --local isHovered = mouseInsideArea(x,y,w,h) 
    
    bgX = bgX > 0 and bgX or 20
    bgW = bgW > 0 and bgW or 20
    
    reaper.ImGui_SetCursorScreenPos(ctx, (vertical and bgX) and bgX or x, (vertical or not bgX) and y or bgX)
    reaper.ImGui_InvisibleButton(ctx, "##bg" .. x .. ":" .. y .. ":" .. w .. ":" .. h, (vertical and bgW) and bgW or headerSizeW, (vertical or not bgW) and headerSizeW or bgW)
    local isHovered = reaper.ImGui_IsItemHovered(ctx)
    color = getColorForIcon(false, isHovered, color) 
    drawHeaderText(title, x, y, w, h, vertical,textMargin, color, align)
    if isHovered then
        setToolTipFunc(toolTipText)
        return true
    end
end

  
function drawHeaderBackground(x1,y1,x2,y2, isCollabsed, vertical, bgColor, borderColor)
    local flags = isCollabsed and reaper.ImGui_DrawFlags_RoundCornersAll() or (vertical and reaper.ImGui_DrawFlags_RoundCornersTop() or reaper.ImGui_DrawFlags_RoundCornersLeft())
    reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, bgColor, 8, flags)
    if not isCollabsed then
        if vertical then
            reaper.ImGui_DrawList_AddLine(draw_list,x1, y2-1, x2, y2-1, borderColor,1)
        else
            reaper.ImGui_DrawList_AddLine(draw_list,x2-1, y1, x2-1, y2, borderColor,1)
        end
    end
end

-- gets x, y relative to the position with the offset
function getIconPosToTheLeft(vertical, pos, screenPosX, screenPosY, height)
    local posX = screenPosX + (not vertical and 0 or pos - 20)
    local posY = vertical and screenPosY or screenPosY + height - pos 
    return posX, posY
end

function getIconPosToTheRight(vertical, pos, screenPosX, screenPosY, width)
    local posX = vertical and screenPosX + width - (pos) or screenPosX
    local posY = screenPosY + (vertical and 0 or pos - 20)
    return posX, posY
end

function mouseInsideArea(x,y,w,h)
    if mouse_pos_x_imgui >= x and mouse_pos_x_imgui <= x + w and mouse_pos_y_imgui >= y and mouse_pos_y_imgui <= y + h then
        return true
    end
end

function mouseClickInAreaAndTooltip(x,y,w,h,tooltipText)
    if mouseInsideArea(x,y,w,h) then
        if isMouseClick then
            return true
        end
        if tooltipText then
            setToolTipFunc(tooltipText)
        end
    end
end


------- PLUGINS SPECIFIC -------
function getFocusedTrackFXAndContainerTable(track)
    -- we only load track fx names if plugins  panel is shown
    local focusedTrackFXNames = getAllTrackFXOnTrack(track)
    
    -- adding keys for dragging etc
    local trackFxTableWithIndentIndicators = {}
    function findAndAddNextIndexOneLevelDown(i, indent) 
        local newF = {name = "<"}
        for i2 = i, 1, -1 do
            local lookAt = focusedTrackFXNames[i2]
            if lookAt.isContainer and indent == lookAt.indent then  
                local subContainerPath = get_container_path_from_fx_id(track, lookAt.fxIndex) 
                newF.fxIndex = lookAt.fxIndex
                newF.indent = indent
                if subContainerPath and #subContainerPath > 1 then 
                    subContainerPath[#subContainerPath] = subContainerPath[#subContainerPath] + 1
                    newF.dropIndex = get_fx_id_from_container_path(track, table.unpack(subContainerPath))  
                else
                    newF.dropIndex = lookAt.fxIndex + 1
                end  
                newF.fxContainerName = lookAt.fxContainerName
                newF.fxContainerIndex = lookAt.fxContainerIndex
                newF.isModulator = lookAt.isModulator
                newF.seperator = true
                table.insert(trackFxTableWithIndentIndicators, newF) 
                break;
            end 
        end 
    end
    
    -- find layers and sublayers of containers
    for i, f in ipairs(focusedTrackFXNames) do  
        if i == 1 then 
            table.insert(trackFxTableWithIndentIndicators, {name = "<", seperator = true, indent = 0, fxIndex = 0, dropIndex = 0})  
        end
        local containerPath = get_container_path_from_fx_id(track, f.fxIndex)
        local currentIndent = f.indent
        local nextFxInfo = i < #focusedTrackFXNames and focusedTrackFXNames[i + 1]
        local simpleName = f.name
        
        if settings.hidePluginTypeName then
            simpleName  = simpleName:gsub("^[^:]+: ", "")
        end
        if settings.hideDeveloperName then
            simpleName  = simpleName:gsub("%s*%b()", "")
        end
        
        f.simpleName = simpleName 
        f.dropIndex = f.fxIndex
        
        -- adding drop index to actual fx
        if f.indent == 0 then
            if f.isContainer then 
                f.dropIndex = get_fx_id_from_container_path(track, table.unpack({f.fxIndex + 1, 1})) 
            else
                f.dropIndexToLower = f.fxIndex + 1
            end
        else 
            if f.isContainer and nextFxInfo and nextFxInfo.indent > currentIndent then  
                f.dropIndex = nextFxInfo.fxIndex
            else
                if f.isContainer then
                    table.insert(containerPath, 1)
                    f.dropIndex = get_fx_id_from_container_path(track, table.unpack(containerPath)) 
                else
                    if not containerPath then  
                        reaper.ShowConsoleMsg(appName .. " ERROR!\nPlugin name: " .. f.name .. ", indent: " .. f.indent .. "\nThere's an issue getting the info from a FX or modulator. If this issue is consistent, please write a bug report so we can solve this together\n\n")
                    else
                        containerPath[#containerPath] = containerPath[#containerPath] + 1
                        f.dropIndexToLower = get_fx_id_from_container_path(track, table.unpack(containerPath)) 
                    end
                end
            end
        end
        
        -- insert original layers with added drop index
        table.insert(trackFxTableWithIndentIndicators, f)  
        
        -- find layers that when going out of a container
        if nextFxInfo and nextFxInfo.indent < currentIndent then  
            for indent = currentIndent -1, nextFxInfo.indent, -1 do  
                findAndAddNextIndexOneLevelDown(i, indent)  
            end
        end
         
        if f.isContainer then 
            -- find layer when container is the last
            local _, fxAmountInContainer = GetNamedConfigParm(track, f.fxIndex, "container_count") 
            if tonumber(fxAmountInContainer) == 0 then
                findAndAddNextIndexOneLevelDown(i, f.indent)  
            end 
        end 
        if (not f.isContainer and i == #focusedTrackFXNames and f.indent > 0) then
            -- find layer when fx is the last within a container
            for indent = currentIndent -1, 0, -1 do  
                findAndAddNextIndexOneLevelDown(i, indent)
            end
        end 
    end
    return focusedTrackFXNames, trackFxTableWithIndentIndicators
end


function openAllAddTrackFX(width) 
    if settings.showOpenAll == true or settings.showAddTrackFX or settings.showAddTrackFXDirectly or settings.showAddContainer then
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
        
        local elementsAmount = 0
        
        if settings.showOpenAll then elementsAmount = elementsAmount + 1 end
        if settings.showAddTrackFX then elementsAmount = elementsAmount + 1 end
        if settings.showAddTrackFXDirectly then elementsAmount = elementsAmount + 1 end
        if settings.showAddContainer then elementsAmount = elementsAmount + 1 end
        
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorDarkGrey)
        local elementsWidth = (width - ( 8 * (elementsAmount-1))) / elementsAmount
        local sameLine = false
        if settings.showOpenAll then
            local textState = (not allIsClosed and "Close " or "Open ")
            if reaper.ImGui_Button(ctx, textState .. ' all##FXOpenall', elementsWidth) then 
                for _, f in ipairs(focusedTrackFXNames) do 
                    if not f.isModulator then
                        openCloseFx(track, tonumber(f.fxIndex), allIsClosed)
                    end
                end
            end  
            setToolTipFunc(textState .. "all FX windows")
            sameLine = true
        end
        
        if settings.showAddTrackFX then
            if sameLine then
                reaper.ImGui_SameLine(ctx)
            end
            
            if reaper.ImGui_Button(ctx, "+##add", elementsWidth) then  
                openAddFXPopupWindow = true
            end
            setToolTipFunc("Add new FX, container or preset to track")
            sameLine = true
            
        end
        
        
        if settings.showAddTrackFXDirectly then
            if sameLine then
                reaper.ImGui_SameLine(ctx)
            end
            
            if reaper.ImGui_Button(ctx, "Add FX##addTrackFX", elementsWidth) then   
                doNotMoveToModulatorContainer, browserHwnd, browserSearchFieldHwnd, insertAtFxIndex, fx_before = addFxViaBrowser(track, fxnumber)
                pathForNextIndex = getPathForNextFxIndex(track, insertAtFxIndex)
                moveToModulatorContainer = false
            end
            setToolTipFunc("Add new FX to track")
            sameLine = true 
        end
        
        if settings.showAddContainer then
            if sameLine then
                reaper.ImGui_SameLine(ctx)
            end
            
            if reaper.ImGui_Button(ctx, "Container##add", elementsWidth) then  
                fxnumber = addFxAfterSelection(track, fxnumber, "Container")
            end
            setToolTipFunc("Add new Container to track")
        end
        --reaper.ImGui_PopStyleColor(ctx)
        
        if settings.showPluginOptionsOnTop then  
            reaper.ImGui_Separator(ctx)
            --reaper.ImGui_Spacing(ctx)
           -- local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
           -- reaper.ImGui_DrawList_AddLine(draw_list, x, y-1, x + width - 12, y-1, colorTextDimmed)
        end
    end
end

function clickPlugin(f, openTag, forceFolderToggle)
    if (isOpenFolder or forceFolderToggle) and f.isContainer then
        openCloseFolder(track,f.fxIndex)
    elseif isRemoveFX then
        DeleteFX(track, f.fxIndex)  
    elseif isBypassFX then
        BypassFX(track, f.fxIndex) 
    elseif isOfflineFX then
        OfflineFX(track, f.fxIndex)  
    elseif isChangeParallel then
        setFXParallelProcess(track, f.fxIndex) 
    elseif isRenameFX then
        openRename = true
        renameFxIndex = f.fxIndex  
    else
        if not openTag then
            openCloseFx(track, f.fxIndex, not f.isOpen)
        else
            return true
        end
    end
end 


function getTextColorForFx(track, f, useContainerColor)
    local isEnabled = GetFXEnabled(track, f.fxIndex)
    local isOffline = GetFXOffline(track, f.fxIndex)
    local textColor = settings.colors.text
    if partOfContainer then
        textColor = settings.colors.mapping
    elseif isOffline then
        textColor = colorRedHidden
    elseif not isEnabled then
        textColor = colorYellowMinimzed 
    elseif (f.isContainer or f.name == "<") then
        textColor = settings.colorContainers and ((useContainerColor and trackSettings.containerColors[f.guid]) and trackSettings.containerColors[f.guid] or (f.indent and indentColors[(f.indent)%3 + 1])) or settings.colors.text
    end
    return textColor
end

function getButtonToolTipText(f) 
    local isEnabled = GetFXEnabled(track, f.fxIndex)
    local isOffline = GetFXOffline(track, f.fxIndex)
    
    local tooltipOpen = (not f.isOpen and "Open " or "Close ") .. f.name .. " window"
    local tooltipFocus = "Click to focus on " .. f.name .. " parameters\n- Double click to open or close"
    local toolTipExtra = ""  
    toolTipExtra = toolTipExtra .. "\n- ".. convertModifierOptionToString(settings.modifierOptionFx.bypassFX) .. ' to ' .. (isEnabled and "bypass" or "enable") .. ' FX'
    toolTipExtra = toolTipExtra .. "\n- ".. convertModifierOptionToString(settings.modifierOptionFx.offlineFX) .. ' to ' .. (isOffline and "online" or "offline") .. ' FX'
    toolTipExtra = toolTipExtra .. "\n- ".. convertModifierOptionToString(settings.modifierOptionFx.removeFX) .. ' to remove FX'
    toolTipExtra = toolTipExtra .. "\n- ".. convertModifierOptionToString(settings.modifierOptionFx.renameFX) .. ' to rename FX'
    local parallel = getFXParallelProcess(track, f.fxIndex)
    
    toolTipExtra = toolTipExtra .. "\n- ".. convertModifierOptionToString(settings.modifierOptionFx.changeParallel) .. ' to change FX parallel setting.\n  ' .. (parallel == 0 and " >" or " ") .. "No parallel process\n  " .. (parallel == 1 and " >" or " ") ..  "Process parallel with previous\n  " .. (parallel == 2 and " >" or " ") .. "Process parallel and merge MIDI"
    
    if f.isContainer then
        toolTipExtra = toolTipExtra .. "\n- ".. convertModifierOptionToString(settings.modifierOptionFx.openFolder) .. ' to ' .. (not isFolderClosed and "open" or "close") .. ' FX'
    end
    toolTipExtra = toolTipExtra .. "\nDrag to move\n   - Hold " .. convertModifierOptionToString(settings.modifierOptionFx.copyFX) .. ' to copy'
    
    return {tooltipOpen, tooltipFocus, tooltipOpen .. toolTipExtra, tooltipFocus .. toolTipExtra}
end

                    
function registrerDragAndDrop(x1,y1,x2,y2,f) 
    if mouse_pos_x_imgui > x1 and mouse_pos_x_imgui < x2 and mouse_pos_y_imgui > y1 and mouse_pos_y_imgui < y2 then 
        if isMouseClick and not beginDragAndDropFXName then
            beginFxDragAndDropName = f.simpleName  
            beginFxDragAndDropFX = f
            beginFxDragAndDropIndex = f.fxIndex
            
        end
        if isMouseDragging and beginFxDragAndDropFX and not beginFxDragAndDrop then
            beginFxDragAndDrop = true
            HideToolTipTemp = true
        end
    end
end

function dragDropInArea(x1,y1,x2,y2,f, indentW) 
    if beginFxDragAndDrop then
        if mouse_pos_x_imgui > x1 and mouse_pos_x_imgui < x2 and mouse_pos_y_imgui > y1 and mouse_pos_y_imgui < y2 then  
            --if dropAllowed then --beginFxDragAndDropIndex ~= f.fxIndex and beginFxDragAndDropIndex ~= f.dropIndex then -- and beginFxDragAndDropFX.dropIndex ~= f.fxIndex and beginFxDragAndDropFX.dropIndex ~= f.dropIndex  then
                --indent = f.indent --f.isContainer and f.indent + 1 or f.indent  
                if indentW > 0 then reaper.ImGui_Indent(ctx, indentW) end
                reaper.ImGui_Separator(ctx)
                
                local extensionName
                if f.fxContainerName then
                    if f.isContainer then
                        extensionName = f.simpleName
                    elseif f.fxContainerName ~= "ROOT" then
                        extensionName = f.fxContainerName 
                    end
                end
                if extensionName then
                    beginFxDragAndDropNameExtension = " in to " .. extensionName
                else 
                    beginFxDragAndDropNameExtension = ""
                end
                
                if indentW > 0 then reaper.ImGui_Unindent(ctx, indentW) end
                if isMouseWasReleased then
                    local useNextIndex = f.dropIndex < beginFxDragAndDropIndex or beginFxDragAndDropFX.fxContainerIndex ~= f.fxContainerIndex
                    beginFxDragAndDropIndexRelease = useNextIndex and f.dropIndexToLower or f.dropIndex 
                end
            --end
        end
    end
end

-------- PARAMETERS SPECIFIC ------------

function setAlpha(color, alpha_hex)
  return (color & 0xFFFFFF00) | (alpha_hex & 0xFF)
end

function getColorForIcon(isActive, isHovered, color) 
    color = color and color or (isActive and colorMapping or colorWhite)
    local fullAlpha = (color & 0xFF) == 0xFF 
    color = isHovered and setAlpha(color, fullAlpha and 0xFFFFFF99 or 0xFFFFFFAA) or color
    return color
end


function drawOpenSearch(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size) 
    local pad = 4
    local pad_x = x + pad - 1
    local pad_y = y + pad - 1
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    reaper.ImGui_DrawList_AddCircle(draw_list, pad_x + pad_size/2, pad_y + pad_size/2, pad_size/2.5, color, nil, 1) 
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x + pad_size/4*3, pad_y + pad_size/4*3, pad_x + pad_size, pad_y+pad_size, color, 2)
    
    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc(toolTipText)
    end
end


function drawListArrayIcon(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size) 
    local pad = 4
    local pad_x = x + pad - 0.5
    local pad_y = y + pad - 1
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    local pad_y_1 = pad_y + pad_size / 5
    local pad_y_2 = pad_y + pad_size / 2
    local pad_y_3 = pad_y + pad_size / 5*4
    
    local pad_x_1 = pad_x + pad_size / 7
    local pad_x_2 = pad_x + pad_size / 4
    local pad_x_3 = pad_x + pad_size
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_1, pad_x_1, pad_y_1, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_2, pad_x_1, pad_y_2, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_3, pad_x_1, pad_y_3, color, 1) 
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y_1, pad_x_3, pad_y_1, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y_2, pad_x_3, pad_y_2, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y_3, pad_x_3, pad_y_3, color, 1)
  
    
    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc(toolTipText)
    end
end


function drawListIcon(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size) 
    local pad = 4
    local pad_x = x + pad - 0.5
    local pad_y = y + pad - 1
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    local pad_y_1 = pad_y + pad_size / 5
    local pad_y_2 = pad_y + pad_size / 2
    local pad_y_3 = pad_y + pad_size / 5*4
    
    local pad_x_1 = pad_x + pad_size / 7
    local pad_x_2 = pad_x + pad_size / 4
    local pad_x_3 = pad_x + pad_size
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_1, pad_x_3, pad_y_1, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_2, pad_x_3, pad_y_2, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_3, pad_x_3, pad_y_3, color, 1) 
    
    --[[
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_1, pad_x_1, pad_y_1, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_2, pad_x_1, pad_y_2, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y_3, pad_x_1, pad_y_3, color, 1) 
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y_1, pad_x_3, pad_y_1, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y_2, pad_x_3, pad_y_2, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y_3, pad_x_3, pad_y_3, color, 1)
    ]]
    
    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc(toolTipText)
    end
end

function drawListHorizontalIcon(x, y, size, isActive, toolTipText, threeStagesThisIsOnOff) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size) 
    local pad = 4
    local pad_x = x + pad - 0.5
    local pad_y = y + pad - 1
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local useThreeStages = threeStagesThisIsOnOff ~= nil
    local sideLineColorStageOff = not isActive and threeStagesThisIsOnOff
    if useThreeStages then
        isActive = threeStagesThisIsOnOff 
    end
    
    local color = getColorForIcon(isActive, isHovered) 
    local colorSide = sideLineColorStageOff and getColorForIcon(false, isHovered) or color
    
    local pad_y_1 = pad_y + pad_size
    
    local pad_x_1 = pad_x + pad_size / 8
    local pad_x_2 = pad_x + pad_size / 2
    local pad_x_3 = pad_x + pad_size / 8*7
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_1, pad_y, pad_x_1, pad_y_1, colorSide, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_2, pad_y, pad_x_2, pad_y_1, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x_3, pad_y, pad_x_3, pad_y_1, colorSide, 1) 
    
    
    
    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc(toolTipText)
    end
end

function drawSortingIcon(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size) 
    local pad = 3
    local pad_x = x + pad 
    local pad_y = y + pad
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    reaper.ImGui_PushFont(ctx, font9)
    reaper.ImGui_DrawList_AddText(draw_list, pad_x+2, pad_y + 2.5, color, "AZ")
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_DrawList_AddRect(draw_list, pad_x, pad_y, pad_x + pad_size, pad_y + pad_size - 1, color & 0xFFFFFF99 , 3)
    

    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc(toolTipText)
    end
end

function drawMapOnceIcon(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size) 
    local pad = 4
    local pad_x = x + pad
    local pad_y = y + pad
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    --reaper.ImGui_DrawList_AddCircle(draw_list, pad_x + pad_size/2, pad_y + pad_size/2, pad_size/2.5, color, nil, 1) 
    
    reaper.ImGui_DrawList_PathArcTo(draw_list, pad_x + pad_size*0.5, pad_y + pad_size*0.5, pad_size*0.5, 3.141592 * 0.75, 3.141592 * 2.25)
    reaper.ImGui_DrawList_PathStroke(draw_list, color & 0xFFFFFF99, reaper.ImGui_DrawFlags_None(), 1)
    
    reaper.ImGui_PushFont(ctx, font10)
    reaper.ImGui_DrawList_AddText(draw_list, pad_x + pad_size /4, pad_y + pad_size / 5, color, "1")
    reaper.ImGui_PopFont(ctx)
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x + pad_size/4*3, pad_y + pad_size/5*4, pad_x + pad_size, pad_y+pad_size/5*4, color, 1)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x + pad_size/4*3, pad_y + pad_size/5*4, pad_x + pad_size/4*3, pad_y+pad_size/2, color, 1)
    
    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc(toolTipText)
    end
end

function drawOpenFXWindow(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size)
    local rounding = 1
    local pad = 4
    local pad_x = x + pad
    local pad_y = y + pad
    local pad_w = size - pad * 2
    local pad_h = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    reaper.ImGui_DrawList_AddRectFilled(draw_list,pad_x, pad_y, pad_x + pad_w, pad_y + pad_h, color & 0xFFFFFF44, rounding) 
    reaper.ImGui_DrawList_AddRect(draw_list,pad_x, pad_y, pad_x + pad_w, pad_y + pad_h, color, rounding) 
    reaper.ImGui_DrawList_AddRectFilled(draw_list,pad_x, pad_y, pad_x + pad_w, pad_y + pad_h / 3, color, rounding) 
    
    if isHovered then
        if isMouseClick then
            return true
        end
        setToolTipFunc2((isActive and "Close " or "Open ") .. toolTipText)
    end
end


function drawPlusIcon(x, y, size, isActive, toolTipText) 
    drawInvisibleDummyButtonAtScreenPos(x,y,size,size)
    local rounding = 1
    local pad = 5
    local pad_x = x + pad
    local pad_y = y + pad
    local pad_w = size - pad * 2
    local pad_h = size - pad * 2
    
    local pad_size = size - pad * 2
    local angle = 4
    local isHovered = mouseInsideArea(x,y,size,size) 
    local color = getColorForIcon(isActive, isHovered) 
    
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x, pad_y + pad_size/2, pad_x + pad_size, pad_y+pad_size/2, color, 2)
    reaper.ImGui_DrawList_AddLine(draw_list, pad_x + pad_size/2, pad_y, pad_x + pad_size/2, pad_y+pad_size, color, 2)
    
    
    if isHovered then
        if isMouseClick then
            return true
        end
        if toolTipText then
            setToolTipFunc2((isActive and "Close " or "Open ") .. toolTipText)
        end
    end
end


-- SPECIFIC FOR FX PARAMETER WINDOW
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

function searchAndOnlyMapped(track, fxIndex, searchAreaH, drawingWidth, showOnlyFocusedPlugin) 
    local guid = GetFXGUID(track,fxIndex)
    local param = trackSettings.focusedParam and trackSettings.focusedParam[guid]
    local showingLastClicked = settings.showLastClicked and fxIndex and param
    --local showOnlyFocusedPlugin = settings.showOnlyFocusedPluginGlobal and settings.showOnlyFocusedPlugin or trackSettings.showOnlyFocusedPlugin
    if (showOnlyFocusedPlugin or settings.showParametersOptionOnAllPlugins) and (settings.showOnlyMappedAndSearchOnFocusedPlugin or settings.showLastClicked) then
        function lastClickDraw(searchAreaH) 
            if settings.showLastClicked then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorTransparent)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed)
                
                if showingLastClicked then  
                    p = param and getAllDataFromParameter(track,fxIndex,param) or {}
                    pluginParameterSlider("parameterLastClicked",p ,nil,nil,nil,nil,drawingWidth,nil,nil,nil,true, nil, useKnobs, false) 
                    if (not p.parameterLinkActive) and settings.showMappedModulatorNameBelow and (not settings.showMidiLearnIfNoParameterModulation or not p.midiLearnText) then
                        reaper.ImGui_InvisibleButton(ctx, "dummy", drawingWidth, 8)
                    end
                else
                    --reaper.ImGui_Button(ctx, " - No parameter clicked - ", moduleWidth, searchAreaH)
                    reaper.ImGui_Button(ctx, "- click a parameter -", drawingWidth, searchAreaH)
                end 
                reaper.ImGui_PopStyleColor(ctx, 4) 
            end 
        end
        
        if not settings.showParameterOptionsOnTop then 
            reaper.ImGui_Separator(ctx)
            lastClickDraw(searchAreaH)  
        end
        
        if settings.showOnlyMappedAndSearchOnFocusedPlugin and guid then
            local isShowing = false
            if showOnlyFocusedPlugin then 
                isShowing = settings.onlyMapped
            else
                isShowing = trackSettings.onlyMapped[guid] or false
            end
            
            local ret, onlyMapped = reaper.ImGui_Checkbox(ctx, "##Only mapped" .. guid, isShowing)
            if ret then 
                if onlyMapped then
                    --trackSettings.searchParameters[guid] = ""
                end
                if showOnlyFocusedPlugin then
                    settings.onlyMapped = onlyMapped
                    saveSettings()
                else
                    trackSettings.onlyMapped[guid] = onlyMapped 
                    saveTrackSettings(track) 
                end
            end 
            setToolTipFunc("Show only mapped parameters")
            
            reaper.ImGui_SameLine(ctx) 
            
            local posX = reaper.ImGui_GetCursorPosX(ctx) - (settings.showOnlyMappedAndSearchOnFocusedPlugin and 4 or 0)
            reaper.ImGui_SameLine(ctx, posX)
            local searchWidth = drawingWidth - posX - 4 - 8
            reaper.ImGui_SetNextItemAllowOverlap(ctx)
            reaper.ImGui_SetNextItemWidth(ctx, searchWidth)
            if focusSearchParameters == guid then
                reaper.ImGui_SetKeyboardFocusHere(ctx)
                focusSearchParameters = nil
            end
            
            if not trackSettings.searchParameters[guid] then trackSettings.searchParameters[guid] = "" end
            ret, search = reaper.ImGui_InputText(ctx,"##SearchParameter" .. guid, trackSettings.searchParameters[guid]) 
            if search ~= trackSettings.searchParameters[guid] then
                trackSettings.searchParameters[guid] = search
                if settings.searchClearsOnlyMapped then
                    trackSettings.onlyMapped[guid] = false
                    settings.onlyMapped = false
                end
                saveTrackSettings(track)
            end
            
            if reaper.ImGui_IsItemFocused(ctx) then 
                ignoreKeypress = true
            end
            
            reaper.ImGui_SameLine(ctx, posX + searchWidth-8)
            local hasSearch = trackSettings.searchParameters[guid] and trackSettings.searchParameters[guid] ~= ""
            if drawSearchIcon(20, "clearSearchParameter" .. guid, 0, 0, colorWhite, hasSearch and "Clear search" or "Search for parameters") then
                if hasSearch then
                    trackSettings.searchParameters[guid] = ""
                    saveTrackSettings(track)
                end
                focusSearchParameters = guid
            end
        end
        
        if settings.showParameterOptionsOnTop then  
            lastClickDraw(searchAreaH) 
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), colorText & 0xFFFFFFFF88)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_PopStyleColor(ctx)
            
        end
    end
end



--------- SPECIFIC FOR MODULATORS -------------

                
                
------------------------
-- MODULATORS ----------
------------------------


    
    
        
        
function mapAndShow(track, fx, mapParam, fxInContainerIndex, name) 
    reaper.ImGui_BeginGroup(ctx)
    local isCollabsed = trackSettings.collabsModules[fx.guid]
    local h = isCollabsed and 20 or buttonWidth/(not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 2 or 3)
    local w = buttonWidth * (not (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 1 or 2)
    
    local isShowing = trackSettings.showMappings[fx.guid] 
    local isMapping = mapActiveFxIndex == fx.fxIndex and mapActiveParam == mapParam
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isMapping and settings.colors.mapping or settings.colors.buttons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),isMapping and settings.colors.mapping or colorButtonsHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),isMapping and settings.colors.mapping or colorButtonsActive)
    
    if reaper.ImGui_Button(ctx, isMapping and "MAPPING" or "MAP", w, h) then 
        mapModulatorActivate(fx.fxIndex,mapParam, fx.fxInContainerIndex, name)
    end
    
    reaper.ImGui_PopStyleColor(ctx, 3) 
     
    local text = (mapActiveFxIndex and (not isMapping and ("Click to map " .. mapActiveName .. "\nPress escape to stop mapping") or "Click or press escape to stop mapping") or "Click to map output")
    if settings.showToolTip then
        reaper.ImGui_SetItemTooltip(ctx, text)
    end 
    
    reaper.ImGui_EndGroup(ctx)
end

function modulatorGuiIsOpen(track, fxIndex, gui)
    if gui then 
        isFxOpen = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible' ))) == 1                  
    else
        isFxOpen = GetOpen(track,fxIndex)
        fxIsFloating = GetFloatingWindow(track,fxIndex)
    end
    return isFxOpen
end

function openCloseModulatorGui(track, fxIndex, gui, isFxOpen)
    if gui then
        SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible',isFxOpen and 0 or 1  )
    else
        --[[if fxIsShowing and fxIsFloating == nil then
            SetOpen(track,fxIndex, false)
        else
            showFX(track, fxIndex, fxIsShowing and 2 or 3)  
        end]]
        openCloseFx(track, fxIndex, not fxIsFloating) 
    end
end

function openGui(track, fxIndex, name, gui, extraIdentifier, isCollabsed, sizeW, sizeH, visualizerSize) 
    if gui then 
        fxIsShowing = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible' ))) == 1                  
    else
        fxIsShowing = GetOpen(track,fxIndex)
        fxIsFloating = GetFloatingWindow(track,fxIndex)
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
            SetNamedConfigParm( track, fxIndex, 'param.'.."1"..'.mod.visible',fxIsShowing and 0 or 1  )
        else
            --[[if fxIsShowing and fxIsFloating == nil then
                SetOpen(track,fxIndex, false)
            else
                showFX(track, fxIndex, fxIsShowing and 2 or 3)  
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
    local isShowing = floating and settings[floating .."ShowMappings"] or trackSettings.showMappings[fx.guid] 
    local colorBg = isShowing and colorLightGrey or colorDarkGrey
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),isShowing and colorMapping or colorMappingLight)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), settings.colors.buttonsSpecial)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),settings.colors.buttonsSpecialHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),settings.colors.buttonsSpecialActive)
    local tv = #mappings -- (isShowing and ">" or "^")
    
    reaper.ImGui_PushFont(ctx, font11) 
    local size = 15
    if reaper.ImGui_Button(ctx,  "##" .. fxIndex .. tostring(floating), size,size) then
       --[[ if floating then
            settings[floating .."ShowMappings"] = not settings[floating .."ShowMappings"]
            saveSettings()
        else
            trackSettings.showMappings[fx.guid] = not isShowing 
            saveTrackSettings(track)
        end]]
    end 
    
    local bX, bY = reaper.ImGui_GetItemRectMin(ctx)
    local bX2, bY2 = reaper.ImGui_GetItemRectMax(ctx)
    
    if reaper.ImGui_IsMouseHoveringRect(ctx, bX, bY, bX2, bY2) then
        if isMouseClick then
            if floating then
                settings[floating .."ShowMappings"] = not settings[floating .."ShowMappings"]
                saveSettings()
            else
                trackSettings.showMappings[fx.guid] = not isShowing 
                saveTrackSettings(track)
            end
        end
    end
    
    
    
    local textW, textH = reaper.ImGui_CalcTextSize(ctx, tv, 0,0)
    reaper.ImGui_DrawList_AddText(draw_list, bX - textW / 2 + 8, bY - textH/ 2 + 8,colorMapping, tv)
    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx,2)
    
    reaper.ImGui_PopFont(ctx)
    
    setToolTipFunc((isShowing and "Hide" or "Show" ) .. " " .. #mappings .." mappings")
end




local function drawFaderFeedback(sizeW, sizeH, fxIndex, param, min, max, isCollabsed, fx, index, buttonWidth)
    local sizeId =  4-- isCollabsed and (settings.vertical and 1 or 2) or ((trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and 4 or 3)
    
    local sizeId = isCollabsed and 1 or (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
    if sizeId == 0 then
        sizeId = 1
    end
    
    local waveFormSize = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid])
    if not inputPlots then inputPlots = {}; timers = {}; offset = {}; phase = {} end
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
          w = modulatorParameterWidth,
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
    
    -- ret, value = GetNamedConfigParm( track, modulatorsPos, 'container_map.get.' .. fxIndex .. '.2' )
    local value = GetParamNormalized(track,fxIndex,param)
    for i = 1, #valuesForPlotting do 
        local idTimer = fx.guid.. i  .. param
        local timerPlotAmount = valuesForPlotting[i].p
        
        if not inputPlots[idTimer] then 
            inputPlots[idTimer] = reaper.new_array(timerPlotAmount); 
            for t = 1, timerPlotAmount do 
                inputPlots[idTimer][t] = value
            end
        end
        if not timers[idTimer] then timers[idTimer] = ImGui.GetTime(ctx) end
        if not offset[idTimer] then offset[idTimer] = 1 end
        if not phase[idTimer] then phase[idTimer] = 0 end
        
        while timers[idTimer] < ImGui.GetTime(ctx) do -- Create data at fixed 60 Hz rate
            inputPlots[idTimer][offset[idTimer]] = value -- math.cos(phase[idTimer])--value
            offset[idTimer] = (offset[idTimer] % timerPlotAmount) + 1
            --phase[idTimer] = phase[idTimer] + (offset[idTimer] * 0.1)
            timers[idTimer] = timers[idTimer] + (1.0 / 120.0)
        end
    end
    
    local isMapping = mapActiveFxIndex == fxIndex and mapActiveParam == param
    
    nameOverlay = ""
    nameForMapping = fx.name
    if #fx.output > 1 then
        paramName = GetParamName(track, fxIndex, param)
        nameForMapping = nameForMapping .. ": " .. paramName
        if fx.outputNames and fx.outputNames[index] then
            nameOverlay = fx.outputNames[index]
        else
            nameOverlay = paramName
        end
    end
    --end
    local posX, posY = reaper.ImGui_GetCursorPos(ctx) 
    local toolTip = (mapActiveFxIndex and (not isMapping and ("Click to map " .. nameForMapping .. "\nPress escape to stop mapping " .. mapActiveName) or "Click or press escape to stop mapping") or "Click to map " .. nameForMapping .."\n - hold Super to change size" )
    --local toolTip = (sizeId == 1 or sizeId == 2) and "Click to map output" or (sizeId == 4 and "Click to make waveform small" or "Click to make waveform big")
    local mappingW = reaper.ImGui_CalcTextSize(ctx, "MAPPING", 0 , 0)
    local id = fx.guid .. sizeId .. param
    --local nameOverlay = "" -- (mapActiveFxIndex and isMapping) and ((isCollabsed or sizeW < mappingW) and "M" or "MAPPING") or ""
    clicked = reaper.ImGui_Button(ctx, "##plotLinesButton" .. id ,sizeW,sizeH)
    local lineX, lineY = reaper.ImGui_GetItemRectMin(ctx)
    if settings.showToolTip then setToolTipFunc(toolTip) end

    if nameOverlay then
        local textW, textH = reaper.ImGui_CalcTextSize(ctx, nameOverlay, 0,0)
        reaper.ImGui_DrawList_AddText(draw_list, lineX + sizeW/2 - textW/2, lineY + sizeH/2 - textH/2,  settings.colors.modulatorOutput & 0xFFFFFFFF99, nameOverlay)
    end
    
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
     
    --if reaper.ImGui_IsItemHovered(ctx) then
    --    reaper.ImGui_SetTooltip(ctx,toolTip)
    --end
    
    
    --

    return clicked
end



function drawOutputFromModulator(name, fx, output, outputArray, isCollabsed, modulatorWidth, modulatorHeight)
    local size = 18
    local offsetX = 0 
    if isCollabsed then
        --reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-7, reaper.ImGui_GetCursorPosY(ctx))
    
        local widthOfHeader = findWidthOfHeaderHorizontal(name, outputArray, modulatorHeight)
        local rowsNeeded = math.floor((widthOfHeader - size -2) / size)
        if rowsNeeded > 0 then 
            startX, startY = reaper.ImGui_GetCursorPos(ctx)
            reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx) + offsetX, reaper.ImGui_GetCursorPosY(ctx)) 
            cutPoint = math.floor(#outputArray / rowsNeeded)
        end
        
        for i, output in ipairs(outputArray) do 
            if cutPoint and cutPoint > 0 and rowsNeeded > 0 then
                local offsetX = math.ceil(i/cutPoint ) * size
                local offsetY = math.ceil((i-1)%cutPoint ) * size 
                reaper.ImGui_SetCursorPos(ctx, 1 + offsetX, 1 + offsetY)
            else 
                if i > 1 then  
                    reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx) - 7, reaper.ImGui_GetCursorPosY(ctx)-4)
                end
            end
            
            if drawFaderFeedback(size,size, fx.fxIndex, output, 0, 1, isCollabsed, fx, i, modulatorWidth -30 / 2 ) then 
                mapModulatorActivate(fx,output, name, nil, #outputArray == 1)
            end     
        end
    end
end


function modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, func, name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx, genericModulatorInfo, outputArray)
    
    local useKnobs = settings.useKnobsModulator
    local useNarrow = (settings.useKnobsModulator == nil and not settings.useNarrowModulator) and settings.useNarrow or settings.useNarrowModulator
    
    
    local width = modulatorWidth
    local height = modulatorHeight 
    local heightAutoAdjust = floating and true or not (not vertical or not settings.limitModulatorHeightToModulesHeight)
    if isCollabsed then
        heightAutoAdjust = false
    end
    
    
    reaper.ImGui_BeginGroup(ctx)
    local valuesFromModulator
    
    local mappings = fx.mappings
    
    local toolTipText = ((isCollabsed and "Maximize " or "Minimize ") .. name .. "\n - right click for more options")
    
    local minX, minY, maxX, maxY = false, false, false, false
    
    
    --local flags = reaper.ImGui_TableFlags_BordersOuter()
    --flags = not isCollabsed and flags or flags | reaper.ImGui_TableFlags_NoPadOuterX() --| reaper.ImGui_TableFlags_RowBg()
    -- ignore scroll if alt is pressed
    --flags = not vertical and flags | reaper.ImGui_TableFlags_ScrollY() or flags
    local hasGui = fx.fxName:match("ACS Native Modulator") ~= nil
    local showOpenGui = false
    local fxName = fx.fxName
    if fx.genericModulatorInfo then
        showOpenGui = true
    else
        for _, mod in ipairs(factoryModules) do
            if mod.showOpenGui and (fxName == mod.insertName or fxName:match(mod.insertName) ~= nil) then
                showOpenGui = true
                break;
            end
        end
    end
    
    local sizeId = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
    

    
    local modulatorStartPosX, modulatorStartPosY = reaper.ImGui_GetCursorScreenPos(ctx)
    
    local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
    
    local openPopupForModule = false
    
    local title = name
    
    
    vertical = not isCollabsed and settings.preferHorizontalHeaders or vertical
    
    local size = 18
    local cutPoint = math.floor((vertical and width or height) / headerSizeWM)
    if cutPoint < 1 then cutPoint = 1 end 
    local rowsNeeded = math.ceil(#outputArray / cutPoint)
    local amountInEachRow = #outputArray / rowsNeeded
    --local headerAreaRemove = 20
    
    local headerW = (vertical or isCollabsed) and width or headerSizeW
    local headerH = vertical and headerSizeW or height 
    local headerSize = vertical and headerH or headerW
    
    local outputsSizeW = #outputArray * headerSizeWM + 4
    local headerTextWidth = calculateSizeOfHeaderText(name, vertical) 
    local headerAreaRemoveTop = 0
    
    
    local headerAreaRemoveBottom = 18 
    if showOpenGui then
        headerAreaRemoveBottom = headerAreaRemoveBottom + 20 
    end 
    if settings.showRemoveCrossModulator then
        headerAreaRemoveBottom = headerAreaRemoveBottom + 16 
    end
    
    local outputOnItsOwnLine = false
     
    
    
    if isCollabsed or sizeId == 0 then
        headerAreaRemoveTop = outputsSizeW
        --local headerAreaRemoveTotal = headerAreaRemoveTop + headerAreaRemoveBottom
        
        if #outputArray > 1 and (vertical and headerW or headerH) - outputsSizeW - headerAreaRemoveBottom - 2 < headerTextWidth then 
           headerAreaRemoveTop = 0
           outputOnItsOwnLine = true 
           if vertical then  
              headerH = headerSizeW + headerSizeWM * rowsNeeded
              if isCollabsed then
                  height = headerH 
              else
                  height = height + headerH 
              end
              headerSize = headerH
           else 
              headerW = headerSizeW + headerSizeWM * rowsNeeded
              if isCollabsed then
                  width = headerW
              else
                  width = width + headerW
              end
              headerSize = headerW
           end
        end
    end
    
    local headerTextX, headerTextY, headerTextW, headerTextH, align, bgX, bgW = getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)
    
    -- in case we have the output shown in the header
    height = height - ((vertical and sizeId == 0 and outputOnItsOwnLine) and headerSize or 0)
    --[[
    
    
    
    
    local headerTextX = screenPosX + (vertical and headerAreaRemove or 0)
    local headerTextY = screenPosY + (vertical and 0 or headerAreaRemove)
    local headerTextW = headerW - (vertical and headerAreaRemove * 2 or 0)
    local headerTextH = headerH - (vertical and 0 or headerAreaRemove * 2)  
    
    local outputsSizeW = #outputArray * headerSizeWM + 4
    
    
    local align = "Center"
     
     
    -- could add a minimum text width size instead of the actual text width
    if isCollabsed then
        if #outputArray > 1 and (vertical and headerW or headerH) - outputsSizeW - headerAreaRemoveTotal - 2 < headerTextWidth then 
            outputOnItsOwnLine = true 
            local widthLeft = (vertical and headerW or headerH) - headerAreaRemoveTotal - headerTextWidth
            if vertical then
                headerH = headerSizeW + headerSizeWM * rowsNeeded
                height = headerH 
                if headerW < headerTextWidth + headerAreaRemove * 2 + 6 then 
                    headerTextX = screenPosX + headerAreaRemoveBottom
                    headerTextW = headerW - headerAreaRemoveTotal
                    align = "Left"
                end
            else
                headerW = headerSizeW + headerSizeWM * rowsNeeded
                width = headerW
                if headerH < headerTextWidth + headerAreaRemove * 2 then 
                    headerTextY = screenPosY + (widthLeft > 0 and widthLeft/2 or 0)
                    headerTextH = headerH - headerAreaRemoveTotal
                end
            end
        elseif #outputArray > 1 and (vertical and headerW or headerH) - outputsSizeW * 2 < headerTextWidth then 
            align = "Right"
            headerTextX = screenPosX + (vertical and 2 or 0)
            headerTextY = screenPosY + (vertical and 0 or outputsSizeW)
            headerTextW = (vertical and headerW - outputsSizeW or headerW)
            headerTextH = (vertical and headerH or headerH)  
        end
    else
        headerTextX, headerTextY, headerTextW, headerTextH, align = getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)
    end]]
    
    
    
    local borderColor = selectedModule == fxIndex and (mapActiveFxIndex == fxIndex and colorMappingPulsating or settings.colors.modulatorBorderSelected) or settings.colors.backgroundWidgetsBorder
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), floating and settings.colors.backgroundWidgetsBorder or borderColor)
    -- 789
    if topChildOfPanel(name .. fxIndex, width, height, heightAutoAdjust) then
        --reaper.ImGui_InvisibleButton(ctx, "dummy", 20 ,20)
        
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorGrey)
        
        
        drawHeaderBackground(screenPosX, screenPosY, screenPosX + headerW, screenPosY + headerH, isCollabsed, vertical, settings.colors.backgroundWidgetsHeader, settings.colors.backgroundWidgetsBorder)
        
        
        offsetButton = 20
        if settings.showRemoveCrossModulator then 
            local posX, posY = getIconPosToTheLeft(vertical, offsetButton, screenPosX, screenPosY, height)
            reaper.ImGui_SetCursorScreenPos(ctx, posX+2, posY+2)
            if specialButtons.close(ctx,reaper.ImGui_GetCursorPosX(ctx),reaper.ImGui_GetCursorPosY(ctx),16,false,"deleteModule" .. fxIndex, settings.colors.removeCross, settings.colors.removeCrossHover,colorTransparent, colorTransparent) then 
                deleteModule(track, fxIndex, modulationContainerPos, fx)
            end
            offsetButton = offsetButton + 16
        end
        
        -- Most left
        local posX, posY = getIconPosToTheLeft(vertical, offsetButton, screenPosX, screenPosY, height)
        reaper.ImGui_SetCursorScreenPos(ctx, posX+3, posY+3)
        openCloseMappings(fx, fxIndex, mappings, floating)
        
        
        if hideParametersFromModulator ~= fx.guid and (showOpenGui or genericModulatorInfo ) then
            offsetButton = offsetButton + 18
            local posX, posY = getIconPosToTheLeft(vertical, offsetButton, screenPosX, screenPosY, height)
            local isFxOpen = modulatorGuiIsOpen(track, fxIndex, hasGui)
            if drawOpenFXWindow(posX, posY, 20, isFxOpen, "window for modulator") then
                openCloseModulatorGui(track, fxIndex, hasGui, isFxOpen) 
            end 
        end
        
        
        
        if drawHeaderTextAndGetHover(title, headerTextX, headerTextY, headerTextW, headerTextH, isCollabsed, vertical, 0, "Right click for more options", colorText, align, bgX, bgW) then
            if isMouseClick then
                if floating then
                    settings[floating .."ShowModulator"] = not settings[floating .."ShowModulator"]
                    saveSettings()
                else
                    trackSettings.collabsModules[fx.guid] = not trackSettings.collabsModules[fx.guid]
                    saveTrackSettings(track)
                    selectedModule = fxIndex
                end
            elseif reaper.ImGui_IsMouseClicked(ctx, 1) then
                selectedModule = fxIndex
                openPopupForModule = true
                ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
            end
        end 
        
        
        
        modulatorWidth = modulatorWidth + (vertical and 0 or -12)
        modulatorHeight = modulatorHeight - 20 -- (settings.vertical and 20 or (sizeId == 0 and headerSize or 0) ) 
        
        local posX, posY = getIconPosToTheRight(vertical, 20, screenPosX, screenPosY, width)
        
        if outputOnItsOwnLine then
            --reaper.ImGui_SetCursorScreenPos(ctx, posX + 1, posY + 1) 
        else
            --reaper.ImGui_SetCursorScreenPos(ctx, posX + 1, posY + 1) 
        end
        --drawOutputFromModulator(name, fx, output, outputArray, isCollabsed, modulatorWidth, modulatorHeight)
        
        local offsetX = 0 
        local offsetY = 0 
        
        
        if isCollabsed or sizeId == 0 then
            --reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx)-7, reaper.ImGui_GetCursorPosY(ctx))
        
            --local widthOfHeader = findWidthOfHeaderHorizontal(name, outputArray, modulatorHeight)
            
            if outputOnItsOwnLine then 
                --startX, startY = reaper.ImGui_GetCursorPos(ctx)
                --reaper.ImGui_SetCursorPos(ctx, reaper.ImGui_GetCursorPosX(ctx) + offsetX, reaper.ImGui_GetCursorPosY(ctx)) 
                --cutPoint = math.floor(#outputArray / rowsNeeded)
                --width = rowsNeeded * 20
            end 
            --function findCutPointAndRowsNeeded(areaSize, buttonSize, outputArray
            -- 789
            
            for i, output in ipairs(outputArray) do 
                --if cutPoint and cutPoint > 0 then
                    if vertical then
                        offsetX = (math.ceil((i-1)%amountInEachRow )) * headerSizeWM - ((amountInEachRow -1) * headerSizeWM)
                        offsetY = outputOnItsOwnLine and (math.ceil(i/amountInEachRow )) * headerSizeWM or 0
                    else
                        offsetX = outputOnItsOwnLine and (math.ceil(i/amountInEachRow )) * headerSizeWM or 0
                        offsetY = (math.ceil((i-1)%amountInEachRow )) * headerSizeWM 
                    end
                    
                    reaper.ImGui_SetCursorScreenPos(ctx, posX + 1 + offsetX, posY + 1 + offsetY)
                --end
                
                if drawFaderFeedback(headerSizeWM,headerSizeWM, fx.fxIndex, output, 0, 1, isCollabsed, fx, i, headerSizeWM) then 
                    mapModulatorActivate(fx,output, name, nil, #outputArray == 1)
                end     
            end
        end
        
        
        
        dropDownSize = modulatorWidth + (vertical and -30 or -14 - 8)
        buttonWidth = dropDownSize / 2
        
        if not isCollabsed then 
            local id = "params" .. name .. fxIndex .. (floating and "floating" or "normal")
            if bodyChildOfPanel(id, headerSize, 6, vertical) then
                width = width - 4 - (vertical and 4 or headerSize + 6)
                height = height - 12 - (vertical and headerSize or 0)
            
            
            
                local isMapped = not genericModulatorInfo or genericModulatorInfo.outputParam ~= -1
                local isNotAbSlider = fx.fxName:match("AB Slider") == nil
                if isNotAbSlider and isMapped then
                    if hideParametersFromModulator == fx.guid then
                        if reaper.ImGui_Button(ctx, "Stop editing", modulatorWidth-16) then
                            hideParametersFromModulator = nil
                        end
                        local allIsShown = true 
                        local param_count = GetNumParams(track, fxIndex)
                        for p = 0, param_count - 1 do 
                            if filterParametersThatAreMostLikelyNotWanted(p, track, fx.fxIndex) then
                                if trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] and trackSettings.hideParametersFromModulator[fx.guid][p] then
                                    allIsShown = false
                                    break;
                                end
                            end
                        end
                        if reaper.ImGui_Button(ctx, allIsShown and "Hide all" or "Show all", modulatorWidth-16) then
                            for p = 0, param_count - 1 do 
                                if filterParametersThatAreMostLikelyNotWanted(p, track, fx.fxIndex) then
                                    trackSettings.hideParametersFromModulator[fx.guid][p] = allIsShown 
                                end
                            end
                            saveTrackSettings(track)
                        end
                    else
                        
                        if sizeId ~= 0 then
                            visualizerSize = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
                            reversedVisualizerSize = 4 - (visualizerSize == 1 and 0 or visualizerSize)
                            
                            size = buttonWidth * 2 / reversedVisualizerSize
                            if visualizerSize == 1 and #outputArray > 1 then
                                size = buttonWidth/2 - 0.5
                            elseif visualizerSize == 2 then
                                size = buttonWidth - 0.5
                            elseif visualizerSize == 3 then
                                size = buttonWidth * 2
                            end
                            
                            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 1, 1)
                            for i, output in ipairs(outputArray) do 
                                if drawFaderFeedback( size,20*visualizerSize, fxIndex, output, 0, 1, isCollabsed, fx, i, buttonWidth) then  
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
                            reaper.ImGui_PopStyleVar(ctx)
                        end
                    end
                end
                
                
                --[[
                local hasGui = fx.fxName:match("ACS Native Modulator") ~= nil
                local showOpenGui = false
                local fxName = fx.fxName
                for _, mod in ipairs(factoryModules) do
                    if mod.showOpenGui and (fxName == mod.insertName or fxName:match(mod.insertName) ~= nil) then
                        showOpenGui = true
                        break;
                    end
                end
                
                if hideParametersFromModulator ~= fx.guid and (showOpenGui or genericModulatorInfo ) then
                    
                    local sizeW = buttonWidth * 2 + 12
                    local sizeH = 20
                    visualizerSize = (trackSettings.bigWaveform and trackSettings.bigWaveform[fx.guid]) and trackSettings.bigWaveform[fx.guid] or settings.visualizerSize
                    
                    if #outputArray % 4 * visualizerSize < 3 and #outputArray % 4 * visualizerSize > 0 then
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
                
                if #outputArray > 0 and isNotAbSlider then
                    reaper.ImGui_Separator(ctx)
                end
                ]]
                
                local curPosY = reaper.ImGui_GetCursorPosY(ctx)
                
                local paramsHeight = modulatorHeight and (modulatorHeight-curPosY) or nil
                
                useWindowFlags = scrollFlags
                
                
                if floating or (vertical and not settings.limitModulatorHeightToModulesHeight) then 
                    --useFlags = reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeY()
                    --useWindowFlags = reaper.ImGui_WindowFlags_re()
                    
                    modulatorAreaHeight = nil
                else 
                    modulatorAreaHeight = paramsHeight 
                    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 40, modulatorWidth, paramsHeight +8)
                end
                
                -- 456
                --modulatorWidth = modulatorWidth + (settings.vertical and -16 or 0)
                
                
                
                --if reaper.ImGui_BeginChild(ctx, id, modulatorWidth, nil, useFlags,useWindowFlags) then 
                if scrollChildOfPanel(id .. "scroll", width, height, heightAutoAdjust) then
                    modulatorAreaX, modulatorAreaY = reaper.ImGui_GetItemRectMin(ctx) -- hot fix
                    local maxScrollBar = math.floor(reaper.ImGui_GetScrollMaxY(ctx))
                    local modulatorParameterWidth = width - (maxScrollBar == 0 and 8 or 20)
                    
                    
                    valuesFromModulator = func(id, name, modulationContainerPos, fxIndex, fxIndContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
                    reaper.ImGui_EndChild(ctx)
                end
                
                
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
        
        --reaper.ImGui_PopStyleColor(ctx,1)
        --reaper.ImGui_EndTable(ctx)
        reaper.ImGui_EndChild(ctx)
    end

    --
    
    
    
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
    
    
    
    
    --reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_PopStyleColor(ctx,1)
    
    
    
    if not minX then minX, minY = reaper.ImGui_GetItemRectMin(ctx) end
    if not maxX then maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) end
    --reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, selectedModule == fxIndex and (mapActiveFxIndex == fxIndex and colorMap or colorWhite) or colorGrey,4)
   
    -- module hoover
    if mouse_pos_x_imgui >= minX and mouse_pos_x_imgui <= maxX and mouse_pos_y_imgui >= minY and mouse_pos_y_imgui <= maxY then 
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
            renameFxIndex = fxIndex
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
                deleteParameterFromContainer(track, modulationContainerPos, valuesFromModulator.indexInContainerMapping)
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
    
    
    
    if addUserModulator then
        ImGui.OpenPopup(ctx, 'addModulatorPreset##' .. fxIndex)  
    end
    
    if reaper.ImGui_BeginPopup(ctx, 'addModulatorPreset##' .. fxIndex, nil) then
        ignoreKeypress = true
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
    
        
function drawAllMappingsParametersWithTheirFXOnTop(mappings, faderWidth)
    
    local alreadyShowing = {}
    
    
    for i, map in ipairs(mappings) do  
        local fxIndex = map.fxIndex
        local name = GetFXName(track, fxIndex)
        
        if not alreadyShowing[fxIndex] and (not ignoreFxIndex or (ignoreFxIndex ~= fxIndex)) then 
            
            --fixMissingIndentOnCollabsModule(isCollabsed)
            
            fxIsShowing = GetOpen(track,fxIndex)
            fxIsFloating = GetFloatingWindow(track,fxIndex)
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
        pluginParameterSlider("mappings" .. (floating and "Floating" or ""),getAllDataFromParameter(track,fxIndex,map.param), nil, nil, true, false, faderWidth, nil, nil,nil,nil,nil, useKnobs, useNarrow )
    
        --reaper.ImGui_Spacing(ctx)
        --reaper.ImGui_Separator(ctx)
        if scroll and map.param == scroll then
            ImGui.SetScrollHereY(ctx,  0.22)
            removeScroll = true
        end
    end
    
    click = false
    if clickType == "right" then 
        ImGui.OpenPopup(ctx, 'popup##' .. fxIndex) 
    elseif clickType == "left" then 
        click = true
    end
end
        
function mappingsArea(mappingWidth, mappingHeight, m, vertical, floating, isCollabsed, ignoreFxIndex, ignoreParam)   
    local name = m.name
    local fxIndex = m.fxIndex
    local mappings = m.mappings
    local guid = m.guid
    
    local filteredMappings = {}
    
    if not vertical or (floating and settings[floating .."ShowModulator"]) then 
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
    local useFlags = reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeY()
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
                settings[floating .. "ShowMappings"] = false
            else
                trackSettings.showMappings[guid] = false
            end
        end
        
        reaper.ImGui_TableNextColumn(ctx)
        
        local curPosX, curPosY = reaper.ImGui_GetCursorPos(ctx)
        --local faderWidth = mappingWidth - 32--(floating and 16 or 32)
        
        local maxScrollBar = math.floor(reaper.ImGui_GetScrollMaxY(ctx))
        local modulatorParameterWidth = mappingWidth - 32 + (maxScrollBar == 0 and 16 or 0)
        
        drawAllMappingsParametersWithTheirFXOnTop(mappings, modulatorParameterWidth)
         
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
    
    
    
    local found
    
    for _, mod in ipairs(factoryModules) do
        if fxName == mod.insertName or fxName:match(mod.insertName) ~= nil then
            modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, mod.layout, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m, nil, m.output) 
            found = true
            break;
        end
    end
    
    
    if not found then  
        if fxName:match("MIDI Out") then
            modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, midiOutModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m,nil,m.output)
            
        else 
            
            local numParams = GetNumParams(track,fxIndex) 
            local output = {}
            -- make possible to have multiple outputs
            local genericModulatorInfo = {outputParam = -1, indexInContainerMapping = -1}
            for p = 0, numParams -1 do
                --retval, buf = GetNamedConfigParm( track, fxIndex, "param." .. p .. ".container_map.hint_id" )
                -- we would have to enable multiple outputs here later
                retval, buf = GetNamedConfigParm( track, modulationContainerPos, "container_map.get." .. fxIndex .. "." .. p )
                --if tonumber(buf) == nil then
                   -- reaper.ShowConsoleMsg(p .. " - " .. fxName .. "\n")
                   -- retval, buf = GetNamedConfigParm( track, modulationContainerPos, "container_map.get." .. fxIndex .. "." .. p, true )
                --end
                
                if retval and tonumber(buf) ~= nil then
                    table.insert(output, p)
                    genericModulatorInfo = {outputParam = p, indexInContainerMapping = tonumber(buf)}
                    break
                end
            end
            
            -- FETCH genericModulator INFO HERE
            modulatorWrapper(floating, vertical, modulatorWidth, modulatorHeight, genericModulator, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, m, genericModulatorInfo,output)
        end
    end
end

function editPluginSetting(_do, paramObj, var)
    local simpleName = paramObj.fxNameSimple
    --local currentStr = readFile(simpleName, pluginsFolderName)
    --pluginObj = currentStr and json.decodeFromJson(currentStr) or {}
    
        if not customPluginSettings[simpleName] then customPluginSettings[simpleName] = {} end
        if not customPluginSettings[simpleName][paramObj.param] then customPluginSettings[simpleName][paramObj.param] = {} end
        
        if _do == "rename" and not customPluginSettings[simpleName][paramObj.param][_do] then
            
            customPluginSettings[simpleName][paramObj.param] = {useRenameOnWide = true, useRenameOnNarrow = true} 
        end
        customPluginSettings[simpleName][paramObj.param][_do] = var
        saveFile(json.encodeToJson(customPluginSettings[simpleName]), simpleName, pluginsFolderName) 
        last_paramTableCatch = {}
    --end
      
      if _do == "rename" then
          paramTableCatch = {}
      end  
    --aa = currentStr
    --settings.colors = currentSettingsStr and json.decodeFromJson(currentSettingsStr) or {}
    
end

function renameParamPopup()
    if openRenameParam then
        ImGui.OpenPopup(ctx, 'rename param##') 
        openRenameParam = false
    end
    
    if reaper.ImGui_BeginPopup(ctx, 'rename param##', nil) then
        ignoreKeypress = true 
        local fxName = GetFXName(track, renameParam.fxIndex)
        
        local paramName = GetParamNameFromCustomSetting(track, renameParam.fxIndex, renameParam.param, "rename")
        reaper.ImGui_Text(ctx, "Rename " .. paramName)
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        local originalName = paramName
        local ret, newName = reaper.ImGui_InputText(ctx,"##" .. renameParam.fxIndex, paramName,nil,nil)
        --reaper.ShowConsoleMsg(newName .. "\n")
        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
            if not newName or newName == "" then newName = GetParamName(track, renameParam.fxIndex, renameParam.param) end
            editPluginSetting("rename", renameParam, newName)
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        ImGui.EndPopup(ctx)
    end 
end


function renameFxIndexPopup()
    if openRename then
        ImGui.OpenPopup(ctx, 'rename##' .. renameFxIndex) 
        openRename = false
    end
    
    if reaper.ImGui_BeginPopup(ctx, 'rename##' .. renameFxIndex, nil) then
        ignoreKeypress = true
        local name = GetFXName(track, renameFxIndex)
        reaper.ImGui_Text(ctx, "Rename " .. name)
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        local originalName = name
        local ret, newName = reaper.ImGui_InputText(ctx,"##" .. renameFxIndex, name,nil,nil)
        --reaper.ShowConsoleMsg(newName .. "\n")
        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Escape(),false) then
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        if reaper.ImGui_IsKeyPressed(ctx,reaper.ImGui_Key_Enter(),false) then
            if not trackSettings.renamed then trackSettings.renamed = {} end
            local guid = GetFXGUID(track, renameFxIndex)
            if trackSettings.renamed[guid] == nil then trackSettings.renamed[guid] = originalName; saveTrackSettings(track) end
            if newName == "" then newName = trackSettings.renamed[guid] end -- ; trackSettings.renamed[fx.guid] = nil end
            if newName ~= originalName then 
                renameModule(track, modulationContainerPos, renameFxIndex, newName)
                reloadParameterLinkCatch = true
            end
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        ImGui.EndPopup(ctx)
    end 
end
---------------------------------------------------------------------------------------------------------------
-------------------------------------MODULES-------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------

function createSliderForNativeLfoSettings(track,fxnumber,paramnumber,name,min,max,sliderFlag)
    reaper.ImGui_SetNextItemWidth(ctx,dropDownSize)
    local currentValue = tonumber(select(2, GetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.lfo.' .. name) ))
    ret, value = reaper.ImGui_SliderDouble(ctx, name.. '##lfo' .. name .. fxnumber, currentValue, min, max, nil, sliderFlag)
    if ret then 
        SetNamedConfigParm( track, fxnumber, 'param.'..paramnumber..'.lfo.' .. name, value) 
    end
end

--[[                
function setParameterNormalizedButReturnFocus(track, fxIndex, param, value) 
    SetParamNormalized(track, fxIndex, param, value)
    -- focus last focused
    SetParamNormalized(track,fxnumber,paramnumber,GetParamNormalized(track,fxnumber,paramnumber))
    return value
end]]

function setParameterButReturnFocus(track, fxIndex, param, value) 
    SetParam(track, fxIndex, param, value)
    -- focus last focused
    -- TODO: do we need this anymore, passed out for now
    --SetParam(track,fxnumber,paramnumber,GetParam(track,fxnumber,paramnumber))
    return value
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

function findModulationParameterWidth(parameterColumnAmount, modulatorParameterWidth)
    local spacingNeeded = 4 * (parameterColumnAmount - 1)
    local spacingTakenFromEach = spacingNeeded / parameterColumnAmount 
    if parameterColumnAmount > 1 then
        modulatorParameterWidth = modulatorParameterWidth / parameterColumnAmount - spacingTakenFromEach
    end
    return modulatorParameterWidth
end

function samelineIfWithinColumnAmount(i, parameterColumnAmount, modulatorParameterWidth)
    if parameterColumnAmount > 1 and i % parameterColumnAmount ~= 0 then
        reaper.ImGui_SameLine(ctx, (modulatorParameterWidth * (i % parameterColumnAmount)) + 4 * (i % parameterColumnAmount))
    end
end

-- wrap slider in to mapping function
function createSlider(track,fxIndex, _type,paramIndex,name,min,max,divide, valueFormat,flag, checkboxFlipped, dropDownText, dropdownOffset,tooltip, width, visualIndex, parameterColumnAmount)  
    --local sizeW = width --and width or buttonWidth
    local narrowIsUsed = false
    if visualIndex then
        local parameterColumnAmount = parameterColumnAmount and parameterColumnAmount or settings.ModulatorParameterColumnAmount 
        if parameterColumnAmount > 1 then
            width = findModulationParameterWidth(parameterColumnAmount, width)
            if visualIndex > 0 then
                samelineIfWithinColumnAmount(visualIndex, parameterColumnAmount, width)
            end 
            narrowIsUsed = true
        end
    end

    currentValue = GetParam(track, fxIndex, paramIndex)
    
    local textW = reaper.ImGui_CalcTextSize(ctx, name,0,0)
    if width then
        reaper.ImGui_SetNextItemWidth(ctx,width - (narrowIsUsed and 0 or textW + 4)) 
    end
    
    if _type == "Combo" then
        ret, val = reaper.ImGui_Combo(ctx, (narrowIsUsed and "" or name) .. '##slider' .. name .. fxIndex, math.floor(currentValue)+dropdownOffset, dropDownText)
        if ret then setParameterButReturnFocus(track, fxIndex, paramIndex, val - dropdownOffset) end
        scrollValue = 1
    elseif _type == "Checkbox" then
    
        ret, val = reaper.ImGui_Checkbox(ctx, '##slider' .. name .. fxIndex, currentValue == (checkboxFlipped and 0 or 1)) 
        if ret then   
            val = checkboxFlipped and (val and 0 or 1) or (val and 1 or 0)
            setParameterButReturnFocus(track, fxIndex, paramIndex, val) 
        end
        scrollValue = 1
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
        if narrowIsUsed and flag ~= "TextOnSameLine" then
            reaper.ImGui_DrawList_AddText(draw_list, minX, maxY, colorText, name) 
        else
            reaper.ImGui_DrawList_AddText(draw_list, maxX + 2,minY+2, colorText, name)
        end
        
    elseif _type == "ButtonToggle" then
        if reaper.ImGui_Button(ctx, name.. '##slider' .. name .. fxIndex,width, narrowIsUsed and (14 + 16)  or buttonSizeH) then
            setParameterButReturnFocus(track, fxIndex, paramIndex, currentValue == 1 and 0 or 1) 
            return true
        end  
    elseif _type == "ButtonVal" then
        if reaper.ImGui_Button(ctx, name.. '##slider' .. name .. fxIndex,width, narrowIsUsed and (14 + 16)  or buttonSizeH) then
            setParameterButReturnFocus(track, fxIndex, paramIndex, divide) 
            return true
        end  
    elseif _type == "ButtonReturn" then
        if reaper.ImGui_Button(ctx, name.. '##slider' .. name .. fxIndex,width, narrowIsUsed and (14 + 16)  or buttonSizeH) then
            return true
        end  
    end 
    if val == true then val = 1 end
    if val == false then val = 0 end
    if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end 
    if _type ~= "ButtonReturn" and _type ~= "ButtonToggle" then
        return ret, val
    end
end


function createModulationLFOParameter(track, fxIndex,  _type, paramName, visualName, min, max, divide, valueFormat, sliderFlags, checkboxFlipped, dropDownText, dropdownOffset,tooltip, modulatorParameterWidth) 
    local currentValue = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)))
    if currentValue then 
        scrollValue = nil
        --reaper.ImGui_Text(ctx,visualName)
        --visualName = ""
        reaper.ImGui_SetNextItemWidth(ctx,modulatorParameterWidth)
        if _type == "Checkbox" then
            ret, newValue = reaper.ImGui_Checkbox(ctx, "##" .. visualName .. paramName .. fxIndex, currentValue == (checkboxFlipped and 0 or 1))
            reaper.ImGui_SameLine(ctx)
            local posX, posY = reaper.ImGui_GetCursorScreenPos(ctx)
            posX = posX - 4
            --reaper.ImGui_PushClipRect(ctx, posX, posY, posX + modulatorParameterWidth, posY + 20, true)  
            reaper.ImGui_DrawList_AddText(draw_list, posX, posY + 2, colorText, visualName) 
            --ImGui.PopClipRect(ctx)
            reaper.ImGui_NewLine(ctx)
            
            if ret then SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue and (checkboxFlipped and 0 or 1) or (not checkboxFlipped and "0" or "1")) end
            scrollValue = 1 
        elseif _type == "Combo" then 
            ret, newValue = reaper.ImGui_Combo(ctx, '##' .. visualName .. paramName .. fxIndex, tonumber(currentValue)+dropdownOffset, dropDownText )
            reaper.ImGui_SameLine(ctx)
            local posX, posY = reaper.ImGui_GetCursorScreenPos(ctx)
            posX = posX - 4
            reaper.ImGui_DrawList_AddText(draw_list, posX, posY + 2, colorText, visualName) 
            reaper.ImGui_NewLine(ctx)
            
            if ret then SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, newValue-dropdownOffset) end
            scrollValue = divide
        end
        if tooltip and settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,tooltip) end
        
    end
    return newValue and newValue or currentValue
end

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


function createShapesPlots()
    plotAmount = 99
    local shapes = {
      function(n) return math.sin((n)*2 * math.pi) end, -- sin
      function(n) return n < 0.5 and -1 or (n> 0.5 and 1 or 0) end, --square
      function(n) return (n * -2 + 1) end, -- saw L
      function(n) return (n * 2 - 1) end, -- saw R
      function(n) return (math.abs(n - math.floor(n + 0.5)) * 4 - 1) end, -- triangle
      function(n) return randomPoints[math.floor(n*(#randomPoints-1))+1] / 50 -1 end, -- random
      function(n) return math.floor(n/0.33)-1 end, -- steps
    }
    local shapeNames = {"Sin", "Square", "Saw L", "Saw R", "Triangle", "Random", "Steps"}
    
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
local shapesPlots, shapeNames = createShapesPlots() 



function nlfoModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    function createShapes() 
        ------------ SHAPE -----------
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
        
        
        local focusedShape = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. "shape")))
    
        if not hovered then hovered = {} end
        if not hovered[fxIndex]  then hovered[fxIndex] = {} end
        
        local buttonSizeW = modulatorParameterWidth/6
        local useExtraLine = false
        if buttonSizeW < 20 then
            buttonSizeW = modulatorParameterWidth/3
            useExtraLine = true
        end
        local buttonSizeW = 20
        local buttonSizeH = 20
        for i = 1, #shapesPlots - 1 do
            plots = shapesPlots[i]
            --ImGui.SetNextItemAllowOverlap(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),focusedShape == i-1 and colorButtonsActive or (hovered and hovered[fxIndex][i]) and colorButtonsHover or colorButtons )
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotLines(), colorText )
            
            
            local posX, posY = reaper.ImGui_GetCursorPos(ctx) 
            if reaper.ImGui_InvisibleButton(ctx, "##shapeButton" .. fxIndex ..":" .. i, buttonSizeW, buttonSizeH) then 
                shape = i -1
                SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. "Shape", shape) 
            end
            local lineX, lineY = reaper.ImGui_GetItemRectMin(ctx)
            if settings.showToolTip then setToolTipFunc("Set shape to: " .. shapeNames[i]) end
            
            reaper.ImGui_SetCursorPos(ctx, posX, posY) 
            
            reaper.ImGui_PlotLines(ctx, '', plots, 0, nil, -1.0, 1.0, buttonSizeW, buttonSizeH)
            reaper.ImGui_PopStyleColor(ctx,2)
            
            if i < #shapesPlots - 1 then
                reaper.ImGui_SameLine(ctx)--, buttonSizeW * i) 
                local posX, posY = reaper.ImGui_GetCursorPos(ctx)
                reaper.ImGui_SetCursorPos(ctx, posX-8, posY)
                
                
                if posX > modulatorParameterWidth - 12 then
                    reaper.ImGui_NewLine(ctx)
                end
            end
            
        end  
        
        reaper.ImGui_PopStyleColor(ctx,3) 
    end
    
    paramOut = "1"
    
    noteTempoNamesToValues = {}
    noteTemposDropdownText = ""
    for _, t in ipairs(noteTempos) do
        noteTemposDropdownText = noteTemposDropdownText .. t.name .. "\0" 
    end
    
    
    
    buttonSize = 20
    
        
    createShapes()
    
    isTempoSync = createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.temposync", "Tempo sync",nil,nil,1, nil,nil,nil,nil,nil,nil,modulatorParameterWidth)
    
    createModulationLFOParameter(track, fxIndex, "Checkbox", "lfo.free", "Seek/loop", nil,nil,1,nil,nil,true, nil, nil, nil, modulatorParameterWidth)  
    --local parameterColumnAmount = settings.ModulatorParameterColumnAmount 
    --modulatorParameterWidth = findModulationParameterWidth(parameterColumnAmount, modulatorParameterWidth)
    
    --local ret, isTempoSync = GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.temposync') 
    --isTempoSync = isTempoSync == "1"
    --nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "lfo.temposync", "Tempo sync", 0, 1, 1, isTempoSync and "On" or "Off", nil, nil, nil, nil, nil,modulatorParameterWidth, 0)

    local paramName = "Speed"
    local visualIndexOffset = 0
    if tonumber(isTempoSync) == 0 then
        nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "lfo.speed", "Speed", 0.0039, 16,1, "%0.4f Hz", reaper.ImGui_SliderFlags_Logarithmic(), nil, nil, nil, nil,modulatorParameterWidth, 1, nil,  useKnobs, useNarrow)
        --visualIndexOffset = visualIndexOffset + 1
    else  
        -- speed drop down menu
        reaper.ImGui_SetNextItemWidth(ctx,modulatorParameterWidth)
        local currentValue = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName)))
        if currentValue then
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
                SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.lfo.' .. paramName, noteTempos[value + 1].value) 
            end
            
            scrollHoveredDropdown(closest_index, track,fxIndex,nil, noteTempos, 'param.'..paramOut..'.lfo.' .. paramName)
        end
    end
    
    
    nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "lfo.phase", "Phase", 0, 1, 1, "%0.2f", nil, nil, nil, nil, nil,modulatorParameterWidth, 0, nil, useKnobs, useNarrow, 0+visualIndexOffset) 
    
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, 1+visualIndexOffset) 
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 2+visualIndexOffset) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 1000, nil,nil,nil,nil, useKnobs, useNarrow, 3+visualIndexOffset) 
end

local acsTrackAudioChannel = {"1","2","3","4","1+2","3+4"}
local acsTrackAudioChannelDropDownText = ""
for _, t in ipairs(acsTrackAudioChannel) do
    acsTrackAudioChannelDropDownText = acsTrackAudioChannelDropDownText .. t .. "\0" 
end
    
function acsModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    paramOut = "1"
     
    buttonSizeH = 22
    buttonSizeW = buttonSizeH * 1.25
    
    reaper.ImGui_TableNextColumn(ctx)

    
    local ret1, chan = GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.chan")  
    local ret2, stereo = GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.stereo")
    if ret1 and ret2 then
        local dropDownSelect = tonumber(stereo) < 1 and tonumber(chan) or (tonumber(chan) == 0 and 4 or 5)
        local textW = reaper.ImGui_CalcTextSize(ctx, "Channel", 0,0)
        reaper.ImGui_SetNextItemWidth(ctx,modulatorParameterWidth - textW-8)
        local ret, value = reaper.ImGui_Combo(ctx, "" .. '##acsModulator' .. "Channel" .. fxIndex, dropDownSelect, acsTrackAudioChannelDropDownText )
        if ret then  
            if value < 4 then
                SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.chan", value)   
            else
                SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.chan", value == 4 and 0 or 2)
            end
                
            SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. "acs.stereo", value < 4 and 0 or 1)
            
        end 
        reaper.ImGui_SameLine(ctx)
        local posX, posY = reaper.ImGui_GetCursorScreenPos(ctx)
        posX = posX - 4
        reaper.ImGui_DrawList_AddText(draw_list, posX, posY + 2, colorText, "Channel") 
        reaper.ImGui_NewLine(ctx)
        
        if settings.showToolTip then reaper.ImGui_SetItemTooltip(ctx,"Set audio channel to use as signal") end
    end
    
    --if ret then SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, amount) end 
    
    nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.attack", "Attack", 0, 1000, 1, "%0.0f ms", nil, nil, nil, nil, nil,modulatorParameterWidth, 300, nil, useKnobs, useNarrow,0)
    nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.release", "Release", 0, 1000, 1, "%0.0f ms", nil, nil, nil, nil, nil,modulatorParameterWidth, 300, nil, useKnobs, useNarrow,1)
    nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.dblo", "Min Volume", -60, 12,1, "%0.2f dB", nil, nil, nil, nil, nil,modulatorParameterWidth, -60, nil, useKnobs, useNarrow,2)
    nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.dbhi", "Max Volume", -60, 12,1, "%0.2f dB", nil, nil, nil, nil, nil,modulatorParameterWidth, 12, nil, useKnobs, useNarrow,3)
    nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.strength", "Strength", 0, 1,100, "%0.1f %%", nil, nil, nil, nil, nil,modulatorParameterWidth, 1, nil, useKnobs, useNarrow,4)
    -- THESE ARE NOT RELEVANT TO SEE
    
    
    --nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.x2", "X pos", 0, 1,1, "%0.2f dB", nil, nil, nil, nil, nil,modulatorParameterWidth, 0.5, nil, useKnobs, useNarrow)
    --nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.y2", "Y pos", 0, 1,1, "%0.2f dB", nil, nil, nil, nil, nil,modulatorParameterWidth, 0.5, nil, useKnobs, useNarrow)
    --nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.chan", "Channel", 0, 2, 1, "%0.1f", nil, nil, nil, nil, nil,modulatorParameterWidth, 2, nil, useKnobs, useNarrow)
    --nativeReaperModuleParameter(id, track, fxIndex, paramOut, "SliderDouble", "acs.stereo", "Stereo", 0, 1, 1, "%0.1f", nil, nil, nil, nil, nil,modulatorParameterWidth, 1, nil, useKnobs, useNarrow)
     
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,5) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,6) 
end

function midiCCModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
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
    --reaper.ImGui_NewLine(ctx)
    createSlider(track,fxIndex,"Combo",1,"Fader",nil,nil,1,nil,nil,nil,typeDropDownText,0,"Select CC or pitchbend to control the output", modulatorParameterWidth)
    createSlider(track,fxIndex,"Combo",2,"Channel",nil,nil,1,nil,nil,nil,channelDropDownText,0,"Select which channel to use", modulatorParameterWidth) 

    isListening = GetParam(track, fxIndex, 3) == 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorMapping )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorMappingLight )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",3,isListening and "Stop" or "Listen",0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input", modulatorParameterWidth) 
    reaper.ImGui_PopStyleColor(ctx,3)
    createSlider(track,fxIndex,"Checkbox",7,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil, nil, modulatorParameterWidth)
    
    local faderSelection = GetParam(track, fxIndex, 1)
    if faderSelection > 0 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,0) 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1) 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
        
    end
end

function keytrackerModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    local list = {"Off","Smooth", "Constant"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    local useTimer = GetParam(track, fxIndex, 1) > 0
    createSlider(track,fxIndex,"Combo",1,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Set the timer mode for changing the value", modulatorParameterWidth, (useColumns and useTimer) and 0 or nil, (useColumns and useTimer) and 2 or nil)
    if useTimer then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1 or nil, 2) 
    end
    
    
     
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0 or nil, 2) 
    
    
    local isListening = GetParam(track, fxIndex, 9) == 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",9,isListening and "Stop" or (useColumns and "Set##minimum" or "Set minimum"),0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set minimum key range", modulatorParameterWidth, useColumns and 1 or nil, 2)   
    reaper.ImGui_PopStyleColor(ctx,3)
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 127, nil,nil,nil,nil, useKnobs, useNarrow,useColumns and 0 or nil,2) 
    local isListening = GetParam(track, fxIndex, 10) == 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons ) 
    createSlider(track,fxIndex,"ButtonToggle",10,isListening and "Stop" or (useColumns and "Set##maximum" or "Set maximum"),0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set maximum key range", modulatorParameterWidth, useColumns and 1 or nil, 2)  
    reaper.ImGui_PopStyleColor(ctx,3)
    
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,11), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,3) 
    
    createSlider(track,fxIndex,"Checkbox",8,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil,nil, modulatorParameterWidth) 
end


function counterModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    local list = {"Up","Down", "Up & Down", "Random"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    --createSlider(track,fxIndex,"Combo",7,"Direction",nil,nil,1,nil,nil,nil,listText,0,"Set the direction of the counter")
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, 1,nil, nil,nil,"%0.0f", useKnobs, useNarrow,0) 
    -- steps
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 1,nil, nil,nil,"%0.0f", useKnobs, useNarrow,1) 
     
    
    local list = {"Note","Trigger", "Both"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    --createSlider(track,fxIndex,"Combo",1,"Mode",nil,nil,1,nil,nil,nil,listText,0,"Set wether to trigger from a note or a trigger")
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    -- use trigger
    
    local visualIndexOffset = 0
    if GetParam(track, fxIndex, 1) ~= 0 then 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 1,nil, nil,nil,"%0.0f", useKnobs, useNarrow,3) 
        visualIndexOffset = 1
    end
    -- use note, add threshold
    if GetParam(track, fxIndex, 1) ~= 1 then
        -- trigger threshold for notes
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 1,nil, nil,nil,"%0.0f", useKnobs, useNarrow,3 + visualIndexOffset) 
        visualIndexOffset = visualIndexOffset + 1
    end
    
    -- reset 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,8), nil, nil, nil, true, modulatorParameterWidth, 0,nil, nil,nil,"%0.0f", useKnobs, useNarrow,3 + visualIndexOffset) 
    
    -- reset value
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,9), nil, nil, nil, true, modulatorParameterWidth, 0,nil, nil,nil,"%0.0f", useKnobs, useNarrow,4 + visualIndexOffset) 
    
    
    local list = {"Off","Smooth", "Constant"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    --createSlider(track,fxIndex,"Combo",5,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Set the timer mode for changing the value")
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 5 + visualIndexOffset) 

    local useTimer = GetParam(track, fxIndex, 5) > 0
    if useTimer then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 6 + visualIndexOffset) 
        visualIndexOffset = visualIndexOffset + 1
    end 
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,10), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 6 + visualIndexOffset) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,11), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 7 + visualIndexOffset) 
    
end

function noteVelocityModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    local list = {"Off","Smooth", "Constant"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    local useTimer = GetParam(track, fxIndex, 1) > 0
    createSlider(track,fxIndex,"Combo",1,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Set the timer mode for changing the value", modulatorParameterWidth, (useColumns and useTimer) and 0 or nil, (useColumns and useTimer) and 2 or nil)
    if useTimer then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1 or nil, 2) 
    end
      
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0 or nil, 2) 
    
    local isListening = GetParam(track, fxIndex, 9) == 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons )
    createSlider(track,fxIndex,"ButtonToggle",9,isListening and "Stop" or (useColumns and "Set##minimum" or "Set minimum"),0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set minimum key range", modulatorParameterWidth, useColumns and 1 or nil, 2)   
    reaper.ImGui_PopStyleColor(ctx,3)
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 127, nil,nil,nil,nil, useKnobs, useNarrow,useColumns and 0 or nil,2) 
    local isListening = GetParam(track, fxIndex, 10) == 1
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping )
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),isListening and colorMapping or colorButtons ) 
    createSlider(track,fxIndex,"ButtonToggle",10,isListening and "Stop" or (useColumns and "Set##maximum" or "Set maximum"),0,1,nil,nil,nil,nil,nil,0,"Listen for MIDI input to set maximum key range", modulatorParameterWidth, useColumns and 1 or nil, 2)  
    reaper.ImGui_PopStyleColor(ctx,3)
    
    
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,11), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,3) 
    
    
    createSlider(track,fxIndex,"Checkbox",8,"Pass through MIDI",nil,nil,1,nil,nil,nil,nil,nil, nil, modulatorParameterWidth) 
end


function audioDetectModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0 or nil, 0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0 or nil, 1) 

    local list = {"Off","Smooth", "Constant"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    local useTimer = GetParam(track, fxIndex, 3) > 0
    createSlider(track,fxIndex,"Combo",3,"Timer",nil,nil,1,nil,nil,nil,listText,0,"Set the timer mode for changing the value", modulatorParameterWidth, (useColumns and useTimer) and 0 or nil, (useColumns and useTimer) and 2 or nil)
    if useTimer then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1 or nil, 2) 
    end 
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,1)  
    
    local list = {"Off","On"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    local useNoteOut = GetParam(track, fxIndex, 7) > 0
    createSlider(track,fxIndex,"Combo",7,"Midi out",nil,nil,1,nil,nil,nil,listText,0,"Send out MIDI note when there's a signal", modulatorParameterWidth, (useColumns and useNoteOut) and 0 or nil, (useColumns and useNoteOut) and 2 or nil)
     
    --pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,0)  
    if useNoteOut then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,8), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,1, (useColumns and useNoteOut) and 2 or nil)  
    end
end


function xyPad(name, id, padSize, track, fxIndex, xParam, yParam,pX, pY, padSizeH, ignoreInput, useKnobs, useNarrow)
    
    
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
            setParamAdvanced(track, getAllDataFromParameter(track,fxIndex,xParam), valX)
            setParamAdvanced(track, getAllDataFromParameter(track,fxIndex,yParam), valY)
            
        end
    end
    return click
end

function largeXyPad(name, id, track, fxIndex, pX, pY, useKnobs, useNarrow)
    
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

function xyModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    pX = getAllDataFromParameter(track,fxIndex,0)
    pY = getAllDataFromParameter(track,fxIndex,1)
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    pluginParameterSlider("modulator", pX, nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0 or nil, 2) 
    pluginParameterSlider("modulator", pY, nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1 or nil, 2) 
    
    local padSize = buttonWidth * 2 - 12 - 4
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

function buttonModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    
    
    p = getAllDataFromParameter(track,fxIndex,0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    if reaper.ImGui_Button(ctx, "Button", modulatorParameterWidth, 30) then 
        SetParam(track, fxIndex, 1, p.currentValue > 0.5 and 0 or 1)
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, 0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, 1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 2) 
end


-- TODO make the module smaller/scale depending on size
function macroModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
end


function macroModulator4(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    for i = 0, 3 do 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1 + i * 4), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, 0 + i * 3) 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2 + i * 4), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, 1 + i * 3) 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3 + i * 4), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, 2 + i * 3) 
    end
end

function midiOutModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    -- msg type
    --pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow) 
    
    local list = {"Note On/Off", "Note Off","Note On","Polyphonic Aftertouch","Control Change","Program Change","Channel Aftertouch","Pitch Bend"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    local p = getAllDataFromParameter(track,fxIndex,0)
    local midiType = list[p.value + 1]
    createSlider(track,fxIndex,"Combo",0,"Type",nil,nil,1,nil,nil,nil,listText,0,"Select MIDI output type", modulatorParameterWidth)
    -- msg2
    if p.value ~= 5 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    else 
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    end
    -- msg3
    -- channel
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow, p.value ~= 5 and 2 or 1) 
    -- pb
end



function abSliderModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    --local startPosX, startPosY = beginModulator(name, fxIndex) 
    local sliderIsMapped = #fx.mappings > 0 -- parameterWithNameIsMapped(name) 
    if not a_trackPluginStates then a_trackPluginStates = {}; b_trackPluginStates = {} end
    local hasBothValues = a_trackPluginStates[fx.guid] and b_trackPluginStates[fx.guid]
    local clearName = sliderIsMapped
    
    local buttonName = clearName and "Clear! Values to A" or (a_trackPluginStates[fx.guid] and "A values are saved" or "Set A values")
    local clearType = nil 
    --reaper.ImGui_SetNextItemWidth(ctx, dropDownSize)
    if reaper.ImGui_Button(ctx, buttonName .. "##"..id, modulatorParameterWidth) then
        if mapActiveFxIndex then mapActiveFxIndex = nil end
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
    if reaper.ImGui_Button(ctx, buttonName .. "##"..id, modulatorParameterWidth) then
        if mapActiveFxIndex then mapActiveFxIndex = nil end
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
    
        if reaper.ImGui_Button(ctx, "Clear! Leave values##"..id, modulatorParameterWidth) then
            clearType = "CurrentValue"
        end 
        reaper.ImGui_Spacing(ctx)
        
        -- AB SLIDER
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, true, false, false, modulatorParameterWidth, 0, "", nil,nil,"%0.2f", useKnobs,false) 
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), mapActiveFxIndex == fxIndex and colorMappingPulsating or settings.colors.buttons) 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), mapActiveFxIndex == fxIndex and colorMappingPulsating or settings.colors.buttons)
        if reaper.ImGui_Button(ctx, "Manual mapping##"..id, modulatorParameterWidth) then 
            mapModulatorActivate(fx, fx.output[1], name, nil, #fx.output == 1)
        end
        
        reaper.ImGui_PopStyleColor(ctx,2)
        --reaper.ImGui_Spacing(ctx)
    end
    
    if clearType then
        for _,map in ipairs(fx.mappings) do 
            local fxIndex = map.fxIndex
            local param = map.param
            disableParameterLink(track, fxIndex, param, "CurrentValue")
        end
        --disableAllParameterModulationMappingsByName(name, "CurrentValue")
        if clearType ~= "MaxValue" then
            a_trackPluginStates[fx.guid] = nil
        end
        if clearType ~= "MinValue" then
            b_trackPluginStates[fx.guid] = nil
        end 
    end
    
    
    
    -- MAKES THE MODULATOR NOT MINIMIZE, but also seems redundant
    --[[
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), trackSettings.showAbSliderMappings[fx.guid] and settings.colors.buttonsSpecialActive or settings.colors.buttonsSpecial)
    if reaper.ImGui_Button(ctx, "Show mappings##"..id, modulatorParameterWidth) then 
        trackSettings.showAbSliderMappings[fx.guid] = not trackSettings.showAbSliderMappings[fx.guid]
        saveTrackSettings(track)
    end
    reaper.ImGui_PopStyleColor(ctx)
    
    if trackSettings.showAbSliderMappings[fx.guid] then
        -- not sure if this function should be moved to the root above this one
        drawAllMappingsParametersWithTheirFXOnTop(fx.mappings, modulatorParameterWidth)
    end
    ]]
end


function adsrModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
     local _, min, max = GetParam(track, fxIndex, 0)
     local visualValue = GetFormattedParamValue(track, fxIndex, 0) 
     local visualValueAsFloorNumber = (tonumber(visualValue) and math.floor(tonumber(visualValue)) or visualValue )  .. " ms"
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, nil, nil, "Attack", modulatorParameterWidth, 5.01,visualValueAsFloorNumber, nil, nil, nil, useKnobs, useNarrow,0) 

     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, "A.Tension", modulatorParameterWidth, 0, "", nil, nil, "%0.2f", useKnobs, useNarrow,1) 
     
     local _, min, max = GetParam(track, fxIndex, 1)
     local visualValue = GetFormattedParamValue(track, fxIndex, 1) 
     local visualValueAsFloorNumber = (tonumber(visualValue) and math.floor(tonumber(visualValue)) or visualValue )  .. " ms"
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, "Decay", modulatorParameterWidth, 5.3, visualValueAsFloorNumber, nil, nil, nil, useKnobs, useNarrow,2)
     
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,8), nil, nil, nil, "D.Tension", modulatorParameterWidth, 0, "", nil, nil, "%0.2f", useKnobs, useNarrow,3) 
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, "Sustain", modulatorParameterWidth, 80, "", nil, nil, "%0.0f", useKnobs, useNarrow,4) 

     local _, min, max = GetParam(track, fxIndex, 3)
     local visualValue = GetFormattedParamValue(track, fxIndex, 3) 
     local visualValueAsFloorNumber = (tonumber(visualValue) and math.floor(tonumber(visualValue)) or visualValue )  .. " ms"
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, "Release", modulatorParameterWidth, 6.214, visualValueAsFloorNumber, nil, nil, nil, useKnobs, useNarrow,5)
     
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,9), nil, nil, nil, "R.Tension", modulatorParameterWidth, 0, "", nil, nil, "%0.2f", useKnobs, useNarrow,6) 
     
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, "Min", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,7) 
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, "Max", modulatorParameterWidth, 100, "", nil, nil, "%0.0f", useKnobs, useNarrow,8) 
     pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, "Smooth", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,9) 
end




function msegModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
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
    
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    --createSlider(track,fxIndex,"SliderDouble",0,"Pattern",1,12,100,"%0.0f",nil,nil,nil,nil) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, nil, nil, "Pattern", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow) 
    
    
    
    local syncOff = math.floor(GetParam(track, fxIndex, 2)) == 0
    local syncColumns = (syncOff and settings.ModulatorParameterColumnAmount > 2) and 3 or 2
    createSlider(track,fxIndex,"Combo",1,"Trigger",nil,nil,1,nil,nil,nil,triggersDropDownText,0,"Select how to trigger pattern", modulatorParameterWidth, useColumns and 0, syncColumns)
    scrollHoveredDropdown(GetParam(track, fxIndex, 1), track,fxIndex, 1, triggers,nil, 0, #triggers-1)
    
    --createSlider(track,fxIndex,"Combo",2,"Tempo Sync",nil,nil,1,nil,nil,nil,tempoSyncDropDownText,0,"Select if the tempo should sync")
    --scrollHoveredDropdown(GetParam(track, fxIndex, 2), track,fxIndex, 2, tempoSync,nil, 0, #tempoSync-1)
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, "Sync", modulatorParameterWidth, 0, "", nil, nil, nil, useKnobs, useNarrow, useColumns and 1, syncColumns) 
    
    if syncOff then 
      pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, "Rate", modulatorParameterWidth, 0, "", nil, nil, "%0.2f Hz", useKnobs, useNarrow, useColumns and 2, syncColumns) 
    end
    
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, "Phase", modulatorParameterWidth, 0, "", nil, nil, "%0.2f", useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, "Min", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, "Max", modulatorParameterWidth, 100, "", nil, nil, "%0.0f", useKnobs, useNarrow,2) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, "Smooth", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,3) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,8), nil, nil, nil, "Att. Smooth", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,4) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,9), nil, nil, nil, "Rel. Smooth", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,5) 
    
    -- RETRIGGER DOES NOT WORK. PROBABLY CAUSE IT*S A SLIDER WITH 1 STEP ONLY.
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,13), nil, nil, nil, "Retrigger", modulatorParameterWidth, 0, "", nil, nil, "%0.0f", useKnobs, useNarrow,6) 
    --createSlider(track,fxIndex,"SliderDouble",13,"Retrigger",0,1,1,"%0.0f",nil,nil,nil,nil)
    --createSlider(track,fxIndex,"SliderDouble",14,"Vel Modulation",0,1,1,"%0.2f",nil,nil,nil,nil)
end




function _4in1Out(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, "Input 1", modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, "Input 2", modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, "Input 3", modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, "Input 4", modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,3) 
end





function snjuk2LfoModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    function createShapes() 
        ------------ SHAPE -----------
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorLightBlue)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorTransparent)
        
        local buttonSizeW = modulatorParameterWidth/7
        local buttonSizeH = buttonSizeW
        
        local useExtraLine = false
        if buttonSizeW < 20 then
            buttonSizeW = modulatorParameterWidth/4
            useExtraLine = true
        end 
        buttonSizeW = 20
        buttonSizeH = 20
        
        if not hovered then hovered = {} end
        if not hovered[fxIndex]  then hovered[fxIndex] = {} end
        for i = 1, #shapesPlots do
            plots = shapesPlots[i]
            --ImGui.SetNextItemAllowOverlap(ctx)
            
            local shape = i -1
            local isSelected = GetParam(track, fxIndex, 2) == shape
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), isSelected and colorButtonsActive or (hovered and hovered[fxIndex][i]) and colorButtonsHover or colorButtons )
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotLines(), colorText )
            
            
            local posX, posY = reaper.ImGui_GetCursorPos(ctx) 
            if reaper.ImGui_InvisibleButton(ctx, "##shapeButton" .. fxIndex ..":" .. i, buttonSizeW, buttonSizeH) then 
                SetParam(track, fxIndex, 2, shape)
            end
            local lineX, lineY = reaper.ImGui_GetItemRectMin(ctx)
            if settings.showToolTip then setToolTipFunc("Set shape to: " .. shapeNames[i]) end
            
            reaper.ImGui_SetCursorPos(ctx, posX, posY) 
            
            reaper.ImGui_PlotLines(ctx, '', plots, 0, nil, -1.0, 1.0, buttonSizeW, buttonSizeH)
            reaper.ImGui_PopStyleColor(ctx,2)
            
            if i < #shapesPlots then
                reaper.ImGui_SameLine(ctx)--, buttonSizeW * i) 
                local posX, posY = reaper.ImGui_GetCursorPos(ctx)
                reaper.ImGui_SetCursorPos(ctx, posX-8, posY)
            end
            
            if posX > modulatorParameterWidth - 36 then
                reaper.ImGui_NewLine(ctx)
            end
        end  
        
        reaper.ImGui_PopStyleColor(ctx,3) 
    end
    
    paramOut = "1"
    
    
    
    buttonSize = 20
    
        
    createShapes(true)
    --[[
    
    noteTempoNamesToValues = {}
    noteTemposDropdownText = ""
    for _, t in ipairs(noteTempos) do
        noteTemposDropdownText = noteTemposDropdownText .. t.name .. "\0" 
    end
    local list = {"Sine","Square","Saw L","Saw R","Triangle","Random","Step"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    createSlider(track,fxIndex,"Combo",2,"Shape",nil,nil,1,nil,nil,nil,listText,0,"Select shape of LFO", modulatorParameterWidth)
    ]]
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    if GetParam(track, fxIndex, 2) == 6 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,22), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, false) 
    end
    
    createSlider(track,fxIndex,"Checkbox",6,"Sync",nil,nil,1,nil,nil,nil,nil,nil, nil, modulatorParameterWidth, useColumns and 0) 
    if GetParam(track, fxIndex, 6) == 0 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, nil, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1) 
    else
        local curVal = GetParam(track, fxIndex, 8)
        local visualVal = curVal .. ""
        for _, v in ipairs(noteTempos) do
            if curVal == v.value then
                visualVal = v.name
                break;
            end
        end
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,8), nil, nil, nil, true, modulatorParameterWidth, 1, visualVal,nil,nil,nil, useKnobs, useNarrow, useColumns and 1)  
    end
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,9), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,3) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,10), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,4) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,17), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,5) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,19), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,6) 
end


function snjuk2MathModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    local list = {"Multiply","Add","Substract","Minimum","Maximum"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    createSlider(track,fxIndex,"Combo",2,"Mode",nil,nil,1,nil,nil,nil,listText,0,"Select how to combine input A and B", modulatorParameterWidth)
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    -- a
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0, 2) 
    -- b
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1, 2) 
end


function snjuk2MidiEnvelopeModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    -- delay
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    -- a (ms)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    -- d (ms)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,3)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,4) 
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,2) 
end

function snjuk2Pitch12Modulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth) 
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,24), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0, 2)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,25), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 1, 2)
end
 
function snjuk2ToggleSelect4Modulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow)
    
    
    createSlider(track,fxIndex,"Checkbox",4,"Toggle",nil,nil,1,nil,nil,nil,nil,nil,nil, modulatorParameterWidth) 
    createSlider(track,fxIndex,"Checkbox",6,"Fill",nil,nil,1,nil,nil,nil,nil,nil,nil, modulatorParameterWidth) 
    
end

function snjuk2CurveModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    local list = {"Play","Hold","Note"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    createSlider(track,fxIndex,"Combo",6,"Mode",nil,nil,1,nil,nil,nil,listText,0,"Select the mode for the triggering.\n - PLAY only outputs when Reaper is playing\n - HOLD uses the Trigger X slider for the position", modulatorParameterWidth)
    if GetParam(track, fxIndex, 6) == 2 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0)
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,8), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1)
    elseif GetParam(track, fxIndex, 6) == 1 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0)
    end
    
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,0), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,0)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,1), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,1)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,2), nil, nil, nil, false, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,2)
    
    
    
    if GetParam(track, fxIndex, 6) == 6 then
    end
    
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,3), nil, nil, nil, "Offset", modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,3)
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,4), nil, nil, nil, "Width", modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,4)
end

 
function snjuk2StepsModulator(id, name, modulatorsPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow) 
    local list = {"Play","Hold","Note"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    
    local useColumns = settings.ModulatorParameterColumnAmount > 1
    
    createSlider(track,fxIndex,"Combo",10,"Mode",nil,nil,1,nil,nil,nil,listText,0,"Select the mode for the triggering. 'Play' only outputs when Reaper is playing", modulatorParameterWidth)
    if GetParam(track, fxIndex, 10) == 1 then
        pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,11), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow) 
    else
        createSlider(track,fxIndex,"ButtonToggle",16,"Reset",0,1,nil,nil,nil,nil,nil,0,"Reset steps position", modulatorParameterWidth)
        --pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,16), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow, useColumns and 0 or nil, 2) 
    end
    
    
    -- timebase 
    local timeBase = {"1/1", "1/2", "1/4", "1/8", "1/16", "1/32"} 
    local curVal = GetParam(track, fxIndex, 5)
    local timebaseName = timeBase[curVal]
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,5), nil, nil, nil, true, modulatorParameterWidth, 2, nil,nil,nil,nil, useKnobs, useNarrow,0)
    
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,6), nil, nil, nil, true, modulatorParameterWidth, 1, nil,nil,nil,nil, useKnobs, useNarrow,1) 
    -- smooth
    pluginParameterSlider("modulator", getAllDataFromParameter(track,fxIndex,7), nil, nil, nil, true, modulatorParameterWidth, 0, nil,nil,nil,nil, useKnobs, useNarrow,2) 
    
    local list = {"On","Ping Pong","Off"}
    local listText = ""
    for _, t in ipairs(list) do
        listText = listText .. t .. "\0" 
    end
    createSlider(track,fxIndex,"Combo",2,"Reverse",nil,nil,1,nil,nil,nil,listText,0,"Select the mode for the triggering. 'Play' only outputs when Reaper is playing", modulatorParameterWidth)
    --[[
    ret, newValue = reaper.ImGui_Checkbox(ctx, "Reverse" .. "##" .. paramName .. fxIndex, GetParam(track, fxIndex, 2) == 0)
    if ret then 
        setParameterButReturnFocus(track, fxIndex, 2, newValue and "0" or "2")
    end
    ]]
    
    
    
    --p = getAllDataFromParameter(track,fxIndex,13)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), p.currentValue >= 0.5 and colorButtonsHover or colorButtons)
    --aa, ab = createSlider(track,fxIndex,"ButtonVal",13,"Randomize",0,1,1,nil,nil,nil,nil,0,"Randomize Parameters", modulatorParameterWidth, useColumns and 1 or nil, 2)
    --if aa then
    --    reaper.ShowConsoleMsg("hej\n")
    --end
    if createSlider(track,fxIndex,"ButtonToggle",13,"Randomize",0,1,nil,nil,nil,nil,nil,0,"Randomize Parameters", modulatorParameterWidth, useColumns and 1 or nil, 2) then
    --if createSlider(track,fxIndex,"ButtonReturn",13,"Randomize",0,1,nil,nil,nil,nil,nil,0,"Randomize Parameters", modulatorParameterWidth, useColumns and 1 or nil, 2) then
    --if reaper.ImGui_Button(ctx, "Randomize", modulatorParameterWidth, 20) then 
        --SetParam(track, fxIndex, 13, 1)
        
    end
    --reaper.ImGui_PopStyleColor(ctx, 3)
end
 

function getOutputAndInfoForGenericModulator(track,fxIndex,modulationContainerPos, doNotUseCatch)
    local numParams = GetNumParams(track,fxIndex, doNotUseCatch) 
    local output = {}
    -- make possible to have multiple outputs
    local genericModulatorInfo = {outputParam = -1, indexInContainerMapping = -1}
    for p = 0, numParams -1 do
        --retval, buf = GetNamedConfigParm( track, fxIndex, "param." .. p .. ".container_map.hint_id" )
        -- we would have to enable multiple outputs here later
        retval, buf = GetNamedConfigParm( track, modulationContainerPos, "container_map.get." .. fxIndex .. "." .. p )
        if retval then
            table.insert(output, p)
            genericModulatorInfo = {outputParam = p, indexInContainerMapping = tonumber(buf)}
            break
        end
    end
    return output, genericModulatorInfo
end

function getOutputArrayForModulator(track, fxName, fxIndex, modulationContainerPos)
    local output
    for _, mod in ipairs(factoryModules) do
        if fxName and (fxName == mod.insertName or fxName:match(mod.insertName) ~= nil) then
            return mod.output 
        end
    end
    if not output then
        return getOutputAndInfoForGenericModulator(track,fxIndex,modulationContainerPos)
    end
end

function getOutputNameArrayForModulator(track, fxName, fxIndex, modulationContainerPos)
    for _, mod in ipairs(factoryModules) do
        if fxName and (fxName == mod.insertName or fxName:match(mod.insertName) ~= nil and mod.outputNames) then
            return mod.outputNames
        end
    end
end





function genericModulator(id, name, modulationContainerPos, fxIndex, fxInContainerIndex, isCollabsed, fx, genericModulatorInfo, modulatorParameterWidth, useKnobs, useNarrow)
    
    -- make it possible to have it multi output. Needs to change genericModulatorInfo everywhere.
    local numParams = GetNumParams(track,fxIndex) 
    local isMapped = genericModulatorInfo and genericModulatorInfo.outputParam ~= -1
    
    if not isMapped then
        reaper.ImGui_TextWrapped(ctx, "Select parameters to use as output") 
    end 
    
    local paramShownCount = 0
    for p = 0, numParams -1 do
        
        
        --x, y = reaper.ImGui_GetCursorPos(ctx)
        hide = hideParametersFromModulator ~= fx.guid and trackSettings.hideParametersFromModulator and trackSettings.hideParametersFromModulator[fx.guid] and trackSettings.hideParametersFromModulator[fx.guid][p]
        
        if not hide then
            if genericModulatorInfo.outputParam == p then reaper.ImGui_BeginDisabled(ctx) end
            pInfo = getAllDataFromParameter(track,fxIndex,p)
            if pInfo then
                pluginParameterSlider("modulator", pInfo, nil, nil, nil, false, modulatorParameterWidth, 1, nil, genericModulatorInfo.outputParam, nil, nil, useKnobs, useNarrow, paramShownCount) 
                --reaper.ImGui_Spacing(ctx)
                paramShownCount = paramShownCount + 1
            end
            if genericModulatorInfo.outputParam == p then reaper.ImGui_EndDisabled(ctx) end
            
        end
         
    end
    
    --if drawFaderFeedback(nil, nil, fxIndex,10, 0, 1, isCollabsed, fx) then
    --    mapModulatorActivate(fxIndex,10, fxInContainerIndex, name)
    --end 
    
    
    --if settings.vertical or not isCollabsed then reaper.ImGui_SameLine(ctx) end 
     
    --endModulator(name, startPosX, startPosY, fxIndex)
    return genericModulatorInfo
end


function addVolumePanAndSendControlPlugin(track)
    
    local nameOpened = "Track controls" 
    local fxPosition = AddByNameFX( track, nameOpened, false, 1 )
    if fxPosition == -1 then
        fxPosition = AddByNameFX( track, "Helgobox", false, 1 )
        SetNamedConfigParm( track, fxPosition, 'renamed_name', nameOpened)
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
    
    SetNamedConfigParm(track, fxPosition, "set-state", state)
end

 
factoryModules = {
    { 
      name = "AB Slider",
      tooltip = "Map two positions A and B of plugin parameters on the selected track. Only parameters changed will be mapped",
      func = "general",
      insertName = "JS: AB Slider Modulator",
      output = {0}, 
      layout = abSliderModulator,
    },
    { 
      name = "ACS Native",
      tooltip = "Add an Audio Control Signal (sidechain) modulator which uses the build in Reaper ACS",
      func = "ACS",
      insertName = "JS: ACS Native Modulator",
      output = {0}, 
      layout = acsModulator,
      showOpenGui = true,
    }, 
    { 
      name = "ADSR (snjuk2)",
      --rename = "MIDI Envelope",
      tooltip = "Trigger an envelope with midi note input",
      func = "general",
      insertName = "JS: MIDI Envelope Modulator (SNJUK2)",
      output = {18}, 
      layout = snjuk2MidiEnvelopeModulator,
      showOpenGui = true,
    },
    { 
      name = "ADSR-1 (tilr)",
      rename = "ADSR (tilr)",
      tooltip = "Add an ADSR that uses the plugin created by tilr",
      func = "general",
      insertName = "JS: ADSR-1",
      required = isAdsr1Installed,
      website = "https://forum.cockos.com/showthread.php?t=286951",
      requiredToolTip = 'Install the ReaPack by "tilr" first.\nClick to open webpage',
      output = {10}, 
      layout = adsrModulator,
      showOpenGui = true,
    },
    { 
      name = "Audio Detect",
      tooltip = "Use audio signale detection as a modulator",
      func = "general",
      insertName = "JS: Audio Detect Modulator",
      output = {0}, 
      layout = audioDetectModulator,
    },
    { 
      name = "Button",
      tooltip = "A button toggle",
      func = "general",
      insertName = "JS: Button Modulator",
      output = {0}, 
      layout = buttonModulator,
    },
    { 
      name = "Counter",
      tooltip = "Count note or trigger input as a modulator",
      func = "general",
      insertName = "JS: Counter Modulator",
      output = {0}, 
      layout = counterModulator,
    },
    { 
      name = "Curve (snjuk2)",
      rename = "Curve",
      tooltip = "Create a curve for modulation and trigger it in various ways",
      func = "general",
      insertName = "JS: Curve (SNJUK2)",
      output = {9}, 
      layout = snjuk2CurveModulator,
      showOpenGui = true,
    }, 
    { 
      name = "Keytracker",
      tooltip = "Use the pitch of notes as a modulator",
      func = "general",
      insertName = "JS: Keytracker Modulator",
      output = {0}, 
      layout = keytrackerModulator,
    },
    { 
      name = "LFO Native",
      tooltip = "Add an LFO modulator that uses the build in Reaper LFO which is sample accurate",
      func = "LFO",
      insertName = "JS: LFO Native Modulator",
      output = {0}, 
      layout = nlfoModulator,
    }, 
    { 
      name = "LFO (snjuk2)",
      tooltip = "Add an LFO modulator that uses the LFO build by SNJUK2",
      func = "general",
      insertName = "JS: LFO Modulator (SNJUK2)",
      output = {23}, 
      layout = snjuk2LfoModulator,
      showOpenGui = true,
    },
    { 
      name = "Macro",
      tooltip = "A slider for control multiple parameter",
      func = "general",
      insertName = "JS: Macro Modulator",
      output = {0}, 
      layout = macroModulator,
    }, 
    { 
      name = "Macro 4",
      tooltip = "4 sliders for control multiple parameter",
      func = "general",
      insertName = "JS: Macro 4 Modulator",
      output = {0, 4, 8, 12}, 
      layout = macroModulator4,
    }, 
    { 
      name = "Math (snjuk2)",
      rename = "Math",
      tooltip = "4 sliders for control multiple parameter",
      func = "general",
      insertName = "JS: Math Modulator (SNJUK2)",
      output = {3}, 
      layout = snjuk2MathModulator,
    },
    { 
      name = "MSEG-1 (tilr)",
      rename = "MSEG",
      tooltip = "Add a multi-segment LFO / Envelope generator\nthat uses the plugin created by tilr",
      func = "general",
      insertName = "JS: MSEG-1",
      required = isAdsr1Installed,
      website = "https://forum.cockos.com/showthread.php?t=286951",
      requiredToolTip = 'Install the ReaPack by "tilr" first.\nClick to open webpage',
      output = {10}, 
      layout = msegModulator,
      showOpenGui = true,
    },
    { 
      name = "MIDI Fader",
      tooltip = "Use a MIDI fader as a modulator",
      func = "general",
      insertName = "JS: MIDI Fader Modulator",
      output = {0}, 
      layout = midiCCModulator,
    },
    { 
      name = "Note Velocity",
      tooltip = "Use note velocity as a modulator",
      func = "general",
      insertName = "JS: Note Velocity Modulator",
      output = {0}, 
      layout = noteVelocityModulator,
    },
    { 
      name = "Pitch 12 (snjuk2)",
      rename = "Pitch 12",
      tooltip = "Have a modulator with 12 outputs, one for each midi pitch",
      func = "general",
      insertName = "JS: Pitch 12 Modulator (SNJUK2)",
      output = {12,13,14,15,16,17,18,19,20,21,22,23}, 
      outputNames = {"C", "C#", "D", "D#", "E", "F", "F#","G","G#","A","A#","B"},
      layout = snjuk2Pitch12Modulator,
    }, 
    { 
      name = "Steps (snjuk2)",
      rename = "Steps",
      tooltip = "Set steps as output for this modulators",
      func = "general",
      insertName = "JS: Steps Modulator (SNJUK2)",
      output = {19}, 
      layout = snjuk2StepsModulator,
      showOpenGui = true,
    },
    { 
      name = "Toggle Select 4 (snjuk2)",
      rename = "Toggle Select 4",
      tooltip = "Slide through 4 different outputs as modulators",
      func = "general",
      insertName = "JS: Toggle Select 4 Modulator (SNJUK2)",
      output = {0,1,2,3}, 
      layout = snjuk2ToggleSelect4Modulator,
    },
    { 
      name = "4-in-1-out",
      tooltip = "Map 4 inputs to 1 output",
      func = "general",
      insertName = "JS: 4-in-1-out Modulator",
      output = {0}, 
      layout = _4in1Out,
    },
    
    { 
      name = "XY",
      tooltip = "XY pad to control two parameters",
      func = "general",
      insertName = "JS: XY Modulator",
      output = {0, 1}, 
      layout = xyModulator,
    }, 
}

local extraModules = {
    name = "MIDI Output",
}

          
function moduleButton(text, tooltip, width)
    local click = false 
    
    if reaper.ImGui_Selectable(ctx, text, false, nil, width) then 
        click = true
    end 
    
    
    setToolTipFunc(tooltip)  
    
    reaper.ImGui_Spacing(ctx)
    return click
end


function menuHeader(text, variable, tooltip, width)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), colorButtonsHover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), colorButtonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed)
    local textState = (not settings[variable] and "Show" or "Hide") 
    if reaper.ImGui_Button(ctx, text, width) then  
        settings[variable] = not settings[variable]
        saveSettings()
    end
    
    reaper.ImGui_PopStyleColor(ctx,4)
    setToolTipFunc(textState .. " " .. tooltip)  
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

          
                
function fxPresetsPanel(ctx, addToParameter, id) 

    
    
    local click = false
    local modulationContainerPos, insert_position
    local curPosY = reaper.ImGui_GetCursorPosY(ctx)
    
    local height = id and settings.modulesPopupHeight or nil
    local width = id and settings.modulesWidth or nil -- (settings.vertical and 250 or nil)
    local widthForClippingText = (id or not settings.vertical) and settings.modulesWidth - (id and 16 or 20) or elementsWidthInVertical -24
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4,2)
    id = id or ""
    if reaper.ImGui_BeginChild(ctx, "fx list" .. id, width, height) then -- , id and nil or reaper.ImGui_ChildFlags_AutoResizeY()) then
    
        menuHeader("FX chain presets [" .. #fxChainPresetsFiles .."]", "showFxChainPresets", "FX chain presets", widthForClippingText)
        if settings.showFxChainPresets then 
            
            for _, val in ipairs(fxChainPresetsFiles) do
                local tooltip = nil
                if moduleButton("+ " .. val.name, tooltip, widthForClippingText) then
                
                
                end
            end
        end
        
        reaper.ImGui_Separator(ctx)
    
    
        ImGui.EndChild(ctx)
    end 
    
    reaper.ImGui_PopStyleVar(ctx)
end



function modulesPanel(ctx, addToParameter, id, width_from_parent, height_from_parent) 

    local click = false
    local modulationContainerPos, insert_position
    local curPosY = reaper.ImGui_GetCursorPosY(ctx)
    
    local height = id and settings.modulesPopupHeight or height_from_parent
    local width = id and settings.modulatorsWidth or width_from_parent -- (settings.vertical and 250 or nil)
    local widthForClippingText = (id) and settings.modulatorsWidth - (id and 16 or 12) or (width_from_parent and width_from_parent - 16 or elementsWidthInVertical -24)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4,2)
    id = id or ""
    if reaper.ImGui_BeginChild(ctx, "modules list" .. id, width, height) then -- , id and nil or reaper.ImGui_ChildFlags_AutoResizeY()) then
    
    --reaper.ImGui_SetNextWindowSizeConstraints(ctx, 0, 100, 200, 200)
    --if reaper.ImGui_BeginChild(ctx, "modules list", 0.0, 0.0, nil,scrollFlags) then
        local currentFocus 
        local nameOpened
        
        
        menuHeader("Factory [" .. #factoryModules .."]", "showBuildin", "factory modulators", widthForClippingText)
        if settings.showBuildin then 
            
            for _, val in ipairs(factoryModules) do
                local notInstalled = (val.requiredToolTip and not val.required)
                local tooltip = notInstalled and val.requiredToolTip or val.tooltip
                
                if notInstalled then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorTextDimmed) end
                
                if moduleButton("+ " .. val.name, tooltip, widthForClippingText) then
                    if val.func ~= "Any" then
                        currentFocus = reaper.JS_Window_GetFocus()
                    end
                    if val.func == "general" then 
                        if notInstalled then
                            openWebpage(val.website)
                        else
                            modulationContainerPos, insert_position = insertFXAndAddContainerMapping(track, val.insertName, val.rename and val.rename or val.name) 
                        end
                    elseif val.func == "ACS" then 
                        modulationContainerPos, insert_position = insertACSAndAddContainerMapping(track)
                    elseif val.func == "LFO" then 
                        modulationContainerPos, insert_position = insertLocalLfoFxAndAddContainerMapping(track)
                    elseif val.func == "Any" then 
                        browserHwnd, browserSearchFieldHwnd = openFxBrowserOnSpecificTrack() 
                        fx_before = getAllTrackFXOnTrackSimple(track)  
                        moveToModulatorContainer = true
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
                    modulationContainerPos, insert_position = insertFXAndAddContainerMapping(track, module.fxName, visualName)
                    mapParameterToContainer(track, modulationContainerPos, insert_position, module.outputParam)
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
        
        
        local count = #settings.userModulators + (addToParameter and 0 or 1)
        menuHeader("User [" .. count .."]", "showPreset", "modulator presets", widthForClippingText)
        if settings.showPreset then  
            if not addToParameter then
                if moduleButton("+ [ANY]", "Add any FX as a modulator", widthForClippingText) then 
                    browserHwnd, browserSearchFieldHwnd = openFxBrowserOnSpecificTrack() 
                    fx_before = getAllTrackFXOnTrackSimple(track) 
                    click = true
                    moveToModulatorContainer = true
                end 
            end
            
            for i, module in ipairs( settings.userModulators) do
                local visualName = module.name and module.name or module.fxName
                if moduleButton("+ " .. visualName .. "##" .. i, module.description, widthForClippingText) then
                    currentFocus = reaper.JS_Window_GetFocus()
                    nameOpened = visualName
                    modulationContainerPos, insert_position = insertFXAndAddContainerMapping(track, module.fxName, visualName)
                    
                    if module.outputParam then
                        mapParameterToContainer(track, modulationContainerPos, insert_position, module.outputParam)
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
                        local guid = GetFXGUID( track, insert_position )
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
        
        
        menuHeader("Extra [" .. 2 .."]", "showExtra", "extra functions", widthForClippingText)
        if settings.showExtra then  
        
            -- set realearn params on the run after the first one
            if setTrackControlParamsOnIndex then
                setVolumePanAndSendControlPluginParams(track, setTrackControlParamsOnIndex) 
                setTrackControlParamsOnIndex = nil
            end
            
            local tooltip = not isReaLearnInstalled and 'Install Helgobox to have ReaLearn installed first.\nClick to open webpage' or "Control you volume, pan and send with modulators.\n[This is not a modulator and have to be placed outside the modulator folder]"
            if not isReaLearnInstalled then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorGrey) end
            if moduleButton("+ Track controls", tooltip, widthForClippingText) then
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
            
            if moduleButton("+ MIDI Out", "Output a midi message", widthForClippingText) then
                modulationContainerPos, insert_position = insertFXAndAddContainerMapping(track, "JS: MIDI Out Modulator", "Midi Out")  
                currentFocus = reaper.JS_Window_GetFocus()
                click = true
            end
        end
        
        reaper.ImGui_Separator(ctx)
        
        
        if currentFocus then 
            --reaper.ShowConsoleMsg(modulationContainerPos .. " - ".. insert_position .. "\n")
            --openCloseFx(track, insert_position, false)
            
            fxIsShowing = GetOpen(track,insert_position)
            fxIsFloating = GetFloatingWindow(track,insert_position)
            if fxIsShowing then
                showFX(track, insert_position, fxIsFloating and 2 or 0) 
            end
            
            if modulationContainerPos then
                containerIsShowin = GetOpen(track,modulationContainerPos)
                containerIsFloating = GetFloatingWindow(track,modulationContainerPos)
                if containerIsShowin then
                    showFX(track, modulationContainerPos, containerIsFloating and 2 or 0) 
                end
            end
            
            --local newFocus = reaper.JS_Window_GetFocus() 
            --if newFocus ~= currentFocus and reaper.JS_Window_GetTitle(newFocus):match(nameOpened) ~= nil then 
             --   reaper.JS_Window_Show(newFocus, "HIDE") 
            --end
        end

        ImGui.EndChild(ctx)
    end 
    
    reaper.ImGui_PopStyleVar(ctx)
    
    
    --[[
    if moveToModulatorContainer then
        doNotMoveToModulatorContainer = nil
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
                SetNamedConfigParm( track, newFxIndex, 'renamed_name', fxName:gsub("^[^:]+: ", "")) 
                modulationContainerPos, insert_position = movePluginToContainer(track, newFxIndex )
                renameModulatorNames(track, modulationContainerPos)
                browserHwnd = nil
                paramTableCatch = {}
                reaper.ShowConsoleMsg("added\n")
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
            --fx_before = nil
            --fx_after = nil
            firstBrowserHwnd = nil
            browserSearchFieldHwnd = nil
            browserHwnd = nil
            moveToModulatorContainer = nil
            
        end  
    end 
    ]]
    return click, modulationContainerPos, insert_position
end

function compareTrackFxArray(fx_before, fx_after)
    if #fx_after ~= #fx_before then return false end
    for i, fx in ipairs(fx_after) do
        if not fx_before[i] or fx.name ~= fx_before[i].name then
            return false
        end
    end
    return true
end


function waitForClosingAddFXBrowser(pathForNextIndex, fx_before) 
    if browserHwnd and track and track == lastTrack then 
        if wasSetToFloatingAuto == nil then
            wasSetToFloatingAuto = setFxFloatAutoToTrue()
        end
        
        firstBrowserHwnd = firstBrowserHwnd and firstBrowserHwnd + 1 or 0 
        
        fx_after = getAllTrackFXOnTrackSimple(track)
        if #fx_after > #fx_before then
            local addedFxIndex
            local fxName
            for i, fx in ipairs(fx_after) do
                if not fx_before[i] or fx.name ~= fx_before[i].name then
                    addedFxIndex = fx.fxIndex
                    fxName = fx.name
                    break;
                end
            end
            
            -- An FX was added
            
            if settings.closeFxWindowAfterBeingAdded then
                openCloseFx(track, addedFxIndex, false) 
            end
            
            if moveToModulatorContainer then
                SetNamedConfigParm( track, addedFxIndex, 'renamed_name', fxName:gsub("^[^:]+: ", "")) 
                modulationContainerPos, insert_position = movePluginToContainer(track, addedFxIndex )
                renameModulatorNames(track, modulationContainerPos)
            else
                newFxIndex = addNewFXToEnd and addedFxIndex or moveFxIfNeeded(pathForNextIndex, addedFxIndex, addNewFXToEnd)
            end
            browserHwnd = nil
            --reloadParameterLinkCatch = true
            --last_paramTableCatch = {}
            paramTableCatch = {}
            
            --if not wasSetToFloatingAuto then toggleFxFloatAuto(); wasSetToFloatingAuto = nil end
            return newFxIndex
        end
         
         if isAddFXAsLast and (not last_isAddFXAsLast_time or time - last_isAddFXAsLast_time > 0.5) then
            addNewFXToEnd = not addNewFXToEnd
            last_isAddFXAsLast_time = time
         end
        --if moveToModulatorContainer then
            if not addingAnyModuleWindow(browserHwnd, moveToModulatorContainer) then
                reaper.JS_Window_Destroy(browserHwnd)
                browserHwnd = nil
            end
        --end
        
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
        moveToModulatorContainer = nil
        
        if wasSetToFloatingAuto ~= nil and wasSetToFloatingAuto == false then toggleFxFloatAuto(); wasSetToFloatingAuto = nil end
        
    end  
end















function setToolTipFunc(text, color)
    if not HideToolTipTemp and settings.showToolTip and text and #tostring(text) > 0 then 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),colorTextDimmed) 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),colorBlack) 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorText) 
        ImGui.SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx,3)
    end
end


function setToolTipFunc3(text1, text2, text3, text4, text5)
    if settings.showToolTip and text1 and #text1 > 0 then  
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorText) 
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),colorTextDimmed) 
        reaper.ImGui_BeginTooltip(ctx)
        
        reaper.ImGui_TextColored(ctx, colorText, text1)
        if text2 then
            reaper.ImGui_TextColored(ctx, colorTextDimmed, text2)
        end
        if text3 then
            reaper.ImGui_TextColored(ctx, colorText, text3)
        end
        if text4 then
            reaper.ImGui_TextColored(ctx, colorTextDimmed, text4)
        end
        if text5 then
            reaper.ImGui_TextColored(ctx, colorText, text5)
        end
        reaper.ImGui_EndTooltip(ctx)
        --ImGui.SetItemTooltip(ctx, text) 
        reaper.ImGui_PopStyleColor(ctx)
    end
end


function setToolTipFunc2(text,color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),color and color or colorText)   
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),colorTextDimmed) 
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),colorBlack) 
    reaper.ImGui_BeginTooltip(ctx)
    --reaper.ImGui_Text(ctx,addNewlinesAtSpaces(text,26))
    reaper.ImGui_Text(ctx, text)
    reaper.ImGui_EndTooltip(ctx)
    reaper.ImGui_PopStyleColor(ctx, 3)
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

local sliderHeight = 14


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


function nativeReaperModuleParameter(id, track, fxIndex, paramOut,  _type, paramName, visualName, min, max, divide, valueFormat, sliderFlags, checkboxFlipped, dropDownText, dropdownOffset,tooltip, width, resetValue, p, useKnobs, useNarrow, visualIndex, parameterColumnAmount) 
    local faderResolution = width --/ range
    
    if visualIndex then
        local parameterColumnAmount = parameterColumnAmount and parameterColumnAmount or settings.ModulatorParameterColumnAmount 
        width = findModulationParameterWidth(parameterColumnAmount, width)
        if visualIndex > 0 then
            samelineIfWithinColumnAmount(visualIndex, parameterColumnAmount, width)
        end
    end
    
    if useKnobs == nil then useKnobs = settings.useKnobs end
    if useNarrow == nil then useNarrow = settings.useNarrow end
    
    local buttonId = fxIndex .. paramName
    local moduleId = "native" .. id
    local fullId = "baseline" .. buttonId .. moduleId
    local range = max - min
    local colorPos = colorSliderBaseline
    local valueColor = colorText
    local textColor = colorText
    local name = visualName
    
    
    if width < 60 then
        useNarrow = true
    end
    
    local totalSliderHeight = sliderHeight + 16
    if useNarrow and useKnobs then
        totalSliderHeight = totalSliderHeight + 16
    end
    
    local ret, currentValue = GetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName)    
    if ret and tonumber(currentValue) then
        currentValue = tonumber(currentValue)
        --local currentValueNormalized = p.currentValueNormalized
        valueFormat = (ret and tonumber(currentValue * divide)) and string.format(valueFormat, tonumber(currentValue * divide)) or ""
        
    --function nativeReaperModuleParameter(id, nameOnSide, buttonId, currentValue,  min, max, divide, valueFormat, sliderFlags, width, _type, colorPos, p, resetValue)
        
        reaper.ImGui_InvisibleButton(ctx, "slider" .. buttonId .. moduleId, width > 0 and width or 1, totalSliderHeight) 
        
        if reaper.ImGui_IsItemHovered(ctx) then
            if not dragKnob then 
                dragKnob = fullId
                mouseDragStartX = mouse_pos_x
                mouseDragStartY = mouse_pos_y
                if not isMouseDown and not anyModifierIsPressed then 
                    local toolTip1 = "Drag to set " .. (parameterLinkActive and "baseline" or "value" ).. " of " .. name ..
                    "\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameter.fineAdjust) .. " for fine resolution"
                    --.. "\n - right click for more options"
                    .."\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameter.scrollValue) .. " and scroll to change value" 
                    local toolTip2 = "-- Click --"
                    local toolTip3 = resetValue and (" - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.resetValue) .. " to reset value") or nil
                    local toolTip4 = "This parameter can't be modulated\n    because it's an internal value!"
                    setToolTipFunc3(toolTip1, toolTip2, toolTip3, toolTip4, toolTip5)
                end
            end  
        end
        
        local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
        local posXOffset = minX + settings.thicknessOfBigValueSlider /2 + 2 
        local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
        
        parStartPosX, parStartPosY = reaper.ImGui_GetItemRectMin(ctx)
        if not canBeMapped then
            --reaper.ImGui_SameLine(ctx)
            --if textButtonNoBackgroundClipped(visualName, textColor,nameOnSideWidth) and resetValue then 
            --    if ret then SetNamedConfigParm( track, fxIndex, 'param.'..paramOut..'.' .. paramName, resetValue/divide) end 
            --end
        end
        
        endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
        parEndPosX, parEndPosY = reaper.ImGui_GetItemRectMax(ctx)
        
        if not p then p = {} end
        p.currentValueNormalized = (currentValue - min) / range
        p.paramOut = paramOut
        p.fxIndex = fxIndex
        p.paramName = paramName
        p.min = min
        p.max = max
        p.range = range
        
        sliderWidthAvailable = drawCustomSlider(visualName, valueFormat, valueColor, colorWhite, p.currentValueNormalized, 0, minX, minY, maxX, maxY, sliderFlags, 0, 1,nil, nil, nil, nil, nil, nil, dragKnob == fullId,false, p, nil, buttonId .. moduleId, useKnobs, useNarrow)
        if not useKnobs then 
            faderResolution = sliderWidthAvailable --/ range
        end
        
        
        setParameterValuesViaMouse(track, buttonId, moduleId, p, range, min, currentValue, faderResolution, resetValue, true, sliderFlags, useKnobs) 

    end
end

function drawCustomKnob(ctx, id, relativePosX, relativePosY, size, amount, textOnTop, textOverlayColor, textOverlayColorBackground, border, nonAvailable)

    local click = false
    reaper.ImGui_InvisibleButton(ctx, "##"..id, size, size)
    if reaper.ImGui_IsItemHovered(ctx) then -- and isMouseClick then
        click = true
    end
    local x, y = reaper.ImGui_GetItemRectMin(ctx)
    --local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 

    local center_x = x + size / 2
    local center_y = y + size / 2
    local radius = size / 2 * 1--* (outerCircleColor and 1 or 0.8) -- Scale down a bit for aesthetic reasons

    -- Map 'amount' from [0, 1] to [-135, 135] degrees
    local startPosAngle = - 230 --246
    local maxAngel = 278
    local angle = (startPosAngle + amount * maxAngel) * (math.pi / 180)
    local leftAngle = startPosAngle * (math.pi / 180)
    local centerAngle = (startPosAngle + (0.5) * maxAngel) * (math.pi / 180)
    local rightAngle = (startPosAngle + (1) * maxAngel) * (math.pi / 180)
    
    -- Calculate end point (p2_x, p2_y)
    local p2_x = center_x + math.cos(angle) * radius
    local p2_y = center_y + math.sin(angle) * radius
    
    -- draw shade of background
    
    local sliderBg = (click or dragKnob == id) and settings.colors.sliderBackgroundHover or settings.colors.sliderBackground
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, leftAngle, rightAngle)
    reaper.ImGui_DrawList_PathStroke(draw_list, sliderBg, reaper.ImGui_DrawFlags_None(), 4) 
    
    if settings.mappingWidthOnlyPositive then
        if amount >= 0 then
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, leftAngle, angle)
            reaper.ImGui_DrawList_PathStroke(draw_list, settings.colors.sliderWidth, reaper.ImGui_DrawFlags_None(), 4) 
            reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, settings.colors.sliderOutput, 2)
        end
    else
        local col = amount >= 0.5 and settings.colors.sliderWidth or settings.colors.sliderWidthNegative
        reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, centerAngle, angle)
        reaper.ImGui_DrawList_PathStroke(draw_list, col, reaper.ImGui_DrawFlags_None(), 4) 
        reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, settings.colors.sliderOutput, 2)
    end

    
    --reaper.ImGui_DrawList_AddRect(draw_list, x + 1, y + 1, x + size - 1, y + size - 1, border, size, nil, 1)

    --reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + size, y + size, border, size, nil, 1)
    return click
end

function modulatorMappingItems(minX, minY, maxX, maxY, p, id, padColor, widthAvailableWithSpaceTaken)
        
        maxX = maxX  -- 20
        minY = minY + 2
        if p.parameterLinkActive and p.width then
            local nameForText = showingMappings and p.name or p.parameterLinkName
            local toolTipText = (p.parameterModulationActive and 'Disable' or 'Enable') .. ' "' .. (p.parameterLinkName and p.parameterLinkName or "") .. '" parameter modulation of ' .. (p.name and p.name or "")
            local curPosX, curPosY = reaper.ImGui_GetCursorScreenPos(ctx)
            local posYOffset = 1
            local posXOffset = 1
            
            if showingMappings then 
                -- parStartPosX, parStartPosY = reaper.ImGui_GetCursorScreenPos(ctx)
            end
            
            
            if settings.showWidthInParameters then
                
                if widthAvailableWithSpaceTaken - 35 > 30 then
                    reaper.ImGui_SetCursorScreenPos(ctx, maxX+posXOffset, minY + 6)
                    
                    local overlayText = nil -- isMouseDown and "Width\n" .. math.floor(linkWidth * 100) .. "%"
                    if widthKnob(ctx, "width" .. id, 0, 0, 20, minWidth == 0 and p.width or p.width / 2 + 0.5, overlayText,  p.parameterModulationActive and colorText or colorTextDimmed, settings.colors.buttons, padColor, settings.colors.buttonsActive) then
                        
                        if not dragKnob then
                            dragKnob = "width" .. id
                            mouseDragStartX = mouse_pos_x
                            mouseDragStartY = mouse_pos_y
                            if not isMouseDown then  
                                if not overlayActive then setToolTipFunc("Width: " .. math.floor(p.width * 100) .. "%") end
                                --reaper.ImGui_SetTooltip(ctx, parameterLinkName .. " width: " ..)
                            end
                        elseif not p.parameterModulationActive then
                            if isMouseDown then   
                                toggleeModulatorAndSetBaselineAcordingly(track, p.fxIndex, p.param, not p.parameterModulationActive)
                            end
                            setToolTipFunc(toolTipText)
                        end
                    end
                    
                    posXOffset = posXOffset + 22
                end 
            end
            --if not settings.showWidthInParameters then reaper.ImGui_BeginDisabled(ctx) end
            if settings.showEnableAndBipolar then 
                if widthAvailableWithSpaceTaken - 13 > 30 then
                    reaper.ImGui_SetCursorScreenPos(ctx, maxX + posXOffset, minY) 
                    if enableButton(ctx, id, 10, padColor) then
                        toggleeModulatorAndSetBaselineAcordingly(track, p.fxIndex, p.param, not p.parameterModulationActive) 
                    end
                    if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        --
                        disableParameterLink(track, p.fxIndex, p.param)
                        -- delete curver plugin if it is a curver after disabling mapping
                        if p.isCurver then
                            DeleteFX(track, p.parameterLinkFXIndexForCurve)
                        end
                    end
                    
                    if not overlayActive then setToolTipFunc(toolTipText.. "\n - Doubleclick to remove") end
                    
                    reaper.ImGui_SetCursorScreenPos(ctx, maxX + posXOffset, minY + 10)
                    if drawModulatorDirection(10, 16, p, track, p.fxIndex, p.param, id, -2,1, padColor, toolTipText) then -- not settings.mappingModeBipolar and padColor or (p.bipolar and padColor or colorMappingLight), toolTipText)  then
                        if settings.mappingModeBipolar then
                            toggleBipolar(track, p.fxIndex, p.param, p.bipolar)
                        else
                            changeDirection(track, p)
                        end 
                    end 
                    if not overlayActive then setToolTipFunc("Change direction of " .. ' "' .. tostring(parameterLinkName) .. '"' ) end
                end
                
                posXOffset = posXOffset + 13
            end
            
        end
        --
    --end
end


function enableButton(ctx, id, size, color) 
    local click = false
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color)
    if reaper.ImGui_Button(ctx, "##enable" .. id, size,size) then
       click = true 
    end 
    reaper.ImGui_PopStyleColor(ctx, 4)
    reaper.ImGui_PopStyleVar(ctx,2)
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
    
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, settings.colors.sliderBackgroundHover, 3, 0, 1)
    end
    
    return click
end

function drawModulatorDirection(sizeW, sizeH, p, track, fxIndex, param, buttonId, offsetX, offsetY, color, toolTip) 
    local pad = 3
    local bipolar = p.bipolar
    local direction = p.direction
    local width = p.width
    local click = false
    if reaper.ImGui_InvisibleButton(ctx, "##direction" .. buttonId, sizeW,sizeH) then
        click = true
    end
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
    
    if reaper.ImGui_IsItemHovered(ctx) then
        --reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, minY, maxX, maxY, settings.colors.sliderBackground, 3)
        reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, settings.colors.sliderBackgroundHover, 3, nil, 1)
    end
    
    minX = minX + pad / 2 + offsetX
    minY = minY + pad - 1 + offsetY
    sizeW = sizeW
    sizeH = sizeH - pad * 2
    local angle = 4
    --local color = color and color obipolar and (colorOn and colorOn or colorMapping) or colorTextDimmed
    -- vertical line
    reaper.ImGui_DrawList_AddLine(draw_list, minX + sizeW/2, minY, minX + sizeW/2, minY+sizeH, color)
    -- top arrow 
    if settings.mappingModeBipolar and (bipolar or width >= 0) or (direction >= 0) then
        reaper.ImGui_DrawList_AddLine(draw_list, minX+sizeW/angle, minY + sizeH / angle, minX + sizeW/2, minY, color)
        reaper.ImGui_DrawList_AddLine(draw_list, minX+sizeW-sizeW/angle, minY + sizeH / angle, minX + sizeW/2, minY, color)
    end
    
    -- bottom arrow
    if settings.mappingModeBipolar and (bipolar or width < 0) or (direction <= 0) then
        reaper.ImGui_DrawList_AddLine(draw_list, minX+sizeW/angle, minY + sizeH - sizeH / angle, minX + sizeW/2, minY+sizeH, color)
        reaper.ImGui_DrawList_AddLine(draw_list, minX+sizeW-sizeW/angle, minY + sizeH - sizeH / angle, minX + sizeW/2, minY + sizeH, color)
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

function widthKnob(ctx, id, relativePosX, relativePosY, size, amount, textOnTop, textOverlayColor, textOverlayColorBackground, border, nonAvailable)

    local click = false
    reaper.ImGui_InvisibleButton(ctx, "##"..id, size, size)
    if reaper.ImGui_IsItemHovered(ctx) then -- and isMouseClick then
        click = true
    end
    local x, y = reaper.ImGui_GetItemRectMin(ctx)
    --local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 

    local center_x = x + size / 2
    local center_y = y + size / 2
    local radius = size / 2 * 1--* (outerCircleColor and 1 or 0.8) -- Scale down a bit for aesthetic reasons

    -- Map 'amount' from [0, 1] to [-135, 135] degrees
    local startPosAngle = - 230 --246
    local maxAngel = 278
    local angle = (startPosAngle + amount * maxAngel) * (math.pi / 180)
    local leftAngle = startPosAngle * (math.pi / 180)
    local centerAngle = (startPosAngle + (0.5) * maxAngel) * (math.pi / 180)
    local rightAngle = (startPosAngle + (1) * maxAngel) * (math.pi / 180)
    
    -- Calculate end point (p2_x, p2_y)
    local p2_x = center_x + math.cos(angle) * radius
    local p2_y = center_y + math.sin(angle) * radius
    
    -- draw shade of background
    
    local sliderBg = (click or dragKnob == id) and settings.colors.sliderBackgroundHover or settings.colors.sliderBackground
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, leftAngle, rightAngle)
    reaper.ImGui_DrawList_PathStroke(draw_list, sliderBg, reaper.ImGui_DrawFlags_None(), 4) 
    
    
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, size / 5, settings.colors.sliderBackground & 0xFFFFFF44) 
    
    if settings.mappingWidthOnlyPositive then
        if amount >= 0 then
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, leftAngle, angle)
            reaper.ImGui_DrawList_PathStroke(draw_list, settings.colors.sliderWidth, reaper.ImGui_DrawFlags_None(), 4) 
            reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, settings.colors.sliderOutput, 2)
        end
    else
        local col = amount >= 0.5 and settings.colors.sliderWidth or settings.colors.sliderWidthNegative
        reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, centerAngle, angle)
        reaper.ImGui_DrawList_PathStroke(draw_list, col, reaper.ImGui_DrawFlags_None(), 4) 
        reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, settings.colors.sliderOutput, 2)
    end

    
    --reaper.ImGui_DrawList_AddRect(draw_list, x + 1, y + 1, x + size - 1, y + size - 1, border, size, nil, 1)

    --reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + size, y + size, border, size, nil, 1)
    return click
end



function drawCustomSlider(showName, valueName, valueColor, padColor, currentValue, spaceTaken, minX, minY, maxX, maxY, sliderFlags, min, max,parameterLinkActive, parameterModulationActive, linkValue, linkWidth, baseline, offset, isHovered, showMappingText, p, sliderPos, id, useKnobs, useNarrow, specialSetting)
    
    
    if useKnobs == nil then useKnobs = settings.useKnobs end
    if useNarrow == nil then useNarrow = settings.useNarrow end
    
    local widthAvailable = maxX - minX
    local widthAvailableWithSpaceTaken = maxX - minX + spaceTaken
    local centerOfWidget = minX + (widthAvailableWithSpaceTaken) / 2
    local moveTextToTheLeft = false
    local modulatorMappingNextToTitle = (useNarrow and (not useKnobs and not showMappingText) or not useNarrow)
    -- background
    if (not specialSetting or specialSetting ~= "WetKnob") then
        reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, minY, maxX + spaceTaken, maxY, settings.colors.sliderAreaBackground, 4) 
    end
    
    if sliderPos and p.parameterLinkActive then
        modulatorMappingItems(minX, minY + (not modulatorMappingNextToTitle and 14 or 0), maxX, maxY, p, id, padColor, widthAvailableWithSpaceTaken)
        
        if (isAdjustWidthToggle and dragKnob == "baseline" .. id) or ((isAnyMouseDown or isScrollValue) and dragKnob == "width" .. id) then
            valueName = (linkWidth * 100) .. "%"
        end
        
    end
    
    if id and useNarrow and ((dragKnob == "baseline" .. id and (isMouseDown or isScrollValue))) then -- or ((isAnyMouseDown or isScrollValue) and dragKnob == "width" .. id)) then
        showName = valueName
    end
    
    local sliderMinY = minY + 15
    local sliderMaxY = sliderMinY + sliderHeight
    
    
    
    if showMappingText then
        if settings.useKnobs and settings.showSeperationLineBeforeMappingName then
            reaper.ImGui_DrawList_AddLine(draw_list, minX+2, maxY- 13, maxX-2,maxY-13, padColor & 0xFFFFFF33, 1)     
        end
        reaper.ImGui_PushFont(ctx, font11)
        
        ImGui.PushClipRect(ctx, minX, minY, maxX + ((useNarrow and not useKnobs) and 0 or spaceTaken), maxY, true) 
        local textW = reaper.ImGui_CalcTextSize(ctx, showMappingText)
        local buttonPosX = minX + 3 
        if useNarrow or (maxX - minX) + spaceTaken < textW then
            if widthAvailable - 8 > textW then
                buttonPosX = centerOfWidget - textW / 2
            else
                buttonPosX = minX + 3
            end 
        elseif settings.alignModulatorMappingNameRight then
            buttonPosX = maxX + spaceTaken - textW - 3
        end
        local buttonPosY = minY + sliderHeight + 1 + 15
        if useNarrow and useKnobs then
            buttonPosY = buttonPosY + 16
        end
        reaper.ImGui_DrawList_AddText(draw_list, buttonPosX, buttonPosY, padColor, showMappingText) 
        ImGui.PopClipRect(ctx)
        reaper.ImGui_PopFont(ctx)
        
    end
    
    minX = minX +3
    maxX = maxX -2
    minY = minY +1
    maxY = maxY -2
    local sliderWidthAvailable = (maxX - minX)
    
    local dif = (sliderHeight - settings.heightOfSliderBackground) / 2
    local sliderBgMinY = sliderMinY + dif
    local sliderBgMaxY = sliderMaxY - dif
    local sliderGrabWidthAvailable = sliderWidthAvailable - settings.thicknessOfBigValueSlider
    local sliderGrabOffsetX = minX + settings.thicknessOfBigValueSlider / 2
    
    local valTextPosMax = minX + sliderWidthAvailable
    
    if parameterLinkActive then
        colorLeft = ((linkWidth <= 0 and offset < 0) or offset == -1) and settings.colors.sliderWidth or settings.colors.sliderWidthNegative
        colorRight = linkWidth <= 0 and offset < 0  and settings.colors.sliderWidthNegative or settings.colors.sliderWidth
        if not parameterModulationActive then
            colorLeft = colorLeft & 0xFFFFFF55
            colorRight = colorRight & 0xFFFFFF55
        end
    end
    
    if not useKnobs then
        -- slider background
        local sliderBg = isHovered and settings.colors.sliderBackgroundHover or settings.colors.sliderBackground
        reaper.ImGui_DrawList_AddRectFilled(draw_list, minX, sliderBgMinY, maxX, sliderBgMaxY, sliderBg, 4) 
        
        local posX = getPosXForLine(sliderGrabOffsetX, sliderGrabWidthAvailable, currentValue, sliderFlags, min, max)
        local sliderCenterGrabPosX = getPosXForLine(minX + 1, sliderWidthAvailable - 2, currentValue, sliderFlags, min, max)
        local sliderCenterPosX = getPosXForLine(minX, sliderWidthAvailable, currentValue, sliderFlags, min, max)
        
        if parameterLinkActive and offset and linkWidth and baseline then  
            local widthColor = linkWidth >= 0 and settings.colors.sliderWidth or settings.colors.sliderWidthNegative
            local initialValue = baseline + (offset * linkWidth) + (linkWidth < 0 and linkWidth or 0)  -- (direction == -1 and - math.abs(linkWidth) or (direction == 0 and - math.abs(linkWidth)/2 or 0))
            
            local posX1 = getPosXForLineNormalized(minX, sliderWidthAvailable, initialValue)
            local posX2 = getPosXForLineNormalized(minX, sliderWidthAvailable, initialValue + math.abs(linkWidth)) --getPosXForLine(posXOffset, sliderWidthAvailable, initialValue + linkWidthAsValue, sliderFlags, min, max)
            posX1 = posX1 < minX and minX or posX1
            posX2 = posX2 > maxX and maxX or posX2
            
            if sliderCenterPosX > minX then
                -- left width 
                reaper.ImGui_DrawList_AddRectFilled(draw_list, posX1, sliderBgMinY, sliderCenterPosX, sliderBgMaxY, colorLeft,4, reaper.ImGui_DrawFlags_RoundCornersLeft())
            end
             
            if sliderCenterPosX < maxX  then
                -- right width
                reaper.ImGui_DrawList_AddRectFilled(draw_list, sliderCenterPosX, sliderBgMinY, posX2, sliderBgMaxY, colorRight,4, reaper.ImGui_DrawFlags_RoundCornersRight())
            end
             
            local playingPosX = getPosXForLine(sliderGrabOffsetX, sliderGrabWidthAvailable, linkValue, sliderFlags, min, max)
            
            if settings.bigSliderMoving then
                reaper.ImGui_DrawList_AddRectFilled(draw_list, sliderCenterGrabPosX - settings.thicknessOfSmallValueSlider / 2, sliderBgMinY, sliderCenterGrabPosX + settings.thicknessOfSmallValueSlider / 2, sliderBgMaxY, settings.colors.sliderOutput, 4)
                reaper.ImGui_DrawList_AddRectFilled(draw_list, playingPosX - settings.thicknessOfBigValueSlider / 2, sliderMinY, playingPosX + settings.thicknessOfBigValueSlider / 2, sliderMaxY, settings.colors.sliderOutput, 4)
            else
                reaper.ImGui_DrawList_AddRectFilled(draw_list, sliderCenterGrabPosX - settings.thicknessOfBigValueSlider / 2, sliderMinY, sliderCenterGrabPosX + settings.thicknessOfBigValueSlider / 2, sliderMaxY, settings.colors.sliderOutput, 4)
                reaper.ImGui_DrawList_AddRectFilled(draw_list, playingPosX - settings.thicknessOfSmallValueSlider / 2, sliderBgMinY, playingPosX + settings.thicknessOfSmallValueSlider / 2, sliderBgMaxY, settings.colors.sliderOutput, 4) 
            end
        else 
            reaper.ImGui_DrawList_AddRectFilled(draw_list, posX - settings.thicknessOfBigValueSlider / 2, sliderMinY, posX + settings.thicknessOfBigValueSlider / 2, sliderMaxY, settings.colors.sliderOutput, 4)
        end
        
        
        
        local textW = reaper.ImGui_CalcTextSize(ctx, valueName, 0, 0)
        valTextPosMax = valTextPosMax - textW - 1
        -- value text
        
        if not useNarrow then
            reaper.ImGui_DrawList_AddText(draw_list, valTextPosMax, minY, valueColor, valueName)
        end
        valTextPosMax = valTextPosMax - 4
    else 
        local size = 26
        local outerCircleSize = 4
        local thicknessOfBigValueKnob = settings.thicknessOfBigValueKnob
        local sliderBackground = settings.colors.sliderBackground
        
        
        local x = (useNarrow or settings.alignParameterKnobToTheRight) and maxX - size or minX 
        local y = minY + 2
        
        if useNarrow then
            if spaceTaken == 0 or widthAvailableWithSpaceTaken / 2 + size / 2 < widthAvailable then
                x = centerOfWidget - size / 2
            else
                x = minX + widthAvailable / 2 - size / 2
                --moveTextToTheLeft = true
            end
            y = y + 14
        end
        
        
        local wetKnob = false
        if (specialSetting and specialSetting == "WetKnob") then
            size = 16
            thicknessOfBigValueKnob = 1
            outerCircleSize = 2
            wetKnobBackground = settings.colors.sliderAreaBackground & (isHovered and 0xFFFFFFBB or 0xFFFFFFFF)
            isHovered = false
            x = minX - 1
            y = y - 1
            --sliderBackground = settings.colors.sliderAreaBackground
            wetKnob = true
        end
        
        
        --local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx) 
        
        local center_x = x + size / 2
        local center_y = y + size / 2
        local radius = size / 2 * 1 - (4 - outerCircleSize) --* (outerCircleColor and 1 or 0.8) -- Scale down a bit for aesthetic reasons
        
        -- Map 'amount' from [0, 1] to [-135, 135] degrees
        local startPosAngle = - 230 --246
        local maxAngel = 282
        local angle = (startPosAngle + currentValue * maxAngel) * (math.pi / 180)
        local leftAngle = startPosAngle * (math.pi / 180)
        local centerAngle = (startPosAngle + (0.5) * maxAngel) * (math.pi / 180)
        local rightAngle = (startPosAngle + (1) * maxAngel) * (math.pi / 180)
         
        -- Calculate end point (p2_x, p2_y)
        local p2_x = center_x + math.cos(angle) * radius
        local p2_y = center_y + math.sin(angle) * radius
        
        -- draw shade of background
        
        if wetKnob then
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, size / 2, settings.colors.sliderAreaBackground) 
        end
        
        reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, size / 4, sliderBackground & 0xFFFFFF55) 
        
        local sliderBg = isHovered and settings.colors.sliderBackgroundHover or sliderBackground
        reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, leftAngle, rightAngle)
        reaper.ImGui_DrawList_PathStroke(draw_list, sliderBg, reaper.ImGui_DrawFlags_None(), outerCircleSize) 
        
        
        if parameterLinkActive and baseline and offset and linkWidth then  
            local playingPosAngle = (startPosAngle + linkValue * maxAngel) * (math.pi / 180)
            local playingPosAngle1 = (startPosAngle + (linkValue - (settings.thicknessOfSmallValueKnob / 100)) * maxAngel) * (math.pi / 180)
            local playingPosAngle2 = (startPosAngle + (linkValue + (settings.thicknessOfSmallValueKnob / 100))* maxAngel) * (math.pi / 180)
            local modMinValue = baseline + (offset * linkWidth) + (linkWidth < 0 and linkWidth or 0)
            local modMaxValue = modMinValue + math.abs(linkWidth)
            modMinValue = modMinValue < 0 and 0 or modMinValue
            modMaxValue = modMaxValue > 1 and 1 or modMaxValue
            local leftModAngle = (startPosAngle + (modMinValue - 0.01) * maxAngel) * (math.pi / 180)
            local rightModAngle = (startPosAngle + (modMaxValue + 0.01) * maxAngel) * (math.pi / 180) 
            
            local centerAngle = (startPosAngle + (currentValue) * maxAngel) * (math.pi / 180)
            local centerAngle1 = (startPosAngle + (currentValue - (settings.thicknessOfSmallValueKnob / 100)) * maxAngel) * (math.pi / 180)
            local centerAngle2 = (startPosAngle + (currentValue + (settings.thicknessOfSmallValueKnob / 100)) * maxAngel) * (math.pi / 180)
        
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, leftModAngle, centerAngle)
            reaper.ImGui_DrawList_PathStroke(draw_list, colorLeft, reaper.ImGui_DrawFlags_None(), outerCircleSize) 
            
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, centerAngle, rightModAngle)
            reaper.ImGui_DrawList_PathStroke(draw_list, colorRight, reaper.ImGui_DrawFlags_None(), outerCircleSize) 
            
            reaper.ImGui_DrawList_PathArcTo(draw_list, center_x , center_y, size / 2 - 2, settings.bigSliderMoving and centerAngle1 or playingPosAngle1, settings.bigSliderMoving and centerAngle2 or playingPosAngle2)
            reaper.ImGui_DrawList_PathStroke(draw_list, settings.colors.sliderOutput, reaper.ImGui_DrawFlags_None(), outerCircleSize) 
            
            
            local p2_x = center_x + math.cos(settings.bigSliderMoving and playingPosAngle or centerAngle) * radius * 0.7
            local p2_y = center_y + math.sin(settings.bigSliderMoving and playingPosAngle or centerAngle) * radius * 0.7
            reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, settings.colors.sliderOutput, thicknessOfBigValueKnob)
        else
            reaper.ImGui_DrawList_AddLine(draw_list, center_x, center_y, p2_x, p2_y, settings.colors.sliderOutput, thicknessOfBigValueKnob)
        end
        
        
        valTextPosMax = (useNarrow or settings.alignParameterKnobToTheRight) and valTextPosMax - size - 3 or maxX
        
        minX = (useNarrow or settings.alignParameterKnobToTheRight) and minX or minX + size + 4
        
        if not useNarrow then
            ImGui.PushClipRect(ctx, minX, minY, valTextPosMax, minY+32, true)
            reaper.ImGui_DrawList_AddText(draw_list, minX, sliderMinY, valueColor, valueName)
            ImGui.PopClipRect(ctx)  
        end
    end
    
    -- clip param text if needed
    local textWidth = reaper.ImGui_CalcTextSize(ctx, showName, 0,0)
    local textPosX = (useNarrow and (modulatorMappingNextToTitle and widthAvailable or widthAvailableWithSpaceTaken) - 8 > textWidth and not moveTextToTheLeft) and centerOfWidget - textWidth / 2 or minX
    
    if not useNarrow then
        ImGui.PushClipRect(ctx, minX, minY, valTextPosMax, minY+32, true)
    else 
        ImGui.PushClipRect(ctx, minX, minY, maxX + (modulatorMappingNextToTitle and 0 or spaceTaken), minY+32, true)
    end
    
    
    reaper.ImGui_DrawList_AddText(draw_list, textPosX, minY, valueColor, showName)
    ImGui.PopClipRect(ctx) 
    
    
    
    return sliderWidthAvailable
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
        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset',  -0.5)
    elseif p.direction == 1 then
        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset',  p.width < 0 and 0 or -1)
    else 
        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset',  p.width < 0 and -1 or 0)
    end 
end
    
    --[[
function envelopeHasPointAtTime(envelope, target_time, time_tolerance)
  local point_count = reaper.CountEnvelopePoints(envelope)
  for i = 0, point_count - 1 do
    local retval, time = reaper.GetEnvelopePoint(envelope, i)
    if retval and math.abs(time - target_time) <= time_tolerance then
      return i -- Found a point close enough
    end
  end
  return false
end]]

function setEnvelopePointAdvanced(track, p, amount)
    local playState = reaper.GetPlayState()
    local stopped = playState == 0 
    if p.singleEnvelopePointAtStart and (isAutomationRead or stopped) then--or isAutomationRead then
        reaper.SetEnvelopePoint(p.envelope,0, 0, amount, nil,nil,nil)
    elseif not isAutomationRead then
        SetParam(track, p.fxIndex, p.param, amount)
        --
        return GetParam(track, p.fxIndex, p.param)
    end
    
    
    -- this seems not necisarry as it's handled by reaper through write types
    --[[
    if lol and geezz then
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
    ]]
end

function setParameterFromFxWindowParameterSlide(track, p)
    if track then
        if p.usesEnvelope then
            if p.parameterLinkActive then
                momentarilyDisabledParameterLink = true --p.parameterModulationActive
                SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.active', "0")
            end
            setEnvelopePointAdvanced(track, p, p.value)
        elseif p.parameterLinkActive then 
            if not momentarilyDisabledParameterLink then
                momentarilyDisabledParameterLink = p.parameterModulationActive
            end
            SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.active', "0")
            SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline', p.value) 
            --SetParam(track, p.fxIndex, p.param, p.value)
        else 
            SetParam(track, p.fxIndex, p.param, p.value)
        end
    end
end

function setParamAdvanced(track, p, amount)
    
    ignoreFocusBecauseOfUiClick = true
    ignoreThisIndex = p.fxIndex
    ignoreThisParameter = p.param
    
    if p.param and p.param > -1 then 
        updateVisibleEnvelopes(track, p)
        if p.usesEnvelope and automation ~= 5 then  
            return setEnvelopePointAdvanced(track, p, amount)
        elseif p.parameterLinkEffect and p.parameterModulationActive then
            SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline', amount ) 
            local newVal = tonumber(select(2, GetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.baseline', true) ))
            return newVal  
        else  
            SetParam(track, p.fxIndex, p.param, amount)
            return GetParam(track, p.fxIndex, p.param)
        end
        
    end 
end

function setParameterValuesViaMouse(track, buttonId, moduleId, p, range, min, currentValue, faderResolution, resetValue, native, sliderFlags, useKnobs) 
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
            local scrollVal = settings.scrollValueInverted and -scrollVertical or scrollVertical
            amount = p.width - ((scrollVal * ((settings.scrollValueSpeed+50)/100)) / grains) --* (scrollVal > 0 and 1 or -1)
        else
            --dragKnob = nil
        end
        if amount and amount ~= p.width then  
            if amount < minWidth then amount = minWidth end
            if amount > 1 then amount = 1 end 
            
            if not settings.mappingModeBipolar then
                if amount < 0 then 
                    if p.direction == -1 and linkOffset ~= 0 then 
                        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', 0 )
                    elseif p.direction == 1 and linkOffset ~= -1 then 
                        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', -1 )
                    end
                elseif amount >= 0 then
                    if p.direction == -1 and linkOffset ~= -1 then 
                        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', -1 )
                    elseif p.direction == 1 and linkOffset ~= 0 then 
                        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.offset', 0 )
                    end 
                end
            end
            
            
            SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param..'.plink.scale', amount )
            --reaper.ImGui_SetTooltip(ctx, parameterLinkName .. " width:\n" .. linkWidth * 100 .. "%")
        end
        
        ignoreScrollHorizontal = true
    end
    
    
    
    if p.parameterLinkActive then 
        if dragKnob and dragKnob == "width" .. buttonId .. moduleId then
            setWidthValue(track, p, linkWidth)
        end
    end 
    
    
    if dragKnob and dragKnob == "baseline" .. buttonId .. moduleId then
        if wasMouseClickedAndNowReleasedAtSamePoint then
            mouse_pos_x_on_click = nil
            mouse_pos_y_on_click = nil
        end
        if wasMouseClickedAndNowReleasedAtSamePoint then 
            if not native then
                if isChangeBipolar then
                    if settings.mappingModeBipolar then
                        toggleBipolar(track, p.fxIndex, p.param, p.bipolar)
                    else
                        changeDirection(track, p)
                    end
                elseif isFlipWidth then
                    flipWidthValue(track, p.fxIndex, p.param)  
                elseif isRemoveMapping then 
                    if p.isCurver then
                        removeCurveForMapping(track, p)
                    else
                        disableParameterLink(track, p.fxIndex, p.param)
                    end
                elseif isOpenCurve then
                    openCloseFx(track, p.parameterLinkFXIndexForCurve)
                elseif isBypassMapping then
                    toggleeModulatorAndSetBaselineAcordingly(track, p.fxIndex, p.param, not p.parameterModulationActive)
                end
            end 
            
            if isResetValue then
                if native then
                    resetNativeParameterValue(track, resetValue, p)
                else
                    resetParameterValue(track, p.fxIndex, p.param, resetValue, p) 
                end
            elseif isSetParameterValue then
            end
        elseif not native and ((isAdjustWidth and not mapActiveFxIndex) or (not isAdjustWidth and mapActiveFxIndex and (mapActiveFxIndex ~= p.fxIndex or mapActiveParam ~= p.param))) then -- and (mapActiveParam ~= p.param))) then 
            setWidthValue(track, p, linkWidth)
        else 
            local amount
            local changeResolution = isFineAdjust and faderResolution * settings.fineAdjustAmount or faderResolution
            local useStepsChange = settings.makeItEasierToChangeParametersThatHasSteps and p.hasSteps and range / p.step < settings.maxAmountOfStepsForStepSlider
            if isMouseDown then 
                if useKnobs then 
                    mouseDragWidth = ((settings.changeKnobValueOnHorizontalDrag and (mouse_pos_x - mouseDragStartX) or 0) - (settings.changeKnobValueOnVerticalDrag and mouse_pos_y - mouseDragStartY or 0) * (isApple and -1 or 1))
                else
                    mouseDragWidth = (settings.changeSliderValueOnHorizontalDrag and mouse_pos_x - mouseDragStartX or 0) - ((dragKnob:match("Window") ~= nil or settings.changeSliderValueOnVerticalDrag) and (mouse_pos_y - mouseDragStartY) * (isApple and -1 or 1) or 0)
                    --mouseDragWidth = (mouse_pos_x - mouseDragStartX) - ((dragKnob:match("Window") ~= nil or settings.allowSliderVerticalDrag) and (mouse_pos_y - mouseDragStartY) * (isApple and -1 or 1) or 0)
                end
                
                if useStepsChange then
                    if math.abs(mouseDragWidth) > settings.movementNeededToChangeStep * (isFineAdjust and 3 or 0) then
                        amount = currentValueNormalized + (p.step / range) * (mouseDragWidth > 0 and 1 or -1) 
                        mouseDragStartX = mouse_pos_x
                        mouseDragStartY = mouse_pos_y
                    end
                else
                    if sliderFlags then
                        local curve = 0.8
                        local valueNormalized = getLogPosition(currentValue, p.min, p.max, curve)
                        local changeRelative = (mouseDragWidth / changeResolution)-- * 4) / sliderWidthAvailable
                        local newVal = valueNormalized + changeRelative
                        local amountNoNormalized = scaleLog(newVal, p.min, p.max, curve)
                        amount = (amountNoNormalized - min) / range
                    else 
                        amount = currentValueNormalized + mouseDragWidth / changeResolution
                    end 
                    mouseDragStartX = mouse_pos_x
                    mouseDragStartY = mouse_pos_y
                end
                
            elseif isScrollValue and scrollVertical and scrollVertical ~= 0 then
                local scrollVal = settings.scrollValueInverted and -scrollVertical or scrollVertical
                
                -- fix for lfo speed being inverted. Could be done some where else maybe
                if native and p.paramName == "lfo.speed" then
                    scrollVal = -scrollVal
                end
                if p.hasSteps and (range / p.step < 100 or isFineAdjust) then 
                    local scrollAmount = (math.floor(math.abs(scrollVertical) + 0.5) * (scrollVal > 0 and 1 or -1))
                    amount = ((currentValueNormalized - (p.step / range) * scrollAmount))-- * range) % p.step--
                else
                    if sliderFlags then
                        local changeAmount = ((scrollVal * ((settings.scrollValueSpeed+50)/100)) / changeResolution) * 100
                        local changeRelative = (changeAmount / changeResolution)-- * 4) / sliderWidthAvailable
                        local curve = 0.8
                        local valueNormalized = getLogPosition(currentValue, p.min, p.max, curve)
                        local newVal = valueNormalized + changeRelative
                        local amountNoNormalized = scaleLog(newVal, p.min, p.max, curve)
                        amount = (amountNoNormalized - min) / range
                    else 
                        amount = currentValueNormalized - ((scrollVal * ((settings.scrollValueSpeed+50)/100)) / changeResolution)
                    end
                end
                if amount then 
                    scrollTime = time
                end
            else
                --dragKnob = nil
                -- TRIED DISABLING THESE, SO SCROLL ALSO WORKS WITH FINE VALUES
                --missingOffset = nil
                --lastAmount = nil
            end
            if amount then 
            lastDragFxIndex = p.fxIndex
            lastDragParam = p.param
                if amount < 0 then amount = 0 end
                if amount > 1 then amount = 1 end 
                if amount ~= currentValueNormalized then  
                    local addOffset = useStepsChange and 0 or (missingOffset and missingOffset or 0) -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference
                    local newVal = (amount + addOffset) * range + min
                    if native then 
                        SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.paramOut..'.' .. p.paramName, newVal)
                    else
                        newAmount = setParamAdvanced(track, p, newVal)
                    end
                    if sliderFlags then
                        newAmount = newVal 
                    end
                         
                    -- SEEMS REDUDANT FOR NOW
                    -- these deals with moving the mouse but the parameter does not change, so we store them and add the difference to the next time
                    if not useStepsChange then
                        if lastAmount and lastAmount == amount then
                            local newAmountRelative = newAmount and (newAmount - min) / range or 0
                            missingOffset = amount - newAmountRelative + (missingOffset and missingOffset or 0)
                        else
                        --reaper.ShowConsoleMsg(tostring(lastAmount) .. " == " .. amount .. "reset\n")
                            missingOffset = 0
                        end
                        lastAmount = amount
                    end
                    
                    -----
                end
            end
            
            ignoreScrollHorizontal = true
        end
    end 
    
    if isMouseWasReleased and lastDragKnob or (scrollTime and time - scrollTime > settings.scrollTimeRelease / 1000) then
        -- tried putting them here
        missingOffset = nil
        lastAmount = nil
        --dragKnob = nil
        
        if p.usesEnvelope and undoStarted then
            --SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param ..'.plink.active',1 )
            reaper.Undo_EndBlock("Inserting envelope points", 0)
            undoStarted = false
        end
        
        if lastDragFxIndex and lastDragParam then
            reaper.TrackFX_EndParamEdit(track,  lastDragFxIndex, lastDragParam)
        end 
        lastDragFxIndex = nil
        lastDragParam = nil
        lastDragKnob = nil
        scrollTime = nil
    end

    
    if isMouseDown and dragKnob and dragKnob ~= lastDragKnob and dragKnob:match("Window") == nil then 
        lastDragKnob = dragKnob
        -- we reset values whenever we focus a new area
        missingOffset = nil
        lastAmount = nil
        dragKnob = nil
        if p.usesEnvelope then
            reaper.Undo_BeginBlock() 
            
            --SetNamedConfigParm( track, p.fxIndex, 'param.'.. p.param ..'.plink.active',0 )
            undoStarted = true
        end
    end
    
    -- TODO: Not sure about this, it's a quick fix
    if isMouseReleased then
        --dragKnob = nil
    end
    
end

function convertModifierOptionToString(option)
    -- 123
    local str = ""
    if option.Super then str = str .. "Super+" end
    if option.Ctrl then str = str .. "Ctrl+" end
    if option.Shift then str = str .. "Shift+" end
    if option.Alt then str = str .. "Alt+" end
    return str:sub(0,-2)
end

function pluginParameterSlider(moduleId, p, doNotSetFocus, excludeName, showingMappings, nameOnSide, width, resetValue, valueAsString, genericModulatorOutput, parametersWindow, formatString, useKnobs, useNarrow, visualIndex,parameterColumnAmount, specialSetting)
    local parameterLinkActive = p.parameterLinkActive
    --reaper.ShowConsoleMsg(p.fxName .. " - " .. p.name .. " - " .. tostring(parameterLinkActive) .. "\n")
    local parameterModulationActive = p.parameterModulationActive
    local hasLink = parameterLinkActive and parameterModulationActive
    
    
    if useKnobs == nil then useKnobs = settings.useKnobs end
    if useNarrow == nil then useNarrow = settings.useNarrow end
    
    
    local faderResolution = width --/ range
    if visualIndex then
        local parameterColumnAmount = parameterColumnAmount and parameterColumnAmount or settings.ModulatorParameterColumnAmount 
        width = findModulationParameterWidth(parameterColumnAmount, width)
        if visualIndex > 0 then
            samelineIfWithinColumnAmount(visualIndex, parameterColumnAmount, width)
        end
    end
    
    
    if width < 60 then
        useNarrow = true
    end
    -- 123
    local valueName = p.valueName or ""
    if valueAsString and valueAsString ~= "" then 
        valueName = valueAsString
    elseif formatString and tonumber(valueName) then
        valueName = string.format(formatString, tonumber(valueName))
    end
    
    if p.hasSteps and p.isToggle and tonumber(valueName) then
        valueName = p.valueNormalized == 0 and "Off" or "On"
    end
    
    if hasLink and settings.showBaselineInsteadOfModulatedValue and p.baseline then
        retStaticValueName, staticValueName = FormatParamValue( track, p.fxIndex, p.param, p.baseline )
        if retStaticValueName and staticValueName then
            valueName = staticValueName
        end
    end
    
    local name = p.name and p.name or "NA"
    local customSettings = (customPluginSettings and customPluginSettings[p.fxNameSimple]) and customPluginSettings[p.fxNameSimple][p.param]
    
    if (customSettings and customSettings.rename) and (customSettings.useRenameOnWide or (useNarrow and customSettings.useRenameOnNarrow)) then
        name = customSettings.rename
    end
    
    local hasEnvelope = p.hasEnvelopePoints
    local singleEnvelopePointAtStart = p.singleEnvelopePointAtStart
    local envelopeActive = p.envelopeActive 
    
    local envelopeAddName = (settings.showEnvelopeIndicationInName and hasEnvelope and not singleEnvelopePointAtStart) and (envelopeActive and "[E] " or "[e] ") or "" 
     
    local showName = envelopeAddName .. (type(nameOnSide) == "string" and nameOnSide or name)
    
    
    
    if not p or not p.fxIndex then return end
    
    ImGui.BeginGroup(ctx)  
    
    local min = p.min or 0
    local max = p.max or 1
    local divide = divide or 1
    local range = p.range -- max - min
    

    local parameterLinkEffect = p.parameterLinkEffect
    
    local linkValue = p.valueNormalized -- p.value 
    local linkOffset = p.offset
    local linkWidth = p.width or 1
    local fxIndex = p.fxIndex
    local param = p.param
    local parameterLinkName = p.parameterLinkName 
    
    local buttonId = fxIndex .. ":" .. param
    local id = buttonId .. moduleId
    
    width = (not width or width < 20) and 20 or width
    
    --local maxScrollBar = math.floor(reaper.ImGui_GetScrollMaxY(ctx))
    --local areaWidth = width + (maxScrollBar == 0 and 12 or - 2)
    --local faderWidth = areaWidth   -- nameOnSide and areaWidth / 2 or areaWidth
    local faderWidth = width
    local areaWidth = faderWidth
    
    local valueNormalized = p.valueNormalized
    local direction = p.direction
    
    
    local parStartPosX, parStartPosY, parEndPosX, parEndPosY
    
    local startPosX, startPosY = reaper.ImGui_GetCursorPos(ctx)
    
    -- we move elements slightly to make sure they are not covered by the line around
    --reaper.ImGui_SetCursorPos(ctx, startPosX + 1, startPosY)
    
    --local currentValue = p.usesEnvelope and p.envelopeValue or ((parameterLinkEffect and parameterModulationActive) and p.baseline or p.value) 
    --currentValue = currentValue or 0
    local currentValueNormalized = p.currentValueNormalized -- (p.currentValue - min) / range
    
    local baseline = currentValueNormalized--(p.baseline and p.baseline or currentValue ) / range
    
    local paramIsMappingParam = mapActiveFxIndex == p.fxIndex and mapActiveParam == p.param
    
    local paramIsMappedToModulator = mapActiveFxIndex and parameterLinkActive and mapActiveName == parameterLinkName
    
    -- this did not work
    --local paramIsModulationParam = mapActiveFxIndex == p.parameterLinkFxIndex and mapActiveParam == p.parameterLinkParam 
    
    local canBeMapped = mapActiveFxIndex and not paramIsMappingParam and (not parameterLinkActive or (not paramIsMappedToModulator )) 
    --local canBeMapped = mapActiveFxIndex and not paramIsMappingParam and (not parameterLinkActive or (parameterLinkActive and mapActiveFxIndex ~= p.parameterLinkFxIndex and mapActiveParam ~= p.parameterLinkParam )) 
    
    -- if we map from a generic modulator
    local isGenericOutput = param == genericModulatorOutput
    local mapOutput = genericModulatorOutput == -1
    -- we check if any overlay is active
    local overlayActive = canBeMapped or mapOutput or (hideParametersFromModulator == p.guid)
    
    
    local bgColor = isMapping and colorMapping or settings.colors.modulatorOutputBackground
    if settings.pulsateMappingButton and isMapping then 
        padColor = colorMappingPulsating
    end
    local mappedColorOnMappingParam = (not mapActiveFxIndex or not settings.pulsateMappingButtonsMapped or canBeMapped) and colorMapping or colorMappingPulsating
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
    
    
    
    function spaceForExtraButtons(canBeMapped, faderWidth)
        local spaceTaken = 0
        if parameterLinkActive or canBeMapped then
            if settings.showEnableAndBipolar and faderWidth - 12 > 30 then
                spaceTaken = spaceTaken + 12
            end 
            if settings.showWidthInParameters and faderWidth - spaceTaken - 23 > 30 then 
                spaceTaken = spaceTaken + 23
            end
        end
        return spaceTaken 
    end
    
    
    
    
    if overlayActive then reaper.ImGui_BeginDisabled(ctx) end
    
    --[[
    if showingMappings then
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
    ]]
    
    
    function formatNumber(value)
      if value == math.floor(value) then
        return string.format("%d", value) -- integer format
      else
        return tostring(value) -- or use string.format("%.1f", value) for 1 decimal place
      end
    end
    
    local showMappingText
    if settings.showMappedModulatorNameBelow and not showingMappings then
        if parameterLinkActive then
            if p.midiMsg then
                showMappingText = p.linkFromMidiText 
            else 
                showMappingText = p.parameterLinkName
                
                if p.isCurver and showMappingText then
                    showMappingText = "[C] ".. showMappingText
                end
            end
        elseif p.midiLearnText and settings.showMidiLearnIfNoParameterModulation then
            showMappingText = p.midiLearnText
            -- we make sure the pad color is brigt
            padColor = mappedColorOnMappingParam
        end
    end
    
    local totalSliderHeight = sliderHeight + 16
    if showMappingText and (not paramIsMappedToModulator and not p.isCurver) then
        totalSliderHeight = totalSliderHeight + 12
    end
    if useNarrow and useKnobs then
        totalSliderHeight = totalSliderHeight + 16
    end
    local spaceTaken = spaceForExtraButtons(canBeMapped, faderWidth)
    
    sliderStartPosX, sliderStartPosY = reaper.ImGui_GetCursorPos(ctx)
    -- we reduce the button size to make sure we do not get a horizontal scroll 
    sliderW = faderWidth - spaceTaken --8 -- 8
    if sliderW <= 10 then sliderW = 10 end
    
    if specialSetting and specialSetting == "WetKnob" then
        sliderW = 20
        totalSliderHeight = 20
        useNarrow = false
        useKnobs = true
        showName = nil
        showMappingText = nil
        reaper.ImGui_SetCursorPos(ctx, sliderStartPosX, sliderStartPosY)
    end
    
    local click = false
    if reaper.ImGui_InvisibleButton(ctx, "slider" .. buttonId .. moduleId, sliderW, totalSliderHeight) then
        click = true
    end
    
    local minX, minY = reaper.ImGui_GetItemRectMin(ctx) 
    local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
    
    
    local hover = false
    if reaper.ImGui_IsItemHovered(ctx) then
        hover = true
        if not dragKnob then 
            dragKnob = "baseline" .. buttonId .. moduleId
            mouseDragStartX = mouse_pos_x
            mouseDragStartY = mouse_pos_y
            if not isMouseDown and not anyModifierIsPressed then 
                local toolTip1 = "Drag to set " .. (parameterLinkActive and "baseline" or "value" ).. " of " .. name ..
                "\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameter.fineAdjust) .. " for fine resolution"
                toolTip1 = toolTip1 .. (showingMappings and "" or "\n - right click for more options")
                local toolTip2 = parameterLinkActive and "-- " .. parameterLinkName .. (p.isCurver and " [Curved]" or "") .. " --"
                local toolTip3 = parameterLinkActive and " - hold " .. convertModifierOptionToString(settings.modifierOptionsParameter.adjustWidth) .. " to change width" ..
                "\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameter.scrollValue) .. " and scroll to change value" 
                local toolTip4 = "-- Click --"
                local toolTip5 = resetValue and (" - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.resetValue) .. " to reset value\n") or ""
                if parameterLinkActive then 
                    toolTip5 = toolTip5 .. " - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.changeBipolar) .. " to change bipolar/direction" ..-- " .. (p.bipolar and "off" or "on")..
                    "\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.flipWidth) .. " to flip width" ..
                    "\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.bypassMapping) .. " to " .. (p.parameterModulationActive and "bypass" or "enable") .. " mapping" ..
                    (p.isCurver and 
                        ("\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.openCurve) .. " to " .. (p.isCurveOpen and "close" or "open") .. " curve") or "") ..
                        
                    --"\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.setParameterValue) .. " to set value with text input" ..
                    "\n - hold " .. convertModifierOptionToString(settings.modifierOptionsParameterClick.removeMapping) .. " to remove mapping"
                end
                
                
                setToolTipFunc3(toolTip1, toolTip2, toolTip3, toolTip4, toolTip5)
            end
        end
    end
    
    if showMappingText and (paramIsMappedToModulator or p.isCurver) then
        reaper.ImGui_SetCursorScreenPos(ctx, minX, maxY)
        
        if reaper.ImGui_InvisibleButton(ctx, "sliderOff" .. buttonId .. moduleId, sliderW + spaceTaken, 12) then
            if paramIsMappedToModulator then
                mapModulatorActivate(nil)
            else
                if isRemoveMapping then 
                    removeCurveForMapping(track, p)
                    mouse_pos_x_on_click = nil
                else
                    openCloseFx(track, p.parameterLinkFXIndexForCurve)
                end
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            showMappingText = paramIsMappedToModulator and "Stop mapping" or (isRemoveMapping and "Remove curve" or (GetOpen(track,p.parameterLinkFXIndexForCurve) and "Close curve" or "Open curve"))
           
        end
        
        maxY = maxY + 12 --+ 8 --
    end
    
    -- we add the missing size from above
    maxX = maxX --+ 8 --
    
    parStartPosX, parStartPosY = minX, minY
    
    local buttonW = maxX - minX 
    
    --if not nameOnSide and dontShowName then 
    reaper.ImGui_SameLine(ctx)
    sliderEndPosX, sliderEndPosY = reaper.ImGui_GetCursorPos(ctx)
    sliderEndPosX = sliderEndPosX --+ 8
    reaper.ImGui_NewLine(ctx)
    
    
    
    
    
    
    
    --[[
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
    ]]
    
    
    
    endPosX, endPosY = reaper.ImGui_GetCursorPos(ctx)
    parEndPosX = parStartPosX + buttonW + spaceTaken
    parEndPosY = parStartPosY + totalSliderHeight
    
    
    --local ret, newValue = reaper.ImGui_DragInt(ctx, visualName .. '##' .. buttonId, currentValue*divide, (max - min) / width, min, max, valueFormat, sliderFlags)
    
    
    
    local sliderVal = {endPosX = sliderEndPosX, endPosY = sliderEndPosY, startPosX = sliderStartPosX, startPosY = sliderStartPosY}
    sliderWidthAvailable = drawCustomSlider(showName, valueName, valueColor, padColor, currentValueNormalized, spaceTaken, minX, minY, maxX, maxY, sliderFlags, 0, 1,parameterLinkActive, parameterModulationActive, linkValue, linkWidth, baseline, linkOffset, dragKnob == "baseline" .. id, showMappingText, p, sliderVal, id, useKnobs, useNarrow, specialSetting)
    if not useKnobs then 
        faderResolution = sliderWidthAvailable --/ range
    end
    
    
    
    
    function focusParameterFromScript(moduleId, p)
        if moduleId:match("Floating") == nil and moduleId:match("modulator") == nil and moduleId:match("mappings") == nil then
            if not doNotSetFocus then
                paramnumber = p.param
                trackSettings.focusedParam[p.guid] = p.param
                saveTrackSettings(track)
                
                -- THIS DOESN*T WORK YET I THINK
                --if not showingMappings then
                --if moduleId:match("parameter") == nil then
                    --reaper.ShowConsoleMsg(moduleId .. "\n")
                --    ignoreScroll = true
                --    ignoreFocusBecauseOfUiClick = true
                --end
            end
        end
    end
    
    -- Check if the mouse is within the button area
    --if parStartPosX and mouse_pos_x_imgui >= parStartPosX and mouse_pos_x_imgui <= parStartPosX + areaWidth and
    --   mouse_pos_y_imgui >= parStartPosY and mouse_pos_y_imgui <= parEndPosY and 
       -- TODO: -36 is a hot fix as I do not get the height of the parameter panel correctly or something so the lower part did not react
    --   (not modulatorAreaHeight or modulatorAreaHeight >= mouse_pos_y_imgui - modulatorAreaY - 36) then
    if hover then
      if not popupAlreadyOpen and reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right(),false) then  --parameterLinkActive and 
          reaper.ImGui_OpenPopup(ctx, 'popup##' .. buttonId)  
          
          focusParameterFromScript(moduleId, p)
          --popupAlreadyOpen = true
      end
      
      if reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Left(),false) then 
          focusParameterFromScript(moduleId, p)
          --end
      end
    end
    
    
     --[[
      
      
      
      
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
    ]]
    
    
    if not popupOpen then popupOpen = {}; popupStartPos = {}; end
    popupOpen[buttonId] = reaper.ImGui_IsPopupOpen(ctx, 'popup##' .. buttonId)
    if popupOpen[buttonId] then 
        local movePopupToX, movePopupToY
        if settings.openMappingsPanelPos == "Right" then
            movePopupToX = parStartPosX + areaWidth + 2
            movePopupToY = parStartPosY - 100
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
        --popupWidth = nil
        --popupHeight = nil
        --popupStartPos[buttonId] = nil
    end
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTextDimmed)
    if reaper.ImGui_BeginPopup(ctx, 'popup##' .. buttonId) then
        
        reaper.ImGui_TextColored(ctx, colorTextDimmed, "Parameter context menu")
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), colorText)
        
        if parameterLinkActive then
            reaper.ImGui_BeginGroup(ctx) 
            
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
            if drawModulatorDirection(20, 20, p, track, fxIndex, param, buttonId, 0,0, not settings.mappingModeBipolar and colorText or (p.bipolar and colorText or colorTextDimmed)) then
                toggleBipolar(track, fxIndex, param, p.bipolar) 
            end
            
            reaper.ImGui_SameLine(ctx)
            local tip = p.isCurver and (p.parameterLinkCurverOpen and "Close curver" or "Open curver") .. "\nHold "..convertModifierOptionToString(settings.modifierOptionsParameterClick.removeMapping).. " to remove curver" or "Add curver"
            local btnColor = p.parameterLinkCurverOpen and settings.colors.pluginOpen or settings.colors.buttons
            if colorButton("Curve##" .. buttonId .. moduleId, colorText, btnColor, settings.colors.buttonsActive,settings.colors.buttonsHover,tip, colorText) then
            --if reaper.ImGui_Button(ctx, "Curve##" .. buttonId .. moduleId) then 
            
                if p.isCurver then
                    if isRemoveMapping then
                        removeCurveForMapping(track, p)
                    else
                        openCloseFx(track, p.parameterLinkFXIndexForCurve)
                    end
                else
                    insertCurveForMapping(track, p) 
                end
            
            end
            --reaper.ImGui_Spacing(ctx)
            
            if not showingMappings and (settings.parameterContextShowModulator or settings.parameterContextShowMappings) then
               -- reaper.ImGui_SameLine(ctx)
            end
            
            if not showingMappings then
                settings.parameterContextShowModulator = true
                local width = settings.modulatorsWidthContext
                showModulatorForParameter(p, width, 22, "parameterContext")
            end
            
            reaper.ImGui_EndGroup(ctx)
            
            if not showingMappings then
                reaper.ImGui_SameLine(ctx)
            end
        end
        
        
        reaper.ImGui_BeginGroup(ctx)
        
        if parameterLinkActive then
            --[[
            for i, dir in ipairs(directions) do
                if reaper.ImGui_RadioButton(ctx, dir, p.direction == - (i - 2)) then 
                    SetNamedConfigParm( track, fxIndex, 'param.'.. param..'.plink.offset',  linkWidth >= 0 and -(i - 1) / 2 or  (i - 3) / 2)
                end
            end
            ]]
            if not showingMappings then
                reaper.ImGui_NewLine(ctx)
            end
            
            local close = false
            if reaper.ImGui_Button(ctx,"Remove mapping##remove" .. buttonId) then
                disableParameterLink(track, fxIndex, param)
                doNotChangeOnlyMapped = true
                close = true
            end 
            
            local isModVisible = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.visible'))) == 1            
            local toggleText = isModVisible and "Hide" or "Show"
            if reaper.ImGui_Button(ctx,toggleText .. " parameter\nmodulation/link window##show" .. buttonId) then 
                SetNamedConfigParm( track, fxIndex, 'param.'..param..'.mod.visible', isModVisible and 0 or 1 )
                close = true
            end 
             
        end 
        
        
            
        fxIsShowing = GetOpen(track,fxIndex)
        fxIsFloating = GetFloatingWindow(track,fxIndex)
        local isShowing = (fxIsShowing or fxIsFloating) 
        
        local toggleName = (not isShowing and "Open " or "Close ")
        if buttonSelect(ctx, toggleName .. " FX##" .. name .. fxIndex, nil, isShowing, nil, 0, colorButtonsBorder, colorButtons, colorButtonsHover, colorButtonsActive, settings.colors.pluginOpen) then
            openCloseFx(track, fxIndex, not isShowing) 
            --close = true
        end
        
        
        reaper.ImGui_TextColored(ctx, colorTextDimmed, "Envelope lane")
        if not p.usesEnvelope then 
            if reaper.ImGui_Checkbox(ctx, "Visible", false) then 
                reaper.GetFXEnvelope(track, fxIndex, param, true) 
            end
        else
            local envelopeStates = getEnvelopeState(track, fxIndex, p.param) 
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
                if i < #types and i % 2 > 0 then reaper.ImGui_SameLine(ctx) end
                
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
        
        
        if reaper.ImGui_BeginMenu(ctx, (parameterLinkActive and "Replace modulation with new" or "Map with new modulator")) then
            local hadModulationContainerPosAlready = modulationContainerPos
            local click, modulationContainerPosTemp, insert_position = modulesPanel(ctx, true, "menu") 
            if click then  
            --  123
                local storeFocusedFXnumberGuid = GetFXGUID(track, fxnumber)
                modulationContainerPos = modulationContainerPosTemp
                if not hadModulationContainerPosAlready then fxIndex = fxIndex + 1 end
                modulatorNames, modulatorFxIndexes = getModulatorNames(track, modulationContainerPos, parameterLinks, true)
                for pos, m in ipairs(modulatorNames) do 
                    if insert_position == m.fxIndex then 
                        
                        mapModulatorActivate(m, m.output[1], m.name, nil, #m.output == 1)
                        local isLFO = mapActiveName:match("LFO") ~= nil
                        setParamaterToLastTouched(track, modulationContainerPos, insert_position, fxIndex, param, GetParam(track,fxIndex, param, true), (isLFO and (settings.defaultBipolarLFO and -0.5 or 0) or (settings.defaultBipolar and -0.5 or 0)), (isLFO and settings.defaultMappingWidthLFO or settings.defaultMappingWidth) / 100) 
                        if parameterLinkActive or settings.mapOnce then mapModulatorActivate(nil) end
                        reloadParameterLinkCatch = true
                        fxnumber = getFxIndexFromGuid(track, storeFocusedFXnumberGuid)
                        break;
                    end
                end  
                
                reaper.ImGui_CloseCurrentPopup(ctx)
                click = false
            end
            reaper.ImGui_EndMenu(ctx)
        end
        
        if modulationContainerPos then
            if reaper.ImGui_BeginMenu(ctx, (parameterLinkActive and "Replace modulation with existing" or "Map with existing modulator")) then
                for pos, m in ipairs(modulatorNames) do 
                    for _, out in ipairs(m.output) do 
                        if moduleButton(m.mappingNames[out]) then
                            --local storeFocusedFXnumberGuid = GetFXGUID(track, fxnumber)
                            --reaper.ShowConsoleMsg(m.name)
                            --reaper.ImGui_CloseCurrentPopup(ctx)
                            mapModulatorActivate(m, out, m.name, nil, #m.output == 1)
                            local isLFO = mapActiveName:match("LFO") ~= nil
                            setParamaterToLastTouched(track, modulationContainerPos, m.fxIndex, fxIndex, param, GetParam(track,fxIndex, param), (isLFO and (settings.defaultBipolarLFO and -0.5 or 0) or (settings.defaultBipolar and -0.5 or 0)), (isLFO and settings.defaultMappingWidthLFO or settings.defaultMappingWidth) / 100) 
                            mapModulatorActivate(nil) 
                            --fxnumber = getFxIndexFromGuid(track, storeFocusedFXnumberGuid)
                            break;
                        end
                    end
                end
                 
                reaper.ImGui_EndMenu(ctx)
            end
        end
        
        function drawLineAroundSelected(selected) 
            if selected then
                local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
                local maxX, maxY = reaper.ImGui_GetItemRectMax(ctx)
                reaper.ImGui_DrawList_AddRect(draw_list, minX, minY, maxX, maxY, colorButtonsActive, nil, nil, 2)
            end
        end
        
        
        function midiSelectMenu(msg1, msg2, midiLearn, midiBus, channel, omniChan)
            local midi_menu = {
              "Note On",
              "Note Off",
              "Poly Aftertouch",
              "Control Change (CC)",
              "Program Change",
              "Channel Aftertouch",
              "Pitchbend"
            }
            for m, menu in ipairs(midi_menu) do
                typeSelectedMsg = 0x70 + (msg1 and (msg1 & 0x0F) or (channel and channel or 0)) + m * 16 or false
                local typeIsSelected = typeSelectedMsg and typeSelectedMsg == tonumber(msg1)
                local menuName = menu
                if menu ~= "Pitchbend" and menu ~= "Program Change" and menu ~= "Channel Aftertouch" then
                    
                    if reaper.ImGui_BeginMenu(ctx, menuName .. "##midi learn select menu", true) then  
                        
                        for i = 0, 12 do
                            local amount = i < 12 and 9 or 7
                            local valSubIsSelected = (typeIsSelected and msg2) and (i * 10 <= msg2 and i * 10 + 9 >= msg2) or false
                            local subMenuName = (i * 10) .. " - " .. (i * 10 + amount) --(typeIsSelected and valSubIsSelected and ">> " or "") .. (i * 10) .. " - " .. (i * 10 + amount)
                            --if valSubIsSelected then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), colorButtonsActive) end
                            
                            if reaper.ImGui_BeginMenu(ctx, subMenuName, reaper.ImGui_ComboFlags_HeightSmall()) then  
                                for v = 0, amount do
                                    val = i * 10 + v
                                    local valIsSelected = typeIsSelected and msg2 == val
                                    if settings.showMidiNoteNames and (menu == "Note On" or menu == "Note Off" or menu == "Poly Aftertouch") then
                                        val = val .. " (" .. getNoteName(val, settings.midiNoteNamesMiddleC + 1) .. ")"
                                    end
                                    
                                    if reaper.ImGui_Selectable(ctx, val,valIsSelected, reaper.ImGui_SelectableFlags_DontClosePopups() ) then
                                        if midiLearn then
                                           SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi1', typeSelectedMsg)
                                           SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi2', val)
                                        else
                                            setModActive(track,fxIndex, param, true)
                                            setPlinkActive(track,fxIndex, param, true)
                                            --setPlinkOffset(track,fxIndex, param, 0)
                                            --setPlinkScale(track,fxIndex, param, 1)
                                            setPlinkEffect(track,fxIndex, param, -100)
                                            setPlinkMidiMsg(track, fxIndex, param, typeSelectedMsg & 0xF0)
                                            setPlinkMidiMsg2(track, fxIndex, param, val)
                                        end
                                    end 
                                end 
                                reaper.ImGui_EndMenu(ctx)
                            end
                            
                            drawLineAroundSelected(valSubIsSelected) 
                        end
                        
                        reaper.ImGui_EndMenu(ctx)
                    end
                    drawLineAroundSelected(typeIsSelected) 
                else
                    if reaper.ImGui_Selectable(ctx, menuName, typeIsSelected, reaper.ImGui_SelectableFlags_DontClosePopups()) then
                        if midiLearn then
                           SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi1', typeSelectedMsg)
                           SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi2', "0")
                        else
                            setModActive(track,fxIndex, param, true)
                            setPlinkActive(track,fxIndex, param, true)
                            --setPlinkOffset(track,fxIndex, param, 0)
                            --setPlinkScale(track,fxIndex, param, 1)
                            setPlinkEffect(track,fxIndex, param, -100)
                            setPlinkMidiMsg(track, fxIndex, param, typeSelectedMsg & 0xF0)
                            setPlinkMidiMsg2(track, fxIndex, param, 0)
                        end
                    end
                end
            end
            
            if reaper.ImGui_BeginMenu(ctx, "Channel" .. "##midi learn select menu") then  
                for i = 0, 16 do
                    if i == 0 then 
                        if not midiLearn then
                            if reaper.ImGui_Selectable(ctx,"Omni", omniChan, reaper.ImGui_SelectableFlags_DontClosePopups()) then 
                                --setPlinkEffect(track,fxIndex, param, -100)
                                setPlinkMidiChan(track, fxIndex, param, i)
                            end 
                        end
                    else
                        local isSelected = not omniChan and msg1 and (msg1 & 0x0F) == (i - 1)
                        local buttonName = i
                        if reaper.ImGui_Selectable(ctx, buttonName, isSelected, reaper.ImGui_SelectableFlags_DontClosePopups()) then
                            if midiLearn then
                                SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi1', (msg1 & 0xF0) + i - 1)
                            else
                                setPlinkMidiChan(track, fxIndex, param, i)
                            end
                        end
                    end
                end 
                reaper.ImGui_EndMenu(ctx)
            end
            
            if midiBus then
                if reaper.ImGui_BeginMenu(ctx, "Bus" .. "##midi learn select menu") then  
                    for i = 0, 15 do 
                        local isSelected = midiBus == i 
                        if reaper.ImGui_Selectable(ctx, i + 1, isSelected, reaper.ImGui_SelectableFlags_DontClosePopups()) then
                            setPlinkMidiBus(track, fxIndex, param, i) 
                        end
                    end 
                    reaper.ImGui_EndMenu(ctx)
                end
            end
        end 
        
        if track and fxIndex and param then
            local midiMsg = getPlinkMidiMsg(track, fxIndex, param)
            local midiMsg2 = getPlinkMidiMsg2(track, fxIndex, param)
            local midiBus = getPlinkMidiBus(track, fxIndex, param)
            local midiChan = getPlinkMidiChan(track, fxIndex, param)
            local omniChan = midiChan == 0
            midiChan = midiChan and midiChan > 0 and midiChan - 1 or 0
            local midiMsgWithChan = midiMsg and midiMsg + midiChan
            local linkFromMidiText 
            local hasMidiLink = getPlinkEffect(track, fxIndex, param) == -100 
            if hasMidiLink then
                if midiMsg2 < 128 then
                    linkFromMidiText = "Link to MIDI: " .. midi_status_to_text(midiMsgWithChan, midiMsg2, omniChan) 
                elseif midiMsg == 176 then
                    linkFromMidiText = "Link to MIDI: " .. (midiMsg2 - 128) .. "/" .. (midiMsg2 - 96) .. " 14-bit"
                end
                if midiBus > 0 then
                    linkFromMidiText = linkFromMidiText .. " (Bus " .. midiBus + 1 .. ")"
                end
            else
                
            end
            linkFromMidiText = "Link to MIDI"
            
            if reaper.ImGui_BeginMenu(ctx, linkFromMidiText) then
                midiSelectMenu(midiMsgWithChan, midiMsg2, false, midiBus, midiChan, omniChan)
                 
                reaper.ImGui_EndMenu(ctx)
            end
            drawLineAroundSelected(hasMidiLink) 
        end
        
        
        local function openMidiOSCWindowButton()
            if reaper.ImGui_Button(ctx, "Open MIDI/OSC learn window") then  
                --reaper.ImGui_CloseCurrentPopup(ctx)
                openSetMidiLearnForLastTouchedFXParameter = true
                
                --if fxIndex ~= fxnumber and param ~= paramnumber then  
                    SetParam(track,fxIndex,param, GetParam(track,fxIndex,param))
                --end
                
                reaper.Main_OnCommand(41144, 0) --FX: Set MIDI learn for last touched FX parameter
                
            end 
            setToolTipFunc("Learn a MIDI message or OSC string to control the parameter") 
        end
        
        
        if track and fxIndex and param then
            local learnMidi1 = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.midi1')))
            local learnMidi2 = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.midi2')))
            local learnOsc = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.osc')))
            local learnMode = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.mode')))
            local learnFlag = tonumber(select(2, GetNamedConfigParm( track, fxIndex, 'param.'..param..'.learn.flags')))
            
            local somethingIsLearned = learnFlag and ((learnMidi1 and learnMidi1 ~= 0) or learnOsc)
            if not somethingIsLearned then
                openMidiOSCWindowButton()
            else
                local midiLearnText
                if learnMidi1 then
                    midiLearnText = midi_status_to_text(learnMidi1, learnMidi2)
                elseif learnOsc then
                    midiLearnText = "OSC msg: ".. learnOsc
                end
                
                if reaper.ImGui_BeginMenu(ctx, "MIDI learn: ".. midiLearnText) then 
                    openMidiOSCWindowButton() 
                    
                    if reaper.ImGui_BeginMenu(ctx, midiLearnText) then 
                        midiSelectMenu(learnMidi1, learnMidi2, true)
                        
                        reaper.ImGui_EndMenu(ctx)
                    end
                    
                    if somethingIsLearned then
                        local learnModes = {"Absolute","127=-1,1=+1", "63=-1, 65=+1", "65=-1, 1=+1", "toggle if nonzero"}
                        local learnFlags = {"Selected track only", "Focused FX only", "Visible FX only", "Soft takeover"}
                        local learnFlagsVal = {1, 4, 16, 2}
                        
                        
                        
                        local learnModeSelected = learnModes[learnMode+1]
                        if reaper.ImGui_BeginCombo(ctx, "Mode##LearnMode", learnModeSelected) then
                            for i,v in ipairs(learnModes) do
                                local is_selected = learnMode+1 == i
                                if reaper.ImGui_Selectable(ctx, learnModes[i], is_selected) then
                                   SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.mode', i - 1)
                                end 
                            end
                            reaper.ImGui_EndCombo(ctx)
                        end
                        for i, lf in ipairs(learnFlags) do
                            local val = learnFlagsVal[i]
                            local isActive
                            local isSoftTakeover = (learnFlag & 2) ~= 0  -- true/false
                            if i < 4 then
                                isActive = (learnFlag & val) ~= 0  -- true/false
                            else
                                isActive = isSoftTakeover
                            end
                            
                            local changed, newValue = reaper.ImGui_Checkbox(ctx, lf, isActive)
                            if changed then 
                                if newValue then
                                    learnFlag = (i < 4 and (isSoftTakeover and 2 or 0) + val or  learnFlag | val) -- Set bit
                                else
                                    learnFlag = learnFlag & (~val) -- Clear bit
                                end
                                SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.flags', learnFlag)
                            end
                        end
                        
                        
                        if reaper.ImGui_Button(ctx, "Remove MIDI learn") then  
                            SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi1', "")
                            SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.midi2', "") 
                            SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.osc', "") 
                            SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.mode', "") 
                            SetNamedConfigParm(track, fxIndex, 'param.'..param..'.learn.flags', "") 
                        end 
                    end
                    
                    reaper.ImGui_EndMenu(ctx)
                end
            end
            
            if moduleId:match("Floating") ~= nil then
                if reaper.ImGui_BeginMenu(ctx, "Manually select touched parameter") then 
                    
                    local numParams = GetNumParams(track, fxIndex)
                    for p = 0, numParams - 1 - 3 do
                          name = GetParamName(track, fxIndex, p)
                          if reaper.ImGui_Selectable(ctx, name, p == param) then
                              parameterTouched = p
                          end
                    end
                    
                    reaper.ImGui_EndMenu(ctx)
                end
            end
            
            if customSettings.rename then
                if reaper.ImGui_BeginMenu(ctx, "Rename settings") then 
                    
                    if reaper.ImGui_Button(ctx, "Rename ".. '"' .. name.. '"') then
                        openRenameParam = true
                        renameParam = p -- we pass the object for most info
                    end
                    
                    -- use on narrow
                    local useOnNarrow = customPluginSettings[p.fxNameSimple][p.param].useRenameOnNarrow
                    local ret, newVal = reaper.ImGui_Checkbox(ctx, "Use on narrow", useOnNarrow)
                    if ret then
                        editPluginSetting("useRenameOnNarrow", p, newVal)
                    end
                    setToolTipFunc("Use rename on narrow sliders/knobs")
                    
                    local useOnWide = customPluginSettings[p.fxNameSimple][p.param].useRenameOnWide
                    local ret, newVal = reaper.ImGui_Checkbox(ctx, "Use on wide", useOnWide)
                    if ret then
                        editPluginSetting("useRenameOnWide", p, newVal)
                    end
                    setToolTipFunc("Use rename on wide sliders/knobs")
                    
                    if reaper.ImGui_Button(ctx, "Reset") then
                        editPluginSetting("rename", p, nil)
                    end
                    
                    reaper.ImGui_EndMenu(ctx)
                end
            else
            
                if reaper.ImGui_Button(ctx, "Rename ".. '"' .. name.. '"') then
                    openRenameParam = true
                    renameParam = p -- we pass the object for most info
                end
            end
            --[[
            if reaper.ImGui_Button(ctx, "Rename narrow " .. '"'.. name.. '"') then
                openRenameParam = true
                renameParamVersion = "nameNarrow"
                renameParam = p -- we pass the object for most info
            end
            ]]
            renameParamPopup()
            
        end
        
        
        reaper.ImGui_EndGroup(ctx)
        
        
        
        ImGui.EndPopup(ctx)
        --popupWidth, popupHeight = reaper.ImGui_GetItemRectSize(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx)
    
    
    
    local padW = 0
    local padH = 0
    if parameterLinkActive then 
        --reaper.ImGui_DrawList_AddRect(draw_list, parStartPosX - padW, parStartPosY - padH, parStartPosX + areaWidth + padW, parEndPosY  + padH, padColor,4,nil,1)
    end
    --
    
    
    
    setParameterValuesViaMouse(track, buttonId, moduleId, p, range, min, p.currentValue, faderResolution, resetValue, nil, nil, useKnobs)
    
    
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
        local overlayColor = borderColor & 0xFFFFFFFF33
        
        reaper.ImGui_InvisibleButton(ctx,  visualName .. "##map" .. buttonId,  areaWidth, endPosY - startPosY - 4)
        local mapToolTip
        if ImGui.IsItemClicked(ctx) then
            --paramnumber = param
            --ignoreScroll = true
            
            if (canBeMapped and not mapOutput) then
                local isLFO = mapActiveName:match("LFO") ~= nil
                local setWidth = (isLFO and settings.defaultMappingWidthLFO or settings.defaultMappingWidth) / 100
                local setOffset = (isLFO and (settings.mappingModeBipolar and (settings.defaultBipolarLFO and -0.5 or 0) or (settings.defaultLFODirection - 3)/2) or ((settings.mappingModeBipolar and settings.defaultBipolar and -0.5 or 0) or (settings.defaultDirection - 3) / 2))
                setParamaterToLastTouched(track, modulationContainerPos, mapActiveFxIndex, fxIndex, param, p.value, setOffset, setWidth)
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
            --ImGui.PushClipRect(ctx, parStartPosX, parStartPosY, parStartPosX + areaWidth, parEndPosY, true)
            --reaper.ImGui_DrawList_AddText(draw_list, posXOffset + areaWidth/2 - textW/2, parStartPosY+2, colorText, visualName)
        end --ImGui.PopClipRect(ctx) 
    end
    
    if stopMappingOnRelease and isMouseReleased then 
        mapActiveFxIndex = false; 
        mapActiveParam = false; 
        stopMappingOnRelease = nil 
    end
    
    if nameOnSide and parameterLinkActive then
        
        --reaper.ImGui_SetCursorPos(ctx, endPosX, endPosY)
        --reaper.ImGui_Spacing(ctx)
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
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorTransparent)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorTransparent)
    reaper.ImGui_Button(ctx,name, width,height)
    reaper.ImGui_PopStyleColor(ctx,3)
end

function mapButtonColor()
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),colorMappingLight)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),colorMapping)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),colorMapLight)
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




function openFxBrowserOnSpecificTrack()
    local index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local trackTitleIndex = "Track " .. math.floor(index)
    local ret, name = reaper.GetTrackName(track)
    local addFXToTrackWindowNameSimple = "Add FX to " .. trackTitleIndex
    local addFXToTrackWindowName = "Add FX to " .. trackTitleIndex .. (name == trackTitleIndex and "" or (' "' .. name .. '"'))
    reaper.SetOnlyTrackSelected(track, true)
    
    -- check if window is already open, if it is we start by closing it
    --local hwnd = reaper.JS_Window_Find(addFXToTrackWindowName, true) 
    --local visible = reaper.JS_Window_IsVisible(hwnd)   
    --if (hwnd and visible) then
    --    reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
    --end
    
    reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
    local browserHwnd, browserSearchFieldHwnd, title = findWindowParentWithName("FX Browser", addFXToTrackWindowName, addFXToTrackWindowNameSimple)
    
    if not browserHwnd then 
        reaper.Main_OnCommand(40271, 0) --View: Show FX browser window
        browserHwnd, browserSearchFieldHwnd, title = findWindowParentWithName("FX Browser", addFXToTrackWindowName, addFXToTrackWindowNameSimple)
    end
    
    --local isDocked = title == "FX Browser (docked)"
    
    return browserHwnd, browserSearchFieldHwnd, isDocked
end

function openCloseFx(track, fxIndex, open)  
    function closeParentContainerRecursive(track, fxIndex)
        if GetOpen(track,fxIndex) then
            local retval, parFxIndex = GetNamedConfigParm( track, fxIndex, "parent_container" )
            if retval and parFxIndex then 
                local fxIsFloating = GetFloatingWindow(track,tonumber(parFxIndex))
                if fxIsFloating then
                    SetOpen(track,tonumber(parFxIndex),false)
                else
                    closeParentContainerRecursive(track, tonumber(parFxIndex))
                end
            else 
                local fxIsFloating = GetFloatingWindow(track,fxIndex)
                if fxIsFloating then
                    SetOpen(track,fxIndex,false)
                else 
                    showFX(track,fxIndex,0)   
                end
            end 
        end
    end
    
    local fxIsFloating = GetFloatingWindow(track,fxIndex, true)
    
    if open == nil then
        SetOpen(track,fxIndex,not GetOpen(track,fxIndex))
    elseif open then 
        -- opens floating window
        SetOpen(track,fxIndex,open)
    else 
        if fxIsFloating then
            -- closes floating window
            SetOpen(track,fxIndex,false)
        else 
            -- check if window is in a container
            retval, parFxIndex = GetNamedConfigParm( track, fxIndex, "parent_container" )
            if retval and parFxIndex then
                -- if in container we try to close that one instead
                closeParentContainerRecursive(track, tonumber(parFxIndex))
            else
                -- else we close the window as we know it's the FX window
                showFX(track,fxIndex,0)   
            end
        end
    end
    
end




function scrollHoveredDropdown(currentValue, track,fxIndex,paramIndex, dropDownList, native, min, max)
    if reaper.ImGui_IsItemHovered(ctx) then
        if scrollVertical ~= 0 and isScrollValue then
            local newIndexValue = currentValue + (scrollVertical > 0 and -1 or 1) 
            newIndexValue = math.min(math.max(newIndexValue, min and min or 1), max and max or #dropDownList)
            local newScrollValue = dropDownList[1].value and dropDownList[newIndexValue].value or (newIndexValue)
            if native then
                SetNamedConfigParm( track, fxIndex, native, newScrollValue) 
            else
                SetParam( track, fxIndex, paramIndex, newScrollValue) 
            end
        end
    end
end

        




function placingOfNextElement(spacing)
    if settings.vertical then
        if not spacing then
            reaper.ImGui_Spacing(ctx)
        else
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) - 4 + spacing)
        end
        --reaper.ImGui_Separator(ctx)
        --reaper.ImGui_Spacing(ctx)
    else
        reaper.ImGui_SameLine(ctx)
        if spacing then
            reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) - 8 + spacing)
        end
    end
end

            
function drawConnectionToNextElement(vertical, width, height)
    local posX, posY = reaper.ImGui_GetCursorScreenPos(ctx)
    local posX1, posX2, posY1, posY2
    if vertical then
        reaper.ImGui_DrawList_AddLine(draw_list, posX, posY - 13, posX, posY + 5, settings.colors.modulesBorder & 0xFFFFFFBB)
        reaper.ImGui_DrawList_AddLine(draw_list, posX + width-1, posY - 13, posX + width - 1, posY + 5, settings.colors.modulesBorder & 0xFFFFFFBB)
    else
        reaper.ImGui_DrawList_AddLine(draw_list, posX-13, posY, posX + 5, posY, settings.colors.modulesBorder & 0xFFFFFFBB)
        reaper.ImGui_DrawList_AddLine(draw_list, posX-13, posY + height - 1, posX + 5, posY + height - 1, settings.colors.modulesBorder & 0xFFFFFFBB)
    end
end

function getCustomPluginSettings() 
    return get_files_in_folder(pluginsFolderName, true) 
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

function colorButton(title, textColor, buttonColor, activeColor, hoverColor, toolTipText, toolTipTextColor, sizeW)
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
    
    reaper.ImGui_Indent(ctx)
    local ret, val = reaper.ImGui_Checkbox(ctx,"Keep when clicking in app window##",settings.keepWhenClickingInAppWindow) 
    if ret then 
        settings.keepWhenClickingInAppWindow = val
        saveSettings()
    end
    setToolTipFunc("Do not hide when clicking the " .. appName .. " app") 
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"Keep when clicking in other FX window##",settings.keepWhenClickingInOtherFxWindow) 
    if ret then 
        settings.keepWhenClickingInOtherFxWindow = val
        saveSettings()
    end
    setToolTipFunc("Do not hide when clicking another FX window.\nThis will be practical when rearranging FX windows, but not wanting to hide the current focused parameter.")
    
    reaper.ImGui_Unindent(ctx)
    
    if sliderInMenu("Floating window width", "floatingMapperParameterWidth", menuSliderWidth, 140, 400, "Set the width of the parameter in the floating mapper window") then 
        --setWindowWidth = true
    end
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
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"Allow changing baseline of modulatated parameters on plugin UI##",settings.allowClickingParameterInFXWindowToChangeBaseline) 
    if ret then 
        settings.allowClickingParameterInFXWindowToChangeBaseline = val
        saveSettings()
    end
    setToolTipFunc("This will allow you to change the value of a parameter modulated value, by changing the value on the plugin ui.\nThis will momentarily bypass the modulator and enable it again on release.\nThis function works best with the Force Mapping turned on.") 
    
    
    --reaper.ImGui_EndGroup(ctx)
end

function envelopeSettings(popup)
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
         
        local ret, val = reaper.ImGui_Checkbox(ctx,"Hide envelopes if previous last touched##",settings.hideEnvelopesIfLastTouched) 
        if ret then 
            settings.hideEnvelopesIfLastTouched = val
            saveSettings()
        end
        setToolTipFunc("Hide the previous last touched envelope if it has no envelope points.\nThis mode is a bit experimental")  
         
        local ret, val = reaper.ImGui_Checkbox(ctx,"Hide envelopes with no points##",settings.hideEnvelopesWithNoPoints) 
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
    
    if popup then
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
    end
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

function layoutKnobsOrSliders(id)
    local isKnob = (settings["useKnobs" .. id] ~= nil and settings["useKnobs" .. id] == true or settings.useKnobs)
    local name = (isKnob and "Knobs" or "Sliders")
    
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_TextColored(ctx, colorGrey, "Layout") 
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_RadioButton(ctx, "Default##" .. id, settings["useKnobs" .. id] == nil) then
        settings["useKnobs" .. id] = nil
        saveSettings()
    end 
    reaper.ImGui_SameLine(ctx)
    
    setToolTipFunc("Use the default layout set in general") 
    
    if reaper.ImGui_RadioButton(ctx, "Slider##" .. id, settings["useKnobs" .. id] == false) then
        settings["useKnobs" .. id] = false
        saveSettings()
    end 
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_RadioButton(ctx, "Knobs##" .. id, settings["useKnobs" .. id] == true) then
        settings["useKnobs" .. id] = true
        saveSettings()
    end
    
    reaper.ImGui_SameLine(ctx)
    
    local ret, val = reaper.ImGui_Checkbox(ctx,"Narrow##" .. id,settings["useNarrow" .. id]) 
    if ret then 
        settings["useNarrow" .. id] = val
        saveSettings()
    end
    setToolTipFunc("Use narrow " .. name .. " layout when working with a compressed module width") 
    
    
    sliderInMenu(name .. " per row", id .."ParameterColumnAmount", menuSliderWidth, 1, 10, "Set how many " .. name .. " should be per row.")  
end

function appSettingsWindow() 
    local rv, open = reaper.ImGui_Begin(ctx, appName .. ' Settings', true, reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() ) 
    if not rv then return open end
    
    
    
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
        function set.General() 
            reaper.ImGui_BeginGroup(ctx)
            --reaper.ImGui_TextColored(ctx, colorGrey, "Panels/Modules")
            
            --if sliderInMenu("Panels width", "generalWidth", menuSliderWidth, 140, 800, "Set the max width of panels. ONLY in horizontal mode") then 
            --   setWindowWidth = true
            --end
            
            --sliderInMenu("Panels height", "modulesHeightVertically", menuSliderWidth, 80, 550, "Set the max height of panels. ONLY in vertical mode") 
            
            
            
            --reaper.ImGui_NewLine(ctx)
            
            
            --reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Track coloring")
            
            
            reaper.ImGui_Indent(ctx)
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
                
                sliderInMenu("Track color line size", "trackColorLineSize", menuSliderWidth, 1, 6, "Set the size of the color line")  
            reaper.ImGui_Unindent(ctx)
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Others")
            
            reaper.ImGui_Indent(ctx)
            
                local ret, val = reaper.ImGui_Checkbox(ctx,"Automation color on envelope button",settings.useAutomationColorOnEnvelopeButton) 
                if ret then 
                    settings.useAutomationColorOnEnvelopeButton = val
                    saveSettings()
                end
                setToolTipFunc("Show the automation color on the envelope button drawing. Set the background in color settings for better visibility") 
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Prefer horizontal headers",settings.preferHorizontalHeaders) 
                if ret then 
                    settings.preferHorizontalHeaders = val
                    saveSettings()
                end
                setToolTipFunc("For modulators and plugins use horizontal header when not collabsed even when panel is in horizontal mode")  
                  
                sliderInMenu("Width between widgets", "widthBetweenWidgets", menuSliderWidth, 1, 20, "Set the width between widgets") 
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show insert options when no track is selected",settings.showInsertOptionsWhenNoTrackIsSelected) 
                if ret then 
                    settings.showInsertOptionsWhenNoTrackIsSelected = val
                    saveSettings()
                end
                setToolTipFunc("When no track is selected show add fx, preset or template tables") 
                
            reaper.ImGui_Unindent(ctx)
            
            
            reaper.ImGui_EndGroup(ctx)
            
            reaper.ImGui_SameLine(ctx)
            
            reaper.ImGui_BeginGroup(ctx)
            
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "Parameter Layout")
            
            
            reaper.ImGui_Indent(ctx)
                 if reaper.ImGui_RadioButton(ctx, "Sliders##general", not settings.useKnobs) then
                    settings.useKnobs = false
                    saveSettings()
                end 
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_RadioButton(ctx, "Knobs##general", settings.useKnobs) then
                    settings.useKnobs = true
                    saveSettings()
                end
                
                
                reaper.ImGui_SameLine(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,"Narrow##general",settings.useNarrow) 
                if ret then 
                    settings.useNarrow = val
                    saveSettings()
                end
                setToolTipFunc("Use narrow knobs layout when working with compressed modules") 
                
                
                reaper.ImGui_Indent(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorTextDimmed, "Change on")
                    reaper.ImGui_SameLine(ctx)
                    local textSel = settings.useKnobs and "changeKnob" or "changeSlider"
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Vertical drag##general",settings[textSel .. "ValueOnVerticalDrag"]) 
                    if ret then 
                        if not val and not settings[textSel .. "ValueOnHorizontalDrag"] then 
                            settings[textSel .. "ValueOnHorizontalDrag"] = true
                        end
                        settings[textSel .. "ValueOnVerticalDrag"] = val
                        saveSettings()
                    end
                    setToolTipFunc("Change parameter value on vertical drags")   
                    reaper.ImGui_SameLine(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Horizontal drag##general",settings[textSel .. "ValueOnHorizontalDrag"]) 
                    if ret then 
                        if not val and not settings[textSel .. "ValueOnVerticalDrag"] then 
                            settings[textSel .. "ValueOnVerticalDrag"] = true
                        end
                        settings[textSel .. "ValueOnHorizontalDrag"] = val
                        saveSettings()
                    end
                    setToolTipFunc("Change parameter value on horizontal drags")  
                    
                    if not settings.useKnobs then 
                        --[[
                        local ret, val = reaper.ImGui_Checkbox(ctx,"Allow slider vertical drag##parameters",settings.allowSliderVerticalDrag) 
                        if ret then 
                            settings.allowSliderVerticalDrag = val
                            saveSettings()
                        end
                        setToolTipFunc("When enabled the value change when dragging will be a combination of vertical and horizontal mouse movement, like it is with knobs")  
                        ]]
                        sliderInMenu("Height of slider background", "heightOfSliderBackground", menuSliderWidth, 2, 14, "Set how thick the slider background should be") 
                        
                    else  
                        
                        
                        local ret, val = reaper.ImGui_Checkbox(ctx,"Have parameter knob to the right of parameter name and value##parameters",settings.alignParameterKnobToTheRight) 
                        if ret then 
                            settings.alignParameterKnobToTheRight = val
                            saveSettings()
                        end
                        setToolTipFunc("Show the parameter knob to the left or right of of the parameter name and value") 
                    end
                    
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show modulated value on big slider##parameters",settings.bigSliderMoving) 
                    if ret then 
                        settings.bigSliderMoving = val
                        saveSettings()
                    end
                    setToolTipFunc("Use knobs for parameters") 
                    if not settings.useKnobs then 
                        sliderInMenu("Size of big slider line", "thicknessOfBigValueSlider", menuSliderWidth, 1, 5, "Set how thick the big slider line should be") 
                        sliderInMenu("Size of small slider line", "thicknessOfSmallValueSlider", menuSliderWidth, 1, 5, "Set how thick the small slider line should be") 
                    else
                        sliderInMenu("Size of big knob line", "thicknessOfBigValueKnob", menuSliderWidth, 1, 5, "Set how thick the big knob line should be") 
                        sliderInMenu("Size of small knob line", "thicknessOfSmallValueKnob", menuSliderWidth, 1, 5, "Set how thick the small knob line should be")  
                    end
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show baseline value instead of modulated value##parameters",settings.showBaselineInsteadOfModulatedValue) 
                    if ret then 
                        settings.showBaselineInsteadOfModulatedValue = val
                        saveSettings()
                    end
                    setToolTipFunc("Show baseline value instead of modulated value on the slider.\nFYI!! This will only work FXs that support. Maybe there's a workaround that I can find later.") 
                    
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show value instead of name when changed##parameters",settings.showValueOnNamePos) 
                    if ret then 
                        settings.showValueOnNamePos = val
                        saveSettings()
                    end 
                    setToolTipFunc("If you have a very narrow parameter layout showing the value on the name position when changing the value, might be better") 
                    
                     
                     local ret, val = reaper.ImGui_Checkbox(ctx,"Show envelope indication in name##parameters",settings.showEnvelopeIndicationInName) 
                     if ret then 
                         settings.showEnvelopeIndicationInName = val
                         saveSettings()
                     end
                     setToolTipFunc("Show [E] in parameter name if the parameter is controlled by an envelope. If the envelope is not active [e] will be shown")  
                     
                     
                reaper.ImGui_Unindent(ctx)
                
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "Extra controls when mapped:")
                
                
                 
                reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show width knob##parameters",settings.showWidthInParameters) 
                    if ret then 
                        settings.showWidthInParameters = val
                        saveSettings()
                    end
                    setToolTipFunc("Show width knob on mapped parameters") 
                    
                    reaper.ImGui_Indent(ctx)
                        local ret, val = reaper.ImGui_Checkbox(ctx,"Show width value when being modified##parameters",settings.showWidthValueWhenChanging) 
                        if ret then 
                            settings.showWidthValueWhenChanging = val
                            saveSettings()
                        end
                        setToolTipFunc("Show width value instead of parameter value when changing the width value") 
                    reaper.ImGui_Unindent(ctx)
                        
                    
                        
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show enable/disable and bipolar buttons##parameters",settings.showEnableAndBipolar) 
                    if ret then 
                        settings.showEnableAndBipolar = val
                        saveSettings()
                    end
                    setToolTipFunc("Show enable/disable and bipolar buttons on mapped parameters") 
                    
                    
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show mapped modulator name below parameter##parameters",settings.showMappedModulatorNameBelow) 
                    if ret then 
                        settings.showMappedModulatorNameBelow = val
                        saveSettings()
                    end
                    setToolTipFunc("Show mapped modulator below the parameter that is mapped.\nThis will not be shown in the mappings windows.") 
                    
                    reaper.ImGui_Indent(ctx)
                        local ret, val = reaper.ImGui_Checkbox(ctx,"Show MIDI learn value##parameters",settings.showMidiLearnIfNoParameterModulation) 
                        if ret then 
                            settings.showMidiLearnIfNoParameterModulation = val
                            saveSettings()
                        end
                        setToolTipFunc("Show MIDI learn value if available and no parameter is mapped") 
                        
                        if settings.useKnobs then 
                            local ret, val = reaper.ImGui_Checkbox(ctx,"Show seperation line before modulator name##parameters",settings.showSeperationLineBeforeMappingName) 
                            if ret then 
                                settings.showSeperationLineBeforeMappingName = val
                                saveSettings()
                            end
                            setToolTipFunc("Show a small line before the modulator name text, to break up the ui a bit") 
                        end
                        
                        local ret, val = reaper.ImGui_Checkbox(ctx,"Align mapped modulator name to the right##parameters",settings.alignModulatorMappingNameRight) 
                        if ret then 
                            settings.alignModulatorMappingNameRight = val
                            saveSettings()
                        end
                        setToolTipFunc("Align mapped modulator name to the left or right") 
                
                    reaper.ImGui_Unindent(ctx)
                
                reaper.ImGui_Unindent(ctx)
                 
                --reaper.ImGui_NewLine(ctx)
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "Context popup options")
                
                reaper.ImGui_Indent(ctx)
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorTextDimmed, "Open")
                    
                    reaper.ImGui_SameLine(ctx)
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
                    reaper.ImGui_TextColored(ctx, colorTextDimmed, "of clicked mapping")
                    
                    
                    
                    --reaper.ImGui_NewLine(ctx)
                    
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show midi notes in menus##",settings.showMidiNoteNames) 
                    if ret then 
                        settings.showMidiNoteNames = val
                        saveSettings()
                    end
                    setToolTipFunc("Show MIDI notes in the right click parameter menu")  
                    
                    
                    reaper.ImGui_Indent(ctx)
                        reaper.ImGui_SetNextItemWidth(ctx, 100)
                        local ret, val = reaper.ImGui_Combo(ctx,"Middle C##", settings.midiNoteNamesMiddleC, table.concat(middle_c_offsetsStr, "\0") .. "\0")  
                        if ret then 
                            settings.midiNoteNamesMiddleC = val
                            saveSettings()
                        end
                        setToolTipFunc("Select which C should be the middle C, eg. value 60")  
                    reaper.ImGui_Unindent(ctx)
                    
                reaper.ImGui_Unindent(ctx)
            reaper.ImGui_Unindent(ctx)
            
            reaper.ImGui_EndGroup(ctx)
        end
        
        
        --reaper.ImGui_TableNextRow(ctx)
        --reaper.ImGui_TableNextColumn(ctx)
        function set.Plugins()
             
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show plugins panel##plugins",settings.showPluginsPanel) 
            if ret then 
                settings.showPluginsPanel = val
                saveSettings()
            end
            setToolTipFunc("Show or hide the plugins panel") 
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Make panel a fixed size##plugins",settings.pluginsPanelWidthFixedSize) 
            if ret then 
                settings.pluginsPanelWidthFixedSize = val
                saveSettings()
            end
            setToolTipFunc("Make the plugins panel a fixed size")  
            
            if settings.pluginsPanelWidthFixedSize then
                reaper.ImGui_Indent(ctx)
                sliderInMenu("Plugins panels width", "pluginsPanelWidth", menuSliderWidth, settings.pluginsWidth+settings.parametersWidth+16, 1600, "Set the fixed width of the plugins panel. ONLY used for horizontal and floating") 
                
                sliderInMenu("Plugins panels height", "pluginsPanelHeight", menuSliderWidth, settings.pluginsHeight+settings.parametersHeight+16, 1600, "Set the fixed height of the plugins panel. ONLY used for vertical and floating")   
                
                reaper.ImGui_Unindent(ctx)
            end
            
            
            reaper.ImGui_BeginGroup(ctx)
            
            reaper.ImGui_TextColored(ctx, colorGrey, "List view") 
            
                
            
            reaper.ImGui_Indent(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,'"Show list" setting is global##pluginList',settings.showPluginsListGlobal) 
                if ret then 
                    settings.showPluginsListGlobal = val
                    saveSettings()
                end
                setToolTipFunc("Enable this to make the last panel show setting global and not track based")  
                
                sliderInMenu("Plugins list width", "pluginsWidth", menuSliderWidth, 100, 400, "Set the max width of the parameters panel. ONLY used for horizontal and floating") 
                
                sliderInMenu("Plugins list height", "pluginsHeight", menuSliderWidth, 100, 800, "Set the max height of the parameters panel. ONLY used for vertical and floating")  
                
                
                reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Use fixed height for plugins panel",settings.alwaysUsePluginsHeight) 
                    if ret then 
                        settings.alwaysUsePluginsHeight = val
                        saveSettings()
                    end
                    setToolTipFunc("Enable this to keep the same size of the plugins panel all the time (Only in vertical mode).")  
                reaper.ImGui_Unindent(ctx)
                
                --reaper.ImGui_NewLine(ctx)
            
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show column with plugin open status",settings.showPluginNumberColumn) 
                if ret then 
                    settings.showPluginNumberColumn = val
                    saveSettings()
                end
                setToolTipFunc("Show a column to the right of plugin names with the plugin number and if a color if it's open.\nIf the parameter area is hidden this will be hidden automatically.")  
                reaper.ImGui_Indent(ctx)
                
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show plugin number in overview",settings.showPluginNumberInPluginOverview) 
                    if ret then 
                        settings.showPluginNumberInPluginOverview = val
                        saveSettings()
                    end
                    setToolTipFunc("Show the plugin number in the plugins overview")  
                reaper.ImGui_Unindent(ctx)
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Hide plugin type from name",settings.hidePluginTypeName) 
                if ret then 
                    settings.hidePluginTypeName = val
                    saveSettings()
                end
                setToolTipFunc("Hide plugin type from the plugin name")  
    
                local ret, val = reaper.ImGui_Checkbox(ctx,"Hide developer name from name",settings.hideDeveloperName) 
                if ret then 
                    settings.hideDeveloperName = val
                    saveSettings()
                end
                setToolTipFunc("Hide developer name from the plugin name")  
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show parallel process indication in name##parameters",settings.showParallelIndicationInName) 
                if ret then 
                    settings.showParallelIndicationInName = val
                    saveSettings()
                end
                setToolTipFunc("Show [P] when FX is processed in parallel. Show [PM] when FX is processed in parallel and mergin MIDI") 
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Allow horizontal scrolling",settings.allowHorizontalScroll) 
                if ret then 
                    settings.allowHorizontalScroll = val
                    saveSettings()
                end
                setToolTipFunc("Allow to scroll horizontal in the plugin list, when namas are too big for module") 
                
                
                reaper.ImGui_TextColored(ctx, colorGrey, "Panel Controls")
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Open plugin when clicking name##",settings.openPluginWhenClickingName) 
                if ret then 
                    settings.openPluginWhenClickingName = val
                    saveSettings()
                end
                setToolTipFunc("Open plugin when clicking name, instead of focusing the plugin and needing doubleclick to open.\nIf enabled, clicking the plugin number will focus the plugin.\nIf the parameters area is not shown the plugins will always be open on single click")  
                
                
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
                
                local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Add FX popup" button (+)',settings.showAddTrackFX) 
                if ret then 
                    settings.showAddTrackFX = val
                    saveSettings()
                end
                setToolTipFunc("Show a button (+) that will allow to add track fx, fx chains and more through a popup, in the plugins panel")  
                
                local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Add FX Directly" button',settings.showAddTrackFXDirectly) 
                if ret then 
                    settings.showAddTrackFXDirectly = val
                    saveSettings()
                end
                setToolTipFunc("Show a button that will allow to add track fx (not a modulator) in the plugins panel")  
                
                local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Add Container" button',settings.showAddContainer) 
                if ret then 
                    settings.showAddContainer = val
                    saveSettings()
                end
                setToolTipFunc("Show a button that will add a contininer to the FX list")  
                
                local ret, val = reaper.ImGui_Checkbox(ctx,'Close new FX window when added',settings.closeFxWindowAfterBeingAdded) 
                if ret then 
                    settings.closeFxWindowAfterBeingAdded = val
                    saveSettings()
                end
                setToolTipFunc("Close the FX window's after FX was added, if open")  
                
                
                reaper.ImGui_TextColored(ctx, colorGrey, "Containers")
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show containers",settings.showContainers) 
                if ret then 
                    settings.showContainers = val
                    saveSettings()
                end
                setToolTipFunc("Show FX container in the plugin list")  
                
                if settings.showContainers then
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Color container names",settings.colorContainers) 
                    if ret then 
                        settings.colorContainers = val
                        saveSettings()
                    end
                    setToolTipFunc("Color FX container grey in the plugin list")  
                end
                   
                        
                   
                sliderInMenu("Indent size for containers", "indentsAmount", menuSliderWidth, 0, 8, "Set how large a visual indents size is shown for container content in the plugin list")
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,'Indicate folder depth indents with "|"',settings.identsType) 
                if ret then 
                    settings.identsType = val
                    saveSettings()
                end
                setToolTipFunc('Use "|" at root of every folder depth indent for easier visual decoding')
                
                
                local ret, includeModulators = reaper.ImGui_Checkbox(ctx,"Include Modulators",settings.includeModulators) 
                if ret then 
                    settings.includeModulators = includeModulators
                    saveSettings()
                end
                setToolTipFunc("Show Modulators container in the plugin list") 
            reaper.ImGui_Unindent(ctx)
            reaper.ImGui_EndGroup(ctx)
            
            
            -- PARAMETERS PANELS
            
            reaper.ImGui_SameLine(ctx)
            
            reaper.ImGui_BeginGroup(ctx)
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Parameter panels") 
            
            reaper.ImGui_Indent(ctx)
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,'"Show plugins" setting is global##parameters',settings.showPluginsGlobal) 
                if ret then 
                    settings.showPluginsGlobal = val
                    saveSettings()
                end
                setToolTipFunc("Enable this to make the last panel show setting (focused or all plugins) global and not track based") 
                
                if settings.showPluginsGlobal then
                    reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show panels##parameters",settings.showPlugins) 
                    if ret then 
                        settings.showPlugins = val
                        saveSettings()
                    end
                    setToolTipFunc("Show plugin panels") 
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show only focused plugin##parameters",settings.showOnlyFocusedPlugin) 
                    if ret then 
                        if val and not settings.showPlugins then
                            settings.showPlugins = true
                        end
                        settings.showOnlyFocusedPlugin = val
                        saveSettings()
                    end
                    setToolTipFunc("Only one plugin panel will be shown")  
                    reaper.ImGui_Unindent(ctx)
                end
                
                 
                
                sliderInMenu("Panels width", "parametersWidth", menuSliderWidth, 80, 400, "Set the width of the parameters panel. ONLY used for horizontal and floating") 
                
                sliderInMenu("Panels height", "parametersHeight", menuSliderWidth, 100, 800, "Set the max height of the parameters panel. ONLY used for vertical and floating")  
                
                
                reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Use fixed height for parameter panels",settings.alwaysUseParametersHeight) 
                    if ret then 
                        settings.alwaysUseParametersHeight = val
                        saveSettings()
                    end
                    setToolTipFunc("Enable this to keep the same size of the parameter panels all the time (Only in vertical mode).")  
                reaper.ImGui_Unindent(ctx)
                
                
                
                
                layoutKnobsOrSliders("Plugin")
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show wet knob##",settings.showWetKnobOnPlugins) 
                if ret then 
                    settings.showWetKnobOnPlugins = val
                    saveSettings()
                end
                setToolTipFunc("Show the wet knob button on the plugins header") 
                
                --inputInMenu("Max parameters shown", "maxParametersShown", 100, "Will only fetch X amount of parameters from focused FX. 0 will show all.\nIf you have problems with performance reduce the amount might help", true, 0, nil) 
                
                
                
                reaper.ImGui_TextColored(ctx, colorGrey, "Panel Controls")
                
                
                 
                local ret, val = reaper.ImGui_Checkbox(ctx,'Show "Only mapped" and search field on focused plugin panel',settings.showOnlyMappedAndSearchOnFocusedPlugin) 
                if ret then 
                    settings.showOnlyMappedAndSearchOnFocusedPlugin = val
                    saveSettings()
                end
                setToolTipFunc("Show only mapped toggle and search field in parameters panel")  
                
                 
                
                reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Searching disables only mapped##",settings.searchClearsOnlyMapped) 
                    if ret then 
                        settings.searchClearsOnlyMapped = val
                        saveSettings()
                    end
                    setToolTipFunc('When enabled this will disable to "Only mapped" toggle, when searching') 
                
                
                reaper.ImGui_Unindent(ctx)
                    
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show last clicked parameter##",settings.showLastClicked) 
                if ret then 
                    settings.showLastClicked = val
                    saveSettings()
                end
                setToolTipFunc("Show the last clicked parameter below the search field")  
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show at top of panel##parameters",settings.showParameterOptionsOnTop) 
                if ret then 
                    settings.showParameterOptionsOnTop = val
                    saveSettings()
                end
                setToolTipFunc("Show search field, only mapped and last clicked parameter on top of the mappings panel")  
                
                --[[
                local ret, val = reaper.ImGui_Checkbox(ctx,'Show on all plugin panels',settings.showParametersOptionOnAllPlugins) 
                if ret then 
                    settings.showParametersOptionOnAllPlugins = val
                    saveSettings()
                end
                setToolTipFunc("Show only mapped toggle and search field in parameters panel") 
                ]]
                
            reaper.ImGui_Unindent(ctx)
            
            reaper.ImGui_EndGroup(ctx)
        end 
         
        
        function set.Modulators()
            
            reaper.ImGui_BeginGroup(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show modulators panel##modulators",settings.showModulatorsPanel) 
                if ret then 
                    settings.showModulatorsPanel = val
                    saveSettings()
                end
                setToolTipFunc("Show or hide the modulators panel")  
                
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Make panel a fixed size##plugins",settings.modulatorsPanelWidthFixedSize) 
                if ret then 
                    settings.modulatorsPanelWidthFixedSize = val
                    saveSettings()
                end
                setToolTipFunc("Make the modulators panel a fixed size")  
                
                if settings.modulatorsPanelWidthFixedSize then
                    reaper.ImGui_Indent(ctx)
                    sliderInMenu("Modulators panels width", "modulatorsPanelWidth", menuSliderWidth, settings.modulesWidth+settings.modulatorsWidth+16, 1600, "Set the fixed width of the modulators panel. ONLY used for horizontal and floating") 
                    
                    sliderInMenu("Modulators panels height", "modulatorsPanelHeight", menuSliderWidth, settings.modulesHeight+settings.modulatorsHeight+16, 1600, "Set the fixed height of the modulators panel. ONLY used for vertical and floating")  
                    reaper.ImGui_Unindent(ctx)
                end
            reaper.ImGui_EndGroup(ctx)
            
            
            
            
            reaper.ImGui_BeginGroup(ctx)
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Options")
            
            reaper.ImGui_Indent(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,'Add modulators container as first',settings.addModulatorContainerToBeginningOfChain) 
                if ret then 
                    settings.addModulatorContainerToBeginningOfChain = val
                    saveSettings()
                end
                setToolTipFunc('Add the modulators container to the beginning of your fx chain to ensure that all MIDI is recieved by the modulators, before passing them to other FXs') 
                
            
            reaper.ImGui_Unindent(ctx) 
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Header")
            
            reaper.ImGui_Indent(ctx)
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
            reaper.ImGui_Unindent(ctx)
            
            reaper.ImGui_NewLine(ctx)
             
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Add list")
            
            reaper.ImGui_Indent(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,"Show add modulator list##modules",settings.showAddModulatorsList) 
                if ret then 
                    settings.showAddModulatorsList = val
                    saveSettings()
                end
                setToolTipFunc("Show or hide the add modulator list")  
                
                if sliderInMenu("Panels width", "modulesWidth", menuSliderWidth, 100, 400, "Set the width of the modules panel. ONLY used for horizontal and floating") then 
                    --setWindowWidth = true
                end
                
                sliderInMenu("Panels height", "modulesHeight", menuSliderWidth, 100, 800, "Set the max height of the modules panel. ONLY used for vertical and floating")  
                
                sliderInMenu("Popup height", "modulesPopupHeight", menuSliderWidth, 100, 800, "Set the height of the popup modules panel")   
            reaper.ImGui_Unindent(ctx)
            
            
            reaper.ImGui_EndGroup(ctx)
            
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_BeginGroup(ctx)
        
            
            
            reaper.ImGui_TextColored(ctx, colorGrey, "Modulators")
            
            reaper.ImGui_Indent(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,'"Show modulators" setting is global##modulators',settings.showModulatorsGlobal) 
                if ret then 
                    settings.showModulatorsGlobal = val
                    saveSettings()
                end
                setToolTipFunc("Show or hide modulators from the modulators panel")  
                
                if settings.showModulatorsGlobal then
                    reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show panels##modulators",settings.showModulators) 
                    if ret then 
                        settings.showModulators = val
                        saveSettings()
                    end
                    setToolTipFunc("Show modulators panels") 
                    
                    --[[
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show only focused plugin##parameters",settings.showOnlyFocusedModulator) 
                    if ret then 
                        if val and not settings.showModulators then
                            settings.showModulators = true
                        end
                        settings.showOnlyFocusedModulator = val
                        saveSettings()
                    end
                    setToolTipFunc("Only one plugin panel will be shown")  
                    ]]
                    reaper.ImGui_Unindent(ctx)
                end
                
                if sliderInMenu("Panels width", "modulatorsWidth", menuSliderWidth, 80, 400, "Set the width of the modulators panel. ONLY used for horizontal and floating") then 
                    --setWindowWidth = true
                end
                
                sliderInMenu("Panels height", "modulatorsHeight", menuSliderWidth, 100, 800, "Set the max height of the modulators panel. ONLY used for vertical and floating")  
                
                sliderInMenu("Panels width in context", "modulatorsWidthContext", menuSliderWidth, 80, 400, "Set the width of the (assigned) modulator in the parameter right click context menu")  
                
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Limit module height in vertical mode",settings.limitModulatorHeightToModulesHeight) 
                if ret then 
                    settings.limitModulatorHeightToModulesHeight = val
                    saveSettings()
                end
                setToolTipFunc("Limit modulators height to panels height set above in vertical mode")  
                
                layoutKnobsOrSliders("Modulator")
                
                reaper.ImGui_TextColored(ctx, colorGrey, "Panel buttons")  
                reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show add button (+) at start##mappings",settings.showAddModulatorButtonBefore) 
                    if ret then 
                        settings.showAddModulatorButtonBefore = val
                        saveSettings()
                    end
                    setToolTipFunc('Show a small "+" before the first modulator, that you can click to add a new modulator') 
                     
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show add button (+) between each modulator##mappings",settings.showAddModulatorButton) 
                    if ret then 
                        settings.showAddModulatorButton = val
                        saveSettings()
                    end
                    setToolTipFunc('Show a small "+" after each modulator, that you can click to add a new modulator') 
                    
                    
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show add button (+) at end##mappings",settings.showAddModulatorButtonAfter) 
                    if ret then 
                        settings.showAddModulatorButtonAfter = val
                        saveSettings()
                    end
                    setToolTipFunc('Show a small "+" after the last modulator, that you can click to add a new modulator') 
                reaper.ImGui_Unindent(ctx)
                
                reaper.ImGui_NewLine(ctx) 
                reaper.ImGui_TextColored(ctx, colorGrey, "Header")
                
                reaper.ImGui_Indent(ctx)
                    local ret, val = reaper.ImGui_Checkbox(ctx,"Show remove button (x)##modulator",settings.showRemoveCrossModulator) 
                    if ret then 
                        settings.showRemoveCrossModulator = val
                        saveSettings()
                    end
                    setToolTipFunc('Show "X" when hovering modulator to remove modulator') 
                    
                     
                    sliderInMenu("Default visualizer size", "visualizerSize", menuSliderWidth, 0, 3, "Set the size of the visualizer (output) for modulators.\nIf 0 it will be contained in the header.\nClicking a visulizer while holding Super will change the size for that modulator")  
                reaper.ImGui_Unindent(ctx)
                
            reaper.ImGui_Unindent(ctx)
             
            reaper.ImGui_EndGroup(ctx)
            
        end
        
        function set.FloatingMapper()
            floatingMapperSettings()
        end
                
        local groups = {"General", "Plugins", "Modulators", "Floating Mapper" }
        
        
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
            reaper.ImGui_BeginGroup(ctx)
            local ret, val = reaper.ImGui_Checkbox(ctx,"New mapping uses previous\nmapping's width and direction",settings.usePreviousMapSettingsWhenOverwrittingMapping) 
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
            
            
            sliderInMenu("Pulsating speed", "pulsateMappingColorSpeed", menuSliderWidth, 1, 10, "Set how fast the pulsating of the mapping button should be")
            
            
            reaper.ImGui_NewLine(ctx)
            reaper.ImGui_TextColored(ctx, colorGrey, "Experimental")
            local ret, val = reaper.ImGui_Checkbox(ctx,"Mapping width only positive",settings.mappingWidthOnlyPositive) 
            if ret then 
                settings.mappingWidthOnlyPositive = val
                saveSettings()
            end
            setToolTipFunc("If enabeled the mapped parameter width will only be from 0 to 1, so never negative")  
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Make it easier to change parameters that have steps##",settings.makeItEasierToChangeParametersThatHasSteps) 
            if ret then 
                settings.makeItEasierToChangeParametersThatHasSteps = val
                saveSettings()
            end
            setToolTipFunc("This will make a smaller mouse movement or scroll change the parameter if it has steps.\nThis might be confusing when not using knobs, as knobs are already relative but sliders aren't") 
            
            reaper.ImGui_Indent(ctx)
                sliderInMenu("Max amount of steps for a parameter to use this mode", "maxAmountOfStepsForStepSlider", menuSliderWidth, 1, 100, "Set the max amount of steps that a paramter can have to use this mode")
                sliderInMenu("Movement needed to change step", "movementNeededToChangeStep", menuSliderWidth, 1, 10, "Set how large a moment is needed to change the parameter") 
            reaper.ImGui_Unindent(ctx)
            sliderInMenu("Scroll envelope release time", "scrollTimeRelease", menuSliderWidth, 100, 5000, "Set how quickly writing a parameter to an envelope will be released (in touch mode) when scrolled")
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Force mapping##",settings.forceMapping) 
            if ret then 
                settings.forceMapping = val
                saveSettings()
            end
            setToolTipFunc("This will ensure that you always map a parameter if you click on it.\nThe downside is that that the last touched FX parameter will always be the delta value for the focused FX, in order to ensure this behavior.") 
            
            
            
            reaper.ImGui_EndGroup(ctx)
            
        end
        
        
        
        
        function set.Envelope() 
            envelopeSettings()
        end
        
        
        function set.Defaults()
        
        
            reaper.ImGui_TextColored(ctx, colorGrey, "Mapping mode for modulators")
            sliderInMenu("Width", "defaultMappingWidth", menuSliderWidth, -100, 100, "Set the default width when mapping a parameter") 
             
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
            
            sliderInMenu("Width", "defaultMappingWidthLFO", menuSliderWidth, -100, 100, "Set the default width when mapping a parameter") 
            
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
        
        local groups =  {"General", "Defaults", "Envelope"}
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
          ignoreKeypress = true
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
            sliderInMenu("Scrolling speed", "scrollingSpeedOfHorizontalScroll", menuSliderWidth, -100, 100, "Set how fast to scroll the horizontal scroll") 
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Scroll horizontal anywhere",settings.scrollModulatorsHorizontalAnywhere) 
            if ret then 
                settings.scrollModulatorsHorizontalAnywhere = val
                saveSettings()
            end
            setToolTipFunc("With this enabled you can scroll the modulators area horizontally anywhere on the app.\nWith this on you should disable Allow scrolling in the plugins area")   
            
            reaper.ImGui_NewLine(ctx)
            if not settings.vertical then
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
                    
                    
                    sliderInMenu("Scrolling speed of vertical horizontal scroll", "scrollingSpeedOfVerticalHorizontalScroll", menuSliderWidth, -100, 100, "Set how fast to scroll the horizontal vertical scroll") 
                end 
            else 
                reaper.ImGui_TextColored(ctx, colorGrey, "Force vertical scroll in modulators area with modifiers:") 
                modifiersSettingsModule("modifierEnablingScrollVerticalVertical")
            end
        end
        
        function set.ModifierSettings()
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "Mouse modifier settings") 
            if reaper.ImGui_BeginTable(ctx, "modifierTable", 2,  reaper.ImGui_TableFlags_SizingFixedFit() | reaper.ImGui_TableFlags_NoHostExtendX()) then
                
                reaper.ImGui_TableNextRow(ctx)
                reaper.ImGui_TableNextColumn(ctx)  
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "DRAGS") 
                reaper.ImGui_TableNextRow(ctx)
                
                local i = 0
                local modifiersOptionsAlphabetic = {}
                for name, _ in pairs(settings.modifierOptionsParameter) do
                    table.insert(modifiersOptionsAlphabetic, name)
                end
                table.sort(modifiersOptionsAlphabetic)
                for i, name in ipairs(modifiersOptionsAlphabetic) do
                    local value = settings.modifierOptionsParameter[name]
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorText, prettifyString(name))
                    reaper.ImGui_TableNextColumn(ctx) 
                    modifiersSettingsModule(name, "modifierOptionsParameter")
                    
                    if name == "fineAdjust" then
                        sliderInMenu("Fine adjust amount", "fineAdjustAmount", menuSliderWidth, 2, 200, "Set how fine the fine adjust key should be. Higher is finer") 
                    end
                    
                    if name == "scrollValue" then
                        sliderInMenu("Scroll value speed", "scrollValueSpeed", menuSliderWidth, 1, 100, "Set how much scrolling value, will change the value") 
                    
                    
                        local ret, val = reaper.ImGui_Checkbox(ctx,"Invert scroll value##",settings.scrollValueInverted) 
                        if ret then 
                            settings.scrollValueInverted = val
                            saveSettings()
                        end
                        setToolTipFunc("This will change the direction of value change for the scroll wheel.") 
                    end
                    
                    
                    if i < #modifiersOptionsAlphabetic then
                        reaper.ImGui_TableNextRow(ctx)
                    end
                    
                end
                
                reaper.ImGui_TableNextRow(ctx)
                reaper.ImGui_TableNextColumn(ctx)  
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "CLICKS")
                reaper.ImGui_TextColored(ctx, colorTextDimmed, " - Parameters") 
                reaper.ImGui_TableNextRow(ctx) 
                local i = 0
                local modifiersOptionsAlphabetic = {}
                for name, _ in pairs(settings.modifierOptionsParameterClick) do
                    table.insert(modifiersOptionsAlphabetic, name)
                end
                table.sort(modifiersOptionsAlphabetic)
                for i, name in ipairs(modifiersOptionsAlphabetic) do
                    local value = settings.modifierOptionsParameterClick[name]
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorText, prettifyString(name))
                    reaper.ImGui_TableNextColumn(ctx) 
                    modifiersSettingsModule(name, "modifierOptionsParameterClick")
                    
                    if i < #modifiersOptionsAlphabetic then
                        reaper.ImGui_TableNextRow(ctx)
                    end
                    
                end
                
                
                reaper.ImGui_TableNextRow(ctx)
                reaper.ImGui_TableNextColumn(ctx)  
                reaper.ImGui_TextColored(ctx, colorTextDimmed, " - Plugins") 
                reaper.ImGui_TableNextRow(ctx) 
                local i = 0
                local modifiersOptionsAlphabetic = {}
                for name, _ in pairs(settings.modifierOptionFx) do
                    table.insert(modifiersOptionsAlphabetic, name)
                end
                table.sort(modifiersOptionsAlphabetic)
                for i, name in ipairs(modifiersOptionsAlphabetic) do
                    local value = settings.modifierOptionFx[name]
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorText, prettifyString(name))
                    reaper.ImGui_TableNextColumn(ctx) 
                    modifiersSettingsModule(name, "modifierOptionFx")
                    
                    if i < #modifiersOptionsAlphabetic then
                        reaper.ImGui_TableNextRow(ctx)
                    end
                    
                end
                
                
                
                
                reaper.ImGui_TableNextRow(ctx)
                reaper.ImGui_TableNextColumn(ctx)  
                reaper.ImGui_TextColored(ctx, colorTextDimmed, " - Modulator Header") 
                reaper.ImGui_TableNextRow(ctx) 
                local i = 0
                local modifiersOptionsAlphabetic = {}
                for name, _ in pairs(settings.modifierOptionsModulatorHeaderClick) do
                    table.insert(modifiersOptionsAlphabetic, name)
                end
                table.sort(modifiersOptionsAlphabetic)
                for i, name in ipairs(modifiersOptionsAlphabetic) do
                    local value = settings.modifierOptionsModulatorHeaderClick[name]
                    reaper.ImGui_TableNextColumn(ctx)
                    
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_TextColored(ctx, colorText, prettifyString(name))
                    reaper.ImGui_TableNextColumn(ctx) 
                    modifiersSettingsModule(name, "modifierOptionsModulatorHeaderClick")
                    
                    if i < #modifiersOptionsAlphabetic then
                        reaper.ImGui_TableNextRow(ctx)
                    end
                    
                end
                
                
                
                
                reaper.ImGui_NewLine(ctx)
                
                
                reaper.ImGui_EndTable(ctx)
                
            end
            
            
            if modifierStr ~= "" then
               -- reaper.ImGui_TextColored(ctx, colorTextDimmed, "(Modifier pressed: " .. modifierStr .. ")")
            end
        end
        
        
        
        
        function set.KeyCommands()
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Block shortcut from this page",settings.allowPassingKeyboardShortcutsFromThisPage) 
            if ret then 
                settings.allowPassingKeyboardShortcutsFromThisPage = val
                saveSettings()
            end
            setToolTipFunc("Block all shortcuts when on this page")  
            
            ignoreKeypress = settings.allowPassingKeyboardShortcutsFromThisPage
            
            
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
                                if isEscapeKey then
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
            
            
            --if listenForPassthroughKeyCommands then
            lastPressedCmdTbl = listeningForKeyCommand(listenForPassthroughKeyCommands)
            lastFoundCmdTbl = lastPressedCmdTbl or lastPressedCmdTbl or lastFoundCmdTbl
            --end
            
            if not settings.passAllUnusedShortcutThrough then
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_TextColored(ctx, listenForPassthroughKeyCommands and colorMappingPulsating or colorTextDimmed, "Pass through shortcuts")
                
                if isEscapeKey then
                    listenForPassthroughKeyCommands = false
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
            
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "Last pressed shortcut:")
            if last_focused_reaper_section_name then reaper.ImGui_TextColored(ctx, colorTextDimmed, "Section:       " .. last_focused_reaper_section_name ) end
            if lastFoundCmdTbl then
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "Shortcut:       " .. lastFoundCmdTbl.key )
                reaper.ImGui_TextColored(ctx, colorTextDimmed, "Command:    " .. lastFoundCmdTbl.name)
            end
             
            --reaper.ImGui_TextColored(ctx, colorTextDimmed, last_focused_reaper_section_name)
            
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
        
        reaper.ImGui_TextColored(ctx, colorGrey, "Thanks to SNJUK2 for allowing to include some of his JSFX plugins.\nIf you use and like them a lot consider letting him know that:")
        if reaper.ImGui_Button(ctx, "SJUK2's forum page") then
            openWebpage("https://forums.cockos.com/member.php?u=113744")
        end
        
        reaper.ImGui_NewLine(ctx)
        local appreaciationText = ""
        appreaciationText  = appreaciationText  .. "Thanks to all the early adopters/testers for giving feedback, finding bugs and help shape the script.\n"
        appreaciationText  = appreaciationText  .. "Here I should mention especially:\n - "
        local users = {"Seventh Sam (for giving really thorough feedback)", "Digitt (also for making a mock redesign of faders)", "Vagelis", "93Nb", "deeb", "tonalstates", "Khron Studio", "AndreiMir", "MCJ"}
        appreaciationText  = appreaciationText  .. table.concat(users, "\n - ")
        
        appreaciationText  = appreaciationText  .. "\n"
        appreaciationText  = appreaciationText  .. "\n"
        appreaciationText  = appreaciationText  .. "This script has taken many month to get where it is now. So many moving parts.\n"
        appreaciationText  = appreaciationText  .. "I'll keep making it better and add more features, especially those you'd like to see.\n"
        appreaciationText  = appreaciationText  .. "So with that said, if you use it and like it, consider donating a bit for all the time spend.\n"
        --appreaciationText  = appreaciationText  .. "r\n"
        reaper.ImGui_TextColored(ctx, colorGrey, appreaciationText) 
        if reaper.ImGui_Button(ctx, "DONATE") then
            openWebpage("https://www.paypal.com/paypalme/saxmand")
        end
    end
    
    
    
    function menus.Performance()
        
        reaper.ImGui_TextColored(ctx, colorTextDimmed, "Performance settings")
        
        reaper.ImGui_Indent(ctx)
        
        
            local ret, val = reaper.ImGui_Checkbox(ctx,"Show script performance: ",settings.showScriptPerformance) 
            if ret then 
                settings.showScriptPerformance = val
                saveSettings()
            end
            setToolTipFunc("Show script performance")  
             
            
            if settings.showScriptPerformance then
                reaper.ImGui_Indent(ctx)
                  reaper.ImGui_TextColored(ctx, colorText, scriptPerformanceText)
                  reaper.ImGui_TextColored(ctx, colorText, "(FPS should be around when it's not staling 33.3)")
                reaper.ImGui_Unindent(ctx)
            end
            
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Limit amount of drawn parameters in plugins",settings.limitAmountOfDrawnParametersInPlugin) 
            if ret then 
                settings.limitAmountOfDrawnParametersInPlugin = val
                saveSettings()
            end
            setToolTipFunc("Enable this if you have poor performance with heavy plugins") 
            
            if settings.limitAmountOfDrawnParametersInPlugin then 
                reaper.ImGui_Indent(ctx) 
                sliderInMenu("Limit amount", "limitAmountOfDrawnParametersInPluginAmount", menuSliderWidth, 10, 1000, "Set how many parameters gets drawn in the plugin panel")
                reaper.ImGui_Unindent(ctx) 
            end
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Use parameter catch",settings.useParamCatch) 
            if ret then 
                settings.useParamCatch = val
                saveSettings()
            end
            setToolTipFunc("This will create a catch of parameters read to ensure that we don't read any parameters multiple times") 
            
            reaper.ImGui_Indent(ctx)
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Use static parameter catch",settings.useStaticParamCatch) 
                if ret then 
                    settings.useStaticParamCatch = val
                    saveSettings()
                end
                setToolTipFunc("This will catch 'static' parameters once and then on certain changes") 
                
                local ret, val = reaper.ImGui_Checkbox(ctx,"Use semi static parameter catch",settings.useSemiStaticParamCatch) 
                if ret then 
                    settings.useSemiStaticParamCatch = val
                    saveSettings()
                end
                setToolTipFunc("This will keep catch of semi static parameters, and only read them again every X ms") 
                
                reaper.ImGui_Indent(ctx) 
                    sliderInMenu("Read every X ms", "checkSemiStaticParamsEvery", menuSliderWidth, 100, 2000, "Set how often to read semi static parameters") 
                reaper.ImGui_Unindent(ctx)
            reaper.ImGui_Unindent(ctx)
            
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Filter parameters that are most likely unwanted",settings.filterParamterThatAreMostLikelyNotWanted) 
            if ret then 
                settings.filterParamterThatAreMostLikelyNotWanted = val
                saveSettings()
            end
            setToolTipFunc("Filter paramters matching tags...")
            
            reaper.ImGui_Indent(ctx)
                local ret, val = reaper.ImGui_Checkbox(ctx,"Build a database of paramters that should be filtered",settings.buildParamterFilterDataBase) 
                if ret then 
                    settings.buildParamterFilterDataBase = val
                    saveSettings()
                end
                setToolTipFunc("This will create a database over plugins that have paramters we would like to filter out, in order to not read unnessesary parameters") 
            reaper.ImGui_Unindent(ctx)
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Limit modulation parameter linking reading",settings.limitParameterLinkLoading) 
            if ret then 
                settings.limitParameterLinkLoading = val
                saveSettings()
            end
            setToolTipFunc("This will limit how often we look for modulation parameter links, as this is a more static value") 
        reaper.ImGui_Unindent(ctx)
        
        reaper.ImGui_NewLine(ctx)
        reaper.ImGui_TextColored(ctx, colorTextDimmed, "Developer settings (Use with causion)")
        
        reaper.ImGui_Indent(ctx)
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
             
            
            reaper.ImGui_NewLine(ctx)
            
            if reaper.ImGui_Button(ctx, "Export app settings") then
                
                local data = json.encodeToJson(settings) 
                -- -- Get username (cross-platform)
                local username = os.getenv("USERNAME") or os.getenv("USER") or "unknown_user"
                
                -- Get date and time
                local timestamp = os.date("%Y-%m-%d_%H-%M-%S")  -- format: 2025-07-27_15-30-45
                
                -- Combine into filename
                local filename = "FX-Modulator-Linking-Settings_" .. username .. "_" .. timestamp
                saveFile(data, filename, settingsFolderName) 
            end
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_Button(ctx, "Open app settings folder") then
                open_folder(settingsFolderName)
            end
            
            
            if reaper.ImGui_Button(ctx, "Import app settings") then 
                local retval, file = reaper.GetUserFileNameForRead(settingsFolderName, "Select a file", "txt")
                if retval then
                    data = readFile(true, nil, file) 
                    if data then
                        settings = json.decodeFromJson(data) 
                        saveSettings()
                        local allColorSets, selectedColorSetIndex = getColorSetsAndSelectedIndex() 
                        
                        local colorSetExist = false
                        for _, name in ipairs(allColorSets) do
                            if name == settings.selectedColorSet then
                                colorSetExist = true
                                break
                            end
                        end
                        if not colorSetExist then 
                            saveFile(json.encodeToJson(settings.colors), settings.selectedColorSet, colorFolderName) 
                            --allColorSets, selectedColorSetIndex =  getColorSetsAndSelectedIndex() 
                        end
                        
                    end
                end
            end
            
            
            
            reaper.ImGui_NewLine(ctx)
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Log loop start",settings.createDevLogStartOfLoop) 
            if ret then 
                settings.createDevLogStartOfLoop = val
                saveSettings()
            end
            setToolTipFunc("Do not activate this as it's just for development")   
            
            local ret, val = reaper.ImGui_Checkbox(ctx,"Extended floating mapper",settings.extendedFloatingMapper) 
            if ret then 
                settings.extendedFloatingMapper = val
                saveSettings()
            end
            setToolTipFunc("Do not activate this mode as it's in development")   
            reaper.ImGui_TextColored(ctx, colorTextDimmed, "(Not ready yet)")
        reaper.ImGui_Unindent(ctx)
    end
    
    local menusOrder = {"Layout", "Mapping", "Mouse And Keyboard", "Colors", "About", "Performance"}
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
local automationTypesDescription = {"Envelopes are active but faders are all for time", "Play faders with armed envelopes", "Record fader movements to armed envelopes", "Record fader movements after first movement", "Record fader positions to armed envelopes", "Allow adjusting parameters but do not apply to envelopes"}
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

function addingAnyModuleWindow(hwnd, moveToModulatorContainer) 
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
    
    
    local text
    if moveToModulatorContainer then
        text = "Adding FX to Modulator container - Click to stop"
    else
        text = "Adding FX to at " .. (addNewFXToEnd and "end" or "position") .. ". - Click " .. convertModifierOptionToString(settings.modifierOptionFx.addFXAsLast) .. " to toggle position."
        --text = "Adding FX to at " .. (addNewFXToEnd and "end" or "position") .. ". Toggle placement with " .. convertModifierOptionToString(settings.modifierOptionFx.addFXAsLast) .. " - Click to stop"
    end
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


    
function updateVisibleEnvelopes(track, p)
    if settings.showEnvelope and fxnumber and paramnumber then 
        
        
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
        
        if settings.hideEnvelopesWithNoPoints or settings.hideEnvelopesWithPoints or settings.hideEnvelopesIfLastTouched then 
            hideTrackEnvelopesUsingSettings(track, p)
        end
        if p.envelope then
            lastFocusedEnvelope = p.envelope--p.envelope
        end
        
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
    end
end

function updateMapping()
    local p = getAllDataFromParameter(track,fxIndexTouched,parameterTouched) 
    local canBeMapped = mapActiveFxIndex and (not p.parameterLinkActive or (p.parameterLinkActive and mapActiveName ~= p.parameterLinkName)) 
    
    if canBeMapped then
        local isLFO = mapActiveName:match("LFO") ~= nil
        setParamaterToLastTouched(track, modulationContainerPos, mapActiveFxIndex, fxnumber, paramnumber, GetParam(track,fxnumber, paramnumber), (isLFO and (settings.defaultBipolarLFO and -0.5 or 0) or (settings.defaultBipolar and -0.5 or 0)), (isLFO and settings.defaultMappingWidthLFO or settings.defaultMappingWidth) / 100)
        if settings.mapOnce then stopMappingOnRelease = true end
    end
    
    if scrollToParameter and (lastFxNumber ~= fxnumber or lastParamNumber ~= paramnumber) then
        scroll = paramnumber 
        scrollToParameter = false
    end
    
    
    if p then
        updateVisibleEnvelopes(track, p)
    end
    
    lastFxNumber = fxnumber
    lastParamNumber = paramnumber
    --lastFxIndexTouched = nil
    --lastParameterTouched = nil
    --track = trackTouched
end

function isFXWindowUnderMouse()
    local x, y = reaper.GetMousePosition()
    local hwnd = reaper.JS_Window_FromPoint(x, y)
    while hwnd ~= nil and reaper.JS_Window_IsWindow(hwnd) do
        local title = reaper.JS_Window_GetTitle(hwnd)
        if title and (title:match("FX:") ~= nil or title:match("VST") ~= nil or title:match("JS:") ~= nil or title:match("Clap:") ~= nil or title:match("AU:") ~= nil or title:match("AU") ~= nil) then
        --if title and title:match(" - Track") ~= nil then
          clickedHwnd = hwnd
          --lastClickedHwnd = hwnd
          return true, title, hwnd
        end
        hwnd = reaper.JS_Window_GetParent(hwnd)
    end
    --local clickedHwndUpdate = reaper.JS_Window_IsVisible(clickedHwnd) and clickedHwnd or nil
    return nil, "", clickedHwndUpdate
end

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
            
            if trackSettings.focusedParam then
                trackSettings.focusedParam[GetFXGUID(trackTemp, fxnumber)] = paramnumber
                saveTrackSettings(track)
            end
            
            
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
            --if fxWindowClicked then 
            
            --end
            lastClickedHwnd = clickedHwnd
        end
    end
    
    
    local retval, trackidx, itemidx, takeidx, fxidx, param = reaper.GetTouchedOrFocusedFX( 0 ) 
    
    --aa1, aa2 = get_container_path_from_fx_id(track, fxidx)
    if retval and trackidx and not modulatorFxIndexes[fxidx] then
        if trackidx == -1 then
           trackTemp  = reaper.GetMasterTrack(0)
            --reaper.ShowConsoleMsg("master\n")
        else
            --reaper.ShowConsoleMsg("not master\n")
           trackTemp = reaper.GetTrack(0, trackidx)
        end
        --if settings.focusFollowsFxClicks and trackTemp and track ~= trackTemp and validateTrack(trackTemp) then
            --if settings.trackSelectionFollowFocus then
            --    reaper.SetOnlyTrackSelected(trackTemp)
            --end
            --track = trackTemp
        --end
        
        if isMouseClick then 
            fxWindowClicked = isFXWindowUnderMouse() 
        end
        
        local deltaParam = GetNumParams(trackTemp, fxidx) - 1  
        local dryWet = GetNumParams(trackTemp, fxidx) - 10  
        
        if trackTemp and deltaParam ~= param and dryWet ~= param then 
            local p = getAllDataFromParameter(trackTemp,fxidx,param) 
            
            if isMouseDown and not reaper.ImGui_IsMousePosValid(ctx) then  
                if isMouseClick then 
                    --fxWindowClicked = isFXWindowUnderMouse() 
                    -- trying to catch the clicked modulator when not using force, through project state change count
                    if fxWindowClicked then
                        projectStateOnClick = reaper.GetProjectStateChangeCount(0)
                    end
                    
                    projectStateOnRelease = nil
                    fxWindowClickedParameterNotFound = nil
                    parameterFound = false
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
                                    --if mouseDragStartX ~= mouse_pos_x or  mouseDragStartY ~= mouse_pos_y then
                                        parameterChanged = true
                                    --end
                                    if not dragKnob then 
                                        dragKnob = "baselineWindow"
                                        mouseDragStartX = mouse_pos_x
                                        mouseDragStartY = mouse_pos_y
                                    end 
                                end  
                                
                                local range = p.max - p.min
                                if mapActiveFxIndex then -- (isAdjustWidth and not mapActiveFxIndex) or (not isAdjustWidth and mapActiveFxIndex) then
                                    setParameterValuesViaMouse(trackTouched, "Window", "", p, range, p.min, p.currentValue, 100)
                                else
                                    if settings.allowClickingParameterInFXWindowToChangeBaseline then
                                        setParameterFromFxWindowParameterSlide(track, p)
                                    end
                                end
                                
                            end
                        end
                    end
                end
            else 
                if momentarilyDisabledParameterLink then
                    SetNamedConfigParm( track, p.fxIndex, 'param.'..p.param..'.mod.active', "1")
                    momentarilyDisabledParameterLink = false
                end
                
                if not parameterFound then
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
                    
                end
                
                -- only used for force mapping
                if settings.forceMapping and param ~= deltaParam then    
                    -- sets the Delta value to it's current value, to clear the last touched or focused fx
                    local deltaVal = GetParam(trackTemp, fxidx, deltaParam)
                    SetParam(trackTemp, fxidx, deltaParam, deltaVal) 
                    -- we store that we have focused delta, so we do not find parameter twice on release above
                    focusDelta = true
                end
                
                -- we remove the variables for next click
                parameterChanged = nil
                --parameterFound = nil
                --fxWindowClicked = nil
                --dragKnob = nil
                lastValTouched = nil
                --clickedHwnd = nil
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


customPluginSettings = getCustomPluginSettings() 
            
_, screenHeight, screenWidth = reaper.JS_Window_GetViewportFromRect( 0, 0, 1, 1, false)
local dock_id, is_docked
local runs = -1
            
local function loop() 
    playPos = reaper.GetPlayPosition() 
    playPos2 = reaper.GetPlayPosition2() 
    runs = runs + 1
    popupAlreadyOpen = false
    ignoreKeypress = false
    
    if settings.createDevLogStartOfLoop then
        reaper.ShowConsoleMsg("---- Loop start ----\n")
    end
    
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
    
    modifierTable = {Super = isSuperPressed, Ctrl = isCtrlPressed, Shift = isShiftPressed, Alt =  isAltPressed }
    modifierStr = ""
    if isSuperPressed then modifierTable.Super = true; modifierStr = modifierStr .. "Super+" end
    if isCtrlPressed then modifierTable.Ctrl = true; modifierStr = modifierStr .. "Ctrl+" end
    if isShiftPressed then modifierTable.Shift = true; modifierStr = modifierStr .. "Shift+" end
    if isAltPressed then modifierTable.Alt = true; modifierStr = modifierStr .. "Alt+" end
    modifierStr = modifierStr:sub(0,-2)
    
    modifierTable = {Super = isSuperPressed, Ctrl = isCtrlPressed, Shift = isShiftPressed, Alt =  isAltPressed }
    noModifiersTable = {Super = false, Ctrl = false, Shift = false, Alt =  false }
    
    function isMatch(optionMods, currentMods)
        for mod, required in pairs(optionMods) do
            if required and not currentMods[mod] then
                return false -- required modifier is missing
            end
        end
        return true
    end
    function isMatchExact(optionMods, currentMods)
        for mod, required in pairs(currentMods) do
            if not optionMods[mod] == required then
                return false -- required modifier is missing
            end
        end
        return true
    end
    
    for name, requiredMods in pairs(settings.modifierOptionsParameter) do
        local match =  isMatch(requiredMods, modifierTable)
        local varName = "is" .. name:sub(1,1):upper() .. name:sub(2)
        _G[varName] = match
    end
    
    for name, requiredMods in pairs(settings.modifierOptionsParameterClick) do
        local match =  isMatchExact(requiredMods, modifierTable)
        local varName = "is" .. name:sub(1,1):upper() .. name:sub(2)
        _G[varName] = match
    end 
    
    for name, requiredMods in pairs(settings.modifierOptionFx) do
        local match =  isMatchExact(requiredMods, modifierTable)
        local varName = "is" .. name:sub(1,1):upper() .. name:sub(2)
        _G[varName] = match
    end 
    
    
    for name, requiredMods in pairs(settings.modifierOptionsModulatorHeaderClick) do
        local match =  isMatchExact(requiredMods, modifierTable)
        local varName = "is" .. name:sub(1,1):upper() .. name:sub(2)
        _G[varName] = match
    end 
    
    
    isAdjustWidthToggle = (isAdjustWidth and not mapActiveFxIndex) or (not isAdjustWidth and mapActiveFxIndex)
    
    
    
    anyModifierIsPressed = isAltPressed or isCtrlPressed or isShiftPressed or isSuperPressed
    --isAltPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
    --isCtrlPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
    --isShiftPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
    --isSuperPressed = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
    isMouseDownImgui = reaper.ImGui_IsMouseDown(ctx,reaper.ImGui_MouseButton_Left())
    isMouseDownRightImgui = reaper.ImGui_IsMouseDown(ctx,reaper.ImGui_MouseButton_Right())
    isMouseClickRightImgui = reaper.ImGui_IsMouseClicked(ctx,reaper.ImGui_MouseButton_Right())
    
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
    
    if isMouseClick then
        mouse_pos_x_on_click = mouse_pos_x
        mouse_pos_y_on_click = mouse_pos_y
    end
    
    wasMouseClickedAndNowReleasedAtSamePoint = isMouseReleased and mouse_pos_x == mouse_pos_x_on_click and mouse_pos_y == mouse_pos_y_on_click 
    
    if isMouseReleased then
        ignoreImguiMousePos = false
    end
    
    scrollVertical, scrollHorizontal = reaper.ImGui_GetMouseWheel(ctx)
    
    -- Add a scroll modifier to bypass isScrollValue and allow scrolling windows 
    local isScrollValueNoModifiers = isMatchExact(settings.modifierOptionsParameter.scrollValue, noModifiersTable)
    if isScrollValueNoModifiers and not dragKnob then
        isScrollValue = false
    end
    if isMatchExact(settings.modifierEnablingScrollVerticalVertical, modifierTable) and not isMatchExact(settings.modifierEnablingScrollVerticalVertical, noModifiersTable) then
        isScrollValue = false
    end
    
    local scrollFlags = isScrollValue and reaper.ImGui_WindowFlags_NoScrollWithMouse() or reaper.ImGui_WindowFlags_None()
    if isMouseReleased then
        dragKnob = nil 
    end
    
    
    
    time = reaper.time_precise() 
    
    -- for catching parameters and stats on time run
    last_paramTableCatch = paramTableCatch
    if (isMouseWasReleased) or (settings.useSemiStaticParamCatch and (not last_semi_static_param_check_time or time - last_semi_static_param_check_time > settings.checkSemiStaticParamsEvery / 1000)) then
        last_semi_static_param_check_time = time
        check_semi_static_params = true
    else
        check_semi_static_params = false
    end
    guidTableCatch = {}
    paramTableCatch = {}
    paramsReadCountSemiStatic = 0
    paramsReadCount = 0
    
    
    
    
    function clearCatch()
        fxnumber = nil
        focusedTrackFXNames = {}
        parameterLinks = nil
        focusedTrackFXParametersData = {}
        modulatorNames = {}
        modulatorFxIndexes = {}
        modulationContainerPos = nil
        buttonHovering = {} 
    end
    
  
    
    -- remove lock if we change project and remove track selection
    currentProject = reaper.EnumProjects(-1)
    if not lastCurrentProject or lastCurrentProject ~= currentProject then
        track = nil
        lastCurrentProject = currentProject
        --track = nil
        locked = false
    end
        
    
    firstSelectedTrack = reaper.GetSelectedTrack2(0, 0, true)
    if not track or not lastFirstSelectedTrack or (firstSelectedTrack ~= lastFirstSelectedTrack and not locked) then 
        clearCatch()
        track = firstSelectedTrack 
        lastFirstSelectedTrack = firstSelectedTrack
        mapModulatorActivate(nil)
    end
    
    
    
    --if not mouseInsideFloatingMapper and not mouseInsideAppWindow then
        if updateTouchedFX() then
            if settings.focusFollowsFxClicks and trackTouched and track ~= trackTouched and validateTrack(trackTouched) then
                if settings.trackSelectionFollowFocus then
                    reaper.SetOnlyTrackSelected(trackTouched)
                end
                track = trackTouched
            end
        end
    --end
     
    
    
    
    -- stop mapping
    if stopMappingOnRelease and isMouseReleased then mapActiveFxIndex = false; mapActiveParam = false; stopMappingOnRelease = nil end
    
    
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
        trackName = "ADD TRACK"
        trackSettings = {}
        lastTrack = nil
    end
    
    
    
    if track then 
        trackGuid = GetTrackGuid(track)
        modulationContainerPos = getModulationContainerPos(track)
        
        

        -- only reload mappings sometimes
        -- could use more settings maybe, like a timer, or just on more actions. Now it's on load or mapping
        fxCount = GetCount(track)
        if not lastFxCount or lastFxCount ~= fxCount then 
            reloadParameterLinkCatch = true
            lastFxCount = fxCount
        end
        
        -- reload paramter link catch if there's a change to track fx (not from script usually)
        local all_fx = getAllTrackFXOnTrackSimpleRecursively(track)
        if all_fx_last then
            if not compareTrackFxArray(all_fx, all_fx_last) then
                reloadParameterLinkCatch = true
                reloadCustomPluginSettings = true
            end
        end
        all_fx_last = all_fx
        
        if reloadCustomPluginSettings or not customPluginSettings then
            customPluginSettings = getCustomPluginSettings() 
            --aa = customPluginSettings
            reloadCustomPluginSettings = false
        end
        
        if reloadParameterLinkCatch then
            last_paramTableCatch = {}
            reloadParameterLinkCatch = false 
            parameterLinks = nil
        end
        
        
        if not settings.limitParameterLinkLoading or (not parameterLinks or (mapActiveFxIndex and isMouseWasReleased)) then
            parameterLinks = getAllParameterModulatorMappings(track)
        end
        
        if modulationContainerPos then 
            modulatorNames, modulatorFxIndexes = getModulatorNames(track, modulationContainerPos, parameterLinks)
        else
            modulatorNames = {} 
            modulatorFxIndexes = {}
        end
        
        automation = math.floor(reaper.GetMediaTrackInfo_Value(track, 'I_AUTOMODE'))
        isAutomationRead = automation < 2
        
        if fxnumber and modulationContainerPos ~= fxnumber and not modulatorFxIndexes[fxnumber] then
            
            --focusedTrackFXParametersData = getAllParametersFromTrackFx(track, fxnumber) 
        else
            
        end 
    else 
        clearCatch()
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
    
    indentColors = {settings.colors.containerLayer1, settings.colors.containerLayer2, settings.colors.containerLayer3}
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), settings.colors.backgroundWindow)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), settings.colors.menuBar)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), settings.colors.menuBar)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), settings.colors.menuBar)
    
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), settings.colors.buttons)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), settings.colors.buttonsActive)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), settings.colors.buttonsHover)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.backgroundWindow)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), settings.colors.backgroundModules)
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
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_DragDropTarget(), colorTransparent)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), settings.colors.modulatorBorder)
    
    local colorsPush = 29
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 5)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 8) 
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 5.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ScrollbarSize(), 10.0)
    
    --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0.0, 0.0)
    local varPush = 4
    
    
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
    
    local mainFlags = reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
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
        --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), settings.colors.backgroundModules)
        
        
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        local winX, winY = reaper.ImGui_GetWindowPos(ctx) 
        
        local x,y = reaper.ImGui_GetCursorPos(ctx) 
        
        local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
        screenPosX = screenPosX
        if not settings.vertical then
            screenPosY = screenPosY - 8
        end
        
        reaper.ImGui_Dummy(ctx, 1,1)
        reaper.ImGui_SetCursorPos(ctx, x,y)
        
        mouseInsideAppWindow = mouse_pos_x_imgui >= winX and mouse_pos_x_imgui <= winX + winW and mouse_pos_y_imgui >= winY and mouse_pos_y_imgui <= winY + winH
        
        focusedHwnd = reaper.JS_Window_GetFocus()
        focusedParent = reaper.JS_Window_GetParent(focusedHwnd)
        -- not sure why I need the parent. Maybe different on windows? 
        if not appHwnd then 
            appHwnd = reaper.JS_Window_Find(appName, true)
        end
        appIsFocused = reaper.JS_Window_GetTitle(focusedParent):match(appName) ~= nil
        
        
        if not appIsFocused then 
            if focusedParent == reaper.GetMainHwnd() then
                if last_focused_reaper_section_name ~= "Main" then lastFoundCmdTbl = nil end
                last_focused_reaper_section_name = "Main"
                last_focused_reaper_section_id = reaper_sections["Main"]
            elseif focusedParent == reaper.MIDIEditor_GetActive() then 
                if last_focused_reaper_section_name ~= "MIDI Editor" then lastFoundCmdTbl = nil end
                last_focused_reaper_section_name = "MIDI Editor"
                last_focused_reaper_section_id = reaper_sections["MIDI Editor"]
                last_focused_midi_editor = focusedHwnd
            else
                last_focused_reaper_section_name = "Unknown" 
            end 
        end
        
        is_docked = reaper.ImGui_IsWindowDocked(ctx)
        
        
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
                        --[[local floating = GetFloatingWindow( track, fileInfo.fxIndex ) ~= nil
                        local floatingContainer = focusedMapping and fileInfo.fxContainerIndex and GetFloatingWindow( track, fileInfo.fxContainerIndex ) ~= nil
                        local isInTheRoot = not fileInfo.fxContainerIndex
                        local topContainerFxIndex = focusedMapping and fileInfo.fxContainerIndex and findParentContainer(fileInfo.fxContainerIndex) or fileInfo.fxIndex
                        local fxWindowOpen = focusedMapping and topContainerFxIndex and GetOpen( track, topContainerFxIndex )
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
        
        function trackHeaderIconsAndName()
        
            local title = trackName 
            local everythingsIsNotMinimized = ((allIsNotCollabsed == nil or allIsNotCollabsed) and not trackSettings.hidePlugins and not trackSettings.hideParameters and not trackSettings.hideModules)
            
            
            ImGui.BeginGroup(ctx)
            
            
            local x,y = reaper.ImGui_GetCursorPos(ctx)
            local width = settings.vertical and elementsWidthInVertical or 24
            local height = settings.vertical and 24 or elementsHeightInHorizontal
            --local width = modulatorsW
            --local height = elementsHeightInHorizontal
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
                    envelopeSettings(true) 
                    reaper.ImGui_EndPopup(ctx)
                end
                
            end
            vertical = settings.vertical
                 
            local posX, posY = getIconPosToTheRight(vertical, 24, screenPosX, screenPosY, width)
            reaper.ImGui_SetCursorScreenPos(ctx, posX, posY)
            if specialButtons.lock(ctx, "lock", 24, locked, (locked and "Unlock from track" or "Lock to selected track"), colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow, trackColor, settings.vertical) then
                locked = not locked and track or false 
                --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
            end
            
            
            local posX, posY = getIconPosToTheRight(vertical, 24*2, screenPosX, screenPosY, width)
            reaper.ImGui_SetCursorScreenPos(ctx, posX, posY)
            
            specialButtons.floatingMapper(ctx, "floatingMapper", 24, settings.useFloatingMapper, (settings.useFloatingMapper and "Disable" or "Enable") .. " floating mapper\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow, settings.vertical)
            clickFloatingMapperButton()
            
            
            local posX, posY = getIconPosToTheRight(vertical, 24*3, screenPosX, screenPosY, width)
            reaper.ImGui_SetCursorScreenPos(ctx, posX, posY)
            specialButtons.envelopeSettings(ctx, "envelopeSettings", 24, settings.showEnvelope, (settings.showEnvelope and "Disable" or "Enable") .. " showing envelope on parameter click\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow, settings.vertical, automationColor, automationColor, fillEnvelopeButton)
            clickEnvelopeSettings()
            --offset = offset + 24 + 8
            
            
            local headerW = vertical and width or 24
            local headerH = vertical and 24 or height  
            local headerAreaRemoveTop = 24*3 + 8
            local headerAreaRemoveBottom = 24 
            
            local headerTextX, headerTextY, headerTextW, headerTextH, align, bgX, bgW = getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)
            
            if drawHeaderTextAndGetHover(title, headerTextX, headerTextY, headerTextW, headerTextH, isCollabsed, vertical, 0, track and (everythingsIsNotMinimized and "Minimize everything" or "Maximize everything") or "Add an empty track", colorText, align, bgX, bgW) then
                if isMouseClick then 
                    if not track then  
                        reaper.Main_OnCommand(40001, 0) --Track: Insert new track
                    else
                        hideShowEverything(track, everythingsIsNotMinimized)
                    end
                end 
            end
            
            --[[reaper.ImGui_SetCursorPos(ctx, x, y + offset)
            if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything", widthOfTrackName, true,false,nil,true,24 ) then 
                hideShowEverything(track, everythingsIsNotMinimized)
            end]]
            
            local posX, posY = getIconPosToTheLeft(vertical, 24, screenPosX, screenPosY, height)
            reaper.ImGui_SetCursorScreenPos(ctx, posX, posY)
            --reaper.ImGui_SetCursorPos(ctx, x, y + elementsHeightInHorizontal - 20 -24)
            if specialButtons.cogwheel(ctx, "settings", 24, settingsOpen, "Show app settings", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow) then
                settingsOpen = not settingsOpen
            end
            
            
            if settings.showScriptPerformance then
                local x1, y1 = reaper.ImGui_GetItemRectMax(ctx)
                reaper.ImGui_DrawList_AddText(draw_list, x1 - 24,y1-2,colorTextDimmed, scriptPerformanceText2)
            end
            
            
            
            --reaper.ImGui_SetCursorPos(ctx, x +20, y + 20)
            reaper.ImGui_EndGroup(ctx)
            
            placingOfNextElement(settings.vertical and 8 or 4)
            drawSeperator()
            placingOfNextElement(4)
        end
        
        
        
        
        --
        
        
        
        
        function drawSeperator(color)
            local vertical = settings.vertical
            local posX, posY = reaper.ImGui_GetCursorScreenPos(ctx)
            color = color and color or settings.colors.modulatorBorder & 0xFFFFFF66
            reaper.ImGui_DrawList_AddLine(draw_list, (vertical and winX or posX-2), vertical and posY - 2 or winY,(vertical and winX + winX or posX-2), vertical and posY - 2 or winY + winH, color, 1)
            return posX, posY
        end
        
        
        
        function topChildOfPanel(title, width, height, heightAutoAdjust, fixedSize)
            local flags =  reaper.ImGui_ChildFlags_Border()
            local flags =  reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeX() | reaper.ImGui_ChildFlags_AutoResizeY() | reaper.ImGui_ChildFlags_Border()
            local visible = reaper.ImGui_BeginChild(ctx, title, width, (heightAutoAdjust and not fixedSize) and 0 or height,flags, reaper.ImGui_WindowFlags_NoScrollWithMouse() | reaper.ImGui_WindowFlags_NoScrollbar() | scrollFlags)
            return visible
        end
        
        
        function bodyChildOfPanel(title, headerSize, margin, vertical, useBorder, fixedSize, bodyWidth, bodyHeight)
            if headerSize then
                if vertical then
                    reaper.ImGui_SetCursorPos(ctx, margin, headerSize+margin) 
                else
                    reaper.ImGui_SetCursorPos(ctx, headerSize+margin, margin) 
                    --reaper.ImGui_Dummy(ctx, 20,20) 
                    --reaper.ImGui_SetCursorPos(ctx, headerSize+margin, margin) 
                end
            end
            
            
            local flags = reaper.ImGui_ChildFlags_None()
            if not fixedSize then
                flags = flags | reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeX() | reaper.ImGui_ChildFlags_AutoResizeY()
            end
            if useBorder then
                flags = flags | reaper.ImGui_ChildFlags_Border()
            end
            local windowFlags = reaper.ImGui_WindowFlags_None()
            if not fixedSize then
                windowFlags = windowFlags | reaper.ImGui_WindowFlags_NoScrollWithMouse() | reaper.ImGui_WindowFlags_NoScrollbar()
            else
                --windowFlags = windowFlags | reaper.ImGui_WindowFlags_NoScrollbar()
                windowFlags = windowFlags | reaper.ImGui_WindowFlags_HorizontalScrollbar()
            end
            return reaper.ImGui_BeginChild(ctx, title, bodyWidth, bodyHeight, flags, windowFlags) 
        end
        
        function scrollChildOfPanel(title, width, scrollAreaHeight, heightAutoAdjust)
            if heightAutoAdjust then reaper.ImGui_SetNextWindowSizeConstraints(ctx, 30, 30, width, scrollAreaHeight) end
            local flags =  reaper.ImGui_ChildFlags_AlwaysAutoResize() | reaper.ImGui_ChildFlags_AutoResizeX() | reaper.ImGui_ChildFlags_AutoResizeY()
            return reaper.ImGui_BeginChild(ctx, "parametersForFocused", width, not heightAutoAdjust and scrollAreaHeight or nil, flags, scrollFlags)
        end
        
        function setCursorAfterHeader(vertical, width, height, offset)
            offset = offset and offset or 0
            if vertical then
                reaper.ImGui_SetCursorPos(ctx, 6, 20+6 + offset) 
                height = height - 26
                width = width - 10
            else
                width = width - 20 - 8
                height = height - 10
                reaper.ImGui_SetCursorPos(ctx, 20+6 + offset, 6)
            end
            
            return width, height
        end
        
        
        
            
            
            function getIfPluginShouldBeShown(folderClosed, track, f, i, trackFxTableWithIndentIndicators, hideUsingSelectors)
                local guid = GetFXGUID(track, f.fxIndex)
                local isFolderClosed = (f.isContainer and trackSettings.closeFolderVisually and trackSettings.closeFolderVisually[guid])
                
                --if (settings.includeModulators) or (not settings.includeModulators and (not f.isModulator)) then
                --if (beginDragAndDropFX and (not f.isModulator or (f.fxIndex == modulationContainerPos))) or (not f.isModulator and (settings.showContainers or (not settings.showContainers and not f.isContainer))) then
                local showPlugin 
                showPlugin = (settings.includeModulators or not f.isModulator) and (settings.showContainers or (not settings.showContainers and not f.isContainer))
                
                if f.isSelector or f.isCurver then
                    showPlugin = false
                    --reaper.ShowConsoleMsg(f.name .. " - " .. tostring(f.isSelectorIndexNumber) .. " hej\n")
                elseif hideUsingSelectors and f.isSelectorIndex and f.isSelectorIndexNumber then 
                    if GetParam(track, f.isSelectorIndex, 5) == 1 then
                        showPlugin = GetParam(track, f.isSelectorIndex, f.isSelectorIndexNumber + 5) > 0 
                        if not showPlugin and f.isContainer then
                            isFolderClosed = true
                        end
                    end
                end
                
                
                
                
                local fxInClosedFolderCount = 0
                if folderClosed then 
                    
                    if folderClosedFX.indent >= f.indent and not f.seperator  then
                        folderClosed = false 
                        --fxInClosedFolderCount = 0
                    end
                    
                    if f.indent > folderClosedFX.indent and not f.seperator then 
                        showPlugin = false 
                    else
                    end
                    
                    if f.isModulator and (f.indent > 0 or f.isContainer) and not f.seperator then
                        showPlugin = false
                    end
                end 
                
                if settings.showContainers and isFolderClosed and not folderClosed then
                    folderClosed = true
                    folderClosedFX = f
                    --fxInClosedFolderCount = 0
                    for i2, f2 in ipairs(trackFxTableWithIndentIndicators) do  
                        if i2 > i then
                            if folderClosedFX.indent >= f2.indent then
                               break;
                            end
                            
                            if f2.indent > folderClosedFX.indent and not f2.seperator then  
                                fxInClosedFolderCount = fxInClosedFolderCount + 1
                            end
                            
                            if f2.isModulator and (f2.indent > 0 or f2.isContainer) and not f2.seperator then
                                fxInClosedFolderCount = fxInClosedFolderCount + 1
                            end
                        end 
                    end 
                end
                return folderClosed, showPlugin, isFolderClosed, fxInClosedFolderCount
            end
            
            --modulatorsW = settings.vertical and elementsWidthInVertical or (winW-x-30)
            
            --local tableWidth = settings.vertical and elementsWidthInVertical or settings.pluginsWidth
            function drawSeperatorAndAddPlacementOfNextPanel(nextElementIsThere, childPosSize, vertical, heightAutoAdjust, widthOfPrevieusElement, heightOfPrevieusElement)
                if nextElementIsThere then
                   placingOfNextElement(5) 
                   drawSeperator(settings.colors.modulatorBorder & 0xFFFFFF55)
                   childPosSize = vertical and (heightAutoAdjust and reaper.ImGui_GetCursorPosY(ctx) or heightOfPrevieusElement) or widthOfPrevieusElement
                end
                return childPosSize
            end
            
            
            function pluginsList(title, width, height, offset, vertical, heightAutoAdjust) 
                --reaper.ImGui_SetNextWindowSizeConstraints(ctx, 30, 30, width, height)
                
                --if reaper.ImGui_BeginChild(ctx, 'PluginsChild1', width, nil, reaper.ImGui_ChildFlags_AutoResizeY(), reaper.ImGui_WindowFlags_NoScrollWithMouse() | reaper.ImGui_WindowFlags_NoScrollbar()) then 
                if bodyChildOfPanel(title .. "body", offset, 6, vertical, true) then
                    
                    --width = width - (vertical and 0 or 20)
                    --height = height - (vertical and 20 or 0)
                    --width = width - 14
            
                    if settings.showPluginOptionsOnTop then
                        openAllAddTrackFX(width)
                    end
                    local _, offsetY = reaper.ImGui_GetCursorScreenPos(ctx)
                    
                    local beginFxDragAndDropNameExtension = ""
                    local beginFxDragAndDropHoverIndex
                    local dropAllowed
                    
                    
                    --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), colorAlmostBlack)
                    
                    local pluginFlags = reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_NoPadOuterX()
                    if settings.allowHorizontalScroll then
                        pluginFlags = pluginFlags | reaper.ImGui_TableFlags_ScrollX()
                    end
                    -- USE FOR DEBUGGIN
                    --pluginFlags = pluginFlags | reaper.ImGui_TableFlags_Borders()
                    
                    local columnAmount = (settings.showPluginNumberColumn) and 2 or 1
                    --local columnAmount = (settings.showPluginNumberColumn and settings.showPluginsPanel) and 2 or 1
                    
                    local openPluginOnSingleClick = settings.openPluginWhenClickingName
                    --local openPluginOnSingleClick = settings.openPluginWhenClickingName or not settings.showPluginsPanel
                    
                    local offset = settings.showOpenAll or settings.showAddTrackFX or settings.showAddTrackFXDirectly or settings.showAddContainer
                    local dragAndDropInside = false
                    local lastIndent = 0
                    local alreadyDragAndDrop = false 
                    local minX, minY, maxX, maxY
                    
                    --local tableMinX, tableMinY = reaper.ImGui_GetCursorScreenPos(ctx) 
                    --local copyFX = false
                    local scrollAreaHeight = height - (offset and 42 or 12)
                    
                    local scrollAreaHeightFixed = (not vertical or settings.alwaysUsePluginsHeight) and scrollAreaHeight or nil
                    local childFlag = (not vertical or settings.alwaysUsePluginsHeight) and reaper.ImGui_ChildFlags_None() or reaper.ImGui_ChildFlags_AutoResizeY()
                    
                    --reaper.ImGui_SetNextWindowSizeConstraints(ctx, 30, 0, width, scrollAreaHeight)
                    --if reaper.ImGui_BeginChild(ctx, "parametersForFocused", width, scrollAreaHeightFixed, childFlag, scrollFlags) then
                    
                    if scrollChildOfPanel(title .. "scroll", width - 12, scrollAreaHeight, heightAutoAdjust) then
                        
                        if reaper.ImGui_BeginTable(ctx, 'PluginsTable',columnAmount, pluginFlags, nil, not heightAutoAdjust and scrollAreaHeight or nil) then -- (offset and (height -  64) or 0)) then
                            
                            
                            --ImGui.TableHeadersRow(ctx)
                            
                            if columnAmount > 1 then
                                ImGui.TableSetupColumn(ctx, 'one', reaper.ImGui_TableColumnFlags_WidthFixed(), 16)--settings.elementsWidthInVertical-60) -- Default to 100.0
                                ImGui.TableSetupColumn(ctx, 'two', reaper.ImGui_TableColumnFlags_WidthFixed(), width-20)--settings.elementsWidthInVertical-60) -- Default to 100.0
                            
                            --ImGui.TableSetupColumn(ctx, 'two', ImGui.TableColumnFlags_WidthFixed, 20.0) -- Default to 200.0
                                reaper.ImGui_TableSetupScrollFreeze(ctx, 1,0)
                            end
                            
                            --reaper.ImGui_TableNextColumn(ctx)
                            local count = 0
                            local lastDropAllowed = true
                            
                            local showExtra = true
                            local lastFxIndex 
                            
                            local containerFound = false
                            local countDragAmount = 0
                            local folderClosed = false
                            --local fxInClosedFolderCount = 0
                            local stopFolderClosingAfter = 0
                            for i, f in ipairs(trackFxTableWithIndentIndicators) do  
                                dropAllowed = true
                                partOfContainer = false
                                
                                
                                
                                folderClosed, showPlugin, isFolderClosed, fxInClosedFolderCount = getIfPluginShouldBeShown(folderClosed, track, f, i, trackFxTableWithIndentIndicators)
                                
                                --showPlugin = not isFolderClose
                                if (showPlugin) then
                                    
                                    local isEnabled = GetFXEnabled(track, f.fxIndex)
                                    local isOffline = GetFXOffline(track, f.fxIndex)
                                    
                                    
                                    
                                    local currentIndent = f.indent
                                    
                                    --local name = (isEnabled and "" or "[B]") .. (f.simpleName and f.simpleName or f.name)
                                    local name = (f.simpleName and f.simpleName or f.name)
                                    local moveIndentName = "<"
                                    
                                    --name = name .. "(" .. f.fxIndex .. "/" .. f.dropIndex .. ")"
                                    if f.isContainer then 
                                        name = "[" ..name .. "]" 
                                        if isFolderClosed then
                                            name = name .. "[" .. fxInClosedFolderCount .. "]"
                                        end
                                    end
                                    
                                    if settings.showParallelIndicationInName then
                                        local parallel = getFXParallelProcess(track, f.fxIndex)
                                        name = (parallel == 0 and "" or (parallel == 1 and "[P]" or "[PM]")) .. name
                                    end
                                    
                                    --if f.isContainer then name = name .. ":" end
                                        
                                    local indentType = settings.identsType and "." or " "
                                    local indentStr = string.rep(" ", settings.indentsAmount)
                                    indentStr = settings.identsType and "|" .. indentStr:sub(0,-2) or indentStr
                                    --local indentStrFolder = string.rep(indentType, settings.indentsAmount)
                                    
                                    if f.indent and f.indent > 0 then 
                                        --if f.isContainer then 
                                        --    name = string.rep(indentStr, f.indent) .. name 
                                        --else
                                        
                                        if settings.indentsAmount > 0 then
                                            name = string.rep(indentStr, f.indent) ..  name  
                                        end
                                            
                                        --end
                                    end
                                    
                                    local isFocused = tonumber(fxnumber) == tonumber(f.fxIndex)
                                    --isFocused =  settings.showPluginNumberColumn and isFocused or true
                                    --if not settings.showPluginNumberColumn or not settings.showPluginsPanel then
                                    if not settings.showPluginNumberColumn then
                                        isFocused = f.isOpen
                                    end
                                    
                                    local indent = f.isContainer and f.indent + 1 or f.indent
                                    local indentW = indent > 0 and reaper.ImGui_CalcTextSize(ctx, string.rep(indentStr, indent), 0,0) or 0
                                    
                                    if beginFxDragAndDrop then 
                                        copyFX = beginFxDragAndDropIndex ~= modulationContainerPos and isCopyFX
                                        
                                        if beginFxDragAndDropIndex == f.fxIndex then --or beginFxDragAndDropIndex == f.dropIndex  then
                                            dropAllowed = false
                                            partOfContainer = true
                                        end
                                        
                                        if beginFxDragAndDropFX.isContainer then  
                                            if containerFound then 
                                                if beginFxDragAndDropFX.indent >= f.indent  then
                                                    containerFound = false
                                                else 
                                                    dropAllowed = false
                                                    partOfContainer = true
                                                    countDragAmount = countDragAmount + 1
                                                end
                                            end 
                                            
                                            if beginFxDragAndDropIndex == modulationContainerPos and (f.indent > 0 or f.isContainer) then 
                                                dropAllowed = false
                                            end
                                            
                                            if f.isModulator and (f.indent > 0 or f.isContainer) then
                                                dropAllowed = false
                                            end
                                        
                                            if beginFxDragAndDropFX.fxIndex == f.fxIndex then
                                                containerFound = true
                                            end
                                            
                                        end
                                    end
                                    
                                    if f.seperator then  
                                        if i == 1 then
                                            reaper.ImGui_TableNextRow(ctx)
                                            reaper.ImGui_TableNextColumn(ctx)
                                            if columnAmount > 1 then  
                                                reaper.ImGui_TableNextColumn(ctx)
                                            end
                                        end
                                        
                                        minX, minY = reaper.ImGui_GetCursorScreenPos(ctx)
                                        maxY = minY + 10 
                                        maxX = width + minX - indentW - 16
                                        if mouse_pos_y_imgui > minY -10 and mouse_pos_y_imgui < minY +10 then
                                            if beginFxDragAndDrop then 
                                                if dropAllowed and beginFxDragAndDropIndex ~= f.dropIndex then
                                                --if beginFxDragAndDropIndex ~= f.fxIndex or beginFxDragAndDropIndex ~= f.dropIndex then
                                                    -- TODO: This could be a better system how to show the spacing, now it's just on pixels of the mouse 
                                                    
                                                    reaper.ImGui_Spacing(ctx)
                                                    local _, maxY = reaper.ImGui_GetCursorScreenPos(ctx)
                                                    local maxX = width + minX
                                                    dragDropInArea(minX,minY,maxX,maxY,f, indentW)  
                                                end
                                            else 
                                                --if f.indent > 0 then reaper.ImGui_Indent(ctx, indentW) end
                                                --reaper.ImGui_Separator(ctx)
                                                --if f.indent > 0 then reaper.ImGui_Unindent(ctx, indentW) end 
                                            end
                                        end
                                        
                                        --reaper.ImGui_Text(ctx, name)
                                    else
                                        
                                        count  = count  + 1
                                        reaper.ImGui_TableNextRow(ctx)
                                        reaper.ImGui_TableNextColumn(ctx)
                                        
                                        
                                        
                                        
                                        if columnAmount > 1 then
                                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), f.isFloating and settings.colors.pluginOpen or settings.colors.pluginOpenInContainer)
                                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), isFocused and colorText or colorTextDimmed)
                                            local buttonTitle = f.isContainer and (not isFolderClosed and " - " or " + ") or ((isFocused) and ">" or (settings.showPluginNumberInPluginOverview and count or ""))
                                            --local buttonTitle = f.isContainer and (not isFolderClosed and " - " or " + ") or ((isFocused and settings.showPluginsPanel) and ">" or (settings.showPluginNumberInPluginOverview and count or ""))
                                            if reaper.ImGui_Selectable(ctx, buttonTitle .. '##' .. f.fxIndex, f.isOpen ,reaper.ImGui_SelectableFlags_AllowDoubleClick()) then 
                                                
                                                
                                                fxnumber = f.fxIndex
                                                paramnumber = 0 
                                                focusedFxNumber = f.fxIndex 
                                                
                                                if f.isContainer then
                                                    clickPlugin(f, true, true)
                                                else
                                                    if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                                        if openPluginOnSingleClick then
                                                            clickPlugin(f) 
                                                        end
                                                    else 
                                                        clickPlugin(f, openPluginOnSingleClick)
                                                    end
                                                end
                                                
                                            end  
                                            setToolTipFunc(getButtonToolTipText(f)[openPluginOnSingleClick and 2 or 1])
                                            reaper.ImGui_PopStyleColor(ctx, 2)
                                            reaper.ImGui_TableNextColumn(ctx) 
                                        end
                                        
                                        --if reaper.ImGui_Checkbox(ctx, "##FXOpen" ..i, f.isOpen) then 
                                        --    openCloseFx(track, f.fxIndex, not f.isOpen)
                                        --end
            
                                        
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),beginFxDragAndDrop and colorTransparent or colorButtonsActive)
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),beginFxDragAndDrop and colorTransparent or colorButtonsHover & 0xFFFFFFFF55)
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),beginFxDragAndDrop and colorTransparent or colorButtons)
                                        
                                        
                                        if not settings.showPluginNumberColumn then
                                        --if not settings.showPluginNumberColumn or not settings.showPluginsPanel then
                                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), beginFxDragAndDrop and colorTransparent or (f.isFloating and settings.colors.pluginOpen or settings.colors.pluginOpenInContainer))
                                        end
                                        
                                        
                                        
                                        local textColor = getTextColorForFx(track, f, true)
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), textColor)
                                        
                                        
                                        minX, minY = reaper.ImGui_GetCursorScreenPos(ctx)  
                                        minX = minX - 4
                                        minY = minY -4
                                        
                                        
                                        if reaper.ImGui_Selectable(ctx, name .. '##' .. f.fxIndex, isFocused ,reaper.ImGui_SelectableFlags_AllowDoubleClick()) then 
                                            if not beginFxDragAndDrop then
                                                 fxnumber = f.fxIndex
                                                 paramnumber = 0 
                                                 focusedFxNumber = f.fxIndex 
                                                 openTag = (not openPluginOnSingleClick and reaper.ImGui_IsMouseDoubleClicked(ctx, 0)) or openPluginOnSingleClick
                                                    
                                                 clickPlugin(f, not openTag)
                                            end
                                        end 
                                        
                                        reaper.ImGui_PopStyleColor(ctx, 1)
                                        
                                        _, maxY = reaper.ImGui_GetCursorScreenPos(ctx)
                                        selW, selH = reaper.ImGui_GetItemRectSize(ctx)
                                        maxX = minX + selW - 4--width - indentW - 16
                                        
                                        
                                        registrerDragAndDrop(minX,minY,maxX,maxY,f)  
                                        if dropAllowed and beginFxDragAndDrop and beginFxDragAndDropIndex ~= f.dropIndex then
                                            dragDropInArea(minX,minY,maxX,maxY,f, indentW) 
                                        end
                                        
                                        reaper.ImGui_PopStyleColor(ctx, 3)
                                        if not settings.showPluginNumberColumn then
                                        --if not settings.showPluginNumberColumn or not settings.showPluginsPanel then
                                            reaper.ImGui_PopStyleColor(ctx, 1)
                                        end
                                        setToolTipFunc(getButtonToolTipText(f)[openPluginOnSingleClick and 3 or 4])
                                        
                                        -- IS THIS USED
                                        if scrollPlugin and tonumber(f.param) == tonumber(scrollPlugin) then
                                            reaper.ImGui_SetScrollHereY(ctx, 0)
                                            scrollPlugin = nil
                                        end
                                        lastIndent = currentIndent
                                    end
                                end
                            end
                             
                            
                            reaper.ImGui_EndTable(ctx)
                            
                            
                            if beginFxDragAndDrop and beginFxDragAndDropName then -- and beginDragAndDropFXIndex ~= f.fxIndex then
                                reaper.ImGui_BeginTooltip(ctx)
                                reaper.ImGui_Text(ctx, (copyFX and "Copy: " or "Move: ") ..  beginFxDragAndDropName .. (countDragAmount > 0 and " [+" .. countDragAmount .. "]" or "") .. beginFxDragAndDropNameExtension)
                                reaper.ImGui_EndTooltip(ctx)
                                --reaper.ShowConsoleMsg("drag\n")  
                            end
                        end
                        
                        reaper.ImGui_EndChild(ctx)
                    end  
                    
                    
                    --_, tableMaxY = reaper.ImGui_GetCursorScreenPos(ctx)
                    --tableMaxX = tableMinX + width - 16
                    
                    
                    
                    --if beginDragAndDropFX then
                        
                    --end
                    
                    
                    
                    
                    if not settings.showPluginOptionsOnTop then
                        openAllAddTrackFX(width)
                    end
            
                    reaper.ImGui_EndChild(ctx)
                
                end
            end
            
            
            
            function pluginParametersPanel(track, fxIndex, isCollabsed, vertical, widthFromParent, heightFromParent, collabsedOverwrite, f, showOnlyFocusedPlugin)
                --
                local vertical = vertical ~= nil and vertical or settings.vertical
                local guid = GetFXGUID(track, fxIndex)
                local isCollabsed = (guid ~= "" and not collabsedOverwrite) and trackSettings.hidePluginSearchParameters[guid] or false
                
                local isContainer = f and f.isContainer
                local isSelectorContainer = f and f.isSelectorContainer
                if isContainer and not showOnlyFocusedPlugin and not isSelectorContainer then  
                    isCollabsed = true
                end
                
                if isSelectorContainer then
                    isCollabsed = trackSettings.closeFolderVisually[guid]
                end
                
                local width = vertical and widthFromParent or (isCollabsed and headerSizeW or settings.parametersWidth)
                local height = vertical and (isCollabsed and headerSizeW or settings.parametersHeight) or heightFromParent
                local heightAutoAdjust = not isCollabsed and vertical and not settings.alwaysUseParametersHeight
                
                vertical = not isCollabsed and settings.preferHorizontalHeaders or vertical
                --local seachWidth = width - (vertical and 0 or headerSizeW)
                --local moduleWidth = width - 14 - (vertical and 0 or headerSizeW)
            
                
                local title = "- no fx selected -"
                title = (validateTrack(track) and fxIndex) and GetFXName(track, fxIndex) or title -- Get the FX name'
                title = fxSimpleName(title)
                
                if isContainer then 
                    title = "[" ..title .. "]" 
                    if f.isFolderClosed then
                        title = title .. " [" .. f.fxInClosedFolderCount .. "]"
                    end
                end
                    --title = title .. " [Switch]"
                -- we could set the color based on the focused FX
                
                local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                
                --reaper.ImGui_SetNextWindowSizeConstraints(ctx, headerSizeW, headerSizeW, width, height)
                
                
                local panelName = 'Parameters' .. (showOnlyFocusedPlugin and "" or fxIndex)
                
                if not fxIndex then
                    if topChildOfPanel(panelName, width, height, heightAutoAdjust) then
                        reaper.ImGui_Text(ctx, "No fx on track")      
                        
                        reaper.ImGui_EndChild(ctx)
                    end
                    return
                end
                
                if topChildOfPanel(panelName, width, height, heightAutoAdjust) then
                
                    
                
                
                    --reaper.ImGui_InvisibleButton(ctx, "dummy", 20 ,20) 
                    
                    local headerW = vertical and width or headerSizeW
                    local headerH = vertical and headerSizeW or height  
                    local headerAreaRemoveTop = 20
                    if settings.showWetKnobOnPlugins then
                        headerAreaRemoveTop = headerAreaRemoveTop + 20
                    end
                    local headerAreaRemoveBottom = isContainer and 0 or 20 
                    
                    
                    
                    local headerTextX, headerTextY, headerTextW, headerTextH, align, bgX, bgW = getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)
                    
                    
                    drawHeaderBackground(screenPosX, screenPosY, screenPosX + headerW, screenPosY + headerH, isCollabsed, vertical, settings.colors.backgroundWidgetsHeader, settings.colors.backgroundWidgetsBorder)
                     
                    local isEnabled = GetFXEnabled(track, fxIndex)
                    local isOffline = GetFXOffline(track, fxIndex)
                    
                    local textColor = getTextColorForFx(track, f, true)
                    
                    if drawHeaderTextAndGetHover(title, headerTextX, headerTextY, headerTextW, headerTextH, isCollabsed, vertical, 0, "Right click for more options", textColor, align, bgX, bgW) then
                        if isMouseClick then 
                            if isContainer then 
                                openCloseFolder(track, fxIndex)
                            else
                                if clickPlugin(getFxInfoAsObject(track, fxIndex), true) then
                                    trackSettings.hidePluginSearchParameters[guid] = not trackSettings.hidePluginSearchParameters[guid]
                                    saveTrackSettings(track) 
                                end
                            end
                        elseif isMouseClickRightImgui then
                            if isContainer then
                                --popupAlreadyOpen = true
                                reaper.ImGui_OpenPopup(ctx, 'container##' .. fxIndex)  
                            end
                        end
                        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            trackSettings.hidePluginSearchParameters[guid] = not trackSettings.hidePluginSearchParameters[guid]
                            saveTrackSettings(track) 
                        end
                    end
                    
                    
                    function updateSelectorContainer(f)
                        for i, fxi in ipairs(f.selectorChildren) do 
                            mapActiveParam = i + 5
                            local wetParam = GetNumParams(track, fxi) - 2
                            setParamaterToLastTouched(track, f.isSelectorIndexForParent, f.isSelectorIndexForParent, fxi, wetParam, 0, 0, 1) 
                            
                            -- ensure that wet params are not written mapped to the folder
                            local root_index, root_param = fx_get_mapped_parameter_with_catch(track,  fxi, wetParam)
                            if root_index and root_param then
                                 deleteParameterFromContainer(track, root_index, root_param)
                            end
                        end 
                        SetParam(track, f.isSelectorIndexForParent, 1, #f.selectorChildren)
                        SetParam(track, f.isSelectorIndexForParent, 0, GetParam(track, f.isSelectorIndexForParent, 0)) 
                        
                        mapActiveParam = nil
                        reloadSelector = false
                    end
                    
                    
                    function removeSelector(f)
                        for i, fxi in ipairs(f.selectorChildren) do  
                            local wetParam = GetNumParams(track, fxi) - 2 
                            SetParam(track, fxi, wetParam, 1)
                        end 
                        DeleteFX(track, f.isSelectorIndexForParent)
                    end
                    
                    function addSelector(fxIndex) 
                        local fxnumber = addFxAfterSelection(track, fxIndex, "JS: Container Selector Expansion") 
                        local rename = SetNamedConfigParm( track, fxnumber, 'renamed_name', "Selector" )
                        newSelectorAdded = true
                    end
                    
                    --popupOpen["container" .. fxIndex] = reaper.ImGui_IsPopupOpen(ctx, 'container##' .. fxIndex)
                    --if popupOpen[buttonId] then 
                    if reaper.ImGui_BeginPopup(ctx, 'container##' .. fxIndex) then 
                        if reaper.ImGui_BeginMenu(ctx, "Set container color") then
                            local indent = f.indent and f.indent + (f.isContainer and 1 or 0) or 0
                            local containerColor = (trackSettings.containerColors and trackSettings.containerColors[guid]) and trackSettings.containerColors[guid] or indentColors[(indent)%3 + 1] 
                            local ret, col = reaper.ImGui_ColorPicker4(ctx, "##ContainerColor", containerColor)
                            if ret and col then
                                --popupAlreadyOpen = false
                                trackSettings.containerColors[guid] = col
                                saveTrackSettings(track)
                                if isCloseColorSelectionOnClick then
                                    reaper.ImGui_CloseCurrentPopup(ctx)
                                end
                            end
                            reaper.ImGui_EndMenu(ctx)
                        end
                        
                        
                        
                        --ret, trackSettings.selectorContainer[guid] = reaper.ImGui_Checkbox(ctx, "Selector container",trackSettings.selectorContainer[guid])
                        local buttonText = f.isSelectorContainer and "Remove as selector" or "Convert to selector"
                        if reaper.ImGui_Button(ctx, buttonText) then
                            if f.isSelectorContainer then
                                removeSelector(f)
                            else
                                addSelector(fxIndex)
                            end
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        reaper.ImGui_EndPopup(ctx)
                    end
                    
                    
                    if not isContainer and guid then 
                        -- Most left
                        local posX, posY = getIconPosToTheLeft(vertical, 20, screenPosX, screenPosY, height)
                        if drawOpenSearch(posX, posY, 20, not isCollabsed, "Show list of all parameters from the plugin") then
                            trackSettings.hidePluginSearchParameters[guid] = not trackSettings.hidePluginSearchParameters[guid]
                            saveTrackSettings(track) 
                        end
                    end
                    
                    -- most right 
                    local posX, posY = getIconPosToTheRight(vertical, 20, screenPosX, screenPosY, width)
                    local isFxOpen = track and fxIndex and GetOpen(track, fxIndex) 
                    if drawOpenFXWindow(posX, posY, 20, isFxOpen, "window for FX") then
                        openCloseFx(track, fxIndex, not isFxOpen)
                    end
                    
                    if settings.showWetKnobOnPlugins then 
                        local posX, posY = getIconPosToTheRight(vertical, 40, screenPosX, screenPosY, width)
                        reaper.ImGui_SetCursorScreenPos(ctx, posX, posY)
                        pluginParameterSlider("parameter",getAllDataFromParameter(track,f.fxIndex,GetNumParams(track, f.fxIndex)-2),nil,nil,nil,nil,20,1,valueText,nil,true, nil, true, false, 0,1, "WetKnob")--, shownCount - 1, parameterColumnAmount)
                    end
                    
                    
                    -- set position and size of sub child, eg the search
                    
                    
                    function dummySlider(hasParameterMapping, useKnobs, useNarrow)
                        --local h = sliderHeight + 16
                        
                        local totalSliderHeight = showMappingText and sliderHeight + 16 + ((settings.showMappedModulatorNameBelow and hasParameterMapping) and 12 or 0) or sliderHeight + 16
                        if useNarrow and useKnobs then
                            totalSliderHeight = totalSliderHeight + 16
                        end
                        --h = h + ((settings.showMappedModulatorNameBelow and hasParameterMapping) and 12 or 0)
                        --reaper.ImGui_InvisibleButton(ctx,"dummy", 20, h)
                        reaper.ImGui_Dummy(ctx, 20, totalSliderHeight)
                    end
                    
                    if not isCollabsed then
                        
                        if bodyChildOfPanel(panelName .. "mid", 20, 6, vertical, false,false) then
                            width = width - 14 - (vertical and 0 or 20)
                            height = height - (vertical and 20 or 0)
                            
                            
                            if isSelectorContainer then  
                                local isSelectorIndex = f.isSelectorIndexForParent
                                
                                local selectorChildrenAmount = #f.selectorChildren
                                local roundValue, isFill
                                local isToggle = GetParam(track, isSelectorIndex, 2) == 1 
                                
                                if colorButton("SELECTOR", colorTextDimmed, colorTransparent, colorTransparent, colorTransparent, "Force updated mapping", colorText, width) then
                                    updateSelectorContainer(f)
                                end
                                
                                --centerText("SELECTOR", colorText, 0, width, 0, 0)
                                reaper.ImGui_BeginGroup(ctx)
                                local isManual = GetParam(track, isSelectorIndex, 3) == 0
                                
                                createSlider(track,isSelectorIndex,"Checkbox",2,"Toggle",nil,nil,1,nil,"TextOnSameLine",nil,nil,nil,nil, width,0,2)  
                                setToolTipFunc("Layers will be activated on or off")
                                
                                if not isManual then 
                                    createSlider(track,isSelectorIndex,"Checkbox",4,"Fill",nil,nil,1,nil,"TextOnSameLine",nil,nil,nil,nil, width,1,2) 
                                    setToolTipFunc("Fill up selection from the top to the selected layer")
                                    
                                    isFill = GetParam(track, isSelectorIndex, 4) == 1 
                                    local p = getAllDataFromParameter(track,isSelectorIndex,0)
                                    roundValue = math.ceil(math.floor(p.value*selectorChildrenAmount + 0.5)/100)
                                    --local roundValue =  math.max(isToggle and 0 or 1, math.ceil(math.floor(p.value*selectorChildrenAmount)/100))
                                    local valueText = roundValue--not isFill and roundValue or math.floor(p.value)
                                    pluginParameterSlider("parameter",p,nil,nil,nil,nil,width,0,valueText,nil,true, nil, true, false, 0,1)--, shownCount - 1, parameterColumnAmount)
                                else
                                    reaper.ImGui_Dummy(ctx, width, 1)
                                end
                                
                                createSlider(track,isSelectorIndex,"Checkbox",3,"Manual",nil,nil,1,nil,"TextOnSameLine",true,nil,nil,nil, width,0,2)
                                setToolTipFunc("Manually adjust what will be played")
                                createSlider(track,isSelectorIndex,"Checkbox",5,"Hide",nil,nil,1,nil,"TextOnSameLine",nil,nil,nil,nil, width,1,2)
                                setToolTipFunc("Hide non active layers")
                                
                                reaper.ImGui_EndGroup(ctx)
                                reaper.ImGui_Separator(ctx)
                                
                                -- create table if needed
                                if not lastSelectorContainer then lastSelectorContainer = {} end
                                if not lastSelectorContainer[isSelectorIndex] then lastSelectorContainer[isSelectorIndex] = {} end
                                if #lastSelectorContainer[isSelectorIndex] ~= #f.selectorChildren then lastSelectorContainer[isSelectorIndex] = {} end
                                
                                local updateContainerNow = false
                                
                                local pluginFlags = reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_NoPadOuterX()
                                if reaper.ImGui_BeginTable(ctx, "selector" .. fxIndex, isToggle and 1 or 2) then --, pluginFlags | reaper.ImGui_TableFlags_BordersInner(), nil, nil, reaper.ImGui_ChildFlags_AlwaysAutoResize()) then
                                    for i, fxi in ipairs(f.selectorChildren) do
                                        local sliderParam = i + 5
                                        --local fxName = GetFXName(track, fxi)
                                        local fxName, fxOriginalName, guid, containerCount, isContainer, isSelector, isEnabled, isOpen, isFloating, parallel = getNameAndOtherInfo(track, fxi, false) 
                                        if not lastSelectorContainer[isSelectorIndex][i] or lastSelectorContainer[isSelectorIndex][i] ~= guid then 
                                            updateContainerNow = true 
                                        end
                                        
                                        --[[
                                        reaper.ImGui_TableNextColumn(ctx)
                                            local isSelected = GetParam(track, f.isSelectorIndex, sliderParam) > 0
                                            if reaper.ImGui_RadioButton(ctx, "##selector" .. fxi, isSelected) then
                                                if isManual then
                                                    SetParam(track, f.isSelectorIndex, sliderParam, isSelected and 0 or 1)
                                                else 
                                                    SetParam(track, f.isSelectorIndex, 0, i * 100 / selectorChildrenAmount)
                                                end
                                            end
                                            reaper.ImGui_PopFont(ctx)
                                        else
                                        ]]
                                        if not isToggle then
                                            reaper.ImGui_TableNextColumn(ctx)
                                            reaper.ImGui_SetCursorPosX(ctx, 0)
                                            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx)-3)
                                            pluginParameterSlider("selector",getAllDataFromParameter(track,isSelectorIndex,sliderParam),nil,nil,nil,nil,20,1,valueText,nil,true, nil, true, false, 0,1, "WetKnob")--, shownCount - 1, parameterColumnAmount)
                                        end
                                        
                                        reaper.ImGui_TableNextColumn(ctx)
                                        
                                        local simpleName = fxSimpleName(fxName)
                                        local isSelected = false
                                        local selectedAmount = GetParam(track, isSelectorIndex, sliderParam)
                                        
                                        isSelected = selectedAmount > 0
                                        if isToggle then 
                                            --if isManual then
                                            --else
                                            --    isSelected = i == roundValue 
                                            --end
                                        end
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), colorButtons & (0xFFFFFF00+ math.ceil(0xFF * selectedAmount/100)))
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), colorButtons & (0xFFFFFF00+ math.ceil(0xFF * selectedAmount/100)))
                                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), colorButtons & (0xFFFFFF00+ math.ceil(0xFF * selectedAmount/100)))
                                        if reaper.ImGui_Selectable(ctx, simpleName .. "##" .. fxi, isSelected, reaper.ImGui_SelectableFlags_SpanAllColumns()) then
                                            if isManual then
                                                SetParam(track, isSelectorIndex, sliderParam, isSelected and 0 or 100)
                                            else 
                                                SetParam(track, isSelectorIndex, 0, i * 100 / selectorChildrenAmount)
                                            end
                                        end
                                        reaper.ImGui_PopStyleColor(ctx,3)
                                        
                                        lastSelectorContainer[isSelectorIndex][i] = guid
                                    end
                                    reaper.ImGui_EndTable(ctx)
                                end
                                
                                if updateContainerNow or (newSelectorAdded and lastSelectorContainer) or reloadSelector then
                                    --lastSelectorContainer[isSelectorIndex] = {}
                                    updateSelectorContainer(f)
                                    newSelectorAdded = false
                                    reloadSelector = false
                                end
                            else
                                local showOnlyMappedAndSearchOnFocusedPlugin = settings.showOnlyMappedAndSearchOnFocusedPlugin --and (showOnlyFocusedPlugin or settings.showParametersOptionOnAllPlugins)
                                local showLastClicked = settings.showLastClicked --and (settings.showOnlyFocusedPlugin or settings.showParametersOptionOnAllPlugins)
                                
                                -- the two splitter lines
                                local searchAreaH = ((showOnlyMappedAndSearchOnFocusedPlugin or showLastClicked) and (settings.showParameterOptionsOnTop and 10 or 8) or 0)
                                searchAreaH = searchAreaH + ((showOnlyMappedAndSearchOnFocusedPlugin) and 24 or 0)
                                local lastClickedAreaH = (showLastClicked and sliderHeight + 16 or 0)
                                lastClickedAreaH = lastClickedAreaH + ((showLastClicked and settings.showMappedModulatorNameBelow) and 12 or 0) --(showingLastClicked and 28 or 0)
                                
                                -- if we show the search area at the top
                                if settings.showParameterOptionsOnTop then
                                    searchAndOnlyMapped(track, fxIndex, lastClickedAreaH, width, showOnlyFocusedPlugin)
                                end
                                
                                
                                local paramsListThatAreNotFiltered = (track and fxIndex) and getFxParamsThatAreNotFiltered(track, fxIndex) or {}
                                local onlyMapped 
                                if showOnlyFocusedPlugin then
                                    onlyMapped = settings.onlyMapped
                                else
                                    onlyMapped = trackSettings.onlyMapped[guid]
                                end 
                                -- check if any parameters links a active, if not we show all of them
                                local someAreActive = false
                                if onlyMapped then
                                    for i, p in ipairs(paramsListThatAreNotFiltered) do
                                        if f.indent and f.indent > 0 then 
                                            local root_fxIndex, root_param = fx_get_mapped_parameter_with_catch(track, fxIndex, p)
                                            if root_fxIndex and root_param then
                                                someAreActive = true; break
                                            end
                                        else
                                            --someAreActive = true; break
                                            if getPlinkActive(track, fxIndex, p) then someAreActive = true; break end
                                        end
                                        
                                    end
                                end 
                                
                                -- we need this to know if we are in the scroll area or not
                                local startPosX, startPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                                
                                local scrollAreaHeight = height - searchAreaH - lastClickedAreaH - 16
                                
                                -- if mouse is outside the slider area we do not accidentially want to set any sliders
                                local doNotSetFocus = not mouseInsideArea(startPosX, startPosY, width, scrollAreaHeight)  
                                
                                -- we need the fx name for custom fx setups, like realearn track controls
                                local fxName = title--GetFXName(track, fxnumber)
                                
                                -- show the scroll area with found parameters
                                --reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 6)
                                
                                local parameterColumnAmount = settings.PluginParameterColumnAmount
                                if scrollChildOfPanel(panelName .. "Scroll", width + 8, scrollAreaHeight, heightAutoAdjust) then
                                    local shownCount = 0
                                    for i, p in ipairs(paramsListThatAreNotFiltered) do
                                        
                                        if not settings.limitAmountOfDrawnParametersInPlugin or shownCount <= settings.limitAmountOfDrawnParametersInPluginAmount + (settings.limitAmountOfDrawnParametersInPluginAmount%parameterColumnAmount) then
                                            local name = GetParamNameFromCustomSetting(track, fxIndex, p, "rename")
                                          
                                            local parameterLinkActive
                                            -- check if fx is inside a folder
                                            if f.indent and f.indent > 0 then 
                                                local root_fxIndex, root_param = fx_get_mapped_parameter_with_catch(track, fxIndex, p)
                                                if root_fxIndex and root_param then
                                                    parameterLinkActive = getPlinkActive(track, root_fxIndex, root_param) 
                                                end
                                            else
                                                parameterLinkActive = getPlinkActive(track, fxIndex, p) 
                                            end
                                            
                                            
                                            local pMappedShown = not settings.showOnlyMappedAndSearchOnFocusedPlugin or not someAreActive or not onlyMapped or (onlyMapped and parameterLinkActive)
                                            
                                            local pSearchShown = not settings.showOnlyMappedAndSearchOnFocusedPlugin or not trackSettings.searchParameters[guid] or trackSettings.searchParameters[guid] == "" or searchName(name, trackSettings.searchParameters[guid])
                                            
                                            local pTrackControlShown = true
                                            if fxName == "Track controls" and i > 35 then
                                                pTrackControlShown = false
                                            end 
                                            
                                            if pMappedShown and pSearchShown and pTrackControlShown then 
                                                shownCount = shownCount + 1
                                            --reaper.ImGui_Spacing(ctx)  
                                                local maxScrollBar = math.floor(reaper.ImGui_GetScrollMaxY(ctx))
                                                local modulatorParameterWidth = width - 12 + (maxScrollBar == 0 and 12 or 0)
                                                local scrollPos = reaper.ImGui_GetScrollY(ctx)
                                                local startPosY = reaper.ImGui_GetCursorPosY(ctx)
                                                
                                                
                                                modulatorParameterWidth = findModulationParameterWidth(parameterColumnAmount, modulatorParameterWidth)
                                                -- 456
                                                
                                                local useKnobs = settings.useKnobsPlugin
                                                local useNarrow = (settings.useKnobsPlugin == nil and not settings.useNarrowPlugin) and settings.useNarrow or settings.useNarrowPlugin
                                                
                                                if startPosY - scrollPos < scrollAreaHeight and (startPosY + sliderHeight + 16) - scrollPos > 0 then
                                                    pluginParameterSlider("parameter",getAllDataFromParameter(track,fxIndex,p),doNotSetFocus,nil,nil,nil,modulatorParameterWidth,nil,nil,nil,true, nil, useKnobs, useNarrow)--, shownCount - 1, parameterColumnAmount)
                                                else
                                                    dummySlider(parameterLinkActive, useKnobs, useNarrow)
                                                end
                                                
                                                samelineIfWithinColumnAmount(shownCount, parameterColumnAmount, modulatorParameterWidth)
                                            end
                                        end
                                    end
                                    reaper.ImGui_EndChild(ctx)
                                end
                                --reaper.ImGui_PopStyleVar(ctx)
                                
                                -- if we show the search area at the bottom
                                if not settings.showParameterOptionsOnTop then
                                    searchAndOnlyMapped(track, fxIndex, lastClickedAreaH, width, showOnlyFocusedPlugin)
                                end
                            end
                        
                            reaper.ImGui_EndChild(ctx)
                        end 
                    end
                    
                    reaper.ImGui_EndChild(ctx)
                end 
                --placingOfNextElement()
            end
            
            function singlePluginParameterPanelFocusFirstIfNeeded() 
                -- auto loads the first fx in to parameters window
                if focusedTrackFXNames and not fxnumber then
                    for i, f in ipairs(focusedTrackFXNames) do
                        if not f.isModulator then
                            fxnumber = f.fxIndex
                            break
                        end
                    end
                end 
            end
            
            
            
            function modulatorsParametersPanel(width_from_parent, height_from_parent)
                
                
                
                local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                local x,y = reaper.ImGui_GetCursorPos(ctx)
                --local modulatorsW = settings.vertical and elementsWidthInVertical or (winW-x-8)  
                --local modulatorsH = settings.vertical and 0 or elementsHeightInHorizontal 
                
                local modulatorsW = vertical and width_from_parent or (isCollabsed and headerSizeW or settings.modulatorsWidth)
                local modulatorsH = vertical and (isCollabsed and headerSizeW or settings.modulatorsHeight) or height_from_parent
                
                --modulatorsH = winH-y-30
                --local visible = ImGui.BeginChild(ctx, 'ModulatorsChilds', modulatorsW, modulatorsH, reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()| reaper.ImGui_ChildFlags_AutoResizeX(), reaper.ImGui_WindowFlags_HorizontalScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse())
                --local visible = reaper.ImGui_BeginTable(ctx, 'ModulatorsChilds', settings.vertical and 1 or #modulatorNames,nil, modulatorsW)
                --if visible then 
                    
                    local mouseInsideModulatorsArea = mouse_pos_x_imgui >= screenPosX and mouse_pos_x_imgui <= screenPosX + modulatorsW and mouse_pos_y_imgui >= screenPosY and mouse_pos_y_imgui <= screenPosY + modulatorsH
                    local allowAnyScroll = not isScrollValue
                    allowAnyScroll = allowAnyScroll and mouseInsideModulatorsArea
                    local allowScroll = (allowAnyScroll and not settings.vertical and settings.useVerticalScrollToScrollModulatorsHorizontally)
                    allowScroll = allowScroll and mouseInsideModulatorsArea 
                    allowScroll = (allowScroll and not settings.onlyScrollVerticalHorizontalOnTopOrBottom) or (allowScroll and (mouse_pos_y_imgui < screenPosY + 80 or mouse_pos_y_imgui > screenPosY + modulatorsH - 30))
                    allowScroll = (allowScroll and not settings.onlyScrollVerticalHorizontalScrollWithModifier) or (allowScroll and  isMatch(settings.modifierEnablingScrollVerticalHorizontal, modifierTable))
                    
                     
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
                    
                    local tableWidthCollabsed = 20
                    local tableHeightHorizontal = modulatorsH--winH- reaper.ImGui_GetCursorPosY(ctx) - 54 -- 8
                    local moduleWidth = settings.vertical and width_from_parent or settings.modulatorsWidth
                    
                    local addNewModulatorW = 16
                    local addNewModulatorHeight = settings.vertical and addNewModulatorW or tableHeightHorizontal 
                    local addNewModulatorWidth = settings.vertical and moduleWidth or addNewModulatorW 
                    
                    
                    if settings.showAddModulatorButtonBefore and (#modulatorNames > 0 or not settings.showAddModulatorButtonAfter) then
                        if titleButtonStyle("+##before", "Add new modulator", addNewModulatorWidth,true,false, addNewModulatorHeight ) then 
                            reaper.ImGui_OpenPopup(ctx, 'Add new modulator')  
                        end
                        placingOfNextElement(1)
                    end
                    
                    function getNameW()
                        reaper.ImGui_PushFont(ctx, font2)
                        local nameW = reaper.ImGui_CalcTextSize(ctx, name, 0,0) 
                        reaper.ImGui_PopFont(ctx)
                        return nameW
                    end
                    
                    function findWidthOfHeaderHorizontal(name, outputs, height)  
                        local nameW = getNameW()
                        local minimumTextWidthShown = 30
                        local rowsNeededForOutputHorizontal = tableHeightHorizontal - nameW - minimumTextWidthShown - 16 - #outputs * headerSizeWM - headerSizeW < 0 and math.ceil(#outputs / ((height - 2)/ headerSizeWM)) or 0
                        return headerSizeW + headerSizeWM * rowsNeededForOutputHorizontal
                    end
                    
                    function findWidthOfHeaderVertical(name, outputs, width) 
                        local nameW = getNameW()
                        local rowsNeededForOutputVertical = moduleWidth - nameW - 16 - #outputs * headerSizeWM - headerSizeW < 0 and math.ceil(#outputs / ((width - 2)/ headerSizeWM)) or 0
                        return headerSizeW + headerSizeWM * rowsNeededForOutputVertical
                    end
                    
                    if modulationContainerPos then 
                        ignoreRightClick = false
                        for pos, m in ipairs(modulatorNames) do   
                            if not m.isCurver then
                            --else
                                local isCollabsed = trackSettings.collabsModules[m.guid] 
                                local smallHeader = isCollabsed and not settings.vertical
                                local tableWidthCollabsedWith
                                
                                -- LOOK at this one again 
                                local modulatorWidth = settings.vertical and moduleWidth or (isCollabsed and headerSizeW or moduleWidth) 
                                --local modulatorWidth = settings.vertical and moduleWidth or (isCollabsed and findWidthOfHeaderHorizontal(m.name, m.output, tableHeightHorizontal) or moduleWidth) 
                                local modulatorHeight = settings.vertical and (isCollabsed and headerSizeW or settings.modulatorsHeight) or tableHeightHorizontal
                                --local modulatorHeight = settings.vertical and (isCollabsed and findWidthOfHeaderVertical(m.name, m.output, moduleWidth) or settings.modulatorsHeight) or tableHeightHorizontal
                                
                                modulatorsWrapped(modulatorWidth, modulatorHeight, m, isCollabsed, settings.vertical)
                                
                                local mappingHeight = vertical and settings.modulesHeightVertically or tableHeightHorizontal
                                if trackSettings.showMappings[m.guid] and #m.mappings > 0 then 
                                    placingOfNextElement(8)
                                    mappingsArea(moduleWidth, mappingHeight, m, settings.vertical,false, isCollabsed)   
                                end 
                                
                                
                                --if not settings.vertical then reaper.ImGui_SameLine(ctx) end
                                if pos < #modulatorNames then
                                    if settings.showAddModulatorButton then 
                                        placingOfNextElement(1)
                                        if titleButtonStyle("+##".. m.fxIndex, "Add new modulator", addNewModulatorWidth,true,false, addNewModulatorHeight ) then 
                                            insertFxOnFxIndex = m.fxIndex
                                            reaper.ImGui_OpenPopup(ctx, 'Add new modulator')  
                                        end
                                        placingOfNextElement(1)
                                    else
                                        placingOfNextElement(settings.widthBetweenWidgets)
                                    end
                                end
                            end
                        end  
                    end
                    
                    
                    placingOfNextElement(1)
                    
                    --if modulePartButton(title,  (everythingsIsNotMinimized and "Minimize" or "Maximize") ..  " everything", widthOfTrackName, true,false,nil,true,24,  settings.colors.buttonsSpecialHover ) then 
                    if settings.showAddModulatorButtonAfter then
                        if titleButtonStyle("+##after", "Add new modulator", addNewModulatorWidth,true,false, addNewModulatorHeight ) then 
                            reaper.ImGui_OpenPopup(ctx, 'Add new modulator')  
                        end
                    end
                    
                    if reaper.ImGui_BeginPopup(ctx, 'Add new modulator') then 
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), colorTransparent)
                        --if reaper.ImGui_BeginChild(ctx, "child of floating modules", nil, nil, reaper.ImGui_ChildFlags_AutoResizeX()| reaper.ImGui_ChildFlags_AutoResizeY() | reaper.ImGui_ChildFlags_AlwaysAutoResize()) then
                            
                            if modulesPanel(ctx, nil, "popup") then 
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
                        reaper.ImGui_PopStyleColor(ctx)
                        reaper.ImGui_EndPopup(ctx)
                    end
                    
                    
                    --reaper.ImGui_EndTable(ctx)
                    --ImGui.EndChild(ctx)
                --end
                
                --reaper.ImGui_PopStyleColor(ctx, 1)
                
                -- TODO: Do we need this?
                --reaper.ImGui_Text(ctx,"")
                --ImGui.EndGroup(ctx) 
            end
            
            function pluginsPanel() 
                --if reaper.ImGui_BeginChild(ctx, "pluginsPanel") then
                    if settings.showPluginsPanel then 
                        
                        local vertical = settings.vertical
                        
                        local showPluginsList 
                        if settings.showPluginsListGlobal then
                            showPluginsList  = settings.showPluginsList 
                        else
                            showPluginsList  = trackSettings.showPluginsList 
                        end
                        
                        local showPlugins
                        if settings.showPluginsGlobal then
                            showPlugins = settings.showPlugins 
                        else
                            showPlugins = trackSettings.showPlugins
                        end
                        local showOnlyFocusedPlugin
                        if settings.showPluginsGlobal then
                            showOnlyFocusedPlugin = settings.showOnlyFocusedPlugin 
                        else
                            showOnlyFocusedPlugin = trackSettings.showOnlyFocusedPlugin
                        end
                        
                        local showAddPluginsList = settings.showAddPluginsList
                        local isCollabsed = trackSettings.hidePlugins or (not showPluginsList and not showPlugins and not showAddPluginsList)
                        
                        local fixedSize = settings.pluginsPanelWidthFixedSize
                        local width = vertical and elementsWidthInVertical or (isCollabsed and headerSizeW or (fixedSize and settings.pluginsPanelWidth or nil))
                        local height = vertical and (isCollabsed and headerSizeW or (fixedSize and settings.pluginsPanelHeight or nil)) or elementsHeightInHorizontal
                        
                        -- instead of -12 we use -14 so in case we do fixed size, it still works
                        local width_child = elementsWidthInVertical - 14
                        local height_child = elementsHeightInHorizontal - 14
                        
                        local pluginsListWidth = vertical and elementsWidthInVertical - 14 or settings.pluginsWidth
                        local pluginsListHeight = vertical and settings.pluginsHeight or elementsHeightInHorizontal - 14
                        local heightAutoAdjust = not isCollabsed and not (not vertical or settings.alwaysUsePluginsHeight)
                        local childPosSize = 20
                        local childPosMargin = 0
                        local title = "Plugins"
                        click = false
                        
                        local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                    
                            
                        focusedTrackFXNames, trackFxTableWithIndentIndicators = getFocusedTrackFXAndContainerTable(track) 
                        -- 789
                        --reaper.ImGui_SetNextWindowSizeConstraints(ctx, headerSizeW, headerSizeW, width, height)
                        --local visible = reaper.ImGui_BeginChild(ctx, 'PLUGINS', width, nil, childFlags, reaper.ImGui_WindowFlags_NoScrollWithMouse() | reaper.ImGui_WindowFlags_NoScrollbar() | scrollFlags)
                        --if visible then
                        if topChildOfPanel(title, width, height, vertical and not isCollabsed, fixedSize) then 
                            
                            
                            local headerW = vertical and width or headerSizeW 
                            local headerH = vertical and headerSizeW or height 
                            
                            local headerW = vertical and width or headerSizeW
                            local headerH = vertical and headerSizeW or height  
                            local headerAreaRemoveTop = 40
                            local headerAreaRemoveBottom = 40 
                            
                            
                            headerTextX, headerTextY, headerTextW, headerTextH, align, bgX, bgW = getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)
                            
                            
                            drawHeaderBackground(screenPosX, screenPosY, screenPosX + headerW, screenPosY + headerH, isCollabsed, vertical, settings.colors.backgroundModulesHeader, settings.colors.backgroundModulesBorder)
                            
                            local toolTip = "Click to minimize plugins panel" -- "Right click for more options"
                            if drawHeaderTextAndGetHover(title, headerTextX, headerTextY, headerTextW, headerTextH, isCollabsed, vertical, 0, toolTip, colorText & 0xFFFFFF88, align, bgX, bgW) then
                                if isMouseClick then
                                    trackSettings.hidePlugins = not trackSettings.hidePlugins  
                                    saveTrackSettings(track) 
                                end
                            end 
                            
                            -- Most left
                            local posX, posY = getIconPosToTheLeft(vertical, 20, screenPosX, screenPosY, height)
                            if drawListIcon(posX, posY, 20, showPluginsList, "Show list view of plugins") then
                                if settings.showPluginsListGlobal then 
                                    settings.showPluginsList = not settings.showPluginsList  
                                    saveSettings() 
                                else
                                    trackSettings.showPluginsList = not trackSettings.showPluginsList  
                                    saveTrackSettings(track) 
                                end
                            end
                            
                            local hideAllFXPanelsOnNextClick = not showOnlyFocusedPlugin and showPlugins
                            local posX, posY = getIconPosToTheLeft(vertical, 40, screenPosX, screenPosY, height)
                            local tip = hideAllFXPanelsOnNextClick and "Hide all plugin panels" or (showOnlyFocusedPlugin and "Show all plugins as seperate panels" or "Show focused plugin panel")
                            if drawListHorizontalIcon(posX, posY, 20, not showOnlyFocusedPlugin, tip, showPlugins) then
                                
                                if hideAllFXPanelsOnNextClick then
                                    if settings.showPluginsGlobal then
                                        settings.showPlugins = not settings.showPlugins
                                        saveSettings()
                                    else 
                                        trackSettings.showPlugins = not trackSettings.showPlugins
                                        --settings.showOnlyFocusedPlugin = not settings.showOnlyFocusedPlugin
                                        saveTrackSettings()  
                                    end
                                else 
                                    if settings.showPluginsGlobal then
                                        settings.showPlugins = true
                                        settings.showOnlyFocusedPlugin = not settings.showOnlyFocusedPlugin
                                        saveSettings()
                                    else
                                        trackSettings.showPlugins = true
                                        trackSettings.showOnlyFocusedPlugin = not trackSettings.showOnlyFocusedPlugin
                                        saveTrackSettings(track) 
                                    end 
                                end
                                
                            end
                            
                            --[[
                            local posX, posY = getIconPosToTheLeft(vertical, 60, screenPosX, screenPosY, height)
                            if drawListArrayIcon(posX, posY, 20, settings.showAddPluginsList, "Show add plugins list") then
                                settings.showAddPluginsList = not settings.showAddPluginsList  
                                saveSettings() 
                            end]]
                            
                            
                            -- most right 
                            local posX, posY = getIconPosToTheRight(vertical, 20, screenPosX, screenPosY, width)
                            
                            local isFxOpen = track and getFXWindowOpen(track)
                            if drawOpenFXWindow(posX, posY, 20, isFxOpen, "FX window") then
                                SetOpen(track, fxnumber or 0, not isFxOpen, true)
                            end
                            
                            -- most right 
                            local posX, posY = getIconPosToTheRight(vertical, 40, screenPosX, screenPosY, width)
                            local tip = not reaper.ImGui_IsPopupOpen(ctx, "add popup", reaper.ImGui_PopupFlags_AnyPopup()) and "add FX popup" or nil
                            if drawPlusIcon(posX, posY, 20, false, tip) then
                                openAddFXPopupWindow = true
                            end
                            
                            -- set position and size of sub child, eg the search
                            --if vertical then
                                --reaper.ImGui_SetCursorPos(ctx, 6, 20+6) 
                            --    height = height - 26
                            --else
                            --    width = width - 26
                                --reaper.ImGui_SetCursorPos(ctx, 20+6, 6)
                            --end
                            -- 321
                            
                            
                            
                            
                            --[[
                            if settings.showAddPluginsList then 
                                --if bodyChildOfPanel(title .. "bodyList", childPosSize, 6, vertical) then
                                --reaper.ImGui_Dummy(ctx, 20,20)
                                
                                    pluginsListWidth, pluginsListHeight = setCursorAfterHeader(vertical, pluginsListWidth, pluginsListHeight)
                                    
                                    if scrollChildOfPanel(title .. "scroll", pluginsListWidth, pluginsListHeight, false) then
                                
                                        fxPresetsPanel(ctx)
                                        
                                        reaper.ImGui_EndChild(ctx)
                                    end
                                    
                                --    reaper.ImGui_EndChild(ctx)
                                --end
                                
                                childPosSize = childPosSize + drawSeperatorAndAddPlacementOfNextPanel(settings.showPluginsList or settings.showPluginsPanel, childPosSize, vertical, heightAutoAdjust, pluginsListWidth + 10, pluginsListHeight + 10)
                                
                            end
                            ]]
                            
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundWidgets)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.backgroundWidgets)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), settings.colors.backgroundWidgetsBorder)
                            
                            
                            if not isCollabsed and showPluginsList then
                                
                                 pluginsList(title, pluginsListWidth, pluginsListHeight, childPosSize, vertical, heightAutoAdjust) 
                                 
                                 placingOfNextElement(settings.widthBetweenWidgets)
                                 childPosSize = nil--childPosSize + drawSeperatorAndAddPlacementOfNextPanel(settings.showPluginsPanel, childPosSize, vertical, heightAutoAdjust, pluginsListWidth, pluginsListHeight)
                                 
                            end
                            
                            reaper.ImGui_PopStyleColor(ctx, 3) 
                            if not isCollabsed and showPlugins then
                                if bodyChildOfPanel(title .. "bodyParameters", childPosSize, 6, vertical, nil, fixedSize, vertical and width_child + 4 or nil, not vertical and height_child + 4 or nil) then
                                    -- fix for now
                                    if fixedSize then 
                                        --height_child = height_child - 2
                                    end
                                    
                                    --local hasScrollBar = settings.vertical and math.floor(reaper.ImGui_GetScrollMaxY(ctx)) > 0 or 
                                    -- has scroll bar horizotnal
                                    if not settings.vertical and math.floor(reaper.ImGui_GetScrollMaxX(ctx)) > 0 then 
                                        height_child = height_child - 8
                                    end
                                    
                                    if settings.vertical and math.floor(reaper.ImGui_GetScrollMaxY(ctx)) > 0 then 
                                        width_child = width_child - 8
                                    end
                                    
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundWidgets)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.backgroundWidgets)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), settings.colors.backgroundWidgetsBorder)
                                    
                                    --local showOnlyFocusedPlugin = settings.showOnlyFocusedPluginGlobal and settings.showOnlyFocusedPlugin or trackSettings.showOnlyFocusedPlugin
                                    if showOnlyFocusedPlugin then
                                        singlePluginParameterPanelFocusFirstIfNeeded() 
                                        --trackSettings.hidePluginSearchParameters[GetFXGUID(track, fxnumber)] = settings.showPluginsPanel
                                        pluginParametersPanel(track, fxnumber, nil, vertical, width_child, height_child, true,getFxInfoAsObject(track, fxnumber), showOnlyFocusedPlugin)
                                    else
                                        local currentIndent, currentParent
                                        local startContainerColorX
                                        local xBefore, yBefore, xAfter, xAfter
                                        
                                        for i, f in ipairs(trackFxTableWithIndentIndicators) do 
                                            if not f.isModulator and not f.seperator  then
                                                
                                                
                                                folderClosed, showPlugin, isFolderClosed, fxInClosedFolderCount = getIfPluginShouldBeShown(folderClosed, track, f, i, trackFxTableWithIndentIndicators, true) 
                                                
                                                
                                                
                                                
                                                if showPlugin then
                                                    
                                                    if startContainerColorX and currentIndent > 0 then 
                                                        local curPosY = yAfter + height_child + 3
                                                        local width = xAfter - (f.indent == 0 and settings.widthBetweenWidgets or 0)
                                                        local containerColor = (trackSettings.containerColors and currentParentGuid and trackSettings.containerColors[currentParentGuid]) and trackSettings.containerColors[currentParentGuid] or indentColors[(currentIndent - 1)%3 + 1]
                                                        reaper.ImGui_DrawList_AddLine(draw_list, xBefore, curPosY, width, curPosY, containerColor, 3)
                                                    end
                                                    
                                                    xBefore, yBefore = reaper.ImGui_GetCursorScreenPos(ctx)
                                                    
                                                    if f.isContainer then
                                                        f.isFolderClosed = isFolderClosed
                                                        f.fxInClosedFolderCount = fxInClosedFolderCount
                                                    end
                                                    
                                                    pluginParametersPanel(track, f.fxIndex, nil, vertical, width_child, height_child, nil, f)
                                                    if i < #trackFxTableWithIndentIndicators then
                                                        if f.isContainer then
                                                        --    placingOfNextElement(1)
                                                            startContainerColorX = xBefore
                                                        else
                                                          
                                                        end
                                                        placingOfNextElement(settings.widthBetweenWidgets)
                                                    end
                                                    
                                                    
                                                    xAfter, yAfter = reaper.ImGui_GetCursorScreenPos(ctx)
                                                    
                                                    if f.isContainer and folderClosed then
                                                        --xAfter = xAfter - settings.widthBetweenWidgets
                                                    end
                                                    
                                                    
                                                    -- start of drawing some indication color for containers 
                                                    if f.indent > 0 or f.isContainer then 
                                                        startContainerColorX = xBefore
                                                    end
                                                    currentIndent = f.indent + (f.isContainer and 1 or 0)
                                                    currentParentGuid = f.isContainer and f.guid or f.containerGuid
                                                end  
                                            end
                                        end
                                        
                                        if startContainerColorX and currentIndent > 0 and currentParentGuid then 
                                            local curPosY = yAfter + height_child + 3
                                            local width = xAfter - settings.widthBetweenWidgets
                                            local containerColor = (trackSettings.containerColors and currentParentGuid and trackSettings.containerColors[currentParentGuid]) and trackSettings.containerColors[currentParentGuid] or indentColors[(currentIndent - 1)%3 + 1]
                                            reaper.ImGui_DrawList_AddLine(draw_list, xBefore, curPosY, width, curPosY, containerColor, 3)
                                        end
                                    end
                                    reaper.ImGui_PopStyleColor(ctx, 3)
                                    
                                    reaper.ImGui_InvisibleButton(ctx, "dummy", 1,1)
                                    reaper.ImGui_EndChild(ctx)
                                end
                            else
                                
                                reaper.ImGui_InvisibleButton(ctx, "dummy", 1,1)
                            end
                            --
                            
                            reaper.ImGui_EndChild(ctx)
                            
                        end 
                        
                        if isMouseReleased then
                            if beginFxDragAndDrop and beginFxDragAndDropIndexRelease and beginFxDragAndDropIndexRelease ~= beginFxDragAndDropIndex  then
                                if modulationContainerPos ~= beginFxDragAndDropIndex or beginFxDragAndDropIndexRelease < 0x200000 then
                                    --reaper.ShowConsoleMsg(modulationContainerPos .. " - " .. beginFxDragAndDropIndex  .. " - > " .. tonumber(beginFxDragAndDropIndexRelease) .. "\n")
                                    
                                    -- ensure we don't move modulator from it's spot if it's the first and is hidden
                                    if not settings.includeModulators and modulationContainerPos == beginFxDragAndDropIndexRelease then
                                        beginFxDragAndDropIndexRelease = beginFxDragAndDropIndexRelease + 1 
                                    end
                                    
                                    reloadParameterLinkCatch = true
                                    
                                    CopyToTrackFX(track, beginFxDragAndDropIndex, track, beginFxDragAndDropIndexRelease, not copyFX)-- + (beginDragAndDropFXIndex > beginDragAndDropFXIndexRelease and 1 or 0)), true)
                                end
                            end
                            beginFxDragAndDropIndexRelease = nil 
                            beginFxDragAndDropName = nil
                            beginFxDragAndDrop = nil
                            HideToolTipTemp = nil
                            beginFxDragAndDropFX = nil
                            beginFxDragAndDropIndex = nil
                        end 
                          
                         
                            
                        
                        
                        --reaper.ImGui_SameLine(ctx)
                        --reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx)-4)
                    end
                    
                    ------------------------
                    -- PARAMETERS ----------
                    ------------------------
                    
                    function addFxViaBrowser(track, fxnumber)
                        local browserHwnd, browserSearchFieldHwnd = openFxBrowserOnSpecificTrack() 
                        local fx_before = getAllTrackFXOnTrackSimple(track)  
                        local doNotMoveToModulatorContainer = true
                        local insertAtFxIndex = fxnumber -- isAddFXAsLast and 999 or fxnumber
                        return doNotMoveToModulatorContainer, browserHwnd, browserSearchFieldHwnd, insertAtFxIndex, fx_before
                    end
                    
                    if openAddFXPopupWindow then 
                        reaper.ImGui_OpenPopup(ctx, "add popup")  
                        openAddFXPopupWindow = false
                    end
                    
                    if reaper.ImGui_BeginPopup(ctx, "add popup") then
                        if reaper.ImGui_Selectable(ctx, "Add FX via browser", false) then 
                            doNotMoveToModulatorContainer, browserHwnd, browserSearchFieldHwnd, insertAtFxIndex, fx_before = addFxViaBrowser(track, fxnumber)
                            pathForNextIndex = getPathForNextFxIndex(track, insertAtFxIndex)
                            addNewFXToEnd = isAddFXAsLast
                            moveToModulatorContainer = false
                        end
                        setToolTipFunc("Add new FX via the native Reaper FX Browser")
                        
                        if reaper.ImGui_Selectable(ctx, "Add container##", false) then  
                            fxnumber = addFxAfterSelection(track, fxnumber, "Container")
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end 
                        
                        if reaper.ImGui_Selectable(ctx, "Move focused FX in to new container##", false) then 
                            local containerIndex = addFxAfterSelection(track, fxnumber, "Container", true)
                            local containerPath = getPathForNextFxIndex(track, containerIndex)
                            local newIndex = get_fx_id_from_container_path(track, table.unpack(containerPath))
                            moveFx(track, fxnumber, newIndex)
                            reaper.ImGui_CloseCurrentPopup(ctx)
                        end
                        
                        if reaper.ImGui_BeginMenu(ctx, "fx chains") then
                            for _, fxChain in ipairs(fxChainPresetsFiles) do
                                if reaper.ImGui_Selectable(ctx, fxChain.name, false) then   
                                    fxnumber = addFxAfterSelection(track, fxnumber, fxChain.id)
                                end
                            end
                              
                            reaper.ImGui_EndMenu(ctx)
                        end
                        
                        setToolTipFunc("Add new Container to track")
                        reaper.ImGui_EndPopup(ctx)
                    end
                    
                    --if doNotMoveToModulatorContainer then
                        local newFxIndexFocus = waitForClosingAddFXBrowser(pathForNextIndex, fx_before)
                        if newFxIndexFocus then
                            fxnumber = newFxIndexFocus
                            newFxIndexFocus = nil
                        end
                    --end
                    
                   -- reaper.ImGui_EndChild(ctx)
                --end
            end
            
            
            
            function modulatorsPanel()
            
            
              
            --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundWidgets)
            --local visible = ImGui.BeginChild(ctx, 'ModulatorsChilds', nil, nil, reaper.ImGui_ChildFlags_Border(), reaper.ImGui_WindowFlags_HorizontalScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse())
            --if visible then
              --reaper.ImGui_SetCursorPos(ctx, 0,0)
              
                if settings.showModulatorsPanel then
                    -- we could set the color based on the focused FX
                    local title = "Modulators"
                    local vertical = settings.vertical
                    local screenPosX, screenPosY = reaper.ImGui_GetCursorScreenPos(ctx)
                    
                        
                    --local isCollabsed = trackSettings.hideModules
                    --local width = settings.vertical and elementsWidthInVertical or (isCollabsed and headerSizeW or settings.modulesWidth)
                    --local height = settings.vertical and (isCollabsed and headerSizeW or settings.modulesHeight) or elementsHeightInHorizontal
                    
                    
                    local showModulatorsList = settings.showModulatorsList
                    local showAddModulatorsList = settings.showAddModulatorsList
                    
                    local showModulators
                    if settings.showModulatorsGlobal then
                        showModulators = settings.showModulators 
                    else
                        showModulators = trackSettings.showModulators
                    end
                    local showOnlyFocusedPlugin
                    if settings.showModulatorsGlobal then
                        showOnlyFocusedModulator = settings.showOnlyFocusedModulator 
                    else
                        showOnlyFocusedModulator = trackSettings.showOnlyFocusedModulator
                    end
                    
                    
                    local isCollabsed = trackSettings.hideModules or (not showAddModulatorsList and not showModulators and not showModulatorsList)
                    
                    local fixedSize = settings.modulatorsPanelWidthFixedSize
                    local width = vertical and elementsWidthInVertical or (isCollabsed and headerSizeW or (fixedSize and settings.modulatorsPanelWidth or nil))
                    local height = vertical and (isCollabsed and headerSizeW or (fixedSize and settings.modulatorsPanelHeight or nil)) or elementsHeightInHorizontal
                    
                    
                    -- instead of -12 we use -14 so in case we do fixed size, it still works
                    local width_child = elementsWidthInVertical - 14
                    local height_child = elementsHeightInHorizontal - 14
                    
                    local modulatorsListWidth = vertical and width_child - 14 or settings.modulesWidth
                    local modulatorsListHeight = vertical and settings.modulesHeight or height_child - 16
                    
                    
                    
                    local heightAutoAdjust = false -- not isCollabsed and not (not vertical or settings.alwaysUsePluginsHeight)
                    local childPosSize = 20
                    
                    
                    
                    if topChildOfPanel(title, width, height, vertical and not isCollabsed, fixedSize) then
                        --reaper.ImGui_InvisibleButton(ctx, "dummy", 20 ,20)
                        
                        --local headerW = vertical and width or headerSizeW 
                        --local headerH = vertical and headerSizeW or height 
                        
                        --[[
                        local headerAreaRemove = 40
                        
                        local headerTextX = screenPosX + (vertical and headerAreaRemove or 0)
                        local headerTextY = screenPosY + (vertical and 0 or headerAreaRemove)
                        local headerTextW = headerW - (vertical and headerAreaRemove * 2 or 0)
                        local headerTextH = headerH - (vertical and 0 or headerAreaRemove * 2)  
                        ]]
                        
                        local headerW = vertical and width or headerSizeW
                        local headerH = vertical and headerSizeW or height  
                        local headerAreaRemoveTop = 0
                        local headerAreaRemoveBottom = 40
                        
                        drawHeaderBackground(screenPosX, screenPosY, screenPosX + headerW, screenPosY + headerH, isCollabsed, vertical, settings.colors.backgroundModulesHeader, settings.colors.backgroundModulesBorder)
                        
                        
                        if settings.showSortByNameModulator then
                            headerAreaRemoveTop = headerAreaRemoveTop + 20
                            -- Most left
                            local posX, posY = getIconPosToTheRight(vertical, headerAreaRemoveTop, screenPosX, screenPosY, width)
                            if drawSortingIcon(posX, posY, 20, settings.sortAsType, "Sort modulators by name") then
                                settings.sortAsType = not settings.sortAsType
                                saveSettings()
                            end
                        end
                        
                        if settings.showMapOnceModulator then
                            headerAreaRemoveTop = headerAreaRemoveTop + 20
                            -- Most left
                            local posX, posY = getIconPosToTheRight(vertical, headerAreaRemoveTop, screenPosX, screenPosY, width)
                            if drawMapOnceIcon(posX, posY, 20, settings.mapOnce, "Map only 1 parameter") then
                                settings.mapOnce = not settings.mapOnce
                                saveSettings()
                            end
                        end
                        
                        
                        headerTextX, headerTextY, headerTextW, headerTextH, align, bgX, bgW = getAlignAndHeaderPlacementAndSize(title, vertical, screenPosX, screenPosY, headerAreaRemoveTop, headerAreaRemoveBottom, headerW, headerH)
                        
                        
                        local toolTip = "Click to minimize modulators panel" -- "Right click for more options"
                        if drawHeaderTextAndGetHover(title, headerTextX, headerTextY, headerTextW, headerTextH, isCollabsed, vertical, 0, toolTip, colorText & 0xFFFFFF88, align, bgX, bgW) then
                            if isMouseClick then
                                trackSettings.hideModules = not trackSettings.hideModules  
                                saveTrackSettings(track) 
                            end
                        end
                         
                        --[[
                        -- Most left
                        local posX, posY = getIconPosToTheLeft(vertical, 20, screenPosX, screenPosY, height)
                        if drawListIcon(posX, posY, 20, trackSettings.showModulatorsList, "Show modules list") then
                            trackSettings.showModulatorsList = not trackSettings.showModulatorsList  
                            saveTrackSettings(track) 
                        end]]
                        
                        local posX, posY = getIconPosToTheLeft(vertical, 20, screenPosX, screenPosY, height)
                        local showOnlyFocusedModulator
                        if settings.showOnlyFocusedModulatorGlobal then
                            showOnlyFocusedModulator = settings.showOnlyFocusedModulatorGlobal 
                        else
                            showOnlyFocusedModulator = trackSettings.showOnlyFocusedModulator  
                        end
                        
                        -- until we have implemented a modulator list
                        showOnlyFocusedModulator = false
                        
                        local hideAllModulatorPanelsOnNextClick = not showOnlyFocusedModulator and showModulators
                        local tip = hideAllModulatorPanelsOnNextClick and "Hide all modulator panels" or "Show all modulator as seperate panels" 
                        --local tip = hideAllModulatorPanelsOnNextClick and "Hide all modulator panels" or (showOnlyFocusedModulator and "Show all modulator as seperate panels" or "Show focused modulator panel")
                        if drawListHorizontalIcon(posX, posY, 20, not showOnlyFocusedModulator, tip, showModulators) then
                            if hideAllModulatorPanelsOnNextClick then
                                if settings.showModulatorsGlobal then
                                    settings.showModulators = not settings.showModulators
                                    saveSettings()
                                else
                                    trackSettings.showModulators = not trackSettings.showModulators
                                    saveTrackSettings()  
                                end
                            else 
                                if settings.showModulatorsGlobal then
                                    settings.showModulators = true
                                    settings.showOnlyFocusedModulator = not settings.showOnlyFocusedModulator
                                    saveSettings()
                                else
                                    trackSettings.showModulators = true
                                    trackSettings.showOnlyFocusedModulator = not trackSettings.showOnlyFocusedModulator
                                    saveTrackSettings(track) 
                                end 
                            end
                            
                            
                            
                        end
                        
                        local posX, posY = getIconPosToTheLeft(vertical, 40, screenPosX, screenPosY, height)
                        if drawListArrayIcon(posX, posY, 20, settings.showAddModulatorsList, "Show add modules list") then
                            settings.showAddModulatorsList = not settings.showAddModulatorsList  
                            saveSettings() 
                        end
                        
                        
                        --[[
                        -- set position and size of sub child, eg the search
                        if vertical then
                            reaper.ImGui_SetCursorPos(ctx, 6, 20+6) 
                            height = height - 26
                            width = width - 10
                        else
                            width = width - 20 - 8
                            height = height - 6
                            reaper.ImGui_SetCursorPos(ctx, 20+6, 6)
                        end
                        ]]
                        
                        ------------------------
                        -- MODULATORS LIST -----
                        ------------------------
                        
                        if not isCollabsed then
                        
                            if settings.showAddModulatorsList then 
                                --if bodyChildOfPanel(title .. "bodyList", childPosSize, 6, vertical) then
                                --reaper.ImGui_Dummy(ctx, 20,20)
                                    --modulatorsListWidth, modulatorsListHeight = setCursorAfterHeader(vertical, modulatorsListWidth, modulatorsListHeight)
                                    
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundWidgets)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.backgroundWidgets)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), settings.colors.backgroundWidgetsBorder)
                                   
                                    if bodyChildOfPanel(title .. "body", childPosSize, 6, vertical, true) then
                                        if scrollChildOfPanel(title .. "scroll", modulatorsListWidth, modulatorsListHeight, false) then
                                    
                                            modulesPanel(ctx, nil, nil, modulatorsListWidth, modulatorsListHeight)
                                            removeCustomModulePopup()
                                        
                                            reaper.ImGui_EndChild(ctx)
                                        end
                                        
                                        reaper.ImGui_EndChild(ctx)
                                    end
                                    
                                    reaper.ImGui_PopStyleColor(ctx, 3)
                                --    reaper.ImGui_EndChild(ctx)
                                --end
                                placingOfNextElement(settings.widthBetweenWidgets)
                                childPosSize = nil--childPosSize + drawSeperatorAndAddPlacementOfNextPanel(settings.showModulatorsPanels, childPosSize, vertical, heightAutoAdjust, modulatorsListWidth + 10, modulatorsListHeight + 10)
                                --[[
                                if settings.showModulators then
                                   placingOfNextElement(5) 
                                   drawSeperator(settings.colors.modulatorBorder & 0xFFFFFF55)
                                   childPosSize = childPosSize + (vertical and (heightAutoAdjust and reaper.ImGui_GetCursorPosY(ctx) or modulatorsListHeight) or modulatorsListWidth)
                                end]]
                            end
                            
                            if showModulators then 
                                if bodyChildOfPanel(title .. "bodyParametersModule", childPosSize, 6, vertical, nil, fixedSize, vertical and width_child + 4 or nil, not vertical and height_child or nil) then
                                    
                                    
                                    if math.floor(reaper.ImGui_GetScrollMaxX(ctx)) > 0 then 
                                        height_child = height_child - 10
                                    end
                                    
                                    if math.floor(reaper.ImGui_GetScrollMaxY(ctx)) > 0 then 
                                        width_child = width_child - 8
                                    end
                                    
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundWidgets)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.backgroundWidgets)
                                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), settings.colors.backgroundWidgetsBorder)
                                    
                                    modulatorsParametersPanel(width_child, height_child)
                                    
                                    
                                    reaper.ImGui_PopStyleColor(ctx, 3)
                                    reaper.ImGui_EndChild(ctx)
                                end
                            end
                        end
                        reaper.ImGui_Dummy(ctx, 1,1)
                        
                        
                        reaper.ImGui_EndChild(ctx)
                    
                    end 
                    
                    
                    
                    --placingOfNextElement(5)
                    
                    if modulationContainerPos then
                        --drawConnectionToNextElement(vertical, elementsWidthInVertical, pansHeight)
                    end
                end
                
                
                
                
                
                ------------------------
                -- MODULATORS ----------
                ------------------------
                
                
                
                
                local startOfModulatorsPanelX, startOfModulatorsPanelY = reaper.ImGui_GetItemRectMin(ctx)
                local endOfModulatorsPanelX, endOfModulatorsPanelY = reaper.ImGui_GetItemRectMax(ctx)
                if not ignoreRightClick and reaper.ImGui_IsMouseHoveringRect(ctx, startOfModulatorsPanelX, startOfModulatorsPanelY, endOfModulatorsPanelX, endOfModulatorsPanelY) and isMouseDownRightImgui then
                    openFloatingModulesWindow = not openFloatingModulesWindow 
                end
                
                
                modulatorsPanelX2, modulatorsPanelY2 = reaper.ImGui_GetCursorScreenPos(ctx)
                --reaper.ImGui_DrawList_AddLine(draw_list, modulatorsPanelX, modulatorsPanelY-3, modulatorsPanelX2, modulatorsPanelY-3, colorText,3)
                
                
                --else
                --    reaper.ImGui_Text(ctx,"SELECT A TRACK OR TOUCH A TRACK PARAMETER")
                --end
                
                
                
                if reaper.ImGui_IsWindowHovered(ctx) then
                  --reaper.ShowConsoleMsg(tostring(reaper.ImGui_IsAnyItemHovered(ctx)) .. "\n")
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
                
                if modulatorsPanelX and endOfModulatorsPanelX then
                    --reaper.ImGui_DrawList_AddRect(draw_list, modulatorsPanelX, modulatorsPanelY, endOfModulatorsPanelX+1, endOfModulatorsPanelY+1, settings.colors.modulators,6, nil, 1)
                end
                
            end
            
            
            
            --placingOfNextElement()
            --drawSeperator()
        local isMuted = track and GetMuted(track)
        local disable = not track or isMuted 
        elementsHeightInHorizontal = winH - y --28 
        elementsWidthInVertical = winW - x - 8-- margin * 4
            
        trackHeaderIconsAndName()
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundWindow)
        
        local mainAreaW = winW - reaper.ImGui_GetCursorPosX(ctx) - 8
        local mainAreaH = winH - reaper.ImGui_GetCursorPosY(ctx) - 8
        
        if track or not settings.showInsertOptionsWhenNoTrackIsSelected then
            if reaper.ImGui_BeginChild(ctx, "mainArea", mainAreaW, mainAreaH , nil, reaper.ImGui_WindowFlags_HorizontalScrollbar()) then
                
                reaper.ImGui_Dummy(ctx, 1,1)
                reaper.ImGui_SetCursorPos(ctx, 0,0)
                
                elementsHeightInHorizontal = elementsHeightInHorizontal - 8
                elementsWidthInVertical = elementsWidthInVertical -- 8
                
                if not settings.vertical and math.floor(reaper.ImGui_GetScrollMaxX(ctx)) > 0 then 
                    elementsHeightInHorizontal = elementsHeightInHorizontal - 12
                end
                
                if settings.vertical and math.floor(reaper.ImGui_GetScrollMaxY(ctx)) > 0 then 
                    elementsWidthInVertical = elementsWidthInVertical - 12
                end
                
                --reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundModules)
                
                --modulatorsPanelX, modulatorsPanelY = reaper.ImGui_GetCursorScreenPos(ctx)
                
                --reaper.ImGui_SetCursorPos(ctx, 1,1)
                
                if disable then
                    reaper.ImGui_BeginDisabled(ctx)
                end
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), settings.colors.backgroundModules)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), settings.colors.backgroundModules)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), settings.colors.backgroundModulesBorder)
                
                pluginsPanel() 
                
                placingOfNextElement()
                
                
                modulatorsPanel()
                -- 321
                
                reaper.ImGui_PopStyleColor(ctx, 3)
                
                --
                
                if disable then
                    reaper.ImGui_EndDisabled(ctx)
                end
                
                --reaper.ImGui_PopStyleColor(ctx)
                reaper.ImGui_EndChild(ctx)
            end
        elseif settings.showInsertOptionsWhenNoTrackIsSelected then 
            newTrack = true --reaper.CountSelectedTracks(0) == 0
            local topSpace = 10
            local tableCount = 3
            
            tableWidthSize = settings.vertical and mainAreaW or (mainAreaW/tableCount - padding)
            local windowHMax = settings.vertical and mainAreaH / tableCount - padding * 3 - 24 or (mainAreaH - topSpace - margin*2 - 24) -- 24 is the missing button when a track has fx on it
            
            reaper.ImGui_BeginGroup(ctx)
            --if reaper.ImGui_Button(ctx, "Insert empty track") then
            --    reaper.Main_OnCommand(40001, 0) --Track: Insert new track
            --end
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), colorTransparent)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), colorTransparent)
            
            --tablePosY = padding
            --reaper.ImGui_SetCursorPos(ctx, startX, padding)
            favoriteList =  {{name = "Container"}}--{{name = "Empty Track", category = "none"}}
            --local text = "Favorite list" 
            --tableWithFilterAndText(text,favoriteList, "fxFavoriteListFilter", tableWidthSize, windowHMax - 40, insertFXOnSelectedTracks, {"Name"}, newTrack) 
            
            reaper.ImGui_EndGroup(ctx)
            
            if not settings.vertical then
                reaper.ImGui_SameLine(ctx)
            end
            
            local text = "Insert track template at bottom of session"
            tableWithFilterAndText(text, trackTemplateFiles, "trackTemplatesFilter", tableWidthSize, windowHMax, insertTrackTemplate, {"Name", "Folder"}, track)
            
            if not settings.vertical then
                reaper.ImGui_SameLine(ctx) 
            end
            
            local text = "Load FX chain presets on " .. (not newTrack and "selected tracks" or "a new track")
            tableWithFilterAndText(text, fxChainPresetsFiles, "chainPresetFilter", tableWidthSize, windowHMax, insertFXChainPreset, {"Name", "Folder"}, track)
            
            if not settings.vertical then
                reaper.ImGui_SameLine(ctx) 
            end
            
            
            local text = "Insert FX on " .. (not newTrack and "selected tracks" or "a new track") 
            tableWithFilterAndText(text, fxListFiles, "fxListFilter", tableWidthSize, windowHMax, insertFXOnSelectedTracks, {"Name", "Developer","Category","Type"}, track) 
            
            reaper.ImGui_PopStyleColor(ctx, 2)
        end
        
        if (track and isMuted) or (not track and not settings.showInsertOptionsWhenNoTrackIsSelected) then -- or not track then
            local minX, minY = reaper.ImGui_GetItemRectMin(ctx)
            reaper.ImGui_SetCursorScreenPos(ctx, minX, minY)
            if reaper.ImGui_BeginChild(ctx, "mainAreaMuted", mainAreaW, mainAreaH , nil, reaper.ImGui_WindowFlags_HorizontalScrollbar()|reaper.ImGui_WindowFlags_NoBackground()) then
                local bgColor = settings.colors.backgroundWidgets
                local bgColorTransparent = bgColor & 0xFFFFFF99
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), bgColor & 0xFFFFFFAA)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), bgColor & 0xFFFFFFAA)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), bgColor & 0xFFFFFFAA)
                if reaper.ImGui_Button(ctx, "##Muted", mainAreaW, mainAreaH) then
                    if not track then
                        reaper.Main_OnCommand(40001, 0) --Track: Insert new track
                    else
                        setMuted(track, false)
                    end
                end
                local nameHover = not track and "ADD TRACK" or "UNMUTE TRACK"
                local nameStatic = not track and "NO TRACK SELECTED" or "TRACK MUTED"
                local name = reaper.ImGui_IsItemHovered(ctx) and nameHover or nameStatic
                reaper.ImGui_PopStyleColor(ctx,3)
                
                
                reaper.ImGui_PushFont(ctx, font60)
                local textW, textH = reaper.ImGui_CalcTextSize(ctx, name, 0,0)
                local textX = minX + mainAreaW / 2 - ((vertical and textH or textW) / 2)
                local textY = minY + mainAreaH / 2 - ((vertical and textW or textH) / 2)
                --reaper.ImGui_DrawList_AddRectFilled(draw_list, textX, textY, textX + textW, textY + textH, bgColor)
                --reaper.ImGui_DrawList_AddText(draw_list, textX, textY, settings.colors.text, name)
                drawHeaderText(name, textX, textY, mainAreaW, mainAreaH, not vertical, textMargin, settings.colors.text, vertical and "Right" or "Left", 4, 60) 
                
                reaper.ImGui_PopFont(ctx)
                reaper.ImGui_EndChild(ctx)
            end
        end
        
        reaper.ImGui_PopStyleColor(ctx)
        
        
        
        
        
        
        
        
        renameFxIndexPopup()
        
        
        ImGui.End(ctx)
    end
    
    
    function floatingModulesWindow()
        local rv, open = reaper.ImGui_Begin(ctx, "MODULES", true, reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse()) 
        if not rv then return open end
        modulesPanel(ctx)
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


    function showModulatorForParameter(p, sizeW, sizeH, showSettingsVar)
        local showVar = settings[showSettingsVar .."ShowModulator"]
        if p.parameterLinkActive then
            local m = nil
            local modName = p.parameterLinkName
            if modulationContainerPos then 
                for pos, mt in ipairs(modulatorNames) do  
                    if modName == mt.mappingNames[p.parameterLinkParam] then
                        m = mt
                        break;
                    end
                end  
            end
            if m then 
                --childFlags = reaper.ImGui_ChildFlags_Border() | reaper.ImGui_ChildFlags_AutoResizeY()
                local curStartY = reaper.ImGui_GetCursorPosY(ctx)
                modulatorsWrapped(sizeW, sizeH, m, not showVar, true, showSettingsVar) 
                local sizeModulatorH = reaper.ImGui_GetCursorPosY(ctx) - curStartY - 8
                if settings[showSettingsVar .."ShowMappings"] then 
                    if not showVar then
                        sizeModulatorH = settings.modulesHeightVertically
                    end
                    mappingsArea(sizeW, sizeModulatorH, m, true, showSettingsVar, showVar, p.fxIndex, p.param)   
                end 
            end
        end
    end
    
    function floatingMappedParameterWindow(trackTouched, fxIndexTouched, parameterTouched)
        
        
        local x, y
        if hwndWindowOnTouchParam and reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) and floatingMapperWin and mousePosOnTouchedParam and settings.openFloatingMapperRelativeToMouse and settings.openFloatingMapperRelativeToMousePos then 
            
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
            --local x, y
            
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
            
            --if floatingMapperWin then
            --    reaper.JS_Window_SetPosition(reaper.JS_Window_Find( "Floating mapper", true), x, y,floatingMapperWin.w,floatingMapperWin.h)
            --end
            reaper.ImGui_SetNextWindowPos(ctx, x,y,reaper.ImGui_Cond_Always())
        end
        
        local rv, open = reaper.ImGui_Begin(ctx, "Floating mapper", true, reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoTitleBar()) 
        if not rv then return open end
        if not trackTouched or not fxIndexTouched or not parameterTouched then return false end
        
        if x and y then
           -- reaper.ImGui_SetWindowPos(ctx, x, y)
        end
        --[[
        -- THIS MADE THE FLOATING MAPPER DISAPEAR WHEN IN NOT FORCE MODE
        if not reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) then  
            --hwndWindowOnTouchParam = GetFloatingWindow(track, fxIndexTouched)
            --if not reaper.JS_Window_IsVisible(hwndWindowOnTouchParam) then 
                open = false
            --end
        end]]
        
        
        
        
        local p = getAllDataFromParameter(trackTouched, fxIndexTouched, parameterTouched)
        
        local winW, winH = reaper.ImGui_GetWindowSize(ctx)
        local winX, winY = reaper.ImGui_GetWindowPos(ctx) 
        mouseInsideFloatingMapper = mouse_pos_x_imgui >= winX and mouse_pos_x_imgui <= winX + winW and mouse_pos_y_imgui >= winY and mouse_pos_y_imgui <= winY + winH
        --[[
        
        
        if mouse_pos_x_imgui >= winX and mouse_pos_x_imgui <= winX + winW and mouse_pos_y_imgui >= winY and mouse_pos_y_imgui <= winY + winH then 
            
            if isAnyMouseDown then
                clickedInFloatingWindow = true 
            end
            if isMouseReleased then
                clickedInFloatingWindow = false
            end
            
        end
        ]]
        
        floatingMapperWin = {w = winW, h = winH}
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, winX,winY,winX+winW,winY+ 16, settings.colors.boxBackground, 8)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, winX,winY + 10,winX+winW,winY+ 24, settings.colors.boxBackground, 0)
        reaper.ImGui_DrawList_AddLine(draw_list, winX,winY + 24,winX+winW,winY+ 24, settings.colors.textDimmed, 1)
        
        
        reaper.ImGui_SetCursorPos(ctx, 3, 3)
        if specialButtons.lock(ctx, "lock", 20, locked, (locked and "Unlock from track" or "Lock to selected track"), colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow, trackColor, true) then
            locked = not locked and track or false 
            --reaper.SetExtState(stateName, "locked", locked and "1" or "0", true)
        end
        
        
        --local startPosX, startPosY = reaper.ImGui_GetItemRectMin(ctx)
        
        
        reaper.ImGui_SetCursorPos(ctx, 3+20, 3)
        specialButtons.envelopeSettings(ctx, "envelopeSettings", 20, settings.showEnvelope, (settings.showEnvelope and "Disable" or "Enable") .. " showing envelope on parameter click\n - right click for more options", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow, true, automationColor, automationColor, fillEnvelopeButton)
        clickEnvelopeSettings()
        
        --[[
        reaper.ImGui_SetCursorPos(ctx, 3+40, 3)
        specialButtons.floatingMapper(ctx, "floatingMapper", 20, settings.useFloatingMapper, "Click for floating mapper settings", colorText, colorTextDimmed, colorTransparent, settings.colors.buttonsSpecialHover, settings.colors.buttonsSpecialActive, settings.colors.backgroundWindow, true)
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
            optionsForModulators()
            reaper.ImGui_EndPopup(ctx)
        end
        
        if (not lastWinW or lastWinW == winW) and specialButtons.close(ctx,winW-22,6,12,false,"closeFloatingMapper", colorTransparent, colorBlack,colorTextDimmed, settings.colors.removeCrossHover) then 
            open = false
        end
        lastWinW = winW
        
        setToolTipFunc("Close floating mapper")
        
        
        reaper.ImGui_SetCursorPos(ctx, 4, 24)
        reaper.ImGui_Spacing(ctx)
        
        
        
        local sizeW = settings.floatingMapperParameterWidth
        
        pluginParameterSlider("parameterFloating",p,nil,nil,true,nil,sizeW,nil,nil,nil,true, nil, useKnobs, useNarrow)
        
        local sizeH = not settings.floatingParameterShowModulator and 22 or 22--60--(winH - reaper.ImGui_GetCursorPosY(ctx) - margin*2)
        
        showModulatorForParameter(p, sizeW, sizeH, "floatingParameter")
        
        
        reaper.ImGui_End(ctx)
        return open 
    end
    
    
    if not settings.useFloatingMapper or not clickedHwnd then
        showFloatingMapper = false
    elseif clickedHwnd and not reaper.JS_Window_IsVisible(clickedHwnd) then
        clickedHwnd = nil
        lastClickedHwnd = nil
        showFloatingMapper = false
    elseif clickedHwnd and lastClickedHwnd ~= clickedHwnd then
        if lastClickedHwnd and not settings.keepWhenClickingInOtherFxWindow then
            showFloatingMapper = false
        end
        --lastClickedHwnd = clickedHwnd
    end
    
    
    
    if showFloatingMapper and validateTrack(track) and track == trackTouched and fxIndexTouched and parameterTouched then
        showFloatingMapper = floatingMappedParameterWindow(trackTouched, fxIndexTouched, parameterTouched) 
    end 
    
    
    if isAnyMouseDown then
        local alreadyShowing = showFloatingMapper == true 
        
        if settings.onlyKeepShowingWhenClickingFloatingWindow and not fxWindowClicked then
            if not reaper.ImGui_IsMousePosValid(ctx) then
                showFloatingMapper = false
            elseif not settings.keepWhenClickingInAppWindow and mouseInsideAppWindow then 
                showFloatingMapper = false
            end
        end 
    end
    
    
    
    
    -------------------------------
    ----------EXPERIMENTAL MODE----
    -------------------------------
    
    function loadTempPlugPos()
        if track then
            local hasSavedState, savedTrackStates = reaper.GetSetMediaTrackInfo_String(track, "P_EXT" .. ":" .. "tempPlugPos", "{}", false)
            if hasSavedState then        
                return json.decodeFromJson(savedTrackStates) 
            else 
                return {}
            end 
        else
            return {}
        end
    end
    
    function saveTempPlugPos(pluginPos)
        if pluginPos then 
            reaper.GetSetMediaTrackInfo_String(track, "P_EXT" .. ":" .. "tempPlugPos", json.encodeToJson(pluginPos), true)
        end
    end
    
    
    
    local initialMappedOverlaySize = settings.initialMappedOverlaySize * 2
    local editAdvancedFloatingMapper = true
    if settings.extendedFloatingMapper then
        ignoreKeypress = true
        if not pluginPos then pluginPos = loadTempPlugPos() end
        
        function returnHwndOnListWithSingleAmountOrHwnd(listAmount, list, hwnd)
            if listAmount == 1 then 
                return reaper.JS_Window_HandleFromAddress(list)
            else
                return hwnd
            end 
        end
        
        function findPluginHwnd(start_hwnd) 
            local CretvalParent, ClistParent = reaper.JS_Window_ListAllChild(start_hwnd)
            local biggestWidth = 0 
            local hwnd
            --reaper.ShowConsoleMsg("----\n")
            for kParent in string.gmatch(ClistParent, "(.-),") do
                local hParent = reaper.JS_Window_HandleFromAddress(kParent) 
                local retSize, wParent = reaper.JS_Window_GetClientSize(hParent)
                local idParent = reaper.JS_Window_GetLongPtr(hParent, "ID") 
                idParent = idParent ~= nil and math.floor(reaper.JS_Window_AddressFromHandle(idParent)) or nil
                local CretvalChild, ClistChild = reaper.JS_Window_ListAllChild(hParent)  
                -- We store the biggest parent in case theres no children
                if biggestWidth <= wParent then
                    --if ClistChild == "" or ClistChild == nil then
                        hwnd = returnHwndOnListWithSingleAmountOrHwnd(CretvalChild, ClistChild, hParent)
                        biggestWidth = wParent
                    --end
                end
                --reaper.ShowConsoleMsg(tostring(wParent) .. " - " .. tostring(idParent) .. " - " .. CretvalChild .. " \n")
                
                -- if there's a child with many sub childs we look in here instead
                if idParent == nil and CretvalChild > 5 then
                --reaper.ShowConsoleMsg(" - - - \n")
                    for kChild in string.gmatch(ClistChild, "(.-),") do 
                        local hChild = reaper.JS_Window_HandleFromAddress(kChild)
                        local idChild = reaper.JS_Window_GetLongPtr(hChild, "ID") 
                        idChild = idChild ~= nil and math.floor(reaper.JS_Window_AddressFromHandle(idChild)) or nil
                        local childChildrenAmount, childChildList = reaper.JS_Window_ListAllChild(hChild)
                        local retSize, wChild = reaper.JS_Window_GetClientSize(hChild)
                        -- we store the biggest. In case you have extended the window so the reaper preset is bigger than the plugin it's an issue
                        
                        --reaper.ShowConsoleMsg(tostring(wChild) .. " - " .. tostring(childChildList).. " - " .. childChildrenAmount ..  "\n")
                        if biggestWidth <= wChild then
                            -- if opening a drop down menu we get something unexpected
                            if childChildList == "" or childChildList == nil then
                                --reaper.ShowConsoleMsg(tostring(wChild) .. " - " .. tostring(childChildList).. " - " .. childChildrenAmount ..  " ||33\n")
                                hwnd = returnHwndOnListWithSingleAmountOrHwnd(childChildrenAmount, childChildList, hChild)
                                biggestWidth = wChild
                            --else
                              -- this doesn't solve it
                               -- hwnd = nil
                            end 
                        end
                    end
                    break
                end  
            end  
            return hwnd
        end
        
        for _ ,plugin in ipairs(focusedTrackFXNames) do
            if plugin.isOpen then
                local HWNDs = {}
                local hwnd
                if plugin.isFloating then  
                    local start_hwnd = plugin.isFloating
                    hwnd = findPluginHwnd(start_hwnd) 
                else 
                    local start_hwnd = reaper.JS_Window_Find("FX: Track 1", false) 
                    hwnd = findPluginHwnd(start_hwnd) 
                end
                --reaper.ShowConsoleMsg(tostring(hwnd) .. "\n")
                --local hwnd = HWNDs[#HWNDs] 
                --atitle = reaper.JS_Window_GetTitle(hwnd)
                if not pluginPos[plugin.fxIndex] then pluginPos[plugin.fxIndex] = {} end
                local retSize, w, h = reaper.JS_Window_GetClientSize(hwnd)
                local retRect, x, y = reaper.JS_Window_GetClientRect(hwnd)  
                if isApple then
                    local _, avHeight = reaper.JS_Window_GetViewportFromRect(0, 0, 0, 0, false)
                    y = avHeight - y
                end
                local x2 = x + w
                local y2 = y + h
                --if 
                --ret = reaper.JS_Window_ArrayAllChild(plugin.isFloating, list)
                if retRect and retSize then
                    reaper.ImGui_SetNextWindowPos(ctx, x,y,reaper.ImGui_Cond_Always())
                    reaper.ImGui_SetNextWindowSize(ctx, w,h,reaper.ImGui_Cond_Always())
                end
                local rv, open = reaper.ImGui_Begin(ctx, "overlay" .. plugin.fxIndex, true, reaper.ImGui_WindowFlags_NoInputs() | reaper.ImGui_WindowFlags_NoBackground() | reaper.ImGui_WindowFlags_NoMove() |reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoTitleBar()) 
                if not rv then return open end
                if open then   
                    
                    reaper.ImGui_DrawList_AddRect(draw_list, x,y, x2, y2, colorBlue, nil, nil, 4)
                    
                    if mouse_pos_x >= x and mouse_pos_y_correct >= y and mouse_pos_x <= x2 and mouse_pos_y_correct <= y2 then
                       if isMouseWasReleased and lastParameterTouched and lastFxIndexTouched == plugin.fxIndex and isFXWindowUnderMouse() then
                          local isSquare = isSuperPressed
                          if not pluginPos[plugin.fxIndex][lastParameterTouched] or not pluginPos[plugin.fxIndex][lastParameterTouched].x then 
                              pluginPos[plugin.fxIndex][lastParameterTouched] = {param = lastParameterTouched, info = getAllDataFromParameter(track, plugin.fxIndex, lastParameterTouched), size = initialMappedOverlaySize/2, w = initialMappedOverlaySize, h = initialMappedOverlaySize, x = mouse_pos_x - x - initialMappedOverlaySize/2, y = mouse_pos_y_correct - y - initialMappedOverlaySize/2, isSquare = isSquare}
                              saveTempPlugPos(pluginPos)
                              focusedMappedParamOverlay = pluginPos[plugin.fxIndex][lastParameterTouched]
                          end
                       end
                    end 
                    
                    reaper.ImGui_End(ctx)
                end
                
                local thicknessSize = 2
                local editFlags = not editAdvancedFloatingMapper and (reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoMove()) or reaper.ImGui_WindowFlags_None()
                
                -- Since not all parameters might be mapped we sort the mapped parameters before showing them
                local keys = {}
                for param in pairs(pluginPos[plugin.fxIndex]) do
                  table.insert(keys, param)
                end
                table.sort(keys)
                
                for _, param in ipairs(keys) do
                    paramMapped = pluginPos[plugin.fxIndex][param]
                    
                    if paramMapped.x then
                        local isSquare = paramMapped.isSquare 
                        local offsetCircle = isSquare and 0 or pluginPos[plugin.fxIndex][param].size
                        local pX = x + paramMapped.x
                        local pY = y + paramMapped.y
                        local info = getAllDataFromParameter(track, plugin.fxIndex, param)
                        
                        if not paramMapped.isFocused or (paramMapped.isFocused and not isMouseDown) or not editAdvancedFloatingMapper then 
                            reaper.ImGui_SetNextWindowPos(ctx, pX - thicknessSize/2, pY - thicknessSize/2,reaper.ImGui_Cond_Always())
                            reaper.ImGui_SetNextWindowSize(ctx, paramMapped.w + thicknessSize, paramMapped.h + thicknessSize,reaper.ImGui_Cond_Always()) 
                        end
                        
                        local rv, open = reaper.ImGui_Begin(ctx, "overlay" .. plugin.fxIndex .. ":" .. param, true, editFlags | reaper.ImGui_WindowFlags_NoBackground() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoTitleBar()) 
                        
                        if not rv then return open end
                        if open then 
                            local isFocused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
                            local isHovered = (isMouseReleased and reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())) and paramMapped or isHovered
                            local isEdited = focusedMappedParamOverlay == paramMapped
                            paramMapped.isFocused = isFocused
                            if editAdvancedFloatingMapper and isMouseDown and isFocused then 
                                local newX, newY = reaper.ImGui_GetWindowPos(ctx)
                                local newW, newH = reaper.ImGui_GetWindowSize(ctx) 
                                paramMapped.x = newX + thicknessSize/2 - x
                                paramMapped.y = newY + thicknessSize/2 - y
                                local diameter = math.min(newW, newH) - thicknessSize
                                paramMapped.w = isSquare and newW - thicknessSize or diameter
                                paramMapped.h = isSquare and newH - thicknessSize or diameter
                                paramMapped.size = math.floor(diameter / 2)
                                saveTempPlugPos(pluginPos)
                                
                                focusedMappedParamOverlay = paramMapped
                            end
                            
                            local colorBorder = isEdited and colorRedHidden or colorGreen
                            local colorBackground = (isHovered or isFocused) and colorLightDarkGreySemiTransparent or colorBlackSemiTransparent
                            
                            if paramMapped.isSquare then
                                reaper.ImGui_DrawList_AddRectFilled(draw_list, pX, pY, pX + paramMapped.w, pY + paramMapped.h, colorBackground, nil, nil)
                                reaper.ImGui_DrawList_AddRect(draw_list, pX, pY, pX + paramMapped.w, pY + paramMapped.h, colorBorder, nil, nil, thicknessSize)
                            else 
                                reaper.ImGui_DrawList_AddCircleFilled(draw_list,  pX + offsetCircle, pY + offsetCircle, paramMapped.size, colorBackground, nil)
                                reaper.ImGui_DrawList_AddCircle(draw_list,  pX + offsetCircle, pY + offsetCircle, paramMapped.size, colorBorder, nil, thicknessSize)
                            end 
                            local textW, textH = reaper.ImGui_CalcTextSize(ctx, info.name, 0, 0)
                            reaper.ImGui_DrawList_AddText(draw_list, pX + paramMapped.w / 2 - textW / 2, pY + paramMapped.h / 2 - textH / 2, colorWhite, info.name)
                            
                            -- focus the next one
                            if focusNext then 
                                focusedMappedParamOverlay = paramMapped
                                focusNext = false
                            end
                            
                            if isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then 
                                if isEdited then
                                    focusNext = true
                                end
                            end
                            
                            if isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then
                                if isEdited then
                                    focusedMappedParamOverlay = lastFocused
                                end
                            end
                            -- store the last param for possible focussing on that
                            lastFocused = paramMapped
                            
                            if not focusedMappedParamOverlay then
                                --focusedMappedParamOverlay = paramMapped
                            end
                            
                            reaper.ImGui_End(ctx)
                        end
                    end
                    
                end
                --reaper.ShowConsoleMsg(tostring(list) .. "\n") 
                local editWindowH = 200
                if editAdvancedFloatingMapper then
                    if retRect and retSize then
                        reaper.ImGui_SetNextWindowPos(ctx, x, y + h,reaper.ImGui_Cond_Always())
                        reaper.ImGui_SetNextWindowSize(ctx, w, editWindowH,reaper.ImGui_Cond_Appearing())
                        if resetAdvancedFloatingMapperWindowSize then
                            reaper.ImGui_SetNextWindowSize(ctx, w, editWindowH,reaper.ImGui_Cond_Always())
                            resetAdvancedFloatingMapperWindowSize = false
                        end
                    end
                    local rv, open = reaper.ImGui_Begin(ctx, "advancedFloatingMapperEditor" .. tostring(track) .. plugin.fxIndex, true, reaper.ImGui_WindowFlags_NoMove() | reaper.ImGui_WindowFlags_NoDocking() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse() | reaper.ImGui_WindowFlags_NoTitleBar()) 
                    
                    if not rv then return open end
                    if open then 
                        local editorWinWidth, editorWinHeight = reaper.ImGui_GetWindowSize(ctx)
                        local isEditorFocused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
                        local isSquare = focusedMappedParamOverlay and focusedMappedParamOverlay.isSquare or nil
                        local info = focusedMappedParamOverlay and getAllDataFromParameter(track, plugin.fxIndex, focusedMappedParamOverlay.param) or {name = "NA", fxIndex = plugin.fxIndex, param = -1, value = 0, currentValueNormalized = 0}
                        local paramText = focusedMappedParamOverlay and "Paramter " .. focusedMappedParamOverlay.param .. " selected" or "Select a parameter"
                        --reaper.ImGui_TextColored(ctx, colorWhite, focusedMappedParamOverlay.info.name)
                        
                        --if not focusedMappedParamOverlay then focusedMappedParamOverlay = {} end
                        reaper.ImGui_TextColored(ctx, colorWhite, paramText)
                        --if info then
                        pluginParameterSlider("advancedFloatingMapper", info, nil, nil, true, nil, 200, nil, nil, nil, false, nil, useKnobs, useNarrow)
                        --else
                        --    reaper.ImGui_InvisibleButton(ctx, "dummy", 200, 30)
                        --end
                        
                        reaper.ImGui_SameLine(ctx)
                        
                        if reaper.ImGui_Button(ctx, "Use settings as default") then
                            settings.initialMappedOverlaySize = focusedMappedParamOverlay.size
                            saveSettings()
                        end
                        
                        if reaper.ImGui_BeginTabBar(ctx, "tab selection")  then
                            local ret, open = reaper.ImGui_BeginTabItem(ctx, "Select", nil, selected_selection_tab)
                            if ret and isEditorFocused then 
                                --focusedMappedParamOverlay = nil
                            end
                            if ret and open then
                                selected_selection_tab = nil
                                if focusedMappedParamOverlay and not isEditorFocused then
                                    selected_position_tab = reaper.ImGui_TabItemFlags_SetSelected()
                                end
                                
                                local mappedParams = {}
                                local unmappedParams = {}
                                local numParams = GetNumParams(track, plugin.fxIndex)
                                for p = 0, numParams - 1 - 3 do
                                      name = GetParamName(track, plugin.fxIndex, p)
                                      if pluginPos[plugin.fxIndex][p] and pluginPos[plugin.fxIndex][p].x then
                                          table.insert(mappedParams, {name = name, param = p})
                                      else
                                          table.insert(unmappedParams, {name = name, param = p})
                                      end
                                end
                                
                                local tableWidth = editorWinWidth / 2 - 16
                                
                                reaper.ImGui_BeginGroup(ctx)
                                
                                reaper.ImGui_TextColored(ctx, colorTextDimmed, "Unmapped parameters")
                                if reaper.ImGui_BeginTable(ctx, 'Not mapped parameters', 1, reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_Borders(), tableWidth) then
                                   
                                    for _, val in ipairs(unmappedParams) do
                                        
                                        reaper.ImGui_TableNextRow(ctx)
                                        reaper.ImGui_TableNextColumn(ctx)
                                        if reaper.ImGui_Selectable(ctx, val.param .. " - " .. val.name, false) then 
                                             if not pluginPos[plugin.fxIndex][val.param] then
                                                pluginPos[plugin.fxIndex][val.param] = {param = val.param}
                                             end
                                             focusedMappedParamOverlay = pluginPos[plugin.fxIndex][val.param]
                                        end
                                    end 
                                     
                                    
                                    reaper.ImGui_EndTable(ctx)
                                end   
                                reaper.ImGui_EndGroup(ctx)
                                
                                reaper.ImGui_SameLine(ctx)
                                
                                reaper.ImGui_BeginGroup(ctx)
                                
                                reaper.ImGui_TextColored(ctx, colorTextDimmed, "Mapped parameters")
                                if reaper.ImGui_BeginTable(ctx, 'Not mapped parameters', 1, reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_Borders(), tableWidth) then
                                   
                                    for _, val in ipairs(mappedParams) do
                                        
                                        reaper.ImGui_TableNextRow(ctx)
                                        reaper.ImGui_TableNextColumn(ctx)
                                        if reaper.ImGui_Selectable(ctx, val.param .. " - " .. val.name, false) then 
                                             if not pluginPos[plugin.fxIndex][val.param] then
                                                pluginPos[plugin.fxIndex][val.param] = {param = val.param}
                                             end
                                             focusedMappedParamOverlay = pluginPos[plugin.fxIndex][val.param]
                                        end
                                    end 
                                     
                                    
                                    reaper.ImGui_EndTable(ctx)
                                end   
                                reaper.ImGui_EndGroup(ctx)
                                
                                
                                reaper.ImGui_EndTabItem(ctx)
                            end
                            
                            if reaper.ImGui_BeginTabItem(ctx, "Position/Size", nil, selected_position_tab ) then
                                
                                local inputDoubleWidth = 40-- editorWinWidth / (isSquare and 4 or 3) - 16 * (isSquare and 3 or 3)
                                if not focusedMappedParamOverlay then
                                    selected_selection_tab = reaper.ImGui_TabItemFlags_SetSelected()
                                else
                                    selected_position_tab = nil
                                    if not focusedMappedParamOverlay.x then
                                        if reaper.ImGui_Button(ctx, "Add overlay for parameter") then 
                                            local isSquare = isSuperPressed
                                            pluginPos[plugin.fxIndex][focusedMappedParamOverlay.param] = {param = focusedMappedParamOverlay.param, info = getAllDataFromParameter(track, plugin.fxIndex, focusedMappedParamOverlay.param), size = initialMappedOverlaySize/2, w = initialMappedOverlaySize, h = initialMappedOverlaySize, x = 0, y = 0, isSquare = isSquare}
                                            saveTempPlugPos(pluginPos)
                                        end
                                    else
                                        reaper.ImGui_AlignTextToFramePadding(ctx)
                                        reaper.ImGui_TextColored(ctx, colorWhite, "X ="); reaper.ImGui_SameLine(ctx); reaper.ImGui_SetNextItemWidth(ctx, inputDoubleWidth)
                                        local ret, val = reaper.ImGui_DragInt(ctx, "##XadvancedFloatingMapperEditor", focusedMappedParamOverlay.x, nil)
                                        if not isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then ret = true; val = focusedMappedParamOverlay.x - 1; end
                                        if not isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then ret = true; val = focusedMappedParamOverlay.x + 1; end
                                        if ret and val then
                                            focusedMappedParamOverlay.x = val
                                            saveTempPlugPos(pluginPos)
                                        end
                                        reaper.ImGui_SameLine(ctx)
                                        reaper.ImGui_TextColored(ctx, colorWhite, "Y ="); reaper.ImGui_SameLine(ctx); reaper.ImGui_SetNextItemWidth(ctx, inputDoubleWidth)
                                        local ret, val = reaper.ImGui_DragInt(ctx, "##YadvancedFloatingMapperEditor", focusedMappedParamOverlay.y)
                                        if not isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then ret = true; val = focusedMappedParamOverlay.y - 1; end
                                        if not isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then ret = true; val = focusedMappedParamOverlay.y + 1; end
                                        if ret and val then
                                            focusedMappedParamOverlay.y = val
                                            saveTempPlugPos(pluginPos)
                                        end
                                        
                                        reaper.ImGui_SameLine(ctx)
                                        if isSquare then
                                            reaper.ImGui_TextColored(ctx, colorWhite, "W ="); reaper.ImGui_SameLine(ctx); reaper.ImGui_SetNextItemWidth(ctx, inputDoubleWidth)
                                            local ret, val = reaper.ImGui_DragInt(ctx, "##WadvancedFloatingMapperEditor", focusedMappedParamOverlay.w)
                                            
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then ret = true; val = focusedMappedParamOverlay.w - 1; end
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then ret = true; val = focusedMappedParamOverlay.w + 1; end
                                            if ret and val then
                                                focusedMappedParamOverlay.w = val
                                                focusedMappedParamOverlay.size = math.min(focusedMappedParamOverlay.h, focusedMappedParamOverlay.w)
                                                saveTempPlugPos(pluginPos)
                                            end
                                            reaper.ImGui_SameLine(ctx)
                                            reaper.ImGui_TextColored(ctx, colorWhite, "H ="); reaper.ImGui_SameLine(ctx); reaper.ImGui_SetNextItemWidth(ctx, inputDoubleWidth)
                                            local ret, val = reaper.ImGui_DragInt(ctx, "##HadvancedFloatingMapperEditor", focusedMappedParamOverlay.h)
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then ret = true; val = focusedMappedParamOverlay.h - 1; end
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then ret = true; val = focusedMappedParamOverlay.h + 1; end
                                            if ret and val then
                                                focusedMappedParamOverlay.h = val
                                                focusedMappedParamOverlay.size = math.min(focusedMappedParamOverlay.h, focusedMappedParamOverlay.w)
                                                saveTempPlugPos(pluginPos)
                                            end
                                        else
                                            reaper.ImGui_TextColored(ctx, colorWhite, "Radius ="); reaper.ImGui_SameLine(ctx); reaper.ImGui_SetNextItemWidth(ctx, inputDoubleWidth)
                                            local ret, val = reaper.ImGui_DragInt(ctx, "##SizeadvancedFloatingMapperEditor", focusedMappedParamOverlay.size)
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow()) then ret = true; val = focusedMappedParamOverlay.size - 1; end
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow()) then ret = true; val = focusedMappedParamOverlay.size + 1; end
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then ret = true; val = focusedMappedParamOverlay.size + 1; end
                                            if isShiftPressed and not isSuperPressed and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then ret = true; val = focusedMappedParamOverlay.size - 1; end
                                            if ret and val then
                                                local valDif = focusedMappedParamOverlay.size - val
                                                focusedMappedParamOverlay.x = focusedMappedParamOverlay.x + valDif
                                                focusedMappedParamOverlay.y = focusedMappedParamOverlay.y + valDif
                                                
                                                focusedMappedParamOverlay.size = val
                                                focusedMappedParamOverlay.h = val * 2
                                                focusedMappedParamOverlay.w = val * 2
                                                saveTempPlugPos(pluginPos)
                                            end
                                        end
                                        
                                        local ret, val = reaper.ImGui_Checkbox(ctx, "Circle", not isSquare)
                                        if ret then
                                            focusedMappedParamOverlay.isSquare = not focusedMappedParamOverlay.isSquare
                                            saveTempPlugPos(pluginPos)
                                        end
                                    end
                                end 
                                
                                reaper.ImGui_EndTabItem(ctx)
                            end
                            
                            if reaper.ImGui_BeginTabItem(ctx, "Appearance") then
                                if not focusedMappedParamOverlay then
                                    selected_selection_tab = reaper.ImGui_TabItemFlags_SetSelected()
                                else
                                
                                end
                                reaper.ImGui_EndTabItem(ctx)
                            end 
                            
                            if reaper.ImGui_BeginTabItem(ctx, "Condition") then
                                if not focusedMappedParamOverlay then
                                    selected_selection_tab = reaper.ImGui_TabItemFlags_SetSelected()
                                else
                                
                                end
                                reaper.ImGui_EndTabItem(ctx)
                            end
                            
                            if reaper.ImGui_BeginTabItem(ctx, "FX Device Layout") then
                                if not focusedMappedParamOverlay then
                                    selected_selection_tab = reaper.ImGui_TabItemFlags_SetSelected()
                                else
                                
                                end
                                reaper.ImGui_EndTabItem(ctx)
                            end
                            
                            if focusedMappedParamOverlay then
                                if reaper.ImGui_TabItemButton(ctx, "Delete") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) then 
                                    pluginPos[plugin.fxIndex][focusedMappedParamOverlay.param] = nil
                                    focusedMappedParamOverlay = nil
                                end
                            end
                            if reaper.ImGui_BeginTabItem(ctx, "Settings") then 
                                
                                if reaper.ImGui_Button(ctx, "Reset mapper window size") then
                                    resetAdvancedFloatingMapperWindowSize = true
                                end
                                
                                if reaper.ImGui_Button(ctx, "Delete FX mapping") then
                                    pluginPos[plugin.fxIndex] = nil
                                end
                                reaper.ImGui_EndTabItem(ctx)
                            end
                            
                        --reaper.ImGui_DrawList_AddRect(draw_list, x,y, x2, y2, colorBlue, nil, nil, 4)
                        
                            reaper.ImGui_EndTabBar(ctx)
                        end
                        reaper.ImGui_End(ctx)
                    end 
                end
                
            end
            
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
       if mapActiveFxIndex then 
          mapActiveFxIndex = false
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
    
    if not ignoreKeypress then
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
                            reloadParameterLinkCatch = true
                        elseif name == "Redo" then
                            reaper.Main_OnCommand(40030, 0) --Edit: Redo    
                            reloadParameterLinkCatch = true
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
            
            function runCommand(s)
                local runCmd = s.external and reaper.NamedCommandLookup('_' .. s.command) or s.command
                if last_focused_reaper_section_id == reaper_sections["MIDI Editor"] then
                    --reaper.JS_Window_SetFocus(last_focused_midi_editor)
                    local midi_editor = reaper.MIDIEditor_GetActive()
                    
                    if midi_editor then
                        --last_focused_reaper_section_hwnd
                        reaper.MIDIEditor_OnCommand(midi_editor, runCmd)
                    end
                    --reaper.JS_Window_SetFocus(reaper.JS_Window_GetParent(appHwnd))
                else
                    reaper.Main_OnCommand(runCmd, 0)
                end
            end
              
            --local shortCut 
            if not alreadyUsed and newKeyPressed ~= "ESC" then
                shortCut = getPressedShortcut()  
                if settings.passAllUnusedShortcutThrough then
                    local s = lookForShortcutWithShortcut(newKeyPressed)
                    if not s then 
                        s = lookForShortcutWithShortcut(altKeyPressed)
                    end
                    if s then
                        runCommand(s)
                        lastKeyPressedTimeInitial = time
                    end
                else 
                    for _, s in ipairs(passThroughKeyCommands) do
                        
                        if s.scriptKeyPress == newKeyPressed or s.scriptKeyPress == altKeyPressed then
                            runCommand(s)
                            lastKeyPressedTimeInitial = time
                            break;
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
    end
    
    
    
    if settings.showScriptPerformance then
        elapsed = time - last_time 
        local updateTime = update_avg(elapsed) 
        
        local semiStaticCount = settings.useSemiStaticParamCatch and "("..paramsReadCountSemiStatic .. ")" or ""
        
        local averageParamsCountPerFrame
        if isMouseDown then 
             averageParamsCountPerFrame = paramsReadCount + math.ceil(paramsReadCountSemiStatic / 1)
        else
            averageParamsCountPerFrame =  paramsReadCount + math.ceil(paramsReadCountSemiStatic * ((1 / updateTime) / settings.checkSemiStaticParamsEvery))-- / ())
        end
        scriptPerformanceText = string.format("Script FPS: %.1f", 1 / updateTime) .. " | " .. "Param reading per frame: " .. paramsReadCount .. ", Semistatic params read : " .. paramsReadCountSemiStatic .. ", avarage in total per frame to: " .. averageParamsCountPerFrame
        scriptPerformanceText2 = string.format("%.1f", 1 / updateTime) .. "\n" .. averageParamsCountPerFrame
        last_time = time
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

