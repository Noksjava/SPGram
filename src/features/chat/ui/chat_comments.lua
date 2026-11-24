local ui = require("src.shared.ui.ui_kit")
local keyboard = require("src.shared.ui.virtual_keyboard")
local helpers = require("src.features.chat.ui.chat_screen_helpers")

local function comment_media(tg, message)
    local kind = message.content and message.content["@type"]
    if kind == "messagePhoto" then return "photo", 146 end
    if tg:video_kind(message) then return "video", 152 end
    if kind == "messageAudio" then return "audio", 53 end
    if kind == "messageVoiceNote" then return "voice", 44 end
    if kind == "messageAnimation" then return "animation", 126 end
    if kind == "messageSticker" then return "sticker", 110 end
end

local function comment_body(tg, message, has_media)
    local content = message and message.content
    local formatted = content and (content.text or content.caption)
    if formatted and formatted.text and formatted.text ~= "" then return formatted.text, formatted.entities end
    return has_media and "" or tg:message_text(message)
end

local function single_line(text)
    return (text or ""):gsub("[\r\n]+", " ")
end

local function draw_comment_avatar(tg, message, name, x, y, f, colors)
    local sender = message.sender_id or {}
    local image
    if sender.user_id then image = tg:user_photo_image(sender.user_id, tg.current_chat_id)
    elseif sender.chat_id then image = tg:chat_photo_image(sender.chat_id) end
    local size = 24
    ui.retro_panel(x, y, size, size, colors.panel, colors.accent_dark)
    if image then
        local scale = math.min(size / image:getWidth(), size / image:getHeight())
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, x + (size - image:getWidth() * scale) / 2,
            y + (size - image:getHeight() * scale) / 2, 0, scale, scale)
    else
        ui.printf(ui.first_char(name), x, y + (size - f.tiny:getHeight()) / 2, size, "center", f.tiny, colors.accent)
    end
end

local function quote_text(text)
    return single_line(text):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function shown_reply(tg, thread, message)
    local reply = tg:message_reply(message)
    if not reply or not tg:is_comment_post_reply(thread, reply) then return reply end
    local quote = reply.quote
    local excerpt = quote and quote.is_manual and quote.text and quote_text(quote.text.text)
    if excerpt and excerpt ~= "" and excerpt ~= quote_text(thread.excerpt or comment_body(tg, thread.post)) then
        return reply
    end
end

