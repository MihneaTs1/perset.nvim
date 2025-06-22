for name, _ in pairs(vim.opt) do
  local ok, val = pcall(function()
    return vim.opt[name]:get()
  end)

  if ok then
    print(name, vim.inspect(val))
  end
end
