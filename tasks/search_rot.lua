local utils = require "core.utils"
local tracker = require "core.tracker"
local rotfarm_task = require "tasks.rotfarm"

local current_city_index = 0

local rotfarm_tps = {
    {name = "Kehj_Ridge", id = 0x8C7B7, file = "tarsarak"},
    {name = "Hawe_Coast", id = 0xA491F, file = "backwater"},
    {name = "Step_Grassland", id = 0x2D392, file = "farobru"},
    {name = "Scos_Moors", id = 0xB92BE, file = "tirmair"},
    {name = "Frac_Taiga_E", id = 0x90A86, file = "margrave"},
    {name = "Frac_GaleValley", id = 0x833F8, file = "yelesna"},
    {name = "Scos_Highlands", id = 0xEED6B, file = "fatgoose"},
}

local search_rotfarm_state = {
    SEARCHING_ROTFARM = "SEARCHING_ROTFARM",
    TELEPORTING = "TELEPORTING",
    WAITING_FOR_TELEPORT = "WAITING_FOR_TELEPORT",
    FOUND_ROTFARM = "FOUND_ROTFARM",
}

local search_rotfarm_task = {
    name = "Search rotfarm",
    current_state = search_rotfarm_state.SEARCHING_ROTFARM,

    shouldExecute = function()
        return not utils.is_in_rotfarm()
    end,

    Execute = function(self)
        -- console.print("Current state: " .. self.current_state)

        if tracker.rotfarm_end then 
            self:reset()
        elseif self.current_state == search_rotfarm_state.SEARCHING_ROTFARM then
            self:searching_rotfarm()
        elseif self.current_state == search_rotfarm_state.TELEPORTING then
            self:teleporting_to_rotfarm()
        elseif self.current_state == search_rotfarm_state.WAITING_FOR_TELEPORT then
            self:waiting_for_teleport()
        elseif self.current_state == search_rotfarm_state.FOUND_ROTFARM then
            self:found_rotfarm()
        end
    end,

    searching_rotfarm = function(self)
        console.print("Initializing search rotfarm")
        if not utils.is_in_rotfarm() then
            console.print("Not in rotfarm, teleport to next town to check")
            self.current_state = search_rotfarm_state.TELEPORTING
        else
            console.print("Found rotfarm")
            self.current_state = search_rotfarm_state.FOUND_ROTFARM
        end
    end,

    teleporting_to_rotfarm = function(self)
        if not ( utils.player_in_zone(nil) or utils.player_in_zone("")) then
            if current_city_index > #rotfarm_tps then
                current_city_index = 1
            else
                current_city_index = (current_city_index % #rotfarm_tps) + 1
            end
            -- console.print("Teleporting to: " .. tostring(rotfarm_tps[current_city_index].file))
            tracker.wait_in_town = nil
            teleport_to_waypoint(rotfarm_tps[current_city_index].id)
            self.current_state = search_rotfarm_state.WAITING_FOR_TELEPORT
        else
            console.print("Currently in loading screen. Waiting before attempting teleport.")
            return
        end
    end,

    waiting_for_teleport = function(self)
        if utils.player_in_zone(rotfarm_tps[current_city_index].name) then
            if not tracker.check_time("wait_in_town", 3) then
                return
            end
            self.current_state = search_rotfarm_state.SEARCHING_ROTFARM
        else
            -- fail teleport, retry
            self.current_state = search_rotfarm_state.TELEPORTING
            return
        end
    end,

    found_rotfarm = function(self)
        console.print("Found rotfarm")
    end,

    reset = function(self)
        tracker.rotfarm_end = false
        rotfarm_task:reset()
        self.current_state = search_rotfarm_state.SEARCHING_ROTFARM
    end
}

return search_rotfarm_task