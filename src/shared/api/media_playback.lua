

return function(telegram)
    function telegram:request_media_playback(message)
        if self:video_kind(message) then
            self:release_audio()
            local entry = self:request_video(message)
            if not entry then return false end
            self.now_playing = message
            entry.autoplay = true
            if entry.video then
                if entry.duration > 0 and entry.video:tell() >= entry.duration - 0.15 then
                    self:seek_media_playback(message, 0)
                else
                    entry.video:play()
                end
            end
            return entry.status ~= "error"
        end
        local content = message and message.content
        if content and content["@type"] == "messageAnimation" then
            return self:ensure_animation(message, true) ~= nil
        end
        local kind, _, entry = self:media_file_for_message(message)
        if kind == "sticker" then
            self:ensure_sticker(message)
            self:ensure_animated_sticker(message)
            return true
        end
        if kind ~= "audio" and kind ~= "voice" then return false end
        if entry and entry.status ~= "error" then
            if entry.paused then return self:resume_media_playback(message) end
            return true
        end
        return self:request_audio(message) ~= nil
    end

    function telegram:media_playback_state(message)
        local kind, _, entry = self:media_file_for_message(message)
        if not kind or not entry then return 0, 0, false end
        if entry.video then
            local playing = entry.video:isPlaying()
            if entry.seek_target ~= nil then playing = entry.autoplay end
            return entry.seek_target or entry.video:tell(), entry.duration,
                playing
        end
        local content = message.content or {}
        local duration = tonumber(entry.duration)
        if not duration then
            if content["@type"] == "messageVideo" then
                duration = tonumber(content.video and content.video.duration)
            elseif content["@type"] == "messageVideoNote" then
                duration = tonumber(content.video_note and content.video_note.duration)
            elseif content["@type"] == "messageAnimation" then
                duration = tonumber(content.animation and content.animation.duration)
            elseif content["@type"] == "messageVoiceNote" then
                duration = tonumber(content.voice_note and content.voice_note.duration)
            elseif content["@type"] == "messageAudio" then
                duration = tonumber(content.audio and content.audio.duration)
            end
        end
        if (kind == "video" or kind == "audio" or kind == "voice") and entry.audio_source then
            local ok, source_duration = pcall(entry.audio_source.getDuration, entry.audio_source, "seconds")
            if ok and tonumber(source_duration) and source_duration > 0 then duration = tonumber(source_duration) end
        elseif (kind == "video" or kind == "sticker" or kind == "animation") and entry.frames and #entry.frames > 0 then
            duration = #entry.frames * (entry.frame_dt or (1 / 10))
        end
        duration = math.max(0, duration or 0)

        local position = tonumber(entry.play_position) or 0
        if entry.audio_source then
            local ok, source_position = pcall(entry.audio_source.tell, entry.audio_source, "seconds")
            if ok and tonumber(source_position) then position = tonumber(source_position) end
        elseif entry.playing then
            position = math.max(0, love.timer.getTime() - (entry.play_origin or love.timer.getTime()))
        end
        if (kind == "sticker" or kind == "animation") and entry.playing and duration > 0 then
            position = position % duration
        end
        position = math.min(duration > 0 and duration or position, math.max(0, position))
        entry.play_position = position
        return position, duration, entry.playing == true
    end

    function telegram:pause_media_playback(message)
        local kind, _, entry = self:media_file_for_message(message)
        if kind == "animation" or kind == "sticker" then return false end
        if not kind or not entry then return false end
        if entry.video then
            entry.autoplay = false
            entry.video:pause()
            return true
        end
        local position = self:media_playback_state(message)
        entry.play_position = position
        entry.playing = false
        entry.paused = true
        entry.autoplay = false
        if entry.audio_source then
            pcall(entry.audio_source.pause, entry.audio_source)
        end
        return true
    end

    function telegram:resume_media_playback(message)
        local kind, _, entry = self:media_file_for_message(message)
        if kind == "animation" or kind == "sticker" then return false end
        if not kind or not entry then return false end
        if entry.video and entry.seek_target then
            entry.autoplay = true
            return true
        end
        if entry.video or not entry.frames and not entry.audio_source then
            return self:request_media_playback(message)
        end
        local position = self:media_playback_state(message)
        entry.play_position = position
        entry.playing = true
        entry.paused = false
        entry.play_origin = love.timer.getTime() - position
        if entry.audio_source then
            local ok, err = pcall(function()
                entry.audio_source:seek(position)
                entry.audio_source:play()
            end)
            if not ok then
                entry.playing = false
                entry.audio_error = tostring(err)
                return false
            end
        end
        return true
    end

    function telegram:seek_media_playback(message, position)
        local kind, _, entry = self:media_file_for_message(message)
        if kind == "animation" or kind == "sticker" then return false end
        if not kind or not entry then return false end
        local _, duration = self:media_playback_state(message)
        position = math.max(0, tonumber(position) or 0)
        if duration > 0 then position = math.min(duration, position) end
        if entry.video then
            if duration <= 0 and position > 0 then return false end
            position = math.min(math.max(0, duration - 0.35), position)
            if entry.seek_target == position then return true end
            entry.seek_target = position
            entry.seek_at = love.timer.getTime() + 0.14
            return true
        end
        entry.play_position = position
        entry.play_origin = love.timer.getTime() - position
        if entry.audio_source then
            local ok, err = pcall(entry.audio_source.seek, entry.audio_source, position)
            if not ok then
                entry.audio_error = tostring(err)
                return false
            end
        end
        return true
    end

    function telegram:poll_video_seek(now)
        local entry = self.active_video
        if not entry or not entry.video or not entry.seek_at or now < entry.seek_at then return end
        local target, video = entry.seek_target, entry.video
        entry.seek_target, entry.seek_at = nil, nil
        if math.abs(video:tell() - target) < 0.08 and video:isPlaying() then return end
        local ok = pcall(function()
            video:pause()
            video:seek(target)
            if entry.autoplay then video:play() end
        end)
        if not ok then
            entry.status, entry.decode_error = "error", "Could not seek in this video. Reopen it to retry."
            entry.video = nil
            video:release()
        end
    end

    function telegram:stop_media_playback(message)
        local kind, _, entry = self:media_file_for_message(message)
        if kind == "animation" or kind == "sticker" then return false end
        if entry and self.active_audio == entry then
            self:release_audio()
            return true
        end
        if entry and self.active_video == entry then
            self:release_video()
            return true
        end
        if entry then
            entry.autoplay = false
            entry.playing = false
            entry.paused = false
            entry.play_position = 0
            if entry.audio_source then
                pcall(entry.audio_source.stop, entry.audio_source)
            end
        end
        return kind ~= nil
    end

    function telegram:media_download_state(message)
        local kind, file_id, entry = self:media_file_for_message(message)
        if not entry then return nil end
        return {
            kind = kind,
            file_id = file_id,
            status = entry.status,
            downloaded = entry.downloaded_bytes or 0,
            size = entry.total_bytes or 0,
            progress = entry.download_progress,
        }
    end
end
