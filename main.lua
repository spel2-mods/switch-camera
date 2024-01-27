---@diagnostic disable: lowercase-global

meta = {
	name = "Switch Camera",
	version = "0.4",
	description = "switch camera when you are a ghost or local co-op",
	author = "fienestar",
	online_safe = true,
}

--require "spel2.lua"

---@type nil
state = nil -- should use get_local_state() instead
---@type nil
players = nil -- should use get_local_players() instead

set_camera_layer_control_enabled(false)

local local_player_slot = 1
local focused_player_slot = 1
local is_online = false
local is_local_player_dead = false

set_callback(function ()
    is_online = true
end, ON.ONLINE_LOBBY)

set_callback(function ()
    is_online = false
end, ON.MENU)

set_callback(function ()
    if is_online then
        local_player_slot = online.lobby.local_player_slot
    else
        local_player_slot = 1
    end
end, ON.LOADING)

---@param slot number
function get_local_player(slot)
    local players = get_local_players()
    for _, player in ipairs(players) do
        if player.inventory.player_slot == slot then
            return player
        end
    end
end

local last_input_door_pressed = { 0, 0, 0, 0 }
function is_door_button_pressed()
    local state = get_local_state()
    local result = false
    local current_ms = get_ms()

    for slot, input in ipairs(state.player_inputs.player_slots) do
        if (not is_online) or slot == local_player_slot then
            local player = get_local_player(slot)

            if player == nil or player.health == 0 then
                local input_buttons = input.buttons_gameplay
                local input_door_pressed = test_mask(input_buttons, INPUTS.DOOR)
        
                if input_door_pressed then
                    if current_ms - last_input_door_pressed[slot] >= 120 then
                        result = true
                    end
                    last_input_door_pressed[slot] = current_ms
                end
            end
        end
    end
    
    return result
end

function get_pressed_number_key()
    local keyboard = get_raw_input().keyboard
    for i = 0, 4 do
        if keyboard[65 + i].pressed then
            return i
        end
    end
    return nil
end

function check_transition()
    local state = get_local_state()
    if state.camera.focused_entity_uid ~= -1 then
        local layer = get_entity(state.camera.focused_entity_uid).layer
        if state.camera_layer ~= layer then
            state.layer_transition_timer = 36
            state.transition_to_layer = layer
            state.camera_layer = layer
        end
    end
end

function get_is_local_player_dead()
    local player = get_local_player(local_player_slot)
    return player == nil or player.health == 0
end

function get_real_focused_player_slot()
    local state = get_local_state()
    local players = get_local_players()
    for _, player in ipairs(players) do
        if player.uid == state.camera.focused_entity_uid then
            return player.inventory.player_slot
        end
    end

    return nil
end

function focus_player(slot)
    local state = get_local_state()
    local player = get_local_player(slot)

    state.camera.focused_entity_uid = player.uid
    focused_player_slot = slot
end

-- focused entity can be rollbacked
-- so should be restored
function restore_focused_player()
    local real_focused_player_slot = get_real_focused_player_slot()
    if real_focused_player_slot == nil or focused_player_slot == real_focused_player_slot then
        return
    end

    local player = get_local_player(focused_player_slot)
    if player == nil or player.health == 0 then
        focused_player_slot = real_focused_player_slot
    else
        focus_player(focused_player_slot)
    end
end

function next_slot(slot)
    if slot == 4 then
        return 1
    else
        return slot + 1
    end
end

function switch_to_next_camera()
    local current_slot = focused_player_slot
    if current_slot == nil then
        return
    end

    local slot = next_slot(current_slot)
    while slot ~= current_slot do
        local player = get_local_player(slot)
        if player ~= nil and player.health ~= 0 then
            focus_player(slot)
            return
        end
        slot = next_slot(slot)
    end
end

set_callback(function()
    local state = get_local_state()
    state.camera_layer = LAYER.FRONT
end, ON.LEVEL)

function process_door_button()
    if is_door_button_pressed() then
        switch_to_next_camera()
        return true
    end

    return false
end

function process_number_button()
    local number_key = get_pressed_number_key()
    if number_key ~= nil then
        if number_key == 0 then
            number_key = local_player_slot
        elseif number_key ~= local_player_slot and is_online and (not is_local_player_dead) then
            return false
        end

        local selected_player = get_local_player(number_key)
        if selected_player ~= nil and selected_player.health ~= 0 then
            focus_player(number_key)
            return true
        end
    end

    return false
end

function process_input()
    if not process_door_button() then
        process_number_button()
    end
end

function process_resurrection()
    local real_is_local_player_dead = get_is_local_player_dead()
    if is_local_player_dead ~= real_is_local_player_dead then
        is_local_player_dead = real_is_local_player_dead
        if not is_local_player_dead and is_online then
            focus_player(local_player_slot)
        end
    end
end

set_callback(function()
    local state = get_local_state()
    if state.screen ~= SCREEN.LEVEL or state.pause ~= 0 then
        return
    end

    restore_focused_player()
    process_resurrection()
    process_input()
    check_transition()
end, ON.PRE_UPDATE)
