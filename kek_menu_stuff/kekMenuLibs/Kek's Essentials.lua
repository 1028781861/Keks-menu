-- Copyright © 2020-2022 Kektram

local essentials <const> = {version = "1.6.5"}

local language <const> = require("Kek's Language")
local lang <const> = language.lang
local enums <const> = require("Kek's Enums")
local settings <const> = require("Kek's Settings")
local memoize <const> = require("Kek's Memoize")

essentials.listeners = {
	player_leave = {},
	player_join = {},
	chat = {},
	exit = {}
}
essentials.nethooks = {}

essentials.number_of_explosion_types = 84 -- This must be updated sometimes after major gta update.
essentials.init_delay = utils.time_ms() + 1000 -- if utils.time_ms() > essentials.init_delay then < STUFF > end, makes sure < STUFF > won't run during script init.

local paths <const> = {home = utils.get_appdata_path("PopstarDevs", "2Take1Menu").."\\"}
paths.kek_menu_stuff = paths.home.."scripts\\kek_menu_stuff\\"

function essentials.is_str(f, str) -- Greatly improves readability
	local str_data <const> = f.str_data
	local status = false
	for i = 1, #str_data do
		if str_data[i] == lang[str] then
			status = true
			break
		end
	end
	if not status then -- An if statement is faster than a function call.
		essentials.assert(false, str.." doesn't match anything in str_data. feature name:", f.name)
	end
	return f.str_data[f.value + 1] == lang[str]
end

function essentials.assert(bool, msg, ...) -- Does the same as regular assert, but sends the error to me.
	if not bool then
		local n_args <const> = select("#", ...)
		msg = string.format(
			(n_args > 0 and "%s\nExtra info:\n" or msg)..string.rep("%s\n", n_args), 
			msg, ...
		)
		-- not essentials.create_thread, because it uses this function. Would cause recursion loop if the thread below got an error.
		local traceback <const> = debug.traceback(msg, 2)
		if __kek_menu.version:match("^%d%.%d%.%d%.%d%.?b?%d?%d?$") and not traceback:find("?:-1: ", 1, true) then
			menu.create_thread(
				essentials.post_to_keks_menu_site, 
				"https://keks-menu-stats.kektram.com?FROM_KEKS=true&error_msg="
				..web.urlencode("Version: "..__kek_menu.version
				..(network.get_online_version and " gta "..tostring(network.get_online_version()) or " gta: native lib not loaded yet") 
				-- Not calling the native directly because I don't want to risk forgetting to update the native id.
				.."\n"..traceback))
		end
		error(msg.."\n"..traceback.."\n", 2)
	end
end

function essentials.create_thread(func, data)
	return menu.create_thread(function(data)
		essentials.assert(pcall(func, data))
	end, data)
end

function essentials.add_feature(name, Type, parent, func)
	essentials.assert(utf8.len(name), "Tried to create a feature with invalid utf8 for its name.") -- The game crashes if this isn't prevented
	
	local feat
	if type(func) == "function" then
		feat = menu.add_feature(name, Type, parent, function(f, data)
			if type(f) ~= "number" then -- Must check if not a number. Custom UI's f is a table, not userdata.
				local status <const>, err <const> = pcall(func, f, data)
				essentials.assert(status, err, name, Type)
			end
		end)
	else
		feat = menu.add_feature(name, Type, parent)
	end
	essentials.assert(feat, "Failed to create feature", "Invalid parent id", name)

	return feat
end

function essentials.add_player_feature(name, Type, parent, func)
	essentials.assert(utf8.len(name), "Tried to create a player feature with invalid utf8 for its name.")
	
	local feat
	if type(func) == "function" then
		feat = menu.add_player_feature(name, Type, parent, function(f, pid, data)
			if type(f) ~= "number" then
				local status <const>, err <const> = pcall(func, f, pid, data)
				essentials.assert(status, err, name, Type)
			end
		end)
	else
		feat = menu.add_player_feature(name, Type, parent)
	end
	essentials.assert(feat, "Failed to create player feature", "Invalid parent id", name)

	return feat
end

do
	local requests_in_last_10_minutes <const> = {}
	local id = 0
	function essentials.post_to_keks_menu_site(...)  -- DO NOT USE essentials.assert IN THIS FUNCTION. essentials.assert uses this function.
	-- Limits entire script to 5 requests per 10 minutes.
		local number_of_requests_in_last_10_minutes = 0
		for i, time in pairs(requests_in_last_10_minutes) do
			if utils.time_ms() > time then
				requests_in_last_10_minutes[i] = nil
			else
				number_of_requests_in_last_10_minutes = number_of_requests_in_last_10_minutes + 1
			end
		end
		if number_of_requests_in_last_10_minutes < 5 then
			id = id + 1
			requests_in_last_10_minutes[id] = utils.time_ms() + (1000 * 60 * 10)
			return web.post(...)
		end
	end
end

function essentials.add_chat_event_listener(callback) -- Fixes crash if someone spams chat
	local tracker <const> = {}
	return event.add_event_listener("chat", function(event)
		if not tracker[event.player] then
			tracker[event.player] = true
			callback(event)
			tracker[event.player] = false
		end
	end)
end

function essentials.pack_3_nums(x, y, z)
	local xi = x * 100 // 1
	local yi = y * 100 // 1
	local zi = z * 100 // 1

	local signs = 0
	if xi < 0 then
		xi = xi * -1
		signs = signs | 1 << 62
	end
	if yi < 0 then
		yi = yi * -1
		signs = signs | 1 << 61
	end
	if zi < 0 then
		zi = zi * -1
		signs = signs | 1 << 60
	end
	return signs | xi << 40 | yi << 20 | zi
end

function essentials.unpack_3_nums(packed_num)
	local sign_bit_1 <const> = packed_num & 1 << 60 ~= 0
	local sign_bit_2 <const> = packed_num & 1 << 61 ~= 0
	local sign_bit_3 <const> = packed_num & 1 << 62 ~= 0
	
	packed_num = packed_num & 0xFFFFFFFFFFFFFFF
	
	return
		sign_bit_3 and -((packed_num >> 40 & 0xFFFFF) / 100) or ((packed_num >> 40 & 0xFFFFF) / 100),
		sign_bit_2 and -((packed_num >> 20 & 0xFFFFF) / 100) or ((packed_num >> 20 & 0xFFFFF) / 100),
		sign_bit_1 and -((packed_num       & 0xFFFFF) / 100) or ((packed_num       & 0xFFFFF) / 100)
end

function essentials.pack_2_nums(x, y)
	local xi = x * 1000 // 1
	local yi = y * 1000 // 1

	local signs = 0
	if xi < 0 then
		xi = xi * -1
		signs = signs | 1 << 62
	end
	if yi < 0 then
		yi = yi * -1
		signs = signs | 1 << 61
	end
	return signs | xi << 30 | yi
end

function essentials.unpack_2_nums(packed_num)
	local sign_bit_1 <const> = packed_num & 1 << 61 ~= 0
	local sign_bit_2 <const> = packed_num & 1 << 62 ~= 0
	
	packed_num = packed_num & 0xFFFFFFFFFFFFFFF	

	return
		sign_bit_2 and -((packed_num >> 30 & 0x3FFFFFFF) / 1000) or ((packed_num >> 30 & 0x3FFFFFFF) / 1000),
		sign_bit_1 and -((packed_num	   & 0x3FFFFFFF) / 1000) or ((packed_num	   & 0x3FFFFFFF) / 1000)
end

function essentials.get_rgb(r, g, b, a)
	return 
		r
		| (g << 8) 
		| (b << 16) 
		| ((a or 0) << 24) 
end

function essentials.rgb_to_bytes(uint32_rgba)
	return
		(uint32_rgba      ) & 0xFF, -- R
		(uint32_rgba >>  8) & 0xFF, -- G
		(uint32_rgba >> 16) & 0xFF, -- B
		(uint32_rgba >> 24) & 0xFF  -- A
end

function essentials.get_max_variadic(...) -- 10% faster than select implementation
	local max = math.mininteger
	local t <const> = table.pack(...)
	for i = 1, #t do
		max = t[i] > max and t[i] or max
	end
	return max
end

do
    local _ENV <const> = {
        getmetatable = debug.getmetatable
    }
	function essentials.rawset(Table, index, value) -- Matches performance of normal rawset.
		local metatable <const> = getmetatable(Table)
		local __newindex
		if metatable then
			__newindex = metatable.__newindex
			metatable.__newindex = nil
		end
		Table[index] = value
		if __newindex then
			metatable.__newindex = __newindex
		end
		return Table
	end
end

do
    local _ENV <const> = {
        getmetatable = debug.getmetatable
    }
	function essentials.rawget(Table, index) -- Matches performance of normal rawget.
		local metatable <const> = getmetatable(Table)
		local __index
		if metatable then
			__index = metatable.__index
			metatable.__index = nil
		end
		local value <const> = value
		if __index then
			metatable.__index = __index
		end
		return value
	end
