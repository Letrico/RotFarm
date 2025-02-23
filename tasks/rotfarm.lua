local utils = require "core.utils"
local tracker = require "core.tracker"
local explorerlite = require "core.explorerlite"
local settings = require "core.settings"

local rotfarm_state = {
    INIT = "INIT",
    EXPLORE_ROTFARM = "EXPLORE_ROTFARM",
    MOVING_TO_COCOON = "MOVING_TO_COCOON",
    INTERACT_COCOON = "INTERACT_COCOON",
    STAY_NEAR_COCOON = "STAY_NEAR_COCOON",
    MOVING_TO_PYRE = "MOVING_TO_PYRE",
    INTERACT_PYRE = "INTERACT_PYRE",
    STAY_NEAR_PYRE = "STAY_NEAR_PYRE",
    MOVING_TO_WHISPER_CHEST = "MOVING_TO_WHISPER_CHEST",
    FIGHT_HUSK = "FIGHT_HUSK",
    -- FOLLOW_PATROL = "FOLLOW_PATROL",
    GO_NEAREST_COORDINATE = "GO_NEAREST_COORDINATE",
    BACK_TO_TOWN = "BACK_TO_TOWN"
}

local ni = 1
-- local stuck_threshold = 60 -- Tempo parado para ativar o explorer
local explorer_active = false
-- local stuck_check_time = os.clock()

-- -- Novas variáveis para controle de movimento
-- local last_movement_time = 0
-- local force_move_cooldown = 0
-- local previous_player_pos = nil -- Variável para armazenar a posição anterior do jogador

local rotfarm_tps = {
    {name = "Kehj_Ridge", id = 0x8C7B7, file = "tarsarak"},
    {name = "Hawe_Coast", id = 0xA491F, file = "backwater"},
    {name = "Step_Grassland", id = 0x2D392, file = "farobru"},
    {name = "Scos_Moors", id = 0xB92BE, file = "tirmair"},
    {name = "Frac_Taiga_E", id = 0x90A86, file = "margrave"},
    {name = "Frac_GaleValley", id = 0x833F8, file = "yelesna"},
    {name = "Scos_Highlands", id = 0xEED6B, file = "fatgoose"},
}

local function find_closest_target(name)
    local actors = actors_manager:get_all_actors()
    local closest_target = nil
    local closest_distance = math.huge

    for _, actor in pairs(actors) do
        if actor:get_skin_name():match(name) then
            local actor_pos = actor:get_position()
            local distance = utils.distance_to(actor_pos)
            if distance < closest_distance then
                closest_target = actor
                closest_distance = distance
            end
        end
    end

    if closest_target then
        return closest_target
    end
    return nil
end

local function find_closest_waypoint_index(waypoints)
    local index = nil
    local closest_coordinate = 10000

    for i, coordinate in ipairs(waypoints) do
        if utils.distance_to(coordinate) < closest_coordinate then
            closest_coordinate = utils.distance_to(coordinate)
            index = i
        end
    end
    return index
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

local function check_events(self)
    if find_closest_target("S07_WitchHunt_GnarledCocoon_Trigger") or find_closest_target("S07_GnarledCocoon_Large_IconProxy") then
        self.current_state = rotfarm_state.MOVING_TO_COCOON
    elseif find_closest_target(".*S07.*Boss.*") then
        self.current_state = rotfarm_state.FIGHT_HUSK
    elseif find_closest_target("WRLD_Switch_S07_SMP_CorpsePyre_Gizmo") and find_closest_target("WRLD_Switch_S07_SMP_CorpsePyre_Gizmo"):is_interactable() then
        self.current_state = rotfarm_state.MOVING_TO_PYRE
    -- elseif find_closest_target("VerbPrototype_VFX_ControlArea") then
    --     self.current_state = rotfarm_state.FOLLOW_PATROL
    elseif settings.whispering_chest and utils.have_whispering_key() and 
            find_closest_target("Spider_Chest_Rare_Locked_GamblingCurrency") and
            find_closest_target("Spider_Chest_Rare_Locked_GamblingCurrency"):is_interactable() and
            utils.distance_to(find_closest_target("Spider_Chest_Rare_Locked_GamblingCurrency")) < 15
    then
        self.current_state = rotfarm_state.MOVING_TO_WHISPER_CHEST
    end
end

