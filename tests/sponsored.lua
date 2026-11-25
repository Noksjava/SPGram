local TDLib = require("src.shared.api.tdlib_client")
local now = 0
love = {timer = {getTime = function() return now end}}
local requests = {}
local client = setmetatable({
    current_chat_id = -2,
    viewed_message_ids = {},
    chats_by_id = {[-2] = {unread_count = 4}},
    send = function(_, request, tag) requests[#requests + 1] = {request, tag} end,
}, {__index = TDLib})
local chat = {id = -2, type = {["@type"] = "chatTypeSupergroup", is_channel = true}}
client:request_channel_sponsors({id = 1, type = {["@type"] = "chatTypePrivate"}}, now)
assert(#requests == 0)
client:request_channel_sponsors(chat, now)
client:request_channel_sponsors(chat, now + 1)
assert(#requests == 1 and requests[1][1]["@type"] == "getChatSponsoredMessages")
local ad = {message_id = 91, sponsor = {url = "https://example.com/notice"}}
local response = {["@type"] = "sponsoredMessages", ["@extra"] = requests[1][2],
    messages = {ad, ad}, messages_between = 0}
client:handle(response)
assert(#client:get_channel_sponsors(-2, now).messages == 1)
assert(client:view_channel_sponsor(-2, 91, now))
assert(not client:view_channel_sponsor(-2, 91, now))
assert(requests[2][1]["@type"] == "viewMessages" and requests[2][1].message_ids[1] == 91)
assert(client:click_channel_sponsor(-2, 91, now) == ad.sponsor.url)
assert(requests[3][1]["@type"] == "clickChatSponsoredMessage")
ad.sponsor.url = "file:///local"
assert(not client:click_channel_sponsor(-2, 91, now) and #requests == 3)
ad.sponsor.url = "https://example.com@elsewhere.test/"
assert(not client:click_channel_sponsor(-2, 91, now) and #requests == 3)
client:mark_chat_viewed(-2, {{id = 1}})
assert(requests[4][1].message_ids[1] == 1 and client.chats_by_id[-2].unread_count == 4)
assert(not client:report_channel_sponsor(-2, 91, "", now))
ad.can_be_reported = true
assert(client:report_channel_sponsor(-2, 91, "", now))
client:handle({["@type"] = "reportSponsoredResultOptionRequired", ["@extra"] = requests[5][2],
    title = "Choose", options = {{id = "YQ==", text = "First"}}})
assert(not client:report_channel_sponsor(-2, 91, "Yg==", now))
assert(client:report_channel_sponsor(-2, 91, "YQ==", now))
client:handle({["@type"] = "reportSponsoredResultOk", ["@extra"] = requests[6][2]})
assert(client.channel_sponsor_report.result == "reportSponsoredResultOk")
now = 301
assert(not client:get_channel_sponsors(-2, now))
client:request_channel_sponsors(chat, now)
client:handle(response)
assert(not client:get_channel_sponsors(-2, now), "a stale response cannot replace a new fetch")

local S = require("src.shared.api.sponsored")
assert(S.telegram_link("https://t.me/example") and S.telegram_link("https://example.t.me/7"))
assert(S.telegram_link("tg://resolve?domain=example") and S.telegram_link("https://telegram.me/example"))
assert(not S.telegram_link("https://to.me/example") and not S.telegram_link("https://t.me.example.com/example"))
local destination
local link_client = setmetatable({
    current_chat_id = -2,
    send = function(_, request, tag) requests[#requests + 1] = {request, tag}; return tag end,
    handle_new_chat = function(_, opened) destination = opened end,
}, {__index = TDLib})
assert(not link_client:open_sponsor_link("https://example.com", now))
local public = link_client:open_sponsor_link("https://t.me/example", now)
assert(requests[#requests][1]["@type"] == "getInternalLinkType")
link_client:handle({["@type"] = "internalLinkTypePublicChat", ["@extra"] = public.token, chat_username = "example"})
assert(requests[#requests][1]["@type"] == "searchPublicChat" and requests[#requests][1].username == "example")
link_client:handle({["@type"] = "chat", ["@extra"] = public.token, id = -999})
assert(public.chat_id == -999 and destination.id == -999)
local person = link_client:open_sponsor_link("tg://resolve?domain=fixture", now, true)
link_client:handle({["@type"] = "internalLinkTypePublicChat", ["@extra"] = person.token, chat_username = "fixture"})
link_client:handle({["@type"] = "chat", ["@extra"] = person.token, id = 78,
    type = {["@type"] = "chatTypePrivate", user_id = 29}})
assert(person.user_id == 29 and not person.chat_id)
local invite = link_client:open_sponsor_link("https://t.me/+fixture", now)
link_client:handle({["@type"] = "internalLinkTypeChatInvite", ["@extra"] = invite.token, invite_link = "https://t.me/+fixture"})
assert(requests[#requests][1]["@type"] == "checkChatInviteLink")
link_client:handle({["@type"] = "chatInviteLinkInfo", ["@extra"] = invite.token, chat_id = 0, title = "Fixture"})
assert(invite.invite.title == "Fixture" and requests[#requests][1]["@type"] == "checkChatInviteLink")
link_client:join_sponsor_invite(invite, now)
assert(requests[#requests][1]["@type"] == "joinChatByInviteLink")
local stale = invite.token
local message = link_client:open_sponsor_link("https://t.me/example/7", now)
link_client:handle({["@type"] = "chat", ["@extra"] = stale, id = -777})
assert(not message.chat_id and destination.id == 78)
link_client:handle({["@type"] = "internalLinkTypeMessage", ["@extra"] = message.token, url = "https://t.me/example/7"})
assert(requests[#requests][1]["@type"] == "getMessageLinkInfo")
link_client:handle({["@type"] = "messageLinkInfo", ["@extra"] = message.token, chat_id = -999, message = {id = 7}})
assert(message.chat_id == -999 and message.message_id == 7)

local bot = {id = 12, type = {["@type"] = "chatTypePrivate", user_id = 12}}
client.users = {[12] = {type = {["@type"] = "userTypeBot"}}}
assert(S.bot(bot, client.users) and not S.bot(bot, {}))
client:request_channel_sponsors(bot, now)
assert(requests[#requests][1]["@type"] == "getChatSponsoredMessages" and requests[#requests][1].chat_id == 12)

local first, second = {message_id = 811}, {message_id = 822}
local function post(id) return {message = {id = id}} end
local function items()
    return {post(1), post(2), {date_label = "date"}, post(3), post(4)}
end
local spaced = S.spaced_items(items(), {spacing = 2, messages = {first, second}})
assert(#spaced == 7 and spaced[1].channel_sponsor == second and spaced[5].channel_sponsor == first)
assert(spaced[6].message.id == 3 and spaced[7].message.id == 4)
local paged = items()
table.insert(paged, 1, post(0))
local older = S.spaced_items(paged, {spacing = 2, messages = {first, second}})
assert(older[2].channel_sponsor == second and older[6].channel_sponsor == first)
assert(#S.spaced_items(items(), {spacing = 0, messages = {first}}) == 5)

client:request_search_sponsors("fixture", 8)
assert(requests[#requests][1]["@type"] == "getSearchSponsoredChats")
local peer = {unique_id = 700, chat_id = -2}
client:handle({["@type"] = "sponsoredChats", ["@extra"] = "search_sponsors:7", chats = {peer}})
assert(#client.search_sponsors.items == 0)
client:handle({["@type"] = "sponsoredChats", ["@extra"] = "search_sponsors:8", chats = {peer, peer}})
local rows = S.search_rows({{id = 10}}, client.search_sponsors.items, {{id = 20}, {id = 10}},
    function(id) return {id = id, title = "Fixture sponsor"} end)
assert(#rows == 3 and rows[1].id == 10 and rows[2].sponsored_peer == peer and rows[3].id == 20)
client:view_search_sponsor(peer)
local calls = #requests
client:view_search_sponsor(peer)
assert(#requests == calls and requests[calls][1]["@type"] == "viewSponsoredChat")
assert(client:open_search_sponsor(peer) and requests[#requests][1]["@type"] == "openSponsoredChat")
assert(client:report_search_sponsor(peer, ""))
client:handle({["@type"] = "reportSponsoredResultOptionRequired", ["@extra"] = requests[#requests][2],
    title = "Choose", options = {{id = "YQ==", text = "First"}}})
assert(not client:report_search_sponsor(peer, "invalid"))
assert(client:report_search_sponsor(peer, "YQ==") and requests[#requests][1]["@type"] == "reportSponsoredChat")
client:request_search_sponsors("", 9)
assert(not client:open_search_sponsor(peer))
print("Sponsored channel, bot and search routing, placement, impressions and reporting passed")
