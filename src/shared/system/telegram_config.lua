local M = {}

function M.read(path)
    local file = io.open(path, "rb")
    if not file then return {} end
    local values = {}
    for line in file:lines() do
        line = line:gsub("^\239\187\191", "")
        local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key then values[key] = value end
    end
    file:close()
    return values
end

function M.credentials(config, env_id, env_hash)
    local id_text = env_id or config.api_id or ""
    local hash = env_hash or config.api_hash or ""
    if id_text == "" or hash == "" then
        return nil, nil, "Telegram API credentials are missing."
    end
    local id = tonumber(id_text)
    if not id_text:match("^%d+$") or not id or id < 1 or id > 2147483647 then
        return nil, nil, "api_id must be the numeric Telegram application ID."
    end
    if #hash ~= 32 or not hash:match("^%x+$") then
        return nil, nil, "api_hash must be the 32-character Telegram application hash."
    end
    return id, hash
end

function M.for_app(config, bundled_path, env_id, env_hash)
    local bundled = M.read(bundled_path)
    if bundled.api_id ~= nil or bundled.api_hash ~= nil then
        local id, hash = M.credentials(bundled)
        if not id then return nil, nil, "The installed package has invalid app credentials. Reinstall SPgram." end
        return id, hash
    end
    return M.credentials(config, env_id, env_hash)
end

return M
