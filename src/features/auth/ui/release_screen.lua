local ui = require("src.shared.ui.ui_kit")
local preferences = require("src.shared.system.media_settings")
local Release = {}
Release.__index = Release

function Release.new(fonts)
    local port = os.getenv("TELEGRAM_SP_UPDATE_PORT")
    local python = os.getenv("TELEGRAM_SP_UPDATE_PYTHON")
    if not love.thread or not love.thread.newChannel then return nil end
    local version = love.filesystem.read("VERSION") or ""
    local update_result = os.getenv("TELEGRAM_SP_UPDATE_RESULT")
    local error_status = update_result == "install-failed" and "Update could not be installed. Try downloading it again."
        or update_result == "rolled-back" and "The update failed to start. The previous version was restored."
    return setmetatable({
        fonts = fonts, port = port or "", python = python or "", version = version:match("^%s*(%d+%.%d+%.%d+)%s*$") or "0.0.0",
        directory = port and port .. "/conf/update-download/", selection = 1, channel = love.thread.newChannel(),
        supported = port ~= nil and python ~= nil,
        status = error_status or ((not port or not python) and "Updates are unavailable in this launch." or nil),
        status_tone = error_status and "error" or nil,
        launch_offer = error_status and true or false,
        update_error = error_status,
    }, Release)
end

function Release:start(operation, on_launch, target)
    if not self.supported or self.thread then return end
    self.downloading = operation == "download" or operation == "rollback-download"
    self.transfer_dir = operation == "rollback-download" and self.directory .. "rollback/" or self.directory
    if operation == "check" then
        self.available, self.verified, self.notes = false, false, nil
    elseif self.downloading then
        os.remove(self.transfer_dir .. "cancel")
        os.remove(self.transfer_dir .. "progress")
        if target then self.rollback_target, self.rollback_ready = target, nil end
    end
    self.thread = love.thread.newThread("threads/release_worker.lua")
    self.thread:start(self.python, self.port, self.version, operation, self.channel, target or "")
    self.operation, self.on_launch = operation, on_launch == true
    self.cancelled = false
    self.status_tone = nil
    self.status = self.downloading and "Downloading release…" or "Checking GitHub…"
end

function Release:poll()
    if not self.thread then return end
    local reply = self.channel:pop()
    if not reply and self.thread:isRunning() then
        if self.downloading and not self.cancelled then
            local handle = io.open(self.transfer_dir .. "progress", "rb")
            if handle then
                local percent = tonumber(handle:read(4))
                handle:close()
                if percent then self.status = "Downloading release… " .. percent .. "%" end
            end
        end
        return
    end
    reply = reply or self.channel:pop() or {failed = true}
    self.thread = nil
    if self.cancelled then
        self.status = "Download cancelled."
    elseif reply.failed or (self.downloading and not reply.verified) then
        self.status_tone = "error"
        self.status = self.downloading and "Download failed or could not be verified. Check Wi-Fi and free space."
            or "Could not check GitHub releases. Check Wi-Fi."
    elseif self.downloading and reply.verified then
        self.status_tone = "success"
        if self.operation == "rollback-download" then
            self.rollback_ready = self.rollback_target
            self.status = "v" .. self.rollback_ready .. " verified. Install when ready."
        else
            self.verified = true
            self.status = "Update verified. Install when ready."
        end
    elseif self.operation == "rollback-list" then
        self.rollback_versions = reply.versions or {}
        self.status = #self.rollback_versions > 0 and "Choose a version to download."
            or "No compatible older release was found."
    else
        self.latest, self.available, self.notes = reply.latest, reply.available, reply.notes
        self.launch_offer = self.on_launch and self.available == true
        self.status_tone = self.available and "new" or nil
        self.status = self.available and ("New release available · v" .. self.latest)
            or reply.signed_required and "This installation requires a signed release."
            or reply.installed_ahead and "This build is newer than the latest public release."
            or reply.no_release and "No public installer was found."
            or "Already up to date."
    end
end

