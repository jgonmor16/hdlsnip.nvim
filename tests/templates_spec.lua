local config = require("hdlsnip.config")
local registry = require("hdlsnip.registry")
local render = require("hdlsnip.render")

local function cfg(over)
  return config.resolve(config.merge(config.defaults, over))
end

--- Render a shipped template by name, failing the test with the collected
--- errors rather than with a nil comparison further down.
local function rendered(name, params, over)
  local tpl = registry.get(name)
  assert.is_not_nil(tpl, ("template %q is not registered"):format(name))
  local text, errs = render.values(tpl, params, cfg(over))
  assert.is_not_nil(text, table.concat(errs, "; "))
  return text
end

describe("shipped templates", function()
  it("all load without problems", function()
    -- The fixture templates live on a separate runtimepath entry that only
    -- registry_spec appends, so anything reported here is a real template.
    assert.are.same({}, registry.problems())
  end)

  it("are registered under their kind", function()
    for _, tpl in ipairs(registry.list()) do
      assert.is_string(tpl.desc)
      assert.matches("templates/vhdl/" .. tpl.kind .. "/", tpl.source)
    end
  end)
end)

describe("template: entity", function()
  it("emits a clock and an asynchronous reset port", function()
    local text = rendered("entity")
    assert.matches("entity top is", text)
    assert.matches("clk%s+: in std_logic;", text)
    assert.matches("rst_n : in std_logic\n  %);", text)
  end)

  it("omits the reset port when there is no reset", function()
    local text = rendered("entity", {}, { reset = { style = "none" } })
    assert.is_nil(text:match("rst"))
    assert.matches("clk : in std_logic\n  %);", text)
  end)

  it("gives the last port no trailing semicolon", function()
    local text = rendered("entity")
    assert.is_nil(text:match(";%s*\n%s*%);"))
  end)

  it("aligns the port columns against the configured names", function()
    local text = rendered("entity", {}, { clock = { name = "axi_aclk" } })
    assert.matches("axi_aclk : in std_logic;", text)
    assert.matches("rst_n%s+: in std_logic", text)
  end)

  it("names the architecture in both places", function()
    local text = rendered("entity", { name = "fifo", arch = "behavioural" })
    assert.matches("architecture behavioural of fifo is", text)
    assert.matches("end architecture behavioural;", text)
  end)

  it("adds a generic clause on request", function()
    assert.is_nil(rendered("entity"):match("generic"))
    local text = rendered("entity", { generics = true })
    assert.matches("generic %(", text)
    assert.matches("G_WIDTH : positive := 8", text)
  end)

  it("cases keywords but not identifiers or predefined types", function()
    local text = rendered(
      "entity",
      { name = "fifo" },
      { keyword_case = "upper" }
    )
    assert.matches("^LIBRARY ieee;", text)
    assert.matches("ENTITY fifo IS", text)
    assert.matches("std_logic", text)
    assert.is_nil(text:match("STD_LOGIC"))
  end)

  it("rejects a reserved word as the entity name", function()
    local tpl = registry.get("entity")
    local text, errs = render.values(tpl, { name = "process" }, cfg())
    assert.is_nil(text)
    assert.matches("not a legal VHDL", errs[1])
  end)
end)

describe("template: package", function()
  it("repeats the name in the declaration and the end clause", function()
    local text = rendered("package", { name = "axi_pkg" })
    assert.matches("package axi_pkg is", text)
    assert.matches("end package axi_pkg;", text)
  end)

  it("cases a static body too", function()
    local text = rendered(
      "package",
      { name = "axi_pkg" },
      { keyword_case = "upper" }
    )
    assert.matches("PACKAGE axi_pkg IS", text)
    assert.matches("USE ieee.std_logic_1164.ALL;", text)
    assert.matches("ieee%.std_logic_1164", text)
  end)

  it("renders as a snippet with the name mirrored", function()
    local body = render.placeholders(registry.get("package"), cfg())
    assert.matches("package %${1:my_pkg} is", body)
    assert.matches("end package %$1;", body)
    assert.matches("%$0", body)
  end)

  it("leaves no trailing whitespace once split into lines", function()
    local lines = render.lines(rendered("package", { name = "axi_pkg" }))
    for _, line in ipairs(lines) do
      assert.is_nil(line:match("%s$"), ("trailing space in %q"):format(line))
    end
  end)
end)
