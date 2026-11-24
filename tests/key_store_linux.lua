
local root = assert(arg[1])
local function absolute(relative)
    assert(relative == "" or relative:match("^[a-zA-Z0-9_./-]+$"))
    return root .. "/" .. relative
end

love = {
    filesystem = {
        getSaveDirectory = function() return root end,
        createDirectory = function(relative)
            return os.execute("mkdir -p -- " .. string.format("%q", absolute(relative))) == 0
        end,
        getInfo = function(relative, kind)
            local directory = os.execute("test -d " .. string.format("%q", absolute(relative))) == 0
            if kind == "directory" then return directory and {} or nil end
            if directory then return {} end
            local file = io.open(absolute(relative), "rb")
            if not file then return nil end
            file:close()
            return {}
        end,
        getDirectoryItems = function(relative)
            local stream = assert(io.popen("find " .. string.format("%q", absolute(relative)) .. " -mindepth 1 -maxdepth 1 -printf '%f\\n'"))
            local items = {}
            for item in stream:lines() do items[#items + 1] = item end
            stream:close()
            return items
        end,
    },
    data = {
        encode = function(_, format, bytes)
            assert(format == "base64" and #bytes == 32)

            return bytes
        end,
    },
}
local store = require("src.shared.api.key_store")
local first = assert(store.prepare("account_1", false))
assert(first.db == root .. "/tdlib")
assert(assert(store.prepare("account_1", false)).encryption_key == first.encryption_key)
local other = assert(store.prepare("account_2", false))
assert(other.db == root .. "/accounts/account_2/tdlib")
assert(other.encryption_key ~= first.encryption_key)
local test = assert(store.prepare("account_1", true))
assert(test.db == root .. "/test_dc/account_1/tdlib" and test.use_test_dc)
assert(test.encryption_key ~= first.encryption_key)
local file = assert(io.open(root .. "/private/production-account_1.key", "rb"))
assert(file:read("*a") == first.encryption_key)
file:close()
assert(love.filesystem.createDirectory("accounts/account_3/tdlib"))
local missing, message = store.prepare("account_3", false)
assert(not missing and message:find("key unavailable", 1, true))
assert(love.filesystem.getInfo("accounts/account_3/tdlib"))
assert(not love.filesystem.getInfo("private/production-account_3.key"))
file = assert(io.open(root .. "/private/production-account_4.key", "wb"))
file:write("invalid")
file:close()
local corrupt, error_message = store.prepare("account_4", false)
assert(not corrupt and error_message:find("Invalid database key", 1, true))
print("Key creation, persistence, isolation and recovery checks passed")

local function write(relative)
    local out = assert(io.open(absolute(relative), "wb"))
    assert(out:write("fixture"))
    assert(out:close())
end
assert(love.filesystem.createDirectory("tdlib_files/photos"))
assert(love.filesystem.createDirectory("tdlib"))
assert(love.filesystem.createDirectory("archives"))
write("tdlib/database")
write("tdlib_files/photos/attachment")
write("archives/keep")
write("private/production-account_1-reading.123456.json")
write("private/test-account_1-reading.123456.json")
write("private/production-account_2-reading.123456.json")
write("spgram-video-1.ogv.progress")
assert(os.execute("ln -s " .. string.format("%q", absolute("archives")) .. " "
    .. string.format("%q", absolute("tdlib_files/linked"))) == 0)
local clean, recovered = store.complete_logout("account_1", false, false)
assert(clean and not recovered and love.filesystem.getInfo("tdlib/database"))
assert(store.mark_logout("account_1", false, false))
clean, recovered = store.complete_logout("account_1", false, false)
assert(clean and recovered)
for _, path in ipairs({"tdlib", "tdlib_files", "private/production-account_1-reading.123456.json",
    "private/production-account_1.key", "private/production-account_1-logout", "spgram-video-1.ogv.progress"}) do
    assert(not love.filesystem.getInfo(path), path)
end
for _, path in ipairs({"archives/keep", "private/test-account_1-reading.123456.json",
    "private/production-account_2-reading.123456.json", "private/production-account_2.key", "private/test-account_1.key"}) do
    assert(love.filesystem.getInfo(path), path)
end
assert(assert(store.prepare("account_1", false)).encryption_key ~= first.encryption_key)
assert(os.execute("ln -s " .. string.format("%q", absolute("archives")) .. " "
    .. string.format("%q", absolute("test_dc/account_2"))) == 0)
assert(store.mark_logout("account_2", true, false))
assert(not store.complete_logout("account_2", true, false))
assert(love.filesystem.getInfo("archives/keep") and love.filesystem.getInfo("private/test-account_2-logout"))
print("Logout removes only scoped account files, resumes a marked cleanup, and preserves symlink targets")
