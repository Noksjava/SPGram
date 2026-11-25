local client = require("src.shared.api.tdlib_client")
local native = require("src.shared.api.native_library")

local sent = {}
local tg = setmetatable({
    options = {
        encryption_key = string.rep("A", 43) .. "=",
        db = "/fixture/test_dc/account_2/tdlib",
        files = "/fixture/test_dc/account_2/tdlib_files",
        use_test_dc = true,
    },
    send = function(_, request, extra) sent[#sent + 1] = {request, extra} end,
}, {__index = client})

tg:handle_authorization({["@type"] = "authorizationStateWaitTdlibParameters"})
assert(#sent == 1 and sent[1][2] == "tdlib_params")
local parameters = sent[1][1]
assert(parameters["@type"] == "setTdlibParameters")
assert(parameters.database_encryption_key == tg.options.encryption_key)
assert(parameters.use_test_dc and parameters.database_directory == tg.options.db)
assert(parameters.parameters == nil)
tg:handle({["@type"] = "error", ["@extra"] = "tdlib_params", code = 401, message = "private fixture"})
assert(#sent == 1 and not tg.auth_error:find("private fixture", 1, true))
tg.options.encryption_key = nil
tg:send_tdlib_parameters()
tg:handle_authorization({["@type"] = "authorizationStateWaitEncryptionKey"})
assert(#sent == 1, "must never try an empty or missing key")
tg.reset_account_state = function() end
tg:handle_authorization({["@type"] = "authorizationStateClosed"})
assert(tg.closed and #sent == 1, "normal close must never request destroy")

local result = {kind = "video", file_id = 1, error = "Playback needs FFmpeg. Original file kept."}
local media = setmetatable({
    anim_out = {pop = function() local item = result; result = nil; return item end},
    videos = {[1] = {source_path = "/fixture/video.mp4", autoplay = true, decode_requested = true}},
    send = function() error("playback failure must never request a media mutation") end,
}, {__index = client})
media:poll_media_decoder()
assert(media.videos[1].source_path == "/fixture/video.mp4")
assert(media.videos[1].status == "error" and not media.videos[1].autoplay)
assert(media.action_error:find("FFmpeg", 1, true))

local first, second = os.tmpname(), os.tmpname()
local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    assert(file:write(bytes))
    assert(file:close())
end
write(first, "OLD")
write(second, "NEW")
local active = first
local original_open = io.open
love = {filesystem = {getSource = function() return "installed" end}}
io.open = function(path, mode)
    assert(path == "installed/lib/libtdjson.so", "opened a cached library")
    return original_open(active, mode)
end
local function selected_bytes()
    local file = assert(io.open(assert(native.installed("lib/libtdjson.so")), "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end
assert(selected_bytes() == "OLD")
active = second
assert(selected_bytes() == "NEW")
io.open = original_open
os.remove(first)
os.remove(second)
print("Session request, safe close, media preservation and equal-size library replacement passed")

do
    local completed, resets = 0, 0
    local account = setmetatable({
        ready = true, worker = true, options = {manual_auth = true},
        reset_account_state = function() resets = resets + 1 end,
        on_logged_out = function(confirmed) if confirmed then completed = completed + 1 end end,
        send = function(_, request, token) assert(request["@type"] == "logOut"); return token end,
    }, {__index = client})
    assert(account:log_out() and not account:log_out())
    assert(not account:shutdown() and completed == 0)
    account:handle({["@type"] = "error", ["@extra"] = "log_out", message = "Network unavailable"})
    account:handle_authorization({["@type"] = "authorizationStateClosed"})
    assert(completed == 0 and resets == 1)
    account.closed, account.ready = false, true
    assert(account:log_out())
    account:handle_authorization({["@type"] = "authorizationStateLoggingOut"})
    assert(completed == 0)
    account:handle_authorization({["@type"] = "authorizationStateClosed"})
    assert(completed == 1 and resets == 2 and not account.logout_pending)
end

local clock, requests = 0, {}
local proc = {
    ["/proc/net/route"] = "Iface Destination Gateway Flags RefCnt Use Metric Mask\n"
        .. "wlan0 00000000 0101A8C0 0003 0 0 600 00000000\n",
    ["/sys/class/net/wlan0/carrier"] = "1\n",
    ["/proc/net/ipv6_route"] = "",
}
love.system = {getOS = function() return "Linux" end}
love.timer = {getTime = function() return clock end}
io.open = function(path)
    local data = proc[path]
    if data then return {read = function() return data end, close = function() end} end
end
local conn = setmetatable({
    worker = true, history_state = {}, current_chat_id = 42, options = {sign_in_only = true},
    send = function(_, request, token) requests[#requests + 1] = request; return token end,
}, {__index = client})
local function sample(time, wall)
    clock = time
    conn:poll_network(time, wall or 100 + time)
end
sample(0)
assert(#requests == 1 and requests[1].type["@type"] == "networkTypeWiFi")
assert(conn:connection_label() == "Reconnecting…")
conn:handle({["@type"] = "updateConnectionState", state = {["@type"] = "connectionStateReady"}})
assert(conn:connection_label() == "Connected")
sample(3)
assert(#requests == 1)
proc["/sys/class/net/wlan0/carrier"] = "0"
sample(6)
assert(conn.last_network_route == false and #requests == 1)
proc["/sys/class/net/wlan0/carrier"] = "1"
sample(9)
assert(#requests == 2 and requests[2].type["@type"] == "networkTypeWiFi")
sample(12, 150)
assert(#requests == 2 and conn.network_reopen_pending)
sample(15, 153)
assert(#requests == 3 and not conn.network_reopen_pending)
proc["/proc/net/route"] = ""
proc["/proc/net/ipv6_route"] = "00000000000000000000000000000000 00 00000000000000000000000000000000"
    .. " 00 fe800000000000000000000000000001 00000400 00000001 00000000 00000003 wlan0\n"
sample(18, 156)
sample(21, 159)
assert(#requests == 4 and requests[4].type["@type"] == "networkTypeWiFi")

conn.history_state[42] = {loading = true, history_deadline = 24, direction = "older",
    request_anchor = 37, request_offset = 0}
clock = 27
conn:check_history_timeout(clock)
assert(#requests == 6 and requests[5]["@type"] == "setNetworkType"
    and requests[6]["@type"] == "getChatHistory" and requests[6].from_message_id == 37)
local history = conn.history_state[42]
assert(history.network_retry and history.loading)
clock = 42
conn:check_history_timeout(clock)
assert(#requests == 6 and not history.loading and history.error)
assert(conn:reconnect_network() and #requests == 7)
io.open = original_open
print("Wi-Fi recovery reopens TDLib after carrier loss, resume and IPv6 route changes, with one history retry")

local preferences = require("src.shared.system.media_settings")
local wifi = setmetatable({wifi_interface = "wlan0"}, {__index = client})
assert(not preferences.get("wifi_keep_awake") and wifi:wifi_power_label() == "Off")
wifi:toggle_wifi_power()
assert(preferences.get("wifi_keep_awake") and wifi.wifi_power_pending.iface == "wlan0")
wifi:toggle_wifi_power()
assert(not wifi.wifi_power_pending and wifi:wifi_power_label() == "Off")

local sent_job, worker_result
wifi.wifi_radio_available = true
wifi.wifi_power_busy, wifi.wifi_power_sequence = true, 1
wifi.wifi_power_worker = {isRunning = function() return true end}
wifi.wifi_power_in = {push = function(_, value) sent_job = value end}
wifi.wifi_power_out = {pop = function() local value = worker_result; worker_result = nil; return value end}
assert(wifi:set_wifi_radio("disable") and not wifi:set_wifi_radio("enable"))
assert(wifi:wifi_radio_label("disable") == "Working…")
wifi:schedule_wifi_power("wlan0")
wifi:poll_wifi_power()
assert(not sent_job and not wifi.wifi_power_pending)
worker_result = {sequence = 1, status = "Active"}
wifi:poll_wifi_power()
assert(sent_job.radio == "disable" and not wifi.wifi_power_status)
worker_result = {radio = "disable", ok = true, status = "Disabled"}
wifi:poll_wifi_power()
assert(wifi:wifi_radio_label("disable") == "Disabled" and wifi.wifi_interface == nil)
assert(wifi:set_wifi_radio("enable"))
wifi:poll_wifi_power()
assert(sent_job.radio == "enable")
wifi.last_network_route, wifi.network_retry_at, wifi.next_network_check = "old-route", 10, 10
worker_result = {radio = "enable", ok = true, status = "Enabled"}
wifi:poll_wifi_power()
assert(not wifi.last_network_route and not wifi.network_retry_at and not wifi.next_network_check)
assert(wifi:wifi_radio_label("enable") == "Enabled")

local jobs = {
    {iface = "wlan0", sequence = 1},
    {iface = "wlan0", sequence = 2},
    {sequence = 3},
    {iface = "wlan1", sequence = 4},
    {iface = "wlan2", sequence = 5},
    {iface = "wlan0", sequence = 6},
    {radio = "disable"},
    {radio = "enable"},
    {radio = "disable"},
    {radio = "enable"},
    {radio = "toggle"},
    {radio = "toggle"},
    {radio = "toggle"},
    {stop = true},
}
local returned, commands, job_index = {}, {}, 0
local modes = {wlan0 = "on", wlan1 = "off"}
local radio_setting
love.thread = {getChannel = function(name)
    if name == "wifi_power_in" then return {demand = function()
        job_index = job_index + 1
        if job_index == 2 then modes.wlan0 = "on" end
        if job_index == 11 then radio_setting = "1\n" end
        if job_index == 13 then radio_setting = nil end
        return jobs[job_index]
    end} end
    return {push = function(_, value) returned[#returned + 1] = value end}
end}
local original_popen, original_execute = io.popen, os.execute
io.popen = function(command)
    if command == "timeout 2 /usr/bin/batocera-settings-get wifi.enabled 2>/dev/null" then
        return {read = function() return radio_setting end, close = function() end}
    end
    local iface = command:match("iw dev (wlan%d) get power_save")
    assert(iface and command:find("timeout 2", 1, true))
    return {read = function() return modes[iface] and "Power save: " .. modes[iface] end, close = function() end}
end
os.execute = function(command)
    local action = command:match("^timeout 30 /usr/bin/batocera%-wifi (%a+) >/dev/null 2>&1$")
    if action then
        commands[#commands + 1] = action
        if job_index == 9 then return 124 * 256 end
        if job_index == 10 then radio_setting = nil; return 0 end
        radio_setting = action == "enable" and "1\n" or "0\n"
        return 0
    end
    local iface, mode = command:match("iw dev (wlan%d) set power_save (%a+)")
    assert(iface and mode and command:find("timeout 2", 1, true))
    modes[iface] = mode
    commands[#commands + 1] = iface .. " " .. mode
    return 0
end
dofile("threads/wifi_power.lua")
io.popen, os.execute = original_popen, original_execute
assert(table.concat(commands, ",") == "wlan0 off,wlan0 off,wlan0 on,wlan0 off,wlan0 on,disable,enable,disable,enable,disable,enable")
assert(returned[1].status == "Active" and returned[2].status == "Active" and returned[3].status == "Off")
assert(returned[4].status == "Active" and returned[5].status == "Driver unavailable")
assert(modes.wlan0 == "on" and modes.wlan1 == "off")
assert(returned[7].ok and returned[7].status == "Disabled")
assert(returned[8].ok and returned[8].status == "Enabled")
assert(not returned[9].ok and returned[9].status == "Timed out")
assert(not returned[10].ok and returned[10].status == "State unverified")
assert(returned[11].ok and returned[11].radio == "disable")
assert(returned[12].ok and returned[12].radio == "enable")
assert(not returned[13].ok and returned[13].status == "State unavailable")
print("Wi-Fi keep-awake is opt-in, reapplies a reset mode, and restores settings on disable and exit")
