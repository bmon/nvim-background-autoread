local M = {}

local config = {
	debounce_duration = 200,
	debug_logging = false,
}

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
	local subscription = require("nvim-background-autoread.subscription")
	subscription.start(config)
end

return M
