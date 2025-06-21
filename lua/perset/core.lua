-- lua/perset/core.lua

local M = {}

local settings_path = nil
local git_enabled = true
local git_cmd = "git"
local opt_whitelist = nil
local opt_blacklist = nil

local function ensure_path(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({ "{}" }, path)
  end
end

local function is_git_repo(path)
  return vim.fn.isdirectory(path .. "/.git") == 1
end

local function init_git_repo(path)
  if not git_enabled then return end
  if not is_git_repo(path) then
    local ok1 = os.execute(git_cmd .. " init -q " .. vim.fn.shellescape(path) .. " > /dev/null 2>&1")
    local ok2 = os.execute(git_cmd .. " -C " .. vim.fn.shellescape(path) .. " add . > /dev/null 2>&1")
    local ok3 = os.execute(git_cmd .. " -C " .. vim.fn.shellescape(path) .. " commit -m 'Initial settings commit' > /dev/null 2>&1")
    if not (ok1 == 0 and ok2 == 0 and ok3 == 0) then
      vim.notify("[perset] Git repo init failed. Disabling Git integration.", vim.log.levels.WARN)
      git_enabled = false
    end
  end
end

local function git_commit_settings()
  if not git_enabled then return end
  local dir = vim.fn.fnamemodify(settings_path, ":h")
  local ok1 = os.execute(git_cmd .. " -C " .. vim.fn.shellescape(dir) .. " add " .. vim.fn.shellescape(settings_path) .. " > /dev/null 2>&1")
  local ok2 = os.execute(git_cmd .. " -C " .. vim.fn.shellescape(dir) .. " commit -m 'Update settings (" .. os.date() .. ")' > /dev/null 2>&1")
  if not (ok1 == 0 and ok2 == 0) then
    vim.notify("[perset] Git commit failed. Disabling Git integration.", vim.log.levels.WARN)
    git_enabled = false
  end
end

function M.setup(path, opts)
  opts = opts or {}
  settings_path = vim.fn.expand(path)
  git_enabled = opts.git ~= false
  git_cmd = opts.git_cmd or "git"
  opt_whitelist = opts.whitelist or nil
  opt_blacklist = opts.blacklist or nil
  ensure_path(settings_path)
  init_git_repo(vim.fn.fnamemodify(settings_path, ":h"))
  M.setup_commands()
end

local function should_include_option(key)
  if opt_whitelist and vim.tbl_contains(opt_whitelist, key) then
    return not (opt_blacklist and vim.tbl_contains(opt_blacklist, key))
  elseif opt_whitelist then
    return false
  elseif opt_blacklist then
    return not vim.tbl_contains(opt_blacklist, key)
  else
    return true
  end
end

function M.load_settings()
  if not settings_path then
    error("perset: setup(path) must be called before load_settings()")
  end

  local content = vim.fn.readfile(settings_path)
  if not content or vim.tbl_isempty(content) then
    vim.notify("[perset] settings file is empty or unreadable: " .. settings_path, vim.log.levels.WARN)
    return
  end

  local ok, decoded = pcall(function()
    return vim.fn.json_decode(table.concat(content, "\n"))
  end)
  if not ok or type(decoded) ~= "table" then
    vim.notify("[perset] Failed to parse settings file: " .. settings_path, vim.log.levels.WARN)
    return
  end

  -- Apply global options
  local gopts = decoded.global or {}
  for k, v in pairs(gopts) do
    if should_include_option(k) then
      pcall(function() vim.opt[k] = v end)
    end
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
    if should_include_option(k) then
      local ok, val = pcall(function() return v:get() end)
      if ok and type(val) ~= "function" and val ~= vim.empty_dict() then
        local enc_ok = pcall(vim.fn.json_encode, { [k] = val })
        if enc_ok then
          gopts[k] = val
        end
      end
    end
  end

  local wopts = {}
  local win = vim.api.nvim_get_current_win()
  local seen = {}
  for _, name in ipairs(vim.api.nvim_get_option_info_list()) do
    if name.scope == "win" and not seen[name.name] then
      seen[name.name] = true
      local ok, val = pcall(vim.api.nvim_win_get_option, win, name.name)
      if ok and type(val) ~= "function" and val ~= vim.empty_dict() then
        local enc_ok = pcall(vim.fn.json_encode, { [name.name] = val })
        if enc_ok then
          wopts[name.name] = val
        end
      end
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
  git_commit_settings()
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

  vim.api.nvim_create_user_command("PersetLog", function()
    if not git_enabled then
      vim.notify("[perset] Git is disabled.", vim.log.levels.INFO)
      return
    end
    local dir = vim.fn.fnamemodify(settings_path, ":h")
    vim.cmd("split | terminal " .. git_cmd .. " -C " .. dir .. " log --oneline --decorate --graph --color=always")
  end, {})

  vim.api.nvim_create_user_command("PersetRevert", function(opts)
    if not git_enabled then
      vim.notify("[perset] Git is disabled.", vim.log.levels.INFO)
      return
    end
    local dir = vim.fn.fnamemodify(settings_path, ":h")
    local commit = opts.args
    os.execute(git_cmd .. " -C " .. vim.fn.shellescape(dir) .. " checkout " .. commit .. " -- " .. vim.fn.shellescape(settings_path) .. " > /dev/null 2>&1")
    print("🔁 Settings reverted to " .. commit .. ": " .. settings_path)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("PersetHist", function()
    if not git_enabled then
      vim.notify("[perset] Git is disabled.", vim.log.levels.INFO)
      return
    end
    local dir = vim.fn.fnamemodify(settings_path, ":h")
    local cmd = string.format("%s -C %s log --pretty=format:'%%h %%ad %%s' --date=short -- %s",
      git_cmd,
      vim.fn.shellescape(dir),
      vim.fn.shellescape(settings_path)
    )

    local output = vim.fn.systemlist(cmd)
    if vim.v.shell_error ~= 0 or not output or vim.tbl_isempty(output) then
      vim.notify("[perset] No Git history available.", vim.log.levels.WARN)
      return
    end

    vim.ui.select(output, {
      prompt = "Select a version to view",
      format_item = function(item)
        return item
      end,
    }, function(choice)
      if not choice then return end
      local commit = choice:match("^%w+")
      if not commit then return end

      local tmpfile = vim.fn.tempname() .. ".json"
      local fetch_cmd = string.format("%s -C %s show %s:%s > %s",
        git_cmd,
        vim.fn.shellescape(dir),
        commit,
        vim.fn.fnamemodify(settings_path, ":t"),
        tmpfile
      )
      os.execute(fetch_cmd)
      vim.cmd("tabnew " .. tmpfile)
    end)
  end, {})
end

return M
