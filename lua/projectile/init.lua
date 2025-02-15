local M = {}

M.config = {
  projects_file = vim.fn.stdpath("data") .. "/projectile_projects.json",
}

M.state = {
  projects = {},     -- List of projects
  tab_projects = {}, -- Map of tab number -> project
}

-- TODO: Use Telescope path picker
function M.add_project(path)
  path = vim.fn.fnamemodify(path, ":p")

  for _, project in ipairs(M.state.projects) do
    if project.path == path then
      return
    end
  end

  local name = vim.fn.fnamemodify(path, ":t")
  local project = {
    path = path,
    name = name,
  }
  table.insert(M.state.projects, project)

  M.save_projects()
end

function M.delete_project(path)
  -- Ensure path is absolute
  path = vim.fn.fnamemodify(path, ":p")

  -- Find and remove the project
  for i, project in ipairs(M.state.projects) do
    if project.path == path then
      table.remove(M.state.projects, i)
      M.save_projects()
      vim.notify(string.format("Deleted project: %s", project.name), vim.log.levels.INFO)
      return
    end
  end
  vim.notify("Project not found", vim.log.levels.WARN)
end

function M.open_project(path)
  for tabnr, project_path in pairs(M.state.tab_projects) do
    if project_path == path then
      vim.cmd("tabnext " .. tabnr)
      return
    end
  end

  vim.cmd("tabnew")
  local tabnr = vim.fn.tabpagenr()
  vim.cmd("tcd " .. path)
  M.state.tab_projects[tabnr] = path
end

function M.save_projects()
  local file = io.open(M.config.projects_file, "w")
  if file then
    file:write(vim.fn.json_encode(M.state.projects))
    file:close()
  end
end

function M.load_projects()
  local file = io.open(M.config.projects_file, "r")
  if file then
    local content = file:read("*all")
    file:close()
    if content and content ~= "" then
      M.state.projects = vim.fn.json_decode(content)
    end
  end
end

-- Telescope integration
function M.project_picker(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = opts or {}

  -- Build format needed by Telescope
  local projects = {}
  for _, project in ipairs(M.state.projects) do
    table.insert(projects, {
      value = project.path,
      display = project.name,
      ordinal = project.name,
    })
  end

  pickers
      .new(opts, {
        prompt_title = "Projects",
        finder = finders.new_table({
          results = projects,
          entry_maker = function(entry)
            return {
              value = entry.value,
              display = entry.display,
              ordinal = entry.ordinal,
            }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            M.open_project(selection.value)
          end)
          return true
        end,
      })
      :find()
end

function M.project_buffers(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = opts or {}

  local tabnr = vim.fn.tabpagenr()
  local project_path = M.state.tab_projects[tabnr]

  if not project_path then
    vim.notify("Not in a project tab", vim.log.levels.WARN)
    return
  end

  local buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if vim.startswith(bufname, project_path) then
      table.insert(buffers, {
        value = bufnr,
        display = vim.fn.fnamemodify(bufname, ":~:."),
        ordinal = bufname,
      })
    end
  end

  pickers
      .new(opts, {
        prompt_title = "Project Buffers",
        finder = finders.new_table({
          results = buffers,
          entry_maker = function(entry)
            return {
              value = entry.value,
              display = entry.display,
              ordinal = entry.ordinal,
            }
          end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            vim.api.nvim_set_current_buf(selection.value)
          end)
          return true
        end,
      })
      :find()
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M.load_projects()

  -- Register Telescope extension
  local has_telescope, telescope = pcall(require, "telescope")
  if has_telescope then
    telescope.register_extension({
      exports = {
        projectile = M.project_picker,
        ["projectile_buffers"] = M.project_buffers,
      },
    })
  end
end

return M
