---@diagnostic disable
local xplr = xplr
---@diagnostic enable

local COMMANDS = {}
local COMMAND_HISTORY = {}
local CURR_CMD_INDEX = 1
local MAX_LEN = 0

local function matches_all(str, cmds)
	for _, p in ipairs(cmds) do
		if string.sub(p, 1, #str) ~= str then
			return false
		end
	end
	return true
end

local function BashExec(script)
	return function(_)
		return {
			{ BashExec = script },
		}
	end
end

local function BashExecSilently(script)
	return function(_)
		return {
			{ BashExecSilently = script },
		}
	end
end

-- !to be deprecated! --
local function map(mode, key, name)
	local cmd = COMMANDS[name]
	if cmd then
		local messages = { "PopMode" }

		if cmd.silent then
			table.insert(messages, { CallLuaSilently = "custom.command_mode.fn." .. name })
		else
			table.insert(messages, { CallLua = "custom.command_mode.fn." .. name })
		end

		xplr.config.modes.builtin[mode].key_bindings.on_key[key] = {
			help = cmd.help,
			messages = messages,
		}
	end
end
-- !to be deprecated! --

local function define(name, help, silent, completer)
	return function(func)
		xplr.fn.custom.command_mode.fn[name] = func
		COMMANDS[name] = { help = help or "", fn = func, silent = silent, completer = completer }

		local len = string.len(name)
		if len > MAX_LEN then
			MAX_LEN = len
		end

		local messages = { "PopMode" }

		local fn_name = "custom.command_mode.fn." .. name

		if silent then
			table.insert(messages, { CallLuaSilently = fn_name })
		else
			table.insert(messages, { CallLua = fn_name })
		end

		return {
			cmd = COMMANDS[name],
			fn = {
				name = fn_name,
				call = func,
			},
			action = {
				help = help,
				messages = messages,
			},
			bind = function(mode, key)
				if type(mode) == "string" then
					mode = xplr.config.modes.builtin[mode]
				end

				mode.key_bindings.on_key[key] = {
					help = help,
					messages = messages,
				}
			end,
		}
	end
end

local function cmd(name, help, completer)
	return define(name, help, false, completer)
end

local function silent_cmd(name, help, completer)
	return define(name, help, true, completer)
end

-- Returns the Levenshtein distance between the two given strings
local function levenshtein(str1, str2)
	local len1 = string.len(str1)
	local len2 = string.len(str2)
	local matrix = {}
	local cost = 0

	-- quick cut-offs to save time
	if len1 == 0 then
		return len2
	elseif len2 == 0 then
		return len1
	elseif str1 == str2 then
		return 0
	end

	-- initialise the base matrix values
	for i = 0, len1, 1 do
		matrix[i] = {}
		matrix[i][0] = i
	end
	for j = 0, len2, 1 do
		matrix[0][j] = j
	end

	-- actual Levenshtein algorithm
	for i = 1, len1, 1 do
		for j = 1, len2, 1 do
			if str1:byte(i) == str2:byte(j) then
				cost = 0
			else
				cost = 1
			end

			matrix[i][j] = math.min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost)
		end
	end

	-- return the last value - this is the Levenshtein distance
	return matrix[len1][len2]
end

local function is_in_first_word(str)
	return str:match("^%S*$") ~= nil
end

