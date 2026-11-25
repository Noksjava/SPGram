local ui = require("src.shared.ui.ui_kit")
local keyboard_languages = require("src.shared.system.keyboard_languages")
local controller_map = require("src.shared.system.controller_map")
local performance = require("src.shared.system.performance")
local media_settings = require("src.shared.system.media_settings")

local settings_screen = {}
local START_Y = 70
local FOOTER_HEIGHT = 60
local FACE_ORDER = {4, 3, 1, 2}

local PERFORMANCE_SECTION = {
    id = "performance", label = "Performance",
    items = {"memory_preset", "inline_animation", "profile_pictures", "autoplay_images", "video_thumbnails",
        "small_texture_cache", "frame_rate", "vsync"},
    icon = {"0001100", "0011000", "0110000", "1111110", "0011000", "0110000", "1100000"},
}
local PROFILE_SECTION = {
    label = "My profile",
    icon = {"0011100", "0011100", "0011100", "0000000", "0011100", "0111110", "1111111"},
}

local MEMORY_ROWS = {
    inline_animation = {"GIFs and animated stickers", "Animate", "Still preview"},
    profile_pictures = {"Profile pictures", "Show", "Initials only"},
    autoplay_images = {"Image loading", "Automatic", "On demand"},
    video_thumbnails = {"Video thumbnails", "Show", "Placeholder"},
    small_texture_cache = {"Texture cache", "Small", "Standard"},
}

local BACKGROUND_MODES = {background_off = "off", background_static = "static", retroscroll = "retroscroll"}
local BACKGROUND_SECTION = {label = "Backgrounds", items = {"background_off", "background_static", "background_animated"}}
local ANIMATED_SECTION = {label = "Animated", items = {"retroscroll"}}
local VISUAL_SUBMENUS = {performance = PERFORMANCE_SECTION, backgrounds = BACKGROUND_SECTION,
    background_animated = ANIMATED_SECTION}

local SECTIONS = {
    {id = "visual", label = "Visual settings", items = {"performance", "theme", "fonts", "ui_motion", "startup_intro", "backgrounds", "scale"},
        icon = {"1111111", "1000001", "1010101", "1001001", "1111111", "0001000", "0011100"}},
    {id = "sounds", label = "Sounds", items = {"message_sound"},
        icon = {"0001000", "0011010", "1111001", "1111001", "1111001", "0011010", "0001000"}},
    {id = "language", label = "Language settings", items = {"keyboard_languages"},
        icon = {"0011100", "0101010", "1001001", "1111111", "1001001", "0101010", "0011100"}},
    {id = "advanced", label = "Advanced", items = {"reconnect", "wifi_radio", "wifi_keep_awake",
        "show_mouse", "refresh_messages", "minimize"},
        icon = {"0100010", "1110000", "0100111", "0100010", "1110010", "0100111", "0100010"}},
    {id = "controls", label = "Controls", items = {"map_keys", "calibrate_faces", "abxy", "vibration_test"},
        icon = {"0000000", "0111110", "1010001", "1111011", "1010001", "1000001", "0111110"}},
}

