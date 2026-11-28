local ui = require("src.shared.ui.ui_kit")
local helpers = require("src.features.chat.ui.chat_screen_helpers")
local draw_circle_image = helpers.draw_circle_image
local decode_waveform = helpers.decode_waveform

return function(messenger_screen)
    function messenger_screen:draw_sender_avatar(user_id, name, x, y, size)
        if not user_id then return end
        local image = self.tg:user_photo_image(user_id, self.tg.current_chat_id)
        if image then
            draw_circle_image(image, x, y, size)
        else
            love.graphics.setColor(ui.colors.accent)
            love.graphics.circle("fill", x + size / 2, y + size / 2, size / 2)
            ui.printf(ui.first_char(name), x, y + 2, size, "center", self.fonts.tiny, ui.colors.text)
        end
    end

    function messenger_screen:album_layout(messages, max_bubble, padding, post_width)
        local columns, gap = math.min(3, #messages), 4
        local cell = math.floor((max_bubble - padding * 2 - gap * (columns - 1)) / columns)
        local cell_h = cell
        for _, message in ipairs(messages) do
            if self.tg:video_kind(message) then cell_h = math.max(50, math.floor(cell * 0.66)); break end
        end
        local rows = math.ceil(#messages / columns)
        local width = columns * cell + (columns - 1) * gap
        local caption = helpers.album_caption(messages)
        local font = self.fonts.normal
        local caption_limit = math.max(width, post_width or 0)
        local lines = caption and helpers.wrapped_lines(font, caption.text, caption_limit) or {}
        local content_width = width
        if caption_limit > width then
            for _, line in ipairs(lines) do content_width = math.max(content_width, font:getWidth(line)) end
            content_width = math.min(content_width, caption_limit)
        end
        return {columns = columns, gap = gap, cell = cell, cell_h = cell_h, w = width,
            content_width = content_width, card_limit = math.max(max_bubble, caption_limit + padding * 2),
            h = rows * cell_h + (rows - 1) * gap, caption = caption, lines = lines,
            caption_h = #lines > 0 and (#lines * font:getHeight() + 6) or 0}
    end

    function messenger_screen:draw_album(messages, area_x, y, area_w, height, max_bubble, padding, small_height, colors, item)
        local first = messages[1]
        local outgoing = self:outgoing(first)
        local media = item and item.album_layout or self:album_layout(messages, max_bubble, padding)
        local grid_w, grid_h = media.w, media.h
        local bubble_w = media.content_width + padding * 2
        local reactions = item and item.reaction_rows or helpers.reaction_rows(
            helpers.merge_message_reactions(messages), self.fonts.tiny, media.card_limit - padding * 2
        )
        bubble_w = math.min(media.card_limit, math.max(
            bubble_w, helpers.reaction_rows_width(reactions) + padding * 2
        ))
        local x = outgoing and (area_x + area_w - bubble_w - 18) or (area_x + 28)
        ui.rect(x, y, bubble_w, height, outgoing and colors.accent_dark or colors.panel_alt, 10)

        local text_y = y + padding
        if not outgoing then
            local sender_id = first.sender_id and first.sender_id["@type"] == "messageSenderUser" and first.sender_id.user_id
            local sender = self.tg:sender_name(first)
            ui.text(ui.fit(sender, self.fonts.small, bubble_w - padding * 2),
                x + padding, text_y, self.fonts.small, colors.accent)
            self:draw_sender_avatar(sender_id, sender, x - 27, text_y, 22)
            if sender_id then
                self.profile_hits = self.profile_hits or {}
                self.profile_hits[#self.profile_hits + 1] = {
                    user_id = sender_id, x = x - 27, y = text_y, w = bubble_w + 27, h = small_height,
                }
            end
            text_y = text_y + small_height + 2
        end

        local forwarded = self.tg:forward_origin(first)
        if forwarded then
            ui.text(ui.fit(forwarded, self.fonts.small, grid_w), x + padding, text_y, self.fonts.small, colors.accent)
            text_y = text_y + small_height + 2
        end

        local reply_message = helpers.album_reply(self.tg, messages)
        if reply_message then
            local reply = self.tg:message_reply(reply_message)
            local parent, status = self.tg:resolve_message_reply(reply_message, reply)
            local name, quote = self.tg:reply_preview(reply, parent, status)
            helpers.draw_reply_card(name, quote, x + padding, text_y, grid_w, self.fonts.tiny, colors, self.custom_emoji_image)
            text_y = text_y + helpers.reply_card_height(self.fonts.tiny) + 4
        end

        for index, message in ipairs(messages) do
            local row = math.floor((index - 1) / media.columns)
            local col = (index - 1) % media.columns
            local cell_x = x + padding + col * (media.cell + media.gap)
            local cell_y = text_y + row * (media.cell_h + media.gap)
            local kind = self.tg:video_kind(message) and "video" or "photo"
            if kind == "video" then
                self:draw_video_card(message, cell_x, cell_y, media.cell, media.cell_h, colors)
            else
                local image = self.tg:photo_image(message)
                ui.rect(cell_x, cell_y, media.cell, media.cell_h, colors.header, 4)
                if image then
                    local scale = math.min(media.cell / image:getWidth(), media.cell_h / image:getHeight())
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(image, cell_x + (media.cell - image:getWidth() * scale) / 2,
                        cell_y + (media.cell_h - image:getHeight() * scale) / 2, 0, scale, scale)
                else
                    ui.printf("Photo", cell_x, cell_y + media.cell_h / 2 - self.fonts.tiny:getHeight() / 2,
                        media.cell, "center", self.fonts.tiny, colors.muted)
                end
            end
            local hit = {message = message, x = cell_x, y = cell_y, w = media.cell, h = media.cell_h,
                media = true, media_kind = kind}
            self.message_hits[#self.message_hits + 1] = hit
            self.media_hits[#self.media_hits + 1] = hit
        end
        local below = text_y + grid_h + 4
        local font = self.fonts.normal
        if media.caption then
            local links = helpers.link_ranges(media.caption.text, media.caption.entities)
            local emoji = helpers.custom_emoji_ranges(media.caption.text, media.caption.entities)
            local starts = (links or emoji) and helpers.line_starts(media.caption.text, media.lines)
            for index, line in ipairs(media.lines) do
                helpers.draw_link_line(line, starts and starts[index], links, x + padding,
                    below + (index - 1) * font:getHeight(), font, colors.text, emoji, self.custom_emoji_image)
            end
        end
        helpers.draw_reaction_rows(reactions, x + padding, below + media.caption_h + helpers.reaction_gap,
            self.fonts.tiny, colors, self.custom_emoji_image, self:reaction_feedback_for(first, reactions))
        local comment, count = helpers.album_comment_target(self.model:current_chat(), messages)
        local footer = y + height - (comment and 27 or 0)
        local time = os.date("%H:%M", first.date or 0)
        local tiny = self.fonts.tiny
        self:draw_message_timestamp(messages[#messages], time, x + bubble_w - padding,
            footer - padding - tiny:getHeight())
        if comment then self:draw_comment_link(comment, count, x + padding, footer, bubble_w - padding * 2) end
        local hit = {message = first, x = x, y = y, w = bubble_w, h = height}
        self.message_hits[#self.message_hits + 1] = hit
        return x - 2, bubble_w + 4
    end

    function messenger_screen:outgoing(message)
        local sender = message and message.sender_id
        return sender and sender["@type"] == "messageSenderUser" and self.tg.me and sender.user_id == self.tg.me.id
    end

    function messenger_screen:format_time(timestamp)
        if not timestamp or timestamp <= 0 then return "" end
        local now = os.time()
        if os.date("%Y-%m-%d", timestamp) == os.date("%Y-%m-%d", now) then
            return os.date("%H:%M", timestamp)
        end
        return os.date("%d.%m", timestamp)
    end

    function messenger_screen:format_bytes(bytes)
        bytes = math.max(0, tonumber(bytes) or 0)
        if bytes >= 1024 * 1024 then
            return string.format("%.1f MB", bytes / (1024 * 1024))
        end
        return string.format("%.0f KB", bytes / 1024)
    end

    function messenger_screen:draw_message_timestamp(message, time, right, y)
        local font, colors = self.fonts.tiny, ui.colors
        local state = self.tg:message_delivery(message)
        local width = state == "read" and 15 or state and 11 or 0
        ui.text(time, right - width - font:getWidth(time), y, font, colors.muted)
        local top = y + math.floor((font:getHeight() - 6) / 2)
        if state == "pending" then
            ui.rect(right - 7, top, 1, 6, colors.muted)
            ui.rect(right - 7, top + 5, 4, 1, colors.muted)
        elseif state == "failed" then
            ui.rect(right - 5, top, 2, 4, colors.red)
            ui.rect(right - 5, top + 5, 2, 2, colors.red)
        elseif state == "sent" or state == "read" then
            local color = state == "read" and colors.accent or colors.muted
            local sent = self.tg.delivery_feedback
            if sent and sent.id == message.id and sent.chat_id == message.chat_id then
                local lift = ui.focus_lift(love.timer.getTime() - sent.at)
                if lift > 0 then
                    top = top - math.floor(lift / 2)
                    color = colors.accent
                    ui.rect(right - 2, top - 1, 2, 2, color)
                    ui.rect(right - 11 - math.floor(lift / 2), top + 2, 2, 2, color)
                    ui.rect(right - 4, top + 8, 1, 1, color)
                end
            end
            local function check(x)
                ui.rect(x, top + 3, 2, 2, color)
                ui.rect(x + 2, top + 4, 2, 2, color)
                for offset = 0, 3 do ui.rect(x + 3 + offset, top + 3 - offset, 2, 2, color) end
            end
            check(right - 8)
            if state == "read" then check(right - 12) end
        end
    end

    function messenger_screen:photo_geometry(message, max_bubble, padding, measure)
        local photo = self.tg:choose_photo_size(message)
        if not photo then return end
        local width, height = math.max(1, tonumber(photo.width) or 96), math.max(1, tonumber(photo.height) or 96)
        local image = not measure and self.tg:photo_image(message) or nil
        local max_width = math.max(96, math.floor(max_bubble / 3 - padding * 2))
        local scale = math.min(1, max_width / width, 180 / height)
        return image, math.max(1, math.floor(width * scale)), math.max(1, math.floor(height * scale))
    end

    function messenger_screen:photo_caption(message)
        local text = self.tg:message_text(message)
        if text == "[photo]" then return "" end
        return text
    end

    function messenger_screen:sticker_geometry(message, max_bubble, padding, measure)
        local content = message and message.content
        if not content or self.tg:is_ephemeral_media(message) then return end
        local doc = content["@type"] == "messageDocument" and content.document
        local sticker = content["@type"] == "messageSticker" and (content.sticker or {})
        if not sticker and not (doc and (doc.file_name or ""):lower():match("%.tgs$")) then return end
        sticker = sticker or {}
        local width, height = tonumber(sticker.width) or 96, tonumber(sticker.height) or 96
        if width <= 0 or height <= 0 then width, height = 96, 96 end
        local image = not measure and self.tg:sticker_image(message) or nil
        local max_width = math.max(48, math.floor((max_bubble - padding * 2) / 3))
        local scale = math.min(1, max_width / width, 136 / height)
        return image, math.max(1, math.floor(width * scale)), math.max(1, math.floor(height * scale)), sticker.emoji or ""
    end

    function messenger_screen:animation_geometry(message, max_bubble, padding, measure)
        local content = message and message.content
        if not content or content["@type"] ~= "messageAnimation" then return end
        local animation = content.animation or {}
        local thumb = animation.thumbnail or {}
        local width, height = tonumber(animation.width), tonumber(animation.height)
        if not width or not height or width <= 0 or height <= 0 then
            width, height = tonumber(thumb.width) or 0, tonumber(thumb.height) or 0
        end
        if width <= 0 or height <= 0 then width, height = 96, 96 end
        local max_width = math.max(48, math.floor((max_bubble - padding * 2) / 3))
        local scale = math.min(1, max_width / width, 136 / height)
        local image = not measure and self.tg:animation_image(message) or nil
        return image, math.max(1, math.floor(width * scale)), math.max(1, math.floor(height * scale))
    end

    function messenger_screen:video_card_size(max_bubble, padding)
        local width = math.min(208, max_bubble - padding * 2)
        return width, math.floor(width * 9 / 16)
    end

    function messenger_screen:draw_video_card(message, x, y, width, height, colors)
        local thumbnail = self.tg:video_thumbnail(message)
        ui.rect(x, y, width, height, colors.bg, 4)
        if thumbnail then
            local scale = math.min((width - 4) / thumbnail:getWidth(), (height - 4) / thumbnail:getHeight())
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(thumbnail, x + (width - thumbnail:getWidth() * scale) / 2,
                y + (height - thumbnail:getHeight() * scale) / 2, 0, scale, scale)
        end
        ui.outline(x, y, width, height, colors.accent_dark, 4)

        local font = self.fonts.tiny
        local badge_w = font:getWidth("VIDEO") + 12
        ui.rect(x + width - badge_w - 6, y + 6, badge_w, font:getHeight() + 6, colors.bg, 3)
        ui.text("VIDEO", x + width - badge_w, y + 9, font, colors.accent)
        local cx, cy = x + width / 2, y + height / 2
        love.graphics.setColor(0.04, 0.07, 0.12, 0.84)
        love.graphics.circle("fill", cx, cy, 17)
        love.graphics.setColor(colors.text)
        love.graphics.polygon("fill", cx - 5, cy - 8, cx - 5, cy + 8, cx + 9, cy)
    end

    function messenger_screen:picker_layout(pack, w, h)
        local width, height = math.min(w - 32, 760), h - 36
        local x, y = math.floor((w - width) / 2), 18
        local grid_w = width - 36
        local columns = math.max(1, math.floor(grid_w / 72))
        local cell_w = grid_w / columns
        local layout = {x = x, y = y, w = width, h = height, grid_x = x + 14, grid_y = y + 72,
            grid_w = grid_w, grid_h = height - 107, entries = {}, rows = {}}
        local top = 0
        local function row(label, height)
            local line = {label = label, y = top, h = height, entries = {}}
            layout.rows[#layout.rows + 1] = line
            top = top + height
            return line
        end
        local function add(line, item, column, width)
            item.x, item.y, item.w, item.h = (column - 1) * cell_w, line.y, width, line.h
            item.row, item.index = #layout.rows, #layout.entries + 1
            layout.entries[#layout.entries + 1] = item
            line.entries[#line.entries + 1] = item
        end
        local function grid(items, kind)
            for index, value in ipairs(items or {}) do
                local column = (index - 1) % columns + 1
                local line = column == 1 and row(nil, 66) or layout.rows[#layout.rows]
                add(line, {kind = kind, value = value}, column, cell_w)
            end
        end

        if pack.emoji_sets then
            local shown = {}
            for _, section in ipairs({{"Installed", pack.installed}, {"Trending", pack.trending}}) do
                row(section[1], 25)
                for _, set in ipairs(section[2]) do
                    if not shown[set.id] then
                        shown[set.id] = true
                        add(row(nil, 31), {kind = "emoji_set", label = set.title or set.name or "Emoji pack", value = set}, 1, grid_w)
                    end
                end
            end
            if not next(shown) then row(pack.loading and "Loading emoji packs…" or pack.error or "No emoji packs", 29) end
        elseif pack.emoji_pack then
            if pack.set_id then
                local label = pack.install_pending and "Updating pack…" or (pack.is_installed and "Remove pack" or "Add pack")
                add(row(nil, 32), {kind = "emoji_install", label = label}, 1, grid_w)
            end
            grid(pack.stickers, "emoji")
            if #pack.stickers == 0 then row(pack.loading and "Loading emoji…" or pack.error or "No emoji in this pack", 29) end
        elseif pack.gifs then
            add(row(nil, 32), {kind = "search", label = "Search GIFs"}, 1, grid_w)
            row(pack.search_query and "Results for " .. pack.search_query or "Recently used", 24)
            grid(pack.animations, "gif")
            if not next(pack.animations or {}) then
                row(pack.error or (pack.loading and "Loading GIFs…" or "No GIFs to show"), 30)
            end
        elseif pack.recent then
            row("Recent stickers", 22)
            grid(pack.stickers, "sticker")
            if not next(pack.stickers or {}) then
                row(pack.error or (pack.loading and "Loading recent stickers…" or "No recently sent stickers"), 26)
            end
            row("Sticker packs", 25)
            for _, set in ipairs(self.tg.installed_sticker_sets or {}) do
                add(row(nil, 30), {kind = "pack", label = set.title or set.name or "Sticker pack", value = set}, 1, grid_w)
            end
            if not next(self.tg.installed_sticker_sets or {}) then row("No installed sticker packs", 26) end
            add(row(nil, 30), {kind = "link", label = "Open pack from link"}, 1, grid_w)
        else
            grid(pack.stickers, "sticker")
            if not next(pack.stickers or {}) then
                row(pack.error or (pack.loading and "Loading sticker pack…" or "No stickers in this pack"), 28)
            end
        end

        layout.max_scroll = math.max(0, top - layout.grid_h)
        pack.scroll = math.max(0, math.min(layout.max_scroll, pack.scroll or 0))
        pack.focus = math.max(1, math.min(#layout.entries, pack.focus or 1))
        return layout
    end

    function messenger_screen:picker_item_image(item, preview)
        if item.kind == "gif" then
            local gif = item.value.animation
            if preview then
                local entry = self.tg:ensure_animation({content = {["@type"] = "messageAnimation", animation = gif}}, nil, true)
                return self.tg:animation_frame(entry)
            end
            local entry = self.tg:animation_thumbnail(gif)
            return entry and entry.image
        elseif item.kind == "sticker" or item.kind == "emoji" then
            local sticker = item.value
            local file = sticker and sticker.sticker
            if not file or not file.id then return end
            local thumbnail = self.tg:media_thumbnail(sticker)
            local thumb = sticker.thumbnail
            local thumb_format = thumb and thumb.format and thumb.format["@type"]
            local has_image_thumb = thumb and thumb.file and (not thumb_format or thumb_format == "thumbnailFormatWebp"
                or thumb_format == "thumbnailFormatJpeg" or thumb_format == "thumbnailFormatPng")
            local thumb_entry = has_image_thumb and self.tg.photos[thumb.file.id]
            if not preview and (thumbnail or (thumb_entry and thumb_entry.status ~= "error")) then return thumbnail end
            local animate = preview
            local message = {id = "picker:" .. file.id, content = {["@type"] = "messageSticker", sticker = sticker}}
            self.tg:ensure_sticker(message, nil, not animate and item.kind ~= "emoji")
            if animate then self.tg:ensure_animated_sticker(message, true)
            elseif item.kind == "emoji" then self.tg:ensure_sticker_frames(file.id, true) end
            local entry = self.tg.stickers[file.id]
            return (animate and self.tg:animation_frame(entry))
                or (entry and (entry.image or (entry.frames and entry.frames[1]))) or thumbnail
        end
    end

    function messenger_screen:draw_voice_note(message, entry, x, y, width, colors)
        local note = message.content and message.content.voice_note or {}
        local samples = decode_waveform(note.waveform)
        local duration = tonumber(note.duration) or 0
        local playing = entry and entry.playing == true
        local progress = 0
        if playing and entry.audio_source then
            local ok, position = pcall(entry.audio_source.tell, entry.audio_source, "seconds")
            if ok and duration > 0 then progress = math.min(1, math.max(0, position / duration)) end
        end

        local center_y = y + 16
        ui.rect(x + 1, y + 3, 26, 26, colors.accent_dark, 5)
        for index, height in ipairs({6, 12, 18, 10, 6}) do
            ui.rect(x + 6 + (index - 1) * 3.5, center_y - height / 2, 2, height, colors.accent, 1)
        end
        ui.text("Voice message", x + 34, y + 1, self.fonts.tiny, colors.text)
        local elapsed = playing and math.floor(progress * duration) or math.floor(duration)
        local time = string.format("%d:%02d", math.floor(elapsed / 60), elapsed % 60)
        local time_w = self.fonts.tiny:getWidth(time)
        ui.text(time, x + width - time_w, y + 21, self.fonts.tiny, colors.muted)

        local graph_x = x + 34
        local graph_w = math.max(24, width - 44 - time_w)
        local count = math.min(48, math.max(1, math.floor(graph_w / 3)))
        local gap = 2
        local bar_w = math.max(1, (graph_w - gap * (count - 1)) / count)
        for index = 1, count do
            local sample_index = math.floor((index - 1) * #samples / count) + 1
            local amplitude = samples[sample_index] and samples[sample_index] / 31 or 0.3
            local bar_h = math.max(3, amplitude * 18)
            local color = index / count <= progress and colors.accent or colors.muted
            ui.rect(graph_x + (index - 1) * (bar_w + gap), y + 26 - bar_h / 2, bar_w, bar_h, color, 1)
        end
    end

    function messenger_screen:draw_music_track(message, entry, x, y, width, colors)
        local _, duration, playing = self.tg:media_playback_state(message)
        if duration == 0 then duration = tonumber(message.content.audio.duration) or 0 end
        local position = entry and entry.play_position or 0
        if entry and entry.audio_source then
            local ok, current = pcall(entry.audio_source.tell, entry.audio_source, "seconds")
            if ok then position = tonumber(current) or position end
        end
        local progress = duration > 0 and math.min(1, math.max(0, position / duration)) or 0
        local center_y = y + 15
        love.graphics.setColor(colors.accent[1], colors.accent[2], colors.accent[3], 1)
        love.graphics.circle("fill", x + 13, center_y, 11)
        love.graphics.setColor(1, 1, 1, 1)
        if playing then
            love.graphics.rectangle("fill", x + 9, center_y - 5, 3, 10)
            love.graphics.rectangle("fill", x + 15, center_y - 5, 3, 10)
        else
            love.graphics.polygon("fill", x + 10, center_y - 6, x + 10, center_y + 6, x + 18, center_y)
        end
        love.graphics.setColor(1, 1, 1, 1)
        local label = self.tg:document_label(message)
        ui.text(ui.fit(label, self.fonts.small, math.max(20, width - 38)),
            x + 32, y + 3, self.fonts.small, colors.text)
        local track_x, track_y, track_w = x + 32, y + 24, math.max(20, width - 40)
        ui.rect(track_x, track_y, track_w, 3, colors.muted, 2)
        if progress > 0 then
            ui.rect(track_x, track_y, track_w * progress, 3, colors.accent, 2)
        end
        local elapsed = math.floor(duration)
        if playing or position > 0 then elapsed = math.floor(position) end
        ui.text(string.format("%d:%02d", math.floor(elapsed / 60), elapsed % 60),
            track_x, y + 30, self.fonts.tiny, colors.muted)
        if entry and entry.audio_error then
            ui.text("Audio error", x + 78, y + 30, self.fonts.tiny, colors.red)
        end
    end

end
