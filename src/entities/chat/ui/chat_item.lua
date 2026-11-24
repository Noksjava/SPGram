
local ui = require("src.shared.ui.ui_kit")
local chat_item = {}
local REPLIES_USER_ID = 1271266957
local TEST_REPLIES_USER_ID = 708513

local function is_replies_chat(tg, chat)
    local kind = chat.type
    if not kind or kind["@type"] ~= "chatTypePrivate" then return false end
    local id = tg.options and tg.options.use_test_dc and TEST_REPLIES_USER_ID or REPLIES_USER_ID
    return tonumber(kind.user_id) == id
end

local function draw_reply_icon(x, y, color)
    ui.rect(x + 6, y, 3, 3, color)
    ui.rect(x + 3, y + 3, 3, 3, color)
    ui.rect(x, y + 6, 21, 3, color)
    ui.rect(x + 3, y + 9, 3, 3, color)
    ui.rect(x + 6, y + 12, 3, 3, color)
    ui.rect(x + 18, y + 9, 3, 9, color)
end

local function draw_muted_icon(x, y, color)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(x, y - 5, x - 4, y - 1, x - 4, y + 3, x + 4, y + 3, x + 4, y - 1, x, y - 5)
    love.graphics.line(x - 2, y + 5, x + 2, y + 5)
    love.graphics.line(x - 7, y - 6, x + 7, y + 7)
    love.graphics.setLineWidth(1)
end

function chat_item.draw(self, chat, x, y, w, h, fonts, colors, is_selected, is_current)
    local bg = colors.panel
    if is_current then
        bg = colors.accent_dark
    elseif is_selected then
        bg = colors.panel_alt
    end
    ui.retro_panel(x + 5, y + 3, w - 10, h - 6, bg, is_current and colors.accent_dark or colors.header)
    if is_selected then
        ui.focus_corners(x + 6, y + 4, w - 12, h - 8, colors.accent, self.list_focus_lift)
    end

    local title = chat.title or ""
    local replies = is_replies_chat(self.tg, chat)
    local avatar_image = not replies and self.tg:chat_photo_image(chat.id)
    local avatar_x, avatar_y, avatar_size = x + 14, y + 14, 34
    ui.retro_panel(avatar_x - 2, avatar_y - 2, avatar_size + 4, avatar_size + 4,
        colors.accent_dark, colors.accent_dark)

    if replies then
        draw_reply_icon(avatar_x + 6, avatar_y + 8, colors.accent)
    elseif avatar_image then
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", avatar_x, avatar_y, avatar_size, avatar_size, 6)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        local scale = math.max(avatar_size / avatar_image:getWidth(), avatar_size / avatar_image:getHeight())
        local aw = avatar_image:getWidth() * scale
        local ah = avatar_image:getHeight() * scale
        local ax = avatar_x + (avatar_size - aw) / 2
        local ay = avatar_y + (avatar_size - ah) / 2
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(avatar_image, ax, ay, 0, scale, scale)
        love.graphics.setStencilTest()
    else
        local initial = ui.first_char(title)
        ui.printf(initial, avatar_x, avatar_y + 8, avatar_size, "center", fonts.subtitle, colors.accent)
    end

    local text_x = x + avatar_size + 26
    local text_w = x + w - text_x - 16
    local muted = self.tg:is_chat_muted(chat)
    local reserved = muted and 28 or 0
    ui.text(ui.fit(title, fonts.normal, text_w - 20), text_x, y + 12, fonts.normal, colors.text)
    if chat.sponsored_peer then
        local hint = is_selected and "Sponsored   {search} — Report   {options} — Info" or "Sponsored"
        ui.button_hint(hint, text_x, y + 38, fonts.tiny, colors.accent, text_w)
        return
    end
    if muted then draw_muted_icon(x + w - 24, y + 42, colors.muted) end

    local last = chat.last_message
    if last and last.date then
        local time_text = os.date("%H:%M", last.date)
        ui.text(time_text, text_x, y + 55, fonts.tiny, colors.muted)
    end

    local preview = ""
    if last then
        preview = self.tg:message_text(last)
    end
    ui.text(ui.fit(preview, fonts.tiny, text_w - reserved), text_x, y + 34, fonts.tiny, colors.muted)

    local ping = self.tg.live_message_pings and self.tg.live_message_pings[chat.id]
    local now = ping and love.timer.getTime()
    local age = ping and now - ping.created
    if age and age >= 0 and age < 4 then
        local lift = ui.focus_lift(age)
        ui.rect(avatar_x + avatar_size - 2, avatar_y - 2 - lift, 7, 7, muted and ui.notification_gray or colors.green)
        ui.rect(avatar_x + avatar_size, avatar_y - lift, 3, 3, colors.bg)
    end

    local unread = chat.unread_count or 0
    if unread > 0 then
        local badge = tostring(unread)
        local badge_w = math.max(22, fonts.tiny:getWidth(badge) + 12)
        local badge_y = y + 52 - (age and ui.focus_lift(age) or 0)
        local badge_color = muted and ui.notification_gray or colors.accent
        ui.retro_panel(x + w - 16 - badge_w, badge_y, badge_w, 18, badge_color, badge_color)
        ui.printf(badge, x + w - 16 - badge_w, badge_y + 2, badge_w, "center", fonts.tiny,
            muted and colors.white or colors.bg)
    end
end

return chat_item
