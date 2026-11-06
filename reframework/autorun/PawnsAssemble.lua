local modName = "PawnsAssemble"
local pending = false
local status = "Ready."
local hotkey_action = modName .. ".Teleport"
local default_hotkeys = { [hotkey_action] = "[Not Bound]" }
local config = { hotkeys = { [hotkey_action] = default_hotkeys[hotkey_action] } }
local hotkeys
local hotkey_error
local hotkey_was_down = false

local function Log(message, level)
    level = level or "info"
    if level == "info" and not debug then return end
    local previousLevel = log.get_level and log.get_level() or "error"
    log.set_level(level)
    local ok, err = pcall(log[level], "["..modName.."] "..message)
    log.set_level(previousLevel)
    if not ok then error(err, 0) end
end

local hotkeys_ok, hotkeys_result = pcall(require, "Hotkeys/Hotkeys")
if hotkeys_ok then
    hotkeys = hotkeys_result
    local loaded = json.load_file(modName .. ".json")
    if loaded ~= nil then
        local binding = type(loaded) == "table" and type(loaded.hotkeys) == "table"
            and loaded.hotkeys[hotkey_action]
        if type(binding) == "string" and (binding == "[Not Bound]"
            or hotkeys.keys[binding] or hotkeys.buttons[binding] or hotkeys.mbuttons[binding]) then
            config.hotkeys[hotkey_action] = binding
        else
            status = "Invalid saved hotkey; binding reset to Not Bound."
            Log(status, "error")
        end
    end
    hotkeys.setup_hotkeys(config.hotkeys, default_hotkeys)
else
    hotkey_error = "Hotkey unavailable: Install _ScriptCore and reload scripts."
    Log(hotkey_error .. " " .. tostring(hotkeys_result), "error")
end

local function save_config()
    if not hotkeys then return end
    local ok, result = pcall(json.dump_file, modName .. ".json", config)
    if not ok or result == false then
        status = "Could not save hotkey settings: " .. tostring(result)
        Log(status, "error")
    end
end

local function queue_teleport()
    pending = true
    status = "Teleport queued."
end

local function teleport_party()
    local character_manager = sdk.get_managed_singleton("app.CharacterManager")
    local pawn_manager = sdk.get_managed_singleton("app.PawnManager")
    local player = character_manager and character_manager:call("get_ManualPlayer")
    if not player or not pawn_manager then
        error("Player or pawn manager unavailable. Try again after loading.", 0)
    end

    local transform = player:call("get_Transform")
    local position = transform and transform:call("get_Position")
    if not position then
        error("Player position unavailable.", 0)
    end

    local option_type = sdk.find_type_definition("app.CharacterWarpOption")
    local option_field = option_type and option_type:get_field("ResetPosRotContext")
    local option = option_field and option_field:get_data(nil)
    if not option then
        error("Character warp unavailable. Try again after loading.", 0)
    end

    local list = pawn_manager:call("get_PartyPawnList")
    if not list then
        error("Party list unavailable. Try again after loading.", 0)
    end

    local seen = {}
    local moved, failed = 0, 0
    local player_address = player:get_address()
    local offsets = { { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 } }

    local function move_pawn(pawn, label)
        if not pawn then return end
        local address = pawn:get_address()
        if seen[address] then return end
        seen[address] = true

        local ok, err = pcall(function()
            local character = pawn:call("get_CachedCharacter")
            if not character then
                error("Pawn no longer exists; it may have fallen into the abyss.", 0)
            end
            if character:get_address() == player_address then
                error("Refusing to teleport the player as a pawn.", 0)
            end
            local pawn_transform = character:call("get_Transform")
            if not pawn_transform then
                error("Pawn transform unavailable.", 0)
            end

            local offset = offsets[(moved % #offsets) + 1]
            local target = Vector3f.new(position.x + offset[1], position.y, position.z + offset[2])
            -- Reset movement history, then explicitly move even an inactive/dead body's transform.
            character:call("warp(via.vec3, app.CharacterWarpOption)", target, option)
            pawn_transform:call("set_Position", target)
        end)
        if ok then
            moved = moved + 1
        else
            failed = failed + 1
            Log(label .. ": " .. tostring(err), "error")
        end
    end

    move_pawn(pawn_manager:call("get_MainPawn"), "Main pawn")
    for i = 0, list:call("get_Count") - 1 do
        move_pawn(list:call("get_Item", i), "Party pawn " .. tostring(i + 1))
    end

    if moved == 0 and failed == 0 then
        status = "No pawns currently in the party."
    else
        status = string.format("Teleported %d pawn(s); %d failed.",
            moved, failed)
    end
    Log(status, failed > 0 and "error" or "info")
end

re.on_frame(function()
    if not hotkeys then return end
    local down = not not hotkeys.check_hotkey(hotkey_action, true)
    local pressed = hotkeys.check_hotkey(hotkey_action, false, true) and not hotkey_was_down
    hotkey_was_down = down
    if not reframework:is_drawing_ui() and pressed then
        queue_teleport()
    end
end)

re.on_config_save(save_config)

re.on_application_entry("LateUpdateBehavior", function()
    if not pending then return end
    pending = false
    local ok, err = pcall(teleport_party)
    if not ok then
        status = "Teleport failed: " .. tostring(err)
        Log(status, "error")
    end
end)

re.on_draw_ui(function()
    if imgui.tree_node("Pawns Assemble!") then
        imgui.text("Summons your party of pawns beside you, dead or alive.")
        imgui.text("Be sure to use on open, level ground.")

        imgui.push_style_color(0,  0xFFFFFFFF) -- Text
        imgui.push_style_color(21, 0xFF995522) -- ButtonNormal
        imgui.push_style_color(22, 0xFFBB7733) -- ButtonHovered
        imgui.push_style_color(23, 0xFF774411) -- ButtonPressed

        local clicked = imgui.button("Pawns Assemble!##" .. modName)

        imgui.pop_style_color(4)

        if clicked then
            queue_teleport()
        end
        if hotkeys then
            if hotkeys.hotkey_setter(hotkey_action, false, "Teleport party hotkey") then
                hotkeys.update_hotkey_table(config.hotkeys)
                save_config()
            end
            imgui.text("Click to bind an input. Right-click to Clear.")
        else
            imgui.text(hotkey_error)
        end
        imgui.push_style_color(0,  0xFF949494) -- Grey Text
        imgui.text(status)
        imgui.pop_style_color(1)
        imgui.tree_pop()
    end
end)
