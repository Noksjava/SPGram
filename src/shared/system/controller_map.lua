local M = {}

M.actions = {
    {id = "confirm", label = "Confirm", key = "return"},
    {id = "back", label = "Back", key = "escape"},
    {id = "options", label = "Options", key = "y"},
    {id = "search", label = "Backspace / Media shortcuts", key = "x"},
    {id = "shortcuts", label = "Controls", key = "tab"},
    {id = "keyboard", label = "Keyboard / Settings", key = "f1"},
}

local button_labels = {a = "A", b = "B", x = "X", y = "Y", back = "SELECT", start = "START"}

M.faces = {"top", "left", "right", "bottom"}
local sdl_positions = {a = 4, b = 3, x = 2, y = 1}

function M.position(button, positions)
    return (positions or sdl_positions)[button]
end

function M.read_positions(data)
    local positions = {}
    for position, face in ipairs(M.faces) do
        local button = (data or ""):match(face .. "=([abxy])")
        if not button or positions[button] then return nil end
        positions[button] = position
    end
    return positions
end

function M.encode_positions(positions)
    local lines = {}
    for button, position in pairs(positions) do lines[position] = M.faces[position] .. "=" .. button end
    return table.concat(lines, "\n") .. "\n"
end

function M.defaults(layout, positions)
    local buttons = {}
    for button, position in pairs(positions or sdl_positions) do buttons[position] = button end
    return {confirm = buttons[layout == "retro" and 3 or 4], back = buttons[layout == "retro" and 4 or 3],
        options = buttons[1], search = buttons[2], shortcuts = "back", keyboard = "start"}
end

function M.same_bindings(left, right)
    for _, action in ipairs(M.actions) do
        if left[action.id] ~= right[action.id] then return false end
    end
    return true
end

function M.label(button)
    return button_labels[button]
end

function M.remap(mapping, action, button)
    if not button_labels[button] or not mapping[action] then return false end
    for _, candidate in ipairs(M.actions) do
        local id = candidate.id
        if mapping[id] == button then mapping[id] = mapping[action]; break end
    end
    mapping[action] = button
    return true
end

function M.read(layout, data, positions)
    local mapping, used = {}, {}
    for _, action in ipairs(M.actions) do
        local button = (data or ""):match("^" .. action.id .. "=(%a+)") or
            (data or ""):match("\n" .. action.id .. "=(%a+)")
        if not button_labels[button] or used[button] then return M.defaults(layout, positions) end
        mapping[action.id], used[button] = button, true
    end
    if not (data or ""):match("^version=2\n") then
        local old_default = M.defaults(layout, {a = 3, b = 4, x = 2, y = 1})
        if M.same_bindings(mapping, old_default) then return M.defaults(layout, positions) end
    end
    return mapping
end

function M.encode(mapping)
    local lines = {"version=2"}
    for _, action in ipairs(M.actions) do
        lines[#lines + 1] = action.id .. "=" .. mapping[action.id]
    end
    return table.concat(lines, "\n") .. "\n"
end

function M.buttons(layout, mapping)
    mapping = mapping or M.defaults(layout)
    local keys = {dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
        leftshoulder = "pageup", rightshoulder = "pagedown", lefttrigger = "l2", righttrigger = "r2"}
    for _, action in ipairs(M.actions) do keys[mapping[action.id]] = action.key end
    return mapping.confirm, mapping.back, keys
end

return M
