local M = {}

function M.installed(relative)
    local source = love.filesystem.getSource()
    local path = source .. "/" .. relative
    local library = io.open(path, "rb")
    if not library then
        return nil, "Install the unpacked application directory with " .. relative
    end
    library:close()
    return path
end

return M
