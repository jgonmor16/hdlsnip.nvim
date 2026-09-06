local config = require("hdlsnip.config")
local style = require("hdlsnip.style")

local function cfg(over)
  return config.resolve(config.merge(config.defaults, over))
end

describe("style.kw", function()
  it("lowercases by default and uppercases on request", function()
    assert.are.equal("signal", style.kw(cfg({}))("signal"))
    assert.are.equal(
      "SIGNAL",
      style.kw(cfg({ keyword_case = "upper" }))("signal")
    )
  end)
end)

describe("style.clock_edge", function()
  it("follows the configured edge and clock name", function()
    assert.are.equal("rising_edge(clk)", style.clock_edge(cfg({})))
    assert.are.equal(
      "falling_edge(aclk)",
      style.clock_edge(cfg({ clock = { name = "aclk", edge = "falling" } }))
    )
  end)

  it("cases the function name with the keywords", function()
    assert.are.equal(
      "RISING_EDGE(clk)",
      style.clock_edge(cfg({ keyword_case = "upper" }))
    )
  end)
end)

describe("style.reset_active", function()
  it("matches polarity", function()
    assert.are.equal("rst_n = '0'", style.reset_active(cfg({})))
    assert.are.equal(
      "rst = '1'",
      style.reset_active(cfg({ reset = { polarity = "high" } }))
    )
  end)

  it("is empty when there is no reset", function()
    assert.are.equal(
      "",
      style.reset_active(cfg({ reset = { style = "none" } }))
    )
  end)
end)

describe("style.sensitivity", function()
  it("includes an asynchronous reset only", function()
    assert.are.equal("(clk, rst_n)", style.sensitivity(cfg({})))
    assert.are.equal(
      "(clk)",
      style.sensitivity(cfg({ reset = { style = "sync" } }))
    )
    assert.are.equal(
      "(clk)",
      style.sensitivity(cfg({ reset = { style = "none" } }))
    )
  end)
end)

describe("style.name", function()
  it("applies prefixes and suffixes per kind", function()
    local c = cfg({})
    assert.are.equal("data_i", style.name(c, "data", "input"))
    assert.are.equal("data_o", style.name(c, "data", "output"))
    assert.are.equal("count_r", style.name(c, "count", "register"))
    assert.are.equal("p_main", style.name(c, "main", "process"))
    assert.are.equal("C_WIDTH", style.name(c, "WIDTH", "constant"))
    assert.are.equal("G_WIDTH", style.name(c, "WIDTH", "generic"))
  end)

  it("honours a signal prefix", function()
    local c = cfg({ naming = { sig_prefix = "s_" } })
    assert.are.equal("s_busy", style.name(c, "busy", "signal"))
  end)
end)

describe("style.align", function()
  it("pads columns and leaves no trailing whitespace", function()
    local out = style.align({
      { "clk", ": in", "std_logic;" },
      { "data_valid", ": in", "std_logic;" },
    })
    assert.are.equal("clk        : in std_logic;", out[1])
    assert.are.equal("data_valid : in std_logic;", out[2])
    for _, line in ipairs(out) do
      assert.is_nil(line:match("%s$"))
    end
  end)

  it("handles ragged rows", function()
    local out = style.align({ { "a", "b" }, { "cc" } })
    assert.are.equal("a  b", out[1])
    assert.are.equal("cc", out[2])
  end)
end)

describe("style.is_legal_identifier", function()
  it("rejects reserved words for the configured standard", function()
    assert.is_false(style.is_legal_identifier(cfg({}), "entity"))
    assert.is_true(style.is_legal_identifier(cfg({ vhdl_std = "93" }), "force"))
    assert.is_false(
      style.is_legal_identifier(cfg({ vhdl_std = "2008" }), "force")
    )
  end)

  it("is case insensitive, like VHDL", function()
    assert.is_false(style.is_legal_identifier(cfg({}), "Signal"))
  end)
end)

describe("style.apply_case", function()
  local upper = cfg({ keyword_case = "upper" })

  it("cases reserved words only", function()
    assert.are.equal(
      "SIGNAL count_r : std_logic;",
      style.apply_case("signal count_r : std_logic;", upper)
    )
  end)

  it("leaves comments alone", function()
    assert.are.equal(
      "-- end of signal\nSIGNAL x",
      style.apply_case("-- end of signal\nsignal x", upper)
    )
  end)

  it("leaves string literals alone", function()
    assert.are.equal(
      'REPORT "end is near" SEVERITY note;',
      style.apply_case('report "end is near" severity note;', upper)
    )
  end)

  it("leaves character literals alone", function()
    assert.are.equal("x <= '0';", style.apply_case("x <= '0';", upper))
  end)

  it("does not mistake an attribute for a character literal", function()
    assert.are.equal(
      "y'high DOWNTO 0",
      style.apply_case("y'high downto 0", upper)
    )
  end)

  it("leaves marker names alone", function()
    assert.are.equal(
      "SIGNAL {{signal}} : std_logic;",
      style.apply_case("signal {{signal}} : std_logic;", upper)
    )
  end)

  it("normalises to lower case as well", function()
    assert.are.equal(
      "signal X : STD_LOGIC;",
      style.apply_case("SIGNAL X : STD_LOGIC;", cfg({}))
    )
  end)
end)