local rotfarm_task = {
    name = "Explore Rotfarm",
    current_state = rotfarm_state.INIT,

    shouldExecute = function()
        return utils.is_in_rotfarm()
    end,

    Execute = function(self)
        -- console.print("Current state: " .. self.current_state)
        if get_local_player() and get_local_player():is_dead() then
            revive_at_checkpoint()
        end

        if LooteerPlugin then
            local looting = LooteerPlugin.getSettings('looting')
            if looting then
                explorerlite.is_task_running = true
                return
            end
        end

        if tracker.has_salvaged then
            self:return_from_salvage()
        elseif utils.is_inventory_full() then
            self:back_to_town()
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
        elseif self.current_state == rotfarm_state.MOVING_TO_PYRE then
            self:move_to_pyre()
        elseif self.current_state == rotfarm_state.INTERACT_PYRE then
            self:interact_pyre()
        elseif self.current_state == rotfarm_state.STAY_NEAR_PYRE then
            self:stay_near_pyre()
        elseif self.current_state == rotfarm_state.MOVING_TO_WHISPER_CHEST then
            self:move_to_whisper_chest()
        -- elseif self.current_state == rotfarm_state.FOLLOW_PATROL then
        --     self:follow_patrol()
        elseif self.current_state == rotfarm_state.FIGHT_HUSK then
            self:fight_husk()
        elseif self.current_state == rotfarm_state.GO_NEAREST_COORDINATE then
            self:go_to_nearest_coordinate()
        elseif self.current_state == rotfarm_state.BACK_TO_TOWN then
            self:back_to_town()
        end
    end,

    initiate_waypoints = function(self)
        explorerlite.is_task_running = true
        explorer_active = false
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

        check_events(self)

        local nearest_ni = find_closest_waypoint_index(tracker.waypoints)
        if nearest_ni and math.abs(nearest_ni - ni) > 5 then
            if nearest_ni == #tracker.waypoints then
                ni = 1
            else
                ni = nearest_ni
            end
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
        local target_cocoon = find_closest_target("S07_WitchHunt_GnarledCocoon_Trigger")
        local big_cocoon = find_closest_target("S07_GnarledCocoon_Large_IconProxy")
        if target_cocoon then 
            if utils.distance_to(target_cocoon) > 2 then
                -- console.print(string.format("Moving to cocoon"))
                explorerlite.is_task_running = false
                explorer_active = true
                explorerlite:set_custom_target(target_cocoon:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(target_cocoon:get_position())
                return
            else
                self.current_state = rotfarm_state.INTERACT_COCOON
            end
        elseif big_cocoon then
            if utils.distance_to(big_cocoon) > 2 then
                explorerlite.is_task_running = false
                explorer_active = true
                -- console.print(string.format("Moving to big cocoon"))
                explorerlite:set_custom_target(big_cocoon:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(big_cocoon:get_position())
                return
            else
                self.current_state = rotfarm_state.STAY_NEAR_COCOON
            end
        else
            self.current_state = rotfarm_state.STAY_NEAR_COCOON
        end
    end,

    interact_cocoon = function(self)
        local target_cocoon = find_closest_target("S07_WitchHunt_GnarledCocoon_Trigger")
        explorerlite.is_task_running = true
        if target_cocoon then
            if target_cocoon:is_interactable() then
                local try_interact_cocoon = interact_object(target_cocoon)
                -- console.print("Cocoon interaction result: " .. tostring(try_interact_cocoon))
                if try_interact_cocoon then
                    self.current_state = rotfarm_state.STAY_NEAR_COCOON
                end
            else
                self.current_state = rotfarm_state.STAY_NEAR_COCOON
            end
            
        else
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    stay_near_cocoon = function(self)
        local big_cocoon = find_closest_target("S07_GnarledCocoon_Large_IconProxy")
        local target_cocoon = find_closest_target("S07_WitchHunt_GnarledCocoon_Trigger")
        if big_cocoon  then
            if utils.distance_to(big_cocoon) > 3 then
                -- console.print(string.format("Stay near big cocoon"))
                explorerlite.is_task_running = false
                explorer_active = true
                explorerlite:set_custom_target(big_cocoon:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(big_cocoon:get_position())
                return
            end
        elseif target_cocoon then
            if target_cocoon:is_interactable() then 
                self.current_state = rotfarm_state.INTERACT_COCOON
            elseif utils.distance_to(target_cocoon) > 3 then
                -- console.print(string.format("Stay near small cocoon"))
                explorerlite.is_task_running = false
                explorer_active = true
                explorerlite:set_custom_target(target_cocoon:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(target_cocoon:get_position())
                return
            end
        else
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    move_to_pyre = function(self)
        local pyre = find_closest_target("WRLD_Switch_S07_SMP_CorpsePyre_Gizmo")
        if pyre then 
            if utils.distance_to(pyre) > 2 then
                -- console.print(string.format("Moving to pyre"))
                explorerlite.is_task_running = false
                explorer_active = true
                explorerlite:set_custom_target(pyre:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(pyre:get_position())
                return
            else
                self.current_state = rotfarm_state.INTERACT_PYRE
            end
        else
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    interact_pyre = function(self)
        local pyre = find_closest_target("WRLD_Switch_S07_SMP_CorpsePyre_Gizmo")
        if pyre then
            if pyre:is_interactable() then
                interact_object(pyre)
            else
                self.current_state = rotfarm_state.STAY_NEAR_PYRE
            end
        else
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    stay_near_pyre = function(self)
        if tracker.check_time("pyre_timeout", 60) then
            -- We know if pyre is bugged, area is cleared so end the farm
            self.current_state = rotfarm_state.BACK_TO_TOWN
            return
        end 
        local pyre = find_closest_target("WRLD_Switch_S07_SMP_CorpsePyre_Gizmo")
        local pyre_monster = find_closest_target("S07_SMP_CorpsePyre_Monster")
        if pyre and pyre_monster then
            if pyre:is_interactable() then
                self.current_state = rotfarm_state.INTERACT_PYRE
            elseif pyre_monster:get_current_health() > 1 then
                if utils.distance_to(pyre) > 3 then
                    -- console.print(string.format("Stay near pyre"))
                    explorerlite.is_task_running = false
                    explorer_active = true
                    explorerlite:set_custom_target(pyre:get_position())
                    explorerlite:move_to_target()
                    -- pathfinder.force_move(pyre:get_position())
                    return
                end
            else
                self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
            end
        else
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    -- follow_patrol = function(self)
    --     local patrol = find_closest_target("VerbPrototype_VFX_ControlArea")
    --     local roots = nearby_roots()
    --     if roots then
    --         self.current_task = rotfarm_state.MOVING_TO_COCOON
    --         return
    --     elseif patrol then
    --         if utils.distance_to(patrol) > 4 then
    --             console.print(string.format("Stay near patrol"))
    --             -- explorerlite:set_custom_target(big_cocoon:get_position())
    --             -- explorerlite:move_to_target()
    --             pathfinder.force_move(patrol:get_position())
    --             return
    --         end
    --     else
    --         self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
    --     end
    -- end,

    move_to_whisper_chest = function(self)
        local chest = find_closest_target("Spider_Chest_Rare_Locked_GamblingCurrency")
        if chest and chest:is_interactable() then 
            if utils.distance_to(chest) > 2 then
                -- console.print(string.format("Moving to chest"))
                explorerlite.is_task_running = false
                explorer_active = true
                explorerlite:set_custom_target(chest:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(chest:get_position())
                return
            else
                interact_object(chest)
            end
        else
            if not tracker.check_time("chest_drop_time", 4) then
                return
            end
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    fight_husk = function (self)
        local husk = find_closest_target(".*S07.*Boss.*")
        if husk and husk:get_current_health() > 1 then
            if utils.distance_to(husk) > 2 then
                -- console.print(string.format("Moving to husk"))
                explorerlite.is_task_running = false
                explorer_active = true
                explorerlite:set_custom_target(husk:get_position())
                explorerlite:move_to_target()
                -- pathfinder.force_move(husk:get_position())
                return
            end
        else
            self.current_state = rotfarm_state.GO_NEAREST_COORDINATE
        end
    end,

    go_to_nearest_coordinate = function(self)
        check_events(self)
        tracker.clear_key('chest_drop_time')
        tracker.clear_key('pyre_timeout')
        local nearest_ni = find_closest_waypoint_index(tracker.waypoints)
        if nearest_ni and math.abs(nearest_ni - ni) > 5 then
            ni = nearest_ni
        end
        explorerlite.is_task_running = false
        explorer_active = true
        if utils.distance_to(tracker.waypoints[ni]) > 4 then
            explorer_active = true
            explorerlite:set_custom_target(tracker.waypoints[ni])
            explorerlite:move_to_target()
        else
            explorer_active = false
            explorerlite.is_task_running = true
            self.current_state = rotfarm_state.EXPLORE_ROTFARM
        end
    end,

    back_to_town = function(self)
        explorerlite.is_task_running = true
        explorer_active = false
        -- console.print("Rotfarm completes")
        tracker.rotfarm_end = true
        -- completed one round, use alfred town task to reset season buff check
        if settings.salvage then
            tracker.needs_salvage = true
        end
    end,

    return_from_salvage = function(self)
        if not tracker.check_time("salvage_return_time", 3) then
            return
        end
        tracker.has_salvaged = false
        console.print("Restart rotfarm")
        ni = 1
        tracker.clear_key('salvage_return_time')
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