if vim.g.loaded_projectile then
  return
end
vim.g.loaded_projectile = true

local projectile = require("projectile")

-- User commands
vim.api.nvim_create_user_command("ProjectileAdd", function()
  projectile.add_project(vim.fn.getcwd())
end, {})

vim.api.nvim_create_user_command("ProjectileDelete", function()
  projectile.delete_project(vim.fn.getcwd())
end, {})
