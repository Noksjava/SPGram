local media_settings = require("src.shared.system.media_settings")

local labels = {
    connectionStateWaitingForNetwork = "Waiting for network",
    connectionStateConnectingToProxy = "Connecting to proxy",
    connectionStateConnecting = "Connecting",
    connectionStateUpdating = "Syncing",
    connectionStateReady = "Connected",
}

local function read_proc(path)
    local file = io.open(path, "r")
    if not file then return end
    local text = file:read(8192)
    file:close()
    return text or ""
end

local function default_route(text, ipv6)
    local best, device, gateway
    for line in (text or ""):gmatch("[^\n]+") do
        local iface, dest, via, flags, metric
        if ipv6 then
            local prefix, source, source_prefix
            dest, prefix, source, source_prefix, via, metric, flags, iface =
                line:match("^%s*(%x+)%s+(%x+)%s+(%x+)%s+(%x+)%s+(%x+)%s+(%x+)%s+%x+%s+%x+%s+(%x+)%s+(%S+)")
            if prefix ~= "00" or source_prefix ~= "00" then dest = nil end
            if source and not source:match("^0+$") then dest = nil end
        else
            local mask
            iface, dest, via, flags, metric, mask =
                line:match("^%s*(%S+)%s+(%x+)%s+(%x+)%s+(%x+)%s+%d+%s+%d+%s+(%d+)%s+(%x+)")
            if mask and not mask:match("^0+$") then dest = nil end
        end
        local bits = flags and tonumber(flags, 16)
        local cost = metric and tonumber(metric, ipv6 and 16 or 10)
        if iface and iface ~= "lo" and dest and dest:match("^0+$") and bits and bits % 2 == 1 and bits % 1024 < 512
            and cost and (not best or cost < best) then
            best, device, gateway = cost, iface, via
        end
    end
    return device, gateway
end

return function(telegram)
    function telegram:network_route()
        if not (love.system and love.system.getOS and love.system.getOS() == "Linux") then return end
        local ipv4 = read_proc("/proc/net/route")
        local iface, gateway = default_route(ipv4, false)
        if not iface then
            local ipv6 = read_proc("/proc/net/ipv6_route")
            iface, gateway = default_route(ipv6, true)
            if not iface then
                if ipv4 or ipv6 then return false end
                return
            end
        end
        local wireless = iface:match("^wl[%w_.-]*$")
        local carrier = wireless and read_proc("/sys/class/net/" .. iface .. "/carrier")
        if carrier and carrier:match("^%s*0%s*$") then return false, nil, iface end
        return iface .. ":" .. gateway, wireless and "networkTypeWiFi" or "networkTypeOther", wireless and iface or nil
    end

    function telegram:connection_label()
        if self.network_feedback_until and love.timer.getTime() < self.network_feedback_until then
            return "Reconnecting…"
        end
        return labels[self.connection_state] or "Checking connection"
    end

    function telegram:reconnect_network(now)
        if not self.worker or self.closed then return false end
        now = now or love.timer.getTime()
        if self.network_retry_at and now < self.network_retry_at then return false end
        local request = self:send({["@type"] = "setNetworkType",
            type = {["@type"] = self.network_type or "networkTypeOther"}}, "network_reconnect")
        if not request then return false end
        self.network_retry_at = now + 5
        self.network_feedback_until = now + 2
        local chat_id = self.current_chat_id
        local state = chat_id and self.history_state[chat_id]
        if state and state.retry_on_reconnect and not state.loading then
            state.retry_on_reconnect = nil
            self:request_history(chat_id, state.direction, state.request_anchor, state.request_offset)
            state.network_retry = true
        end
        return true
    end

    function telegram:poll_network(now, wall)
        if not self.worker or self.closed or now < (self.next_network_check or 0) then return end
        self.next_network_check = now + 3
        local resumed = self.network_checked_wall and wall - self.network_checked_wall >= 9
        self.network_checked_wall = wall
        local route, kind, iface = self:network_route()
        local previous = self.wifi_interface
        self.wifi_interface = iface or (route == false and previous or nil)
        local changed = route ~= self.last_network_route
        local power_recheck = self.wifi_power_status == "Active" and now >= (self.wifi_power_recheck_at or 0)
        if media_settings.get("wifi_keep_awake") and self.wifi_interface
            and (self.wifi_interface ~= previous or resumed or (changed and route) or power_recheck) then
            self:schedule_wifi_power(self.wifi_interface)
        end
        if changed or resumed then
            self.last_network_route, self.network_type = route, kind
            self.network_reopen_pending = route and true or (route == nil and resumed)
        end
        if self.network_reopen_pending and self:reconnect_network(now) then self.network_reopen_pending = nil end
    end
end
