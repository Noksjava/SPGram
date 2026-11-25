local requests = love.thread.getChannel("wifi_power_in")
local replies = love.thread.getChannel("wifi_power_out")
local saved = {}

local function power_mode(iface)
    local pipe = io.popen("LC_ALL=C timeout 2 iw dev " .. iface .. " get power_save 2>/dev/null")
    if not pipe then return end
    local output = pipe:read(256) or ""
    pipe:close()
    local mode = output:match("Power save:%s*(%a+)")
    if mode == "on" or mode == "off" then return mode end
end

local function set_mode(iface, mode)
    local status = os.execute("timeout 2 iw dev " .. iface .. " set power_save " .. mode .. " >/dev/null 2>&1")
    return status == true or status == 0
end

local function restore(except)
    local ok = true
    for iface in pairs(saved) do
        if iface ~= except then
            if set_mode(iface, "on") then saved[iface] = nil else ok = false end
        end
    end
    return ok
end

local function configured_radio()
    local pipe = io.popen("timeout 2 /usr/bin/batocera-settings-get wifi.enabled 2>/dev/null")
    if not pipe then return end
    local value = (pipe:read(16) or ""):match("^%s*([01])%s*$")
    pipe:close()
    return value
end

local function set_radio(action)
    restore()
    local status, _, code = os.execute("timeout 30 /usr/bin/batocera-wifi " .. action .. " >/dev/null 2>&1")
    if status ~= true and status ~= 0 then
        return false, (status == 124 or status == 124 * 256 or code == 124) and "Timed out" or "Command failed"
    end
    local expected = action == "enable" and "1" or "0"
    if configured_radio() ~= expected then return false, "State unverified" end
    return true, action == "enable" and "Enabled" or "Disabled"
end

while true do
    local request = requests:demand()
    if request.stop then restore(); break end
    local iface = request.iface
    local status
    if request.radio then
        local radio = request.radio
        if radio == "toggle" then
            local configured = configured_radio()
            radio = configured == "1" and "disable" or configured == "0" and "enable" or nil
        end
        if radio == "enable" or radio == "disable" then
            local ok, outcome = set_radio(radio)
            replies:push({radio = radio, ok = ok, status = outcome})
        else
            replies:push({radio = request.radio, ok = false, status = "State unavailable"})
        end
    elseif iface and iface:match("^wl[%w_.-]*$") and #iface <= 15 then
        restore(iface)
        local mode = power_mode(iface)
        if mode == "on" and set_mode(iface, "off") then
            saved[iface] = true
            mode = power_mode(iface)
        end
        status = mode == "off" and "Active" or "Driver unavailable"
    else
        status = restore() and "Off" or "Restore failed"
    end
    if status then replies:push({sequence = request.sequence, status = status}) end
end
