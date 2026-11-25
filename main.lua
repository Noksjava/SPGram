local performance_trace = require("src.shared.system.performance_trace")
local intro_screen = require("src.shared.ui.startup_intro")
local startup_intro
local media_settings = require("src.shared.system.media_settings")
local ui = require("src.shared.ui.ui_kit")
local json = require("dkjson")
local telegram_config = require("src.shared.system.telegram_config")
local controller_map = require("src.shared.system.controller_map")
local telegram = require("src.shared.api.tdlib_client")
local key_store = require("src.shared.api.key_store")
local native_library = require("src.shared.api.native_library")
local sign_in_only = (love.filesystem.read("SIGN_IN_PREVIEW") or ""):match("^%s*1%s*$") ~= nil
local startup_marker = os.getenv("TELEGRAM_SP_STARTUP_OK")
local auth_screen = require("src.features.auth.ui.auth_screen")
local messenger_screen = require("src.features.chat.ui.chat_screen")
local profile_screen = require("src.features.auth.ui.profile_screen")
local settings_screen = require("src.features.auth.ui.settings_screen")
local release_screen = require("src.features.auth.ui.release_screen")
local controls_screen = require("src.features.help.ui.controls_screen")
local performance = require("src.shared.system.performance")

local tg
local current
local screens
local fonts
local settings_scale = 0.9
local settings_open = false
local settings_slide
local releases, launch_releases_open
local SETTINGS_SLIDE_TIME = 0.24
local controls_return, face_setup_return, profile_return

local handle_key

local function load_theme()
    local handle = io.open("theme.conf", "r")
    if handle then
        local name = handle:read("*l")
        handle:close()
        name = name and name:gsub("%s+$", "")
        if name and ui and ui.set_theme then ui.set_theme(name) end
    end
end
local function save_theme(name)
    local handle = io.open("theme.conf", "w")
    if handle then handle:write(name .. "\n"); handle:close() end
end

local wallpaper_enabled = false
local function load_wallpaper()
    local handle = io.open("wallpaper.conf", "r")
    if handle then
        local v = handle:read("*l")
        handle:close()
        wallpaper_enabled = (v and v:gsub("%s+$", "") == "1")
    end
end
local function save_wallpaper(v)
    local handle = io.open("wallpaper.conf", "w")
    if handle then handle:write((v and "1" or "0") .. "\n"); handle:close() end
end

local ABXY_LAYOUT = "modern"
local FACE_POSITIONS
local SELECT_BUTTON
local BUTTON_MAPPING = controller_map.defaults(ABXY_LAYOUT)
local DIRECTION_KEYS = {up = true, down = true, left = true, right = true}
local GAMEPAD_KEYS = {}

local function rebuild_gamepad_keys()
    local confirm, _, keys = controller_map.buttons(ABXY_LAYOUT, BUTTON_MAPPING)
    SELECT_BUTTON, GAMEPAD_KEYS = confirm, keys
    ui.set_controller_bindings(FACE_POSITIONS, BUTTON_MAPPING)
end
rebuild_gamepad_keys()

local function load_saved_abxy()
    local env = os.getenv("TG_ABXY")
    if env == "modern" or env == "retro" then return env end
    local ok, data = pcall(love.filesystem.read, "controls.conf")
    if ok and data then
        local saved = data:match("abxy%s*=%s*([%w_]+)")
        if saved == "modern" or saved == "retro" then return saved end
    end
    return "modern"
end

local function save_button_mapping()
    pcall(love.filesystem.write, "button-map.conf", controller_map.encode(BUTTON_MAPPING))
    rebuild_gamepad_keys()
end

local function toggle_abxy()
    ABXY_LAYOUT = ABXY_LAYOUT == "retro" and "modern" or "retro"
    BUTTON_MAPPING.confirm, BUTTON_MAPPING.back = BUTTON_MAPPING.back, BUTTON_MAPPING.confirm
    save_button_mapping()
    pcall(love.filesystem.write, "controls.conf", "abxy=" .. ABXY_LAYOUT .. "\n")
end
local function calibrate_faces(positions, confirm)
    local was_default = controller_map.same_bindings(BUTTON_MAPPING, controller_map.defaults(ABXY_LAYOUT, FACE_POSITIONS))
    FACE_POSITIONS = positions
    ABXY_LAYOUT = positions[confirm] == 3 and "retro" or "modern"
    if was_default then BUTTON_MAPPING = controller_map.defaults(ABXY_LAYOUT, positions) end
    controller_map.remap(BUTTON_MAPPING, "confirm", confirm)
    pcall(love.filesystem.write, "face-positions.conf", controller_map.encode_positions(positions))
    pcall(love.filesystem.write, "controls.conf", "abxy=" .. ABXY_LAYOUT .. "\n")
    save_button_mapping()
