local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error('This plugin requires nvim-telescope/telescope.nvim')
end

-- Return extension configuration
return {
  exports = {
    projectile = function(opts)
      return require("projectile").project_picker(opts)
    end,
    projectile_buffers = function(opts)
      return require("projectile").project_buffers(opts)
    end
  },
}
