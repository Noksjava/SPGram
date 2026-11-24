local ui = require("src.shared.ui.ui_kit")

local controls_screen = {}

local SECTIONS = {
    { title = "Chat list", rows = {
        {"↑ / ↓", "Select a chat"}, {"{confirm}", "Open chat"}, {"{options}", "Search and chat options"},
        {"L1 / R1", "Move five chats"}, {"L2 / R2", "Switch chats, folders and archive"},
        {"↑ at first chat", "Settings and profile shortcuts"}, {"{shortcuts}", "Controls"},
    }},
    { title = "Conversation", rows = {
        {"↑ / ↓", "Move between messages"}, {"← / →", "Scroll chat"},
        {"{confirm}", "Open message or chosen control"}, {"{options}", "Search, select and more"},
        {"↓ at latest", "Message box, media picker and Send"}, {"{keyboard}", "On-screen keyboard"},
        {"{confirm}", "Type"}, {"{search} / {options}", "Shift / choose language"},
        {"{keyboard} / {back}", "Submit / close keyboard"}, {"L1 / R1", "Page through history"},
        {"R2", "Jump to last-read message"}, {"{back}", "Back to chats or clear selection"},
    }},
    { title = "Media", rows = {
        {"D-pad", "Pan a picture"}, {"L1 / R1", "Zoom pictures or seek video"},
        {"L2 / R2", "Previous or next picture"}, {"{confirm}", "Play or pause video"},
        {"{back}", "Close viewer"},
    }},
    { title = "Stickers, GIFs and emoji", rows = {
        {"Composer", "Open media picker"}, {"{search}", "Preview fullscreen"},
        {"{confirm}", "Open or send"}, {"{options}", "Choose Stickers or GIFs"},
        {"{back}", "Close preview / pack"},
    }},
    { title = "Profile", rows = {
        {"{options}", "User or chat profile via Options"},
        {"{back}", "Back"},
    }},
    { title = "Files", rows = {
        {"{options}", "Message options"}, {"View text", "Text file (txt/log/md/json/lua)"},
        {"D-pad / L1 / R1", "Scroll or page through text"}, {"{back}", "Close reader"},
    }},
    { title = "Voice / Audio", rows = {
        {"{confirm}", "Play / pause"}, {"{back}", "Stop"},
    }},
    { title = "General", rows = {
        {"↑ at first chat", "Settings and profile shortcuts"}, {"{shortcuts}", "Controls"},
        {"{shortcuts} + {confirm}", "Exit"}, {"{back}", "Back"},
    }},
}

local FIRST_ROW_Y = 72
local VIEW_TOP = 60
local FOOTER_HEIGHT = 36
local ROW_HEIGHT = 22
local TITLE_HEIGHT = 24
local SECTION_GAP = 14
local SCROLL_STEP = 30

local function column_for(section_index)
    return section_index <= 4 and 1 or 2
end

local function scroll_limit(height)
    local ends = {FIRST_ROW_Y, FIRST_ROW_Y}
    for index, section in ipairs(SECTIONS) do
        local column = column_for(index)
        ends[column] = ends[column] + TITLE_HEIGHT + #section.rows * ROW_HEIGHT + SECTION_GAP
    end
    return math.max(0, math.max(ends[1], ends[2]) - (height - FOOTER_HEIGHT))
end

function controls_screen.new(fonts, tg)
    local self = {fonts = fonts, tg = tg, scroll = 0}
    return setmetatable(self, {__index = controls_screen})
end

function controls_screen:enter()
    self.scroll = 0
end

function controls_screen:update(dt)
end

function controls_screen:draw()
    local f, colors = self.fonts, ui.colors
    local w, h = ui.width(), ui.height()

    ui.rect(0, 0, w, h, colors.bg)
    ui.rect(0, 0, w, 56, colors.header)
    ui.text("Controls", 24, 15, f.subtitle, colors.text)
    ui.button_hint("{shortcuts} — Close   D-pad — Scroll", w - 260, 18, f.tiny, colors.muted, 240)

    local margin = 24
    local gap = 24
    local col_w = math.floor((w - margin * 2 - gap) / 2)
    local col_x = {margin, margin + col_w + gap}
    local viewport_h = h - FOOTER_HEIGHT - VIEW_TOP
    local max_scroll = scroll_limit(h)
    self.scroll = math.max(0, math.min(max_scroll, self.scroll))
    local col_y = {FIRST_ROW_Y - self.scroll, FIRST_ROW_Y - self.scroll}

    love.graphics.setScissor(0, VIEW_TOP, w, viewport_h)
    for index, section in ipairs(SECTIONS) do
        local column = column_for(index)
        local x = col_x[column]
        local y = col_y[column]
        ui.text(section.title, x, y, f.small, colors.accent)
        y = y + TITLE_HEIGHT
        for _, row in ipairs(section.rows) do
            local label = row[1]:gsub("{%a+}", "  ")
            local chip_w = math.max(36, f.tiny:getWidth(label) + 24)
            ui.rect(x, y, chip_w, 18, colors.panel_alt, 4)
            ui.button_hint(row[1], x + 6, y + 3, f.tiny, colors.text, chip_w - 12)
            ui.text(ui.fit(row[2], f.tiny, col_w - chip_w - 12), x + chip_w + 8, y + 3, f.tiny, colors.muted)
            y = y + ROW_HEIGHT
        end
        col_y[column] = y + SECTION_GAP
    end

    love.graphics.setScissor()
    if max_scroll > 0 then
        local bar_h = math.max(30, viewport_h * viewport_h / (viewport_h + max_scroll))
        local bar_y = VIEW_TOP + (self.scroll / max_scroll) * (viewport_h - bar_h)
        ui.rect(w - 10, VIEW_TOP, 6, viewport_h, colors.panel_alt, 3)
        ui.rect(w - 10, bar_y, 6, bar_h, colors.accent, 3)
    end

    ui.cog(27, h - 23, colors.accent)
    ui.button_hint("{confirm} — Set up buttons   {back} — Back   D-pad — Scroll", 40, h - 30, f.tiny, colors.muted)
end

function controls_screen:scroll_by(amount)
    self.scroll = math.max(0, math.min(scroll_limit(ui.height()), self.scroll + amount))
end

function controls_screen:keypressed(key)
    if key == "down" then
        self:scroll_by(SCROLL_STEP)
    elseif key == "up" then
        self:scroll_by(-SCROLL_STEP)
    elseif key == "pagedown" or key == "pageup" then
        local page = math.max(SCROLL_STEP, ui.height() - FOOTER_HEIGHT - VIEW_TOP - ROW_HEIGHT)
        self:scroll_by(key == "pagedown" and page or -page)
    end
end

function controls_screen:wheelmoved(_, y)
    self:scroll_by(-y * SCROLL_STEP)
end

return controls_screen