end

local function open_face_setup()
    if not screens or current == screens.settings then return end
    face_setup_return = current == screens.controls and controls_return or current
    controls_return = nil
    current = screens.settings
    current:enter()
    current:activate_item({id = "calibrate_faces"})
end

local dir_state = {up = false, down = false, left = false, right = false}
local gamepad_held = {}
local trigger_held = {triggerleft = false, triggerright = false}
local last_dir_source = {}
local repeat_timer = 0
local REPEAT_DELAY = 0.35
local REPEAT_RATE = 0.09

local function should_dispatch_dir(key, source)
    local now = love.timer.getTime()
    local last = last_dir_source[key]
    if last and last.source ~= source and (now - last.time) < 0.06 then
        return false
    end
    last_dir_source[key] = {source = source, time = now}
    return true
end

local function emergency_close()
    love.event.quit()
end

local function show_profile(chat_id, user_id)
    if not screens then return end
    if screens.messenger and screens.messenger.keyboard then
        screens.messenger.keyboard.visible = false
    end
    local profile = screens.profile
    profile_return = current == screens.settings and current or screens.messenger
    profile.is_me = tg.me and (user_id == tg.me.id or (chat_id ~= nil and chat_id == tg.saved_chat_id)) or false
    profile.chat_id = not profile.is_me and chat_id or nil
    profile.user_id = profile.is_me and tg.me.id or user_id
    current = profile
    profile:enter()
end

local function show_my_profile()
    if not screens then return end
    if screens.messenger and screens.messenger.keyboard then
        screens.messenger.keyboard.visible = false
    end
    local profile = screens.profile
    profile_return = current == screens.settings and current or screens.messenger
    profile.chat_id = nil
    profile.user_id = tg and tg.me and tg.me.id
    profile.is_me = true
    current = profile
    profile:enter()
end

local function load_settings()
    local path = os.getenv("TG_CONFIG")
    if not path or path == "" then
        local home = os.getenv("HOME") or ""
        path = home .. "/.config/Telegram/telegram.conf"
    end
    local config = telegram_config.read(path)
    local api_id, api_hash, config_error =
        telegram_config.for_app(config, love.filesystem.getSource() .. "/app-credentials.ini",
            os.getenv("TG_API_ID"), os.getenv("TG_API_HASH"))
    local use_test_dc = (os.getenv("TG_ENVIRONMENT") or config.environment) == "test"
    if config_error then return nil, nil, nil, use_test_dc, config_error, path end

    local proxy_type = os.getenv("TG_PROXY_TYPE") or config.proxy_type
    local proxy = nil
    if proxy_type and proxy_type ~= "" then
        local port = tonumber(os.getenv("TG_PROXY_PORT") or config.proxy_port)
        local server = os.getenv("TG_PROXY_SERVER") or config.proxy_server
        if port and server and server ~= "" then
            proxy = {
                type = proxy_type,
                server = server,
                port = port,
                username = os.getenv("TG_PROXY_USER") or config.proxy_user or "",
                password = os.getenv("TG_PROXY_PASSWORD") or config.proxy_password or "",
                secret = os.getenv("TG_PROXY_SECRET") or config.proxy_secret or "",
                path = os.getenv("TG_PROXY_PATH") or config.proxy_path or "",
            }
        end
    end

    return api_id, api_hash, proxy, use_test_dc
end

local logged_messages = {}
local logged_count = 0
local logged_max = 1000
local function app_log(kind, message)
    if not message or message == "" then return end
    local key = kind .. ":" .. tostring(message)
    if logged_messages[key] then return end
    logged_messages[key] = true
    logged_count = logged_count + 1
    if logged_count > logged_max then

        local n = 0
        for k in pairs(logged_messages) do
            logged_messages[k] = nil
            n = n + 1
            if n >= math.ceil(logged_max * 0.1) then break end
        end
        logged_count = 0
        for _ in pairs(logged_messages) do logged_count = logged_count + 1 end
        logged_messages[key] = true
        logged_count = logged_count + 1
    end
    local ok, source = pcall(love.filesystem.getSource)
    if not ok or type(source) ~= "string" then return end
    local handle = io.open(source:gsub("/+$", "") .. "/log.txt", "a")
    if not handle then return end
    handle:write(os.date("[%Y-%m-%d %H:%M:%S] "), kind, ": ", tostring(message), "\n")
    handle:close()
end

local account_store = {active_key = "account_1", accounts = {}}
local pending_account_key
local pending_logout
local account_store_filename = "accounts.json"
local last_mouse_move

