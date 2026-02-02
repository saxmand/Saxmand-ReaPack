-- @description Articulation Script License Window
-- @author Saxmand
-- @package Articulation Scripts
-- @version 0.0.2
-- @provides
--   Helpers/*.lua

local is_new_value, filename, sectionID, cmdID, mode, resolution, val, contextstr = reaper.get_action_context()
local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
local scriptPath = debug.getinfo(1, 'S').source:match("@(.*[/\\])")
local scriptPathSubfolder = scriptPath .. "Functions" .. seperator   

local devMode = scriptPath:match("jesperankarfeldt") ~= nil
if devMode then
    local devFilesPath = reaper.GetResourcePath() .. "/Scripts/Jesper/Articulations/Functions/"
    package.path = package.path .. ";" .. devFilesPath .. "?.lua"
else
    package.path = package.path .. ";" .. scriptPathSubfolder .. "?.luac"
end
package.path = package.path .. ";" .. scriptPathSubfolder .. "?.lua"
package.path = package.path .. ";" .. scriptPathSubfolder .. "Helpers" .. seperator  .. "?.lua"


local devMode = scriptPath:match("jesperankarfeldt") ~= nil

local license = require("check_license")
local ctx = reaper.ImGui_CreateContext('Articulation Script - License')

local registeredEmail, registeredCode = license.registered_license()
local isDemo = license.is_demo_valid()
--local isFree = license.check_articulation_script_list()
-- UI state
local email_buf = registeredEmail and registeredEmail or ''
local code_buf  = registeredCode and registeredCode or ''
local status_msg = (registeredEmail and registeredCode) and 'Active license installed' or ('Activation requires an active internet connection')
local validLicense = (registeredEmail and registeredCode)

-- Function to set the toolbar icon state
local function setToolbarState(isActive)
    -- Set the command state to 1 for active, 0 for inactive
    reaper.SetToggleCommandState(0, cmdID, isActive and 1 or 0)
    reaper.RefreshToolbar(0) -- Refresh the toolbar to update the icon
end

local function exit()
    setToolbarState(false)
end


-- URLs
local BUY_URL     = "https://www.paypal.com/paypalme/saxmand"
local SUPPORT_URL = "https://forum.cockos.com/showthread.php?t=299999"

local function openWebpage(url)
    if reaper.GetOS():match("Win") then
    os.execute('start "" "' .. url .. '"')
    elseif reaper.GetOS():match("mac") then
    os.execute('open "' .. url .. '"')
    else -- Assume Linux
    os.execute('xdg-open "' .. url .. '"')
    end
end

local text = 
[[Hi there. Thanks for your interest in my "Articulation Scripts" system.

These scripts are the result of 2 years work, and over 15 years of thinking and experience.
Therefor I ask for a donation of a minimum of $60, which works as a perpetual license. 
(You can use the scripts for free if you have 6 or less articulation maps)

On the Paypal page please SUBMIT YOUR EMAIL and you will receive an activation code 
for that email, on that email, within 24 hours! The license is personal.

Paypal charges 2.9% + $0.30 per donation. 
After that I'll give 10% of all sales to ReaImGui and ReaPack development. 
Nothing could be done without the work of those who paved the way <3

I will continue developing the functionallity of Articulation scripts, 
and will love any feedback and wishes for them.

These scripts were made for professionals composers, that see the value in them!! 
You could probably create some simple articulations scripts with a AI chatbot. 
If that feels better to you, then I encurage you to do that :) 

Best regards, Jesper
]]  
------------------------------------------------------------
-- UI loop
------------------------------------------------------------
local function loop()
    
    reaper.ImGui_SetNextWindowSize(ctx, 600, 456, reaper.ImGui_Cond_Appearing())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Articulation scripts - License window', true, 
    reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_TopMost() | reaper.ImGui_WindowFlags_NoCollapse())
    if visible then
                
        local isEscape = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())

        if isDemo then 
            reaper.ImGui_Text(ctx, "This is a beta version of the script which will work until 2026-03-01")
            reaper.ImGui_BeginDisabled(ctx) 
        end
    
        reaper.ImGui_TextColored(ctx, 0x999999FF, text)
        --reaper.ImGui_Text(ctx, 'Enter your license information:')
        reaper.ImGui_Separator(ctx)

        retval, email_buf = reaper.ImGui_InputText(ctx, 'Email', email_buf, reaper.ImGui_InputTextFlags_CharsNoBlank())

        retval, code_buf = reaper.ImGui_InputText(ctx, 'License Code', code_buf)
        
        local wasIsNoteValid = validLicense
        if not isDemo and status_msg ~= '' then
            reaper.ImGui_TextColored(ctx, 0x999999FF, status_msg)
        end
        
        reaper.ImGui_Spacing(ctx)
        
        if wasIsNoteValid then reaper.ImGui_BeginDisabled(ctx) end
            if reaper.ImGui_Button(ctx, 'Activate', 120, 0) then
                if license.verify_code(email_buf, code_buf) then
                    if license.save_license(email_buf, code_buf) then
                        status_msg = 'License activated successfully.'
                        visible = false
                        validLicense = true
                    else
                        status_msg = 'No internet. Please check your connection.'    
                    end
                else
                    status_msg = 'Invalid license. Please check your details.'
                end
            end
        if wasIsNoteValid then reaper.ImGui_EndDisabled(ctx) end

        reaper.ImGui_SameLine(ctx)
        
        
        if isDemo then reaper.ImGui_EndDisabled(ctx) end

        if reaper.ImGui_Button(ctx, (isDemo or validLicense) and 'Support development' or 'Buy License') then
            openWebpage(BUY_URL)
            --reaper.CF_ShellExecute(BUY_URL)
        end

        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, 'Website', 60, 0) then
            openWebpage(SUPPORT_URL)
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, 'Close', 60, 0) or isEscape then
            open = false
        end
        
        if devMode then 
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, 'Remove', 60, 0) then
                reaper.SetExtState("ArticualtionScripts", "LicenseCode", "reset", false)
                reaper.SetExtState("ArticualtionScripts", "LicenseEmail", "reset", false)
            end
        end
        
        reaper.ImGui_End(ctx)
    end

    if not visible then 
        return validLicense
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
