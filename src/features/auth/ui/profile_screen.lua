
local ui = require("src.shared.ui.ui_kit")
local keyboard = require("src.shared.ui.virtual_keyboard")
local fields = {{"first_name", "First name"}, {"last_name", "Last name"}, {"bio", "Bio"}}

local function username(user)
    local handles = user.usernames
    return (handles and (handles.active_usernames or {})[1]) or user.username or ""
end

local profile_screen = {}
local categories = {
    {key = "photos", label = "Photos"},
    {key = "videos", label = "Videos"},
    {key = "files", label = "Files"},
    {key = "links", label = "Links"},
    {key = "music", label = "Music"},
    {key = "voice", label = "Voice"},
}

local function draw_avatar(image, x, y, size)
    if not image then return end
    local scale = math.max(size / image:getWidth(), size / image:getHeight())
    local draw_w = image:getWidth() * scale
    local draw_h = image:getHeight() * scale
    love.graphics.stencil(function()
        love.graphics.circle("fill", x + size / 2, y + size / 2, size / 2)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x + (size - draw_w) / 2, y + (size - draw_h) / 2, 0, scale, scale)
    love.graphics.setStencilTest()
end

function profile_screen.new(fonts, tg)
    local self = {}
    self.fonts = fonts
    self.tg = tg
    self.user_id = nil
    self.chat_id = nil
    self.is_me = false
    self.category = "photos"
    self.media_scroll = 0
    return setmetatable(self, {__index = profile_screen})
end

function profile_screen:load_chat_profile(chat)
    self.loaded_chat_id = chat.id
    local kind = chat.type or {}
    self.peer_kind = kind.is_channel and "Channel" or (kind["@type"] == "chatTypeBasicGroup"
        or kind["@type"] == "chatTypeSupergroup") and "Group" or "Profile"
    local extra = "profile_details:" .. tostring(chat.id)
    if kind.supergroup_id then
        self.tg:send({["@type"] = "getSupergroupFullInfo", supergroup_id = kind.supergroup_id}, extra)
    elseif kind.basic_group_id then
        self.tg:send({["@type"] = "getBasicGroupFullInfo", basic_group_id = kind.basic_group_id}, extra)
    end
    self.tg:load_profile_media(chat.id, self.category)
end

function profile_screen:enter()
    self.avatar = nil
    self.avatar_w = 0
    self.avatar_h = 0
    self.name = ""
    self.loaded_chat_id, self.peer_kind = nil, nil
    self.category = "photos"
    self.username = ""
    self.bio = ""
    self.phone = ""
    self.status = ""
    self.editor, self.save_notice = nil, nil
    self.media_scroll = 0

    if self.is_me then
        local me = self.tg.me
        if me then
            self.user_id = me.id
            self.tg:request_my_profile()
            self.tg:ensure_user(me.id)
            self.tg:ensure_user_photo(me.id)
            self.name = self.tg:user_name(me.id)
            self.username = username(me)
            self.phone = me.phone_number or ""
            local avatar = self.tg:user_photo_image(me.id)
            if avatar then
                self.avatar = avatar
                self.avatar_w = avatar:getWidth()
                self.avatar_h = avatar:getHeight()
            end
        end
    elseif self.user_id then
        self.tg:ensure_user(self.user_id)
        local user = self.tg.users[self.user_id]
        if user then
            self.name = self.tg:user_name(self.user_id)
            self.username = username(user)
            self.phone = user.phone_number or ""
            local avatar = self.tg:user_photo_image(self.user_id)
            if avatar then
                self.avatar = avatar
                self.avatar_w = avatar:getWidth()
                self.avatar_h = avatar:getHeight()
            end
        end
        self.status = self.tg:user_status_text(self.user_id)
    elseif self.chat_id then
        local chat = self.tg.chats_by_id[self.chat_id] or self.tg.archive_chats_by_id[self.chat_id]
        if not chat then
            self.name = "Loading profile…"
            self.tg:send({["@type"] = "getChat", chat_id = self.chat_id}, "getChat:" .. tostring(self.chat_id))
        else
            self:load_chat_profile(chat)
            self.name = chat.title or ("Chat " .. tostring(self.chat_id))
            self.username = chat.username or ""
            local avatar = self.tg:chat_photo_image(self.chat_id)
            if avatar then
                self.avatar = avatar
                self.avatar_w = avatar:getWidth()
                self.avatar_h = avatar:getHeight()
            end
            self.user_id = self.tg:private_chat_user_id(chat)
            if self.user_id then
                self.tg:ensure_user(self.user_id)
                self.status = self.tg:user_status_text(self.user_id)
                local user = self.tg.users[self.user_id]
                if user then
                    self.username = username(user)
                    self.phone = user.phone_number or ""
                end
            end
        end
    end