local ROW_ICONS = {
    exit_app = {"1111000", "1000000", "1000100", "1001111", "1000100", "1000000", "1111000"},
    logout = {"1111100", "1000100", "1010100", "1011111", "1010100", "1000100", "1111100"},
    add_account = {"0110000", "0110000", "0000010", "1110111", "1110010", "1110000", "0000000"},
    update_github = {"0001000", "0011000", "0111110", "0011001", "0000001", "1000001", "0111110"},
    theme = {"0011100", "0100010", "1010101", "1000001", "1010110", "0100100", "0011000"},
    fonts = {"0011100", "0100010", "1000001", "1111111", "1000001", "1000001", "1000001"},
    ui_motion = {"0010000", "0011000", "0011100", "0011110", "0011100", "0011000", "0010000"},
    startup_intro = {"1111111", "1000001", "1010001", "1011001", "1010001", "1000001", "1111111"},
    wallpaper = {"1111111", "1000001", "1000101", "1010001", "1101011", "1000101", "1111111"},
    scale = {"1110111", "1000001", "1010101", "0001000", "1010101", "1000001", "1110111"},
    memory_preset = {"0010100", "0111110", "1101011", "0100010", "1101011", "0111110", "0010100"},
    inline_animation = {"1111111", "1000001", "1011001", "1011101", "1011001", "1000001", "1111111"},
    small_texture_cache = {"0111110", "1100011", "1011101", "1000001", "1011101", "1000001", "1111111"},
    frame_rate = {"0111110", "1000001", "1001001", "1011001", "1000001", "1000001", "0111110"},
    vsync = {"1100110", "0010010", "0001010", "1010010", "1001000", "1000100", "0110011"},
    keyboard_languages = {"0000000", "1111111", "1000001", "1111111", "1010101", "1111111", "0000000"},
    wifi_radio = {"0111110", "1000001", "0011100", "0100010", "0001000", "0000000", "0001000"},
    wifi_keep_awake = {"0111110", "1000001", "0011100", "0100010", "0001000", "0011100", "0001000"},
    show_mouse = {"1000000", "1100000", "1010000", "1001000", "1000100", "1111100", "0010000"},
    minimize = {"1111111", "1000001", "1000001", "1000001", "1000001", "1011101", "1111111"},
    calibrate_faces = {"0001000", "0011100", "0101010", "1110111", "0101010", "0011100", "0001000"},
    abxy = {"0000000", "0111110", "0001010", "0100000", "0101000", "0111110", "0000000"},
    vibration_test = {"0011100", "1010101", "1010101", "0010100", "1010101", "1010101", "0011100"},
    confirm = {"0000000", "0000001", "0000010", "1000100", "0101000", "0010000", "0000000"},
    back = {"0010000", "0100000", "1111111", "0100001", "0010001", "0000001", "0000000"},
    media_shortcuts = {"0001100", "0011000", "0110000", "1111110", "0011000", "0110000", "1100000"},
}
ROW_ICONS.profile = PROFILE_SECTION.icon
ROW_ICONS.profile_pictures = PROFILE_SECTION.icon
ROW_ICONS.account = PROFILE_SECTION.icon
ROW_ICONS.font_family = ROW_ICONS.fonts
ROW_ICONS.autoplay_images = ROW_ICONS.wallpaper
ROW_ICONS.backgrounds = ROW_ICONS.wallpaper
ROW_ICONS.background_off = ROW_ICONS.minimize
ROW_ICONS.background_static = ROW_ICONS.wallpaper
ROW_ICONS.background_animated = ROW_ICONS.startup_intro
ROW_ICONS.retroscroll = {"0000011", "0000110", "0011111", "0001100", "0011000", "0110000", "1100000"}
ROW_ICONS.video_thumbnails = ROW_ICONS.startup_intro
ROW_ICONS.message_sound = SECTIONS[2].icon
ROW_ICONS.keyboard_language = SECTIONS[3].icon
ROW_ICONS.reconnect = ROW_ICONS.update_github
ROW_ICONS.refresh_messages = ROW_ICONS.update_github
ROW_ICONS.map_keys = SECTIONS[5].icon
ROW_ICONS.shortcuts = SECTIONS[5].icon
ROW_ICONS.options = SECTIONS[4].icon
ROW_ICONS.search = ROW_ICONS.media_shortcuts
ROW_ICONS.keyboard = ROW_ICONS.keyboard_languages

function settings_screen:row_layout(height)
    local item_height = ui.settings_row_height(self.fonts.normal)
    local row_height = item_height + 6
    local visible = math.max(1, math.floor((height - START_Y - FOOTER_HEIGHT) / row_height))
    return visible, item_height, row_height
end

