local M = {}

local config = {
  debounce_duration = 200,
}

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  vim.notify("Hello from nvim-background-autoread! Debounce duration: " .. config.debounce_duration .. "ms")
end

return M
