
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
        self.tg:send({["@type"] = "getSupergroup", supergroup_id = kind.supergroup_id}, "profile_handle:" .. tostring(chat.id))
        self.tg:send({["@type"] = "getSupergroupFullInfo", supergroup_id = kind.supergroup_id}, extra)
    elseif kind.basic_group_id then
        self.tg:send({["@type"] = "getBasicGroupFullInfo", basic_group_id = kind.basic_group_id}, extra)
    end
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
    self.action_index, self.action_hits = 1, {}
    self.media_open, self.photo_view, self.block_confirm = nil, nil, nil
    self.open_chat_id, self.pending_message = nil, nil
    self.tg.profile_message_open = nil
    self.tg:close_profile_photo()

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
    if self.user_id and not self.is_me then self.tg:load_profile_user(self.user_id) end
end

function profile_screen:update()
    if not self.user_id then
        if not self.chat_id then return end
        local chat = self.tg.chats_by_id[self.chat_id] or self.tg.archive_chats_by_id[self.chat_id]
        if not chat then return end
        if self.loaded_chat_id ~= chat.id then self:load_chat_profile(chat) end
        self.user_id = self.tg:private_chat_user_id(chat)
        if self.user_id then
            self.tg:ensure_user(self.user_id)
            self.tg:load_profile_user(self.user_id)
            return
        end
        self.name = chat.title or "Chat"
        local details = self.tg.profile_details and self.tg.profile_details[chat.id]
        self.username = details and details.username or chat.username or ""
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

function profile_screen:full_photo_file()
    local chat = self.chat_id and (self.tg.chats_by_id[self.chat_id] or self.tg.archive_chats_by_id[self.chat_id])
    local user = self.user_id and self.tg.users[self.user_id]
    local photo = (user and user.profile_photo) or (chat and chat.photo)
    local user_profile = self.tg.profile_user
    local chat_profile = chat and self.tg.profile_details and self.tg.profile_details[chat.id]
    local full = (user_profile and user_profile.id == self.user_id and user_profile.photo)
        or (chat_profile and chat_profile.photo)
    local file, best = nil, 0
    for _, size in ipairs(full and full.sizes or {}) do
        local area = (size.width or 0) * (size.height or 0)
        if size.photo and size.photo.id and area > best and math.max(size.width, size.height) <= 1280 then
            file, best = size.photo, area
        end
    end
    file = file or (photo and (photo.big or photo.small))
    return file and file.id and file or nil
end

