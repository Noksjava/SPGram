package.preload.utf8 = function() return {len = string.len} end

local removed = {}
love = {
    timer = {getTime = function() return 1 end},
    filesystem = {
        remove = function(name) removed[#removed + 1] = name end,
        write = function(name) removed.cancelled = name end,
    },
    graphics = {getWidth = function() return 640 end, getHeight = function() return 480 end},
}

local client = require("src.shared.api.tdlib_client")
local requests = {}
local tg = setmetatable({
    chats = {}, archive_chats = {}, messages = {}, history_state = {}, users = {},
    chats_by_id = {[-42] = {id = -42, last_message = {id = 100},
        last_read_inbox_message_id = 50, unread_count = 4}},
    archive_chats_by_id = {}, videos = {}, video_notes = {}, video_by_message = {},
    video_note_by_message = {}, notifications = {},
    ensure_user_photo = function() end, ensure_sticker = function() end,
    animations = {}, animation_by_message = {}, ensure_voice_note = function() end,
    ensure_audio = function() end, request_channel_sponsors = function() end,
    send = function(_, data, extra)
        requests[#requests + 1] = {data = data, extra = extra}
        return extra
    end,
}, {__index = client})

local function response(token, ...)
    local messages = {}
    for _, id in ipairs({...}) do
        messages[#messages + 1] = {id = id, chat_id = -42, content = {["@type"] = "messageText"}}
    end
    tg:handle_history({["@extra"] = token, messages = messages})
end

tg:open_chat(-42)
local first = requests[#requests]
assert(first.data.from_message_id == 50 and first.data.offset < 0)
response(first.extra, 55, 50, 40)
assert(tg.history_state[-42].initial_focus_id == 55)
assert(tg.history_state[-42].has_more and tg.history_state[-42].has_newer)
assert(tg:load_more_history(-42))
local older = requests[#requests]
assert(older.data.from_message_id == 40)
response(older.extra, 40, 30)
assert(#tg.messages[-42] == 4 and tg.messages[-42][1].id == 30)
assert(tg:load_newer_history(-42))
local newer = requests[#requests]
assert(newer.data.from_message_id == 55 and newer.data.offset < 0)
response(newer.extra, 100, 70, 55)
assert(#tg.messages[-42] == 6 and not tg.history_state[-42].has_newer)
tg:close_chat()
tg.chats_by_id[-42].unread_count = 0
tg:open_chat(-42)
local latest = requests[#requests]
assert(latest.data.from_message_id == 50 and latest.data.offset == -15)
response(first.extra, 5)
assert(#tg.messages[-42] == 0)
response(latest.extra, 100)
assert(requests[#requests].data.from_message_id == 100 and tg.history_state[-42].loading)

tg:handle_user({["@extra"] = "me", id = 10})
assert(requests[#requests].extra == "saved_messages" and requests[#requests].data.user_id == 10)
tg:handle({["@type"] = "chat", ["@extra"] = "saved_messages", id = 10, title = "Account"})
tg:handle_new_chat({id = -99, positions = {{list = {["@type"] = "chatListArchive"}, order = "100"}}})
assert(tg.saved_chat_id == 10 and tg.archive_chats_by_id[-99])
local messenger = require("src.features.chat.ui.chat_screen")
local screen = setmetatable({tg = tg, model = {}, fonts = {small = {getHeight = function() return 14 end}},
    list_kind = "main"}, {__index = messenger})
local rows = screen:get_visible_chat_list()
assert(rows[1].title == "Saved Messages" and rows[1].id == 10 and rows[2].title == "Archived Chats")
screen:select_list_chat(rows[2])
assert(screen:get_visible_chat_list()[2].id == -99)
assert(requests[#requests].extra == "loadArchiveChats")
screen.context_menu = {x = -40, y = -30, items = {{label = "Copy"}}}
local x, y, width, height = screen:context_menu_bounds(640, 480)
assert(x >= 8 and y >= 8 and x + width <= 632 and y + height <= 472)

local listings = setmetatable({chats_by_id = {}, archive_chats_by_id = {}, pending_archive_changes = {}}, {__index = client})
listings.send = function(_, _, extra) return extra end
local main_list = {["@type"] = "chatListMain"}
local archive_list = {["@type"] = "chatListArchive"}
local folder_list = {["@type"] = "chatListFolder", chat_folder_id = 8}
local function listed(id, list)
    for _, chat in ipairs(list or {}) do
        if chat.id == id then return true end
    end
    return false
end
local function event(kind, data)
    data["@type"] = kind
    listings:handle(data)
end
event("updateNewChat", {chat = {id = 11, positions = {}, title = "Previously seen"}})
event("updateNewChat", {chat = {id = 12, chat_lists = {}, positions = {{list = main_list, order = "30"}}}})
event("updateNewChat", {chat = {id = 13, chat_lists = {main_list}, positions = {}}})
event("updateNewChat", {chat = {id = 14, chat_lists = {folder_list}, positions = {}}})
assert(listings.chats_by_id[11] and listings.chats_by_id[12])
assert(#listings.chats == 1 and listed(13, listings.chats))
assert(listed(14, listings.filter_chats[8]) and not listed(14, listings.chats))
event("updateChatPosition", {chat_id = 13, position = {list = main_list, order = "0"}})
assert(listed(13, listings.chats), "Explicit membership is independent of ordering")
event("updateChatRemovedFromList", {chat_id = 13, chat_list = main_list})
event("updateChatAddedToList", {chat_id = 13, chat_list = archive_list})
assert(not listed(13, listings.chats) and listed(13, listings.archive_chats))
event("updateChatRemovedFromList", {chat_id = 13, chat_list = archive_list})
assert(not listed(13, listings.archive_chats) and listings.chats_by_id[13])
event("updateChatRemovedFromList", {chat_id = 14, chat_list = folder_list})
assert(not listings.filter_chats[8])

event("updateChatPosition", {chat_id = 11, position = {list = main_list, order = "70"}})
assert(listed(11, listings.chats))
event("updateChatPosition", {chat_id = 11, position = {list = main_list, order = "0"}})
assert(not listed(11, listings.chats))
event("updateChatLastMessage", {chat_id = 11, positions = {{list = archive_list, order = "75"}}})
assert(listed(11, listings.archive_chats))
event("updateChatDraftMessage", {chat_id = 11, positions = {}})
assert(not listed(11, listings.archive_chats) and listings:chat_title(11) == "Previously seen")
listings.chat_search_generation, listings.search_chat_results = 2, {}
event("chat", {["@extra"] = "chat_search_detail:2:15", id = 15, chat_lists = {}, positions = {}})
assert(listed(15, listings.search_chat_results) and not listed(15, listings.chats))
print("Chat list membership, archive moves, removals, legacy positions, and search-only chats passed")

local video = {id = 13, content = {["@type"] = "messageVideo",
    video = {duration = 600, video = {id = 123, size = 1200}},
    alternative_videos = {{codec = "h264", width = 640, height = 360, video = {id = 124, size = 600}}}}}
local count = #requests
local kind, id, entry = tg:media_file_for_message(video)
assert(kind == "video" and id == 124 and not entry and #requests == count)
assert(tg:request_media_playback(video))
assert(#requests == count + 1 and requests[#requests].data["@type"] == "downloadFile")
assert(tg.active_video.duration == 600 and requests[#requests].data.file_id == 124)
assert(tg:request_media_playback(video) and #requests == count + 1)
local alternate_token = tg.active_video.download_token
tg:handle({["@type"] = "error", ["@extra"] = alternate_token, code = 400})
assert(tg.active_video.status == "error")
assert(tg:request_media_playback(video))
assert(tg.active_video.file_id == 123 and requests[#requests].data.file_id == 123)
tg:handle({["@type"] = "error", ["@extra"] = alternate_token, code = 400})
assert(tg.active_video.status == "downloading")
tg:handle({["@type"] = "error", ["@extra"] = tg.active_video.download_token, code = 400})
assert(tg:request_media_playback(video) and tg.active_video.file_id == 123)

tg.active_video.status, tg.active_video.name = "decoding", "spgram-video-1.ogv"
local progress_path = os.tmpname()
local progress_file = assert(io.open(progress_path, "wb"))
progress_file:write("frame=120\nout_time_us=8000000\nprogress=continue\nframe=135\nout_time_us=9000000\n")
progress_file:close()
tg.active_video.progress_path = progress_path
tg:poll_video_progress(1)
os.remove(progress_path)
assert(tg.active_video.converted_seconds == 9)
tg:stop_media_playback(video)
assert(not tg.active_video and not tg.videos[123] and removed.cancelled == "spgram-video-1.ogv.cancel")
assert(requests[#requests - 1].data["@type"] == "cancelDownloadFile")
assert(requests[#requests].data["@type"] == "deleteFile")
tg:finish_video_conversion({name = "spgram-video-1.ogv", ok = true})
assert(removed[2] == "spgram-video-1.ogv.cancel" and removed[3] == "spgram-video-1.ogv.progress"
    and removed[4] == "spgram-video-1.ogv")
video.content.alternative_videos = nil
video.content.video.video.size = 300 * 1024 * 1024
count = #requests
assert(not tg:request_media_playback(video) and #requests == count)
tg:prune_download_cache(false)
assert(requests[#requests].data.ttl == 86400 and requests[#requests].data.count == 250)
assert(requests[#requests].data.size == 256 * 1024 * 1024)

local attachment = {id = 24, chat_id = -42, content = {
    ["@type"] = "messageDocument",
    document = {file_name = "fixture.MKV", mime_type = "application/octet-stream", document = {id = 222, size = 900}},
}}
assert(tg:video_kind(attachment) == "video" and tg:choose_sticker_size(attachment) == nil)
local before_attachment = #requests
local attachment_kind, attachment_id, attachment_entry = tg:media_file_for_message(attachment)
assert(attachment_kind == "video" and attachment_id == 222 and not attachment_entry and #requests == before_attachment)
screen.model.current_chat = function() end
local video_option
for _, item in ipairs(screen:context_menu_items(attachment)) do
    if item.action == "play_media" then video_option = item end
end
assert(video_option)
screen.focused_message = function() return attachment end
screen:activate_focused_message()
assert(screen.fullscreen_media.message == attachment and requests[#requests].data.file_id == 222)

local attachment_video = tg.active_video
local attachment_progress = os.tmpname()
local progress_output = assert(io.open(attachment_progress, "wb"))
progress_output:write("frame=135\nout_time_us=9000000\nprogress=end\n")
progress_output:close()
attachment_video.name = "spgram-video-2.ogv"
attachment_video.status, attachment_video.progress_path = "decoding", attachment_progress
love.graphics.newVideo = function()
    return {play = function() end, pause = function() end, release = function() end}
end
tg:finish_video_conversion({name = attachment_video.name, ok = true})
os.remove(attachment_progress)
assert(attachment_video.status == "ready" and attachment_video.duration == 9)
screen:close_media_viewer()
assert(not tg.active_video and requests[#requests].data["@type"] == "deleteFile")

for _, filename in ipairs({"fixture.M3U8", "fixture.mp4.txt"}) do
    attachment.content.document.file_name = filename
    assert(not tg:video_kind(attachment))
end
attachment.content.document.file_name = "fixture.tgs"
assert(tg:choose_sticker_size(attachment).id == 222)
attachment.content.document.file_name = "fixture.ts"
attachment.content.document.mime_type = "text/typescript"
assert(not tg:video_kind(attachment))

local animation = {id = 25, chat_id = -42, content = {
    ["@type"] = "messageAnimation",
    animation = {animation = {id = 225, size = 1200}, thumbnail = {file = {id = 226}}},
}}
local before_animation = #requests
local animation_entry = tg:ensure_animation(animation)
assert(animation_entry.status == "downloading")
assert(#requests == before_animation + 2 and requests[#requests - 1].data.file_id == 226)
assert(requests[#requests].data.file_id == 225 and requests[#requests].data.limit == 16 * 1024 * 1024 + 1)
assert(tg:ensure_animation(animation) == animation_entry and #requests == before_animation + 2)
local animation_token = animation_entry.download_requested
assert(animation_token and tg:request_media_playback(animation) and #requests == before_animation + 2)
tg:handle({["@type"] = "error", ["@extra"] = animation_token, code = 400})
assert(animation_entry.status == "error" and not animation_entry.download_requested)
assert(tg:ensure_animation(animation) == animation_entry and #requests == before_animation + 2)
assert(tg:request_media_playback(animation) and #requests == before_animation + 3)
assert(not tg:pause_media_playback(animation) and not tg:stop_media_playback(animation))
local first_frame, second_frame = {}, {}
animation_entry.frames, animation_entry.play_origin = {first_frame, second_frame}, 0.85
animation_entry.frame_dt, animation_entry.width, animation_entry.height = 0.1, 80, 60
assert(tg:animation_image(animation) == second_frame)
animation_entry.play_origin = 0.75
assert(tg:animation_image(animation) == first_frame)

local sticker = {id = 26, chat_id = -42, content = {["@type"] = "messageSticker",
    sticker = {sticker = {id = 227}, format = {["@type"] = "stickerFormatWebm"}}}}
tg.sticker_by_message, tg.stickers, tg.sticker_format_by_file = {}, {[227] = {source_path = "sample.webm"}},
    {[227] = "stickerFormatWebm"}
local queued_sticker
tg.queue_media_decode = function(_, kind, id, path)
    queued_sticker = {kind, id, path}
end
tg:ensure_animated_sticker(sticker)
assert(queued_sticker[1] == "sticker" and queued_sticker[2] == 227 and queued_sticker[3] == "sample.webm")
local sticker_entry = tg.stickers[227]
sticker_entry.frames, sticker_entry.play_origin, sticker_entry.frame_dt = {first_frame, second_frame}, 0.85, 0.1
sticker_entry.width, sticker_entry.height = 60, 60
assert(tg:sticker_image(sticker) == second_frame)
assert(not tg:pause_media_playback(sticker) and not tg:stop_media_playback(sticker))
assert(tg:sticker_image(sticker) == second_frame)
tg.queue_media_decode = nil

local channel_list = {["@type"] = "chatListMain"}
local pinned = {id = -51, positions = {{list = channel_list, order = "9000000000000000001", is_pinned = true}}}
local pinned_after = {id = -52, positions = {{list = channel_list, order = "9000000000000000000", is_pinned = true}}}
local newer = {id = -53, last_message = {date = 99999},
    positions = {{list = channel_list, order = "9000000000000000002", is_pinned = false}}}
tg:handle_new_chat(pinned)
tg:handle_new_chat(pinned_after)
tg:handle_new_chat(newer)
assert(tg.chats[1] == pinned and tg.chats[2] == pinned_after and tg.chats[3] == newer)
tg:toggle_chat_pin(pinned, channel_list)
assert(requests[#requests].data["@type"] == "toggleChatIsPinned" and not requests[#requests].data.is_pinned)
tg:handle_chat_position({chat_id = pinned.id, position = {list = channel_list, order = "1000", is_pinned = false}})
assert(tg.chats[1] == pinned_after and not tg:chat_is_pinned(pinned, channel_list))
screen.list_kind, screen.model.selected, screen.model.list_offset = "main", 1, 0
local list_rows = screen:layout_chat_list(screen:get_visible_chat_list(), 459)
screen.chat_list_rows = list_rows
assert(list_rows[1].height == 25 and list_rows[2].height == 25 and list_rows[3].height == 76)
assert(screen:chat_row_at(80).chat.navigation == "saved")
assert(screen:chat_row_at(81).chat.navigation == "archive")
assert(screen:chat_row_at(106).chat == pinned_after)
screen.model.selected, screen.model.list_offset = 4, 2
local scrolled = screen:layout_chat_list(screen:get_visible_chat_list(), 459)
assert(scrolled[1].index == 3 and scrolled[1].y == 56)
assert(not screen:chat_row_at(463))

local settings = require("src.features.auth.ui.settings_screen")
local menu = setmetatable({fonts = {normal = {getHeight = function() return 17 end},
    tiny = {getHeight = function() return 13 end}}, selected_item = 1, scroll_offset = 0, tg = tg, callbacks = {
        accounts = function() return {{key = "one"}, {key = "two"}} end,
        map_key = function() return true end,
        calibrate_faces = function() end,
    }}, {__index = settings})
menu:wheelmoved(0, -1)
assert(menu.selected_item == 2 and menu.scroll_offset == 1)
menu:wheelmoved(0, 1)
assert(menu.scroll_offset == 0)
local sections = {
    {"visual", "performance"}, {"sounds", "message_sound"}, {"language", "keyboard_languages"},
    {"advanced", "reconnect"}, {"controls", "map_keys"},
}
assert(menu:items()[1].id == "exit_app" and menu:items()[2].id == "profile")
for i, expected in ipairs(sections) do
    menu:keypressed("down")
    assert(menu.selected_item == i + 2 and menu:items()[i + 2].id == expected[1])
    menu:keypressed("return")
    assert(menu.section.id == expected[1] and menu.selected_item == 1 and menu.scroll_offset == 0)
    assert(menu:items()[1].id == expected[2])
    if expected[1] == "visual" then
        menu:keypressed("return")
        assert(menu.section.id == "performance" and menu:items()[1].id == "memory_preset")
        assert(menu:keypressed("escape") == nil and menu.section.id == "visual" and menu.selected_item == 1)
    end
    if expected[1] == "language" or expected[1] == "controls" then
        menu:keypressed("return")
        assert(menu.languages_open or menu.keymap_open)
        assert(menu:keypressed("escape") == nil and not menu.languages_open and not menu.keymap_open)
        assert(menu.section.id == expected[1] and menu.selected_item == 1)
    end
    assert(menu:keypressed("escape") == nil and not menu.section and menu.selected_item == i + 2)
end
assert(menu:keypressed("escape") == "back")

local sleeps, receives, pushes = 0, 0, 0
local in_channel = {
    demand = function() return {lib = "fixture"} end,
    pop = function() if pushes > 0 then return {type = "quit"} end end,
}
local out_channel = {
    getCount = function() return sleeps == 0 and 500 or 499 end,
    pop = function() error("The worker must preserve queued updates") end,
    push = function(_, value) assert(value == "fixture response"); pushes = pushes + 1 end,
}
love.timer.sleep = function() assert(receives == 0); sleeps = sleeps + 1 end
love.thread = {getChannel = function(name) return name == "td_in" and in_channel or out_channel end}
package.preload["love.timer"] = function() return love.timer end
package.loaded.ffi = {
    cdef = function() end, string = function(value) return value end,
    load = function()
        return {
            td_json_client_create = function() return {} end,
            td_json_client_destroy = function() end,
            td_json_client_execute = function() end,
            td_json_client_receive = function() receives = receives + 1; return "fixture response" end,
        }
    end,
}
dofile("threads/tdlib_worker.lua")
assert(sleeps == 1 and receives == 1 and pushes == 1)
print("Handheld history, navigation, media lifetime, layout and queue checks passed")


local motion = require("src.shared.ui.ui_kit")
assert(motion.focus_lift(0) == 0 and motion.focus_lift(0.05) > 0)
assert(motion.focus_lift(0.16) < 0 and motion.focus_lift(0.24) == 0)
local live = setmetatable({
    current_chat_id = 1, chats = {}, archive_chats = {}, chats_by_id = {
        [1] = {id = 1, title = "Open chat"},
        [2] = {id = 2, title = "Other chat"},
        [3] = {id = 3, title = "Muted chat", notification_settings = {mute_for = 300}},
    }, archive_chats_by_id = {}, messages = {}, history_state = {},
    notifications = {}, ensure_voice_note = function() end, ensure_audio = function() end,
}, {__index = client})
local now = 10
love.timer.getTime = function() return now end
local function receive(chat_id, id, outgoing)
    live:handle_new_message({id = id, chat_id = chat_id, is_outgoing = outgoing,
        content = {["@type"] = "messageText", text = {text = "Fixture"}}})
end
receive(1, 21)
assert(live.live_message_pings[1].id == 21 and #live.notifications == 0)
receive(2, 22)
assert(live.live_message_pings[2].id == 22 and #live.notifications == 1)
receive(2, 22)
assert(#live.notifications == 1 and live.notifications[1].created == 10)
receive(3, 23)
assert(live.live_message_pings[3].id == 23 and #live.notifications == 1)
receive(2, 24, true)
assert(live.live_message_pings[2].id == 22 and #live.notifications == 1)
now = 15
for index = 10, 60 do live:record_message_ping(index, index * 2, now) end
local total = 0
for _ in pairs(live.live_message_pings) do total = total + 1 end
assert(total == 32 and not live.live_message_pings[1])

local media_preferences = require("src.shared.system.media_settings")
local loads, starts = 0, 0
love.audio = {newSource = function(path, kind)
    assert(path == "sounds/beepo/beepo.wav" and kind == "static")
    loads = loads + 1
    return {stop = function() end, play = function() starts = starts + 1 end}
end}
assert(media_preferences.get("message_sound"))
love.filesystem.read = function() return "message_sound=0\n" end
media_preferences.load()
assert(media_preferences.get("message_sound"))
love.filesystem.read = function() return "incoming_message_sound=0\n" end
media_preferences.load()
receive(1, 995)
assert(starts == 0)
media_preferences.set("message_sound", true)
receive(1, 996)
receive(1, 997)
now = now + 0.5
receive(2, 998)
assert(loads == 1 and starts == 2)
now = now + 1
receive(3, 999)
assert(starts == 2, "Muted chats must stay silent")
local group = {id = 4, title = "Inherited group mute",
    type = {["@type"] = "chatTypeBasicGroup"},
    notification_settings = {use_default_mute_for = true, mute_for = 0}}
local channel = {id = 5, title = "Explicit unmute",
    type = {["@type"] = "chatTypeSupergroup", is_channel = true},
    notification_settings = {use_default_mute_for = false, mute_for = 0}}
live.chats_by_id[4], live.chats_by_id[5] = group, channel
live:handle({["@type"] = "scopeNotificationSettings",
    ["@extra"] = "notification_scope:notificationSettingsScopeGroupChats", mute_for = 900})
live:handle({["@type"] = "updateScopeNotificationSettings", scope = {["@type"] = "notificationSettingsScopeChannelChats"},
    notification_settings = {mute_for = 900}})
assert(live:is_chat_muted(group) and not live:is_chat_muted(channel))
now = now + 1
receive(4, 44)
assert(live.live_message_pings[4] and starts == 2)
receive(5, 55)
assert(starts == 3)
channel.notification_settings.use_default_mute_for = true
assert(live:is_chat_muted(channel))
live:handle({["@type"] = "updateScopeNotificationSettings", scope = {["@type"] = "notificationSettingsScopeGroupChats"},
    notification_settings = {mute_for = 0}})
assert(not live:is_chat_muted(group))
media_preferences.set("message_sound", false)
print("Live row pings, chat and inherited scope mute, overrides, and sound gating passed")

local image = {getWidth = function() return 16 end, getHeight = function() return 16 end}
local converted, uploads, thumbnail_result = {}, 0, nil
local thumbnail_starts = 0
love.thread = {newThread = function(path)
    assert(path == "threads/anim_decode.lua")
    return {start = function(_, mode)
        assert(mode == "thumbnail")
        thumbnail_starts = thumbnail_starts + 1
    end, isRunning = function() return true end}
end}
local decoded_paths = {}
for index = 1, 12 do decoded_paths[index] = "fixture-frame-" .. index end
local result = {kind = "sticker", file_id = 7, ok = true, paths = decoded_paths}
local media_fixture = setmetatable({
    stickers = {[7] = {status = "decoding", decode_requested = true, autoplay = true}},
    photos = {[8] = {status = "loading", thumbnail = true}, [9] = {status = "loading", thumbnail = true}},
    anim_out = {pop = function() local item = result; result = nil; return item end},
    anim_in = {push = function() error("A thumbnail must not join the playback queue") end},
    thumbnail_in = {clear = function() end, push = function(_, job) converted[#converted + 1] = job end},
    thumbnail_out = {clear = function() end, pop = function()
        local item = thumbnail_result
        thumbnail_result = nil
        return item
    end},
}, {__index = client})
love.filesystem.newFileData = function(bytes) return bytes end
love.filesystem.getSaveDirectory = function() return "fixture" end
love.image = {newImageData = function() return image end}
love.graphics.newImage = function() uploads = uploads + 1; return image end
local real_open, real_remove, real_execute = io.open, os.remove, os.execute
io.open = function(path)
    return {read = function() return path:match("%.webp$") and "RIFF0000WEBP" or "png fixture" end,
        close = function() end}
end
os.remove = function() end
os.execute = function() error("WebP conversion must stay off the UI thread") end
media_fixture:load_photo(8, "eight.webp")
media_fixture:load_photo(8, "eight.webp")
media_fixture:load_photo(9, "nine.webp")
assert(#media_fixture.webp_queue == 2 and not media_fixture.photos[8].image)
media_fixture:dispatch_webp_image()
media_fixture:dispatch_webp_image()
assert(thumbnail_starts == 1 and #converted == 1 and converted[1].file_id == 9)
media_fixture:poll_media_decoder()
assert(uploads == 4 and media_fixture.stickers[7].decode_requested)
media_fixture:poll_media_decoder()
assert(uploads == 8 and media_fixture.stickers[7].decode_requested)
media_fixture:poll_media_decoder()
assert(uploads == 12 and #media_fixture.stickers[7].frames == 12 and media_fixture.stickers[7].playing)
local job = converted[1]
thumbnail_result = {type = "converted_webp", storage = job.storage, file_id = job.file_id, output = job.output, ok = true}
media_fixture:poll_thumbnail_worker()
assert(uploads == 13 and media_fixture.photos[9].image == image)
media_fixture:dispatch_webp_image()
assert(#converted == 2 and converted[2].file_id == 8)
io.open, os.remove, os.execute = real_open, real_remove, real_execute
print("WebP conversion queues one worker job and animation frames upload in bounded batches")

local avatar_downloads, avatar_uploads, live_textures, peak_textures = {}, 0, 0, 0
local avatars = setmetatable({avatar_photos = {}, users = {}, chats_by_id = {}, archive_chats_by_id = {},
    send = function(_, request, token) avatar_downloads[#avatar_downloads + 1] = request; return token end,
    queue_webp_image = function() return false end,
    load_image = function(_, id, _, storage, max_bytes, max_edge)
        assert(max_bytes == 262144 and max_edge == 160)
        avatar_uploads = avatar_uploads + 1
        live_textures = live_textures + 1
        peak_textures = math.max(peak_textures, live_textures)
        storage[id].image = {release = function() live_textures = live_textures - 1 end}
        storage[id].status = "ready"
    end,
}, {__index = client})
for group = 1, 8 do
    for index = 1, 40 do
        local id = (group - 1) * 40 + index
        local avatar = {small = {id = id, ["local"] = {is_downloading_completed = true, path = "avatar-" .. id}},
            big = {id = id + 1000}}
        avatars.users[id] = {profile_photo = avatar}
        avatars.chats_by_id[-id] = {photo = avatar}
        avatars:user_photo_image(id)
        avatars:chat_photo_image(-id)
        assert(not avatars.avatar_photos[id + 1000])
        local prior = avatar_uploads
        avatars:poll_avatar_images()
        assert(avatar_uploads == prior + 1)
        assert(avatars:user_photo_image(id) == avatars:chat_photo_image(-id))
    end
end
assert(avatar_uploads == 320 and peak_textures == 64 and live_textures == 64)
assert(not avatars.avatar_photos[1] and avatars.avatar_photos[320])
assert(#avatar_downloads == 0)
avatars.users[321] = {profile_photo = {small = {id = 321}, big = {id = 421}}}
avatars:user_photo_image(321)
assert(#avatar_downloads == 1 and avatar_downloads[1].file_id == 321 and avatar_downloads[1].limit == 262145)
avatars.load_image = function(_, id, _, storage)
    avatar_uploads = avatar_uploads + 1
    storage[id].status = "error"
end
avatars:load_avatar(321, "invalid.jpg")
avatars:poll_avatar_images()
local before = avatar_uploads
for _ = 1, 10 do
    avatars:load_avatar(321, "invalid.jpg")
    avatars:user_photo_image(321)
    avatars:poll_avatar_images()
end
assert(avatar_uploads == before)

local images, alive = {}, 0
local photos = setmetatable({photos = images, load_image = function(_, id, _, storage)
    alive = alive + 1
    storage[id].image = {release = function() alive = alive - 1 end}
    storage[id].width, storage[id].height = 1280, 1280
end}, {__index = client})
for id = 1, 20 do
    images[id] = {}
    photos:load_photo(id, "group-photo")
    assert(alive <= 3)
end
local animated = {image = image, frames = {image}, last_visible = now - 20}
assert(media_fixture:animation_frame(animated, true) == image and animated.last_visible == now - 20)
assert(media_fixture:animation_frame(animated) == image and animated.last_visible == now)
print("Eight groups of avatars stayed within one 64-entry pool, with bounded photo textures and retry work")

local pins = setmetatable({avatar_photos = {}, users = {}, chats_by_id = {}, archive_chats_by_id = {},
    send = avatars.send, queue_webp_image = avatars.queue_webp_image}, {__index = client})
local first_download = #avatar_downloads
for id = 1, 67 do pins.users[id] = {profile_photo = {small = {id = id}}} end
for id = 1, 64 do pins:user_photo_image(id, 88) end
pins:begin_avatar_frame()
pins:user_photo_image(1, 88)
pins:user_photo_image(2)
pins:begin_avatar_frame()
pins:user_photo_image(65, 88)
assert(pins.avatar_photos[1] and pins.avatar_photos[2])
pins:cancel_chat_avatars(88)
assert(pins.avatar_photos[2] and not pins.avatar_photos[1] and not pins.avatar_photos[65])
assert(avatar_downloads[first_download + 65]["@type"] == "cancelDownloadFile")
pins:begin_avatar_frame()
for id = 1, 64 do pins:user_photo_image(id, 99) end
local count_before = #avatar_downloads
assert(not pins:user_photo_image(67, 99) and #avatar_downloads == count_before)
print("Visible and shared portraits survive eviction, and switching chats cancels stale private avatar work")

do
    local settings = require("src.shared.system.media_settings")
    local read, write = love.filesystem.read, love.filesystem.write
    local saved = "autoplay_images=0\n"
    love.filesystem.read = function() return saved end
    love.filesystem.write = function(_, data) saved = data; return true end
    settings.load()
    assert(settings.memory_preset() == "Custom" and not settings.get("video_thumbnails"))
    settings.apply_memory_preset(false)
    assert(settings.memory_preset() == "Default")

    local released, requests, queue, pending = 0, {}, {}, nil
    local function texture()
        return {release = function() released = released + 1 end}
    end
    local window = setmetatable({
        avatar_frame = 20, avatar_photos = {[20] = {image = texture()}, [21] = {status = "downloading"}},
        users = {[2] = {profile_photo = {small = {id = 22}}}},
        photos = {
            [32] = {image = texture(), width = 1024, height = 1024, last_used = 1, visible_frame = 20},
            [33] = {image = texture(), width = 1024, height = 1024, last_used = 2},
            [34] = {image = texture(), width = 1024, height = 1024, last_used = 3},
            [35] = {status = "downloading", video_preview = true, thumbnail = true},
        },
        animations = {}, stickers = {}, photo_by_message = {}, animation_by_message = {},
        send = function(_, req) requests[#requests + 1] = req; return "fixture" end,
        ensure_media_decoder = function() end,
        anim_in = {push = function(_, job) queue[#queue + 1] = job end},
        anim_out = {pop = function() local item = pending; pending = nil; return item end},
    }, {__index = client})
    settings.set("small_texture_cache", true)
    window:trim_photo_cache(false)
    assert(window.photos[32] and not window.photos[33] and window.photos[34] and released == 1)
    settings.apply_memory_preset(true)
    assert(settings.memory_preset() == "Low memory")
    window:apply_memory_settings()
    assert(not next(window.avatar_photos) and not next(window.photos) and released == 4)
    assert(#requests == 2 and requests[1]["@type"] == "cancelDownloadFile")
    assert(not window:user_photo_image(2) and #requests == 2)

    local photo = {id = 11, content = {["@type"] = "messagePhoto", photo = {sizes = {{width = 320, height = 240, photo = {id = 44}}}}}}
    local video = {content = {["@type"] = "messageVideo", video = {thumbnail = {file = {id = 45}}}}}
    assert(not window:ensure_photo(photo) and not window:video_thumbnail(video) and #requests == 2)
    assert(window:ensure_photo(photo, true) and requests[3].file_id == 44)
    assert(not window:photo_image(photo))

    local gif = {id = 12, content = {["@type"] = "messageAnimation", animation = {animation = {
        id = 46, ["local"] = {is_downloading_completed = true, path = "fixture.gif"},
    }}}}
    local entry = window:ensure_animation(gif)
    assert(entry and #queue == 0)
    assert(window:ensure_animation(gif, true, true) == entry and #queue == 1)
    entry.image, entry.frame_bytes = texture(), 8
    entry.frames = {entry.image, texture()}
    window:close_inline_media()
    assert(entry.image and not entry.frames and released == 5)
    pending = {kind = "animation", file_id = 46, paths = {}, frames = {texture()}, ok = true}
    window:poll_media_decoder()
    assert(released == 6 and not entry.decode_requested and not window.pending_frame_upload)
    settings.toggle("profile_pictures")
    assert(settings.memory_preset() == "Custom")
    settings.apply_memory_preset(false)
    settings.load()
    assert(settings.memory_preset() == "Default")
    love.filesystem.read, love.filesystem.write = read, write
end
print("Memory presets migrate and persist, gate background media, preserve manual playback, and release textures")
