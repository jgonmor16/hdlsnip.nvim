--- The template registry.
---
--- Templates are discovered from the runtimepath rather than hard-coded, so
--- a user can add their own house templates by dropping a file into their
--- config at the same path. Because Neovim searches the user's config
--- directory before plugins, a file there with the same name shadows the one
--- shipped here -- overriding a template needs no configuration at all.
---
--- Layout, and the invariant enforced on it:
---
---   lua/hdlsnip/templates/<lang>/<kind>/<name>.lua
---
--- The directory names must match the template's own `kind` field and the
--- file name its `name` field. A template that says one thing and lives
--- somewhere else is rejected at load: the picker groups by `kind`, and a
--- mismatch would put a template somewhere nobody looks for it.
---
--- The `<lang>` level exists so a future SystemVerilog set can share this
--- engine without restructuring. Only `vhdl` is accepted today.
local template = require("hdlsnip.template")

local M = {}

--- Languages the registry will load. Anything else is reported and skipped.
M.languages = { vhdl = true }

M.default_language = "vhdl"

local PATTERN = "lua/hdlsnip/templates/*/*/*.lua"

local state = {
  loaded = false,
  index = {}, ---@type table<string, table<string, table>>
  triggers = {}, ---@type table<string, table<string, string>>
  problems = {}, ---@type string[]
}

local function problem(fmt, ...)
  state.problems[#state.problems + 1] = fmt:format(...)
end

--- Split `.../templates/<lang>/<kind>/<name>.lua`. Accepts both separators so
--- the same code works on Windows.
---@param path string
---@return string? lang
---@return string? kind
---@return string? name
local function parse_path(path)
  return path:match("templates[/\\]([^/\\]+)[/\\]([^/\\]+)[/\\]([^/\\]+)%.lua$")
end

--- Add an already-built template to the index.
---
--- Used by `load()` and available to users who would rather build a template
--- in their config than put it in a file.
---@param tpl table
---@param source string? where it came from, for error messages
---@return boolean ok
---@return string[] errors
function M.register(tpl, source)
  source = source or "register()"

  if type(tpl) ~= "table" then
    local err = ("%s: expected a template table, got %s"):format(
      source,
      type(tpl)
    )
    return false, { err }
  end

  local lang = tpl.lang or M.default_language
  if not M.languages[lang] then
    return false, { ("%s: unknown language %q"):format(source, tostring(lang)) }
  end

  local ok, errors = template.validate(tpl)
  if not ok then
    return false, errors
  end

  -- Triggers must be unique: two templates firing on the same word would
  -- make expansion depend on load order, which is invisible to the user.
  -- Checked before anything is indexed, so a rejected template leaves no
  -- trace behind.
  if tpl.trig then
    local owner = (state.triggers[lang] or {})[tpl.trig]
    if owner and owner ~= tpl.name then
      return false,
        {
          ("%s: trigger %q is already used by %s"):format(
            source,
            tpl.trig,
            owner
          ),
        }
    end
  end

  tpl.lang = lang
  tpl.source = source
  state.index[lang] = state.index[lang] or {}
  state.index[lang][tpl.name] = tpl
  if tpl.trig then
    state.triggers[lang] = state.triggers[lang] or {}
    state.triggers[lang][tpl.trig] = tpl.name
  end
  return true, {}
end

--- Load one discovered file into the index.
---@param path string
local function load_file(path)
  local lang, kind, name = parse_path(path)
  if not lang then
    problem("%s: does not match templates/<lang>/<kind>/<name>.lua", path)
    return
  end
  if not M.languages[lang] then
    problem("%s: unknown language directory %q", path, lang)
    return
  end

  -- The first match on the runtimepath wins, so a template in the user's
  -- config shadows the one shipped with the plugin.
  if state.index[lang] and state.index[lang][name] then
    return
  end

  local chunk, load_err = loadfile(path)
  if not chunk then
    problem("%s: %s", path, load_err)
    return
  end

  local ok, tpl = pcall(chunk)
  if not ok then
    problem("%s: %s", path, tpl)
    return
  end
  if type(tpl) ~= "table" then
    problem("%s: must return a template table, got %s", path, type(tpl))
    return
  end

  if tpl.name ~= name then
    problem(
      "%s: name is %q but the file is %s.lua",
      path,
      tostring(tpl.name),
      name
    )
    return
  end
  if tpl.kind ~= kind then
    problem(
      "%s: kind is %q but it lives in %s/",
      path,
      tostring(tpl.kind),
      kind
    )
    return
  end

  tpl.lang = lang
  local registered, errors = M.register(tpl, path)
  if not registered then
    for _, err in ipairs(errors) do
      problem("%s: %s", path, err)
    end
  end
end

--- Discover and load every template on the runtimepath.
---
--- Idempotent: the first call populates the index and later calls are free,
--- so lookups can call it without the caller having to sequence anything.
---@param opts table? `{ force = true }` to rescan
---@return table index
function M.load(opts)
  opts = opts or {}
  if state.loaded and not opts.force then
    return state.index
  end

  state.index, state.triggers, state.problems = {}, {}, {}
  for _, path in ipairs(vim.api.nvim_get_runtime_file(PATTERN, true)) do
    load_file(path)
  end
  state.loaded = true

  -- One notification for the batch. A broken template is skipped rather than
  -- aborting the load, so one bad file in a user's config cannot take the
  -- whole library down with it.
  if #state.problems > 0 then
    vim.notify(
      "hdlsnip: skipped templates that failed to load\n  "
        .. table.concat(state.problems, "\n  "),
      vim.log.levels.WARN
    )
  end

  return state.index
end

--- Rescan the runtimepath. For `:HdlSnipReload` and for tests.
---@return table index
function M.reload()
  return M.load({ force = true })
end

--- Look up one template by name.
---@param name string
---@param lang string? defaults to vhdl
---@return table?
function M.get(name, lang)
  M.load()
  return (state.index[lang or M.default_language] or {})[name]
end

--- Look up one template by its trigger word.
---@param trig string
---@param lang string? defaults to vhdl
---@return table?
function M.by_trigger(trig, lang)
  M.load()
  lang = lang or M.default_language
  local name = (state.triggers[lang] or {})[trig]
  return name and state.index[lang][name] or nil
end

--- Every template, sorted by kind then name so the picker and the tests both
--- see a stable order.
---@param filter table? `{ kind = "rtl", lang = "vhdl" }`
---@return table[]
function M.list(filter)
  M.load()
  filter = filter or {}

  local out = {}
  for lang, by_name in pairs(state.index) do
    if not filter.lang or filter.lang == lang then
      for _, tpl in pairs(by_name) do
        if not filter.kind or filter.kind == tpl.kind then
          out[#out + 1] = tpl
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.kind ~= b.kind then
      return a.kind < b.kind
    end
    return a.name < b.name
  end)
  return out
end

--- Template names, for command completion.
---@param filter table?
---@return string[]
function M.names(filter)
  local out = {}
  for i, tpl in ipairs(M.list(filter)) do
    out[i] = tpl.name
  end
  return out
end

--- Problems recorded during the last load. For `:checkhealth hdlsnip`.
---@return string[]
function M.problems()
  M.load()
  return vim.deepcopy(state.problems)
end

return M
