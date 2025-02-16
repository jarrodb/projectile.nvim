local M = {}

M.config = {
  projects_file = vim.fn.stdpath("data") .. "/projectile_projects.json",
}

M.state = {
  projects = {},     -- List of projects
  tab_projects = {}, -- Map of tab number -> project
}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local function get_dirs(path)
  local search_path = path
  if path:sub(-1) == "/" then
    search_path = search_path:sub(1, -2)       -- remove trailing /
  else
    search_path = path:match("^(.*)/") or path -- search up to the last /
  end

  local result = vim.fn.systemlist('find "' .. search_path .. '" -maxdepth 1 -type d')
  local dirs = {}

  search_path = search_path .. "/" -- ensure current search path is first

  table.insert(dirs, {
    value = search_path,
    display = search_path,
    ordinal = search_path,
  })

  for _, dir in ipairs(result) do
    if dir ~= search_path then
      table.insert(dirs, {
        value = dir,
        display = dir,
        ordinal = dir,
      })
    end
  end

  return dirs
end

local function refresh_picker(prompt_bufnr, input)
  local new_dirs = get_dirs(input)
  local picker = action_state.get_current_picker(prompt_bufnr)
  picker:refresh(
    finders.new_table({
      results = new_dirs,
      entry_maker = function(entry)
        return entry
      end,
    }),
    { reset_prompt = false }
  )
end

function M.add_project()
  local current_path = vim.fn.getcwd()
  local initial_dirs = get_dirs(current_path)

  pickers
      .new({}, {
        prompt_title = "Search Path",
        results_title = "Project Directories",
        default_text = current_path,
        finder = finders.new_table({
          results = initial_dirs,
          entry_maker = function(entry)
            return entry
          end,
        }),
        sorter = conf.generic_sorter({ fuzzy = false }),
        previewer = false,

        -- Here we set up our custom key mappings and attach a change callback.
        attach_mappings = function(prompt_bufnr, map)
          -- vim.api.nvim_buf_set_option(prompt_bufnr, "omnifunc", "")
          -- vim.b[prompt_bufnr].cmp_enabled = false

          require("cmp").setup.filetype("TelescopePrompt", {
            enabled = false,
          })

          -- Backspace mapping: remove the last directory element from the prompt.
          map("i", "<bs>", function()
            local prompt = action_state.get_current_line()

            if prompt:sub(-1) == "/" then
              prompt = prompt:gsub("^(.*)/[^/]+/$", "%1/")
            else
              prompt = prompt:sub(1, -2)
            end

            action_state.get_current_picker(prompt_bufnr):set_prompt(prompt)
            refresh_picker(prompt_bufnr, prompt)
          end)

          map("i", "<Tab>", function()
            local picker = action_state.get_current_picker(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection then
              local new_prompt = selection.value .. "/"
              picker:set_prompt(new_prompt)
              refresh_picker(prompt_bufnr, new_prompt)
            end
          end)

          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end

            local sel_value = selection.value or ""
            sel_value = sel_value:gsub("/$", "")
            local name = vim.fn.fnamemodify(sel_value, ":t")

            actions.close(prompt_bufnr)

            -- Save project to state and write for persistence
            table.insert(M.state.projects, {
              name = name,
              path = sel_value,
            })
            M.save_projects()
          end)

          -- Watch for changes in the prompt buffer. When the prompt changes,
          -- update the finder results based on the new path.
          vim.api.nvim_buf_attach(prompt_bufnr, false, {
            on_lines = function()
              local prompt = action_state.get_current_line()
              if prompt == "" then
                return
              end

              refresh_picker(prompt_bufnr, prompt)
            end,
          })

          return true
        end,
      })
      :find()
end

function M.delete_project(opts)
  opts = type(opts) == "table" and opts or {}

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
        prompt_title = "Delete Project",
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

        attach_mappings = function()
          actions.select_default:replace(function(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            if selection then
              actions.close(prompt_bufnr)
              local path = selection.value

              -- Find and remove the project
              for i, project in ipairs(M.state.projects) do
                if project.path == path then
                  table.remove(M.state.projects, i)
                  M.save_projects()
                  vim.notify(
                    string.format("%s removed from your project list", project.name),
                    vim.log.levels.INFO
                  )

                  -- Check if a tab exists with that project and close it
                  for tabnr, project_path in pairs(M.state.tab_projects) do
                    if project_path == path then
                      vim.cmd("tabclose " .. tabnr)
                      M.state.tab_projects[tabnr] = nil
                    end
                  end
                  return
                end
              end
            end
          end)
          return true
        end,
      })
      :find()
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

-- using scope instead with bufferline...
function M.project_buffers(opts)
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
