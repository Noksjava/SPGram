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
        signed = signed,
    }, Release)
end

function Release:start(operation, on_launch)
    if self.thread or (operation == "download" and not self.signed) then return end
    self.manual_help = nil
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
    self.status_tone = nil
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
        self.status_tone = "error"
        self.status = self.operation == "check" and "Could not check or verify releases. Check Wi-Fi."
            or "Download failed or could not be verified. Check Wi-Fi and free space."
    elseif self.signed and self.operation == "download" and reply.verified then
        self.verified = true
        self.status_tone = "success"
        self.status = "Verified. Select Install and quit to apply."
    else
        self.checked_at = love.timer.getTime()
        self.latest, self.available, self.manual_update, self.notes = reply.latest, self.signed and reply.available, reply.manual_update, reply.notes
        self.launch_offer = self.on_launch and (self.available == true or reply.manual_update == true)
        local newer = self.available or self.manual_update
        self.status_tone = newer and "new" or nil
        self.status = newer and ("New release available · v" .. self.latest)
            or reply.installed_ahead and "This build is newer than the latest public release."
            or reply.no_release and "No public installer was found."
            or "Already up to date."
    end
end

function Release:items()
    return {
        "Check for updates",
        self.verified and "Install and quit" or self.available and "Download update"
            or self.manual_update and "Install instructions" or "No update selected",
        "Check at launch: " .. (preferences.get("check_updates_on_launch") and "On" or "Off"),
        self.rollback and "Roll back and quit" or "Rollback unavailable",
        "Back",
    }
end

function Release:keypressed(key)
    self:poll()
    if self.manual_help then
        if key == "escape" or key == "b" or key == "return" or key == "kpenter" or key == "a" then
            self.manual_help = nil
        elseif key == "up" or key == "down" then
            self.manual_scroll = math.max(0, math.min(self.manual_scroll_max or 0,
                self.manual_scroll + (key == "up" and -24 or 24)))
        end
        return
    end
    if key == "escape" or key == "b" then
        if self.thread and self.operation == "download" then
            local handle = io.open(self.directory .. "cancel", "wb")
            if handle then
                handle:close()
                self.cancelled = true
                self.status_tone = nil
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
        elseif self.available then self:start("download")
        elseif self.manual_update then
            self.manual_help, self.manual_scroll, self.manual_scroll_max = true, 0, 0
        end
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

function Release:draw_install_help(w, h)
    local f, colors = self.fonts, ui.colors
    local x, width = 24, w - 48
    local title = ui.fit("Install SPgram v" .. self.latest, f.subtitle, width - 32)
    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    ui.pixel_icon(UPDATE_ICONS[2], 24, 17, colors.accent)
    ui.text(title, 56, 15, f.subtitle, colors.text)
    local lines = {
        "Download the installer and its .sha256 file from:",
        "github.com/Noksjava/SPGram/releases",
        "SPgram-PortMaster-v" .. self.latest .. ".zip",
        "Verify the checksum, then copy the ZIP to roms/ports/autoinstall and open PortMaster.",
    }
    local top, viewport = 69, math.max(1, h - 69 - 36)
    local rows, height = {}, 0
    for index, line in ipairs(lines) do
        local font = (index == 2 or index == 3) and f.tiny or f.small
        local _, wrapped = font:getWrap(line, width)
        rows[index] = {text = line, font = font, offset = height}
        height = height + #wrapped * font:getHeight() + 7
    end
    self.manual_scroll_max = math.max(0, height - 7 - viewport)
    self.manual_scroll = math.min(self.manual_scroll, self.manual_scroll_max)
    love.graphics.setScissor(x, top, width, viewport)
    for index, row in ipairs(rows) do
        ui.printf(row.text, x, top + row.offset - self.manual_scroll, width, "left",
            row.font, index == 2 and colors.accent or colors.text)
    end
    love.graphics.setScissor()
    local hint = self.manual_scroll_max > 0 and "↑/↓ — Scroll   {back} — Back" or "{back} — Back"
    ui.button_hint(hint, x, h - 29, f.tiny, colors.muted)
end

function Release:draw()
    self:poll()
    local fonts, colors = self.fonts, ui.colors
    local w, h = ui.width(), ui.height()
    if self.manual_help then self:draw_install_help(w, h); return end
    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    ui.pixel_icon(UPDATE_ICONS[2], 24, 17, colors.accent)
    ui.text("SPgram updates", 56, 15, fonts.subtitle, colors.text)
    ui.rect(0, 54, w, 2, colors.accent_dark)
    local version_w = math.floor((w - 88) / 2)
    local function version_panel(label, x, highlight)
        ui.retro_panel(x, 62, version_w, 32, colors.panel, highlight and colors.accent or colors.accent_dark)
        ui.text(ui.fit(label, fonts.small, version_w - 20), x + 10, 62 + (32 - fonts.small:getHeight()) / 2,
            fonts.small, highlight and colors.accent or colors.text)
    end
    version_panel("Installed v" .. self.version, 40)
    version_panel(self.latest and "Latest v" .. self.latest or "Latest —", 48 + version_w, self.status_tone == "new")
    local items = self:items()
    local top = 104
    local row_h = ui.settings_row_height(fonts.normal)
    local step = row_h + 6
    local _, status_lines = fonts.small:getWrap(self.status or "", w - 104)
    local status_h = math.max(1, #status_lines) * fonts.small:getHeight() + 12
    local footer_h = 36 + (self.status and status_h + 10 or 0)
        + (self.manual_update and fonts.small:getHeight() + 6 or 0)
    local visible = math.min(#items, math.max(1, math.floor((h - top - footer_h) / step)))
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
    if self.status then
        local marker = self.status_tone == "error" and colors.red
            or self.status_tone == "success" and colors.green
            or self.status_tone == "new" and colors.accent or colors.accent_dark
        ui.retro_panel(40, below, w - 80, status_h, colors.panel_alt, colors.header)
        ui.rect(42, below + 4, 3, status_h - 8, marker)
        ui.printf(self.status, 52, below + 6, w - 104, "left", fonts.small, colors.text)
        below = below + status_h + 6
    end
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
