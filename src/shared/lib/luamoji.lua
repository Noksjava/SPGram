local EmojiRenderer = {}
EmojiRenderer.__index = EmojiRenderer

local utf8 = require("utf8")

function EmojiRenderer.new()
    local self = setmetatable({}, EmojiRenderer)
    self.baseDir = ""
    self.cache = {}
    self.missing = {}
    self.emojiSize = 32
    return self
end

function EmojiRenderer:setEmojiDirectory(path)
    if path:sub(-1) ~= "/" then
        path = path .. "/"
    end
    self.baseDir = path
end

function EmojiRenderer:setEmojiSize(size)
    self.emojiSize = size
end

function EmojiRenderer:_getEmojiImage(codepoint)
    if self.cache[codepoint] then return self.cache[codepoint] end
    if self.missing[codepoint] then return nil end

    local hex = string.format("%x", codepoint):lower()
    local path = self.baseDir .. hex .. ".png"

    local info = love.filesystem.getInfo(path)
    if info then
        local status, img = pcall(love.graphics.newImage, path)
        if status and img then
            self.cache[codepoint] = img
            return img
        end
    end

    self.missing[codepoint] = true
    return nil
end

function EmojiRenderer:getWidth(text, font)
    font = font or love.graphics.getFont()
    local width = 0
    local targetSize = font:getHeight()

    for p, c in utf8.codes(text) do
        local img = self:_getEmojiImage(c)
        if img then
            width = width + targetSize
        else
            width = width + font:getWidth(utf8.char(c))
        end
    end
    return width
end

function EmojiRenderer:print(text, x, y)
    local font = love.graphics.getFont()
    local fontHeight = font:getHeight()
    local currentX = x
    local textBuffer = ""

    for p, c in utf8.codes(text) do
        local img = self:_getEmojiImage(c)

        if img then
            if #textBuffer > 0 then
                love.graphics.print(textBuffer, currentX, y)
                currentX = currentX + font:getWidth(textBuffer)
                textBuffer = ""
            end

            local imgW, imgH = img:getDimensions()
            local s = fontHeight / imgH

            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, currentX, y, 0, s, s)
            currentX = currentX + (imgW * s)
        else
            textBuffer = textBuffer .. utf8.char(c)
        end
    end

    if #textBuffer > 0 then
        love.graphics.print(textBuffer, currentX, y)
    end
end

function EmojiRenderer:printf(text, x, y, limit, align)
    local font = love.graphics.getFont()
    local fontHeight = font:getHeight()
    align = align or "left"

    local lines = {}
    local currentLine = ""
    local currentWidth = 0

    for word in text:gmatch("%S+") do

        local wordW = self:getWidth(word, font)
        local spaceW = font:getWidth(" ")

        if currentWidth + wordW > limit then

             table.insert(lines, currentLine)
             currentLine = word
             currentWidth = wordW
        else
            if #currentLine > 0 then
                currentLine = currentLine .. " " .. word
                currentWidth = currentWidth + spaceW + wordW
            else
                currentLine = word
                currentWidth = wordW
            end
        end
    end
    table.insert(lines, currentLine)

    local currentY = y
    local lineHeight = fontHeight * 1.2

    for _, line in ipairs(lines) do
        local lineW = self:getWidth(line, font)
        local lineX = x

        if align == "center" then
            lineX = x + (limit - lineW) / 2
        elseif align == "right" then
            lineX = x + (limit - lineW)
        end

        self:print(line, lineX, currentY)
        currentY = currentY + lineHeight
    end
end

return EmojiRenderer
