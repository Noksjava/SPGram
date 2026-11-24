local ui = require("src.shared.ui.ui_kit")

local intro = {}
intro.__index = intro

local interactive = {
    authorizationStateWaitPhoneNumber = true,
    authorizationStateWaitOtherDeviceConfirmation = true,
    authorizationStateWaitCode = true,
    authorizationStateWaitPassword = true,
    authorizationStateWaitEmailAddress = true,
    authorizationStateWaitEmailCode = true,
    authorizationStateWaitRegistration = true,
}

function intro.new(font, enabled)
    local video
    if enabled ~= false then
        local ok, opened = pcall(love.graphics.newVideo, "intro/spgram-intro.ogv", {dpiscale = 1})
        if not ok then
            ok, opened = pcall(love.graphics.newVideo, "intro/spgram-intro.ogv", {audio = false, dpiscale = 1})
        end
        if ok and opened then
            local audio = opened:getSource()
            if audio then audio:setVolume(0.25) end
            if pcall(opened.play, opened) then video = opened else opened:release() end
        end
    end
    return setmetatable({video = video, font = font, started = love.timer.getTime()}, intro)
end

function intro:close()
    if self.video then
        self.video:pause()
        self.video:release()
        self.video = nil
    end
end

function intro:update(tg, sign_in_only)
    local elapsed = love.timer.getTime() - self.started
    local ready = tg.setup_error or (tg.auth_error and tg.auth_error ~= "") or interactive[tg.auth_state]
        or (tg.ready and (sign_in_only or tg.chats_loaded))
    if self.video then
        if elapsed < 8 and (not self.presented or self.video:isPlaying()) then return false end
        self:close()
    end
    return elapsed >= 8 or not not ready
end

function intro:draw()
    self.presented = true
    local width, height = ui.width(), ui.height()
    local video = self.video
    if video then
        local w, h = video:getDimensions()
        local scale = math.min(width / w, height / h)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(video, (width - w * scale) / 2, (height - h * scale) / 2, 0, scale, scale)
    else
        love.graphics.clear(ui.colors.bg)
        local text = "Starting SPgram…"
        ui.text(text, (width - self.font:getWidth(text)) / 2,
            (height - self.font:getHeight()) / 2, self.font, ui.colors.text)
    end
end

return intro
