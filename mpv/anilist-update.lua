local utils = require("mp.utils")
local home = os.getenv("HOME")
local BASE_PATH = home .. "/.local/share/anilist"
local LOG_FILE = BASE_PATH .. "/logs/anilist-update.log"

-- ensure base path exists
utils.subprocess({
	args = { "mkdir", "-p", BASE_PATH },
	cancellable = false,
})

local function log(msg)
	mp.msg.info("anilist-update.lua: " .. msg)
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
