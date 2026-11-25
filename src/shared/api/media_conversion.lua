local preferences = require("src.shared.system.media_settings")

return function(telegram)
    local next_convert_idx = 0

    local function detect_format(input_path)
        local f = io.open(input_path, "rb")
        if not f then
            return nil
        end
        local head = f:read(16)
        f:close()
        if not head then
            return nil
        end
        if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WEBP" then
            return "webp"
        end
        if head:sub(1, 6) == "GIF87a" or head:sub(1, 6) == "GIF89a" then
            return "gif"
        end
        if head:sub(1, 8) == "\137PNG\r\n\026\n" then
            return "png"
        end
        if head:sub(1, 2) == "\255\216" then
            return "jpeg"
        end
        if head:sub(5, 8) == "ftyp" then
            return "video"
        end
        if head:sub(1, 4) == "\026\069\223\163" then
            return "video"
        end
        if head:sub(1, 2) == "\031\139" then
            return "tgs"
        end
        return "unknown"
    end

    function telegram:detect_media_format(path)
        return detect_format(path)
    end

    function telegram:load_image(file_id, path, storage, max_bytes, max_edge)
        local entry = storage[file_id]
        if not entry or entry.image then
            return
        end
        local input = io.open(path, "rb")
        if not input then
            entry.status = "error"
            return "missing"
        end
        local data = input:read(max_bytes and max_bytes + 1 or "*a")
        input:close()
        if not data or data == "" then
            entry.status = "error"
            return "missing"
        end
        if max_bytes and #data > max_bytes then
            entry.status = "error"
            return
        end
        local ok, file_data = pcall(love.filesystem.newFileData, data, "file_" .. tostring(file_id))
        if not ok or not file_data then
            entry.status = "error"
            return
        end
        local ok2, image_data = pcall(love.image.newImageData, file_data)
        if type(file_data) == "userdata" then file_data:release() end
        if not ok2 or not image_data then
            entry.status = "error"
            return
        end
        if max_edge and math.max(image_data:getWidth(), image_data:getHeight()) > max_edge then
            if image_data.release then image_data:release() end
            entry.status = "error"
            return
        end
        local ok3, image = pcall(love.graphics.newImage, image_data)
        if type(image_data) == "userdata" then image_data:release() end
        if not ok3 or not image then
            entry.status = "error"
            return "texture"
        end
        entry.image = image
        entry.width = image:getWidth()
        entry.height = image:getHeight()
        entry.status = "ready"
        if storage == self.stickers or storage == self.animations then
            entry.last_visible = love.timer.getTime()
            self:trim_media_previews(entry)
        end
    end

    function telegram:queue_webp_image(file_id, path, storage_name)
        local entry = self[storage_name][file_id]
        if not entry or entry.image then return false end
        if entry.webp_job or entry.webp_failed then return true end
        if detect_format(path) ~= "webp" then return false end
        local queue = self.webp_queue or {}
        self.webp_queue = queue
        next_convert_idx = next_convert_idx + 1
        local output = love.filesystem.getSaveDirectory() .. "/conv_" .. next_convert_idx .. ".png"
        local job = {type = "convert_webp", path = path, output = output,
            file_id = file_id, storage = storage_name}
        entry.webp_job, entry.status = output, "loading"
        if #queue >= 48 then
            local old = table.remove(queue, 1)
            local storage = self[old.storage]
            if storage[old.file_id] and storage[old.file_id].webp_job == old.output then storage[old.file_id] = nil end
        end
        queue[#queue + 1] = job
        return true
    end

    function telegram:dispatch_webp_image()
        if self.webp_active or not self.webp_queue then return end
        local job, entry
        repeat
            job = table.remove(self.webp_queue)
            if not job then return end
            entry = self[job.storage][job.file_id]
        until entry and entry.webp_job == job.output
        if not self.thumbnail_worker then
            self.thumbnail_in:clear()
            self.thumbnail_out:clear()
            self.thumbnail_worker = love.thread.newThread("threads/anim_decode.lua")
            self.thumbnail_worker:start("thumbnail")
        end
        self.webp_active = job.output
        self.thumbnail_job = job
        self.thumbnail_in:push(job)
    end

    function telegram:poll_thumbnail_worker()
        if not self.thumbnail_out then return end
        local result = self.thumbnail_out:pop()
        if result then self:finish_webp_image(result) end
        if self.thumbnail_worker and not self.thumbnail_worker:isRunning() then
            if self.thumbnail_job then self:finish_webp_image(self.thumbnail_job) end
            self.thumbnail_worker = nil
        end
    end

    function telegram:finish_webp_image(result)
        if self.webp_active == result.output then self.webp_active, self.thumbnail_job = nil, nil end
        local storage = self[result.storage]
        local entry = storage and storage[result.file_id]
        if entry and entry.webp_job == result.output then
            if result.ok then
                if result.storage == "photos" then
                    self:load_photo(result.file_id, result.output, true)
                elseif result.storage == "avatar_photos" then
                    self:load_avatar(result.file_id, result.output, true)
                else
                    self:load_image(result.file_id, result.output, storage)
                end
            end
            entry.webp_job = nil
            entry.webp_failed = not entry.image
            if entry.webp_failed then
                entry.status = "error"
                if storage == self.avatar_photos then entry.failed_path = entry.avatar_path end
            end
        end
        os.remove(result.output)
    end

    function telegram:load_photo(file_id, path, converted)
        local existing = self.photos[file_id]
        if not existing or existing.image then return end
        if not converted and existing.thumbnail and self:queue_webp_image(file_id, path, "photos") then return end
        local max_bytes = existing.thumbnail and 512 * 1024 or 16 * 1024 * 1024
        self:load_image(file_id, path, self.photos, max_bytes, existing.thumbnail and 384 or 1280)
        local entry = self.photos[file_id]
        if not entry or not entry.image then return end
        entry.last_used = love.timer.getTime()
        self:trim_photo_cache(entry.thumbnail == true, entry)
    end

    function telegram:trim_photo_cache(thumbnail, loaded, apply_settings)
        local images, bytes, count = {}, 0, 0
        for id, photo in pairs(self.photos) do
            if (photo.thumbnail == true) == thumbnail then
                local discard = apply_settings and ((not thumbnail and not preferences.get("autoplay_images")
                    and (not photo.explicit_frame or photo.explicit_frame ~= self.avatar_frame))
                    or (photo.video_preview and not preferences.get("video_thumbnails")))
                if discard then
                    if photo.image and photo.image.release then photo.image:release() end
                    if photo.status == "downloading" then
                        self:send({["@type"] = "cancelDownloadFile", file_id = id, only_if_pending = false})
                    end
                    self.photos[id] = nil
                elseif photo.image then
                    count = count + 1
                    bytes = bytes + photo.width * photo.height * 4
                    if photo ~= loaded and (not photo.visible_frame or photo.visible_frame ~= self.avatar_frame) then
                        images[#images + 1] = {id = id, last_used = photo.last_used or 0}
                    end
                end
            end
        end
        local small = preferences.get("small_texture_cache")
        local limit = thumbnail and (small and 24 or 64) or (small and 8 or 24)
        local budget = thumbnail and preferences.texture_budget(6, 2) or preferences.texture_budget(24, 8)
        if count <= limit and bytes <= budget then return end
        table.sort(images, function(a, b) return a.last_used < b.last_used end)
        for _, candidate in ipairs(images) do
            if count <= limit and bytes <= budget then break end
            local old = self.photos[candidate.id]
            bytes = bytes - old.width * old.height * 4
            count = count - 1
            if old.image.release then old.image:release() end
            self.photos[candidate.id] = nil
        end
    end

    function telegram:trim_media_previews(loaded)
        local previews, bytes = {}, 0
        for _, storage in ipairs({self.stickers, self.animations}) do
            for _, entry in pairs(storage) do
                if entry.image and not entry.frames then
                    bytes = bytes + entry.width * entry.height * 4
                    if entry ~= loaded and entry ~= self.manual_animation_entry
                        and (not entry.visible_frame or entry.visible_frame ~= self.avatar_frame) then
                        previews[#previews + 1] = entry
                    end
                end
            end
        end
        local limit = preferences.texture_budget(6, 2)
        if bytes <= limit then return end
        table.sort(previews, function(a, b) return (a.last_visible or 0) < (b.last_visible or 0) end)
        for _, entry in ipairs(previews) do
            bytes = bytes - entry.width * entry.height * 4
            if entry.image.release then entry.image:release() end
            entry.image, entry.preview_ready = nil, nil
            if bytes <= limit then break end
        end
    end

    function telegram:apply_memory_settings()
        self:trim_avatar_cache()
        self:trim_photo_cache(false, nil, true)
        self:trim_photo_cache(true, nil, true)
        self:trim_animation_frames()
        self:trim_media_previews()
        local cache = self.video_minithumbnails
        if cache then
            local limit = not preferences.get("video_thumbnails") and 0
                or preferences.get("small_texture_cache") and 8 or 16
            while #cache.order > limit do
                local key = table.remove(cache.order, 1)
                local image = cache.images[key]
                if image and image.release then image:release() end
                cache.images[key] = nil
            end
        end
    end
end
