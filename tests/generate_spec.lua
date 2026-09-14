local config = require("hdlsnip.config")
local entity = require("hdlsnip.vhdl.entity")
local generate = require("hdlsnip.vhdl.generate")

local function cfg(over)
  return config.resolve(config.merge(config.defaults, over))
end

local function source(text)
  return vim.split(text, "\n", { plain = true })
end

local FIFO = entity.parse(source([[
entity fifo is
  generic (
    G_WIDTH : positive := 8;
    G_DEPTH : positive
  );
  port (
    clk       : in  std_logic;
    wr_en_i   : in  std_logic;
    wr_data_i : in  std_logic_vector(G_WIDTH - 1 downto 0);
    full_o    : out std_logic
  );
end entity fifo;
]]))

describe("generate.instantiate", function()
  it("instantiates directly, needing no component", function()
    local text = generate.instantiate(FIFO, cfg())
    assert.matches("fifo_inst : entity work%.fifo", text)
  end)

  it("uses named association for every port", function()
    local text = generate.instantiate(FIFO, cfg())
    assert.matches("clk%s+=> clk,", text)
    assert.matches("wr_data_i%s+=> wr_data_i", text)
  end)

  it("gives the last association no comma", function()
    local text = generate.instantiate(FIFO, cfg())
    assert.matches("full_o%s+=> full_o\n  %);", text)
  end)

  it("takes a label and a library", function()
    local text = generate.instantiate(FIFO, cfg(), {
      label = "u_buffer",
      library = "fifos",
    })
    assert.matches("u_buffer : entity fifos%.fifo", text)
  end)

  it("emits the component form on request", function()
    local text = generate.instantiate(FIFO, cfg(), { component = true })
    assert.matches("^fifo_inst : fifo\n", text)
    assert.is_nil(text:match("entity work"))
  end)

  it("maps a generic to its default", function()
    assert.matches("G_WIDTH%s+=> 8", generate.instantiate(FIFO, cfg()))
  end)

  it("leaves a generic with no default named after itself", function()
    -- Deliberately will not analyse: it is a value the caller must supply,
    -- and the name says so where a wrong guess would not.
    assert.matches("G_DEPTH%s+=> G_DEPTH", generate.instantiate(FIFO, cfg()))
  end)

  it("takes given values over defaults", function()
    local text = generate.instantiate(FIFO, cfg(), {
      values = { G_WIDTH = "32", G_DEPTH = "64", clk = "axi_aclk" },
    })
    assert.matches("G_WIDTH%s+=> 32", text)
    assert.matches("G_DEPTH%s+=> 64", text)
    assert.matches("clk%s+=> axi_aclk", text)
  end)
end)

describe("generate.signals", function()
  it("declares one signal per port", function()
    local text = generate.signals(FIFO, cfg())
    assert.are.equal(4, select(2, text:gsub("signal", "")))
  end)

  it("drops the configured direction suffixes", function()
    local text = generate.signals(FIFO, cfg())
    assert.matches("signal wr_en%s+:", text)
    assert.matches("signal full%s+:", text)
    assert.is_nil(text:match("wr_en_i%s+:"))
  end)

  it("substitutes generic values into a subtype", function()
    -- The instantiating scope has no G_WIDTH, so copying the subtype as it
    -- stands would not analyse.
    assert.matches(
      "std_logic_vector%(8 %- 1 downto 0%)",
      generate.signals(FIFO, cfg())
    )
  end)

  it("uses given generic values", function()
    local text = generate.signals(FIFO, cfg(), { G_WIDTH = "32" })
    assert.matches("std_logic_vector%(32 %- 1 downto 0%)", text)
  end)

  it("matches the names the instantiation maps to", function()
    local values = generate.signal_values(FIFO, cfg())
    assert.are.equal("wr_en", values.wr_en_i)
    assert.are.equal("full", values.full_o)
    assert.are.equal("clk", values.clk)
  end)

  it("keeps the port name when stripping would collide", function()
    -- wb_dat_i and wb_dat_o both strip to wb_dat, which is one signal
    -- declared twice.
    local pair = entity.parse(source([[
entity bus_if is
  port (
    wb_dat_i : in  std_logic_vector(31 downto 0);
    wb_dat_o : out std_logic_vector(31 downto 0)
  );
end entity bus_if;
]]))
    local values = generate.signal_values(pair, cfg())
    assert.are.equal("wb_dat_i", values.wb_dat_i)
    assert.are.equal("wb_dat_o", values.wb_dat_o)
  end)
end)

describe("generate.component", function()
  it("declares the interface with modes aligned", function()
    local text = generate.component(FIFO, cfg())
    assert.matches("component fifo is", text)
    assert.matches("clk%s+: in%s+std_logic;", text)
    assert.matches("full_o%s+: out std_logic\n", text)
    assert.matches("end component fifo;", text)
  end)

  it("gives a generic no mode column", function()
    -- Generics have no mode, and padding an empty cell leaves a gap.
    assert.matches("G_WIDTH : positive := 8;", generate.component(FIFO, cfg()))
  end)
end)

describe("generated instantiations analyse", function()
  it("wires every shipped entity up so GHDL accepts it", function()
    if vim.fn.executable("ghdl") == 0 then
      pending("ghdl is not installed")
      return
    end

    -- The check that found the only real bug here: generated code referenced
    -- the entity's own generics, which do not exist where it is instantiated.
    local fixtures =
      vim.fn.glob("tests/golden/vhdl/*__default__defaults.vhd", false, true)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local checked, failures = 0, {}

    for _, path in ipairs(fixtures) do
      local parsed = entity.parse(vim.fn.readfile(path))
      if parsed and #parsed.ports > 0 then
        local values = generate.signal_values(parsed, cfg())
        local harness = {
          "library ieee;",
          "  use ieee.std_logic_1164.all;",
          "  use ieee.numeric_std.all;",
          "",
          ("entity %s_harness is"):format(parsed.name),
          ("end entity %s_harness;"):format(parsed.name),
          "",
          ("architecture tb of %s_harness is"):format(parsed.name),
          "",
        }
        for _, line in ipairs(vim.split(generate.signals(parsed, cfg()), "\n")) do
          harness[#harness + 1] = "  " .. line
        end
        vim.list_extend(harness, { "", "begin", "" })
        local instance =
          generate.instantiate(parsed, cfg(), { values = values })
        for _, line in ipairs(vim.split(instance, "\n")) do
          harness[#harness + 1] = "  " .. line
        end
        vim.list_extend(harness, { "", "end architecture tb;" })

        local harness_path = ("%s/%s_harness.vhd"):format(dir, parsed.name)
        vim.fn.writefile(harness, harness_path)

        local work = ("%s/work_%s"):format(dir, parsed.name)
        vim.fn.mkdir(work, "p")
        local output = vim.fn.system({
          "ghdl",
          "-a",
          "--std=08",
          "--workdir=" .. work,
          path,
          harness_path,
        })
        if vim.v.shell_error ~= 0 then
          failures[#failures + 1] = ("%s: %s"):format(parsed.name, output)
        end
        checked = checked + 1
      end
    end

    assert.is_true(checked > 0, "no entities were checked")
    assert.are.same({}, failures)
  end)
end)
