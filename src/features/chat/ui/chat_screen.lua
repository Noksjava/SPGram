
local ui = require("src.shared.ui.ui_kit")
local chat_model = require("src.features.chat.model.chat_model")
local chat_item = require("src.entities.chat.ui.chat_item")
local virtual_keyboard = require("src.shared.ui.virtual_keyboard")
local performance = require("src.shared.system.performance")
local media_settings = require("src.shared.system.media_settings")
local sponsors = require("src.shared.api.sponsored")

local HEADER_HEIGHT = 56
local CHAT_HEADER_HEIGHT = 64
local INPUT_HEIGHT = 72
local FOOTER_HEIGHT = 24
local ITEM_HEIGHT = 76
local NAV_ITEM_HEIGHT = math.floor(ITEM_HEIGHT / 3)

local function row_height(chat)
    return chat.navigation and NAV_ITEM_HEIGHT or ITEM_HEIGHT
end

local function draw_nav_icon(kind, x, y, color)
    love.graphics.setColor(color)
    if kind == "saved" then
        love.graphics.polygon("line", x, y, x + 12, y, x + 12, y + 13, x + 6, y + 9, x, y + 13)
    elseif kind == "archive" then
        love.graphics.rectangle("line", x, y + 3, 13, 10, 1)
        love.graphics.line(x - 1, y + 3, x + 14, y + 3, x + 14, y, x - 1, y, x - 1, y + 3)
        love.graphics.line(x + 4, y + 7, x + 9, y + 7)
    else
        love.graphics.line(x + 5, y + 2, x, y + 7, x + 5, y + 12)
        love.graphics.line(x, y + 7, x + 12, y + 7)
    end
end

local REACTION_EMOJIS = {
    "👍", "👎", "❤️", "🔥", "🥰",
    "👏", "😁", "🤔", "🤯", "😱",
    "🤬", "😢", "🎉", "🤩", "💩",
    "🙏", "💯", "👀", "🤝", "✌️",
}
local REACTION_COLUMNS = 5

local function alpha_color(color, alpha)
    return {color[1], color[2], color[3], alpha}
end

local messenger_screen = {}
require("src.features.chat.ui.chat_comments")(messenger_screen)
require("src.features.chat.ui.chat_screen_media")(messenger_screen)
require("src.features.chat.ui.chat_screen_input")(messenger_screen, {
    HEADER_HEIGHT = HEADER_HEIGHT,
    CHAT_HEADER_HEIGHT = CHAT_HEADER_HEIGHT,
    INPUT_HEIGHT = INPUT_HEIGHT,
    ITEM_HEIGHT = ITEM_HEIGHT,
    REACTION_EMOJIS = REACTION_EMOJIS,
    REACTION_COLUMNS = REACTION_COLUMNS,
})

local helpers = require("src.features.chat.ui.chat_screen_helpers")
local wrapped_lines = helpers.wrapped_lines
local draw_circle_image = helpers.draw_circle_image
local draw_text_lines = helpers.draw_text_lines

local conversation_items = helpers.conversation_items

function messenger_screen.new(fonts, tg)
    local self = {}
    self.fonts = fonts
    self.tg = tg
    self.model = chat_model.new(tg)
    self.custom_emoji_image = function(id)
        local sticker = type(id) == "table" and id or tg:custom_emoji_sticker(id)
        if not sticker then return end
        local image = self:picker_item_image({kind = "emoji", value = sticker}, false)
        return image, sticker.full_type and sticker.full_type.needs_repainting
    end
    self.status_info = {last_refresh = -math.huge, time = os.date("%H:%M")}
    self.keyboard = virtual_keyboard.new(fonts)
    self.model.input = ""
    self.archive_mode = false
    self.list_kind = "main"
    self.list_filter_id = nil
    self.selected_messages = {}
    self.context_menu = nil
    self.reaction_menu = nil
    self.forward_mode = false
    self.forward_from_chat_id = nil
    self.wants_settings = false
    self.wants_profile_chat_id = nil
    self.wants_profile_self = nil
    self.edit_mode = false
    self.edit_message = nil
    self.edit_input = ""
    self.wants_profile_user_id = nil
    self.wants_open_chat = nil
    self.fullscreen_media = nil
    self.sticker_pack_menu = nil
    self.last_media_click = nil
    self.search_active = false
    self.search_query = ""
    self.search_changed_at = 0
    self.search_submitted_query = nil
    self.hashtag_hits = {}
    self.message_cursor_id = nil
    self.display_cursor_id = nil
    self.composer_focus = nil
    self.selected_messages = {}
    self.cursor_highlight_timer = 0
    self.nav_messages = {}
    self.nav_pos = {}
    self.conv_area_x = nil
    self.conv_area_y = nil
    self.conv_area_w = nil
    self.conv_area_h = nil
    self.fullscreen_zoom = 1
    self.fullscreen_pan_x = 0
    self.fullscreen_pan_y = 0
    self.fullscreen_drag_start = nil
    self.notification_timer = nil
    self.smooth_scroll = 0
    self.scroll_dir = nil
    self.scroll_hold_start = nil
    self.menu_anim = 1
    return setmetatable(self, {__index = messenger_screen})
end

function messenger_screen:enter()
    self.draft_emoji_entities = nil
    self.model.input = ""
    self.model.scroll = 0
    self.smooth_scroll = 0
    self.model.list_offset = 0
    if self.tg.current_chat_id then
        self:select_chat(self.tg.current_chat_id)
    else
        self:load_chats_for_mode()
    end
end

function messenger_screen:select_chat(chat_id, history_loaded)
    if self.tg.current_chat_id == chat_id then return end
    self.tg:open_chat(chat_id, history_loaded)
    self.model.scroll = 0
    self.sponsor_tail, self.sponsor_focus, self.sponsor_prompt = nil, nil, nil
    self.sponsor_inline = nil
    self.smooth_scroll = 0
    self.message_cursor_id = nil
    self.display_cursor_id = nil
    self.composer_focus = nil
    self.cursor_highlight_timer = 0
    self.nav_messages = {}
    self.nav_pos = {}
    if self.search_active and self.search_query ~= "" then
        self.tg:search_chat_messages(chat_id, self.search_query)
    end
end

function messenger_screen:select_list_chat(chat)
    if chat.navigation == "archive" or chat.navigation == "main" then
        return self:select_list({kind = chat.navigation})
    end
    if chat.navigation == "saved" and not chat.id then return self.tg:load_saved_messages() end
    if not chat.id then return end
    if chat.sponsored_peer and not self.tg:open_search_sponsor(chat.sponsored_peer) then return end
    if self.search_active then
        self.search_active = false
        self:set_search_query("", false)
    end
    self:select_chat(chat.id)
end

