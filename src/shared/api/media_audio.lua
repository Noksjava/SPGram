local AUDIO_BYTES = 128 * 1024 * 1024

local function audio_file(message)
    local content = message and message.content or {}
    if content["@type"] == "messageAudio" and content.audio then
        return content.audio.audio, content.audio, "audio"
    elseif content["@type"] == "messageVoiceNote" and content.voice_note then
        return content.voice_note.voice, content.voice_note, "voice"
    end
end

return function(telegram)
    function telegram:request_audio(message)
        if self:is_ephemeral_media(message) then return end
        local file, media, kind = audio_file(message)
        if not file or not file.id then return end
        self:release_audio()
        self:release_video()
        self.finished_audio = nil
        self.audio_sequence = (self.audio_sequence or 0) + 1
        local entry = {file_id = file.id, kind = kind, message = message,
            name = "spgram-audio-" .. tostring(self.audio_sequence) .. ".ogg",
            download_token = "audio_download:" .. tostring(self.audio_sequence),
            duration = math.max(0, tonumber(media.duration) or 0), status = "downloading",
            total_bytes = math.max(tonumber(file.size) or 0, tonumber(file.expected_size) or 0),
            autoplay = true}
        self.active_audio = entry
        if entry.total_bytes > AUDIO_BYTES then
            entry.status, entry.audio_error = "error", "This audio exceeds the 128 MB temporary storage limit."
        else
            entry.requested = true
            self:send({["@type"] = "downloadFile", file_id = file.id, priority = 32,
                offset = 0, limit = AUDIO_BYTES + 1, synchronous = false}, entry.download_token)
        end
        return entry
    end

    function telegram:release_audio()
        local entry = self.active_audio
        if not entry then return end
        self.active_audio = nil
        if entry.audio_source then
            entry.audio_source:stop()
            entry.audio_source:release()
        end
        if entry.status == "decoding" then love.filesystem.write(entry.name .. ".cancel", "cancel") end
        if entry.name then love.filesystem.remove(entry.name) end
        if entry.requested then
            self:send({["@type"] = "cancelDownloadFile", file_id = entry.file_id, only_if_pending = false})
            self:send({["@type"] = "deleteFile", file_id = entry.file_id})
        end
    end

    local function stream_audio(entry, path)
        if not love.audio or not love.audio.newSource then return false end
        local ok, source = pcall(love.audio.newSource, path, "stream")
        if not ok or not source then return false end
        local played, started = pcall(source.play, source)
        if not played or started == false then
            source:release()
            return false
        end
        entry.audio_source, entry.status, entry.playing = source, "ready", true
        return true
    end

    function telegram:handle_audio_file(file, entry)
        if entry.status ~= "downloading" then return end
        local data = file["local"] or {}
        entry.total_bytes = math.max(entry.total_bytes, tonumber(file.size) or 0, tonumber(file.expected_size) or 0)
        entry.downloaded_bytes = math.max(entry.downloaded_bytes or 0, tonumber(data.downloaded_size) or 0)
        if entry.total_bytes > AUDIO_BYTES or entry.downloaded_bytes > AUDIO_BYTES then
            local message = entry.message
            self:release_audio()
            self.active_audio = {message = message, file_id = entry.file_id, kind = entry.kind,
                status = "error", audio_error = "This audio exceeds the 128 MB temporary storage limit."}
        elseif data.is_downloading_completed and data.path and data.path ~= "" then
            local root = love.filesystem.getSaveDirectory():gsub("\\", "/") .. "/"
            local path = data.path:gsub("\\", "/")
            if path:sub(1, #root) == root and stream_audio(entry, path:sub(#root + 1)) then return end
            self:ensure_media_decoder()
            entry.status = "decoding"
            self:submit_media_job({type = "convert_audio", name = entry.name,
                path = data.path, output = root .. entry.name}, true)
        elseif data.can_be_downloaded == false and not data.is_downloading_active then
            entry.status, entry.audio_error = "error", "Telegram could not download this audio."
        end
    end

    function telegram:finish_audio_conversion(result)
        love.filesystem.remove(result.name .. ".cancel")
        local entry = self.active_audio
        if not entry or entry.name ~= result.name then
            love.filesystem.remove(result.name)
            return
        end
        if not result.ok or not stream_audio(entry, result.name) then
            entry.status, entry.audio_error = "error", result.error or "This audio could not be played."
            love.filesystem.remove(result.name)
        end
    end

    function telegram:poll_audio_end()
        local entry = self.active_audio
        if entry and entry.playing and entry.audio_source and not entry.audio_source:isPlaying() then
            self.finished_audio = entry.message
            self:release_audio()
        end
    end

    function telegram:clear_stale_audio()
        for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
            if name:match("^spgram%-audio%-%d+%.ogg$") or name:match("^spgram%-audio%-%d+%.ogg%.cancel$") then
                love.filesystem.remove(name)
            elseif name:match("^audio_voice_%d+$") or name:match("^audio_audio_%d+$") then
                love.filesystem.remove(name .. "/audio.wav")
                love.filesystem.remove(name)
            end
        end
        self:send({["@type"] = "optimizeStorage", size = 0, ttl = 0, count = 0, immunity_delay = 0,
            file_types = {{["@type"] = "fileTypeAudio"}, {["@type"] = "fileTypeVoiceNote"}}, chat_limit = 0})
    end
end
