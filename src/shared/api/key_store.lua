local M = {}
local lock_fd
local libc, ffi

local function linux()
    if libc then return libc end
    ffi = require("ffi")
    if ffi.os ~= "Linux" then return nil end
    ffi.cdef[[
        int open(const char *pathname, int flags, ...);
        int close(int fd);
        int chmod(const char *pathname, unsigned int mode);
        int flock(int fd, int operation);
        int mkstemp(char *template);
        long write(int fd, const void *buf, unsigned long count);
        int fsync(int fd);
        long readlink(const char *pathname, char *buf, unsigned long bufsiz);
    ]]
    libc = ffi.C
    return libc
end

function M.lock()
    if lock_fd then return true end
    local C = linux()
    if not C then return nil, "Session storage requires Linux." end
    if not love.filesystem.createDirectory("private") then
        return nil, "Cannot create private session storage."
    end
    local private = love.filesystem.getSaveDirectory() .. "/private"
    C.chmod(private, 448)

    local fd = C.open(private .. "/session.lock", 524354, ffi.cast("unsigned int", 384))
    if fd < 0 then return nil, "Cannot open the session lock." end
    if C.flock(fd, 6) ~= 0 then
        C.close(fd)
        return nil, "Session storage is in use or cannot be locked."
    end

    lock_fd = fd
    return true
end

local function persist(directory, path, bytes)
    local template = directory .. "/key-XXXXXX"
    local temporary = ffi.new("char[?]", #template + 1, template)
    local fd = libc.mkstemp(temporary)
    if fd < 0 then return false end
    local written = libc.write(fd, bytes, #bytes) == #bytes and libc.fsync(fd) == 0
    local closed = libc.close(fd) == 0
    temporary = ffi.string(temporary)
    if not written or not closed or not os.rename(temporary, path) then
        os.remove(temporary)
        return false
    end
    return true
end

local function session_paths(account, use_test_dc, sign_in_only)
    assert(type(account) == "string" and account:match("^account_%d+$"), "invalid account")
    local scope = use_test_dc and ("test_dc/" .. account .. "/")
        or (account == "account_1" and "" or ("accounts/" .. account .. "/"))
    local name = (use_test_dc and "test-" or "production-") .. account
    if sign_in_only then
        scope = "preview/" .. scope
        name = "preview-" .. name
    end
    return scope, "private/" .. name
end

local function safe_parents(root, relative)
    local path = root
    local buffer = ffi.new("char[1]")
    for part in relative:gmatch("([^/]+)/") do
        if part == "." or part == ".." then return false end
        path = path .. "/" .. part
        local result = libc.readlink(path, buffer, 1)
        local reason = ffi.errno()
        if result >= 0 or (reason ~= 22 and reason ~= 2) then return false end
    end
    return true
end

local function remove_tree(root, relative)
    local removed, _, code = os.remove(root .. "/" .. relative)
    if removed or code == 2 then return true end
    if not safe_parents(root, relative .. "/child") or not love.filesystem.getInfo(relative, "directory") then
        return false
    end
    for _, name in ipairs(love.filesystem.getDirectoryItems(relative)) do
        if name == "." or name == ".." or name:find("/", 1, true)
            or not remove_tree(root, relative .. "/" .. name) then return false end
    end
    return os.remove(root .. "/" .. relative) == true
end

local function sync_directory(path)
    local fd = libc.open(path, 0)
    if fd < 0 then return false end
    local synced = libc.fsync(fd) == 0
    libc.close(fd)
    return synced
end

function M.mark_logout(account, use_test_dc, sign_in_only)
    if not M.lock() then return false end
    local _, base = session_paths(account, use_test_dc, sign_in_only)
    local root = love.filesystem.getSaveDirectory()
    return safe_parents(root, base .. "-logout")
        and persist(root .. "/private", root .. "/" .. base .. "-logout", "1")
        and sync_directory(root .. "/private")
end

function M.complete_logout(account, use_test_dc, sign_in_only, confirmed)
    if not M.lock() then return false end
    local scope, base = session_paths(account, use_test_dc, sign_in_only)
    local root = love.filesystem.getSaveDirectory()
    local marker = base .. "-logout"
    if not safe_parents(root, marker) then return false end
    if not confirmed and not love.filesystem.getInfo(marker) then return true, false end
    if not safe_parents(root, scope .. "tdlib") then return false end
    local prefix = (base:match("[^/]+$") or "") .. "-reading."
    local clean = true
    for _, name in ipairs(love.filesystem.getDirectoryItems("private")) do
        if name:sub(1, #prefix) == prefix and name:sub(#prefix + 1):match("^%d+%.json$") then
            if not remove_tree(root, "private/" .. name) then clean = false end
        end
    end
    if not remove_tree(root, scope .. "tdlib") then clean = false end
    if not remove_tree(root, scope .. "tdlib_files") then clean = false end
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
        if name:match("^conv_%d+%.png$") or name:match("^anim_animation_%d+_%a+$")
            or name:match("^anim_sticker_%d+_%a+$") or name:match("^audio_voice_%d+$")
            or name:match("^audio_audio_%d+$") or name:match("^spgram%-audio%-%d+%.ogg$")
            or name:match("^spgram%-audio%-%d+%.ogg%.cancel$")
            or name:match("^spgram%-video%-%d+%.ogv$") or name:match("^spgram%-video%-%d+%.ogv%.cancel$")
            or name:match("^spgram%-video%-%d+%.ogv%.progress$") then
            if not remove_tree(root, name) then clean = false end
        end
    end
    if not clean or not remove_tree(root, base .. ".key") then return false end
    local scope_dir = scope == "" and root or root .. "/" .. scope
    if (scope == "" or love.filesystem.getInfo(scope:sub(1, -2), "directory")) and not sync_directory(scope_dir) then return false end
    if scope ~= "" and not sync_directory(root) then return false end
    if not sync_directory(root .. "/private") or not remove_tree(root, marker) then return false end
    return sync_directory(root .. "/private"), true
end

function M.prepare(account, use_test_dc, sign_in_only)
    local scope, base = session_paths(account, use_test_dc, sign_in_only)
    local locked, reason = M.lock()
    if not locked then return nil, reason end
    local root = love.filesystem.getSaveDirectory()
    local database = scope .. "tdlib"
    local directory = root .. "/private"
    local path = root .. "/" .. base .. ".key"
    local file = io.open(path, "rb")
    local bytes
    if file then
        bytes = file:read(33)
        file:close()
        if not bytes or #bytes ~= 32 then
            return nil, "Invalid database key. Restore the matching backup. Database retained."
        end
    elseif love.filesystem.getInfo(database) or love.filesystem.getInfo(base .. ".key") then
        return nil, "Database key unavailable. Restore the key or back up the database before signing in again."
    else
        local random = io.open("/dev/urandom", "rb")
        if not random then return nil, "Cannot open the system random source." end
        bytes = random:read(32)
        random:close()
        if not bytes or #bytes ~= 32 or not persist(directory, path, bytes) then
            return nil, "Cannot create a persistent database key."
        end
    end

    for _, path_to_sync in ipairs({directory, root}) do
        if not sync_directory(path_to_sync) then return nil, "Cannot sync the key directory." end
    end
    if scope ~= "" and not love.filesystem.createDirectory(scope) then
        return nil, "Cannot create the account directory."
    end
    return {
        db = root .. "/" .. database,
        reading_position_file = base .. "-reading",
        files = root .. "/" .. scope .. "tdlib_files",
        encryption_key = love.data.encode("string", "base64", bytes),
        use_test_dc = use_test_dc,
    }
end

return M
