local preferences = require("src.shared.system.media_settings")
return function(telegram)
    function telegram:custom_emoji_id(sticker)
        local full = sticker and sticker.full_type
        return full and full["@type"] == "stickerFullTypeCustomEmoji" and full.custom_emoji_id or nil
    end

    function telegram:open_emoji_packs()
        self.sticker_set_generation = (self.sticker_set_generation or 0) + 1
        local gen = tostring(self.sticker_set_generation)
        self.sticker_set_viewer = {emoji_sets = true, title = "Emoji packs", loading = true, pending = 2,
            installed = {}, trending = {}, generation = gen}
        local kind = {["@type"] = "stickerTypeCustomEmoji"}
        self:send({["@type"] = "getInstalledStickerSets", sticker_type = kind}, "emoji_sets_installed:" .. gen)
        self:send({["@type"] = "getTrendingStickerSets", sticker_type = kind, offset = 0, limit = 24}, "emoji_sets_trending:" .. gen)
    end

    function telegram:open_emoji_pack(set, parent)
        self.sticker_set_generation = self.sticker_set_generation + 1
        local gen = tostring(self.sticker_set_generation)
        self.sticker_set_viewer = {emoji_pack = true, loading = true, generation = gen, parent = parent,
            title = set.title or "Emoji pack", stickers = {}}
        self:send({["@type"] = "getStickerSet", set_id = set.id}, "emoji_pack:" .. gen)
    end

    function telegram:toggle_emoji_pack(pack)
        if pack.install_pending or not pack.set_id then return end
        pack.install_token = "emoji_install:" .. pack.generation
        pack.install_pending = self:send({["@type"] = "changeStickerSet", set_id = pack.set_id,
            is_installed = not pack.is_installed, is_archived = false}, pack.install_token)
    end

    function telegram:custom_emoji_sticker(id)
        if not id then return end
        id = tostring(id)
        self.custom_emojis = self.custom_emojis or {}
        local cached = self.custom_emojis[id]
        if cached == nil then
            self.custom_emojis[id] = false
            self.custom_emoji_queue = self.custom_emoji_queue or {}
            self.custom_emoji_queue[#self.custom_emoji_queue + 1] = id
            self.custom_emoji_order = self.custom_emoji_order or {}
            self.custom_emoji_order[#self.custom_emoji_order + 1] = id
            if #self.custom_emoji_order > 384 then
                self.custom_emojis[table.remove(self.custom_emoji_order, 1)] = nil
            end
        end
        return cached or nil
    end

    function telegram:request_custom_emojis()
        local queue = self.custom_emoji_queue
        if not queue or #queue == 0 or self.custom_emoji_request then return end
        local batch = {}
        while #batch < 32 and #queue > 0 do batch[#batch + 1] = table.remove(queue, 1) end
        self.custom_emoji_sequence = (self.custom_emoji_sequence or 0) + 1
        local token = "emoji_lookup:" .. tostring(self.custom_emoji_sequence)
        self.custom_emoji_request = self:send({["@type"] = "getCustomEmojiStickers", custom_emoji_ids = batch}, token)
        if not self.custom_emoji_request then
            for index = #batch, 1, -1 do table.insert(queue, 1, batch[index]) end
        end
    end

    function telegram:handle_emoji_response(kind, extra, object)
        local category, generation = extra:match("^emoji_sets_(%a+):(%d+)$")
        local pack_generation = extra:match("^emoji_pack:(%d+)$")
        local install_generation = extra:match("^emoji_install:(%d+)$")
        if install_generation then
            local pack = self.sticker_set_viewer
            if pack and pack.install_token == extra then
                pack.install_pending, pack.install_token = nil, nil
                if kind == "ok" then
                    pack.is_installed = not pack.is_installed
                    self.action_error = ""
                    self.action_status = pack.is_installed and "Emoji pack added" or "Emoji pack removed"
                    if pack.parent and pack.parent.emoji_sets then
                        local parent = pack.parent
                        for index = #parent.installed, 1, -1 do
                            if parent.installed[index].id == pack.set_id then table.remove(parent.installed, index) end
                        end
                        if pack.is_installed then
                            parent.installed[#parent.installed + 1] = {id = pack.set_id, title = pack.title}
                        end
                    end
                else
                    pack.error = object.message or "Could not update emoji pack."
                    self.action_error = pack.error
                end
            end
            return true
        end
        if category or pack_generation then
            local picker = self.sticker_set_viewer
            if not picker or picker.generation ~= (generation or pack_generation) then return true end
            if category then
                picker[category] = object.sets or object.sticker_sets or {}
                picker.pending = picker.pending - 1
                picker.loading = picker.pending > 0
            else
                picker.loading = false
                picker.title = object.title or picker.title
                picker.stickers = object.stickers or {}
                picker.set_id, picker.is_installed = object.id, object.is_installed == true
            end
            if kind == "error" then picker.error = object.message or "Could not load emoji packs." end
            return true
        end
        if not extra:match("^emoji_lookup:%d+$") then return false end
        if self.custom_emoji_request == extra then
            self.custom_emoji_request = nil
            for _, sticker in ipairs(object.stickers or {}) do
                local id = self:custom_emoji_id(sticker)
                if id then self.custom_emojis[tostring(id)] = sticker end
            end
        end
        return true
    end

    function telegram:choose_sticker_size(message)
        local content = message and message.content
        if not content then return nil end

        if content["@type"] == "messageSticker" then
            local sticker = content.sticker and content.sticker.sticker
            if not sticker or not sticker.id then return nil end
            return sticker
        end

        if content["@type"] == "messageDocument" then
            local doc = content.document
            if doc then
                if (doc.file_name or ""):lower():match("%.tgs$") then
                    return doc.document
                end
            end
        end

        return nil
    end

    function telegram:sticker_thumbnail_file(sticker)
        local thumbnail = sticker and sticker.thumbnail
        if not thumbnail then return nil end
        return thumbnail.file or (thumbnail.photo and thumbnail.photo.file) or thumbnail.photo
    end

    function telegram:ensure_sticker(message, sticker_format, inline)
        local sticker = self:choose_sticker_size(message)
        if not sticker then return end

        local file = sticker.sticker or sticker
        if not file or not file.id then return end
        local file_id = file.id
        self.sticker_by_message[self:media_message_key(message)] = file_id

        local sticker_obj = message.content and message.content.sticker
        local format = (sticker_obj and sticker_obj.format and sticker_obj.format["@type"])
            or sticker_format or self.sticker_format_by_file[file_id]

        local file_local = file["local"] or {}

        if not format and file_local.path then
            local ext = file_local.path:match("%.([^.]+)$")
            if ext == "webm" then format = "stickerFormatWebm"
            elseif ext == "tgs" then format = "stickerFormatTgs"
            end
        end

        self.sticker_format_by_file[file_id] = format

        local is_animated = (format == "stickerFormatWebm" or format == "stickerFormatTgs")
        if inline and is_animated and not preferences.get("inline_animation") then return end

        local entry = self.stickers[file_id]
        if not entry then
            entry = {status = "remote", format = format, autoplay = is_animated}
            self.stickers[file_id] = entry
        else
            entry.format = format or entry.format
            if is_animated then entry.autoplay = true end
        end
        if file_local.is_downloading_completed and file_local.path and file_local.path ~= "" then
            self:load_sticker(file_id, file_local.path)
        elseif not entry.download_requested then
            entry.download_requested = true
            entry.status = "downloading"
            local extra = self:send({
                ["@type"] = "downloadFile",
                file_id = file_id,
                priority = 1,
                offset = 0,
                limit = 0,
                synchronous = false,
            }, "sticker:" .. tostring(file_id))
            if not extra then
                entry.download_requested = false
                entry.status = "remote"
            end
        end
    end

    function telegram:load_sticker(file_id, path)
        local entry = self.stickers[file_id]
        if not entry then return end
        entry.source_path = path
        local format = self.sticker_format_by_file[file_id] or entry.format
        if format == "stickerFormatWebm" or format == "stickerFormatTgs" then
            if entry.status == "downloading" then entry.status = "remote" end
        elseif not entry.image and entry.failed_path ~= path and not self:queue_webp_image(file_id, path, "stickers") then
            self:load_image(file_id, path, self.stickers)
            if not entry.image then entry.failed_path = path end
        end

    end

    function telegram:sticker_playback_supported(message)
        local content = message and message.content
        local sticker_obj = content and content.sticker
        local format = sticker_obj and sticker_obj.format and sticker_obj.format["@type"]
        return format == "stickerFormatWebm" or format == "stickerFormatTgs"
    end

    function telegram:sticker_image(message, measure)
        local file = self:choose_sticker_size(message)
        local image, width, height = self:animation_frame(file and self.stickers[file.id], measure)
        if image or preferences.get("inline_animation") then return image, width, height end
        local sticker = message.content and message.content.sticker
        local preview = self:media_thumbnail(sticker, nil, measure)
        if preview then return preview, preview:getWidth(), preview:getHeight() end
    end
end
