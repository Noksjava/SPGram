local ui = require("src.shared.ui.ui_kit")
local keyboard_languages = require("src.shared.system.keyboard_languages")
local controller_map = require("src.shared.system.controller_map")
local performance = require("src.shared.system.performance")
local media_settings = require("src.shared.system.media_settings")
local release_screen = require("src.features.auth.ui.release_screen")

local settings_screen = {}
local ITEM_HEIGHT = 34
local START_Y = 70
local FOOTER_HEIGHT = 60
local FACE_ORDER = {4, 3, 1, 2}

local PERFORMANCE_SECTION = {
    id = "performance", label = "Performance",
    items = {"memory_preset", "inline_animation", "profile_pictures", "autoplay_images", "video_thumbnails",
        "small_texture_cache", "frame_rate", "vsync"},
    icon = {"0001100", "0011000", "0110000", "1111110", "0011000", "0110000", "1100000"},
}

local MEMORY_ROWS = {
    inline_animation = {"GIFs and animated stickers", "Animate", "Still preview"},
    profile_pictures = {"Profile pictures", "Show", "Initials only"},
    autoplay_images = {"Image loading", "Automatic", "On demand"},
    video_thumbnails = {"Video thumbnails", "Show", "Placeholder"},
    small_texture_cache = {"Texture cache", "Small", "Standard"},
}

local SECTIONS = {
    {id = "visual", label = "Visual settings", items = {"performance", "theme", "fonts", "ui_motion", "startup_intro", "wallpaper", "scale"},
        icon = {"1111111", "1000001", "1010101", "1001001", "1111111", "0001000", "0011100"}},
    {id = "sounds", label = "Sounds", items = {"message_sound"},
        icon = {"0001000", "0011010", "1111001", "1111001", "1111001", "0011010", "0001000"}},
    {id = "language", label = "Language settings", items = {"keyboard_languages"},
        icon = {"0011100", "0101010", "1001001", "1111111", "1001001", "0101010", "0011100"}},
    {id = "advanced", label = "Advanced", items = {"reconnect", "wifi_off", "wifi_on", "wifi_keep_awake",
        "show_mouse", "refresh_messages", "update_github", "minimize"},
        icon = {"0100010", "1110000", "0100111", "0100010", "1110010", "0100111", "0100010"}},
    {id = "controls", label = "Controls", items = {"map_keys", "calibrate_faces", "abxy", "vibration_test"},
        icon = {"0000000", "0111110", "1010001", "1111011", "1010001", "1000001", "0111110"}},
}

local WIFI_ACTIONS = {wifi_off = "disable", wifi_on = "enable"}

local function draw_section_icon(icon, x, y, color)
    for row, pixels in ipairs(icon) do
        for column = 1, #pixels do
            if pixels:sub(column, column) == "1" then
                ui.rect(x + (column - 1) * 3, y + (row - 1) * 3, 3, 3, color)
            end
        end
    end
end

function settings_screen:row_layout(height)
    local item_height = math.max(ITEM_HEIGHT, self.fonts.normal:getHeight() + 14)
    local inline_hints = self.section and self.section ~= PERFORMANCE_SECTION and not self.fonts_open and not self.languages_open
    local row_height = item_height + (inline_hints and self.fonts.tiny:getHeight() + 4 or 6)
    local visible = math.max(1, math.floor((height - START_Y - FOOTER_HEIGHT) / row_height))
    return visible, item_height, row_height
end