end

do
	local _ENV <const> = { -- 12% faster, 20% less garbage created
		essentials = essentials,
		getmetatable = debug.getmetatable, 
		setmetatable = setmetatable, 
		assert = essentials.assert,
		__newindex = function()
			essentials.assert(false, "Tried to modify a read-only table.")
		end,
		__pairs = function(Table)
			return next, debug.getmetatable(Table).__index
		end,
		__len = function(Table)
			return #debug.getmetatable(Table).__index
		end
	}

	function essentials.const(Table)
		assert(not getmetatable(Table) or getmetatable(Table).__is_const, "Tried to overwrite a non-const metatable while changing the table to const.")
		if not getmetatable(Table) then
			return setmetatable({}, {
				__is_const = true,
				__index = Table,
				__newindex = __newindex,
				__pairs = __pairs,
				__len = __len
			})
		else
			return Table
		end
	end
end

function essentials.const_all(Table, timeout)
	timeout = timeout or utils.time_ms() + 1000 -- In case a table with references to itself. Faster than using a tracking table. Unless I actually need to properly handle self reference, I will keep it this way.
	essentials.assert(timeout > utils.time_ms(), "Entered recursion loop while setting table to const all.")
	for key, value in pairs(Table) do
		if type(value) == "table" then
			essentials.rawset(Table, key, essentials.const_all(value, timeout))
		end
	end
	return essentials.const(Table)
end

function essentials.make_string_case_insensitive(str)
	str = str:gsub("%a", function(str)
		return "["..str:lower()..str:upper().."]"
	end)
	return str
end

function essentials.get_player_coords(pid) -- Allows you to get player coords with accurate z coordinate.
	if pid == player.player_id() then
		return player.get_player_coords(pid)
	else
		return network.network_get_last_player_pos_received_over_network(pid)
	end
end

function essentials.split_string(str, size) 
--[[
	Strings may be up to 4 bytes smaller than requested size if unicode is present. (alternative would be up to 3 bytes bigger, which cause more problems)
	This happens if it finds a unicode character that needs more space than requested size. (at the end of the string)
	Performance: split a 46k byte string (with chinese and ascii characters) by size 255 9,000 times in one second. (110 micro seconds per iteration).
	Returns a table with 1 empty string if str is empty.
--]]
	essentials.assert(size >= 4, "Failed to split string. Split size must be 4 or more.", str, size) -- Infinite loop (only if unicode is present). For consistency, 4 or more is required.
	local strings <const> = {}
	local pos, i, len <const> = 0, 1, #str
	local find <const>, sub <const> = string.find, string.sub
	local found_no_more_unicode = false
	local start_pos, end_pos = math.mininteger, math.mininteger
	repeat
		local posz <const> = pos + size
		if not found_no_more_unicode and posz > end_pos then -- Makes sure all bytes in the string is searched no more than once.
			start_pos, end_pos = find(str, "[\0-\x7F\xC2-\xFD][\x80-\xBF]+", posz > 4 and posz - 4 or 1) -- This will cause no unicode strings to be slower. Many smaller string.finds is much cheaper than one massive string.find.
			if not start_pos then
				found_no_more_unicode, end_pos, start_pos = true, math.mininteger, math.mininteger
			end
		end
		strings[i] = sub(
			str,
			pos + 1, 
			end_pos >= posz - 4 and end_pos <= posz and end_pos -- Found unicode char that fits in the requested size?
			or start_pos >= posz - 4 and start_pos <= posz and start_pos - 1 -- Found uni char, but it doesn't fit the requested size?
			or posz -- No unicode interference.
		)
		pos = pos + #strings[i]
		i = i + 1
	until pos >= len
	return strings
end

