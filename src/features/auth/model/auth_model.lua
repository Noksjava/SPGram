
local auth_model = {}

local STATE_TEXT = {
    starting = "Starting TDLib…",
    authorizationStateWaitTdlibParameters = "Connecting to Telegram…",
    authorizationStateWaitPhoneNumber = "Choose a sign-in method",
    authorizationStateWaitCode = "Enter the Telegram code",
    authorizationStateWaitEmailAddress = "This sign-in requires email verification.",
    authorizationStateWaitEmailCode = "This sign-in requires a code from your email.",
    authorizationStateWaitOtherDeviceConfirmation = "Scan the QR code to sign in",
    authorizationStateWaitPassword = "Enter your two-step verification password",
    authorizationStateReady = "Ready",
    authorizationStateClosed = "Connection closed",
}

function auth_model.new(tg)
    local self = {}
    self.tg = tg
    self.qr_link = nil
    self.qr_image = nil
    self.qr_size = 0
    self.password_mode = false
    self.password = ""
    return setmetatable(self, {__index = auth_model})
end

function auth_model:get_status_text()
    return STATE_TEXT[self.tg.auth_state] or self.tg.auth_state or "Connecting…"
end

function auth_model:has_error()
    return self.tg.auth_error and self.tg.auth_error ~= ""
end

function auth_model:get_error()
    return self.tg.auth_error or ""
end

function auth_model:is_qr_ready()
    return self.qr_image ~= nil
end

function auth_model:is_password_mode()
    return self.tg.auth_state == "authorizationStateWaitPassword"
end

function auth_model:get_password_hint()
    return self.tg.password_hint or ""
end

return auth_model
