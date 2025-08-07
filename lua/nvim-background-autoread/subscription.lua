local M = {}

local tracked_buffers = {}
local config = {}
local debounced_event_count = 0

local pid = vim.uv.getpid()
local log_file_path = string.format("/tmp/nvim-background-autoread-%d.log", pid)

---Writes a message to the instance-specific log file.
---@param message string The message to log.
local function log(message)
	if not config.debug_logging then
		return
	end
	local file = io.open(log_file_path, "a")
	if file then
		file:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n")
		file:close()
	end
end

---Stops all handles for a given buffer.
---@param bufnr number The buffer number to stop watching.
local function stop_handles(bufnr)
	if not tracked_buffers[bufnr] then
		return
	end
	log(string.format("Stopping handles for buffer %d", bufnr))
	if tracked_buffers[bufnr].watcher then
		tracked_buffers[bufnr].watcher:close()
	end
	if tracked_buffers[bufnr].timer then
		log(string.format("Closing pending timer for buffer %d", bufnr))
		tracked_buffers[bufnr].timer:close()
	end
end

---@param bufnr number The buffer number to process.
local function on_file_changed(bufnr)
	if bufnr == nil then
		log("ERROR: on_file_changed called with nil bufnr!")
		return
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		log(string.format("Buffer %d is no longer valid.", bufnr))
		return
	end

	if not tracked_buffers[bufnr] then
		log(string.format("tracked_buffers entry missing for bufnr %d", bufnr))
		return
	end

	debounced_event_count = debounced_event_count + 1

	if not vim.api.nvim_buf_get_option(bufnr, "modified") then
		log(string.format("Calling checktime for buffer %d", bufnr))
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("checktime")
		end)
	end

	log("Debounced event #" .. debounced_event_count .. " for buffer " .. tostring(bufnr))
end

local handle_fs_event

---adds a buffer to start watching for file changes
---@param bufnr number The buffer number to add.
local function add_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or tracked_buffers[bufnr] then
		return
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath and filepath ~= "" then
		local fs_watcher = vim.uv.new_fs_event()
		if not fs_watcher then
			return
		end

		log(string.format("Adding buffer %d for path %s", bufnr, filepath))
		tracked_buffers[bufnr] = { path = filepath, watcher = fs_watcher, timer = nil }

		fs_watcher:start(filepath, {}, function(err, filename, status)
			handle_fs_event(err, filename, status, bufnr)
		end)
	end
end

---main handler for file system events.
handle_fs_event = function(err, filename, status, bufnr)
	vim.schedule(function()
		log(
			string.format(
				"File event for buffer %d. Err: %s, Filename: %s, Status: %s",
				bufnr,
				tostring(err),
				tostring(filename),
				vim.inspect(status)
			)
		)
		if err then
			return
		end

		local buffer_info = tracked_buffers[bufnr]
		if not buffer_info then
			return
		end

		if status and status.rename then
			log(string.format("Re-attaching watcher for buffer %d due to rename.", bufnr))
			buffer_info.watcher:close()
			local new_watcher = vim.uv.new_fs_event()
			if new_watcher then
				buffer_info.watcher = new_watcher
				new_watcher:start(buffer_info.path, {}, function(err, filename, status)
					handle_fs_event(err, filename, status, bufnr)
				end)
			end
		end

		if buffer_info.timer then
			buffer_info.timer:close()
		end
		local new_timer = vim.uv.new_timer()
		if not new_timer then
			return
		end
		buffer_info.timer = new_timer

		new_timer:start(config.debounce_duration, 0, function()
			vim.schedule(function()
				if tracked_buffers[bufnr] and tracked_buffers[bufnr].timer == new_timer then
					tracked_buffers[bufnr].timer = nil
					on_file_changed(bufnr)
				end
			end)
		end)
	end)
end

---remove a buffer from tracking
---@param bufnr number The buffer number to remove.
local function remove_buffer(bufnr)
	if tracked_buffers[bufnr] then
		log(string.format("Removing buffer %d", bufnr))
		stop_handles(bufnr)
		tracked_buffers[bufnr] = nil
	end
end

---start the buffer tracking
---@param user_config table The user's configuration.
function M.start(user_config)
	config = user_config

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		add_buffer(bufnr)
	end

	local group = vim.api.nvim_create_augroup("NvimBackgroundAutoread", { clear = true })

	vim.api.nvim_create_autocmd("BufAdd", {
		group = group,
		pattern = "*",
		callback = function(args)
			add_buffer(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		pattern = "*",
		callback = function(args)
			remove_buffer(args.buf)
		end,
	})
end

-- expose the tracked buffers for debugging purposes.
M.tracked_buffers = tracked_buffers

return M
