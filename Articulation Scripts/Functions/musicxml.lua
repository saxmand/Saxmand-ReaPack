-- @version 1.0
-- @noindex

local export = {}

export.articulations = {
  {name = "Default", area = "", text = ""},
  {area = "note", text = "staccato", name = "Staccato" },
  {area = "note", text = "staccatissimo", name = "Staccatissimo" },
  {area = "note", text = "tenuto", name = "Tenuto" },
  {area = "note", text = "accent", name = "Accent" },
  {area = "note", text = "marcato", name = "Marcato" },
  {area = "note", text = "portato", name = "Portato" },
  {area = "note", text = "tremolo", name = "Tremolo" },
  {area = "note", text = "gracenote", name = "Gracenote" },

  {area = "note", text = "trill", name = "Trills Minor" },
  {area = "note", text = "whole_note_trill", name = "Trills Major" },
  
  {area = "track", text = "pizz.", name = "Pizz." },
  --{ text = "soft-accent", name = "Soft Accent" },


  --{ text = "stress", name = "Stress" },
  --{ text = "unstress", name = "Unstress" },

  --{ text = "scoop", name = "Scoop" },
  --{ text = "plop", name = "Plop" },
  --{ text = "doit", name = "Doit" },
  --{ text = "falloff", name = "Falloff" },
}

function export.withinNotationArea(artName, areaName)
    for _, art in ipairs(export.articulations) do
        if art.name == artName and art.area == areaName then
            return true
        end
    end
    return false
end

function export.getNotationText(artName)
    for _, art in ipairs(export.articulations) do
        if art.name == artName then
            return art.text
        end
    end
    return artName
end


return export
