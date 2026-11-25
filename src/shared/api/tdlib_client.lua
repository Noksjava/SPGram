local json = require("dkjson")
local media_settings = require("src.shared.system.media_settings")

local NOTIFICATION_SCOPES = {
    "notificationSettingsScopePrivateChats",
    "notificationSettingsScopeGroupChats",
    "notificationSettingsScopeChannelChats",
}

local function log_to_file(self, message)
    local path = self.log_path
    if not path then return end
    local handle = io.open(path, "a")
    if handle then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        handle:write(string.format("[%s] %s\n", timestamp, message))
        handle:close()
    end
end

local telegram = {}
telegram.__index = telegram
require("src.shared.api.chat_methods")(telegram)
require("src.shared.api.sponsored").install(telegram)
require("src.shared.api.message_methods")(telegram)
require("src.shared.api.comment_methods")(telegram)
require("src.shared.api.media_methods")(telegram)
require("src.shared.api.media_avatars")(telegram)
require("src.shared.api.media_playback")(telegram)
require("src.shared.api.network_recovery")(telegram)
require("src.shared.api.wifi_power")(telegram)

function telegram.new()
    local self = setmetatable({}, telegram)
    self.worker = nil
    self.in_channel = love.thread.getChannel("td_in")
    self.out_channel = love.thread.getChannel("td_out")
    self.anim_in = love.thread.getChannel("anim_in")
    self.anim_out = love.thread.getChannel("anim_out")
    self.anim_priority_in = love.thread.getChannel("anim_priority_in")
    self.anim_priority_out = love.thread.getChannel("anim_priority_out")
    self.thumbnail_in = love.thread.getChannel("thumbnail_in")
    self.thumbnail_out = love.thread.getChannel("thumbnail_out")
    self.sequence = 0

    self.auth_state = "starting"
    self.ready = false
    self.closed = false
    self.qr_link = ""
    self.qr_requested_at = 0
    self.qr_request_pending = false
    self.qr_conflict = false
    self.password_hint = ""
    self.auth_error = ""
    self.action_status = ""
    self.action_error = ""
    self.proxy_added = false
    self.proxy_ready = false
    self.proxy_flat = false
    self.tdlib_parameters_nested = true
    self.encryption_key_sent = false

    self.me, self.saved_chat_id = nil, nil
    self.my_bio, self.my_profile_save = nil, nil
    self.custom_emojis, self.custom_emoji_queue, self.custom_emoji_order, self.custom_emoji_request = {}, {}, {}, nil
    self.users = {}
    self.requested_users = {}
    self.chats = {}
    self.chats_by_id = {}
    self.chats_loaded = false
    self.archive_chats = {}
    self.archive_chats_by_id = {}
    self.archive_loaded = false
    self.archive_load_pending = false
    self.archive_load_error = nil
    self.pending_archive_changes = {}
    self.send_user_access, self.send_group_status = {}, {basicGroup = {}, supergroup = {}}
    self.scope_notification_settings = {}
    self.profile_media = {}
    self.profile_details = {}
    self.pending_chat_mute_settings = {}
    self.chat_search_generation = 0
    self.chat_search_query = ""
    self.search_chat_results = {}
    self.public_search_generation = 0
    self.public_search_query = ""
    self.public_search_results = {}
    self.public_search_result_ids = {}
    self.public_search_detail_pending_ids = {}
    self.public_search_details_pending = 0
    self.public_search_user_pending = false
    self.public_search_pending = false
    self.public_search_error = nil
    self.dialog_search_generation = {}
    self.dialog_search_query = {}
    self.dialog_search_results = {}
    self.chat_filters = {}
    self.filter_chats = {}
    self.filter_load_pending = {}
    self.messages = {}
    self.history_state = {}
    self.current_chat_id = nil
    self.viewed_message_ids = {}
    self.typing_sent_at = {}
    self.photos = {}
    self.photo_by_message, self.photo_hires_by_message = {}, {}
    self.stickers = {}
    self.sticker_by_message = {}
    self.sticker_format_by_file = {}
    self.media_preview_by_file = {}
    self.video_minithumbnails = nil
    self.sticker_set_generation = 0
    self.sticker_set_viewer = nil
    self.gif_bot_id = nil
    self.animations = {}
    self.animation_by_message = {}
    self.videos = {}
    self.video_by_message = {}
    self.voice_notes = {}
    self.voice_by_message = {}
    self.audios = {}
    self.audio_by_message = {}
    self.avatar_photos, self.avatar_pending = {}, nil
    self.notifications = {}
    self.live_message_pings = {}
    self.forward_origin_titles = {}
    self.reply_previews, self.reply_preview_order = {}, {}
    self.last_notification_sound = nil

    self.on_ready = nil
    self.proxy_wait_start = nil
    return self
end

function telegram:user_status_text(user_id)
    if not user_id then return "" end
    self:ensure_user(user_id)
    local user = self.users[user_id]
    local status = user and user.status
    local kind = status and status["@type"]
    if kind == "userStatusOnline" then
        if (tonumber(status.expires) or 0) > os.time() then return "Online" end
        return "Last seen recently"
    elseif kind == "userStatusOffline" then
        local was_online = tonumber(status.was_online) or 0
        if was_online > 0 then
            return "Last seen " .. os.date("%d.%m %H:%M", was_online)
        end
    elseif kind == "userStatusRecently" then
        return "Last seen recently"
    elseif kind == "userStatusLastWeek" then
        return "Last seen this week"
    elseif kind == "userStatusLastMonth" then
        return "Last seen this month"
    elseif kind == "userStatusEmpty" then
        return "Last seen a long time ago"
    end
    return "Status unavailable"
end

function telegram:start(options)
    self.in_channel:clear()
    self.out_channel:clear()
    self.encryption_key_sent = false
    self.closed = false
    self.ready = false
    self.auth_state = "starting"
    self.qr_link = ""
    self.qr_request_pending = false
    self.qr_requested_at = 0
    self.proxy_confirmed = false
    self.worker = love.thread.newThread("threads/tdlib_worker.lua")
    self.worker:start()
    self.in_channel:push({
        type = "init",
        lib = options.lib,
        db = options.db,
        files = options.files,
        log = options.log,
    })
    self.options = options

    if options.proxy and not self.proxy_added then
        self.proxy_added = true
        log_to_file(self, "TDLib: adding proxy...")
        self:add_proxy(options.proxy)
        log_to_file(self, "TDLib: proxy added, waiting for confirmation...")
        self.proxy_wait_start = love.timer.getTime()
    end
end

local PREVIEW_REQUESTS = {
    addProxy = true, setTdlibParameters = true, requestQrCodeAuthentication = true,
    setAuthenticationPhoneNumber = true, checkAuthenticationCode = true,
    checkAuthenticationPassword = true, close = true, logOut = true, setNetworkType = true,
}

function telegram:send(request, extra)
    if self.options and self.options.sign_in_only and not PREVIEW_REQUESTS[request["@type"]] then
        return nil
    end
    if request and request["@type"] == "downloadFile" then
        self.active_downloads = (self.active_downloads or 0) + 1
    end
    self.sequence = self.sequence + 1
    request["@extra"] = extra or ("req:" .. tostring(self.sequence))
    local encoded = json.encode(request)
    if encoded then
        self.in_channel:push({type = "send", req = encoded})
    end
    return request["@extra"]
end

