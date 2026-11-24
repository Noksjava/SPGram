local languages = {}

languages.options = {
    {id = "en", label = "English"},
    {id = "fr", label = "French"},
    {id = "ru", label = "Russian"},
    {id = "uk", label = "Ukrainian"},
    {id = "pl", label = "Polish"},
    {id = "zh", label = "Chinese (Pinyin)"},
}

local enabled = {en = true, ru = true}
local active = "en"
local loaded = false

function languages.load()
    if loaded then return end
    loaded = true
    local fs = love.filesystem
    if not fs or not fs.read then return end
    local ok, data = pcall(fs.read, "keyboard-languages.conf")
    if not ok or not data then return end
    local configured = {}
    local ids = data:match("enabled=([^\r\n]+)") or ""
    for id in ids:gmatch("%a+") do configured[id] = true end
    local count = 0
    for _, option in ipairs(languages.options) do
        if configured[option.id] then count = count + 1 end
    end
    if count > 0 then enabled = configured end
    active = data:match("active=(%a+)") or "en"
end

function languages.enabled(id)
    languages.load()
    return enabled[id] == true
end

function languages.current()
    languages.load()
    for _, option in ipairs(languages.options) do
        if option.id == active and enabled[active] then return active end
    end
    for _, option in ipairs(languages.options) do
        if enabled[option.id] then return option.id end
    end
end

local function save()
    local ids = {}
    for _, option in ipairs(languages.options) do
        if enabled[option.id] then ids[#ids + 1] = option.id end
    end
    if love.filesystem and love.filesystem.write then
        love.filesystem.write("keyboard-languages.conf",
            "enabled=" .. table.concat(ids, ",") .. "\nactive=" .. languages.current() .. "\n")
    end
end

function languages.toggle(id)
    languages.load()
    if enabled[id] then
        local count = 0
        for _, option in ipairs(languages.options) do
            if enabled[option.id] then count = count + 1 end
        end
        if count == 1 then return false end
    end
    enabled[id] = not enabled[id]
    active = languages.current()
    save()
    return true
end

function languages.enabled_options()
    languages.load()
    local options = {}
    for _, option in ipairs(languages.options) do
        if enabled[option.id] then options[#options + 1] = option end
    end
    return options
end

function languages.select(id)
    if not languages.enabled(id) then return false end
    active = id
    save()
    return true
end

return languages
