local python, port, version, operation, result = ...
local json = require("dkjson")
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
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
        result:push(reply)
        return
    end
end
result:push({failed = true})