function settings_screen.new(fonts, tg, callbacks)
    local self = {
        fonts = fonts,
        tg = tg,
        callbacks = callbacks or {},
        scale = ui.get_scale(),
        selected_item = 2,
        scroll_offset = 0,
        logout_confirm = false,
        releases = release_screen.new(fonts),
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
    if self.section then
        local items = {}
        for _, id in ipairs(self.section.items) do
            if (id ~= "wifi_keep_awake" or self.tg:wifi_power_supported())
                and (not WIFI_ACTIONS[id] or self.tg:wifi_radio_supported())
                and (id ~= "calibrate_faces" or self.callbacks.calibrate_faces)
                and (id ~= "update_github" or self.releases) then
                items[#items + 1] = {id = id, section = id == "performance" and PERFORMANCE_SECTION or nil}
            end
        end
        return items
    end
    local accounts = self:accounts()
    local items = {{id = "exit_app"}, {id = "profile"}}
    for _, section in ipairs(SECTIONS) do
        items[#items + 1] = {id = section.id, section = section}
    end
    for _, account in ipairs(accounts) do
        items[#items + 1] = {id = "account:" .. account.key, account = account}
    end
    items[#items + 1] = {id = "add_account"}
    items[#items + 1] = {id = "logout"}
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
    if self.section then draw_section_icon(self.section.icon, 24, 17, colors.accent) end
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
        local is_scale = item.id == "scale"
        local is_vibration_test = item.id == "vibration_test"
        local is_minimize = item.id == "minimize"
        local is_abxy = item.id == "abxy"
        local is_show_mouse = item.id == "show_mouse"
        local is_account = item.id and item.id:match("^account:")
        local is_exit = item.id == "exit_app"
        local is_add = item.id == "add_account"
        local is_logout = item.id == "logout"
        local is_update_github = item.id == "update_github"
        local is_profile = item.id == "profile"
        local is_theme = item.id == "theme"
        local is_wallpaper = item.id == "wallpaper"

        local danger = selected and ((is_exit and self.quit_confirm) or (is_logout and self.logout_confirm))
        local bg = selected and (danger and colors.red or colors.accent) or colors.panel_alt
        local ink = selected and ui.contrasting_text(bg) or nil
        local row_text, row_secondary = ink or colors.text, ink or colors.muted

        ui.retro_panel(40, y, w - 80, item_h, bg, selected and colors.accent_dark or colors.header)
        if selected then
            local now = love.timer.getTime()
            if self.animated_item ~= idx then self.animated_item, self.focus_at = idx, now end
            ui.focus_corners(41, y + 1, w - 82, item_h - 2, colors.accent, ui.focus_lift(now - self.focus_at))
        end

        if item.section then
            local icon_y = y + math.floor((item_h - 21) / 2)
            draw_section_icon(item.section.icon, 56, icon_y, ink or colors.accent)
            ui.text(ui.fit(item.section.label, f.normal, w - 160), 90,
                y + (item_h - f.normal:getHeight()) / 2, f.normal, row_text)
            local arrow_x = w - 64
            for step = 0, 4 do
                ui.rect(arrow_x + math.min(step, 4 - step) * 2, icon_y + 5 + step * 2, 2, 2, row_secondary)
            end
        elseif is_exit then
            ui.text("Quit SPgram", 60, y + 9, f.normal, row_text)
            if self.quit_confirm then
                ui.button_hint("{confirm} — Quit", w - 180, y + 9, f.small, row_secondary, 120, ink)
            end
        elseif is_scale then
            ui.text("Interface scale", 60, y + 7, f.normal, row_text)
            ui.text(string.format("%.1f x", self.scale), w - 100, y + 7, f.small, row_text)
            ui.button_hint("Left/Right — Adjust   {confirm} — Apply", 60, y + item_h + 1, f.tiny, colors.muted)
        elseif self.section == PERFORMANCE_SECTION then
            local setting = MEMORY_ROWS[item.id]
            local label, value
            if setting then
                label, value = setting[1], setting[media_settings.get(item.id) and 2 or 3]
            elseif item.id == "memory_preset" then
                label, value = "Memory preset", media_settings.memory_preset()
            elseif item.id == "frame_rate" then
                label, value = "Frame-rate cap", tostring(performance.get_fps()) .. " FPS"
            else
                label, value = "VSync", performance.get_vsync() and "On" or "Off"
            end
            local value_x = w - 58 - f.small:getWidth(value)
            ui.text(ui.fit(label, f.normal, value_x - 74), 60, y + (item_h - f.normal:getHeight()) / 2, f.normal, row_text)
            ui.text(value, value_x, y + (item_h - f.small:getHeight()) / 2, f.small, row_secondary)
        elseif item.id == "calibrate_faces" then
            ui.text("Calibrate face buttons", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Open", w - 170, y + 7, f.small, row_secondary, 120, ink)
        elseif item.id == "map_keys" then
            ui.text("Map keys", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Open", w - 170, y + 7, f.small, row_secondary, 120, ink)
        elseif item.id == "fonts" then
            ui.text("Interface font", 60, y + 7, f.normal, row_text)
            ui.text(ui.get_font_family().label, w - 228, y + 7, f.small, row_secondary)
        elseif item.id == "font_family" then
            local option = item.option
            local preview = ui.font_preview(option)
            local fg = row_text
            ui.text(option.label, 60, y + (item_h - f.normal:getHeight()) / 2, f.normal, fg)
            ui.text("Aa 09", w - 231, y + (item_h - preview:getHeight()) / 2, preview, fg)
            if ui.get_font_family() == option then
                ui.text("Active", w - 122, y + 9, f.tiny, row_secondary)
            end
        elseif item.id == "ui_motion" then
            ui.text("Interface motion", 60, y + 7, f.normal, row_text)
            ui.text(media_settings.get("ui_motion") and "On" or "Off", w - 109, y + 7, f.small,
                row_secondary)
        elseif item.id == "keyboard_languages" then
            ui.text("Keyboard languages", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Configure", w - 180, y + 7, f.small, row_secondary, 130, ink)
        elseif item.id == "keyboard_language" then
            local enabled = keyboard_languages.enabled(item.code)
            ui.text(item.label, 60, y + 7, f.normal, row_text)
            ui.text(enabled and "On" or "Off", w - 110, y + 7, f.small,
                row_secondary)
        elseif item.id == "message_sound" or item.id == "startup_intro" then
            local enabled = media_settings.get(item.id)
            ui.text(item.id == "startup_intro" and "Startup intro" or "Message sound", 60, y + 7, f.normal, row_text)
            ui.text(enabled and "On" or "Off", w - 110, y + 7, f.small, row_secondary)
        elseif is_vibration_test then
            ui.text("Vibration test", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Test", w - 200, y + 7, f.small, row_secondary, nil, ink)
        elseif is_minimize then
            ui.text("Minimize", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Minimize", w - 180, y + 7, f.small, row_secondary, nil, ink)
        elseif WIFI_ACTIONS[item.id] then
            local action = WIFI_ACTIONS[item.id]
            ui.text(action == "enable" and "Turn Wi-Fi on" or "Turn Wi-Fi off", 60, y + 7, f.normal, row_text)
            local state = self.tg:wifi_radio_label(action)
            if state then
                ui.text(state, w - 57 - f.small:getWidth(state), y + 7, f.small, row_secondary)
            else
                ui.button_hint("{confirm} — Apply", w - 170, y + 7, f.small, row_secondary, 120, ink)
            end
        elseif item.id == "reconnect" or item.id == "wifi_keep_awake" then
            local wifi = item.id == "wifi_keep_awake"
            ui.text(wifi and "Keep Wi-Fi awake" or "Reconnect to Telegram", 60, y + 7, f.normal, row_text)
            local status = wifi and self.tg:wifi_power_label() or self.tg:connection_label()
            local right = w - 57 - f.small:getWidth(status)
            ui.text(status, right, y + 7, f.small, row_secondary)
        elseif is_profile then
            ui.text("My profile", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Open", w - 180, y + 7, f.small, row_secondary, nil, ink)
        elseif is_theme then
            local cur = (self.callbacks.get_theme and self.callbacks.get_theme()) or "dark"
            ui.text("Theme: " .. cur, 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Change", w - 180, y + 7, f.small, row_secondary, nil, ink)
        elseif is_wallpaper then
            local cur = (self.callbacks.get_wallpaper and self.callbacks.get_wallpaper()) or "off"
            ui.text("Chat wallpaper: " .. cur, 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Toggle", w - 180, y + 7, f.small, row_secondary, nil, ink)
        elseif is_abxy then
            local swapped = self:abxy_layout() == "retro"
            ui.text("Swap Confirm / Back", 60, y + 7, f.normal, row_text)
            local layout = swapped and "On" or "Off"
            ui.text(layout, w - 108, y + 7, f.small, row_text)
            ui.text("Left/Right — Change", 56, y + item_h + 1, f.tiny, colors.muted)
        elseif is_show_mouse then
            local ms = media_settings.get("show_mouse_cursor")
            ui.text("Mouse pointer", 60, y + 7, f.normal, row_text)
            ui.text(ms and "On" or "Off", w - 110, y + 7, f.small, row_secondary)
            ui.text("Left/Right — Change", 60, y + item_h + 1, f.tiny, colors.muted)
        elseif item.id == "refresh_messages" then
            ui.text("Refresh messages", 60, y + 7, f.normal, row_text)
            ui.button_hint("{confirm} — Refresh", w - 130, y + 7, f.small, row_secondary, nil, ink)
        elseif is_account then
            local account = item.account
            ui.text(ui.fit(account.title or "Account", f.small, w - 190), 54, y + 2, f.small, row_text)
            local status = account.key == active_key and "active"
                or account.authorized and "saved" or "signed out"
            ui.text(status, w - 150, y + 4, f.tiny, row_secondary)
        elseif is_add then
            ui.text("+ Add account", 54, y + 5, f.small, row_text)
        elseif is_update_github then
            ui.text("PortMaster updates", 54, y + 7, f.small, row_text)
        elseif is_logout then
            local logout_label = self.logout_confirm and "Confirm sign-out" or "Sign out"
            ui.text(logout_label, 54, y + 7, f.small, row_text)
        end
    end

    local status = self.tg.action_error ~= "" and self.tg.action_error or self.tg.action_status
    if status and status ~= "" then
        local status_y = start_y + (last_visible - first_visible + 1) * row_h + 10
        ui.text(ui.fit(status, f.tiny, w - 80), 44, status_y, f.tiny,
            self.tg.action_error ~= "" and colors.red or colors.muted)
    end

    local hint_y = h - 30
    ui.button_hint("D-pad — Move or adjust   {confirm} — Select   {back} — Back", 24, hint_y, f.tiny, colors.muted)

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
    local panel_w = math.min(440, w - 36)
    local row_h = math.min(39, math.floor((h - 120) / (#controller_map.actions + 1)))
    local panel_h = row_h * (#controller_map.actions + 1) + 86
    local x, y = math.floor((w - panel_w) / 2), math.floor((h - panel_h) / 2)
    ui.rect(0, 0, w, h, colors.bg)
    ui.retro_panel(x, y, panel_w, panel_h, colors.panel, colors.accent_dark)
    ui.text("Map keys", x + 16, y + 13, f.subtitle, colors.text)
    for i = 1, #controller_map.actions + 1 do
        local action = controller_map.actions[i]
        local top = y + 44 + (i - 1) * row_h
        local selected = self.keymap_index == i
        ui.retro_panel(x + 12, top, panel_w - 24, row_h - 4,
            selected and colors.accent_dark or colors.panel_alt, colors.header)
        if selected then ui.focus_corners(x + 13, top + 1, panel_w - 26, row_h - 6, colors.accent) end
        ui.text(action and action.label or "Reset to defaults", x + 22, top + 8, f.small, colors.text)
        if action then
            local state = selected and self.keymap_waiting and "Press a button" or "{" .. action.id .. "}"
            ui.button_hint(state, x + panel_w - 120, top + 10, f.tiny,
                selected and colors.accent or colors.muted, 98)
        end
    end
    local text = self.keymap_waiting and "Face buttons, START or SELECT   ← — Cancel"
        or "D-pad — Move   {confirm} — Remap   {back} — Back"
    ui.button_hint(text, x + 12, y + panel_h - 29, f.tiny, colors.muted, panel_w - 24)
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
        self.release_open = self.releases ~= nil
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
    elseif WIFI_ACTIONS[item.id] then
        self.tg:set_wifi_radio(WIFI_ACTIONS[item.id])
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
    elseif item.id == "wallpaper" then
        if self.callbacks.toggle_wallpaper then self.callbacks.toggle_wallpaper() end
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
