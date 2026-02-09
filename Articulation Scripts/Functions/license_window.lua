-- @noindex

local export = {}

local ctx2 = reaper.ImGui_CreateContext('Articulation Script - License')

local license = require("check_license")
-- License Window (ReaImGui)
-- Intended to be used in LUAC

local registeredEmail, registeredCode = license.registered_license()
local isDemo = license.is_demo_valid()
--local isFree = license.check_articulation_script_list()
-- UI state
local email_buf = registeredEmail and registeredEmail or ''
local code_buf  = registeredCode and registeredCode or ''
local status_msg = (registeredEmail and registeredCode) and 'Active license installed1' or ('Activation requires an active internet connection')
local validLicense = (registeredEmail and registeredCode)

local devMode = scriptPath:match("jesperankarfeldt") ~= nil
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
------------------------------------------------------------
-- UI loop
------------------------------------------------------------
local function beginloop()
    local visible, open = reaper.ImGui_Begin(ctx2, 'Activate License', true, 
    reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_TopMost())
    if visible then
        local text = 
[[Hi there. Thanks for your interest in my "Articulation Scripts" system.

These scripts are the result of 2 years work, and over 15 years of thinking and experience.
Therefor I ask for a donation of a minimum of $60, which works as a perpetual license. 
(You can use the scripts for free if you have less than 6 articulation maps)

On the Paypal page please SUBMIT YOUR EMAIL and you will receive an activation code 
for that email, on that email, within 24 hours! The license is personal.

Paypal charges 2.9% + $0.30 per donation. 
After that I'll give 10% of all sales to ReaImGui and ReaPack development.

I will continue developing the functionallity of these script, and will love any feedback and wishes for them.

These scripts were made for professionals composers, that see the value in them. 
You could probably create some simple articulations scripts with a AI chatbot. 
If that feels better to you, then I encurage you to do that. Regardless of how many license that are bought, 
I'll never have the many many hours invested in this project covered. 

Best regards, Jesper
]]  

        reaper.ImGui_SetNextWindowSize(ctx2, 600, 436, reaper.ImGui_Cond_Appearing())
    
        if isDemo then 
            reaper.ImGui_Text(ctx2, "This is a beta version of the script which ends on 2026-03-01")
            reaper.ImGui_BeginDisabled(ctx2) 
        end
    
        reaper.ImGui_Text(ctx2, text)
        --reaper.ImGui_Text(ctx2, 'Enter your license information:')
        reaper.ImGui_Separator(ctx2)

        retval, email_buf = reaper.ImGui_InputText(ctx2, 'Email', email_buf, reaper.ImGui_InputTextFlags_CharsNoBlank())

        retval, code_buf = reaper.ImGui_InputText(ctx2, 'License Code', code_buf)
        
        
        if not isDemo and status_msg ~= '' then
            reaper.ImGui_TextColored(ctx2, 0x999999FF, status_msg)
        end
        
        reaper.ImGui_Spacing(ctx2)
        
        if validLicense or not devMode then reaper.ImGui_BeginDisabled(ctx2) end
            if reaper.ImGui_Button(ctx2, 'Activate', 120, 0) then
                --if license.verify_code(email_buf, code_buf) then
                    license.save_license(email_buf, code_buf)
                    status_msg = 'License activated successfully.'
                    visible = false
                    validLicense = true
                --else
                --    status_msg = 'Invalid license. Please check your details.'
                --end
            end
        if validLicense or not devMode then reaper.ImGui_EndDisabled(ctx2) end

        reaper.ImGui_SameLine(ctx2)
        
        
        if isDemo then reaper.ImGui_EndDisabled(ctx2) end

        if reaper.ImGui_Button(ctx2, (isDemo or validLicense) and 'Support development' or 'Buy License') then
            openWebpage(BUY_URL)
            --reaper.CF_ShellExecute(BUY_URL)
        end

        
        reaper.ImGui_SameLine(ctx2)
        
        if reaper.ImGui_Button(ctx2, 'Website', 60, 0) then
            openWebpage(SUPPORT_URL)
        end
        
        reaper.ImGui_SameLine(ctx2)
        if reaper.ImGui_Button(ctx2, 'Close', 60, 0) then
            open = false
        end
        
        reaper.ImGui_End(ctx2)
    end

    if not visible then 
        return validLicense
    end
    
    if open then 
        reaper.defer(beginloop)
    
    end
end

function export.loop()
    beginloop()
end
--export.loop()

return export
