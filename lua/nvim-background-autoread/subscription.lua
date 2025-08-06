local M = {}

-- Table to store the buffer numbers of tracked buffers.
-- The key is the buffer number and the value is a table containing the file path, watcher handle, and debounce timer.
local tracked_buffers = {}
local config = {}
local debounced_event_count = 0 -- New counter for debounced events

---Stops all handles for a given buffer.
---@param bufnr number The buffer number to stop watching.
local function stop_handles(bufnr)
	if not tracked_buffers[bufnr] then
		return
	end
	if tracked_buffers[bufnr].watcher then
		tracked_buffers[bufnr].watcher:close()
	end
	if tracked_buffers[bufnr].timer then
		tracked_buffers[bufnr].timer:close()
	end
end

---The debounced function that gets called after file events have settled.
---@param bufnr number The buffer number to process.
local function on_file_changed(bufnr)
	-- Check if bufnr is nil before trying to access tracked_buffers[bufnr]
	if bufnr == nil then
		if config.debug_logging then
			vim.notify("ERROR: on_file_changed called with nil bufnr!", vim.log.levels.ERROR)
		end
		return
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		if config.debug_logging then
			vim.notify(string.format("DEBUG: Buffer %d is no longer valid.", bufnr), vim.log.levels.DEBUG)
		end
		return
	end

	if not tracked_buffers[bufnr] then
		-- This can happen if the buffer was wiped out after the timer started but before it fired.
		if config.debug_logging then
			vim.notify(string.format("DEBUG: tracked_buffers entry missing for bufnr %d", bufnr), vim.log.levels.DEBUG)
		end
		return
	end

	debounced_event_count = debounced_event_count + 1 -- Increment debounced counter

	-- Only reload if the buffer is valid and has not been modified by the user.
	if not vim.api.nvim_buf_get_option(bufnr, "modified") then
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("checktime")
		end)
	end

	-- Simplified notification for debugging
	if config.debug_logging then
		vim.notify(
			"Debounced event #" .. debounced_event_count .. " for buffer " .. tostring(bufnr),
			vim.log.levels.INFO
		)
	end
end

---Adds a buffer to the tracking list and starts watching its file for changes.
---@param bufnr number The buffer number to add.
local function add_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or tracked_buffers[bufnr] then
		return
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath and filepath ~= "" then
		local fs_watcher = vim.uv.new_fs_event()
		local debounce_timer = vim.uv.new_timer()

		if not fs_watcher or not debounce_timer then
			return
		end

		tracked_buffers[bufnr] = { path = filepath, watcher = fs_watcher, timer = debounce_timer }

		fs_watcher:start(filepath, {}, function(err, filename, status)
			if err then
				return
			end
			-- On any file event, start (or restart) the debounce timer.
			debounce_timer:start(config.debounce_duration, 0, function()
				vim.schedule(function()
					on_file_changed(bufnr)
				end)
			end)
		end)
	end
end

---Removes a buffer from the tracking list and stops its handles.
---@param bufnr number The buffer number to remove.
local function remove_buffer(bufnr)
	if tracked_buffers[bufnr] then
		stop_handles(bufnr)
		tracked_buffers[bufnr] = nil
	end
end

---Starts the buffer subscription manager.
---@param user_config table The user's configuration.
function M.start(user_config)
	config = user_config

	-- Add all existing buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		add_buffer(bufnr)
	end

	-- Create an autocommand group to avoid duplicate autocmds
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

-- Expose the tracked buffers for debugging purposes.
M.tracked_buffers = tracked_buffers

return M

