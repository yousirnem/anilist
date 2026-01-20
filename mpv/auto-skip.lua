local utils = require("mp.utils")

local data_path = os.getenv("HOME") .. "/.config/ani-skip/custom.json"

local title = mp.get_property("media-title")
local id, ep = title:match("%[(%d+)%].*%- (%d+)")

if not id then
	return
end

local f = io.open(data_path, "r")
if not f then
	return
end
local data = utils.parse_json(f:read("*a"))
f:close()

local entry = data[id] and data[id][ep]
if not entry then
	return
end

mp.register_event("playback-restart", function()
	if entry.op then
		mp.set_property_number("time-pos", entry.op[2])
		mp.osd_message("OP skipped")
	end
end)

mp.observe_property("time-pos", "number", function(_, t)
	if entry.ed and t >= entry.ed[1] then
		mp.command("quit")
	end
end)
