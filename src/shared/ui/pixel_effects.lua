local media_settings = require("src.shared.system.media_settings")

local effects = {}
local paths = {
    {6, -18, 2}, {16, -14, 2}, {23, -7, 3}, {25, 2, 2}, {19, 12, 2},
    {-6, 16, 2}, {-15, 10, 3}, {-24, 2, 2}, {-19, -9, 2}, {-10, -13, 3},
}

local function pixel(x, y, w, h, color, opacity)
    love.graphics.setColor(color[1], color[2], color[3], opacity)
    love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function burst(x, y, progress, colors)
    local travel = 1 - (1 - progress) ^ 2
    local opacity = (1 - progress) ^ 1.5
    for index, path in ipairs(paths) do
        local px = x + path[1] * travel
        local py = y + path[2] * travel + 6 * progress * progress
        local size = progress < 0.65 and path[3] or 1
        pixel(px, py, size, size, colors.accent, opacity)
        if index % 3 == 0 then
            pixel(px - 2, py, 1, 1, colors.text, opacity)
        end
    end
end

function effects.message_launch(x, y, w, h, age, colors)
    if age < 0 or age >= 0.46 or w < 24 or h < 12 or not media_settings.get("ui_motion") then return end
    local progress = age / 0.46
    local streak = math.floor(math.min(w - 10, 46) * (1 - (1 - progress) ^ 3))
    if streak > 0 then
        pixel(x + w - 4 - streak, y + h - 2, streak, 2, colors.accent, (1 - progress) * 0.85)
    end
    burst(x + w - math.min(28, w / 2), y + h - 4, progress, colors)
end

function effects.notification_scan(x, y, w, age, colors)
    if age < 0 or age >= 0.52 or w < 24 or not media_settings.get("ui_motion") then return end
    local progress = age / 0.52
    local track = w - 16
    local head = math.floor(track * (1 - (1 - progress) ^ 2))
    local tail = math.min(head, 26)
    if tail > 0 then
        pixel(x + 8 + head - tail, y, tail, 2, colors.accent, 1 - progress)
    end
    pixel(x + 8 + head, y - 1, 3, 3, colors.text, (1 - progress) * 0.9)
    burst(x + 12, y + 3, progress, colors)
end

return effects
