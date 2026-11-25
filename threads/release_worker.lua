local python, port, version, operation, result = ...
local json = require("dkjson")
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function public_release()
    local endpoint = "https://api.github.com/repos/Noksjava/SPGram/releases/latest"
    local command = "curl -q -fsS --proto =https --connect-timeout 5 --max-time 10 --max-filesize 524288 "
        .. "-A SPgram-updater " .. endpoint .. " 2>/dev/null"
    local pipe = io.popen(command, "r")
    if not pipe then return end
    local text = pipe:read(524289)
    pipe:close()
    if not text or #text > 524288 then return end
    local release = json.decode(text)
    if type(release) ~= "table" or release.draft ~= false or release.prerelease ~= false
        or type(release.tag_name) ~= "string" or not release.tag_name:match("^[%w_.-]+$")
        or type(release.assets) ~= "table" then return end
    local latest
    for _, asset in ipairs(release.assets) do
        if type(asset) == "table" and type(asset.name) == "string" then
            local label = asset.name:match("^SPgram%-PortMaster%-v(%d+%.%d+%.%d+)%.zip$")
            if label and #label <= 26 and asset.state == "uploaded" and type(asset.size) == "number" and asset.size > 0
                and asset.browser_download_url == "https://github.com/Noksjava/SPGram/releases/download/"
                    .. release.tag_name .. "/" .. asset.name then
                if latest then return end
                latest = label
            end
        end
    end
    if not latest then return {no_release = true} end
    local difference = 0
    local installed_parts = version:gmatch("%d+")
    for part in latest:gmatch("%d+") do
        difference = tonumber(part) - tonumber(installed_parts())
        if difference ~= 0 then break end
    end
    return {latest = latest, manual_update = difference > 0, installed_ahead = difference < 0}
end

if operation == "discover" then
    result:push(public_release() or {failed = true})
    return
end
if operation ~= "check" and operation ~= "download" then return end
local command = table.concat({
    quote(python), quote(port .. "/updater.py"), "--port", quote(port),
    operation, quote(version), "2>/dev/null",
}, " ")
local pipe = io.popen(command, "r")
if pipe then
    local text = pipe:read(8192)
    pipe:close()
    local reply = text and json.decode(text)
    if type(reply) == "table" then
        if reply.no_release then reply = public_release() or reply end
        result:push(reply)
        return
    end
end
result:push({failed = true})
