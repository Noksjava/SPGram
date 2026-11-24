local trace = {}
local channel, worker, next_sample
local update_peak, draw_peak, frame_peak, slow = 0, 0, 0, 0
local graphics = {}

function trace.start()
    local enabled = os.getenv("SPGRAM_PERF_TRACE")
    if enabled ~= "1" and (enabled ~= nil or not os.getenv("TG_CONFIG")) then return end
    if not love.filesystem.createDirectory("diagnostics") then return end
    channel = love.thread.getChannel("spgram_perf_trace")
    channel:clear()
    worker = love.thread.newThread("threads/performance_log.lua")
    worker:start(love.filesystem.getSaveDirectory() .. "/diagnostics")
    next_sample = 0
end

function trace.clock()
    return channel and love.timer.getTime()
end

function trace.update(started, dt)
    if not started then return end
    update_peak = math.max(update_peak, love.timer.getTime() - started)
    frame_peak = math.max(frame_peak, dt)
    if dt >= 0.05 then slow = slow + 1 end
end

local function count(entries)
    local total = 0
    for _ in pairs(entries or {}) do total = total + 1 end
    return total
end

local function resident_kib()
    local file = io.open("/proc/self/status", "r")
    if not file then return "unavailable" end
    local status = file:read(4096) or ""
    file:close()
    return status:match("VmRSS:%s*(%d+)") or "unavailable"
end

function trace.draw(started, tg)
    if not started then return end
    local now = love.timer.getTime()
    draw_peak = math.max(draw_peak, now - started)
    if now < next_sample then return end
    next_sample = now + 3
    if channel:getCount() >= 2 then return end
    local stats = love.graphics.getStats(graphics)
    local history = tg and tg.current_chat_id and tg.history_state[tg.current_chat_id]
    local media_jobs = tg and tg.anim_in:getCount() or 0
    channel:push(string.format(
        "rss_kib=%s lua_kib=%.0f texture_kib=%.0f frame_ms=%.1f update_ms=%.1f draw_ms=%.1f slow_frames=%d"
        .. " avatars=%d avatar_pending=%d thumbnail_queued=%d thumbnail_active=%d media_jobs=%d"
        .. " file_requests=%d history_pending=%d video_active=%d",
        resident_kib(), collectgarbage("count"), (stats.texturememory or 0) / 1024, frame_peak * 1000,
        update_peak * 1000, draw_peak * 1000, slow, count(tg and tg.avatar_photos),
        count(tg and tg.avatar_pending), tg and #(tg.webp_queue or {}) or 0, tg and tg.webp_active and 1 or 0,
        media_jobs, tg and tg.active_downloads or 0, history and history.loading and 1 or 0,
        tg and tg.active_video and 1 or 0))
    update_peak, draw_peak, frame_peak, slow = 0, 0, 0, 0
end

function trace.stop()
    if channel then
        channel:push(false)
        channel = nil
    end
end

return trace
