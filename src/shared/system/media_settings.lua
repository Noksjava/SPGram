
local media_settings = {}

local backgrounds = {off = true, static = true, retroscroll = true}
local background

function media_settings.chat_background()
    return background or "off"
end

function media_settings.set_chat_background(mode)
    if not backgrounds[mode] then return end
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
    end
    if not background then
        local legacy = io.open("wallpaper.conf", "r")
        local value = legacy and legacy:read("*l")
        if legacy then legacy:close() end
        background = value and value:match("^%s*1%s*$") and "static" or "off"
    end
end

function media_settings.save()
    local lines = {"chat_background=" .. media_settings.chat_background()}
    for key, val in pairs(settings) do
        lines[#lines + 1] = saved_key(key) .. "=" .. (val and "1" or "0")
    end
    pcall(love.filesystem.write, "media_settings.conf", table.concat(lines, "\n") .. "\n")
end

return media_settings
