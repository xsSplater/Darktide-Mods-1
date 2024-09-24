-- Guarantee Weapon Swap by KamiUnitY. Ver. 1.3.2

local mod = get_mod("guarantee_weapon_swap")
local modding_tools = get_mod("modding_tools")

---------------
-- CONSTANTS --
---------------

local PROMISE_ACTION_MAP = {
    quick_wield             = "quick",
    wield_1                 = "primary",
    wield_2                 = "secondary",
    wield_3                 = "pocketable",
    wield_4                 = "pocketable_small",
    wield_5                 = "device",
    grenade_ability_pressed = "grenade",
}

local PROMISE_SLOT_MAP = {
    slot_primary          = "primary",
    slot_secondary        = "secondary",
    slot_pocketable       = "pocketable",
    slot_pocketable_small = "pocketable_small",
    slot_device           = "device",
    slot_grenade_ability  = "grenade",
}

local SLOT_ACTION_MAP = {
    primary          = "slot_primary",
    secondary        = "slot_secondary",
    pocketable       = "slot_pocketable",
    pocketable_small = "slot_pocketable_small",
    device           = "slot_device",
    grenade          = "slot_grenade_ability",
}

local ALLOWED_CHARACTER_STATE = {
    dodging        = true,
    ledge_vaulting = true,
    lunging        = true,
    sliding        = true,
    sprinting      = true,
    stunned        = true,
    walking        = true,
    jumping        = true,
    falling        = true,
}

---------------
-- VARIABLES --
---------------

mod.promise_exist = false

mod.promises = {
    quick            = false,
    primary          = false,
    secondary        = false,
    pocketable       = false,
    pocketable_small = false,
    device           = false,
    grenade          = false,
}

local is_attack_prevent_weapon = false

local is_in_hub = false

local grenade_ability = ""

local current_slot = ""
local previous_slot = ""

local character_state = ""

---------------
-- UTILITIES --
---------------

---@class tablelib
---@field contains function

local debug = {
    is_enabled = function(self)
        return mod.settings["enable_debug_modding_tools"] and modding_tools and modding_tools:is_enabled()
    end,
    print = function(self, text)
        pcall(function() modding_tools:console_print(text) end)
    end,
    print_mod = function(self, text)
        if self:is_enabled() then
            self:print(mod:localize("mod_name") .. ": " .. text)
        end
    end,
}

local _is_in_hub = function()
    local game_mode_manager = Managers.state.game_mode
    local game_mode_name = game_mode_manager and game_mode_manager:game_mode_name()
    return game_mode_name == "hub"
end

--------------------------
-- MOD SETTINGS CACHING --
--------------------------

mod.settings = {
    enable_zealot_throwing_knives = mod:get("enable_zealot_throwing_knives"),
    enable_debug_modding_tools    = mod:get("enable_debug_modding_tools"),
}

mod.on_setting_changed = function(setting_id)
    mod.settings[setting_id] = mod:get(setting_id)
end

------------------------
-- ON ALL MODS LOADED --
------------------------

mod.on_all_mods_loaded = function()
    -- Update is_in_hub
    is_in_hub = _is_in_hub()

    -- WATCHER
    -- modding_tools:watch("promise_exist",mod,"promise_exist")
    -- modding_tools:watch("character_state",mod,"character_state")
end

---------------------------
-- ON GAME STATE CHANGED --
---------------------------

mod.on_game_state_changed = function(status, state_name)
    -- Update is_in_hub
    is_in_hub = _is_in_hub()
end

-----------------------
-- PROMISE FUNCTIONS --
-----------------------

local function setPromise(action)
    if not mod.promises[action] then
        mod.promises[action] = true
        mod.promise_exist = true
    end
end

local function clearPromise(action)
    if mod.promises[action] then
        mod.promises[action] = false
        mod.promise_exist = table.contains(mod.promises, true)
    end
end

local function clearAllPromises()
    if mod.promise_exist then
        for key in pairs(mod.promises) do
            mod.promises[key] = false
        end
        mod.promise_exist = false
    end
end

local function isPromised(action)
    local promise = mod.promises[action]

    if promise then
        if current_slot == SLOT_ACTION_MAP[action] then
            clearPromise(action)
            return false
        end
        if modding_tools then debug:print_mod("Attempting to switch weapon !!!") end
    end

    return promise
end

----------------
-- ON TRIGGER --
----------------

-- CLEAR PROMISE ON ENTER OR EXIT GAMEPLAY

mod:hook_safe("GameplayStateRun", "on_enter", function(...)
    clearAllPromises()
end)

mod:hook_safe("GameplayStateRun", "on_exit", function(...)
    clearAllPromises()
end)

-- CLEAR PROMISE ON SUCCESSFULLY CHANGE WEAPON