end

function profile_screen:update()
    if not self.user_id then
        if not self.chat_id then return end
        local chat = self.tg.chats_by_id[self.chat_id] or self.tg.archive_chats_by_id[self.chat_id]
        if not chat then return end
        if self.loaded_chat_id ~= chat.id then self:load_chat_profile(chat) end
        self.name = chat.title or "Chat"
        self.username = chat.username or ""
        self.avatar = self.tg:chat_photo_image(self.chat_id)
        return
    end
    local user = self.tg.users[self.user_id]
    if user then
        self.name = self.tg:user_name(self.user_id)
        self.username = username(user)
        self.phone = user.phone_number or self.phone
        self.status = not self.is_me and self.tg:user_status_text(self.user_id) or ""
    end
    if self.is_me then self.bio = self.tg.my_bio or "" end
    local editor = self.editor
    if editor and not editor.bio_dirty then editor.bio = self.bio end
    if editor and editor.saving and editor.saving.pending == 0 then
        if #editor.saving.errors == 0 then self.editor, self.save_notice = nil, "Profile saved"
        else
            editor.error = table.concat(editor.saving.errors, " · ")
            editor.saving = nil
        end
    end
    local avatar = self.tg:user_photo_image(self.user_id)
    self.avatar = avatar
    if avatar then
        self.avatar_w = avatar:getWidth()
        self.avatar_h = avatar:getHeight()
    end
end