function profile_screen:actions()
    local items = {}
    if self.is_me then
        items[#items + 1] = {id = "edit", label = "Edit profile"}
    elseif self.user_id then
        items[#items + 1] = {id = "message", label = "Message"}
    elseif self.loaded_chat_id then
        items[#items + 1] = {id = "chat", label = self.peer_kind == "Channel" and "View channel posts" or "Open group"}
    end
    if self:full_photo_file() then items[#items + 1] = {id = "photo", label = "View profile picture"} end
    local profile = self.tg.profile_user
    if self.user_id and not self.is_me and profile and profile.id == self.user_id and profile.blocked ~= nil then
        local label = profile.blocked and "Unblock user" or "Block user"
        items[#items + 1] = {id = "block", label = self.block_confirm and "Confirm " .. label:lower() or label}
    end
    if self.loaded_chat_id then items[#items + 1] = {id = "media", label = "Shared media"} end
    return items
end

function profile_screen:activate_action(action)
    if not action then return end
    local id = action.id
    if id == "edit" then
        self:begin_edit()
    elseif id == "chat" or (id == "message" and self.chat_id) then
        self.open_chat_id = self.chat_id
    elseif id == "message" then
        if self.pending_message and not self.pending_message.error then return end
        local tg = self.tg
        tg.profile_message_generation = (tg.profile_message_generation or 0) + 1
        local token = "profile_message:" .. tostring(tg.profile_message_generation)
        local request = {token = token}
        self.pending_message, tg.profile_message_open = request, request
        tg:open_private_chat(self.user_id, token)
    elseif id == "photo" then
        local file = self:full_photo_file()
        if file then
            self.photo_view = self.tg:open_profile_photo(file)
            self.photo_zoom, self.photo_x, self.photo_y = false, 0, 0
        end
    elseif id == "block" then
        local profile = self.tg.profile_user
        if profile.pending then return end
        if self.block_confirm then self.tg:set_profile_user_blocked(not profile.blocked) end
        self.block_confirm = not self.block_confirm
    elseif id == "media" then
        self.media_open = true
        self.tg:load_profile_media(self.chat_id, self.category)
    end
end

function profile_screen:draw_photo(w, h, f, colors)
    local entry = self.photo_view
    local image = entry.image
    if image then
        local iw, ih = image:getWidth(), image:getHeight()
        local height = math.max(1, h - 100)
        local scale = self.photo_zoom and 1 or math.min(1, (w - 24) / iw, height / ih)
        local max_x, max_y = math.max(0, (iw * scale - w) / 2), math.max(0, (ih * scale - height) / 2)
        self.photo_x = math.max(-max_x, math.min(max_x, self.photo_x))
        self.photo_y = math.max(-max_y, math.min(max_y, self.photo_y))
        love.graphics.setScissor(0, 56, w, height)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, (w - iw * scale) / 2 + self.photo_x,
            56 + (height - ih * scale) / 2 + self.photo_y, 0, scale, scale)
        love.graphics.setScissor()
    else
        ui.printf(entry.status == "error" and "Could not load profile picture." or "Loading profile picture…",
            24, h / 2, w - 48, "center", f.normal, colors.text)
    end
    local hint = image and (self.photo_zoom and "{confirm} — Fit   D-pad — Pan" or "{confirm} — Actual size") or ""
    ui.button_hint(hint .. "   {back} — Back", 24, h - 30, f.tiny, colors.muted, w - 48)
end

function profile_screen:draw_media(f, colors, w, h)
    local top, step = 76, math.floor((w - 24) / #categories)
    for index, category in ipairs(categories) do
        local x = 12 + (index - 1) * step
        local selected = self.category == category.key
        ui.rect(x, top - 4, step - 4, 26, selected and colors.accent_dark or colors.panel_alt, 5)
        ui.printf(ui.fit(category.label, f.tiny, step - 6), x, top + 1, step - 4, "center", f.tiny, colors.text)
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
    if self.photo_view then heading = "Profile picture"
    elseif self.media_open then heading = "Shared media" end
    ui.text(heading, 24, 15, f.subtitle, colors.text)
    ui.button_hint("{back} — Back", w - 140, 18, f.tiny, colors.muted)
    if self.editor then self:draw_editor(w, h, f, colors); return end
    if self.photo_view then self:draw_photo(w, h, f, colors); return end
    if self.media_open then
        self:draw_media(f, colors, w, h)
        ui.button_hint("←/→ — Categories   ↑/↓ — Scroll   {back} — Back", 24, h - 32, f.tiny, colors.muted, w - 48)
        return
    end

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
        ui.text(ui.fit("@" .. self.username, f.small, w - text_x - 20), text_x, yy, f.small, colors.muted)
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
    local profile = self.tg.profile_user
    if not self.user_id or not profile or profile.id ~= self.user_id then profile = nil end
    local bio = self.is_me and self.bio or profile and profile.bio
    if bio and bio ~= "" and h >= 300 then
        ui.text(ui.fit(bio, f.small, w - 48), 24, 156, f.small, colors.muted)
    end
    local actions = self:actions()
    local row_h = math.max(30, f.normal:getHeight() + 10)
    local top = h >= 330 and 201 or math.min(158, math.max(110, h - row_h - 55))
    local visible = math.max(1, math.floor((h - top - 55) / (row_h + 5)))
    self.action_index = math.max(1, math.min(#actions, self.action_index or 1))
    local first = math.max(1, self.action_index - visible + 1)
    self.action_hits = {}
    for i = first, math.min(#actions, first + visible - 1) do
        local y = top + (i - first) * (row_h + 5)
        local selected = self.action_index == i
        local bg = selected and colors.accent or colors.panel_alt
        ui.retro_panel(24, y, w - 48, row_h, bg, colors.accent_dark)
        ui.text(ui.fit(actions[i].label, f.normal, w - 72), 36, y + (row_h - f.normal:getHeight()) / 2,
            f.normal, selected and ui.contrasting_text(bg) or colors.text)
        self.action_hits[#self.action_hits + 1] = {index = i, action = actions[i], y = y, h = row_h}
    end
    local notice = self.save_notice or (profile and (profile.error or (profile.pending and "Updating block status…")))
        or (self.pending_message and (self.pending_message.error or "Opening chat…"))
    if notice then ui.text(ui.fit(notice, f.tiny, w - 48), 24, h - 53, f.tiny, colors.muted) end
    local hint = #actions > 0 and "↑/↓ — Move   {confirm} — Open   {back} — Back" or "{back} — Back"
    ui.button_hint(hint, 24, h - 32, f.tiny, colors.muted, w - 48)
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
                elseif result and result.kind == "enter" then
                    self:textinput(editor.input:commit_pinyin()); editor.input.visible = false
                else
                    local value = editor.input:apply_edit(editor[field], result)
                    if field == "bio" and editor[field] ~= value then editor.bio_dirty = true end
                    editor[field] = value
                end
            end
        elseif key == "up" or key == "down" then
            editor.index = math.max(1, math.min(#fields + 1, editor.index + (key == "up" and -1 or 1)))
        elseif key == "escape" then
            self.editor = nil
        elseif confirm then
            if fields[editor.index] then
                editor.input:reset_caret()
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
    if self.photo_view then
        if key == "escape" then
            self.tg:close_profile_photo()
            self.photo_view = nil
        elseif confirm and self.photo_view.image then
            self.photo_zoom, self.photo_x, self.photo_y = not self.photo_zoom, 0, 0
        elseif self.photo_zoom then
            if key == "left" then self.photo_x = self.photo_x + 48
            elseif key == "right" then self.photo_x = self.photo_x - 48
            elseif key == "up" then self.photo_y = self.photo_y + 48
            elseif key == "down" then self.photo_y = self.photo_y - 48 end
        end
        return
    end
    if not self.media_open then
        local actions = self:actions()
        if key == "escape" then
            if self.block_confirm then self.block_confirm = nil; return end
            self.pending_message, self.tg.profile_message_open = nil, nil
            return "back"
        elseif key == "up" or key == "down" then
            self.block_confirm = nil
            self.action_index = math.max(1, math.min(#actions, self.action_index + (key == "up" and -1 or 1)))
        elseif confirm then
            self:activate_action(actions[self.action_index])
        end
        return
    end
    if key == "escape" then
        self.media_open = nil
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
        local list_h = ui.height() - 150
        local visible = math.max(1, math.floor((list_h - 8) / 44))
        self.media_scroll = math.min(math.max(0, count - visible), self.media_scroll + 1)
    end
end

function profile_screen:wheelmoved(_, y)
    if not self.media_open then return end
    local data = self.chat_id and self.tg.profile_media[self.category]
        and self.tg.profile_media[self.category][self.chat_id]
    local count = data and #(data.messages or {}) or 0
    local visible = math.max(1, math.floor((ui.height() - 158) / 44))
    self.media_scroll = math.max(0, math.min(math.max(0, count - visible), self.media_scroll - y * 2))
end
function profile_screen:mousepressed(x, y, button)
    if button ~= 1 or self.editor or self.photo_view then return end
    if not self.media_open then
        for _, hit in ipairs(self.action_hits) do
            if x >= 24 and x < ui.width() - 24 and y >= hit.y and y < hit.y + hit.h then
                if self.action_index ~= hit.index then self.block_confirm = nil end
                self.action_index = hit.index
                self:activate_action(hit.action)
                return
            end
        end
        if x >= 24 and x < 100 and y >= 70 and y < 146 then self:activate_action({id = "photo"}) end
        return
    end
    local tab_y = 72
    if y >= tab_y and y <= tab_y + 32 then
        local index = math.floor((x - 12) / math.floor((ui.width() - 24) / #categories)) + 1
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
    editor[key] = editor.input:apply_edit(editor[key], {kind = "text", text = text:gsub("[\r\n]+", " ")})
end

return profile_screen