local function _on_slot_wielded(self)
    local inventory_component = self._inventory_component
    local wielded_slot = inventory_component.wielded_slot

    if wielded_slot ~= current_slot then
        previous_slot = current_slot
        current_slot = wielded_slot

        local slot_weapon = self._weapons[current_slot]
        local weapon_template = slot_weapon and slot_weapon.weapon_template
        local weapon_keywords = weapon_template and weapon_template.keywords
        is_attack_prevent_weapon = weapon_keywords and (
            table.contains(weapon_keywords, "psyker") or
            table.contains(weapon_keywords, "force_staff")
        )

        clearPromise("quick")
        clearPromise(PROMISE_SLOT_MAP[current_slot])

        if current_slot ~= "" and previous_slot ~= "" then
            if modding_tools then debug:print_mod(previous_slot .. " -> " .. current_slot) end
        end
    end
end

mod:hook_safe("PlayerUnitWeaponExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if current_slot ~= "" then
        mod:hook_disable("PlayerUnitWeaponExtension", "fixed_update")
    end
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "on_slot_wielded", function(self, slot_name, t, skip_wield_action)
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

mod:hook_safe("PlayerUnitWeaponExtension", "server_correction_occurred", function(self, unit)
    if self._player.viewport_name == "player1" then
        _on_slot_wielded(self)
    end
end)

-- CLEAR PROMISE ON FAILING TO WIELD GRENADE

mod:hook("PlayerUnitAbilityExtension", "can_wield", function(func, self, slot_name, previous_check)
    local can_wield = func(self, slot_name, previous_check)
    if self._player.viewport_name == "player1" then
        if slot_name == "slot_grenade_ability" then
            if not can_wield then
                clearPromise("grenade")
            elseif self._equipped_abilities.grenade_ability.name == "zealot_throwing_knives" then
                clearPromise("grenade")
            end
        end
    end
    return can_wield
end)

-- CLEAR PROMISE FOR NOT AVAILABLE ITEMS

mod:hook("PlayerUnitWeaponExtension", "can_wield", function(func, self, slot_name)
    local can_wield = func(self, slot_name)
    if self._player.viewport_name == "player1" then
        if not can_wield then
            clearPromise(PROMISE_SLOT_MAP[slot_name])
        end
    end
    return can_wield
end)

-- UPDATE CHARACTER STATE VARIABLE AND CLEAR PROMISE ON UNALLOWED CHARACTER STATE

local _on_character_state_change = function (self)
    character_state = self._state_current.name
    if not ALLOWED_CHARACTER_STATE[character_state] then
        clearAllPromises()
    end
end

mod:hook_safe("CharacterStateMachine", "fixed_update", function(self, unit, dt, t, frame, ...)
    if character_state ~= "" then
        mod:hook_disable("CharacterStateMachine", "fixed_update")
    end
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "_change_state", function(self, unit, dt, t, next_state, ...)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

mod:hook_safe("CharacterStateMachine", "server_correction_occurred", function(self, unit)
    if self._unit_data_extension._player.viewport_name == 'player1' then
        _on_character_state_change(self)
    end
end)

-- UPDATE GRENADE ABILITY VARIABLE

mod:hook_safe("PlayerUnitAbilityExtension", "fixed_update", function(self, unit, dt, t, fixed_frame)
    if grenade_ability ~= "" then
        mod:hook_disable("PlayerUnitAbilityExtension", "fixed_update")
    end
    if self._player.viewport_name == "player1" then
        local _grenade_ability = self._equipped_abilities.grenade_ability
        if _grenade_ability ~= nil then
            grenade_ability = _grenade_ability.name
        end
    end
end)

mod:hook_safe("PlayerUnitAbilityExtension", "equip_ability", function(self, ability_type, ability, fixed_t)
    if self._player.viewport_name == "player1" then
        if ability_type == "grenade_ability" then
            grenade_ability = ability.name
        end
    end
end)

--------------------
-- ON EVERY FRAME --
--------------------

----------------
-- INPUT HOOK --
----------------

local _input_hook = function(func, self, action_name)
    local out = func(self, action_name)
    local pressed = (out == true) or (type(out) == "number" and out > 0)

    if is_in_hub then
        return out
    end

    local promise_action = PROMISE_ACTION_MAP[action_name]
    if promise_action then
        if pressed then
            clearAllPromises()
            if current_slot ~= SLOT_ACTION_MAP[promise_action] and ALLOWED_CHARACTER_STATE[character_state] then
                if action_name ~= "grenade_ability_pressed"
                    or (
                        (grenade_ability ~= "zealot_throwing_knives" or mod.settings["enable_zealot_throwing_knives"])
                        and current_slot ~= "slot_luggable"
                    )
                then
                    setPromise(promise_action)
                end
            end
        end
        return out or isPromised(promise_action)
    end

    if mod.promise_exist and is_attack_prevent_weapon then
        if action_name == "action_one_pressed" or action_name == "action_one_hold" then
            return false
        end

        if action_name == "action_two_pressed" or action_name == "action_two_hold" then
            return false
        end
    end

    return out
end

mod:hook("InputService", "_get", _input_hook)
mod:hook("InputService", "_get_simulate", _input_hook)