function messenger_screen:list_entries()
    local entries = {{kind = "main", title = "Chats"}}
    for _, filter in ipairs(self.tg.chat_filters or {}) do
        entries[#entries + 1] = {
            kind = "filter",
            id = filter.id,
            title = filter.title or ("Folder " .. tostring(filter.id)),
        }
    end
    entries[#entries + 1] = {kind = "archive", title = "Archive"}
    return entries
end

function messenger_screen:is_current_entry(entry)
    return entry.kind == self.list_kind
        and (entry.kind ~= "filter" or entry.id == self.list_filter_id)
end

function messenger_screen:current_list_entry()
    for _, entry in ipairs(self:list_entries()) do
        if self:is_current_entry(entry) then return entry end
    end
    return {kind = "main", title = "Chats"}
end

function messenger_screen:load_chats_for_mode()
    if self.list_kind == "archive" then
        self.tg:load_archive_chats()
    elseif self.list_kind == "filter" then
        self.tg:load_filter_chats(self.list_filter_id)
    else
        self.tg:send({
            ["@type"] = "loadChats",
            chat_list = {["@type"] = "chatListMain"},
            limit = 20,
        }, "loadChats")
    end
end

function messenger_screen:switch_list(delta)
    local entries = self:list_entries()
    if #entries <= 1 then return end
    local index = 1
    for i, entry in ipairs(entries) do
        if self:is_current_entry(entry) then
            index = i
            break
        end
    end
    index = ((index - 1 + delta) % #entries) + 1
    self:select_list(entries[index])
end

function messenger_screen:select_list(target)
    if self:is_current_entry(target) then return end
    if self.tg.current_chat_id then self.tg:close_chat() end
    self.list_kind = target.kind
    self.list_filter_id = target.id
    self.archive_mode = target.kind == "archive"
    self.model.archive_mode = self.archive_mode
    self.model.selected = 1
    self.model.list_offset = 0
    self.model.scroll = 0
    self:load_chats_for_mode()
end

function messenger_screen:toggle_archive()
    self:switch_list(1)
end

function messenger_screen:archive_current_chat(archive)
    if not self.tg.current_chat_id then return end
    self.tg:archive_chat(self.tg.current_chat_id, archive)
end

function messenger_screen:get_visible_chat_list()
    if self.search_active and self.search_query ~= "" then
        local peer_results = self.tg.search_sponsors
        local peers = not self.forward_mode and peer_results and peer_results.items or {}
        return sponsors.search_rows(self.tg.search_chat_results or {},
            peers, self.tg.public_search_results or {}, function(id)
                return self.tg.chats_by_id[id] or self.tg.archive_chats_by_id[id]
            end)
    end
    if self.list_kind == "archive" then
        local rows = self.forward_mode and {} or {{navigation = "main", title = "Back to Chats"}}
        for _, chat in ipairs(self.tg.archive_chats) do rows[#rows + 1] = chat end
        return rows
    end
    if self.list_kind == "filter" then
        return (self.tg.filter_chats or {})[self.list_filter_id] or {}
    end
    local rows = {}
    if not self.forward_mode then
        rows = {
            {navigation = "saved", title = "Saved Messages", id = self.tg.saved_chat_id},
            {navigation = "archive", title = "Archived Chats"},
        }
    end
    for _, chat in ipairs(self.tg.chats or {}) do
        if chat.id ~= self.tg.saved_chat_id or self.forward_mode then rows[#rows + 1] = chat end
    end
    return rows
end

function messenger_screen:set_search_query(query, immediate)
    self.search_query = query or ""
    self.search_changed_at = love.timer.getTime()
    if immediate then
        self.search_changed_at = self.search_changed_at - 1
    end
    self.search_submitted_query = nil
    self.model.list_offset = 0
    self.model.selected = 1
    self.model.visible_chats = nil
    self.tg:search_chats("")
    self.tg:search_public_chats("")
    if self.search_query == "" then
        if self.tg.current_chat_id then
            self.tg:search_chat_messages(self.tg.current_chat_id, "")
        end
        self.search_submitted_query = ""
    else
        self.tg.search_chat_results = {}
        self.tg.public_search_results = {}
    end
end

function messenger_screen:submit_search()
    local query = self.search_query
    if query == self.search_submitted_query then return end
    self.search_submitted_query = query
    self.tg:search_chats(query)
    self.tg:search_public_chats(query)
    if self.tg.current_chat_id then
        self.tg:search_chat_messages(self.tg.current_chat_id, query)
    end
end

function messenger_screen:update(dt)
    self:update_quote_jump()
    local action = (self.tg.action_error ~= "" and self.tg.action_error) or self.tg.action_status
    if action and action ~= "" and action ~= self.last_action then
        self.notification_timer = 6
    elseif self.notification_timer then
        self.notification_timer = self.notification_timer - dt
        if self.notification_timer <= 0 then
            self.tg.action_status, self.tg.action_error = "", ""
            self.notification_timer, action = nil, nil
        end
    end
    self.last_action = action

    if self.list_kind == "filter" then
        local found = false
        for _, filter in ipairs(self.tg.chat_filters or {}) do
            if filter.id == self.list_filter_id then
                found = true
                break
            end
        end
        if not found then
            self.list_kind = "main"
            self.list_filter_id = nil
            self.archive_mode = false
            self.model.archive_mode = false
        end
    end
    if self.search_active and self.search_query ~= ""
        and self.search_query ~= self.search_submitted_query
        and love.timer.getTime() - self.search_changed_at >= 0.25 then
        self:submit_search()
    end
    local previous_selection = self.search_active and self.model.visible_chats and self.model:selected_chat()
    self.model.visible_chats = self:get_visible_chat_list()
    if previous_selection then
        for index, row in ipairs(self.model.visible_chats) do
            if row.id == previous_selection.id and row.sponsored_peer == previous_selection.sponsored_peer then
                self.model.selected = index
                break
            end
        end
    end
    self.model:clamp_selection()

    local target_scroll = self.model.scroll or 0
    if self.smooth_scroll == nil or math.abs(target_scroll - self.smooth_scroll) > 2000 then
        self.smooth_scroll = target_scroll
    end
    local factor = 0.25
    self.smooth_scroll = self.smooth_scroll + (target_scroll - self.smooth_scroll) * factor
    if math.abs(target_scroll - self.smooth_scroll) < 0.5 then
        self.smooth_scroll = target_scroll
        if self.message_cursor_target_id then
            self.display_cursor_id = self.message_cursor_target_id
            self.message_cursor_target_id = nil
        end
    end

    if self.text_preview and self.text_preview.loading then
        local msg = self.text_preview.message
        local doc = msg and msg.content and msg.content.document
        local file = doc and doc.document
        local fl = file and file["local"]
        if fl then

            if fl.size and fl.size > 0 then
                self.text_preview.download_progress = fl.downloaded / fl.size
            end
            if fl.path and fl.path ~= "" and not self.text_preview.preview_lines then
                local pf = io.open(fl.path, "r")
                if pf then
                    local plines = {}
                    for i = 1, 10 do
                        local l = pf:read("*l")
                        if not l then break end
                        plines[#plines + 1] = l
                    end
                    pf:close()
                    if #plines > 0 then
                        self.text_preview.preview_lines = plines
                    end
                end
            end
            if fl.is_downloading_completed and fl.path and fl.path ~= "" then
                local lines = {}
                local f = io.open(fl.path, "r")
                if f then
                    for line in f:lines() do lines[#lines + 1] = line end
                    f:close()
                end
                self.text_preview.loading = false
                self.text_preview.lines = lines
                self.text_preview.download_progress = 1.0
                self.text_preview.preview_lines = nil
            end
        end
    end
    self.menu_anim = math.min(1, (self.menu_anim or 1) + dt * 12)
    self:refresh_status()
    local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
    if self.composer_focus then
        if self.composer_focus == 2 and not media or self.composer_focus ~= 2 and not text then
            self.composer_focus = text and 1 or media and 2 or nil
        end
    end
    if not text and self.keyboard.visible and not self.search_active and not self.edit_mode
        and not self.tg.sticker_set_viewer and not self.tg.comments_thread then
        self.keyboard.visible = false
    end

    if self.fullscreen_media then
        local pan_x = self.fullscreen_pan_x or 0
        local pan_y = self.fullscreen_pan_y or 0
        local target_x = self.fullscreen_pan_target_x
        local target_y = self.fullscreen_pan_target_y
        if target_x ~= nil then
            local factor = 1 - math.exp(-12 * dt)
            pan_x = pan_x + (target_x - pan_x) * factor
            if math.abs(target_x - pan_x) < 0.5 then pan_x = target_x; target_x = nil end
            self.fullscreen_pan_x = pan_x
            self.fullscreen_pan_target_x = target_x
        end
        if target_y ~= nil then
            local factor = 1 - math.exp(-12 * dt)
            pan_y = pan_y + (target_y - pan_y) * factor
            if math.abs(target_y - pan_y) < 0.5 then pan_y = target_y; target_y = nil end
            self.fullscreen_pan_y = pan_y
            self.fullscreen_pan_target_y = target_y
        end
    end

    local held_keys = {}
    if self.tg and love and love.keyboard and love.keyboard.isDown then
        if love.keyboard.isDown("left") then held_keys[#held_keys + 1] = "left" end
        if love.keyboard.isDown("right") then held_keys[#held_keys + 1] = "right" end
        if love.keyboard.isDown("pageup") then held_keys[#held_keys + 1] = "pageup" end
        if love.keyboard.isDown("pagedown") then held_keys[#held_keys + 1] = "pagedown" end
    end
    if held_keys[1] == "pageup" and self.tg.current_chat_id then
        local step = (self.conv_area_h or 300) * 0.9
        self.smooth_scroll = math.min(self.model.max_scroll or 0, (self.smooth_scroll or 0) + step * dt)
    elseif held_keys[1] == "pagedown" and self.tg.current_chat_id then
        local step = (self.conv_area_h or 300) * 0.9
        self.smooth_scroll = math.max(0, (self.smooth_scroll or 0) - step * dt)
    end
end

function messenger_screen:chat_list_width(w)
    return math.floor(w * (self.tg.current_chat_id and 0.30 or 0.50))
end

function messenger_screen:focus_header(action)
    self.header_focus, self.header_focus_at = action, love.timer.getTime()
end

function messenger_screen:activate_header(action)
    self.header_focus = nil
    if action == "settings" then
        self.wants_settings = true
    elseif action == "profile" and self.tg.me then
        self.wants_profile_self = true
    end
end

function messenger_screen:draw()
    local f = self.fonts
    local colors = ui.colors
    local w = ui.width()
    local h = ui.height()
    local left_width = self:chat_list_width(w)
    local right_width = w - left_width

    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, HEADER_HEIGHT, colors.header)
    ui.rect(0, HEADER_HEIGHT - 2, w, 2, colors.accent_dark)
    if self.app_logo == nil then
        local ok, logo = pcall(love.graphics.newImage, "icons/app/spgram.png", {mipmaps = true})
        self.app_logo = ok and logo or false
        if self.app_logo then
            logo:setFilter("linear", "linear")
            logo:setMipmapFilter("linear")
            local width, height = logo:getDimensions()
            if width == 396 and height == 419 then
                self.app_logo_quad = love.graphics.newQuad(96, 5, 240, 330, width, height)
            end
        end
    end
    local header_age = love.timer.getTime() - (self.header_focus_at or -1)
    local header_lift = ui.focus_lift(header_age)
    local logo_x, logo_y, logo_size = 10, 5, 44
    local settings_selected = self.header_focus == "settings"
    if settings_selected then logo_y = logo_y - header_lift end
    if self.app_logo then
        local logo = self.app_logo
        local quad = self.app_logo_quad
        local width, height = logo:getDimensions()
        if quad then
            local _, _, crop_width, crop_height = quad:getViewport()
            width, height = crop_width, crop_height
        end
        local scale = logo_size / math.max(width, height)
        local x = logo_x + (logo_size - width * scale) / 2
        local y = logo_y + (logo_size - height * scale) / 2
        love.graphics.setColor(1, 1, 1)
        if quad then love.graphics.draw(logo, quad, x, y, 0, scale, scale)
        else love.graphics.draw(logo, x, y, 0, scale, scale) end
    else
        ui.pixel_chat(logo_x + 7, logo_y + 12, 3, colors.accent)
    end
    if settings_selected then ui.focus_corners(logo_x - 1, logo_y - 1, logo_size + 2, logo_size + 2, colors.accent) end
    self.header_hits = {{action = "settings", x = logo_x - 4, w = logo_size + 8}}
    local status_scale = math.min(1, w / 600)
    local status_width = math.floor(260 * status_scale)
    local status_x = math.floor((w - status_width) / 2)
    local status_right = status_x + status_width
    self:draw_status_panel(status_x, status_width, status_scale)
    local title = self.search_active and "Search" or self:current_list_entry().title
    ui.text(ui.fit(title, f.subtitle, math.min(left_width, status_x) - 74), 66, 17, f.subtitle, colors.text)
    if self.search_active then
        local x = status_right + 10
        local width = w - x - 14
        ui.rect(x, 10, width, 36, colors.panel_alt, 6)
        ui.text(ui.fit(self.search_query .. (self.search_query == "" and "Search chats and channels…" or " |"), f.small, width - 20),
            x + 10, 19, f.small, colors.text)
    elseif self.forward_mode then
        ui.text(ui.fit("Choose a destination chat", f.tiny, w - status_right - 24), status_right + 10, 18, f.tiny, colors.yellow)
    end

    local me = self.tg.me
    if me and not self.search_active and not self.forward_mode then
        local x, size = w - 49, 34
        local selected = self.header_focus == "profile"
        local y = 10 - (selected and header_lift or 0)
        local name = ui.fit(self.tg:user_name(me.id), f.normal, math.max(10, x - status_right - 24))
        local name_x = x - 11 - f.normal:getWidth(name)
        local avatar = self.tg:user_photo_image(me.id)
        ui.retro_panel(x, y, size, size, colors.panel_alt, colors.accent_dark)
        if avatar then
            local inner = size - 4
            local scale = math.max(inner / avatar:getWidth(), inner / avatar:getHeight())
            love.graphics.setScissor(x + 2, y + 2, inner, inner)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(avatar, x + (size - avatar:getWidth() * scale) / 2,
                y + (size - avatar:getHeight() * scale) / 2, 0, scale, scale)
            love.graphics.setScissor()
        else
            ui.printf(ui.first_char(name), x, y + (size - f.normal:getHeight()) / 2, size, "center", f.normal, colors.accent)
        end
        ui.text(name, name_x, 17, f.normal, selected and colors.accent or colors.text)
        if selected then ui.focus_corners(x - 3, y - 3, 40, 40, colors.accent, header_lift) end
        self.header_hits[2] = {action = "profile", x = name_x - 4, w = w - name_x - 6}
    end

    self:draw_loading_indicator(f, colors, w, left_width, right_width)

    self:draw_chat_list(left_width, h)

    local chat = self.model:current_chat()
    self.read_jump_hit = nil
    if not chat then self.cached_conversation_layout = nil end
    if chat then
        self:draw_conversation(chat, left_width, right_width, h)
    else
        ui.rect(left_width, HEADER_HEIGHT, right_width, h - HEADER_HEIGHT, colors.bg)
        local panel_w = math.min(270, right_width - 32)
        local panel_x, panel_y = left_width + (right_width - panel_w) / 2, math.floor(h / 2) - 66
        ui.retro_panel(panel_x, panel_y, panel_w, 126, colors.panel, colors.accent_dark)
        ui.pixel_chat(left_width + math.floor(right_width / 2) - 16, panel_y + 18, 4, colors.accent)
        ui.printf("Choose a chat", panel_x, panel_y + 63, panel_w, "center", f.subtitle, colors.text)
        ui.button_hint("{confirm} — Open   {options} — Options",
            panel_x + 10, panel_y + 94, f.small, colors.muted, panel_w - 20)
    end

    local hint
    if self.header_focus and not self.search_active and not self.forward_mode then
        local action = self.header_focus == "settings" and "Settings" or "My profile"
        hint = "←/→ — Switch   {confirm} — " .. action .. "   ↓ — Return"
    elseif self.forward_mode then
        hint = "{confirm} — Forward   {back} — Cancel"
    elseif self.search_active then
        hint = "{keyboard} — Search   {confirm} — Open   {back} — Close search"
    elseif chat and next(self.selected_messages) then
        local count = 0
        for _ in pairs(self.selected_messages) do count = count + 1 end
        hint = string.format("%d selected   {options} — Options   {back} — Clear selection", count)
    elseif self.composer_focus and chat and self:can_show_composer(chat) then
        hint = "←/→ — Choose   {confirm} — Activate   ↑ — Messages   {back} — Chats"
    elseif chat then
        local message = self:focused_message()
        local kind = message and message.content and message.content["@type"]
        local action = kind == "messageText" and "Read" or "Open"
        if self:is_video_post(message, chat) then action = "Read post"
        elseif self.tg:video_kind(message) or kind == "messageAudio" or kind == "messageVoiceNote" then action = "Play" end
        local comment = self:focused_comment_target()
        hint = "{confirm} — " .. (self.nav_albums and message and self.nav_albums[message.id] and "Post" or action)
            .. "   {options} — Options" .. (comment and "   {search} — Comments" or "")
            .. (self:can_show_composer(chat) and "   ↓ — Compose" or "") .. "   {back} — Chats"
    else
        hint = "{confirm} — Open   {options} — Options   ↑ — Header   {shortcuts} — Controls"
    end
    ui.rect(0, h - FOOTER_HEIGHT, w, FOOTER_HEIGHT, colors.header)
    self.face_setup_hit = {x = w - 39, y = h - FOOTER_HEIGHT, w = 27, h = FOOTER_HEIGHT}
    ui.cog(w - 25, h - FOOTER_HEIGHT / 2, colors.accent)
    ui.button_hint(hint, 12, h - 18, f.tiny, colors.muted, w - 54)
    local action_error = self.tg.action_error
    local action_message = (action_error ~= "" and action_error) or self.tg.action_status
    if action_message and action_message ~= "" then
        local color = action_error and action_error ~= "" and colors.red or colors.green
        local action_w = math.min(w - 32, f.tiny:getWidth(action_message) + 34)
        local x, y = math.floor((w - action_w) / 2), h - 112
        ui.retro_panel(x, y, action_w, 24, colors.panel, colors.accent_dark)
        ui.rect(x + 8, y + 9, 5, 5, color)
        ui.text(ui.fit(action_message, f.tiny, action_w - 26), x + 20, y + 5, f.tiny, colors.text)
    end

    self:draw_notifications(f, colors, w, h)
    if not (self.context_menu and self.context_menu.comment_thread) then self:draw_context_menu(f, colors, w, h) end
    if not self.tg.comments_thread then self:draw_reaction_menu(f, colors, w, h) end

    self:draw_edit_overlay(f, colors, w, h)
    if self.keyboard and self.keyboard.visible and not self.fullscreen_media
        and not self.tg.sticker_set_viewer then
        self.keyboard:draw(self:keyboard_preview())
    end
    if not self.tg.comments_thread then self:draw_fullscreen_media(w, h) end
    self:draw_sticker_pack(w, h)
    if self.sponsor_prompt then
        local prompt = self.sponsor_prompt
        local box_w = math.min(500, w - 32)
        local x = (w - box_w) / 2
        if prompt.report then
            local report = self.tg.channel_sponsor_report
            local options = report and report.options
            local selected = prompt.selected or 1
            ui.rect(x, 80, box_w, 312, colors.panel, 8)
            if options and #options > 0 then
                ui.printf(ui.fit(report.title or "Report sponsored post", f.normal, box_w - 24),
                    x + 12, 94, box_w - 24, "center", f.normal, colors.text)
                local first = math.max(1, selected - 5)
                for index = first, math.min(#options, first + 5) do
                    local line_y = 129 + (index - first) * 34
                    if selected == index then ui.rect(x + 10, line_y - 3, box_w - 20, 30, colors.header, 5) end
                    ui.text(ui.fit(options[index].text, f.small, box_w - 36),
                        x + 18, line_y, f.small, colors.text)
                end
            else
                local verdicts = {
                    reportSponsoredResultOk = "Report sent",
                    reportSponsoredResultAdsHidden = "Ads hidden by Telegram",
                    reportSponsoredResultPremiumRequired = "Telegram Premium is required for that option",
                    reportSponsoredResultFailed = "This sponsored post has expired",
                    error = "Telegram could not complete the report",
                }
                ui.printf(report and report.result and (verdicts[report.result] or "No report options")
                    or "Waiting for Telegram…", x + 12, 160, box_w - 24, "center", f.normal, colors.text)
            end
            ui.button_hint("{confirm} — Select   {back} — Close", x + 12, 354, f.small, colors.muted, box_w - 24)
        elseif prompt.info then
            ui.rect(x, 80, box_w, 312, colors.panel, 8)
            ui.printf("Sponsor information", x + 12, 94, box_w - 24, "center", f.normal, colors.text)
            love.graphics.setScissor(x + 12, 126, box_w - 24, 205)
            ui.printf(prompt.info, x + 12, 126 - (prompt.scroll or 0), box_w - 24, "left", f.small, colors.text)
            love.graphics.setScissor()
            ui.button_hint("D-pad — Scroll   {back} — Close", x + 12, 354, f.small, colors.muted, box_w - 24)
        end
    end
    local thread = self.tg.comments_thread
    if thread and thread.preview and not self.fullscreen_media then
        self:draw_text_preview(w, h, thread.preview)
    else
        self:draw_text_preview(w, h)
        self:draw_post_comments(w, h)
    end
    if thread then self:draw_fullscreen_media(w, h) end
    if self.context_menu and self.context_menu.comment_thread then self:draw_context_menu(f, colors, w, h) end
    if thread then self:draw_reaction_menu(f, colors, w, h) end
    self:draw_html_preview(w, h)
    self:draw_file_browser(w, h)
    self:draw_media_player(w, h)
end

function messenger_screen:draw_file_browser(w, h)
    local fb = self.file_browser
    if not fb then return end
    local f = self.fonts
    local colors = ui.colors
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local panel_w = math.min(w - 32, 760)
    local panel_h = math.min(h - 32, tp.note and 210 or 620)
    local panel_x = (w - panel_w) / 2
    local panel_y = (h - panel_h) / 2
    ui.rect(panel_x, panel_y, panel_w, panel_h, colors.panel, 8)
    ui.outline(panel_x, panel_y, panel_w, panel_h, colors.accent, 8)
    ui.text(ui.fit("Files: " .. (fb.path or ""), f.subtitle, panel_w - 24), panel_x + 12, panel_y + 8, f.subtitle, colors.text)
    local files = fb.files or {}
    if #files == 0 then
        ui.text("Folder is empty", panel_x + 12, panel_y + 40, f.small, colors.muted)
        ui.button_hint("{back} — Close", panel_x + 12, panel_y + panel_h - 18, f.tiny, colors.muted)
        return
    end
    local line_h = 24
    local visible = math.floor((panel_h - 60) / line_h)
    local focus = fb.focus or 1
    local scroll = fb.scroll or 0
    local max_scroll = math.max(0, #files - visible)
    if focus < scroll + 1 then scroll = focus - 1 end
    if focus > scroll + visible then scroll = focus - visible end
    scroll = math.max(0, math.min(max_scroll, scroll))
    fb.scroll = scroll
    love.graphics.setScissor(panel_x + 8, panel_y + 36, panel_w - 16, panel_h - 52)
    local y = panel_y + 36
    for i = scroll + 1, math.min(#files, scroll + visible) do
        local entry = files[i]
        local is_focus = (i == focus)
        if is_focus then
            ui.rect(panel_x + 8, y - 2, panel_w - 16, line_h, colors.accent, 4)
        end
        local icon = entry.is_dir and "📁" or "📄"
        local col = is_focus and colors.bg or colors.text
        ui.text(ui.fit(icon .. " " .. entry.name, f.tiny, panel_w - 24), panel_x + 12, y + 4, f.tiny, col)
        y = y + line_h
    end
    love.graphics.setScissor()
    ui.button_hint("↑↓ Navigate   {confirm} — Open   {back} — Close   L1/R1 — Page",
        panel_x + 12, panel_y + panel_h - 18, f.tiny, colors.muted, panel_w - 24)
end

function messenger_screen:draw_media_player(w, h)
    local np = self.tg and self.tg.now_playing
    if not np then return end

    if self.fullscreen_media then return end
    local kind = nil
    if self.tg and self.tg.media_file_for_message then
        kind = self.tg:media_file_for_message(np)
    end
    if kind == "video" or kind == "video_note" or kind == "animation" then return end
    local pos, dur, playing = self.tg:media_playback_state(np)
    local f = self.fonts
    local colors = ui.colors
    local bar_h = 40
    local bar_y = h - bar_h
    ui.rect(0, bar_y, w, bar_h, colors.panel, 0)
    ui.outline(0, bar_y, w, bar_h, colors.accent, 0)

    local btn_x, btn_y = 12, bar_y + 10
    love.graphics.setColor(1, 1, 1, 1)
    if playing then
        love.graphics.rectangle("fill", btn_x + 4, btn_y + 2, 4, 16)
        love.graphics.rectangle("fill", btn_x + 12, btn_y + 2, 4, 16)
    else
        love.graphics.polygon("fill", btn_x + 4, btn_y + 2, btn_x + 4, btn_y + 18, btn_x + 18, btn_y + 10)
    end

    local bar_x = btn_x + 28
    local bar_w = w - bar_x - 120
    local bar_y2 = bar_y + 16
    ui.rect(bar_x, bar_y2, bar_w, 6, colors.panel_alt, 3)
    if dur > 0 then
        local frac = math.min(1, pos / dur)
        ui.rect(bar_x, bar_y2, math.floor(bar_w * frac), 6, colors.accent, 3)
    end

    local function fmt(t)
        t = math.max(0, t or 0)
        return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
    end
    ui.text(fmt(pos) .. " / " .. fmt(dur), bar_x + bar_w + 8, bar_y + 12, f.tiny, colors.muted)
    ui.button_hint("{confirm} — Play / pause   ←/→ — Seek   {back} — Stop", 12, bar_y + 24, f.tiny, colors.muted)
end

function messenger_screen:draw_text_preview(w, h, preview)
    local tp = preview or self.text_preview
    if not tp or self.fullscreen_media then return end
    local f = self.fonts
    local colors = ui.colors
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local panel_w = math.min(w - 32, 760)
    local panel_h = math.min(h - 32, tp.note and 210 or 620)
    local panel_x = (w - panel_w) / 2
    local panel_y = (h - panel_h) / 2
    ui.rect(panel_x, panel_y, panel_w, panel_h, colors.panel, 8)
    ui.outline(panel_x, panel_y, panel_w, panel_h, colors.accent, 8)
    local title = tp.post_message and self.tg:post_title(tp.post_message) or tp.title or "Text file"
    if tp.path then
        title = tp.path:match("([^/]+)$") or title
    elseif tp.message and tp.message.content and tp.message.content.document then
        title = tp.message.content.document.file_name or title
    end
    ui.text(ui.fit(title, f.subtitle, panel_w - 24), panel_x + 12, panel_y + 8, f.subtitle, colors.text)
    if tp.loading then
        local prog = tp.download_progress or 0
        local pct = math.floor(prog * 100)
        ui.text("Downloading… " .. pct .. "%", panel_x + 12, panel_y + 40, f.small, colors.muted)
        local bar_x, bar_y = panel_x + 12, panel_y + 56
        local bar_w = panel_w - 24
        ui.rect(bar_x, bar_y, bar_w, 6, colors.panel_alt, 3)
        if prog > 0 then
            ui.rect(bar_x, bar_y, math.floor(bar_w * prog), 6, colors.accent, 3)
        end
        local plines = tp.preview_lines or {}
        if #plines > 0 then
            ui.text("Preview", panel_x + 12, panel_y + 72, f.tiny, colors.muted)
            local y = panel_y + 88
            local lh = f.tiny:getHeight() + 2
            for i = 1, math.min(10, #plines) do
                ui.text(ui.fit(plines[i] or "", f.tiny, panel_w - 24), panel_x + 12, y, f.tiny, colors.text)
                y = y + lh
            end
        end
        return
    end
    local font = tp.message_text and f.normal or f.tiny
    local width = panel_w - 32
    if tp.message_text and (tp.wrap_width ~= width or tp.wrap_font ~= font) then
        tp.lines = wrapped_lines(font, tp.message_text, width)
        tp.inline_links = helpers.link_ranges(tp.message_text, tp.entities)
        tp.inline_emoji = helpers.custom_emoji_ranges(tp.message_text, tp.entities, tp.emoji_sticker)
        tp.line_starts = (tp.inline_links or tp.inline_emoji) and helpers.line_starts(tp.message_text, tp.lines)
        tp.links_start = nil
        if tp.links and #tp.links > 0 then
            tp.lines[#tp.lines + 1] = ""
            tp.links_start = #tp.lines + 1
            for _, url in ipairs(tp.links) do
                for _, row in ipairs(wrapped_lines(font, url, width)) do tp.lines[#tp.lines + 1] = row end
            end
        end
        tp.wrap_width, tp.wrap_font = width, font
    end
    local lines = tp.lines or {}
    local line_h = font:getHeight() + (tp.message_text and 5 or 2)
    local note_height = tp.note and 32 or 0
    local visible = math.max(1, math.floor((panel_h - 72 - note_height) / line_h))
    local media = tp.photo or tp.comment_media
    local photo_rows = media and math.max(3, math.floor(math.min(184, panel_h * 0.43) / line_h)) or 0
    local quote_rows = 0
    local thread = tp.comment_thread
    local reply = thread and tp.reply or (not thread and self.tg:message_reply(tp.reply_message))
    tp.quote_available = not thread and reply and (tonumber(reply.message_id) or 0) > 0
    if tp.quote_selected == nil then tp.quote_selected = tp.quote_available end
    if reply then
        local parent, status
        if thread then parent, status = self.tg:comment_reply_parent(thread, reply)
        else parent, status = self.tg:resolve_message_reply(tp.reply_message, reply) end
        local name, quote = self.tg:reply_preview(reply, parent, status)
        if tp.quote ~= quote or tp.quote_width ~= width or tp.quote_font ~= font then
            tp.quote_lines = wrapped_lines(font, quote, width - 24)
            tp.quote, tp.quote_width, tp.quote_font = quote, width, font
        end
        tp.quote_name = name
        quote_rows = #tp.quote_lines + 2
    end
    tp.media_end = quote_rows + photo_rows
    local content_rows = #lines + tp.media_end
    local comment_rows = tp.comment and math.min(visible, math.max(2, math.ceil(36 / line_h))) or 0
    local count = content_rows + comment_rows
    tp.page_size, tp.max_scroll = visible, math.max(0, count - visible)
    tp.scroll = math.max(0, math.min(tp.max_scroll, tp.scroll or 0))
    local skip = math.floor(tp.scroll)
    local last = math.min(count, skip + visible)
    local top = panel_y + 40
    local left = panel_x + 12
    local bottom = top + visible * line_h
    tp.photo_hit, tp.quote_hit = nil, nil
    love.graphics.setScissor(left, top, width, visible * line_h)
    if quote_rows > skip then
        local quote_y = top - skip * line_h
        local quote_height = (quote_rows - 1) * line_h
        local selected = tp.quote_selected
        local ink = selected and ui.contrasting_text(colors.accent)
        ui.rect(left, quote_y, width, quote_height, selected and colors.accent or colors.panel_alt, 4)
        ui.rect(left, quote_y, 2, quote_height, colors.accent)
        ui.text(ui.fit("Reply to " .. tp.quote_name, f.small, width - 52), left + 12, quote_y + 3, f.small, ink or colors.accent)
        if tp.quote_available then
            ui.button_hint("{confirm}", left + width - 32, quote_y + 3, f.tiny, ink or colors.muted, nil, ink)
            local hit_h = math.min(bottom, quote_y + quote_height) - top
            if hit_h > 0 then tp.quote_hit = {x = left, y = top, w = width, h = hit_h} end
        end
        for index = math.max(1, skip), math.min(#tp.quote_lines, skip + visible - 1) do
            ui.text(tp.quote_lines[index], left + 12, quote_y + index * line_h, font, ink or colors.muted)
        end
    end
    if media and tp.media_end > skip and quote_rows < last then
        local photo_y = top + (quote_rows - skip) * line_h
        local photo_h = photo_rows * line_h - 10
        ui.retro_panel(left, photo_y, width, photo_h, colors.panel_alt, colors.accent_dark)
        local video = self.tg:video_kind(media.message)
        local image = not tp.comment_media and not video and self.tg:photo_image(media.message, media.index, nil, true)
        local hint_y = photo_y + photo_h - 23
        if tp.comment_media then
            self:draw_comment_media(media.message, media.kind, left + 8, photo_y + 4, width - 16, photo_h - 32, true)
        elseif video then
            local card_w = math.min(width - 16, math.floor((photo_h - 32) * 1.75))
            self:draw_video_card(media.message, left + (width - card_w) / 2, photo_y + 4, card_w, photo_h - 32, colors)
        elseif image then
            local scale = math.min((width - 24) / image:getWidth(), (photo_h - 30) / image:getHeight())
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, left + (width - image:getWidth() * scale) / 2, photo_y + 6, 0, scale, scale)
        else
            ui.printf("Loading photo…", left, photo_y + 22, width, "center", f.small, colors.muted)
        end
        local media_hint = video and "{confirm} — Play video" or "{confirm} — View photo"
        if tp.comment_media and media.kind ~= "photo" and not video then
            local audio = media.kind == "audio" or media.kind == "voice"
            media_hint = audio and "{confirm} — Play audio" or "{confirm} — Open media"
        end
        if tp.album then
            media_hint = string.format("←/→ — Media %d/%d   ", tp.album_index, #tp.album) .. media_hint
        end
        ui.button_hint(media_hint, left, hint_y, f.tiny, colors.accent, width)
        local hit_y = math.max(top, photo_y)
        tp.photo_hit = {x = left, y = hit_y, w = width, h = math.max(0, math.min(bottom, photo_y + photo_h) - hit_y)}
    end
    for i = math.max(1, skip + 1 - tp.media_end), math.min(#lines, last - tp.media_end) do
        local text = tp.message_text and lines[i] or ui.fit(lines[i], font, width)
        helpers.draw_link_line(text, tp.line_starts and tp.line_starts[i], tp.inline_links,
            left, top + (i + tp.media_end - skip - 1) * line_h, font,
            tp.links_start and i >= tp.links_start and colors.accent or colors.text, tp.inline_emoji, self.custom_emoji_image)
    end
    tp.comment_hit = nil
    if tp.comment and content_rows < skip + visible then
        local row_y = top + (content_rows - skip) * line_h
        local row_h = comment_rows * line_h - 4
        local selected = tp.comment_selected and tp.scroll >= tp.max_scroll
        local replies = helpers.comment_count(self.model:current_chat(), tp.comment) or 0
        local label = "Comments (" .. tostring(replies) .. ")"
        local fg = selected and colors.bg or colors.text
        ui.retro_panel(left, row_y + 2, width, row_h, selected and colors.accent or colors.panel_alt, colors.accent_dark)
        ui.pixel_chat(left + 10, row_y + math.max(5, (row_h - 12) / 2), 1, fg)
        ui.text(label, left + 34, row_y + 2 + (row_h - f.small:getHeight()) / 2, f.small, fg)
        ui.button_hint("{confirm}", left + width - 32, row_y + 2 + (row_h - f.tiny:getHeight()) / 2, f.tiny, fg)
        if selected then ui.focus_corners(left + 1, row_y + 3, width - 2, row_h - 2, colors.accent) end
        local hit_y = math.max(top, row_y + 2)
        local hit_h = math.min(bottom, row_y + 2 + row_h) - hit_y
        if hit_h > 0 then tp.comment_hit = {message = tp.comment, x = left, y = hit_y, w = width, h = hit_h} end
    end
    love.graphics.setScissor()

    local footer_y = panel_y + panel_h - 24
    if tp.note then
        ui.printf(tp.note, left, footer_y - 31, width, "left", f.tiny, alpha_color(colors.text, 0.55))
    end
    local hint
    if tp.quote_error then
        hint = tp.quote_error .. "   {back} — Close"
    elseif tp.quote_jump then
        hint = "Finding quoted message…   {back} — Cancel"
    elseif tp.quote_selected then
        hint = "{confirm} — Jump to quote   ↓ — Read message   {back} — Close"
    elseif tp.comment_selected then
        hint = "{confirm} — Open comments   ↑ — Read post   {back} — Close"
    elseif tp.scroll == 0 and tp.quote_available then
        hint = "↑ — Select quote   {back} — Close"
    elseif tp.comment and tp.scroll >= tp.max_scroll then
        hint = "↓ — Select comments   {back} — Close"
    elseif tp.max_scroll > 0 then
        hint = "D-pad — Scroll   L1/R1 — Page   {back} — Close"
    else
        hint = "{back} — Close"
    end
    ui.button_hint(hint, left, footer_y, f.tiny, colors.muted)
    if tp.max_scroll > 0 then
        local track_h = visible * line_h
        local thumb_h = math.max(12, track_h * visible / count)
        local bar_x = panel_x + panel_w - 10
        ui.rect(bar_x, top, 3, track_h, colors.panel_alt, 2)
        ui.rect(bar_x, top + (track_h - thumb_h) * tp.scroll / tp.max_scroll, 3, thumb_h, colors.accent, 2)
    end
end

function messenger_screen:html_run_font(run, base)
    local f = self.fonts
    if run.code then return f.mono
    elseif run.bold then return f.bold or base or f.normal
    elseif run.italic then return f.italic or base or f.normal
    else return base or f.normal end
end

function messenger_screen:layout_html_runs(runs, content_w, block_style)
    local f = self.fonts
    local base = f.normal
    if block_style == "h1" then base = f.title
    elseif block_style == "h2" then base = f.subtitle end
    local lines = {}
    local cur_line = {}
    local cur_x = 0
    for _, run in ipairs(runs or {}) do
        local font = self:html_run_font(run, base)
        local text = run.text or ""
        local pos = 1
        while pos <= #text do
            local remaining = content_w - cur_x
            local lo, hi = pos, #text
            local best = pos - 1
            while lo <= hi do
                local mid = math.floor((lo + hi) / 2)
                if font:getWidth(text:sub(pos, mid)) <= remaining then best = mid; lo = mid + 1
                else hi = mid - 1 end
            end
            if best < pos then
                lines[#lines + 1] = cur_line
                cur_line = {}
                cur_x = 0
                best = pos
            end
            local seg = text:sub(pos, best)
            cur_line[#cur_line + 1] = { text = seg, font = font, color = run.color }
            cur_x = cur_x + font:getWidth(seg)
            pos = best + 1
        end
    end
    if #cur_line > 0 then lines[#lines + 1] = cur_line end
    if #lines == 0 then lines[1] = {} end
    return lines
end

function messenger_screen:get_html_image(tp, b)
    tp.images = tp.images or {}
    if tp.images[b.src] ~= nil then return tp.images[b.src] or nil end
    local src = b.src
    local tmp
    if src:match("^data:") then
        local b64 = src:match("base64,(.+)")
        if not b64 then tp.images[src] = false; return nil end
        local ok, raw = pcall(love.data.decode, "base64", b64)
        if not ok or not raw then tp.images[src] = false; return nil end
        tmp = "/tmp/tg_html_" .. tostring(#src) .. "_" .. tostring(math.random(1, 1000000)) .. ".img"
        local fh = io.open(tmp, "wb")
        if not fh then tp.images[src] = false; return nil end
        local str = (raw.getString and raw:getString()) or tostring(raw)
        fh:write(str)
        fh:close()
    elseif src:match("^https?://") then
        tmp = "/tmp/tg_html_" .. tostring(#src) .. "_" .. tostring(math.random(1, 1000000)) .. ".img"
        local safe = src:gsub("'", "")
        os.execute("curl -s --max-time 12 --socks5-hostname 127.0.0.1:10808 '" .. safe .. "' -o " .. tmp .. " 2>/dev/null")
    else
        tp.images[src] = false
        return nil
    end
    local ok, img = pcall(love.graphics.newImage, tmp)
    if ok and img then
        tp.images[src] = img
        return img
    end
    tp.images[src] = false
    return nil
end

function messenger_screen:draw_html_preview(w, h)
    local tp = self.html_preview
    if not tp then return end
    local f = self.fonts
    local colors = ui.colors
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.rectangle("fill", 0, 0, w, h)
    local panel_w = math.min(w - 32, 900)
    local panel_h = math.min(h - 32, tp.note and 210 or 620)
    local panel_x = (w - panel_w) / 2
    local panel_y = (h - panel_h) / 2
    ui.rect(panel_x, panel_y, panel_w, panel_h, colors.panel, 8)
    ui.outline(panel_x, panel_y, panel_w, panel_h, colors.accent, 8)
    local title = "HTML file"
    if tp.path then
        title = tp.path:match("([^/]+)$") or title
    elseif tp.message and tp.message.content and tp.message.content.document then
        title = tp.message.content.document.file_name or title
    end
    ui.text(ui.fit(title, f.subtitle, panel_w - 24), panel_x + 12, panel_y + 8, f.subtitle, colors.text)
    if tp.loading then
        local prog = tp.download_progress or 0
        local pct = math.floor(prog * 100)
        ui.text("Downloading… " .. pct .. "%", panel_x + 12, panel_y + 40, f.small, colors.muted)
        local bar_x, bar_y = panel_x + 12, panel_y + 56
        local bar_w = panel_w - 24
        ui.rect(bar_x, bar_y, bar_w, 6, colors.panel_alt, 3)
        if prog > 0 then
            ui.rect(bar_x, bar_y, math.floor(bar_w * prog), 6, colors.accent, 3)
        end
        return
    end

    local blocks = tp.blocks or {}
    local line_h = f.normal:getHeight() + 6
    local block_gap = 1
    local content_x = panel_x + 20
    local content_w = panel_w - 40
    local view_h = panel_h - 52

    local measured = {}
    local total_lines = 0
    for _, b in ipairs(blocks) do
        if b.type == "image" then
            local img = self:get_html_image(tp, b)
            local lines_used
            if img then
                local scale = math.min(1, content_w / img:getWidth())
                lines_used = math.max(1, math.ceil((img:getHeight() * scale + 10) / line_h)) + block_gap
            else
                lines_used = 1 + block_gap
            end
            measured[#measured + 1] = { block = b, lines = lines_used, img = img }
            total_lines = total_lines + lines_used
        elseif b.type == "hr" then
            measured[#measured + 1] = { block = b, lines = 1 + block_gap }
            total_lines = total_lines + 1 + block_gap
        else
            local lines = self:layout_html_runs(b.runs, content_w, b.style)
            local used = math.max(1, #lines) + block_gap
            measured[#measured + 1] = { block = b, lines = used, layout = lines }
            total_lines = total_lines + used
        end
    end

    local visible = math.max(1, math.floor(view_h / line_h))
    local scroll = tp.scroll or 0
    local max_scroll = math.max(0, total_lines - visible)
    if scroll > max_scroll then scroll = max_scroll; tp.scroll = scroll end

    love.graphics.setScissor(panel_x + 8, panel_y + 36, panel_w - 16, panel_h - 52)
    local y = panel_y + 36 - scroll * line_h
    local line_no = 0
    for _, m in ipairs(measured) do
        local b = m.block
        local block_lines = m.lines
        local block_h = block_lines * line_h
        if line_no + block_lines >= scroll and line_no <= scroll + visible + 2 then
            if b.type == "image" then
                if m.img then
                    local scale = math.min(1, content_w / m.img:getWidth())
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(m.img, content_x, y, 0, scale, scale)
                else
                    ui.text("[image]", content_x, y, f.small, colors.muted)
                end
            elseif b.type == "hr" then
                love.graphics.setColor(colors.muted)
                love.graphics.line(content_x, y + line_h / 2, content_x + content_w, y + line_h / 2)
            else

                if b.bg then
                    ui.rect(content_x - 12, y - 6, content_w + 24, block_h - 2, { b.bg[1], b.bg[2], b.bg[3] }, 8)
                end

                local prefix = (b.style == "li") and "• " or ((b.style == "quote") and "│ " or "")
                local ly = y
                for li, line in ipairs(m.layout) do
                    local lx = content_x
                    if li == 1 and prefix ~= "" then
                        ui.text(prefix, lx, ly, f.normal, colors.accent)
                        lx = lx + f.normal:getWidth(prefix)
                    end
                    for _, seg in ipairs(line) do
                        local col = seg.color or b.color or ((b.style == "quote") and colors.muted or colors.text)
                        ui.text(seg.text, lx, ly, seg.font, col)
                        lx = lx + seg.font:getWidth(seg.text)
                    end
                    ly = ly + line_h
                end
            end
        end
        y = y + block_h
        line_no = line_no + block_lines
    end
    love.graphics.setScissor()
    ui.button_hint(string.format("%d/%d · ↑↓ Scroll · L1/R1 — Page · {back} — Close", scroll + 1, math.max(1, total_lines)),
        panel_x + 12, panel_y + panel_h - 18, f.tiny, colors.muted)
end

function messenger_screen:draw_picker_home(pack, w, h)
    local f, colors = self.fonts, ui.colors
    local width, height = math.min(w - 40, 480), 242
    local x, y = math.floor((w - width) / 2), math.floor((h - height) / 2)
    ui.rect(0, 0, w, h, {0, 0, 0, 0.86}, 0)
    ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
    ui.text("Stickers, GIFs and emoji", x + 18, y + 15, f.subtitle, colors.text)
    pack.cards = {}
    local card_w = math.floor((width - 68) / 3)
    for index, title in ipairs({"Stickers", "GIFs", "Emoji packs"}) do
        local left, top = x + 18 + (index - 1) * (card_w + 16), y + 60
        local selected = pack.focus == index
        local enabled = (index == 3 and pack.text) or (index ~= 3 and pack.media)
        pack.cards[index] = {x = left, y = top, w = card_w, h = 124}
        ui.retro_panel(left, top, card_w, 124, selected and colors.accent_dark or colors.panel_alt, colors.header)
        if selected then ui.focus_corners(left, top, card_w, 124, colors.accent) end
        local icon_x, icon_y = left + math.floor(card_w / 2) - 17, top + 20
        ui.rect(icon_x, icon_y, 34, 30, colors.bg, 4)
        ui.outline(icon_x, icon_y, 34, 30, colors.accent, 4)
        if index == 1 then
            ui.rect(icon_x + 8, icon_y + 8, 4, 5, colors.accent, 0)
            ui.rect(icon_x + 22, icon_y + 8, 4, 5, colors.accent, 0)
            ui.rect(icon_x + 10, icon_y + 19, 14, 3, colors.accent, 0)
        else
            ui.printf(index == 2 and "GIF" or "🙂", icon_x, icon_y + 8, 34, "center", f.tiny, colors.accent)
        end
        ui.printf(title, left, top + 60, card_w, "center", f.small, enabled and colors.text or colors.muted)
    end
    ui.button_hint("←/→ — Choose   {confirm} — Open   {back} — Close", x + 16, y + height - 34,
        f.tiny, colors.muted, width - 32)
end

function messenger_screen:draw_sticker_pack(w, h)
    local pack = self.tg.sticker_set_viewer
    if not pack then return end
    if pack.home then self:draw_picker_home(pack, w, h); return end
    local colors, f = ui.colors, self.fonts
    local layout = self:picker_layout(pack, w, h)
    local x, y, width, height = layout.x, layout.y, layout.w, layout.h
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, w, h)
    ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
    local title = pack.recent and "Stickers" or (pack.gifs and "GIFs" or pack.title)
    ui.text(ui.fit(title or "Sticker pack", f.subtitle, width - 36), x + 16, y + 9, f.subtitle, colors.text)
    local subtitle = pack.gifs and (pack.search_query and "Search results" or "Recent GIFs")
        or (pack.emoji_pack or pack.emoji_sets) and "Telegram custom emoji" or "Stickers"
    ui.text(subtitle, x + 16, y + 41, f.small, colors.accent)

    love.graphics.setScissor(layout.grid_x, layout.grid_y, layout.grid_w, layout.grid_h)
    for _, line in ipairs(layout.rows) do
        local top = layout.grid_y + line.y - pack.scroll
        if top + line.h > layout.grid_y and top < layout.grid_y + layout.grid_h then
            if line.label then
                ui.text(ui.fit(line.label, f.small, layout.grid_w - 8), layout.grid_x + 4, top + 2,
                    f.small, colors.muted)
            end
            for _, item in ipairs(line.entries) do
                local left = layout.grid_x + item.x
                local focused = item.index == pack.focus
                ui.retro_panel(left + 2, top + 2, item.w - 4, item.h - 4,
                    focused and colors.accent_dark or colors.panel_alt, colors.header)
                if focused then ui.focus_corners(left + 2, top + 2, item.w - 4, item.h - 4, colors.accent) end
                if item.label then
                    ui.text(ui.fit(item.label, f.small, item.w - 20), left + 10, top + 7, f.small, colors.text)
                else
                    local image = self:picker_item_image(item, false)
                    if image then
                        local scale = math.min((item.w - 10) / image:getWidth(), (item.h - 10) / image:getHeight())
                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.draw(image, left + (item.w - image:getWidth() * scale) / 2,
                            top + (item.h - image:getHeight() * scale) / 2, 0, scale, scale)
                    else
                        local fallback = item.kind == "gif" and "GIF" or (item.value.emoji or "")
                        if fallback == "" then fallback = "Sticker" end
                        ui.printf(fallback, left + 4, top + 25, item.w - 8, "center", f.tiny, colors.muted)
                    end
                end
            end
        end
    end
    love.graphics.setScissor()
    if layout.max_scroll > 0 then
        local bar_h = math.max(20, layout.grid_h * layout.grid_h / (layout.grid_h + layout.max_scroll))
        local track_x = x + width - 12
        ui.rect(track_x, layout.grid_y, 3, layout.grid_h, colors.header, 2)
        ui.rect(track_x, layout.grid_y + pack.scroll / layout.max_scroll * (layout.grid_h - bar_h),
            3, bar_h, colors.accent, 2)
    end
    local back = pack.parent and "Back" or "Close"
    local use = pack.emoji_pack and "Insert" or pack.emoji_sets and "Open pack" or "Open/Send"
    ui.button_hint("{confirm} — " .. use .. "   {search} — Preview   {options} — Choose type   {back} — " .. back,
        x + 14, y + height - 25, f.tiny, colors.muted, width - 28)

    if pack.search_input then
        ui.button_hint("{keyboard} — Search   {back} — Cancel", x + 220, y + 42, f.tiny,
            colors.muted, width - 236)
        self.keyboard:draw(pack.query or "", "Search GIFs…")
    end
    if pack.preview then
        ui.rect(0, 0, w, h, {0, 0, 0, 0.92}, 0)
        local image = self:picker_item_image(pack.preview, true)
        if image then
            local scale = math.min((w - 48) / image:getWidth(), (h - 70) / image:getHeight())
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, (w - image:getWidth() * scale) / 2,
                (h - 28 - image:getHeight() * scale) / 2, 0, scale, scale)
        else
            ui.printf("Loading preview…", 20, h / 2, w - 40, "center", f.small, colors.muted)
        end
        ui.button_hint((pack.emoji_pack and "{confirm} — Insert" or "{confirm} — Send") .. "   {back} — Back", 16, h - 27, f.tiny, colors.text, w - 32)
    end
end

function messenger_screen:draw_notifications(f, colors, w, h)
    local notices = self.tg.notifications or {}
    if #notices == 0 then return end
    local now = love.timer.getTime()
    local box_w, box_h = math.min(350, w - 32), 62
    local x = w - box_w - 16
    local bottom = h - INPUT_HEIGHT - 8
    for _, notice in ipairs(notices) do
        local age = now - (notice.created or now)
        if age >= 0 and age < 6 then
            local slide = age < 0.24 and math.floor((1 - age / 0.24) ^ 3 * 12) or 0
            local y = bottom - box_h + slide
            local title = self.tg:notification_title(notice)
            ui.retro_panel(x, y, box_w, box_h, colors.panel, colors.accent_dark)
            local avatar = notice.user_id and self.tg:user_photo_image(notice.user_id)
            if not avatar and notice.avatar_chat_id then
                self.tg:ensure_chat_photo(notice.avatar_chat_id)
                avatar = self.tg:chat_photo_image(notice.avatar_chat_id)
            end
            if avatar then
                draw_circle_image(avatar, x + 12, y + 11, 40)
            else
                ui.rect(x + 12, y + 11, 40, 40, colors.accent_dark, 6)
                ui.printf(ui.first_char(title), x + 12, y + 18, 40, "center", f.subtitle, colors.green)
            end
            ui.text(ui.fit(title, f.subtitle, box_w - 78), x + 64, y + 9, f.subtitle, colors.green)
            ui.text(ui.fit(notice.text or "", f.small, box_w - 78), x + 64, y + 34, f.small, colors.text)
            ui.rect(x + 4, y + box_h - 2, math.floor((box_w - 8) * (1 - age / 6)), 2, colors.green)
            bottom = bottom - box_h - 6
        end
    end
end

function messenger_screen:context_menu_bounds(w, h)
    local menu = self.context_menu
    local menu_w = math.min(240, w - 16)
    local row_h = math.max(24, self.fonts.small:getHeight() + 8)
    local visible = math.min(#menu.items, 12, math.max(1, math.floor((h - 52) / row_h)))
    local menu_h = visible * row_h + 34
    local progress = self.menu_anim or 1
    local offset = math.floor((1 - progress) ^ 2 * 12 - ui.focus_lift(progress * 0.24))
    local x = math.max(8, math.min(menu.x, w - menu_w - 8))
    local y = math.max(8, math.min(menu.y + offset, h - menu_h - 8))
    return x, y, menu_w, menu_h, row_h, visible
end

function messenger_screen:draw_context_menu(f, colors, w, h)
    if not self.context_menu then return end
    local items = self.context_menu.items
    local anim = self.menu_anim or 1
    local mx2, my2, menu_w, menu_h, row_h, visible_count = self:context_menu_bounds(w, h)

    self.context_menu.scroll = self.context_menu.scroll or 0
    local scroll = self.context_menu.scroll
    if scroll < 0 then scroll = 0 end
    if scroll > math.max(0, #items - visible_count) then scroll = math.max(0, #items - visible_count) end
    self.context_menu.scroll = scroll

    ui.retro_panel(mx2, my2, menu_w, menu_h, colors.panel, colors.accent_dark)

    for vi = 1, visible_count do
        local index = scroll + vi
        local item = items[index]
        if not item then break end
        local row_y = my2 + 6 + (vi - 1) * row_h
        if self.context_menu.index == index then
            ui.rect(mx2 + 4, row_y - 2, menu_w - 8, row_h,
                alpha_color(colors.accent_dark, anim), 4)
        end
        ui.text(ui.fit(item.label, f.small, menu_w - 28), mx2 + 12, row_y, f.small, alpha_color(colors.text, anim))
    end
    ui.button_hint("↑↓ Move   {confirm} Select   {back} Close", mx2 + 10, my2 + menu_h - 23,
        f.tiny or f.small, alpha_color(colors.muted, anim), menu_w - 20)
    if #items > visible_count then
        local bar_h = math.max(10, visible_count / #items * (menu_h - 34))
        local bar_y = my2 + 6 + (scroll / math.max(1, #items - visible_count)) * (menu_h - 34 - bar_h)
        ui.rect(mx2 + menu_w - 6, my2 + 6, 4, menu_h - 34, colors.panel_alt, 2)
        ui.rect(mx2 + menu_w - 6, bar_y, 4, bar_h, colors.accent, 2)
    end
end

function messenger_screen:draw_reaction_menu(f, colors, w, h)
    local menu = self.reaction_menu
    if not menu then return end
    local anim = self.menu_anim or 1
    local items = menu.items or {}
    local cols = REACTION_COLUMNS
    local total_rows = math.max(1, math.ceil(#items / cols))
    local cell = math.max(28, math.min(56, math.floor((w - 80) / cols)))
    local gap = 8
    local rows = math.min(total_rows, math.max(1, math.floor((h - 84) / (cell + gap))))
    local active_row = math.floor((menu.index - 1) / cols)
    local first_row = math.max(0, math.min(total_rows - rows, active_row - rows + 1))
    local menu_w = cols * cell + (cols - 1) * gap + 32
    local menu_h = rows * cell + (rows - 1) * gap + 76
    local mx = math.floor((w - menu_w) / 2)
    local my = math.floor((h - menu_h) / 2)

    love.graphics.setColor(0, 0, 0, 0.55 * anim)
    love.graphics.rectangle("fill", 0, 0, w, h)
    ui.rect(mx, my, menu_w, menu_h, alpha_color(colors.panel, 0.98 * anim), 10)
    ui.outline(mx, my, menu_w, menu_h, alpha_color(colors.accent_dark, anim), 10)
    ui.text("Reaction", mx + 16, my + 12, f.small, alpha_color(colors.muted, anim))

    if #items == 0 then
        ui.printf(menu.loading and "Loading reactions…" or menu.status or "", mx + 16, my + 54,
            menu_w - 32, "center", f.small, alpha_color(colors.text, anim))
    end
    menu.hits = {}
    for index = first_row * cols + 1, math.min(#items, (first_row + rows) * cols) do
        local item = items[index]
        local col = (index - 1) % cols
        local row = math.floor((index - 1) / cols) - first_row
        local x = mx + 16 + col * (cell + gap)
        local y = my + 44 + row * (cell + gap)
        if index == menu.index then
            ui.rect(x, y, cell, cell, alpha_color(colors.accent_dark, anim), 8)
        elseif item.chosen then
            ui.rect(x, y, cell, cell, alpha_color(colors.header, anim), 8)
            ui.outline(x, y, cell, cell, alpha_color(colors.accent, anim), 8)
        end
        local size = f.normal:getHeight()
        local emoji = item.custom_id and {{1, #item.emoji, item.custom_id}}
        helpers.draw_link_line(item.emoji, 1, nil, x + (cell - size) / 2,
            y + (cell - size) / 2, f.normal, alpha_color(colors.text, anim), emoji, self.custom_emoji_image)
        menu.hits[#menu.hits + 1] = {index = index, x = x, y = y, size = cell}
    end

    local hint = #items == 0 and "{back} — Close"
        or items[menu.index].chosen and "{confirm} — Remove   {back} — Cancel" or "{confirm} — React   {back} — Cancel"
    ui.button_hint(hint, mx + 16, my + menu_h - 24, f.tiny,
        alpha_color(colors.muted, anim))
    if total_rows > rows then
        local range = tostring(active_row + 1) .. "/" .. tostring(total_rows)
        ui.text(range, mx + menu_w - 16 - f.tiny:getWidth(range), my + 14, f.tiny, alpha_color(colors.muted, anim))
    end
end

function messenger_screen:fullscreen_image()
    local media = self.fullscreen_media
    if not media then return end
    if media.kind == "video" then return self.tg:video_image(media.message) end
    if media.kind == "video_note" then return self.tg:video_note_image(media.message) end
    if media.kind == "animation" then return self.tg:animation_image(media.message) end
    if media.kind == "sticker" then return self.tg:sticker_image(media.message) end
    return self.tg:photo_image(media.message, media.media_index or 1, nil, true)
end

function messenger_screen:fullscreen_geometry(image, w, h)
    local viewport_w, viewport_h = math.max(1, w - 48), math.max(1, h - 82)
    local width, height = image:getWidth(), image:getHeight()
    local scale = math.min(viewport_w / width, viewport_h / height) * (self.fullscreen_zoom or 1)
    return scale, math.max(0, (width * scale - viewport_w) / 2), math.max(0, (height * scale - viewport_h) / 2)
end

function messenger_screen:draw_audio_player(message, w, h)
    local f, colors = self.fonts, ui.colors
    local content = message.content or {}
    local media = content.audio or content.voice_note or {}
    local _, _, entry = self.tg:media_file_for_message(message)
    local position, duration, playing = self.tg:media_playback_state(message)
    if duration <= 0 then duration = tonumber(media.duration) or 0 end
    local status, status_color
    if not entry then
        if self.tg.finished_audio == message then
            position, status = duration, "Playback finished"
        else
            status = "Audio unavailable"
        end
    elseif entry.status == "error" then
        status, status_color = entry.audio_error or "Could not play this audio.", colors.red
    elseif entry.status == "downloading" then
        status = "Downloading audio… " .. self:format_bytes(entry.downloaded_bytes or 0)
    elseif entry.status == "decoding" then
        status = "Preparing audio…"
    elseif entry.paused then
        status = "Paused"
    else
        status = "Playing"
    end

    local width, height = math.min(w - 40, 476), 204
    local x, y = math.floor((w - width) / 2), math.floor((h - height) / 2)
    ui.rect(0, 0, w, h, {0, 0, 0, 0.88}, 0)
    ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
    local title = media.title
    if not title or title == "" then title = media.file_name end
    if not title or title == "" then title = content.audio and "Audio" or "Voice message" end
    ui.text(ui.fit(title, f.subtitle, width - 36), x + 18, y + 16, f.subtitle, colors.text)
    ui.text(ui.fit(media.performer or "", f.small, width - 36), x + 18, y + 42, f.small, colors.muted)
    ui.text(ui.fit(status, f.small, width - 36), x + 18, y + 72, f.small, status_color or colors.accent)

    local button_x, button_y = x + 18, y + 110
    ui.retro_panel(button_x, button_y, 32, 32, colors.accent_dark, colors.accent)
    love.graphics.setColor(colors.text)
    if playing then
        love.graphics.rectangle("fill", button_x + 10, button_y + 8, 4, 16)
        love.graphics.rectangle("fill", button_x + 18, button_y + 8, 4, 16)
    else
        love.graphics.polygon("fill", button_x + 11, button_y + 8, button_x + 11, button_y + 24, button_x + 24, button_y + 16)
    end
    local track_x, track_y, track_w = x + 64, y + 118, width - 84
    local progress = duration > 0 and math.max(0, math.min(1, position / duration)) or 0
    ui.rect(track_x, track_y, track_w, 6, colors.header, 3)
    ui.rect(track_x, track_y, progress * track_w, 6, colors.accent, 3)
    local timestamp = string.format("%d:%02d / %d:%02d", math.floor(position / 60), math.floor(position % 60),
        math.floor(duration / 60), math.floor(duration % 60))
    ui.text(timestamp, x + width - 20 - f.tiny:getWidth(timestamp), y + 136, f.tiny, colors.text)
    ui.button_hint("{confirm} — Play/Pause   L1/R1 — ±10 s   {back} — Close",
        x + 12, y + height - 30, f.tiny, colors.muted, width - 24)
    self.player_controls = {button = {x = button_x, y = button_y, w = 32, h = 32}}
end

function messenger_screen:draw_fullscreen_media(w, h)
    local fullscreen = self.fullscreen_media
    if not fullscreen then
        self.fullscreen_hint_time = nil
        return
    end
    if fullscreen.kind == "audio" then
        self:draw_audio_player(fullscreen.message, w, h)
        return
    end
    if not self.fullscreen_hint_time then self.fullscreen_hint_time = love.timer.getTime() end
    local animation = fullscreen.kind == "animation" and self.tg:ensure_animation(fullscreen.message, nil, true)
    if fullscreen.kind == "sticker" then self.tg:ensure_animated_sticker(fullscreen.message, true) end
    local image = self:fullscreen_image()
    local video_entry = fullscreen.kind == "video" and self.tg.active_video
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if self.fullscreen_zoom_target then
        local elapsed = love.timer.getTime() - (self.fullscreen_zoom_start or love.timer.getTime())
        local t = math.min(1, elapsed / 0.25)
        local zoom_start = self.fullscreen_zoom_start_val or self.fullscreen_zoom
        self.fullscreen_zoom = zoom_start + (self.fullscreen_zoom_target - zoom_start) * t
        if t >= 1 then
            self.fullscreen_zoom = self.fullscreen_zoom_target
            self.fullscreen_zoom_target = nil
            self.fullscreen_zoom_start = nil
            self.fullscreen_zoom_start_val = nil
        end
    end

    local video_panel_y = h - self.fonts.tiny:getHeight() - 74
    local video_height = math.max(1, video_panel_y - 18)
    if image then
        if fullscreen.video_note then
            local diameter = math.min(w - 48, video_height)
            draw_circle_image(image, (w - diameter) / 2, 8 + (video_height - diameter) / 2, diameter)
        elseif fullscreen.kind == "video" then
            local scale = math.min((w - 32) / image:getWidth(), video_height / image:getHeight())
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, (w - image:getWidth() * scale) / 2,
                8 + (video_height - image:getHeight() * scale) / 2, 0, scale, scale)
        else
            local scale, max_x, max_y = self:fullscreen_geometry(image, w, h)
            local pan_x = math.max(-max_x, math.min(max_x, self.fullscreen_pan_x or 0))
            local pan_y = math.max(-max_y, math.min(max_y, self.fullscreen_pan_y or 0))
            local draw_x = (w - image:getWidth() * scale) / 2 + pan_x
            local draw_y = (h - image:getHeight() * scale) / 2 + pan_y - 23
            love.graphics.setScissor(24, 18, math.max(1, w - 48), math.max(1, h - 82))
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, draw_x, draw_y, 0, scale, scale)
            love.graphics.setScissor()
        end
    else
        love.graphics.setColor(1, 1, 1, 1)
        local progress_text = "Loading media…"
        local fraction
        if fullscreen.kind == "video" then
            local entry = video_entry
            if not entry then progress_text = "Video is unavailable."
            elseif entry.status == "error" then progress_text = entry.decode_error
            elseif entry.status == "decoding" then
                progress_text = "Preparing video…"
                if entry.converted_seconds and entry.duration > 0 then
                    fraction = math.min(0.99, entry.converted_seconds / entry.duration)
                end
            else
                local bytes = entry.downloaded_bytes or 0
                progress_text = "Downloading video… " .. self:format_bytes(bytes)
                if (entry.total_bytes or 0) > 0 then fraction = math.min(0.99, bytes / entry.total_bytes) end
            end
        elseif fullscreen.kind == "animation" then
            progress_text = animation and animation.decode_error or "Loading GIF…"
        elseif fullscreen.kind == "photo" and fullscreen.message then
            local msg = fullscreen.message
            local key = self.tg:media_message_key(msg)
            local file_id = self.tg.photo_by_message and self.tg.photo_by_message[key]
            local entry = file_id and self.tg.photos and self.tg.photos[file_id]
            if entry and entry.download_progress then
                progress_text = string.format("Downloading… %d%%", math.floor((entry.download_progress or 0) * 100))
            end

            if self.tg.photo_hires_by_message and self.tg.photo_hires_by_message[key] then
                local hid = self.tg.photo_hires_by_message[key]
                local he = self.tg.photos and self.tg.photos[hid]
                if he and he.status == "downloading" and he.download_progress then
                    progress_text = string.format("Hi-Res: %d%%", math.floor((he.download_progress or 0) * 100))
                end
            end
        end
        if fraction then
            progress_text = progress_text .. string.format("  %d%%", math.floor(fraction * 100))
            local track_width = math.min(280, w - 48)
            local x = (w - track_width) / 2
            ui.rect(x, h / 2 + 32, track_width, 6, ui.colors.panel_alt, 3)
            ui.rect(x, h / 2 + 32, track_width * fraction, 6, ui.colors.accent, 3)
        end
        ui.printf(progress_text, 24, h / 2, w - 48, "center", self.fonts.normal, ui.colors.white)
    end

    if fullscreen.kind == "video" and image then
        local position, duration, playing = self.tg:media_playback_state(fullscreen.message)
        local panel_w = math.min(w - 40, 440)
        local panel_x = (w - panel_w) / 2
        local panel_y = video_panel_y
        ui.rect(panel_x, panel_y, panel_w, 55, {0.08, 0.09, 0.12, 0.96}, 8)

        local button_x, button_y = panel_x + 12, panel_y + 12
        love.graphics.setColor(1, 1, 1, 1)
        if playing then
            love.graphics.rectangle("fill", button_x + 7, button_y + 4, 4, 14)
            love.graphics.rectangle("fill", button_x + 15, button_y + 4, 4, 14)
        else
            love.graphics.polygon("fill", button_x + 7, button_y + 3, button_x + 7, button_y + 19, button_x + 21, button_y + 11)
        end

        local track_x = panel_x + 44
        local track_w = panel_w - 60
        local track_y = panel_y + 20
        local progress = duration > 0 and math.min(1, math.max(0, position / duration)) or 0
        ui.rect(track_x, track_y, track_w, 5, {0.35, 0.37, 0.4}, 2)
        if progress > 0 then ui.rect(track_x, track_y, track_w * progress, 5, ui.colors.accent, 2) end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("fill", track_x + track_w * progress, track_y + 2.5, 5)

        local time_label = string.format("%d:%02d / %d:%02d",
            math.floor(position / 60), math.floor(position % 60),
            math.floor(duration / 60), math.floor(duration % 60))
        ui.text(time_label, panel_x + panel_w - 16 - self.fonts.tiny:getWidth(time_label),
            panel_y + 35, self.fonts.tiny, ui.colors.text)
        self.player_controls = {
            button = {x = button_x, y = button_y, w = 28, h = 28},
            track = {x = track_x, y = track_y - 8, w = track_w, h = 30},
        }
    else
        self.player_controls = nil
    end
    if fullscreen.kind == "animation" then
        local retry = animation and animation.status == "error"
        if retry and image then
            ui.printf(animation.decode_error, 20, h - 61, w - 40, "center", self.fonts.small, ui.colors.text)
        end
        local hint = retry and "{confirm} — Retry   {back} — Close"
            or fullscreen.from_comments and "L1/R1 — Zoom −/+   D-pad — Pan   {back} — Comments"
            or "L1/R1 — Zoom −/+   D-pad — Pan   L2/R2 — Media   {back} — Close"
        ui.button_hint(hint, 20, h - 26, self.fonts.tiny, ui.colors.text, w - 40)
    elseif fullscreen.kind ~= "video" and fullscreen.kind ~= "video_note" then
        local detail = fullscreen.from_comments and "   {back} — Comments"
            or fullscreen.from_post and "   {back} — Post" or "   L2/R2 — Media   {back} — Back"
        local hint = string.format("L1/R1 — Zoom %d%%   D-pad — Pan", math.floor((self.fullscreen_zoom or 1) * 100)) .. detail
        ui.button_hint(hint, 24, h - 26, self.fonts.tiny, ui.colors.text, w - 48)
    elseif image then
        local detail = fullscreen.from_comments and "   {back} — Comments" or "   ←/→ — Media   {back} — Back"
        ui.button_hint("{confirm} — Play/Pause   L1/R1 — ±10 s" .. detail,
            16, h - self.fonts.tiny:getHeight() - 10, self.fonts.tiny, ui.colors.muted, w - 32)
    else
        local hint = fullscreen.kind == "video" and (not video_entry or video_entry.status == "error")
            and "{confirm} — Retry   {back} — Close" or "{back} — Cancel"
        ui.button_hint(hint, 24, h - 26, self.fonts.tiny, ui.colors.muted)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function messenger_screen:draw_edit_overlay(f, colors, w, h)
    if not self.edit_mode then return end
    local overlay_w = math.floor(w * 0.7)
    local lines = wrapped_lines(f.normal, self.edit_input, overlay_w - 64)
    local text_h = math.max(1, #lines) * f.normal:getHeight()
    local overlay_h = math.min(h - 32, math.max(150, text_h + 112))
    local overlay_x = math.floor((w - overlay_w) / 2)
    local overlay_y = math.floor((h - overlay_h) / 2)

    ui.rect(overlay_x, overlay_y, overlay_w, overlay_h, colors.panel, 8)
    ui.outline(overlay_x, overlay_y, overlay_w, overlay_h, colors.accent_dark, 8)

    ui.text("Edit message", overlay_x + 20, overlay_y + 18, f.small, colors.muted)
    local text_box_y = overlay_y + 44
    local text_box_h = overlay_h - 88
    ui.rect(overlay_x + 20, text_box_y, overlay_w - 40, text_box_h, colors.panel_alt, 6)
    if self.edit_input == "" then
        ui.text("Message…", overlay_x + 32, text_box_y + 10, f.normal, colors.muted)
    else
        draw_text_lines(lines, overlay_x + 32, text_box_y + 10, f.normal, colors.text)
    end
    ui.button_hint("{keyboard} — Keyboard   {confirm} — Save   {back} — Cancel",
        overlay_x + 20, overlay_y + overlay_h - 28, f.tiny, colors.muted)
end

function messenger_screen:context_menu_items(message)
    local items = {{label = "Search messages", action = "search"}}
    local selection = self.selected_messages or {}
    if message then
        items[#items + 1] = {label = selection[message.id] and "Deselect message" or "Select message",
            action = "select_message"}
    end
    if next(selection) then
        items[#items + 1] = {label = "Forward selected", action = "forward_selected"}
        items[#items + 1] = {label = "Clear selection", action = "clear_selection"}
    end
    if not message then return items end
    local chat = self.model:current_chat()
    local album = self.nav_albums and self.nav_albums[message.id]
    local comment = album and helpers.album_comment_target(chat, album)
        or (helpers.comment_count(chat, message) and message)
    if comment then
        items[#items + 1] = {label = "Comments (" .. tostring(helpers.comment_count(chat, comment)) .. ")",
            action = "open_comments", message = comment}
    end

    local content_type = message and message.content and message.content["@type"]
    if content_type == "messageAnimation" or content_type == "messageSticker" then
        items[#items + 1] = {label = "View", action = "view_fullscreen"}
    end
    local video_kind = self.tg:video_kind(message)
    local audio_kind = content_type == "messageAudio" or content_type == "messageVoiceNote"
    local video_post = self:is_video_post(message, chat)
    if (video_kind and not video_post) or audio_kind then
        items[#items + 1] = {label = "Download and play", action = "play_media"}
    end
    if content_type == "messageSticker" then
        items[#items + 1] = {label = "Sticker pack", action = "open_sticker_pack"}
        items[#items + 1] = {label = "Download sticker", action = "download_sticker"}
    end
    if content_type == "messageDocument" and not video_kind then
        items[#items + 1] = {label = "View text", action = "preview_text"}
        local doc = message.content and message.content.document
        local mime = doc and doc.mime_type or ""
        if mime == "text/html" or (doc and doc.file_name and doc.file_name:match("%.html?$")) then
            items[#items + 1] = {label = "View HTML", action = "preview_html"}
        end
    end

    if content_type == "messagePhoto" then
        local hi = self.tg and self.tg:choose_photo_hires(message)
        if hi and hi.photo and hi.photo.id then
            local entry = self.photos and self.photos[hi.photo.id]
            local is_downloaded = false
            if entry ~= nil and entry.source_path ~= nil and entry.source_path ~= "" then
                is_downloaded = true
            end
            if is_downloaded then
                items[#items + 1] = {label = "Already downloaded", action = nil}
            else
                items[#items + 1] = {label = "Download high resolution", action = "download_photo_hires"}
            end
        end
    end

    local msg_text = ""
    if message and message.content then
        if message.content.text and message.content.text.text then
            msg_text = message.content.text.text
        elseif message.content.caption and message.content.caption.text then
            msg_text = message.content.caption.text
        end
    end
    local has_reply = self.tg:message_reply(message) or (album and helpers.album_reply(self.tg, album))
    if msg_text ~= "" or comment or has_reply or video_post then
        local label = comment and "Examine post" or (has_reply and "Read reply"
            or (content_type == "messageText" and "Read message" or "Read post"))
        items[#items + 1] = {label = label, action = "read_message"}
    end
    local sticker_link = msg_text:match("https?://t%.me/addstickers/[^%s]+") or msg_text:match("https?://telegram%.me/addstickers/[^%s]+")
    if sticker_link then
        items[#items + 1] = {label = "Open sticker pack", action = "open_sticker_pack_from_link", link = sticker_link}
    end

    local sender = message.sender_id or {}
    local sender_user_id = sender["@type"] == "messageSenderUser" and sender.user_id or nil
    local sender_chat_id = sender["@type"] == "messageSenderChat" and sender.chat_id or nil
    if sender_user_id or sender_chat_id then
        items[#items + 1] = {label = sender_chat_id and "Sender chat info" or "Sender profile", action = "open_sender_profile",
            user_id = sender_user_id, chat_id = sender_chat_id}
    end
    local _, origin_user_id, origin_chat_id, source_chat_id = self.tg:forward_origin(message)
    if origin_chat_id then
        local origin = message.forward_info.origin or {}
        local label = origin["@type"] == "messageOriginChannel" and "Original channel info" or "Original chat info"
        items[#items + 1] = {label = label, action = "open_sender_profile", chat_id = origin_chat_id}
    elseif origin_user_id then
        items[#items + 1] = {label = "Original sender profile", action = "open_sender_profile", user_id = origin_user_id}
    end
    if source_chat_id and source_chat_id ~= origin_chat_id and source_chat_id ~= message.chat_id then
        items[#items + 1] = {label = "Forwarded via · Chat info", action = "open_sender_profile", chat_id = source_chat_id}
    end

    items[#items + 1] = {label = "Copy", action = "copy"}
    items[#items + 1] = {label = "Reaction", action = "react"}
    if not next(selection) then
        items[#items + 1] = {label = "Forward", action = "forward"}
    end
    if not sponsors.channel(chat) or self:outgoing(message) then
        items[#items + 1] = {label = message.is_pinned and "Unpin" or "Pin",
            action = message.is_pinned and "unpin" or "pin"}
    end

    if not self:outgoing(message) then
        local sender = message.sender_id
        if sender and sender["@type"] == "messageSenderUser" then
            items[#items + 1] = {label = "Message author", action = "write_to_author", sender_id = sender.user_id}
        end
    end
    if self:outgoing(message) and message.content and message.content["@type"] == "messageText" then
        items[#items + 1] = {label = "Edit", action = "edit"}
    end
    return items
end

function messenger_screen:chat_list_for(chat)
    if self.list_kind == "filter" then
        return {["@type"] = "chatListFolder", chat_folder_id = self.list_filter_id}
    end
    return chat.chat_list or {["@type"] = self.list_kind == "archive" and "chatListArchive" or "chatListMain"}
end

function messenger_screen:chat_context_menu_items(chat)
    local items = {{label = "Search chats", action = "search"}}
    if not chat or chat.navigation then return items end
    local muted = self.tg:is_chat_muted(chat)
    local list = self:chat_list_for(chat)
    local pinned = self.tg:chat_is_pinned(chat, list)
    local is_archived = chat and chat.chat_list and chat.chat_list["@type"] == "chatListArchive"
    items[#items + 1] = {label = pinned and "Unpin chat" or "Pin chat", action = "toggle_chat_pin", list = list}
    items[#items + 1] = {label = muted and "Unmute" or "Mute", action = muted and "unmute_chat" or "mute_chat"}
    items[#items + 1] = {label = is_archived and "Unarchive" or "Archive", action = is_archived and "unarchive_chat" or "archive_chat"}
    local kind = chat.type or {}
    local info = kind.is_channel and "Channel info" or "Chat info"
    if kind["@type"] == "chatTypeBasicGroup" or (kind["@type"] == "chatTypeSupergroup" and not kind.is_channel) then
        info = "Group info"
    elseif self.tg:private_chat_user_id(chat) then
        info = "Contact info"
    end
    items[#items + 1] = {label = info, action = "chat_info"}
    items[#items + 1] = {label = "Send file", action = "open_file_browser"}
    local chat_type = chat and chat.type and chat.type["@type"]
    if chat_type ~= "chatTypePrivate" and chat_type ~= "chatTypeSecret" then
        items[#items + 1] = {label = "Leave chat", action = "leave_chat"}
    end
    return items
end

function messenger_screen:is_loading()

    if not self.tg.current_chat_id and not self.tg.chats_loaded then
        return true
    end

    local chat = self.model:current_chat()
    if chat then
        local hs = self.tg.history_state and self.tg.history_state[chat.id]
        if hs and hs.loading then return true end
    end

    if self.list_kind == "filter" and self.list_filter_id
        and self.tg.filter_load_pending[self.list_filter_id] then
        return true
    end

    if self.list_kind == "archive" and self.tg.archive_load_pending then
        return true
    end

    if self.search_active and self.search_query ~= "" then
        if self.tg.dialog_search_query and self.tg.dialog_search_query[chat and chat.id or 0]
            and self.tg.dialog_search_query[chat and chat.id or 0] ~= self.search_query then
            return true
        end
    end
    return false
end

function messenger_screen:draw_loading_indicator(f, colors, w, left_width, right_width)
    if not self:is_loading() then return end
    local now = love.timer.getTime()

    local step = math.floor(now * 8) % 3
    for i = 0, 2 do
        ui.rect(math.floor(w / 2) - 9 + i * 7, math.floor(HEADER_HEIGHT / 2) + 7, 4, 4,
            i == step and colors.accent or colors.accent_dark)
    end
end

function messenger_screen:layout_chat_list(chats, bottom)
    local selected = math.max(1, math.min(#chats, self.model.selected))
    self.model.selected = selected
    local offset = math.min(self.model.list_offset or 0, selected - 1)
    if #chats > 0 then
        local height = 0
        for i = offset + 1, selected do height = height + row_height(chats[i]) end
        while offset < selected - 1 and height > bottom - HEADER_HEIGHT do
            offset = offset + 1
            height = height - row_height(chats[offset])
        end
    end
    self.model.list_offset = offset
    local rows, y = {}, HEADER_HEIGHT
    for i = offset + 1, #chats do
        if y >= bottom then break end
        local chat = chats[i]
        local height = row_height(chat)
        rows[#rows + 1] = {chat = chat, index = i, y = y, height = height, bottom = math.min(y + height, bottom)}
        y = y + height
    end
    return rows
end

function messenger_screen:chat_row_at(y)
    for _, row in ipairs(self.chat_list_rows or {}) do
        if y >= row.y and y < row.bottom then return row end
    end
end

function messenger_screen:draw_chat_list(left_width, h)
    local f = self.fonts
    local colors = ui.colors
    local bottom = h - 21
    local list_h = bottom - HEADER_HEIGHT
    ui.rect(0, HEADER_HEIGHT, left_width, list_h, colors.panel)
    ui.rect(left_width - 1, HEADER_HEIGHT, 1, list_h, colors.bg)

    local chat_list = self:get_visible_chat_list()
    self.chat_list_rows = self:layout_chat_list(chat_list, bottom)
    if self.list_kind == "archive" and #chat_list == 1 and chat_list[1].navigation == "main" then
        local status = self.tg.archive_load_error and "Could not load archive"
            or (self.tg.archive_loaded and "Archive is empty" or "Loading archive…")
        ui.printf(status, 16, HEADER_HEIGHT + NAV_ITEM_HEIGHT + 18, left_width - 32, "left", f.small, colors.muted)
    end
    if #chat_list == 0 then
        if self.search_active and self.search_query ~= "" then
            local search_error = self.tg.chat_search_error or self.tg.public_search_error
            local label = search_error
                and ("Search failed: " .. search_error)
                or "No chats found"
            if self.tg.chat_search_query ~= self.search_query
                or self.tg.public_search_query ~= self.search_query
                or self.tg.public_search_pending or self.tg.public_search_user_pending then
                label = "Searching chats, channels and people…"
            end
            ui.printf(label, 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small,
                search_error and colors.red or colors.muted)
            return
        elseif self.list_kind == "filter" then
            if self.tg.filter_load_pending[self.list_filter_id] then
                ui.printf("Loading folder…", 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.muted)
            else
                ui.printf("No chats in this folder", 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.muted)
            end
            return
        elseif self.list_kind == "archive" then
            if self.tg.archive_load_error then
                ui.printf("Could not load archive: " .. self.tg.archive_load_error, 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.red)
            elseif self.tg.archive_loaded then
                ui.printf("Archive is empty", 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.muted)
            else
                ui.printf("Loading archive…", 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.muted)
            end
            return
        elseif self.tg.chats_loaded then
            ui.printf("No chats", 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.muted)
        else
            ui.printf("Loading chats…", 16, HEADER_HEIGHT + 40, left_width - 32, "left", f.small, colors.muted)
        end
        return
    end

    local now = love.timer.getTime()
    local selected_row = chat_list[self.model.selected]
    local focus_key = selected_row and (selected_row.navigation or selected_row.id)
    if self.list_focus ~= focus_key then self.list_focus, self.list_focus_time = focus_key, now end
    local lift = ui.focus_lift(now - (self.list_focus_time or now))
    self.list_focus_lift = lift
    love.graphics.setScissor(0, HEADER_HEIGHT, left_width, list_h)
    for _, row in ipairs(self.chat_list_rows) do
        local chat, index, y, rh = row.chat, row.index, row.y, row.height
        local is_selected = not self.header_focus and index == self.model.selected
        local is_current = self.tg.current_chat_id == chat.id

        if chat.navigation then

            local bg = (is_selected or (chat.id and is_current)) and colors.panel_alt or colors.panel
            ui.retro_panel(5, y + 2, left_width - 10, rh - 4, bg, colors.accent_dark)
            if is_selected then ui.focus_corners(6, y + 3, left_width - 12, rh - 6, colors.accent, lift) end
            local color = is_selected and colors.accent or colors.muted
            draw_nav_icon(chat.navigation, 12, y + math.floor((rh - 13) / 2), color)
            local label = chat.title
            if chat.navigation == "saved" and not chat.id then
                label = label .. "  …"
            end
            ui.text(ui.fit(label, f.tiny, left_width - 42), 34, y + math.floor((rh - f.tiny:getHeight()) / 2), f.tiny, color)
        else
            chat_item.draw(self, chat, 0, y, left_width, ITEM_HEIGHT, f, colors, is_selected, is_current)

            if self.tg:chat_is_pinned(chat, self:chat_list_for(chat)) then
                ui.text("📌", left_width - 22, y + 4, f.tiny, colors.muted)
            end
        end
        if chat.sponsored_peer and y >= HEADER_HEIGHT and y + rh <= HEADER_HEIGHT + list_h
            and not self.sponsor_prompt and not self.fullscreen_media and not self.context_menu
            and not self.text_preview and not self.html_preview and not self.file_browser
            and not (self.keyboard and self.keyboard.visible)
            and (not love.window or not love.window.hasFocus or love.window.hasFocus()) then
            self.tg:view_search_sponsor(chat.sponsored_peer)
        end
    end
    love.graphics.setScissor()
end

local function measure_message(self, chat, message, max_bubble, padding, wrap_width)
    local f = self.fonts
    local font, small_height = f.normal, f.small:getHeight()
    local line_height = font:getHeight()
    local author_height = 0
    if not self:outgoing(message) then
        author_height = small_height + 2
    end
    if message.forward_info then author_height = author_height + small_height + 2 end
    if self.tg:message_reply(message) then author_height = author_height + helpers.reply_card_height(f.tiny) + 4 end
    local image, image_width, image_height = self:photo_geometry(message, max_bubble, padding, true)
    local is_sticker = false
    local is_animation = false
    local is_video = self.tg:video_kind(message) ~= nil
    local sticker_emoji = ""
    local animation_label = ""
    local content_type = message.content and message.content["@type"]
    local sticker_like_doc = false
    if content_type == "messageDocument" then
        local doc = message.content.document
        if doc then
            sticker_like_doc = (doc.file_name or ""):lower():match("%.tgs$") ~= nil
        end
    end
    if not image then
        local simg, sw, sh, semoji = self:sticker_geometry(message, max_bubble, padding, true)
        if simg then
            image, image_width, image_height, sticker_emoji = simg, sw, sh, semoji
            is_sticker = true
        end
    end
    if not is_sticker and sticker_like_doc then
        is_sticker = true
        local simg, sw, sh, semoji = self:sticker_geometry(message, max_bubble, padding, true)
        if simg then
            image, image_width, image_height, sticker_emoji = simg, sw, sh, semoji
        else
            local aimg, aw, ah, alabel = self:animation_geometry(message, max_bubble, padding, true)
            if aimg then
                image, image_width, image_height, animation_label = aimg, aw, ah, alabel
            end
        end
    end
    if not image then
        local aimg, aw, ah, alabel = self:animation_geometry(message, max_bubble, padding, true)
        if aimg then
            image, image_width, image_height, animation_label = aimg, aw, ah, alabel
            is_animation = true
        end
    end
    local audio_post = content_type == "messageAudio" or content_type == "messageVoiceNote"
    local formatted = (is_video or audio_post) and message.content.caption
    local caption = formatted and formatted.text or ""
    local post_text_height = caption ~= "" and (#wrapped_lines(font, caption, wrap_width) * line_height + 6) or 0
    local height
    if is_video then
        local _, card_h = self:video_card_size(max_bubble, padding)
        height = padding * 2 + author_height + card_h + post_text_height + small_height + 6
    elseif image then
        local caption = (is_sticker or is_animation) and "" or self:photo_caption(message)
        local caption_height = 0
        if caption ~= "" then
            local _, caption_lines = font:getWrap(caption, image_width)
            caption_height = #caption_lines * line_height + 4
        end
        height = padding * 2 + author_height + image_height + caption_height + small_height + 2
    elseif is_sticker and sticker_emoji ~= "" then
        local emoji_font = f.subtitle
        local _, emoji_lines = emoji_font:getWrap(sticker_emoji, wrap_width)
        local emoji_line_count = math.max(1, #emoji_lines)
        height = padding * 2 + author_height + emoji_line_count * emoji_font:getHeight() + small_height + 2
    elseif is_animation and animation_label ~= "" then
        local small_font = f.small
        local _, label_lines = small_font:getWrap(animation_label, wrap_width)
        local label_line_count = math.max(1, #label_lines)
        height = padding * 2 + author_height + label_line_count * small_font:getHeight() + small_height + 2
    elseif message.content and message.content["@type"] == "messageAudio" then
        height = padding * 2 + author_height + 54 + post_text_height + small_height + 2
    elseif message.content and message.content["@type"] == "messageVoiceNote" then
        height = padding * 2 + author_height + 38 + post_text_height + small_height + 2
    elseif message.content and message.content["@type"] == "messageDocument" then
        local text = self.tg:document_label(message)
        local lines = wrapped_lines(font, text, math.max(32, wrap_width - 28))
        height = padding * 2 + author_height + math.max(1, #lines) * line_height + small_height + 2
    else
        local text = self.tg:message_text(message)
        local lines = wrapped_lines(font, text, wrap_width)
        local line_count = math.max(1, #lines)
        height = padding * 2 + author_height + line_count * line_height + small_height + 2
    end
    local reactions = helpers.reaction_rows(helpers.reaction_summary(message), f.tiny, max_bubble - padding * 2)
    height = height + helpers.reaction_rows_height(reactions)
    if helpers.comment_count(chat, message) then height = height + 27 end
    local download_state = self.tg:media_download_state(message)
    if download_state and download_state.status == "downloading" then
        height = height + 30
    end
    return height
end

local variable_media = {
    messagePhoto = true, messageSticker = true, messageAnimation = true,
    messageVideo = true, messageVideoNote = true, messageAudio = true,
    messageVoiceNote = true, messageDocument = true,
}

local empty_history = {}

local function matches_history(snapshot, messages)
    if #snapshot ~= #messages then return false end
    for index, message in ipairs(messages) do
        local saved = snapshot[index]
        if saved.message ~= message or saved.content ~= message.content
            or saved.interaction ~= message.interaction_info then return false end
    end
    return true
end

local function sponsored_text(ad)
    local content = ad and ad.content
    local text = content and content["@type"] == "messageText" and content.text and content.text.text
    if type(text) == "string" and text ~= "" then return text end
end

local function sponsored_height(text, font, width)
    if not text then return 0 end
    local _, lines = font:getWrap(text, width - 32)
    return 78 + math.max(1, #lines) * font:getHeight()
end

function messenger_screen:conversation_layout(chat, messages, sponsored, bot, width, max_bubble, padding, wrap_width)
    local f = self.fonts
    local me = self.tg.me and self.tg.me.id
    local channel = chat.type and chat.type["@type"] == "chatTypeSupergroup" and chat.type.is_channel
    local year = os.date("%Y")
    local layout = self.cached_conversation_layout
    if not layout or layout.chat ~= chat.id or layout.messages ~= messages or layout.sponsors ~= sponsored
        or layout.bot ~= bot or layout.width ~= width or layout.me ~= me or layout.channel ~= channel
        or layout.year ~= year or layout.normal ~= f.normal or layout.small ~= f.small
        or layout.tiny ~= f.tiny or layout.subtitle ~= f.subtitle or not matches_history(layout.snapshot, messages) then
        local items = conversation_items(messages)
        if not bot then items = sponsors.spaced_items(items, sponsored) end
        layout = {chat = chat.id, messages = messages, sponsors = sponsored, bot = bot, width = width,
            channel = channel, me = me, year = year, normal = f.normal, small = f.small, tiny = f.tiny,
            subtitle = f.subtitle, items = items, heights = {}, snapshot = {}, variable = {}, fixed_height = 0}
        for index, message in ipairs(messages) do
            layout.snapshot[index] = {message = message, content = message.content, interaction = message.interaction_info}
        end
        layout.tail_ad = not bot and sponsored and sponsored.spacing == 0 and sponsored.messages[1]
        layout.tail_text = sponsored_text(layout.tail_ad)
        layout.tail_height = sponsored_height(layout.tail_text, f.small, width)
        local small_height = f.small:getHeight()
        for i, item in ipairs(items) do
            local height
            if item.channel_sponsor then
                height = sponsored_height(sponsored_text(item.channel_sponsor), f.small, width)
            elseif item.date_label then
                height = 28
            elseif item.action_label then
                height = 24
            elseif item.messages then
                local media = self:album_layout(item.messages, max_bubble, padding)
                local first = item.messages[1]
                local author_height = self:outgoing(first) and 0 or small_height + 2
                if first.forward_info then author_height = author_height + small_height + 2 end
                if helpers.album_reply(self.tg, item.messages) then
                    author_height = author_height + helpers.reply_card_height(f.tiny) + 4
                end
                height = padding * 2 + author_height + media.h + media.caption_h + small_height + 4
                if helpers.album_comment_target(chat, item.messages) then height = height + 27 end
                local reactions = helpers.reaction_rows(helpers.merge_message_reactions(item.messages),
                    f.tiny, max_bubble - padding * 2)
                height = height + helpers.reaction_rows_height(reactions)
                item.album_layout, item.reaction_rows = media, reactions
            else
                local content = item.message.content
                if content and variable_media[content["@type"]] then
                    layout.variable[#layout.variable + 1] = i
                else
                    height = measure_message(self, chat, item.message, max_bubble, padding, wrap_width)
                end
            end
            layout.heights[i] = height
            layout.fixed_height = layout.fixed_height + (height or 0) + (item.channel_sponsor and 0 or 6)
        end
        self.cached_conversation_layout = layout
    end
    local total = layout.fixed_height
    for _, index in ipairs(layout.variable) do
        local height = measure_message(self, chat, layout.items[index].message, max_bubble, padding, wrap_width)
        layout.heights[index] = height
        total = total + height
    end
    return layout, total
end

function messenger_screen:draw_conversation(chat, left_width, right_width, h)
    local f = self.fonts
    local colors = ui.colors
    local panel_x = left_width
    local panel_w = right_width

    ui.rect(panel_x, HEADER_HEIGHT, panel_w, CHAT_HEADER_HEIGHT, colors.header)
    local profile_user_id = self.tg:private_chat_user_id(chat)
    if profile_user_id then
        self.tg:ensure_user(profile_user_id)
        ui.text(self.tg:user_status_text(profile_user_id), panel_x + 20, HEADER_HEIGHT + 40, f.tiny, colors.muted)
    else
        local kind = chat.type or {}
        local typ = kind.is_channel and "Channel" or "Group"
        local status = typ .. (self.tg:is_chat_muted(chat) and " · Muted" or "")
        ui.text(status, panel_x + 20, HEADER_HEIGHT + 40, f.tiny, colors.muted)
    end
    local unread = tonumber(chat.unread_count) or 0
    local badge = unread > 99 and "99+" or tostring(unread)
    local badge_w = unread > 0 and f.tiny:getWidth(badge) + 18 or 0
    ui.text(ui.fit(chat.title or "Chat", f.subtitle, panel_w - 52 - badge_w), panel_x + 20, HEADER_HEIGHT + 12, f.subtitle, colors.text)
    if unread > 0 then
        local muted = self.tg:is_chat_muted(chat)
        local x = panel_x + panel_w - 28 - badge_w
        ui.retro_panel(x, HEADER_HEIGHT + 12, badge_w, f.tiny:getHeight() + 8,
            muted and colors.panel_alt or colors.accent, colors.accent_dark)
        ui.printf(badge, x, HEADER_HEIGHT + 16, badge_w, "center", f.tiny, muted and colors.muted or colors.bg)
    end

    local area_x = panel_x
    local area_y = HEADER_HEIGHT + CHAT_HEADER_HEIGHT
    local area_w = panel_w
    local area_h = h - area_y - (self:can_show_composer(chat) and INPUT_HEIGHT or FOOTER_HEIGHT)
    local now = love.timer.getTime()
    local history_state = self.tg.history_state and self.tg.history_state[chat.id]
    local finding_unread = history_state and history_state.unread_after ~= nil
    local live = self.tg.live_message_pings and self.tg.live_message_pings[chat.id]
    local live_age = live and now - live.created
    local ping_color = self.tg:is_chat_muted(chat) and ui.notification_gray or colors.green
    if live_age and live_age >= 0 and live_age < 4 then
        local ping_x = panel_x + panel_w - 20
        local ping_y = HEADER_HEIGHT + 16
        ui.rect(ping_x, ping_y - ui.focus_lift(live_age), 6, 6, ping_color)
    end
    local report_visible = not finding_unread and not (history_state and history_state.jump) and not self.search_active and not self.fullscreen_media
        and not self.context_menu and not self.edit_mode and not self.reaction_menu
        and not self.sponsor_prompt and not self.tg.sticker_set_viewer and not self.tg.comments_thread
        and not self.text_preview and not self.html_preview and not self.file_browser
        and not (self.keyboard and self.keyboard.visible)
        and (not love.window or not love.window.hasFocus or love.window.hasFocus())
    if not self.search_active then self.tg:request_channel_sponsors(chat, now) end
    local sponsored = not self.search_active and self.tg:get_channel_sponsors(chat.id, now)
    local bot = sponsors.bot(chat, self.tg.users)
    local bot_ad = bot and sponsored and sponsored.messages[1]
    local bot_text = bot_ad and bot_ad.content and bot_ad.content["@type"] == "messageText"
        and bot_ad.content.text and bot_ad.content.text.text
    self.sponsor_bot = nil
    if type(bot_text) == "string" and bot_text ~= "" then
        local _, lines = f.small:getWrap(bot_text, area_w - 24)
        local text_height = #lines * f.small:getHeight()
        local bar_height = math.min(112, 57 + text_height, area_h - 32)
        if bar_height > 57 then
            self.sponsor_bot = bot_ad
            ui.rect(area_x, area_y, area_w, bar_height, colors.panel_alt)
            local label = bot_ad.is_recommended and "Recommended" or "Ad"
            ui.text(ui.fit(label .. " · " .. (bot_ad.title or ""), f.small, area_w - 24),
                area_x + 12, area_y + 7, f.small, colors.accent)
            love.graphics.setScissor(area_x + 12, area_y + 25, area_w - 24, bar_height - 53)
            ui.printf(bot_text, area_x + 12, area_y + 25, area_w - 24, "left", f.small, colors.text)
            love.graphics.setScissor()
            local hint = bot_ad.button_text or "Open"
            if self.sponsor_focus then
                hint = "{confirm} — " .. hint
                if bot_ad.can_be_reported then hint = hint .. "   {search} — Report" end
                if (bot_ad.additional_info or "") ~= "" or (bot_ad.sponsor and bot_ad.sponsor.info or "") ~= "" then
                    hint = hint .. "   {options} — Info"
                end
                ui.outline(area_x + 2, area_y + 2, area_w - 4, bar_height - 4, colors.accent, 5)
            end
            ui.button_hint(hint, area_x + 12, area_y + bar_height - 19, f.tiny, colors.muted, area_w - 24)
            if report_visible and text_height <= bar_height - 53 then
                self.tg:view_channel_sponsor(chat.id, bot_ad.message_id, now)
            end
            area_y, area_h = area_y + bar_height, area_h - bar_height
        end
    end

    local keep_position_id = history_state and history_state.keep_position_id
    local previous_position = keep_position_id and self.nav_pos[keep_position_id]
    local previous_scroll = self.smooth_scroll or self.model.scroll
    self.conv_area_x, self.conv_area_y = area_x, area_y
    self.conv_area_w, self.conv_area_h = area_w, area_h
    self.nav_messages = {}
    self.nav_pos = {}

    ui.rect(area_x, area_y, area_w, area_h, colors.bg)

    local messages = self.tg:get_messages(chat.id)
    local search_loading = false
    if self.search_active and self.search_query ~= "" then
        local search_results = self.tg.dialog_search_results and self.tg.dialog_search_results[chat.id]
        search_loading = search_results == false or self.tg.dialog_search_query[chat.id] ~= self.search_query
        messages = type(search_results) == "table" and search_results or {}
    end
    if finding_unread and not self.search_active then messages = empty_history end
    if #messages == 0 then messages = empty_history end
    if #messages == 0 then
        local empty_label = self.search_active and self.search_query ~= "" and "No matching messages" or "No messages"
        if self.search_active and self.tg.dialog_search_error then
            empty_label = "Search failed: " .. self.tg.dialog_search_error
        elseif search_loading then
            empty_label = "Searching messages…"
        elseif history_state and history_state.error then
            empty_label = history_state.error
        elseif history_state and history_state.loading then
            empty_label = "Loading messages…"
        end
        ui.printf(empty_label, area_x, area_y + area_h / 2 - 20, area_w, "center", f.small, colors.muted)
    end

    local font = f.normal
    local small = f.small
    local padding = 10

    local max_bubble = math.floor(area_w * 0.85)

    local wrap_width = math.min(max_bubble - padding * 2, 280)
    local line_height = font:getHeight()
    local small_height = small:getHeight()
    local layout, total = self:conversation_layout(chat, messages, sponsored, bot, area_w, max_bubble, padding, wrap_width)
    local items, heights = layout.items, layout.heights
    local ad, text, tail = layout.tail_ad, layout.tail_text, layout.tail_height
    if tail ~= (self.sponsor_tail or 0) then
        local difference = tail - (self.sponsor_tail or 0)
        self.model.scroll = math.max(0, (self.model.scroll or 0) + difference)
        self.smooth_scroll = math.max(0, (self.smooth_scroll or 0) + difference)
        self.sponsor_tail = tail
    end
    self.sponsor_ad = tail > 0 and ad or nil
    local inline = sponsored and self.sponsor_inline and sponsored.by_id[self.sponsor_inline]
    if self.sponsor_inline and not inline then self.sponsor_inline, self.sponsor_focus = nil, nil end
    if not self.sponsor_ad and not self.sponsor_bot and not inline then self.sponsor_focus = nil end
    self.sponsor_rows = {}
    self.model.max_scroll = math.max(tail, total + tail - area_h)
    if self.model.scroll > self.model.max_scroll then self.model.scroll = self.model.max_scroll end
    if self.model.scroll < 0 then self.model.scroll = 0 end
    local focus_id = history_state and history_state.initial_focus_id
    local anchor_id = focus_id or (previous_position and keep_position_id)
    if anchor_id and not self.search_active then
        local height_from_bottom = tail
        for i = #items, 1, -1 do
            local item = items[i]
            height_from_bottom = height_from_bottom + (heights[i] or 0) + (item.channel_sponsor and 0 or 6)
            local messages = item.messages or (item.message and {item.message}) or {}
            local matched
            for _, message in ipairs(messages) do
                if message.id == anchor_id then
                    matched = true
                    break
                end
            end
            if matched then
                local new_scroll = height_from_bottom - area_h
                if focus_id then
                    self.message_cursor_id = messages[1].id
                    self.display_cursor_id = self.message_cursor_id
                    history_state.initial_focus_id = nil
                else
                    new_scroll = new_scroll + previous_position.y - area_y
                    self.model.scroll = self.model.scroll + new_scroll - previous_scroll
                end
                if focus_id then self.model.scroll = new_scroll end
                self.model.scroll = math.max(0, math.min(self.model.max_scroll, self.model.scroll))
                self.smooth_scroll = math.max(0, math.min(self.model.max_scroll, new_scroll))
                break
            end
        end
    end
    if history_state then history_state.keep_position_id = nil end

    love.graphics.setScissor(area_x, area_y, area_w, area_h)
    local y = area_y + area_h + (self.smooth_scroll or self.model.scroll)
    local function draw_sponsor(card, body, top, height, focused)
        local bottom = top + height
        ui.rect(area_x + 4, top + 2, area_w - 8, height - 6, colors.panel_alt, 8)
        ui.text(card.is_recommended and "Recommended" or "Sponsored",
            area_x + 16, top + 8, f.tiny, colors.accent)
        ui.text(ui.fit(card.title or "", f.small, area_w - 32),
            area_x + 16, top + 27, f.small, colors.text)
        ui.printf(body, area_x + 16, top + 46, area_w - 32, "left", f.small, colors.text)
        local action = card.button_text or "Open"
        if focused then
            action = "{confirm} — " .. action
            if card.can_be_reported then action = action .. "   {search} — Report" end
            if (card.additional_info or "") ~= "" or (card.sponsor and card.sponsor.info or "") ~= "" then
                action = action .. "   {options} — Info"
            end
        end
        ui.button_hint(action, area_x + 16, bottom - 26, f.small, colors.accent, area_w - 32)
        if focused then
            ui.outline(area_x + 4, top + 2, area_w - 8, height - 6, colors.accent, 8)
        end
        if report_visible and top + 46 >= area_y and bottom - 32 <= area_y + area_h then
            self.tg:view_channel_sponsor(chat.id, card.message_id, now)
        end
    end
    if tail > 0 then
        y = y - tail
        draw_sponsor(ad, text, y, tail, self.sponsor_focus and not self.sponsor_inline)
    end
    local viewed = {}
    self.message_hits = {}
    self.media_hits = {}
    self.profile_hits = {}
    self.hashtag_hits = {}
    self.comment_hits, self.nav_albums = {}, {}
    for i = #items, 1, -1 do
        local item = items[i]
        if item.channel_sponsor then
            local height = heights[i]
            if height > 0 then
                y = y - height
                local card = item.channel_sponsor
                self.sponsor_rows[#self.sponsor_rows + 1] = {id = card.message_id, y = y, h = height}
                if y <= area_y + area_h and y + height >= area_y then
                    draw_sponsor(card, sponsored_text(card), y, height, self.sponsor_inline == card.message_id)
                end
            end
        elseif item.date_label then
            local date_height = 28
            y = y - date_height - 6
            if y + date_height >= area_y and y <= area_y + area_h then
                local label_w = f.tiny:getWidth(item.date_label) + 22
                local label_x = area_x + (area_w - label_w) / 2
                ui.rect(label_x, y + 3, label_w, 22, colors.header, 10)
                ui.printf(item.date_label, label_x, y + 6, label_w, "center", f.tiny, colors.muted)
            end
            if y < area_y - 100 then break end
        elseif item.action_label then
            local action_height = 24
            y = y - action_height - 6
            if y + action_height >= area_y and y <= area_y + area_h then
                local label_w = math.min(area_w - 20, f.tiny:getWidth(item.action_label) + 22)
                local label_x = area_x + (area_w - label_w) / 2
                ui.rect(label_x, y + 2, label_w, 20, colors.header, 10)
                ui.printf(item.action_label, label_x, y + 5, label_w, "center", f.tiny, colors.muted)
            end
            if y < area_y - 100 then break end
        else
        local height = heights[i] or 60
        y = y - height - 6
        local nav_msg = item.messages and item.messages[1] or item.message
        if nav_msg then
            self.nav_messages[#self.nav_messages + 1] = nav_msg
            self.nav_pos[nav_msg.id] = {y = y, h = height}
            for _, member in ipairs(item.messages or {}) do self.nav_albums[member.id] = item.messages end
        end
        if y + height >= area_y and y <= area_y + area_h then
            if report_visible and math.min(y + height, area_y + area_h) - math.max(y, area_y)
                >= math.min(height, area_h) * 0.5 then
                for _, message in ipairs(item.messages or {item.message}) do
                    viewed[#viewed + 1] = message
                end
            end
            for _, message in ipairs(item.messages or {item.message}) do
                if media_settings.get("autoplay_images") then self.tg:ensure_photo(message) end
            end
            local focus_x, focus_w = area_x + 2, area_w - 4
            if item.messages then
                focus_x, focus_w = self:draw_album(item.messages, area_x, y, area_w, height, max_bubble, padding, small_height, colors, item)
            else
                local hit = { message = item.message, x = area_x, y = y, w = area_w, h = height }
                table.insert(self.message_hits, hit)
                self:draw_message(item.message, area_x, y, area_w, height, max_bubble, padding, wrap_width, small_height, line_height, colors, hit)
                focus_x, focus_w = (hit.bubble_x or focus_x) - 2, (hit.bubble_w or focus_w) + 4
            end
            if live_age and live_age >= 0 and live_age < 2.4 and nav_msg and live.id == nav_msg.id then
                ui.rect(area_x + 5, y + 5, 3, math.min(26, height - 10), ping_color)
            end
            if not self.header_focus and not self.composer_focus and nav_msg and self.display_cursor_id == nav_msg.id then
                if self.message_focus ~= nav_msg.id then
                    self.message_focus, self.message_focus_time = nav_msg.id, now
                end
                ui.focus_corners(focus_x, y - 1, focus_w, height + 2, colors.accent,
                    ui.focus_lift(now - self.message_focus_time))
            end
        end
        if y < area_y - 100 then break end
        end
    end
    love.graphics.setScissor()
    if #viewed > 0 then
        self.tg:mark_chat_viewed(chat.id, viewed)
        if history_state then
            local position = self.nav_pos[self.message_cursor_id]
            local cursor_visible = position and position.y < area_y + area_h and position.y + position.h > area_y
            self.tg:remember_reading_position(chat.id, cursor_visible and self.message_cursor_id or viewed[#viewed].id)
        end
    end
    local ordered = {}
    for index = #self.nav_messages, 1, -1 do
        ordered[#ordered + 1] = self.nav_messages[index]
    end
    self.nav_messages = ordered
    if self.message_cursor_id and not self.nav_pos[self.message_cursor_id] then
        self.message_cursor_id = nil
        self.display_cursor_id = nil
    end
    if not self.message_cursor_id and #ordered > 0 then
        self.message_cursor_id = ordered[#ordered].id
        self.display_cursor_id = ordered[#ordered].id
    end

    if math.abs((self.model.scroll or 0) - (self.smooth_scroll or 0)) < 1 then
        self.display_cursor_id = self.message_cursor_id
    end

    self.load_more_button = nil
    if history_state and not (self.search_active and self.search_query ~= "")
        and (history_state.loading or history_state.has_more or history_state.error)
        and self.model.scroll >= self.model.max_scroll - 12 then
        local button_w, button_h = 146, 28
        local button_x, button_y = area_x + (area_w - button_w) / 2, area_y + 6
        local label = history_state.loading and "Loading…"
            or history_state.error and "Retry loading"
            or "L1 — Older messages"
        ui.rect(button_x, button_y, button_w, button_h, colors.header, 8)
        ui.printf(label, button_x + 4, button_y + 6, button_w - 8, "center", f.tiny,
            history_state.error and colors.red or colors.text)
        self.load_more_button = {x = button_x, y = button_y, w = button_w, h = button_h}
    end

    if self:can_show_composer(chat) then
        self:draw_input(panel_x, panel_w, h)
    else
        self.composer_bounds = nil
    end
    if not self.search_active and not self.forward_mode and not self.composer_focus
        and (self.model.scroll > 26 or self:cursor_index() < #ordered - 1 or (unread > 0 and #ordered > 0)
            or history_state and (history_state.has_newer or history_state.jump or history_state.jump_error)) then
        self:draw_read_jump(area_x + area_w - 34, area_y + area_h - 46, history_state, now, unread)
    end
end

function messenger_screen:draw_read_jump(x, y, state, now, unread)
    local colors, font = ui.colors, self.fonts.tiny
    local w, h = 30, 42
    self.read_jump_hit = {x = x, y = y, w = w, h = h}
    local loading = state and state.jump
    local failed = state and state.jump_error
    local has_unread = unread > 0
    local ink = has_unread and colors.accent or colors.muted
    ui.retro_panel(x, y, w, h, colors.header, failed and colors.red or (has_unread and colors.accent_dark or colors.panel_alt))
    local badge_top = y
    if has_unread then
        local label = tostring(unread)
        local badge_w = math.max(21, font:getWidth(label) + 10)
        local badge_h = font:getHeight() + 5
        local badge_x = x + math.min(w - badge_w, math.floor((w - badge_w) / 2))
        badge_top = y - badge_h - 5
        ui.outline(badge_x - 2, badge_top - 2, badge_w + 4, badge_h + 4, alpha_color(ink, 0.22), 5)
        ui.outline(badge_x - 1, badge_top - 1, badge_w + 2, badge_h + 2, alpha_color(ink, 0.5), 4)
        ui.rect(badge_x, badge_top, badge_w, badge_h, ink, 3)
        ui.printf(label, badge_x, badge_top + 2, badge_w, "center", font, ui.contrasting_text(ink))
    end
    if self.latest_arrow == nil then
        local ok, atlas = pcall(love.graphics.newImage, "icons/app/bouncyarrow.png")
        self.latest_arrow = ok and atlas or false
        if self.latest_arrow then
            atlas:setFilter("nearest", "nearest")
            self.latest_frames = {}
            for index = 0, 13 do
                self.latest_frames[index + 1] = love.graphics.newQuad((index % 7) * 32,
                    math.floor(index / 7) * 32, 32, 32, atlas:getDimensions())
            end
        end
    end
    if loading then
        ui.printf("…", x, y + 6, w, "center", self.fonts.small, ink)
    elseif self.latest_arrow then
        local time = now % 0.97
        local frame = media_settings.get("ui_motion") and (time < 0.25 and 1 or math.min(7, 2 + math.floor((time - 0.25) / 0.12))) or 1
        love.graphics.setColor(1, 1, 1, 1)
        local variant = has_unread and frame or frame + 7
        love.graphics.draw(self.latest_arrow, self.latest_frames[variant], x + 4, y + 2, 0, 22 / 32, 22 / 32)
    else
        ui.printf("↓", x, y + 5, w, "center", self.fonts.normal, ink)
    end
    ui.printf("R2", x, y + 25, w, "center", font, failed and colors.red or (has_unread and colors.text or colors.muted))
    if failed then
        local width = font:getWidth(failed) + 14
        ui.retro_panel(x + w - width, badge_top - 25, width, 22, colors.header, colors.red)
        ui.text(failed, x + w - width + 7, badge_top - 20, font, colors.text)
    end
end

function messenger_screen:draw_message(message, area_x, y, area_w, height, max_bubble, padding, wrap_width, small_height, line_height, colors, hit)
    local function sticker_like_document(message)
        local content = message and message.content
        if not content or content["@type"] ~= "messageDocument" then return false end
        local doc = content.document
        if not doc then return false end
        return (doc.file_name or ""):lower():match("%.tgs$") ~= nil
    end
    local f = self.fonts
    local content = message and message.content
    local content_type = content and content["@type"]
    local is_sticker_like_doc = sticker_like_document(message)
    if content_type == "messageSticker" or is_sticker_like_doc then
        self.tg:ensure_sticker(message, nil, true)
        self.tg:ensure_animated_sticker(message)
    end
    if content_type == "messageAnimation" then
        self.tg:ensure_animation(message)
    end
    local outgoing = self:outgoing(message)
    local text = self.tg:message_text(message)
    local lines = {}
    local entities = (message and message.content and message.content.text and message.content.text.entities) or {}
    local sender_name = not outgoing and self.tg:sender_name(message) or nil
    local forwarded = self.tg:forward_origin(message)
    local reply = self.tg:message_reply(message)
    local download_state = self.tg:media_download_state(message)
    local is_downloading = download_state and download_state.status == "downloading"
    local image, image_width, image_height = self:photo_geometry(message, max_bubble, padding)
    local is_sticker = false
    local is_animation = false
    local is_video = self.tg:video_kind(message) ~= nil
    local animation_label = ""
    local sticker_emoji = ""
    local is_selected = self.selected_messages[message.id] ~= nil
    local reactions = helpers.reaction_rows(
        helpers.reaction_summary(message), f.tiny, max_bubble - padding * 2
    )
    local reactions_height = helpers.reaction_rows_height(reactions)
    local comment_count = helpers.comment_count(self.model:current_chat(), message)
    local body_height = height - (comment_count and 27 or 0)
    local is_document = (content_type == "messageDocument" or content_type == "messageAudio")
        and not is_sticker_like_doc and not self.tg:video_kind(message)
    local display_text = is_document and self.tg:document_label(message) or text
    if not image then
        local simg, sw, sh, semoji = self:sticker_geometry(message, max_bubble, padding)
        if simg then
            image, image_width, image_height, sticker_emoji = simg, sw, sh, semoji
            is_sticker = true
        end
    end
    if not is_sticker and is_sticker_like_doc then
        is_sticker = true
        local simg, sw, sh, semoji = self:sticker_geometry(message, max_bubble, padding)
        if simg then
            image, image_width, image_height, sticker_emoji = simg, sw, sh, semoji
        else
            local aimg, aw, ah, alabel = self:animation_geometry(message, max_bubble, padding)
            if aimg then
                image, image_width, image_height, animation_label = aimg, aw, ah, alabel
            end
        end
    end
    if content_type == "messageAnimation" then
        is_animation = true
        local aimg, aw, ah, alabel = self:animation_geometry(message, max_bubble, padding)
        if aimg then
            image, image_width, image_height, animation_label = aimg, aw, ah, alabel
        else
            animation_label = "GIF · open to enlarge"
        end
    end
    local formatted_caption = message.content and message.content.caption
    local is_audio = content_type == "messageAudio" or content_type == "messageVoiceNote"
    local post_media = is_video or is_audio
    local caption = post_media and (formatted_caption and formatted_caption.text or "")
        or ((is_sticker or is_animation) and "" or (image and self:photo_caption(message) or ""))
    local caption_lines = caption ~= "" and wrapped_lines(f.normal, caption, post_media and wrap_width or image_width) or {}
    local caption_links = formatted_caption and helpers.link_ranges(caption, formatted_caption.entities)
    local caption_emoji = formatted_caption and helpers.custom_emoji_ranges(caption, formatted_caption.entities)
    local caption_starts = (caption_links or caption_emoji) and helpers.line_starts(caption, caption_lines)
    local function draw_caption(left, top)
        for index, line in ipairs(caption_lines) do
            helpers.draw_link_line(line, caption_starts and caption_starts[index], caption_links,
                left, top + (index - 1) * line_height, f.normal, colors.text, caption_emoji, self.custom_emoji_image)
        end
    end
    local bubble_w
    local draw_bubble_bg = not is_sticker or reply ~= nil
    local card_w, card_h
    if is_video then card_w, card_h = self:video_card_size(max_bubble, padding) end

    if is_video then
        bubble_w = card_w + padding * 2
    elseif image then
        bubble_w = image_width + padding * 2
    else
        lines = wrapped_lines(f.normal, display_text, is_document and math.max(32, wrap_width - 28) or wrap_width)
        local max_line = 0
        for _, line in ipairs(lines or {}) do
            local line_w = f.normal:getWidth(line)
            max_line = math.max(max_line, line_w)
        end
        bubble_w = math.min(max_bubble, math.max(96, max_line + padding * 2 + (is_document and 28 or 0)))
    end
    if post_media then
        for _, line in ipairs(caption_lines) do
            bubble_w = math.max(bubble_w, math.min(max_bubble, f.normal:getWidth(line) + padding * 2))
        end
    end
    if forwarded then
        bubble_w = math.max(bubble_w, math.min(max_bubble, f.small:getWidth(forwarded) + padding * 2))
    end
    if reply then
        bubble_w = math.max(bubble_w, math.min(max_bubble, 254))
    end
    if sender_name then
        bubble_w = math.max(bubble_w, math.min(max_bubble, f.small:getWidth(sender_name) + padding * 2))
    end
    bubble_w = math.min(max_bubble, math.max(
        bubble_w, helpers.reaction_rows_width(reactions) + padding * 2
    ))
    if is_downloading then
        bubble_w = math.min(max_bubble, math.max(bubble_w, 210))
    end

    if message.content and (message.content["@type"] == "messageVoiceNote"
        or message.content["@type"] == "messageAudio") then
        bubble_w = math.min(max_bubble, math.max(bubble_w, 220))
    end

    local x = outgoing and (area_x + area_w - bubble_w - 18) or (area_x + 28)
    hit.bubble_x, hit.bubble_w = x, bubble_w
    if draw_bubble_bg then
        if is_selected then
            ui.rect(x, y, bubble_w, height, colors.accent, 10)
        elseif outgoing then
            ui.rect(x, y, bubble_w, height, colors.accent_dark, 10)
        else
            ui.rect(x, y, bubble_w, height, colors.panel_alt, 10)
        end
    elseif is_selected then
        ui.rect(x, y, bubble_w, height, colors.accent, 10)
    end

    local text_y = y + padding
    if not outgoing then
        local sender_id = message.sender_id and message.sender_id["@type"] == "messageSenderUser" and message.sender_id.user_id
        ui.text(ui.fit(sender_name, f.small, bubble_w - padding * 2), x + padding, text_y, f.small, colors.accent)
        self:draw_sender_avatar(sender_id, sender_name, x - 27, text_y, 22)
        if sender_id then
            hit.profile_user_id = sender_id
            self.profile_hits[#self.profile_hits + 1] = {
                user_id = sender_id, x = x - 27, y = text_y, w = bubble_w + 27, h = small_height,
            }
        end
        text_y = text_y + small_height + 2
    end

    if forwarded then
        ui.text(ui.fit(forwarded, f.small, bubble_w - padding * 2), x + padding, text_y, f.small, colors.accent)
        text_y = text_y + small_height + 2
    end

    if reply then
        local parent, status = self.tg:resolve_message_reply(message, reply)
        local name, quote = self.tg:reply_preview(reply, parent, status)
        helpers.draw_reply_card(name, quote, x + padding, text_y, bubble_w - padding * 2, f.tiny, colors)
        text_y = text_y + helpers.reply_card_height(f.tiny) + 4
    end

    if is_video then
        self:draw_video_card(message, x + padding, text_y, card_w, card_h, colors)
        draw_caption(x + padding, text_y + card_h + 6)
        hit.media = true
        hit.media_kind, hit.media_x, hit.media_y = "video", x + padding, text_y
        hit.media_w, hit.media_h = card_w, card_h
        self.media_hits[#self.media_hits + 1] = hit
    elseif image then
        local media_x, media_y = x + padding, text_y
        local content_kind = message.content and message.content["@type"]

        local sx = math.max(math.floor(x), self.conv_area_x or 0)
        local sy = math.max(math.floor(y), self.conv_area_y or 0)
        local sw = math.min(math.ceil(x + bubble_w), (self.conv_area_x or 0) + (self.conv_area_w or 9999)) - sx
        local sh = math.min(math.ceil(y + height), (self.conv_area_y or 0) + (self.conv_area_h or 9999)) - sy
        if sw > 0 and sh > 0 then
            love.graphics.setScissor(sx, sy, sw, sh)
        end
        local scale = image_width / image:getWidth()
        love.graphics.draw(image, media_x, media_y, 0, scale, scale)
        love.graphics.setScissor(self.conv_area_x or 0, self.conv_area_y or 0, self.conv_area_w or 9999, self.conv_area_h or 9999)
        if content_kind == "messagePhoto" then
            hit.media = true
            hit.media_kind = "photo"
            hit.media_x, hit.media_y = media_x, media_y
            hit.media_w, hit.media_h = image_width, image_height
            self.media_hits[#self.media_hits + 1] = hit
        elseif is_sticker or is_animation then
            hit.media = true
            hit.media_kind = is_sticker and "sticker" or "animation"
            hit.media_x, hit.media_y = media_x, media_y
            hit.media_w, hit.media_h = image_width, image_height

            local sticker_obj = nil
            if message and message.content then
                if message.content.sticker then
                    sticker_obj = message.content.sticker
                elseif message.content.animation then
                    sticker_obj = message.content.animation
                end
            end
            if (is_sticker or is_animation) and sticker_obj then
                local set_id = sticker_obj.set_id
                if not set_id and sticker_obj.sticker then
                    set_id = sticker_obj.sticker.set_id
                end
                if set_id then
                    hit.link = "https://t.me/addstickers/" .. tostring(set_id)
                    hit.sticker_set_id = set_id

                    message._sticker_set_link = hit.link
                    message._sticker_set_id = set_id
                end
            end
            self.media_hits[#self.media_hits + 1] = hit
        end
        text_y = text_y + image_height + 4
        draw_caption(x + padding, text_y)
        if is_sticker and sticker_emoji ~= "" then
            ui.text(sticker_emoji, x + padding, text_y + 4, f.small, colors.accent)
        end
    elseif is_sticker and sticker_emoji ~= "" then
        ui.text(sticker_emoji, x + padding, text_y, f.small, colors.accent)
    elseif message.content and message.content["@type"] == "messageAudio" then
        local _, _, audio_entry = self.tg:media_file_for_message(message)
        self:draw_music_track(message, audio_entry, x + padding, text_y, bubble_w - padding * 2, colors)
        hit.voice = true
        hit.voice_x, hit.voice_y = x + padding, text_y
        hit.voice_w, hit.voice_h = bubble_w - padding * 2, 54
        draw_caption(x + padding, text_y + 60)
    elseif message.content and message.content["@type"] == "messageVoiceNote" then
        local _, _, voice_entry = self.tg:media_file_for_message(message)
        self:draw_voice_note(message, voice_entry, x + padding, text_y, bubble_w - padding * 2, colors)
        hit.voice = true
        hit.voice_x, hit.voice_y = x + padding, text_y
        hit.voice_w, hit.voice_h = bubble_w - padding * 2, 38
        draw_caption(x + padding, text_y + 44)
    elseif is_animation and animation_label ~= "" then
        ui.printf(animation_label, x + padding, text_y, wrap_width, "left", f.small, colors.muted)
        hit.media_kind, hit.media_x, hit.media_y = "animation", x, y
        hit.media_w, hit.media_h = bubble_w, height
        self.media_hits[#self.media_hits + 1] = hit
    elseif is_document then
        local icon_x = x + padding + 2
        local icon_y = text_y + 2
        love.graphics.setColor(colors.accent)
        love.graphics.rectangle("line", icon_x, icon_y, 16, 20, 2)
        love.graphics.line(icon_x + 10, icon_y, icon_x + 10, icon_y + 6, icon_x + 16, icon_y + 6)
        love.graphics.line(icon_x + 3, icon_y + 11, icon_x + 13, icon_y + 11)
        love.graphics.line(icon_x + 3, icon_y + 15, icon_x + 11, icon_y + 15)
        draw_text_lines(wrapped_lines(f.normal, display_text, math.max(32, wrap_width - 28)),
            x + padding + 26, text_y, f.normal, colors.text)
    else
        local links = helpers.link_ranges(display_text, entities)
        local emoji_sticker = content and content.animated_emoji and content.animated_emoji.sticker
        local emoji = helpers.custom_emoji_ranges(display_text, entities, emoji_sticker)
        local starts = (links or emoji) and helpers.line_starts(display_text, lines)
        for index, line in ipairs(lines) do
            helpers.draw_link_line(line, starts and starts[index], links,
                x + padding, text_y + (index - 1) * line_height, f.normal, colors.text, emoji, self.custom_emoji_image)
        end
        local tags = helpers.hashtag_tokens(text)
        for _, tag in ipairs(tags) do
            for line_index, line in ipairs(lines) do
                local tag_start = line:find(tag, 1, true)
                if tag_start then
                    local tag_x = x + padding + f.normal:getWidth(line:sub(1, tag_start - 1))
                    local tag_y = text_y + (line_index - 1) * line_height
                    local tag_width = f.normal:getWidth(tag)
                    love.graphics.setColor(colors.accent)
                    love.graphics.line(tag_x, tag_y + line_height - 1, tag_x + tag_width, tag_y + line_height - 1)
                    self.hashtag_hits[#self.hashtag_hits + 1] = {
                        tag = tag, x = tag_x, y = tag_y, w = tag_width, h = line_height,
                    }
                    break
                end
            end
        end
    end

    if is_downloading then
        local progress_y = y + body_height - padding - small_height - 25 - reactions_height
        local downloaded = self:format_bytes(download_state.downloaded)
        local label
        if download_state.size > 0 then
            local remaining = math.max(0, download_state.size - download_state.downloaded)
            label = "Remaining " .. self:format_bytes(remaining)
            if download_state.progress then
                label = label .. string.format(" · %.0f%%", (1 - download_state.progress) * 100)
            end
        else
            label = downloaded .. " loaded"
        end
        ui.text(label, x + padding, progress_y, f.tiny, colors.muted)
        local bar_x = x + padding
        local bar_y = progress_y + f.tiny:getHeight() + 2
        local bar_w = bubble_w - padding * 2
        ui.rect(bar_x, bar_y, bar_w, 4, colors.header, 2)
        if download_state.progress and download_state.progress > 0 then
            ui.rect(bar_x, bar_y, bar_w * download_state.progress, 4, colors.accent, 2)
        end
    end

    if #reactions > 0 then
        local reactions_y = y + body_height - padding - small_height - reactions_height + helpers.reaction_gap
        helpers.draw_reaction_rows(reactions, x + padding, reactions_y, f.tiny, colors, self.custom_emoji_image)
    end

    local time_text = os.date("%H:%M", message.date or 0)
    ui.text(time_text, x + bubble_w - padding - f.tiny:getWidth(time_text), y + body_height - padding - f.tiny:getHeight(), f.tiny, colors.muted)
    if comment_count then self:draw_comment_link(message, comment_count, x + padding, y + body_height, bubble_w - padding * 2) end
end

function messenger_screen:can_show_composer(chat)
    local text, media = self.tg:chat_send_capabilities(chat)
    return text or media
end

local function read_status_line(path)
    local file = io.open(path, "r")
    if not file then return end
    local line = file:read("*l")
    file:close()
    return line
end

function messenger_screen:refresh_status()
    local status = self.status_info
    local now = love.timer.getTime()
    if now - status.last_refresh < 5 then return end
    status.last_refresh, status.time = now, os.date("%H:%M")
    local capacity = read_status_line("/sys/class/power_supply/axp2202-battery/capacity")
        or read_status_line("/sys/class/power_supply/battery/capacity")
    status.battery = tonumber(capacity)
    if not status.battery and love.system and love.system.getPowerInfo then
        local _, percent = love.system.getPowerInfo()
        status.battery = percent
    end
    status.signal = 0
    local wireless = io.open("/proc/net/wireless", "r")
    if wireless then
        for line in wireless:lines() do
            local quality = tonumber(line:match(":%s+[%x]+%s+([%d%.]+)"))
            if quality then status.signal = math.max(status.signal, math.min(4, math.ceil(quality / 18))) end
        end
        wireless:close()
    end
end

function messenger_screen:draw_status_panel(x, width, scale)
    local status, fonts, colors = self.status_info, self.fonts, ui.colors
    local height = math.floor(40 * scale)
    local y = math.floor((HEADER_HEIGHT - 2 - height) / 2)
    local center = y + math.floor(height / 2)
    local function size(px) return math.floor(px * scale + 0.5) end
    local clock = scale >= 0.85 and fonts.normal or fonts.small
    local label = scale >= 0.85 and fonts.small or fonts.tiny
    ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
    ui.retro_panel(x + size(4), y + size(4), size(92), height - size(8), colors.accent_dark, colors.header)
    local clock_width = size(84)
    ui.printf(ui.fit(status.time, clock, clock_width), x + size(8), center - math.floor(clock:getHeight() / 2),
        clock_width, "center", clock, colors.accent)
    ui.rect(x + size(192), y + size(7), size(2), height - size(14), colors.accent_dark)
    local battery_x = x + size(109)
    ui.outline(battery_x, center - size(8), size(27), size(16), colors.muted, 0)
    ui.rect(battery_x + size(27), center - size(4), size(3), size(8), colors.muted)
    local battery = status.battery
    if battery and battery >= 0 then
        local filled = math.ceil(math.min(battery, 100) / 25)
        for segment = 0, 3 do
            ui.rect(battery_x + size(3 + segment * 5), center - size(5), size(4), size(10),
                segment >= filled and colors.accent_dark or battery <= 15 and colors.red or colors.accent)
        end
    end
    local percentage = battery and battery >= 0 and tostring(math.floor(battery)) .. "%" or "—"
    ui.printf(ui.fit(percentage, label, size(44)), x + size(143), center - math.floor(label:getHeight() / 2),
        size(44), "center", label, colors.text)
    for bar = 1, 4 do
        local bar_height = size(5 + bar * 4)
        ui.rect(x + size(206 + (bar - 1) * 10), center + size(10) - bar_height, size(7), bar_height,
            bar <= (status.signal or 0) and colors.accent or colors.accent_dark)
    end
end

function messenger_screen:draw_input(panel_x, panel_w, h)
    local f = self.fonts
    local colors = ui.colors

    if self.sticker_link_mode then
        ui.rect(panel_x, h - INPUT_HEIGHT, panel_w, INPUT_HEIGHT, colors.header)
        ui.text("Enter a sticker pack link", panel_x + 16, h - INPUT_HEIGHT + 16, f.small, colors.text)
        ui.text("> " .. self.sticker_link_input, panel_x + 16, h - INPUT_HEIGHT + 42, f.normal, colors.text)
        ui.button_hint("{confirm} — Open   {back} — Cancel", panel_x + 16, h - INPUT_HEIGHT + 66, f.tiny, colors.muted)
        return
    end

    local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
    local x, y = panel_x + 16, h - INPUT_HEIGHT + 10
    local gap, height, sticker_w, send_w = 8, 42, 94, 52
    local input_w = panel_w - 32 - send_w - gap - (media and sticker_w + gap or 0)
    local sticker_x = text and x + input_w + gap or x
    local send_x = panel_x + panel_w - 16 - send_w
    local enabled = self.model.input ~= ""
    self.composer_bounds = {}
    ui.rect(panel_x, h - INPUT_HEIGHT, panel_w, INPUT_HEIGHT, colors.header)
    if text then
        self.composer_bounds[1] = {x = x, y = y, w = input_w, h = height}
        self.composer_bounds[3] = {x = send_x, y = y, w = send_w, h = height}
        ui.rect(x, y, input_w, height, colors.panel_alt, 8)
        ui.outline(x, y, input_w, height, colors.accent_dark, 8)
        local shown = enabled and self.model.input or "Message…"
        ui.text(ui.fit(shown, f.normal, input_w - 22), x + 11, y + 11, f.normal,
            enabled and colors.text or colors.muted)
        local age = self.send_flash_at and love.timer.getTime() - self.send_flash_at or 1
        local lift = ui.focus_lift(age)
        ui.retro_panel(send_x, y - lift, send_w, height, enabled and colors.accent or colors.panel_alt,
            enabled and colors.accent or colors.accent_dark)
        ui.printf(age < 0.65 and "Queued" or "Send", send_x, y + 13 - lift, send_w, "center",
            f.tiny, enabled and colors.bg or colors.text)
    end
    if media then
        self.composer_bounds[2] = {x = sticker_x, y = y, w = sticker_w, h = height}
        ui.retro_panel(sticker_x, y, sticker_w, height, colors.panel_alt, colors.accent_dark)
        ui.media_picker_icon(sticker_x + sticker_w / 2, y + height / 2, colors.text)
    end
    local focused = self.composer_focus and self.composer_bounds[self.composer_focus]
    if focused and not self.header_focus then
        local now = love.timer.getTime()
        if self.last_composer_focus ~= self.composer_focus then
            self.last_composer_focus, self.composer_focus_at = self.composer_focus, now
        end
        local focus_color = self.composer_focus == 3 and enabled and colors.bg or colors.accent
        ui.focus_corners(focused.x + 2, focused.y + 2, focused.w - 4, focused.h - 4, focus_color, ui.focus_lift(now - self.composer_focus_at))
    end
end

return messenger_screen
