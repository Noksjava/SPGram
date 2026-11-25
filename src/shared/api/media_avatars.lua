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

    local function queue_avatar(self, id, entry, path)
        self.avatar_pending = self.avatar_pending or {}
        if not self.avatar_pending[id] then
            self.avatar_queue_order = (self.avatar_queue_order or 0) + 1
            entry.queue_order = self.avatar_queue_order
        end
        self.avatar_pending[id] = entry
        entry.pending_path, entry.status = path, "loading"
    end

    local function retry_avatar(entry, now)
        entry.status, entry.download_deadline = "error", nil
        local attempts = entry.download_attempts or 0
        if entry.downloadable and attempts < 3 then entry.retry_at = now + 3 * (attempts + 1) end
    end

    local function request_avatar(self, id, entry, now)
        entry.retry_at, entry.failed_path, entry.webp_failed = nil, nil, nil
        entry.download_attempts = (entry.download_attempts or 0) + 1
        entry.status, entry.download_deadline = "downloading", now + 20
        self.avatar_download_generation = (self.avatar_download_generation or 0) + 1
        entry.download_token = self:send({
            ["@type"] = "downloadFile", file_id = id, priority = 1,
            offset = 0, limit = 262145, synchronous = false,
        }, "avatar:" .. tostring(id) .. ":" .. tostring(self.avatar_download_generation))
        if not entry.download_token then retry_avatar(entry, now) end
    end

    function telegram:fail_avatar_download(token)
        local id = tonumber(token:match("^avatar:(%d+):%d+$"))
        if not id then return false end
        local entry = self.avatar_photos[id]
        if entry and entry.download_token == token and entry.status == "downloading" then
            retry_avatar(entry, love.timer.getTime())
        end
        return true
    end

    local function ensure_avatar(self, photo, chat_id)
        if not preferences.get("profile_pictures") then return end
        local size = photo and photo.small
        local id = size and size.id
        if not id then return end
        local storage = self.avatar_photos
        local location = size["local"] or {}
        local entry = storage[id]
        if entry then
            mark_visible(self, entry, chat_id)
            if entry.retry_at or entry.download_deadline then
                local now = love.timer.getTime()
                if entry.download_deadline and now >= entry.download_deadline then retry_avatar(entry, now) end
                if entry.retry_at and now >= entry.retry_at then
                    entry.retry_at = nil
                    queue_avatar(self, id, entry)
                end
            elseif not entry.image and entry.status == "error" and location.is_downloading_completed
                and location.path and location.path ~= "" and location.path ~= entry.failed_path then
                self:load_avatar(id, location.path)
            end
            return entry
        end
        if not make_room(self) then return end
        entry = {status = "downloading", downloadable = location.can_be_downloaded ~= false}
        mark_visible(self, entry, chat_id)
        storage[id] = entry
        if location.is_downloading_completed and location.path and location.path ~= "" then
            self:load_avatar(id, location.path)
        elseif entry.downloadable then
            request_avatar(self, id, entry, love.timer.getTime())
        else
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
            local reason = self:load_image(file_id, path, self.avatar_photos, 262144, 160)
            if entry.image then entry.download_attempts = nil end
            return reason
        elseif entry.failed_path ~= path and not entry.webp_job then
            entry.download_deadline, entry.retry_at, entry.webp_failed = nil, nil, nil
            entry.avatar_path = path
            queue_avatar(self, file_id, entry, path)
        end
    end

    function telegram:poll_avatar_images()
        local pending = self.avatar_pending
        if not pending or not next(pending) then return end
        local selected_id, selected
        for id, entry in pairs(pending) do
            if not selected or entry.queue_order < selected.queue_order then selected_id, selected = id, entry end
        end
        pending[selected_id] = nil
        local path = selected.pending_path
        selected.pending_path = nil
        if not path then
            request_avatar(self, selected_id, selected, love.timer.getTime())
        elseif not self:queue_webp_image(selected_id, path, "avatar_photos") then
            local reason = self:load_avatar(selected_id, path, true)
            if not selected.image then
                selected.failed_path = path
                if reason == "missing" or reason == "texture" then retry_avatar(selected, love.timer.getTime()) end
            end
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
