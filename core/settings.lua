local gui = require "gui"
local settings = {
    enabled = false,
    salvage = false,
    path_angle = 10,
}

function settings:update_settings()
    settings.enabled = gui.elements.main_toggle:get()
    settings.salvage = gui.elements.salvage_toggle:get() -- Change this line
end

return settings