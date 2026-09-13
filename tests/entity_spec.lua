local entity = require("hdlsnip.vhdl.entity")

--- A source file as lines.
local function source(text)
  return vim.split(text, "\n", { plain = true })
end

local FIFO = source([[
library ieee;
  use ieee.std_logic_1164.all;

entity fifo is
  generic (
    G_WIDTH : positive := 8;
    G_DEPTH : positive := 16
  );
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    wr_en_i   : in  std_logic;
    wr_data_i : in  std_logic_vector(G_WIDTH - 1 downto 0);
    full_o    : out std_logic
  );
end entity fifo;
]])

describe("entity.parse", function()
  it("reads the name", function()
    assert.are.equal("fifo", entity.parse(FIFO).name)
  end)

  it("reads generics with their subtype and default", function()
    local parsed = entity.parse(FIFO)
    assert.are.equal(2, #parsed.generics)
    assert.are.equal("G_WIDTH", parsed.generics[1].name)
    assert.are.equal("positive", parsed.generics[1].subtype)
    assert.are.equal("8", parsed.generics[1].default)
  end)

  it("reads ports with their mode and subtype", function()
    local parsed = entity.parse(FIFO)
    assert.are.equal(5, #parsed.ports)
    assert.are.equal("clk", parsed.ports[1].name)
    assert.are.equal("in", parsed.ports[1].mode)
    assert.are.equal("std_logic", parsed.ports[1].subtype)
    assert.are.equal("out", parsed.ports[5].mode)
  end)

  it("keeps a constrained subtype whole", function()
    -- The parentheses in the range must not end the declaration early.
    assert.are.equal(
      "std_logic_vector(G_WIDTH - 1 downto 0)",
      entity.parse(FIFO).ports[4].subtype
    )
  end)

  it("expands several names sharing one declaration", function()
    local parsed = entity.parse(
      source("entity x is port (a, b, c : in std_logic); end entity x;")
    )
    assert.are.equal(3, #parsed.ports)
    assert.are.equal("b", parsed.ports[2].name)
    assert.are.equal("in", parsed.ports[3].mode)
  end)

  it("treats a port with no mode as an input", function()
    local parsed =
      entity.parse(source("entity x is port (a : std_logic); end entity x;"))
    assert.are.equal("in", parsed.ports[1].mode)
  end)

  it("ignores comments", function()
    local parsed = entity.parse(source(table.concat({
      "entity x is",
      "  port (",
      "    a : in std_logic -- the clock",
      "  );",
      "end entity x;",
    }, "\n")))
    assert.are.equal("std_logic", parsed.ports[1].subtype)
  end)

  it("reads an entity with no generics", function()
    local parsed =
      entity.parse(source("entity x is port (a : in std_logic); end entity x;"))
    assert.are.same({}, parsed.generics)
    assert.are.equal(1, #parsed.ports)
  end)

  it("is case insensitive, like VHDL", function()
    local parsed =
      entity.parse(source("ENTITY x IS PORT (a : IN std_logic); END ENTITY x;"))
    assert.are.equal("x", parsed.name)
    assert.are.equal("in", parsed.ports[1].mode)
  end)

  it("reports when there is no entity", function()
    local parsed, err = entity.parse(
      source("architecture rtl of x is begin end architecture rtl;")
    )
    assert.is_nil(parsed)
    assert.matches("no entity", err)
  end)

  it("reads an entity with no interface at all", function()
    -- Legal, and what every testbench looks like.
    local parsed = entity.parse(source("entity tb_x is end entity tb_x;"))
    assert.are.equal("tb_x", parsed.name)
    assert.are.same({}, parsed.ports)
    assert.are.same({}, parsed.generics)
  end)

  it("reads a generated testbench entity", function()
    local parsed = entity.parse(
      vim.fn.readfile("tests/golden/vhdl/testbench__default__defaults.vhd")
    )
    assert.are.equal("tb_dut", parsed.name)
    assert.are.same({}, parsed.ports)
  end)
end)

describe("entity.parse against the fixtures", function()
  it("reads every entity the templates generate", function()
    -- Four hundred odd entities across every configuration variant, including
    -- upper case and VHDL-93. Cheap, and it re-runs whenever a template
    -- changes, which is when the parser is most likely to be broken.
    local failures = {}
    for _, path in ipairs(vim.fn.glob("tests/golden/vhdl/*.vhd", false, true)) do
      local lines = vim.fn.readfile(path)
      if table.concat(lines, "\n"):lower():match("\nentity [%w_]+ is") then
        local parsed, err = entity.parse(lines)
        if not parsed then
          failures[#failures + 1] = ("%s: %s"):format(path, err)
        end
      end
    end
    assert.are.same({}, failures)
  end)

  it("gets the interface of the AXI4-Lite slave right", function()
    local parsed = entity.parse(
      vim.fn.readfile("tests/golden/vhdl/axi4lite_slave__default__defaults.vhd")
    )
    assert.are.equal("axi_regs", parsed.name)
    assert.are.equal(19, #parsed.ports)
    assert.are.equal(2, #parsed.generics)
  end)

  it("reads an upper case entity from the VHDL-93 variant", function()
    local parsed = entity.parse(
      vim.fn.readfile(
        "tests/golden/vhdl/bit_sync__upper_sync_high__defaults.vhd"
      )
    )
    assert.are.equal(4, #parsed.ports)
  end)
end)

describe("entity.from_file", function()
  it("reports a file it cannot read", function()
    local parsed, err = entity.from_file("/nonexistent/nowhere.vhd")
    assert.is_nil(parsed)
    assert.matches("cannot read", err)
  end)
end)
