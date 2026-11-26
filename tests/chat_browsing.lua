package.preload.utf8 = function() return {len = string.len} end

local function noop() end
local now = 100
local font = {
    getHeight = function() return 14 end,
    getWidth = function(_, text) return #text * 7 end,
    getWrap = function(_, text) return #text * 7, {text} end,
}
love = {
    timer = {getTime = function() return now end},
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
        send = function(client, object, extra)
            requests[#requests + 1] = {object = object, extra = extra}
            if object["@type"] == "viewMessages" then
                assert(object.chat_id == chat_id and object.force_read == false)
                local scoped = client.forum and client.forum.active
                assert(object.source["@type"] == (scoped and "messageSourceForumTopicHistory" or "messageSourceChatHistory"))
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
        screen:keyreleased(name)
        screen.smooth_scroll = screen.model.scroll
        draw()
    end
    screen:keypressed("return")
    assert(tg.current_chat_id == chat_id)
    return {answer = answer, focus = focus, key = key, draw = draw, seen = seen, tg = tg, chat_id = chat_id,
        screen = screen, requests = requests, history = history}
end

local channel = fixture("Channel", "chatTypeSupergroup", 3, 17)
channel.answer(3, -15, 3, 12)
assert(next(channel.seen) == nil, "History fetch reported views before drawing")
channel.draw()
channel.focus(4)
assert(channel.tg.history_state[channel.chat_id].unread_divider_id == 4 * id_step)
channel.tg:handle({["@type"] = "updateChatReadInbox", chat_id = channel.chat_id,
    last_read_inbox_message_id = 4 * id_step, unread_count = 16})
assert(channel.tg.history_state[channel.chat_id].unread_divider_id == 4 * id_step)
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
local items = require("src.features.chat.ui.chat_screen_helpers").conversation_items(messages, 4 * id_step)
assert(items[5].unread_divider and items[6].message.id == 4 * id_step)
local later_items = require("src.features.chat.ui.chat_screen_helpers").conversation_items({messages[5]}, 4 * id_step)
assert(#later_items == 2 and not later_items[2].unread_divider)
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
assert(unread.tg.history_state[unread.chat_id].unread_divider_id == id_step)
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
assert(not never_read.tg.history_state[never_read.chat_id].jump_error)

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

do
    local hold = fixture("Hold to newest", "chatTypePrivate", 3, 17)
    hold.answer(3, -15, 1, 11)
    hold.draw()
    local sprite, scale_x, scale_y, arrow_x, arrow_y = {}, nil, nil, nil, nil
    hold.screen.latest_arrow, hold.screen.latest_frames = sprite, {}
    love.graphics.draw = function(image, quad, x, y, rotation, sx, sy)
        if image == sprite then scale_x, scale_y, arrow_x, arrow_y = sx, sy, x, y end
    end
    hold.screen:keypressed("r2")
    now = 100.65
    hold.screen:update_read_jump(now)
    assert(math.abs(hold.screen:read_jump_progress(now) - 0.5) < 0.000001)
    hold.screen:draw_read_jump(600, 400, nil, now, 17)
    assert(hold.screen.read_jump_hit.h == 48 and hold.screen.read_jump_hit.w == 36)
    assert(scale_x == 28 / 32 and scale_y == scale_x)
    assert(arrow_x ~= 598 or arrow_y ~= 396)
    local motion = require("src.shared.system.media_settings")
    motion.set("ui_motion", false)
    hold.screen:draw_read_jump(600, 400, nil, now, 17)
    assert(hold.screen.read_jump_hit.h == 42 and scale_y == 22 / 32 and arrow_x == 604 and arrow_y == 402)
    motion.set("ui_motion", true)
    now = 101.29
    hold.screen:update_read_jump(now)
    assert(not hold.tg.history_state[hold.chat_id].jump)
    now = 101.3
    hold.screen:update_read_jump(now)
    assert(hold.tg.history_state[hold.chat_id].jump.newest)
    hold.screen:draw_read_jump(600, 400, nil, now, 17)
    assert(hold.screen.read_jump_hit.h == 53 and hold.screen.read_jump_hit.w == 41)
    assert(scale_x == 33 / 32 and scale_y == scale_x and arrow_x == 593)
    love.graphics.draw = noop
    hold.screen:keyreleased("r2")
    hold.answer(0, 0, 10, 20)
    hold.draw()
    hold.focus(20)
    now = 103
    hold.screen:update_read_jump(now)
    assert(not hold.screen.read_jump_hold)
end

do
    local view = fixture("Forum", "chatTypeSupergroup", 0, 20)
    local tg, screen, chat_id = view.tg, view.screen, view.chat_id
    local group = tg.chats_by_id[chat_id]
    group.type.is_channel, group.type.supergroup_id = false, 42
    tg:handle({["@type"] = "updateSupergroup", supergroup = {["@type"] = "supergroup", id = 42, is_forum = true}})
    local forum = assert(tg.forum)
    assert(tg.forum_groups[42] and not forum.active and view.requests[#view.requests].object["@type"] == "getForumTopics")
    local original, count = forum.token, #view.requests
    now = forum.deadline + 1
    tg:handle({["@type"] = "updateConnectionState", state = {["@type"] = "connectionStateWaitingForNetwork"}})
    tg:check_forum_topics(now)
    assert(forum.token == original and #view.requests == count)
    tg:handle({["@type"] = "updateConnectionState", state = {["@type"] = "connectionStateReady"}})
    tg:check_forum_topics(now)
    assert(forum.token ~= original and forum.previous_token == original and #view.requests == count + 1)
    assert(view.requests[#view.requests].object.limit == 8)
    local retry = forum.token
    now = forum.deadline + 1
    tg:check_forum_topics(now)
    assert(forum.slow and forum.token == retry and #view.requests == count + 1)
    local function topic(id, name, closed)
        return {info = {forum_topic_id = id, name = name, is_closed = closed},
            last_read_inbox_message_id = 3 * id_step, unread_count = 2, last_message = view.history[5]}
    end
    local first, second = topic(1, "General"), topic(9, "Hardware", true)
    local late_reply = require("dkjson").encode({["@type"] = "forumTopics", ["@extra"] = original, topics = {first},
        next_offset_date = 50, next_offset_message_id = 3 * id_step, next_offset_forum_topic_id = 1})
    tg.out_channel = {pop = function() local reply = late_reply; late_reply = nil; return reply end}
    tg:poll()
    assert(#forum.topics == 1 and not forum.slow and not forum.token and not forum.error)
    tg:handle({["@type"] = "forumTopics", ["@extra"] = retry, topics = {second}})
    assert(#forum.topics == 1 and not forum.complete)
    screen:draw_forum_topics(group, forum, 224, 416, 480)
    screen:keypressed("down")
    assert(view.requests[#view.requests].object.offset_forum_topic_id == 1)
    now = forum.deadline + 1
    tg:check_forum_topics(now)
    local prior = forum.previous_token
    tg:handle({["@type"] = "error", ["@extra"] = prior, code = 500})
    assert(#forum.topics == 1 and not forum.error)
    tg:handle({["@type"] = "forumTopics", ["@extra"] = forum.token, topics = {first, second}})
    assert(#forum.topics == 2 and forum.complete)
    screen:keypressed("return")
    local request = view.requests[#view.requests]
    assert(request.object["@type"] == "getForumTopicHistory" and request.object.forum_topic_id == 1)
    assert(request.object.from_message_id == 3 * id_step and request.object.limit == 24)
    tg:handle({["@type"] = "messages", ["@extra"] = request.extra,
        messages = {view.history[5], view.history[4], view.history[3]}})
    assert(tg.history_state[chat_id].initial_focus_id == view.history[4].id)
    view.draw()
    view.focus(4)
    assert(next(view.seen))
    tg:send_message(chat_id, "Topic reply")
    assert(view.requests[#view.requests].object.topic_id.forum_topic_id == 1)
    tg:search_chat_messages(chat_id, "hardware")
    assert(view.requests[#view.requests].object.topic_id.forum_topic_id == 1)
    local foreign = view.history[8]
    foreign.is_outgoing = true
    foreign.topic_id = {["@type"] = "messageTopicForum", forum_topic_id = 9}
    tg:handle_new_message(foreign)
    assert(#tg:get_messages(chat_id) == 3 and forum.by_id[9].last_message.id == foreign.id)
    assert(forum.by_id[9].last_message.preview == foreign.content.text.text)
    tg:handle({["@type"] = "updateMessageContent", chat_id = chat_id, message_id = foreign.id,
        new_content = {["@type"] = "messageVideo", caption = {text = "Edited\nvideo caption"}}})
    assert(forum.by_id[9].last_message.preview == "Edited video caption")
    assert(forum.by_id[1].last_message.preview == view.history[5].content.text.text)
    screen.model.input = "Saved in General"
    screen:keypressed("escape")
    assert(not forum.active and #tg:get_messages(chat_id) == 0 and #forum.topics == 2)
    screen:keypressed("down")
    screen:keypressed("return")
    assert(forum.active.info.forum_topic_id == 9 and not screen:can_show_composer(group))
    assert(view.requests[#view.requests].object.forum_topic_id == 9)
    tg:handle({["@type"] = "messages", ["@extra"] = request.extra, messages = {view.history[3]}})
    assert(#tg:get_messages(chat_id) == 0)
    screen:keypressed("escape")
    screen:keypressed("up")
    screen:keypressed("return")
    assert(screen.model.input == "Saved in General")
    screen:keypressed("escape")
    screen:keypressed("escape")
    assert(not tg.current_chat_id and not tg.forum)
end
print("Forum topics retry after reconnection, accept late worker replies, paginate and isolate history, search and sending.")

do
    local view = fixture("Busy forum", "chatTypeSupergroup", 0, 12000)
    local tg, screen, chat_id = view.tg, view.screen, view.chat_id
    local group = tg.chats_by_id[chat_id]
    group.type.is_channel, group.type.supergroup_id = false, 243
    tg:close_chat()
    tg.forum_groups = {[243] = true}
    local start = #view.requests
    tg:open_chat(chat_id)
    local forum = tg.forum
    assert(view.requests[start + 1].object["@type"] == "openChat")
    assert(view.requests[start + 2].object["@type"] == "getForumTopics" and view.requests[start + 2].object.limit == 12)
    local function topic(id)
        local icon = id == 1 and {custom_emoji_id = "0", color = 0x6FB9F0}
            or {custom_emoji_id = tostring(id) .. "455000000000000001"}
        return {info = {forum_topic_id = id, name = "Topic " .. id, icon = icon}, unread_count = 500,
            last_message = {id = id * id_step, content = {["@type"] = "messageText", text = {text = "A preview " .. id}}}}
    end
    tg:handle({["@type"] = "forumTopics", ["@extra"] = forum.token, total_count = 1000,
        topics = {topic(1), topic(2)}, next_offset_date = 50, next_offset_forum_topic_id = 2})
    local graphics, rendered, resolved = love.graphics, {}, {}
    local emoji = {getDimensions = function() return 28, 28 end}
    graphics.print = function(text) rendered[text] = true end
    graphics.draw = function(image) assert(image == emoji); rendered.emoji = true end
    screen.custom_emoji_image = function(id) resolved[#resolved + 1] = id; return emoji end
    screen:draw_forum_topics(group, forum, 224, 416, 480)
    assert(rendered["#"] and rendered.emoji and rendered["A preview 1"] and rendered["A preview 2"])
    assert(#resolved == 1 and resolved[1] == topic(2).info.icon.custom_emoji_id)
    tg:check_forum_topics(now)
    assert(#forum.topics == 2 and #forum.rows == 2)
    assert(not forum.topics[1].last_message.content)
    local next_page = view.requests[#view.requests].object
    assert(next_page["@type"] == "getForumTopics" and next_page.limit == 20 and next_page.offset_forum_topic_id == 2)
    local more = {}
    for id = 3, 22 do more[#more + 1] = topic(id) end
    tg:handle({["@type"] = "forumTopics", ["@extra"] = forum.token, total_count = 1000,
        topics = more, next_offset_date = 60, next_offset_forum_topic_id = 22})
    assert(#forum.topics == 22)
    resolved = {}
    screen:draw_forum_topics(group, forum, 224, 416, 480)
    assert(#resolved == #forum.rows - 1 and #forum.rows < 22)
    graphics.draw, graphics.print = noop, noop
    for index = start + 1, #view.requests do
        local request = view.requests[index].object
        assert(request["@type"] ~= "getForumTopicHistory" and request["@type"] ~= "getChatHistory")
    end
    tg:close_chat()
    tg:open_chat(chat_id)
    forum = tg.forum
    assert(#forum.topics == 2 and forum.token and not forum.loaded)
    assert(forum.topics[1].last_message.preview == "A preview 1")
    screen:keypressed("return")
    assert(forum.active.info.forum_topic_id == 1)
    assert(view.requests[#view.requests].object["@type"] == "getForumTopicHistory")
    local active = forum.active
    tg:handle({["@type"] = "forumTopics", ["@extra"] = forum.token, total_count = 1000,
        topics = {topic(2), topic(1)}, next_offset_date = 50, next_offset_forum_topic_id = 1})
    assert(forum.active == active and forum.by_id[1] == active and forum.index == 2)
end
print("A 1,000-topic forum displays short pages without opening topic histories, and its first page is reusable.")

do
    local graphics = love.graphics
    local old_image, old_batch, old_draw = graphics.newImage, graphics.newSpriteBatch, graphics.draw
    local old_new_shader, old_set_shader = graphics.newShader, graphics.setShader
    local read, write, info = love.filesystem.read, love.filesystem.write, love.filesystem.getInfo
    local added, batches, released, draw_x, draw_y = 0, 0, 0
    local image = {getWidth = function() return 600 end, getHeight = function() return 448 end,
        setFilter = noop, release = function() released = released + 1 end}
    local batch = {add = function() added = added + 1 end, release = function() released = released + 1 end}
    local paths = {}
    local shader_count, active_shader, shader_used, draw_angle = 0
    local uniforms = {}
    local shader = {send = function(_, name, pair)
        uniforms[name] = {unpack(pair)}
    end}
    graphics.newShader = function(source)
        assert(source:find("Texel", 1, true))
        shader_count = shader_count + 1
        return shader
    end
    graphics.setShader = function(value) active_shader = value end
    graphics.newImage = function(path) paths[#paths + 1] = path; return image end
    graphics.newSpriteBatch = function(texture, capacity)
        assert(texture == image and (capacity == 63 or capacity == 99))
        batches = batches + 1
        return batch
    end
    graphics.draw = function(drawable, x, y, angle)
        assert(drawable == batch)
        shader_used = active_shader
        draw_x, draw_y, draw_angle = x, y, angle
    end
    local saved
    love.filesystem.write = function(_, value) saved = value; return true end
    love.filesystem.read = function() return saved end
    local media = require("src.shared.system.media_settings")
    local screen = messenger.new(font_set, setmetatable({}, {__index = client}))
    assert(not screen:draw_chat_background(0, 56, 640, 402, 0))
    media.set_chat_background("retroscroll")
    assert(saved:find("chat_background=retroscroll", 1, true))
    assert(screen:draw_chat_background(0, 56, 640, 402, 0))
    assert(paths[1] == "res/telegram.png")
    assert(draw_x == 0 and draw_y == 56 and added == 63 and batches == 1)
    screen:draw_chat_background(0, 56, 640, 402, 1)
    assert(draw_x == -74 and draw_y == 38 and batches == 1)
    assert(shader_count == 0)
    media.cycle_retroscroll_effect("color", 1)
    screen:draw_chat_background(0, 56, 640, 402, 0)
    assert(shader_used == shader and not active_shader and uniforms.hueRotation[1] == 1 and uniforms.hueRotation[2] == 0)
    screen:draw_chat_background(0, 56, 640, 402, 9)
    assert(math.abs(uniforms.hueRotation[1]) < 0.000001 and uniforms.hueRotation[2] == 1 and shader_count == 1 and batches == 1)
    media.set("ui_motion", false)
    screen:draw_chat_background(0, 56, 640, 402, 1)
    assert(draw_x == 0 and draw_y == 56 and batches == 1 and not shader_used)
    media.set("ui_motion", true)
    screen:draw_chat_background(0, 56, 640, 402, 335)
    assert(draw_x == -40 and draw_y == 56 and batches == 1)
    media.set_chat_background("static")
    screen:draw_chat_background(0, 56, 640, 402, 1)
    assert(draw_x == 0 and draw_y == 56 and not shader_used)
    saved = "chat_background=retroscroll\n"
    media.load()
    assert(media.chat_background() == "retroscroll")
    love.filesystem.getInfo = function(path)
        return path == "effects/retroscroll/themes/night.png" and {type = "file"} or nil
    end
    media.set_chat_background("retroscroll", "night.png")
    assert(screen:draw_chat_background(0, 56, 640, 402, 1))
    assert(paths[2] == "effects/retroscroll/themes/night.png" and released == 2 and batches == 2)
    media.cycle_retroscroll_effect("color", 2)
    screen:draw_chat_background(0, 56, 640, 402, 0)
    local teal = uniforms.tint[1]
    screen:draw_chat_background(0, 56, 640, 402, 14)
    assert(uniforms.tint[1] > teal and uniforms.hueRotation[1] == 0)
    media.cycle_retroscroll_effect("motion", 1)
    screen:draw_chat_background(0, 56, 640, 402, 4.5)
    assert(draw_angle > 0 and draw_x == 320 and draw_y == 257 and batches == 3)
    media.cycle_retroscroll_effect("color", 1)
    media.cycle_retroscroll_effect("motion", 1)
    screen:draw_chat_background(0, 56, 640, 402, 0)
    local first_palette = uniforms.tint[1]
    assert(uniforms.ripple[1] > 0)
    screen:draw_chat_background(0, 56, 640, 402, 5)
    assert(uniforms.tint[1] == first_palette)
    screen:draw_chat_background(0, 56, 640, 402, 6)
    assert(uniforms.tint[1] ~= first_palette and not active_shader)
    media.cycle_retroscroll_effect("motion", 1)
    screen:draw_chat_background(0, 56, 640, 402, 10)
    assert(draw_x == -26 and not draw_angle and uniforms.ripple[1] == 0 and shader_count == 1)
    screen:draw_chat_background(0, 56, 640, 402, 40)
    assert(draw_x == 0 and draw_y == 56)
    media.set_chat_background("off")
    assert(not screen:draw_chat_background(0, 56, 640, 402, 1) and released == 6)
    assert(not screen:draw_chat_background(0, 56, 640, 402, 2) and released == 6)
    media.cycle_retroscroll_effect("color", 1)
    media.cycle_retroscroll_effect("motion", 1)
    graphics.newImage, graphics.newSpriteBatch, graphics.draw = old_image, old_batch, old_draw
    graphics.newShader, graphics.setShader = old_new_shader, old_set_shader
    love.filesystem.read, love.filesystem.write, love.filesystem.getInfo = read, write, info
end

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
