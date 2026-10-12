local S = core.get_translator("server_news")

local news_file_name = core.settings:get("news.file_name") or "news.txt"
local news_marker = core.settings:get("news.marker") or false

local news_edit_enabled = core.settings:get_bool("news.edit_enabled", false)
local news_add_enabled = core.settings:get_bool("news.add_enabled", false)
local news_delete_enabled = core.settings:get_bool("news.delete_enabled", false)
local news_backup_enabled = core.settings:get_bool("news.backup_enabled", false)
local news_restore_enabled = core.settings:get_bool("news.restore_enabled", false)

-- register bypass priv
local news_bypass_permission = core.settings:get("news.bypass_permission") or "news_bypass"
if not core.registered_privileges[news_bypass_permission] then
	core.register_privilege(news_bypass_permission, {
		description = "Skip the news.",
		give_to_singleplayer = false,
	})
end
-- register edit priv
local news_edit_permission = core.settings:get("news.edit_permission") or "news_edit"
if not core.registered_privileges[news_edit_permission] then
	core.register_privilege(news_edit_permission, {
		description = S("Can add and remove news."),
		give_to_singleplayer = false,
	})
end
-- register backup priv
local news_backup_permission = core.settings:get("news.backup_permission") or "news_backup"
if not core.registered_privileges[news_backup_permission] then
	core.register_privilege(news_backup_permission, {
		description = S("Can backup and restore news."),
		give_to_singleplayer = false,
	})
end

local file_path = core.get_worldpath() .. "/" .. news_file_name

local function split(inputstr, sep) -- Split string by separator
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
end

local function join(inputtab, sep) -- Join table by separator
	local s = ""
	if sep == nil then
		sep = ""
	end
	for _, str in ipairs(inputtab) do
		s = s .. str .. sep
	end
	return s
end

local function get_news_contents()
	local news_file = io.open(file_path, "r")

	if not news_file then
		return false
	end

	local news = news_file:read("*a")
	news_file:close()

	if news == "" or news == "\n" then
		return false
	end

	return news
end

local function set_news_contents(news)
	core.safe_file_write(file_path, news)
end

-- create formspec from text file
local function get_formspec(name)
	local news = get_news_contents()
	local news_fs = "size[12,8.25]" .. "button_exit[-0.05,7.8;2,1;exit;Close]"
	if news_edit_enabled and core.get_player_privs(name)[news_edit_permission] then
		news_fs = news_fs .. "button[2,7.8;2,1;save;Save]"
	end
	if news then
		news_fs = news_fs .. "textarea[0.25,0;12.1,9;news;;" .. core.formspec_escape(news) .. "]"
	else
		news_fs = news_fs .. "textarea[0.25,0;12.1,9;news;;No current news.]"
	end

	return news_fs
end

-- edit the news lines with the given modifier function
-- read from file and write back the modifications
local function edit_news(modifier)
	local news = get_news_contents() or ""

	local news_start = ""
	local news_end = news
	if news_marker then
		local i = string.find(news, news_marker, 1, true) + #news_marker
		news_start = string.sub(news, 1, i - 1)
		news_end = string.sub(news, i)
	end

	local lines = split(news_end, "\n")

	-- Get new table as returned from modifier
	-- or fallback to old table if nothing is returned
	local new_lines = modifier(lines) or lines

	set_news_contents(news_start .. join(new_lines, "\n"))
end

-- show news formspec to a user
local function show_news(name)
	core.show_formspec(name, "news", get_formspec(name))
end

-- show news formspec on player join, unless player has bypass priv
core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	if core.get_player_privs(name)[news_bypass_permission] then
		return
	else
		show_news(name)
	end
end)

-- write news from textarea if the player has edit priv
core.register_on_player_receive_fields(function(player, formname, fields)
	-- Not the right form? exit
	if formname ~= "news" then
		return
	end
	-- Form is not being saved? exit
	if not fields.save then
		return
	end
	-- User doesn't have permission? exit
	local name = player:get_player_name()
	if not core.get_player_privs(name)[news_edit_permission] then
		return
	end
	-- No news to save? exit
	if not fields.news then
		return
	end

	set_news_contents(fields.news)
end)

-- command to display server news at any time
core.register_chatcommand("news", {
	description = "Shows server news to the player",
	func = function(name)
		show_news(name)
	end,
})

-- command to add a line to the top of the news section
if news_edit_enabled and news_add_enabled then
	core.register_chatcommand("add_news", {
		description = "Adds a record to the server news file",
		privs = { [news_edit_permission] = true },
		func = function(name, text)
			local date = os.date("*t")
			local date_string = date.year .. "-" .. date.month .. "-" .. date.day

			edit_news(function(lines)
				table.insert(lines, 1, date_string .. ": " .. text)
			end)

			show_news(name)
		end,
	})
end

-- command to remove a line from the news section by line number
if news_edit_enabled and news_delete_enabled then
	core.register_chatcommand("delete_news", {
		description = "Deletes the n-th record from server news",
		privs = { [news_edit_permission] = true },
		func = function(name, line)
			local line_number = tonumber(line)
			if not line_number then
				return
			end

			edit_news(function(lines)
				table.remove(lines, line_number)
			end)

			show_news(name)
		end,
	})
end

-- command to backup the news file to a different backup file - will overwrite old backup
if news_backup_enabled then
	core.register_chatcommand("backup_news", {
		description = "Creates a backup if the server news file",
		privs = { [news_backup_permission] = true },
		func = function()
			local news = get_news_contents()

			core.safe_file_write(file_path .. ".backup", news)
		end,
	})
end

-- command to restore the news file from the last backup
if news_restore_enabled then
	core.register_chatcommand("restore_news", {
		description = "Restores the backup of the server news file",
		privs = { [news_backup_permission] = true },
		func = function()
			local backup_file = io.open(file_path .. ".backup", "r")
			if not backup_file then
				return
			end

			local news = backup_file:read("*a")
			backup_file:close()

			set_news_contents(news)
		end,
	})
end
