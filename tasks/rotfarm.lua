local utils = require "core.utils"
local tracker = require "core.tracker"
local explorer = require "core.explorer"
local settings = require "core.settings"

local rotfarm_state = {
    INIT = "INIT",
    EXPLORE_ROTFARM = "EXPLORE_ROTFARM",
    MOVING_TO_COCOON = "MOVING_TO_COCOON",
    INTERACT_COCOON = "INTERACT_COCOON",
    STAY_NEAR_COCOON = "STAY_NEAR_COCOON",
    BACK_TO_TOWN = "BACK_TO_TOWN"
}

local ni = 1
local stuck_threshold = 60 -- Tempo parado para ativar o explorer
local explorer_active = false
local stuck_check_time = os.clock()

-- Novas variáveis para controle de movimento
local last_movement_time = 0
local force_move_cooldown = 0
local previous_player_pos = nil -- Variável para armazenar a posição anterior do jogador

local rotfarm_tps = {
    {name = "Kehj_Ridge", id = 0x8C7B7, file = "tarsarak"},
    {name = "Hawe_Coast", id = 0xA491F, file = "backwater"},
    {name = "Step_Grassland", id = 0x2D392, file = "farobru"},
    {name = "Scos_Moors", id = 0xB92BE, file = "tirmair"},
    {name = "Frac_Taiga_E", id = 0x90A86, file = "margrave"},
    {name = "Frac_GaleValley", id = 0x833F8, file = "yelesna"},
    {name = "Scos_Highlands", id = 0xEED6B, file = "fatgoose"},
}

local function find_closest_cocoon()
    local actors = actors_manager:get_all_actors()
    local closest_cocoon = nil
    local closest_distance = math.huge

    for _, actor in pairs(actors) do
        if actor:get_skin_name():match("S07_WitchHunt_GnarledCocoon_Trigger") then
            local actor_pos = actor:get_position()
            local distance = utils.distance_to(actor_pos)
            if distance < closest_distance then
                closest_cocoon = actor
                closest_distance = distance
            end
        end
    end

    if closest_cocoon then
        return closest_cocoon
    end
    return nil
end

local function find_big_cocoon()
    local actors = actors_manager:get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "S07_GnarledCocoon_Large_IconProxy" then
            return actor
        end
    end
    return nil
end

local function get_distance(point)
    return get_player_position():dist_to(point)
end

local function load_waypoints(file)
    if file == "tarsarak" then
        tracker.waypoints = require("waypoints.tarsarak")
        console.print("Loaded waypoints: tarsarak")
    elseif file == "backwater" then
        tracker.waypoints = require("waypoints.backwater")
        console.print("Loaded waypoints: backwater")
    elseif file == "farobru" then
        tracker.waypoints = require("waypoints.farobru")
        console.print("Loaded waypoints: farobru")
    elseif file == "tirmair" then
        tracker.waypoints = require("waypoints.tirmair")
        console.print("Loaded waypoints: tirmair")
    elseif file == "margrave" then
        tracker.waypoints = require("waypoints.margrave")
        console.print("Loaded waypoints: margrave")
    elseif file == "yelesna" then
        tracker.waypoints = require("waypoints.yelesna")
        console.print("Loaded waypoints: yelesna")
    elseif file == "fatgoose" then
        tracker.waypoints = require("waypoints.fatgoose")
        console.print("Loaded waypoints: fatgoose")
    else
        console.print("No waypoints loaded")
    end
end

local function check_and_load_waypoints()
    for _, tp in ipairs(rotfarm_tps) do
        if utils.player_in_zone(tp.name) then
            load_waypoints(tp.file)
            return
        end
    end
end

local function randomize_waypoint(waypoint, max_offset)
    max_offset = max_offset or 1.5 -- Valor padrão de 1.5 metros
    local random_x = math.random() * max_offset * 2 - max_offset
    local random_y = math.random() * max_offset * 2 - max_offset
    
    local randomized_point = vec3:new(
        waypoint:x() + random_x,
        waypoint:y() + random_y,
        waypoint:z()
    )
    
    -- Garante que o ponto randomizado seja caminhável
    randomized_point = utility.set_height_of_valid_position(randomized_point)
    if utility.is_point_walkeable(randomized_point) then
        return randomized_point
    else
        return waypoint -- Retorna o waypoint original se o ponto randomizado não for caminhável
    end
end

