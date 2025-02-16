local gui = {}
local plugin_label = "Rot Farmer - Letrico Edition"

local function create_checkbox(key)
    return checkbox:new(false, get_hash(plugin_label .. "_" .. key))
end

gui.elements = {
    main_tree = tree_node:new(0),
    main_toggle = create_checkbox("main_toggle"),
    settings_tree = tree_node:new(1),
    salvage_toggle = create_checkbox(plugin_label .. "salvage_toggle"),
}

function gui.render()
    if not gui.elements.main_tree:push(plugin_label) then return end

    gui.elements.main_toggle:render("Enable", "Enable the bot")
    
    if gui.elements.settings_tree:push("Settings") then
        gui.elements.salvage_toggle:render("Salvage with alfred", "Enable salvaging items with alfred")
        gui.elements.settings_tree:pop()
    end

    gui.elements.main_tree:pop()
end

return gui