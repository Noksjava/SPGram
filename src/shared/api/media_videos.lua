local preferences = require("src.shared.system.media_settings")
local ANIMATION_BYTES = 16 * 1024 * 1024
local VIDEO_THUMBNAIL_BYTES = 256 * 1024
local VIDEO_BYTES = 256 * 1024 * 1024
local VIDEO_LIMIT_ERROR = "The video download exceeds the 256 MB temporary storage limit."
local video_extensions = {
    mp4 = true, m4v = true, mov = true, mkv = true, webm = true, avi = true,
    mpg = true, mpeg = true, m2v = true, ts = true, mts = true, m2ts = true, vob = true,
    wmv = true, asf = true, flv = true, ogv = true, dv = true, ["3gp"] = true, ["3g2"] = true,
}

local function video_document(content)
    local document = content["@type"] == "messageDocument" and content.document
    if not document or not document.document or not document.document.id then return end
    local extension = (document.file_name or ""):lower():match("%.([%w]+)$")
    local mime = (document.mime_type or ""):lower()
    if extension == "m3u" or extension == "m3u8" or extension == "mpd" or mime:find("mpegurl", 1, true) then return end
    if extension == "ts" and (mime:match("^text/") or mime == "application/typescript") then return end
    if video_extensions[extension] or mime:match("^video/") then return document end
end

local function remove_video_signals(name)
    love.filesystem.remove(name .. ".cancel")
    love.filesystem.remove(name .. ".progress")
end

local function file_size(file)
    return math.max(tonumber(file.size) or 0, tonumber(file.expected_size) or 0)
end