return function(screen)
    function screen:open_comment_media(message, kind)
        local thread = self.tg.comments_thread
        if not self:can_open_media(message) then
            if thread then thread.media_error = self.tg.action_error end
            return
        end
        if thread then thread.media_error = nil end
        if kind == "video" then self:open_video(message)
        elseif kind == "audio" or kind == "voice" then self:open_audio(message)
        else self:open_visual_media(message, kind) end
        self.fullscreen_media.from_comments, self.fullscreen_media.from_post = true, true
    end

    function screen:draw_comment_media(message, kind, x, y, width, height, explicit)
        local tg, colors, f = self.tg, ui.colors, self.fonts
        if kind == "audio" or kind == "voice" then
            width = math.min(width, 340)
            ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
            if kind == "voice" then self:draw_voice_note(message, nil, x + 8, y + 3, width - 16, colors)
            else self:draw_music_track(message, nil, x + 8, y + 4, width - 16, colors) end
            return width
        end
        if kind == "video" then
            width = math.min(width, 276)
            self:draw_video_card(message, x, y, width, height, colors)
            return width
        end

        local content = message.content
        local image, label
        if kind == "photo" then
            tg:ensure_photo(message, explicit)
            image, label = tg:photo_image(message, nil, nil, explicit), "Photo"
        elseif kind == "animation" then
            local entry = tg:ensure_animation(message)
            local thumbnail = not (entry and entry.frames) and tg:animation_thumbnail(content.animation)
            image, label = tg:animation_frame(entry) or (thumbnail and thumbnail.image), "GIF"
        else
            tg:ensure_sticker(message, nil, true)
            tg:ensure_animated_sticker(message)
            image, label = tg:sticker_image(message) or tg:media_thumbnail(content.sticker), "Sticker"
        end
        width = math.min(width, kind == "sticker" and 156 or 262)
        ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
        if image then
            local scale = math.min((width - 12) / image:getWidth(), (height - 12) / image:getHeight())
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(image, x + (width - image:getWidth() * scale) / 2,
                y + (height - image:getHeight() * scale) / 2, 0, scale, scale)
        else
            local fallback = kind == "sticker" and content.sticker and content.sticker.emoji
            ui.printf(fallback and fallback ~= "" and fallback or label, x, y + (height - f.normal:getHeight()) / 2,
                width, "center", f.normal, colors.muted)
        end
        return width
    end

    function screen:open_comment_options(thread, message, x, y, primary)
        if not message then return end
        local items = {{label = "Reply", action = "comment_reply"}}
        if primary then
            table.insert(items, 1, {label = "View comment", action = "comment_view"})
        else
            local target = self.tg:quoted_comment_id(thread, message)
            if target then items[#items + 1] = {label = "Jump to quoted comment", action = "comment_jump", target = target} end
            local kind = comment_media(self.tg, message)
            if kind then items[#items + 1] = {label = "Open media", action = "comment_media", media = kind} end
            items[#items + 1] = {label = "React", action = "comment_react"}
        end
        local row = thread.rows and thread.rows[message.id]
        self.context_menu = {comment_thread = thread, message = message, items = items, index = 1,
            x = x or math.floor(ui.width() * 0.43),
            y = y or (row and 92 + row.y - (thread.scroll or 0) or 92)}
        self.menu_anim = 0
    end

    function screen:view_comment(thread, message)
        local kind = comment_media(self.tg, message)
        local text, entities = comment_body(self.tg, message, kind ~= nil)
        local animated = message.content and message.content.animated_emoji
        thread.preview = {title = self.tg:sender_name(message), message_text = text, entities = entities,
            comment_thread = thread, scroll = 0, reply_message = message, reply = shown_reply(self.tg, thread, message),
            emoji_sticker = animated and animated.sticker, comment_media = kind and {message = message, kind = kind}}
    end

    function screen:activate_comment_option(menu, item)
        self.context_menu = nil
        if not item then return end
        if item.action == "comment_jump" then self.tg:jump_to_comment(menu.comment_thread, item.target)
        elseif item.action == "comment_media" then self:open_comment_media(menu.message, item.media)
        elseif item.action == "comment_view" then self:view_comment(menu.comment_thread, menu.message)
        elseif item.action == "comment_react" then self:open_reaction_menu(menu.message, menu.comment_thread)
        else self:compose_comment(menu.comment_thread, menu.message) end
    end

    function screen:focused_comment_target()
        local message = self:focused_message()
        if not message then return end
        local chat = self.model:current_chat()
        local album = self.nav_albums and self.nav_albums[message.id]
        if album then return helpers.album_comment_target(chat, album) end
        local count = helpers.comment_count(chat, message)
        if count then return message, count end
    end

    function screen:open_post_comments(message)
        if not message then return end
        local thread = self.tg:request_comments(message)
        local album = self.nav_albums and self.nav_albums[message.id]
        local caption = album and helpers.album_caption(album)
        thread.excerpt = caption and caption.text
        if self.keyboard then self.keyboard.visible = false end
    end

    function screen:draw_comment_link(message, count, x, y, width)
        local colors, font = ui.colors, self.fonts.tiny
        ui.rect(x, y, width, 1, colors.accent_dark, 0)
        ui.button_hint("{search} — Comments (" .. tostring(count) .. ")", x + 2, y + 6, font, colors.accent, width - 4)
        self.comment_hits = self.comment_hits or {}
        self.comment_hits[#self.comment_hits + 1] = {message = message, x = x, y = y, w = width, h = 26}
    end

    local function comment_index(thread)
        for index, message in ipairs(thread.messages) do
            if message.id == thread.focus_id then return index end
        end
        return #thread.messages
    end

    function screen:compose_comment(thread, reply)
        if not thread.topic_id or thread.sending then return end
        thread.reply_to, thread.compose = reply, true
        thread.keyboard = thread.keyboard or keyboard.new(self.fonts, true)
        thread.keyboard.visible = true
    end

    function screen:comments_keypressed(thread, key)
        if self.reaction_menu then self:reaction_keypressed(key); return end
        local confirm = key == "return" or key == "kpenter"
        local menu = self.context_menu
        if menu and menu.comment_thread == thread then
            if key == "escape" or key == "y" then self.context_menu = nil
            elseif key == "up" or key == "down" then
                menu.index = math.max(1, math.min(#menu.items, menu.index + (key == "up" and -1 or 1)))
            elseif confirm then self:activate_comment_option(menu, menu.items[menu.index]) end
            return
        end
        local preview = thread.preview
        if preview then
            local page = preview.page_size or 1
            if key == "escape" then thread.preview = nil
            elseif confirm and preview.photo_hit and preview.comment_media then
                self:open_comment_media(preview.comment_media.message, preview.comment_media.kind)
            elseif key == "up" then self:scroll_text_preview(-1, preview)
            elseif key == "down" then self:scroll_text_preview(1, preview)
            elseif key == "pageup" then self:scroll_text_preview(-page, preview)
            elseif key == "pagedown" then self:scroll_text_preview(page, preview) end
            return
        end
        if thread.compose then
            local input = thread.keyboard
            if thread.sending then
                if key == "escape" then input.visible = false; thread.compose = false end
                return
            end
            if key == "f1" and not input.language_menu then
                thread.draft = thread.draft .. (input:commit_pinyin() or "")
                self.tg:send_comment(thread)
            elseif key == "escape" and not input.language_menu then
                thread.compose, input.visible = false, false
            else
                local _, result = input:keypressed(key)
                if result and result.kind == "text" then thread.draft = thread.draft .. result.text
                elseif result and result.kind == "backspace" then thread.draft = ui.remove_last_utf8(thread.draft)
                elseif result and result.kind == "enter" then self:comments_keypressed(thread, "f1")
                elseif not input.visible then thread.compose = false end
            end
            return
        end
        if key == "escape" then
            self.tg.comments_thread = nil
            return
        end
        local index = comment_index(thread)
        local focused = not thread.compose_selected and thread.messages[index] or nil
        if key == "y" then
            if focused then self:open_comment_options(thread, focused)
            else self:compose_comment(thread) end
        elseif confirm then
            if focused then
                if thread.error and thread.advance_from == focused.id then
                    self.tg:request_comment_page(thread, focused.id)
                else
                    self:open_comment_options(thread, focused, nil, nil, true)
                end
            elseif thread.error then
                if thread.chat_id then
                    self.tg:request_comment_page(thread)
                else
                    self:open_post_comments(thread.post)
                end
            else
                self:compose_comment(thread)
            end
        elseif key == "up" or key == "down" or key == "pageup" or key == "pagedown" then
            local delta = (key == "up" or key == "pageup") and -1 or 1
            local step = (key == "pageup" or key == "pagedown") and 4 or 1
            local next_index = math.max(1, math.min(#thread.messages, index + delta * step))
            local current = thread.messages[index]
            local row = current and thread.rows and thread.rows[current.id]
            local viewport = thread.viewport or 310
            if step == 1 and row and row.h > viewport then
                local scroll = thread.scroll or 0
                local edge = delta < 0 and row.y or row.y + row.h - viewport
                if not thread.compose_selected and delta * (edge - scroll) > 1 then
                    thread.scroll = delta < 0 and math.max(edge, scroll - 64) or math.min(edge, scroll + 64)
                    return
                end
            end
            if thread.compose_selected then
                if delta < 0 and #thread.messages > 0 then
                    thread.compose_selected = false
                    thread.focus_id, thread.reveal_focus = thread.messages[#thread.messages].id, true
                end
            elseif delta > 0 and current and thread.has_more
                and (index == #thread.messages or current.id == thread.page_cursor) then
                self.tg:request_comment_page(thread, current.id)
            elseif delta > 0 and index == #thread.messages and thread.topic_id and not thread.loading then
                thread.compose_selected = true
            else
                local message = thread.messages[next_index]
                if message and next_index ~= index then thread.focus_id, thread.reveal_focus = message.id, true end
            end
        end
    end

    function screen:draw_post_comments(w, h)
        local thread = self.tg.comments_thread
        if not thread then return end
        local f, colors = self.fonts, ui.colors
        if not thread.compose and thread.keyboard then thread.keyboard.visible = false end
        local width, height = math.min(w - 32, 740), h - 34
        local x, y = math.floor((w - width) / 2), 17
        local viewport_top = y + 74
        local viewport = height - 146
        thread.viewport = viewport
        ui.rect(0, 0, w, h, {0, 0, 0, 0.88}, 0)
        ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
        local count = math.max(#thread.messages, helpers.comment_count(self.model:current_chat(), thread.post) or 0)
        ui.text("Comments (" .. tostring(count) .. ")", x + 14, y + 10, f.subtitle, colors.text)
        ui.button_hint("{back} — Post", x + width - 108, y + 14, f.tiny, colors.muted)
        thread.new_button = nil
        local content = thread.post.content or {}
        local formatted = content.caption or content.text
        local excerpt = thread.excerpt or (formatted and formatted.text) or self.tg:message_text(thread.post)
        ui.retro_panel(x + 12, y + 34, width - 24, 29, colors.panel_alt, colors.accent_dark)
        ui.text(ui.fit(single_line(excerpt), f.small, width - 44),
            x + 22, y + 34 + (29 - f.small:getHeight()) / 2, f.small, colors.muted)

        local row_y, rows = 0, {}
        local previous = thread.rows or {}
        local line_h = f.normal:getHeight() + 3
        local quote_h = helpers.reply_card_height(f.tiny) + 4
        local message_top = 33
        local day_h = f.tiny:getHeight() + 12
        local previous_day
        for _, message in ipairs(thread.messages) do
            local media, media_h = comment_media(self.tg, message)
            local body, entities = comment_body(self.tg, message, media ~= nil)
            local row = previous[message.id]
            local quote = shown_reply(self.tg, thread, message)
            if not row or row.body ~= body or row.width ~= width or row.font ~= f.normal
                or row.quote ~= quote or row.media ~= media then
                local lines = body ~= "" and helpers.wrapped_lines(f.normal, body, width - 80) or {}
                row = {h = #lines * line_h + message_top + 8 + (quote and quote_h or 0) + (media_h and media_h + 5 or 0),
                    lines = lines, body = body, width = width, font = f.normal, quote = quote, media = media, media_h = media_h,
                    day = message.date and os.date("%d %b %Y", message.date),
                    time = message.date and os.date("%H:%M", message.date) or ""}
            end
            local info = message.interaction_info
            if not row.reactions or row.interaction_info ~= info or row.reaction_font ~= f.tiny then
                row.h = row.h - (row.reaction_height or 0)
                row.reactions = helpers.reaction_rows(helpers.reaction_summary(message), f.tiny, width - 80)
                row.reaction_height = helpers.reaction_rows_height(row.reactions)
                row.h = row.h + row.reaction_height
                row.interaction_info, row.reaction_font = info, f.tiny
            end
            local content = message.content or {}
            local sticker = content.animated_emoji and content.animated_emoji.sticker
            if not row.inline_ready or row.entities ~= entities or row.emoji_sticker ~= sticker then
                row.inline_ready, row.entities, row.emoji_sticker = true, entities, sticker
                row.links = helpers.link_ranges(row.body, entities)
                row.emoji = helpers.custom_emoji_ranges(row.body, entities, sticker)
                row.starts = (row.links or row.emoji) and helpers.line_starts(row.body, row.lines)
            end
            row.day_marker = row.day and row.day ~= previous_day and row.day or nil
            if row.day_marker then row_y = row_y + day_h end
            previous_day = row.day
            row.y = row_y
            rows[message.id] = row
            row_y = row_y + row.h + 6
        end
        thread.rows = rows
        local max_scroll = math.max(0, row_y - viewport)
        local focused = thread.focus_id and rows[thread.focus_id]
        if thread.scroll == nil or thread.reveal_focus then
            if focused then
                local scroll = thread.scroll or 0
                if focused.y < scroll then scroll = focused.y
                elseif focused.y + focused.h > scroll + viewport then
                    scroll = math.min(focused.y, focused.y + focused.h - viewport)
                end
                thread.scroll = scroll
            else
                thread.scroll = max_scroll
            end
            thread.reveal_focus = nil
        end
        thread.scroll = math.max(0, math.min(max_scroll, thread.scroll))
        thread.max_scroll = max_scroll
        thread.hits = {}
        local seen = {}
        love.graphics.setScissor(x + 8, viewport_top, width - 16, viewport)
        for _, message in ipairs(thread.messages) do
            local row = rows[message.id]
            local top = viewport_top + row.y - thread.scroll
            if row.day_marker and top >= viewport_top and top - day_h < viewport_top + viewport then
                ui.printf(row.day_marker, x + 12, top - day_h + 4, width - 28, "center", f.tiny, colors.muted)
            end
            if top < viewport_top + viewport and top + row.h > viewport_top then
                local selected = not thread.compose_selected and message.id == thread.focus_id
                ui.retro_panel(x + 12, top, width - 28, row.h,
                    selected and colors.accent_dark or colors.panel_alt, colors.header)
                if selected then ui.focus_corners(x + 13, top + 1, width - 30, row.h - 2, colors.accent) end
                local author = self.tg:sender_name(message)
                draw_comment_avatar(self.tg, message, author, x + 21, top + 5, f, colors)
                local tx = x + 53
                ui.text(ui.fit(author, f.small, width - 145), tx, top + 8, f.small, colors.accent)
                ui.text(row.time, x + width - 25 - f.tiny:getWidth(row.time), top + 8, f.tiny, colors.muted)
                local body_top = top + message_top
                if row.quote then
                    local reply = row.quote
                    local parent = self.tg:comment_reply_parent(thread, reply)
                    local name, quote = self.tg:reply_preview(reply, parent)
                    if parent == thread.post then name = "Channel post" end
                    helpers.draw_reply_card(name, quote, tx, body_top, width - 80, f.tiny, colors)
                    body_top = body_top + quote_h
                end
                if row.media then
                    self:draw_comment_media(message, row.media, tx, body_top, width - 82, row.media_h)
                    body_top = body_top + row.media_h + 5
                end
                for index, line in ipairs(row.lines) do
                    helpers.draw_link_line(line, row.starts and row.starts[index], row.links,
                        tx, body_top + (index - 1) * line_h, f.normal, colors.text, row.emoji, self.custom_emoji_image)
                end
                if #row.reactions > 0 then
                    helpers.draw_reaction_rows(row.reactions, tx, body_top + #row.lines * line_h + helpers.reaction_gap,
                        f.tiny, colors, self.custom_emoji_image)
                end
                local hit_y = math.max(viewport_top, top)
                thread.hits[#thread.hits + 1] = {message = message, x = x + 12, y = hit_y, w = width - 28,
                    h = math.min(top + row.h, viewport_top + viewport) - hit_y}
                if not thread.compose and math.min(top + row.h, viewport_top + viewport) - hit_y
                    >= math.min(row.h, viewport) / 2 then seen[#seen + 1] = message.id end
            end
        end
        love.graphics.setScissor()
        if #seen > 0 and not self.fullscreen_media and not self.context_menu and not self.reaction_menu
            and (not love.window or not love.window.hasFocus or love.window.hasFocus()) then
            self.tg:view_thread_comments(thread, seen)
        end

        if max_scroll > 0 then
            local thumb = math.max(12, viewport * viewport / row_y)
            ui.rect(x + width - 9, viewport_top, 2, viewport, colors.panel_alt)
            ui.rect(x + width - 9, viewport_top + (viewport - thumb) * thread.scroll / max_scroll, 2, thumb, colors.accent)
        end
        local status = thread.send_error or thread.jump_error or thread.reaction_error or thread.media_error or thread.error
            or (thread.jump_id and "Finding quoted comment…")
            or (thread.loading and "Loading comments…")
            or (thread.sending and "Sending comment…") or (#thread.messages == 0 and "No comments yet")
        if status then
            ui.text(ui.fit(status, f.tiny, width - 30), x + 14, y + height - 72, f.tiny,
                (thread.error or thread.send_error or thread.jump_error or thread.reaction_error or thread.media_error)
                    and colors.red or colors.muted)
        end
        if thread.compose then
            local target = thread.reply_to and self.tg:sender_name(thread.reply_to)
            local title = target and ("Reply to " .. target) or "New comment"
            if thread.send_error then title = "Could not send: " .. thread.send_error end
            ui.retro_panel(x + 12, y + 66, width - 24, 75, colors.panel, colors.accent_dark)
            ui.text(ui.fit(title, f.small, width - 48), x + 22, y + 74, f.small, colors.accent)
            if thread.reply_to then
                ui.text(ui.fit(single_line(comment_body(self.tg, thread.reply_to)), f.tiny, width - 48),
                    x + 22, y + 94, f.tiny, colors.muted)
            end
            ui.button_hint("{keyboard} — Send   {back} — Cancel", x + 18, y + 116, f.tiny, colors.muted, width - 36)
            thread.keyboard:draw(thread.draft, thread.reply_to and "Write a reply…" or "Write a comment…")
            return
        end
        if thread.topic_id then
            local bx, by, bw = x + 12, y + height - 54, width - 24
            local fg = thread.compose_selected and colors.bg or colors.accent
            ui.retro_panel(bx, by, bw, 27, thread.compose_selected and colors.accent or colors.panel_alt, colors.accent_dark)
            ui.text("Write a comment", bx + 9, by + (27 - f.small:getHeight()) / 2, f.small, fg)
            ui.button_hint(thread.compose_selected and "{confirm}" or "{options}", bx + bw - 28,
                by + (27 - f.tiny:getHeight()) / 2, f.tiny, fg)
            thread.new_button = {x = bx, y = by, w = bw, h = 27}
        end
        local hint = thread.error and "{confirm} — Retry   {back} — Post"
            or (thread.compose_selected and "{confirm} — Write   ↑ — Comments   {back} — Post"
                or "D-pad — Browse   {confirm} — View or reply   {options} — Options   {back} — Post")
        ui.button_hint(hint, x + 12, y + height - 23, f.tiny, colors.muted, width - 24)
    end

    function screen:comments_at(x, y, button)
        local thread = self.tg.comments_thread
        if self.reaction_menu then
            if button == 2 then self:reaction_keypressed("escape") end
            if button == 1 then
                local menu = self.reaction_menu
                for _, hit in ipairs(menu.hits or {}) do
                    if x >= hit.x and x < hit.x + hit.size and y >= hit.y and y < hit.y + hit.size then
                        menu.index = hit.index
                        self:reaction_keypressed("return")
                        return
                    end
                end
            end
            return
        end
        local menu = self.context_menu
        if menu and menu.comment_thread == thread then
            if button == 1 then
                local left, top, width, _, row_h, visible = self:context_menu_bounds(ui.width(), ui.height())
                local index = math.floor((y - top - 6) / row_h) + 1
                if x >= left and x < left + width and index >= 1 and index <= visible then
                    self:activate_comment_option(menu, menu.items[(menu.scroll or 0) + index])
                    return
                end
            end
            self.context_menu = nil
            return
        end
        local preview = thread.preview
        if preview then
            local hit = preview.photo_hit
            if button == 2 then thread.preview = nil
            elseif button == 1 and hit and x >= hit.x and x < hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
                self:open_comment_media(preview.comment_media.message, preview.comment_media.kind)
            end
            return
        end
        if thread.compose or (button ~= 1 and button ~= 2) then return end
        local new = thread.new_button
        if button == 1 and new and x >= new.x and x < new.x + new.w and y >= new.y and y < new.y + new.h then
            self:compose_comment(thread)
            return
        end
        for _, hit in ipairs(thread.hits or {}) do
            if x >= hit.x and x < hit.x + hit.w and y >= hit.y and y < hit.y + hit.h then
                thread.focus_id, thread.compose_selected = hit.message.id, false
                self:open_comment_options(thread, hit.message, x, y, button == 1)
                return
            end
        end
        if button == 2 then self:comments_keypressed(thread, "escape") end
    end
end
