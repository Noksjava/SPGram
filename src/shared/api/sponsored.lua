local M = {}
local lifetime = 300

function M.link_host(url)
    if type(url) ~= "string" or url:find("[%s%z\\]") then return nil end
    local authority = url:match("^https://([^/#?]+)")
    if not authority then return nil end
    return authority:match("^([%w][%w.-]*)$") or authority:match("^([%w][%w.-]*):443$")
end

function M.channel(chat)
    local kind = chat and chat.type
    return kind and kind["@type"] == "chatTypeSupergroup" and kind.is_channel == true
end

function M.bot(chat, users)
    local kind = chat and chat.type
    if not kind or kind["@type"] ~= "chatTypePrivate" then return false end
    local user = users and users[kind.user_id]
    return user and user.type and user.type["@type"] == "userTypeBot"
end

function M.search_rows(local_chats, peers, public_chats, chat_for_id)
    local rows, seen = {}, {}
    local function append_organic(chats)
        for _, item in ipairs(chats) do
            if item.id and not seen[item.id] then
                seen[item.id] = true
                rows[#rows + 1] = item
            end
        end
    end
    append_organic(local_chats)
    for _, peer in ipairs(peers) do
        local chat = chat_for_id(peer.chat_id)
        if chat then
            rows[#rows + 1] = {id = chat.id, title = chat.title, sponsored_peer = peer}
        end
    end
    append_organic(public_chats)
    return rows
end

function M.spaced_items(items, entry)
    local gap = entry and math.floor(entry.spacing or 0) or 0
    if gap < 1 then return items end
    local placements, count, ad_index = {}, 0, 1
    for index = #items, 1, -1 do
        local item = items[index]
        if item.message or item.messages then
            count = count + (item.messages and #item.messages or 1)
            if count >= gap and entry.messages[ad_index] then

                placements[index] = entry.messages[ad_index]
                count, ad_index = 0, ad_index + 1
            end
        end
    end
    local output = {}
    for index, item in ipairs(items) do
        if placements[index] then output[#output + 1] = {channel_sponsor = placements[index]} end
        output[#output + 1] = item
    end
    return output
end

function M.install(client)

    function client:request_search_sponsors(query, generation)
        self.search_sponsors = nil
        if query == "" then return end
        self.search_sponsors = {generation = generation, items = {}, by_id = {}, seen = {}}
        self:send({["@type"] = "getSearchSponsoredChats", query = query},
            "search_sponsors:" .. tostring(generation))
    end

    function client:receive_search_sponsors(generation, response)
        local state = self.search_sponsors
        if not state or state.generation ~= generation or state.received then return end
        state.received = true
        for _, peer in ipairs(response.chats or {}) do
            if type(peer.unique_id) == "number" and type(peer.chat_id) == "number"
                and not state.by_id[peer.unique_id] then
                state.items[#state.items + 1] = peer
                state.by_id[peer.unique_id] = peer
            end
        end
    end

    function client:view_search_sponsor(peer)
        local state = self.search_sponsors
        if not state or state.by_id[peer.unique_id] ~= peer or state.seen[peer.unique_id] then return end
        self:send({["@type"] = "viewSponsoredChat", sponsored_chat_unique_id = peer.unique_id})
        state.seen[peer.unique_id] = true
    end

    function client:open_search_sponsor(peer)
        local state = self.search_sponsors
        if not state or state.by_id[peer.unique_id] ~= peer then return false end
        self:send({["@type"] = "openSponsoredChat", sponsored_chat_unique_id = peer.unique_id})
        return true
    end

    function client:report_search_sponsor(peer, option)
        local state = self.search_sponsors
        if not state or state.by_id[peer.unique_id] ~= peer then return false end
        local report = self.channel_sponsor_report
        if option ~= "" and (not report or report.peer ~= peer or not report.allowed[option]) then return false end
        local sequence = (self.channel_sponsor_report_sequence or 0) + 1
        self.channel_sponsor_report_sequence = sequence
        self.channel_sponsor_report = {peer = peer, sequence = sequence, allowed = {}}
        self:send({["@type"] = "reportSponsoredChat", sponsored_chat_unique_id = peer.unique_id,
            option_id = option}, "report_sponsor:" .. tostring(sequence))
        return true
    end

    function client:request_channel_sponsors(chat, now)
        if not M.channel(chat) and not M.bot(chat, self.users) then return end
        self.channel_sponsors = self.channel_sponsors or {}
        local entry = self.channel_sponsors[chat.id]
        if entry and now < entry.expires then return end
        for id, cached in pairs(self.channel_sponsors) do
            if now >= cached.expires then self.channel_sponsors[id] = nil end
        end
        local generation = (self.channel_sponsors_generation or 0) + 1
        self.channel_sponsors_generation = generation

        self.channel_sponsors[chat.id] = {generation = generation, pending = true, expires = now + 15}
        self:send({["@type"] = "getChatSponsoredMessages", chat_id = chat.id},
            "channel_sponsors:" .. tostring(chat.id) .. ":" .. tostring(generation))
    end

    function client:receive_channel_sponsors(chat_id, generation, result, now)
        local pending = self.channel_sponsors and self.channel_sponsors[chat_id]
        if not pending or not pending.pending or pending.generation ~= generation then return end
        local messages, by_id = {}, {}
        for _, ad in ipairs(result.messages or {}) do
            if type(ad) == "table" and type(ad.message_id) == "number" and not by_id[ad.message_id] then
                messages[#messages + 1] = ad
                by_id[ad.message_id] = ad
            end
        end
        self.channel_sponsors[chat_id] = {
            expires = now + lifetime, messages = messages, by_id = by_id,
            spacing = math.max(0, tonumber(result.messages_between) or 0), seen = {},
        }
    end

    function client:get_channel_sponsors(chat_id, now)
        local entry = self.channel_sponsors and self.channel_sponsors[chat_id]
        if entry and not entry.pending and entry.expires > now then return entry end
    end

    function client:view_channel_sponsor(chat_id, message_id, now)
        local entry = self:get_channel_sponsors(chat_id, now)
        if self.current_chat_id ~= chat_id or not entry or not entry.by_id[message_id]
            or entry.seen[message_id] then return false end
        self:send({["@type"] = "viewMessages", chat_id = chat_id, message_ids = {message_id},
            source = {["@type"] = "messageSourceChatHistory"}, force_read = false})
        entry.seen[message_id] = true
        return true
    end

    function client:click_channel_sponsor(chat_id, message_id, now)
        local entry = self:get_channel_sponsors(chat_id, now)
        local ad = entry and entry.by_id[message_id]
        local url = ad and ad.sponsor and ad.sponsor.url
        if self.current_chat_id ~= chat_id or type(url) ~= "string" then return nil end

        if not M.link_host(url) then return nil end
        self:send({["@type"] = "clickChatSponsoredMessage", chat_id = chat_id,
            message_id = message_id, is_media_click = false, from_fullscreen = false})
        return url
    end

    function client:report_channel_sponsor(chat_id, message_id, option, now)
        local entry = self:get_channel_sponsors(chat_id, now)
        local ad = entry and entry.by_id[message_id]
        if self.current_chat_id ~= chat_id or not ad or not ad.can_be_reported then return false end
        local report = self.channel_sponsor_report
        if option ~= "" and (not report or report.chat_id ~= chat_id
            or report.message_id ~= message_id or not report.allowed[option]) then return false end
        local sequence = (self.channel_sponsor_report_sequence or 0) + 1
        self.channel_sponsor_report_sequence = sequence
        self.channel_sponsor_report = {chat_id = chat_id, message_id = message_id, sequence = sequence, allowed = {}}
        self:send({["@type"] = "reportChatSponsoredMessage", chat_id = chat_id,
            message_id = message_id, option_id = option}, "report_sponsor:" .. tostring(sequence))
        return true
    end

    function client:receive_channel_sponsor_report(sequence, object)
        local report = self.channel_sponsor_report
        if not report or report.sequence ~= sequence then return end
        if report.peer then
            local state = self.search_sponsors
            if not state or state.by_id[report.peer.unique_id] ~= report.peer then return end
        elseif self.current_chat_id ~= report.chat_id then
            return
        end
        local kind = object["@type"]
        report.result = kind
        if kind == "reportSponsoredResultOptionRequired" then
            report.title = object.title
            report.options = {}
            for _, option in ipairs(object.options or {}) do
                if type(option.id) == "string" and option.id ~= "" and type(option.text) == "string" then
                    report.options[#report.options + 1] = option
                    report.allowed[option.id] = true
                end
            end
        end
    end
end

return M
