package.preload.utf8 = function()
    return {len = string.len}
end
local client = require("src.shared.api.tdlib_client")
local auth = require("src.features.auth.ui.auth_screen")
local buttons = require("src.shared.system.controller_map")
local confirm, back, keys = buttons.buttons("modern")
assert(confirm == "a" and back == "b" and keys.x == "x" and keys.y == "y")
assert(buttons.position(confirm) == 4 and buttons.position(back) == 3)
assert(keys[confirm] == "return" and keys[back] == "escape")
local swapped_confirm, swapped_back, swapped_keys = buttons.buttons("retro")
assert(swapped_confirm == back and swapped_back == confirm)
assert(swapped_keys[swapped_confirm] == "return" and swapped_keys[swapped_back] == "escape")
assert(swapped_keys.x == keys.x and swapped_keys.y == keys.y and swapped_keys.dpdown == "down")
assert(buttons.position(swapped_confirm) == 3 and buttons.position(swapped_back) == 4)
local reversed = assert(buttons.read_positions("top=x\nleft=y\nright=a\nbottom=b\n"))
assert(buttons.position("b", reversed) == 4 and buttons.position("x", reversed) == 1)
local calibrated = buttons.defaults("modern", reversed)
assert(calibrated.confirm == "b" and calibrated.options == "x" and calibrated.back == "a")
assert(buttons.read_positions(buttons.encode_positions(reversed)).a == 3)
assert(not buttons.read_positions("top=x\nleft=x\nright=a\nbottom=b\n"))
local legacy = "confirm=b\nback=a\noptions=y\nsearch=x\nshortcuts=back\nkeyboard=start\n"
assert(buttons.read("modern", legacy).confirm == "a")
local deliberately_swapped = buttons.defaults("retro")
assert(buttons.read("modern", buttons.encode(deliberately_swapped)).confirm == "b")
local custom = "confirm=y\nback=a\noptions=b\nsearch=x\nshortcuts=back\nkeyboard=start\n"
assert(buttons.read("modern", custom).confirm == "y")
local sent = {}
local tg = setmetatable({
    options = {manual_auth = true},
    send = function(_, request, extra) sent[#sent + 1] = {request, extra} end,
    reset_account_state = function() end,
}, {__index = client})

tg:handle_authorization({["@type"] = "authorizationStateWaitPhoneNumber"})
assert(#sent == 0, "manual login must not compete with an automatic QR request")
local swaps = 0
local screen = auth.new({}, tg, {toggle_face_buttons = function() swaps = swaps + 1 end})
screen:enter()
screen:keypressed("f1")
assert(swaps == 1 and #sent == 0)
screen:keypressed(keys[confirm])
assert(screen:keyboard_mode() == "phone")
assert(screen.password == "+")
screen:keypressed("f1")
assert(#sent == 0, "incomplete number must not be sent")
screen:textinput("ignored")
for digit in ("9996620001"):gmatch(".") do screen:textinput(digit) end
screen:keypressed("f1")
assert(#sent == 1 and sent[1][1]["@type"] == "setAuthenticationPhoneNumber")
assert(sent[1][1].phone_number == "+9996620001")
screen:keypressed("f1")
assert(#sent == 1, "duplicate submit is blocked")
tg:handle_authorization({["@type"] = "authorizationStateWaitCode"})
screen:sync_keyboard()
assert(screen:keyboard_mode() == "code" and screen.password == "")
screen:textinput("bad")
screen:textinput("11111")
screen:keypressed("f1")
assert(#sent == 2 and sent[2][1]["@type"] == "checkAuthenticationCode")
assert(sent[2][1].code == "11111" and screen.password == "")
tg:handle({["@type"] = "error", ["@extra"] = sent[2][2], code = 400,
    message = "private-message-fixture"})
assert(not tg.auth_input_pending and not tg.auth_error:find("private-message-fixture", 1, true))
screen:textinput("22222")
screen:keypressed("f1")
assert(#sent == 3 and sent[3][1].code == "22222")
tg:handle_authorization({["@type"] = "authorizationStateWaitPassword"})
screen:sync_keyboard()
screen:textinput("password-fixture")
screen:keypressed("f1")
assert(#sent == 4 and sent[4][1]["@type"] == "checkAuthenticationPassword")
assert(screen.password == "")

love = {timer = {getTime = function() return 1 end}}
tg:handle_authorization({["@type"] = "authorizationStateWaitPhoneNumber"})
screen:enter()
screen:keypressed("down")
screen:keypressed("return")
assert(#sent == 5 and sent[5][1]["@type"] == "requestQrCodeAuthentication")

local config = require("src.shared.system.telegram_config")
local path = os.tmpname()
local file = assert(io.open(path, "wb"))
file:write("\239\187\191api_id=12345\r\napi_hash=", string.rep("a", 32), "\r\n")
file:close()
local id, hash = config.credentials(config.read(path))
assert(id == 12345 and #hash == 32)
local bundled_id, bundled_hash = config.for_app({}, path)
assert(bundled_id == id and bundled_hash == hash)
assert(config.for_app({api_id = "1", api_hash = hash}, path) == id)
os.remove(path)
for _, fixture in ipairs({{}, {api_id = "1e4", api_hash = hash},
    {api_id = "12345", api_hash = "placeholder"}}) do
    local rejected, _, reason = config.credentials(fixture)
    assert(not rejected and reason)
end

local drawn = {}
local ui = require("src.shared.ui.ui_kit")
local circles = {}
love.graphics = {
    setColor = function() end,
    circle = function(mode, x, y) circles[#circles + 1] = {mode, x, y} end,
}
local hint_font = {getHeight = function() return 14 end, getWidth = function(_, text) return #text end}
ui.button_hint("{confirm}", 0, 0, hint_font, ui.colors.text)
ui.button_hint("{back}", 0, 0, hint_font, ui.colors.text)
assert(#circles == 8 and circles[4][1] == "fill" and circles[4][3] > circles[2][3])
assert(circles[7][1] == "fill" and circles[7][2] > circles[6][2])
ui.width = function() return 640 end
ui.height = function() return 480 end
ui.rect = function() end
ui.text = function() end
ui.printf = function(label) drawn[#drawn + 1] = label end
ui.button_hint = ui.printf
love.filesystem = {read = function(name)
    assert(name == "VERSION")
    return "0.2.57\n"
end}
local setup = auth.new({}, {
    setup_error = "Telegram API credentials are missing.", setup_path = "telegramsp/conf/telegram.conf",
})
setup:draw()
local text = table.concat(drawn, "\n")
assert(text:find("Telegram setup required", 1, true))
assert(text:find("v0.2.57", 1, true))
assert(text:find("telegramsp/conf/telegram.conf", 1, true))
assert(text:find("{confirm} — Exit", 1, true))
assert(not text:find("QR", 1, true) and not text:find("Starting", 1, true))
love.event = {quit = function() drawn[#drawn + 1] = "exit" end}
setup:keypressed(keys[confirm])
assert(drawn[#drawn] == "exit")

local preview_sent = {}
local preview = setmetatable({
    options = {sign_in_only = true, encryption_key = "fixture"},
    sequence = 0,
    in_channel = {push = function(_, item) preview_sent[#preview_sent + 1] = item end},
}, {__index = client})
assert(preview:send({["@type"] = "getChatHistory"}) == nil)
assert(preview:send({["@type"] = "searchPublicChats"}) == nil)
assert(preview:send({["@type"] = "sendMessage"}) == nil)
preview:handle({["@type"] = "updateNewMessage", message = {id = 1}})
preview:handle_authorization({["@type"] = "authorizationStateWaitTdlibParameters"})
preview:handle_authorization({["@type"] = "authorizationStateReady"})
assert(preview.ready and #preview_sent == 1)
local params = require("dkjson").decode(preview_sent[1].req)
assert(not params.use_message_database and not params.use_chat_info_database and not params.use_file_database)
os.getenv = original_getenv
print("Phone, code retry, 2FA, QR and first-launch setup checks passed")

local intro = require("src.shared.ui.startup_intro")
local clock, playing, released, volume = 0, false, 0, nil
love.timer.getTime = function() return clock end
local fake = {
    play = function() assert(volume == 0.25); playing = true end,
    getSource = function() return {setVolume = function(_, value) volume = value end} end,
    pause = function() playing = false end,
    release = function() released = released + 1 end,
    isPlaying = function() return playing end,
}
love.graphics.newVideo = function(path)
    assert(path == "intro/spgram-intro.ogv")
    return fake
end
local player = intro.new(font)
assert(player.video == fake and playing)
assert(not player:update({ready = true, chats_loaded = true}))
player.presented = true
assert(not player:update({ready = true, chats_loaded = false}))
assert(not player:update({ready = true, chats_loaded = true}) and player.video == fake)
playing = false
assert(player:update({ready = true, chats_loaded = true}) and not player.video and released == 1)

player = intro.new(font)
player.presented = true
playing = false
clock = 5
assert(not player:update({auth_state = "authorizationStateWaitTdlibParameters"}))
assert(not player.video and released == 2)
assert(player:update({auth_state = "authorizationStateWaitPhoneNumber"}))

love.graphics.newVideo = function() error("Missing intro") end
local opened = 0
local original = love.graphics.newVideo
love.graphics.newVideo = function(...) opened = opened + 1; return original(...) end
player = intro.new(font, false)
assert(opened == 0 and not player.video)
assert(not player:update({auth_state = "starting"}))
assert(player:update({auth_state = "authorizationStateWaitPhoneNumber"}))
player = intro.new(font)
player.presented = true
clock = 14
assert(player:update({auth_state = "starting"}))
print("Startup cover lets the intro finish, skips opening a disabled intro and handles missing assets or slow startup")
