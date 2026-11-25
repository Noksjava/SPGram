
local utf8 = require("utf8")
local media_settings = require("src.shared.system.media_settings")
local ui = {notification_gray = {0.42, 0.42, 0.42}}

ui.themes = {
    dark = {
        bg = {0.055, 0.072, 0.13}, panel = {0.09, 0.115, 0.195}, panel_alt = {0.135, 0.16, 0.255},
        header = {0.075, 0.094, 0.16}, accent = {0.51, 0.92, 0.76}, accent_dark = {0.19, 0.29, 0.36},
        text = {0.93, 0.96, 1}, muted = {0.65, 0.72, 0.84},
        green = {0.51, 0.92, 0.76}, red = {1, 0.49, 0.53}, yellow = {1, 0.79, 0.43},
        white = {1, 1, 1},
    },
    light = {
        bg = {0.95, 0.96, 0.98}, panel = {1.00, 1.00, 1.00}, panel_alt = {0.92, 0.93, 0.96},
        header = {0.88, 0.90, 0.94}, accent = {0.15, 0.45, 0.85}, accent_dark = {0.10, 0.32, 0.62},
        text = {0.12, 0.14, 0.18}, muted = {0.45, 0.48, 0.55},
        green = {0.15, 0.60, 0.30}, red = {0.85, 0.20, 0.20}, yellow = {0.80, 0.60, 0.10},
        white = {1, 1, 1},
    },
    redwine = {
        bg = {0.12, 0.06, 0.08}, panel = {0.18, 0.09, 0.12}, panel_alt = {0.22, 0.12, 0.16},
        header = {0.14, 0.07, 0.10}, accent = {0.85, 0.25, 0.35}, accent_dark = {0.60, 0.18, 0.25},
        text = {0.95, 0.90, 0.92}, muted = {0.65, 0.50, 0.55},
        green = {0.40, 0.85, 0.50}, red = {1.00, 0.30, 0.30}, yellow = {1.00, 0.75, 0.30},
        white = {1, 1, 1},
    },
    bluemoon = {
        bg = {0.05, 0.08, 0.16}, panel = {0.08, 0.12, 0.22}, panel_alt = {0.10, 0.16, 0.28},
        header = {0.06, 0.10, 0.18}, accent = {0.30, 0.60, 1.00}, accent_dark = {0.20, 0.45, 0.80},
        text = {0.90, 0.95, 1.00}, muted = {0.50, 0.60, 0.75},
        green = {0.30, 0.85, 0.55}, red = {0.95, 0.35, 0.40}, yellow = {1.00, 0.85, 0.30},
        white = {1, 1, 1},
    },
    xmas = {
        bg = {0.05, 0.12, 0.08}, panel = {0.08, 0.18, 0.12}, panel_alt = {0.10, 0.22, 0.16},
        header = {0.06, 0.14, 0.10}, accent = {0.90, 0.20, 0.20}, accent_dark = {0.65, 0.15, 0.15},
        text = {0.95, 1.00, 0.95}, muted = {0.55, 0.70, 0.60},
        green = {0.30, 0.85, 0.40}, red = {0.95, 0.25, 0.25}, yellow = {1.00, 0.85, 0.30},
        white = {1, 1, 1},
    },
    hackers = {
        bg = {0.02, 0.06, 0.02}, panel = {0.04, 0.10, 0.04}, panel_alt = {0.05, 0.13, 0.05},
        header = {0.03, 0.08, 0.03}, accent = {0.20, 0.95, 0.30}, accent_dark = {0.12, 0.70, 0.20},
        text = {0.30, 1.00, 0.40}, muted = {0.25, 0.60, 0.30},
        green = {0.20, 0.95, 0.30}, red = {0.95, 0.25, 0.25}, yellow = {0.95, 0.95, 0.20},
        white = {1, 1, 1},
    },
    violet = {
        bg = {0.10, 0.06, 0.16}, panel = {0.14, 0.09, 0.22}, panel_alt = {0.18, 0.12, 0.28},
        header = {0.12, 0.07, 0.18}, accent = {0.65, 0.30, 0.95}, accent_dark = {0.45, 0.20, 0.70},
        text = {0.95, 0.92, 1.00}, muted = {0.60, 0.55, 0.70},
        green = {0.40, 0.85, 0.55}, red = {0.95, 0.30, 0.45}, yellow = {1.00, 0.80, 0.30},
        white = {1, 1, 1},
    },
}
ui.current_theme = "dark"
function ui.set_theme(name)
    if ui.themes[name] then
        ui.current_theme = name
        ui.colors = ui.themes[name]
    end
