-- mpv script to save and load playback position.
-- This version uses an observer to seek only when playback has truly started.

local utils = require 'mp.utils'

-- Configuration
local ANILIST_DIR = os.getenv("HOME") .. "/.local/share/anilist"
local CACHE_DIR = ANILIST_DIR .. "/cache"
local HISTORY_FILE = CACHE_DIR .. "/history.txt"
local STOP_BINGE_FILE = ANILIST_DIR .. "/cache/stop_binge"
local MIN_SAVE_PROGRESS = 5 -- Save if progress is greater than this (percent)
local MAX_SAVE_PROGRESS = 95 -- Save if progress is less than this (percent)
local MIN_RESUME_SECONDS = 10 -- Don't resume if saved time is less than this

-- In-memory state
local last_known_title = nil
local last_known_time = nil
local last_known_duration = nil
local seek_target_time = nil
local playback_observer_id = nil
local file_end_reason = nil

mp.msg.info("Anilist Save/Load Script: Initializing.")
os.execute("mkdir -p '" .. CACHE_DIR .. "'")

---
-- Formats seconds into a hh:mm:ss string for OSD messages.
--
local function format_time(seconds)
    local s = math.floor(seconds)
    local h = math.floor(s / 3600)
    local m = math.floor(s / 60) % 60
    s = s % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    else
        return string.format("%02d:%02d", m, s)
    end
end

---
-- Reads the entire history file into a Lua table.
-- Returns a table mapping: { [title] = timestamp }
--
local function read_history()
    local history = {}
    local file = io.open(HISTORY_FILE, "r")
    if file then
        for line in file:lines() do
            -- Manually find the last colon to be more robust
            local last_colon_pos = -1
            for i = #line, 1, -1 do
                if line:sub(i, i) == ':' then
                    last_colon_pos = i
                    break
                end
            end

            if last_colon_pos > 0 then
                local title = line:sub(1, last_colon_pos - 1)
                local ts_str = line:sub(last_colon_pos + 1):match("^%s*(.-)%s*$")
                local ts = tonumber(ts_str)

                if title and title ~= "" and ts then history[title] = ts; end
            end
        end
        file:close()
    end
    return history
end

---
-- Writes a history table back to the file, overwriting it.
--
local function write_history(history)
    local file = io.open(HISTORY_FILE, "w")
    if file then
        for title, timestamp in pairs(history) do
            file:write(string.format("%s:%d\n", title, math.floor(timestamp)))
        end
        file:close()
    end
end

-- Periodically update the script's knowledge of the current playback state.
local function update_progress()
    local title = mp.get_property("media-title")
    -- Only update if a file is playing and has a valid duration
    if title and mp.get_property_number("duration", 0) > 0 then
        last_known_title = title
        last_known_time = mp.get_property_number("playback-time")
        last_known_duration = mp.get_property_number("duration")
    end
end

-- On shutdown, stop the binge and save the position if applicable.
local function on_shutdown()
    mp.msg.info("Shutdown event. Processing history.")

    if file_end_reason ~= 'eof' then
        mp.msg.info("  - Not an end-of-file shutdown. Stopping binge.")
        local stop_file, err_stop = io.open(STOP_BINGE_FILE, "w")
        if stop_file then
            stop_file:close()
            mp.msg.info("  - Created stop_binge file.")
        else
            mp.msg.error("  - FAILED to create stop_binge file: " .. tostring(err_stop))
        end
    else
        mp.msg.info("  - End-of-file shutdown detected. Binge not stopped.")
    end

    if not last_known_title or not last_known_time or not last_known_duration or last_known_duration == 0 then
        mp.msg.warn("  - No valid progress data to save.")
        return
    end
    local progress = (last_known_time / last_known_duration) * 100
    mp.msg.info("  - Last known progress for '" .. last_known_title .. "': " .. string.format("%.2f", progress) .. "%")
    local history = read_history()
    history[last_known_title] = nil
    if progress > MIN_SAVE_PROGRESS and progress < MAX_SAVE_PROGRESS then
        mp.msg.info("  - Progress is in save range. Adding to history.")
        history[last_known_title] = last_known_time
    else
        mp.msg.warn("  - Progress not in save range. Old history entry is removed.")
    end
    write_history(history)
end

-- On file start, find a saved position and set up an observer to seek.
local function on_file_start()
    -- Reset the end reason for the new file.
    file_end_reason = nil

    -- Use a short timer to ensure media-title is populated.
    mp.add_timeout(0.5, function()
        local current_title = mp.get_property("media-title")
        if not current_title then return end

        mp.msg.info("File started: '" .. current_title .. "'. Checking history.")

        -- Reset state for the new file
        last_known_title, last_known_time, last_known_duration, seek_target_time = nil, nil, nil, nil
        if playback_observer_id then mp.unobserve_property(playback_observer_id); playback_observer_id = nil; end

        local history = read_history()
        local saved_time = history[current_title]

        if saved_time and saved_time > MIN_RESUME_SECONDS then
            mp.msg.info("  - Found position at " .. saved_time .. "s. Will seek when playback starts.")
            seek_target_time = saved_time

            -- This observer will fire whenever playback-time changes.
            playback_observer_id = mp.observe_property("playback-time", "number", function(name, value)
                -- value > 0.1 is a small guard to ensure playback isn't at 0.
                if seek_target_time and value and value > 0.1 then
                    mp.msg.info("  - Playback detected at " .. value .. "s. Seeking to " .. seek_target_time .. "s.")
                    mp.set_property_number("playback-time", seek_target_time)
                    mp.osd_message("Resuming from " .. format_time(seek_target_time), 3)

                    -- Clean up history and the observer itself
                    local hist = read_history(); hist[current_title] = nil; write_history(hist)
                    seek_target_time = nil
                    if playback_observer_id then mp.unobserve_property(playback_observer_id); playback_observer_id = nil; end
                end
            end)
        else
            mp.msg.info("  - No saved position found or timestamp is below threshold.")
        end
    end)
end

-- Capture the reason why a file ended.
local function on_end_file(event)
    mp.msg.info("End-file event. Reason: " .. event.reason)
    file_end_reason = event.reason
end

-- Register the events and timers
mp.add_periodic_timer(5, update_progress)
mp.register_event("shutdown", on_shutdown)
mp.register_event("start-file", on_file_start)
mp.register_event("end-file", on_end_file)

mp.msg.info("Anilist Save/Load Script: Loaded and ready.")