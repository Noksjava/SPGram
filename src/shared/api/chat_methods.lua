local json = require("dkjson")

local function folder_id(list)
    return list and (list.chat_folder_id or list.chat_filter_id)
end

local function same_list(a, b)
    if not a or not b then return false end
    local folder = folder_id(a)
    if folder then return folder == folder_id(b) end
    return not folder_id(b) and a["@type"] == b["@type"]
end

local MAIN_LIST = {["@type"] = "chatListMain"}
local ARCHIVE_LIST = {["@type"] = "chatListArchive"}
local FORUM_FIRST_PAGE = 12
local FORUM_NEXT_PAGE = 20
local FORUM_RETRY_PAGE = 8

local function copy_forum_row(topic)
    local message_id = topic.last_message and topic.last_message.id
    return {info = topic.info, is_pinned = topic.is_pinned, unread_count = topic.unread_count,
        last_read_inbox_message_id = topic.last_read_inbox_message_id, last_message = message_id and {id = message_id}}
end

local function chat_position(chat, list)
    for _, position in ipairs(chat.positions or {}) do
        if same_list(position.list, list) and (tonumber(position.order) or 0) ~= 0 then return position end
    end
end

local function chat_memberships(chat)
    if type(chat.chat_lists) == "table" then return chat.chat_lists end
    local lists = {}
    for _, position in ipairs(chat.positions or {}) do
        if position.list and (tonumber(position.order) or 0) ~= 0 then
            lists[#lists + 1] = position.list
        end
    end
    return lists
end

local function primary_list(chat)
    local main
    for _, list in ipairs(chat_memberships(chat)) do
        if same_list(list, ARCHIVE_LIST) then return ARCHIVE_LIST end
        if same_list(list, MAIN_LIST) then main = MAIN_LIST end
    end
    return main
end

local function sort_chats(chats, list)
    table.sort(chats, function(a, b)
        local ap, bp = chat_position(a, list), chat_position(b, list)
        local a_pinned, b_pinned = ap and ap.is_pinned == true or false, bp and bp.is_pinned == true or false
        if a_pinned ~= b_pinned then return a_pinned end
        if ap and bp then
            local ao, bo = tostring(ap.order), tostring(bp.order)
            if #ao ~= #bo then return #ao > #bo end
            if ao ~= bo then return ao > bo end
            return a.id > b.id
        end
        if ap or bp then return ap ~= nil end
        local ad = a.last_message and a.last_message.date or 0
        local bd = b.last_message and b.last_message.date or 0
        if ad ~= bd then return ad > bd end
        return a.id > b.id
    end)
end

return function(telegram)
    function telegram:load_profile_user(user_id)
        self.profile_user = {id = user_id, loading = true}
        self:send({["@type"] = "getUserFullInfo", user_id = user_id}, "profile_user:" .. tostring(user_id))
    end

    function telegram:set_profile_user_blocked(blocked)
        local profile = self.profile_user
        if not profile or profile.loading or profile.pending or profile.blocked == nil
            or (self.me and profile.id == self.me.id) then return end
        profile.pending, profile.error = blocked and "block" or "unblock", nil
        self:send({["@type"] = "setMessageSenderBlockList",
            sender_id = {["@type"] = "messageSenderUser", user_id = profile.id},
            block_list = blocked and {["@type"] = "blockListMain"} or nil}, "profile_block:" .. tostring(profile.id))
    end

    function telegram:handle_profile_user(kind, extra, object)
        local info_id = tonumber(extra:match("^profile_user:(%d+)$"))
        local block_id = tonumber(extra:match("^profile_block:(%d+)$"))
        if not info_id and not block_id then return false end
        local profile = self.profile_user
        if not profile or profile.id ~= (info_id or block_id) then return true end
        if info_id then
            profile.loading = false
            if kind == "userFullInfo" then
                profile.blocked = object.block_list and object.block_list["@type"] == "blockListMain" or false
                profile.bio = object.bio and object.bio.text or ""
                profile.photo = object.personal_photo or object.photo or object.public_photo
            else
                profile.error = "Could not load profile details."
            end
        elseif profile.pending then
            if kind == "ok" then profile.blocked = profile.pending == "block"
            else profile.error = "Could not change the block status." end
            profile.pending = nil
        end
        return true
    end

    function telegram:request_my_profile()
        if not self.me then return end
        self:send({["@type"] = "getUserFullInfo", user_id = self.me.id},
            "my_profile:" .. string.format("%.0f", self.me.id))
    end

    function telegram:save_my_profile(first_name, last_name, bio)
        if not self.me or (self.my_profile_save and self.my_profile_save.pending > 0) then return end
        self.my_profile_sequence = (self.my_profile_sequence or 0) + 1
        local state = {pending = 0, sequence = self.my_profile_sequence, user_id = self.me.id,
            first_name = first_name, last_name = last_name, bio = bio, errors = {}}
        self.my_profile_save = state
        local function submit(field, request)
            local token = string.format("my_profile_save:%d:%s", state.sequence, field)
            if self:send(request, token) then state.pending = state.pending + 1
            else state.errors[#state.errors + 1] = "Could not update " .. field .. "." end
        end
        if first_name ~= (self.me.first_name or "") or last_name ~= (self.me.last_name or "") then
            submit("name", {["@type"] = "setName", first_name = first_name, last_name = last_name})
        end
        if bio ~= nil and bio ~= (self.my_bio or "") then submit("bio", {["@type"] = "setBio", bio = bio}) end
        return state
    end

    function telegram:handle_my_profile(kind, extra, object)
        local user_id = extra:match("^my_profile:(%d+)$")
        if user_id then
            if kind == "userFullInfo" and self.me and self.me.id == tonumber(user_id) then
                self.my_bio = object.bio and object.bio.text or ""
            end
            return true
        end
        if kind == "updateUserFullInfo" and self.me and object.user_id == self.me.id then
            self.my_bio = object.user_full_info and object.user_full_info.bio and object.user_full_info.bio.text or ""
            return true
        end
        local sequence, field = extra:match("^my_profile_save:(%d+):(%a+)$")
        if not sequence then return false end
        local state = self.my_profile_save
        if not state or state.sequence ~= tonumber(sequence) or not self.me or self.me.id ~= state.user_id then return true end
        state.pending = math.max(0, state.pending - 1)
        if kind == "ok" then
            if field == "bio" then self.my_bio = state.bio
            else
                self.me.first_name, self.me.last_name = state.first_name, state.last_name
                self.users[self.me.id] = self.me
            end
        else
            state.errors[#state.errors + 1] = (field == "bio" and "Bio" or "Name") .. " · " .. (object.message or "Update failed")
        end
        return true
    end

    function telegram:handle_user(user)
        if user["@extra"] == "me" then
            self.me = user
            self.users[user.id] = user
            self:load_saved_messages()
            if self.on_me then self.on_me(user) end
        else
            self.users[user.id] = user
            if self.me and self.me.id == user.id then self.me = user end
            self.requested_users[user.id] = nil
        end
    end

    function telegram:load_saved_messages()
        if not self.me or self.saved_chat_id or self.saved_chat_pending then return end
        self.saved_chat_pending = self:send({
            ["@type"] = "createPrivateChat", user_id = self.me.id, force = false,
        }, "saved_messages")
        self.saved_chat_error = nil
    end

    function telegram:ensure_user(user_id)
        if user_id and not self.users[user_id] and not self.requested_users[user_id] then
            self.requested_users[user_id] = true
            self:send({["@type"] = "getUser", user_id = user_id}, "user:" .. tostring(user_id))
        end
    end

    function telegram:user_name(user_id)
        local user = self.users[user_id]
        if not user then
            return "User " .. tostring(user_id)
        end
        local first = user.first_name or ""
        local last = user.last_name or ""
        local name = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then
            name = user.username or ("User " .. tostring(user_id))
        end
        return name
    end

    function telegram:private_chat_user_id(chat)
        if not chat then return nil end
        local chat_type = chat.type or {}
        if chat_type["@type"] == "chatTypePrivate" or chat_type["@type"] == "chatTypeSecret" then
            return chat_type.user_id
        end
        return nil
    end

    function telegram:request_chat_send_access(chat)
        if not chat then return end
        local kind = chat.type or {}
        if kind["@type"] == "chatTypeSupergroup" and kind.supergroup_id then
            self:send({["@type"] = "getSupergroup", supergroup_id = kind.supergroup_id}, "compose_group")
        elseif kind["@type"] == "chatTypeBasicGroup" and kind.basic_group_id then
            self:send({["@type"] = "getBasicGroup", basic_group_id = kind.basic_group_id}, "compose_group")
        elseif kind["@type"] == "chatTypePrivate" and kind.user_id
            and not (self.me and self.me.id == kind.user_id) then
            self:send({["@type"] = "canSendMessageToUser", user_id = kind.user_id, only_local = false},
                "compose_user:" .. string.format("%.0f", kind.user_id))
        end
    end

    function telegram:handle_chat_send_access(kind, extra, object)
        local group
        if kind == "updateSupergroup" then group = object.supergroup
        elseif kind == "updateBasicGroup" then group = object.basic_group
        elseif kind == "supergroup" or kind == "basicGroup" then group = object end
        if group and group.id then
            self.send_group_status = self.send_group_status or {basicGroup = {}, supergroup = {}}
            local statuses = self.send_group_status[group["@type"]]
            if statuses then statuses[group.id] = group.status end
            if group.is_forum ~= nil then
                self.forum_groups = self.forum_groups or {}
                self.forum_groups[group.id] = group.is_forum
                local chat = self.current_chat_id and self:history_chat(self.current_chat_id)
                local kind = chat and chat.type
                if group.is_forum and not self.forum and kind and kind.supergroup_id == group.id then
                    self:show_forum_topics(chat.id)
                end
            end
        elseif extra:match("^compose_user:") then
            local id = tonumber(extra:match(":(%d+)$"))
            if id and kind:match("^canSendMessageToUserResult") then
                self.send_user_access = self.send_user_access or {}
                self.send_user_access[id] = kind == "canSendMessageToUserResultOk"
            end
            return true
        end
        return false
    end

    function telegram:chat_send_capabilities(chat)
        if not chat or (chat.block_list and chat.block_list["@type"] == "blockListMain") then return false, false end
        local kind = chat.type or {}
        local topic = self.forum and self.forum.chat_id == chat.id and self.forum.active
        if topic and topic.info.is_closed then return false, false end
        local statuses = self.send_group_status or {}
        local status
        if kind["@type"] == "chatTypeSupergroup" then
            status = (statuses.supergroup or {})[kind.supergroup_id]
        elseif kind["@type"] == "chatTypeBasicGroup" then
            status = (statuses.basicGroup or {})[kind.basic_group_id]
        elseif kind["@type"] == "chatTypePrivate" or kind["@type"] == "chatTypeSecret" then
            local user = self.users and self.users[kind.user_id]
            local deleted = user and user.type and user.type["@type"] == "userTypeDeleted"
            local blocked = self.send_user_access and self.send_user_access[kind.user_id] == false
            if deleted or blocked then return false, false end
        end
        local membership = status and status["@type"]
        if kind["@type"] == "chatTypeSupergroup" and kind.is_channel then
            local can_post = membership == "chatMemberStatusCreator" and status.is_member ~= false
                or membership == "chatMemberStatusAdministrator" and status.rights and status.rights.can_post_messages == true
            return can_post == true, can_post == true
        end
        if membership == "chatMemberStatusLeft" or membership == "chatMemberStatusBanned"
            or (membership == "chatMemberStatusRestricted" and not status.is_member)
            or (membership == "chatMemberStatusCreator" and status.is_member == false) then
            return false, false
        end
        if membership == "chatMemberStatusCreator" or membership == "chatMemberStatusAdministrator" then
            return true, true
        end
        local permissions = membership == "chatMemberStatusRestricted" and status.permissions or chat.permissions or {}
        return permissions.can_send_basic_messages ~= false, permissions.can_send_other_messages ~= false
    end

    function telegram:show_forum_topics(chat_id, refresh)
        local forum = self.forum
        if not forum or forum.chat_id ~= chat_id then
            forum = {chat_id = chat_id, topics = {}, by_id = {}, drafts = {}, index = 1}
            self.forum = forum
            local cached = self.recent_forum_topics
            if cached and cached.chat_id == chat_id then
                for i, topic in ipairs(cached.topics) do
                    local row = copy_forum_row(topic)
                    forum.topics[i], forum.by_id[row.info.forum_topic_id] = row, row
                end
            end
        end
        if refresh then
            forum.topics, forum.by_id, forum.index, forum.first = {}, {}, 1, 1
            forum.date, forum.message_id, forum.topic_id = nil, nil, nil
            forum.loaded, forum.complete = nil, nil
            forum.token, forum.previous_token, forum.deadline, forum.slow = nil, nil, nil, nil
        end
        forum.active = nil
        self.messages[chat_id], self.history_state[chat_id] = {}, nil
        self.quote_lookup = nil
        if not forum.loaded and not forum.token then self:request_forum_topics() end
    end

    function telegram:request_forum_topics(retry)
        local forum = self.forum
        if not forum or forum.complete or (forum.token and not retry) then return end
        self.forum_sequence = (self.forum_sequence or 0) + 1
        local token = "forum_topics:" .. self.forum_sequence
        local limit = retry and FORUM_RETRY_PAGE or (forum.loaded and FORUM_NEXT_PAGE or FORUM_FIRST_PAGE)
        local sent = self:send({["@type"] = "getForumTopics", chat_id = forum.chat_id, query = "",
            offset_date = forum.date or 0, offset_message_id = forum.message_id or 0,
            offset_forum_topic_id = forum.topic_id or 0, limit = limit}, token)
        if sent then
            forum.previous_token, forum.token = forum.token, sent
            forum.error, forum.slow, forum.retried = nil, nil, retry == true
            forum.deadline = love.timer.getTime() + (retry and 25 or 12)
        else
            forum.deadline = nil
            if forum.token then forum.slow = true
            else forum.error = "Could not load topics." end
        end
    end

    function telegram:check_forum_topics(now)
        local forum = self.forum
        if not forum or forum.active then return end
        if self.connection_state and self.connection_state ~= "connectionStateReady" then return end
        if not forum.token then
            if not forum.error and not forum.complete and forum.loaded
                and forum.visible and #forum.topics < forum.visible then self:request_forum_topics() end
            return
        end
        if not forum.deadline or now < forum.deadline then return end
        if not forum.retried then
            self:request_forum_topics(true)
        else
            forum.deadline, forum.slow = nil, true
        end
    end

    function telegram:handle_forum_topics(kind, extra, response)
        local forum = self.forum
        if kind == "updateForumTopic" or kind == "updateForumTopicInfo" then
            local info = response.info
            local chat_id = info and info.chat_id or response.chat_id
            local id = info and info.forum_topic_id or response.forum_topic_id
            local topic = forum and forum.chat_id == chat_id and self:find_forum_topic(forum, id)
            if topic and info then topic.info = info
            elseif topic then
                topic.is_pinned = response.is_pinned
                local read = response.last_read_inbox_message_id
                if read and read >= (topic.last_read_inbox_message_id or 0) then
                    topic.last_read_inbox_message_id = read
                    if topic.last_message and read >= topic.last_message.id then topic.unread_count = 0 end
                end
            end
            return true
        end
        if not extra:match("^forum_topics:%d+$") then return false end
        if not forum or (forum.token ~= extra and forum.previous_token ~= extra) then return true end
        if kind ~= "forumTopics" then
            if extra == forum.previous_token then
                forum.previous_token = nil
            elseif forum.previous_token then
                forum.token, forum.previous_token = forum.previous_token, nil
            else
                forum.token, forum.deadline, forum.slow = nil, nil, nil
                forum.error = "Could not load topics."
            end
            return true
        end
        forum.token, forum.previous_token, forum.deadline, forum.slow = nil, nil, nil, nil
        forum.error = nil
        local first = not forum.loaded
        local selected = forum.topics[forum.index]
        local selected_id = selected and selected.info.forum_topic_id
        if first then
            forum.topics, forum.by_id, forum.index, forum.first = {}, {}, 1, 1
        end
        forum.loaded = true
        for _, topic in ipairs(response.topics or {}) do
            local id = topic.info and topic.info.forum_topic_id
            if id and not forum.by_id[id] then
                local active = forum.active and forum.active.info.forum_topic_id == id and forum.active
                local row = active or copy_forum_row(topic)
                row.info, row.is_pinned = topic.info, topic.is_pinned
                if active and (topic.last_read_inbox_message_id or 0) >= (row.last_read_inbox_message_id or 0) then
                    row.last_read_inbox_message_id, row.unread_count = topic.last_read_inbox_message_id, topic.unread_count
                end
                local last_id = topic.last_message and topic.last_message.id
                if active and last_id and (not row.last_message or last_id >= row.last_message.id) then
                    row.last_message = {id = last_id}
                end
                forum.by_id[id] = row
                forum.topics[#forum.topics + 1] = row
                if first and id == selected_id then forum.index = #forum.topics end
            end
        end
        if first then
            local cached = {chat_id = forum.chat_id, topics = {}}
            for i = 1, math.min(#forum.topics, FORUM_FIRST_PAGE) do
                cached.topics[i] = copy_forum_row(forum.topics[i])
            end
            self.recent_forum_topics = cached
        end
        local date, message_id, id = response.next_offset_date or 0,
            response.next_offset_message_id or 0, response.next_offset_forum_topic_id or 0
        forum.complete = (date == 0 and message_id == 0 and id == 0)
            or (date == forum.date and message_id == forum.message_id and id == forum.topic_id)
            or #(response.topics or {}) == 0
        forum.date, forum.message_id, forum.topic_id = date, message_id, id
        return true
    end

    function telegram:find_forum_topic(forum, id)
        local active = forum.active
        return active and active.info.forum_topic_id == id and active or forum.by_id[id]
    end

    function telegram:forum_message_scope(chat_id)
        local forum = self.forum
        local topic = forum and forum.chat_id == chat_id and forum.active
        if topic then return {["@type"] = "messageTopicForum", forum_topic_id = topic.info.forum_topic_id} end
    end

    function telegram:chat_title(chat_id)
        local chat = self.chats_by_id[chat_id]
        if chat then
            return chat.title or ("Chat " .. tostring(chat_id))
        end
        return "Chat " .. tostring(chat_id)
    end

    function telegram:handle_new_chat(chat, chat_list)
        if not chat or not chat.id then
            return
        end
        local list = chat_list or primary_list(chat)
        local is_archive = same_list(list, ARCHIVE_LIST)
        chat.chat_list = list
        if is_archive then
            self.chats_by_id[chat.id] = nil
            self.archive_chats_by_id[chat.id] = chat
        else
            self.archive_chats_by_id[chat.id] = nil
            self.chats_by_id[chat.id] = chat
            if same_list(list, MAIN_LIST) then self.chats_loaded = true end
        end
        self:rebuild_chats()
        self:rebuild_archive_chats()
        self:rebuild_filter_chats()
    end

    function telegram:handle_chat_last_message(update)
        local chat = self.chats_by_id[update.chat_id] or self.archive_chats_by_id[update.chat_id]
        if not chat then return end
        if update["@type"] == "updateChatDraftMessage" then
            chat.draft_message = update.draft_message
        else
            chat.last_message = update.last_message
        end
        if update.positions then
            chat.positions = update.positions
            self:handle_new_chat(chat)
        else
            self:rebuild_chats()
            self:rebuild_archive_chats()
            self:rebuild_filter_chats()
        end
    end

    function telegram:rebuild_chats()
        if self.defer_chat_lists then
            self.pending_main_list = true
            return
        end
        self.pending_main_list = nil
        local list = {}
        for _, chat in pairs(self.chats_by_id) do
            if same_list(chat.chat_list, MAIN_LIST) then
                list[#list + 1] = chat
            end
        end
        sort_chats(list, MAIN_LIST)
        self.chats = list
    end

    function telegram:rebuild_archive_chats()
        if self.defer_chat_lists then
            self.pending_archive_list = true
            return
        end
        self.pending_archive_list = nil
        local list = {}
        for _, chat in pairs(self.archive_chats_by_id) do
            if same_list(chat.chat_list, ARCHIVE_LIST) then
                list[#list + 1] = chat
            end
        end
        sort_chats(list, ARCHIVE_LIST)
        self.archive_chats = list
    end

    function telegram:rebuild_filter_chats()
        if self.defer_chat_lists then
            self.pending_filter_lists = true
            return
        end
        self.pending_filter_lists = nil
        local lists = {}
        local function is_discussion(chat)
            local t = chat and chat.type
            if not t or t["@type"] ~= "chatTypeSupergroup" or t.is_channel == true then return false end
            local linked = tonumber(chat.linked_chat_id) or 0
            return linked ~= 0
        end
        local function add(chat)
            if is_discussion(chat) then return end
            local seen = {}
            for _, list in ipairs(chat_memberships(chat)) do
                local id = folder_id(list)
                if id and not seen[id] then
                    seen[id] = true
                    local bucket = lists[id]
                    if not bucket then
                        bucket = {}
                        lists[id] = bucket
                    end
                    bucket[#bucket + 1] = chat
                end
            end
        end
        for _, chat in pairs(self.chats_by_id) do add(chat) end
        for _, chat in pairs(self.archive_chats_by_id) do add(chat) end
        for id, bucket in pairs(lists) do
            sort_chats(bucket, {["@type"] = "chatListFolder", chat_folder_id = id})
        end
        self.filter_chats = lists
    end

    function telegram:handle_chat_position(update)
        local chat = self.chats_by_id[update.chat_id] or self.archive_chats_by_id[update.chat_id]
        local position = update.position
        if not chat or not position or not position.list then return end
        local positions = {}
        for _, previous in ipairs(chat.positions or {}) do
            if not same_list(previous.list, position.list) then
                positions[#positions + 1] = previous
            end
        end
        if (tonumber(position.order) or 0) ~= 0 then positions[#positions + 1] = position end
        chat.positions = positions
        self:handle_new_chat(chat)
    end

    function telegram:handle_chat_list_membership(update, added)
        local chat = self.chats_by_id[update.chat_id] or self.archive_chats_by_id[update.chat_id]
        local list = update.chat_list
        if not chat or not list then return end
        local lists = {}
        for _, previous in ipairs(chat_memberships(chat)) do
            if not same_list(previous, list) then lists[#lists + 1] = previous end
        end
        if added then lists[#lists + 1] = list end
        chat.chat_lists = lists
        self:handle_new_chat(chat)
        local pending = self.pending_archive_changes[chat.id]
        if added and pending and same_list(list, pending.target_list) then
            self.pending_archive_changes[chat.id] = nil
        end
    end

    function telegram:load_filter_chats(filter_id)
        filter_id = tonumber(filter_id)
        if not filter_id or self.filter_load_pending[filter_id] then return end
        self.filter_load_pending[filter_id] = true
        self:send({
            ["@type"] = "loadChats",
            chat_list = {["@type"] = "chatListFolder", chat_folder_id = filter_id},
        limit = 15,
    }, "loadFilterChats:" .. tostring(filter_id))
    end

    function telegram:load_archive_chats()
        if self.archive_loaded or self.archive_load_pending then
            return
        end
        self.archive_loaded = false
        self.archive_load_error = nil
        self:request_archive_chat_batch()
    end

    function telegram:request_archive_chat_batch()
        self.archive_load_pending = true
        self:send({
            ["@type"] = "loadChats",
            chat_list = {["@type"] = "chatListArchive"},
        limit = 15,
    }, "loadArchiveChats")
    end

    function telegram:search_chats(query)
        query = tostring(query or "")
        self.chat_search_generation = (self.chat_search_generation or 0) + 1
        self.chat_search_query = query
        self.search_chat_results = {}
        self.chat_search_error = nil
        if query == "" then return end
        self:send({
            ["@type"] = "searchChats",
            query = query,
            limit = 50,
        }, "chat_search:" .. tostring(self.chat_search_generation))
    end

    function telegram:search_public_chats(query)
        query = tostring(query or "")
        self.public_search_generation = (self.public_search_generation or 0) + 1
        local generation = self.public_search_generation
        self.public_search_query = query
        self.public_search_results = {}
        self.public_search_result_ids = {}
        self.public_search_detail_pending_ids = {}
        self.public_search_details_pending = 0
        self.public_search_error = nil
        self.public_search_user_pending = false
        self.public_search_pending = query ~= ""
        self:request_search_sponsors(query, generation)
        if query == "" then return end

        self:send({
            ["@type"] = "searchPublicChats",
            query = query,
        }, "public_search:" .. tostring(generation))

        local username = query:gsub("^@", "")
        if username:match("^[%w_]+$") and #username >= 5 and #username <= 32 then
            self.public_search_user_pending = true
            self:send({
                ["@type"] = "searchPublicChat",
                username = username,
            }, "public_user_search:" .. tostring(generation))
        end
    end

    function telegram:handle_public_search_chats(response)
        local generation = tonumber(tostring(response["@extra"] or ""):match("^public_search:(%d+)$"))
        if not generation or generation ~= self.public_search_generation then return end
        self.public_search_details_pending = 0
        self.public_search_detail_pending_ids = {}
        for _, chat_id in ipairs(response.chat_ids or {}) do
            local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
            if chat then
                if not self.public_search_result_ids[chat_id] then
                    self.public_search_results[#self.public_search_results + 1] = chat
                    self.public_search_result_ids[chat_id] = true
                end
            elseif not self.public_search_result_ids[chat_id] and not self.public_search_detail_pending_ids[chat_id] then
                self.public_search_detail_pending_ids[chat_id] = true
                self.public_search_details_pending = self.public_search_details_pending + 1
                self:send({
                    ["@type"] = "getChat",
                    chat_id = chat_id,
                }, "public_search_detail:" .. tostring(generation) .. ":" .. tostring(chat_id))
            end
        end
        self.public_search_pending = self.public_search_details_pending > 0
    end

    function telegram:handle_public_search_detail(chat)
        local generation, chat_id = tostring(chat["@extra"] or "")
            :match("^public_search_detail:(%d+):(%-?%d+)$")
        generation, chat_id = tonumber(generation), tonumber(chat_id)
        if not generation or generation ~= self.public_search_generation then return end
        if chat_id and self.public_search_detail_pending_ids[chat_id] then
            self.public_search_detail_pending_ids[chat_id] = nil
            self.public_search_details_pending = math.max(0, self.public_search_details_pending - 1)
            self.public_search_pending = self.public_search_details_pending > 0
        end
        if not chat_id or chat.id ~= chat_id then return end
        self.public_search_result_ids = self.public_search_result_ids or {}
        if self.public_search_result_ids[chat_id] then return end
        self.public_search_result_ids[chat_id] = true
        self.public_search_results[#self.public_search_results + 1] = chat
    end

    function telegram:handle_public_user_search(chat)
        local generation = tonumber(tostring(chat["@extra"] or ""):match("^public_user_search:(%d+)$"))
        if not generation or generation ~= self.public_search_generation then return end
        self.public_search_user_pending = false
        self.public_search_result_ids = self.public_search_result_ids or {}
        if not self.public_search_result_ids[chat.id] then
            self.public_search_result_ids[chat.id] = true
            self.public_search_results[#self.public_search_results + 1] = chat
        end
    end

    function telegram:handle_search_chats(response)
        local generation = tonumber(tostring(response["@extra"] or ""):match("^chat_search:(%d+)$"))
        if not generation or generation ~= self.chat_search_generation then return end
        local results = {}
        for _, chat_id in ipairs(response.chat_ids or {}) do
            local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
            if chat then
                results[#results + 1] = chat
            else
                self:send({
                    ["@type"] = "getChat",
                    chat_id = chat_id,
                }, "chat_search_detail:" .. tostring(generation) .. ":" .. tostring(chat_id))
            end
        end
        self.search_chat_results = results
    end

    function telegram:handle_search_chat_detail(chat)
        local extra = tostring(chat["@extra"] or "")
        local generation, chat_id = extra:match("^chat_search_detail:(%d+):(%-?%d+)$")
        generation, chat_id = tonumber(generation), tonumber(chat_id)
        if not generation or generation ~= self.chat_search_generation or not chat_id or chat.id ~= chat_id then
            return
        end
        self:handle_new_chat(chat)
        self.search_chat_results[#self.search_chat_results + 1] = chat
    end

    function telegram:search_chat_messages(chat_id, query)
        if not chat_id then return end
        query = tostring(query or "")
        self.dialog_search_generation = self.dialog_search_generation or {}
        self.dialog_search_generation[chat_id] = (self.dialog_search_generation[chat_id] or 0) + 1
        self.dialog_search_query = self.dialog_search_query or {}
        self.dialog_search_results = self.dialog_search_results or {}
        self.dialog_search_error = nil
        self.dialog_search_query[chat_id] = query
        if query == "" then
            self.dialog_search_results[chat_id] = nil
            return
        end
        self.dialog_search_results[chat_id] = false
        self:send({
            ["@type"] = "searchChatMessages",
            chat_id = chat_id,
            query = query,
            sender_id = json.null,
            from_message_id = 0,
            offset = 0,
            limit = 50,
            filter = {["@type"] = "searchMessagesFilterEmpty"},
            topic_id = self:forum_message_scope(chat_id),
        }, "dialog_search:" .. tostring(chat_id) .. ":" .. tostring(self.dialog_search_generation[chat_id]))
    end

    function telegram:handle_dialog_search(response)
        local chat_id, generation = tostring(response["@extra"] or ""):match("^dialog_search:(%-?%d+):(%d+)$")
        chat_id, generation = tonumber(chat_id), tonumber(generation)
        if not chat_id or not generation or generation ~= (self.dialog_search_generation[chat_id] or 0) then
            return
        end
        local messages = response.messages or {}
        table.sort(messages, function(a, b)
            return (a.id or 0) < (b.id or 0)
        end)
        self.dialog_search_results[chat_id] = messages
    end

    function telegram:chat_is_pinned(chat, list)
        local position = chat_position(chat, list)
        return position ~= nil and position.is_pinned == true
    end

    function telegram:toggle_chat_pin(chat, list)
        self:send({["@type"] = "toggleChatIsPinned", chat_list = list, chat_id = chat.id,
            is_pinned = not self:chat_is_pinned(chat, list)}, "toggle_chat_pin")
    end

    function telegram:archive_chat(chat_id, archive)
        if not chat_id then return false end
        self.action_error = ""
        self.action_status = archive and "Archiving chat…" or "Moving chat out of the archive…"
        local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
        local target_list = {["@type"] = archive and "chatListArchive" or "chatListMain"}
        if chat then
            self.pending_archive_changes[chat_id] = {chat = chat, previous_list = chat.chat_list, target_list = target_list}
            self:handle_new_chat(chat, target_list)
        end
        self:send({
            ["@type"] = "addChatToList",
            chat_id = chat_id,
            chat_list = target_list,
        }, "archive:" .. tostring(chat_id) .. ":" .. tostring(archive))
        return true
    end

    function telegram:set_chat_muted(chat_id, muted)
        if not chat_id then return end
        self.action_error = ""
        self.action_status = muted and "Muting chat…" or "Unmuting chat…"
        local notification_settings = {
            ["@type"] = "chatNotificationSettings",
            use_default_mute_for = false,
            mute_for = muted and 2147483647 or 0,
            use_default_sound = true,
            sound = "",
            use_default_show_preview = true,
            show_preview = true,
            use_default_disable_pinned_message_notifications = true,
            disable_pinned_message_notifications = false,
            use_default_disable_mention_notifications = true,
            disable_mention_notifications = false,
        }
        local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
        self.pending_chat_mute_settings[chat_id] = chat and chat.notification_settings or false
        if chat then chat.notification_settings = notification_settings end
        self:send({
            ["@type"] = "setChatNotificationSettings",
            chat_id = chat_id,
            notification_settings = notification_settings,
        }, "mute:" .. tostring(chat_id) .. ":" .. tostring(muted))
    end

    function telegram:load_profile_media(chat_id, category)
        local filters = {
            photos = "searchMessagesFilterPhoto",
            videos = "searchMessagesFilterVideo",
            files = "searchMessagesFilterDocument",
            links = "searchMessagesFilterUrl",
            music = "searchMessagesFilterAudio",
            voice = "searchMessagesFilterVoiceAndVideoNote",
        }
        local filter = filters[category]
        if not chat_id or not filter then return end
        self.profile_media[category] = self.profile_media[category] or {}
        self.profile_media[category][chat_id] = {loading = true, messages = {}}
        self:send({
            ["@type"] = "searchChatMessages",
            chat_id = chat_id,
            query = "",
            sender_id = json.null,
            from_message_id = 0,
            offset = 0,
            limit = 30,
            filter = {["@type"] = filter},
            message_thread_id = 0,
        }, "profile_media:" .. tostring(chat_id) .. ":" .. category)
    end

    function telegram:handle_profile_media(response)
        local extra = tostring(response["@extra"] or "")
        local chat_id, category = extra:match("^profile_media:(%-?%d+):([%w_]+)$")
        chat_id = tonumber(chat_id)
        if not chat_id or not category then return end
        self.profile_media[category] = self.profile_media[category] or {}
        local messages = response.messages or {}
        self.profile_media[category][chat_id] = {
            loading = false,
            total_count = tonumber(response.total_count) or #messages,
            messages = messages,
        }
        for _, message in ipairs(messages) do
            self:ensure_photo(message)
            if message.sender_id and message.sender_id["@type"] == "messageSenderUser" then
                self:ensure_user(message.sender_id.user_id)
            end
        end
    end

end