local function setup(args)
	-- Parse args
	args = args or {}
	args.mode = args.mode or "default"
	args.key = args.key or ":"
	args.remap_action_mode_to = args.remap_action_mode_to or { mode = "default", key = ";" }

	xplr.config.modes.builtin[args.remap_action_mode_to.mode].key_bindings.on_key[args.remap_action_mode_to.key] =
		xplr.config.modes.builtin.default.key_bindings.on_key[":"]

	xplr.config.modes.builtin[args.mode].key_bindings.on_key[args.key] = {
		help = "command mode",
		messages = {
			"PopMode",
			{ SwitchModeCustom = "command_mode" },
			{ SetInputBuffer = "" },
			{ SetInputPrompt = ":" },
		},
	}

	xplr.config.modes.custom.command_mode = {
		name = "command mode",
		layout = {
			Horizontal = {
				config = {
					constraints = {
						{ Percentage = 70 },
						{ Percentage = 30 },
					},
				},
				splits = {
					{
						Vertical = {
							config = {
								constraints = {
									{ Max = 3 },
									{ Percentage = 50 },
									{ Min = 1 },
									{ Length = 3 },
								},
							},
							splits = {
								"SortAndFilter",
								"Table",
								{
									CustomContent = {
										title = "Commands",
										body = {
											DynamicList = { render = "custom.command_mode.render" },
										},
									},
								},
								"InputAndLogs",
							},
						},
					},
					xplr.config.layouts.builtin.default.Horizontal.splits[2],
				},
			},
		},

		key_bindings = {
			on_alphanumeric = {
				messages = {
					"UpdateInputBufferFromKey",
					{ CallLuaSilently = "custom.command_mode.on_key" },
				},
			},
			on_key = {
				enter = {
					help = "execute",
					messages = {
						{ CallLuaSilently = "custom.command_mode.execute" },
						"PopMode",
					},
				},
				esc = {
					help = "cancel",
					messages = { "CancelSearch", "PopMode" },
				},
				tab = {
					help = "try complete",
					messages = {
						{ CallLuaSilently = "custom.command_mode.try_complete" },
					},
				},
				up = {
					help = "prev",
					messages = {
						{ CallLuaSilently = "custom.command_mode.prev_command" },
					},
				},
				down = {
					help = "next",
					messages = {
						{ CallLuaSilently = "custom.command_mode.next_command" },
					},
				},
				["!"] = {
					help = "shell",
					messages = {
						{ Call = { command = "bash", args = { "-i" } } },
						"ExplorePwdAsync",
						"PopMode",
					},
				},
				["?"] = {
					help = "list commands",
					messages = {
						{ CallLua = "custom.command_mode.list" },
					},
				},
				backspace = {
					messages = {
						"RemoveInputBufferLastCharacter",
						{ CallLuaSilently = "custom.command_mode.on_key" },
					},
				},
			},
			default = {
				messages = {
					"UpdateInputBufferFromKey",
				},
			},
		},
	}

	xplr.fn.custom.command_mode = {
		map = map,
		cmd = cmd,
		silent_cmd = silent_cmd,
		fn = {},
	}

	xplr.fn.custom.command_mode.execute = function(app)
		local name, args = app.input_buffer:match("([^%s]+)%s*(.*)")
		if name then
			local command = COMMANDS[name]
			if command then
				table.insert(COMMAND_HISTORY, name .. " " .. args)
				CURR_CMD_INDEX = CURR_CMD_INDEX + 1

				if command.silent then
					return command.fn(app, args)
				else
					return {
						{ CallLua = "custom.command_mode.fn." .. name },
					}
				end
			end
		end
	end

	local function get_completions(app)
		if not app.input_buffer then
			return {}
		end

		local input = app.input_buffer
		local found = {}

		local in_first_word = is_in_first_word(input)
		local first_word = input:match("^%S+") or ""
		local search = input:match("%S+$") or ""

		local command
		for name, def in pairs(COMMANDS) do
			if name == first_word then
				command = def
			end
		end

		local new_search
		if in_first_word then
			for name, _ in pairs(COMMANDS) do
				if string.sub(name, 1, #first_word) == first_word then
					table.insert(found, name)
				end
			end
		else
			if command == nil or command.completer == nil then
				return {}
			end

			local completions
			completions, new_search = command.completer(search, input, app)
			for _, name in ipairs(completions) do
				if string.sub(name, 1, #(new_search or search)) == (new_search or search) then
					table.insert(found, name)
				end
			end
		end
		if #found > 1 then
			table.sort(found, function(a, b)
				if not a then
					return false
				end
				if not b then
					return true
				end
				local da = levenshtein(search, a)
				local db = levenshtein(search, b)
				return da < db
			end)
		end
		return found, new_search
	end

	xplr.fn.custom.command_mode.on_key = function(app)
		if not app.input_buffer then
			return
		end

		local input = app.input_buffer
		local in_first_word = not is_in_first_word(input)
		local search = input:match("%S+$") or ""

		if in_first_word then
			return {
				{ SearchFuzzy = search },
				"ExplorePwd",
			}
		end
	end

	xplr.fn.custom.command_mode.try_complete = function(app)
		if not app.input_buffer then
			return {}
		end

		local input = app.input_buffer
		local in_first_word = is_in_first_word(input)
		local search = input:match("%S+$")

		local found, new_search = get_completions(app)
		if new_search then
			search = new_search
		end

		local count = #found

		if count == 0 then
			return
		elseif count == 1 then
			if in_first_word then
				return {
					{ SetInputBuffer = found[1] },
				}
			else
				return {
					{ SetInputBuffer = app.input_buffer:gsub(search .. "$", found[1]) },
				}
			end
		else
			if matches_all(search, found) and search:gsub("%s", "") ~= "" then
				return {
					{ SetInputBuffer = input:gsub(search .. "$", found[1]) },
				}
			end

			return {}
		end
	end

	xplr.fn.custom.command_mode.list = function(_)
		local list = {}
		for name, command in pairs(COMMANDS) do
			local help = command.help or ""
			local text = name
			for _ = #name, MAX_LEN, 1 do
				text = text .. " "
			end

			table.insert(list, text .. " " .. help)
		end

		table.sort(list)

		local pager = os.getenv("PAGER") or "less"
		local p = assert(io.popen(pager, "w"))
		p:write(table.concat(list, "\n"))
		p:flush()
		p:close()
	end

	xplr.fn.custom.command_mode.prev_command = function(_)
		if CURR_CMD_INDEX > 1 then
			CURR_CMD_INDEX = CURR_CMD_INDEX - 1
		else
			for i, _ in ipairs(COMMAND_HISTORY) do
				CURR_CMD_INDEX = i + 1
			end
		end
		local command = COMMAND_HISTORY[CURR_CMD_INDEX]

		if command then
			return {
				{ SetInputBuffer = command },
			}
		end
	end

	xplr.fn.custom.command_mode.next_command = function(_)
		local len = 0
		for i, _ in ipairs(COMMAND_HISTORY) do
			len = i
		end

		if CURR_CMD_INDEX >= len then
			CURR_CMD_INDEX = 1
		else
			CURR_CMD_INDEX = CURR_CMD_INDEX + 1
		end

		local command = COMMAND_HISTORY[CURR_CMD_INDEX]
		if command then
			return {
				{ SetInputBuffer = command },
			}
		end
	end

	xplr.fn.custom.command_mode.render = function(ctx)
		local input = ctx.app.input_buffer or ""
		local ui = {}

		local search = input:match("%S+$") or ""
		local completions, new_search = get_completions(ctx.app)
		-- if new_search then
		-- 	search = new_search
		-- end
		for _, name in ipairs(completions) do
			local color = "\x1b[1m"

			if input == name then
				color = "\x1b[1;7m"
			end

			local line = color .. " " .. name .. " \x1b[0m"

			for _ = #name, MAX_LEN, 1 do
				line = line .. " "
			end

			if COMMANDS[name] then
				line = line .. COMMANDS[name].help
			end

			if search == name then
				line = "\x1b[1;7m" .. line .. "\x1b[0m"
			end

			table.insert(ui, line)
		end

		-- table.sort(ui)
		table.insert(ui, 1, " ")

		return ui
	end
end

local completers = {}

function completers.path(show_hidden, dirs_only)
	return function(search, _input, app)
		local function scandir(directory)
			local i, t, popen = 0, {}, io.popen
			local pfile = popen('ls -a "' .. directory .. '"')
			if not pfile then
				return {}
			end
			for filename in pfile:lines() do
				i = i + 1
				t[i] = filename
			end
			pfile:close()
			return t
		end
		local found = {}
		local function collect_entries(dir)
			for _, name in ipairs(scandir(dir)) do
				if name ~= "" and name ~= "." and name ~= ".." then
					if show_hidden or not name:match("^%.") then
						if xplr.util.is_dir(dir .. "/" .. name) then
							name = name .. "/"
						end
						if xplr.util.is_dir(dir .. "/" .. name) or not dirs_only then
							table.insert(found, name)
						end
					end
				end
			end
		end

		search = search:gsub("%.+$", "")
		local home = false
		local root = false
		local new_root = ""
		if search == "~" then
			return { "~/" }, "~"
		end
		if search:match("^~") then
			search = search:gsub("~", os.getenv("HOME"))
			home = true
		elseif search:match("^/") then
			root = true
		end
		local path
		if home or root then
			path = search
		else
			path = app.pwd .. "/" .. search
		end

		local dirname = xplr.util.dirname(path)
		local basename = xplr.util.basename(path)

		if xplr.util.is_dir(path) and path:sub(-1) == "/" then
			collect_entries(path)
		elseif xplr.util.is_dir(dirname) then
			collect_entries(dirname)
			new_root = basename or new_root
		else
			collect_entries(app.pwd)
			new_root = basename or new_root
		end

		return found, new_root
	end
end

return {
	setup = setup,
	cmd = cmd,
	silent_cmd = silent_cmd,
	map = map,
	BashExec = BashExec,
	BashExecSilently = BashExecSilently,
	completers = completers,
}
