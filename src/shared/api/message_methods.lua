local json = require("dkjson")
local HISTORY_PAGE_SIZE = 50
local MAX_MESSAGES_PER_CHAT = 500

local function log_to_file(self, message)
    if type(self.log_to_file) == "function" then
        return self:log_to_file(message)
    end
end

local function prune_messages(chat_id, self_ref)
    local list = self_ref.messages[chat_id]
    if not list or #list <= MAX_MESSAGES_PER_CHAT then return end
    local keep = MAX_MESSAGES_PER_CHAT
    local pruned = {}
    for i = #list - keep + 1, #list do
        if i >= 1 then pruned[#pruned + 1] = list[i] end
    end
    self_ref.messages[chat_id] = pruned
end

return function(telegram)
    function telegram:message_delivery(message)
        if not message or not message.is_outgoing or message.is_channel_post or message.scheduling_state then return end
        local chat = self.chats_by_id[message.chat_id] or self.archive_chats_by_id[message.chat_id]
        local kind = chat and chat.type
        if not kind or kind.is_channel or (kind.user_id and self.me and kind.user_id == self.me.id) then return end
        if message.sending_state then
            return message.sending_state["@type"] == "messageSendingStateFailed" and "failed" or "pending"
        end
        local id = tonumber(message.id) or 0
        if id <= 0 or chat.last_read_outbox_message_id == nil then return end
        return id <= (tonumber(chat.last_read_outbox_message_id) or 0) and "read" or "sent"
    end

    function telegram:receipt_chat(message)
        if not message or not message.is_outgoing or message.is_channel_post or message.sending_state
            or message.scheduling_state or (tonumber(message.id) or 0) <= 0 then return end
        local chat = self.chats_by_id[message.chat_id] or self.archive_chats_by_id[message.chat_id]
        local kind = chat and chat.type
        if not kind or kind.is_channel or (kind.user_id and self.me and kind.user_id == self.me.id) then return end
        local name = kind["@type"]
        if name == "chatTypePrivate" or name == "chatTypeBasicGroup" or name == "chatTypeSupergroup" then
            return chat
        end
    end

    function telegram:check_message_receipts(message)
        if not self:receipt_chat(message) then return end
        return self:check_message_options(message)
    end

    function telegram:check_message_options(message)
        if not message or not message.chat_id or (tonumber(message.id) or 0) <= 0 then return end
        local chat = self:receipt_chat(message)
        local lookup = {message = message, receipt_chat = chat ~= nil, user_id = chat and chat.type.user_id,
            deadline = love.timer.getTime() + 15}
        self.message_receipt_generation = (self.message_receipt_generation or 0) + 1
        lookup.request_id = "read_receipts:" .. tostring(self.message_receipt_generation)
        self.message_receipt_lookup = lookup
        lookup.token = self:send({["@type"] = "getMessageProperties", chat_id = message.chat_id,
            message_id = message.id}, lookup.request_id .. ":properties")
        if not lookup.token then lookup.deadline = nil end
        return lookup
    end

    function telegram:fetch_message_receipt_details(lookup)
        if not lookup or lookup ~= self.message_receipt_lookup or not lookup.method then return end
        lookup.token = self:send({["@type"] = lookup.method, chat_id = lookup.message.chat_id,
            message_id = lookup.message.id}, lookup.request_id .. ":details")
        if lookup.token then
            lookup.status = "Loading read receipts…"
            lookup.deadline = love.timer.getTime() + 15
        else lookup.status = "Could not load read receipts." end
        return lookup
    end

    function telegram:handle_message_receipts(kind, extra, response)
        if not extra:match("^read_receipts:") then return false end
        local lookup = self.message_receipt_lookup
        if not lookup or extra ~= lookup.token then return true end
        lookup.token, lookup.deadline = nil, nil
        if kind == "messageProperties" then
            lookup.properties = response
            if lookup.receipt_chat then
                lookup.method = lookup.user_id and response.can_get_read_date and "getMessageReadDate"
                    or not lookup.user_id and response.can_get_viewers and "getMessageViewers"
            end
        elseif kind == "messageViewers" then
            lookup.viewers = response.viewers or {}
            for _, viewer in ipairs(lookup.viewers) do self:ensure_user(viewer.user_id) end
            lookup.status = "No readers reported yet."
        elseif kind == "messageReadDateRead" then
            lookup.viewers = {{user_id = lookup.user_id, view_date = response.read_date}}
            self:ensure_user(lookup.user_id)
        elseif kind == "messageReadDateUnread" then
            lookup.status = "This message has not been read yet."
        elseif kind == "messageReadDateTooOld" then
            lookup.status = "The read time is no longer available."
        elseif kind == "messageReadDateUserPrivacyRestricted" or kind == "messageReadDateMyPrivacyRestricted" then
            lookup.status = "The read time is hidden by Telegram privacy settings."
        else
            lookup.status = "Could not load read receipts."
        end
        return true
    end

    function telegram:message_text(message)
        local content = message and message.content
        if not content then
            return ""
        end
        local kind = content["@type"]
        if kind == "messageText" then
            local text = content.text
            return text and text.text or ""
        elseif kind == "messageAnimatedEmoji" then
            return content.emoji or ""
        elseif kind == "messagePhoto" then
            local caption = content.caption and content.caption.text or ""
            if caption ~= "" then
                return caption
            end
            return "[photo]"
        elseif kind == "messageVideo" or kind == "messageVideoNote" then
            return kind == "messageVideoNote" and "[video message]" or "[video]"
        elseif kind == "messageSticker" then
            local emoji = content.sticker and content.sticker.emoji or ""
            if emoji and emoji ~= "" then
                return emoji .. " sticker"
            end
            return "[sticker]"
        elseif kind == "messageVoiceNote" then
            local note = content.voice_note
            local duration = note and tonumber(note.duration)
            if duration and duration > 0 then
                return string.format("[voice message · %d:%02d]", math.floor(duration / 60), math.floor(duration % 60))
            end
            return "[voice message]"
        elseif kind == "messageDocument" then
            local doc = content.document
            if doc then
                local mime = doc.mime_type or ""
                local fname = doc.file_name or ""
                if mime:match("^video/") or fname:match("%.webm$") or fname:match("%.tgs$") then
                    return "[sticker]"
                end
            end
            return "[file]"
        elseif kind == "messageAudio" then
            return self:document_label(message)
        elseif kind == "messageAnimation" then
            local text = content.caption and content.caption.text
            return text and text ~= "" and text or "[GIF]"
        end
        return "[message]"
    end

    function telegram:message_reply(message)
        local reply = message and message.reply_to
        if reply and reply["@type"] == "messageReplyToMessage" then return reply end
    end

    function telegram:reply_preview(reply, parent, status)
        local quote = reply.quote and reply.quote.text and reply.quote.text.text
        local origin = reply.origin or {}
        local name = parent and self:sender_name(parent)
        if not name and origin.sender_user_id then
            self:ensure_user(origin.sender_user_id)
            name = self:user_name(origin.sender_user_id)
        elseif not name then
            local chat_id = origin.sender_chat_id or origin.chat_id
            local chat = chat_id and (self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id])
            name = (chat and chat.title) or origin.sender_name or origin.author_signature
            if not name or name == "" then name = origin.chat_id and "Channel post" or "Earlier message" end
        end
        if not quote or quote == "" then
            local content = parent and parent.content or reply.content
            local formatted = content and (content.caption or content.text)
            quote = formatted and formatted.text
            if (not quote or quote == "") and content then quote = self:message_text({content = content}) end
        end
        return name, quote and quote ~= "" and quote or status or "Original message unavailable"
    end

    function telegram:resolve_message_reply(message, reply)
        local id = reply.message_id
        local chat_id = tonumber(reply.chat_id)
        if not id or id <= 0 then return end
        if not chat_id or chat_id == 0 then chat_id = message.chat_id end
        if not chat_id then return end
        for _, parent in ipairs(self.messages[chat_id] or {}) do
            if parent.id == id then return parent end
        end
        if chat_id ~= message.chat_id then return end
        local key = string.format("reply_preview:%.0f:%.0f", chat_id, id)
        self.reply_previews = self.reply_previews or {}
        self.reply_preview_order = self.reply_preview_order or {}
        local entry = self.reply_previews[key]
        if not entry then
            entry = {chat_id = chat_id, message_id = id, loading = true}
            self.reply_previews[key] = entry
            self.reply_preview_order[#self.reply_preview_order + 1] = key
            if #self.reply_preview_order > 192 then
                self.reply_previews[table.remove(self.reply_preview_order, 1)] = nil
            end
            self:send({["@type"] = "getMessage", chat_id = chat_id, message_id = id}, key)
        end
        return entry.message, entry.loading and "Loading original…" or nil
    end

    function telegram:handle_reply_preview(kind, extra, object)
        if not extra:match("^reply_preview:%-?%d+:%d+$") then return false end
        local entry = self.reply_previews and self.reply_previews[extra]
        if entry and entry.loading then
            entry.loading = false
            if kind == "message" and object.chat_id == entry.chat_id and object.id == entry.message_id then
                entry.message = object
            end
        end
        return true
    end

    function telegram:update_reply_preview(update)
        if not self.reply_previews then return end
        if update.new_content then
            local key = string.format("reply_preview:%.0f:%.0f", update.chat_id, update.message_id)
            local entry = self.reply_previews[key]
            if entry and entry.message then entry.message.content = update.new_content end
        elseif not update.from_cache then
            for _, id in ipairs(update.message_ids or {}) do
                local key = string.format("reply_preview:%.0f:%.0f", update.chat_id, id)
                local entry = self.reply_previews[key]
                if entry then entry.message, entry.loading = nil, false end
            end
        end
    end

    function telegram:document_label(message)
        local content = message and message.content
        if not content then return "File" end
        local kind = content["@type"]
        local document = kind == "messageDocument" and content.document
        local audio = kind == "messageAudio" and content.audio
        local metadata = document or audio
        if not metadata then return "File" end
        local name = tostring(metadata.file_name or "")
        if name == "" and audio then
            name = tostring(audio.title or "")
            if audio.performer and audio.performer ~= "" then
                name = name ~= "" and (name .. " — " .. audio.performer) or tostring(audio.performer)
            end
        end
        if name == "" then name = audio and "Music" or "Document" end
        if not name:match("%.[%w]+$") then
            local extensions = {
                ["application/pdf"] = ".pdf",
                ["application/zip"] = ".zip",
                ["application/x-rar-compressed"] = ".rar",
                ["application/msword"] = ".doc",
                ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = ".docx",
                ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = ".xlsx",
                ["text/plain"] = ".txt",
                ["text/html"] = ".html",
                ["audio/mpeg"] = ".mp3",
                ["audio/mp3"] = ".mp3",
                ["audio/mp4"] = ".m4a",
                ["audio/x-m4a"] = ".m4a",
                ["audio/aac"] = ".aac",
                ["audio/flac"] = ".flac",
                ["audio/x-flac"] = ".flac",
                ["audio/ogg"] = ".ogg",
                ["application/ogg"] = ".ogg",
                ["audio/opus"] = ".opus",
                ["audio/wav"] = ".wav",
                ["audio/x-wav"] = ".wav",
                ["audio/vnd.wave"] = ".wav",
                ["audio/webm"] = ".webm",
                ["audio/x-ms-wma"] = ".wma",
                ["audio/midi"] = ".mid",
                ["audio/x-midi"] = ".mid",
                ["video/mp4"] = ".mp4",
            }
            name = name .. (extensions[metadata.mime_type] or "")
        end
        return name
    end

    local function displayed_user_name(user)
        if not user then return end
        local name = ((user.first_name or "") .. " " .. (user.last_name or "")):match("^%s*(.-)%s*$")
        if name ~= "" then return name end
        local handles = user.usernames
        return handles and (handles.active_usernames or {})[1]
    end

    function telegram:notification_title(notice)
        local user = notice.user_id and self.users and self.users[notice.user_id]
        local sender = notice.avatar_chat_id and (self.chats_by_id[notice.avatar_chat_id] or self.archive_chats_by_id[notice.avatar_chat_id])
        local chat = self.chats_by_id[notice.chat_id] or self.archive_chats_by_id[notice.chat_id]
        return displayed_user_name(user) or (sender and sender.title) or (chat and chat.title) or notice.title or "New message"
    end

    function telegram:post_title(message)
        local sender = message.sender_id or {}
        local user = sender.user_id and self.users[sender.user_id]
        local chat_id = sender.chat_id or message.chat_id
        local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
        local signature = message.author_signature
        return displayed_user_name(user) or (signature and signature:match("%S") and signature)
            or (chat and chat.title) or "Channel post"
    end

    function telegram:sender_name(message)
        local sender = message and message.sender_id
        if not sender then
            return "Unknown"
        end
        if sender["@type"] == "messageSenderUser" then
            if self.me and sender.user_id == self.me.id then
                return "You"
            end
            self:ensure_user(sender.user_id)
            return self:user_name(sender.user_id)
        elseif sender["@type"] == "messageSenderChat" then
            return self:chat_title(sender.chat_id)
        end
        return "Unknown"
    end

    function telegram:forward_origin(message)
        local info = message and message.forward_info
        if not info then return end
        local origin = info.origin or {}
        local source = info.source or {}
        local source_sender = source.sender_id or {}
        local origin_kind = origin["@type"]
        local user_id = origin_kind ~= "messageOriginChat" and origin_kind ~= "messageOriginChannel"
            and origin.sender_user_id or nil
        local chat_id = origin.sender_chat_id or origin.chat_id
        local source_chat_id = type(source.chat_id) == "number" and source.chat_id < 0 and source.chat_id or nil
        if not chat_id and not user_id and origin_kind ~= "messageOriginHiddenUser"
            and source_sender["@type"] == "messageSenderChat" then
            chat_id = source_sender.chat_id
        end
        local chat = chat_id and (self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id])
        local name = origin.sender_name
        if not name or name == "" then name = source.sender_name end
        if user_id then
            if self.users[user_id] then name = self:user_name(user_id)
            else self:ensure_user(user_id) end
        elseif chat_id then
            self.forward_origin_titles = self.forward_origin_titles or {}
            if chat then
                name = chat.title
            else
                local title = self.forward_origin_titles[chat_id]
                if title == nil then
                    self.forward_origin_titles[chat_id] = false
                    self:send({["@type"] = "getChat", chat_id = chat_id}, "forward_origin:" .. tostring(chat_id))
                end
                if title then name = title end
            end
        end
        if (not name or name == "") and origin.author_signature and origin.author_signature ~= "" then
            name = origin.author_signature
        end
        return name and name ~= "" and "Forwarded from " .. name or "Forwarded", user_id, chat_id, source_chat_id
    end

    function telegram:get_messages(chat_id)
        return self.messages[chat_id] or {}
    end

    function telegram:reading_position_path()
        local base = self.options and self.options.reading_position_file
        local user_id = self.me and self.me.id
        if base and user_id then return base .. "." .. string.format("%.0f", user_id) .. ".json" end
    end

    function telegram:reading_positions()
        local path = self:reading_position_path()
        if not self.reading_bookmarks or (path and path ~= self.reading_bookmark_path) then
            self.reading_bookmarks = {}
            self.reading_bookmark_path = path
            self.reading_positions_dirty = false
            if path then
                local ok, data = pcall(love.filesystem.read, path)
                local saved = ok and data and json.decode(data)
                if type(saved) == "table" then self.reading_bookmarks = saved end
            end
        end
        return self.reading_bookmarks
    end

    function telegram:remember_reading_position(chat_id, message_id)
        if not message_id or message_id <= 0 then return end
        local positions = self:reading_positions()
        local key, value = self:reading_position_key(chat_id), string.format("%.0f", message_id)
        if positions[key] ~= value then
            positions[key] = value
            self.reading_positions_dirty = true
        end
        local now = love.timer.getTime()
        if now >= (self.next_reading_save or 0) then
            self.next_reading_save = now + 3
            self:save_reading_positions()
        end
    end

    function telegram:history_chat(chat_id)
        return self.chats_by_id[chat_id] or (self.archive_chats_by_id or {})[chat_id]
    end

    function telegram:history_peer(chat_id)
        local forum = self.forum
        return forum and forum.chat_id == chat_id and forum.active or self:history_chat(chat_id)
    end

    function telegram:reading_position_key(chat_id)
        local scope = self:forum_message_scope(chat_id)
        local key = string.format("%.0f", chat_id)
        return scope and (key .. ":" .. scope.forum_topic_id) or key
    end

    function telegram:save_reading_positions()
        local path = self.reading_bookmark_path
        if not path or not self.reading_positions_dirty then return end
        local ok, written = pcall(love.filesystem.write, path, json.encode(self.reading_bookmarks))
        if ok and written then self.reading_positions_dirty = false end
    end

    function telegram:open_chat(chat_id, history_loaded)
        if self.current_chat_id and self.current_chat_id ~= chat_id then self:close_chat() end
        self.current_chat_id = chat_id
        if not chat_id then
            return
        end
        for index = #(self.notifications or {}), 1, -1 do
            if self.notifications[index].chat_id == chat_id then
                table.remove(self.notifications, index)
            end
        end
        local chat = self:history_chat(chat_id)
        self:send({["@type"] = "openChat", chat_id = chat_id})
        self:request_chat_send_access(chat)
        self:request_channel_sponsors(chat, love.timer.getTime())
        self:send({["@type"] = "getChat", chat_id = chat_id}, "getChat:" .. tostring(chat_id))
        local kind = chat and chat.type
        if kind and self.forum_groups and self.forum_groups[kind.supergroup_id] then
            self:show_forum_topics(chat_id)
        else
            self:initialize_history(chat_id, history_loaded)
        end
    end

    function telegram:open_forum_topic(topic)
        local forum = self.forum
        if not forum or not topic or forum.by_id[topic.info.forum_topic_id] ~= topic then return false end
        forum.active = topic
        self:initialize_history(forum.chat_id)
        return true
    end

    function telegram:initialize_history(chat_id, history_loaded)
        local chat = self:history_peer(chat_id)
        local unread = chat and (chat.unread_count or 0) > 0
        local read_id = chat and tonumber(chat.last_read_inbox_message_id) or 0
        local saved_id = tonumber(self:reading_positions()[self:reading_position_key(chat_id)])
        local anchor = saved_id or read_id
        local resume = saved_id or (not unread and read_id > 0 and read_id or nil)
        self.history_state[chat_id] = {
            has_more = true, unread_after = not resume and unread and read_id or nil,
            catch_up = anchor > 0, resume_id = resume, fallback_read_id = read_id,
            fallback_unread = unread and chat.unread_count or nil,
            unread_remaining = not resume and unread and read_id == 0 and chat.unread_count or nil,
        }
        self.messages[chat_id] = {}
        if not history_loaded then self:request_history(chat_id, "initial", anchor, anchor > 0 and -15 or 0) end
    end

    function telegram:find_quoted_message(message, reply)
        local id = tonumber(reply.message_id)
        local chat_id = tonumber(reply.chat_id)
        if not chat_id or chat_id == 0 then chat_id = message.chat_id or self.current_chat_id end
        if not id or id <= 0 or not chat_id then return end
        if chat_id == self.current_chat_id then
            for _, parent in ipairs(self.messages[chat_id] or {}) do
                if parent.id == id then return {chat_id = chat_id, id = id, loaded = true} end
            end
        end
        self.history_sequence = (self.history_sequence or 0) + 1
        local token = "quote_history:" .. self.history_sequence
        local request = {chat_id = chat_id, id = id, token = token}
        if not self:send(self:history_request(chat_id, id, 0), token) then return end
        self.quote_lookup = request
        return request
    end

    function telegram:handle_quote_history(kind, extra, response)
        if not extra:match("^quote_history:%d+$") then return false end
        local request = self.quote_lookup
        if not request or request.token ~= extra then return true end
        self.quote_lookup = nil
        if kind == "messages" then
            for _, item in ipairs(response.messages or {}) do
                if item.id == request.id then request.page = response.messages; return true end
            end
        end
        request.error = "Quoted message is unavailable."
        return true
    end

    function telegram:focus_quoted_message(request)
        local state = self.history_state[request.chat_id] or {}
        self.history_state[request.chat_id] = state
        if request.page then
            table.sort(request.page, function(a, b) return a.id < b.id end)
            self.messages[request.chat_id] = request.page
            state.token, state.error, state.jump, state.loading = nil, nil, nil, false
            state.resume_id, state.unread_after, state.unread_remaining = nil, nil, nil
            state.has_more, state.has_newer, state.catch_up = true, true, true
        end
        state.keep_position_id = nil
        state.initial_focus_id = request.id
    end

    function telegram:request_history(chat_id, direction, message_id, offset)
        local state = self.history_state[chat_id]
        self.history_sequence = (self.history_sequence or 0) + 1
        state.token = string.format("history:%.0f:%d", chat_id, self.history_sequence)
        state.request_anchor, state.request_offset = message_id, offset
        state.loading, state.error, state.direction = true, nil, direction
        state.retry_on_reconnect, state.network_retry = nil, nil
        state.history_deadline = love.timer.getTime() + 12
        self:send(self:history_request(chat_id, message_id, offset), state.token)
        return true
    end

    function telegram:history_request(chat_id, message_id, offset)
        local topic = self:forum_message_scope(chat_id)
        if topic then
            return {["@type"] = "getForumTopicHistory", chat_id = chat_id, forum_topic_id = topic.forum_topic_id,
                from_message_id = message_id, offset = offset, limit = HISTORY_PAGE_SIZE}
        end
        return {["@type"] = "getChatHistory", chat_id = chat_id, from_message_id = message_id,
            offset = offset, limit = HISTORY_PAGE_SIZE, only_local = false}
    end

    function telegram:jump_to_newest(chat_id)
        local state = chat_id == self.current_chat_id and self.history_state[chat_id]
        if not state or (state.jump and state.jump.newest) then return false end
        state.jump_error = nil
        state.jump = {newest = true, deadline = love.timer.getTime() + 12}
        local peer = self:history_peer(chat_id)
        local messages = self.messages[chat_id]
        if peer and peer.last_message and messages and messages[#messages]
            and messages[#messages].id == peer.last_message.id then
            self:finish_read_jump(chat_id, state, {messages = messages})
            return true
        end
        return self:request_history(chat_id, "newest", 0, 0)
    end

    function telegram:jump_to_last_read(chat_id)
        if not chat_id or self.current_chat_id ~= chat_id then return false end
        local state = self.history_state[chat_id] or {}
        if state.loading then return false end
        self.history_state[chat_id] = state
        local chat = self:history_peer(chat_id)
        local read_id = chat and tonumber(chat.last_read_inbox_message_id) or 0
        if read_id <= 0 then
            local unread = chat and (tonumber(chat.unread_count) or 0) or 0
            if unread == 0 then return self:jump_to_newest(chat_id) end
            state.jump_error = nil
            if state.unread_divider_id then
                for _, message in ipairs(self.messages[chat_id] or {}) do
                    if message.id == state.unread_divider_id then
                        state.initial_focus_id, state.keep_position_id = message.id, nil
                        return true
                    end
                end
            end
            self.messages[chat_id] = {}
            state.resume_id, state.unread_after, state.unread_remaining = nil, 0, unread
            state.fallback_unread, state.fallback_read_id, state.unread_divider_id = unread, 0, nil
            return self:request_history(chat_id, "initial", 0, 0)
        end
        state.jump_error = nil
        state.jump = {read_id = read_id, deadline = love.timer.getTime() + 12}
        local messages = self.messages[chat_id]
        for _, message in ipairs(messages or {}) do
            if message.id == read_id then
                self:finish_read_jump(chat_id, state, {messages = messages})
                return true
            end
        end
        return self:request_history(chat_id, "last_read", read_id, 0)
    end

    function telegram:fail_read_jump(state)
        local destination = state.jump.newest and "newest" or "last-read"
        state.jump, state.loading, state.token = nil, false, nil
        state.jump_error = "Could not load the " .. destination .. " message."
    end

    function telegram:check_history_timeout(now)
        local state = self.current_chat_id and self.history_state[self.current_chat_id]
        if not state or not state.loading or not state.history_deadline then return end
        if now < (state.jump and state.jump.deadline or state.history_deadline) then return end
        if state.jump then
            self:fail_read_jump(state)
        else
            state.loading, state.token = false, nil
            state.error = "Loading messages timed out. Try again."
            if not state.network_retry then
                state.retry_on_reconnect = true
                if self.last_network_route and not self:reconnect_network(now) then self.network_reopen_pending = true end
            end
        end
    end

    function telegram:finish_read_jump(chat_id, state, response)
        local read_id, newest = state.jump.read_id, state.jump.newest
        local page, seen = {}, {}
        for _, message in ipairs(response.messages or {}) do
            if message.id and (newest or message.id <= read_id) and not seen[message.id] then
                seen[message.id] = true
                page[#page + 1] = message
            end
        end
        table.sort(page, function(a, b) return a.id < b.id end)
        local target = page[#page]
        if not target then self:fail_read_jump(state); return end
        self.messages[chat_id] = page
        state.jump, state.loading, state.error, state.token = nil, false, nil, nil
        state.has_more = true
        local chat = self:history_peer(chat_id)
        local latest = chat and chat.last_message and chat.last_message.id
        state.has_newer = not newest and (not latest or target.id < latest)
        state.catch_up = state.has_newer
        state.resume_id, state.unread_after, state.unread_remaining, state.keep_position_id = nil, nil, nil, nil
        state.initial_focus_id = target.id
    end

    function telegram:load_more_history(chat_id)
        local state = self.history_state[chat_id]
        if not state or state.loading then return false end
        if state.error then
            return self:request_history(chat_id, state.direction, state.request_anchor, state.request_offset)
        end
        if not state.has_more then return false end
        local oldest = (self.messages[chat_id] or {})[1]
        return self:request_history(chat_id, oldest and "older" or "initial",
            oldest and oldest.id or (state.resume_id or state.unread_after or 0),
            not oldest and state.catch_up and -15 or 0)
    end

    function telegram:load_newer_history(chat_id)
        local state = self.history_state[chat_id]
        local messages = self.messages[chat_id] or {}
        if not state or state.loading or not state.has_newer or #messages == 0 then return false end
        return self:request_history(chat_id, "newer", messages[#messages].id, -(HISTORY_PAGE_SIZE - 1))
    end

    function telegram:close_chat()
        local chat_id = self.current_chat_id
        self.current_chat_id = nil
        self.forum = nil
        self.sponsor_link = nil
        if chat_id then
            self:save_reading_positions()
            self:cancel_chat_avatars(chat_id)
            self:release_audio()
            self.comments_thread = nil
            self.history_state[chat_id] = nil
            for _, msg in ipairs(self.messages[chat_id] or {}) do
                pcall(self.pause_media_playback, self, msg)
            end
            self.messages[chat_id] = nil
            if self.viewed_message_ids then self.viewed_message_ids[chat_id] = nil end
            local prefix = string.format("%.0f:", chat_id)
            for _, key in ipairs({"photo_by_message", "photo_hires_by_message", "sticker_by_message",
                "animation_by_message", "video_by_message", "video_note_by_message", "audio_by_message", "voice_by_message"}) do
                for id in pairs(self[key] or {}) do
                    if type(id) == "string" and id:sub(1, #prefix) == prefix then self[key][id] = nil end
                end
            end
            self:send({["@type"] = "closeChat", chat_id = chat_id})
        end
    end

    function telegram:send_sticker(chat_id, sticker)
        local file = sticker and sticker.sticker
        if not chat_id or not file or not file.id then
            self.action_error = "This sticker is unavailable."
            return false
        end
        local request = self:send({
            ["@type"] = "sendMessage",
            chat_id = chat_id,
            input_message_content = {
                ["@type"] = "inputMessageSticker",
                sticker = {
                    ["@type"] = "inputSticker",
                    sticker = {["@type"] = "inputFileId", id = file.id},
                    width = sticker.width or 0,
                    height = sticker.height or 0,
                },
                emoji = sticker.emoji or "",
            },
        }, "send_sticker")
        if not request then return false end
        self.action_error = ""
        self.action_status = "Sending sticker…"
        return true
    end

    function telegram:send_gif(chat_id, animation, query_id, result_id)
        local file = animation and animation.animation
        local inline = query_id and result_id
        if not chat_id or (not inline and (not file or not file.id)) then
            self.action_error = "This GIF is unavailable."
            return false
        end
        local request
        if inline then
            request = {["@type"] = "sendInlineQueryResultMessage", chat_id = chat_id,
                query_id = query_id, result_id = result_id}
        else
            request = {["@type"] = "sendMessage", chat_id = chat_id, input_message_content = {
                ["@type"] = "inputMessageAnimation",
                animation = {
                    ["@type"] = "inputAnimation", animation = {["@type"] = "inputFileId", id = file.id},
                    duration = animation.duration or 0, width = animation.width or 0, height = animation.height or 0,
                },
            }}
        end
        if not self:send(request, "send_gif") then return false end
        self.action_error, self.action_status = "", "Sending GIF…"
        return true
    end

    function telegram:send_document(chat_id, path)
        if not chat_id or not path then return end
        self:send({
            ["@type"] = "sendMessage",
            chat_id = chat_id,
            input_message_content = {
                ["@type"] = "inputMessageDocument",
                document = {
                    ["@type"] = "inputFileLocal",
                    path = path,
                    expected_size = (function()
                        local f = io.open(path, "rb")
                        if not f then return 0 end
                        local sz = f:seek("end")
                        f:close()
                        return sz or 0
                    end)(),
                },
                caption = {["@type"] = "formattedText", text = ""},
            },
        })
    end

    function telegram:send_photo(chat_id, path)
        if not chat_id or not path then return end
        self:send({
            ["@type"] = "sendMessage",
            chat_id = chat_id,
            input_message_content = {
                ["@type"] = "inputMessagePhoto",
                photo = {
                    ["@type"] = "inputPhoto",
                    photo = {
                        ["@type"] = "inputFileLocal",
                        path = path,
                        expected_size = (function()
                            local f = io.open(path, "rb")
                            if not f then return 0 end
                            local sz = f:seek("end")
                            f:close()
                            return sz or 0
                        end)(),
                    },
                },
                caption = {["@type"] = "formattedText", text = ""},
                width = 0,
                height = 0,
            },
        })
    end

    function telegram:send_message(chat_id, text, topic, reply, token, entities)
        if not chat_id or not text or text == "" then
            return
        end
        return self:send({
            ["@type"] = "sendMessage",
            chat_id = chat_id,
            topic_id = topic or self:forum_message_scope(chat_id),
            reply_to = reply,
            input_message_content = {
                ["@type"] = "inputMessageText",
                text = {
                    ["@type"] = "formattedText",
                    text = text,
                    entities = entities or {},
                },
            },
        }, token)
    end

    function telegram:mark_chat_viewed(chat_id, messages)
        if not chat_id then return end
        local seen = self.viewed_message_ids[chat_id]
        if not seen then
            seen = {}
            self.viewed_message_ids[chat_id] = seen
        end
        local ids = {}
        for _, message in ipairs(messages or self.messages[chat_id] or {}) do
            local id = message and message.id
            if id and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
        if #ids == 0 then return end
        self:send({
            ["@type"] = "viewMessages",
            chat_id = chat_id,
            message_ids = ids,
            source = {["@type"] = self:forum_message_scope(chat_id) and "messageSourceForumTopicHistory" or "messageSourceChatHistory"},
            force_read = false,
        }, "view:" .. tostring(chat_id) .. ":" .. tostring(ids[#ids]))
    end

    function telegram:send_typing(chat_id)
        if not chat_id then return end
        local now = love.timer.getTime()
        local last = self.typing_sent_at[chat_id]
        if last and now - last < 4 then return end
        self.typing_sent_at[chat_id] = now
        self:send({
            ["@type"] = "sendChatAction",
            chat_id = chat_id,
            action = {["@type"] = "chatActionTyping"},
        }, "typing:" .. tostring(chat_id))
    end

    function telegram:message_can_be_shared(message, chat_id)
        chat_id = chat_id or message and message.chat_id
        local chat = self.chats_by_id[chat_id] or (self.archive_chats_by_id or {})[chat_id]
        return not ((chat and chat.has_protected_content) or (message and
            (message.can_be_saved == false or message.can_be_forwarded == false or self:is_ephemeral_media(message))))
    end

    function telegram:forward_messages(to_chat_id, from_chat_id, message_ids, hide_sender, hide_text)
        if not to_chat_id or not from_chat_id or not message_ids or #message_ids == 0 then
            return false
        end
        if not self:message_can_be_shared(nil, from_chat_id) then
            self.action_error, self.action_status = "Telegram restricts forwarding from this chat.", ""
            return false
        end
        local selected = {}
        for _, id in ipairs(message_ids) do selected[id] = true end
        for _, list in ipairs({self:get_messages(from_chat_id), (self.dialog_search_results or {})[from_chat_id] or {}}) do
            for _, message in ipairs(list) do
                if selected[message.id] and not self:message_can_be_shared(message, from_chat_id) then
                    self.action_error, self.action_status = "Telegram restricts forwarding this message.", ""
                    return false
                end
            end
        end
        self.action_error = ""
        self.action_status = "Forwarding messages…"
        self:send({
            ["@type"] = "forwardMessages",
            chat_id = to_chat_id,
            from_chat_id = from_chat_id,
            message_ids = message_ids,
            options = {
                ["@type"] = "messageSendOptions",
                disable_notification = false,
                from_background = false,
                scheduling_state = json.null,
            },
            send_copy = hide_sender == true or hide_text == true,
            remove_caption = hide_text == true,
        }, "forward:" .. tostring(to_chat_id) .. ":" .. tostring(from_chat_id))
        return true
    end

    function telegram:set_message_pinned(chat_id, message_id, pinned)
        if not chat_id or not message_id then return false end
        self.action_error = ""
        self.action_status = pinned and "Pinning message…" or "Unpinning message…"
        if pinned then
            self:send({
                ["@type"] = "pinChatMessage",
                chat_id = chat_id,
                message_id = message_id,
                disable_notification = false,
                only_for_self = false,
            }, "pin:" .. tostring(chat_id) .. ":" .. tostring(message_id))
        else
            self:send({
                ["@type"] = "unpinChatMessage",
                chat_id = chat_id,
                message_id = message_id,
            }, "unpin:" .. tostring(chat_id) .. ":" .. tostring(message_id))
        end
        return true
    end

    function telegram:delete_messages(chat_id, message_ids, revoke)
        if not chat_id or not message_ids or #message_ids == 0 then
            return
        end
        self.action_error, self.action_status = "", "Deleting message…"
        self:send({
            ["@type"] = "deleteMessages",
            chat_id = chat_id,
            message_ids = message_ids,
            revoke = revoke or false,
        }, "delete:" .. tostring(chat_id))
    end

    function telegram:is_saved_messages(chat_id)
        if not chat_id then return false end
        if chat_id == self.saved_chat_id then return true end
        local chat = (self.chats_by_id or {})[chat_id] or (self.archive_chats_by_id or {})[chat_id]
        local kind = chat and chat.type
        return self.me and kind and kind["@type"] == "chatTypePrivate" and kind.user_id == self.me.id or false
    end

    function telegram:edit_message_text(chat_id, message_id, text)
        if self:is_saved_messages(chat_id) then return false end
        if not chat_id or not message_id or not text or text == "" then
            self.action_error = "Enter a message first."
            self.action_status = ""
            return false
        end
        self.action_error = ""
        self.action_status = "Saving changes…"
        self:send({
            ["@type"] = "editMessageText",
            chat_id = chat_id,
            message_id = message_id,
            input_message_content = {
                ["@type"] = "inputMessageText",
                text = {
                    ["@type"] = "formattedText",
                    text = text,
                    entities = {},
                },
            },
        }, "edit:" .. tostring(chat_id) .. ":" .. tostring(message_id))
        return true
    end

    function telegram:set_message_reaction(chat_id, message_id, emoji)
        if not chat_id or not message_id then return false end
        self.action_error = ""
        self.action_status = (emoji and emoji ~= "") and ("Reaction " .. emoji) or "Removing reaction…"
        local reaction = setmetatable({}, {__jsontype = "array"})
        if emoji and emoji ~= "" then
            reaction[1] = {["@type"] = "reactionTypeEmoji", emoji = emoji}
        end
        self:send({
            ["@type"] = "setMessageReactions",
            chat_id = chat_id,
            message_id = message_id,
            reaction = reaction,
            is_big = false,
        }, "reaction:" .. tostring(chat_id) .. ":" .. tostring(message_id))
        return true
    end

    function telegram:submit_password(password)
        if not password or password == "" then
            return
        end
        self:send({
            ["@type"] = "checkAuthenticationPassword",
            password = password,
        }, "password")
    end

    function telegram:retry_history_from_read_position(chat_id, state)
        local fallback = state.fallback_read_id or 0
        if fallback == state.resume_id then fallback = 0 end
        state.resume_id = fallback > 0 and not state.fallback_unread and fallback or nil
        state.catch_up = fallback > 0
        state.unread_after = state.fallback_unread and fallback or nil
        state.unread_remaining = fallback == 0 and state.fallback_unread or nil
        return self:request_history(chat_id, "initial", fallback, fallback > 0 and -15 or 0)
    end

    function telegram:handle_history(response)
        local extra = response["@extra"] or ""
        local chat_id = tonumber(extra:match("^history:(%-?%d+):%d+$"))
        local state = chat_id and self.history_state[chat_id]
        if self.current_chat_id ~= chat_id or not state or state.token ~= extra or not state.loading then return end
        if state.jump then
            self:finish_read_jump(chat_id, state, response)
            return
        end
        local direction = state.direction
        local previous_ids = {}
        local by_id = {}
        for _, message in ipairs(self.messages[chat_id] or {}) do
            by_id[message.id] = message
            previous_ids[message.id] = true
        end
        local new_count, new_incoming = 0, 0
        for _, message in ipairs(response.messages or {}) do
            local id = message.id
            if id and (direction ~= "newer" or id >= state.request_anchor)
                and (direction ~= "older" or id <= state.request_anchor) then
                if not previous_ids[id] then
                    previous_ids[id] = true
                    new_count = new_count + 1
                    if not message.is_outgoing then new_incoming = new_incoming + 1 end
                end
                by_id[id] = message
            end
        end
        local list = {}
        for _, message in pairs(by_id) do
            list[#list + 1] = message
        end
        table.sort(list, function(a, b)
            return (a.id or 0) < (b.id or 0)
        end)
        self.messages[chat_id] = list
        state.loading = false
        state.error = nil
        if direction == "newer" and new_count > 0 then state.keep_position_id = state.request_anchor end
        if direction ~= "newer" then state.has_more = new_count > 0 end
        if direction ~= "older" then
            local chat = self:history_peer(chat_id)
            local latest = chat and chat.last_message and chat.last_message.id
            local newest = list[#list]
            state.has_newer = state.catch_up and newest and new_count > 0
                and (not latest or newest.id < latest) or false
        end
        if #list > MAX_MESSAGES_PER_CHAT then
            local window = {}
            local start_index = direction == "older" and 1 or #list - MAX_MESSAGES_PER_CHAT + 1
            for index = start_index, start_index + MAX_MESSAGES_PER_CHAT - 1 do
                window[#window + 1] = list[index]
            end
            if direction == "older" then
                state.catch_up, state.has_newer = true, true
            else
                state.has_more = true
            end
            self.messages[chat_id], list = window, window
        end
        if direction == "initial" and state.resume_id then
            if #list == 0 then
                self:retry_history_from_read_position(chat_id, state)
                return
            end
            local resume_id = state.resume_id
            state.resume_id = nil
            local nearby = list[#list]
            for _, message in ipairs(list) do
                if message.id >= resume_id then nearby = message; break end
            end
            state.initial_focus_id = nearby.id
        end
        if state.unread_remaining then
            state.unread_remaining = state.unread_remaining - new_incoming
            if state.unread_remaining > 0 and state.has_more then
                self:load_more_history(chat_id)
            else
                state.unread_remaining = nil
            end
        end
        if state.unread_after and not state.unread_remaining then
            for _, message in ipairs(list) do
                if message.id > state.unread_after and not message.is_outgoing then
                    state.initial_focus_id = message.id
                    state.unread_divider_id = message.id
                    state.unread_after = nil
                    break
                end
            end
        end
        local boundary = state.fallback_read_id
        if state.fallback_unread and not state.unread_divider_id and #list > 0
            and (not state.has_more or (boundary and list[1].id <= boundary)) then
            for _, message in ipairs(list) do
                if message.id > (boundary or 0) and not message.is_outgoing then
                    state.unread_divider_id = message.id
                    break
                end
            end
        end
        if not state.loading then
            if state.unread_after and state.has_newer then
                local anchor = math.max(state.unread_after, list[#list].id)
                self:request_history(chat_id, "newer", anchor, -15)
            else
                state.unread_after = nil
                if direction == "initial" and #list == 1 then self:load_more_history(chat_id) end
            end
        end
    end

    function telegram:handle_new_message(message)
        if not message or not message.chat_id then
            log_to_file(self, "handle_new_message: rejected - missing message or chat_id")
            return
        end
        if message.sender_id and message.sender_id["@type"] == "messageSenderUser" then
            self:ensure_user(message.sender_id.user_id)
        end

        local chat = self.chats_by_id[message.chat_id] or self.archive_chats_by_id[message.chat_id]
        local sender = message.sender_id
        local from_me = sender and sender["@type"] == "messageSenderUser"
            and self.me and sender.user_id == self.me.id
        if not from_me and not message.is_outgoing then
            local now = love.timer.getTime()
            if self:record_message_ping(message.chat_id, message.id, now) and not self:is_chat_muted(chat) then
                self:play_incoming_message_sound(now)
                if self.current_chat_id ~= message.chat_id then
                    local formatted = message.content and message.content.caption
                    self:push_notification({
                        chat_id = message.chat_id,
                        title = chat and chat.title,
                        user_id = sender and sender["@type"] == "messageSenderUser" and sender.user_id or nil,
                        avatar_chat_id = sender and sender["@type"] == "messageSenderChat" and sender.chat_id or message.chat_id,
                        text = formatted and formatted.text ~= "" and formatted.text or self:message_text(message),
                        created = now,
                    })
                end
            end
        end

        local history = self.history_state[message.chat_id]
        local catching_up = history and (history.jump or history.has_newer or (history.catch_up and history.loading))
        local forum = self.forum
        local scoped = forum and forum.chat_id == message.chat_id
        local topic_id = message.topic_id and message.topic_id.forum_topic_id
        local topic = scoped and topic_id and forum.by_id[topic_id]
        if topic and (not topic.last_message or message.id > topic.last_message.id) then
            topic.last_message = message
            if not message.is_outgoing and message.id > (topic.last_read_inbox_message_id or 0) then
                topic.unread_count = (topic.unread_count or 0) + 1
            end
        end
        if self.current_chat_id == message.chat_id and not catching_up
            and (not scoped or (topic and forum.active == topic)) then
            local list = self.messages[message.chat_id] or {}
            local replaced = false
            for i, existing in ipairs(list) do
                if existing.id == message.id then
                    list[i] = message
                    replaced = true
                    break
                end
            end
            if not replaced then
                list[#list + 1] = message
                if history and not history.unread_divider_id and not history.fallback_unread
                    and chat and not from_me and not message.is_outgoing
                    and message.id > (tonumber((topic or chat).last_read_inbox_message_id) or 0) then
                    history.unread_divider_id = message.id
                end
            end
            table.sort(list, function(a, b)
                return (a.id or 0) < (b.id or 0)
            end)
            self.messages[message.chat_id] = list
            prune_messages(message.chat_id, self)
        end

        if chat and (not chat.last_message or (message.id or 0) >= (chat.last_message.id or 0)) then
            chat.last_message = message
            if self.archive_chats_by_id[message.chat_id] then
                self:rebuild_archive_chats()
            else
                self:rebuild_chats()
            end
        end
    end

    function telegram:handle_send_succeeded(update)
        local old_id = update.old_message_id
        local message = update.message
        if not message or not message.chat_id then
            return
        end
        self.delivery_feedback = {chat_id = message.chat_id, id = message.id, at = love.timer.getTime()}
        local list = self.messages[message.chat_id]
        if list then
            for i, existing in ipairs(list) do
                if existing.id == old_id then
                    list[i] = message
                    return
                end
            end
        end
        self:handle_new_message(message)
    end

    function telegram:handle_message_content(update)
        local list = self.messages[update.chat_id]
        if not list then
            return
        end
        for _, message in ipairs(list) do
            if message.id == update.message_id then
                message.content = update.new_content
                self.action_error = ""
                self.action_status = "Message edited"
                if self.current_chat_id == update.chat_id then
                end
                return
            end
        end
    end

    function telegram:handle_message_interaction_info(update)
        local chat_id, message_id = update.chat_id, update.message_id
        if not chat_id or not message_id then return end
        local function apply(message)
            if message and message.id == message_id then
                message.interaction_info = update.interaction_info
            end
        end
        for _, message in ipairs(self.messages[chat_id] or {}) do
            apply(message)
        end
        for _, message in ipairs(self.dialog_search_results[chat_id] or {}) do
            apply(message)
        end
        local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
        if chat then apply(chat.last_message) end
    end

    function telegram:handle_delete_messages(update)
        local deleted = {}
        for _, id in ipairs(update.message_ids or {}) do
            deleted[id] = true
        end
        for _, storage in ipairs({self.messages, self.dialog_search_results or {}}) do
            local list = storage[update.chat_id]
            if list then
                local kept = {}
                for _, message in ipairs(list) do
                    if not deleted[message.id] then kept[#kept + 1] = message end
                end
                storage[update.chat_id] = kept
            end
        end
        if self.on_messages_deleted then self.on_messages_deleted(update.chat_id, deleted) end
    end

end
