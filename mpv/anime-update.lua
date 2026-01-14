local utils = require("mp.utils")
local home = os.getenv("HOME")
local BASE_PATH = home .. "/.local/share/anilist"
local LOG_FILE = BASE_PATH .. "/logs/anime-update.log"

-- ensure base path exists
utils.subprocess({
	args = { "mkdir", "-p", BASE_PATH },
	cancellable = false,
})

local function log(msg)
	mp.msg.info("anime-update.lua: " .. msg)
	local f = io.open(LOG_FILE, "a")
	if f then
		f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg .. "\n")
		f:close()
	end
end

log("Script loaded.")

local updated_for_file = nil

local function check_and_update()
	local current_file = mp.get_property("path")
	if updated_for_file == current_file then
		return
	end

	local percent = mp.get_property_number("percent-pos")
	local remaining = mp.get_property_number("duration-remaining")

	if (percent and percent >= 90) or (remaining and remaining <= 120) then
		log("Update condition met. Percent: " .. tostring(percent) .. ", Remaining: " .. tostring(remaining))
		updated_for_file = current_file

		local title = mp.get_property("media-title") or ""
		if title == "" then
			log("media-title empty, skipping.")
			return
		end

		local episode = title:match("[Ee]pisode%s+(%d+)")
		if not episode then
			log("Episode not found in title: " .. title)
			return
		end

		local anime = title:gsub("[Ee]pisode%s+%d+", ""):gsub("%s+$", "")

		local command = {
			"bash",
			BASE_PATH .. "/lib/update.sh",
			anime,
			episode,
		}

		log(string.format("Running update.sh | anime='%s' | episode='%s'", anime, episode))

		local result = utils.subprocess({
			args = command,
			cancellable = false,
		})

		log("Exit status: " .. tostring(result.status))

		if result.stdout and result.stdout ~= "" then
			log("stdout: " .. result.stdout)
		end

		if result.stderr and result.stderr ~= "" then
			log("stderr: " .. result.stderr)
		end
	end
end

mp.observe_property("percent-pos", "number", check_and_update)
mp.observe_property("duration-remaining", "number", check_and_update)

mp.register_event("file-loaded", function()
	log("File loaded, resetting update status.")
	updated_for_file = nil
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

    -- Skip intro
    -- chapter is 0-indexed, but lua tables are 1-indexed
    local current_chapter_index = chapter + 1

    local chapter_info = chapters[current_chapter_index]
    -- if the chapter starts after 5 minutes, it's probably not an intro
    if chapter_info.time > 300 then
        return
    end

    local chapter_duration
    -- The next chapter is `current_chapter_index + 1`, which is `chapter + 2` in 1-based index
    if (current_chapter_index + 1) > #chapters then
        -- This case should not be reached due to the last chapter check above, but as a safeguard.
        return
    else
        chapter_duration = chapters[current_chapter_index + 1].time - chapter_info.time
    end


    log("Current chapter " .. chapter .. " | Start time: " .. chapter_info.time .. " | Duration: " .. chapter_duration)

    -- Duration between 80 seconds and 130 seconds.
    if chapter_duration >= 80 and chapter_duration <= 130 then
        log("Chapter is likely an intro, skipping to next chapter.")
        mp.command("no-osd add chapter 1")
    end
end

mp.observe_property("chapter", "number", handle_chapter_change)
