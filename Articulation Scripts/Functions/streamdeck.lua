-- @noindex

local export = {}



function export.check()
  local is_windows = reaper.GetOS():find("Win")

  local sd_installed, plugin_installed

  if is_windows then
    local pf      = os.getenv("PROGRAMFILES") or "C:\\Program Files"
    local appdata = os.getenv("APPDATA")       or ""

    sd_installed     = reaper.file_exists(pf .. "\\Elgato\\StreamDeck\\StreamDeck.exe")
    plugin_installed = reaper.file_exists(
      appdata .. "\\Elgato\\StreamDeck\\Plugins\\dev.reaper.articulation.sdPlugin\\manifest.json"
    )
  else
    local home = os.getenv("HOME") or ""

    sd_installed = reaper.file_exists("/Applications/Elgato Stream Deck.app")
               or reaper.file_exists(home .. "/Applications/Elgato Stream Deck.app")
    plugin_installed = reaper.file_exists(
      home .. "/Library/Application Support/com.elgato.StreamDeck/Plugins/dev.reaper.articulation.sdPlugin/manifest.json"
    )
  end

  return sd_installed, plugin_installed
end

function export.install_plugin()
  local script_path = debug.getinfo(1, "S").source:match("^@(.+[/\\])")
  local seperator = package.config:sub(1,1)  -- path separator: '/' on Unix, '\\' on Windows
  local plugin_folder = script_path .. "streamdeck" .. seperator
  local plugin_file = plugin_folder .. "dev.reaper.articulation.streamDeckPlugin"

--reaper.ShowConsoleMsg(tostring(plugin_file) .. "\n")
--file_handling.openFolderInExplorer(plugin_folder) 
  local os_name = reaper.GetOS()
  if os_name:find("Win") then
    os.execute('start "" "' .. plugin_file .. '"')
  else
    os.execute('open "' .. plugin_file .. '"')
  end
end

return export
