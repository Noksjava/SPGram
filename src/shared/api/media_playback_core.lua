local preferences = require("src.shared.system.media_settings")
return function(telegram)
    local function diag(self, message)
        if not self.log_path then return end
        local handle = io.open(self.log_path, "a")
        if handle then
            handle:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), message))
            handle:close()
        end
    end

    function telegram:ensure_media_decoder()
        if self.anim_worker then return true end
        self.anim_in:clear()
        self.anim_out:clear()
        self.anim_worker = love.thread.newThread("threads/anim_decode.lua")
        self.anim_worker:start()
        diag(self, "MEDIA: spawned anim_decode thread")
        return true
    end

    function telegram:media_entry(kind, file_id)
        if kind == "animation" then return self.animations[file_id] end
        if kind == "video" then return self.videos[file_id] end
        if kind == "video_note" then return self.video_notes[file_id] end
        if kind == "sticker" then return self.stickers[file_id] end
        if kind == "voice" then return self.voice_notes[file_id] end
        if kind == "audio" then return self.audios[file_id] end
        return nil
    end

    function telegram:media_file_for_message(message)
        if not message or not message.id then
            return nil, nil, nil
        end
        local content = message.content or {}
        local active = self.active_video
        local video_kind = self:video_kind(message)
        if active and active.message_id == message.id and active.chat_id == message.chat_id
            and video_kind then
            return active.kind, active.file_id, active
        end
        local kind, file_id
        local key = self:media_message_key(message)
        if video_kind == "video" then
            kind = "video"
            local file = self:choose_video_size(message)
            file_id = file and file.id
        elseif content["@type"] == "messageVideoNote" then
            kind = "video_note"
            file_id = self.video_note_by_message[key]
            if not file_id and content.video_note and content.video_note.video then
                file_id = content.video_note.video.id
                self.video_note_by_message[key] = file_id
            end
        elseif content["@type"] == "messageAnimation" then
            kind = "animation"
            file_id = self.animation_by_message[key]
            if not file_id and content.animation then
                file_id = content.animation.animation and content.animation.animation.id
                self.animation_by_message[key] = file_id
            end
        elseif content["@type"] == "messagePhoto" then
            kind = "photo"
            file_id = self.photo_by_message[key]
            if not file_id then
                local size = self:choose_photo_size(message)
                file_id = size and size.photo and size.photo.id
                self.photo_by_message[key] = file_id
            end
        elseif content["@type"] == "messageSticker" then
            kind = "sticker"
            file_id = self.sticker_by_message[key]
            if not file_id and content.sticker and content.sticker.sticker then
                file_id = content.sticker.sticker.id
                self.sticker_by_message[key] = file_id
            end
        elseif content["@type"] == "messageVoiceNote" then
            kind = "voice"
            file_id = self.voice_by_message[key]
            if not file_id and content.voice_note and content.voice_note.voice then
                file_id = content.voice_note.voice.id
                self.voice_by_message[key] = file_id
            end
        elseif content["@type"] == "messageAudio" then
            kind = "audio"
            file_id = self.audio_by_message[key]
            if not file_id and content.audio and content.audio.audio then
                file_id = content.audio.audio.id
                self.audio_by_message[key] = file_id
            end
        end
        if not kind or not file_id then
            return nil, nil, nil
        end
        local audio = self.active_audio
        if (kind == "audio" or kind == "voice") and audio and audio.message.chat_id == message.chat_id
            and audio.message.id == message.id then
            return kind, file_id, audio
        end
        local entry
        if kind == "photo" then entry = self.photos[file_id]
        elseif kind == "video" then entry = self.videos[file_id]
        elseif kind == "video_note" then entry = self.video_notes[file_id]
        elseif kind == "animation" then entry = self.animations[file_id]
        elseif kind == "sticker" then entry = self.stickers[file_id]
        elseif kind == "voice" then entry = self.voice_notes[file_id]
        elseif kind == "audio" then entry = self.audios[file_id]
        end
        return kind, file_id, entry
    end

    function telegram:queue_media_decode(kind, file_id, path, first_frame)
        local entry = self:media_entry(kind, file_id)
        if not entry or not path then return end
        if not first_frame and (kind == "animation" or kind == "sticker")
            and not preferences.get("inline_animation") and self.manual_animation_entry ~= entry then return end
        if first_frame and (entry.preview_ready or entry.preview_requested or entry.frames) then return end
        if not first_frame and (entry.decode_requested or entry.frames) then return end
        self:ensure_media_decoder()
        local safe_id = tostring(file_id):gsub("[^%w_-]", "_")
        local mode = first_frame and "preview" or "playback"
        if first_frame then
            entry.preview_requested = true
        else
            entry.decode_requested = true
        end
        entry.status = "decoding"
        diag(self, string.format("MEDIA: queue %s id=%s %s", kind, file_id, first_frame and "preview" or "playback"))
        self.anim_in:push({
            type = "decode",
            kind = kind,
            file_id = file_id,
            path = path,
            sticker_format = kind == "sticker" and self.sticker_format_by_file[file_id] or nil,
            first_frame = first_frame == true,
            duration = entry.duration,
            out_dir = love.filesystem.getSaveDirectory() .. "/anim_" .. kind .. "_" .. safe_id .. "_" .. mode,
        })
    end

    function telegram:ensure_sticker_frames(file_id, first_frame)
        local entry = self.stickers[file_id]
        if not entry or not entry.source_path or entry.decode_error then return end
        local format = self.sticker_format_by_file[file_id]
        if format == "stickerFormatWebm" or format == "stickerFormatTgs" then
            entry.autoplay = true
            self:queue_media_decode("sticker", file_id, entry.source_path, first_frame)
        end
    end

    function telegram:ensure_animated_sticker(message, explicit)
        local file = self:choose_sticker_size(message)
        if file then
            if explicit then self.manual_animation_entry = self.stickers[file.id] end
            self:ensure_sticker_frames(file.id)
        end
    end

    local function load_decoded_frame(path, name)
        local file = io.open(path, "rb")
        if not file then return nil end
        local data = file:read("*a")
        file:close()
        if not data or data == "" then return nil end
        local ok_data, file_data = pcall(love.filesystem.newFileData, data, name)
        if not ok_data or not file_data then return nil end
        local ok_image_data, image_data = pcall(love.image.newImageData, file_data)
        if type(file_data) == "userdata" then file_data:release() end
        if not ok_image_data or not image_data then return nil end
        local ok_image, image = pcall(love.graphics.newImage, image_data)
        if type(image_data) == "userdata" then image_data:release() end
        if not ok_image then return nil end
        return image
    end

    local function load_audio_source(entry, path, file_id, looping)
        if not love.audio or not love.audio.newSource then
            entry.audio_error = "Audio playback is unavailable."
            return false
        end
        local file = io.open(path, "rb")
        if not file then
            entry.audio_error = "decoded audio file is missing"
            return false
        end
        local bytes = file:read("*a")
        file:close()
        local ok_data, data = pcall(love.filesystem.newFileData, bytes, "audio_" .. tostring(file_id) .. ".wav")
        if not ok_data or not data then
            entry.audio_error = tostring(data or "could not load audio data")
            return false
        end
        local ok_source, source = pcall(love.audio.newSource, data, "static")
        if not ok_source or not source then
            entry.audio_error = tostring(source or "could not create audio source")
            return false
        end
        if looping then
            pcall(source.setLooping, source, true)
        end
        entry.audio_source = source
        entry.audio_error = nil
        if entry.autoplay then
            if (tonumber(entry.play_position) or 0) > 0 then
                pcall(source.seek, source, entry.play_position)
            end
            local ok_play, play_error = pcall(source.play, source)
            if not ok_play then
                entry.audio_error = tostring(play_error)
                entry.playing = false
                return false
            end
        end
        return true
    end

    local function release_frames(entry)
        for _, frame in ipairs(entry.frames) do
            if frame ~= entry.image and frame.release then frame:release() end
        end
        entry.frames, entry.frame_bytes, entry.playing = nil, nil, false
    end

    function telegram:trim_animation_frames(loaded)
        local cached, bytes = {}, 0
        local inline = preferences.get("inline_animation")
        for _, entries in ipairs({self.animations, self.stickers}) do
            for _, entry in pairs(entries) do
                if entry.frames and (entry.frame_bytes or not inline) then
                    if not inline and entry ~= self.manual_animation_entry then
                        release_frames(entry)
                    else
                        bytes = bytes + entry.frame_bytes
                        if entry ~= loaded and entry ~= self.manual_animation_entry
                            and (not entry.visible_frame or entry.visible_frame ~= self.avatar_frame) then
                            cached[#cached + 1] = entry
                        end
                    end
                end
            end
        end
        local budget = preferences.texture_budget(24, 6)
        if bytes <= budget then return end
        table.sort(cached, function(a, b) return (a.last_visible or 0) < (b.last_visible or 0) end)
        for _, entry in ipairs(cached) do
            bytes = bytes - entry.frame_bytes
            release_frames(entry)
            if bytes <= budget then break end
        end
    end

    function telegram:close_inline_media()
        self.manual_animation_entry = nil
        if not preferences.get("inline_animation") or preferences.get("small_texture_cache") then
            self:trim_animation_frames()
        end
    end

    function telegram:poll_media_decoder(draining)
        if not self.anim_out then return end
        local get_time = love and love.timer and love.timer.getTime or os.clock
        local deadline = get_time() + 0.003
        local uploads_left = draining and math.huge or 4
        repeat
            local result = self.pending_frame_upload or self.anim_out:pop()
            if not result then break end
            if type(result) == "table" and result.type == "converted_audio" then
                self:finish_audio_conversion(result)
            elseif type(result) == "table" and result.type == "converted_video" then
                self:finish_video_conversion(result)
            elseif type(result) == "table" and result.file_id then
                local entry = self:media_entry(result.kind, result.file_id)
                if not result.first_frame and (result.kind == "animation" or result.kind == "sticker")
                    and not preferences.get("inline_animation") and (not entry or self.manual_animation_entry ~= entry) then
                    if entry then
                        entry.decode_requested = nil
                        entry.status = entry.image and "ready" or "remote"
                    end
                    for _, frame in ipairs(result.frames or {}) do
                        if frame.release then frame:release() end
                    end
                    entry = nil
                end
                if entry then
                    if not result.paths and result.error then
                        if result.first_frame then
                            entry.preview_requested = nil
                        else
                            entry.decode_requested = nil
                        end
                        entry.status = "error"
                        entry.decode_error = result.error
                        diag(self, string.format("MEDIA: decode fail %s id=%s %s", result.kind or "?", result.file_id, tostring(result.error)))
                        if not result.first_frame and entry.autoplay and result.kind ~= "animation" and result.kind ~= "sticker" then
                            entry.autoplay = false
                            self.action_error = result.error
                            self.action_status = ""
                        end
                    end
                    if result.paths then
                        if result.first_frame then
                            entry.preview_requested = nil
                        else
                            entry.decode_requested = nil
                        end
                        if result.ok and type(result.paths) == "table" then
                            local frames = result.frames or {}
                            for index = result.next_frame or 1, #result.paths do
                                if uploads_left == 0 or (not draining and result.frames and get_time() >= deadline) then
                                    result.frames, result.next_frame = frames, index
                                    self.pending_frame_upload = result
                                    if result.first_frame then entry.preview_requested = true else entry.decode_requested = true end
                                    return
                                end
                                local image = load_decoded_frame(result.paths[index],
                                    "media_" .. tostring(result.file_id) .. "_" .. tostring(index))
                                if image then frames[#frames + 1] = image end
                                uploads_left = uploads_left - 1
                            end
                            if result.first_frame and entry.frames then
                                for _, frame in ipairs(frames) do if frame.release then frame:release() end end
                            elseif #frames > 0 then
                                entry.width = result.width or frames[1]:getWidth()
                                entry.height = result.height or frames[1]:getHeight()
                                if entry.image and entry.image ~= frames[1] and entry.image.release then entry.image:release() end
                                entry.image = frames[1]
                                if result.audio_path then
                                    load_audio_source(entry, result.audio_path, result.file_id, false)
                                elseif result.kind == "video" and not result.first_frame then
                                    entry.audio_error = "no audio track found"
                                end
                                if result.first_frame then
                                    entry.preview_ready = true
                                    entry.status = "ready"
                                    if result.kind == "sticker" or result.kind == "animation" then
                                        entry.last_visible = love.timer.getTime()
                                        self:trim_media_previews(entry)
                                    end
                                else
                                    entry.frames = frames
                                    if result.transient_dir then
                                        entry.frame_bytes = #frames * frames[1]:getWidth() * frames[1]:getHeight() * 4
                                        self:trim_animation_frames(entry)
                                        self:trim_media_previews(entry)
                                    end
                                    entry.frame_dt = result.frame_dt or (1 / 10)
                                    entry.status = "ready"
                                    entry.playing = entry.autoplay == true
                                    entry.play_origin = love.timer.getTime() - (tonumber(entry.play_position) or 0)
                                end
                            else
                                entry.status = entry.image and "ready" or "error"
                                entry.decode_error = "no decodable frames"
                            end
                        else
                            entry.status = entry.image and "ready" or "error"
                            entry.decode_error = result.error or "media decoding failed"
                            if entry.autoplay then
                                self.action_error = entry.decode_error
                                self.action_status = ""
                            end
                        end
                    end

                end
            end
            self.pending_frame_upload = nil
            if type(result) == "table" and result.transient_dir then
                for _, path in ipairs(result.paths or {}) do os.remove(path) end
                os.remove(result.transient_dir)
            end
        until not draining and get_time() >= deadline
    end
end