local function account_key_valid(key)
    return type(key) == "string" and key:match("^account_%d+$") ~= nil
end

local function find_account(key)
    for _, account in ipairs(account_store.accounts) do
        if account.key == key then return account end
    end
end

local function save_account_store()
    local encoded = json.encode(account_store)
    if not encoded then return false end
    return love.filesystem.write(account_store_filename, encoded)
end

local function clear_account_identity(key)
    local account = find_account(key)
    if account then
        account.title = key == "account_1" and "Main account" or "Signed-out account"
        account.user_id, account.authorized = nil, false
        return save_account_store()
    end
    return true
end

local function finish_pending_logout()
    if not pending_logout then return true end
    local logout = pending_logout
    if not key_store.complete_logout(logout.key, logout.test_dc, logout.preview, true) then return false end
    pending_logout = nil
    return true
end

local function load_account_store()
    local contents = love.filesystem.read(account_store_filename)
    if contents then
        local ok, stored = pcall(json.decode, contents)
        if ok and type(stored) == "table" then
            account_store.accounts = {}
            local accounts = type(stored.accounts) == "table" and stored.accounts or {}
            for _, account in ipairs(accounts) do
                if type(account) == "table" and account_key_valid(account.key) then
                    account_store.accounts[#account_store.accounts + 1] = {
                        key = account.key,
                        title = type(account.title) == "string" and account.title or "Account",
                        user_id = tonumber(account.user_id),
                        authorized = account.authorized == true,
                    }
                end
            end
            if account_key_valid(stored.active_key) then account_store.active_key = stored.active_key end
        end
    end
    if #account_store.accounts == 0 then
        account_store.accounts[1] = {key = "account_1", title = "Main account", authorized = false}
    end
    if not find_account(account_store.active_key) then
        account_store.active_key = account_store.accounts[1].key
    end
    save_account_store()
end

local function next_account_key()
    local index = 1
    while find_account("account_" .. index) do index = index + 1 end
    local key = "account_" .. index
    account_store.accounts[#account_store.accounts + 1] = {
        key = key,
        title = "New account",
        authorized = false,
    }
    return key
end