function Release:items()
    if self.rollback_open then
        local items = {}
        for index, version in ipairs(self.rollback_versions) do
            items[index] = (version == self.rollback_ready and "Install and restart · v" or "Download v") .. version
        end
        items[#items + 1] = "Back"
        return items
    end
    return {
        "Check for updates",
        self.verified and "Install and restart" or self.available and "Download update" or "No update available",
        "Check at launch: " .. (preferences.get("check_updates_on_launch") and "On" or "Off"),
        self.supported and "Previous releases" or "Rollback unavailable",
        "Back",
    }
end

function Release:keypressed(key)
    self:poll()
    if key == "escape" or key == "b" then
        if self.thread and self.downloading then
            local handle = io.open(self.transfer_dir .. "cancel", "wb")
            if handle then
                handle:close()
                self.cancelled = true
                self.status_tone = nil
                self.status = "Cancelling…"
            end
            return
        end
        if self.rollback_open then
            if self.thread then return end
            self.rollback_open, self.selection = false, 4
            self.status, self.status_tone = self.update_status, self.update_status_tone
            return
        end
        return "back"
    end
    local last = self.rollback_open and (#self.rollback_versions + 1) or 5
    if key == "up" then self.selection = math.max(1, self.selection - 1) end
    if key == "down" then self.selection = math.min(last, self.selection + 1) end
    if key ~= "return" and key ~= "kpenter" and key ~= "a" then return end
    if self.selection == last then return self:keypressed("escape") end
    if self.rollback_open then
        if self.thread then return end
        local target = self.rollback_versions[self.selection]
        if target == self.rollback_ready then love.event.quit(43)
        elseif target then self:start("rollback-download", false, target) end
        return
    end
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
    elseif self.selection == 4 and self.supported then
        self.rollback_open, self.selection, self.rollback_versions, self.rollback_ready = true, 1, {}, nil
        self.update_status, self.update_status_tone = self.status, self.status_tone
        self:start("rollback-list")
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
    ui.text(self.rollback_open and "Previous releases" or "SPgram updates", 56, 15, fonts.subtitle, colors.text)
    ui.rect(0, 54, w, 2, colors.accent_dark)
    local version_w = math.floor((w - 88) / 2)
    local function version_panel(label, x, highlight)
        ui.retro_panel(x, 62, version_w, 32, colors.panel, highlight and colors.accent or colors.accent_dark)
        ui.text(ui.fit(label, fonts.small, version_w - 20), x + 10, 62 + (32 - fonts.small:getHeight()) / 2,
            fonts.small, highlight and colors.accent or colors.text)
    end
    version_panel("Installed v" .. self.version, 40)
    if not self.rollback_open then
        version_panel(self.latest and "Latest v" .. self.latest or "Latest —", 48 + version_w, self.status_tone == "new")
    end
    local items = self:items()
    local top = 104
    local row_h = ui.settings_row_height(fonts.normal)
    local step = row_h + 6
    local _, status_lines = fonts.small:getWrap(self.status or "", w - 104)
    local status_h = math.max(1, #status_lines) * fonts.small:getHeight() + 12
    local footer_h = 36 + (self.status and status_h + 10 or 0)
    local visible = math.min(#items, math.max(1, math.floor((h - top - footer_h) / step)))
    local first = math.max(1, self.selection - visible + 1)
    for index = first, first + visible - 1 do
        local label, value = items[index], nil
        if index == 3 and not self.rollback_open then
            label, value = "Check at launch", preferences.get("check_updates_on_launch") and "On" or "Off"
        end
        ui.settings_row(fonts.normal, top + (index - first) * step, row_h, {
            label = label, value = value, selected = index == self.selection,
            icon = UPDATE_ICONS[self.rollback_open and (index == #items and 5 or 4) or index],
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
    if not self.rollback_open and self.notes and self.notes ~= "" and below + fonts.small:getHeight() < h - 36 then
        ui.text("Release notes", 40, below, fonts.small, colors.text)
        below = below + fonts.small:getHeight() + 4
        love.graphics.setScissor(40, below, w - 80, math.max(0, h - 36 - below))
        ui.printf(self.notes, 40, below, w - 80, "left", fonts.small, colors.muted)
        love.graphics.setScissor()
    end
    ui.button_hint("{confirm} — Select   {back} — Back / Cancel download", 24, h - 29, fonts.tiny, colors.muted)
end

return Release