end
ui.colors = ui.themes.dark

local fonts = {}
local ui_scale = 0.9

ui.font_families = {
    {id = "default", label = "SPgram Classic"},
    {id = "pixelify", label = "Pixelify Sans", file = "PixelifySans.ttf"},
    {id = "vt323", label = "VT323", file = "VT323-Regular.ttf", size = 1.15},
    {id = "silkscreen", label = "Silkscreen", file = "Silkscreen-Regular.ttf", size = 0.92},
    {id = "pressstart", label = "Press Start 2P", file = "PressStart2P-Regular.ttf", size = 0.72},
    {id = "dotgothic", label = "DotGothic16", file = "DotGothic16-Regular.ttf"},
    {id = "jersey10", label = "Jersey 10", file = "Jersey10-Regular.ttf", size = 1.12},
    {id = "jersey15", label = "Jersey 15", file = "Jersey15-Regular.ttf", size = 1.12},
    {id = "jersey20", label = "Jersey 20", file = "Jersey20-Regular.ttf", size = 1.12},
    {id = "micro5", label = "Micro 5", file = "Micro5-Regular.ttf", size = 1.23},
    {id = "bytesized", label = "Bytesized", file = "Bytesized-Regular.ttf", size = 1.15},
    {id = "jacquard12", label = "Jacquard 12", file = "Jacquard12-Regular.ttf", size = 1.12},
    {id = "sixtyfour", label = "Sixtyfour", file = "Sixtyfour.ttf", size = 0.8},
}
local font_family = ui.font_families[1]
local font_previews = {}

function ui.get_font_family()
    return font_family
end

local function select_font(id)
    for _, option in ipairs(ui.font_families) do
        if option.id == id then
            font_family = option
            return true
        end
    end
    return false
end

function ui.load_font_preference()
    local data = love.filesystem.read("font-family.conf")
    if data then select_font(data:match("^%s*(%w+)%s*$")) end
end

function ui.set_font_family(id)
    if select_font(id) then
        love.filesystem.write("font-family.conf", id .. "\n")
        ui.load_fonts(ui_scale)
    end
end


local function load_font(path, size)
    local scale_size = math.floor(size * ui_scale)
    local ok, font = pcall(love.graphics.newFont, path, scale_size)
    if ok and font then
        return font
    end
    return love.graphics.newFont(scale_size)
end