function telegram:open_private_chat(user_id)
    self:send({
        ["@type"] = "createPrivateChat",
        user_id = user_id,
        force = true,
    }, "open_private_chat:" .. tostring(user_id))
end

function telegram:shutdown()
    if self.logout_pending and not self.closed then
        return false, "Telegram is still signing out."
    end
    self:save_reading_positions()
    self:stop_wifi_power()
    self:release_audio()
    self:release_video()
    if self.anim_in then
        self.anim_in:clear()
        self.anim_in:push({type = "quit"})
    end
    if self.thumbnail_worker then
        self.thumbnail_in:push({type = "quit"})
        self.thumbnail_worker:wait()
        self.thumbnail_worker = nil
        self:poll_thumbnail_worker()
    end
    if self.anim_worker then
        pcall(self.anim_worker.wait, self.anim_worker, 1)
        self.anim_worker = nil
        self:poll_media_decoder(true)
    end
    self:collect_video_source(math.huge)
    if not self.worker then
        return true
    end
    if not self.worker:isRunning() then
        self.worker = nil
        return true
    end
    if not self.closed then
        self.in_channel:push({
            type = "send",
            req = json.encode({["@type"] = "close", ["@extra"] = "close"}),
        })
        local deadline = love.timer.getTime() + 2
        while not self.closed and love.timer.getTime() < deadline do
            self:poll()
            if not self.closed then love.timer.sleep(0.01) end
        end
        if not self.closed then
            return false, "TDLib did not confirm shutdown"
        end
    end
    self.in_channel:push({type = "quit"})
    local wait_ok, wait_error = pcall(self.worker.wait, self.worker)
    if not wait_ok then
        return false, tostring(wait_error)
    end
    local running_ok, running = pcall(self.worker.isRunning, self.worker)
    if running_ok and running then
        return false, "TDLib worker is still running"
    end
    self.worker = nil
    return true
end

function telegram:reset_account_state()
    self.comments_thread = nil
    self:save_reading_positions()
    self:stop_wifi_power()
    self:release_audio()
    self.finished_audio = nil
    self.gif_bot_id = nil
    self.sent_picker_gifs = nil
    self.reading_bookmarks, self.reading_bookmark_path, self.next_reading_save = nil, nil, nil
    self.reading_positions_dirty = false
    self.channel_sponsors = nil
    self.channel_sponsor_report = nil
    self.search_sponsors = nil
    for _, media in pairs({self.voice_notes, self.audios, self.videos, self.animations, self.stickers}) do
        for _, entry in pairs(media) do
            if entry.audio_source then pcall(entry.audio_source.stop, entry.audio_source) end
        end
    end
    self.me, self.saved_chat_id = nil, nil
    self.my_bio, self.my_profile_save = nil, nil
    self.custom_emojis, self.custom_emoji_queue, self.custom_emoji_order, self.custom_emoji_request = {}, {}, {}, nil
    self.saved_chat_pending, self.saved_chat_error = nil, nil
    self.users = {}
    self.requested_users = {}
    self.chats = {}
    self.chats_by_id = {}
    self.chats_loaded = false
    self.archive_chats = {}
    self.archive_chats_by_id = {}
    self.archive_loaded = false
    self.archive_load_pending = false
    self.archive_load_error = nil
    self.pending_archive_changes = {}
    self.send_user_access, self.send_group_status = {}, {basicGroup = {}, supergroup = {}}
    self.scope_notification_settings = {}
    self.profile_media = {}
    self.profile_details = {}
    self.messages = {}
    self.history_state = {}
    self.webp_queue = nil
    self.current_chat_id = nil
    self.viewed_message_ids = {}
    self.typing_sent_at = {}
    self.photos = {}
    self.photo_by_message, self.photo_hires_by_message = {}, {}
    self.stickers = {}
    self.sticker_by_message = {}
    self.sticker_format_by_file = {}
    self.media_preview_by_file = {}
    self.video_minithumbnails = nil
    self.sticker_set_generation = 0
    self.sticker_set_viewer = nil
    self.animations = {}
    self.animation_by_message = {}
    self.videos = {}
    self.video_by_message = {}
    self.voice_notes = {}
    self.voice_by_message = {}
    self.audios = {}
    self.audio_by_message = {}
    self.avatar_photos, self.avatar_pending = {}, nil
    self.pending_chat_mute_settings = {}
    self.chat_search_generation = 0
    self.chat_search_query = ""
    self.search_chat_results = {}
    self.public_search_generation = 0
    self.public_search_query = ""
    self.public_search_results = {}
    self.public_search_result_ids = {}
    self.public_search_detail_pending_ids = {}
    self.public_search_details_pending = 0
    self.public_search_user_pending = false
    self.public_search_pending = false
    self.public_search_error = nil
    self.dialog_search_generation = {}
    self.dialog_search_query = {}
    self.dialog_search_results = {}
    self.chat_filters = {}
    self.filter_chats = {}
    self.filter_load_pending = {}
    self.encryption_key_sent = false
    self.qr_link = ""
    self.qr_request_pending = false
    self.qr_conflict = false
    self.qr_requested_at = 0
    self.password_hint = ""
    self.notifications = {}
    self.live_message_pings = {}
    self.forward_origin_titles = {}
    self.reply_previews, self.reply_preview_order = {}, {}
    self.last_notification_sound = nil
end

function telegram:log_out()
    if self.logout_pending then return false end
    if not self.worker or not self.ready then
        self.action_error = "No active Telegram session"
        return false
    end
    self.action_error = ""
    self.action_status = "Signing out…"
    self.logout_pending = true
    self.logout_confirmed = false
    log_to_file(self, "TDLib: sending logOut request")
    if not self:send({["@type"] = "logOut"}, "log_out") then
        self.logout_pending = false
        self.action_error, self.action_status = "Could not sign out.", ""
        return false
    end
    return true
end

function telegram:request_qr()
    if self.auth_input_pending then return false end
    local now = love.timer.getTime()
    if self.qr_request_pending and now - self.qr_requested_at < 30 then
        return false
    end
    self.qr_request_pending = true
    self.qr_requested_at = love.timer.getTime()
    log_to_file(self, "TDLib: sending requestQrCodeAuthentication")
    self:send({
        ["@type"] = "requestQrCodeAuthentication",
        other_user_ids = {},
    }, "qr")
    return true
end

function telegram:submit_auth_input(mode, value)
    if self.auth_input_pending then return false end
    local request
    if mode == "phone" and self.auth_state == "authorizationStateWaitPhoneNumber" then
        if not value:match("^%+[1-9]%d+$") or #value < 8 or #value > 16 then
            self.auth_error = "Enter your international phone number starting with +."
            return false
        end
        request = {["@type"] = "setAuthenticationPhoneNumber", phone_number = value}
    elseif mode == "code" and self.auth_state == "authorizationStateWaitCode" then
        if not value:match("^%d+$") or #value > 12 then
            self.auth_error = "Enter the numeric code from Telegram."
            return false
        end
        request = {["@type"] = "checkAuthenticationCode", code = value}
    else
        return false
    end
    self.auth_error = ""
    self.auth_input_pending = mode
    self:send(request, "auth_input:" .. mode)
    return true
end

