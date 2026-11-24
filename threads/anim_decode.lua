

local json = require("dkjson")

local thumbnail = (...) == "thumbnail"
local prefix = thumbnail and "thumbnail" or "anim"
local in_channel = love.thread.getChannel(prefix .. "_in")
local out_channel = love.thread.getChannel(prefix .. "_out")

local MAX_FRAMES = 24
local MAX_EDGE = 128
local MAX_FPS = 24
local MAX_TGS_FILE_BYTES = 1024 * 1024

local function sh_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function file_size(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local size = handle:seek("end")
    handle:close()
    return size
end

local function run(command)
    local ok, why, code = os.execute(command)
    if ok == true or ok == 0 then
        return true
    end
    return false, tostring(why or code or ok)
end

local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local data = handle:read("*a")
    handle:close()
    return data
end

local function file_exists(path)
    local handle = io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
end

local function which(bin)
    local handle = io.popen("command -v " .. bin .. " 2>/dev/null")
    if not handle then
        return nil
    end
    local path = handle:read("*l")
    handle:close()
    if path and path ~= "" then
        return path
    end
    return nil
end

local ffmpeg = os.getenv("SPGRAM_FFMPEG") or which("ffmpeg")
local thumbnail_timeout = thumbnail and which("timeout")
local ffprobe = not thumbnail and which("ffprobe")
local lottie_converter = not thumbnail and (os.getenv("LOTTIE_CONVERTER")
    or which("lottie_convert.py")
    or which("lottie_convert"))
local clean_env = "env -u LD_LIBRARY_PATH "
local local_input = " -protocol_whitelist file,pipe -format_whitelist "
    .. "mov,matroska,webm,ogg,avi,mpegts,mpeg,mpegvideo,asf,flv,dv,gif,apng,png_pipe,webp_pipe,wav,aiff,mp3,flac,image2"

local function probe(path)
    if not ffprobe then
        return nil
    end
    local tmp = os.tmpname()
    local command = string.format(
        "%s%s -v error%s -select_streams v:0 -show_entries stream=width,height,duration:format=duration -of json %s > %s 2>/dev/null",
        clean_env,
        sh_quote(ffprobe),
        local_input,
        sh_quote(path),
        sh_quote(tmp)
    )
    local ok = run(command)
    local raw = read_file(tmp)
    os.remove(tmp)
    if not ok or not raw or raw == "" then
        return nil
    end
    local decoded_ok, meta = pcall(json.decode, raw)
    if not decoded_ok or type(meta) ~= "table" then
        return nil
    end
    local stream = meta.streams and meta.streams[1] or {}
    local format = meta.format or {}
    return tonumber(stream.width), tonumber(stream.height), tonumber(stream.duration) or tonumber(format.duration)
end

local function plan(width, height, duration, is_webm)
    if not duration or duration <= 0 then duration = 3 end
    local fps = math.min(is_webm and MAX_FPS / 2 or MAX_FPS, MAX_FRAMES / duration)
    local count = math.max(1, math.min(MAX_FRAMES, math.floor(duration * fps + 0.5)))
    local frame_dt = 1 / fps
    local target_w, target_h = width, height
    if not target_w or not target_h or target_w < 2 or target_h < 2 then
        return count, frame_dt, MAX_EDGE, nil
    end
    local edge = math.max(target_w, target_h)
    if edge > MAX_EDGE then
        local scale = MAX_EDGE / edge
        target_w = math.max(2, math.floor(target_w * scale + 0.5))
        target_h = math.max(2, math.floor(target_h * scale + 0.5))
    end
    return count, frame_dt, target_w, target_h
end

local function collect_paths(out_dir, count)
    local paths = {}
    for index = 1, count do
        local path = string.format("%s/f_%03d.png", out_dir, index)
        local handle = io.open(path, "rb")
        if not handle then
            break
        end
        handle:close()
        paths[#paths + 1] = path
    end
    return paths
end

local function extract_audio(path, out_dir, duration, channels)
    local candidate = out_dir .. "/audio.wav"
    local limit = duration and math.max(1, math.min(900, tonumber(duration) or 900)) or 12
    local command = string.format(
        "%s%s -nostdin -y -v error -threads 2%s -i %s -map 0:a:0 -vn -t %.3f -c:a pcm_s16le -ar 44100 -ac %d %s >/dev/null 2>&1",
        clean_env,
        sh_quote(ffmpeg),
        local_input,
        sh_quote(path),
        limit,
        channels or 2,
        sh_quote(candidate)
    )
    if run(command) and file_exists(candidate) then
        return candidate
    end
    return nil
end

local function finish(kind, file_id, paths, width, height, frame_dt, cached, first_frame, audio_path)
    return {
        ok = true,
        kind = kind,
        file_id = file_id,
        first_frame = first_frame == true,
        paths = paths,
        width = width,
        height = height,
        frame_dt = frame_dt,
        cached = cached or false,
        audio_path = audio_path,
    }
end

local function decode_job(job)
    if not ffmpeg then
        return {ok = false, kind = job.kind, file_id = job.file_id, first_frame = job.first_frame == true, error = "Playback needs FFmpeg. Original file kept."}
    end
    local out_dir = job.out_dir
    local transient = job.kind == "animation" or job.kind == "sticker"
    local meta_raw = not transient and read_file(out_dir .. "/meta.json")
    if meta_raw then
        local ok, meta = pcall(json.decode, meta_raw)
        if ok and type(meta) == "table" and meta.version == 3
            and tonumber(meta.count) and tonumber(meta.frame_dt)
            and meta.first_frame == (job.first_frame == true) then
            local paths = collect_paths(out_dir, meta.count)
            if #paths == meta.count and #paths > 0 then
                local audio_path = meta.audio_path
                if audio_path and (not file_exists(audio_path) or not audio_path:match("%.wav$")) then audio_path = nil end
                if job.kind == "video" and not job.first_frame and not audio_path then
                    audio_path = extract_audio(job.path, out_dir)
                    meta.audio_path = audio_path
                    local meta_file = io.open(out_dir .. "/meta.json", "w")
                    if meta_file then
                        meta_file:write(json.encode(meta))
                        meta_file:close()
                    end
                end
                return finish(job.kind, job.file_id, paths, tonumber(meta.width), tonumber(meta.height), tonumber(meta.frame_dt), true, job.first_frame, audio_path)
            end
        end
    end

    run("rm -rf " .. sh_quote(out_dir))
    local made = run("mkdir -p " .. sh_quote(out_dir))
    if not made then
        return {ok = false, kind = job.kind, file_id = job.file_id, first_frame = job.first_frame == true, error = "cannot create frame directory"}
    end

    local input_path = job.path
    if job.kind == "sticker" and job.sticker_format == "stickerFormatTgs" then
        if not lottie_converter then
            return {
                ok = false,
                kind = job.kind,
                file_id = job.file_id,
                first_frame = job.first_frame == true,
                error = "The TGS sticker converter is unavailable.",
            }
        end
        local size = file_size(job.path)
        if not size or size > MAX_TGS_FILE_BYTES then
            return {
                ok = false,
                kind = job.kind,
                file_id = job.file_id,
                first_frame = job.first_frame == true,
                error = "Sticker file is too large.",
            }
        end
        input_path = out_dir .. "/tgs.gif"
        local command = string.format(
            "%s%s %s %s >/dev/null 2>&1",
            clean_env,
            sh_quote(lottie_converter),
            sh_quote(job.path),
            sh_quote(input_path)
        )
        if not run(command) or (file_size(input_path) or 0) == 0 then
            return {
                ok = false,
                kind = job.kind,
                file_id = job.file_id,
                first_frame = job.first_frame == true,
                error = "Could not convert the sticker. Original file kept.",
            }
        end
    end

    local width, height, duration = probe(input_path)
    local is_webm = (job.path or ""):match("%.webm$")
        or (job.sticker_format == "stickerFormatWebm")
        or (input_path or ""):match("%.webm$")
    local count, frame_dt, target_w, target_h = plan(width, height, duration or job.duration, is_webm)
    if job.first_frame then count = 1 end
    local filter
    if target_h then
        filter = string.format("fps=%.4f,scale=%d:%d:flags=lanczos", 1 / frame_dt, target_w, target_h)
    else
        filter = string.format("fps=%.4f,scale=%d:%d:force_original_aspect_ratio=decrease:flags=lanczos",
            1 / frame_dt, MAX_EDGE, MAX_EDGE)
    end
    local command = string.format(
        "%s%s -nostdin -y -v error -an -max_alloc 67108864 -threads 1 -filter_threads 1%s -i %s -vf %s " ..
        "-start_number 1 -frames:v %d -c:v png -threads:v 1 -pix_fmt rgba %s >/dev/null 2>&1",
        clean_env,
        sh_quote(ffmpeg),
        local_input,
        sh_quote(input_path),
        sh_quote(filter),
        count,
        sh_quote(out_dir .. "/f_%03d.png")
    )
    run(command)
    local paths = collect_paths(out_dir, count)
    if transient and input_path ~= job.path then os.remove(input_path) end
    if #paths == 0 then
        if transient then os.remove(out_dir) end
        return {ok = false, kind = job.kind, file_id = job.file_id, first_frame = job.first_frame == true, error = "Playback failed. Original file kept."}
    end

    local audio_path
    if job.kind == "video" and not job.first_frame then
        audio_path = extract_audio(job.path, out_dir)
    end

    if transient then
        local result = finish(job.kind, job.file_id, paths, target_w, target_h, frame_dt, false, job.first_frame)
        result.transient_dir = out_dir
        return result
    end

    local actual_dt = frame_dt
    local meta = {
        version = 3,
        count = #paths,
        width = target_w,
        height = target_h or 0,
        frame_dt = actual_dt,
        first_frame = job.first_frame == true,
        audio_path = audio_path,
    }
    local meta_file = io.open(out_dir .. "/meta.json", "w")
    if meta_file then
        meta_file:write(json.encode(meta))
        meta_file:close()
    end
    return finish(job.kind, job.file_id, paths, target_w, target_h, actual_dt, false, job.first_frame, audio_path)
end

local function run_cancelable(command, output)
    local cancel = sh_quote(output .. ".cancel")
    return run("{ [ ! -f " .. cancel .. " ] || exit 1; " .. command .. " >/dev/null 2>&1 & encoder=$!; "
        .. 'while kill -0 "$encoder" 2>/dev/null; do '
        .. 'if [ -f ' .. cancel .. ' ]; then kill -KILL "$encoder" 2>/dev/null; break; fi; sleep 1; done; '
        .. 'wait "$encoder"; } 2>/dev/null')
end

local function convert_audio(job)
    local result = {type = "converted_audio", name = job.name, ok = false}
    if not ffmpeg then
        result.error = "This audio format needs FFmpeg."
        return result
    end
    local command = clean_env .. sh_quote(ffmpeg)
        .. " -nostdin -y -v error -max_alloc 134217728 -threads 1" .. local_input .. " -i " .. sh_quote(job.path)
        .. " -map 0:a:0 -vn -map_metadata -1 -c:a libvorbis -b:a 64k -ac 2 -ar 32000 -fs 134217728 "
        .. sh_quote(job.output)
    local completed = run_cancelable(command, job.output)
    local bytes = file_size(job.output) or 0
    result.ok = completed and bytes > 0 and bytes < 134217728
    if not result.ok then
        os.remove(job.output)
        result.error = "Could not prepare this audio. Its format may be unsupported."
    end
    return result
end

local function convert_video(job)
    local result = {type = "converted_video", name = job.name, ok = false}
    if not ffmpeg then
        result.error = "Video playback requires FFmpeg on this device."
        return result
    end
    local filter = "fps=15,scale='min(320,iw)':'min(240,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"
    local command = clean_env .. sh_quote(ffmpeg)
        .. " -nostdin -y -v error -nostats -stats_period 1 -progress " .. sh_quote(job.output .. ".progress")
        .. " -max_alloc 134217728 -threads 1" .. local_input .. " -i " .. sh_quote(job.path)
        .. " -map 0:V:0 -map '0:a:0?' -map_metadata -1 -map_chapters -1 -filter_threads 1 -threads 1"
        .. " -vf " .. sh_quote(filter)
        .. " -c:v libtheora -b:v 240k -pix_fmt yuv420p -c:a libvorbis -b:a 40k -ac 1 -ar 24000 "
        .. sh_quote(job.output)
    result.ok = run_cancelable(command, job.output) and (file_size(job.output) or 0) > 0
    if not result.ok then
        os.remove(job.output)
        result.error = "Could not prepare this video. Its container or codec may be unsupported."
    end
    return result
end

local function convert_webp(job)
    if not ffmpeg then return false end
    if job.storage == "avatar_photos" and (file_size(job.path) or math.huge) > 262144 then return false end
    local deadline = thumbnail_timeout and (sh_quote(thumbnail_timeout) .. " 5 ") or ""
    local command = clean_env .. deadline .. sh_quote(ffmpeg)
        .. " -nostdin -y -v error -max_alloc 33554432 -threads 1" .. local_input .. " -i " .. sh_quote(job.path)
        .. " -vf scale=128:128:force_original_aspect_ratio=decrease -filter_threads 1 -frames:v 1"
        .. " -c:v png -threads:v 1 -pix_fmt rgba -f image2 " .. sh_quote(job.output) .. " 2>/dev/null"
    return run(command) and (file_size(job.output) or 0) > 0
end

while true do
    local job = in_channel:demand()
    if type(job) ~= "table" or job.type == "quit" then
        break
    end
    if thumbnail and job.type == "convert_webp" then
        local ok, converted = pcall(convert_webp, job)
        out_channel:push({type = "converted_webp", storage = job.storage, file_id = job.file_id,
            output = job.output, ok = ok and converted == true})
    elseif not thumbnail and job.type == "convert_video" then
        local ok, result = pcall(convert_video, job)
        out_channel:push(ok and result or {
            type = "converted_video", name = job.name, ok = false, error = "Could not prepare this video.",
        })
    elseif not thumbnail and job.type == "convert_audio" then
        local ok, result = pcall(convert_audio, job)
        out_channel:push(ok and result or {
            type = "converted_audio", name = job.name, ok = false, error = "Could not prepare this audio.",
        })
    elseif not thumbnail and job.type == "decode" and job.path and job.out_dir and job.file_id then
        local ok, result = pcall(decode_job, job)
        out_channel:push(ok and result or {
            ok = false, kind = job.kind, file_id = job.file_id, first_frame = job.first_frame == true,
            error = "Playback failed. Original file kept.",
        })
    end
end
