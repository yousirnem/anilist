local utils = require("mp.utils")

local data_path = os.getenv("HOME") .. "/.config/ani-skip/custom.json"

local state = {
	anime_id = nil,
	episode = nil,
	mark = nil,
}

-- ani-cli passes --force-media-title
local title = mp.get_property("media-title")

-- Expected format example:
-- "[11061] Cowboy Bebop - 01"
local id, ep = title:match("%[(%d+)%].*%- (%d+)")

state.anime_id = id
state.episode = ep

local function load_data()
	local f = io.open(data_path, "r")
	if not f then
		return {}
	end
	local c = f:read("*a")
	f:close()
	return utils.parse_json(c) or {}
end

local function save_data(data)
	utils.mkdir_path(data_path:match("(.*/)"))
	local f = io.open(data_path, "w")
	f:write(utils.format_json(data))
	f:close()
end

local function mark_time(kind)
	local t = mp.get_property_number("time-pos")
	state.mark = state.mark or {}
	state.mark[kind] = t
	mp.osd_message(kind .. " marked: " .. string.format("%.2f", t))
end

local function commit(kind)
	if not state.mark or not state.mark.start then
		mp.osd_message("No start marked")
		return
	end

	local data = load_data()
	data[state.anime_id] = data[state.anime_id] or {}
	data[state.anime_id][state.episode] = data[state.anime_id][state.episode] or {}

	data[state.anime_id][state.episode][kind] = {
		state.mark.start,
		state.mark["end"],
	}

	save_data(data)
	state.mark = nil
	mp.osd_message(kind .. " saved")
end

-- Keybindings
mp.add_key_binding("o", "op-start", function()
	mark_time("start")
end)
mp.add_key_binding("O", "op-end", function()
	mark_time("end")
	commit("op")
end)

mp.add_key_binding("e", "ed-start", function()
	mark_time("start")
end)
mp.add_key_binding("E", "ed-end", function()
	mark_time("end")
	commit("ed")
end)
