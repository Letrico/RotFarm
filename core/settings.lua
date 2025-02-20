local gui = require "gui"
local settings = {
    enabled = false,
    salvage = true,
    path_angle = 20,
    whispering_chest = true,
}

function settings:update_settings()
    settings.enabled = gui.elements.main_toggle:get()
    settings.salvage = gui.elements.salvage_toggle:get()
    settings.whispering_chest = gui.elements.whisper_chest_toggle:get()
end

return settings