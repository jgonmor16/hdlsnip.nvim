--- Two-process finite state machine.
---
--- The first template with a `mixed` scope: the state type and its signals
--- belong above `begin`, the two processes below it, so the render function
--- returns both halves rather than one block of text.
---
--- Two processes rather than one because the state register and the next
--- state logic have different sensitivity: the register is clocked, the
--- combinational half is not. Merging them is legal and common, but it makes
--- every output a registered output whether that was intended or not.
local style = require("hdlsnip.style")

--- Split a comma-separated list into trimmed, non-empty entries.
---@param list string
---@return string[]
local function split(list)
  local out = {}
  for item in list:gmatch("[^,]+") do
    local trimmed = item:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      out[#out + 1] = trimmed
    end
  end
  return out
end

return {
  name = "fsm",
  trig = "fsm",
  kind = "rtl",
  scope = "mixed",
  desc = "Two-process finite state machine",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "main",
      desc = "Machine name, used for the type and the signals",
    },
    {
      name = "states",
      type = "string",
      default = "idle, run, done",
      example = "init, load, shift, done",
      desc = "State names, comma separated",
      check = function(value)
        local states = split(value)
        if #states < 2 then
          return false, "needs at least two states"
        end
        local seen = {}
        for _, state in ipairs(states) do
          if not state:match("^%a[%w_]*$") then
            return false, ("%q is not a valid identifier"):format(state)
          end
          if seen[state:lower()] then
            return false, ("%q appears twice"):format(state)
          end
          seen[state:lower()] = true
        end
        return true
      end,
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local states = split(params.states)
    local type_name = "t_" .. params.name .. "_state"
    local state_r = style.name(cfg, params.name .. "_state", "register")
    local state_next = params.name .. "_state_next"
    local modern = tonumber(cfg.vhdl_std) >= 2008

    local declarations, statements = {}, {}

    local function decl(depth, text)
      declarations[#declarations + 1] = text == "" and ""
        or (ind:rep(depth) .. text)
    end
    local function stmt(depth, text)
      statements[#statements + 1] = text == "" and ""
        or (ind:rep(depth) .. text)
    end

    decl(
      0,
      ("%s %s %s (%s);"):format(
        kw("type"),
        type_name,
        kw("is"),
        table.concat(states, ", ")
      )
    )
    decl(0, "")
    local signals = style.align({
      { state_r, (": %s := %s;"):format(type_name, states[1]) },
      { state_next, (": %s;"):format(type_name) },
    })
    for _, line in ipairs(signals) do
      decl(0, kw("signal") .. " " .. line)
    end

    -- State register: the only clocked part, and the only part that resets.
    local reg_label = style.name(cfg, params.name .. "_state", "process")
    stmt(
      0,
      ("%s : %s %s %s"):format(
        reg_label,
        kw("process"),
        style.sensitivity(cfg),
        kw("is")
      )
    )
    stmt(0, kw("begin"))
    if cfg.reset.style == "async" then
      stmt(
        1,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      stmt(2, ("%s <= %s;"):format(state_r, states[1]))
      stmt(
        1,
        ("%s %s %s"):format(kw("elsif"), style.clock_edge(cfg), kw("then"))
      )
      stmt(2, ("%s <= %s;"):format(state_r, state_next))
      stmt(1, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      stmt(1, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      stmt(
        2,
        ("%s %s %s"):format(kw("if"), style.reset_active(cfg), kw("then"))
      )
      stmt(3, ("%s <= %s;"):format(state_r, states[1]))
      stmt(2, kw("else"))
      stmt(3, ("%s <= %s;"):format(state_r, state_next))
      stmt(2, kw("end if") .. ";")
      stmt(1, kw("end if") .. ";")
    else
      stmt(1, ("%s %s %s"):format(kw("if"), style.clock_edge(cfg), kw("then")))
      stmt(2, ("%s <= %s;"):format(state_r, state_next))
      stmt(1, kw("end if") .. ";")
    end
    stmt(0, ("%s %s %s;"):format(kw("end"), kw("process"), reg_label))
    stmt(0, "")

    -- Next state logic. `process (all)` is VHDL-2008; before that the list is
    -- explicit, and an incomplete one is the classic source of a simulation
    -- and synthesis mismatch.
    local next_label = style.name(cfg, params.name .. "_next", "process")
    local sensitivity = modern and ("(%s)"):format(kw("all"))
      or ("(%s)"):format(state_r)
    stmt(
      0,
      ("%s : %s %s %s"):format(next_label, kw("process"), sensitivity, kw("is"))
    )
    stmt(0, kw("begin"))
    if not modern then
      stmt(1, "-- Add every signal read below to the sensitivity list.")
    end
    stmt(1, "-- Default assignment, so every path is covered and the logic")
    stmt(1, "-- stays combinational rather than inferring a latch.")
    stmt(1, ("%s <= %s;"):format(state_next, state_r))
    stmt(1, "")
    stmt(1, ("%s %s %s"):format(kw("case"), state_r, kw("is")))
    for index, state in ipairs(states) do
      stmt(2, ("%s %s =>"):format(kw("when"), state))
      local following = states[index + 1]
      if following then
        stmt(3, ("%s <= %s;"):format(state_next, following))
      else
        stmt(3, ("%s <= %s;"):format(state_next, states[1]))
      end
      stmt(2, "")
    end
    stmt(2, ("%s %s =>"):format(kw("when"), kw("others")))
    stmt(3, ("%s <= %s;"):format(state_next, states[1]))
    stmt(1, ("%s %s;"):format(kw("end"), kw("case")))
    stmt(0, ("%s %s %s;"):format(kw("end"), kw("process"), next_label))

    return {
      declarations = table.concat(declarations, "\n"),
      statements = table.concat(statements, "\n"),
    }
  end,
}
