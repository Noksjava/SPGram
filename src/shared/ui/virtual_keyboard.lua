
local ui = require("src.shared.ui.ui_kit")
local languages = require("src.shared.system.keyboard_languages")

local keyboard = {}

local function keys(row)
    local list = {}
    for key in row:gmatch("%S+") do list[#list + 1] = key end
    return list
end

local function layout(...)
    local rows = {...}
    for i, row in ipairs(rows) do rows[i] = keys(row) end
    return rows
end

local layouts = {
    en = layout("q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m , . ?"),
    fr = layout("a z e r t y u i o p", "q s d f g h j k l m", "w x c v b n , . ?", "à â æ ç é è ê ë î ï ô œ ù û ü ÿ"),
    ru = layout("й ц у к е н г ш щ з х ъ", "ф ы в а п р о л д ж э", "я ч с м и т ь б ю ё , ."),
    uk = layout("й ц у к е н г ш щ з х ї", "ф і в а п р о л д ж є", "я ч с м и т ь б ю ґ ’ ."),
    pl = layout("q w e r t y u i o p", "a s d f g h j k l", "z x c v b n m , . ?", "ą ć ę ł ń ó ś ź ż"),
}
layouts.zh = layouts.en

local pinyin_data
local CANDIDATE_COUNT = 8
local function pinyin_candidates(syllable)
    if syllable == "" then return {} end
    if not pinyin_data then
        pinyin_data = "\n" .. (love.filesystem.read("keyboard/pinyin.tsv") or "")
    end
    return keys(pinyin_data:match("\n" .. syllable .. "\t([^\n]+)") or "")
end

local EMOJI_PAGES = {
    {
        {"😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇"},
        {"🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚"},
        {"😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🤩"},
        {"🥳", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣"},
    },
    {
        {"😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬"},
        {"🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗"},
        {"🤔", "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬", "🙄", "😯"},
        {"😦", "😧", "😮", "😲", "🥱", "😴", "🤤", "😪", "😵", "🤐"},
    },
    {
        {"👍", "👎", "👌", "🤌", "🤏", "✌️", "🤞", "🤟", "🤘", "🤙"},
        {"👈", "👉", "👆", "👇", "☝️", "✋", "🤚", "🖐", "🖖", "👋"},
        {"🤝", "🙏", "✍️", "💪", "🦾", "🖕", "👏", "🙌", "👐", "🤲"},
        {"🫶", "🫰", "🫱", "🫲", "🫳", "🫴", "💅", "🤳", "🧠", "👀"},
    },
    {
        {"❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔"},
        {"❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "♥️"},
        {"🔥", "✨", "⭐", "🌟", "💫", "⚡", "💥", "💯", "✅", "❌"},
        {"⭕", "❗", "❓", "‼️", "⁉️", "💤", "🎉", "🎊", "🎁", "🏆"},
    },
    {
        {"🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯"},
        {"🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🦆"},
        {"🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋"},
        {"🐌", "🐞", "🐢", "🐍", "🦎", "🐙", "🦑", "🦀", "🐬", "🐳"},
    },
    {
        {"🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍒"},
        {"🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥦", "🥕", "🌽"},
        {"🍞", "🧀", "🍗", "🍔", "🍟", "🍕", "🌭", "🍿", "🍰", "🍫"},
        {"🍬", "🍺", "☕", "🍵", "🎮", "🎲", "🎯", "🎸", "🎧", "📱"},
    },
}

local extra_upper = {
    ["й"] = "Й", ["ц"] = "Ц", ["у"] = "У", ["к"] = "К", ["е"] = "Е",
    ["н"] = "Н", ["г"] = "Г", ["ш"] = "Ш", ["щ"] = "Щ", ["з"] = "З",
    ["х"] = "Х", ["ф"] = "Ф", ["ы"] = "Ы", ["в"] = "В", ["а"] = "А",
    ["п"] = "П", ["р"] = "Р", ["о"] = "О", ["л"] = "Л", ["д"] = "Д",
    ["ж"] = "Ж", ["э"] = "Э", ["я"] = "Я", ["ч"] = "Ч", ["с"] = "С",
    ["м"] = "М", ["и"] = "И", ["т"] = "Т", ["ь"] = "Ь", ["б"] = "Б",
    ["ю"] = "Ю", ["ё"] = "Ё", ["ъ"] = "Ъ", ["і"] = "І", ["ї"] = "Ї", ["є"] = "Є", ["ґ"] = "Ґ",
    ["à"] = "À", ["â"] = "Â", ["æ"] = "Æ", ["ç"] = "Ç", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê",
    ["ë"] = "Ë", ["î"] = "Î", ["ï"] = "Ï", ["ô"] = "Ô", ["œ"] = "Œ", ["ù"] = "Ù", ["û"] = "Û",
    ["ü"] = "Ü", ["ÿ"] = "Ÿ", ["ą"] = "Ą", ["ć"] = "Ć", ["ę"] = "Ę", ["ł"] = "Ł", ["ń"] = "Ń",
    ["ó"] = "Ó", ["ś"] = "Ś", ["ź"] = "Ź", ["ż"] = "Ż",
}

local CONTROLS = {
    {label = "Shift", action = "shift", width = 62},
    {action = "lang", width = 36},
    {label = "Caps", action = "caps", width = 58},
    {label = "Space", action = "space", width = 120},
    {label = "😀", action = "emoji", width = 52},
    {action = "stickers", width = 54},
    {label = "Files", action = "files", width = 58},
    {label = "⌫", action = "backspace", width = 52},
    {label = "⏎", action = "enter", width = 52},

}

local TEXT_CONTROLS = {}
for _, control in ipairs(CONTROLS) do
    if control.action ~= "stickers" and control.action ~= "files" then
        TEXT_CONTROLS[#TEXT_CONTROLS + 1] = control
    end
end

local PAD = 8
local KEY_W = 44
local KEY_H = 38
local KEY_GAP = 4
local ROW_H = KEY_H + KEY_GAP

local function upper_key(key)
    return extra_upper[key] or string.upper(key)
end

function keyboard.new(fonts, text_only)
    local self = {}
    self.fonts = fonts
    self.controls = text_only and TEXT_CONTROLS or CONTROLS
    self.visible = false
    self.lang = languages.current()
    self.pinyin, self.pinyin_page = "", 1
    self.mode = "text"
    self.emoji_page = 1
    self.shift = false
    self.caps = false
    self.row = 1
    self.col = 1
    setmetatable(self, {__index = keyboard})
    self:_sync_layout()
    return self
end

function keyboard:_sync_layout()
    if self.mode == "emoji" then
        self.emoji_page = math.max(1, math.min(#EMOJI_PAGES, self.emoji_page or 1))
        self.layout = EMOJI_PAGES[self.emoji_page]
    else
        self.layout = layouts[self.lang]
        if self.lang == "zh" then
            self.pinyin_options = pinyin_candidates(self.pinyin)
            local shown = {}
            local first = (self.pinyin_page - 1) * CANDIDATE_COUNT + 1
            for i = 1, CANDIDATE_COUNT do shown[i] = self.pinyin_options[first + i - 1] or "" end
            self.layout = {self.layout[1], self.layout[2], self.layout[3], shown}
        end
    end
end

function keyboard:switch_emoji_page(delta)
    if self.mode ~= "emoji" then return end
    local count = #EMOJI_PAGES
    self.emoji_page = ((self.emoji_page - 1 + delta) % count) + 1
    self:_sync_layout()
    self:_clamp_cursor()
end

function keyboard:_row_count()
    return #self.layout + 1
end

function keyboard:_col_count(row)
    if row <= #self.layout then return #self.layout[row] end
    return #self.controls
end

function keyboard:_clamp_cursor()
    self.row = math.max(1, math.min(self:_row_count(), self.row or 1))
    self.col = math.max(1, math.min(self:_col_count(self.row), self.col or 1))
end

function keyboard:toggle()
    self.visible = not self.visible
    if not self.visible then self.language_menu = nil end
    return self.visible
end

function keyboard:sync_language()
    local id = languages.current()
    if self.lang == id then return end
    self.lang = id
    self.pinyin, self.pinyin_page = "", 1
    self.shift, self.caps = false, false
    self:_sync_layout()
    self:_clamp_cursor()
end

function keyboard:open_language_menu()
    local options = languages.enabled_options()
    if #options < 2 then return end
    local menu = {options = options, index = 1}
    for index, option in ipairs(options) do
        if option.id == self.lang then menu.index = index; break end
    end
    self.language_menu = menu
end

function keyboard:select_language(index)
    local menu = self.language_menu
    local option = menu and menu.options[index]
    if not option then return {kind = "nav"} end
    self.language_menu = nil
    if option.id == self.lang then return {kind = "nav"} end
    local pending = self:commit_pinyin()
    languages.select(option.id)
    self.mode = "text"
    self:sync_language()
    return pending and {kind = "text", text = pending} or {kind = "nav"}
end

function keyboard:update_pinyin(text)
    self.pinyin, self.pinyin_page = text, 1
    self:_sync_layout()
end

function keyboard:commit_pinyin(candidate)
    if self.lang ~= "zh" or self.mode ~= "text" or self.pinyin == "" then return end
    local first = (self.pinyin_page - 1) * CANDIDATE_COUNT + 1
    local text = candidate or (self.pinyin_options or {})[first] or self.pinyin
    self:update_pinyin("")
    return text
end

function keyboard:navigate(dx, dy)
    if dy ~= 0 then
        self.row = self.row + dy
        if self.row < 1 then self.row = self:_row_count() end
        if self.row > self:_row_count() then self.row = 1 end
        self.col = math.min(self.col, self:_col_count(self.row))
    end
    if dx ~= 0 then
        local count = self:_col_count(self.row)
        self.col = self.col + dx
        if self.col < 1 then self.col = count end
        if self.col > count then self.col = 1 end
    end
    return {kind = "nav"}
end

function keyboard:activate()
    if self.row <= #self.layout then
        local key = self.layout[self.row][self.col]
        if not key or key == "" then return nil end
        if self.mode == "text" and self.lang == "zh" then
            if self.row == 4 then return {kind = "text", text = self:commit_pinyin(key)} end
            if key:match("^[a-z]$") and not self.shift and not self.caps then
                if #self.pinyin < 6 then self:update_pinyin(self.pinyin .. key) end
                return {kind = "nav"}
            end
            if self.pinyin ~= "" then
                return {kind = "text", text = self:commit_pinyin() .. key}
            end
        end
        local text = key
        if self.mode == "text" and self.shift ~= self.caps then text = upper_key(key) end
        if self.mode == "text" and self.shift then self.shift = false end
        return {kind = "text", text = text}
    end

    local control = self.controls[self.col]
    if not control then return nil end
    if control.action == "shift" then
        self.shift = not self.shift
        return {kind = "nav"}
    elseif control.action == "caps" then
        self.caps = not self.caps
        return {kind = "nav"}
    elseif control.action == "lang" then
        self:open_language_menu()
        return {kind = "nav"}
    elseif control.action == "emoji" then
        self.mode = self.mode == "emoji" and "text" or "emoji"
        self:_sync_layout()
        self:_clamp_cursor()
        return {kind = "nav"}
    elseif control.action == "space" then
        return {kind = "text", text = self:commit_pinyin() or " "}
    elseif control.action == "backspace" then
        return self:delete_key()
    elseif control.action == "enter" then
        return {kind = "enter"}
    elseif control.action == "hide" then
        self.visible = false
        return {kind = "hide"}
    elseif control.action == "stickers" then
        return {kind = "stickers"}
    elseif control.action == "files" then
        return {kind = "files"}
    end
    return nil
end

function keyboard:delete_key()
    if self.mode == "text" and self.lang == "zh" and self.pinyin ~= "" then
        self:update_pinyin(self.pinyin:sub(1, -2))
        return {kind = "nav"}
    end
    return {kind = "backspace"}
end

function keyboard:keypressed(key)
    if not self.visible then return false end
    self:sync_language()

    local menu = self.language_menu
    if menu then
        if key == "escape" or key == "y" then self.language_menu = nil
        elseif key == "up" or key == "down" then
            menu.index = math.max(1, math.min(#menu.options, menu.index + (key == "up" and -1 or 1)))
        elseif key == "return" or key == "kpenter" or key == "a" then
            return true, self:select_language(menu.index)
        end
        return true, {kind = "nav"}
    end
    if key == "escape" then
        self.visible = false
        return true, {kind = "hide"}
    elseif self.mode == "emoji" and (key == "pageup" or key == "l1") then
        self:switch_emoji_page(-1)
        return true, {kind = "nav"}
    elseif self.mode == "emoji" and (key == "pagedown" or key == "r1") then
        self:switch_emoji_page(1)
        return true, {kind = "nav"}
    elseif self.mode == "text" and self.lang == "zh" and (key == "pageup" or key == "pagedown") then
        local max_page = math.max(1, math.ceil(#self.pinyin_options / CANDIDATE_COUNT))
        self.pinyin_page = math.max(1, math.min(max_page, self.pinyin_page + (key == "pageup" and -1 or 1)))
        self:_sync_layout()
        return true, {kind = "nav"}
    elseif key == "up" then
        return true, self:navigate(0, -1)
    elseif key == "down" then
        return true, self:navigate(0, 1)
    elseif key == "left" then
        return true, self:navigate(-1, 0)
    elseif key == "right" then
        return true, self:navigate(1, 0)
    elseif key == "x" then
        self.shift = not self.shift
        return true, {kind = "nav"}
    elseif key == "y" then
        self:open_language_menu()
        return true, {kind = "nav"}
    elseif key == "return" or key == "kpenter" or key == "a" then
        return true, self:activate()
    elseif key == "backspace" then
        return true, self:delete_key()
    end
    return false
end

local function draw_globe(x, y, color, alpha)
    ui.set_color(color, alpha)
    love.graphics.circle("line", x, y, 8)
    love.graphics.ellipse("line", x, y, 3.5, 8)
    love.graphics.line(x - 8, y, x + 8, y)
    ui.set_color(ui.colors.white)
end

function keyboard:draw_language_menu()
    local menu = self.language_menu
    if not menu then return end
    local f, colors = self.fonts, ui.colors
    local w, h = ui.width(), ui.height()
    local width = math.min(310, w - 32)
    local row_h = math.max(27, f.small:getHeight() + 10)
    local height = 65 + #menu.options * row_h
    local x, y = math.floor((w - width) / 2), math.floor((h - height) / 2)
    ui.rect(0, 0, w, h, {0, 0, 0, 0.64})
    ui.retro_panel(x, y, width, height, colors.panel, colors.accent_dark)
    ui.text("Keyboard language", x + 12, y + 9, f.small, colors.text)
    for index, option in ipairs(menu.options) do
        local top = y + 33 + (index - 1) * row_h
        local selected = index == menu.index
        local fg = selected and ui.contrasting_text(colors.accent) or colors.text
        ui.retro_panel(x + 9, top, width - 18, row_h - 3, selected and colors.accent or colors.panel_alt, colors.accent_dark)
        ui.text(option.label, x + 18, top + 5, f.small, fg)
        if option.id == self.lang then
            ui.text("Current", x + width - 64, top + 6, f.tiny, selected and fg or colors.muted)
        end
    end
    ui.button_hint("{confirm} — Select   {back} — Cancel", x + 9, y + height - 22, f.tiny, colors.muted, width - 18)
end

function keyboard:draw(preview, placeholder)
    if not self.visible then return end

    local f = self.fonts.normal or self.fonts
    local small = self.fonts.small or f
    local tiny = self.fonts.tiny or small
    local colors = ui.colors

    self:sync_language()
    local KB_W = math.min(624, ui.width() - PAD * 2)
    local badge_h = tiny:getHeight() + 10
    local draft_line = small:getHeight() + 3
    local draft_h = draft_line * 2 + 10
    local kb_h = badge_h + draft_h + PAD + #self.layout * ROW_H + ROW_H + 22
    local x = math.floor((ui.width() - KB_W) / 2)
    local y = ui.height() - kb_h - 6

    ui.rect(x, y, KB_W, kb_h, colors.panel, 8)
    ui.outline(x, y, KB_W, kb_h, colors.accent, 8)

    local lang_text = self.lang:upper()
    if self.mode == "emoji" then
        lang_text = string.format("EMOJI %d/%d", self.emoji_page or 1, #EMOJI_PAGES)
    end
    local state = {}
    if self.mode == "text" and self.lang == "zh" and self.pinyin ~= "" then
        state[#state + 1] = self.pinyin .. " · " .. self.pinyin_page .. "/" ..
            math.max(1, math.ceil(#self.pinyin_options / CANDIDATE_COUNT))
    end
    if self.mode == "text" and self.shift then state[#state + 1] = "SHIFT" end
    if self.mode == "text" and self.caps then state[#state + 1] = "CAPS" end
    local badge = lang_text .. (#state > 0 and ("  " .. table.concat(state, " ")) or "")
    ui.text(badge, x + PAD, y + 5, tiny, colors.accent)
    if self.mode == "emoji" then
        ui.button_hint("L1/R1 — Emoji pages", x + KB_W - 155, y + 5, tiny, colors.muted, 145)
    end

    local draft_x, draft_y = x + PAD, y + badge_h
    local draft_w = KB_W - PAD * 2
    local text_x, text_w = draft_x + 8, draft_w - 20
    ui.retro_panel(draft_x, draft_y, draft_w, draft_h, colors.bg, colors.accent_dark)
    if preview and preview ~= "" then
        local cache = self.draft_preview
        if not cache or cache.text ~= preview or cache.width ~= text_w or cache.font ~= small then
            local _, rows = small:getWrap(preview, text_w)
            if #rows == 0 then rows[1] = "" end
            if preview:sub(-1) == "\n" and rows[#rows] ~= "" then rows[#rows + 1] = "" end
            cache = {text = preview, width = text_w, font = small, rows = rows}
            self.draft_preview = cache
        end
        local rows = cache.rows
        local first = math.max(1, #rows - 1)
        for index = first, #rows do
            ui.text(rows[index], text_x, draft_y + 5 + (index - first) * draft_line, small, colors.text)
        end
        local cursor = math.min(text_w, small:getWidth(rows[#rows]))
        ui.rect(text_x + cursor + 2, draft_y + 6 + (#rows - first) * draft_line, 1, small:getHeight(), colors.accent)
    else
        self.draft_preview = nil
        ui.text(ui.fit(placeholder or "Type here…", small, text_w), text_x, draft_y + 5, small, colors.muted)
    end

    local key_y = draft_y + draft_h + PAD
    for row_idx, row in ipairs(self.layout) do
        local kwidth = math.min(KEY_W, math.floor((KB_W - PAD * 2 - (#row - 1) * KEY_GAP) / #row))
        local row_w = #row * kwidth + (#row - 1) * KEY_GAP
        local key_x = x + math.floor((KB_W - row_w) / 2)
        for col_idx, key in ipairs(row) do
            local selected = self.row == row_idx and self.col == col_idx
            local bg = selected and colors.accent_dark or colors.bg
            local outline = selected and colors.accent or colors.muted
            ui.rect(key_x, key_y, kwidth, KEY_H, bg, 4)
            ui.outline(key_x, key_y, kwidth, KEY_H, outline, 4)
            local label = key
            if self.mode == "text" and self.shift ~= self.caps then label = upper_key(key) end
            ui.text(label, key_x + math.floor((kwidth - f:getWidth(label)) / 2),
                key_y + math.floor((KEY_H - f:getHeight()) / 2), f, colors.text)
            key_x = key_x + kwidth + KEY_GAP
        end
        key_y = key_y + ROW_H
    end

    local total_w = 0
    for i, control in ipairs(self.controls) do
        total_w = total_w + control.width
        if i > 1 then total_w = total_w + KEY_GAP end
    end
    local key_x = x + PAD + math.floor((KB_W - PAD * 2 - total_w) / 2)
    local can_switch = #languages.enabled_options() > 1
    for col_idx, control in ipairs(self.controls) do
        local selected = self.row == #self.layout + 1 and self.col == col_idx
        local active = (control.action == "shift" and self.shift)
            or (control.action == "caps" and self.caps)
        local disabled = control.action == "lang" and not can_switch
        local bg = disabled and colors.panel_alt or (selected and colors.accent_dark or (active and colors.accent or colors.bg))
        local outline = selected and not disabled and colors.accent or colors.muted
        ui.rect(key_x, key_y, control.width, KEY_H, bg, 4)
        ui.outline(key_x, key_y, control.width, KEY_H, outline, 4)
        if control.action == "lang" then
            draw_globe(key_x + control.width / 2, key_y + KEY_H / 2, disabled and colors.muted or colors.text,
                disabled and 0.42 or 1)
        elseif control.action == "stickers" then
            ui.media_picker_icon(key_x + control.width / 2, key_y + KEY_H / 2, colors.text)
        else
            ui.text(control.label, key_x + math.floor((control.width - tiny:getWidth(control.label)) / 2),
                key_y + math.floor((KEY_H - tiny:getHeight()) / 2), tiny, active and colors.bg or colors.text)
        end
        key_x = key_x + control.width + KEY_GAP
    end
    local tip = self.lang == "zh" and "Type Pinyin   L1/R1 — Candidates" or "{search} — Shift"
    if can_switch then tip = tip .. "   {options} — Language" end
    ui.button_hint(tip .. "   {back} — Close", x + PAD, y + kb_h - 18, tiny, colors.muted, KB_W - PAD * 2)
    self:draw_language_menu()
end

function keyboard:textinput(text)

end

return keyboard