local rotfarm_task = {
    name = "Explore Rotfarm",
    current_state = rotfarm_state.INIT,
    failed_attempts = 0,
    max_attempts = 100,

    shouldExecute = function()
        return utils.is_in_rotfarm()
    end,

    Execute = function(self)
        -- console.print("Current state: " .. self.current_state)

        if tracker.has_salvaged then
            self:return_from_salvage()
        elseif self.current_state == rotfarm_state.INIT then
            self:initiate_waypoints()
        elseif self.current_state == rotfarm_state.EXPLORE_ROTFARM then
            self:explore_rotfarm()
        elseif self.current_state == rotfarm_state.MOVING_TO_COCOON then
            self:move_to_cocoon()
        elseif self.current_state == rotfarm_state.INTERACT_COCOON then
            self:interact_cocoon()
        elseif self.current_state == rotfarm_state.STAY_NEAR_COCOON then
            self:stay_near_cocoon()
        elseif self.current_state == rotfarm_state.BACK_TO_TOWN then
            self:back_to_town()
        end
    end,

    initiate_waypoints = function(self)
        check_and_load_waypoints()
        self.current_state = rotfarm_state.EXPLORE_ROTFARM
    end,

    explore_rotfarm = function(self)
        if not utils.is_in_rotfarm() then
            self.current_state = rotfarm_state.BACK_TO_TOWN
        end

        if type(tracker.waypoints) ~= "table" then
            console.print("Error: waypoints is not a table")
            return
        end
    
        if type(ni) ~= "number" then
            console.print("Error: ni is not a number")
            return
        end

        if find_closest_cocoon() or find_big_cocoon() then
            self.current_state = rotfarm_state.MOVING_TO_COCOON
        end

        if ni > #tracker.waypoints or ni < 1 or #tracker.waypoints == 0 then
            self.current_state = rotfarm_state.BACK_TO_TOWN
            return
        end

        local current_waypoint = tracker.waypoints[ni]
        if current_waypoint then
            local distance = get_distance(current_waypoint)
            
            if distance < 2 then
                ni = ni + 1
            else
                if not explorer_active then
                    local randomized_waypoint = randomize_waypoint(current_waypoint)
                    pathfinder.request_move(randomized_waypoint)
                else
                    console.print("no explorer")
                end
            end
        end
    end,

    move_to_cocoon = function(self)
        explorer.is_task_running = true
        local target_cocoon = find_closest_cocoon()
        local big_cocoon = find_big_cocoon()
        if target_cocoon then 
            if utils.distance_to(target_cocoon) > 2 then
                console.print(string.format("Moving to cocoon"))
                -- explorer:set_custom_target(target_cocoon:get_position())
                -- explorer:move_to_target()
                pathfinder.force_move(target_cocoon:get_position())
                return
            else
                self.current_state = rotfarm_state.INTERACT_COCOON
            end
        elseif big_cocoon then
            if utils.distance_to(big_cocoon) > 2 then
                console.print(string.format("Moving to big cocoon"))
                -- explorer:set_custom_target(target_cocoon:get_position())
                -- explorer:move_to_target()
                pathfinder.force_move(big_cocoon:get_position())
                return
            else
                self.current_state = rotfarm_state.INTERACT_COCOON
            end
        else
            explorer.is_task_running = false
            self.current_state = rotfarm_state.STAY_NEAR_COCOON
        end
    end,

    interact_cocoon = function(self)
        explorer.is_task_running = true
        local big_cocoon = find_big_cocoon()
        local target_cocoon = find_closest_cocoon()
        if big_cocoon then
            self.current_state = rotfarm_state.STAY_NEAR_COCOON
        elseif target_cocoon then
            local try_interact_cocoon = interact_object(target_cocoon)
            -- console.print("Cocoon interaction result: " .. tostring(try_interact_cocoon))
            if try_interact_cocoon then
                local big_cocoon_triggered = find_big_cocoon()
                if big_cocoon_triggered then 
                    self.current_state = rotfarm_state.STAY_NEAR_COCOON
                end
            end
        else
            explorer.is_task_running = false
            self.current_state = rotfarm_state.EXPLORE_ROTFARM
        end
    end,

    stay_near_cocoon = function(self)
        explorer.is_task_running = true
        local big_cocoon = find_big_cocoon()
        if big_cocoon then
            if utils.distance_to(big_cocoon) > 4 then
                console.print(string.format("Stay near big cocoon"))
                -- explorer:set_custom_target(big_cocoon:get_position())
                -- explorer:move_to_target()
                pathfinder.force_move(big_cocoon:get_position())
                return
            end
        else
            explorer.is_task_running = false
            self.current_state = rotfarm_state.EXPLORE_ROTFARM
        end
    end,

    back_to_town = function(self)
        console.print("Rotfarm completes")
        tracker.rotfarm_end = true
        -- completed one round, use alfred town task to reset season buff check
        if settings.salvage then
            tracker.needs_salvage = true
        end
    end,

    return_from_salvage = function(self)
        if not tracker.check_time("salvage_return_time", 3) then
            console.print("Waiting before resuming rotfarm")
            return
        end
        tracker.has_salvaged = false
        console.print("Restart rotfarm")
        ni = 1
        self.current_state = rotfarm_state.EXPLORE_ROTFARM
    end,

    reset = function(self)
        ni = 1
        self.current_state = rotfarm_state.INIT
        tracker.has_salvaged = false
        tracker.needs_salvage = false
    end
}

return rotfarm_task