function telegram:record_message_ping(chat_id, message_id, now)
    local pings = self.live_message_pings or {}
    local previous = pings[chat_id]
    if previous and previous.id == message_id then return false end
    self.live_message_pings = pings
    local count, oldest_id, oldest_time = 0, nil, now
    for id, ping in pairs(pings) do
        if now - ping.created >= 4 then
            pings[id] = nil
        else
            count = count + 1
            if not oldest_id or ping.created < oldest_time then oldest_id, oldest_time = id, ping.created end
        end
    end
    if count >= 32 and not pings[chat_id] and oldest_id then pings[oldest_id] = nil end
    pings[chat_id] = {id = message_id, created = now}
    return true
end

function telegram:push_notification(notice)
    self.notifications = self.notifications or {}
    for index = #self.notifications, 1, -1 do
        if self.notifications[index].chat_id == notice.chat_id then
            table.remove(self.notifications, index)
        end
    end
    table.insert(self.notifications, 1, notice)
    while #self.notifications > 3 do table.remove(self.notifications) end
end

function telegram:play_incoming_message_sound(now)
    if not media_settings.get("message_sound") or not love.audio then return end
    if self.last_notification_sound and now - self.last_notification_sound < 0.4 then return end
    local ok, started = pcall(function()
        if not self._notification_sound then
            self._notification_sound = love.audio.newSource("sounds/beepo/beepo.wav", "static")
        end
        self._notification_sound:stop()
        return self._notification_sound:play()
    end)
    if ok and started ~= false then self.last_notification_sound = now end
end

function telegram:store_scope_notification_settings(scope_type, settings)
    if not scope_type or not settings then return end
    self.scope_notification_settings = self.scope_notification_settings or {}
    self.scope_notification_settings[scope_type] = settings
end

function telegram:is_chat_muted(chat)
    local settings = chat and chat.notification_settings
    if not settings then return false end
    if settings.use_default_mute_for then
        local kind = chat.type or {}
        local scope = NOTIFICATION_SCOPES[1]
        if kind["@type"] == "chatTypeSupergroup" then
            scope = kind.is_channel and NOTIFICATION_SCOPES[3] or NOTIFICATION_SCOPES[2]
        elseif kind["@type"] == "chatTypeBasicGroup" then
            scope = NOTIFICATION_SCOPES[2]
        end
        settings = self.scope_notification_settings and self.scope_notification_settings[scope]
    end
    return (settings and tonumber(settings.mute_for) or 0) > 0
end

function telegram:update(dt)
    local now = love.timer.getTime()
    self:poll_video_seek(now)
    self:collect_video_source(now)
    self:poll_media_decoder()
    self:poll()
    if self.ready and not self.foreground_media then self:request_custom_emojis() end

    if self.proxy_wait_start and not self.proxy_confirmed then
        if love.timer.getTime() - self.proxy_wait_start >= 2 then

            self.proxy_confirmed = true
            self.proxy_ready = true
            self.auth_error = ""
            self.proxy_wait_start = nil
            log_to_file(self, "TDLib: proxy confirmed via fallback (2s)")
        end
    end
    if self.foreground_media ~= "video" and self.foreground_media ~= "audio" then
        self:poll_thumbnail_worker()
        self:dispatch_webp_image()
    end
    if not self.foreground_media then self:poll_avatar_images() end
    self:poll_network(now, os.time())
    self:poll_wifi_power()
    self:check_history_timeout(now)
    self:poll_video_progress(now)
    if self.ready and not self.foreground_media and not (self.options and self.options.sign_in_only)
        and now >= (self.next_photo_cleanup or 0) then
        self.next_photo_cleanup = now + 300
        self:prune_download_cache(false)
    end
    for index = #self.notifications, 1, -1 do
        local notice = self.notifications[index]
        if not notice or now - (notice.created or now) >= 6 then
            table.remove(self.notifications, index)
        end
    end
    self:poll_audio_end()
    for _, entry in pairs(self.videos) do
        if entry.playing and entry.audio_source then
            local ok, is_playing = pcall(entry.audio_source.isPlaying, entry.audio_source)
            if ok and not is_playing then
                entry.playing = false
                entry.autoplay = false
            end
        end
    end
    if self.auth_state == "authorizationStateWaitPhoneNumber" then
        local has_proxy = self.options and self.options.proxy
        if not has_proxy or self.proxy_ready then
            if self.qr_conflict and love.timer.getTime() - self.qr_requested_at >= 120 then
                self.qr_conflict = false
                self.qr_request_pending = false
            end
        end
    end
end

function telegram:poll()
    local deadline = love.timer.getTime() + (self.foreground_media and 0.002 or 0.004)
    self.defer_chat_lists = true
    for _ = 1, 200 do
        local raw = self.out_channel:pop()
        if not raw then
            break
        end
        local ok, object = pcall(json.decode, raw)
        if ok and type(object) == "table" then
            self:handle(object)
        end
        if love.timer.getTime() >= deadline then break end
    end
    self.defer_chat_lists = nil
    if not self.foreground_media then
        if self.pending_main_list then self:rebuild_chats() end
        if self.pending_archive_list then self:rebuild_archive_chats() end
        if self.pending_filter_lists then self:rebuild_filter_chats() end
    end
end

