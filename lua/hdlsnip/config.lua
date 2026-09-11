--- Configuration for hdlsnip.nvim.
---
--- Every template reads its house style from here, so the resolved table is
--- validated eagerly: a typo in `reset.polarity` should fail at `setup()`
--- with a readable message, not silently emit an active-high reset into a
--- design that expects active low.
local keywords = require("hdlsnip.vhdl.keywords")

local M = {}

---@class hdlsnip.Config
M.defaults = {
  --- VHDL revision the templates target. Affects reserved words, and later
  --- whether templates may emit 2008-only constructs.
  vhdl_std = "2008",

  --- Case of emitted reserved words. Identifiers always keep the case given.
  keyword_case = "lower", ---@type "lower"|"upper"

  --- One indent level. Spaces or tabs, never mixed.
  indent = "  ",

  clock = {
    name = "clk",
    edge = "rising", ---@type "rising"|"falling"
  },

  reset = {
    style = "async", ---@type "async"|"sync"|"none"
    polarity = "low", ---@type "low"|"high"
    --- Left unset by default and derived from `polarity`: `rst_n` when
    --- active low, `rst` when active high. Set explicitly to override.
    name = nil, ---@type string?
  },

  naming = {
    in_suffix = "_i",
    out_suffix = "_o",
    reg_suffix = "_r",
    sig_prefix = "",
    proc_prefix = "p_",
    const_prefix = "C_",
    generic_prefix = "G_",
  },

  --- Target family. Selects vendor attributes such as `async_reg` (AMD) or
  --- `preserve` (Intel), and inference-friendly RAM coding styles.
  vendor = "generic", ---@type "generic"|"amd"|"intel"|"lattice"|"microchip"

  --- Align the columns of generated port and signal declarations.
  align_ports = true,

  --- Optional file header. Receives a context table, returns lines.
  header = nil, ---@type fun(ctx: table): string[]|nil

  --- Offer templates through an in-process LSP server, so they appear in
  --- whatever completion menu is already in use. Costs nothing when idle:
  --- the server is a Lua table, not a process.
  lsp = true,

  --- Mappings created by `setup()`. Every entry is `false` by default: a
  --- plugin that claims keys on install is a plugin people uninstall.
  keys = {
    expand = false, ---@type string|false trigger word before the cursor
    jump_next = false, ---@type string|false next tabstop
    jump_prev = false, ---@type string|false previous tabstop
  },
}

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

local function is_identifier(v, std)
  if type(v) ~= "string" then
    return false, "must be a string"
  end
  -- VHDL basic identifier: letter, then letters/digits/underscores, with no
  -- doubled or trailing underscore (LRM 15.4).
  if not v:match("^%a[%w_]*$") or v:match("__") or v:match("_$") then
    return false, "not a valid VHDL basic identifier"
  end
  if keywords.is_reserved(v, std) then
    return false, ("'%s' is a VHDL-%s reserved word"):format(v, std)
  end
  return true
end

local function keymap(v)
  if v == false then
    return true
  end
  if type(v) ~= "string" or v == "" then
    return false, 'must be a mapping such as "<C-k>", or false'
  end
  return true
end

local function affix(v)
  if type(v) ~= "string" then
    return false, "must be a string"
  end
  if v ~= "" and not v:match("^[%a_][%w_]*$") then
    return false, "must be empty or an identifier fragment"
  end
  return true
end

--- Leaf specs carry `one_of`, `type` or `check`; anything else is a subtable.
local schema = {
  vhdl_std = { one_of = { "93", "2002", "2008", "2019" } },
  keyword_case = { one_of = { "lower", "upper" } },
  indent = {
    type = "string",
    check = function(v)
      if not v:match("^[ \t]+$") then
        return false, "must be one or more spaces or tabs"
      end
      if v:match(" ") and v:match("\t") then
        return false, "must not mix spaces and tabs"
      end
      return true
    end,
  },
  clock = {
    name = { type = "string", check = is_identifier },
    edge = { one_of = { "rising", "falling" } },
  },
  reset = {
    style = { one_of = { "async", "sync", "none" } },
    polarity = { one_of = { "low", "high" } },
    name = { type = "string", optional = true, check = is_identifier },
  },
  naming = {
    in_suffix = { type = "string", check = affix },
    out_suffix = { type = "string", check = affix },
    reg_suffix = { type = "string", check = affix },
    sig_prefix = { type = "string", check = affix },
    proc_prefix = { type = "string", check = affix },
    const_prefix = { type = "string", check = affix },
    generic_prefix = { type = "string", check = affix },
  },
  vendor = { one_of = { "generic", "amd", "intel", "lattice", "microchip" } },
  align_ports = { type = "boolean" },
  lsp = { type = "boolean" },
  header = { type = "function", optional = true },
  keys = {
    expand = { check = keymap },
    jump_next = { check = keymap },
    jump_prev = { check = keymap },
  },
}

local function is_leaf(spec)
  return spec.one_of ~= nil or spec.type ~= nil or spec.check ~= nil
end

