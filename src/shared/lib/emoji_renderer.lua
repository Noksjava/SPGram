local atlas, glyphs
local cell, columns = 24, 64
local variation = "️"
local character = "[%z\1-\127\194-\244][\128-\191]*"
local capture = "(" .. character .. ")"

local function load_glyphs()
    glyphs = {}
    local ok, index = pcall(love.filesystem.read, "icons/emoji/twemoji.txt")
    if not ok or not index then return end
    local ok_image, image = pcall(love.graphics.newImage, "icons/emoji/twemoji.png")
    if not ok_image then return end
    atlas = image
    local index_in_atlas = 0
    for line in index:gmatch("[^\n]+") do
        local node = glyphs
        for unit in line:gmatch(character) do
            if not node[unit] then node[unit] = {} end
            node = node[unit]
        end
        node.quad_x = index_in_atlas % columns * cell
        node.quad_y = math.floor(index_in_atlas / columns) * cell
        index_in_atlas = index_in_atlas + 1
    end
end

return function(text, x, y, font, color)
    if not text:find("[\194-\244]") then return false end
    if not glyphs then load_glyphs() end
    if not atlas then return false end
    local start, plain = 1, 1
    local height = font:getHeight()
    while start <= #text do
        local _, last, unit = text:find(capture, start)
        if not last then break end
        local node = glyphs[unit]
        if node then
            local ending = node.quad_x and last
            local found = node.quad_x and node
            local cursor = last + 1
            while cursor <= #text do
                local _, tail, next_unit = text:find(capture, cursor)
                if not tail then break end
                if next_unit ~= variation then node = node[next_unit] end
                if not node then break end
                if node.quad_x then ending, found = tail, node end
                cursor = tail + 1
            end
            if found and text:sub(ending + 1, ending + 3) ~= "︎" then
                local offset = font:getWidth(text:sub(1, start - 1))
                if start > plain then
                    love.graphics.setColor(color)
                    love.graphics.print(text:sub(plain, start - 1), x + font:getWidth(text:sub(1, plain - 1)), y)
                end
                local advance = font:getWidth(text:sub(1, ending)) - offset
                local size = math.min(height, math.max(1, advance))
                if not found.quad then found.quad = love.graphics.newQuad(found.quad_x, found.quad_y, cell, cell,
                    atlas:getDimensions()) end
                love.graphics.setColor(1, 1, 1, color[4] or 1)
                love.graphics.draw(atlas, found.quad, x + offset + (advance - size) / 2, y + (height - size) / 2,
                    0, size / cell, size / cell)
                plain, last = ending + 1, ending
            end
        end
        start = last + 1
    end
    if plain == 1 then return false end
    if plain <= #text then
        love.graphics.setColor(color)
        love.graphics.print(text:sub(plain), x + font:getWidth(text:sub(1, plain - 1)), y)
    end
    return true
end
