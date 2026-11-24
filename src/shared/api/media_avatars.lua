local preferences = require("src.shared.system.media_settings")

return function(telegram)
    local function touch(self, entry)
        self.avatar_access = (self.avatar_access or 0) + 1
        entry.last_used = self.avatar_access
    end

    local function discard(self, id, entry)
        if entry.image and entry.image.release then entry.image:release() end
        if entry.status == "downloading" then
            self:send({["@type"] = "cancelDownloadFile", file_id = id, only_if_pending = false})
        end
        self.avatar_photos[id] = nil
        if self.avatar_pending then self.avatar_pending[id] = nil end
    end

    local function recently_visible(self, frame)
        return frame and self.avatar_frame and frame >= self.avatar_frame - 1
    end

    function telegram:begin_avatar_frame()
        self.avatar_frame = (self.avatar_frame or 0) + 1
    end

    function telegram:cancel_chat_avatars(chat_id)
        for id, entry in pairs(self.avatar_photos or {}) do
            if entry.chat_id == chat_id and not entry.image and not recently_visible(self, entry.shared_frame) then
                discard(self, id, entry)
            end
        end
    end

    local function make_room(self)
        local storage = self.avatar_photos
        local count, oldest, oldest_id = 0
        for id, entry in pairs(storage) do
            count = count + 1
            if not recently_visible(self, entry.visible_frame) and (not oldest or entry.last_used < oldest.last_used) then
                oldest, oldest_id = entry, id
            end
        end
        local limit = preferences.get("small_texture_cache") and 32 or 64
        if count < limit then return true end
        if not oldest then return false end
        discard(self, oldest_id, oldest)
        return true
    end

    local function mark_visible(self, entry, chat_id)
        touch(self, entry)
        entry.visible_frame = self.avatar_frame
        if chat_id then entry.chat_id = chat_id else entry.shared_frame = self.avatar_frame end
    end

    local function ensure_avatar(self, photo, chat_id)
        if not preferences.get("profile_pictures") then return end
        local size = photo and photo.small
        local id = size and size.id
        if not id then return end
        local storage = self.avatar_photos
        local entry = storage[id]
        if entry then
            mark_visible(self, entry, chat_id)
            return entry
        end
        if not make_room(self) then return end
        entry = {status = "downloading"}
        mark_visible(self, entry, chat_id)
        storage[id] = entry
        local location = size["local"] or {}
        if location.is_downloading_completed and location.path and location.path ~= "" then
            self:load_avatar(id, location.path)
        elseif location.can_be_downloaded == false or not self:send({
            ["@type"] = "downloadFile", file_id = id, priority = 1,
            offset = 0, limit = 262145, synchronous = false,
        }, "avatar:" .. tostring(id)) then
            entry.status = "error"
        end
        return entry
    end

    function telegram:ensure_user_photo(user_id, chat_id)
        local user = user_id and self.users[user_id]
        if not user then self:ensure_user(user_id); return end
        return ensure_avatar(self, user.profile_photo, chat_id)
    end

    function telegram:user_photo_image(user_id, chat_id)
        local entry = self:ensure_user_photo(user_id, chat_id)
        if entry and entry.image then return entry.image, entry.width, entry.height end
    end

    function telegram:ensure_chat_photo(chat_id)
        local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
        return ensure_avatar(self, chat and chat.photo)
    end

    function telegram:chat_photo_image(chat_id)
        local entry = self:ensure_chat_photo(chat_id)
        if entry and entry.image then return entry.image, entry.width, entry.height end
        local chat = self.chats_by_id[chat_id] or self.archive_chats_by_id[chat_id]
        local user_id = self:private_chat_user_id(chat)
        if user_id then return self:user_photo_image(user_id) end
    end

    function telegram:load_avatar(file_id, path, converted)
        if not preferences.get("profile_pictures") then return end
        local entry = self.avatar_photos[file_id]
        if not entry or entry.image then return end
        if converted then
            self:load_image(file_id, path, self.avatar_photos, 262144, 160)
        elseif entry.failed_path ~= path and not entry.webp_job and not entry.webp_failed then
            self.avatar_pending = self.avatar_pending or {}
            self.avatar_pending[file_id] = entry
            entry.pending_path, entry.status = path, "loading"
        end
    end

    function telegram:poll_avatar_images()
        local pending = self.avatar_pending
        if not pending or not next(pending) then return end
        local newest_id, newest
        for id, entry in pairs(pending) do
            if not newest or entry.last_used > newest.last_used then newest_id, newest = id, entry end
        end
        pending[newest_id] = nil
        local path = newest.pending_path
        newest.pending_path = nil
        if not self:queue_webp_image(newest_id, path, "avatar_photos") then
            self:load_avatar(newest_id, path, true)
            if not newest.image then newest.failed_path = path end
        end
    end

    function telegram:trim_avatar_cache()
        local enabled = preferences.get("profile_pictures")
        local entries, count = {}, 0
        for id, entry in pairs(self.avatar_photos or {}) do
            if not enabled then
                discard(self, id, entry)
            else
                count = count + 1
                if not recently_visible(self, entry.visible_frame) then entries[#entries + 1] = {id = id, entry = entry} end
            end
        end
        if count <= 32 or not preferences.get("small_texture_cache") then return end
        table.sort(entries, function(a, b) return a.entry.last_used < b.entry.last_used end)
        for index = 1, math.min(#entries, count - 32) do
            local item = entries[index]
            discard(self, item.id, item.entry)
        end
    end
end