function settings_screen.new(fonts, tg, callbacks)
    local version = love.filesystem and love.filesystem.read and love.filesystem.read("VERSION")
    local self = {
        fonts = fonts,
        tg = tg,
        callbacks = callbacks or {},
        scale = ui.get_scale(),
        selected_item = 2,
        scroll_offset = 0,
        logout_confirm = false,
        releases = callbacks and callbacks.releases,
        version = version and version:match("^%s*(%d+%.%d+%.%d+)%s*$"),
    }
    return setmetatable(self, {__index = settings_screen})
end

function settings_screen:accounts()
    if self.callbacks.accounts then return self.callbacks.accounts() end
    return {}, nil
end

function settings_screen:abxy_layout()
    if self.callbacks.abxy_layout then return self.callbacks.abxy_layout() end
    return "modern"
end

function settings_screen:toggle_abxy()
    if self.callbacks.toggle_abxy then self.callbacks.toggle_abxy() end
end

function settings_screen:items()
    if self.fonts_open then
        local items = {}
        for _, option in ipairs(ui.font_families) do
            items[#items + 1] = {id = "font_family", option = option}
        end
        return items
    end
    if self.languages_open then
        local items = {}
        for _, option in ipairs(keyboard_languages.options) do
            items[#items + 1] = {id = "keyboard_language", code = option.id, label = option.label}
        end
        return items
    end
    if self.section == PROFILE_SECTION then
        local items = {{id = "profile"}}
        for _, account in ipairs(self:accounts()) do
            items[#items + 1] = {id = "account:" .. account.key, account = account}
        end
        items[#items + 1] = {id = "add_account"}
        items[#items + 1] = {id = "logout"}
        return items
    elseif self.section then
        local items = {}
        for _, id in ipairs(self.section.items) do
            if (id ~= "wifi_keep_awake" or self.tg:wifi_power_supported())
                and (id ~= "wifi_radio" or self.tg:wifi_radio_supported())
                and (id ~= "calibrate_faces" or self.callbacks.calibrate_faces) then
                items[#items + 1] = {id = id, section = VISUAL_SUBMENUS[id]}
            end
        end
        return items
    end
    local items = {{id = "exit_app"}, {id = "my_profile", section = PROFILE_SECTION}}
    if self.releases then items[#items + 1] = {id = "update_github"} end
    for _, section in ipairs(SECTIONS) do
        items[#items + 1] = {id = section.id, section = section}
    end
    return items
end

function settings_screen:enter()
    self.scale = ui.get_scale()
    self.section, self.section_parent = nil, nil
    self.fonts_open, self.languages_open, self.release_open = false, false, false
    self.keymap_open, self.keymap_waiting, self.face_calibration = false, nil, nil
    self.selected_item, self.scroll_offset = 2, 0
    self.animated_item = nil
    self.quit_confirm, self.logout_confirm = false, false
    media_settings.load()
end

local ROW_LABELS = {
    exit_app = "Quit SPgram", logout = "Sign out", add_account = "Add account", profile = "View profile",
    update_github = "Updates", scale = "Interface scale", calibrate_faces = "Calibrate face buttons",
    map_keys = "Map keys", fonts = "Interface font", ui_motion = "Interface motion",
    keyboard_languages = "Keyboard languages", message_sound = "Message sound", startup_intro = "Startup intro",
    vibration_test = "Vibration test", minimize = "Minimize", wifi_radio = "Wi-Fi radio",
    wifi_keep_awake = "Keep Wi-Fi awake", reconnect = "Reconnect to Telegram", theme = "Theme",
    background_off = "Off", background_static = "Static", retroscroll = "Retroscroll",
    abxy = "Swap Confirm / Back", show_mouse = "Mouse pointer",
    refresh_messages = "Refresh messages", memory_preset = "Memory preset", frame_rate = "Frame-rate cap", vsync = "VSync",
}

local function enabled_label(value)
    return value and "On" or "Off"
end

local function row_content(self, item, active_key)
    local id = item.id
    if item.section then return item.section.label, nil, true end
    if item.account then
        local account = item.account
        if account.key == active_key then
            local me = self.tg.me
            return me and self.tg:user_name(me.id) or account.title or "Account", "Active"
        end
        return account.title or "Account", account.authorized and "Saved" or "Signed out"
    end
    local setting = MEMORY_ROWS[id]
    if setting then return setting[1], setting[media_settings.get(id) and 2 or 3] end
    local label = ROW_LABELS[id]
    if id == "scale" then return label, string.format("%.1f×", self.scale) end
    if id == "memory_preset" then return label, media_settings.memory_preset() end
    if id == "frame_rate" then return label, tostring(performance.get_fps()) .. " FPS" end
    if id == "vsync" then return label, enabled_label(performance.get_vsync()) end
    if id == "fonts" then return label, ui.get_font_family().label end
    if id == "font_family" then
        return item.option.label, ui.get_font_family() == item.option and "Active" or "Aa 09",
            false, ui.font_preview(item.option)
    end
    if id == "keyboard_language" then return item.label, enabled_label(keyboard_languages.enabled(item.code)) end
    if id == "ui_motion" or id == "message_sound" or id == "startup_intro" then
        return label, enabled_label(media_settings.get(id))
    end
    if id == "wifi_radio" then return label, self.tg:wifi_radio_label() or "Toggle" end
    if id == "wifi_keep_awake" then return label, self.tg:wifi_power_label() end
    if id == "reconnect" then return label, self.tg:connection_label() end
    if id == "theme" then return label, self.callbacks.get_theme and self.callbacks.get_theme() or "dark" end
    if BACKGROUND_MODES[id] then
        return label, media_settings.chat_background() == BACKGROUND_MODES[id] and "Active" or nil
    end
    if id == "abxy" then return label, enabled_label(self:abxy_layout() == "retro") end
    if id == "show_mouse" then return label, enabled_label(media_settings.get("show_mouse_cursor")) end
    if id == "logout" and self.logout_confirm then return "Confirm sign-out" end
    if id == "exit_app" and self.quit_confirm then return "Confirm quit" end
    return label, nil, id == "profile" or id == "update_github" or id == "keyboard_languages"
        or id == "map_keys" or id == "calibrate_faces"
end

function settings_screen:draw()
    if self.face_calibration then self:draw_face_calibration(); return end
    if self.keymap_open then self:draw_keymap(); return end
    if self.release_open then self.releases:draw(); return end
    local f, colors = self.fonts, ui.colors
    local w, h = ui.width(), ui.height()
    local _, active_key = self:accounts()
    local items = self:items()

    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    local title = self.fonts_open and "Interface font" or self.languages_open and "Keyboard languages"
        or self.section and self.section.label or "Settings"
    if self.section then ui.pixel_icon(self.section.icon, 24, 17, colors.accent) end
    local title_x = self.section and 56 or 24
    ui.text(ui.fit(title, f.subtitle, w - title_x - 144), title_x, 15, f.subtitle, colors.text)
    ui.button_hint("{back} — Back", w - 140, 18, f.tiny, colors.muted)

    local max_visible, item_h, row_h = self:row_layout(h)
    local start_y = START_Y
    local content_h = h - start_y - FOOTER_HEIGHT

    self:clamp_scroll(#items, max_visible)

    local first_visible = self.scroll_offset + 1
    local last_visible = math.min(#items, self.scroll_offset + max_visible)

    for idx = first_visible, last_visible do
        local item = items[idx]
        local display_idx = idx - self.scroll_offset
        local y = start_y + (display_idx - 1) * row_h
        local selected = self.selected_item == idx
        local lift
        if selected then
            local now = love.timer.getTime()
            if self.animated_item ~= idx then self.animated_item, self.focus_at = idx, now end
            lift = ui.focus_lift(now - self.focus_at)
        end
        local label, value, arrow, sample = row_content(self, item, active_key)
        ui.settings_row(f.normal, y, item_h, {
            label = label, value = value, arrow = arrow, selected = selected, lift = lift,
            value_font = value == "Aa 09" and sample or nil,
            icon = item.section and item.section.icon or ROW_ICONS[item.account and "account" or item.id],
            danger = (item.id == "exit_app" and self.quit_confirm) or (item.id == "logout" and self.logout_confirm),
        })
    end

    local status = self.tg.action_error ~= "" and self.tg.action_error or self.tg.action_status
    if status and status ~= "" then
        local status_y = start_y + (last_visible - first_visible + 1) * row_h + 10
        ui.text(ui.fit(status, f.tiny, w - 80), 44, status_y, f.tiny,
            self.tg.action_error ~= "" and colors.red or colors.muted)
    end

    local hint_y = h - 30
    ui.button_hint("D-pad — Move or adjust   {confirm} — Select   {back} — Back", 24, hint_y, f.tiny, colors.muted)
    if self.version then
        local muted = colors.muted
        ui.printf("v" .. self.version, w - 108, hint_y, 84, "right", f.tiny,
            {muted[1], muted[2], muted[3], 0.65})
    end

    if #items > max_visible then
        local scroll_h = content_h
        local thumb_h = math.max(20, scroll_h * max_visible / #items)
        local thumb_y = start_y + (self.scroll_offset / math.max(1, #items - max_visible)) * (scroll_h - thumb_h)
        ui.rect(w - 16, start_y, 8, scroll_h, colors.panel, 4)
        ui.rect(w - 16, thumb_y, 8, thumb_h, colors.accent, 4)
    end

    self:draw_update_dialog(w, h)

end

function settings_screen:clamp_scroll(total_items, max_visible)
    local max_scroll = math.max(0, total_items - max_visible)
    self.scroll_offset = math.max(0, math.min(max_scroll, self.scroll_offset))
    if self.selected_item <= self.scroll_offset then
        self.scroll_offset = self.selected_item - 1
    elseif self.selected_item > self.scroll_offset + max_visible then
        self.scroll_offset = self.selected_item - max_visible
    end
end

function settings_screen:draw_keymap()
    local w, h = ui.width(), ui.height()
    local f, colors = self.fonts, ui.colors
    local visible, item_h, row_h = self:row_layout(h)
    local count = #controller_map.actions + 1
    local first = math.max(1, self.keymap_index - visible + 1)
    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    ui.pixel_icon(ROW_ICONS.map_keys, 24, 17, colors.accent)
    ui.text("Map keys", 56, 15, f.subtitle, colors.text)
    for i = first, math.min(count, first + visible - 1) do
        local action = controller_map.actions[i]
        local selected = self.keymap_index == i
        local waiting = selected and self.keymap_waiting
        ui.settings_row(f.normal, START_Y + (i - first) * row_h, item_h, {
            label = action and action.label or "Reset to defaults", selected = selected,
            icon = ROW_ICONS[action and action.id or "refresh_messages"],
            value = waiting and "Press a button" or nil,
            binding = action and not waiting and "{" .. action.id .. "}" or nil,
        })
    end
    local text = self.keymap_waiting and "Face buttons, START or SELECT   ← — Cancel"
        or "D-pad — Move   {confirm} — Remap   {back} — Back"
    ui.button_hint(text, 24, h - 30, f.tiny, colors.muted, w - 48)
end

function settings_screen:draw_face_calibration()
    local w, h = ui.width(), ui.height()
    local f, colors = self.fonts, ui.colors
    local panel_w = math.min(w - 32, 400)
    local x, y = (w - panel_w) / 2, (h - 224) / 2
    local step = self.face_calibration.step
    local position = FACE_ORDER[step]
    local face = position and controller_map.faces[position]
    ui.rect(0, 0, w, h, colors.bg)
    ui.retro_panel(x, y, panel_w, 224, colors.panel, colors.accent_dark)
    ui.printf("Calibrate face buttons", x + 8, y + 13, panel_w - 16, "center", f.subtitle, colors.text)
    local prompt = face and ("Press your " .. face .. " face button") or "Press the button you want to use for Confirm"
    ui.printf(prompt, x + 8, y + 48, panel_w - 16, "center", f.normal, colors.text)
    local cx, cy = w / 2, y + 123
    local dots = {{0, -1}, {-1, 0}, {1, 0}, {0, 1}}
    for index, dot in ipairs(dots) do
        love.graphics.setColor(index == position and colors.accent or colors.muted)
        love.graphics.circle(index == position and "fill" or "line", cx + dot[1] * 23, cy + dot[2] * 23, 8)
    end
    ui.printf(tostring(step) .. " / " .. tostring(#FACE_ORDER + 1), x, y + 165, panel_w, "center", f.tiny, colors.muted)
    ui.printf("START — Cancel", x, y + 192, panel_w, "center", f.tiny, colors.muted)
end

function settings_screen:record_gamepad_button(button)
    local calibration = self.face_calibration
    if calibration then
        if button == "start" then self.face_calibration = nil; return end
        if not controller_map.position(button) then return end
        local position = FACE_ORDER[calibration.step]
        if not position then
            self.callbacks.calibrate_faces(calibration.positions, button)
            self.face_calibration = nil
        elseif not calibration.positions[button] then
            calibration.positions[button] = position
            calibration.step = calibration.step + 1
        end
        return
    end
    if button == "dpleft" then self.keymap_waiting = nil; return end
    if self.keymap_waiting and self.callbacks.map_key(self.keymap_waiting, button) then
        self.keymap_waiting = nil
    end
end

function settings_screen:keymap_keypressed(key)
    if self.keymap_waiting then
        if key == "escape" or key == "left" then self.keymap_waiting = nil end
        return
    end
    if key == "escape" then
        self.keymap_open = false
    elseif key == "up" or key == "down" then
        local delta = key == "up" and -1 or 1
        self.keymap_index = math.max(1, math.min(#controller_map.actions + 1, self.keymap_index + delta))
    elseif key == "return" or key == "kpenter" then
        local action = controller_map.actions[self.keymap_index]
        if action then self.keymap_waiting = action.id else self.callbacks.reset_keys() end
    end
end

function settings_screen:close_keyboard_languages()
    self.languages_open = false
    self.selected_item, self.scroll_offset = self.language_return_selection, self.language_return_offset
end

function settings_screen:activate_item(item)
    if not item then return end
    if item.section then
        self.section_parent = {section = self.section, parent = self.section_parent,
            selection = self.selected_item, offset = self.scroll_offset}
        self.section = item.section
        self.selected_item, self.scroll_offset = 1, 0
        self.animated_item = nil
    elseif item.id == "exit_app" then
        if self.quit_confirm then
            love.event.quit()
        else
            self.quit_confirm = true
        end
    elseif item.id:match("^account:") then
        local key = item.id:sub(9)
        local _, active_key = self:accounts()
        if key ~= active_key and self.callbacks.switch_account then
            self.callbacks.switch_account(key)
        end
    elseif item.id == "update_github" then
        self.release_open = true
        self.releases.launch_offer = false
        self.releases.selection = 1
    elseif item.id == "add_account" then
        if self.callbacks.add_account then self.callbacks.add_account() end
    elseif item.id == "logout" then
        if self.logout_confirm then
            if self.tg:log_out() then self.logout_confirm = false end
        else
            self.logout_confirm = true
        end
    elseif item.id == "reconnect" then
        self.tg:reconnect_network()
    elseif item.id == "wifi_radio" then
        self.tg:set_wifi_radio("toggle")
    elseif item.id == "wifi_keep_awake" then
        self.tg:toggle_wifi_power()
    elseif item.id == "profile" then
        if self.callbacks.open_profile then self.callbacks.open_profile() end
    elseif item.id == "theme" then
        if self.callbacks.cycle_theme then self.callbacks.cycle_theme() end
    elseif item.id == "calibrate_faces" then
        self.face_calibration = {step = 1, positions = {}}
    elseif item.id == "map_keys" then
        if self.callbacks.map_key then
            self.keymap_open, self.keymap_index = true, 1
        end
    elseif item.id == "fonts" then
        self.fonts_open = true
        self.font_return_selection, self.font_return_offset = self.selected_item, self.scroll_offset
        self.selected_item, self.scroll_offset = 1, 0
        for index, option in ipairs(ui.font_families) do
            if option == ui.get_font_family() then self.selected_item = index; break end
        end
    elseif item.id == "font_family" then
        ui.set_font_family(item.option.id)
    elseif item.id == "ui_motion" then
        media_settings.toggle("ui_motion")
    elseif item.id == "keyboard_languages" then
        self.languages_open = true
        self.language_return_selection, self.language_return_offset = self.selected_item, self.scroll_offset
        self.selected_item, self.scroll_offset = 1, 0
    elseif item.id == "keyboard_language" then
        if not keyboard_languages.toggle(item.code) then
            self.tg.action_error = "Keep at least one language enabled."
        else
            self.tg.action_error = ""
        end
    elseif item.id == "message_sound" or item.id == "startup_intro" then
        media_settings.toggle(item.id)
    elseif BACKGROUND_MODES[item.id] then
        media_settings.set_chat_background(BACKGROUND_MODES[item.id])
    elseif item.id == "scale" then
        ui.set_scale(self.scale)
    elseif item.id == "frame_rate" then
        performance.toggle()
    elseif item.id == "memory_preset" then
        media_settings.apply_memory_preset(media_settings.memory_preset() ~= "Low memory")
        self.tg:apply_memory_settings()
    elseif MEMORY_ROWS[item.id] then
        media_settings.toggle(item.id)
        self.tg:apply_memory_settings()
    elseif item.id == "show_mouse" then
        local visible = media_settings.toggle("show_mouse_cursor")
        if love.mouse then love.mouse.setVisible(visible) end
    elseif item.id == "vsync" then
        performance.toggle_vsync()
    elseif item.id == "vibration_test" then
        local ok = false
        if love.system and love.system.vibrate then
            local s, e = pcall(love.system.vibrate, 0.5)
            if s then ok = true end
        end
        if not ok then
            for _, j in ipairs(love.joystick.getJoysticks()) do
                local s = pcall(function() j:setVibration(1, 1, 0.5) end)
                if s then ok = true; break end
            end
        end
        if ok then
            self.tg.action_status = "Vibration sent"
        else
            self.tg.action_error = "Vibration unavailable"
        end
    elseif item.id == "minimize" then
        if love.window and love.window.minimize then
            love.window.minimize()
            self.tg.action_status = "App minimized"
        end
    elseif item.id == "abxy" then
        self:toggle_abxy()
    elseif item.id == "refresh_messages" then
        if self.tg and self.tg.current_chat_id then
            self.tg.action_status = "Refreshing messages…"
            if self.tg.open_chat then
                self.tg:open_chat(self.tg.current_chat_id)
            end
        elseif self.tg then
            self.tg.action_status = "Refreshing chats…"
            if self.tg.send then
                self.tg:send({["@type"] = "getChats", chat_list = {["@type"] = "chatListMain"}, limit = 100}, "loadChats")
            end
        end
    end
end

function settings_screen:draw_update_dialog(w, h)
    if not (self.tg and self.tg.update_restart_pending) then return end
    local f = self.fonts
    local colors = ui.colors
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local pw, ph = 420, 140
    local px, py = (w - pw) / 2, (h - ph) / 2
    ui.rect(px, py, pw, ph, colors.panel, 8)
    ui.outline(px, py, pw, ph, colors.accent, 8)
    ui.text("Update downloaded", px + 20, py + 16, f.subtitle, colors.text)
    ui.text("Restart the app to apply the update.", px + 20, py + 52, f.small, colors.muted)
    ui.button_hint("{back} — Close", px + 20, py + ph - 24, f.tiny, colors.muted)
end

function settings_screen:keypressed(key)
    if self.face_calibration then
        if key == "escape" then self.face_calibration = nil end
        return
    end
    if self.keymap_open then self:keymap_keypressed(key); return end
    if self.fonts_open and key == "escape" then
        self.fonts_open = false
        self.selected_item, self.scroll_offset = self.font_return_selection, self.font_return_offset
        return
    end
    if self.languages_open and key == "escape" then
        self:close_keyboard_languages()
        return
    end
    if self.release_open then
        if self.releases:keypressed(key) == "back" then self.release_open = false end
        return
    end
    if self.tg and self.tg.update_restart_pending then
        if key == "escape" or key == "b" then
            self.tg.update_restart_pending = false
        end
        return
    end
    if key == "escape" then
        if self.quit_confirm then self.quit_confirm = false; return end
        if self.logout_confirm then self.logout_confirm = false; return end
        if self.section then
            local previous = self.section_parent
            self.section, self.section_parent = previous.section, previous.parent
            self.selected_item, self.scroll_offset = previous.selection, previous.offset
            self.animated_item = nil
            return
        end
        return "back"
    end
    local items = self:items()
    local selected = items[self.selected_item]
    local id = selected and selected.id
    if key == "up" or key == "down" then
        local direction = key == "down" and 1 or -1
        self.selected_item = math.max(1, math.min(#items, self.selected_item + direction))
        local max_visible = self:row_layout(ui.height())
        self:clamp_scroll(#items, max_visible)
        selected = items[self.selected_item]
        if selected.id ~= "exit_app" then self.quit_confirm = false end
        if selected.id ~= "logout" then self.logout_confirm = false end
    elseif key == "left" or key == "right" then
        if id == "scale" then
            local direction = key == "right" and 0.1 or -0.1
            self.scale = math.max(0.7, math.min(2.0, self.scale + direction))
        elseif self.section == PERFORMANCE_SECTION or id == "abxy" or id == "show_mouse" then
            self:activate_item(selected)
        end
    elseif key == "kpplus" or key == "+" or key == "=" then
        if id == "scale" then
            self.scale = math.min(2.0, self.scale + 0.1)
        end
    elseif key == "kpminus" or key == "-" then
        if id == "scale" then
            self.scale = math.max(0.7, self.scale - 0.1)
        end
    elseif key == "return" or key == "kpenter" then
        self:activate_item(selected)
    end
end

function settings_screen:wheelmoved(_, y)
    if self.release_open or self.keymap_open or self.face_calibration or self.tg.update_restart_pending then return end
    local items = self:items()
    local max_visible = self:row_layout(ui.height())
    if y == 0 then return end
    local step = y > 0 and math.ceil(y) or math.floor(y)
    self.scroll_offset = math.max(0, math.min(math.max(0, #items - max_visible), self.scroll_offset - step))
    self.selected_item = math.max(self.scroll_offset + 1,
        math.min(self.selected_item, self.scroll_offset + max_visible, #items))
    local id = items[self.selected_item].id
    if id ~= "exit_app" then self.quit_confirm = false end
    if id ~= "logout" then self.logout_confirm = false end
end

function settings_screen:mousepressed(x, y, button)
    if self.release_open or self.keymap_open or self.face_calibration or self.tg.update_restart_pending then return end
    if button ~= 1 then return end
    local items = self:items()
    local max_visible, item_h, row_h = self:row_layout(ui.height())
    local start_y = START_Y

    for idx = self.scroll_offset + 1, math.min(#items, self.scroll_offset + max_visible) do
        local item = items[idx]
        local display_idx = idx - self.scroll_offset
        local y_pos = start_y + (display_idx - 1) * row_h
        local bounds = {x = 40, y = y_pos, w = ui.width() - 80, h = item_h}

        if x >= bounds.x and x <= bounds.x + bounds.w and y >= bounds.y and y <= bounds.y + bounds.h then
            self.selected_item = idx
            if item.id ~= "exit_app" then self.quit_confirm = false end
            if item.id ~= "logout" then self.logout_confirm = false end
            if item.id == "scale" then
                local direction = x < ui.width() / 2 and -0.1 or 0.1
                self.scale = math.max(0.7, math.min(2.0, self.scale + direction))
            end
            self:activate_item(item)
            return
        end
    end

    if self.logout_confirm then self.logout_confirm = false end
end

function settings_screen:textinput() end

return settings_screen
