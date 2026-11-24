local ui = require("src.shared.ui.ui_kit")

local function wrapped_lines(font, text, width)
    local lines = {}
    local start = 1
    while true do
        local newline = text:find("\n", start, true)
        local paragraph = text:sub(start, newline and newline - 1 or #text)
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            local ok, _, paragraph_lines = pcall(font.getWrap, font, paragraph, width)
            if ok and type(paragraph_lines) == "table" and #paragraph_lines > 0 then
                for _, line in ipairs(paragraph_lines) do lines[#lines + 1] = line end
            else
                lines[#lines + 1] = paragraph
            end
        end
        if not newline then break end
        start = newline + 1
    end
    return lines
end

local function utf16_units(text)
    local count = 0
    for index = 1, #text do
        local byte = text:byte(index)
        if byte < 128 or byte >= 192 then count = count + (byte >= 240 and 2 or 1) end
    end
    return count
end

local function entity_ranges(text, entities, custom)
    local bounds, ranges = {}, {}
    for _, entity in ipairs(entities or {}) do
        local kind = entity.type and entity.type["@type"]
        local id = kind == "textEntityTypeCustomEmoji" and entity.type.custom_emoji_id
        if (custom and id) or (not custom and (kind == "textEntityTypeUrl" or kind == "textEntityTypeTextUrl")) then
            local offset, length = tonumber(entity.offset), tonumber(entity.length)
            if offset and length and offset >= 0 and length > 0 then
                ranges[#ranges + 1] = {offset, offset + length, id}
            end
        end
    end
    if #ranges == 0 then return end
    local units = 0
    for index = 1, #text do
        local byte = text:byte(index)
        if byte < 128 or byte >= 192 then
            bounds[units] = index
            units = units + (byte >= 240 and 2 or 1)
        end
    end
    bounds[units] = #text + 1
    local links = {}
    for _, range in ipairs(ranges) do
        local first, after = bounds[range[1]], bounds[range[2]]
        if first and after then links[#links + 1] = {first, after - 1, range[3]} end
    end
    return links
end

local function link_ranges(text, entities)
    return entity_ranges(text, entities, false)
end

local function custom_emoji_ranges(text, entities, sticker)
    if sticker and text ~= "" then return {{1, #text, sticker}} end
    local ranges = entity_ranges(text, entities, true)
    if ranges then table.sort(ranges, function(a, b) return a[1] < b[1] end) end
    return ranges
end

local function line_starts(text, lines)
    local starts, cursor = {}, 1
    for index, line in ipairs(lines) do
        if line ~= "" then
            local first, last = text:find(line, cursor, true)
            starts[index] = first
            if last then cursor = last + 1 end
        end
    end
    return starts
end

local function draw_link_line(text, start, links, x, y, font, color, emojis, resolve)
    local cursor = 1
    local function draw_span(first, last)
        if first > last then return end
        ui.text(text:sub(first, last), x + font:getWidth(text:sub(1, first - 1)), y, font, color)
        if not start or not links then return end
        for _, link in ipairs(links) do
            local link_first = math.max(first, link[1] - start + 1)
            local link_last = math.min(last, link[2] - start + 1)
            if link_first <= link_last then
                local offset = x + font:getWidth(text:sub(1, link_first - 1))
                local label = text:sub(link_first, link_last)
                ui.text(label, offset, y, font, ui.colors.accent)
                local bottom = y + font:getHeight() - 1
                love.graphics.setColor(ui.colors.accent)
                love.graphics.line(offset, bottom, offset + font:getWidth(label), bottom)
            end
        end
    end
    if start and emojis and resolve then
        for _, range in ipairs(emojis) do
            local first, last = range[1] - start + 1, range[2] - start + 1
            if first >= cursor and last <= #text then
                local image, tint = resolve(range[3])
                if image then
                    local left = font:getWidth(text:sub(1, first - 1))
                    local width = font:getWidth(text:sub(1, last)) - left
                    local height = font:getHeight()
                    local scale = math.min(width / image:getWidth(), height / image:getHeight())
                    if scale > 0 then
                        draw_span(cursor, first - 1)
                        love.graphics.setColor(tint and color or {1, 1, 1, color[4] or 1})
                        love.graphics.draw(image, x + left + (width - image:getWidth() * scale) / 2,
                            y + (height - image:getHeight() * scale) / 2, 0, scale, scale)
                        cursor = last + 1
                    end
                end
            end
        end
    end
    draw_span(cursor, #text)
end

local function draw_circle_image(image, x, y, diameter)
    local scale = math.max(diameter / image:getWidth(), diameter / image:getHeight())
    local draw_w = image:getWidth() * scale
    local draw_h = image:getHeight() * scale
    love.graphics.stencil(function()
        love.graphics.circle("fill", x + diameter / 2, y + diameter / 2, diameter / 2)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x + (diameter - draw_w) / 2, y + (diameter - draw_h) / 2, 0, scale, scale)
    love.graphics.setStencilTest()
end

local function draw_text_lines(lines, x, y, font, color)
    for index, line in ipairs(lines) do
        ui.text(line, x, y + (index - 1) * font:getHeight(), font, color)
    end
end

local function draw_settings_icon(x, y, color)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(2)
    for index = 0, 7 do
        local angle = index * math.pi / 4
        love.graphics.line(
            x + math.cos(angle) * 6, y + math.sin(angle) * 6,
            x + math.cos(angle) * 10, y + math.sin(angle) * 10
        )
    end
    love.graphics.circle("line", x, y, 6)
    love.graphics.circle("line", x, y, 2)
    love.graphics.setLineWidth(1)
end

local function media_album_id(message)
    local id = message and message.media_album_id
    if not id or tostring(id) == "0" then return nil end
    return tostring(id)
end

local function album_caption(messages)
    for _, message in ipairs(messages) do
        local caption = message.content and message.content.caption
        if caption and caption.text and caption.text ~= "" then return caption end
    end
end

local function comment_count(chat, message)
    local kind = chat and chat.type
    local channel = kind and kind["@type"] == "chatTypeSupergroup" and kind.is_channel
    local info = message and message.interaction_info
    local replies = info and info.reply_info
    if replies and (message.is_channel_post or channel) then
        return math.max(0, tonumber(replies.reply_count) or 0)
    end
end

local function album_comment_target(chat, messages)
    local selected, count
    for _, message in ipairs(messages) do
        local replies = comment_count(chat, message)
        if replies and (not selected or replies > count) then selected, count = message, replies end
    end
    return selected, count
end

local MONTHS_GENITIVE = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

local date_label

local function conversation_items(messages)
    local items = {}
    local last_day
    for _, message in ipairs(messages) do
        local timestamp = tonumber(message.date) or 0
        local day = os.date("%Y-%m-%d", timestamp)
        if day ~= last_day then
            items[#items + 1] = {
                date_label = date_label(timestamp),
            }
            last_day = day
        end
        local content = message.content
        local ctype = content and content["@type"]

        local action_text = nil
        if ctype == "messageChatAddMembers" then
            local members = content.member_user_ids or {}
            action_text = "Members added"
        elseif ctype == "messageChatDeleteMember" then
            action_text = "A member left"
        elseif ctype == "messageChatChangeTitle" then
            action_text = "Chat renamed to " .. tostring(content.title or "")
        elseif ctype == "messageChatChangePhoto" then
            action_text = "Chat photo changed"
        elseif ctype == "messagePinMessage" then
            action_text = "Message pinned"
        elseif ctype == "messageBasicGroupChatCreate" or ctype == "messageSupergroupChatCreate" then
            action_text = "Group created"
        elseif ctype == "messageCall" then
            local duration = tonumber(content.duration) or 0
            local reason = content.discard_reason and content.discard_reason["@type"]
            if reason == "callDiscardReasonMissed" then
                action_text = "Missed call"
            elseif reason == "callDiscardReasonDeclined" then
                action_text = "Call declined"
            elseif reason == "callDiscardReasonDisconnected" then
                action_text = "Call disconnected"
            elseif reason == "callDiscardReasonHungUp" then
                if duration > 0 then
                    action_text = string.format("Call ended (%d:%02d)", math.floor(duration / 60), duration % 60)
                else
                    action_text = "Call ended"
                end
            else
                action_text = "Call"
            end
        elseif ctype == "messageChatSetTtl" then
            action_text = "Auto-delete timer changed"
        end
        if action_text then
            items[#items + 1] = {action_label = action_text}
        else
            local album_id = (ctype == "messagePhoto" or ctype == "messageVideo") and media_album_id(message)
            local previous = items[#items]
            if album_id and previous and previous.album_id == album_id and #previous.messages < 10 then
                previous.messages[#previous.messages + 1] = message
            elseif album_id then
                items[#items + 1] = {album_id = album_id, messages = {message}}
            else
                items[#items + 1] = {message = message}
            end
        end
    end
    for index = #items, 1, -1 do
        local item = items[index]
        if item.messages and #item.messages == 1 then
            item.message = item.messages[1]
            item.messages = nil
        end
    end
    return items
end

date_label = function(timestamp)
    if not timestamp or timestamp <= 0 then return "" end
    local date = os.date("*t", timestamp)
    local day_month = tostring(date.day) .. " " .. MONTHS_GENITIVE[date.month]
    if date.year ~= os.date("*t").year then
        return tostring(date.year) .. " " .. day_month
    end
    return day_month
end

local function hashtag_tokens(text)
    local tokens = {}
    local index = 1
    while index <= #text do
        if text:sub(index, index) == "#" then
            local finish = index + 1
            while finish <= #text do
                local byte = text:byte(finish)
                local is_ascii_word = (byte >= 48 and byte <= 57)
                    or (byte >= 65 and byte <= 90)
                    or (byte >= 97 and byte <= 122)
                    or byte == 95
                if not is_ascii_word and byte < 128 then break end
                finish = finish + 1
            end
            if finish > index + 1 then
                tokens[#tokens + 1] = text:sub(index, finish - 1)
            end
            index = finish
        else
            index = index + 1
        end
    end
    return tokens
end

local function reaction_summary(message)
    local interaction_info = message and message.interaction_info
    local reactions = interaction_info and interaction_info.reactions
    local summary = {}
    for _, reaction in ipairs(reactions and reactions.reactions or {}) do
        local reaction_type = reaction.type or {}
        local type_name = reaction_type["@type"]
        local emoji = type_name == "reactionTypeEmoji" and reaction_type.emoji
            or type_name == "reactionTypePaid" and "⭐"
            or "✨"
        local count = tonumber(reaction.total_count) or 0
        if count > 0 then
            summary[#summary + 1] = {
                emoji = emoji,
                key = type_name == "reactionTypeEmoji" and emoji
                    or (tostring(type_name) .. ":" .. tostring(reaction_type.custom_emoji_id or "")),
                custom_id = reaction_type.custom_emoji_id,
                count = count,
                chosen = reaction.is_chosen == true,
            }
        end
    end
    return summary
end

local function merge_message_reactions(messages)
    local summary, by_emoji = {}, {}
    for _, message in ipairs(messages or {}) do
        for _, reaction in ipairs(reaction_summary(message)) do
            local merged = by_emoji[reaction.key]
            if merged then
                merged.count = merged.count + reaction.count
                merged.chosen = merged.chosen or reaction.chosen
            else
                merged = {
                    emoji = reaction.emoji,
                    custom_id = reaction.custom_id,
                    count = reaction.count,
                    chosen = reaction.chosen,
                }
                by_emoji[reaction.key] = merged
                summary[#summary + 1] = merged
            end
        end
    end
    return summary
end

local function reaction_rows(summary, font, max_width)
    local rows = {}
    local row, row_width = {}, 0
    for _, reaction in ipairs(summary or {}) do
        local count = tostring(reaction.count)
        local width = font:getHeight() + font:getWidth(count) + 18
        if #row > 0 and row_width + 4 + width > max_width then
            rows[#rows + 1] = row
            row, row_width = {}, 0
        end
        row[#row + 1] = {reaction = reaction, count = count, width = width}
        row_width = row_width + width + (#row > 1 and 4 or 0)
    end
    if #row > 0 then rows[#rows + 1] = row end
    return rows
end

local REACTION_GAP = 10

local function reaction_rows_height(rows)
    return #rows > 0 and REACTION_GAP + #rows * 22 or 0
end

local function draw_reaction_rows(rows, x, y, font, colors, resolve)
    local chip_height = 20
    for row_index, row in ipairs(rows or {}) do
        local chip_x = x
        local chip_y = y + (row_index - 1) * 22
        for _, chip in ipairs(row) do
            local reaction = chip.reaction
            ui.rect(chip_x, chip_y, chip.width, chip_height,
                reaction.chosen and colors.accent_dark or colors.header, 10)
            if reaction.chosen then
                ui.outline(chip_x, chip_y, chip.width, chip_height, colors.accent, 10)
            end

            local emoji = reaction.custom_id and {{1, #reaction.emoji, reaction.custom_id}}
            draw_link_line(reaction.emoji, 1, nil, chip_x + 5, chip_y + 3, font, colors.text, emoji, resolve)
            ui.text(chip.count, chip_x + 5 + font:getHeight(), chip_y + 3, font,
                reaction.chosen and colors.text or colors.muted)
            chip_x = chip_x + chip.width + 4
        end
    end
end

local function reaction_rows_width(rows)
    local max_width = 0
    for _, row in ipairs(rows or {}) do
        local width = math.max(0, (#row - 1) * 4)
        for _, chip in ipairs(row) do
            width = width + chip.width
        end
        max_width = math.max(max_width, width)
    end
    return max_width
end

local waveform_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local waveform_values = {}
for index = 1, #waveform_alphabet do
    waveform_values[waveform_alphabet:sub(index, index)] = index - 1
end
local waveform_cache = {}

local function decode_waveform(encoded)
    if type(encoded) ~= "string" or encoded == "" then return {} end
    if waveform_cache[encoded] then return waveform_cache[encoded] end
    local bytes, accumulator, bit_count = {}, 0, 0
    for index = 1, #encoded do
        local value = waveform_values[encoded:sub(index, index)]
        if value then
            accumulator = accumulator * 64 + value
            bit_count = bit_count + 6
            if bit_count >= 8 then
                bit_count = bit_count - 8
                bytes[#bytes + 1] = math.floor(accumulator / (2 ^ bit_count)) % 256
                accumulator = accumulator % (2 ^ bit_count)
            end
        end
    end
    local samples = {}
    accumulator, bit_count = 0, 0
    for _, byte in ipairs(bytes) do
        accumulator = accumulator + byte * (2 ^ bit_count)
        bit_count = bit_count + 8
        while bit_count >= 5 do
            samples[#samples + 1] = accumulator % 32
            accumulator = math.floor(accumulator / 32)
            bit_count = bit_count - 5
        end
    end
    waveform_cache[encoded] = samples
    return samples
end

local function album_reply(tg, messages)
    for _, message in ipairs(messages) do
        if tg:message_reply(message) then return message end
    end
end

local function reply_card_height(font)
    return font:getHeight() * 2 + 8
end

local function draw_reply_card(name, body, x, y, width, font, colors)
    local height = reply_card_height(font)
    ui.rect(x, y, width, height, colors.panel, 3)
    ui.rect(x, y, 2, height, colors.accent)
    ui.text(ui.fit("Reply to " .. name, font, width - 14), x + 7, y + 3, font, colors.accent)
    ui.text(ui.fit(body:gsub("[\r\n]+", " "), font, width - 14),
        x + 7, y + 4 + font:getHeight(), font, colors.muted)
end

return {
    reply_card_height = reply_card_height,
    album_reply = album_reply,
    draw_reply_card = draw_reply_card,
    wrapped_lines = wrapped_lines,
    utf16_units = utf16_units,
    link_ranges = link_ranges,
    custom_emoji_ranges = custom_emoji_ranges,
    line_starts = line_starts,
    draw_link_line = draw_link_line,
    draw_circle_image = draw_circle_image,
    draw_text_lines = draw_text_lines,
    media_album_id = media_album_id,
    album_caption = album_caption,
    comment_count = comment_count,
    album_comment_target = album_comment_target,
    conversation_items = conversation_items,
    date_label = date_label,
    hashtag_tokens = hashtag_tokens,
    reaction_summary = reaction_summary,
    merge_message_reactions = merge_message_reactions,
    reaction_rows = reaction_rows,
    reaction_gap = REACTION_GAP,
    reaction_rows_height = reaction_rows_height,
    reaction_rows_width = reaction_rows_width,
    draw_reaction_rows = draw_reaction_rows,
    decode_waveform = decode_waveform,
}
