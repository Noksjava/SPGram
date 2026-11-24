local PAGE_SIZE = 24

local function merge_comments(thread, messages)
    for _, message in ipairs(messages or {}) do
        if message.id and message.chat_id == thread.chat_id and not thread.roots[message.id] and not message.sending_state then
            thread.by_id[message.id] = message
        end
    end
    local ordered = {}
    for _, message in pairs(thread.by_id) do ordered[#ordered + 1] = message end
    table.sort(ordered, function(a, b) return a.id < b.id end)
    thread.messages = ordered
end

local function reaction_key(kind)
    if kind["@type"] == "reactionTypeEmoji" then return kind.emoji end
    if kind["@type"] == "reactionTypeCustomEmoji" and kind.custom_emoji_id then
        return "custom:" .. tostring(kind.custom_emoji_id)
    end
end

local function load_reaction_items(menu, available, premium)
    local seen, chosen = {}, {}
    local info = menu.message.interaction_info
    for _, reaction in ipairs(info and info.reactions and info.reactions.reactions or {}) do
        local key = reaction.type and reaction_key(reaction.type)
        if key and reaction.is_chosen then chosen[key] = reaction.type end
    end
    local function add(kind, key)
        if not key or seen[key] then return end
        seen[key] = true
        menu.items[#menu.items + 1] = {emoji = kind.emoji or "✨", custom_id = kind.custom_emoji_id,
            reaction_type = kind, chosen = chosen[key] ~= nil}
    end
    if not available.unavailability_reason then
        for _, group in ipairs({"top_reactions", "recent_reactions", "popular_reactions"}) do
            for _, reaction in ipairs(available[group] or {}) do
                if reaction.type and (not reaction.needs_premium or premium) then
                    add(reaction.type, reaction_key(reaction.type))
                end
            end
        end
    end
    for key, kind in pairs(chosen) do add(kind, key) end
    if #menu.items == 0 then menu.status = "Reactions are unavailable for this comment." end
end

return function(telegram)
    function telegram:request_comments(post)
        self.comments_sequence = (self.comments_sequence or 0) + 1
        local token = "comments_thread:" .. tostring(self.comments_sequence)
        local thread = {post = post, messages = {}, by_id = {}, roots = {}, seen = {},
            draft = "", loading = true, load_token = token, quote_scope = self.comments_sequence, reply_cache = {}}
        self.comments_thread = thread
        if not self:send({["@type"] = "getMessageThread", chat_id = post.chat_id, message_id = post.id}, token) then
            thread.loading, thread.load_token, thread.error = false, nil, "Could not load comments."
        end
        return thread
    end

    function telegram:request_comment_page(thread, advance, use_post)
        if self.comments_thread ~= thread or not thread.topic_id or thread.loading or thread.has_more == false then return end
        self.comments_sequence = self.comments_sequence + 1
        local token = "comments_page:" .. tostring(self.comments_sequence)
        thread.loading, thread.load_token, thread.error = true, token, nil
        thread.advance_from, thread.page_via_post = advance, use_post
        local chat_id = use_post and thread.post.chat_id or thread.chat_id
        local message_id = use_post and thread.post.id or thread.topic_id
        if not self:send({["@type"] = "getMessageThreadHistory", chat_id = chat_id, message_id = message_id,
            from_message_id = thread.page_cursor or thread.topic_id, offset = 1 - PAGE_SIZE, limit = PAGE_SIZE}, token) then
            thread.loading, thread.load_token, thread.error = false, nil, "Could not load comments."
        end
    end

    function telegram:request_comment_reactions(thread, menu, row_size)
        if self.comments_thread ~= thread then return end
        self.comments_sequence = self.comments_sequence + 1
        menu.token = "comments_reactions:" .. tostring(self.comments_sequence)
        menu.loading, thread.reaction_menu, thread.reaction_error = true, menu, nil
        if not self:send({["@type"] = "getMessageAvailableReactions", chat_id = thread.chat_id,
            message_id = menu.message.id, row_size = row_size}, menu.token) then
            menu.loading, menu.status = false, "Could not load reactions."
        end
    end

    function telegram:react_to_comment(thread, message, item)
        if self.comments_thread ~= thread then return end
        self.comments_sequence = self.comments_sequence + 1
        local token = "comments_react:" .. tostring(self.comments_sequence)
        local request = {
            ["@type"] = item.chosen and "removeMessageReaction" or "addMessageReaction",
            chat_id = thread.chat_id, message_id = message.id, reaction_type = item.reaction_type,
        }
        if not item.chosen then request.is_big, request.update_recent_reactions = false, true end
        thread.reaction_token, thread.reaction_error = token, nil
        if not self:send(request, token) then thread.reaction_error = "Could not update reaction." end
    end

    function telegram:send_comment(thread)
        if self.comments_thread ~= thread or not thread.topic_id or thread.sending
            or not thread.draft:match("%S") then return false end
        self.comments_sequence = self.comments_sequence + 1
        local token = "comments_send:" .. tostring(self.comments_sequence)
        local reply_id = thread.reply_to and thread.reply_to.id or thread.root_id or thread.topic_id
        local sent = self:send_message(thread.chat_id, thread.draft, {
            ["@type"] = "messageTopicThread", message_thread_id = thread.topic_id,
        }, {["@type"] = "inputMessageReplyToMessage", message_id = reply_id}, token)
        if not sent then return false end
        thread.sending, thread.send_token, thread.send_error = true, token, nil
        return true
    end

    function telegram:is_comment_post_reply(thread, reply)
        if not reply then return false end
        local chat_id, id = reply.chat_id, reply.message_id
        if chat_id == thread.post.chat_id and id == thread.post.id then return true end
        return (chat_id == thread.chat_id or chat_id == 0) and thread.roots[id] == true
    end

    function telegram:quoted_comment_id(thread, message)
        local reply = self:message_reply(message)
        if not reply or self:is_comment_post_reply(thread, reply) then return end
        if reply.chat_id == thread.chat_id or reply.chat_id == 0 then
            local id = reply.message_id
            if id and id > 0 and id ~= message.id then return id end
        end
    end

    function telegram:jump_to_comment(thread, id)
        if self.comments_thread ~= thread or not id or thread.roots[id] then return end
        thread.jump_error = nil
        if thread.by_id[id] then
            thread.focus_id, thread.reveal_focus, thread.compose_selected = id, true, false
            return
        end
        self.comments_sequence = self.comments_sequence + 1
        thread.jump_id, thread.jump_token = id, "comments_jump:" .. tostring(self.comments_sequence)
        if not self:send({["@type"] = "getMessageThreadHistory", chat_id = thread.chat_id,
            message_id = thread.topic_id, from_message_id = id, offset = -5, limit = PAGE_SIZE}, thread.jump_token) then
            thread.jump_id, thread.jump_token = nil, nil
            thread.jump_error = "Could not load the quoted comment."
        end
    end

    function telegram:comment_reply_parent(thread, reply)
        if self:is_comment_post_reply(thread, reply) then return thread.post end
        local id = reply.message_id
        if not id or id <= 0 or (reply.chat_id ~= thread.chat_id and reply.chat_id ~= 0) then return end
        if thread.by_id[id] then return thread.by_id[id] end
        local parent = thread.reply_cache[id]
        if parent == nil then
            thread.reply_cache[id] = false
            self:send({["@type"] = "getMessage", chat_id = thread.chat_id, message_id = id},
                string.format("comments_quote:%d:%.0f", thread.quote_scope, id))
        end
        return parent or nil
    end

    function telegram:handle_comments_response(kind, extra, object)
        local thread = self.comments_thread
        local scope, parent_id = extra:match("^comments_quote:(%d+):(%d+)$")
        if scope then
            if thread and thread.quote_scope == tonumber(scope) and kind == "message"
                and object.chat_id == thread.chat_id and object.id == tonumber(parent_id) then
                thread.reply_cache[object.id] = object
            end
            return true
        end
        if not extra:match("^comments_%a+:%d+$") then return false end
        if not thread then return true end
        local menu = thread.reaction_menu
        if menu and extra == menu.token then
            menu.loading, menu.token = false, nil
            if kind == "availableReactions" then
                load_reaction_items(menu, object, self.me and self.me.is_premium)
            else
                menu.status = "Could not load reactions."
            end
        elseif extra == thread.reaction_token then
            thread.reaction_token = nil
            if kind == "error" then thread.reaction_error = object.message or "Could not update reaction." end
        elseif extra == thread.jump_token then
            local id = thread.jump_id
            thread.jump_id, thread.jump_token = nil, nil
            if kind == "messages" then
                for _, message in ipairs(object.messages or {}) do
                    if message.id == id and message.chat_id == thread.chat_id then
                        merge_comments(thread, object.messages)
                        thread.focus_id, thread.reveal_focus, thread.compose_selected = id, true, false
                        return true
                    end
                end
            end
            thread.jump_error = "Quoted comment is unavailable."
        elseif extra == thread.load_token then
            thread.loading, thread.load_token = false, nil
            if kind == "error" then
                if thread.topic_id and not thread.page_via_post and thread.chat_id ~= thread.post.chat_id then
                    self:request_comment_page(thread, thread.advance_from, true)
                else
                    thread.error = "Could not load comments."
                end
            elseif kind == "messageThreadInfo" and object.chat_id and object.message_thread_id then
                thread.chat_id, thread.topic_id = object.chat_id, object.message_thread_id
                for _, message in ipairs(object.messages or {}) do
                    if message.chat_id == thread.chat_id and message.id then
                        thread.root_id = message.id
                        thread.roots[message.id] = true
                    end
                end
                thread.roots[thread.topic_id] = true
                self:request_comment_page(thread)
            elseif kind == "messages" then
                local cursor = thread.page_cursor or thread.topic_id
                local first, last
                for _, message in ipairs(object.messages or {}) do
                    if message.chat_id == thread.chat_id and message.id and message.id > cursor
                        and not thread.roots[message.id] and not message.sending_state then
                        first = math.min(first or message.id, message.id)
                        last = math.max(last or message.id, message.id)
                    end
                end
                merge_comments(thread, object.messages)
                local info = thread.post.interaction_info
                local tail = info and info.reply_info and tonumber(info.reply_info.last_message_id) or 0
                thread.has_more = last ~= nil and (tail == 0 or last < tail)
                if not thread.page_cursor then
                    local oldest = thread.messages[1]
                    thread.focus_id, thread.compose_selected = oldest and oldest.id, not oldest
                    thread.scroll = 0
                elseif first and thread.advance_from and first > thread.advance_from
                    and thread.focus_id == thread.advance_from and not thread.compose_selected then
                    thread.focus_id, thread.reveal_focus = first, true
                elseif not first and thread.focus_id == thread.advance_from then
                    thread.compose_selected = true
                end
                thread.page_cursor, thread.advance_from = last or cursor, nil
            end
        elseif extra == thread.send_token then
            if kind == "error" then
                thread.sending, thread.send_token, thread.send_error = false, nil, object.message or "Could not send comment."
            elseif kind == "message" then
                if object.sending_state then
                    thread.sending_id = object.id
                else
                    self:finish_comment_send(thread, object)
                end
            end
        end
        return true
    end

    function telegram:finish_comment_send(thread, message)
        thread.sending, thread.sending_id, thread.send_token = false, nil, nil
        thread.draft, thread.reply_to, thread.compose = "", nil, false
        merge_comments(thread, {message})
        thread.focus_id, thread.reveal_focus, thread.compose_selected = message.id, true, false
        local post = thread.post
        local info = post.interaction_info and post.interaction_info.reply_info
        if info and message.id > (tonumber(info.last_message_id) or 0) then
            info.reply_count = (tonumber(info.reply_count) or 0) + 1
            info.last_message_id = message.id
        end
    end

    function telegram:update_comment_delivery(update)
        local thread = self.comments_thread
        local message = update.message
        if not thread or not message or message.chat_id ~= thread.chat_id
            or thread.sending_id ~= update.old_message_id then return end
        if update["@type"] == "updateMessageSendSucceeded" then
            self:finish_comment_send(thread, message)
        else
            thread.sending, thread.sending_id, thread.send_token = false, nil, nil
            thread.send_error = update.error and update.error.message or "Could not send comment."
        end
    end

    function telegram:receive_thread_message(message)
        local thread = self.comments_thread
        local topic = message and message.topic_id
        if thread and topic and topic.message_thread_id == thread.topic_id
            and message.chat_id == thread.chat_id and not message.sending_state then
            merge_comments(thread, {message})
        end
    end

    function telegram:update_thread_comment(update)
        local thread = self.comments_thread
        if not thread or update.chat_id ~= thread.chat_id then return end
        if update.new_content then
            local message = thread.by_id[update.message_id] or thread.reply_cache[update.message_id]
            if message then message.content = update.new_content end
        elseif not update.from_cache then
            local changed
            for _, id in ipairs(update.message_ids or {}) do
                if thread.by_id[id] then
                    thread.by_id[id] = nil
                    if thread.focus_id == id then thread.focus_id = nil end
                    changed = true
                end
                thread.reply_cache[id] = false
            end
            if changed then
                merge_comments(thread)
                if not thread.focus_id then
                    local latest = thread.messages[#thread.messages]
                    thread.focus_id, thread.compose_selected = latest and latest.id, not latest
                    thread.reveal_focus = true
                end
            end
        end
    end

    function telegram:update_comment_interactions(update)
        local thread = self.comments_thread
        if not thread or update.chat_id ~= thread.chat_id then return end
        local message = thread.by_id[update.message_id]
        if message then message.interaction_info = update.interaction_info end
    end

    function telegram:view_thread_comments(thread, ids)
        local unseen = {}
        for _, id in ipairs(ids) do
            if not thread.seen[id] then
                unseen[#unseen + 1], thread.seen[id] = id, true
            end
        end
        if #unseen > 0 then
            self:send({["@type"] = "viewMessages", chat_id = thread.chat_id, message_ids = unseen,
                source = {["@type"] = "messageSourceMessageThreadHistory"}, force_read = false})
        end
    end
end
