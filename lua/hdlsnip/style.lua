--- House-style primitives shared by every template.
---
--- Templates never spell out `rising_edge(clk)` or `if rst_n = '0' then`
--- directly: they ask this module, so one configuration change re-renders the
--- whole library consistently.
local keywords = require("hdlsnip.vhdl.keywords")

local M = {}

--- Reserved-word caser. Identifiers are never touched -- VHDL is case
--- insensitive, but a user who writes `AXI_AWADDR` expects it back verbatim.
---@param cfg table
---@return fun(word: string): string
function M.kw(cfg)
  if cfg.keyword_case == "upper" then
    return string.upper
  end
  return string.lower
end

---@param cfg table
---@param level integer? number of indent levels, default 1
---@return string
function M.indent(cfg, level)
  return cfg.indent:rep(level or 1)
end

--- Clock edge expression, e.g. `rising_edge(clk)`.
---@param cfg table
---@return string
function M.clock_edge(cfg)
  local fn = cfg.clock.edge == "falling" and "falling_edge" or "rising_edge"
  return ("%s(%s)"):format(M.kw(cfg)(fn), cfg.clock.name)
end

--- Reset condition expression, e.g. `rst_n = '0'`. Empty when reset is off.
---@param cfg table
---@return string
function M.reset_active(cfg)
  if cfg.reset.style == "none" then
    return ""
  end
  return ("%s = '%s'"):format(
    cfg.reset.name,
    cfg.reset.polarity == "low" and "0" or "1"
  )
end

--- Sensitivity list for a clocked process, including the reset only when it
--- is asynchronous. A synchronous reset in the sensitivity list is the
--- classic way to get a simulation/synthesis mismatch past review.
---@param cfg table
---@return string
function M.sensitivity(cfg)
  if cfg.reset.style == "async" then
    return ("(%s, %s)"):format(cfg.clock.name, cfg.reset.name)
  end
  return ("(%s)"):format(cfg.clock.name)
end

--- Apply the configured naming convention.
---@param cfg table
---@param base string
---@param kind "input"|"output"|"register"|"signal"|"process"|"constant"|"generic"
---@return string
function M.name(cfg, base, kind)
  local n = cfg.naming
  local map = {
    input = { n.sig_prefix, n.in_suffix },
    output = { n.sig_prefix, n.out_suffix },
    register = { n.sig_prefix, n.reg_suffix },
    signal = { n.sig_prefix, "" },
    process = { n.proc_prefix, "" },
    constant = { n.const_prefix, "" },
    generic = { n.generic_prefix, "" },
  }
  local fix = map[kind] or { "", "" }
  return fix[1] .. base .. fix[2]
end

---@param s string
---@return integer display width
function M.width(s)
  if vim and vim.fn and vim.fn.strdisplaywidth then
    return vim.fn.strdisplaywidth(s)
  end
  return #s
end

--- Pad rows of cells into aligned columns. The last cell of each row is not
--- padded, so no trailing whitespace reaches the buffer.
---@param rows string[][]
---@param sep string? column separator, default a single space
---@return string[]
function M.align(rows, sep)
  sep = sep or " "
  local widths = {}
  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      widths[i] = math.max(widths[i] or 0, M.width(cell))
    end
  end
  local out = {}
  for _, row in ipairs(rows) do
    local cells = {}
    for i, cell in ipairs(row) do
      cells[i] = i < #row and (cell .. (" "):rep(widths[i] - M.width(cell)))
        or cell
    end
    out[#out + 1] = table.concat(cells, sep)
  end
  return out
end

--- True when `word` may be used as an identifier under the configured
--- standard.
---@param cfg table
---@param word string
---@return boolean
function M.is_legal_identifier(cfg, word)
  if not word:match("^%a[%w_]*$") or word:match("__") or word:match("_$") then
    return false
  end
  return not keywords.is_reserved(word, cfg.vhdl_std)
end

--- Apply the configured keyword case to a block of VHDL.
---
--- Static template bodies are literal text, so they cannot call `kw()` the
--- way a render function does. They are authored in lower case and passed
--- through here instead, which is what lets a static body honour
--- `keyword_case` at all.
---
--- The scan skips the four places a reserved word is not a keyword: comments,
--- string literals, character literals such as `'0'`, and `{{marker}}` names,
--- which are parameter names rather than VHDL. Attribute names survive
--- because `x'high` opens no character literal -- the quote is not followed
--- by a closing one two characters later.
---@param text string
---@param cfg table
---@return string
function M.apply_case(text, cfg)
  local transform = M.kw(cfg)
  local out, i, n = {}, 1, #text

  while i <= n do
    local two = text:sub(i, i + 1)
    local c = text:sub(i, i)

    if two == "--" then
      local stop = text:find("\n", i) or (n + 1)
      out[#out + 1] = text:sub(i, stop - 1)
      i = stop
    elseif two == "{{" then
      local stop = text:find("}}", i, true)
      stop = stop and (stop + 1) or n
      out[#out + 1] = text:sub(i, stop)
      i = stop + 1
    elseif c == '"' then
      local stop = text:find('"', i + 1, true) or n
      out[#out + 1] = text:sub(i, stop)
      i = stop + 1
    elseif c == "'" and text:sub(i + 2, i + 2) == "'" then
      out[#out + 1] = text:sub(i, i + 2)
      i = i + 3
    elseif c:match("%a") then
      local word = text:match("^%a[%w_]*", i)
      out[#out + 1] = keywords.is_reserved(word, cfg.vhdl_std)
          and transform(word)
        or word
      i = i + #word
    else
      out[#out + 1] = c
      i = i + 1
    end
  end

  return table.concat(out)
end

return M
