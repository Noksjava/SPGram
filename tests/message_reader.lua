package.preload.utf8 = function() return {len = string.len} end

local function noop() end
local drawn = {}
local function capture(text) drawn[text] = true end
local font = {
    getHeight = function() return 16 end,
    getWidth = function(_, text) return #text * 8 end,
    getWrap = function(_, text, width)
        local lines, line = {}, ""
        for word in text:gmatch("%S+") do
            local next_line = line == "" and word or line .. " " .. word
            if #next_line * 8 > width and line ~= "" then
                lines[#lines + 1], line = line, word
            else
                line = next_line
            end
        end
        lines[#lines + 1] = line
        return width, lines
    end,
}
love = {
    timer = {getTime = function() return 1 end},
    filesystem = {read = noop},
    keyboard = {isDown = function() return false end},
    graphics = setmetatable({getWidth = function() return 640 end, getHeight = function() return 480 end,
        print = capture, printf = capture}, {__index = function() return noop end}),
}

local client = require("src.shared.api.tdlib_client")
local messenger = require("src.features.chat.ui.chat_screen")
local chat = {id = 42, title = "Test chat", type = {["@type"] = "chatTypePrivate", user_id = 7}}
local paragraphs = {"Opening paragraph.", "", ("A long paragraph remains readable across several wrapped rows. "):rep(8)}
for index = 1, 60 do paragraphs[#paragraphs + 1] = "Paragraph " .. index end
paragraphs[#paragraphs + 1] = "End of message."
local text = table.concat(paragraphs, "\n")
local message = {id = 100, chat_id = 42, content = {["@type"] = "messageText", text = {text = text}}}
local tg = setmetatable({
    current_chat_id = 42, chats = {chat}, chats_by_id = {[42] = chat}, archive_chats_by_id = {}, dialog_search_results = {},
    search_chats = noop, search_public_chats = noop, search_chat_messages = noop,
    users = {},
}, {__index = client})
local screen = messenger.new({normal = font, small = font, subtitle = font, tiny = font}, tg)
screen.nav_messages, screen.message_cursor_id = {message}, message.id
screen.model.scroll = 96

dofile("main.lua")
local function replace_upvalue(fn, name, value)
    for index = 1, 32 do
        local key, previous = debug.getupvalue(fn, index)
        if key == name then
            debug.setupvalue(fn, index, value)
            return previous
        end
        if not key then break end
    end
    error("Missing test binding: " .. name)
end
local handle_key = replace_upvalue(love.gamepadpressed, "handle_key", noop)
replace_upvalue(love.gamepadpressed, "handle_key", handle_key)
replace_upvalue(love.gamepadpressed, "current", screen)
local controls = require("src.features.help.ui.controls_screen").new(screen.fonts, tg)
replace_upvalue(love.gamepadpressed, "screens", {messenger = screen, controls = controls})
replace_upvalue(handle_key, "tg", tg)
local function press(button)
    love.gamepadpressed(nil, button)
    love.gamepadreleased(nil, button)
end

press("a")
assert(screen.text_preview and screen.text_preview.message_text == text)
screen:draw_text_preview(640, 480)
assert(drawn["Opening paragraph."] and not drawn["End of message."])
local preview = screen.text_preview
assert(preview.lines[2] == "" and #preview.lines > #paragraphs, "Reader must preserve and wrap paragraphs")
press("dpdown")
assert(preview.scroll == 1)
press("rightshoulder")
assert(preview.scroll == 1 + preview.page_size)
for _ = 1, 10 do press("rightshoulder") end
screen:draw_text_preview(640, 480)
assert(preview.scroll == preview.max_scroll and drawn["End of message."])
press("b")
assert(not screen.text_preview and screen.model.scroll == 96 and screen:focused_message() == message)
press("y")
assert(screen.context_menu and screen.context_menu.message == message)
press("b")
assert(not screen.context_menu and tg.current_chat_id == 42)
press("x")
assert(not screen.search_active and not next(screen.selected_messages))
press("y")
press("dpdown")
press("a")
assert(screen.selected_messages[message.id] == message and not screen.context_menu)
press("y")
assert(screen.context_menu.items[2].label == "Deselect message")
assert(screen.context_menu.items[3].action == "forward_selected")
press("dpdown")
press("dpdown")
press("dpdown")
press("a")
assert(not next(screen.selected_messages))
press("y")
press("a")
assert(screen.search_active and screen.keyboard.visible)
press("b")
assert(not screen.search_active and not screen.keyboard.visible and tg.current_chat_id == 42)
press("y")
press("a")
screen:set_search_query("test", false)
press("start")
assert(screen.search_submitted_query == "test" and not screen.keyboard.visible)
press("b")
assert(not screen.search_active)
tg.current_chat_id = nil
press("x")
assert(not screen.search_active)
press("y")
press("a")
assert(screen.search_active)
press("b")
assert(not screen.search_active and not screen.keyboard.visible)
local confirm, back, keys = require("src.shared.system.controller_map").buttons("retro")
replace_upvalue(love.gamepadpressed, "SELECT_BUTTON", confirm)
replace_upvalue(love.gamepadpressed, "GAMEPAD_KEYS", keys)
tg.current_chat_id = 42
press(confirm)
assert(screen.text_preview)
press(back)
press("y")
assert(screen.context_menu and screen.context_menu.message == message)
local printed_at = {}
love.graphics.print = function(value, x, y)
    if value ~= "Controls" or x == 24 then printed_at[value] = y end
end
press("back")
controls:draw()
local start_y = printed_at["Chat list"]
local header_y = printed_at.Controls
press("dpdown")
controls:draw()
assert(printed_at["Chat list"] < start_y and printed_at.Controls == header_y)
press("dpup")
controls:draw()
assert(printed_at["Chat list"] == start_y and controls.scroll == 0)
for _ = 1, 10 do press("rightshoulder") end
local end_scroll = controls.scroll
assert(end_scroll > 0 and end_scroll < 600)
press("dpdown")
assert(controls.scroll == end_scroll)
love.wheelmoved(0, 1)
assert(controls.scroll < end_scroll)
press("back")
love.graphics.print = capture
assert(tg.current_chat_id == 42)
print("Controller Options, nested search and selection, and Controls scroll direction passed")

screen.context_menu = nil
tg.now_playing = {id = 99, chat_id = 42}
tg.videos = {}
tg.stickers = {[987] = {}}
tg.send = function(_, request, token)
    tg.test_request = request
    return token or "fixture-request"
end
local video = {id = 101, chat_id = 42, content = {
    ["@type"] = "messageVideo", video = {video = {id = 987, size = 1024}, duration = 20},
}}
screen.nav_messages, screen.message_cursor_id = {video}, video.id
press(confirm)
assert(screen.fullscreen_media and screen.fullscreen_media.message == video)
assert(tg.test_request["@type"] == "downloadFile" and tg.test_request.file_id == 987)
tg:handle_file({id = 987, ["local"] = {can_be_downloaded = false}})
assert(tg.active_video.status == "error" and tg.active_video.decode_error:find("Try again.", 1, true))
press(back)
assert(not screen.fullscreen_media)
screen.media_hits, screen.profile_hits, screen.hashtag_hits = {}, {}, {}
screen:draw_message(video, 220, 130, 400, 80, 340, 10, 280, 16, 16,
    require("src.shared.ui.ui_kit").colors, {message = video})
local hit = assert(screen.media_hits[1])
video.content.caption = {text = "📽 Field notes from the video",
    entities = {{offset = 3, length = 11, type = {["@type"] = "textEntityTypeTextUrl", url = "https://example.org"}}}}
screen:draw_message(video, 220, 130, 400, 170, 340, 10, 280, 16, 16,
    require("src.shared.ui.ui_kit").colors, {message = video})
assert(drawn["📽 Field notes from the video"] and drawn["Field notes"])
local chat_options = screen:chat_context_menu_items(chat)
for _, option in ipairs(chat_options) do
    if option.label == "Contact info" then
        screen:activate_context_item({chat = chat}, option)
    end
end
assert(screen.wants_profile_chat_id == 42)
screen.wants_profile_chat_id = nil
assert(drawn.VIDEO and hit.media_kind == "video" and hit.media_w > 100)
screen:mousepressed(hit.media_x + 5, hit.media_y + 25, 1)
assert(screen.fullscreen_media and tg.test_request["@type"] == "downloadFile")
press(back)

local private_type = chat.type
for _, scenario in ipairs({{"chatTypeBasicGroup", "Read the post before playing."},
    {"chatTypeSupergroup", "Read the channel post before playing."}}) do
    chat.type = {["@type"] = scenario[1], is_channel = scenario[1] == "chatTypeSupergroup"}
    video.content.caption = scenario[2] ~= "" and {text = scenario[2]} or nil
    local previous = tg.test_request
    press(confirm)
    local post = assert(screen.text_preview)
    assert(post.photo.message == video and post.message_text == scenario[2])
    assert(not screen.fullscreen_media and tg.test_request == previous)
    screen:draw_text_preview(640, 480)
    assert(post.photo_hit and (scenario[2] == "" or drawn[scenario[2]]))
    press(confirm)
    assert(screen.fullscreen_media.from_post and screen.fullscreen_media.message == video)
    assert(tg.test_request["@type"] == "downloadFile")
    press(back)
    assert(screen.text_preview == post and not screen.fullscreen_media)
    press(back)
end
chat.type = {["@type"] = "chatTypeSupergroup", is_channel = true}
video.content.caption = {text = " "}
video.interaction_info = {reply_info = {reply_count = 3}}
press(confirm)
assert(screen.fullscreen_media and screen.fullscreen_media.message == video and not screen.text_preview)
assert(tg.test_request["@type"] == "downloadFile" and screen:focused_comment_target() == video)
press(back)
screen:mousepressed(hit.media_x + 5, hit.media_y + 25, 1)
assert(screen.fullscreen_media and screen.fullscreen_media.message == video and not screen.text_preview)
press(back)
video.interaction_info = nil
video.content.caption = {text = "Read before playing."}
screen:mousepressed(hit.media_x + 5, hit.media_y + 25, 1)
assert(screen.text_preview and screen.text_preview.photo.message == video and not screen.fullscreen_media)
press(back)
chat.type = private_type

tg.users[7] = {first_name = "Sender"}
tg.users[8] = {first_name = "Original"}
tg.ensure_user_photo = noop
tg.user_photo_image = noop
message.sender_id = {["@type"] = "messageSenderUser", user_id = 7}
message.forward_info = {origin = {["@type"] = "messageOriginUser", sender_user_id = 8}}
screen.nav_messages, screen.message_cursor_id = {message}, message.id
assert(tg:forward_origin(message) == "Forwarded from Original")
screen:draw_message(message, 220, 130, 400, 80, 340, 10, 280, 16, 16,
    require("src.shared.ui.ui_kit").colors, {message = message})
assert(drawn["Forwarded from Original"])
local menu_items = screen:context_menu_items(message)
local sender, original
for _, item in ipairs(menu_items) do
    if item.label == "Sender profile" then sender = item
    elseif item.label == "Original sender profile" then original = item end
end
screen:activate_context_item({message = message}, assert(sender))
assert(screen.wants_profile_user_id == 7)
screen:activate_context_item({message = message}, assert(original))
assert(screen.wants_profile_user_id == 8)
message.forward_info.origin = {["@type"] = "messageOriginHiddenUser", sender_name = "Hidden"}
local label, user_id, chat_id = tg:forward_origin(message)
assert(label == "Forwarded from Hidden" and not user_id and not chat_id)
local scale_x
love.graphics.scale = function(x) scale_x = x end
require("src.shared.ui.ui_kit").button_hint("{confirm} — Some long hint", 16, 16, font, {1, 1, 1}, 90)
assert(scale_x > 0 and scale_x < 1)
tg.photos, tg.avatar_photos = {}, {}
video.content.video.thumbnail = {format = {["@type"] = "thumbnailFormatJpeg"}, file = {id = 444, size = 3000}}
assert(not tg:video_thumbnail(video))
assert(tg.test_request.file_id == 444 and tg.test_request["@type"] == "downloadFile")
local last_request = tg.test_request
assert(not tg:video_thumbnail(video) and tg.test_request == last_request)
local preview_image = {getWidth = function() return 80 end, getHeight = function() return 60 end}
tg.load_photo = function(self, id, path)
    assert(path == "small-preview.jpg")
    self.photos[id].image = preview_image
end
tg:handle_file({["@type"] = "file", id = 444, ["local"] = {
    is_downloading_completed = true, path = "small-preview.jpg",
}})
assert(tg:video_thumbnail(video) == preview_image)

tg.video_image = function() return preview_image end
tg.media_playback_state = function() return 65, 3602, true end
screen.fullscreen_media = {kind = "video", message = video}
local printed = {}
love.graphics.print = function(value, x, y) printed[value] = y end
screen:draw_fullscreen_media(640, 480)
local time_y = assert(printed["1:05 / 60:02"])
local footer_y = assert(printed[" — Play/Pause   L1/R1 — ±10 s   ←/→ — Media   "])
assert(footer_y >= time_y + font:getHeight(), "Playback time and controls need separate rows")
love.graphics.print = capture
screen.fullscreen_media = nil
tg.video_image, tg.media_playback_state = nil, nil
print("Video thumbnail routing, playback hint separation, forwarded labels and sender profiles passed")


local gif = {id = 102, chat_id = 42, content = {
    ["@type"] = "messageAnimation", animation = {animation = {id = 222, size = 4096}},
}}
tg.animations, tg.animation_by_message = {}, {}
screen.nav_messages, screen.message_cursor_id = {gif}, gif.id
press(confirm)
assert(screen.fullscreen_media and screen.fullscreen_media.kind == "animation")
assert(tg.test_request["@type"] == "downloadFile" and tg.test_request.file_id == 222)
press("rightshoulder")
assert(screen.fullscreen_zoom_target == 1.5)
screen.fullscreen_zoom = 1.5
tg.animations[222].image = {getWidth = function() return 400 end, getHeight = function() return 300 end}
press("dpright")
press("dpdown")
assert(screen.fullscreen_pan_target_x <= -52 and screen.fullscreen_pan_target_y <= -52)
press("dpup")
press("dpleft")
assert(screen.fullscreen_pan_target_x == 0 and screen.fullscreen_pan_target_y == 0)
press("leftshoulder")
assert(screen.fullscreen_zoom_target == 1)
press(confirm)
assert(screen.fullscreen_media.kind == "animation" and not tg.now_playing)
love.event = {quit = function() tg.quit_requested = true end}
press("guide")
assert(screen.fullscreen_media and not tg.quit_requested)
press(back)
assert(not screen.fullscreen_media)
tg.close_chat = function(self) self.current_chat_id = nil end
press("back")
assert(tg.current_chat_id == 42)
press("back")
assert(tg.current_chat_id == 42)
press(back)
assert(not tg.current_chat_id and not tg.quit_requested)
tg.current_chat_id = 42
love.gamepadpressed(nil, "back")
press(confirm)
love.gamepadreleased(nil, "back")
assert(tg.quit_requested)
press("back")
print("GIF viewer zoom, SELECT controls and dedicated Back passed")


tg.current_chat_id, tg.messages, tg.history_state = 42, {[42] = {message}}, {}
tg.quit_requested = nil
screen.nav_messages, screen.message_cursor_id = {message}, message.id
screen.keyboard.visible = false
screen.model.input = "Composer message"
press("dpdown")
assert(screen.composer_focus == 1)
press(confirm)
assert(screen.keyboard.visible and screen.composer_focus == 1)
press(back)
assert(not screen.keyboard.visible)
press("dpright")
assert(screen.composer_focus == 2)
press(confirm)
assert(tg.sticker_set_viewer.home)
press(confirm)
assert(tg.sticker_set_viewer.title == "Recent stickers" and tg.test_request["@type"] == "getRecentStickers")
local token = tg.sticker_set_viewer.token
local sticker = {sticker = {id = 904}, width = 320, height = 256, emoji = "✦"}
tg:handle({["@type"] = "stickers", ["@extra"] = token, stickers = {sticker}})
assert(tg.sticker_set_viewer.stickers[1] == sticker and not tg.sticker_set_viewer.loading)
press(confirm)
local send_sticker = tg.test_request.input_message_content
assert(tg.test_request["@type"] == "sendMessage" and send_sticker["@type"] == "inputMessageSticker")
assert(send_sticker.sticker["@type"] == "inputSticker")
assert(send_sticker.sticker.sticker["@type"] == "inputFileId" and send_sticker.sticker.sticker.id == 904)
assert(send_sticker.sticker.width == 320 and send_sticker.sticker.height == 256 and not tg.sticker_set_viewer)
tg:handle({["@type"] = "error", ["@extra"] = "send_sticker", code = 400, message = "Sticker sending restricted"})
assert(tg.action_error == "Sticker sending restricted")
tg.installed_sticker_sets = {{title = "Retro pack", name = "retro_pack", id = "1234567890123456789"}}
press(confirm)
press(confirm)
local picker = tg.sticker_set_viewer
tg:handle({["@type"] = "stickers", ["@extra"] = picker.token, stickers = {sticker}})
local picker_layout = screen:picker_layout(picker, 640, 480)
assert(picker_layout.entries[1].kind == "sticker" and picker_layout.entries[2].label == "Retro pack")
press("dpdown")
press(confirm)
assert(tg.test_request["@type"] == "searchStickerSet" and tg.sticker_set_viewer.parent == picker)
press(back)
assert(tg.sticker_set_viewer == picker)

press(back)
assert(tg.sticker_set_viewer.home)
press("dpright")
press(confirm)
local gifs = tg.sticker_set_viewer
assert(gifs.gifs and tg.test_request["@type"] == "getSavedAnimations")
local saved = {animation = {id = 908}, width = 100, height = 70, duration = 3}
tg:handle({["@type"] = "animations", ["@extra"] = gifs.token, animations = {saved}})
press("dpdown")
press("x")
assert(gifs.preview and gifs.preview.kind == "gif")
press(confirm)
local outgoing = tg.test_request.input_message_content
assert(outgoing["@type"] == "inputMessageAnimation" and outgoing.animation["@type"] == "inputAnimation")
assert(outgoing.animation.animation["@type"] == "inputFileId" and outgoing.animation.animation.id == 908)
assert(outgoing.animation.duration == 3 and not tg.sticker_set_viewer)

press(confirm)
press("dpright")
press(confirm)
gifs = tg.sticker_set_viewer
press(confirm)
assert(gifs.search_input and screen.keyboard.visible)
screen:textinput("pixel cats")
press("start")
assert(tg.test_request.name == "animation_search_bot_username")
tg:handle({["@type"] = "optionValueString", ["@extra"] = gifs.token, value = "gif"})
assert(tg.test_request["@type"] == "searchPublicChat" and tg.test_request.username == "gif")
tg:handle({["@type"] = "chat", ["@extra"] = gifs.token, id = 500, type = {
    ["@type"] = "chatTypePrivate", user_id = 500,
}})
assert(tg.test_request["@type"] == "getInlineQueryResults" and tg.test_request.query == "pixel cats")
local query_id = "-918273645546372819"
tg:handle({["@type"] = "inlineQueryResults", ["@extra"] = gifs.token, inline_query_id = query_id,
    results = {{["@type"] = "inlineQueryResultAnimation", id = "cat1", animation = saved}}})
press("dpdown")
press(confirm)
assert(tg.test_request["@type"] == "sendInlineQueryResultMessage" and tg.test_request.result_id == "cat1")
assert(tg.test_request.query_id == query_id and tg.test_request.chat_id == 42 and not tg.sticker_set_viewer)
tg:handle({["@type"] = "message", ["@extra"] = "send_gif", id = -4, chat_id = 42,
    is_outgoing = true, sending_state = {}, content = {["@type"] = "messageAnimation", animation = saved}})
tg:handle({["@type"] = "updateMessageSendSucceeded", old_message_id = -4,
    message = {id = 1001, chat_id = 42, is_outgoing = true, content = {["@type"] = "messageAnimation", animation = saved}}})
assert(tg.test_request["@type"] == "addSavedAnimation" and tg.test_request.animation.id == 908)
print("Compact sticker picker, nested TDLib 1.8.67 media inputs, saved GIFs and GIF search sending passed")
press("dpright")
assert(screen.composer_focus == 3)
press(confirm)
assert(tg.test_request["@type"] == "sendMessage" and screen.model.input == "")
press("dpup")
assert(not screen.composer_focus and screen:focused_message() == message)

local forwarded_chat = {id = 103, chat_id = 42, forward_info = {
    origin = {["@type"] = "messageOriginChannel", chat_id = -9876},
}}
assert(tg:forward_origin(forwarded_chat) == "Forwarded" and tg.test_request.chat_id == -9876)
assert(tg.test_request["@type"] == "getChat")
tg:handle({["@type"] = "chat", ["@extra"] = "forward_origin:-9876", id = -9876, title = "Pixel News"})
assert(tg:forward_origin(forwarded_chat) == "Forwarded from Pixel News")
assert(not tg.chats_by_id[-9876], "Forward attribution must not insert unrelated chats in the list")
print("Composer recents, direct sticker sending, errors, photo pan and forward attribution passed")


local saved_languages
love.filesystem.read = function(name)
    if name == "keyboard/pinyin.tsv" then
        local file = assert(io.open(name, "rb"))
        local data = file:read("*a")
        file:close()
        return data
    end
end
love.filesystem.write = function(name, data)
    if name == "keyboard-languages.conf" then saved_languages = data end
    return true
end
local keyboard = require("src.shared.ui.virtual_keyboard")
local preferences = require("src.shared.system.keyboard_languages")
local menu = require("src.features.auth.ui.settings_screen").new({normal = font, small = font, tiny = font}, tg, {})
menu:activate_item({id = "keyboard_languages"})
assert(menu.languages_open and #menu:items() == 6)
for _, option in ipairs(menu:items()) do
    if option.code ~= "en" and option.code ~= "ru" then menu:activate_item(option) end
end
menu:keypressed("escape")
assert(not menu.languages_open and saved_languages:find("en,fr,ru,uk,pl,zh", 1, true))

local typed = keyboard.new({normal = font})
typed.visible = true
local function pick(label)
    for row, values in ipairs(typed.layout) do
        for column, value in ipairs(values) do
            if value == label then
                typed.row, typed.col = row, column
                return typed:activate()
            end
        end
    end
    error("Missing key: " .. label)
end
assert(typed.lang == "en" and pick("q").text == "q")
typed:keypressed("y")
assert(typed.language_menu and typed.language_menu.index == 1 and typed.lang == "en")
typed:keypressed("escape")
assert(not typed.language_menu and typed.visible and typed.lang == "en")
local function choose_next_language()
    typed:keypressed("y")
    assert(typed.language_menu)
    typed:keypressed("down")
    typed:keypressed("return")
    assert(not typed.language_menu)
end
for _, item in ipairs({{"fr", "é", "É"}, {"ru", "ъ", "Ъ"}, {"uk", "ї", "Ї"}, {"pl", "ż", "Ż"}}) do
    choose_next_language()
    assert(typed.lang == item[1])
    typed:keypressed("x")
    assert(pick(item[2]).text == item[3])
end
choose_next_language()
assert(typed.lang == "zh")
assert(pick("n").kind == "nav" and pick("i").kind == "nav")
assert(typed.pinyin == "ni")
typed:draw("Message")
assert(drawn["ZH  ni · 1/" .. math.ceil(#typed.pinyin_options / 8)])
typed:keypressed("pagedown")
assert(typed.pinyin_page == 2)
typed:keypressed("pageup")
assert(pick("你").text == "你" and typed.pinyin == "")
pick("h")
pick("a")
pick("o")
assert(typed:commit_pinyin() == "好")
pick("x")
typed:keypressed("backspace")
assert(typed.pinyin == "")
for _, language in ipairs({"en","fr","ru","uk","pl"}) do assert(preferences.toggle(language)) end
assert(not preferences.toggle("zh") and preferences.current() == "zh")
assert(preferences.toggle("en"))
assert(preferences.toggle("zh"))
assert(preferences.current() == "en")
typed:keypressed("y")
assert(not typed.language_menu and typed.visible)

menu:enter()
assert(menu:items()[menu.selected_item].id == "my_profile")
menu:keypressed("up")
assert(menu:items()[menu.selected_item].id == "exit_app" and not menu.quit_confirm)
local event = love.event
local quit_called = false
love.event = {quit = function() quit_called = true end}
menu:keypressed("return")
assert(menu.quit_confirm and not quit_called)
menu:keypressed("escape")
assert(not menu.quit_confirm and not quit_called)
menu:keypressed("return")
menu:keypressed("return")
assert(quit_called)
love.event = event
print("Persistent language settings and all six keyboard layouts, including Chinese candidates, passed")

local controller = require("src.shared.system.controller_map")
local mapping = controller.defaults("modern")
assert(controller.position(mapping.confirm) == 4 and controller.position(mapping.back) == 3)
assert(controller.position(mapping.options) == 1 and mapping.shortcuts == "back")
local calibrated_positions
local keymenu = require("src.features.auth.ui.settings_screen").new({normal = font, small = font, tiny = font}, tg, {
    map_key = function(action, button) return controller.remap(mapping, action, button) end,
    reset_keys = function() mapping = controller.defaults("modern") end,
    calibrate_faces = function(positions, preferred)
        calibrated_positions = positions
        assert(preferred == "a")
    end,
})
local screens = replace_upvalue(love.gamepadpressed, "screens", {messenger = screen, settings = keymenu})
replace_upvalue(love.gamepadpressed, "current", keymenu)
keymenu:activate_item({id = "map_keys"})
press(confirm)
assert(keymenu.keymap_waiting == "confirm")
press("leftshoulder")
assert(keymenu.keymap_waiting == "confirm")
press("dpleft")
assert(not keymenu.keymap_waiting)
press(confirm)
press("y")
assert(mapping.confirm == "y" and mapping.options == "a")
local read = controller.read("modern", controller.encode(mapping))
assert(read.confirm == "y" and read.options == "a")
local new_confirm, new_back, dispatch = controller.buttons("modern", read)
assert(new_confirm == "y" and new_back == "b" and dispatch.y == "return" and dispatch.a == "y")
keymenu.keymap_index = #controller.actions + 1
press(confirm)
assert(mapping.confirm == "a" and mapping.options == "y")
press(back)
assert(not keymenu.keymap_open)
keymenu:activate_item({id = "calibrate_faces"})
press("b")
press("b")
assert(keymenu.face_calibration.step == 2)
press("a")
press("x")
press("y")
assert(keymenu.face_calibration.step == 5)
press("a")
assert(not keymenu.face_calibration and calibrated_positions.b == 4 and calibrated_positions.x == 1)
keymenu:activate_item({id = "calibrate_faces"})
press("start")
assert(not keymenu.face_calibration)
local hint_ui = require("src.shared.ui.ui_kit")
local active_x, active_y
love.graphics.circle = function(style, x, y) if style == "fill" then active_x, active_y = x, y end end
hint_ui.set_controller_bindings(calibrated_positions, controller.defaults("modern", calibrated_positions))
hint_ui.button_hint("{confirm}", 0, 0, font, {1, 1, 1})
assert(active_y > 8 and active_x == 8)
hint_ui.set_controller_bindings(calibrated_positions, controller.defaults("retro", calibrated_positions))
hint_ui.button_hint("{confirm}", 0, 0, font, {1, 1, 1})
assert(active_y == 8 and active_x > 8)
hint_ui.set_controller_bindings(nil, controller.defaults("modern"))
replace_upvalue(love.gamepadpressed, "screens", screens)
replace_upvalue(love.gamepadpressed, "current", screen)

local image = {getWidth = function() return 800 end, getHeight = function() return 600 end}
tg.ensure_photo, tg.ensure_photo_hires = noop, noop
tg.photo_image = function() return image, 800, 600 end
local post_url = "https://example.org/field-notes"
local post = {id = 110, chat_id = 42, content = {["@type"] = "messagePhoto", caption = {
    text = text, entities = {{offset = 0, length = 7, type = {["@type"] = "textEntityTypeTextUrl", url = post_url}}},
}}}
tg.current_chat_id = 42
screen.nav_messages, screen.message_cursor_id = {post}, post.id
chat.type["@type"] = "chatTypeSupergroup"
press(confirm)
local reader = assert(screen.text_preview)
assert(reader.photo.message == post and reader.message_text == text and reader.entities[1].type.url == post_url)
screen:draw_text_preview(640, 480)
assert(reader.photo_hit)
press("dpdown")
local scroll = reader.scroll
press(confirm)
assert(screen.fullscreen_media.from_post and screen.fullscreen_media.message == post)
press("rightshoulder")
assert(screen.fullscreen_zoom_target == 1.5)
press(back)
assert(not screen.fullscreen_media and screen.text_preview == reader and reader.scroll == scroll)
for _ = 1, 15 do press("rightshoulder") end
screen:draw_text_preview(640, 480)
assert(drawn.Opening and not drawn[post_url], "Link label must appear in place")
press(back)
assert(not screen.text_preview and screen:focused_message() == post)
local single_photo = {id = 112, chat_id = 42, is_channel_post = true,
    interaction_info = {reply_info = {reply_count = 2}}, content = {["@type"] = "messagePhoto"}}
chat.type = {["@type"] = "chatTypeSupergroup", is_channel = true}
screen.nav_messages, screen.message_cursor_id = {single_photo}, single_photo.id
press(confirm)
assert(screen.fullscreen_media and screen.fullscreen_media.message == single_photo and not screen.text_preview)
assert(screen:focused_comment_target() == single_photo)
press(back)
screen.nav_messages, screen.message_cursor_id = {post}, post.id
chat.type["@type"] = "chatTypePrivate"
press(confirm)
assert(screen.fullscreen_media.message == post and not screen.text_preview)
press(back)

chat.type["@type"] = "chatTypeBasicGroup"
local album_photo = {id = 111, chat_id = 42, media_album_id = "33", content = {["@type"] = "messagePhoto"}}
post.media_album_id = "33"
tg.messages[42] = {album_photo, post}
screen.nav_messages, screen.message_cursor_id = {album_photo, post}, album_photo.id
press(confirm)
assert(screen.text_preview and screen.text_preview.photo.message == album_photo and screen.text_preview.entities[1].type.url == post_url)
press(back)

local sponsor_url = "https://example.org/sponsor/details"
screen.sponsor_focus, screen.sponsor_ad = true, {message_id = 71}
tg.get_channel_sponsors = function() return {by_id = {[71] = {sponsor = {url = sponsor_url}}}} end
love.system = {openURL = function() error("Sponsored link must stay inside SPgram") end}
press(confirm)
assert(screen.text_preview.links[1] == sponsor_url and screen.text_preview.note:find("no web browser", 1, true))
assert(tg.test_request["@type"] == "clickChatSponsoredMessage" and tg.test_request.message_id == 71)
screen:draw_text_preview(640, 480)
assert(drawn[sponsor_url])
press(back)
assert(not screen.text_preview and screen.sponsor_focus)
print("Controller remapping, group and private media, album captions, plain links, and sponsored reporting passed")

local audio = {id = 120, chat_id = 42, content = {["@type"] = "messageAudio", audio = {
    audio = {id = 801, size = 12000}, duration = 34, title = "Field recording",
}, caption = {text = "Audio post text is visible."}}}
screen.sponsor_focus, screen.sponsor_ad = nil, nil
screen.nav_messages, screen.message_cursor_id = {audio}, audio.id
local audio_requests, removals, signs = {}, {}, {}
local last_audio_token
tg.send = function(_, object, extra)
    audio_requests[#audio_requests + 1] = object
    last_audio_token = extra
    return extra
end
love.filesystem.getSaveDirectory = function() return "/fixture" end
love.filesystem.remove = function(path) removals[path] = true end
love.filesystem.write = function(path) signs[path] = true; return true end
local source = {active = false, position = 0}
source.play = function(self) self.active = true; return true end
source.pause = function(self) self.active = false end
source.stop = source.pause
source.isPlaying = function(self) return self.active end
source.release = function(self) self.released = true end
source.getDuration = function() return 34 end
source.tell = function(self) return self.position end
source.seek = function(self, value) self.position = value end
love.audio = {newSource = function(path, mode)
    assert(path == "fixture.mp3" and mode == "stream")
    return source
end}
screen.media_hits, screen.profile_hits, screen.hashtag_hits = {}, {}, {}
screen:draw_message(audio, 220, 130, 400, 140, 340, 10, 280, 16, 16,
    require("src.shared.ui.ui_kit").colors, {message = audio})
assert(drawn[audio.content.caption.text] and not tg.active_audio and #audio_requests == 0)
press(confirm)
assert(screen.fullscreen_media.kind == "audio" and audio_requests[1]["@type"] == "downloadFile")
local function download(path)
    tg:handle_file({["@type"] = "file", ["@extra"] = tg.active_audio.download_token, id = 801, size = 12000,
        ["local"] = {is_downloading_completed = true, path = path}})
end
download("/fixture/fixture.mp3")
assert(tg.active_audio.playing and source.active)
press(confirm)
assert(tg.active_audio.paused and not source.active)
press("rightshoulder")
assert(source.position == 10)
press(confirm)
assert(source.active and source.position == 10)
press(back)
assert(not screen.fullscreen_media and not tg.active_audio and source.released and not source.active)
assert(audio_requests[#audio_requests]["@type"] == "deleteFile" and audio_requests[#audio_requests].file_id == 801)

press(confirm)
download("/fixture/fixture.mp3")
source.active = false
tg:poll_audio_end()
assert(tg.finished_audio == audio and not tg.active_audio)
assert(audio_requests[#audio_requests]["@type"] == "deleteFile")
press(back)

local job
tg.ensure_media_decoder = noop
tg.anim_in = {push = function(_, value) job = value end}
press(confirm)
download("/fixture/unsupported.m4a")
assert(tg.active_audio.status == "decoding" and job.type == "convert_audio")
press(back)
assert(signs[job.name .. ".cancel"] and not tg.active_audio)
tg:finish_audio_conversion({name = job.name, ok = true})
assert(removals[job.name] and removals[job.name .. ".cancel"])
print("Audio post text, on-demand download, pause/resume/seek, and cleanup after Back, natural end and conversion cancellation passed")

local media_a = {id = 130, chat_id = 42, media_album_id = "987654321012345678", is_channel_post = true,
    date = 1700000020, interaction_info = {reply_info = {reply_count = 20}},
    content = {["@type"] = "messageVideo", video = {video = {id = 810}, duration = 30}}}
local media_b = {id = 131, chat_id = 42, media_album_id = media_a.media_album_id, is_channel_post = true,
    date = media_a.date, content = {["@type"] = "messageVideo", video = {video = {id = 811}, duration = 27},
        caption = {text = "One post with two videos."}}}
chat.type = {["@type"] = "chatTypeSupergroup", is_channel = true}
tg.chat_photo_image = noop
tg.messages[42], tg.current_chat_id, tg.viewed_message_ids = {media_a, media_b}, 42, {}
tg.request_channel_sponsors, tg.get_channel_sponsors = noop, noop
screen.message_cursor_id, screen.display_cursor_id = media_a.id, media_a.id
screen.model.scroll, screen.smooth_scroll = 0, 0
screen:draw_conversation(chat, 224, 416, 480)
assert(#screen.media_hits == 2 and screen.media_hits[1].media_kind == "video")
assert(drawn["One post with two videos."])
assert(screen.comment_hits[1].message == media_a and screen.nav_albums[media_a.id][2] == media_b)
local second_video_hit = screen.media_hits[2]
screen:mousepressed(second_video_hit.x + 5, second_video_hit.y + 5, 1)
assert(screen.text_preview and screen.text_preview.album_index == 2 and not screen.fullscreen_media)
press(back)
local comment_hit = screen.comment_hits[1]
screen:mousepressed(comment_hit.x + 5, comment_hit.y + 5, 1)
assert(tg.comments_thread.post == media_a)
press(back)
press(confirm)
assert(screen.text_preview.album[2] == media_b and screen.text_preview.message_text == "One post with two videos.")
press("dpright")
assert(screen.text_preview.photo.message == media_b)
screen:draw_text_preview(640, 480)
assert(screen.text_preview.comment_hit and drawn["Comments (20)"])
assert(not screen.text_preview.comment_selected)
press("dpdown")
assert(screen.text_preview.comment_selected and not tg.comments_thread)
press(confirm)
local thread = assert(tg.comments_thread)
assert(audio_requests[#audio_requests]["@type"] == "getMessageThread" and audio_requests[#audio_requests].message_id == media_a.id)
local root = {chat_id = 99, id = 400}
media_a.interaction_info.reply_info.last_message_id = 410
tg:handle({["@type"] = "messageThreadInfo", ["@extra"] = thread.load_token,
    chat_id = 99, message_thread_id = 400, messages = {root}})
local first_request = audio_requests[#audio_requests]
assert(first_request["@type"] == "getMessageThreadHistory" and first_request.chat_id == 99 and first_request.message_id == 400)
assert(first_request.from_message_id == 400 and first_request.offset < 0)
local reply = {chat_id = 99, id = 410, date = 1700000030,
    reply_to = {["@type"] = "messageReplyToMessage", chat_id = 99, message_id = 400,
        quote = {is_manual = true, text = {text = "Quote from the post"}}},
    content = {["@type"] = "messageText", text = {text = "Existing reply"}}}
tg:handle({["@type"] = "messages", ["@extra"] = thread.load_token, messages = {reply, root}})
assert(#thread.messages == 1 and thread.messages[1] == reply and tg.current_chat_id == 42)
screen:draw_post_comments(640, 480)
assert(drawn["Existing reply"] and drawn["Reply to Channel post"] and drawn["Quote from the post"])
reply.reply_to.quote = nil
screen:draw_post_comments(640, 480)
assert(not thread.rows[reply.id].quote)
reply.reply_to.quote = {is_manual = true, text = {text = "One post with two videos."}}
screen:draw_post_comments(640, 480)
assert(not thread.rows[reply.id].quote)
assert(audio_requests[#audio_requests].source["@type"] == "messageSourceMessageThreadHistory")
press("dpdown")
assert(thread.compose_selected)
press(confirm)
assert(thread.compose and not thread.reply_to)
press(back)
press("dpup")
assert(not thread.compose_selected and thread.focus_id == reply.id)
press(confirm)
local choices = assert(screen.context_menu)
assert(#choices.items == 2 and choices.items[1].label == "View comment" and choices.items[2].label == "Reply")
assert(not thread.compose and not thread.preview)
press(confirm)
assert(thread.preview and thread.preview.message_text == "Existing reply" and not thread.compose)
screen:draw_text_preview(640, 480, thread.preview)
assert(drawn["Existing reply"])
press(back)
assert(not thread.preview and tg.comments_thread == thread and thread.focus_id == reply.id)
local parent_preview = screen.text_preview
local long_comment = string.rep("Long comment paragraph.\n", 40)
reply.content.text.text = long_comment
screen:draw_post_comments(640, 480)
local row_hit = assert(thread.hits[1])
screen:mousepressed(row_hit.x + 6, row_hit.y + 4, 1)
assert(screen.context_menu.items[1].action == "comment_view")
press(confirm)
screen:draw_text_preview(640, 480, thread.preview)
press("dpdown")
assert(thread.preview.scroll == 1 and thread.preview.max_scroll > 1)
press(back)
assert(screen.text_preview == parent_preview and not thread.preview)
reply.content.text.text = "Existing reply"

press(confirm)
press("dpdown")
press(confirm)
assert(thread.compose and thread.reply_to == reply)
screen:textinput("This is a reply.")
press("start")
local request = audio_requests[#audio_requests]
assert(request["@type"] == "sendMessage" and request.chat_id == 99)
assert(request.topic_id["@type"] == "messageTopicThread" and request.topic_id.message_thread_id == 400)
assert(request.reply_to["@type"] == "inputMessageReplyToMessage" and request.reply_to.message_id == 410)
assert(request.input_message_content.text.text == "This is a reply.")
tg:handle({["@type"] = "error", ["@extra"] = thread.send_token, code = 400, message = "Comments are restricted"})
assert(thread.send_error == "Comments are restricted" and thread.draft == "This is a reply.")
press("start")
tg:handle({["@type"] = "message", ["@extra"] = thread.send_token, id = 420, chat_id = 99, content = {
    ["@type"] = "messageText", text = {text = "This is a reply."},
}})
assert(#thread.messages == 2 and thread.messages[2].id == 420 and not thread.compose and thread.reveal_focus)
local quote_lookup = {["@type"] = "messageReplyToMessage", chat_id = 99, message_id = 401}
assert(not tg:comment_reply_parent(thread, quote_lookup))
local requested_quote = audio_requests[#audio_requests]
assert(requested_quote["@type"] == "getMessage" and requested_quote.message_id == 401)
local older = {["@type"] = "message", ["@extra"] = last_audio_token, id = 401, chat_id = 99}
tg:handle(older)
assert(tg:comment_reply_parent(thread, quote_lookup) == older and #thread.messages == 2)
tg:handle({["@type"] = "updateMessageContent", chat_id = 99, message_id = 420, new_content = {
    ["@type"] = "messageText", text = {text = "Edited reply"},
}})
assert(thread.by_id[420].content.text.text == "Edited reply")
tg:update_thread_comment({chat_id = 99, message_ids = {420}, from_cache = true})
assert(#thread.messages == 2)
tg:update_thread_comment({chat_id = 99, message_ids = {420}})
assert(#thread.messages == 1 and thread.focus_id == reply.id)
press(back)
assert(not tg.comments_thread and screen.text_preview.album_index == 2 and tg.current_chat_id == 42)
assert(screen.text_preview.comment_selected)
press(back)
assert(not screen.text_preview)

screen.text_preview = {title = "Long post", message_text = ("A long post.\n"):rep(45), comment = media_a}
screen:draw_text_preview(640, 480)
assert(not screen.text_preview.comment_hit and screen.text_preview.max_scroll > 0)
for _ = 1, 6 do press("rightshoulder") end
screen:draw_text_preview(640, 480)
assert(screen.text_preview.comment_selected and screen.text_preview.comment_hit and not tg.comments_thread)
press("dpup")
assert(not screen.text_preview.comment_selected)
press("dpdown")
press(confirm)
assert(tg.comments_thread and tg.comments_thread.post == media_a)
press(back)
press(back)
print("Selectable comments on short and long posts, quoted replies, new comments, and return to the reader passed")

chat.type = {["@type"] = "chatTypeSupergroup", supergroup_id = 73, is_channel = true}
tg.current_chat_id = chat.id
screen.nav_messages = {message}
screen.message_cursor_id = message.id
screen.composer_focus = nil
screen.keyboard.visible = false
tg:handle({["@type"] = "updateSupergroup", supergroup = {
    ["@type"] = "supergroup", id = 73, status = {["@type"] = "chatMemberStatusMember"},
}})
assert(not screen:can_show_composer(chat))
press("dpdown")
press("start")
assert(not screen.composer_focus and not screen.keyboard.visible)
screen:draw_conversation(chat, 204, 436, 480)
assert(not screen.composer_bounds)

tg:handle({["@type"] = "updateSupergroup", supergroup = {
    ["@type"] = "supergroup", id = 73,
    status = {["@type"] = "chatMemberStatusAdministrator", rights = {can_post_messages = true}},
}})
screen:draw_conversation(chat, 204, 436, 480)
assert(screen.composer_bounds[1] and screen.composer_bounds[2] and screen.composer_bounds[3])

chat.type.is_channel = false
tg:handle({["@type"] = "updateSupergroup", supergroup = {
    ["@type"] = "supergroup", id = 73,
    status = {["@type"] = "chatMemberStatusMember"},
}})
tg:handle({["@type"] = "updateChatPermissions", chat_id = chat.id,
    permissions = {can_send_basic_messages = true, can_send_other_messages = false}})
screen:draw_conversation(chat, 204, 436, 480)
assert(screen.composer_bounds[1] and not screen.composer_bounds[2] and screen.composer_bounds[3])

chat.type = {["@type"] = "chatTypePrivate", user_id = 7}
tg:handle({["@type"] = "canSendMessageToUserResultUserRestrictsNewChats", ["@extra"] = "compose_user:7"})
assert(not screen:can_show_composer(chat))
print("Read-only channel, channel administrator, text-only group, and restricted private composer checks passed")

tg.current_chat_id = nil
tg.me = {id = 7}
screen.model.selected = 1
screen.wants_settings, screen.wants_profile_self = false, false
screen:keypressed("up")
assert(screen.header_focus == "settings")
screen:keypressed("right")
assert(screen.header_focus == "profile")
screen:keypressed("return")
assert(screen.wants_profile_self and not screen.header_focus)
screen:keypressed("up")
screen:keypressed("return")
assert(screen.wants_settings and not screen.header_focus)
screen:keypressed("up")
screen:keypressed("down")
assert(not screen.header_focus and screen.model.selected == 1)

message.forward_info = {
    origin = {["@type"] = "messageOriginUser", sender_user_id = 8},
    source = {chat_id = -9876, sender_id = {["@type"] = "messageSenderUser", user_id = 8}},
}
local routed_user, routed_chat
for _, item in ipairs(screen:context_menu_items(message)) do
    if item.label == "Original sender profile" then routed_user = item end
    if item.label == "Forwarded via · Chat info" then routed_chat = item end
end
assert(routed_user and routed_user.user_id == 8)
assert(routed_chat and routed_chat.chat_id == -9876 and not routed_chat.user_id)
screen:activate_context_item({message = message}, routed_chat)
assert(screen.wants_profile_chat_id == -9876 and not screen.wants_profile_user_id)

local channel = {id = -9876, title = "Pixel News",
    type = {["@type"] = "chatTypeSupergroup", supergroup_id = 41, is_channel = true}}
tg.chats_by_id[channel.id] = channel
tg.profile_media = {}
local profile = require("src.features.auth.ui.profile_screen").new(screen.fonts, tg)
profile.chat_id = channel.id
profile:enter()
tg:handle({["@type"] = "supergroupFullInfo", ["@extra"] = "profile_details:-9876",
    description = "Retro handheld news.", member_count = 750})
profile:draw()
assert(profile.peer_kind == "Channel" and not profile.user_id)
assert(drawn["Channel info"] and drawn["750 subscribers"] and drawn["Retro handheld news."])
print("Header shortcuts and forwarded user, source chat and channel details passed")

local original = {id = 501, chat_id = 42, sender_id = {["@type"] = "messageSenderUser", user_id = 8},
    content = {["@type"] = "messageText", text = {text = "Original body"}}}
local quoted = {id = 502, chat_id = 42, content = {["@type"] = "messageText", text = {text = "The reply"}},
    reply_to = {["@type"] = "messageReplyToMessage", chat_id = 42, message_id = 501,
        quote = {text = {text = "Selected quote"}}}}
tg.current_chat_id = 42
tg.messages[42] = {original, quoted}
for _, chat_type in ipairs({"chatTypePrivate", "chatTypeBasicGroup", "chatTypeSupergroup"}) do
    chat.type = {["@type"] = chat_type, is_channel = chat_type == "chatTypeSupergroup"}
    drawn["Reply to Original"], drawn["Selected quote"] = nil, nil
    screen:draw_conversation(chat, 204, 436, 480)
    assert(drawn["Reply to Original"] and drawn["Selected quote"], chat_type)
end
assert(screen:read_message(quoted))
screen:draw_text_preview(640, 480)
assert(screen.text_preview.quote == "Selected quote" and drawn["The reply"])
assert(screen.text_preview.quote_selected and screen.text_preview.quote_hit)
screen:keypressed("down")
assert(screen.text_preview and not screen.text_preview.quote_selected)
screen:keypressed("up")
assert(screen.text_preview.quote_selected)
screen:keypressed("return")
assert(not screen.text_preview and tg.history_state[42].initial_focus_id == 501)

tg.messages[42] = {quoted}
local reply_info = quoted.reply_to
reply_info.quote = nil
local lookup, status = tg:resolve_message_reply(quoted, reply_info)
assert(not lookup and status == "Loading original…")
local token = last_audio_token
local count = #audio_requests
tg:resolve_message_reply(quoted, reply_info)
assert(#audio_requests == count and audio_requests[count]["@type"] == "getMessage")
original["@type"], original["@extra"] = "message", token
tg:handle(original)
assert(tg:resolve_message_reply(quoted, reply_info) == original)
tg:update_reply_preview({chat_id = 42, message_id = original.id,
    new_content = {["@type"] = "messageText", text = {text = "Edited original"}}})
local _, body = tg:reply_preview(reply_info, original)
assert(body == "Edited original")
tg:update_reply_preview({chat_id = 42, message_ids = {original.id}})
local parent, missing = tg:resolve_message_reply(quoted, reply_info)
assert(not parent and not missing and #audio_requests == count)

local remote = {["@type"] = "messageReplyToMessage", chat_id = -9876, message_id = 909,
    origin = {["@type"] = "messageOriginChannel", chat_id = -9876},
    content = {["@type"] = "messagePhoto", caption = {text = "Remote caption"}}}
assert(not tg:resolve_message_reply(quoted, remote))
local origin, text = tg:reply_preview(remote)
assert(origin == "Pixel News" and text == "Remote caption" and #audio_requests == count)

tg.messages[42] = {quoted}
assert(screen:read_message(quoted))
screen:draw_text_preview(640, 480)
screen:keypressed("return")
local quoted_request = screen.text_preview.quote_jump
assert(quoted_request and audio_requests[#audio_requests].from_message_id == 501)
tg:handle({["@type"] = "messages", ["@extra"] = quoted_request.token, messages = {quoted}})
screen:update_quote_jump()
assert(screen.text_preview.quote_error and not screen.text_preview.quote_jump)
screen:keypressed("return")
quoted_request = screen.text_preview.quote_jump
tg:handle({["@type"] = "messages", ["@extra"] = quoted_request.token, messages = {quoted, original}})
screen:update_quote_jump()
assert(not screen.text_preview and tg.history_state[42].initial_focus_id == 501)
assert(tg.messages[42][1] == original and tg.messages[42][2] == quoted)

screen.keyboard.visible = true
screen.model.input = string.rep("Earlier draft text ", 40) .. "TAIL"
screen.keyboard:draw(screen:keyboard_preview())
local rows = screen.keyboard.draft_preview.rows
assert(#rows > 2 and rows[#rows]:find("TAIL", 1, true) and drawn[rows[#rows]])
screen.keyboard:draw("", "Write a message…")
assert(drawn["Write a message…"] and not screen.keyboard.draft_preview)
print("Conversation reply previews, full quotes, older-message lookup, and live keyboard draft passed")

do
    local own = require("src.features.auth.ui.profile_screen").new(screen.fonts, tg)
    tg.me = {id = 7, first_name = "Sam", last_name = "Tester", usernames = {active_usernames = {"sam"}}}
    tg.users[7] = tg.me
    own.is_me = true
    own:enter()
    assert(audio_requests[#audio_requests]["@type"] == "getUserFullInfo")
    own:keypressed("return")
    local get_info_token = last_audio_token
    tg:handle({["@type"] = "userFullInfo", ["@extra"] = get_info_token, bio = {text = "Original bio"}})
    own:update()
    assert(own.status == "" and own.bio == "Original bio" and own.editor.bio == "Original bio")
    own:keypressed("return")
    own:textinput("uel")
    own:keypressed("f1")
    own:keypressed("down")
    own:keypressed("down")
    own:keypressed("return")
    own:textinput(" changed")
    own:keypressed("f1")
    own:keypressed("down")
    own:keypressed("return")
    local state = own.editor.saving
    assert(state.pending == 2 and audio_requests[#audio_requests]["@type"] == "setBio")
    local name_token = "my_profile_save:" .. state.sequence .. ":name"
    local bio_token = "my_profile_save:" .. state.sequence .. ":bio"
    tg:handle({["@type"] = "ok", ["@extra"] = name_token})
    tg:handle({["@type"] = "error", ["@extra"] = bio_token, message = "Try again"})
    own:update()
    assert(own.editor and own.editor.error:find("Try again") and tg.me.first_name == "Samuel")
    own:keypressed("return")
    assert(own.editor.saving.pending == 1 and audio_requests[#audio_requests]["@type"] == "setBio")
    tg:handle({["@type"] = "ok", ["@extra"] = last_audio_token})
    own:update()
    own:draw()
    assert(not own.editor and own.bio == "Original bio changed" and drawn["Profile saved"])
end

do
    chat.type = {["@type"] = "chatTypePrivate", user_id = 8}
    tg.current_chat_id = 42
    screen.model.input = "你好🙂 "
    screen:open_stickers()
    local home = tg.sticker_set_viewer
    screen:open_picker_category(home, 3)
    local library = tg.sticker_set_viewer
    assert(library.emoji_sets and audio_requests[#audio_requests]["@type"] == "getTrendingStickerSets")
    assert(audio_requests[#audio_requests - 1].sticker_type["@type"] == "stickerTypeCustomEmoji")
    local set = {id = "9223372036854775000", title = "Pixel icons"}
    tg:handle({["@type"] = "stickerSets", ["@extra"] = "emoji_sets_installed:" .. library.generation, sets = {set}})
    tg:handle({["@type"] = "trendingStickerSets", ["@extra"] = "emoji_sets_trending:" .. library.generation, sets = {set}})
    local entries = screen:picker_layout(library, 640, 480).entries
    assert(#entries == 1 and entries[1].kind == "emoji_set")
    screen:activate_picker_item(library, entries[1])
    local pack = tg.sticker_set_viewer
    local id = "9223372036854775001"
    local emoji = {emoji = "🎮", full_type = {["@type"] = "stickerFullTypeCustomEmoji", custom_emoji_id = id}}
    tg:handle({["@type"] = "stickerSet", ["@extra"] = "emoji_pack:" .. pack.generation, id = set.id, stickers = {emoji}})
    local pack_entries = screen:picker_layout(pack, 640, 480).entries
    screen:activate_picker_item(pack, pack_entries[1])
    assert(audio_requests[#audio_requests]["@type"] == "changeStickerSet" and audio_requests[#audio_requests].is_installed)
    tg:handle({["@type"] = "ok", ["@extra"] = last_audio_token})
    assert(pack.is_installed and #library.installed == 1)
    screen:activate_picker_item(pack, pack_entries[2])
    assert(screen.model.input == "你好🙂 🎮" and not tg.sticker_set_viewer)
    screen:send()
    local sent = audio_requests[#audio_requests].input_message_content.text
    local entity = sent.entities[1]
    assert(entity.offset == 5 and entity.length == 2 and entity.type.custom_emoji_id == id)
    assert(not tg:custom_emoji_sticker(id))
    tg:request_custom_emojis()
    assert(audio_requests[#audio_requests].custom_emoji_ids[1] == id)
    tg:handle({["@type"] = "stickers", ["@extra"] = last_audio_token, stickers = {emoji}})
    assert(tg:custom_emoji_sticker(id) == emoji)
    local preview = {thumbnail = {format = {["@type"] = "thumbnailFormatWebp"},
        width = 64, height = 64, file = {id = 88771, ["local"] = {can_be_downloaded = true}}}}
    tg:media_thumbnail(preview)
    assert(audio_requests[#audio_requests]["@type"] == "downloadFile")
    assert(audio_requests[#audio_requests].file_id == 88771)
    local helpers = require("src.features.chat.ui.chat_screen_helpers")
    local ranges = helpers.custom_emoji_ranges(sent.text, sent.entities)
    local painted
    love.graphics.draw = function(image) painted = image end
    local image = {getWidth = function() return 15 end, getHeight = function() return 15 end}
    helpers.draw_link_line(sent.text, 1, nil, 0, 0, font, {1, 1, 1}, ranges, function(key)
        assert(key == id)
        return image
    end)
    assert(painted == image)
end
print("My Profile editing, partial-save retry, and Telegram emoji packs, insertion, and rendering passed")

do
    local notice = {chat_id = 42, avatar_chat_id = 42, user_id = 12345678}
    assert(tg:notification_title(notice) == chat.title)
    tg.users[notice.user_id] = {first_name = "Mika", last_name = "Chen"}
    assert(tg:notification_title(notice) == "Mika Chen")
    tg.current_chat_id = 42
    chat.type = {["@type"] = "chatTypeSupergroup", is_channel = true}
    assert(screen:read_message({id = 515, chat_id = 42, is_channel_post = true,
        author_signature = "News Desk", content = {["@type"] = "messageText", text = {text = "Today's post"}}}))
    screen:draw_text_preview(640, 480)
    assert(drawn["News Desk"])
    screen.text_preview = nil

    local thread = tg:request_comments(media_a)
    tg:handle({["@type"] = "messageThreadInfo", ["@extra"] = thread.load_token,
        chat_id = 99, message_thread_id = 400, messages = {{chat_id = 99, id = 400}}})
    local current = {chat_id = 99, id = 980, content = {["@type"] = "messageText", text = {text = "Nested reply"}},
        reply_to = {["@type"] = "messageReplyToMessage", chat_id = 99, message_id = 907}}
    tg:handle({["@type"] = "messages", ["@extra"] = thread.load_token, messages = {current}})
    screen:keypressed("y")
    assert(screen.context_menu.items[2].label == "Jump to quoted comment")
    screen:keypressed("down")
    screen:keypressed("return")
    local request = audio_requests[#audio_requests]
    assert(request["@type"] == "getMessageThreadHistory" and request.chat_id == 99 and request.message_id == 400)
    assert(request.from_message_id == 907 and request.offset < 0)
    local earlier = {chat_id = 99, id = 907, content = {["@type"] = "messageText", text = {text = "Older comment"}}}
    tg:handle({["@type"] = "messages", ["@extra"] = thread.jump_token, messages = {earlier}})
    assert(thread.focus_id == 907 and thread.reveal_focus)

    local played, stopped
    tg.request_media_playback = function(_, media) played = media end
    tg.stop_media_playback = function(_, media) stopped = media end
    tg.ensure_photo, tg.ensure_photo_hires = noop, noop
    tg.ensure_sticker, tg.ensure_animated_sticker = noop, noop
    tg.ensure_animation, tg.animation_thumbnail = noop, noop
    tg.sticker_image, tg.media_thumbnail = noop, noop

    local fixtures = {
        {"messagePhoto", "photo"},
        {"messageVideo", "video", {video = {id = 1002, duration = 24}}},
        {"messageVideoNote", "video", {video_note = {duration = 9}}},
        {"messageAudio", "audio", {audio = {title = "A song", duration = 30}}},
        {"messageVoiceNote", "audio", {voice_note = {duration = 7}}},
        {"messageAnimation", "animation", {animation = {animation = {id = 993}}}},
        {"messageSticker", "sticker", {sticker = {emoji = "🎮"}}},
    }
    for index, fixture in ipairs(fixtures) do
        local content = fixture[3] or {}
        content["@type"] = fixture[1]
        local media = {id = 1000 + index, chat_id = 99,
            topic_id = {message_thread_id = 400}, content = content}
        tg:receive_thread_message(media)
        thread.focus_id, thread.reveal_focus = media.id, true
        screen:draw_post_comments(640, 480)
        local row = thread.rows[media.id]
        assert(row.media and row.body == "", fixture[1])
        screen:keypressed("return")
        assert(screen.context_menu.items[1].label == "View comment" and not screen.fullscreen_media)
        screen:keypressed("return")
        assert(thread.preview and thread.preview.comment_media.message == media and not screen.fullscreen_media)
        screen:draw_text_preview(640, 480, thread.preview)
        screen:keypressed("return")
        assert(screen.fullscreen_media.from_comments and screen.fullscreen_media.kind == fixture[2], fixture[1])
        if fixture[2] == "audio" or fixture[2] == "video" then assert(played == media) end
        screen:keypressed("escape")
        assert(not screen.fullscreen_media and tg.comments_thread == thread and thread.focus_id == media.id)
        if fixture[2] == "audio" or fixture[2] == "video" then assert(stopped == media) end
        assert(thread.preview)
        screen:keypressed("escape")
        assert(not thread.preview and thread.focus_id == media.id)
    end
    screen:keypressed("escape")
    assert(not tg.comments_thread)
    local parent_photo = {id = 600, chat_id = 42, content = {["@type"] = "messageSticker", sticker = {sticker = {id = 710}}}}
    local thread_photo = {id = 600, chat_id = 99, content = {["@type"] = "messageSticker", sticker = {sticker = {id = 711}}}}
    local _, first = tg:media_file_for_message(parent_photo)
    local _, second = tg:media_file_for_message(thread_photo)
    assert(first == 710 and second == 711)
end
print("Dynamic notification names, channel post authors, quoted comment jumps and all six comment media kinds passed")

do
    local post = {chat_id = 42, id = 300, interaction_info = {reply_info = {reply_count = 5, last_message_id = 0}}}
    local thread = tg:request_comments(post)
    local root = {chat_id = 99, id = 400}
    tg:handle({["@type"] = "messageThreadInfo", ["@extra"] = thread.load_token,
        chat_id = 99, message_thread_id = root.id, messages = {root}})
    local emoji = {["@type"] = "reactionTypeEmoji", emoji = "👍"}
    local function comment(id)
        return {chat_id = 99, id = id, content = {["@type"] = "messageText", text = {text = "Comment " .. id}}}
    end
    local function info(count, chosen)
        return {reactions = {reactions = {{type = emoji, total_count = count, is_chosen = chosen}}}}
    end
    local first, middle, last = comment(405), comment(410), comment(415)
    first.interaction_info = info(2, false)
    tg:handle({["@type"] = "messages", ["@extra"] = thread.load_token, messages = {middle, first, root}})
    assert(thread.focus_id == first.id and thread.scroll == 0 and thread.has_more)
    screen:draw_post_comments(640, 480)
    assert(thread.rows[first.id].reactions[1][1].count == "2")
    local before = #audio_requests
    screen:keypressed("up")
    screen:keypressed("pageup")
    assert(#audio_requests == before and thread.focus_id == first.id and not thread.error)

    screen:keypressed("y")
    assert(screen.context_menu.items[2].action == "comment_react")
    screen:keypressed("down")
    screen:keypressed("return")
    local menu = assert(screen.reaction_menu)
    local request = audio_requests[#audio_requests]
    assert(request["@type"] == "getMessageAvailableReactions" and request.chat_id == 99 and request.message_id == first.id)
    tg:handle({["@type"] = "availableReactions", ["@extra"] = menu.token,
        top_reactions = {{type = emoji}, {type = {["@type"] = "reactionTypePaid"}}},
        recent_reactions = {{type = emoji}}})
    assert(#menu.items == 1 and not menu.items[1].chosen)
    screen:keypressed("return")
    request = audio_requests[#audio_requests]
    assert(request["@type"] == "addMessageReaction" and request.chat_id == 99 and request.message_id == first.id)
    assert(request.reaction_type == emoji)
    tg:handle({["@type"] = "ok", ["@extra"] = thread.reaction_token})
    tg:handle({["@type"] = "updateMessageInteractionInfo", chat_id = 99, message_id = first.id, interaction_info = info(3, true)})
    screen:draw_post_comments(640, 480)
    assert(thread.rows[first.id].reactions[1][1].count == "3")
    assert(thread.rows[first.id].reactions[1][1].reaction.chosen)
    screen:open_reaction_menu(first, thread)
    tg:handle({["@type"] = "availableReactions", ["@extra"] = screen.reaction_menu.token, top_reactions = {}})
    screen:keypressed("return")
    request = audio_requests[#audio_requests]
    assert(request["@type"] == "removeMessageReaction" and request.reaction_type == emoji)
    assert(thread.focus_id == first.id and not screen.reaction_menu)

    screen:keypressed("down")
    assert(thread.focus_id == middle.id)
    screen:keypressed("down")
    request = audio_requests[#audio_requests]
    assert(request.chat_id == 99 and request.from_message_id == middle.id and request.offset < 0)
    tg:handle({["@type"] = "messages", ["@extra"] = thread.load_token, messages = {last, middle}})
    assert(thread.focus_id == last.id and #thread.messages == 3 and thread.has_more)
    screen:keypressed("down")
    tg:handle({["@type"] = "messages", ["@extra"] = thread.load_token, messages = {last}})
    assert(thread.compose_selected and not thread.has_more and not thread.error)
    before = #audio_requests
    screen:keypressed("down")
    assert(#audio_requests == before)
    screen:keypressed("escape")

    local empty = tg:request_comments(post)
    tg:handle({["@type"] = "messageThreadInfo", ["@extra"] = empty.load_token,
        chat_id = 99, message_thread_id = root.id, messages = {root}})
    tg:handle({["@type"] = "messages", ["@extra"] = empty.load_token, messages = {root}})
    assert(not empty.has_more and not empty.error and empty.compose_selected and #empty.messages == 0)
    screen:keypressed("escape")
end
print("Oldest-first comments, forward paging, quiet boundaries, and comment reactions passed")

do
    local room = {id = 17, has_protected_content = true}
    local requests = 0
    local session = setmetatable({chats_by_id = {[17] = room}, messages = {[17] = {{id = 21, can_be_saved = false}}},
        send = function() requests = requests + 1; return "fixture" end}, {__index = client})
    assert(not session:forward_messages(18, 17, {21}) and requests == 0)
    session:handle({["@type"] = "updateChatHasProtectedContent", chat_id = 17, has_protected_content = false})
    assert(not room.has_protected_content and not session:forward_messages(18, 17, {21}))
    assert(session:forward_messages(18, 17, {22}) and requests == 1)
    for _, kind in ipairs({"Photo", "Video", "VoiceNote"}) do
        local message = {id = 22, chat_id = 17,
            self_destruct_type = {["@type"] = "messageSelfDestructTypeImmediately"},
            content = {["@type"] = "message" .. kind}}
        assert(session:is_ephemeral_media(message) and not session:message_can_be_shared(message))
        assert(not session:ensure_photo(message, true) and not session:video_thumbnail(message))
        assert(not session:request_video(message) and not session:request_audio(message))
    end
    assert(requests == 1)
end
print("Protected forwarding and disappearing media checks passed")

do
    screen.text_preview, screen.fullscreen_media, tg.comments_thread = nil, nil, nil
    chat.type = {["@type"] = "chatTypePrivate", user_id = 81}
    tg.users[81] = {id = 81, first_name = "Fixture Author"}
    local text = "See @fixture and t.me/fixture_group. Site"
    local site_start = text:find("Site", 1, true)
    local message = {id = 999, chat_id = 42, sender_id = {["@type"] = "messageSenderUser", user_id = 81},
        content = {["@type"] = "messageText", text = {text = text, entities = {
            {offset = site_start - 1, length = 4, type = {["@type"] = "textEntityTypeTextUrl", url = "https://example.org"}},
        }}}}
    assert(screen:read_message(message))
    screen:draw_text_preview(640, 480)
    local reader = screen.text_preview
    assert(drawn["Message from Fixture Author"] and #reader.reader_links == 3)
    screen:keypressed("y")
    assert(reader.link_index == 1)
    screen:keypressed("return")
    local pending = screen.sponsor_prompt.link
    assert(pending.prefer_profile and not screen.text_preview)
    pending.user_id = 81
    screen:update_sponsor_link()
    assert(screen.text_preview == reader and screen.wants_profile_user_id == 81)
    screen.wants_profile_user_id = nil
    screen:keypressed("down")
    assert(reader.link_index == 2 and reader.reader_links[2].url == "t.me/fixture_group")
    screen:keypressed("down")
    screen:keypressed("return")
    assert(screen.text_preview.title == "External link" and screen.text_preview.links[1] == "https://example.org")
    screen:keypressed("escape")
    assert(screen.text_preview == reader)
    screen:keypressed("escape")
    assert(not reader.link_index)
    screen:keypressed("escape")
    assert(not screen.text_preview)

    local menu = require("src.features.auth.ui.settings_screen").new({}, tg, {
        accounts = function() return {{key = "account_1", title = "Fixture Author"}}, "account_1" end,
    })
    for _, item in ipairs(menu:items()) do assert(item.id ~= "account:account_1" and item.id ~= "logout") end
    menu:activate_item(menu:items()[2])
    assert(menu.section.label == "My profile")
    local account_items = menu:items()
    assert(account_items[1].id == "profile" and account_items[2].id == "account:account_1"
        and account_items[3].id == "add_account" and account_items[4].id == "logout")
end
print("Reader sender labels, link selection, and account submenu passed")

do
    local gif = {id = 1004, chat_id = 42, is_channel_post = true,
        interaction_info = {reply_info = {reply_count = 2}},
        content = {["@type"] = "messageAnimation", animation = {width = 720, height = 980, animation = {id = 3346}}}}
    chat.type = {["@type"] = "chatTypeSupergroup", is_channel = true}
    tg.messages[42], tg.current_chat_id = {gif}, 42
    tg.animation_by_message[tg:media_message_key(gif)] = 3346
    local entry = {status = "remote"}
    tg.animations[3346] = entry
    tg.ensure_animation = noop
    tg.animation_image = function() return entry.image end
    screen.model.scroll, screen.smooth_scroll = 0, 0
    local function bounds()
        screen:draw_conversation(chat, 204, 436, 480)
        local position, hit, comments = screen.nav_pos[gif.id], screen.media_hits[1], screen.comment_hits[1]
        assert(position and hit and comments)
        return {position.y, position.h, hit.media_x, hit.media_y, hit.media_w, hit.media_h, comments.y}
    end
    local resting = bounds()
    drawn["0 KB loaded"] = nil
    entry.status = "downloading"
    local pending = bounds()
    assert(not drawn["0 KB loaded"])
    tg:handle_animation_file({id = 3346, size = 1024, ["local"] = {downloaded_prefix_size = 512}}, entry)
    assert(entry.downloaded_bytes == 512 and entry.download_progress == 0.5)
    entry.image = {getWidth = function() return 207 end, getHeight = function() return 128 end}
    local with_thumbnail = bounds()
    entry.status = "ready"
    local ready = bounds()
    for index, value in ipairs(resting) do
        assert(pending[index] == value and with_thumbnail[index] == value and ready[index] == value)
    end

    local pixel
    tg.photo_image = function() return pixel, 48, 128 end
    tg.sticker_image = function() return pixel, 128, 48 end
    tg.ensure_photo, tg.ensure_sticker, tg.ensure_animated_sticker = noop, noop, noop
    for _, content in ipairs({
        {["@type"] = "messagePhoto", photo = {sizes = {{width = 320, height = 280, photo = {id = 3350}}}},
            caption = {text = "The photo stays in place."}},
        {["@type"] = "messageSticker", sticker = {width = 320, height = 420, sticker = {id = 3351}}},
    }) do
        gif.content = content
        pixel = nil
        local empty = bounds()
        local cached = screen.cached_conversation_layout
        pixel = {getWidth = function() return 48 end, getHeight = function() return 128 end}
        local loaded = bounds()
        assert(screen.cached_conversation_layout == cached)
        for index, value in ipairs(empty) do assert(loaded[index] == value) end
    end
end
print("Photo, sticker and GIF layout stays fixed as textures and progress arrive")