function ui.load_fonts(scale)
    if scale == nil then
        local w, h = love.graphics.getDimensions()
        ui_scale = math.min(w / 640, h / 480)
        if ui_scale < 0.5 then ui_scale = 0.5 end
        if ui_scale > 2.0 then ui_scale = 2.0 end
    else
        ui_scale = scale
    end
    local path = "fonts/AdwaitaSans-Regular.ttf"
    if not love.filesystem.getInfo(path) then
        path = nil
    end

    local retro = "fonts/JetBrainsMono_SemiBold.ttf"
    local selected = font_family.file and "fonts/retro/" .. font_family.file
    local function face(default, size)
        return load_font(selected or default, size * (font_family.size or 1))
    end
    font_previews = {}
    fonts.title = face(retro, 24)
    fonts.subtitle = face(retro, 18)
    fonts.normal = face(path, 15)
    fonts.small = face(retro, 13)
    fonts.tiny = face(retro, 12)
    fonts.mono = face(retro, 13)
    fonts.emoji_normal = load_font("fonts/NotoEmoji-Regular.ttf", 16)
    fonts.emoji_small = load_font("fonts/NotoEmoji-Regular.ttf", 14)
    fonts.emoji_tiny = load_font("fonts/NotoEmoji-Regular.ttf", 12)
    fonts.bold = face(path, 16)
    fonts.italic = face(path, 16)
    fonts.bold_italic = face(path, 16)
    local han = "fonts/SPgramHan-Regular.ttf"
    local has_han = love.filesystem.getInfo(han)
    local fallbacks = {}
    local function fallback(font, emoji, han_font, size)
        local chain = {}
        if selected or font ~= fonts.normal then
            fallbacks[size] = fallbacks[size] or load_font(path, size)
            chain[#chain + 1] = fallbacks[size]
        end
        chain[#chain + 1] = emoji
        if han_font then chain[#chain + 1] = han_font end
        font:setFallbacks(unpack(chain))
    end
    local han_normal = has_han and load_font(han, 15)
    local han_small = has_han and load_font(han, 13)
    local han_tiny = has_han and load_font(han, 12)
    for _, font in ipairs({fonts.title, fonts.subtitle, fonts.normal, fonts.mono,
        fonts.bold, fonts.italic, fonts.bold_italic}) do
        fallback(font, fonts.emoji_normal, han_normal, 15)
    end
    fallback(fonts.small, fonts.emoji_small, han_small, 13)
    fallback(fonts.tiny, fonts.emoji_tiny, han_tiny, 12)
    return fonts
end

function ui.font_preview(option)
    if not font_previews[option.id] then
        local path = option.file and "fonts/retro/" .. option.file or "fonts/JetBrainsMono_SemiBold.ttf"
        font_previews[option.id] = load_font(path, 17 * (option.size or 1))
    end
    return font_previews[option.id]
end

function ui.get_scale()
    return ui_scale
end

function ui.set_scale(scale)
    ui_scale = scale
end

function ui.width()    return love.graphics.getWidth() end
function ui.height()   return love.graphics.getHeight() end

function ui.set_color(color, alpha)
    if not color then
        love.graphics.setColor(1, 1, 1, alpha or 1)
        return
    end
    love.graphics.setColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

function ui.clear(color)
    ui.set_color(color or ui.colors.bg)
    love.graphics.rectangle("fill", 0, 0, ui.width(), ui.height())
    ui.set_color(ui.colors.white)
end

function ui.rect(x, y, w, h, color, radius)
    ui.set_color(color)
    if radius then
        love.graphics.rectangle("fill", x, y, w, h, radius, radius)
    else
        love.graphics.rectangle("fill", x, y, w, h)
    end
    ui.set_color(ui.colors.white)
end

function ui.outline(x, y, w, h, color, radius)
    ui.set_color(color)
    if radius then
        love.graphics.rectangle("line", x, y, w, h, radius, radius)
    else
        love.graphics.rectangle("line", x, y, w, h)
    end
    ui.set_color(ui.colors.white)
end

function ui.retro_panel(x, y, w, h, fill, rim)
    ui.rect(x + 4, y, w - 8, h, rim)
    ui.rect(x, y + 4, w, h - 8, rim)
    ui.rect(x + 2, y + 4, w - 4, h - 8, fill)
    ui.rect(x + 4, y + 2, w - 8, h - 4, fill)
end

function ui.pixel_chat(x, y, size, color)
    ui.rect(x + size, y, size * 6, size, color)
    ui.rect(x, y + size, size, size * 4, color)
    ui.rect(x + size * 7, y + size, size, size * 4, color)
    ui.rect(x + size, y + size * 5, size * 6, size, color)
    ui.rect(x + size * 2, y + size * 6, size * 2, size, color)
    for n = 2, 6, 2 do ui.rect(x + size * n, y + size * 3, size, size, color) end
end

function ui.motion_progress(age, duration)
    if not media_settings.get("ui_motion") then return 1 end
    return math.max(0, math.min(1, age / duration))
end

function ui.press_inset(age)
    local t = ui.motion_progress(age, 0.14)
    if t == 1 then return 0 end
    return math.floor(3 * (1 - t) ^ 2 + 0.5)
end

function ui.focus_lift(age)
    if age < 0 or age >= 0.24 then return 0 end
    local progress = ui.motion_progress(age, 0.24)
    return math.floor(math.sin(progress * math.pi * 1.8) * (1 - progress) * 7 + 0.5)
end

function ui.focus_corners(x, y, w, h, color, lift)
    local edge = math.min(math.max(4, 8 + (lift or 0)), math.max(4, math.floor(math.min(w, h) / 2)))
    for _, px in ipairs({x, x + w - edge}) do
        ui.rect(px, y, edge, 2, color)
        ui.rect(px, y + h - 2, edge, 2, color)
    end
    for _, px in ipairs({x, x + w - 2}) do
        ui.rect(px, y + 2, 2, edge - 2, color)
        ui.rect(px, y + h - edge, 2, edge - 2, color)
    end
end

local draw_emoji_text = require("src.shared.lib.emoji_renderer")

function ui.text(text, x, y, font, color)
    local ink = color or ui.colors.text
    local f = font or fonts.normal
    love.graphics.setFont(f)
    if not draw_emoji_text(tostring(text or ""), x, y, f, ink) then
        ui.set_color(ink)
        love.graphics.print(text or "", x, y)
    end
    ui.set_color(ui.colors.white)
end

function ui.media_picker_icon(x, y, color)
    ui.outline(x - 21, y - 7, 15, 14, color, 2)
    ui.set_color(color)
    love.graphics.circle("fill", x - 16, y - 3, 1.5)
    love.graphics.line(x - 19, y + 4, x - 14, y, x - 11, y + 3, x - 8, y + 1)
    love.graphics.line(x - 2, y + 7, x + 4, y - 7)
    love.graphics.circle("line", x + 13, y, 7)
    love.graphics.circle("fill", x + 11, y - 2, 1)
    love.graphics.circle("fill", x + 15, y - 2, 1)
    love.graphics.line(x + 10, y + 2, x + 12, y + 4, x + 14, y + 4, x + 16, y + 2)
end

function ui.cog(x, y, color)
    ui.set_color(color)
    for step = 0, 7 do
        local angle = step * math.pi / 4
        love.graphics.line(x + math.cos(angle) * 5, y + math.sin(angle) * 5,
            x + math.cos(angle) * 7, y + math.sin(angle) * 7)
    end
    love.graphics.circle("line", x, y, 5)
    love.graphics.circle("line", x, y, 2)
end

local face_positions = {{0, -1}, {-1, 0}, {1, 0}, {0, 1}}
local controller = require("src.shared.system.controller_map")
local controller_positions, controller_bindings = nil, controller.defaults("modern")

function ui.set_controller_bindings(positions, bindings)
    controller_positions, controller_bindings = positions, bindings
end

function ui.contrasting_text(background)
    local function linear(channel)
        return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
    end
    local luminance = 0.2126 * linear(background[1]) + 0.7152 * linear(background[2]) + 0.0722 * linear(background[3])
    return luminance >= 0.179 and {0, 0, 0} or ui.colors.white
end

function ui.pixel_icon(icon, x, y, color)
    if not icon then return end
    for row, pixels in ipairs(icon) do
        for column = 1, #pixels do
            if pixels:sub(column, column) == "1" then
                ui.rect(x + (column - 1) * 3, y + (row - 1) * 3, 3, 3, color)
            end
        end
    end
end

function ui.settings_row_height(font)
    return math.max(34, font:getHeight() + 14)
end

function ui.settings_row(font, y, height, row)
    local w, colors = ui.width(), ui.colors
    local bg = row.selected and (row.danger and colors.red or colors.accent) or colors.panel_alt
    local ink = row.selected and ui.contrasting_text(bg) or colors.text
    local icon_y = y + math.floor((height - 21) / 2)
    local text_y = y + math.floor((height - font:getHeight()) / 2)
    local right = w - 58
    local value_font = row.value_font or font
    local value = row.value and ui.fit(row.value, value_font, math.max(1, math.floor((w - 142) * 0.38)))
    if value then
        right = right - value_font:getWidth(value)
    elseif row.binding then
        right = right - font:getHeight()
    elseif row.arrow then
        right = right - 14
    end
    ui.retro_panel(40, y, w - 80, height, bg, row.selected and colors.accent_dark or colors.header)
    if row.selected then
        ui.focus_corners(41, y + 1, w - 82, height - 2, colors.accent, row.lift)
    end
    ui.pixel_icon(row.icon, 56, icon_y, row.selected and ink or colors.accent)
    ui.text(ui.fit(row.label, font, math.max(1, right - 102)), 90, text_y, font, ink)
    if value then
        ui.text(value, right, y + math.floor((height - value_font:getHeight()) / 2), value_font, ink)
    elseif row.binding then
        ui.button_hint(row.binding, right, text_y, font, ink, nil, ink)
    elseif row.arrow then
        for step = 0, 4 do
            ui.rect(w - 64 + math.min(step, 4 - step) * 2, icon_y + 5 + step * 2, 2, 2, ink)
        end
    end
end

function ui.button_hint(text, x, y, font, color, center_width, active_color)
    local parts, width = {}, 0
    local icon_size = font:getHeight()
    for label, button in (text .. "{}"):gmatch("(.-){(%a*)}") do
        local physical = controller_bindings[button]
        local position = physical and controller.position(physical, controller_positions)
        if physical and not position then label = label .. controller.label(physical) end
        local label_width = font:getWidth(label)
        parts[#parts + 1] = {label, label_width, position}
        width = width + label_width + (position and icon_size or 0)
    end
    local scaled = center_width and center_width > 0 and width > center_width
    if scaled then
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(center_width / width, 1)
        x, y = 0, 0
    elseif center_width then
        x = x + math.max(0, (center_width - width) / 2)
    end
    local step = icon_size * 0.29
    local radius = icon_size * 0.12
    for _, part in ipairs(parts) do
        local label, label_width, button = part[1], part[2], part[3]
        if label ~= "" then ui.text(label, x, y, font, color) end
        x = x + label_width
        if button then
            local cx, cy = x + icon_size / 2, y + icon_size / 2
            for position, offset in ipairs(face_positions) do
                local active = button == position
                ui.set_color(active and (active_color or ui.colors.text) or color)
                love.graphics.circle(active and "fill" or "line", cx + offset[1] * step, cy + offset[2] * step, radius)
            end
            ui.set_color(ui.colors.white)
            x = x + icon_size
        end
    end
    if scaled then love.graphics.pop() end
end

function ui.printf(text, x, y, limit, align, font, color)
    ui.set_color(color or ui.colors.text)
    local f = font or fonts.normal
    if not text or text == "" then
        ui.set_color(ui.colors.white)
        return
    end
    local ok, _, lines = pcall(function() return f:getWrap(text, limit) end)
    if not ok or type(lines) ~= "table" or #lines == 0 then
        love.graphics.setFont(f)
        love.graphics.print(text or "", x, y)
        ui.set_color(ui.colors.white)
        return
    end
    local line_h = f:getHeight()
    for i, line in ipairs(lines) do
        local line_y = y + (i - 1) * line_h
        if align == "center" then
            local lw = f:getWidth(line)
            local lx = x + math.max(0, (limit - lw) / 2)
            ui.text(line, lx, line_y, f, color)
        elseif align == "right" then
            local lw = f:getWidth(line)
            local lx = x + math.max(0, limit - lw)
            ui.text(line, lx, line_y, f, color)
        else
            ui.text(line, x, line_y, f, color)
        end
    end
    ui.set_color(ui.colors.white)
end

function ui.first_char(text)
    if not text or text == "" then return "?" end
    local byte = string.byte(text, 1)
    if byte < 0x80 then return string.sub(text, 1, 1)
    elseif byte < 0xE0 then return string.sub(text, 1, 2)
    elseif byte < 0xF0 then return string.sub(text, 1, 3)
    end
    return string.sub(text, 1, 4)
end

function ui.remove_last_utf8(text)
    if not text or text == "" then return "" end
    local index = #text
    while index > 0 do
        local byte = string.byte(text, index)
        if byte < 0x80 or byte >= 0xC0 then break end
        index = index - 1
    end
    if index <= 0 then return "" end
    return string.sub(text, 1, index - 1)
end

function ui.fit(text, font, max_width)
    if not text or text == "" or max_width <= 0 then return "" end
    local ok, _, lines = pcall(font.getWrap, font, text, max_width)
    if not ok or not lines or #lines == 0 then return text end
    if #lines == 1 then return lines[1] end
    local ellipsis = "…"
    local available = max_width - font:getWidth(ellipsis)
    if available <= 0 then return "" end
    local fits, _, clipped = pcall(font.getWrap, font, lines[1], available)
    return (fits and clipped and clipped[1] or "") .. ellipsis
end

function ui.parse_markdown(text)
    local segments = {}
    if type(text) ~= "string" or text == "" then
        return segments
    end
    local i = 1
    local n = #text
    local plain = ""
    local function flush_plain()
        if plain ~= "" then
            segments[#segments + 1] = { text = plain }
            plain = ""
        end
    end
    local ok = pcall(function()
        while i <= n do

            if text:sub(i, i + 1) == "**" then
                local j = text:find("%*%*", i + 2)
                if j then
                    flush_plain()
                    segments[#segments + 1] = { text = text:sub(i + 2, j - 1), bold = true }
                    i = j + 2
                else
                    plain = plain .. text:sub(i, i)
                    i = i + 1
                end

            elseif text:sub(i, i) == "`" then
                local j = text:find("`", i + 1)
                if j then
                    flush_plain()
                    segments[#segments + 1] = { text = text:sub(i + 1, j - 1), code = true }
                    i = j + 1
                else
                    plain = plain .. text:sub(i, i)
                    i = i + 1
                end

            elseif text:sub(i, i) == "[" then
                local cb = text:find("]", i + 1)
                if cb and text:sub(cb + 1, cb + 1) == "(" then
                    local cp = text:find(")", cb + 2)
                    if cp then
                        flush_plain()
                        segments[#segments + 1] = {
                            text = text:sub(i + 1, cb - 1),
                            link = true,
                            url = text:sub(cb + 2, cp - 1),
                        }
                        i = cp + 1
                    else
                        plain = plain .. text:sub(i, i)
                        i = i + 1
                    end
                else
                    plain = plain .. text:sub(i, i)
                    i = i + 1
                end

            elseif text:sub(i, i) == "*" and text:sub(i + 1, i + 1) ~= "*" then
                local j = text:find("%*", i + 1)
                if j then
                    flush_plain()
                    segments[#segments + 1] = { text = text:sub(i + 1, j - 1), italic = true }
                    i = j + 1
                else
                    plain = plain .. text:sub(i, i)
                    i = i + 1
                end
            else
                plain = plain .. text:sub(i, i)
                i = i + 1
            end
        end
        flush_plain()
    end)
    if not ok or #segments == 0 then
        return { { text = text } }
    end
    return segments
end

function ui.printf_markdown(text, x, y, limit, align, font, color)
    local segments = ui.parse_markdown(text)
    local f = font or fonts.normal
    local bold_font = fonts.bold or f
    local italic_font = fonts.italic or f
    local bold_italic_font = fonts.bold_italic or f
    local code_font = fonts.mono or f
    local link_color = color and { color[1], color[2], color[3], color[4] or 1 } or nil
    if link_color then
        link_color[1], link_color[2], link_color[3] = ui.colors.accent[1], ui.colors.accent[2], ui.colors.accent[3]
    end
    local line_h = f:getHeight()

    local lines = {}
    local line_idx = 0
    local function emit_line(line_text, seg)
        lines[#lines + 1] = { text = line_text, seg = seg }
    end

    local cur_x = x
    local remaining = limit
    local cur_seg = nil
    local cur_buf = ""

    local function flush_buf()
        if cur_buf ~= "" then
            emit_line(cur_buf, cur_seg)
        end
        cur_buf = ""
    end

    for _, seg in ipairs(segments) do
        local seg_font = f
        if seg.code then seg_font = code_font
        elseif seg.bold and seg.italic then seg_font = bold_italic_font
        elseif seg.bold then seg_font = bold_font
        elseif seg.italic then seg_font = italic_font end

        local seg_text = seg.text
        local seg_len = #seg_text
        local pos = 1
        while pos <= seg_len do

            local chunk = seg_text:sub(pos)
            local w = seg_font:getWidth(chunk)
            if w <= remaining or cur_buf == "" then

                if cur_buf ~= "" then cur_buf = cur_buf .. chunk end
                cur_buf = cur_buf .. chunk
                pos = seg_len + 1
            else

                local lo, hi = 1, seg_len - pos + 1
                local best = 0
                while lo <= hi do
                    local mid = math.floor((lo + hi) / 2)
                    local test = seg_text:sub(pos, pos + mid - 1)
                    if seg_font:getWidth(test) <= remaining then
                        best = mid
                        lo = mid + 1
                    else
                        hi = mid - 1
                    end
                end
                if best > 0 then
                    local test = seg_text:sub(pos, pos + best - 1)
                    if cur_buf ~= "" then cur_buf = cur_buf .. test end
                    cur_buf = cur_buf .. test
                    pos = pos + best
                end
                flush_buf()
                cur_x = x
                remaining = limit

                if pos <= seg_len then

                    local c = seg_text:sub(pos, pos)
                    cur_buf = cur_buf .. c
                    pos = pos + 1
                    flush_buf()
                    cur_x = x
                    remaining = limit
                end
            end
            remaining = remaining - seg_font:getWidth(cur_buf)
            cur_x = cur_x + seg_font:getWidth(cur_buf)
            flush_buf()
        end
    end
    flush_buf()

    local line_y = y
    for _, ln in ipairs(lines) do
        local seg = ln.seg
        local ln_font = f
        local ln_color = color or ui.colors.text
        if seg then
            if seg.code then ln_font = code_font
            elseif seg.bold and seg.italic then ln_font = bold_italic_font
            elseif seg.bold then ln_font = bold_font
            elseif seg.italic then ln_font = italic_font end
            if seg.link then ln_color = link_color or ui.colors.accent end
        end
        love.graphics.setFont(ln_font)
        ui.set_color(ln_color)
        local lx = x
        if align == "center" then
            local lw = ln_font:getWidth(ln.text)
            lx = x + math.max(0, (limit - lw) / 2)
        elseif align == "right" then
            local lw = ln_font:getWidth(ln.text)
            lx = x + math.max(0, limit - lw)
        end
        love.graphics.print(ln.text, lx, line_y)
        line_y = line_y + line_h
    end
    ui.set_color(ui.colors.white)
end

function ui.fonts() return fonts end

return ui