return function(telegram)
    local function diag(message)
        local handle = io.open("log.txt", "a")
        if handle then
            handle:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
            handle:close()
        end
    end

    local function request_preview(self, kind, storage_name, owner_file_id, obj)
        if self.media_preview_by_file == nil then
            self.media_preview_by_file = {}
        end
        local thumbnail = obj and obj.thumbnail
        local thumb_file = thumbnail and (thumbnail.file or (thumbnail.photo and thumbnail.photo.file) or thumbnail.photo)
        if not thumb_file or not thumb_file.id then
            diag("PREVIEW: no thumb kind=" .. kind .. " owner=" .. tostring(owner_file_id))
            return false
        end
        local thumb_id = tonumber(thumb_file.id)
        if self.media_preview_by_file[thumb_id] then return true end
        local l = thumb_file["local"] or {}
        if l.is_downloading_completed and l.path and l.path ~= "" then
            if kind == "animation" then self:load_animation_preview(owner_file_id, l.path)
            else self:load_image(owner_file_id, l.path, self[storage_name]) end
            diag("PREVIEW: loaded inline kind=" .. kind .. " owner=" .. tostring(owner_file_id))
            return true
        end
        self.media_preview_by_file[thumb_id] = {kind = kind, owner = owner_file_id, storage = storage_name}
        diag("PREVIEW: request kind=" .. kind .. " owner=" .. tostring(owner_file_id) ..
            " thumb=" .. tostring(thumb_id))
        self:send({
            ["@type"] = "downloadFile",
            file_id = thumb_id,
            priority = 16,
            offset = 0,
            limit = 0,
            synchronous = false,
        }, "thumb:" .. kind .. ":" .. tostring(thumb_id))
        return true
    end

    function telegram:video_kind(message)
        local content = message and message.content or {}
        if content["@type"] == "messageVideoNote" then return "video_note" end
        if content["@type"] == "messageVideo" or video_document(content) then return "video" end
    end

    function telegram:video_thumbnail(message)
        if not preferences.get("video_thumbnails") or self:is_ephemeral_media(message) then return end
        local kind = self:video_kind(message)
        if not kind then return end
        local content = message.content
        return self:media_thumbnail(content[kind] or video_document(content), true)
    end

    function telegram:media_thumbnail(media, video_preview, measure)
        if not media then return end
        local thumbnail = media.thumbnail
        local format = thumbnail and thumbnail.format and thumbnail.format["@type"]
        local file = thumbnail and thumbnail.file
        if file and file.id and (not format or format == "thumbnailFormatJpeg" or format == "thumbnailFormatPng" or format == "thumbnailFormatWebp")
            and (tonumber(thumbnail.width) or 0) <= 384 and (tonumber(thumbnail.height) or 0) <= 384
            and file_size(file) <= VIDEO_THUMBNAIL_BYTES then
            local entry = self.photos[file.id]
            if not entry and not measure then
                local location = file["local"] or {}
                if location.is_downloading_completed and location.path and location.path ~= "" then
                    entry = {status = "loading", thumbnail = true, video_preview = video_preview}
                    self.photos[file.id] = entry
                    self:load_photo(file.id, location.path)
                elseif location.can_be_downloaded ~= false then
                    entry = {status = "downloading", thumbnail = true, video_preview = video_preview}
                    self.photos[file.id] = entry
                    self:send({["@type"] = "downloadFile", file_id = file.id, priority = 1,
                        offset = 0, limit = VIDEO_THUMBNAIL_BYTES + 1, synchronous = false}, "photo:" .. tostring(file.id))
                end
            end
            if entry and entry.image then
                if not measure then
                    entry.last_used = love.timer.getTime()
                    entry.visible_frame = self.avatar_frame
                end
                return entry.image
            end
        end

        local mini = media.minithumbnail and media.minithumbnail.data
        if type(mini) ~= "string" or mini == "" or #mini > 16384 then return end
        local cache = self.video_minithumbnails
        if measure then return cache and cache.images[mini] or nil end
        if not cache then
            cache = {images = {}, order = {}}
            self.video_minithumbnails = cache
        end
        if cache.images[mini] ~= nil then return cache.images[mini] or nil end
        local ok, image = pcall(function()
            local bytes = love.data.decode("string", "base64", mini)
            local data = love.filesystem.newFileData(bytes, "video-preview.jpg")
            return love.graphics.newImage(love.image.newImageData(data))
        end)
        local limit = preferences.get("small_texture_cache") and 8 or 16
        while #cache.order >= limit do
            local key = table.remove(cache.order, 1)
            local old = cache.images[key]
            if old and old.release then old:release() end
            cache.images[key] = nil
        end
        cache.order[#cache.order + 1] = mini
        cache.images[mini] = ok and image or false
        if ok then return image end
    end

    function telegram:choose_video_size(message)
        local content = message and message.content
        if not content then return end
        local document = video_document(content)
        if document then return document.document end
        if content["@type"] ~= "messageVideo" then return end
        local original = content.video and content.video.video
        if not original or not original.id then return nil end
        local choice, size = original, file_size(original)
        for _, rendition in ipairs(content.alternative_videos or {}) do
            local file = rendition.video
            local short_edge = math.min(tonumber(rendition.width) or 0, tonumber(rendition.height) or 0)
            local bytes = file and file_size(file) or 0
            if rendition.codec == "h264" and file and file.id and short_edge > 0 and short_edge <= 480
                and bytes > 0 and (size == 0 or bytes < size) then
                choice, size = file, bytes
            end
        end
        return choice
    end

    function telegram:choose_animation_size(message)
        local content = message and message.content
        if not content or content["@type"] ~= "messageAnimation" then
            return nil
        end

        local animation = content.animation and content.animation.animation
        if not animation or not animation.id then return nil end
        return animation
    end

    function telegram:request_video(message)
        if self:is_ephemeral_media(message) then return end
        local content = message.content or {}
        local kind = self:video_kind(message)
        if not kind then return end
        local document = video_document(content)
        local media = document or content[kind]
        local original = document and document.document or (media and media.video)
        if not original or not original.id then return nil end
        local active = self.active_video
        local same_message = active and active.message_id == message.id and active.chat_id == message.chat_id
        if same_message and active.status ~= "error" then return active end
        local file = (kind == "video" and not same_message and self:choose_video_size(message)) or original
        self:release_video()
        local storage = kind == "video" and self.videos or self.video_notes
        local entry = {
            file_id = file.id, kind = kind, storage = storage,
            message_id = message.id, chat_id = message.chat_id,
            duration = math.max(0, tonumber(media.duration) or 0),
            total_bytes = file_size(file),
            autoplay = true, status = "downloading",
        }
        storage[file.id], self.active_video = entry, entry
        if os.getenv("SPGRAM_NO_FFMPEG") == "1" then
            entry.status, entry.decode_error = "error", "Video playback requires FFmpeg on this device."
        elseif file_size(file) > VIDEO_BYTES then
            entry.status, entry.decode_error = "error", VIDEO_LIMIT_ERROR
        else
            entry.requested = true
            self.video_request_sequence = (self.video_request_sequence or 0) + 1
            entry.download_token = "video_download:" .. tostring(self.video_request_sequence)
            self:send({
                ["@type"] = "downloadFile", file_id = file.id, priority = 32,
                offset = 0, limit = VIDEO_BYTES + 1, synchronous = false,
            }, entry.download_token)
        end
        return entry
    end

    function telegram:release_video()
        local entry = self.active_video
        if not entry then return end
        self.active_video = nil
        self.now_playing = nil
        entry.storage[entry.file_id] = nil
        if entry.video then
            entry.video:pause()
            entry.video:release()
        end
        if entry.status == "decoding" then love.filesystem.write(entry.name .. ".cancel", "cancel") end
        if entry.name then love.filesystem.remove(entry.name) end
        if entry.requested or entry.source_path then
            self:send({["@type"] = "cancelDownloadFile", file_id = entry.file_id, only_if_pending = false})
            self:send({["@type"] = "deleteFile", file_id = entry.file_id})
        end
    end

    function telegram:handle_video_file(file, entry)
        if entry.status ~= "downloading" then return end
        local local_file = file["local"] or {}
        entry.total_bytes = file_size(file)
        entry.downloaded_bytes = tonumber(local_file.downloaded_size) or 0
        if math.max(entry.total_bytes, entry.downloaded_bytes) > VIDEO_BYTES then
            self:send({["@type"] = "cancelDownloadFile", file_id = file.id, only_if_pending = false})
            self:send({["@type"] = "deleteFile", file_id = file.id})
            entry.requested = nil
            entry.status, entry.decode_error = "error", VIDEO_LIMIT_ERROR
        elseif local_file.is_downloading_completed and local_file.path and local_file.path ~= "" then
            self:load_video(file.id, local_file.path)
        elseif local_file.can_be_downloaded == false and not local_file.is_downloading_active then
            entry.status, entry.decode_error = "error", "Telegram could not provide this video. Try again."
        end
    end

    function telegram:load_video(file_id, path)
        local entry = self.active_video
        if not entry or entry.file_id ~= file_id or entry.status ~= "downloading" then return end
        entry.source_path = path
        local file = io.open(path, "rb")
        local size = file and file:seek("end") or 0
        if file then file:close() end
        if size <= 0 or size > VIDEO_BYTES then
            entry.status, entry.decode_error = "error", "Video is missing or exceeds the playback limit."
            return
        end
        self:ensure_media_decoder()
        self.video_sequence = (self.video_sequence or 0) + 1
        entry.name = "spgram-video-" .. tostring(self.video_sequence) .. ".ogv"
        local output = love.filesystem.getSaveDirectory() .. "/" .. entry.name
        entry.progress_path = output .. ".progress"
        entry.status = "decoding"
        self.anim_in:push({type = "convert_video", path = path, name = entry.name,
            output = output})
    end

    function telegram:poll_video_progress(now)
        local entry = self.active_video
        if not entry or entry.status ~= "decoding" or not entry.progress_path
            or now < (entry.next_progress_read or 0) then return end
        entry.next_progress_read = now + 1
        local file = io.open(entry.progress_path, "rb")
        if not file then return end
        local length = file:seek("end") or 0
        file:seek("set", math.max(0, length - 1024))
        local tail = file:read("*a")
        file:close()
        for microseconds in (tail or ""):gmatch("\nout_time_us=(%d+)\r?\n") do
            entry.converted_seconds = math.max(entry.converted_seconds or 0, tonumber(microseconds) / 1000000)
        end
    end

    function telegram:finish_video_conversion(result)
        local entry = self.active_video
        if entry and entry.name == result.name and result.ok then
            self:poll_video_progress(math.huge)
            if entry.duration == 0 then entry.duration = entry.converted_seconds or 0 end
        end
        remove_video_signals(result.name)
        if not entry or entry.name ~= result.name then
            love.filesystem.remove(result.name)
            return
        end
        if result.ok then
            local ok, video = pcall(love.graphics.newVideo, result.name)
            if ok then
                entry.video, entry.status = video, "ready"
                if entry.autoplay then video:play() end
                return
            end
        end
        entry.status = "error"
        entry.decode_error = result.error or "Could not open the converted video."
    end

    function telegram:load_animation_preview(file_id, path)
        local entry = self.animations[file_id]
        if not entry then return end
        local status = entry.status
        self:load_image(file_id, path, self.animations)
        entry.status = status
    end

    function telegram:animation_thumbnail(animation)
        local file = animation and animation.animation
        if not file or not file.id then return end
        local entry = self.animations[file.id]
        if not entry then
            entry = {status = "remote", autoplay = true, duration = tonumber(animation.duration)}
            self.animations[file.id] = entry
            request_preview(self, "animation", "animations", file.id, animation)
        end
        return entry
    end

    function telegram:ensure_animation(message, retry, explicit)
        local animation = self:choose_animation_size(message)
        if not animation then return end
        local file_id = animation.id
        if message.id then self.animation_by_message[self:media_message_key(message)] = file_id end
        local entry = self:animation_thumbnail(message.content.animation)
        if explicit then self.manual_animation_entry = entry end
        entry.last_visible = love.timer.getTime()
        if not explicit and not preferences.get("inline_animation") then return entry end
        if retry and entry.status == "error" then
            entry.status, entry.decode_error, entry.autoplay = "remote", nil, true
        end
        if entry.status == "error" or entry.frames or entry.decode_requested or entry.download_requested then return entry end
        if file_size(animation) > ANIMATION_BYTES then
            entry.status, entry.decode_error = "error", "This GIF exceeds the 16 MB animation limit."
            return entry
        end
        local local_file = animation["local"] or {}
        if not entry.source_path and local_file.is_downloading_completed and local_file.path and local_file.path ~= "" then
            entry.source_path = local_file.path
        end
        if entry.source_path then
            self:queue_media_decode("animation", file_id, entry.source_path)
        else
            self:download_animation(file_id, entry)
        end
        return entry
    end

    function telegram:download_animation(file_id, entry)
        entry.status = "downloading"
        entry.download_requested = self:send({
            ["@type"] = "downloadFile", file_id = file_id, priority = 2,
            offset = 0, limit = ANIMATION_BYTES + 1, synchronous = false,
        }, "animation:" .. tostring(file_id))
    end

    function telegram:handle_animation_file(file, entry)
        local local_file = file["local"] or {}
        if math.max(file_size(file), tonumber(local_file.downloaded_size) or 0) > ANIMATION_BYTES then
            if entry.download_requested then
                self:send({["@type"] = "cancelDownloadFile", file_id = file.id, only_if_pending = false})
                self:send({["@type"] = "deleteFile", file_id = file.id})
            end
            entry.download_requested, entry.source_path = nil, nil
            entry.status, entry.decode_error = "error", "This GIF exceeds the 16 MB animation limit."
            return
        end
        if entry.status == "error" then return end
        if local_file.is_downloading_completed and local_file.path and local_file.path ~= "" then
            entry.download_requested = nil
            entry.source_path = local_file.path
            if self.manual_animation_entry == entry
                or (preferences.get("inline_animation") and entry.last_visible and love.timer.getTime() - entry.last_visible < 1) then
                self:queue_media_decode("animation", file.id, local_file.path)
            end
        elseif local_file.can_be_downloaded == false and not local_file.is_downloading_active then
            entry.download_requested = nil
            entry.status, entry.decode_error = "error", "Telegram could not provide this GIF. Open it to retry."
        end
    end

    function telegram:video_image(message)
        local kind, _, entry = self:media_file_for_message(message)
        local video = (kind == "video" or kind == "video_note") and entry and entry.video
        if video then return video, video:getWidth(), video:getHeight() end
    end

    telegram.video_note_image = telegram.video_image

    function telegram:animation_frame(entry, measure)
        if not entry then return end
        local image = entry.image or (entry.frames and entry.frames[1])
        local now = not measure and love.timer.getTime()
        if now and image then entry.last_visible, entry.visible_frame = now, self.avatar_frame end
        if now and (preferences.get("inline_animation") or self.manual_animation_entry == entry)
            and entry.frames and #entry.frames > 0 then
            local step = math.max(0.03, entry.frame_dt or (1 / 10))
            local index = math.floor(math.max(0, now - (entry.play_origin or now)) / step) % #entry.frames + 1
            image = entry.frames[index]
        end
        if image then return image, entry.width or image:getWidth(), entry.height or image:getHeight() end
    end

    function telegram:animation_image(message, measure)
        local file_id = self.animation_by_message[self:media_message_key(message)]
        return self:animation_frame(file_id and self.animations[file_id], measure)
    end
end