function essentials.split_string_table_by_size(string_table, size) -- Split strings will always be equal to or smaller in size than requested size
	local strings, count = {}, 0
	local strings_to_return <const> = {}

	for i = 1, #string_table do
		essentials.assert(size >= #string_table[i], "One of the strings are longer then the requested split size.", string_table[i])
		count = count + #string_table[i] + (#string_table > 0 and 1 or 0) -- Account for new lines
		if count <= size then
			strings[#strings + 1] = string_table[i]
			if i == #string_table then
				strings_to_return[#strings_to_return + 1] = table.concat(strings, "\n")
			end
		else
			strings_to_return[#strings_to_return + 1] = table.concat(strings, "\n")
			strings, count = {string_table[i]}, #string_table[i]
		end
	end

	return strings_to_return
end

function essentials.date_to_int(date)
	local day <const> = tonumber(date:match("^%d+/(%d+)/%d+$"))
	local month <const> = tonumber(date:match("^(%d+)/%d+/%d+$")) * 30
	local year <const> = tonumber(date:match("^%d+/%d+/(%d+)$")) * 365
	return day + month + year
end

function essentials.time_to_float(time)
	local hours <const> = tonumber(time:match("^(%d+):%d+:%d+$")) * 60^2
	local minutes <const> = tonumber(time:match("^%d+:(%d+):%d+$")) * 60
	local seconds <const> = tonumber(time:match("^%d+:%d+:(%d+)$"))
	return (hours + minutes + seconds) / (60^2 * 24)
end

function essentials.create_empty_file(file_path)
	essentials.assert(not utils.file_exists(file_path), "Tried to overwrite existing file:", file_path)
	local file <close> = io.open(file_path, "w+")
end

function essentials.are_all_lines_pattern_valid(str, pattern)
	local line_num = 1
	for line in str:gmatch(pattern) do
		if not pcall(function()
			return (""):find(line)
		end) then
			return false, line_num
		end
		line_num = line_num + 1
	end
	return true
end

function essentials.delete_thread(id) -- If this assert fails, it often means the thread had a runtime error.
	essentials.assert(not menu.has_thread_finished(id), "Attempted to delete a finished thread.")
	menu.delete_thread(id)
end

do
	local v3_mt <const>, v2_mt <const> = debug.getmetatable(memoize.v3()), debug.getmetatable(memoize.v2())
	function essentials.deep_copy(object, keep_meta, tracker)
		if object == nil then
			return nil
		end
		tracker = tracker or {}
		if tracker[object] then 
			return tracker[object] 
		end

		local new_object
		local object_mt <const> = debug.getmetatable(object)
		if type(object) == "table" then
			new_object = {}
			tracker[object] = new_object

			for key, value in next, object do
				new_object[essentials.deep_copy(key, keep_meta, tracker)] = essentials.deep_copy(value, keep_meta, tracker)
			end
			if keep_meta then
				setmetatable(new_object, essentials.deep_copy(debug.getmetatable(object), keep_meta, tracker))
			end
		elseif rawequal(object_mt, v3_mt) then
			new_object = v3(object.x, object.y, object.z)
		elseif rawequal(object_mt, v2_mt) then
			new_object = v2(object.x, object.y)
		else
			new_object = object
		end
		return new_object
	end
end

do
	local is_valid <const> = player.is_player_valid
	function essentials.players(me)
		local pid = -1
		if not me then
			me = player.player_id()
		end
		return function()
			repeat
				pid = pid + 1
			until pid == 32 or (me ~= pid and is_valid(pid))
			if pid ~= 32 then
				return pid
			end
		end
	end
end

function essentials.entities(Table)
	local mt <const> = debug.getmetatable(Table)
	if mt and mt.__is_const then
		Table = mt.__index
	end
	local key, Entity
	return function()
		repeat
			key, Entity = next(Table, key)
		until key == nil or entity.is_an_entity(Entity)
		return Entity, key
	end
end

essentials.FEATURE_ID_MAP = essentials.const({ -- The table keys are derived from the Feat.type property.
-- Regular feat types
	[1 << 9] = "action",
	[1 << 0] = "toggle",
	[1 << 1 | 1 << 7 | 1 << 9 ] = "action_value_f",
	[1 << 0 | 1 << 1 | 1 << 7 ] = "value_f",
	[1 << 1 | 1 << 2 | 1 << 9 ] = "action_slider",
	[1 << 0 | 1 << 1 | 1 << 2 ] = "slider",
	[1 << 1 | 1 << 5 | 1 << 10] = "autoaction_value_str",
	[1 << 1 | 1 << 2 | 1 << 10] = "autoaction_slider",
	[1 << 1 | 1 << 3 | 1 << 9 ] = "action_value_i",
	[1 << 0 | 1 << 1 | 1 << 3 ] = "value_i",
	[1 << 1 | 1 << 7 | 1 << 10] = "autoaction_value_f",
	[1 << 1 | 1 << 3 | 1 << 10] = "autoaction_value_i",
	[1 << 1 | 1 << 5 | 1 << 9 ] = "action_value_str",
	[1 << 1 | 1 << 4 | 1 << 9 ] = "action_value_str",
	[1 << 0 | 1 << 1 | 1 << 5 ] = "value_str",
	[1 << 0 | 1 << 14] = "value_str",
-- Regular feat types

	[1 << 11] = "parent", -- Both player feat & regular feat type have same id

-- Player feat types
	[1 << 9 | 1 << 15] = "action",
	[1 << 0 | 1 << 15] = "toggle",
	[1 << 1 | 1 << 7 | 1 << 9  | 1 << 15] = "action_value_f",
	[1 << 0 | 1 << 1 | 1 << 7  | 1 << 15] = "value_f",
	[1 << 1 | 1 << 2 | 1 << 9  | 1 << 15] = "action_slider",
	[1 << 0 | 1 << 1 | 1 << 2  | 1 << 15] = "slider",
	[1 << 1 | 1 << 5 | 1 << 10 | 1 << 15] = "autoaction_value_str",
	[1 << 1 | 1 << 2 | 1 << 10 | 1 << 15] = "autoaction_slider",
	[1 << 1 | 1 << 3 | 1 << 9  | 1 << 15] = "action_value_i",
	[1 << 0 | 1 << 1 | 1 << 3  | 1 << 15] = "value_i",
	[1 << 1 | 1 << 7 | 1 << 10 | 1 << 15] = "autoaction_value_f",
	[1 << 1 | 1 << 3 | 1 << 10 | 1 << 15] = "autoaction_value_i",
	[1 << 1 | 1 << 5 | 1 << 9  | 1 << 15] = "action_value_str",
	[1 << 0 | 1 << 1 | 1 << 5  | 1 << 15] = "value_str"
-- Player feat types

--[[
	1 << 0 == toggle flag
	1 << 1 == Not a parent, toggle or regular action feature?
	1 << 2 == slider flag
	1 << 3 == value_i flag
	1 << 4 == Seems to be show info, like properties of a fake friend. Only available in menu features
	1 << 5 == value_str flag
	1 << 7 == value_f flag
	1 << 9 == action flag
	1 << 10 == autoaction flag
	1 << 11 == parent flag
	1 << 14 == player_feat flag
	1 << 15 == player_feat flag
--]]

})

function essentials.sub_unicode(str, start, End)
	return str:sub(utf8.offset(str, start), utf8.offset(str, End + 1) - 1)
end

function essentials.sub_unicode_byte_len(str, start, End)
	return utf8.char(utf8.codepoint(str, start, End))
end

do -- Makes sure lead bytes aren't confused as regular characters in regex
	local gsub <const> = string.gsub
	local sub  <const> = string.sub
	local byte <const> = string.byte
	local char <const> = string.char
	local find <const> = string.find

	local conversion_callback <const> = function(str)
		local byte <const> = byte(sub(str, 1, 1))
		local lead_byte <const> = char(byte < 128 and byte + 128 or byte)
		return lead_byte..sub(str, 2, -1)
	end
	function essentials.unicode_find_2(str, pattern, pos, plain) -- Converts pattern & string's unicode into codepoint.
		return find(
			gsub(str, "[\0-\x7F\xC2-\xFD][\x80-\xBF]+", conversion_callback),
			gsub(pattern, "[\0-\x7F\xC2-\xFD][\x80-\xBF]+", conversion_callback),
			pos, 
			plain
		)
	end -- Converts lead bytes into characters that doesnt interfere with patterns
end

function essentials.get_safe_feat_name(name) -- Checks if string is valid utf8, removes corrupted bytes if not
	local str = name
	if not utf8.len(name) then
		str = name:gsub("[^A-Za-z0-9%s%p%c]", "")
	end
	return str
end

function essentials.wait_conditional(duration, func, ...)
	local duration <const> = duration
	local func <const> = func
	essentials.assert(duration > 0, "Duration must be longer than 0.", duration)
	local time <const> = utils.time_ms() + duration
	repeat -- Must guarantee one yield or else there's a possibility of loops without yield
		system.yield(0)
	until not func(...) or utils.time_ms() > time
end

function essentials.write_table_recursively_to_file(Table, tracker, file, level) -- File is written in json format.
	tracker = tracker or {}
	level = level or 0
	file = file or io.open(paths.home.."scripts\\printed_table.txt", "w+")
	if level == 0 then
		file:write("{\n")
	end
	for key, value in pairs(Table) do
		if type(value) == "table" and not tracker[value] then
			file:write(string.format("\n%s\"%s\": {\n", string.rep("\t", level), key))
			tracker[value] = true
			essentials.write_table_recursively_to_file(value, tracker, file, level + 1)
			if next(Table, key) == nil then -- Some json parsers fails if there's a comma at the last entry in an array
				file:write(string.rep("\t", level).."}\n\n")
			else
				file:write(string.rep("\t", level).."},\n\n")
			end
		else
			if next(Table, key) == nil then -- Some json parsers fails if there's a comma at the last entry in an array
				file:write(string.format("%s\"%s\": %s\n", string.rep("\t", level), key, value))
			else
				file:write(string.format("%s\"%s\": %s,\n", string.rep("\t", level), key, value))
			end
		end
	end
	if level == 0 then
		file:write("}\n")
		file:flush()
		file:close()
		return essentials.get_file_string(paths.home.."scripts\\printed_table.txt")
	end
end

do
	local files_extensions <const> = { -- Those allowed by the api
		"txt",
		"log",
		"xml",
		"ini",
		"cfg",
		"csv",
		"json",
		"lua",
		"2t1",
		"jpg",
		"jpeg",
		"png",
		"gif",
		"bmp",
		"dds"
	}
	function essentials.get_all_files_recursively(path, obtained_folders)
		obtained_folders = obtained_folders or {}
		
		local folders <const> = utils.get_all_sub_directories_in_directory(path)
		for i = 1, #folders do
			obtained_folders[path] = essentials.get_all_files_recursively(path.."\\"..folders[i], obtained_folders[path])
		end
		obtained_folders[path] = obtained_folders[path] or {}
		
		for i = 1, #files_extensions do
			local files <const> = utils.get_all_files_in_directory(path, files_extensions[i])
			table.move(files, 1, #files, #obtained_folders[path] + 1, obtained_folders[path])
		end

		return obtained_folders
	end

	function essentials.get_all_files_recursively_without_map(path, files)
		files = files or {}
		
		local folders <const> = utils.get_all_sub_directories_in_directory(path)
		for i = 1, #folders do
			essentials.get_all_files_recursively_without_map(path.."\\"..folders[i], files)
		end
		
		for i = 1, #files_extensions do
			local folder_files <const> = utils.get_all_files_in_directory(path, files_extensions[i])
			table.move(folder_files, 1, #folder_files, #files + 1, files)
		end

		return files
	end
end

function essentials.is_file_name_change_is_invalid(folder_path, input, extension)
	if input:find("..", 1, true) or input:find("%.$") then
		essentials.msg(lang["There can't be a \"..\" in the name. There also can't be a \".\" at the end of the name."], "red")
		return true
	elseif input:find("[<>:\"/\\|%?%*]") then
		essentials.msg(lang["Illegal characters detected. Please try again. Illegal chars:"].." \"<\", \">\", \":\", \"/\", \"\\\", \"|\", \"?\", \"*\"", "red", 7)
		return true
	elseif extension ~= "FOLDER" and not utils.dir_exists(folder_path) then
		essentials.msg(lang["This folder no longer exists."], "red", 8)
		return true
	elseif extension == "FOLDER" and utils.dir_exists(folder_path.."\\"..input) then
		essentials.msg(lang["Existing folder found. Please choose another name."], "red")
		return true
	elseif extension ~= "FOLDER" and utils.file_exists(folder_path.."\\"..input.."."..extension) then
		essentials.msg(lang["Existing file found. Please choose another name."], "red")
		return true
	end
end

function essentials.table_to_xml(...)
	local Table <const>,
	tabs,
	name <const>,
	lines <const>,
	_return,
	timeout = ...
	timeout = timeout or utils.time_ms() + 1000 -- In case of recursion loop
	if name then
		lines[#lines + 1] = string.format("%s<%s>", ("\t"):rep(tabs - 1), name)
	end
	local tab_string <const> = ("\t"):rep(tabs)
	for property_name, property in pairs(Table) do
		if type(property) == "table" then
			tabs = tabs + 1
			essentials.table_to_xml(property, tabs, property_name, lines, nil, timeout)
			tabs = tabs - 1
		else
			lines[#lines + 1] = string.format("%s<%s>%s</%s>", tab_string, property_name, tostring(property), property_name)
		end
	end
	if name then
		local line
		if (type(name) == "string" and name or tostring(name)):find("=", 1, true) then
			line = string.format("%s</%s>", ("\t"):rep(tabs - 1), name:match("^%S+"))
		else
			line = string.format("%s</%s>", ("\t"):rep(tabs - 1), name)
		end
		lines[#lines + 1] = line
	end
	essentials.assert(timeout > utils.time_ms(), "Entered recursion loop while attempting to convert table to xml.")
	if _return then
		return table.concat(lines, "\n")
	end
end

local function cast_string_element(string_element)
	if string_element:find(",", 1, true) then
		local string_elements = {}
		for string_element in string_element:gmatch("([^,%s]+)") do
			string_elements[#string_elements + 1] = cast_string_element(string_element)
		end
		return string_elements
	elseif string_element == "false" then
		return false
	else
		return
			string_element == "true"
			or tonumber(string_element)
			or tonumber(string_element, 16)
			or tonumber("0x"..string_element) -- The former tonumber doesn't support hexadecimal with fractions.
			or string_element
	end
end

local function parse_attribute(str)
	local name <const>, where <const> = str:match("^<([^\32>]+)()")
	local values
	if str:find("=", where + 1, true) then
		values = {}
		for index, value in str:gmatch("([^=]+)=[\"']([^=]+)[\"'][\32>]", where + 1) do
			values[index] = cast_string_element(value)
		end
	end
	return name, values
end

--[[
	DOM XML parser. Read only.
	Supports:
		Fundamentals
		Multi-line elements. Such as a paragraph. Tabs at start of each line are also removed.
		Multi-line elements must start its value on the same line as the same. <name>\n would have it ignore its content.
		Multiple values in a element separated by comma
		Ignore single line & multi line comment, empty lines & nodes with no values
		Escape sequences
		Attributes, but only for node parents & tags
		Multiple roots, if the roots have different names
		Duplicate parent and child names. They are converted to a new node & split up into nodes, starting from 1, 2, 3...
	
	Does not support:
		Defining types (schema)
		DOCTYPE declaration
		CSS
		Loading files

	This parser is meant to be as fast as possible.
	Prologue is info.prologue
	Performance: Parsed a 15k lines menyoo vehicle in 28ms.
	Parses are remembered until garbage collector is collecting.
--]]

local __is_table_mt <const> = {__index = {__is_table = true}}

local accepted_whitespace <const> = "[\t\n\r]"
local escape_seq_map <const> = {
	["&quot;"] = "\"",
	["&apos;"] = "'",
	["&lt;"] = "<",
	["&gt;"] = ">",
	["&amp;"] = "&"
}

local memoized <const> = setmetatable({}, {__mode = "vk"})
function essentials.parse_xml(str)
	if memoized[str] then
		return memoized[str]
	else
		memoized[str] = {}
	end
	local find <const> = string.find
	local gsub <const> = string.gsub
	local match <const> = string.match
	local setmetatable <const> = setmetatable
	local parse_attribute <const> = parse_attribute
	local cast_string_element <const> = cast_string_element

	local info = memoized[str]

	if not str:find(accepted_whitespace, -1) then
		str = str.."\n" -- This is extremely expensive, but adapting the entire parser is worse
	end -- Completely fails to parse anything if last char isn't whitespace.
	-- Must have both \r and \n. Missing \r will make certain files like BIGHEAD AngryDoggo unparseable.

	local memoized <const> = {}
	local parent_tree <const> = {}
	if pcall(function()
		local start_of_first_line <const> = find(str, "<?", 1, true) -- some files have hidden characters in its first line
		local end_of_first_line <const> = select(2, find(str, "\n", start_of_first_line, true))
		local first_line <const> = str:sub(start_of_first_line, end_of_first_line - 1)
		info.prologue = select(2, parse_attribute(first_line:gsub("%?", "")))
	end) then

		for line in str:gmatch("<.->%f"..accepted_whitespace) do
			memoized[line] = memoized[line] or {
				new_value_find = find(line, "^<.+>.+</.+>$"),
				is_comment = find(line, "^<!%-%-"),
				index = false,
				value = false
			}
			local memoized <const> = memoized[line]
			if memoized.is_comment then
				goto continue
			end
			if memoized.new_value_find then
				if not memoized.index then
					local value = gsub(match(line, ">([^<>]+)</"), "\n\t*", "\n")
					value = gsub(value, "&%a%a%a?%a?;", escape_seq_map)
					memoized.index = match(line, "^<([^>]+)>")
					memoized.value = cast_string_element(value)
				end
				local parent <const> = parent_tree[#parent_tree][memoized.index]
				if parent then
					if parent.__is_table then
						parent[#parent + 1] = memoized.value
					else
						parent_tree[#parent_tree][memoized.index] = setmetatable({parent, memoized.value}, __is_table_mt)
					end
				else
					parent_tree[#parent_tree][memoized.index] = memoized.value
				end
				goto continue
			end

			memoized.new_tag_find = memoized.new_tag_find or find(line, "^<.+/>$")
			if memoized.new_tag_find then
				local name <const>, attributes <const> = parse_attribute(line)
				if parent_tree[#parent_tree][name] then
					local mt <const> = getmetatable(parent_tree[#parent_tree][name])
					mt.__count = mt.__count + 1
					parent_tree[#parent_tree][name.."_"..mt.__count] = {__attributes = attributes}
				else
					parent_tree[#parent_tree][name] = setmetatable({__attributes = attributes}, {__count = 1})
				end
				goto continue
			end

			memoized.new_parent_find = memoized.new_parent_find or find(line, "^<[^/?][^<>]+>$")
			if memoized.new_parent_find then
				local name <const>, attributes <const> = parse_attribute(line) -- Each set of attributes must have its own unique table so it can be modified without affecting others.
				parent_tree[#parent_tree + 1] = {__attributes = attributes}
				parent_tree[#parent_tree].__name = name
				goto continue
			end

			memoized.parent_end = memoized.parent_end or (#parent_tree > 0 and find(line, "</"..parent_tree[#parent_tree].__name..">", 1, true))
			if memoized.parent_end then
				local child <const> = parent_tree[#parent_tree]
				local parent <const> = parent_tree[#parent_tree - 1]
				if #parent_tree == 1 then
					info[child.__name] = child
				else
					local value <const> = parent[child.__name]
					if value then
						if value.__is_table then
							value[#value + 1] = child
						else
							parent[child.__name] = setmetatable({parent[child.__name], child}, __is_table_mt)
						end
					else
						parent[child.__name] = child
					end
				end
				child.__name = nil
				parent_tree[#parent_tree] = nil
			end
			::continue::
		end
	end
	return info
end

function essentials.is_z_coordinate_correct(pos)
	return pos.z ~= -50 and pos.z ~= -180 and pos.z ~= -190
end

function essentials.get_random_string(...)
	local rand_min <const>,
	rand_max <const>,
	max <const> = ...
	local vecu64_table <const> = {}
	for i = 1, math.random(rand_min or 1, rand_max or 12) do
		vecu64_table[#vecu64_table + 1] = math.random(1, max or math.maxinteger)
	end
	return utils.vecu64_to_str(vecu64_table)
end

do
	local notif_colors <const> = {
		red = 0xff0000ff,
		yellow = 0xff00ffff,
		blue = 0xffff0000,
		green = 0xff00ff00,
		purple = 0xff800080,
		orange = 0xff0080ff,
		brown = 0xff336699,
		pink = 0xffff00ff
	}

	local header_text <const> = lang["Kek's menu"].." "..__kek_menu.version

	function essentials.msg(...)
		local message_text <const>, color_name <const>, duration <const> = ...

		essentials.assert(notif_colors[color_name], "Invalid color to notification.", color_name, message_text, type(message_text))

		essentials.assert(type(message_text) == "string", "Expected a string for the notification's text.", message_text, type(message_text))

		menu.notify(
			message_text, 
			header_text, 
			duration or 5, 
			notif_colors[color_name]
		)
	end
end

function essentials.is_in_vehicle(pid)
	return player.is_player_in_any_vehicle(pid) or player.get_player_coords(pid).z == -50
end

--[[
	The purpose of counting and limiting the ptfx is to prevent crashes.
	Spamming ptfx will always lead to a crash.
--]]
essentials.ptfx_in_use = {}
local function ptfx_count()
	repeat
		local status = true
		for i = 1, #essentials.ptfx_in_use do
			if utils.time_ms() > essentials.ptfx_in_use[i] then
				table.remove(essentials.ptfx_in_use, i)
				status = false
				break
			end
		end
	until status
	return #essentials.ptfx_in_use <= 180
end
function essentials.request_ptfx(...)
	local str_asset <const> = ...
	if ptfx_count() then
		graphics.request_named_ptfx_asset(str_asset)
		local time <const> = utils.time_ms() + 400
		while not graphics.has_named_ptfx_asset_loaded(str_asset) and time > utils.time_ms() do
			system.yield(0)
		end
		if graphics.has_named_ptfx_asset_loaded(str_asset) then
			graphics.set_next_ptfx_asset(str_asset)
			return true
		end
	end
end

function essentials.request_anim_dict(dict)
	local time <const> = utils.time_ms() + 500
	streaming.request_anim_dict(dict)
	while time > utils.time_ms() and not streaming.has_anim_dict_loaded(dict) do
		system.yield(0)
	end
	return streaming.has_anim_dict_loaded(dict)
end

function essentials.request_anim_set(anim_set)
	local time <const> = utils.time_ms() + 500
	streaming.request_anim_set(anim_set)
	while time > utils.time_ms() and not streaming.has_anim_set_loaded(anim_set) do
		system.yield(0)
	end
	return streaming.has_anim_set_loaded(anim_set)
end

local ptfx_cost_exceptions <const> = essentials.const({
	[gameplay.shoot_single_bullet_between_coords] = 1000,
	[graphics.start_networked_ptfx_looped_on_entity] = 6000
})

function essentials.use_ptfx_function(func, ...)
	local func <const> = func
	if ptfx_count() then
		essentials.ptfx_in_use[#essentials.ptfx_in_use + 1] = utils.time_ms() + (ptfx_cost_exceptions[func] or 3000)
		return func(...)
	end
end

function essentials.is_not_friend(pid)
	return not settings.toggle["Exclude friends from attacks"].on or not network.is_scid_friend(player.get_player_scid(pid))
end

function essentials.kick_player(pid)
	essentials.assert(pid ~= player.player_id(), "Tried to kick yourself.")
	return network.force_remove_player(pid)
end

do
	local msg_queue <const> = {}
	local id = 0
	function essentials.send_message(...)
		local text, team <const> = ...
		if not utf8.len(text) then -- split_string requires valid utf8
			text = text:gsub("[\0-\x7F\xC2-\xFD][\x80-\xBF]+", "")
			text = text:gsub("[\x80-\xFF]", "")
		end
		local local_id = id + 1
		id = local_id
		msg_queue[#msg_queue + 1] = local_id
		while msg_queue[1] ~= local_id do
			system.yield(0)
		end
		local strings <const> = essentials.split_string(text, 255)
		for i = 1, math.min(#strings, 50) do
			network.send_chat_message(strings[i], team == true)
			system.yield(100)
		end
		if #strings == 0 then -- Some features rely on this function yielding. [chat spam is example]
			system.yield(100)
		end
		table.remove(msg_queue, 1)
	end
end

function essentials.binary_search(Table, value) -- Only use if table is sorted in ascending numbers.
	local left, mid, right = 1, 0, #Table
	while left <= right do
		local mid <const> = (left + right) // 2
		if Table[mid] < value then
			left = mid + 1
		elseif Table[mid] > value then
			right = mid - 1
		else
			return mid
		end
	end
end

function essentials.get_index_of_value(...)
	local Table <const>, value_to_find_index_of <const> = ...
	for i, value in pairs(Table) do
		if value_to_find_index_of == value then
			return i
		end
	end
end

function essentials.get_random_player_except(...)
	local exclusions <const> = ...
	essentials.assert(select(2, next(exclusions)) == true, "Invalid exclusions table.")
	local pids <const> = {}
	for pid in essentials.players(true) do
		if not exclusions[pid] then
			pids[#pids + 1] = pid
		end
	end
	if #pids > 0 then
		return pids[math.random(1, #pids)]
	else
		local pids <const> = {}
		for pid in essentials.players(true) do
			pids[#pids + 1] = pid
		end
		return pids[math.random(1, #pids)]
	end
end

do
	local special_char_map <const> = essentials.const({
		["%"] = "%%",
		["["] = "%[",
		["]"] = "%]",
		["("] = "%(",
		[")"] = "%)",
		["-"] = "%-",
		["+"] = "%+",
		["?"] = "%?",
		["*"] = "%*",
		["^"] = "%^",
		["$"] = "%$",
		["."] = "%."
	})
	
	function essentials.remove_special(text)
		local str <const> = text:gsub("[%%%[%]%(%)%-%+%?%*%^%$%.]", special_char_map)
		return str
	end
end

function essentials.get_file_string(file_path, mode)
	local file <close> = io.open(file_path, mode or "r")
	if file and io.type(file) == "file" then
		return file:read("*a") or ""
	else
		return ""
	end
end

function essentials.get_descendants(...)
	local parent <const>,
	Table,
	add_parent_of_descendants <const> = ...
	local children <const> = parent.children
	for i = 1, #children do
		local feat <const> = children[i]
		if feat.type & 1 << 11 == 1 << 11 and feat.child_count > 0 then
			essentials.get_descendants(feat, Table)
		end
		Table[#Table + 1] = feat
	end
	if add_parent_of_descendants then
		Table[#Table + 1] = parent
	end
	return Table
end

function essentials.get_player_descendants(...)
	local parent <const>,
	Table,
	add_parent_of_descendants <const> = ...
	for _, feat in pairs(parent.feats[0].children) do
		feat = menu.get_player_feature(feat.id)
		if feat.feats[0].type == 2048 and feat.child_count > 0 then
			essentials.get_player_descendants(menu.get_player_feature(feat.id), Table)
		end
		Table[#Table + 1] = menu.get_player_feature(feat.id)
	end
	if add_parent_of_descendants then
		Table[#Table + 1] = parent
	end
	return Table
end

function essentials.get_feat_hierarchy(feat, tab)
	local str <const>, parent = {}, feat.parent
	while parent do
		local encoded_parent_name = parent.name:gsub("[%s%p%c]", "_")
		table.insert(str, 1, encoded_parent_name)
		parent = parent.parent
	end
	local encoded_feat_name = feat.name:gsub("[%s%p%c]", "_")
	table.insert(str, 1, tab or "local")
	str[#str + 1] = encoded_feat_name
	return table.concat(str, ".")
end

function essentials.player_feat_to_pid(feat)
	local player_name_map <const> = {}
	for pid in essentials.players(true) do
		player_name_map[player.get_player_name(pid)] = pid
	end
	local parent = feat.parent
	while parent and not player_name_map[parent.name] do
		parent = parent.parent
	end
	return player_name_map[parent and parent.name]
end

function essentials.name_to_pid(name)
	if type(name) == "string" then
		name = name:lower()
		for pid in essentials.players(true) do
			if player.get_player_name(pid):lower():find(name, 1, true) then
				return pid
			end
		end
	end
	return 32
end

function essentials.name_to_pid_strict(name)
	for pid in essentials.players(true) do
		if player.get_player_name(pid) == name then
			return pid
		end
	end
	return 32
end

function essentials.how_many_people_named(pid)
	local name <const> = player.get_player_name(pid)
	local scid <const> = player.get_player_scid(pid)
	local ip <const> = player.get_player_ip(pid)
	local count = 0
	for pid in essentials.players(true) do
		if name == player.get_player_name(pid) 
		or scid == player.get_player_scid(pid) 
		or ip == player.get_player_ip(pid) then
			count = count + 1
		end
	end
	return count
end

function essentials.get_ped_closest_to_your_pov()
	local spectate_target <const> = network.get_player_player_is_spectating(player.player_id())
	if spectate_target then
		return player.get_player_ped(spectate_target)
	else
		return player.get_player_ped(player.player_id())
	end
end

function essentials.is_any_true(...)
	local Table <const>, conditions <const> = ...
	for i = 1, #Table do
		if conditions(Table[i]) then
			return true
		end
	end
	return false
end

function essentials.is_any_virtual_key_pressed(...)
	for i = 1, select("#", ...) do
		local Key <const> = MenuKey()
		Key:push_str(select(i, ...))
		if Key:is_down_stepped() then
			return true
		end
	end
	return false
end

do
	local _1440p_magnitude <const> = math.sqrt(2560^2 + 1440^2) -- Faster to find magnitude manually than creating v2 objects.
	function essentials.correct_scale_for_resolution(scale, text)
		local width <const> = graphics.get_screen_width()
		local height <const> = graphics.get_screen_height()

		local size_adjust_width = width * 0.995
		local size_adjust_height = height * 0.995

		local new_scale <const> = scale * ((width^2 + height^2)^0.5 / _1440p_magnitude)

		local size <const> = scriptdraw.get_text_size(text, new_scale)

		local size_correction = 1.0 -- Handles text being too big for the screen
		if size.x > size_adjust_width then
			size_correction = size_adjust_width / size.x
		end

		if size.y > size_adjust_height and size_correction > size_adjust_height / size.y then
			size_correction = size_adjust_height / size.y
		end

		return new_scale * size_correction
	end
end

function essentials.draw_text_prevent_offscreen(...)
	local text <const>, 
	pos <const>, -- Coordinates must be in relative, not pixels
	scale,
	rgba <const>,
	outline <const> = ...

	scale = essentials.correct_scale_for_resolution(scale, text)

	pos.x = pos.x < -0.995 and -0.995 or pos.x
	pos.y = pos.y > 0.995 and 0.995 or pos.y

	local size <const> = scriptdraw.get_text_size(text, scale, nil)
	size.x = scriptdraw.size_pixel_to_rel_x(size.x)
	size.y = scriptdraw.size_pixel_to_rel_y(size.y)

	pos.x = pos.x + size.x > 0.995 and 0.995 - size.x or pos.x
	pos.y = pos.y - size.y < -0.995 and -0.995 + size.y or pos.y
	scriptdraw.draw_text(
		text, 
		pos,
		size,
		scale,
		rgba,
		outline and enums.scriptdraw_flags.shadow or 0,
		nil
	)
end

function essentials.draw_auto_adjusted_text(...) 

-- REMEMBER, IF MULTIPLE DRAWS ARE RELATED, THEY MUST USE "dont_adjust_scale", and pass an already handled scale to all draws. essentials.show_changelog does this.
-- This is only relevant if the text size varies, and scaling down to fit the screen occurs.

	local text <const>, rgba <const>, scale, y_pos <const>, dont_adjust_scale <const> = ...

	if not dont_adjust_scale then -- To have scales matched if 2 scriptdraws are matched together
		scale = essentials.correct_scale_for_resolution(scale or 0.7, text)
	end

	local size <const> = scriptdraw.get_text_size(text, scale, nil)
	size.x = scriptdraw.size_pixel_to_rel_x(size.x)
	size.y = scriptdraw.size_pixel_to_rel_y(size.y)

	local pos <const> = v2(-size.x, size.y) / 2
	pos.y = type(y_pos) == "table" and y_pos.y or y_pos or pos.y

	scriptdraw.draw_text(
		text, 
		pos,
		size,
		scale,
		rgba,
		enums.scriptdraw_flags.shadow,
		nil
	)

	return (pos.y - size.y) - (scriptdraw.size_pixel_to_rel_y(scriptdraw.get_text_size("One line of text.", scale or 0.7, nil).y) / 2)
end

function essentials.dont_retry_request(status) -- Too much work with little benefit to handle all codes properly
	return enums.html_response_codes[status] ~= "OK" and enums.html_response_codes[status] ~= "Not Found"
end

function essentials.web_get_file(url, rgba, scale, y_pos)
	local try_count = 0
	local file_name <const> = web.urldecode(url:match(".+/(.-)$"))
	local status, str, is_done
	local thread <const> = essentials.create_thread(function()
		while true do
			essentials.draw_auto_adjusted_text(
				is_done and enums.html_response_codes[status] == "OK" and lang["Successfully fetched %s."]:format(file_name)
				or is_done and lang["Failed to fetch %s with error: %s"]:format(file_name, enums.html_response_codes[status] or status)
				or lang["Attempt %s / %s to fetch %s."]:format(try_count, 3, file_name), 

				is_done and enums.html_response_codes[status] == "OK" and essentials.get_rgb(0, 255, 0, 255) 
				or is_done and essentials.get_rgb(255, 0, 0, 255) 
				or rgba, 
				
				scale,
				y_pos
			)
			system.yield(0)
		end
	end)
	system.yield(0)
	repeat
		if try_count > 0 then
			system.yield(2000)
		end
		try_count = try_count + 1
		status, str = web.get(url)
	until try_count == 3 or not essentials.dont_retry_request(status)
	is_done = true
	system.yield(enums.html_response_codes[status] ~= "OK" and 5000 or 250)
	essentials.delete_thread(thread)
	return status, str
end

essentials.is_changelog_currently_shown = false
function essentials.show_changelog()
	if not essentials.is_changelog_currently_shown then
		essentials.is_changelog_currently_shown = true
		essentials.create_thread(function()
			while essentials.is_any_virtual_key_pressed(
				"LCONTROL",
				"RCONTROL",
				"SPACE"
			) do
				system.yield(0)
			end
			local github_branch_name <const> = 
				__kek_menu.participate_in_betas and "beta" 
				or language.what_language == "Chinese.txt" and "chinese"
				or "main"


			local status <const>, str <const> = essentials.web_get_file(
				"https://raw.githubusercontent.com/kektram/Keks-menu/"..github_branch_name.."/Changelog.md",
				essentials.get_rgb(0, 255, 0, 255), 
				1.2
			)
			if enums.html_response_codes[status] ~= "OK" then
				essentials.is_changelog_currently_shown = false
				return
			end

			local str_t <const> = {}
			for line in str:gmatch("[^\n]+") do
				str_t[#str_t + 1] = line
			end

			local str <const> = table.concat(str_t, "\n")
			local scale <const> = essentials.correct_scale_for_resolution(0.7, str.."\n"..lang["Press space or ctrl to remove this message."].."\n\nfiller text")
			while not essentials.is_any_virtual_key_pressed(
				"LCONTROL",
				"RCONTROL",
				"SPACE"
			) do
				local y_pos <const> = essentials.draw_auto_adjusted_text(str, essentials.get_rgb(255, 140, 0, 255), scale, nil, true)
				essentials.draw_auto_adjusted_text(lang["Press space or ctrl to remove this message."], essentials.get_rgb(255, 0, 0, 255), scale, y_pos, true)
				system.yield(0)
			end
			while essentials.is_any_virtual_key_pressed(
				"LCONTROL",
				"RCONTROL",
				"SPACE"
			) do
				system.yield(0)
			end
			essentials.is_changelog_currently_shown = false
		end, nil)
	end
end

function essentials.update_keks_menu()
	system.yield(0) -- Prevent stuff from being drawn while you're waiting for gta to load
	local github_branch_name <const> = __kek_menu.participate_in_betas and "beta" or "main"
	local base_path <const> = "https://raw.githubusercontent.com/kektram/Keks-menu/"..github_branch_name.."/"
	local y_pos_2 <const> = {y = 0} -- Is table so most up-to-date value is always being used
	local version_check_draw_thread <const> = essentials.create_thread(function()
		while true do
			y_pos_2.y = essentials.draw_auto_adjusted_text(lang["Obtaining Kek's menu version info..."], essentials.get_rgb(255, 140, 0, 255), 1.0)
			system.yield(0)
		end
	end, nil)
	system.yield(0)
	local status <const>, update_details = essentials.web_get_file(
		base_path.."VERSION.lua",
		essentials.get_rgb(0, 255, 120, 255),
		1.0,
		y_pos_2
	)
	essentials.delete_thread(version_check_draw_thread)
	local
		update_status,
		current_file_num,
		lib_file_strings, 
		language_file_strings, 
		current_file,
		html_page_info,
		kek_menu_file_string = true, 0, {}, {}

	if enums.html_response_codes[status] ~= "OK" then
		essentials.msg(lang["Failed to check what the latest version of the script is."], "red", 6)
		return "failed to check what is the latest version"
	end
	update_details = load(update_details, "Update info", "t", {})()
	local script_version <const> = update_details.version
	local updated_lib_files <const> = update_details.libs
	local updated_language_files <const> = update_details.language_files

	if __kek_menu.version == script_version then
		essentials.msg(lang["You have the latest version of Kek's menu."], "green", 3)
		return "is latest version"
	else
		if __kek_menu_has_done_update then
			essentials.msg(lang["Kektram messed up the version strings! You have the latest version."], "green", 8)
			return "already updated"
		end
		while essentials.is_any_virtual_key_pressed( -- Prevent accidental presses
			"ALT",
			"LCONTROL",
			"RCONTROL",
			"SPACE",
			"RETURN",
			"LSHIFT",
			"RSHIFT",
			"TAB"
		) do
			system.yield(0)
		end

		local time = utils.time_ms() + 25000
		while not essentials.is_any_virtual_key_pressed("ALT", "RETURN") and time > utils.time_ms() do

			local y_pos <const> = essentials.draw_auto_adjusted_text(lang["A new update for Kek's menu is available. Press alt or enter to install it, space or ctrl to not."], essentials.get_rgb(255, 140, 0, 255), 1.0)
			local y_pos <const> = essentials.draw_auto_adjusted_text(lang["Press shift or tab to show changelog."], essentials.get_rgb(255, 0, 0, 255), 1.0, y_pos)
			essentials.draw_auto_adjusted_text(lang["This message will disappear in %s seconds and will assume you don't want the update."]:format(math.ceil((time - utils.time_ms()) / 1000)), essentials.get_rgb(255, 140, 0, 255), 1.0, y_pos)

			if essentials.is_any_virtual_key_pressed("TAB", "LSHIFT", "RSHIFT") then
				while essentials.is_any_virtual_key_pressed("TAB", "LSHIFT", "RSHIFT") do
					system.yield(0)
				end
				essentials.show_changelog()
				while essentials.is_changelog_currently_shown do
					system.yield(0)
				end
				while essentials.is_any_virtual_key_pressed("TAB", "LSHIFT", "RSHIFT") do
					system.yield(0)
				end
				time = utils.time_ms() + 25000
			end
			if essentials.is_any_virtual_key_pressed("SPACE", "LCONTROL", "RCONTROL") then
				return "Cancelled update"
			end
			system.yield(0)
		end
		if not essentials.is_any_virtual_key_pressed("ALT", "RETURN") then
			return "Cancelled update"
		end

		if __kek_menu.debug_mode then
			essentials.msg(lang["Turn off debug mode to use auto-updater."], "red", 6)
			return "tried to update with debug mode on"
		end

		essentials.create_thread(function()
			while update_status ~= "done" do
				y_pos_2.y = essentials.draw_auto_adjusted_text(
					string.format(
						"%i / %i "..lang["files downloaded"].." [%s]", 
						current_file_num, 
						#updated_lib_files + #updated_language_files + 1, 
						current_file
					),
					essentials.get_rgb(0, 255, 0, 255), 
					1.2, 
					y_pos
				)
				system.yield(0)
			end
		end, nil)

	end
	do
		current_file = "Kek's menu.lua" -- Download updated files
		local status <const>, str <const> = essentials.web_get_file(
			base_path.."Kek's%20menu.lua",
			essentials.get_rgb(0, 255, 0, 255), 
			1.2, 
			y_pos_2
		)
		update_status = enums.html_response_codes[status] == "OK"
		if not update_status then
			goto exit
		end
		kek_menu_file_string = str
		current_file_num = current_file_num + 1
	end

	for i = 1, #updated_lib_files do
		current_file = updated_lib_files[i]
		local status <const>, str <const> = essentials.web_get_file(
			base_path.."kek_menu_stuff/kekMenuLibs/"..updated_lib_files[i]:gsub("\32", "%%20"),
			essentials.get_rgb(0, 255, 0, 255), 
			1.2, 
			y_pos_2
		)
		update_status = enums.html_response_codes[status] == "OK"
		if not update_status then
			goto exit
		end
		lib_file_strings[updated_lib_files[i]] = str
		current_file_num = current_file_num + 1
	end

	for i = 1, #updated_language_files do
		current_file = updated_language_files[i]
		local status <const>, str <const> = essentials.web_get_file(
			base_path.."kek_menu_stuff/kekMenuLibs/Languages/"..updated_language_files[i]:gsub("\32", "%%20"),
			essentials.get_rgb(0, 255, 0, 255), 
			1.2, 
			y_pos_2
		)
		update_status = enums.html_response_codes[status] == "OK"
		if not update_status then
			goto exit
		end
		language_file_strings[updated_language_files[i]] = str
		current_file_num = current_file_num + 1
	end

	::exit::
	if __kek_menu.version ~= script_version then
		if update_status then
			do -- Checks if there's write permissions to all files that needs to be overwritten.
				local msg <const> = lang["Missing write permissions for \"%s\". Update cancelled, no files changed."]
				local file <close> = io.open(paths.home.."scripts\\Kek's menu.lua", "a")
				if utils.file_exists(paths.home.."scripts\\Kek's menu.lua") and not file then
					essentials.msg(msg:format("Kek's menu.lua"), "red", 10)
					update_status = "done"
					return "missing write permissions"
				end

				for file_name in pairs(lib_file_strings) do
					local file_path <const> = paths.kek_menu_stuff.."kekMenuLibs\\"..file_name
					if utils.file_exists(file_path) then
						local file <close> = io.open(file_path, "a")
						if not file then
							essentials.msg(msg:format(file_name), "red", 10)
							update_status = "done"
							return "missing write permissions"
						end
					end
				end

				for file_name in pairs(language_file_strings) do
					local file_path <const> = paths.kek_menu_stuff.."kekMenuLibs\\Languages\\"..file_name
					if utils.file_exists(file_path) then
						local file <close> = io.open(file_path, "a")
						if not file and language_file_strings[file_name] then
							essentials.msg(msg:format(file_name), "red", 10)
							update_status = "done"
							return "missing write permissions"
						end
					end
				end
			end

			__kek_menu.version = script_version
			essentials.msg(lang["Update successfully installed."], "green", 6)

			-- Remove old files & undo all changes to the global space
			for _, file_name in pairs(utils.get_all_files_in_directory(paths.kek_menu_stuff.."kekMenuLibs", "lua")) do
				package.loaded[file_name:sub(1, -5)] = nil
				io.remove(paths.kek_menu_stuff.."kekMenuLibs\\"..file_name)
			end
			for _, file_name in pairs(utils.get_all_files_in_directory(paths.kek_menu_stuff.."kekMenuLibs\\Languages", "txt")) do
				io.remove(paths.kek_menu_stuff.."kekMenuLibs\\Languages\\"..file_name)
			end

			local file <close> = io.open(paths.home.."scripts\\Kek's menu.lua", "w+b")
			file:write(kek_menu_file_string)
			file:flush()

			-- Copy new files to their desired locations
			for file_name in pairs(lib_file_strings) do
				local file <close> = io.open(paths.kek_menu_stuff.."kekMenuLibs\\"..file_name, "w+b")
				file:write(lib_file_strings[file_name])
				file:flush()
			end

			for file_name in pairs(language_file_strings) do
				local file <close> = io.open(paths.kek_menu_stuff.."kekMenuLibs\\Languages\\"..file_name, "w+b")
				file:write(language_file_strings[file_name])
				file:flush()
			end

			update_status = "done"
			system.yield(0)
			essentials.show_changelog()
			system.yield(0) -- show_changelog creates a thread
			__kek_menu = nil
			__kek_menu_has_done_update = true
			dofile(paths.home.."scripts\\Kek's menu.lua")
			return "has updated"
		else
			update_status = "done"
			essentials.msg(lang["Update failed. No files are changed."], "green", 6)
			return "failed update"
		end
	end
end

function essentials.is_all_true(...)
	local Table <const>, conditions <const> = ...
	for i = 1, #Table do
		if not conditions(Table[i]) then
			return false
		end
	end
	return true
end

function essentials.round(num)
	local floor <const> = math.floor(num) -- Must be math.floor, floor division. Floor division returns a float.
	if num - 0.5 >= floor then
		return math.ceil(num)
	else
		return floor
	end
end

function essentials.random_real(...)
	local a, b <const> = ...
	local power <const> = math.min(18 - #tostring(a), 17 - #tostring(b))
	a = math.random(a * 10^power, b * 10^power)
	return a / 10^power
end

function essentials.set_all_player_feats_except(...)
	local player_feat_id <const>,
	bool <const>,
	exclusions <const> = ...
	essentials.assert(select(2, next(exclusions)) == true, "Invalid exclusions table.")
	for pid = 0, 31 do
		if not exclusions[pid] then
			menu.get_player_feature(player_feat_id).feats[pid].on = bool == true
		end
	end
end

function essentials.dec_to_ipv4(ip)
	return string.format(
		"%i.%i.%i.%i", 
		ip >> 24 & 0xFF, 
		ip >> 16 & 0xFF, 
		ip >> 8  & 0xFF, 
		ip 		 & 0xFF
	)
end

function essentials.ipv4_to_dec(ipv4)
    local which_oct, dec = 24, 0
    for octet in ipv4:gmatch("%d+") do
        dec = dec | tonumber(octet) << which_oct
        which_oct = which_oct - 8
    end
    return dec
end

function essentials.get_position_of_previous_newline(str, str_pos)
	local current_char = str:sub(str_pos, str_pos)
	while str_pos > 1 and current_char ~= '\n' and current_char ~= '\r' do
		str_pos = str_pos - 1
		current_char = str:sub(str_pos, str_pos)
	end
	return str_pos > 1 and str_pos + 1 or 1
end

function essentials.search_for_match_and_get_line(...)
	local file_path <const>,
	search <const>,
	exact <const> = ...

	local search_without_special_chars
	if exact then
		search_without_special_chars = {}
		for i = 1, #search do
			search_without_special_chars[i] = essentials.remove_special(search[i])
		end
	end

	local str <const> = essentials.get_file_string(file_path, "rb")
	for i = 1, #search do
		local str_pos
		if exact then
			str_pos = str:find(string.format("[\r\n]%s[\r\n]", search_without_special_chars[i]))
			or str:find(string.format("^%s[\r\n]", search_without_special_chars[i]))
			or str:find(string.format("[\r\n]%s$", search_without_special_chars[i]))
			or str:find(string.format("^%s$", search_without_special_chars[i]))
		else
			str_pos = str:find(search[i], 1, true)
		end
		if str_pos then
			str_pos = essentials.get_position_of_previous_newline(str, str_pos)
			local End = str:find("[\n\r]", str_pos)
			if End then
				End = End - 1
			else
				End = #str
			end
			return str:sub(str_pos, End), search[i]
		end
	end
end

do
	local get_start <const> = essentials.get_position_of_previous_newline
	local find <const> = string.find
	local match <const> = string.match
	local sub <const> = string.sub

	function essentials.get_all_matches(str, pattern, match_pattern)
		essentials.assert(#pattern > 0, "Tried to get all matches with an empty pattern.")
		local End, start = 1
		local i = 1
		local matches <const> = {}
		while true do
			start, End = find(str, pattern, End, true)
			if start then
				local str_pos <const> = get_start(str, start)
				End = find(str, "[\r\n]", End) or (#str + 1)
				matches[i] = sub(str, str_pos, End - 1)
				End = End + 1
				if match_pattern then
					matches[i] = match(matches[i], match_pattern)
				end
				i = i + 1
			else
				break
			end
		end
		return matches
	end
end

do
	local ad_strings <const> = essentials.const({
		"%.com",
		"%.net",
		"%.org",
		"http",
		"www%.",
		"%.tk",
		"%.ru",
		"%.info",
		"%.cn",
		"%.uk",
		"%.biz",
		"%.xyz",
		"qq",
		"%.gg",
		"#%d%d%d%d", -- Discord ig tag
		"gta%d%d"
	})
	function essentials.contains_advert(str)
		local str <const> = str:lower()
		for i = 1, #ad_strings do
			if str:find(ad_strings[i]) then
				return true
			end
		end
	end
end

function essentials.log(...)
	local file_path <const>,
	text_to_log <const>,
	search <const>, -- Whether to check if text_to_log appears in the file already or not
	exact <const> = ... -- Whether the existing text check must be identical to an entire line or a substring of a line.
	if search then
		local str <const> = essentials.search_for_match_and_get_line(file_path, search, exact)
		if str then
			return str
		end
	end
	local file <close> = io.open(file_path, "a+b")
	assert(file, "Missing write permissions to:\n"..file_path)
	file:seek("end", -1)
	local last_char <const> = file:read("*L") -- *L keeps the newline char, unlike *l.
	if last_char ~= "\n" and last_char ~= "\r" and file:seek("end") ~= 0 then
		file:write("\n")
	end
	file:seek("end")
	file:write(text_to_log)
	file:write("\n")
end

function essentials.add_to_timeout(pid)
	essentials.assert(pid ~= player.player_id(), "Tried to add yourself to join timeout.")
	essentials.log(paths.home.."cfg\\scid.cfg", 
		string.format("%s:%x:c", player.get_player_name(pid), player.get_player_scid(pid)), 
		{string.format("%x", player.get_player_scid(pid)), player.get_player_name(pid)})
end

function essentials.send_pattern_guide_msg(...)
	local part <const>, Type <const> = ...
	local parts <const> = {
		["Chat judger"] = {
			"There are 2 special texts for the chat judger: [BLACKLIST] = Add people to the blacklist\n[JOIN TIMEOUT] = Add people to 2take1's join timeout.",
			"Examples of how to use:\nmoney[BLACKLIST] -- This will add anyone saying the word money in a sentence to the blacklist",
			"money[JOIN TIMEOUT][BLACKLIST] -- This will add anyone saying money to the timeout and blacklist."
		},
		["Chatbot"] = {
			"There are 3 special texts for the chatbot:\n[PLAYER_NAME] -- This grabs the player sending the message's name.",
			"[MY_NAME] -- This gets your name\n[RANDOM_NAME] -- This gets a random player's name."
		},
		regular = {
			"When adding entries, it's important to know about patterns. A pattern could look like this: %s+money%s+. This would look for people using money in the middle of a sentence.",
			"Note that these characters: \"*\", \"+\", \"-\", \"^\", \"$\", \".\", \"?\", \"[\", \"]\", \"(\" & \")\" have special meanings. Google \"Lua magic characters\" to find out what they mean.",
			"For further assistance, join the Kek's menu discord. An invite comes with the script. It is in a file called \"Discord invite.txt\"."
		}

	}
	table.move(parts.regular, 1, #parts.regular, #parts[Type] + 1, parts[Type])
	for i = 1, #parts[Type] do
		if part + 1 == i then
			essentials.msg(lang[parts[Type][i]], "blue", 12)
			break
		end
	end
end

--[[
	Checks if a string can be used with regex functions.
	Warns if string contains special characters that has an other meaning in patterns.
--]]
function essentials.invalid_pattern(...)
	local text <const>,
	display_feedback <const>,
	warn <const> = ...
	if warn then
		if text:find("[.+-*?^$]") and not text:find("%%[.+-*?^$]") then
			essentials.msg(string.format("%s %s.\n%s", 
				lang["Warning: missing \"%\" before any of these characters;"],
				"\".\", \"+\", \"-\", \"*\", \"?\", \"^\", \"$\"",
				lang["This is fine, just note that if you don't put the \"%\" before those characters, they mean something else."]), 
			"red", 12)
		end
	end
	local status <const> = pcall(function() 
		return text:find(text)
	end)
	if not status then
		if display_feedback then
			essentials.msg(lang["Invalid pattern. Most likely missing a \"[\", \"]\", \"(\", \")\" or a \"%\" somewhere. Could also be \"[]\", having \"[]\" causes an error."], "red", 12)
		end
		return true
	end
end

do
	local mod_flag_memoize <const> = {}
	function essentials.modder_flags_to_text(...)
		local mod_flags <const> = ...
		if not mod_flag_memoize[mod_flags] then
			local all_flags <const> = {}
			for i = 0, 63 do
				local flag <const> = 1 << i
				if flag == player.get_modder_flag_ends() then
					break
				end
				if mod_flags & flag ~= 0 then
					all_flags[#all_flags + 1] = player.get_modder_flag_text(flag)
				end
			end
			mod_flag_memoize[mod_flags] = table.concat(all_flags, ", ")
		end
		return mod_flag_memoize[mod_flags]
	end
end

do
	local modder_text_to_flags_map <const> = {}
	for i = 0, 63 do
		if 1 << i == player.get_modder_flag_ends() then
			break
		end
		modder_text_to_flags_map[player.get_modder_flag_text(1 << i)] = 1 << i
	end

	function essentials.modder_text_to_flags(modder_text)
		local flags = 0
		for flag in modder_text:gmatch("%a[^,]+") do
			flags = flags | (modder_text_to_flags_map[flag] or 0)
		end
		return flags
	end
end

function essentials.replace_lines_in_file_exact(...)
	local file_path <const>,
	what_to_be_replaced <const>,
	replacement <const> = ...
	local new_string <const> = {}
	local found_what_to_be_replaced = false
	for line in io.lines(file_path) do
		if not found_what_to_be_replaced and line == what_to_be_replaced then
			new_string[#new_string + 1] = replacement
			found_what_to_be_replaced = true
		else
			new_string[#new_string + 1] = line
		end
	end
	local file <close> = io.open(file_path, "w+")
	new_string[#new_string + 1] = ""
	file:write(table.concat(new_string, "\n"))
	file:flush()
	return found_what_to_be_replaced
end

function essentials.replace_lines_in_file_substring(...)
	local file_path <const>,
	what_to_be_replaced <const>,
	replacement <const>,
	use_regex <const> = ...
	local new_string <const> = {}
	local found_what_to_be_replaced = false
	for line in io.lines(file_path) do
		if not found_what_to_be_replaced and line:find(what_to_be_replaced, 1, not use_regex) then
			new_string[#new_string + 1] = replacement
			found_what_to_be_replaced = true
		else
			new_string[#new_string + 1] = line
		end
	end
	local file <close> = io.open(file_path, "w+")
	new_string[#new_string + 1] = ""
	file:write(table.concat(new_string, "\n"))
	file:flush()
	return found_what_to_be_replaced
end

function essentials.remove_lines_from_file_exact(...)
	local file_path <const>,
	what_to_be_removed <const> = ...
	local new_string <const> = {}
	local found_what_to_be_removed = false
	for line in io.lines(file_path) do
		if found_what_to_be_removed or line ~= what_to_be_removed then
			new_string[#new_string + 1] = line
		else
			found_what_to_be_removed = true
		end
	end
	local file <close> = io.open(file_path, "w+")
	new_string[#new_string + 1] = ""
	file:write(table.concat(new_string, "\n"))
	file:flush()
	return found_what_to_be_removed
end

function essentials.remove_lines_from_file_substring(...)
	local file_path <const>,
	what_to_be_removed <const>,
	use_regex <const> = ...
	local new_string <const> = {}
	local found_what_to_be_removed = false
	for line in io.lines(file_path) do
		if found_what_to_be_removed or not line:find(what_to_be_removed, 1, not use_regex) then
			new_string[#new_string + 1] = line
		else
			found_what_to_be_removed = true
		end
	end
	local file <close> = io.open(file_path, "w+")
	new_string[#new_string + 1] = ""
	file:write(table.concat(new_string, "\n"))
	file:flush()
	return found_what_to_be_removed
end

return essentials