local function start_account(key)
    key = key or account_store.active_key
    local locked, lock_error = key_store.lock()
    if not locked then tg.auth_error = lock_error; return tg end
    account_store.active_key = key
    save_account_store()
    tg = telegram.new()
    tg.sign_in_only = sign_in_only
    local library, library_error = native_library.installed("lib/libtdjson.so")
    local api_id, api_hash, proxy, use_test_dc, config_error, config_path = load_settings()
    if not api_id then
        tg.setup_error = config_error
        tg.setup_path = os.getenv("TG_CONFIG") and "telegramsp/conf/telegram.conf" or config_path
    elseif not library then
        tg.auth_error = "TDLib: " .. tostring(library_error)
    else
        local clean, resumed = key_store.complete_logout(key, use_test_dc, sign_in_only)
        if not clean then tg.auth_error = "Local sign-out cleanup could not finish. Check the SD card and retry."; return tg end
        if resumed then clear_account_identity(key) end
        local session, reason = key_store.prepare(key, use_test_dc, sign_in_only)
        if not session then tg.auth_error = reason; return tg end
        session.lib, session.api_id, session.api_hash, session.proxy = library, api_id, api_hash, proxy
        session.manual_auth = true
        session.sign_in_only = sign_in_only
        session.application_version = (love.filesystem.read("VERSION") or ""):match("^%s*(%d+%.%d+%.%d+)%s*$")
        tg:start(session)
    end
    tg.on_me = function(user)
        local account = find_account(key)
        if not account then
            account = {key = key}
            account_store.accounts[#account_store.accounts + 1] = account
        end
        local name = ((user.first_name or "") .. " " .. (user.last_name or "")):gsub("^%s+", ""):gsub("%s+$", "")
        account.title = name ~= "" and name or user.username or ("Account " .. tostring(user.id))
        account.user_id = user.id
        account.authorized = true
        save_account_store()
    end
    tg.on_logged_out = function(confirmed)
        if confirmed then
            pending_logout = {key = key, test_dc = use_test_dc, preview = sign_in_only}
            key_store.mark_logout(key, use_test_dc, sign_in_only)
            clear_account_identity(key)
            pending_account_key = key
            return
        end
        local account = find_account(key)
        if account and (account.authorized or account.user_id) then clear_account_identity(key) end
    end
    return tg
end

function love.load()
    performance_trace.start()
    love.graphics.setBackgroundColor(ui.colors.bg)
    performance.load()
    ABXY_LAYOUT = load_saved_abxy()
    local ok, data = pcall(love.filesystem.read, "face-positions.conf")
    FACE_POSITIONS = controller_map.read_positions(ok and data or nil)
    ok, data = pcall(love.filesystem.read, "button-map.conf")
    BUTTON_MAPPING = controller_map.read(ABXY_LAYOUT, ok and data or nil, FACE_POSITIONS)
    rebuild_gamepad_keys()
    ui.load_font_preference()
    fonts = ui.load_fonts(settings_scale)
    load_theme()
    load_wallpaper()
    media_settings.load()
    if love.mouse then
        if media_settings.get("show_mouse_cursor") then
            love.mouse.setVisible(true)
        else
            love.mouse.setVisible(false)
        end
        love.mouse.setRelativeMode(false)
    end
    last_mouse_move = love.timer.getTime()

    local locked, reason = key_store.lock()
    if locked then
        for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
            if name:match("^spgram%-video%-%d+%.ogv$") or name:match("^spgram%-video%-%d+%.ogv%.cancel$")
                or name:match("^spgram%-video%-%d+%.ogv%.progress$")
                or name:match("^spgram%-audio%-%d+%.ogg$") or name:match("^spgram%-audio%-%d+%.ogg%.cancel$") then
                love.filesystem.remove(name)
            elseif name:match("^anim_animation_%d+_%a+$") or name:match("^anim_sticker_%d+_%a+$") then
                for _, frame in ipairs(love.filesystem.getDirectoryItems(name)) do
                    if frame:match("^f_%d+%.png$") or frame == "tgs.gif" then
                        love.filesystem.remove(name .. "/" .. frame)
                    end
                end
                love.filesystem.remove(name)
            end
        end
        local _, _, _, use_test_dc = load_settings()
        account_store_filename = use_test_dc and "accounts-test.json" or "accounts.json"
        if sign_in_only then account_store_filename = "preview-" .. account_store_filename end
        load_account_store()
        start_account(account_store.active_key)
    else
        tg = telegram.new()
        tg.auth_error = reason
    end

    releases = release_screen.new(fonts)
    screens = {
        auth = auth_screen.new(fonts, tg, {
            open_face_setup = open_face_setup,
            accounts = function() return account_store.accounts, account_store.active_key end,
            switch_account = function(key) pending_account_key = key end,
            restart_account = function()
                if locked then pending_account_key = account_store.active_key end
            end,
        }),
        messenger = messenger_screen.new(fonts, tg),
        profile = profile_screen.new(fonts, tg),
        settings = settings_screen.new(fonts, tg, {
            releases = releases,
            accounts = function() return account_store.accounts, account_store.active_key end,
            switch_account = function(key) pending_account_key = key end,
            add_account = function() pending_account_key = next_account_key() end,
            open_profile = function() show_my_profile() end,
            abxy_layout = function() return ABXY_LAYOUT end,
            toggle_abxy = toggle_abxy,
            calibrate_faces = calibrate_faces,
            map_key = function(action, button)
                if not controller_map.remap(BUTTON_MAPPING, action, button) then return false end
                save_button_mapping()
                return true
            end,
            reset_keys = function()
                BUTTON_MAPPING = controller_map.defaults(ABXY_LAYOUT, FACE_POSITIONS)
                save_button_mapping()
            end,
            get_theme = function() return ui.current_theme end,
            get_wallpaper = function() return wallpaper_enabled and "on" or "off" end,
            toggle_wallpaper = function()
                wallpaper_enabled = not wallpaper_enabled
                save_wallpaper(wallpaper_enabled)
            end,
            cycle_theme = function()
                local order = {"dark", "light", "redwine"}
                local cur = (ui and ui.current_theme) or "dark"
                local idx = 1
                for i, n in ipairs(order) do if n == cur then idx = i; break end end
                idx = (idx % #order) + 1
                if ui and type(ui.set_theme) == "function" then
                    ui.set_theme(order[idx])
                end
                save_theme(order[idx])
            end,
            open_profile = function() show_my_profile() end,
        }),
        controls = controls_screen.new(fonts, tg),
    }
    tg.on_chat_opened = function(chat_id)
        if screens and screens.messenger then
            screens.messenger.wants_open_chat = chat_id
        end
    end
    current = screens.auth
    current:enter()
    startup_intro = intro_screen.new(fonts.subtitle, media_settings.get("startup_intro"))
    if releases and media_settings.get("check_updates_on_launch") then releases:start("check", true) end
end

local function settings_slide_progress()
    if not settings_slide then return current == screens.settings and 1 or 0 end
    local elapsed = love.timer.getTime() - settings_slide.started
    local t = math.min(1, math.max(0, elapsed / settings_slide.duration))
    local eased = 1 - (1 - t) ^ 3
    return settings_slide.start + (settings_slide.finish - settings_slide.start) * eased
end

local function slide_settings_to(target)
    local start = settings_slide_progress()
    settings_slide = nil
    if start ~= target and media_settings.get("ui_motion") then
        settings_slide = {start = start, finish = target, started = love.timer.getTime(),
            duration = SETTINGS_SLIDE_TIME * math.abs(target - start)}
    end
end

local function update_app(dt)

    if pending_account_key then
        local key = pending_account_key
        pending_account_key = nil
        local stopped, reason = tg:shutdown()
        if not stopped then
            if pending_logout then pending_account_key = key end
            tg.auth_error = reason
            return
        end
        local cleanup_failed = not finish_pending_logout()
        if cleanup_failed then pending_logout = nil end
        start_account(key)
        if cleanup_failed and (not tg.auth_error or tg.auth_error == "") then
            tg.auth_error = "Local sign-out cleanup could not finish. Check the SD card and retry."
        end
        screens.auth = auth_screen.new(fonts, tg, {
            open_face_setup = open_face_setup,
            accounts = function() return account_store.accounts, account_store.active_key end,
            switch_account = function(account) pending_account_key = account end,
            restart_account = function() pending_account_key = account_store.active_key end,
        })
        screens.messenger = messenger_screen.new(fonts, tg)
        screens.profile = profile_screen.new(fonts, tg)
        screens.settings = settings_screen.new(fonts, tg, {
            releases = releases,
            accounts = function() return account_store.accounts, account_store.active_key end,
            switch_account = function(k) pending_account_key = k end,
            add_account = function() pending_account_key = next_account_key() end,
            open_profile = function() show_my_profile() end,
            abxy_layout = function() return ABXY_LAYOUT end,
            toggle_abxy = toggle_abxy,
            calibrate_faces = calibrate_faces,
            map_key = function(action, button)
                if not controller_map.remap(BUTTON_MAPPING, action, button) then return false end
                save_button_mapping()
                return true
            end,
            reset_keys = function()
                BUTTON_MAPPING = controller_map.defaults(ABXY_LAYOUT, FACE_POSITIONS)
                save_button_mapping()
            end,
        })
        tg.on_chat_opened = function(chat_id)
            if screens and screens.messenger then
                screens.messenger.wants_open_chat = chat_id
            end
        end
        current = screens.auth
        current:enter()
    end
    if tg then
        local viewer = current == screens.messenger and screens.messenger.fullscreen_media
        tg.foreground_media = viewer and viewer.kind or nil
        tg:update(dt)
    end

    if face_setup_return and not screens.settings.face_calibration then
        current, face_setup_return = face_setup_return, nil
    end
    if tg.ready and not sign_in_only and current ~= screens.messenger and current ~= screens.profile
        and current ~= screens.settings and current ~= screens.controls then
        current = screens.messenger
        current:enter()
    elseif not tg.ready and current ~= screens.auth and current ~= screens.controls and not face_setup_return then
        current = screens.auth
        current:enter()
    end
    if tg.ready and not sign_in_only and tg.installed_sticker_sets == nil then
        tg.installed_sticker_sets = {}
        if type(tg.load_installed_sticker_sets) == "function" then
            tg:load_installed_sticker_sets()
        end
    end

    if settings_open or (current == screens.messenger and current.wants_settings) then
        slide_settings_to(1)
        current = screens.settings
        settings_open = false
        current:enter()
        screens.messenger.wants_settings = false
    end
    if settings_slide then
        if current ~= screens.settings then
            settings_slide = nil
        elseif love.timer.getTime() - settings_slide.started >= settings_slide.duration then
            if settings_slide.finish == 0 then current = screens.messenger end
            settings_slide = nil
        end
    end

    if current.update then current:update(dt) end

    if current == screens.profile then
        local profile, ms = screens.profile, screens.messenger
        local chat_id = profile.open_chat_id or (profile.pending_message and profile.pending_message.chat_id)
        if chat_id then
            profile.open_chat_id, profile.pending_message, profile_return = nil, nil, nil
            tg.profile_message_open = nil
            ms.wants_open_chat = chat_id
            current = ms
        end
    end

    if current == screens.messenger then
        local ms = screens.messenger
        if ms.wants_face_setup then
            ms.wants_face_setup = nil
            open_face_setup()
        elseif ms.wants_open_chat then
            local chat_id = ms.wants_open_chat
            ms.wants_open_chat = nil
            ms:select_chat(chat_id)
        elseif ms.wants_profile_user_id then
            local user_id = ms.wants_profile_user_id
            ms.wants_profile_user_id = nil
            show_profile(nil, user_id)
        elseif ms.wants_profile_chat_id then
            local chat_id = ms.wants_profile_chat_id
            ms.wants_profile_chat_id = nil
            show_profile(chat_id)
        elseif ms.wants_profile_self then
            ms.wants_profile_self = nil
            show_my_profile()
        end
    end

    local current_scale = ui.get_scale()
    if current_scale ~= settings_scale then
        settings_scale = current_scale
        fonts = ui.load_fonts(settings_scale)
        for _, s in pairs(screens) do
            if s.fonts then s.fonts = fonts end
        end
        if releases then releases.fonts = fonts end
    end

    if love.mouse and media_settings then
        if media_settings.get("show_mouse_cursor") then
            love.mouse.setVisible(true)
        else
            love.mouse.setVisible(false)
        end
    end

    local held_dir = nil
    for _, direction in ipairs({"up", "down", "left", "right"}) do
        if dir_state[direction] then held_dir = direction break end
    end
    if held_dir then
        repeat_timer = repeat_timer - dt
        if repeat_timer <= 0 then
            repeat_timer = REPEAT_RATE
            handle_key(held_dir, true)
        end
    else
        repeat_timer = REPEAT_DELAY
    end

    performance.limit_frame()
end

local function open_controls()
    if not screens or current == screens.controls then return end
    controls_return = current
    current = screens.controls
    current:enter()
end

local function close_controls()
    if current ~= screens.controls then return end
    current = controls_return or screens.messenger
    controls_return = nil
end

function love.update(dt)
    local started = performance_trace.clock()
    update_app(dt)
    if startup_intro and startup_intro:update(tg, sign_in_only) then startup_intro = nil end
    if releases then
        releases:poll()
        if releases.launch_offer and not startup_intro and not settings_slide
            and media_settings.get("check_updates_on_launch") then
            local chat_list = current == screens.messenger and not tg.current_chat_id
                and not current.header_focus and not current.context_menu and not current.search_active
            local sign_in = current == screens.auth and tg.auth_state == "authorizationStateWaitPhoneNumber"
                and not tg.qr_link and not tg.qr_request_pending and not tg.auth_input_pending
                and not current:keyboard_mode()
            if chat_list or sign_in then
                releases.launch_offer = false
                releases.selection = releases.available and 2 or 1
                launch_releases_open = true
            end
        end
    end
    performance_trace.update(started, dt)
end

function love.draw()
    local started = performance_trace.clock()
    if tg then tg:begin_avatar_frame() end
    if startup_intro then
        startup_intro:draw()
        performance_trace.draw(started, tg)
        return
    end
    if launch_releases_open then
        releases:draw()
    elseif settings_slide and current == screens.settings then
        local progress = settings_slide_progress()
        local width, height = ui.width(), ui.height()
        screens.messenger:draw()
        ui.rect(0, 0, width, height, {0, 0, 0, 0.28 * progress})
        if progress > 0 then
            local offset = math.floor((progress - 1) * width)
            love.graphics.push("all")
            love.graphics.translate(offset, 0)
            current:draw()
            ui.rect(width - 2, 0, 2, height, ui.colors.accent)
            love.graphics.pop()
        end
    elseif current and current.draw then
        current:draw()
    end

    if love.mouse and media_settings and media_settings.get("show_mouse_cursor") then
        local mx, my = love.mouse.getPosition()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.polygon("fill", mx, my, mx + 12, my + 4, mx + 4, my + 12)
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.polygon("line", mx, my, mx + 12, my + 4, mx + 4, my + 12)
    end
    if startup_marker and current then
        local handle = io.open(startup_marker, "wb")
        if handle then
            handle:close()
            startup_marker = nil
        end
    end
    performance_trace.draw(started, tg)
end

handle_key = function(key, from_gamepad)
    if launch_releases_open then
        if releases:keypressed(key) == "back" then launch_releases_open = false end
        return
    end
    if settings_slide and settings_slide.finish == 0 and current == screens.settings then return end
    if key == "tab" and current ~= screens.settings then
        if current == screens.messenger and current.fullscreen_media and current.fullscreen_media.kind == "audio" then
            current:close_media_viewer()
        end
        if current == screens.controls then close_controls() else open_controls() end
        return
    end
    if key == "y" and current == screens.messenger and current:allows_options() then
        current:keypressed("options")
        return
    end
    if current == screens.messenger and (current.text_preview or current.sponsor_prompt or current.sponsor_focus
        or tg.sticker_set_viewer or tg.comments_thread or (key == "escape" and (current.search_active or current.context_menu
            or current.reaction_menu or current.file_browser or current.html_preview))) then
        current:keypressed(key)
        return
    end
    if current == screens.settings and (current.release_open or current.languages_open or current.fonts_open or current.keymap_open or current.face_calibration) then
        current:keypressed(key)
        return
    end
    if key == "f1" and current == screens.messenger and current.search_active then
        if current.keyboard and current.keyboard.visible then
            current:keyboard_enter()
        else
            current:submit_search()
        end
        return
    end
    if key == "f1" and current == screens.messenger and current.keyboard
        and not current.fullscreen_media and not current.context_menu and not current.tg.sticker_set_viewer then
        if current.keyboard.visible then
            current:keyboard_enter()
        elseif tg.current_chat_id or current.edit_mode then
            if current.edit_mode or tg:chat_send_capabilities(current.model:current_chat()) then
                if not current.edit_mode then current.composer_focus = 1 end
                current.keyboard.visible = true
            end
        else
            current.header_focus = nil
            settings_open = true
        end
        return
    end
    if current == screens.controls then
        if key == "return" or key == "kpenter" then open_face_setup(); return end
        if key == "escape" then close_controls(); return end
    end
    if key == "home" or key == "m" then
        if love.window and love.window.minimize then love.window.minimize() end
        return
    end
    if key == "escape" and current == screens.auth then
        if tg.setup_error or (sign_in_only and tg.ready) or current:keyboard_mode() then
            current:keypressed(key)
            return
        end
        if from_gamepad then return end
        love.event.quit()
        return
    end
    if key == "escape" and current == screens.messenger and current.header_focus then
        current.header_focus = nil
        return
    end
    if key == "escape" and current == screens.messenger and not tg.current_chat_id then
        if from_gamepad then return end
        love.event.quit()
        return
    end
    if key == "escape" and current == screens.settings then
        if current:keypressed(key) ~= "back" then return end
        settings_open = false
        slide_settings_to(0)
        if not settings_slide then current = screens.messenger end
        return
    end

    if key == "escape" and current == screens.profile and current:keypressed(key) == "back" then
        current, profile_return = profile_return or screens.messenger, nil
        return
    elseif key == "escape" and current == screens.profile then
        return
    end

    if key == "escape" and current == screens.messenger then
        local ms = screens.messenger
        if ms.keyboard and ms.keyboard.visible then
            ms.keyboard:keypressed(key)
            return
        end
        if ms.context_menu or ms.forward_mode or ms.edit_mode or ms.fullscreen_media
            or ms.player_controls or tg.sticker_set_viewer or ms.search_active then
            ms.context_menu = nil
            ms.forward_mode = false
            ms.forward_from_chat_id = nil
            ms.edit_mode = false
            ms.edit_message = nil
            ms.edit_input = ""
            ms:close_media_viewer()
            ms.fullscreen_zoom = 1
            ms.fullscreen_pan_x = 0
            ms.fullscreen_pan_y = 0
            if ms.search_active then
                ms.search_active = false
                ms:set_search_query("", false)
            end
            if ms.keyboard then ms.keyboard.visible = false end
            return
        end
        if next(ms.selected_messages) then
            ms.selected_messages = {}
            return
        end
    end

    if key == "f1" and current == screens.messenger then
        settings_open = true
        return
    end

    if key == "p" and current == screens.messenger then
        local chat_id, _, user_id = screens.messenger:get_profile_target()
        if chat_id then
            show_profile(chat_id, user_id)
        end
        return
    end

    if (key == "v" and love.keyboard.isDown("lctrl", "rctrl")) and current.textinput then
        current:textinput(love.system.getClipboardText())
        return
    end

    if current.keypressed then current:keypressed(key) end
end

function love.keypressed(key)
    if startup_intro then return end
    if DIRECTION_KEYS[key] then
        if not should_dispatch_dir(key, "keyboard") then return end
        dir_state[key] = true
        repeat_timer = REPEAT_DELAY
    end
    handle_key(key, false)
end

function love.keyreleased(key)
    if DIRECTION_KEYS[key] then dir_state[key] = false end
    if current.keyreleased then current:keyreleased(key) end
end

function love.gamepadpressed(_, button)
    if current == screens.settings and (current.keymap_waiting or current.face_calibration) then
        current:record_gamepad_button(button)
        return
    end
    if startup_intro then return end
    gamepad_held[button] = true
    if gamepad_held[BUTTON_MAPPING.shortcuts] and gamepad_held[SELECT_BUTTON] then
        love.event.quit()
        return
    end

    if gamepad_held.leftshoulder and gamepad_held.rightshoulder and gamepad_held.start then
        emergency_close()
        return
    end

    local key = GAMEPAD_KEYS[button]
    if not key then return end
    if DIRECTION_KEYS[key] then
        if not should_dispatch_dir(key, "gamepad") then return end
        dir_state[key] = true
        repeat_timer = REPEAT_DELAY
    end
    handle_key(key, true)
end

function love.gamepadreleased(_, button)
    gamepad_held[button] = nil
    local key = GAMEPAD_KEYS[button]
    if key and DIRECTION_KEYS[key] then dir_state[key] = false end
end

function love.gamepadaxis(_, axis, value)
    if startup_intro then return end
    if axis ~= "triggerleft" and axis ~= "triggerright" then return end
    local key = axis == "triggerleft" and "l2" or "r2"
    if value > 0.5 then
        if not trigger_held[axis] then
            trigger_held[axis] = true
            handle_key(key, true)
        end
    elseif value < 0.35 then
        trigger_held[axis] = false
        if current.keyreleased then current:keyreleased(key) end
    end
end

function love.textinput(text)
    if launch_releases_open then return end
    if startup_intro then return end
    if current.textinput then current:textinput(text) end
end

function love.wheelmoved(x, y)
    if launch_releases_open then return end
    if startup_intro then return end
    if settings_slide and current == screens.settings then return end
    if current.wheelmoved then current:wheelmoved(x, y) end
end

function love.mousepressed(x, y, button)
    if launch_releases_open then return end
    if startup_intro then return end
    if settings_slide and current == screens.settings then return end
    if current.mousepressed then current:mousepressed(x, y, button) end
    if current == screens.messenger then
        local ms = screens.messenger
        if ms.wants_profile_user_id then
            local user_id = ms.wants_profile_user_id
            ms.wants_profile_user_id = nil
            show_profile(nil, user_id)
        elseif ms.wants_profile_chat_id then
            local chat_id = ms.wants_profile_chat_id
            ms.wants_profile_chat_id = nil
            show_profile(chat_id)
        elseif ms.wants_profile_self then
            ms.wants_profile_self = nil
            show_my_profile()
        end
    end
end

function love.quit()
    if startup_intro then startup_intro:close(); startup_intro = nil end
    if tg then
        local stopped = tg:shutdown()
        if not stopped then
            if releases and (launch_releases_open or (current and current.release_open)) then
                releases.status = "TDLib is still closing. Try again in a moment."
            end
            return true
        end
    end
    finish_pending_logout()
    performance_trace.stop()
    return false
end

function love.conf(t)
    t.identity = "Telegram"
    t.version = "11.5"
    t.console = false

    t.window.title = "SPgram"
    t.window.width = 640
    t.window.height = 480
    t.window.resizable = false
    t.window.fullscreen = true
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.highdpi = false

    t.modules.physics = false
    t.modules.video = false
    t.modules.audio = true
    t.modules.joystick = true
    t.modules.thread = true
    t.modules.image = true
    t.modules.font = true
end

function love.errorhandler(msg)
    msg = tostring(msg)
    app_log("fatal", "Application error")

    local error_font = love.graphics.newFont(16)
    local small_font = love.graphics.newFont(12)

    local function draw_error()
        love.graphics.setBackgroundColor(0.1, 0.1, 0.12)
        love.graphics.clear()

        local w, h = love.graphics.getDimensions()

        love.graphics.setFont(error_font)
        love.graphics.setColor(1, 0.3, 0.3, 1)
        love.graphics.printf("APPLICATION ERROR", 0, 40, w, "center")

        love.graphics.setFont(small_font)
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf(msg, 20, 100, w - 40, "left")

        love.graphics.setColor(0.6, 0.6, 0.7, 1)
        ui.button_hint("{shortcuts} + {confirm} — Exit", 20, h - 40, small_font, ui.colors.muted, w - 40)
        love.graphics.printf("Reopen SPgram from Ports", 0, h - 20, w, "center")
    end

    local held = {}

    love.graphics.reset()
    love.event.pump()

    while true do
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
            if name == "quit" or (name == "keypressed" and a == "escape") then
                return
            elseif name == "keypressed" and a == "home" then
                love.event.quit("restart")
                return
            elseif name == "gamepadpressed" then
                held[b] = true
                if held[BUTTON_MAPPING.shortcuts] and held[SELECT_BUTTON] then return end
            elseif name == "gamepadreleased" then
                held[b] = nil
            end
        end

        draw_error()
        love.graphics.present()
        love.timer.sleep(0.016)
    end
end

function love.mousemoved(x, y, dx, dy)
    last_mouse_move = love.timer.getTime()
    if love.mouse and media_settings and media_settings.get("show_mouse_cursor") then
        love.mouse.setVisible(true)
    end
end
