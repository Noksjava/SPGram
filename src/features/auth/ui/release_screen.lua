local ui = require("src.shared.ui.ui_kit")
local preferences = require("src.shared.system.media_settings")
local Release = {}
Release.__index = Release

function Release.new(fonts)
    local port = os.getenv("TELEGRAM_SP_UPDATE_PORT")
    local python = os.getenv("TELEGRAM_SP_UPDATE_PYTHON")
    if not love.thread or not love.thread.newChannel then return nil end
    local version = love.filesystem.read("VERSION") or ""
    local signed = port and python and os.getenv("TELEGRAM_SP_SIGNED_UPDATES") == "1"
    return setmetatable({
        fonts = fonts, port = port or "", python = python or "", version = version:match("^%s*(%d+%.%d+%.%d+)%s*$") or "0.0.0",
        directory = port and port .. "/conf/update-download/", selection = 1, channel = love.thread.newChannel(),
        rollback = port and python and os.getenv("TELEGRAM_SP_CAN_ROLLBACK") == "1",
        signed = signed, status = not signed and "Install updates with the full PortMaster ZIP." or nil,
    }, Release)
end

function Release:start(operation, on_launch)
    if self.thread or (operation == "download" and not self.signed) then return end
    if operation == "check" then
        if self.checked_at and love.timer.getTime() - self.checked_at < 60 then return end
        self.available, self.verified, self.manual_update, self.notes = false, false, false, nil
    else
        os.remove(self.directory .. "cancel")
        os.remove(self.directory .. "progress")
    end
    self.thread = love.thread.newThread("threads/release_worker.lua")
    local worker_operation = not self.signed and operation == "check" and "discover" or operation
    self.thread:start(self.python, self.port, self.version, worker_operation, self.channel)
    self.operation, self.on_launch = operation, on_launch == true
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
        self.status = self.operation == "check" and "Could not check or verify releases. Check Wi-Fi."
            or "Download failed or could not be verified. Check Wi-Fi and free space."
    elseif self.signed and self.operation == "download" and reply.verified then
        self.verified = true
        self.status = "Verified. Select Install and quit to apply."
    else
        self.checked_at = love.timer.getTime()
        self.latest, self.available, self.manual_update, self.notes = reply.latest, self.signed and reply.available, reply.manual_update, reply.notes
        self.launch_offer = self.on_launch and (self.available == true or reply.manual_update == true)
        self.status = self.available and "Signed update available."
            or reply.manual_update and "A newer release is available as a full PortMaster ZIP."
            or reply.installed_ahead and "This build is newer than the latest public release."
            or reply.no_release and "No public installer was found."
            or "Already up to date."
    end
end

function Release:items()
    return {
        "Check for updates",
        self.verified and "Install and quit" or self.available and "Download update"
            or (self.manual_update or not self.signed) and "Install updates with the full ZIP" or "No update selected",
        "Check at launch: " .. (preferences.get("check_updates_on_launch") and "On" or "Off"),
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
    if key == "down" then self.selection = math.min(5, self.selection + 1) end
    if key ~= "return" and key ~= "kpenter" and key ~= "a" then return end
    if self.selection == 5 then return self:keypressed("escape") end
    if self.selection == 3 then
        if not preferences.toggle("check_updates_on_launch", true) then
            self.on_launch, self.launch_offer = false, false
        end
        return
    end
    if self.thread then return end
    if self.selection == 1 then
        self:start("check")
    elseif self.selection == 2 then
        if self.verified then love.event.quit(41)
        elseif self.available then self:start("download") end
    elseif self.selection == 4 and self.rollback then
        love.event.quit(42)
    end
end

local UPDATE_ICONS = {
    {"0011100", "0100010", "1000001", "1000001", "0100010", "0011110", "0000011"},
    {"0001000", "0001000", "0001000", "0101010", "0011100", "0001000", "0111110"},
    {"0011100", "0001000", "0111110", "1001001", "1001101", "1000001", "0111110"},
    {"0010000", "0100000", "1111100", "0100010", "0010001", "0000001", "0011110"},
    {"0010000", "0100000", "1111111", "0100001", "0010001", "0000001", "0000000"},
}

function Release:draw()
    self:poll()
    local fonts, colors = self.fonts, ui.colors
    local w, h = ui.width(), ui.height()
    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    ui.pixel_icon(UPDATE_ICONS[2], 24, 17, colors.accent)
    ui.text("SPgram updates", 56, 15, fonts.subtitle, colors.text)
    ui.text(ui.fit("Installed  " .. self.version .. "    Latest  " .. (self.latest or "—"), fonts.small, w - 80),
        40, 62, fonts.small, colors.muted)
    local items = self:items()
    local top = 88
    local row_h = ui.settings_row_height(fonts.normal)
    local step = row_h + 6
    local visible = math.min(#items, math.max(1, math.floor((h - top - 77) / step)))
    local first = math.max(1, self.selection - visible + 1)
    for index = first, first + visible - 1 do
        local label, value = items[index], nil
        if index == 3 then
            label, value = "Check at launch", preferences.get("check_updates_on_launch") and "On" or "Off"
        end
        ui.settings_row(fonts.normal, top + (index - first) * step, row_h, {
            label = label, value = value, selected = index == self.selection, icon = UPDATE_ICONS[index],
        })
    end
    local below = top + visible * step + 4
    ui.text(ui.fit(self.status or "", fonts.small, w - 80), 40, below, fonts.small, colors.text)
    below = below + fonts.small:getHeight() + 6
    if self.manual_update then
        ui.text(ui.fit("github.com/Noksjava/SPGram/releases", fonts.small, w - 80), 40, below, fonts.small, colors.muted)
        below = below + fonts.small:getHeight() + 6
    end
    if self.notes and self.notes ~= "" and below + fonts.small:getHeight() < h - 36 then
        ui.text("Release notes", 40, below, fonts.small, colors.text)
        below = below + fonts.small:getHeight() + 4
        love.graphics.setScissor(40, below, w - 80, math.max(0, h - 36 - below))
        ui.printf(self.notes, 40, below, w - 80, "left", fonts.small, colors.muted)
        love.graphics.setScissor()
    end
    ui.button_hint("{confirm} — Select   {back} — Back / Cancel download", 24, h - 29, fonts.tiny, colors.muted)
end

return Release
