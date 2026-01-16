local utils = require("mp.utils")
local home = os.getenv("HOME")
local BASE_PATH = home .. "/.local/share/anilist"
local LOG_FILE = BASE_PATH .. "/logs/auto-skip.log"

-- ensure base path exists
utils.subprocess({
	args = { "mkdir", "-p", BASE_PATH },
	cancellable = false,
})

local function log(msg)
	mp.msg.info("auto-skip.lua: " .. msg)
	local f = io.open(LOG_FILE, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg .. "\n")
		f:close()
	end
end

log("Script loaded.")

-- Skips intro if found at the beginning of the video
local function skip_intro_on_start()
	-- we only want to run this at the start of the video
	local playback_time = mp.get_property_number("playback-time")
	if playback_time and playback_time > 5 then
		return
	end

	local chapters = mp.get_property_native("chapter-list")
	if not chapters or #chapters < 2 then
		log("Not enough chapters to check for intro.")
		return
	end

	log("Checking for intro to skip...")

	local candidates = {}
	for i = 1, #chapters - 1 do
		local chapter_info = chapters[i]
		if chapter_info.time < 300 then
			local chapter_duration = chapters[i + 1].time - chapter_info.time
			if chapter_duration >= 60 and chapter_duration <= 120 then
				log("Found candidate intro: Chapter " .. (i - 1) .. " | Start: " .. chapter_info.time .. " | Duration: " .. chapter_duration)
				table.insert(candidates, i) -- store the index
			end
		else
			-- Chapters are ordered by time, so we can stop.
			log("Reached chapter outside of 5-min window, stopping check for candidates.")
			break
		end
	end

	if #candidates == 0 then
		log("No intro candidates found.")
		return
	end

	local chapter_to_skip_index = nil

	-- Prefer a candidate that is not the very first chapter
	for _, index in ipairs(candidates) do
		if chapters[index].time > 1 then -- not starting at the very beginning
			chapter_to_skip_index = index
			break -- found our preferred candidate, stop searching
		end
	end

	-- If we didn't find a "preferred" candidate, and there are candidates,
	-- it means the only candidate(s) are at the start. Let's take the first one.
	if chapter_to_skip_index == nil then
		chapter_to_skip_index = candidates[1]
	end

	if chapter_to_skip_index then
		local skip_to_time = chapters[chapter_to_skip_index + 1].time
		log("Decided to skip chapter " .. (chapter_to_skip_index - 1) .. ". Skipping to " .. skip_to_time)
		mp.set_property("time-pos", skip_to_time)
	end
end

mp.register_event("file-loaded", function()
	log("File loaded, running startup tasks.")
	mp.add_timeout(1, skip_intro_on_start)
end)

local function handle_chapter_change()
    local chapter = mp.get_property_number("chapter")
    if not chapter then
        return
    end

    local chapters = mp.get_property_native("chapter-list")
    if not chapters or #chapters == 0 then
        return
    end

    -- Quit on last chapter
    local chapter_count = #chapters
    if chapter >= chapter_count - 1 then -- use >= to be safe
        log("Last chapter reached, quitting.")
        mp.command("quit")
        return -- Execution stops here
    end
end

mp.observe_property("chapter", "number", handle_chapter_change)
