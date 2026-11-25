local media_settings = require("src.shared.system.media_settings")

local function file_exists(path)
    local file = io.open(path, "r")
    if not file then return false end
    file:close()
    return true
end

return function(telegram)
    function telegram:wifi_power_supported()
        return love.system and love.system.getOS and love.system.getOS() == "Linux"
    end

    function telegram:wifi_power_label()
        return self.wifi_power_status or (media_settings.get("wifi_keep_awake") and "Waiting for Wi-Fi" or "Off")
    end

    function telegram:wifi_radio_supported()
        if self.wifi_radio_available == nil then
            local firmware = (os.getenv("CFW_NAME") or ""):lower()
            self.wifi_radio_available = self:wifi_power_supported()
                and (firmware == "knulli" or file_exists("/userdata/system/knulli.conf")
                    or file_exists("/boot/knulli.board") or file_exists("/boot/boot/knulli.board"))
                and file_exists("/usr/bin/batocera-wifi") and file_exists("/usr/bin/batocera-settings-get")
        end
        return self.wifi_radio_available
    end

    function telegram:wifi_radio_label(action)
        if self.wifi_radio_action then
            return (not action or self.wifi_radio_action == action) and "Working…" or "Wait…"
        end
        if not action or self.wifi_radio_last_action == action then return self.wifi_radio_status end
    end

    function telegram:set_wifi_radio(action)
        if (action ~= "enable" and action ~= "disable" and action ~= "toggle") or not self:wifi_radio_supported()
            or self.wifi_radio_action then return false end
        self.wifi_radio_action = action
        self.wifi_radio_pending = {radio = action}
        self.wifi_power_pending = nil
        self.wifi_power_sequence = (self.wifi_power_sequence or 0) + 1
        self.wifi_power_status = nil
        return true
    end

    function telegram:schedule_wifi_power(iface)
        if not self:wifi_power_supported() or self.wifi_radio_action then return end
        if not iface and not self.wifi_power_worker then
            self.wifi_power_pending = nil
            self.wifi_power_status = "Off"
            return
        end
        self.wifi_power_sequence = (self.wifi_power_sequence or 0) + 1
        self.wifi_power_pending = {iface = iface, sequence = self.wifi_power_sequence}
        self.wifi_power_status = "Applying…"
        if iface then self.wifi_power_recheck_at = love.timer.getTime() + 90 end
    end

    function telegram:toggle_wifi_power()
        if not self:wifi_power_supported() then return end
        if media_settings.toggle("wifi_keep_awake") then
            self.wifi_power_status = "Waiting for Wi-Fi"
            self.next_network_check = nil
            if self.wifi_interface then self:schedule_wifi_power(self.wifi_interface) end
        else
            self:schedule_wifi_power(nil)
        end
    end

    function telegram:poll_wifi_power()
        if self.wifi_power_worker then
            local result = self.wifi_power_out:pop()
            if result then
                self.wifi_power_busy = false
                if result.radio then
                    self.wifi_radio_last_action, self.wifi_radio_status = result.radio, result.status
                    self.wifi_radio_action = nil
                    self.next_network_check, self.last_network_route, self.wifi_interface = nil, nil, nil
                    if result.ok and result.radio == "enable" then self.network_retry_at = nil end
                elseif result.sequence == self.wifi_power_sequence then
                    self.wifi_power_status = result.status
                end
            elseif not self.wifi_power_worker:isRunning() then
                self.wifi_power_worker, self.wifi_power_busy = nil, false
                self.wifi_power_status = "Driver unavailable"
                if self.wifi_radio_action and not self.wifi_radio_pending then
                    self.wifi_radio_last_action, self.wifi_radio_status = self.wifi_radio_action, "Unavailable"
                    self.wifi_radio_action = nil
                end
            end
        end
        local pending = self.wifi_radio_pending or self.wifi_power_pending
        if self.wifi_power_busy or not pending then return end
        if not self.wifi_power_worker then
            self.wifi_power_in = love.thread.getChannel("wifi_power_in")
            self.wifi_power_out = love.thread.getChannel("wifi_power_out")
            self.wifi_power_in:clear()
            self.wifi_power_out:clear()
            self.wifi_power_worker = love.thread.newThread("threads/wifi_power.lua")
            self.wifi_power_worker:start()
        end
        self.wifi_power_in:push(pending)
        self.wifi_radio_pending, self.wifi_power_pending, self.wifi_power_busy = nil, nil, true
    end

    function telegram:stop_wifi_power()
        if self.wifi_power_worker then
            self.wifi_power_in:push({stop = true})
            self.wifi_power_worker:wait()
            self.wifi_power_worker = nil
        end
        self.wifi_power_pending, self.wifi_power_busy = nil, false
        self.wifi_power_status, self.wifi_interface = nil, nil
        self.wifi_radio_pending, self.wifi_radio_action = nil, nil
        self.wifi_radio_last_action, self.wifi_radio_status = nil, nil
    end
end
