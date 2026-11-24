local ui = require("src.shared.ui.ui_kit")
local Release = {}
Release.__index = Release

function Release.new(fonts)
    local port = os.getenv("TELEGRAM_SP_UPDATE_PORT")
    local python = os.getenv("TELEGRAM_SP_UPDATE_PYTHON")
    local version = love.filesystem.read("VERSION")
    if not port or not python or not version then return nil end
    local directory = port .. "/conf/update-download/"
    local signed = os.getenv("TELEGRAM_SP_SIGNED_UPDATES") == "1"
    return setmetatable({
        fonts = fonts, port = port, python = python, version = version:match("^%s*(.-)%s*$"),
        directory = directory, selection = 1, channel = love.thread.newChannel(),
        rollback = os.getenv("TELEGRAM_SP_CAN_ROLLBACK") == "1",
        signed = signed, status = not signed and "Install updates with the full PortMaster ZIP." or nil,
    }, Release)
end

function Release:start(operation)
    if self.thread or not self.signed then return end
    if operation == "check" then
        local config = io.open(self.port .. "/conf/updates.json", "rb")
        if not config then
            self.status = "Configure conf/updates.json to check for releases."
            return
        end
        config:close()
        if self.checked_at and love.timer.getTime() - self.checked_at < 60 then return end
        self.available, self.verified, self.notes = false, false, nil
    else
        os.remove(self.directory .. "cancel")
        os.remove(self.directory .. "progress")
    end
    self.thread = love.thread.newThread("threads/release_worker.lua")
    self.thread:start(self.python, self.port, self.version, operation, self.channel)
    self.operation = operation
    self.cancelled = false
    self.status = operation == "check" and "Checking GitHub…" or "Downloading update…"
end

function Release:poll()
    if not self.thread then return end
    local reply = self.channel:pop()
    if not reply and self.thread:isRunning() then
        if self.operation == "download" and not self.cancelled then
            local handle = io.open(self.directory .. "progress", "rb")
            if handle then
                local percent = tonumber(handle:read(4))
                handle:close()
                if percent then self.status = "Downloading update… " .. percent .. "%" end
            end
        end
        return
    end
    reply = reply or self.channel:pop() or {failed = true}
    self.thread = nil
    if self.cancelled then
        self.status = "Download cancelled."
    elseif reply.failed then
        self.status = "Update failed. Check Wi-Fi, configuration and free space."
    elseif reply.verified then
        self.verified = true
        self.status = "Verified. Select Install and quit to apply."
    else
        self.checked_at = love.timer.getTime()
        self.latest, self.available, self.notes = reply.latest, reply.available, reply.notes
        self.status = reply.available and "Update available." or "Already up to date."
    end
end

function Release:items()
    return {
        self.signed and "Check for updates" or "Online updates unavailable",
        self.verified and "Install and quit" or self.signed and "Download update" or "Full ZIP required",
        self.rollback and "Roll back and quit" or "Rollback unavailable",
        "Back",
    }
end

function Release:keypressed(key)
    self:poll()
    if key == "escape" or key == "b" then
        if self.thread and self.operation == "download" then
            local handle = io.open(self.directory .. "cancel", "wb")
            if handle then
                handle:close()
                self.cancelled = true
                self.status = "Cancelling…"
            end
            return
        end
        return "back"
    end
    if key == "up" then self.selection = math.max(1, self.selection - 1) end
    if key == "down" then self.selection = math.min(4, self.selection + 1) end
    if key ~= "return" and key ~= "kpenter" and key ~= "a" then return end
    if self.selection == 4 then return self:keypressed("escape") end
    if self.thread then return end
    if self.selection == 1 then
        self:start("check")
    elseif self.selection == 2 then
        if self.verified then love.event.quit(41)
        elseif self.available then self:start("download") end
    elseif self.selection == 3 and self.rollback then
        love.event.quit(42)
    end
end

function Release:draw()
    self:poll()
    local fonts, colors = self.fonts, ui.colors
    local w, h = ui.width(), ui.height()
    ui.rect(0, 0, w, h, colors.bg)
    ui.text("SPgram updates", 24, 18, fonts.subtitle, colors.text)
    ui.text("Installed  " .. self.version .. "    Latest  " .. (self.latest or "—"),
        24, 57, fonts.small, colors.muted)
    for index, label in ipairs(self:items()) do
        local y = 90 + (index - 1) * 40
        ui.rect(24, y, w - 48, 34, index == self.selection and colors.accent or colors.panel_alt, 6)
        ui.text(label, 38, y + 6, fonts.normal, index == self.selection and colors.bg or colors.text)
    end
    ui.text(ui.fit(self.status or "", fonts.small, w - 48), 24, 255, fonts.small, colors.text)
    if self.notes and self.notes ~= "" then
        ui.text("Release notes", 24, 286, fonts.small, colors.text)
        love.graphics.setScissor(24, 315, w - 48, math.max(0, h - 350))
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(colors.muted)
        love.graphics.printf(self.notes, 24, 315, w - 48)
        love.graphics.setScissor()
    end
    ui.button_hint("{confirm} — Select   {back} — Back / Cancel download", 24, h - 29, fonts.tiny, colors.muted)
end

return Release
