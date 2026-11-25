
local ui = require("src.shared.ui.ui_kit")
local qr = require("src.shared.lib.qr")
local auth_model = require("src.features.auth.model.auth_model")
local utf8 = require("utf8")

local auth_screen = {}

local function key_chars(list)
    local out = {}
    for _, ch in ipairs(list) do
        out[#out + 1] = {ch = ch}
    end
    return out
end

function auth_screen.new(fonts, tg, callbacks)
    local self = {}
    self.fonts = fonts
    self.tg = tg
    self.callbacks = callbacks or {}
    local version = love and love.filesystem and love.filesystem.read("VERSION")
    self.version = version and version:match("^%s*(%d+%.%d+%.%d+)%s*$")
    self.model = auth_model.new(tg)
    self.qr_link = nil
    self.qr_image = nil
    self.qr_size = 0
    self.qr_error = ""
    self.password = ""

    self.selected_item = 1
    self.items = {"Sign in by phone", "Sign in by QR code", "Exit"}
    self.kb_row = 1
    self.kb_col = 1
    self.account_selected = 0
    self.account_bounds = {}
    self.kb_layer = "abc"
    self.kb_shift = false
    setmetatable(self, {__index = auth_screen})
    self:build_keyboard()
    return self
end

function auth_screen:enter()
    self.password = ""
    self.phone_input = false
    self.selected_item = 1
    self.account_selected = 0
    self.previous_keyboard_mode = nil
    self:reset_keyboard()
end

function auth_screen:keyboard_mode()
    if self.model:is_password_mode() then return "password" end
    if self.tg.auth_state == "authorizationStateWaitCode" then return "code" end
    if self.phone_input and self.tg.auth_state == "authorizationStateWaitPhoneNumber" then
        return "phone"
    end
end

function auth_screen:update(dt)
    if self.tg.qr_link ~= self.qr_link then
        self.qr_link = self.tg.qr_link
        if self.qr_link and self.qr_link ~= "" then
            local matrix, size = qr.encode(self.qr_link)
            if matrix then
                self.qr_image = qr.make_image(matrix, size)
                self.qr_size = size
                self.qr_error = ""
            else
                self.qr_image = nil
                self.qr_size = 0
                self.qr_error = "The sign-in link is too long for this QR code."
            end
        else
            self.qr_image = nil
            self.qr_size = 0
            self.qr_error = ""
        end
    end

    self:sync_keyboard()
end

function auth_screen:draw()
    local f = self.fonts
    local w = ui.width()
    local h = ui.height()
    local colors = ui.colors

    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 48, colors.header)
    ui.rect(0, 46, w, 2, colors.accent_dark)
    ui.pixel_chat(20, 13, 3, colors.accent)
    ui.text("SPgram", 56, 12, f.subtitle, colors.text)
    if self.version then
        ui.printf("v" .. self.version, w - 100, 16, 80, "right", f.small, colors.muted)
    end

    if self.tg.sign_in_only and self.tg.ready then
        ui.printf("Sign-in successful", 28, 92, w - 56, "center", f.subtitle, colors.text)
        ui.printf("This test build checks sign-in and session restart.",
            40, 148, w - 80, "center", f.normal, colors.text)
        ui.printf("Exit and reopen SPgram to check that you stay signed in.",
            40, 208, w - 80, "center", f.small, colors.muted)
        ui.button_hint("{confirm} — Exit", 40, h - 47, f.small, colors.text, w - 80)
        return
    end

    if self.tg.setup_error then
        ui.printf("Telegram setup required", 28, 76, w - 56, "center", f.subtitle, colors.text)
        ui.printf(self.tg.setup_error, 28, 116, w - 56, "center", f.normal, colors.red)
        ui.printf("Get your app credentials at my.telegram.org under API development tools.",
            40, 160, w - 80, "center", f.normal, colors.text)
        ui.printf("Save api_id and api_hash in:", 40, 217, w - 80, "center", f.small, colors.muted)
        ui.printf(self.tg.setup_path, 32, 245, w - 64, "center", f.normal, colors.text)
        ui.printf("Restart SPgram after saving the file.", 40, 298, w - 80, "center", f.small, colors.muted)
        ui.button_hint("{confirm} — Exit", 40, h - 47, f.small, colors.text, w - 80)
        return
    end

    if self:keyboard_mode() then
        self:draw_password(w, h)
        return
    end

    local status_y = 60
    if self.model:has_error() then
        ui.printf(self.model:get_error(), 40, 58, w - 80, "center", f.small, colors.red)
        local _, error_lines = f.small:getWrap(self.model:get_error(), w - 80)
        status_y = 58 + math.max(1, #error_lines) * f.small:getHeight() + 6
    end

    local accounts = (self.callbacks and self.callbacks.accounts and self.callbacks.accounts()) or ({})
    local active_key = nil
    local acc_list = accounts[1] or accounts

    local accs, active = {}, nil
    if self.callbacks and self.callbacks.accounts then
        local l, a = self.callbacks.accounts()
        accs = l or {}
        active = a
    end
    local saved = {}
    for _, a in ipairs(accs) do
        if a.authorized then saved[#saved+1] = a end
    end
    local welcome = #saved == 0 and self.tg.auth_state == "authorizationStateWaitPhoneNumber"
        and self.tg.options and self.tg.options.manual_auth and not self.tg.qr_request_pending
        and not self.qr_image and not self.model:has_error()
    if welcome then
        local mark_y = math.floor(h * 0.27)
        ui.retro_panel(math.floor(w / 2) - 49, mark_y - 12, 98, 80, colors.panel, colors.accent_dark)
        ui.pixel_chat(math.floor(w / 2) - 28, mark_y + 1, 7, colors.accent)
        status_y = mark_y + 87
    end
    ui.printf(self.model:get_status_text(), 40, status_y, w - 80, "center",
        welcome and f.subtitle or f.normal, colors.text)

    local btn_w = 300
    local btn_h = 30
    local gap = 8
    local acc_y = status_y + 10
    if #saved > 0 then
        ui.text("Saved accounts", 40, acc_y, f.small, colors.accent)
        acc_y = acc_y + 22
        self.account_bounds = {}
        for i, acc in ipairs(saved) do
            local x = math.floor((w - btn_w) / 2)
            local y = acc_y + (i - 1) * (btn_h + gap)
            local sel = (i == self.account_selected)
            local bg = sel and colors.accent or colors.panel
            local txt_color = sel and colors.bg or colors.text
            ui.rect(x, y, btn_w, btn_h, bg, 8)
            ui.outline(x, y, btn_w, btn_h, sel and colors.text or colors.muted, 8)
            local label = ui.fit((acc.title or "Account") .. (acc.key == active and " (active)" or ""), f.normal, btn_w - 20)
            local tx = x + 10
            local ty = y + math.floor((btn_h - f.normal:getHeight()) / 2)
            ui.text(label, tx, ty, f.normal, txt_color)
            self.account_bounds[i] = {x = x, y = y, w = btn_w, h = btn_h, key = acc.key}
        end
        acc_y = acc_y + #saved * (btn_h + gap) + 8
    end

    local menu_h = #self.items * btn_h + (#self.items - 1) * gap
    local menu_y = welcome and math.floor(h * 0.55) or h - menu_h - 36
    self.menu_bounds = {}
    local now = love.timer.getTime()
    if self.menu_focus ~= self.selected_item then
        self.menu_focus, self.menu_focus_time = self.selected_item, now
    end
    for i, item in ipairs(self.items) do
        local sel = (i == self.selected_item)
        local x = math.floor((w - btn_w) / 2)
        local y = menu_y + (i - 1) * (btn_h + gap)

        local bg = sel and colors.accent or colors.panel
        local txt_color = sel and colors.bg or colors.text
        local lift = sel and ui.focus_lift(now - self.menu_focus_time) or 0
        ui.retro_panel(x, y + 3, btn_w, btn_h, colors.header, colors.header)
        ui.retro_panel(x, y - lift, btn_w, btn_h, bg, sel and colors.accent or colors.accent_dark)
        local tx = x + math.floor((btn_w - f.normal:getWidth(item)) / 2)
        local ty = y + math.floor((btn_h - f.normal:getHeight()) / 2)
        ui.text(item, tx, ty - lift, f.normal, txt_color)
        self.menu_bounds[i] = {x = x, y = y - lift, w = btn_w, h = btn_h}
    end

    if self.qr_image then
        local available = math.min(w * 0.5, h - 300)
        local scale = math.max(2, math.floor(available / (self.qr_size + 8)))
        local total = (self.qr_size + 8) * scale
        local x = math.floor((w - total) / 2)
        local y = 100
        qr.draw(self.qr_image, x, y, scale, 3)

        local ty = y + total + 10
        ui.printf("Open Telegram on your phone", 40, ty, w - 80, "center", f.small, colors.text)
        ui.printf("Settings → Devices → Link Desktop Device", 40, ty + 18, w - 80, "center", f.tiny, colors.muted)
        ui.printf("Scan this QR code", 40, ty + 34, w - 80, "center", f.tiny, colors.muted)
    else
        if self.qr_error ~= "" then
            ui.printf(self.qr_error, 40, 190, w - 80, "center", f.normal, colors.red)
        elseif not welcome and not self.model:has_error()
            and not (self.tg.auth_state == "authorizationStateWaitPhoneNumber"
                and self.tg.options and self.tg.options.manual_auth and not self.tg.qr_request_pending) then
            ui.printf("Waiting for a QR code", 40, 190, w - 80, "center", f.normal, colors.muted)
            ui.printf("Check your Wi-Fi and Telegram API credentials.", 40, 218, w - 80, "center", f.small, colors.muted)
        end
    end

    local footer = "D-pad — Move   {confirm} — Select   {shortcuts} + {confirm} — Exit"
    if self.callbacks.open_face_setup then
        footer = footer .. "   {keyboard} — Set up buttons"
        ui.cog(w - 23, h - 14, colors.accent)
    end
    ui.button_hint(footer, 20, h - 21, f.tiny, colors.muted, w - 56)
end

function auth_screen:reset_keyboard()
    self.kb_row = 1
    self.kb_col = 1
    self.kb_layer = "abc"
    self.kb_shift = false
    self:build_keyboard()
end

function auth_screen:sync_keyboard()
    local mode = self:keyboard_mode()
    if mode ~= self.previous_keyboard_mode then
        self.previous_keyboard_mode = mode
        self.password = mode == "phone" and "+" or ""
        if mode then self:reset_keyboard() end
    end
end

function auth_screen:build_keyboard()
    local L = {}
    local mode = self:keyboard_mode()
    if mode == "phone" or mode == "code" then
        L[1] = key_chars({"1", "2", "3", "4", "5"})
        L[2] = key_chars({"6", "7", "8", "9", "0"})
        L[3] = {{label = "Back", action = "back", w = 90}}
        if mode == "phone" then L[3][#L[3] + 1] = {ch = "+"} end
        L[3][#L[3] + 1] = {label = "DEL", action = "backspace", w = 70}
        L[3][#L[3] + 1] = {label = "Send", action = "enter", w = 140}
    elseif self.kb_layer == "sym" then
        L[1] = key_chars({"!", "@", "#", "$", "%", "^", "&", "*", "(", ")"})
        L[2] = key_chars({"-", "_", "=", "+", "[", "]", "{", "}", "\\", "|"})
        L[3] = key_chars({";", ":", "'", "\"", ",", ".", "<", ">", "/", "?"})
        L[4] = {{label = "ABC", action = "layer", w = 70}}
        for _, ch in ipairs({"~", "`", "\\", "|"}) do
            L[4][#L[4] + 1] = {ch = ch}
        end
        L[4][#L[4] + 1] = {label = "DEL", action = "backspace", w = 70}
        L[5] = {
            {label = "Space", action = "space", w = 200},
            {ch = ","},
            {label = "Enter", action = "enter", w = 140},
        }
        L[6] = {{label = "Back", action = "back", w = 120}, {label = "Exit SPgram", action = "exit_app", w = 280}}
    else
        L[1] = key_chars({"1", "2", "3", "4", "5", "6", "7", "8", "9", "0"})
        L[2] = key_chars({"q", "w", "e", "r", "t", "y", "u", "i", "o", "p"})
        L[3] = key_chars({"a", "s", "d", "f", "g", "h", "j", "k", "l"})
        L[4] = {{label = "SHIFT", action = "shift", w = 70}}
        for _, ch in ipairs({"z", "x", "c", "v", "b", "n", "m"}) do
            L[4][#L[4] + 1] = {ch = ch}
        end
        L[4][#L[4] + 1] = {label = "DEL", action = "backspace", w = 70}
        L[5] = {{label = "?123", action = "layer", w = 70}}
        for _, ch in ipairs({"@", ".", "_", "-", "/", ":", ";", "!", "?"}) do
            L[5][#L[5] + 1] = {ch = ch}
        end
        L[6] = {
            {label = "Back", action = "back", w = 90},
            {label = "Space", action = "space", w = 170},
            {ch = ","},
            {label = "Enter", action = "enter", w = 120},
        }
        L[7] = {{label = "Exit SPgram", action = "exit_app", w = 400}}
    end
    self.kb_layout = L
    self.kb_row = math.max(1, math.min(self.kb_row or 1, #L))
    local row = L[self.kb_row]
    self.kb_col = math.max(1, math.min(self.kb_col or 1, #row))
end

function auth_screen:move_kb(dr, dc)
    local L = self.kb_layout
    if not L then return end
    if dr ~= 0 then
        self.kb_row = math.max(1, math.min(#L, self.kb_row + dr))
        local row = L[self.kb_row]
        self.kb_col = math.min(self.kb_col, #row)
    elseif dc ~= 0 then
        local row = L[self.kb_row]
        self.kb_col = math.max(1, math.min(#row, self.kb_col + dc))
    end
end

function auth_screen:activate_kb()
    local row = self.kb_layout and self.kb_layout[self.kb_row]
    local k = row and row[self.kb_col]
    if not k then return end
    if k.action == "shift" then
        self.kb_shift = not self.kb_shift
    elseif k.action == "layer" then
        self.kb_layer = (self.kb_layer == "abc") and "sym" or "abc"
        self:build_keyboard()
    elseif k.action == "back" then
        self:cancel_input()
    elseif k.action == "backspace" then
        self.password = ui.remove_last_utf8(self.password)
    elseif k.action == "space" then
        self.password = self.password .. " "
    elseif k.action == "enter" then
        self:send_input()
    elseif k.action == "exit_app" then
        love.event.quit()
    elseif k.ch then
        local ch = k.ch
        if self.kb_layer == "abc" and self.kb_shift and ch:match("%a") then
            ch = ch:upper()
        end
        self:textinput(ch)
    end
end

function auth_screen:send_input()
    local mode = self:keyboard_mode()
    if mode == "password" and self.password ~= "" then
        self.tg:submit_password(self.password)
        self.password = ""
    elseif mode == "phone" or mode == "code" then
        if self.tg:submit_auth_input(mode, self.password) and mode == "code" then
            self.password = ""
        end
    end
end

function auth_screen:cancel_input()
    if self:keyboard_mode() == "phone" and not self.tg.auth_input_pending then
        self.phone_input = false
        self:sync_keyboard()
    elseif self.callbacks.restart_account then
        self.callbacks.restart_account()
    end
end

function auth_screen:draw_password(w, h)
    local f = self.fonts
    local colors = ui.colors

    local mode = self:keyboard_mode()
    local title = mode == "phone" and "Phone number"
        or mode == "code" and "Telegram code" or "Two-step verification"
    ui.printf(title, 40, 58, w - 80, "center", f.subtitle, colors.text)
    if mode == "password" and self.model:get_password_hint() ~= "" then
        ui.printf(self.model:get_password_hint(), 40, 84, w - 80, "center", f.small, colors.muted)
    elseif self.tg.auth_input_pending then
        ui.printf("Waiting for Telegram…", 40, 84, w - 80, "center", f.small, colors.muted)
    end

    local btn_w, btn_h = 120, 30
    local bx = w - btn_w - 12
    local by = 12
    ui.rect(bx, by, btn_w, btn_h, colors.panel_alt, 6)
    ui.outline(bx, by, btn_w, btn_h, colors.accent, 6)
    local lbl = "Back"
    local tx = bx + math.floor((btn_w - f.normal:getWidth(lbl)) / 2)
    local ty = by + math.floor((btn_h - f.normal:getHeight()) / 2)
    ui.text(lbl, tx, ty, f.normal, colors.text)
    self.back_button = {x = bx, y = by, w = btn_w, h = btn_h}
    ui.button_hint("{back} — Back", 24, h - 28, f.tiny, colors.muted)

    local box_w = math.min(560, w - 80)
    local box_h = 40
    local bx = math.floor((w - box_w) / 2)
    local by = 108
    ui.rect(bx, by, box_w, box_h, colors.panel, 8)
    ui.outline(bx, by, box_w, box_h, colors.accent, 8)
    local shown = mode == "phone" and "+…" or mode == "code" and "Code" or "Password"
    if #self.password > 0 then
        local count = utf8.len(self.password) or #self.password
        shown = mode == "phone" and self.password or string.rep("•", math.min(32, count))
    end
    local ty = by + math.floor((box_h - f.normal:getHeight()) / 2)
    ui.text(shown, bx + 16, ty, f.normal, #self.password == 0 and colors.muted or colors.text)

    if self.model:has_error() then
        ui.printf(self.model:get_error(), 40, by + box_h + 2, w - 80, "center", f.tiny, colors.red)
    end

    if not self.kb_layout then self:build_keyboard() end
    local L = self.kb_layout
    local key_h = 36
    local gap = 3
    local kb_y = 166
    for r, row in ipairs(L) do
        local total = 0
        for i, k in ipairs(row) do
            total = total + (k.w or 58)
            if i > 1 then total = total + 3 end
        end
        local x = math.floor((w - total) / 2)
        local y = kb_y + (r - 1) * (key_h + gap)
        for c, k in ipairs(row) do
            local kw = k.w or 58
            local label = k.label
            if not label then
                label = k.ch
                if self.kb_layer == "abc" and self.kb_shift and label:match("%a") then
                    label = label:upper()
                end
            end
            local sel = (r == self.kb_row and c == self.kb_col)
            local active = (k.action == "shift" and self.kb_shift)
            local bg, txt, border
            if k.action == "exit_app" then
                bg = sel and colors.red or colors.panel
                txt = sel and colors.white or colors.red
                border = colors.red
            else
                bg = sel and colors.accent or (active and colors.header or colors.panel)
                txt = sel and colors.bg or colors.text
                border = sel and colors.text or colors.muted
            end
            ui.rect(x, y, kw, key_h, bg, 6)
            ui.outline(x, y, kw, key_h, border, 6)
            local lw = f.normal:getWidth(label)
            local lx = x + math.floor((kw - lw) / 2)
            local ly = y + math.floor((key_h - f.normal:getHeight()) / 2)
            ui.text(label, lx, ly, f.normal, txt)
            x = x + kw + 3
        end
    end

    ui.button_hint("D-pad — Move   {confirm} — Select   {back} — Cancel   {keyboard} — Submit",
        20, h - 17, f.tiny, colors.muted)
end

function auth_screen:textinput(text)
    local mode = self:keyboard_mode()
    if self.tg.auth_input_pending then return end
    if mode == "password" and #self.password + #text <= 256 then
        self.password = self.password .. text
    elseif mode == "phone" then
        if text == "+" and self.password == "" then self.password = "+" end
        local digits = text:match("^%+?(%d+)$")
        if digits and #self.password + #digits <= 16 then
            self.password = (self.password == "" and "+" or self.password) .. digits
        end
    elseif mode == "code" and text:match("^%d+$") and #self.password + #text <= 12 then
        self.password = self.password .. text
    end
end

function auth_screen:keypressed(key)
    if self.tg.setup_error or (self.tg.sign_in_only and self.tg.ready) then
        if key == "return" or key == "kpenter" or key == "escape" then love.event.quit() end
        return
    end
    self:sync_keyboard()
    if self:keyboard_mode() then
        if key == "up" then
            self:move_kb(-1, 0)
        elseif key == "down" then
            self:move_kb(1, 0)
        elseif key == "left" then
            self:move_kb(0, -1)
        elseif key == "right" then
            self:move_kb(0, 1)
        elseif key == "backspace" then
            self.password = ui.remove_last_utf8(self.password)
        elseif key == "return" or key == "kpenter" then
            self:activate_kb()
        elseif key == "f1" then
            self:send_input()
        elseif key == "escape" or key == "b" then
            self:cancel_input()
        end
        return
    end

    local accs, active = {}, nil
    if self.callbacks and self.callbacks.accounts then
        local l, a = self.callbacks.accounts()
        accs = l or {}
        active = a
    end
    local saved = {}
    for _, a in ipairs(accs) do if a.authorized then saved[#saved+1] = a end end

    if key == "f1" and (self.callbacks.open_face_setup or self.callbacks.toggle_face_buttons) then
        local setup = self.callbacks.open_face_setup or self.callbacks.toggle_face_buttons
        setup()
    elseif key == "up" then
        if self.account_selected > 0 then
            self.account_selected = math.max(1, self.account_selected - 1)
        elseif self.selected_item > 1 then
            self.selected_item = self.selected_item - 1
        else
            self.account_selected = #saved
        end
    elseif key == "down" then
        if self.account_selected > 0 then
            self.account_selected = self.account_selected < #saved and self.account_selected + 1 or 0
        else
            self.selected_item = math.min(#self.items, self.selected_item + 1)
        end
    elseif key == "return" or key == "kpenter" or key == "a" then
        if saved[self.account_selected] then
            local key_name = saved[self.account_selected].key
            if key_name ~= active and self.callbacks.switch_account then
                self.callbacks.switch_account(key_name)
            end
        else
            local item = self.items[self.selected_item]
            if item == "Sign in by phone" then
                if self.tg.auth_state == "authorizationStateWaitPhoneNumber" and not self.tg.qr_request_pending then
                    self.phone_input = true
                    self:sync_keyboard()
                elseif self.tg.auth_state == "authorizationStateWaitOtherDeviceConfirmation" then
                    self:cancel_input()
                end
            elseif item == "Sign in by QR code" then
                if self.tg.auth_state == "authorizationStateWaitPhoneNumber" then self.tg:request_qr() end
            elseif item == "Exit" then
                love.event.quit()
            end
        end
    elseif key == "escape" then
        love.event.quit()
    end
end

function auth_screen:mousepressed(x, y, button)
    if button == 1 then
        if self:keyboard_mode() and self.back_button then
            local b = self.back_button
            if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                self:cancel_input()
            end
        elseif not self:keyboard_mode() and not self.tg.setup_error and not (self.tg.sign_in_only and self.tg.ready) then
            if self.callbacks.open_face_setup and x >= ui.width() - 39 and y >= ui.height() - 26 then
                self.callbacks.open_face_setup()
                return
            end
            for index, bounds in ipairs(self.menu_bounds or {}) do
                if x >= bounds.x and x < bounds.x + bounds.w and y >= bounds.y and y < bounds.y + bounds.h then
                    self.selected_item, self.account_selected = index, 0
                    self:keypressed("return")
                    return
                end
            end
        end
    end
end
function auth_screen:wheelmoved() end

return auth_screen
