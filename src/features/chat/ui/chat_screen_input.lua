local ui = require("src.shared.ui.ui_kit")
local helpers = require("src.features.chat.ui.chat_screen_helpers")
local sponsored = require("src.shared.api.sponsored")

return function(messenger_screen, layout)
    local HEADER_HEIGHT = layout.HEADER_HEIGHT
    local CHAT_HEADER_HEIGHT = layout.CHAT_HEADER_HEIGHT
    local INPUT_HEIGHT = layout.INPUT_HEIGHT
    local REACTION_EMOJIS = layout.REACTION_EMOJIS
    local REACTION_COLUMNS = layout.REACTION_COLUMNS

    messenger_screen.r2_pressed = false
    messenger_screen.l2_pressed = false

    function messenger_screen:send()
        local chat = self.model:current_chat()
        local entities = {}
        local units = helpers.utf16_units(self.model.input)
        for _, entity in ipairs(self.draft_emoji_entities or {}) do
            if entity.offset + entity.length <= units then entities[#entities + 1] = entity end
        end
        if self.tg:chat_send_capabilities(chat) and self.model.input ~= ""
            and self.tg:send_message(chat.id, self.model.input, nil, nil, nil, entities) then
            self.send_flash_at = love.timer.getTime()
            self.draft_emoji_entities = nil
            self.model.input = ""
            self.model.scroll = 0
        end
    end

    function messenger_screen:activate_composer(index)
        local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
        if index == 2 and not media or index ~= 2 and not text then return end
        self.composer_focus = index
        if index == 1 then
            self.keyboard.visible = true
        elseif index == 2 then
            self:open_stickers()
        else
            self:send()
        end
    end

    function messenger_screen:jump_to_last_read()
        if not self.tg:jump_to_last_read(self.tg.current_chat_id) then return end
        self.sponsor_focus, self.sponsor_inline, self.sponsor_bot = nil, nil, nil
        self.composer_focus = nil
    end

    function messenger_screen:cursor_index()
        local nav = self.nav_messages or {}
        if not self.message_cursor_id then return #nav end
        for index, message in ipairs(nav) do
            if message.id == self.message_cursor_id then return index end
        end
        return #nav
    end

    function messenger_screen:focused_message()
        local nav = self.nav_messages or {}
        return nav[self:cursor_index()]
    end

    function messenger_screen:ensure_row_visible(pos)
        local area_y, area_h = self.conv_area_y, self.conv_area_h
        if not pos or not area_y or not area_h then return end
        local top, bottom = pos.y, pos.y + pos.h
        local delta = 0
        if top < area_y then
            delta = area_y - top
        elseif bottom > area_y + area_h then
            delta = (area_y + area_h) - bottom
        end
        if delta ~= 0 then
            self.model.scroll = math.max(0, math.min(self.model.max_scroll, self.model.scroll + delta))
        end
    end

    function messenger_screen:ensure_message_visible(message_id)
        self:ensure_row_visible(self.nav_pos and self.nav_pos[message_id])
    end

    function messenger_screen:move_message_cursor(delta)
        local nav = self.nav_messages or {}
        if #nav == 0 then return end
        local active = self:cursor_index()
        local index = math.max(1, math.min(#nav, active + delta))
        local start = self.nav_pos[nav[active].id]
        local finish = self.nav_pos[nav[index].id]
        local chosen
        if start and finish then
            for _, row in ipairs(self.sponsor_rows or {}) do
                if (row.y - start.y) * delta > 0
                    and (active == index or (finish.y - row.y) * delta > 0)
                    and (not chosen or (row.y - chosen.y) * delta < 0) then
                    chosen = row
                end
            end
        end
        if chosen then
            self.sponsor_focus = true
            self.sponsor_inline = chosen.id
            self:ensure_row_visible(chosen)
            return
        end
        self.message_cursor_id = nav[index].id
        self:ensure_message_visible(nav[index].id)
    end

    function messenger_screen:scroll_chat(dir)
        local now = love.timer.getTime()
        local base = 25
        if self.scroll_dir == dir and self.scroll_hold_start then
            local hold = now - self.scroll_hold_start
            local accel = math.min(1 + hold * 4, 12)
            base = base * accel
        else
            self.scroll_dir = dir
            self.scroll_hold_start = now
        end
        self.model.scroll = math.max(0, math.min(self.model.max_scroll or 0, (self.model.scroll or 0) + base * dir))
    end

    function messenger_screen:keyboard_preview()
        if self.edit_mode then
            return self.edit_input or "", "Edit message…"
        elseif self.search_active then
            return self.search_query or "", "Search messages…"
        elseif self.tg.current_chat_id then
            return self.model.input or "", "Write a message…"
        end
        return ""
    end

    function messenger_screen:keyboard_text(text)
        if not text or text == "" then return end
        if self.edit_mode then
            self.edit_input = (self.edit_input or "") .. text
            if self.tg.current_chat_id then self.tg:send_typing(self.tg.current_chat_id) end
        elseif self.search_active then
            self:set_search_query(self.search_query .. text, false)
        elseif self.tg.current_chat_id then
            self.model.input = self.model.input .. text
            self.tg:send_typing(self.tg.current_chat_id)
        end
    end

    function messenger_screen:keyboard_backspace()
        if self.edit_mode then
            self.edit_input = ui.remove_last_utf8(self.edit_input)
        elseif self.search_active then
            self:set_search_query(ui.remove_last_utf8(self.search_query), false)
        elseif self.tg.current_chat_id then
            self.model.input = ui.remove_last_utf8(self.model.input)
            local length = helpers.utf16_units(self.model.input)
            while self.draft_emoji_entities and #self.draft_emoji_entities > 0 do
                local last = self.draft_emoji_entities[#self.draft_emoji_entities]
                if last.offset + last.length <= length then break end
                table.remove(self.draft_emoji_entities)
            end
        end
    end

    function messenger_screen:keyboard_enter()
        if self.keyboard.language_menu then return end
        local candidate = self.keyboard and self.keyboard:commit_pinyin()
        if candidate then self:keyboard_text(candidate); return end
        if self.edit_mode then
            local chat_id = self.tg.current_chat_id
            local msg_id = self.edit_message and self.edit_message.id
            if chat_id and msg_id and self.tg:edit_message_text(chat_id, msg_id, self.edit_input) then
                self.edit_mode = false
                self.edit_message = nil
                self.edit_input = ""
            end
        elseif self.search_active then
            self:submit_search()
            if self.keyboard then self.keyboard.visible = false end
        elseif self.tg.current_chat_id then
            if self.model.input ~= "" then
                self:send()
            else
                self.keyboard.visible = false
            end
        end
    end

    function messenger_screen:open_stickers()
        local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
        if not text and not media then return end
        if self.keyboard then self.keyboard.visible = false end
        self.tg.sticker_set_viewer = {home = true, focus = media and 1 or 3, text = text, media = media}
    end

    function messenger_screen:open_picker_category(home, index)
        home.focus = index
        if index == 3 and home.text then self.tg:open_emoji_packs()
        elseif index == 1 and home.media then self.tg:open_recent_stickers()
        elseif index == 2 and home.media then self.tg:open_saved_gifs()
        else return end
        self.tg.sticker_set_viewer.parent = home
    end

    function messenger_screen:activate_picker_item(pack, item)
        if not item then return end
        if item.kind == "emoji_install" then
            self.tg:toggle_emoji_pack(pack)
        elseif item.kind == "emoji_set" then
            self.tg:open_emoji_pack(item.value, pack)
        elseif item.kind == "emoji" then
            local id = self.tg:custom_emoji_id(item.value)
            if not id or not self.tg:chat_send_capabilities(self.model:current_chat()) then return end
            local glyph = item.value.emoji
            if not glyph or glyph == "" then glyph = "🙂" end
            local text = self.model.input
            self.draft_emoji_entities = self.draft_emoji_entities or {}
            self.draft_emoji_entities[#self.draft_emoji_entities + 1] = {["@type"] = "textEntity",
                offset = helpers.utf16_units(text), length = helpers.utf16_units(glyph),
                type = {["@type"] = "textEntityTypeCustomEmoji", custom_emoji_id = id}}
            self.model.input = text .. glyph
            self.tg.sticker_set_viewer = nil
            self.keyboard.visible = true
            self.composer_focus = 1
        elseif item.kind == "search" then
            pack.search_input = true
            self.keyboard.visible, self.keyboard.mode = true, "text"
            self.keyboard:_sync_layout()
        elseif item.kind == "pack" then
            if self.tg:open_sticker_set_by_name(item.value.name) or self.tg:open_sticker_set_by_id(item.value.id) then
                self.tg.sticker_set_viewer.parent = pack
            end
        elseif item.kind == "link" then
            self.tg.sticker_set_viewer = nil
            self.sticker_link_input, self.sticker_link_mode = "", true
        elseif self.tg.current_chat_id then
            local _, media = self.tg:chat_send_capabilities(self.model:current_chat())
            if not media then
                self.tg.action_error = "This chat does not allow stickers or GIFs."
                return
            end
            local sent
            if item.kind == "gif" then
                local gif = item.value
                sent = self.tg:send_gif(self.tg.current_chat_id, gif.animation, gif.query_id, gif.result_id)
            else
                sent = self.tg:send_sticker(self.tg.current_chat_id, item.value)
            end
            if sent then
                if pack.preview then self.tg:close_inline_media() end
                self.tg.sticker_set_viewer = nil
            end
        else
            self.tg.action_error = "Choose a chat to send to."
        end
    end

    function messenger_screen:picker_keypressed(pack, key)
        if pack.home then
            if key == "left" or key == "up" then pack.focus = math.max(pack.media and 1 or 3, pack.focus - 1)
            elseif key == "right" or key == "down" then pack.focus = math.min(pack.text and 3 or 2, pack.focus + 1)
            elseif key == "return" or key == "kpenter" then self:open_picker_category(pack, pack.focus)
            elseif key == "escape" then self.tg.sticker_set_viewer = nil end
            return
        end
        if pack.search_input then
            if key == "f1" and not self.keyboard.language_menu then
                pack.search_input, self.keyboard.visible = nil, false
                self.tg:search_picker_gifs((pack.query or "") .. (self.keyboard:commit_pinyin() or ""))
            else
                local _, result = self.keyboard:keypressed(key)
                if result and result.kind == "text" then pack.query = (pack.query or "") .. result.text
                elseif result and result.kind == "backspace" then pack.query = ui.remove_last_utf8(pack.query or "")
                elseif result and result.kind == "enter" then self:picker_keypressed(pack, "f1")
                elseif not self.keyboard.visible then pack.search_input = nil end
            end
            return
        end
        local confirm = key == "return" or key == "kpenter"
        if pack.preview then
            if key == "escape" then
                pack.preview = nil
                self.tg:close_inline_media()
            elseif confirm then self:activate_picker_item(pack, pack.preview) end
            return
        end
        if key == "escape" then
            self.tg.sticker_set_viewer = pack.parent
            return
        elseif key == "y" or key == "l2" or key == "r2" then
            self:open_stickers()
            return
        end

        local layout = self:picker_layout(pack, ui.width(), ui.height())
        local current = layout.entries[pack.focus]
        if not current then return end
        local target
        if confirm then
            self:activate_picker_item(pack, current)
        elseif key == "x" and (current.kind == "gif" or current.kind == "sticker" or current.kind == "emoji") then
            pack.preview = current
        elseif key == "left" or key == "right" then
            target = layout.entries[current.index + (key == "left" and -1 or 1)]
        elseif key == "up" or key == "down" or key == "pageup" or key == "pagedown" then
            local delta = (key == "up" or key == "pageup") and -1 or 1
            local distance = (key == "pageup" or key == "pagedown") and layout.grid_h - 66 or 0
            local best
            for index = current.row + delta, delta > 0 and #layout.rows or 1, delta do
                local line = layout.rows[index]
                if #line.entries > 0 then
                    target = line.entries[1]
                    for _, item in ipairs(line.entries) do
                        if math.abs(item.x - current.x) < math.abs(target.x - current.x) then target = item end
                    end
                    best = target
                    if math.abs(line.y - current.y) >= distance then break end
                end
            end
            target = best
        end
        if target then
            pack.focus = target.index
            pack.scroll = math.max(0, math.min(layout.max_scroll, pack.scroll, target.y))
            pack.scroll = math.min(layout.max_scroll, math.max(pack.scroll, target.y + target.h - layout.grid_h))
        end
    end

    function messenger_screen:open_file_browser(path)
        path = path or "/userdata/"

        if path:sub(-1) ~= "/" then path = path .. "/" end
        local files = {}

        local handle = io.popen("ls -1pa " .. "'" .. path:gsub("'", "'\\''") .. "' 2>/dev/null")
        if handle then
            for line in handle:lines() do
                if line ~= "" and line ~= "./" and line ~= "../" then
                    local is_dir = line:sub(-1) == "/"
                    local name = is_dir and line:sub(1, -2) or line
                    files[#files+1] = {name = name, is_dir = is_dir, path = path .. name}
                end
            end
            handle:close()
        end

        table.sort(files, function(a, b)
            if a.is_dir ~= b.is_dir then return a.is_dir end
            return a.name:lower() < b.name:lower()
        end)

        if path ~= "/" then
            table.insert(files, 1, {name = "..", is_dir = true, path = path:match("^(.*/)[^/]+/$") or "/"})
        end
        self.file_browser = {path = path, files = files, focus = 1, scroll = 0}
        if self.keyboard then self.keyboard.visible = false end
    end

    function messenger_screen:is_video_post(message, chat)
        if self.tg:video_kind(message) ~= "video" then return false end
        local kind = chat and chat.type
        return message.is_channel_post or (kind and
            (kind.is_channel or kind["@type"] == "chatTypeSupergroup" or kind["@type"] == "chatTypeBasicGroup"))
    end

    function messenger_screen:read_message(message, photo)
        local content = message.content or {}
        local formatted = content.caption or content.text or {text = content.emoji}
        local chat = self.model:current_chat()
        local comment = helpers.comment_count(chat, message) and message or nil
        local is_post = message.is_channel_post or (chat and chat.type and chat.type.is_channel)
        local reply = self.tg:message_reply(message)
        local video_post = self:is_video_post(message, chat)
        if video_post and not photo then photo = {message = message} end
        if (not formatted.text or formatted.text == "") and not comment and not reply and not video_post then return false end
        if comment and not photo then
            if content["@type"] == "messagePhoto" then
                self.tg:ensure_photo(message, true)
                photo = {message = message}
            elseif self.tg:video_kind(message) then
                photo = {message = message}
            end
        end
        if self.keyboard then self.keyboard.visible = false end
        self.text_preview = {message_text = formatted.text or "", entities = formatted.entities,
            title = (content.caption or comment or video_post) and "Post" or "Message",
            scroll = 0, photo = photo, comment = comment, reply_message = reply and message,
            emoji_sticker = content.animated_emoji and content.animated_emoji.sticker,
            post_message = is_post and message or nil}
        return true
    end

    function messenger_screen:can_open_media(message)
        if not self.tg:is_ephemeral_media(message) then return true end
        self.tg.action_error = "Open disappearing media in Telegram."
        self.tg.action_status = ""
        return false
    end

    function messenger_screen:open_photo_message(message, media_index)
        if not self:can_open_media(message) then return end
        local chat = self.model:current_chat()
        local kind = chat and chat.type and chat.type["@type"]
        if kind == "chatTypeSupergroup" or kind == "chatTypeBasicGroup" then
            self.tg:ensure_photo(message, true)
            local photo = {message = message, index = media_index}
            if self:read_message(message, photo) then return end
            local album = helpers.media_album_id(message)
            if album then
                for _, item in ipairs(self.tg:get_messages(chat.id)) do
                    if helpers.media_album_id(item) == album and self:read_message(item, photo) then return end
                end
            end
        end
        self:open_visual_media(message, "photo", media_index)
    end

    function messenger_screen:open_video_message(message)
        local album = self.nav_albums and self.nav_albums[message.id]
        if album then self:open_album_post(album, message)
        elseif self:is_video_post(message, self.model:current_chat()) then self:read_message(message)
        else self:open_video(message) end
    end

    function messenger_screen:open_album_post(album, selected_message)
        local caption = helpers.album_caption(album)
        local first = album[1]
        local index = 1
        for i, message in ipairs(album) do
            if message == selected_message then index = i; break end
        end
        local selected = album[index]
        local chat = self.model:current_chat()
        local is_post = first.is_channel_post or (chat and chat.type and chat.type.is_channel)
        if not self.tg:video_kind(selected) then self.tg:ensure_photo(selected, true) end
        if self.keyboard then self.keyboard.visible = false end
        self.text_preview = {message_text = caption and caption.text or "", entities = caption and caption.entities,
            title = "Post", post_message = is_post and first or nil, scroll = 0, album = album, album_index = index,
            photo = {message = selected},
            comment = helpers.album_comment_target(self.model:current_chat(), album),
            reply_message = helpers.album_reply(self.tg, album)}
    end

    function messenger_screen:open_post_photo()
        local photo = self.text_preview and self.text_preview.photo
        if not photo or not self:can_open_media(photo.message) then return end
        if self.tg:video_kind(photo.message) then self:open_video(photo.message)
        else self:open_visual_media(photo.message, "photo", photo.index) end
        self.fullscreen_media.from_post = true
    end

    function messenger_screen:jump_from_quote()
        local preview = self.text_preview
        local message = preview.reply_message
        local reply = self.tg:message_reply(message)
        if not reply or preview.quote_jump then return end
        local request = self.tg:find_quoted_message(message, reply)
        preview.quote_jump, preview.quote_error = request, nil
        if not request then preview.quote_error = "Quoted message is unavailable." end
        self:update_quote_jump()
    end

    function messenger_screen:update_quote_jump()
        local preview = self.text_preview
        local request = preview and preview.quote_jump
        if not request then return end
        if request.error then
            preview.quote_jump, preview.quote_error = nil, request.error
        elseif request.page or request.loaded then
            if request.chat_id ~= self.tg.current_chat_id then self:select_chat(request.chat_id, true) end
            self.tg:focus_quoted_message(request)
            self.composer_focus, self.sponsor_focus = nil, nil
            self.text_preview = nil
        end
    end

    function messenger_screen:scroll_text_preview(lines, preview)
        preview = preview or self.text_preview
        local max_scroll = preview.max_scroll or 0
        if preview.quote_selected and lines == 1 then
            preview.quote_selected = false
            return
        end
        if lines < 0 and not preview.comment_selected and (preview.scroll or 0) == 0 and preview.quote_available then
            preview.quote_selected = true
            return
        end
        if lines > 0 then preview.quote_selected = false end
        if lines < 0 and preview.comment_selected then preview.comment_selected = false end
        preview.scroll = math.max(0, math.min(max_scroll, (preview.scroll or 0) + lines))
        if lines > 0 and preview.comment and preview.max_scroll and preview.scroll >= max_scroll then
            preview.comment_selected = true
        end
    end

    function messenger_screen:allows_options()
        return not (self.context_menu or self.search_active or self.text_preview or self.html_preview
            or self.fullscreen_media or self.player_controls or self.reaction_menu
            or self.forward_mode or self.edit_mode or self.file_browser or self.sticker_link_mode
            or self.tg.sticker_set_viewer or self.tg.comments_thread or self.sponsor_prompt
            or self.sponsor_focus or (self.keyboard and self.keyboard.visible))
    end

    function messenger_screen:open_options()
        if self.tg.current_chat_id then
            self:open_message_context_menu(self:focused_message())
        else
            local chat = self.model:selected_chat()
            local y = HEADER_HEIGHT
            for _, row in ipairs(self.chat_list_rows or {}) do
                if row.index == self.model.selected then y = row.y; break end
            end
            self.context_menu = {x = 116, y = y, chat = chat, items = self:chat_context_menu_items(chat), index = 1}
            self.menu_anim = 0
        end
    end

    function messenger_screen:open_text_preview(path)
        local lines = {}
        local fh = io.open(path, "r")
        if fh then
            for line in fh:lines() do lines[#lines + 1] = line end
            fh:close()
        end
        self.text_preview = {loading = false, lines = lines, scroll = 0, message = nil, path = path}
    end

    function messenger_screen:open_html_preview(path)
        local html_render = require("src.shared.api.html_render")
        local fh = io.open(path, "r")
        local html = ""
        if fh then
            html = fh:read("*a") or ""
            fh:close()
        end
        local blocks = html_render.parse(html)
        local lines = {}
        for _, b in ipairs(blocks) do
            if b.type == "text" then
                local line = ""
                for _, r in ipairs(b.runs or {}) do line = line .. r.text end
                lines[#lines + 1] = line
            end
        end
        self.html_preview = {loading = false, blocks = blocks, lines = lines, scroll = 0, message = nil, path = path, images = {}}
    end

    function messenger_screen:handle_virtual_keyboard(key)
        if key == "f1" and not self.keyboard.language_menu then
            self:open_stickers()
            return true
        end
        local handled, result = self.keyboard:keypressed(key)
        if not handled then return false end
        if result then
            if result.kind == "text" then
                self:keyboard_text(result.text)
            elseif result.kind == "backspace" then
                self:keyboard_backspace()
            elseif result.kind == "enter" then
                self:keyboard_enter()
            elseif result.kind == "stickers" then
                self:open_stickers()
            elseif result.kind == "files" then
                self:open_file_browser()
            end
        end
        return true
    end

    function messenger_screen:open_message_context_menu(message, pointer_x, pointer_y)
        if self.keyboard then self.keyboard.visible = false end
        local pos = message and self.nav_pos and self.nav_pos[message.id]
        local x = 120
        if self.conv_area_x and self.conv_area_w then
            x = self.conv_area_x + (self.conv_area_w - 240) / 2
        end
        local y = pos and pos.y or 160
        self.context_menu = {
            x = pointer_x or x, y = pointer_y or y, message = message,
            items = self:context_menu_items(message),
            index = 1,
        }
        self.menu_anim = 0
    end

    function messenger_screen:open_reaction_menu(message, comment_thread)
        if self.keyboard then self.keyboard.visible = false end
        if comment_thread then
            local menu = {message = message, items = {}, index = 1, comment_thread = comment_thread}
            self.reaction_menu, self.menu_anim = menu, 0
            self.tg:request_comment_reactions(comment_thread, menu, REACTION_COLUMNS)
            return
        end
        local chosen = {}
        for _, reaction in ipairs(helpers.reaction_summary(message)) do
            if reaction.chosen then chosen[reaction.emoji] = true end
        end
        local items = {}
        for _, emoji in ipairs(REACTION_EMOJIS) do
            items[#items + 1] = {emoji = emoji, chosen = chosen[emoji] == true}
        end
        self.reaction_menu = {message = message, items = items, index = 1}
        self.menu_anim = 0
    end

    function messenger_screen:reaction_keypressed(key)
        local menu = self.reaction_menu
        local count = #menu.items
        local confirm = key == "return" or key == "kpenter" or key == "a"
        local cancel = key == "escape" or key == "b"
        if cancel or (confirm and count > 0) then
            self.reaction_menu = nil
            local thread = menu.comment_thread
            if thread then thread.reaction_menu = nil end
            if not confirm then return end
            local item = menu.items[menu.index]
            if thread then
                self.tg:react_to_comment(thread, menu.message, item)
            else
                self.tg:set_message_reaction(menu.message.chat_id or self.tg.current_chat_id, menu.message.id,
                    item.chosen and "" or item.emoji)
            end
        elseif count > 0 then
            local step = key == "left" and -1 or key == "right" and 1 or key == "up" and -REACTION_COLUMNS
                or key == "down" and REACTION_COLUMNS
            if step then menu.index = math.max(1, math.min(count, menu.index + step)) end
        end
    end

    function messenger_screen:open_video(message)
        if not self:can_open_media(message) then return end
        self.fullscreen_media = {message = message, kind = "video",
            video_note = message.content["@type"] == "messageVideoNote"}
        self.fullscreen_zoom, self.fullscreen_zoom_target = 1, nil
        self.fullscreen_pan_x, self.fullscreen_pan_y = 0, 0
        self.player_controls = nil
        self.tg:request_media_playback(message)
    end

    function messenger_screen:open_audio(message)
        if not self:can_open_media(message) then return end
        self.fullscreen_media = {message = message, kind = "audio"}
        self.player_controls = nil
        self.tg:request_media_playback(message)
    end

    function messenger_screen:audio_player_key(key)
        local message = self.fullscreen_media.message
        local position, duration, playing = self.tg:media_playback_state(message)
        if key == "escape" then
            self:close_media_viewer()
        elseif key == "return" or key == "kpenter" then
            if playing then self.tg:pause_media_playback(message)
            else self.tg:request_media_playback(message) end
        elseif key == "left" or key == "right" or key == "pageup" or key == "pagedown" then
            if duration > 0 then
                local step = (key == "left" or key == "pageup") and -10 or 10
                self.tg:seek_media_playback(message, position + step)
            end
        end
    end

    function messenger_screen:open_visual_media(message, kind, media_index)
        if not self:can_open_media(message) then return end
        if kind == "animation" then

            self.tg:ensure_animation(message, true, true)
        elseif kind == "sticker" then
            self.tg:ensure_sticker(message)
            self.tg:ensure_animated_sticker(message, true)
        elseif self.tg.ensure_photo_hires then
            self.tg:ensure_photo(message, true)
            self.tg:ensure_photo_hires(message)
        end
        self.fullscreen_media = {message = message, kind = kind, media_index = media_index}
        self.fullscreen_zoom, self.fullscreen_zoom_target = 1, nil
        self.fullscreen_drag_start, self.fullscreen_hint_time = nil, nil
        self.fullscreen_pan_x, self.fullscreen_pan_y = 0, 0
        self.fullscreen_pan_target_x, self.fullscreen_pan_target_y = nil, nil
        self.player_controls = nil
    end

    function messenger_screen:pan_fullscreen(dx, dy)
        local image = self:fullscreen_image()
        if not image then return end
        local _, max_x, max_y = self:fullscreen_geometry(image, ui.width(), ui.height())
        local x = (self.fullscreen_pan_target_x or self.fullscreen_pan_x or 0) + dx
        local y = (self.fullscreen_pan_target_y or self.fullscreen_pan_y or 0) + dy
        self.fullscreen_pan_target_x = math.max(-max_x, math.min(max_x, x))
        self.fullscreen_pan_target_y = math.max(-max_y, math.min(max_y, y))
    end

    function messenger_screen:close_media_viewer()
        if self.fullscreen_media and (self.fullscreen_media.kind == "video" or self.fullscreen_media.kind == "audio") then
            self.tg:stop_media_playback(self.fullscreen_media.message)
        end
        if self.fullscreen_media and (self.fullscreen_media.kind == "animation" or self.fullscreen_media.kind == "sticker") then
            self.tg:close_inline_media()
        end
        self.fullscreen_media, self.player_controls = nil, nil
    end

    function messenger_screen:activate_focused_message()
        local message = self:focused_message()
        if not message then return end
        local album = self.nav_albums and self.nav_albums[message.id]
        if album then self:open_album_post(album); return end
        local content = message.content or {}
        local kind = content["@type"]
        if kind == "messageText" then
            self:read_message(message)
        elseif kind == "messagePhoto" then
            self:open_photo_message(message)
        elseif self.tg:video_kind(message) then
            self:open_video_message(message)
        elseif kind == "messageAudio" or kind == "messageVoiceNote" then
            self:open_audio(message)
        elseif kind == "messageAnimation" then
            self:open_visual_media(message, "animation")
        elseif kind == "messageSticker" then
            self:open_visual_media(message, "sticker")
        else
            self:open_message_context_menu(message)
        end
    end

    function messenger_screen:media_nav_list()
        local list = {}
        local source = self.nav_messages or {}
        if self.tg.current_chat_id then
            local messages = self.tg:get_messages(self.tg.current_chat_id)
            if messages and #messages > 0 then source = messages end
        end
        for _, message in ipairs(source) do
            local kind = message.content and message.content["@type"]
            if kind == "messagePhoto" then

                if message.content and message.content.photos then
                    for i, _ in ipairs(message.content.photos) do
                        list[#list + 1] = {message = message, media_index = i, media_kind = "photo"}
                    end
                else
                    list[#list + 1] = {message = message, media_index = 1, media_kind = "photo"}
                end
            elseif self.tg:video_kind(message) then
                list[#list + 1] = {message = message, media_index = 1, media_kind = self.tg:video_kind(message)}
            elseif kind == "messageAnimation" then
                list[#list + 1] = {message = message, media_index = 1, media_kind = "animation"}
            end
        end
        return list
    end

    function messenger_screen:switch_fullscreen_media(delta)
        local fm = self.fullscreen_media
        if not fm then return end
        local list = self:media_nav_list()
        if #list == 0 then return end
        local index = 1
        for i, item in ipairs(list) do
            if item.message.id == fm.message.id and (item.media_index or 1) == (fm.media_index or 1) then
                index = i
                break
            end
        end
        local new_index = math.max(1, math.min(#list, index + delta))
        if new_index == index then return end
        local item = list[new_index]
        if not self:can_open_media(item.message) then return end
        if fm.kind == "video" then self.tg:stop_media_playback(fm.message)
        elseif fm.kind == "animation" or fm.kind == "sticker" then self.tg:close_inline_media() end
        local kind = item.media_kind
        if kind == "video" or kind == "video_note" then
            self.fullscreen_media = {message = item.message, kind = "video", video_note = kind == "video_note", media_index = item.media_index}
            self.tg:request_media_playback(item.message)
        elseif kind == "animation" then
            self:open_visual_media(item.message, "animation", item.media_index)
        else
            self.tg:ensure_photo(item.message, true)
            self.fullscreen_media = {message = item.message, kind = "photo", media_index = item.media_index}
            if self.tg.ensure_photo_hires then self.tg:ensure_photo_hires(item.message) end
            self.fullscreen_pan_x = 0
            self.fullscreen_pan_y = 0
            self.fullscreen_pan_target_x = nil
            self.fullscreen_pan_target_y = nil
        end
        self.fullscreen_zoom, self.fullscreen_zoom_target = 1, nil
        self.fullscreen_drag_start = nil
        self.fullscreen_pan_x = 0
        self.fullscreen_pan_y = 0
        self.player_controls = nil
        self.message_cursor_id = item.message.id
        self:ensure_message_visible(item.message.id)
    end

    function messenger_screen:start_search(show_keyboard)
        self.search_active = true
        self:set_search_query(self.search_query, false)
        if self.keyboard then self.keyboard.visible = show_keyboard end
    end

    function messenger_screen:activate_context_item(cm, item)
        if not item then return end
        if item.action == "search" then
            self:start_search(true)
            return
        end
        if item.action == "clear_selection" then
            self.selected_messages = {}
            return
        end
        if item.action == "forward_selected" then
            self.forward_from_chat_id = self.tg.current_chat_id
            self.forward_mode = true
            return
        end
        if item.action == "recent_stickers" then
            self.tg:open_recent_stickers()
            return
        end
        if cm.chat then
            if item.action == "chat_info" then
                self.wants_profile_chat_id = cm.chat.id
                self.wants_profile_user_id = nil
            elseif item.action == "toggle_chat_pin" then
                self.tg:toggle_chat_pin(cm.chat, item.list)
            elseif item.action == "mute_chat" then
                self.tg:set_chat_muted(cm.chat.id, true)
            elseif item.action == "unmute_chat" then
                self.tg:set_chat_muted(cm.chat.id, false)
            elseif item.action == "archive_chat" then
                self.tg:archive_chat(cm.chat.id, true)
            elseif item.action == "unarchive_chat" then
                self.tg:archive_chat(cm.chat.id, false)
            elseif item.action == "leave_chat" then
                self.tg:leave_chat(cm.chat.id)
            end
            self.context_menu = nil
            return
        end
        if item.action == "open_comments" then
            self:open_post_comments(item.message)
        elseif item.action == "read_message" then
            local album = self.nav_albums and self.nav_albums[cm.message.id]
            if album then self:open_album_post(album, cm.message)
            else self:read_message(cm.message) end
        elseif item.action == "select_message" then
            local id = cm.message.id
            if self.selected_messages[id] then self.selected_messages[id] = nil
            else self.selected_messages[id] = cm.message end
        elseif item.action == "open_sender_profile" then
            self.wants_profile_user_id, self.wants_profile_chat_id = item.user_id, item.chat_id
        elseif item.action == "copy" then
            if not self.tg:message_can_be_shared(cm.message, cm.message.chat_id or self.tg.current_chat_id) then
                self.tg.action_error, self.tg.action_status = "Telegram restricts copying this message.", ""
                return
            end
            local text = cm.message.content and cm.message.content.text and cm.message.content.text.text or ""
            if text ~= "" then love.system.setClipboardText(text) end
        elseif item.action == "react" then
            self:open_reaction_menu(cm.message)
        elseif item.action == "forward" then
            if not self.tg:message_can_be_shared(cm.message, cm.message.chat_id or self.tg.current_chat_id) then
                self.tg.action_error, self.tg.action_status = "Telegram restricts forwarding this message.", ""
                return
            end
            self.selected_messages[cm.message.id] = cm.message
            self.forward_from_chat_id = cm.message.chat_id or self.tg.current_chat_id
            self.forward_mode = true
        elseif item.action == "play_media" then
            if self.tg:video_kind(cm.message) then self:open_video(cm.message)
            else self:open_audio(cm.message) end
        elseif item.action == "view_fullscreen" then
            local msg = cm.message
            local kind = "photo"
            local media_index = 1
            if msg and msg.content then
                local ct = msg.content["@type"]
                if ct == "messageVideo" then kind = "video"
                elseif ct == "messageVideoNote" then kind = "video_note"
                elseif ct == "messageSticker" then kind = "sticker"
                elseif ct == "messageAnimation" then kind = "animation"
                elseif ct == "messagePhoto" then
                    local photos = msg.content.photos
                    if photos and #photos > 0 then
                        media_index = #photos
                    end
                end
            end
            if kind == "video" or kind == "video_note" then return self:open_video(msg) end
            self:open_visual_media(msg, kind, media_index)
        elseif item.action == "open_sticker_pack_by_name" then
            if item.name then
                self.tg:open_sticker_set_by_name(item.name)
            end
        elseif item.action == "open_sticker_pack_by_link" then

            self.sticker_link_input = ""
            self.sticker_link_mode = true
        elseif item.action == "open_sticker_pack" then
            if not self.tg:open_sticker_set(cm.message) then
                self.tg.action_error = "Could not open sticker pack"
            end
        elseif item.action == "download_sticker" then
            self.tg:ensure_sticker(cm.message)
            self.tg.action_status = "Downloading sticker…"
        elseif item.action == "pin" or item.action == "unpin" then
            local chat_id = self.tg.current_chat_id
            local msg_id = cm.message and cm.message.id
            if chat_id and msg_id then
                self.tg:set_message_pinned(chat_id, msg_id, item.action == "pin")
            end
        elseif item.action == "edit" then
            self.edit_mode = true
            self.edit_message = cm.message
            self.edit_input = cm.message.content and cm.message.content.text and cm.message.content.text.text or ""
        elseif item.action == "write_to_author" then
            local sender_id = item.sender_id
            if sender_id then
                self.tg:open_private_chat(sender_id)
            end
        elseif item.action == "preview_text" then
            if cm.message then
                local doc = cm.message.content and cm.message.content.document
                local file = doc and doc.document
                self.text_preview = {loading = true, lines = {}, scroll = 0, message = cm.message, file_id = file and file.id}
                if file and file.id then
                    local fl = file["local"] or (file.file and file.file["local"]) or {}
                    if not (fl.is_downloading_completed) then
                        self.tg:send({["@type"] = "downloadFile", file_id = file.id, priority = 32, offset = 0, limit = 0, synchronous = false}, "text_preview:" .. tostring(file.id))
                    else
                        local path = fl.path
                        if path then self:open_text_preview(path) end
                    end
                end
            end
        elseif item.action == "preview_html" then
            if cm.message then
                local doc = cm.message.content and cm.message.content.document
                local file = doc and doc.document
                self.html_preview = {loading = true, lines = {}, scroll = 0, message = cm.message, file_id = file and file.id}
                if file and file.id then
                    local fl = file["local"] or (file.file and file.file["local"]) or {}
                    if not (fl.is_downloading_completed) then
                        self.tg:send({["@type"] = "downloadFile", file_id = file.id, priority = 32, offset = 0, limit = 0, synchronous = false}, "html_preview:" .. tostring(file.id))
                    else
                        local path = fl.path
                        if path then self:open_html_preview(path) end
                    end
                end
            end
        end
    end

    function messenger_screen:keypressed(key)
        if self.tg.comments_thread and not self.fullscreen_media then
            self:comments_keypressed(self.tg.comments_thread, key)
            return
        end
        if self.tg.sticker_set_viewer then
            self:picker_keypressed(self.tg.sticker_set_viewer, key)
            return
        end
        if self.text_preview and not self.fullscreen_media then
            local page = self.text_preview.page_size or 1
            if key == "escape" then
                self.tg.quote_lookup = nil
                self.text_preview = nil
            elseif (key == "return" or key == "kpenter") and self.text_preview.quote_selected then
                self:jump_from_quote()
            elseif (key == "return" or key == "kpenter") and self.text_preview.comment_selected then
                self:open_post_comments(self.text_preview.comment)
            elseif self.text_preview.album and not self.text_preview.comment_selected and (key == "left" or key == "right") then
                local preview = self.text_preview
                preview.album_index = math.max(1, math.min(#preview.album, preview.album_index + (key == "left" and -1 or 1)))
                preview.photo = {message = preview.album[preview.album_index]}
                if not self.tg:video_kind(preview.photo.message) then self.tg:ensure_photo(preview.photo.message, true) end
                preview.scroll = 0
            elseif (key == "return" or key == "kpenter") and self.text_preview.photo
                and ((self.text_preview.media_end == nil) or self.text_preview.photo_hit) then
                self:open_post_photo()
            elseif key == "up" then self:scroll_text_preview(-1)
            elseif key == "down" then self:scroll_text_preview(1)
            elseif key == "pageup" then self:scroll_text_preview(-page)
            elseif key == "pagedown" then self:scroll_text_preview(page) end
            return
        end
        if key == "escape" and self.search_active and not self.sponsor_prompt and not self.fullscreen_media then
            self.search_active = false
            self:set_search_query("", false)
            if self.keyboard then self.keyboard.visible = false end
            return
        end
        if self.header_focus then
            if key == "left" then self:focus_header("settings")
            elseif key == "right" and self.tg.me then self:focus_header("profile")
            elseif key == "down" or key == "escape" then self.header_focus = nil
            elseif key == "return" or key == "kpenter" then self:activate_header(self.header_focus) end
            return
        end
        if key == "options" and self:allows_options() then
            self:open_options()
            return
        end
        if key == "x" and self:allows_options() then
            local post = self:focused_comment_target()
            if post then self:open_post_comments(post); return end
        end
        if self.sponsor_prompt then
            local prompt = self.sponsor_prompt
            if prompt.report then
                local report = self.tg.channel_sponsor_report
                local options = report and report.options
                if key == "escape" then self.sponsor_prompt = nil end
                if options and #options > 0 then
                    local selected = prompt.selected or 1
                    if key == "up" then prompt.selected = math.max(1, selected - 1) end
                    if key == "down" then prompt.selected = math.min(#options, selected + 1) end
                    if key == "return" or key == "kpenter" then
                        local sent
                        if prompt.peer then
                            sent = self.tg:report_search_sponsor(prompt.peer, options[selected].id)
                        else
                            sent = self.tg:report_channel_sponsor(prompt.chat_id, prompt.message_id,
                                options[selected].id, love.timer.getTime())
                        end
                        if sent then prompt.selected = 1 end
                    end
                end
                return
            elseif prompt.info then
                if key == "escape" then self.sponsor_prompt = nil end
                if key == "down" then prompt.scroll = (prompt.scroll or 0) + 25 end
                if key == "up" then prompt.scroll = math.max(0, (prompt.scroll or 0) - 25) end
                return
            end
            self.sponsor_prompt = nil
            return
        elseif self.sponsor_focus then
            if key == "r2" then self:jump_to_last_read(); return end
            local inline = self.sponsor_inline
            local cache = inline and self.tg:get_channel_sponsors(self.tg.current_chat_id, love.timer.getTime())
            local ad = inline and cache and cache.by_id[inline] or self.sponsor_bot or self.sponsor_ad
            if inline and (key == "up" or key == "down") then
                local delta = key == "up" and -1 or 1
                local selected
                local row_y
                for _, row in ipairs(self.sponsor_rows or {}) do
                    if row.id == inline then row_y = row.y; break end
                end
                if row_y then
                    for _, message in ipairs(self.nav_messages or {}) do
                        local row = self.nav_pos[message.id]
                        if row and (row.y - row_y) * delta > 0
                            and (not selected or (row.y - selected.y) * delta < 0) then
                            selected = {id = message.id, y = row.y}
                        end
                    end
                end
                self.sponsor_focus, self.sponsor_inline = nil, nil
                if selected then
                    self.message_cursor_id = selected.id
                    self:ensure_message_visible(selected.id)
                end
            elseif key == "down" and self.sponsor_ad and not self.sponsor_inline and not self.sponsor_bot then
                self.sponsor_focus = nil
                local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
                self.composer_focus = text and 1 or media and 2 or nil
            elseif key == (self.sponsor_bot and "down" or "up") or key == "escape" then
                self.sponsor_focus = nil
                self.sponsor_inline = nil
                if not inline and not self.sponsor_bot then self.model.scroll = self.sponsor_tail or 0 end
            elseif key == "return" or key == "kpenter" then
                local url = ad and self.tg:click_channel_sponsor(self.tg.current_chat_id, ad.message_id, love.timer.getTime())
                if url then
                    self.text_preview = {title = "Sponsored link", message_text = "Visit this address for more information.",
                        links = {url}, note = "SPgram has no web browser. Enter the address on another device to visit the site.", scroll = 0}
                end
            elseif key == "down" then
                self.model.scroll = 0
            elseif key == "left" or key == "right" then
                self:scroll_chat(key == "left" and -1 or 1)
            elseif key == "x" and ad and ad.can_be_reported then
                local chat_id = self.tg.current_chat_id
                if self.tg:report_channel_sponsor(chat_id, ad.message_id, "", love.timer.getTime()) then
                    self.sponsor_prompt = {chat_id = chat_id, message_id = ad.message_id, report = true}
                end
            elseif key == "y" and ad then
                local info = table.concat({ad.sponsor and ad.sponsor.info or "", ad.additional_info or ""}, "\n")
                if info:match("%S") then self.sponsor_prompt = {info = info} end
            end
            return
        end
        if self.keyboard and self.keyboard.visible then
            if self:handle_virtual_keyboard(key) then return end
        end
        if self.composer_focus and self:allows_options() then
            if key == "up" then self.composer_focus = nil; return end
            if key == "down" then return end
            if key == "left" or key == "right" then
                local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
                if text then
                    local step = (key == "left" and -1 or 1) * (media and 1 or 2)
                    self.composer_focus = math.max(1, math.min(3, self.composer_focus + step))
                else
                    self.composer_focus = media and 2 or nil
                end
                return
            end
            if key == "return" or key == "kpenter" then self:activate_composer(self.composer_focus); return end
        end

        local np = self.tg.now_playing
        if np and not self.fullscreen_media and not self.context_menu then
            local focused = self:focused_message()
            if (key == "return" or key == "kpenter" or key == "a")
                and (not focused or (focused.id == np.id and focused.chat_id == np.chat_id)) then
                local _, _, playing = self.tg:media_playback_state(np)
                if playing then self.tg:pause_media_playback(np)
                else self.tg:request_media_playback(np) end
                return
            elseif key == "left" then
                local pos, dur = self.tg:media_playback_state(np)
                self.tg:seek_media_playback(np, math.max(0, (pos or 0) - 10))
                return
            elseif key == "right" then
                local pos, dur = self.tg:media_playback_state(np)
                self.tg:seek_media_playback(np, math.min(dur or 0, (pos or 0) + 10))
                return
            elseif key == "escape" or key == "b" then
                self.tg:pause_media_playback(np)
                self.tg.now_playing = nil
                return
            end
        end
        if self.file_browser then
            local fb = self.file_browser
            local files = fb.files or {}
            if key == "escape" or key == "b" then
                self.file_browser = nil
                return
            end
            if #files == 0 then return end
            if key == "up" then
                fb.focus = math.max(1, (fb.focus or 1) - 1)
            elseif key == "down" then
                fb.focus = math.min(#files, (fb.focus or 1) + 1)
            elseif key == "a" or key == "return" or key == "kpenter" then
                local sel = files[fb.focus or 1]
                if sel then
                    if sel.is_dir then
                        self:open_file_browser(sel.path)
                    elseif sel.name:match("%.txt$") or sel.name:match("%.log$") or sel.name:match("%.md$") or sel.name:match("%.json$") or sel.name:match("%.lua$") then
                        self:open_text_preview(sel.path)
                    elseif self.tg.current_chat_id then
                        local ext = sel.name:match("%.([^%.]+)$")
                        ext = ext and ext:lower() or ""
                        if ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "gif" or ext == "webp" then
                            self.tg:send_photo(self.tg.current_chat_id, sel.path)
                        else
                            self.tg:send_document(self.tg.current_chat_id, sel.path)
                        end
                        self.tg.action_status = "Sending file…"
                        self.file_browser = nil
                    else
                        self.tg.action_error = "Choose a chat to send to"
                        self.file_browser = nil
                    end
                end
            elseif key == "pageup" then
                fb.focus = math.max(1, (fb.focus or 1) - 10)
            elseif key == "pagedown" then
                fb.focus = math.min(#files, (fb.focus or 1) + 10)
            end
            return
        end
        if key == "f" and self.tg.current_chat_id and not self.keyboard.visible then
            self:open_file_browser()
            return
        end
        if self.html_preview then
            local tp = self.html_preview
            if key == "escape" or key == "b" then
                self.html_preview = nil
                return
            elseif key == "up" then
                tp.scroll = math.max(0, (tp.scroll or 0) - 1)
                return
            elseif key == "down" then
                tp.scroll = (tp.scroll or 0) + 1
                return
            elseif key == "pageup" then
                tp.scroll = math.max(0, (tp.scroll or 0) - 10)
                return
            elseif key == "pagedown" then
                tp.scroll = (tp.scroll or 0) + 10
                return
            end
            return
        end
        if (key == "p" or key == "m") and not self.tg.current_chat_id then
            self.wants_profile_self = true
            return
        end
        if self.sticker_link_mode then
            if key == "return" or key == "kpenter" or key == "a" then
                local link = self.sticker_link_input
                self.sticker_link_input = ""
                self.sticker_link_mode = false
                if link and link ~= "" then
                    self.tg:open_sticker_set_by_link(link)
                end
                return
            elseif key == "escape" or key == "b" then
                self.sticker_link_input = ""
                self.sticker_link_mode = false
                return
            elseif key == "backspace" then
                self.sticker_link_input = self.sticker_link_input:sub(1, -2)
                return
            end
            return
        end
        if self.reaction_menu then
            self:reaction_keypressed(key)
            return
        end
        if self.context_menu then
            local cm = self.context_menu
            local count = #(cm.items or {})
            if key == "up" then
                cm.index = math.max(1, (cm.index or 1) - 1)
                cm.scroll = cm.scroll or 0
                if cm.index <= cm.scroll then cm.scroll = cm.index - 1 end
            elseif key == "down" then
                cm.index = math.min(count, (cm.index or 1) + 1)
                cm.scroll = cm.scroll or 0
                local _, _, _, _, _, max_visible = self:context_menu_bounds(ui.width(), ui.height())
                if cm.index > cm.scroll + max_visible then cm.scroll = cm.index - max_visible end
            elseif key == "return" or key == "kpenter" then
                local item = cm.items and cm.items[cm.index or 1]
                self.context_menu = nil
                self:activate_context_item(cm, item)
            elseif key == "escape" or key == "b" or key == "y" or key == "backspace" or key == "menu" then
                self.context_menu = nil
            end
            return
        end
        if self.fullscreen_media then
            local fm = self.fullscreen_media
            if fm.kind == "audio" then
                self:audio_player_key(key)
            elseif key == "escape" then
                self:close_media_viewer()
                self.fullscreen_zoom = 1.2
                self.fullscreen_drag_start = nil
                self.fullscreen_pan_x = 0
                self.fullscreen_pan_y = 0
                self.fullscreen_pan_target_x = nil
                self.fullscreen_pan_target_y = nil
                self.fullscreen_hint_time = nil
            elseif key == "return" or key == "kpenter" then
                if fm.kind == "video" then

                    local _, _, playing = self.tg:media_playback_state(fm.message)
                    if playing then
                        self.tg:pause_media_playback(fm.message)
                    else
                        self.tg:request_media_playback(fm.message)
                    end
                end

            elseif fm.kind ~= "video" then
                if key == "pageup" or key == "pagedown" then
                    local zoom = self.fullscreen_zoom or 1
                    local target = self.fullscreen_zoom_target or zoom
                    self.fullscreen_zoom_target = math.max(1, math.min(6, target + (key == "pagedown" and 0.5 or -0.5)))
                    self.fullscreen_zoom_start_val = zoom
                    self.fullscreen_zoom_start = love.timer.getTime()
                    if self.fullscreen_zoom_target == 1 then
                        self.fullscreen_pan_target_x, self.fullscreen_pan_target_y = 0, 0
                    end
                elseif key == "up" or key == "down" then
                    self:pan_fullscreen(0, key == "up" and 56 or -56)
                elseif key == "left" or key == "right" then
                    self:pan_fullscreen(key == "left" and 56 or -56, 0)
                elseif (key == "l2" or key == "r2") and not fm.from_post then
                    self:switch_fullscreen_media(key == "l2" and -1 or 1)
                end
            elseif (key == "left" or key == "right") and not fm.from_comments then
                self:switch_fullscreen_media(key == "left" and -1 or 1)
            elseif key == "pageup" or key == "pagedown" then
                local position, duration = self.tg:media_playback_state(fm.message)
                local target = (position or 0) + (key == "pageup" and -10 or 10)
                self.tg:seek_media_playback(fm.message, math.max(0, math.min(duration or 0, target)))
            end
            return
        end
        if self.edit_mode then
            if key == "escape" then
                self.edit_mode = false
                self.edit_message = nil
                self.edit_input = ""
                return
            end
            if key == "return" or key == "kpenter" then
                if love.keyboard.isDown("lshift", "rshift") then
                    self.edit_input = self.edit_input .. "\n"
                    return
                end
                local chat_id = self.tg.current_chat_id
                local msg_id = self.edit_message and self.edit_message.id
                if chat_id and msg_id and self.tg:edit_message_text(chat_id, msg_id, self.edit_input) then
                    self.edit_mode = false
                    self.edit_message = nil
                    self.edit_input = ""
                else
                    return
                end
                return
            end
            if key == "backspace" then
                self.edit_input = ui.remove_last_utf8(self.edit_input)
                return
            end
            return
        end

        if key == "f" and love.keyboard.isDown("lctrl", "rctrl") then
            self:start_search(false)
            return
        end

        if self.search_active then
            local list = self:get_visible_chat_list()
            local selected = list[self.model.selected]
            local peer = selected and selected.sponsored_peer
            if key == "x" and peer then
                if self.tg:report_search_sponsor(peer, "") then
                    self.sponsor_prompt = {peer = peer, report = true}
                end
            elseif key == "y" and peer then
                local info = table.concat({peer.sponsor_info or "", peer.additional_info or ""}, "\n")
                if info:match("%S") then self.sponsor_prompt = {info = info} end
            elseif key == "escape" or key == "b" or key == "menu" then
                self.search_active = false
                self:set_search_query("", false)
            elseif key == "up" or key == "down" then
                local delta = key == "up" and -1 or 1
                if self.tg.current_chat_id then
                    self:move_message_cursor(delta)
                else
                    self.model.selected = math.max(1, math.min(#list, self.model.selected + delta))
                end
            elseif key == "backspace" then
                self:set_search_query(ui.remove_last_utf8(self.search_query), false)
            elseif key == "return" or key == "kpenter" then
                if self.search_query ~= "" and self.search_submitted_query == self.search_query then
                    if self.tg.current_chat_id then self:activate_focused_message()
                    elseif selected then self:select_list_chat(selected) end
                else
                    self:submit_search()
                end
            end
            return
        end

        if self.forward_mode then
            local chat_list = self:get_visible_chat_list()
            if key == "up" then
                self.model.selected = math.max(1, self.model.selected - 1)
            elseif key == "down" then
                self.model.selected = math.min(#chat_list, self.model.selected + 1)
            elseif key == "pageup" then
                self.model.selected = math.max(1, self.model.selected - 5)
            elseif key == "pagedown" then
                self.model.selected = math.min(#chat_list, self.model.selected + 5)
            elseif key == "return" or key == "kpenter" or key == "a" then
                local chat = chat_list[self.model.selected]
                local ids = {}
                for _, msg in pairs(self.selected_messages) do
                    table.insert(ids, msg.id)
                end
                table.sort(ids)
                if chat and self.forward_from_chat_id and #ids > 0 then
                    if not self.tg:forward_messages(chat.id, self.forward_from_chat_id, ids) then
                        return
                    end
                end
                self.forward_mode = false
                self.forward_from_chat_id = nil
                self.selected_messages = {}
            elseif key == "escape" or key == "b" then
                self.forward_mode = false
                self.forward_from_chat_id = nil
                self.selected_messages = {}
            end
            return
        end

        if key == "r2" and self.tg.current_chat_id then
            self:jump_to_last_read()
            return
        elseif key == "l2" or key == "r2" then
            self:switch_list(key == "l2" and -1 or 1)
            return
        end

        if key == "escape" then
            if self.tg.current_chat_id then
                self.tg:close_chat()
                self.composer_focus = nil
                self.model.scroll = 0
            end
            return
        end

        if key == "return" or key == "kpenter" then
            if self.tg.current_chat_id then
                self:activate_focused_message()
            else
                local chat = self.model:selected_chat()
                if chat then self:select_list_chat(chat) end
            end
            return
        end

        if key == "backspace" then
            self:keyboard_backspace()
            return
        end

        if self.tg.current_chat_id then
            if key == "up" then
                local messages = self.tg:get_messages(self.tg.current_chat_id)
                local at_oldest = messages[1] and self.message_cursor_id == messages[1].id
                if self:cursor_index() <= 1 and (at_oldest or self.model.scroll >= self.model.max_scroll - 8)
                    and self.tg:load_more_history(self.tg.current_chat_id) then
                    return
                elseif self.sponsor_bot and self:cursor_index() <= 1 then
                    self.sponsor_focus = true
                elseif self:cursor_index() <= 1 and at_oldest then
                    self:focus_header("settings")
                else
                    self:move_message_cursor(-1)
                end
            elseif key == "down" then
                if self.model.scroll <= (self.sponsor_tail or 0) + 8
                    and self:cursor_index() >= #(self.nav_messages or {})
                    and self.tg:load_newer_history(self.tg.current_chat_id) then
                    return
                elseif self.sponsor_ad and self:cursor_index() >= #(self.nav_messages or {}) then
                    self.sponsor_focus = true
                    self.model.scroll = 0
                elseif self:cursor_index() >= #(self.nav_messages or {}) then
                    local text, media = self.tg:chat_send_capabilities(self.model:current_chat())
                    self.composer_focus = text and 1 or media and 2 or nil
                    self.model.scroll = 0
                else
                    self:move_message_cursor(1)
                end
            elseif key == "left" then
                self:scroll_chat(-1)
            elseif key == "right" then
                self:scroll_chat(1)
            elseif key == "pageup" then
                if self.model.scroll >= self.model.max_scroll - 8
                    and self.tg:load_more_history(self.tg.current_chat_id) then return end
                local step = (self.conv_area_h or 300) * 0.9
                self.model.scroll = math.min(self.model.max_scroll, self.model.scroll + step)
            elseif key == "pagedown" then
                if self.model.scroll <= (self.sponsor_tail or 0) + 8
                    and self.tg:load_newer_history(self.tg.current_chat_id) then return end
                local step = (self.conv_area_h or 300) * 0.9
                self.model.scroll = math.max(0, self.model.scroll - step)
            elseif key == "a" then
                local chat = self.tg.chats_by_id[self.tg.current_chat_id]
                local is_archived = chat and chat.chat_list and chat.chat_list["@type"] == "chatListArchive"
                self.tg:archive_chat(self.tg.current_chat_id, not is_archived)
            end
        else
            if key == "a" then
                self:toggle_archive()
            elseif key == "up" then
                if self.model.selected <= 1 then self:focus_header("settings")
                else self.model.selected = self.model.selected - 1 end
            elseif key == "down" then
                self.model.selected = math.min(#self:get_visible_chat_list(), self.model.selected + 1)
            elseif key == "pageup" then
                self.model.selected = math.max(1, self.model.selected - 5)
            elseif key == "pagedown" then
                self.model.selected = math.min(#self:get_visible_chat_list(), self.model.selected + 5)
            end
        end
    end

    function messenger_screen:get_profile_target()
        if self.tg.current_chat_id then
            local chat = self.tg.chats_by_id[self.tg.current_chat_id] or self.tg.archive_chats_by_id[self.tg.current_chat_id]
            if chat then
                return chat.id, false, self.tg:private_chat_user_id(chat)
            end
        end
        local chat = self.model:selected_chat()
        if chat then
            return chat.id, false, self.tg:private_chat_user_id(chat)
        end
        return nil, false
    end

    function messenger_screen:textinput(text)
        local comments = self.tg.comments_thread
        if comments then
            if comments.compose and not comments.sending then comments.draft = comments.draft .. text end
            return
        end
        local pack = self.tg.sticker_set_viewer
        if pack then
            if pack.search_input then pack.query = (pack.query or "") .. text end
            return
        end
        if self.sticker_link_mode then
            self.sticker_link_input = self.sticker_link_input .. text
            return
        end
        if self.edit_mode then
            self.edit_input = self.edit_input .. text
            if self.tg.current_chat_id then self.tg:send_typing(self.tg.current_chat_id) end
        elseif self.search_active then
            self:set_search_query(self.search_query .. text, false)
        elseif self.tg.current_chat_id then
            self.model.input = self.model.input .. text
            self.tg:send_typing(self.tg.current_chat_id)
        end
    end

    function messenger_screen:wheelmoved(x, y)
        local comments = self.tg.comments_thread
        if comments and not self.fullscreen_media then
            if comments.preview then
                self:scroll_text_preview(-y, comments.preview)
            elseif not comments.compose and not self.context_menu and not self.reaction_menu then
                if y < 0 and comments.has_more and comments.scroll == comments.max_scroll then
                    self.tg:request_comment_page(comments)
                end
                comments.scroll = math.max(0, math.min(comments.max_scroll or 0, (comments.scroll or 0) - y * 42))
            end
            return
        end
        if self.text_preview and not self.fullscreen_media then
            self:scroll_text_preview(-y)
            return
        end
        if self.fullscreen_media then
            local fm = self.fullscreen_media
            if fm.kind == "audio" then return end
            if fm.kind ~= "video" then
                local zoom = self.fullscreen_zoom or 1
                if y > 0 then
                    zoom = math.min(6, zoom + 0.25)
                else
                    zoom = math.max(1, zoom - 0.25)
                end
                self.fullscreen_zoom = zoom

                local mx, my = love.mouse.getPosition()
                local w, h = ui.width(), ui.height()
                local img = self:fullscreen_image()
                if img then
                    local iw, ih = img:getWidth(), img:getHeight()
                    local old_zoom = self.fullscreen_zoom or 1
                    local scale_factor = zoom / old_zoom

                    local dx = (mx - w/2)
                    local dy = (my - h/2)
                    self.fullscreen_pan_x = (self.fullscreen_pan_x or 0) + dx * (1 - 1/scale_factor) * 0.5
                    self.fullscreen_pan_y = (self.fullscreen_pan_y or 0) + dy * (1 - 1/scale_factor) * 0.5
                end
                return
            end
        end
        local pack = self.tg.sticker_set_viewer
        if pack then
            if not pack.home and not pack.preview and not pack.search_input then
                local layout = self:picker_layout(pack, ui.width(), ui.height())
                pack.scroll = math.max(0, math.min(layout.max_scroll, pack.scroll - y * 66))
            end
            return
        end
    function messenger_screen:mousemoved(x, y, dx, dy)
        if self.fullscreen_media and self.fullscreen_drag_start then
            local fm = self.fullscreen_media
            if fm.kind ~= "video" then
                local img = self:fullscreen_image()
                if img then
                    local iw, ih = img:getWidth(), img:getHeight()
                    local w, h = ui.width(), ui.height()
                    local scale = self.fullscreen_zoom or 1
                    local draw_w = iw * scale
                    local draw_h = ih * scale
                    if draw_w > w or draw_h > h then
                        self.fullscreen_pan_x = (self.fullscreen_pan_x or 0) + dx
                        self.fullscreen_pan_y = (self.fullscreen_pan_y or 0) + dy
                        if draw_w > w then
                            self.fullscreen_pan_x = math.max(w - draw_w, math.min(self.fullscreen_pan_x, 0))
                        else
                            self.fullscreen_pan_x = 0
                        end
                        if draw_h > h then
                            self.fullscreen_pan_y = math.max(h - draw_h, math.min(self.fullscreen_pan_y, 0))
                        else
                            self.fullscreen_pan_y = 0
                        end
                    end
                end
            end
        end
    end

    local left_width = self:chat_list_width(ui.width())
        local mx = love.mouse.getX()
        if mx < left_width then
            local chats = self:get_visible_chat_list()
            local step = y > 0 and math.ceil(y) or math.floor(y)
            self.model.selected = math.max(1, math.min(#chats, self.model.selected - step))
        elseif self.tg.current_chat_id then
            self.model.scroll = math.max(0, math.min(self.model.max_scroll, self.model.scroll + y * 48))
        end
    end

    function messenger_screen:mousepressed(x, y, button)
        if self.tg.comments_thread and not self.fullscreen_media then self:comments_at(x, y, button); return end
        if button == 1 then
            local hits = self.text_preview and {self.text_preview.comment_hit} or self.comment_hits
            if not self.fullscreen_media and not self.context_menu then
                for _, hit in ipairs(hits or {}) do
                    if x >= hit.x and x < hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
                        if self.text_preview then
                            self.text_preview.scroll = self.text_preview.max_scroll
                            self.text_preview.comment_selected = true
                        end
                        self:open_post_comments(hit.message)
                        return
                    end
                end
            end
        end
        if self.text_preview and not self.fullscreen_media then
            if button == 2 then self.text_preview = nil
            elseif button == 1 then
                local quote = self.text_preview.quote_hit
                local hit = self.text_preview.photo_hit
                if quote and x >= quote.x and x < quote.x + quote.w and y >= quote.y and y < quote.y + quote.h then
                    self:jump_from_quote()
                elseif hit and x >= hit.x and x < hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
                    self:open_post_photo()
                end
            end
            return
        end
        local jump = self.read_jump_hit
        if button == 1 and not self.sponsor_prompt and not self.fullscreen_media and not self.context_menu and jump
            and x >= jump.x and x < jump.x + jump.w and y >= jump.y and y < jump.y + jump.h then
            self:jump_to_last_read()
            return
        end
        if self.sponsor_prompt or self.sponsor_focus then return end
        if self.fullscreen_media then
            local fm = self.fullscreen_media
            if fm.kind == "audio" then
                if button == 2 then self:close_media_viewer()
                elseif button == 1 and self.player_controls then
                    local control = self.player_controls.button
                    if x >= control.x and x <= control.x + control.w and y >= control.y and y <= control.y + control.h then
                        self:audio_player_key("return")
                    end
                end
                return
            end
            if fm.kind ~= "video" then
                if button == 1 then
                    self.fullscreen_drag_start = {x = x, y = y, pan_x = self.fullscreen_pan_x or 0, pan_y = self.fullscreen_pan_y or 0}
                    return
                elseif button == 2 then

                    self.fullscreen_zoom = 1.2
                    self.fullscreen_pan_x = 0
                    self.fullscreen_pan_y = 0
                    self.fullscreen_drag_start = nil
                    return
                end
            end
        end
        local pack = self.tg.sticker_set_viewer
        if pack then
            if button == 2 then self:picker_keypressed(pack, "escape"); return end
            if button ~= 1 or pack.search_input then return end
            if pack.home then
                for index, card in ipairs(pack.cards or {}) do
                    if x >= card.x and x < card.x + card.w and y >= card.y and y < card.y + card.h then
                        self:open_picker_category(pack, index)
                        return
                    end
                end
                return
            end
            if pack.preview then self:activate_picker_item(pack, pack.preview); return end
            local layout = self:picker_layout(pack, ui.width(), ui.height())
            if y >= layout.grid_y and y < layout.grid_y + layout.grid_h then
                for _, item in ipairs(layout.entries) do
                    local left, top = layout.grid_x + item.x, layout.grid_y + item.y - pack.scroll
                    if x >= left and x < left + item.w and y >= top and y < top + item.h then
                        pack.focus = item.index
                        if item.kind == "sticker" or item.kind == "gif" then pack.preview = item
                        else self:activate_picker_item(pack, item) end
                        break
                    end
                end
            end
            return
        end
        if self.fullscreen_media then
            if button == 1 and (self.fullscreen_media.kind == "photo" or self.fullscreen_media.kind == "animation" or self.fullscreen_media.kind == "video") then
            end
            if button == 1 and self.fullscreen_media.kind == "video" then
                local controls = self.player_controls
                if controls then
                    local toggle = controls.button
                    if x >= toggle.x and x <= toggle.x + toggle.w and y >= toggle.y and y <= toggle.y + toggle.h then
                        local _, _, playing = self.tg:media_playback_state(self.fullscreen_media.message)
                        local _, _, entry = self.tg:media_file_for_message(self.fullscreen_media.message)
                        if playing then
                            self.tg:pause_media_playback(self.fullscreen_media.message)
                        elseif entry and entry.paused then
                            self.tg:resume_media_playback(self.fullscreen_media.message)
                        else
                            self.tg:request_media_playback(self.fullscreen_media.message)
                        end
                        return
                    end
                    local track = controls.track
                    if x >= track.x and x <= track.x + track.w and y >= track.y and y <= track.y + track.h then
                        local _, duration = self.tg:media_playback_state(self.fullscreen_media.message)
                        if duration > 0 then
                            local position = (x - track.x) / track.w * duration
                            self.tg:seek_media_playback(self.fullscreen_media.message, position)
                        end
                        return
                    end
                end
            end
            if button == 1 then
                self:close_media_viewer()
            end
            return
        end
        if self.context_menu then
            local cm = self.context_menu
            local mx, my, menu_w, _, row_h, visible = self:context_menu_bounds(ui.width(), ui.height())
            local row = math.floor((y - my - 6) / row_h) + 1
            if x >= mx and x <= mx + menu_w and row >= 1 and row <= visible then
                self:activate_context_item(cm, cm.items[(cm.scroll or 0) + row])
            end
            self.context_menu = nil
            return
        end
        local w = ui.width()
        local h = ui.height()
        local left_width = self:chat_list_width(w)
        if button == 2 then
            if x < left_width and y >= HEADER_HEIGHT then
                local row = self:chat_row_at(y)
                local chat, index = row and row.chat, row and row.index
                if chat and not chat.navigation then
                    self.model.selected = index
                    self.context_menu = {x = x, y = y, chat = chat, items = self:chat_context_menu_items(chat), index = 1}
                    self.menu_anim = 0
                end
                return
            elseif self.tg.current_chat_id then
                for _, hit in ipairs(self.message_hits or {}) do
                    if x >= hit.x and x <= hit.x + hit.w and y >= hit.y and y <= hit.y + hit.h then
                        self:open_message_context_menu(hit.message, x, y)
                        return
                    end
                end
            end
            return
        end
        if button ~= 1 then return end

        local load_more = self.load_more_button
        if load_more and x >= load_more.x and x <= load_more.x + load_more.w
            and y >= load_more.y and y <= load_more.y + load_more.h then
            if self.tg.current_chat_id then
                self.tg:load_more_history(self.tg.current_chat_id)
            end
            return
        end

        for _, tag_hit in ipairs(self.hashtag_hits or {}) do
            if x >= tag_hit.x and x <= tag_hit.x + tag_hit.w and y >= tag_hit.y and y <= tag_hit.y + tag_hit.h then
                self.search_active = true
                self:set_search_query(tag_hit.tag, true)
                self:submit_search()
                return
            end
        end

        for _, hit in ipairs(self.message_hits or {}) do
            if hit.voice and x >= hit.voice_x and x <= hit.voice_x + hit.voice_w
                and y >= hit.voice_y and y <= hit.voice_y + hit.voice_h then
                self:open_audio(hit.message)
                return
            end
        end

        for _, media_hit in ipairs(self.media_hits or {}) do
            local hit_x = media_hit.media_x or media_hit.x
            local hit_y = media_hit.media_y or media_hit.y
            local hit_w = media_hit.media_w or media_hit.w
            local hit_h = media_hit.media_h or media_hit.h
            local inside = x >= hit_x and x <= hit_x + hit_w and y >= hit_y and y <= hit_y + hit_h
            if inside and media_hit.media_circle then
                local dx, dy = x - (hit_x + hit_w / 2), y - (hit_y + hit_h / 2)
                inside = dx * dx + dy * dy <= (hit_w / 2) ^ 2
            end
            if inside then
                if media_hit.media_kind == "sticker" then
                    if not self.tg:open_sticker_set(media_hit.message) then
                        self:open_visual_media(media_hit.message, "sticker")
                    end
                    return
                elseif media_hit.media_kind == "video" then
                    self:open_video_message(media_hit.message)
                    return
                elseif media_hit.media_kind == "animation" then
                    self:open_visual_media(media_hit.message, "animation")
                    return
                elseif media_hit.media_kind == "audio" or media_hit.media_kind == "voice" then
                    self:open_audio(media_hit.message)
                    return
                end
                if media_hit.media_kind == "photo" then
                    self:open_photo_message(media_hit.message, media_hit.media_index)
                end
                return
            end
        end

        for _, profile_hit in ipairs(self.profile_hits or {}) do
            if x >= profile_hit.x and x <= profile_hit.x + profile_hit.w
                and y >= profile_hit.y and y <= profile_hit.y + profile_hit.h then
                self.wants_profile_user_id = profile_hit.user_id
                return
            end
        end

        local cog = self.face_setup_hit
        if button == 1 and cog and x >= cog.x and x < cog.x + cog.w and y >= cog.y and y < cog.y + cog.h then
            self.wants_face_setup = true
            return
        end
        if y >= 4 and y <= HEADER_HEIGHT - 4 and not self.search_active and not self.forward_mode then
            for _, target in ipairs(self.header_hits or {}) do
                if x >= target.x and x <= target.x + target.w then
                    self:activate_header(target.action)
                    return
                end
            end
        end
        self.header_focus = nil

        if x < left_width and y >= HEADER_HEIGHT then
            local row = self:chat_row_at(y)
            local chat, index = row and row.chat, row and row.index
            if chat then
                self.model.selected = index
                if self.forward_mode and self.forward_from_chat_id then
                    local ids = {}
                    for _, msg in pairs(self.selected_messages) do
                        table.insert(ids, msg.id)
                    end
                    table.sort(ids)
                    if #ids > 0 then
                        if not self.tg:forward_messages(chat.id, self.forward_from_chat_id, ids) then
                            return
                        end
                    end
                    self.forward_mode = false
                    self.forward_from_chat_id = nil
                    self.selected_messages = {}
                    return
                else
                    self.model.input, self.draft_emoji_entities = "", nil
                    self:select_list_chat(chat)
                end
            end
            return
        end

        if self.tg.current_chat_id then
            if x >= left_width and y >= HEADER_HEIGHT and y < HEADER_HEIGHT + CHAT_HEADER_HEIGHT then
                self.wants_profile_chat_id = self.tg.current_chat_id
                return
            end
            for index, cell in pairs(self.composer_bounds or {}) do
                if x >= cell.x and x < cell.x + cell.w and y >= cell.y and y < cell.y + cell.h then
                    self:activate_composer(index)
                    return
                end
            end
        end
    end

    function messenger_screen:keyreleased(key)
        if key == "r2" then
            self.r2_pressed = false
        elseif key == "l2" then
            self.l2_pressed = false
        elseif key == "up" or key == "down" then
            self.scroll_dir = nil
            self.scroll_hold_start = nil
        end
    end
end
