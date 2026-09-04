local config = require("hdlsnip.config")

local function fresh()
  package.loaded["hdlsnip.config"] = nil
  return require("hdlsnip.config")
end

describe("config defaults", function()
  it("validate cleanly", function()
    local cfg = config.resolve(vim.deepcopy(config.defaults))
    local ok, errors = config.validate(cfg)
    assert.is_true(ok, table.concat(errors, "; "))
  end)

  it("are not mutated by setup", function()
    local c = fresh()
    local before = vim.deepcopy(c.defaults)
    c.setup({ clock = { name = "aclk" }, keyword_case = "upper" })
    assert.are.same(before, c.defaults)
  end)
end)

describe("config merge", function()
  it("keeps sibling defaults when one leaf is overridden", function()
    local c = fresh()
    local cfg = c.setup({ reset = { polarity = "high" } })
    assert.are.equal("high", cfg.reset.polarity)
    assert.are.equal("async", cfg.reset.style)
    assert.are.equal("clk", cfg.clock.name)
  end)

  it("derives reset.name from polarity", function()
    local c = fresh()
    assert.are.equal("rst_n", c.setup({}).reset.name)
    assert.are.equal(
      "rst",
      c.setup({ reset = { polarity = "high" } }).reset.name
    )
  end)

  it("honours an explicit reset.name", function()
    local c = fresh()
    local cfg = c.setup({ reset = { polarity = "high", name = "reset_p" } })
    assert.are.equal("reset_p", cfg.reset.name)
  end)

  it(
    "re-derives reset.name when polarity changes after a named reset",
    function()
      local c = fresh()
      c.setup({ reset = { polarity = "high" } })
      assert.are.equal(
        "rst",
        c.setup({ reset = { polarity = "high" } }).reset.name
      )
      assert.are.equal("rst_n", c.setup({}).reset.name)
    end
  )
end)

describe("config validation", function()
  local function errors_for(tbl)
    local cfg = config.resolve(config.merge(config.defaults, tbl))
    local _, errs = config.validate(cfg)
    return table.concat(errs, "\n")
  end

  it("rejects an unknown enum value and names the path", function()
    assert.matches(
      "reset%.polarity",
      errors_for({ reset = { polarity = "inverted" } })
    )
  end)

  it("rejects a wrong type", function()
    assert.matches(
      "align_ports: expected boolean",
      errors_for({ align_ports = "yes" })
    )
  end)

  it("rejects mixed indentation", function()
    assert.matches("indent", errors_for({ indent = " \t" }))
  end)

  it("rejects an empty indent", function()
    assert.matches("indent", errors_for({ indent = "" }))
  end)

  it("rejects unknown options", function()
    assert.matches("unknown option", errors_for({ vdhl_std = "2008" }))
  end)

  it("rejects reserved words as signal names", function()
    assert.matches("reserved word", errors_for({ clock = { name = "signal" } }))
  end)

  it("allows a VHDL-2008 reserved word under VHDL-93", function()
    assert.are.equal(
      "",
      errors_for({ vhdl_std = "93", clock = { name = "context" } })
    )
    assert.matches(
      "reserved word",
      errors_for({ vhdl_std = "2008", clock = { name = "context" } })
    )
  end)

  it("rejects malformed identifiers", function()
    assert.matches("identifier", errors_for({ clock = { name = "2clk" } }))
    assert.matches("identifier", errors_for({ clock = { name = "clk_" } }))
    assert.matches("identifier", errors_for({ clock = { name = "a__b" } }))
  end)

  it("keeps the previous configuration when setup is invalid", function()
    local c = fresh()
    c.setup({ clock = { name = "aclk" } })
    local kept = c.setup({ reset = { polarity = "sideways" } })
    assert.are.equal("aclk", kept.clock.name)
    assert.are.equal("low", kept.reset.polarity)
  end)
end)