function profile_screen:draw_media(f, colors, w, h)
    local top = 220
    for index, category in ipairs(categories) do
        local x = 16 + (index - 1) * 100
        local selected = self.category == category.key
        ui.rect(x, top - 4, 94, 26, selected and colors.accent_dark or colors.panel_alt, 5)
        ui.printf(category.label, x, top + 1, 94, "center", f.tiny, colors.text)
    end
    local media_by_chat = self.tg.profile_media[self.category] or {}
    local data = self.chat_id and media_by_chat[self.chat_id]
    local list_y = top + 32
    local list_h = h - list_y - 42
    ui.rect(12, list_y, w - 24, list_h, colors.panel, 6)
    if not data or data.loading then
        ui.printf("Loading media…", 24, list_y + 20, w - 48, "left", f.small, colors.muted)
        return
    end
    if data.error then
        ui.printf(ui.fit(data.error, f.small, w - 48), 24, list_y + 20, w - 48, "left", f.small, colors.red)
        return
    end
    local messages = data.messages or {}
    if #messages == 0 then
        ui.printf("Nothing in this category yet", 24, list_y + 20, w - 48, "left", f.small, colors.muted)
        return
    end
    local row_h = 44
    local visible = math.max(1, math.floor((list_h - 8) / row_h))
    love.graphics.setScissor(12, list_y, w - 24, list_h)
    for index = self.media_scroll + 1, math.min(#messages, self.media_scroll + visible) do
        local message = messages[index]
        local row_y = list_y + 6 + (index - self.media_scroll - 1) * row_h
        local text = self.tg:message_text(message)
        local content = message.content or {}
        if self.category == "files" then
            text = self.tg:document_label(message)
        elseif self.category == "music" then
            text = self.tg:document_label(message)
        elseif self.category == "videos" then
            local video = content.video and content.video.video
            text = (video and video.file_name) or "[video]"
        end
        if self.category == "photos" then
            local image = self.tg:photo_image(message)
            if image then
                local size = 12
                local scale = math.min(size / image:getWidth(), size / image:getHeight())
                love.graphics.draw(image, 20, row_y + 3, 0, scale, scale)
            end
        end
        local date = os.date("%d.%m.%Y", message.date or 0)
        ui.text(ui.fit(text, f.small, w - 150), 68, row_y + 4, f.small, colors.text)
        ui.text(date, w - 84, row_y + 5, f.tiny, colors.muted)
        ui.rect(68, row_y + row_h - 1, w - 100, 1, colors.panel_alt)
    end
    love.graphics.setScissor()
    ui.button_hint("←/→ — Categories   ↑/↓ — Scroll   {back} — Back", 20, h - 30, f.tiny, colors.muted, w - 40)
end

function profile_screen:begin_edit()
    local me = self.tg.me
    if not self.is_me or not me then return end
    self.editor = {index = 1, first_name = me.first_name or "", last_name = me.last_name or "",
        bio = self.tg.my_bio or "", input = keyboard.new(self.fonts, true)}
    self.save_notice = nil
end

function profile_screen:draw_editor(w, h, f, colors)
    local editor = self.editor
    local width = math.min(514, w - 36)
    local x, y = (w - width) / 2, 66
    local editing = editor.input.visible
    if not editing then
        for index, field in ipairs(fields) do
            local row_y = y + (index - 1) * 62
            local focused = index == editor.index
            ui.retro_panel(x, row_y, width, 54, focused and colors.accent_dark or colors.panel_alt, colors.header)
            ui.text(field[2], x + 12, row_y + 7, f.tiny, colors.accent)
            ui.text(ui.fit(editor[field[1]], f.normal, width - 24), x + 12, row_y + 24, f.normal, colors.text)
        end
        local save_y = y + #fields * 62
        ui.retro_panel(x, save_y, width, 32, editor.index == #fields + 1 and colors.accent or colors.panel_alt, colors.header)
        ui.text(editor.saving and "Saving…" or "Save profile", x + 12, save_y + 8, f.small,
            editor.index == #fields + 1 and colors.bg or colors.text)
        if editor.error then ui.text(ui.fit(editor.error, f.small, width), x, save_y + 43, f.small, colors.red) end
        ui.button_hint("↑/↓ — Move   {confirm} — Edit or save   {back} — Cancel", x, h - 29, f.tiny, colors.muted, width)
    else
        local field = fields[editor.index]
        ui.text(field[2], x, y + 14, f.subtitle, colors.accent)
        ui.button_hint("{keyboard} — Done   {back} — Done", x, y + 47, f.tiny, colors.muted)
        editor.input:draw(editor[field[1]], field[2])
    end
end

function profile_screen:draw()
    local f = self.fonts
    local w = ui.width()
    local h = ui.height()
    local colors = ui.colors

    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    local heading = self.editor and "Edit profile" or self.is_me and "My profile" or self.peer_kind == "Channel" and "Channel info"
        or self.peer_kind == "Group" and "Group info" or "Profile"
    ui.text(heading, 24, 15, f.subtitle, colors.text)
    ui.button_hint("{back} — Back", w - 140, 18, f.tiny, colors.muted)
    if self.editor then self:draw_editor(w, h, f, colors); return end

    local avatar_size = 76
    local avatar_x = 24
    local avatar_y = 70

    if self.avatar then
        draw_avatar(self.avatar, avatar_x, avatar_y, avatar_size)
    else
        love.graphics.setColor(colors.accent)
        love.graphics.circle("fill", avatar_x + avatar_size / 2, avatar_y + avatar_size / 2, avatar_size / 2)
        local initial = ui.first_char(self.name)
        ui.printf(initial, avatar_x, avatar_y + avatar_size / 2 - f.normal:getHeight() / 2, avatar_size, "center", f.normal, colors.text)
    end

    local text_x = avatar_x + avatar_size + 18
    local yy = avatar_y + 2
    ui.text(ui.fit(self.name, f.subtitle, w - text_x - 20), text_x, yy, f.subtitle, colors.text)
    yy = yy + f.subtitle:getHeight() + 6
    if self.status ~= "" then
        ui.text(ui.fit(self.status, f.small, w - text_x - 20), text_x, yy, f.small,
            self.status == "Online" and colors.green or colors.muted)
        yy = yy + f.small:getHeight() + 6
    end
    if self.username and self.username ~= "" then
        ui.text("@" .. self.username, text_x, yy, f.small, colors.muted)
        yy = yy + f.small:getHeight() + 4
    end
    if self.phone and self.phone ~= "" then
        ui.text(self.phone, text_x, yy, f.tiny, colors.muted)
    end

    local details = self.chat_id and self.tg.profile_details and self.tg.profile_details[self.chat_id]
    if details then
        if details.member_count and details.member_count > 0 then
            local count = self.peer_kind == "Channel" and " subscribers" or " members"
            ui.text(tostring(details.member_count) .. count, text_x, yy, f.tiny, colors.accent)
        end
        if details.description and details.description ~= "" then
            local line_width = w - 48
            local _, lines = f.small:getWrap(details.description, line_width)
            local count = math.min(2, #lines)
            for i = 1, count do
                local line = lines[i] .. (i == count and #lines > count and "…" or "")
                ui.text(ui.fit(line, f.small, line_width), 24, 155 + (i - 1) * f.small:getHeight(), f.small, colors.muted)
            end
        end
    end
    if self.is_me then
        ui.retro_panel(24, 157, w - 48, 102, colors.panel, colors.accent_dark)
        ui.text("Bio", 36, 168, f.small, colors.accent)
        ui.printf(self.bio ~= "" and self.bio or "Add a bio in Edit profile", 36, 193, w - 72, "left", f.normal, colors.text)
        self.edit_button = {x = 24, y = 276, w = math.min(w - 48, 230), h = 37}
        ui.retro_panel(24, 276, self.edit_button.w, 37, colors.accent_dark, colors.accent)
        ui.button_hint("{confirm} — Edit profile", 33, 286, f.small, colors.text)
        if self.save_notice then ui.text(self.save_notice, 24, 327, f.small, colors.accent) end
    end

    if self.chat_id and self.loaded_chat_id then
        local view = self.tg.profile_media[self.category]
        local data = view and view[self.chat_id]
        self:draw_media(f, colors, w, h)
        if not data or data.loading or data.error or #(data.messages or {}) == 0 then
            ui.button_hint("←/→ — Categories   {back} — Back", 24, h - 32, f.tiny, colors.muted, w - 48)
        end
    else
        ui.button_hint("{back} — Back", 24, h - 32, f.tiny, colors.muted)
    end
end

function profile_screen:keypressed(key)
    local editor = self.editor
    local confirm = key == "return" or key == "kpenter"
    if editor then
        if editor.saving then return end
        if editor.input.visible then
            local field = fields[editor.index][1]
            if (key == "escape" or key == "f1") and not editor.input.language_menu then
                if key == "f1" then self:textinput(editor.input:commit_pinyin()) end
                editor.input.visible = false
            else
                local _, result = editor.input:keypressed(key)
                if result and result.kind == "text" then self:textinput(result.text)
                elseif result and result.kind == "backspace" then
                    editor[field] = ui.remove_last_utf8(editor[field])
                    if field == "bio" then editor.bio_dirty = true end
                elseif result and result.kind == "enter" then
                    self:textinput(editor.input:commit_pinyin()); editor.input.visible = false
                end
            end
        elseif key == "up" or key == "down" then
            editor.index = math.max(1, math.min(#fields + 1, editor.index + (key == "up" and -1 or 1)))
        elseif key == "escape" then
            self.editor = nil
        elseif confirm then
            if fields[editor.index] then
                editor.input.visible = true
            elseif not editor.first_name:match("%S") then
                editor.error = "First name is required."
            else
                editor.error = nil
                editor.saving = self.tg:save_my_profile(editor.first_name, editor.last_name, editor.bio_dirty and editor.bio or nil)
            end
        end
        return
    end
    if self.is_me and confirm then self:begin_edit(); return end
    if key == "escape" then
        return "back"
    elseif key == "left" or key == "right" then
        local idx = 1
        for i, c in ipairs(categories) do if c.key == self.category then idx = i; break end end
        idx = idx + (key == "right" and 1 or -1)
        if idx < 1 then idx = #categories end
        if idx > #categories then idx = 1 end
        self.category = categories[idx].key
        self.media_scroll = 0
        if self.chat_id then self.tg:load_profile_media(self.chat_id, self.category) end
    elseif key == "up" then
        self.media_scroll = math.max(0, self.media_scroll - 1)
    elseif key == "down" then
        local data = self.chat_id and self.tg.profile_media[self.category]
            and self.tg.profile_media[self.category][self.chat_id]
        local count = data and #(data.messages or {}) or 0
        local list_h = ui.height() - 254
        local visible = math.max(1, math.floor((list_h - 8) / 44))
        self.media_scroll = math.min(math.max(0, count - visible), self.media_scroll + 1)
    end
end

function profile_screen:wheelmoved(_, y)
    local data = self.chat_id and self.tg.profile_media[self.category]
        and self.tg.profile_media[self.category][self.chat_id]
    local count = data and #(data.messages or {}) or 0
    local visible = math.max(1, math.floor((ui.height() - 294) / 44))
    self.media_scroll = math.max(0, math.min(math.max(0, count - visible), self.media_scroll - y * 2))
end
function profile_screen:mousepressed(x, y, button)
    if button ~= 1 or self.editor then return end
    local edit = self.is_me and self.edit_button
    if edit and x >= edit.x and x < edit.x + edit.w and y >= edit.y and y < edit.y + edit.h then
        self:begin_edit()
        return
    end
    local tab_y = 216
    if y >= tab_y and y <= tab_y + 32 then
        local index = math.floor((x - 16) / 100) + 1
        local category = categories[index]
        if category then
            self.category = category.key
            self.media_scroll = 0
            if self.chat_id then self.tg:load_profile_media(self.chat_id, self.category) end
        end
    end
end
function profile_screen:textinput(text)
    local editor = self.editor
    if not text or not editor or not editor.input.visible or editor.saving then return end
    local key = fields[editor.index][1]
    if key == "bio" then editor.bio_dirty = true end
    editor[key] = editor[key] .. text:gsub("[\r\n]+", " ")
end

return profile_screen
