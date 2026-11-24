local dir = ...
local path = dir .. "/performance.log"
local previous = dir .. "/performance.previous.log"
local channel = love.thread.getChannel("spgram_perf_trace")
local limit = 16 * 1024

local existing = io.open(path, "rb")
local bytes = existing and existing:seek("end") or 0
if existing then existing:close() end

local function rss()
    local file = io.open("/proc/self/status", "r")
    if not file then return -1 end
    local data = file:read(4096)
    file:close()
    return data and tonumber(data:match("VmRSS:%s+(%d+)")) or -1
end

while true do
    local sample = channel:demand()
    if sample == false then break end
    local line = string.format("%s rss_kib=%d %s\n", os.date("%Y-%m-%dT%H:%M:%S"), rss(), sample)
    if bytes + #line > limit then
        os.remove(previous)
        if os.rename(path, previous) then bytes = 0 end
    end
    local file = io.open(path, bytes + #line <= limit and "ab" or "wb")
    if file then
        if bytes + #line > limit then bytes = 0 end
        if file:write(line) then bytes = bytes + #line end
        file:close()
    end
end
