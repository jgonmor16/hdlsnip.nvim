local placement = require("hdlsnip.placement")
local insert = require("hdlsnip.insert")
local config = require("hdlsnip.config")
local hdlsnip = require("hdlsnip")

local function scratch(lines, row)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_cursor(0, { row or 1, 0 })
  return bufnr
end

local function contents(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function row_of(bufnr, pattern)
  for index, line in ipairs(contents(bufnr)) do
    if line:match(pattern) then
      return index
    end
  end
  return nil
end

local ARCHITECTURE = {
  "library ieee;",
  "  use ieee.std_logic_1164.all;",
  "",
  "entity fifo is",
  "end entity fifo;",
  "",
  "architecture rtl of fifo is",
  "",
  "  signal a : std_logic;",
  "",
  "begin",
  "",
  "  a <= '1';",
  "",
  "end architecture rtl;",
}

describe("placement.architecture", function()
  it("finds the parts from inside the statement part", function()
    local bufnr = scratch(ARCHITECTURE, 13)
    local found = placement.architecture(bufnr, 13)
    assert.are.equal(7, found.architecture)
    assert.are.equal(11, found.begin_row)
    assert.are.equal(15, found.end_row)
  end)

  it("finds them from inside the declarative part too", function()
    local bufnr = scratch(ARCHITECTURE, 9)
    assert.are.equal(11, placement.architecture(bufnr, 9).begin_row)
  end)

  it("skips a begin belonging to a function in the declarations", function()
    local bufnr = scratch({
      "architecture rtl of x is",
      "  function f return integer is",
      "  begin",
      "    return 1;",
      "  end function f;",
      "begin",
      "  y <= '1';",
      "end architecture rtl;",
    }, 7)
    assert.are.equal(6, placement.architecture(bufnr, 7).begin_row)
  end)

  it("is not confused by an end process above the cursor", function()
    local bufnr = scratch({
      "architecture rtl of x is",
      "begin",
      "  p_a : process (clk) is",
      "  begin",
      "  end process p_a;",
      "",
      "end architecture rtl;",
    }, 6)
    assert.are.equal(2, placement.architecture(bufnr, 6).begin_row)
  end)

  it("reports nothing outside an architecture", function()
    local bufnr =
      scratch({ "library ieee;", "entity x is", "end entity x;" }, 2)
    assert.is_nil(placement.architecture(bufnr, 2))
  end)

  it("reports nothing past the end of one", function()
    local bufnr = scratch({
      "architecture a of x is",
      "begin",
      "end architecture a;",
      "",
      "entity y is",
    }, 5)
    assert.is_nil(placement.architecture(bufnr, 5))
  end)

  it("reports nothing in an empty buffer", function()
    assert.is_nil(placement.architecture(scratch({ "" }, 1), 1))
  end)
end)

describe("insert.insert_sections", function()
  local cfg = config.resolve(config.merge(config.defaults, {}))

  it("puts declarations above begin and statements below", function()
    local bufnr = scratch(ARCHITECTURE, 13)
    local placed = insert.insert_sections(bufnr, {
      declarations = "signal count_r : unsigned(7 downto 0);",
      statements = "p_count : process (clk) is\nbegin\nend process p_count;",
    }, cfg)

    assert.is_true(placed)
    local declaration = row_of(bufnr, "signal count_r")
    local statement = row_of(bufnr, "p_count : process")
    local begin_row = row_of(bufnr, "^begin$")
    assert.is_true(declaration < begin_row)
    assert.is_true(statement > begin_row)
  end)

  it("indents both halves", function()
    local bufnr = scratch(ARCHITECTURE, 13)
    insert.insert_sections(bufnr, {
      declarations = "signal count_r : unsigned(7 downto 0);",
      statements = "count_r <= (others => '0');",
    }, cfg)
    for _, line in ipairs(contents(bufnr)) do
      if line:match("count_r") then
        assert.matches("^  ", line)
      end
    end
  end)

  it("falls back to the cursor with no architecture around it", function()
    local bufnr = scratch({ "" }, 1)
    local placed = insert.insert_sections(bufnr, {
      declarations = "signal a : std_logic;",
      statements = "a <= '1';",
    }, cfg)

    assert.is_false(placed)
    local text = table.concat(contents(bufnr), "\n")
    assert.matches("signal a : std_logic;", text)
    assert.matches("a <= '1';", text)
  end)

  it("inserts at the cursor when there are no declarations", function()
    local bufnr = scratch(ARCHITECTURE, 13)
    local placed = insert.insert_sections(bufnr, {
      statements = "b <= '0';",
    }, cfg)
    assert.is_false(placed)
    assert.matches("b <= '0';", table.concat(contents(bufnr), "\n"))
  end)
end)

describe("hdlsnip.insert with a mixed template", function()
  it("places an FSM's state type above begin", function()
    local bufnr = scratch(ARCHITECTURE, 13)
    hdlsnip.insert("fsm", { name = "main", states = "idle, run" })

    local type_row = row_of(bufnr, "type t_main_state")
    local process_row = row_of(bufnr, "p_main_state : process")
    local begin_row = row_of(bufnr, "^begin$")

    assert.is_not_nil(type_row)
    assert.is_not_nil(process_row)
    assert.is_true(type_row < begin_row)
    assert.is_true(process_row > begin_row)
  end)
end)