function telegram:handle(object)
    local kind = object["@type"]
    if self.options and self.options.sign_in_only and kind ~= "updateAuthorizationState"
        and kind ~= "error" and kind ~= "ok" and kind ~= "proxy"
        and kind ~= "worker_error" and kind ~= "updateConnectionState" then return end
    if kind == "worker_log" then
        log_to_file(self, "worker: " .. tostring(object.message))
        return
    end

    local extra = tostring(object["@extra"] or "")
    if extra:sub(1, 13) == "sponsor_link:"
        and self:handle_sponsor_link(kind, extra, object, love.timer.getTime()) then return end
    if self:handle_gif_picker_response(kind, extra, object) or self:handle_comments_response(kind, extra, object)
        or self:handle_reply_preview(kind, extra, object) or self:handle_my_profile(kind, extra, object)
        or self:handle_quote_history(kind, extra, object) or self:handle_emoji_response(kind, extra, object) or self:handle_chat_send_access(kind, extra, object) then return end
    local sponsor_report = tonumber(extra:match("^report_sponsor:(%d+)$"))
    if sponsor_report then
        self:receive_channel_sponsor_report(sponsor_report, object)
    elseif kind == "sponsoredChats" then
        local generation = tonumber(tostring(object["@extra"] or ""):match("^search_sponsors:(%d+)$"))
        if generation then self:receive_search_sponsors(generation, object) end
    elseif kind == "sponsoredMessages" then
        local chat_id, generation = tostring(object["@extra"] or ""):match("^channel_sponsors:(%-?%d+):(%d+)$")
        if chat_id then
            self:receive_channel_sponsors(tonumber(chat_id), tonumber(generation), object, love.timer.getTime())
        end
    elseif kind == "updateConnectionState" then
        self.connection_state = object.state and object.state["@type"]
        if self.connection_state == "connectionStateReady" then self.network_feedback_until = nil end
    elseif kind == "updateAuthorizationState" then
        self:handle_authorization(object.authorization_state or {})
    elseif kind == "updateNewChat" then
        self:handle_new_chat(object.chat)
    elseif kind == "updateChatPhoto" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then
            chat.photo = object.photo
        end
    elseif kind == "updateChatHasProtectedContent" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then chat.has_protected_content = object.has_protected_content end
    elseif kind == "updateChatChatList" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then
            chat.chat_list = object.chat_list
            self:handle_new_chat(chat, object.chat_list)
            self.pending_archive_changes[object.chat_id] = nil
            self.action_status = "Chat list refreshed"
        end
    elseif kind == "updateChatAddedToList" or kind == "updateChatRemovedFromList" then
        self:handle_chat_list_membership(object, kind == "updateChatAddedToList")
    elseif kind == "updateChatPosition" then
        self:handle_chat_position(object)
    elseif kind == "updateChatFilters" then
        self.chat_filters = object.chat_filters or object.filters or self.chat_filters or {}
        log_to_file(self, "CHAT_FILTERS update: " .. tostring(#(self.chat_filters or {})))
    elseif kind == "chatFilters" then
        self.chat_filters = object.chat_filters or object.filters or self.chat_filters or {}
        log_to_file(self, "CHAT_FILTERS loaded: " .. tostring(#(self.chat_filters or {})))
    elseif kind == "scopeNotificationSettings" then
        self:store_scope_notification_settings(extra:match("^notification_scope:(%a+)$"), object)
    elseif kind == "updateChatPermissions" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then chat.permissions = object.permissions end
    elseif kind == "updateChatBlockList" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then chat.block_list = object.block_list end
    elseif kind == "updateScopeNotificationSettings" then
        self:store_scope_notification_settings(object.scope and object.scope["@type"], object.notification_settings)
    elseif kind == "updateChatNotificationSettings" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then chat.notification_settings = object.notification_settings end
        self.pending_chat_mute_settings[object.chat_id] = nil
    elseif kind == "updateUser" and object.user then
        self:handle_user(object.user)
    elseif kind == "updateUserStatus" then
        local user = self.users[object.user_id]
        if user then user.status = object.status end
    elseif kind == "updateChatLastMessage" or kind == "updateChatDraftMessage" then
        self:handle_chat_last_message(object)
    elseif kind == "updateChatTitle" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then
            chat.title = object.title
            self:rebuild_chats()
        end
    elseif kind == "updateChatReadInbox" then
        local chat = self.chats_by_id[object.chat_id] or self.archive_chats_by_id[object.chat_id]
        if chat then
            chat.unread_count = object.unread_count or 0
            chat.last_read_inbox_message_id = object.last_read_inbox_message_id
        end
    elseif kind == "updateNewMessage" then
        self:receive_thread_message(object.message)
        self:handle_new_message(object.message)
    elseif kind == "updateMessageSendSucceeded" then
        self:update_comment_delivery(object)
        self:remember_picker_gif(object.message, object.old_message_id)
        self:handle_send_succeeded(object)
        local content = object.message and object.message.content
        if content and object.message.chat_id == self.current_chat_id then
            if content["@type"] == "messageSticker" then
                self.action_error, self.action_status = "", "Sticker sent"
            elseif content["@type"] == "messageAnimation" then
                self.action_error, self.action_status = "", "GIF sent"
            end
        end
    elseif kind == "updateMessageSendFailed" then
        self:update_comment_delivery(object)
        if self.sent_picker_gifs and object.message then
            self.sent_picker_gifs[tostring(object.message.chat_id) .. ":" .. tostring(object.old_message_id)] = nil
        end
        local content = object.message and object.message.content
        if content and (content["@type"] == "messageSticker" or content["@type"] == "messageAnimation")
            and object.message.chat_id == self.current_chat_id then
            self.action_error = object.error and object.error.message or "Could not send media."
            self.action_status = ""
        end
    elseif kind == "updateMessageContent" then
        self:update_thread_comment(object)
        self:update_reply_preview(object)
        self:handle_message_content(object)
    elseif kind == "updateMessageIsPinned" then
        for _, message in ipairs(self.messages[object.chat_id] or {}) do
            if message.id == object.message_id then
                message.is_pinned = object.is_pinned
                break
            end
        end
    elseif kind == "updateMessageInteractionInfo" then
        self:handle_message_interaction_info(object)
        self:update_comment_interactions(object)
    elseif kind == "updateFile" then
        self:handle_file(object.file)
    elseif kind == "file" then
        self:handle_file(object)
    elseif kind == "updateDeleteMessages" then
        self:update_thread_comment(object)
        self:update_reply_preview(object)
        self:handle_delete_messages(object)
    elseif kind == "proxy" then
        log_to_file(self, "handle: received proxy update, extra=" .. tostring(object["@extra"]))
        if object["@extra"] == "proxy" then
            self.proxy_ready = true
            self.proxy_confirmed = true
            self.auth_error = ""
            log_to_file(self, "TDLib: proxy ready (proxy update)")
            if self.auth_state == "authorizationStateWaitPhoneNumber" and not self.options.manual_auth then
                self:request_qr()
            end
        end
    elseif kind == "ok" then
        if object["@extra"] == "proxy" then
            self.proxy_ready = true
            self.proxy_confirmed = true
            self.auth_error = ""
            log_to_file(self, "TDLib: proxy ready (ok response)")
            if self.auth_state == "authorizationStateWaitPhoneNumber" and not self.options.manual_auth then
                self:request_qr()
            end
        elseif object["@extra"] == "loadChats" then
            self.chats_loaded = true
        elseif object["@extra"] == "loadArchiveChats" then
            self.archive_load_pending = false
            self:request_archive_chat_batch()
        elseif tostring(object["@extra"] or ""):match("^loadFilterChats:") then
            local filter_id = tonumber(tostring(object["@extra"]):match("^loadFilterChats:(%-?%d+)$"))
            if filter_id then self.filter_load_pending[filter_id] = nil end
        elseif tostring(object["@extra"] or ""):match("^archive:") then
            self.action_error = ""
            self.action_status = "Done"
            local chat_id = tonumber(tostring(object["@extra"]):match("^archive:(%-?%d+):"))
            if chat_id then self.pending_archive_changes[chat_id] = nil end
        elseif tostring(object["@extra"] or ""):match("^mute:") then
            self.action_error = ""
            self.action_status = "Notification settings updated"
            local chat_id = tostring(object["@extra"]):match("^mute:(%-?%d+):")
            if chat_id then self.pending_chat_mute_settings[tonumber(chat_id)] = nil end
        elseif object["@extra"] == "log_out" then
            if self.logout_pending then self.logout_confirmed = true end
            self.action_error = ""
            self.auth_error = ""
            self.action_status = "Waiting for sign-in…"
        end
    elseif kind == "user" then
        self:handle_user(object)
    elseif kind == "messages" then
        local extra = object["@extra"] or ""
        if extra:match("^profile_media:") then
            self:handle_profile_media(object)
        elseif extra:match("^forward:") then
            self.action_error = ""
            self.action_status = "Messages forwarded"
        elseif extra:match("^dialog_search:") then
            self:handle_dialog_search(object)
        else
            self:handle_history(object)
        end
    elseif (kind == "supergroupFullInfo" or kind == "basicGroupFullInfo") and extra:match("^profile_details:") then
        local chat_id = tonumber(extra:match("^profile_details:(%-?%d+)$"))
        if chat_id then
            self.profile_details = self.profile_details or {}
            self.profile_details[chat_id] = {description = object.description,
                member_count = object.member_count or (object.members and #object.members)}
        end
    elseif kind == "chats" then
        local extra = tostring(object["@extra"] or "")
        if extra:match("^public_search:") then
            self:handle_public_search_chats(object)
        else
            self:handle_search_chats(object)
        end
    elseif kind == "chat" then
        local extra = tostring(object["@extra"] or "")
        if extra:match("^forward_origin:") then
            if self.forward_origin_titles and self.forward_origin_titles[object.id] == false then
                self.forward_origin_titles[object.id] = object.title or false
            end
        elseif extra:match("^public_search_detail:") then
            self:handle_public_search_detail(object)
        elseif extra:match("^public_user_search:") then
            self:handle_public_user_search(object)
        elseif extra:match("^chat_search_detail:") then
            self:handle_search_chat_detail(object)
        elseif extra == "saved_messages" then
            self.saved_chat_id = object.id
            self.saved_chat_pending, self.saved_chat_error = nil, nil
            self:handle_new_chat(object)
        elseif extra:match("^open_private_chat:") then
            self:handle_new_chat(object)
            local chat_id = object and object.id
            if chat_id then
                if self.on_chat_opened then self.on_chat_opened(chat_id) end
            end
        else
            self:handle_new_chat(object)
        end
    elseif kind == "stickers" and extra:match("^recent_stickers:") then
        local pack = self.sticker_set_viewer
        if pack and pack.token == extra then
            pack.stickers, pack.loading = object.stickers or {}, false
        end
    elseif kind == "updateRecentStickers" then
        local pack = self.sticker_set_viewer
        if not object.is_attached and pack and pack.recent and not pack.loading then
            self:open_recent_stickers()
        end
    elseif kind == "stickerSet" then
        self:handle_sticker_set(object)
    elseif kind == "stickerSets" then
        local extra = tostring(object["@extra"] or "")
        if extra == "installed_sticker_sets" then
            self.installed_sticker_sets = object.sets or object.sticker_sets or {}
        end
    elseif kind == "message" then
        if extra == "send_gif" then
            self.sent_picker_gifs = self.sent_picker_gifs or {}
            self.sent_picker_gifs[tostring(object.chat_id) .. ":" .. tostring(object.id)] = true
            if not object.sending_state then self:remember_picker_gif(object, object.id) end
        end
        if tostring(object["@extra"] or ""):match("^edit:") then
            self.action_error = ""
            self.action_status = "Message edited"
        end
        self:handle_new_message(object)
    elseif kind == "error" then
        local message = tostring(object.message or "TDLib error")
        local extra = tostring(object["@extra"] or "")
        if extra:match("^auth_input:") then
            self.auth_input_pending = nil
            if object.code == 429 then
                self.auth_error = "Too many attempts. Try again later."
            elseif extra == "auth_input:phone" then
                self.auth_error = "Telegram did not accept the number. Check the number and Wi-Fi."
            else
                self.auth_error = "Telegram did not accept the code. Check the code and its expiry."
            end
            return
        end
        log_to_file(self, string.format("TDLib error: code=%s request=%s", tostring(object.code),
            extra:match("^[%w_]+") or "unknown"))
        if self:fail_avatar_download(extra) then
            self.active_downloads = math.max(0, (self.active_downloads or 0) - 1)
            return
        end
        local qr_query_in_progress = extra == "qr"
            and message:find("Another authorization query has started", 1, true) ~= nil
        if extra == "tdlib_params" then
            self.auth_error = object.code == 401
                and "TDLib rejected the database key. Restore the matching backup."
                or "TDLib initialization failed. Check your API settings and storage."
            return
        end
        if object.code == 400 and extra == "proxy"
            and not self.proxy_flat
            and message:find("Proxy type must be non-empty", 1, true) then
            self.proxy_flat = true
            log_to_file(self, "TDLib: retrying addProxy with flat schema")
            if self.options and self.options.proxy then
                self:add_proxy(self.options.proxy)
            end
            return
        end
        local history_chat_id = tonumber(extra:match("^history:(%-?%d+):%d+$"))
        if history_chat_id then
            local state = self.history_state[history_chat_id]
            if state and state.loading and state.token == extra then
                if state.jump then
                    self:fail_read_jump(state)
                elseif object.code == 400 and state.direction == "initial" and state.resume_id then
                    self:retry_history_from_read_position(history_chat_id, state)
                else
                    state.loading = false
                    state.error = "Could not load messages. Try again."
                end
            end
        elseif extra == "saved_messages" then
            self.saved_chat_pending, self.saved_chat_error = nil, true
        elseif extra:match("^audio_download:") then
            local entry = self.active_audio
            if entry and entry.download_token == extra and entry.status == "downloading" then
                entry.status, entry.audio_error = "error", "Could not download this audio."
            end
        elseif extra:match("^video_download:") then
            local entry = self.active_video
            if entry and entry.download_token == extra and entry.status == "downloading" then
                entry.status, entry.decode_error = "error", "Could not download this video."
            end
        elseif extra:match("^animation:") then
            local entry = self.animations[tonumber(extra:match(":(%d+)$"))]
            if entry and entry.download_requested == extra then
                entry.download_requested, entry.autoplay = nil, false
                entry.status = "error"
                entry.decode_error = "Could not download this GIF. Open it to retry."
            end
        elseif extra == "toggle_chat_pin" then
            self.action_error = "Could not change the pinned chat. Check Telegram’s pin limit and try again."
            self.action_status = ""
        elseif extra:match("^profile_media:") then
            local chat_id, category = extra:match("^profile_media:(%-?%d+):([%w_]+)$")
            chat_id = tonumber(chat_id)
            self.profile_media[category] = self.profile_media[category] or {}
            self.profile_media[category][chat_id] = {loading = false, messages = {}, error = message}
        elseif extra:match("^chat_search:") then
            local generation = tonumber(extra:match("^chat_search:(%d+)$"))
            if generation == self.chat_search_generation then
                self.chat_search_error = message
                self.search_chat_results = {}
            end
        elseif extra:match("^public_search_detail:") then
            local generation, chat_id = extra:match("^public_search_detail:(%d+):(%-?%d+)$")
            generation, chat_id = tonumber(generation), tonumber(chat_id)
            if generation == self.public_search_generation and self.public_search_detail_pending_ids[chat_id] then
                self.public_search_detail_pending_ids[chat_id] = nil
                self.public_search_details_pending = math.max(0, self.public_search_details_pending - 1)
                self.public_search_pending = self.public_search_details_pending > 0
            end
        elseif extra == "send_sticker" or extra == "send_gif" then
            self.action_error = message
            self.action_status = ""
        elseif extra == "installed_sticker_sets" then
            self.installed_sticker_sets = self.installed_sticker_sets or {}
        elseif extra:match("^recent_stickers:") then
            local pack = self.sticker_set_viewer
            if pack and pack.token == extra then pack.loading, pack.error = false, message end
        elseif extra:match("^sticker_set:") then
            local generation = tonumber(extra:match("^sticker_set:(%d+):"))
            if generation and generation == self.sticker_set_generation and self.sticker_set_viewer then
                self.sticker_set_viewer.loading = false
                self.sticker_set_viewer.error = message
            end
        elseif extra:match("^sticker_thumbnail:") or extra:match("^sticker:") then
            local file_id = tonumber(extra:match(":(%d+)$"))
            local entry = file_id and self.stickers[file_id]
            if entry then
                entry.status = "error"
                entry.download_requested = nil
                entry.download_error = message
            end
        elseif extra:match("^public_search:") then
            local generation = tonumber(extra:match(":(%d+)$"))
            if generation == self.public_search_generation then
                self.public_search_error = message
                self.public_search_pending = false
                self.public_search_results = {}
            end
        elseif extra:match("^public_user_search:") then
            local generation = tonumber(extra:match(":(%d+)$"))
            if generation == self.public_search_generation then
                self.public_search_user_pending = false
                if message ~= "USERNAME_NOT_OCCUPIED" and message ~= "USERNAME_INVALID" then
                    self.public_search_error = message
                end
            end
        elseif extra:match("^dialog_search:") then
            local chat_id = tonumber(extra:match("^dialog_search:(%-?%d+):"))
            if chat_id and self.dialog_search_generation[chat_id] then
                self.dialog_search_results[chat_id] = {}
                self.dialog_search_error = message
            end
        elseif extra:match("^edit:") then
            self.action_error = message
            self.action_status = ""
        elseif extra == "log_out" then
            self.logout_pending, self.logout_confirmed = false, false
            self.action_error = message
            self.action_status = ""
        elseif extra == "qr" then
            if qr_query_in_progress then
                self.qr_request_pending = true
                self.qr_requested_at = love.timer.getTime()
                self.qr_conflict = true
                self.auth_error = ""
            else
                self.qr_request_pending = false
                self.qr_conflict = false
                self.action_error = message
            end
        elseif extra:match("^archive:") then
            self.action_error = message
            self.action_status = ""
            local chat_id = tonumber(extra:match("^archive:(%-?%d+):"))
            local change = chat_id and self.pending_archive_changes[chat_id]
            if change then
                local chat = change.chat
                self.pending_archive_changes[chat_id] = nil
                self:handle_new_chat(chat, change.previous_list)
            end
        elseif extra:match("^forward:") or extra:match("^mute:") then
            self.action_error = message
            self.action_status = ""
            local chat_id = tonumber(extra:match("^mute:(%-?%d+):"))
            if chat_id then
                local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
                local previous = self.pending_chat_mute_settings[chat_id]
                if chat and previous ~= nil then
                    chat.notification_settings = previous ~= false and previous or nil
                end
                self.pending_chat_mute_settings[chat_id] = nil
            end
        end
        if object.code == 401 then
            if self.auth_state ~= "authorizationStateWaitPhoneNumber" and not self.logout_pending then
                self.auth_error = message
            end
        elseif object["@extra"] == "loadChats" then
            self.chats_loaded = true
            if object.code ~= 404 then
                self.auth_error = message
            end
        elseif object["@extra"] == "loadArchiveChats" then
            self.archive_load_pending = false
            self.archive_loaded = object.code == 404
            if object.code == 404 then
                self.archive_load_error = nil
            else
                self.archive_load_error = message
            end
        elseif tostring(object["@extra"] or ""):match("^loadFilterChats:") then
            local filter_id = tonumber(tostring(object["@extra"]):match("^loadFilterChats:(%-?%d+)$"))
            if filter_id then self.filter_load_pending[filter_id] = nil end
        elseif not qr_query_in_progress and (object["@extra"] == "me" or object["@extra"] == "qr"
            or object["@extra"] == "tdlib_params" or object["@extra"] == "password"
            or object["@extra"] == "proxy" or object["@extra"] == "encryption_key") then
            self.auth_error = message
        end
    elseif kind == "worker_error" then
        self.auth_error = tostring(object.message or "TDLib worker error")
    end
end

function telegram:handle_file(file)
    if type(file) ~= "table" then return end
    local file_id = tonumber(file.id)
    if not file_id and type(file.file) == "table" then file_id = tonumber(file.file.id) end
    if not file_id then return end
    local active_audio = self.active_audio
    local extra = tostring(file["@extra"] or "")
    if active_audio and active_audio.file_id == file_id
        and (not extra:match("^audio_download:") or extra == active_audio.download_token) then
        if file["@type"] == "file" then
            self.active_downloads = math.max(0, (self.active_downloads or 0) - 1)
        end
        return self:handle_audio_file(file, active_audio)
    end
    local active_video = self.active_video
    if active_video and active_video.file_id == file_id then
        if file["@type"] == "file" then
            self.active_downloads = math.max(0, (self.active_downloads or 0) - 1)
        end
        if not extra:match("^video_download:") or extra == active_video.download_token then
            return self:handle_video_file(file, active_video)
        end
        return
    end
    local animation = self.animations[file_id]
    if animation then
        if file["@type"] == "file" then
            self.active_downloads = math.max(0, (self.active_downloads or 0) - 1)
        end
        return self:handle_animation_file(file, animation)
    end
    local kind, entry
    if self.avatar_photos[file_id] then
        kind, entry = "avatar", self.avatar_photos[file_id]
    elseif self.photos[file_id] then
        kind, entry = "photo", self.photos[file_id]
    elseif self.stickers[file_id] then
        kind, entry = "sticker", self.stickers[file_id]
    end
    if not entry then
    if file and file["@type"] == "file" then
        self.active_downloads = math.max(0, (self.active_downloads or 0) - 1)
    end
        local file_local0 = file["local"] or {}
        if file_local0.is_downloading_completed and file_local0.path and file_local0.path ~= "" then
            local preview = self.media_preview_by_file and self.media_preview_by_file[file_id]
            log_to_file(self, string.format("THUMB DONE: id=%s kind=%s", file_id, preview and preview.kind or "?"))
            if preview then
                self.media_preview_by_file[file_id] = nil
                local storage = self[preview.storage]
                if preview.kind == "animation" then
                    self:load_animation_preview(preview.owner, file_local0.path)
                elseif storage then
                    self:load_image(preview.owner, file_local0.path, storage)
                end
            end

            if self.text_preview and self.text_preview.loading then
                local file_local0 = file["local"] or (file.file and file.file["local"]) or {}
                if file_local0.is_downloading_completed and file_local0.path and file_local0.path ~= "" then
                    local lines = {}
                    local fh = io.open(file_local0.path, "r")
                    if fh then
                        for line in fh:lines() do lines[#lines+1] = line end
                        fh:close()
                    end
                    self.text_preview.loading = false
                    self.text_preview.lines = lines
                end
            end

            if self.html_preview and self.html_preview.loading then
                local file_local0 = file["local"] or (file.file and file.file["local"]) or {}
                if file_local0.is_downloading_completed and file_local0.path and file_local0.path ~= "" then
                    local html_render = require("src.shared.api.html_render")
                    local fh = io.open(file_local0.path, "r")
                    local html = ""
                    if fh then
                        html = fh:read("*a") or ""
                        fh:close()
                    end
                    local blocks = html_render.parse(html)
                    local lines = {}
                    for _, b in ipairs(blocks) do
                        if b.type == "text" then
                            local line = ""
                            for _, r in ipairs(b.runs or {}) do line = line .. r.text end
                            lines[#lines + 1] = line
                        end
                    end
                    self.html_preview.loading = false
                    self.html_preview.blocks = blocks
                    self.html_preview.lines = lines
                    self.html_preview.images = {}
                end
            end
        end
        return
    end
    if file and file["@type"] == "file" then
        self.active_downloads = math.max(0, (self.active_downloads or 0) - 1)
    end
    local file_local = file["local"] or {}
    if file_local.is_downloading_active then
        entry.status = "downloading"
    end
    log_to_file(self, string.format("FILE: %s id=%s active=%s done=%s", kind, file_id,
        tostring(file_local.is_downloading_active), tostring(file_local.is_downloading_completed)))
    local total_bytes = tonumber(file.size)
    if not total_bytes or total_bytes <= 0 then
        total_bytes = tonumber(file.expected_size)
    end
    if total_bytes and total_bytes > 0 then
        entry.total_bytes = total_bytes
    end
    local downloaded_size = tonumber(file_local.downloaded_size) or 0
    local downloaded_prefix = tonumber(file_local.downloaded_prefix_size) or 0
    if kind == "avatar" and entry.download_deadline
        and math.max(downloaded_size, downloaded_prefix) > (entry.downloaded_bytes or 0) then
        entry.download_deadline = love.timer.getTime() + 20
    end
    entry.downloaded_bytes = math.max(downloaded_size, downloaded_prefix, entry.downloaded_bytes or 0)
    if entry.total_bytes and entry.total_bytes > 0 then
        entry.download_progress = math.min(1, entry.downloaded_bytes / entry.total_bytes)
    end
    if file_local.is_downloading_completed and file_local.path and file_local.path ~= "" then
        entry.downloaded_bytes = entry.total_bytes and entry.total_bytes > 0 and entry.total_bytes or entry.downloaded_bytes
        entry.download_progress = 1
        entry.source_path = file_local.path
        if kind == "photo" then
            self:load_photo(file_id, file_local.path)
        elseif kind == "sticker" then
            self:load_sticker(file_id, file_local.path)
        elseif kind == "avatar" then
            self:load_avatar(file_id, file_local.path)
        end
    elseif file_local.is_downloading_active then
        entry.status = "downloading"
    end
end

function telegram:open_sticker_set(message)
    local content = message and message.content
    local sticker = content and content.sticker
    local name = sticker and sticker.set_name
    if name and name ~= "" then return self:open_sticker_set_by_name(name) end
    return self:open_sticker_set_by_id(sticker and sticker.set_id)
end

function telegram:open_sticker_set_by_id(id)
    local set_id = tostring(id or "")
    if not set_id:match("^%-?%d+$") or set_id == "0" then return false end
    self.sticker_set_generation = self.sticker_set_generation + 1
    local gen = self.sticker_set_generation
    self.sticker_set_viewer = {loading = true, stickers = {}, title = "Sticker pack"}
    self:send({["@type"] = "getStickerSet", sticker_set_id = set_id},
        "sticker_set:" .. tostring(gen) .. ":" .. set_id)
    return true
end

function telegram:open_sticker_set_by_name(name)
    if not name or name == "" then
        return false
    end
    self.sticker_set_generation = self.sticker_set_generation + 1
    local gen = self.sticker_set_generation
    self.sticker_set_viewer = {loading = true, error = nil, stickers = {}, title = name}
    self:send({
        ["@type"] = "searchStickerSet",
        name = name,
    }, "sticker_set:" .. tostring(gen) .. ":name:" .. name)
    return true
end

function telegram:open_recent_stickers()
    self.sticker_set_generation = (self.sticker_set_generation or 0) + 1
    local token = "recent_stickers:" .. tostring(self.sticker_set_generation)
    self.sticker_set_viewer = {recent = true, title = "Recent stickers", loading = true, stickers = {}, token = token}
    self:send({["@type"] = "getRecentStickers", is_attached = false}, token)
end

function telegram:remember_picker_gif(message, pending_id)
    if not self.sent_picker_gifs or not message then return end
    local key = tostring(message.chat_id) .. ":" .. tostring(pending_id)
    if not self.sent_picker_gifs[key] then return end
    self.sent_picker_gifs[key] = nil
    local content = message.content
    local file = content and content.animation and content.animation.animation
    if file and file.id then
        self:send({["@type"] = "addSavedAnimation",
            animation = {["@type"] = "inputFileId", id = file.id}}, "remember_gif")
    end
end

function telegram:open_saved_gifs()
    self.sticker_set_generation = (self.sticker_set_generation or 0) + 1
    local token = "gif_saved:" .. tostring(self.sticker_set_generation)
    local parent = self.sticker_set_viewer and self.sticker_set_viewer.parent
    self.sticker_set_viewer = {gifs = true, title = "GIFs", loading = true,
        animations = {}, token = token, parent = parent}
    self:send({["@type"] = "getSavedAnimations"}, token)
end

function telegram:search_picker_gifs(query)
    local pack = self.sticker_set_viewer
    if not pack or not pack.gifs then return end
    if not query:match("%S") then self:open_saved_gifs(); return end
    self.sticker_set_generation = self.sticker_set_generation + 1
    pack.query, pack.search_query, pack.loading, pack.error = query, query, true, nil
    pack.animations, pack.focus, pack.scroll = {}, 1, 0
    pack.generation = self.sticker_set_generation
    if self.gif_bot_id then
        self:request_gif_results(pack)
    else
        pack.token = "gif_bot_option:" .. tostring(pack.generation)
        self:send({["@type"] = "getOption", name = "animation_search_bot_username"}, pack.token)
    end
end

function telegram:request_gif_results(pack)
    pack.token = "gif_results:" .. tostring(pack.generation)
    self:send({["@type"] = "getInlineQueryResults", bot_user_id = self.gif_bot_id,
        chat_id = self.current_chat_id or 0, query = pack.search_query, offset = ""}, pack.token)
end

function telegram:handle_gif_picker_response(kind, extra, object)
    if not extra:match("^gif_%a+[%a_]*:%d+$") then return false end
    local pack = self.sticker_set_viewer
    if not pack or pack.token ~= extra then return true end
    if kind == "error" then
        pack.loading, pack.error = false, object.message or "Could not load GIFs."
    elseif extra:match("^gif_saved:") and kind == "animations" then
        for _, animation in ipairs(object.animations or {}) do
            pack.animations[#pack.animations + 1] = {animation = animation}
        end
        pack.loading = false
    elseif extra:match("^gif_bot_option:") then
        local name = kind == "optionValueString" and object.value
        if not name or name == "" then
            pack.loading, pack.error = false, "Telegram GIF search is unavailable."
        else
            pack.token = "gif_bot_chat:" .. tostring(pack.generation)
            self:send({["@type"] = "searchPublicChat", username = name}, pack.token)
        end
    elseif extra:match("^gif_bot_chat:") then
        local peer = kind == "chat" and object.type
        self.gif_bot_id = peer and peer["@type"] == "chatTypePrivate" and peer.user_id or nil
        if self.gif_bot_id then
            self:request_gif_results(pack)
        else
            pack.loading, pack.error = false, "Telegram GIF search is unavailable."
        end
    elseif extra:match("^gif_results:") and kind == "inlineQueryResults" then
        local query_id = object.inline_query_id
        for _, result in ipairs(object.results or {}) do
            if query_id and result.id and result["@type"] == "inlineQueryResultAnimation"
                and result.animation and #pack.animations < 36 then
                pack.animations[#pack.animations + 1] = {
                    animation = result.animation, result_id = result.id, query_id = query_id,
                }
            end
        end
        pack.loading = false
    end
    return true
end

function telegram:load_installed_sticker_sets()
    self.installed_sticker_sets = self.installed_sticker_sets or {}
    self:send({
        ["@type"] = "getInstalledStickerSets",
        sticker_type = {["@type"] = "stickerTypeRegular"},
    }, "installed_sticker_sets")
    return true
end

function telegram:open_sticker_set_by_link(link)
    if not link or link == "" then return false end

    local name = link:match("addstickers/([^/?&#]+)") or link:match("stickers/([^/?&#]+)")
    if not name or name == "" then

        name = link:match("^([%w_]+)$")
    end
    if not name or name == "" then return false end
    name = name:gsub("[^%w_]", "")
    if name == "" then return false end
    return self:open_sticker_set_by_name(name)
end

function telegram:handle_sticker_set(object)
    local extra = tostring((object and object["@extra"]) or "")
    if extra:match("^sticker_set:") then
        local generation = tonumber(tostring(extra):match("^sticker_set:(%d+):"))
        if generation and generation == self.sticker_set_generation and self.sticker_set_viewer then
            self.sticker_set_viewer.loading = false
            self.sticker_set_viewer.error = nil
            self.sticker_set_viewer.title = object.title or self.sticker_set_viewer.title or ""
            self.sticker_set_viewer.name = object.name or self.sticker_set_viewer.name or ""
            self.sticker_set_viewer.stickers = object.stickers or self.sticker_set_viewer.stickers or {}
            self.sticker_set_viewer.focus = 1
            self.sticker_set_viewer.scroll = 0
            self.sticker_set_viewer.thumbnail = object.thumbnail or self.sticker_set_viewer.thumbnail

        end
    end
end

function telegram:load_sticker_file(file)
    if not file or not file.id then return end
    local file_id = file.id
    local fl = file["local"] or (file.file and file.file["local"]) or {}
    local entry = self.stickers[file_id]
    if not entry then
        entry = {status = "remote", format = self.sticker_format_by_file[file_id], autoplay = false}
        self.stickers[file_id] = entry
    end
    if fl.is_downloading_completed and fl.path and fl.path ~= "" then
        self:load_sticker(file_id, fl.path)
    elseif not entry.download_requested then
        entry.download_requested = true
        entry.status = "downloading"
        local extra = self:send({
            ["@type"] = "downloadFile",
            file_id = file_id,
            priority = 1,
            offset = 0,
            limit = 0,
            synchronous = false,
        }, "sticker:" .. tostring(file_id))
        if not extra then
            entry.download_requested = false
            entry.status = "remote"
        end
    end
end

function telegram:add_proxy(proxy)
    local kind = proxy.type
    local proxy_type
    if kind == "socks5" then
        proxy_type = {
            ["@type"] = "proxyTypeSocks5",
            username = proxy.username or "",
            password = proxy.password or "",
        }
    elseif kind == "http" then
        proxy_type = {
            ["@type"] = "proxyTypeHttp",
            username = proxy.username or "",
            password = proxy.password or "",
            http_only = false,
        }
    elseif kind == "mtproto" then
        proxy_type = {
            ["@type"] = "proxyTypeMtproto",
            secret = proxy.secret or "",
        }
    elseif kind == "web" then
        proxy_type = {
            ["@type"] = "proxyTypeWeb",
            path = proxy.path or "",
            secret = proxy.secret or "",
        }
    else
        self.auth_error = "Unknown proxy type: " .. tostring(kind)
        return
    end

    if self.proxy_flat then
        self:send({
            ["@type"] = "addProxy",
            server = proxy.server,
            port = proxy.port,
            type = proxy_type,
            enable = true,
        }, "proxy")
    else
        self:send({
            ["@type"] = "addProxy",
            proxy = {
                ["@type"] = "proxy",
                server = proxy.server,
                port = proxy.port,
                type = proxy_type,
            },
            enable = true,
        }, "proxy")
    end
end

function telegram:send_tdlib_parameters()
    local options = self.options or {}
    if type(options.encryption_key) ~= "string" or options.encryption_key == "" then
        self.auth_error = "A persistent database key is required."
        return
    end
    local parameters = {
        ["@type"] = "setTdlibParameters",
        use_test_dc = options.use_test_dc == true,
        database_directory = options.db,
        files_directory = options.files,
        database_encryption_key = options.encryption_key,
        use_message_database = not options.sign_in_only,
        use_file_database = not options.sign_in_only,
        use_chat_info_database = not options.sign_in_only,
        use_secret_chats = false,
        api_id = options.api_id,
        api_hash = options.api_hash,
        system_language_code = "en",
        device_model = "Handheld",
        system_version = "Linux",
        application_version = options.application_version or "development",
    }
    self:send(parameters, "tdlib_params")
end

function telegram:handle_authorization(state)
    local kind = state["@type"]
    local options = self.options or {}
    local previous_state = self.auth_state
    self.auth_state = kind
    if previous_state ~= kind then self.auth_input_pending = nil end

    if kind == "authorizationStateWaitTdlibParameters" then

        self:send_tdlib_parameters()
    elseif kind == "authorizationStateWaitEncryptionKey" then
        self.auth_error = "Unsupported TDLib database API. Install the bundled library."
    elseif kind == "authorizationStateWaitPhoneNumber" then
        log_to_file(self, string.format("TDLib: authorizationStateWaitPhoneNumber (previous=%s, logout_pending=%s)", tostring(previous_state), tostring(self.logout_pending)))

        self:reset_account_state()
        if self.on_logged_out then self.on_logged_out(false) end
        self.logout_pending, self.logout_confirmed = false, false
        self.ready = false
        self.qr_link = ""
        self.qr_conflict = false
        self.action_status = ""
        self.action_error = ""
        self.auth_error = ""

        if not options.manual_auth then self:request_qr() end

        if self.qr_conflict and love.timer.getTime() - self.qr_requested_at >= 120 then
            self.qr_conflict = false
            self.qr_request_pending = false
        end
    elseif kind == "authorizationStateWaitOtherDeviceConfirmation" then
        self.qr_request_pending = false
        self.qr_conflict = false
        self.qr_link = state.link or ""
        self.auth_error = ""
    elseif kind == "authorizationStateWaitCode" then
        self.qr_link = ""
        self.auth_error = ""
    elseif kind == "authorizationStateWaitPassword" then
        self.qr_conflict = false
        self.password_hint = state.password_hint or ""
        self.auth_error = ""
    elseif kind == "authorizationStateReady" then
        log_to_file(self, "TDLib: authorizationStateReady")
        self.qr_conflict = false
        self.ready = true
        self.qr_link = ""
        self.auth_error = ""
        self.action_status = ""
        self.action_error = ""
        if options.sign_in_only then return end
        self:send({["@type"] = "getMe"}, "me")
        for _, scope in ipairs(NOTIFICATION_SCOPES) do
            self:send({["@type"] = "getScopeNotificationSettings", scope = {["@type"] = scope}},
                "notification_scope:" .. scope)
        end
        self:prune_download_cache(true)
        self:clear_stale_audio()
        self:send({
            ["@type"] = "loadChats",
            chat_list = {["@type"] = "chatListMain"},
            limit = 15,
        }, "loadChats")
        if self.on_ready then
            self.on_ready()
        end
    elseif kind == "authorizationStateLoggingOut" then
        self.ready = false
        if self.logout_pending then self.logout_confirmed = true end
    elseif kind == "authorizationStateClosed" then
        log_to_file(self, "TDLib: authorizationStateClosed")
        self.closed = true
        self.ready = false
        local signed_out = self.logout_pending and self.logout_confirmed
        self.logout_pending, self.logout_confirmed = false, false
        self:reset_account_state()
        if signed_out and self.on_logged_out then self.on_logged_out(true) end
    else
        self.ready = false
    end
end

return telegram
