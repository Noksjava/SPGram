
local media_settings = {}

local backgrounds = {off = true, static = true, retroscroll = true}
local background, retroscroll_tile
local tile_directory = "effects/retroscroll/themes/"
local default_tile = "wavelenght-tg.png"
local color_index, motion_index = 1, 1
local color_effects = {
    {"original", "Original"}, {"gradient", "Gradient"}, {"two_tone", "Two-tone fade"},
    {"palette", "Palette steps"},
}
local motion_effects = {
    {"diagonal", "Diagonal"}, {"sway", "Sway"}, {"ripple", "Ripple"}, {"orbit", "Orbit"},
}

function media_settings.retroscroll_effect(kind)
    local effect = kind == "color" and color_effects[color_index] or motion_effects[motion_index]
    return effect[1], effect[2]
end

function media_settings.cycle_retroscroll_effect(kind, direction)
    if kind == "color" then
        color_index = (color_index - 1 + direction) % #color_effects + 1
    else
        motion_index = (motion_index - 1 + direction) % #motion_effects + 1
    end
    media_settings.save()
end

local function effect_index(options, value)
    for index, effect in ipairs(options) do
        if effect[1] == value then return index end
    end
    return 1
end

local function valid_tile(name)
    return type(name) == "string" and name:lower():match("^[%w_][%w_. %-]*%.png$") ~= nil
end

function media_settings.retroscroll_tiles()
    local files = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems and love.filesystem.getDirectoryItems(tile_directory:sub(1, -2)) or {}) do
        if valid_tile(name) and love.filesystem.getInfo(tile_directory .. name, "file") then
            files[#files + 1] = name
        end
    end
    if not love.filesystem.getInfo(tile_directory .. default_tile, "file")
        and love.filesystem.getInfo("res/telegram.png", "file") then
        files[#files + 1] = default_tile
    end
    table.sort(files)
    return files
end

function media_settings.retroscroll_tile()
    return retroscroll_tile or default_tile
end

function media_settings.background_tile()
    return (background == "retroscroll" and retroscroll_tile) or default_tile
end

function media_settings.background_asset(tile)
    if tile and love.filesystem.getInfo(tile_directory .. tile, "file") then return tile_directory .. tile end
    local path = tile_directory .. default_tile
    return love.filesystem.getInfo(path, "file") and path or "res/telegram.png"
end

function media_settings.chat_background()
    return background or "off"
end

function media_settings.set_chat_background(mode, tile)
    if not backgrounds[mode] or (tile and not valid_tile(tile)) then return end
    if mode == "retroscroll" and tile then retroscroll_tile = tile end
    background = mode
    media_settings.save()
end

local settings = {
    autoplay_videos = false,
    autoplay_images = true,
    autoplay_circles = false,
    autoload = true,
    show_mouse_cursor = false,
    message_sound = true,
    ui_motion = true,
    startup_intro = true,
    check_updates_on_launch = true,
    wifi_keep_awake = false,
    inline_animation = true,
    profile_pictures = true,
    video_thumbnails = true,
    small_texture_cache = false,
}

local low_memory = {
    inline_animation = false, profile_pictures = false,
    autoplay_images = false, video_thumbnails = false, small_texture_cache = true,
}

function media_settings.memory_preset()
    local low, standard = true, true
    for key, value in pairs(low_memory) do
        low = low and settings[key] == value
        standard = standard and settings[key] ~= value
    end
    return low and "Low memory" or standard and "Default" or "Custom"
end

function media_settings.apply_memory_preset(low)
    for key, value in pairs(low_memory) do
        if low then settings[key] = value else settings[key] = not value end
    end
    media_settings.save()
end

function media_settings.texture_budget(standard, small)
    return (settings.small_texture_cache and small or standard) * 1024 * 1024
end

local function saved_key(key)

    return key == "message_sound" and "incoming_message_sound" or key
end

function media_settings.get(key)
    return settings[key] ~= false
end

function media_settings.set(key, v, persist)
    if settings[key] ~= nil then
        settings[key] = v == true
        if persist then media_settings.save() end
    end
    return settings[key]
end

function media_settings.toggle(key)
    if settings[key] ~= nil then
        settings[key] = not settings[key]
        media_settings.save()
    end
    return settings[key]
end

function media_settings.load()
    local ok, data = pcall(love.filesystem.read, "media_settings.conf")
    if ok and data then
        for key in pairs(settings) do
            local val = data:match(saved_key(key) .. "%s*=%s*([01])")
            if val then settings[key] = (val == "1") end
        end
        if not data:match("video_thumbnails%s*=%s*[01]") then
            settings.video_thumbnails = settings.autoplay_images
        end
        local mode = data:match("chat_background%s*=%s*(%a+)")
        if backgrounds[mode] then background = mode end
        local tile = data:match("retroscroll_tile[ \t]*=[ \t]*([^\r\n]+)")
        retroscroll_tile = valid_tile(tile) and tile or nil
        local color = data:match("retroscroll_color[ \t]*=[ \t]*([%w_]+)")
        if not color and data:match("retroscroll_gradient%s*=%s*1") then color = "gradient" end
        color_index = effect_index(color_effects, color)
        motion_index = effect_index(motion_effects, data:match("retroscroll_motion[ \t]*=[ \t]*([%w_]+)"))
    end
    if not background then
        local legacy = io.open("wallpaper.conf", "r")
        local value = legacy and legacy:read("*l")
        if legacy then legacy:close() end
        background = value and value:match("^%s*1%s*$") and "static" or "off"
    end
end

function media_settings.save()
    local color, motion = media_settings.retroscroll_effect("color"), media_settings.retroscroll_effect("motion")
    local lines = {"chat_background=" .. media_settings.chat_background(),
        "retroscroll_color=" .. color, "retroscroll_motion=" .. motion,
        "retroscroll_gradient=" .. (color == "gradient" and "1" or "0")}
    if retroscroll_tile then lines[#lines + 1] = "retroscroll_tile=" .. retroscroll_tile end
    for key, val in pairs(settings) do
        lines[#lines + 1] = saved_key(key) .. "=" .. (val and "1" or "0")
    end
    pcall(love.filesystem.write, "media_settings.conf", table.concat(lines, "\n") .. "\n")
end

return media_settings
