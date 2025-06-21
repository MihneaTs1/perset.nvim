-- lua/perset/core.lua

local M = {}
local settings_path = nil

local function ensure_path(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({ "{}" }, path)
  end
end

function M.setup(path)
  settings_path = vim.fn.expand(path)
  ensure_path(settings_path)
end

function M.load_settings()
  if not settings_path then
    error("perset: setup(path) must be called before load_settings()")
  end

  local content = vim.fn.readfile(settings_path)
  local decoded = vim.fn.json_decode(table.concat(content, "\n")) or {}

  -- Apply global options
  local gopts = decoded.global or {}
  for k, v in pairs(gopts) do
    pcall(function() vim.opt[k] = v end)
  end

  -- Apply window-local options
  local wopts = decoded.window or {}
  vim.api.nvim_create_autocmd("WinNew", {
    callback = function()
      for k, v in pairs(wopts) do
        pcall(function() vim.wo[k] = v end)
      end
    end
  })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    for k, v in pairs(wopts) do
      pcall(function() vim.api.nvim_win_set_option(win, k, v) end)
    end
  end

  -- Apply colorscheme
  if decoded.colorscheme then
    pcall(function()
      vim.cmd.colorscheme(decoded.colorscheme)
    end)
  end

  -- Apply global variables
  local gvars = decoded.vimvars or {}
  for k, v in pairs(gvars) do
    pcall(function() vim.g[k] = v end)
  end
end

function M.save_settings_all()
  if not settings_path then
    error("perset: setup(path) must be called before save_settings_all()")
  end

  local gopts = {}
  for k, v in pairs(vim.opt) do
    local ok, val = pcall(function() return v:get() end)
    if ok and type(val) ~= "function" and val ~= vim.empty_dict() then
      local enc_ok = pcall(vim.fn.json_encode, { [k] = val })
      if enc_ok then
        gopts[k] = val
      end
    end
  end

  local wopts = {}
  local win = vim.api.nvim_get_current_win()
  for _, name in ipairs({ "number", "relativenumber", "cursorline", "wrap" }) do
    local ok, val = pcall(function() return vim.api.nvim_win_get_option(win, name) end)
    if ok then
      wopts[name] = val
    end
  end

  local gvars = {}
  for k, v in pairs(vim.g) do
    local ok = pcall(function() return vim.fn.json_encode({ [k] = v }) end)
    if ok and type(v) ~= "function" and v ~= vim.empty_dict() then
      gvars[k] = v
    end
  end

  local colorscheme = vim.g.colors_name

  local data = {
    global = gopts,
    window = wopts,
    colorscheme = colorscheme,
    vimvars = gvars,
  }

  local encoded = vim.fn.json_encode(data)
  vim.fn.writefile(vim.split(encoded, "\n"), settings_path)
end

function M.setup_commands()
  vim.api.nvim_create_user_command("PersetSave", function()
    M.save_settings_all()
    print("✅ Settings saved to " .. settings_path)
  end, {})

  vim.api.nvim_create_user_command("PersetLoad", function()
    M.load_settings()
    print("🔄 Settings loaded from " .. settings_path)
  end, {})

  vim.api.nvim_create_user_command("PersetPath", function()
    print("🛠 perset.nvim path: " .. settings_path)
  end, {})

  vim.api.nvim_create_user_command("PersetReset", function()
    vim.fn.delete(settings_path)
    print("🧹 Settings file deleted: " .. settings_path)
  end, {})
end

return M
