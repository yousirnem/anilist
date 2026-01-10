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

mp.register_event("end-file", function(event)
	log("end-file event triggered.")

	if event.reason ~= "eof" then
		log("Not EOF, skipping. Reason: " .. tostring(event.reason))
		return
	end

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
end)