local function check_leaf(spec, value, path, std, errors)
  if value == nil then
    if not spec.optional then
      errors[#errors + 1] = ("%s: missing"):format(path)
    end
    return
  end
  if spec.one_of then
    for _, allowed in ipairs(spec.one_of) do
      if value == allowed then
        return
      end
    end
    errors[#errors + 1] = ("%s: expected one of %s, got %s"):format(
      path,
      table.concat(spec.one_of, ", "),
      vim.inspect(value)
    )
    return
  end
  if spec.type and type(value) ~= spec.type then
    errors[#errors + 1] = ("%s: expected %s, got %s"):format(
      path,
      spec.type,
      type(value)
    )
    return
  end
  if spec.check then
    local ok, why = spec.check(value, std)
    if not ok then
      errors[#errors + 1] = ("%s: %s"):format(path, why or "invalid")
    end
  end
end

local function walk(spec, tbl, path, std, errors)
  for key, sub in pairs(spec) do
    local value = tbl and tbl[key]
    local child = path == "" and key or (path .. "." .. key)
    if is_leaf(sub) then
      check_leaf(sub, value, child, std, errors)
    elseif value ~= nil and type(value) ~= "table" then
      errors[#errors + 1] = ("%s: expected table, got %s"):format(
        child,
        type(value)
      )
    else
      walk(sub, value, child, std, errors)
    end
  end
  -- Unknown keys are a typo often enough to be worth reporting.
  for key in pairs(tbl or {}) do
    if spec[key] == nil then
      errors[#errors + 1] = ("%s: unknown option"):format(
        path == "" and key or (path .. "." .. key)
      )
    end
  end
end

--- Validate a fully resolved configuration table.
---@param cfg table
---@return boolean ok
---@return string[] errors
function M.validate(cfg)
  local errors = {}
  local std = type(cfg.vhdl_std) == "string" and cfg.vhdl_std or "2008"
  walk(schema, cfg, "", std, errors)
  table.sort(errors)
  return #errors == 0, errors
end

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

--- Fill in values derived from other values. Kept separate from the defaults
--- so `reset.name` can follow `reset.polarity` when the user overrides one
--- and not the other -- an active-high reset called `rst_n` is the kind of
--- inconsistency that survives review and confuses everyone downstream.
---@param cfg table
---@return table
function M.resolve(cfg)
  if cfg.reset.name == nil then
    cfg.reset.name = cfg.reset.polarity == "low" and "rst_n" or "rst"
  end
  return cfg
end

--- Merge user options over a base table. Scalars and lists are replaced,
--- tables merged, so a user setting only `reset.polarity` keeps the default
--- style and derived name.
---@param base table
---@param user table?
---@return table
function M.merge(base, user)
  return vim.tbl_deep_extend("force", vim.deepcopy(base), user or {})
end

-- ---------------------------------------------------------------------------
-- Public state
-- ---------------------------------------------------------------------------

--- `raw` is the merge of defaults and user options *before* derivation, so a
--- project override that flips `reset.polarity` re-derives `reset.name`
--- instead of inheriting an already-derived one.
local raw = vim.deepcopy(M.defaults)
local current = M.resolve(vim.deepcopy(raw))

--- Apply user options.
---
--- Partial: options not given keep the value they already have, so calling
--- `setup()` twice accumulates rather than resetting everything not repeated
--- in the second call. Changing `keyword_case` must not silently unmap your
--- keys.
---
--- Invalid options are reported and ignored, and the previous configuration
--- is kept, so a bad `setup()` cannot leave templates rendering from a
--- half-applied table.
---@param user table?
---@return table cfg the configuration now in effect
function M.setup(user)
  local candidate_raw = M.merge(raw, user)
  local candidate = M.resolve(vim.deepcopy(candidate_raw))
  local ok, errors = M.validate(candidate)
  if not ok then
    vim.notify(
      "hdlsnip: invalid configuration, keeping previous values\n  "
        .. table.concat(errors, "\n  "),
      vim.log.levels.ERROR
    )
    return current
  end
  raw, current = candidate_raw, candidate
  M.clear_cache() -- project overrides were merged onto the old options
  return current
end

--- Configuration without any project override, so callers that must not
--- trigger a trust prompt have something to read.
---@return table
function M.get_global()
  return current
end

--- Configuration in effect for a buffer, including any project override.
---@param bufnr integer? defaults to the current buffer
---@return table
function M.get(bufnr)
  local project = M.project(bufnr)
  return project or current
end

-- ---------------------------------------------------------------------------
-- Project-local override
-- ---------------------------------------------------------------------------

local project_cache = {}

--- Load `.hdlsnip.lua` from the project root, if present.
---
--- The file is arbitrary Lua, so it goes through `vim.secure.read`, which
--- prompts once per file and remembers the decision -- the same trust model
--- Neovim uses for `exrc`. Declining leaves the global configuration in
--- place rather than failing.
---@param bufnr integer?
---@return table? cfg nil when there is no project override
function M.project(bufnr)
  bufnr = bufnr or 0

  -- vim.fs.root needs a path to search from, and a scratch buffer has none.
  -- Opening :HdlSnip in one is ordinary, so this must not throw.
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return nil
  end

  local ok, root = pcall(vim.fs.root, bufnr, { ".hdlsnip.lua" })
  if not ok or not root then
    return nil
  end
  local path = root .. "/.hdlsnip.lua"
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end

  local cached = project_cache[path]
  if cached and cached.mtime == stat.mtime.sec then
    return cached.cfg
  end

  local content = vim.secure.read(path)
  if not content then -- user declined to trust the file
    return nil
  end

  local chunk, load_err = loadstring(content, "@" .. path)
  if not chunk then
    vim.notify(("hdlsnip: %s: %s"):format(path, load_err), vim.log.levels.ERROR)
    return nil
  end

  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    vim.notify(
      ("hdlsnip: %s must return a table of options"):format(path),
      vim.log.levels.ERROR
    )
    return nil
  end

  local candidate = M.resolve(M.merge(raw, result))
  local valid, errors = M.validate(candidate)
  if not valid then
    vim.notify(
      ("hdlsnip: %s:\n  %s"):format(path, table.concat(errors, "\n  ")),
      vim.log.levels.ERROR
    )
    return nil
  end

  project_cache[path] = { mtime = stat.mtime.sec, cfg = candidate }
  return candidate
end

--- Drop cached project configurations. Exposed for tests and for a future
--- `:HdlSnipReload`.
function M.clear_cache()
  project_cache = {}
end

return M
