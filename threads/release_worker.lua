local python, port, version, operation, result, target = ...
local json = require("dkjson")
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

if operation ~= "check" and operation ~= "download"
    and operation ~= "rollback-list" and operation ~= "rollback-download" then return end
local argument = operation == "rollback-download" and quote(target) or ""
local command = table.concat({
    quote(python), quote(port .. "/updater.py"), "--port", quote(port),
    operation, quote(version), argument, "2>/dev/null",
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
