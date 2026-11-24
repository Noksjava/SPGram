package.preload.utf8 = function() return {len = string.len} end

local function noop() end
local font = {
    getHeight = function() return 14 end,
    getWidth = function(_, text) return #text * 7 end,
    getWrap = function(_, text) return #text * 7, {text} end,
}
love = {
    timer = {getTime = function() return 100 end},
    graphics = setmetatable({getWidth = function() return 640 end, getHeight = function() return 480 end},
        {__index = function() return noop end}),
    filesystem = {getInfo = function() return nil end},
}

local client = require("src.shared.api.tdlib_client")
local messenger = require("src.features.chat.ui.chat_screen")
local font_set = {normal = font, small = font, tiny = font, subtitle = font}
local id_step = 1048576

local function fixture(title, chat_type, last_read, unread_count, outgoing, bookmark_path, total)
    total = total or 20
    local chat_id = chat_type == "chatTypePrivate" and 42 or -1000000000042
    local history = {}
    for index = 1, total do
        history[index] = {
            id = index * id_step, chat_id = chat_id, date = 1700000000 + index,
            is_outgoing = index == outgoing,
            content = {["@type"] = "messageText", text = {text = title .. " message " .. index, entities = {}}},
        }
    end
    local chat = {id = chat_id, title = title,
        type = {["@type"] = chat_type, user_id = 42, is_channel = true},
        last_read_inbox_message_id = last_read * id_step, unread_count = unread_count, last_message = history[total]}
    local requests, seen = {}, {}
    local tg = setmetatable({
        options = bookmark_path and {reading_position_file = bookmark_path},
        me = bookmark_path and {id = 77},
        chats = {chat}, chats_by_id = {[chat_id] = chat}, archive_chats_by_id = {},
        users = {[42] = {id = 42, first_name = "Fixture"}}, messages = {}, history_state = {}, viewed_message_ids = {},
        send = function(_, object, extra)
            requests[#requests + 1] = {object = object, extra = extra}
            if object["@type"] == "viewMessages" then
                assert(object.chat_id == chat_id and object.force_read == false)
                assert(object.source["@type"] == "messageSourceChatHistory")
                for _, id in ipairs(object.message_ids) do
                    assert(not seen[id], "Duplicate view notification")
                    seen[id] = true
                end
            end
            return extra
        end,
        request_channel_sponsors = noop, get_channel_sponsors = noop,
    }, {__index = client})
    local screen = messenger.new(font_set, tg)
    local function draw()
        screen:draw_conversation(chat, 224, 416, 480)
    end
    local function answer(anchor, offset, low, high)
        local request
        for index = #requests, 1, -1 do
            local candidate = requests[index]
            if candidate.object["@type"] == "getChatHistory" then request = candidate; break end
        end
        assert(request and request.object.chat_id == chat_id)
        assert(request.object.from_message_id == anchor * id_step, title .. ": wrong history anchor")
        assert(request.object.offset == offset, title .. ": wrong history offset")
        if not low then
            tg:handle({["@type"] = "error", ["@extra"] = request.extra, code = 500})
            return
        end
        local page = {}
        for index = high, low, -1 do page[#page + 1] = history[index] end
        tg:handle({["@type"] = "messages", ["@extra"] = request.extra, messages = page})
    end
    local function focus(index)
        local selected = screen:focused_message()
        assert(selected and selected.id == history[index].id,
            ("%s: expected focus on #%d, got %s"):format(title, index, tostring(selected and selected.id / id_step)))
        local position = screen.nav_pos[selected.id]
        assert(position.y < screen.conv_area_y + screen.conv_area_h and position.y + position.h > screen.conv_area_y,
            title .. ": focused message is offscreen")
    end
    local function key(name)
        screen:keypressed(name)
        screen.smooth_scroll = screen.model.scroll
        draw()
    end
    screen:keypressed("return")
    assert(tg.current_chat_id == chat_id)
    return {answer = answer, focus = focus, key = key, draw = draw, seen = seen, tg = tg, chat_id = chat_id}
end

local channel = fixture("Channel", "chatTypeSupergroup", 3, 17)
channel.answer(3, -15, 3, 12)
assert(next(channel.seen) == nil, "History fetch reported views before drawing")
channel.draw()
channel.focus(4)
assert(channel.seen[4 * id_step] and not channel.seen[12 * id_step])
channel.key("up")
channel.focus(3)
channel.key("up")
channel.answer(3, 0, 1, 3)
channel.draw()
channel.key("up")
channel.focus(2)
channel.key("up")
channel.focus(1)
for index = 2, 12 do
    channel.key("down")
    channel.focus(index)
end
channel.key("down")
channel.answer(12, -49, 12, 20)
channel.draw()
channel.focus(12)
assert(not channel.seen[20 * id_step], "Fetching the newer page marked its last message as viewed")
for index = 13, 20 do
    channel.key("down")
    channel.focus(index)
end
assert(channel.seen[20 * id_step])
local messages = channel.tg:get_messages(channel.chat_id)
assert(#messages == 20)
for index, message in ipairs(messages) do assert(message.id == index * id_step) end
print("20-message channel: opened at #4, browsed all 20 in order, preserved focus across short pages")

local dialog = fixture("Private chat", "chatTypePrivate", 8, 11, 9)
dialog.answer(8, -15, 1, 20)
dialog.draw()
dialog.focus(10)
dialog.key("up")
dialog.focus(9)
dialog.key("down")
dialog.focus(10)
assert(dialog.seen[10 * id_step] and not dialog.seen[20 * id_step])
print("20-message private chat: skipped an outgoing message when choosing first unread")

local unread = fixture("All unread", "chatTypeSupergroup", 0, 20)
unread.answer(0, 0, 13, 20)
unread.draw()
assert(next(unread.seen) == nil, "An incomplete initial page must not mark the channel read")
unread.answer(13, 0, 1, 13)
unread.draw()
unread.focus(1)
assert(unread.seen[id_step] and not unread.seen[20 * id_step])
print("20-message all-unread channel: loaded the older page before opening at #1")

local short = fixture("Short initial page", "chatTypePrivate", 8, 11, 9)
short.answer(8, -15, 7, 9)
short.draw()
assert(next(short.seen) == nil, "An outgoing message must not finish the unread lookup")
short.answer(9, -15)
short.draw()
assert(next(short.seen) == nil, "A failed unread lookup must not mark messages read")
short.key("up")
short.answer(9, -15, 9, 15)
short.draw()
short.focus(10)
print("20-message private chat: continued a short initial fetch until the first unread reply")

local fully_read = fixture("Fully read", "chatTypePrivate", 20, 0)
fully_read.answer(20, -15, 1, 20)
fully_read.draw()
fully_read.focus(20)
print("20-message fully read chat: opened at the latest message")

local saves = {}
love.filesystem.read = function(path) return saves[path] end
love.filesystem.write = function(path, data) saves[path] = data; return true end
local previous = fixture("Bookmark", "chatTypePrivate", 6, 14, nil, "fixture-read")
previous.answer(6, -15, 1, 17)
previous.draw()
previous.focus(7)
previous.key("up")
previous.key("up")
previous.focus(5)
previous.tg:close_chat()
local stored = assert(saves["fixture-read.77.json"])
assert(stored:find(tostring(5 * id_step), 1, true))
local reopened = fixture("Bookmark", "chatTypePrivate", 20, 0, nil, "fixture-read")
reopened.answer(5, -15, 1, 20)
reopened.draw()
reopened.focus(5)
assert(not reopened.seen[20 * id_step])

local deleted = fixture("Bookmark", "chatTypePrivate", 10, 10, nil, "fixture-read")
deleted.answer(5, -15, 6, 12)
deleted.draw()
deleted.focus(6)
print("Saved reading position survived reopening, and a deleted position resumed at the nearest later message")


local deep = fixture("Deep history", "chatTypeSupergroup", 3, 2496, 2500, nil, 2500)
deep.answer(3, -15, 1, 13)
deep.draw()
deep.focus(4)
local peer = deep.tg.chats_by_id[deep.chat_id]
peer.last_read_inbox_message_id = 1500 * id_step
deep.key("r2")
deep.answer(1500, 0, 1451, 1500)
deep.draw()
deep.focus(1500)
assert(#deep.tg:get_messages(deep.chat_id) == 50 and deep.tg.history_state[deep.chat_id].has_newer)
assert(not deep.seen[1501 * id_step])
deep.key("down")
deep.answer(1500, -49, 1500, 1540)
deep.draw()
deep.key("down")
deep.focus(1501)

local cached = fixture("Read marker inside loaded history", "chatTypePrivate", 8, 11, 20)
cached.answer(8, -15, 7, 17)
cached.draw()
cached.focus(9)
cached.key("r2")
cached.focus(8)
assert(#cached.tg:get_messages(cached.chat_id) == 2 and cached.tg.history_state[cached.chat_id].has_newer)

fully_read.key("up")
fully_read.focus(19)
fully_read.key("r2")
fully_read.focus(20)
assert(not fully_read.tg.history_state[fully_read.chat_id].has_newer)

local gap = fixture("Deleted read marker", "chatTypePrivate", 8, 11, 20)
gap.answer(8, -15, 7, 17)
gap.draw()
gap.focus(9)
gap.tg.chats_by_id[gap.chat_id].last_read_inbox_message_id = 18 * id_step
gap.key("r2")
gap.answer(18, 0, 19, 20)
assert(gap.tg.history_state[gap.chat_id].jump_error)
gap.draw()
gap.focus(9)
gap.key("r2")
gap.answer(18, 0, 13, 17)
gap.draw()
gap.focus(17)
assert(not gap.seen[19 * id_step] and gap.tg.history_state[gap.chat_id].has_newer)

local never_read = fixture("Unread chat", "chatTypePrivate", 0, 20)
never_read.answer(0, 0, 1, 20)
never_read.draw()
never_read.focus(1)
never_read.key("r2")
never_read.focus(1)
assert(never_read.tg.history_state[never_read.chat_id].jump_error == "No last-read message yet.")

local slow = fixture("Delayed opening", "chatTypePrivate", 8, 11, 20)
local initial = slow.tg.history_state[slow.chat_id]
local initial_token = initial.token
slow.key("r2")
assert(initial.loading and initial.token == initial_token and not initial.jump)
slow.tg:check_history_timeout(initial.history_deadline + 1)
assert(not initial.loading and initial.error)
slow.answer(8, -15, 7, 17)
assert(#slow.tg:get_messages(slow.chat_id) == 0)
assert(slow.tg:load_more_history(slow.chat_id))
slow.answer(8, -15, 7, 17)
slow.draw()
slow.focus(9)
slow.tg.chats_by_id[slow.chat_id].last_read_inbox_message_id = 18 * id_step
slow.key("r2")
slow.tg:check_history_timeout(initial.jump.deadline + 1)
assert(initial.jump_error and not initial.loading)
slow.draw()
slow.focus(9)
print("R2 targets the last-read message, preserves the unread tail, and handles deleted markers and timeouts")

local wrapping = 0
local wrap = font.getWrap
font.getWrap = function(...)
    wrapping = wrapping + 1
    return wrap(...)
end
local long_chat = fixture("Long loaded history", "chatTypeSupergroup", 400, 0, nil, nil, 400)
long_chat.answer(400, -15, 1, 400)
long_chat.draw()
local cold_wraps = wrapping
wrapping = 0
long_chat.draw()
assert(cold_wraps >= 400 and wrapping < 30, "A stable frame must only wrap visible rows")
local list = long_chat.tg:get_messages(long_chat.chat_id)
list[400].content = {["@type"] = "messageText", text = {text = "Edited in place"}}
wrapping = 0
long_chat.draw()
assert(wrapping >= 400, "Edits must invalidate conversation layout")
list[400].interaction_info = {reply_info = {reply_count = 1}}
wrapping = 0
long_chat.draw()
assert(wrapping >= 400, "New comments or reactions must invalidate conversation layout")
font.getWrap = wrap
print("Stable conversation frames reuse the measured history and rebuild after edits and interaction updates")
