local config = require("hdlsnip.config")
local hdlsnip = require("hdlsnip")

--- The mapping for `lhs` in `mode`, or nil.
---
--- Via maparg rather than nvim_get_keymap: Neovim normalises a stored lhs
--- (`<C-s>` becomes `<C-S>`), and maparg normalises the query the same way
local function mapping(mode, lhs)
  local map = vim.fn.maparg(lhs, mode, false, true)
  if vim.tbl_isempty(map) then
    return nil
  end
  return map
end

local function reset()
  -- Back to the defaults, which map nothing.
  hdlsnip.setup({})
end

describe("keymaps", function()
  after_each(reset)

  it("creates nothing by default", function()
    hdlsnip.setup({})
    assert.is_nil(mapping("i", "<F13>"))
    assert.is_nil(mapping("i", "<F14>"))
  end)

  it("creates only what is configured", function()
    hdlsnip.setup({ keys = { expand = "<F13>" } })
    assert.is_not_nil(mapping("i", "<F13>"))
    assert.is_nil(mapping("s", "<F14>"))
  end)

  it("maps the jumps in insert and select mode", function()
    hdlsnip.setup({ keys = { jump_next = "<F14>", jump_prev = "<F15>" } })
    assert.is_not_nil(mapping("i", "<F14>"))
    assert.is_not_nil(mapping("s", "<F14>"))
    assert.is_not_nil(mapping("i", "<F15>"))
    assert.is_not_nil(mapping("s", "<F15>"))
  end)

  it("describes what each mapping does", function()
    hdlsnip.setup({ keys = { expand = "<F13>" } })
    assert.matches("hdlsnip", mapping("i", "<F13>").desc)
  end)

  it("removes the previous mappings when setup runs again", function()
    hdlsnip.setup({ keys = { expand = "<F13>" } })
    assert.is_not_nil(mapping("i", "<F13>"))

    hdlsnip.setup({ keys = { expand = "<F14>" } })
    assert.is_nil(mapping("i", "<F13>"))
    assert.is_not_nil(mapping("i", "<F14>"))
  end)

  it("removes a mapping set to false", function()
    hdlsnip.setup({ keys = { expand = "<F13>" } })
    hdlsnip.setup({ keys = { expand = false } })
    assert.is_nil(mapping("i", "<F13>"))
  end)
end)

describe("keymap validation", function()
  local function errors_for(keys)
    local cfg = config.resolve(config.merge(config.defaults, { keys = keys }))
    local _, errs = config.validate(cfg)
    return table.concat(errs, "\n")
  end

  it("accepts a mapping or false", function()
    assert.are.equal("", errors_for({ expand = "<F13>" }))
    assert.are.equal("", errors_for({ expand = false }))
  end)

  it("rejects an empty mapping", function()
    assert.matches("keys%.expand", errors_for({ expand = "" }))
  end)

  it("rejects a non-string", function()
    assert.matches("keys%.jump_next", errors_for({ jump_next = 42 }))
  end)

  it("rejects an unknown key", function()
    assert.matches("unknown option", errors_for({ jump_sideways = "<F13>" }))
  end)
end)
