local config = require("hdlsnip.config")
local entity = require("hdlsnip.vhdl.entity")
local testbench = require("hdlsnip.vhdl.testbench")

local function cfg(over)
  return config.resolve(config.merge(config.defaults, over))
end

local function source(text)
  return vim.split(text, "\n", { plain = true })
end

local FIFO = entity.parse(source([[
entity fifo is
  generic (G_WIDTH : positive := 8);
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    wr_en_i   : in  std_logic;
    wr_data_i : in  std_logic_vector(G_WIDTH - 1 downto 0);
    full_o    : out std_logic
  );
end entity fifo;
]]))

describe("testbench.build", function()
  it("wraps the entity in a testbench of its own", function()
    local text = testbench.build(FIFO, cfg())
    assert.matches("entity tb_fifo is", text)
    assert.matches("end entity tb_fifo;", text)
    assert.matches("dut : entity work%.fifo", text)
  end)

  it("declares a signal for every port", function()
    local text = testbench.build(FIFO, cfg())
    assert.matches("signal clk%s+: std_logic", text)
    assert.matches(
      "signal wr_data%s+: std_logic_vector%(8 %- 1 downto 0%)",
      text
    )
    assert.matches("signal full%s+: std_logic;", text)
  end)

  it("drives every input from time zero", function()
    -- Without a value the design starts with 'U' on its inputs and nothing
    -- downstream means anything.
    local text = testbench.build(FIFO, cfg())
    assert.matches("signal wr_en%s+: std_logic := '0';", text)
    assert.matches(
      "wr_data%s+: std_logic_vector%b() := %(others => '0'%);",
      text
    )
    -- An output is driven by the design, so it takes no initial value.
    assert.matches("signal full%s+: std_logic;\n", text)
  end)

  it("generates the clock and releases the reset", function()
    local text = testbench.build(FIFO, cfg())
    assert.matches(
      "clk <= not clk after C_CLK_PERIOD / 2 when running else '0';",
      text
    )
    assert.matches("rst_n <= '1' after 4 %* C_CLK_PERIOD;", text)
  end)

  it("waits for the reset and an edge before stimulating", function()
    local text = testbench.build(FIFO, cfg())
    assert.matches("wait until rst_n = '1';", text)
    assert.matches("wait until rising_edge%(clk%);", text)
  end)

  it("stops the run", function()
    local text = testbench.build(FIFO, cfg())
    assert.matches("running <= false;", text)
    assert.matches("finish;", text)
  end)

  it("takes a clock period", function()
    assert.matches(
      "C_CLK_PERIOD : time := 20 ns;",
      testbench.build(FIFO, cfg(), { period_ns = 20 })
    )
  end)
end)

describe("testbench.build clock and reset detection", function()
  local CDC = entity.parse(source([[
entity crossing is
  port (
    src_clk   : in  std_logic;
    src_rst_n : in  std_logic;
    dst_clk   : in  std_logic;
    dst_reset : in  std_logic;
    data_i    : in  std_logic;
    data_o    : out std_logic
  );
end entity crossing;
]]))

  it("finds clocks that are not called clk", function()
    -- By shape, not by the configured name: a crossing has two clocks and
    -- neither is called clk.
    local text = testbench.build(CDC, cfg())
    assert.matches("src_clk <= not src_clk after", text)
    assert.matches("dst_clk <= not dst_clk after", text)
  end)

  it("takes the reset polarity from the name", function()
    local text = testbench.build(CDC, cfg())
    assert.matches("src_rst_n%s+: std_logic := '0';", text)
    assert.matches("dst_reset%s+: std_logic := '1';", text)
    assert.matches("src_rst_n <= '1' after", text)
    assert.matches("dst_reset <= '0' after", text)
  end)

  it("says what it cannot fix about two clocks", function()
    assert.matches("unrelated rates", testbench.build(CDC, cfg()))
  end)
end)

describe("testbench.build under VHDL-93", function()
  it("stops by parking rather than with std.env", function()
    -- std.env arrived in VHDL-2008, and a failing assertion exits non-zero,
    -- which makes a passing testbench look like a failure.
    local text = testbench.build(FIFO, cfg({ vhdl_std = "93" }))
    assert.is_nil(text:match("std%.env"))
    assert.is_nil(text:match("severity failure"))
    assert.matches("running <= false;\n%s+wait;", text)
  end)
end)

describe("generated testbenches run", function()
  it("elaborates and completes for every shipped entity", function()
    if vim.fn.executable("ghdl") == 0 then
      pending("ghdl is not installed")
      return
    end

    local fixtures =
      vim.fn.glob("tests/golden/vhdl/*__default__defaults.vhd", false, true)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local checked, failures = 0, {}

    for _, path in ipairs(fixtures) do
      local parsed = entity.parse(vim.fn.readfile(path))
      if parsed and #parsed.ports > 0 then
        local tb = ("%s/tb_%s.vhd"):format(dir, parsed.name)
        vim.fn.writefile(
          vim.split(testbench.build(parsed, cfg()), "\n", { plain = true }),
          tb
        )

        local work = ("%s/work_%s"):format(dir, parsed.name)
        vim.fn.mkdir(work, "p")
        vim.fn.system({
          "ghdl",
          "-a",
          "--std=08",
          "--workdir=" .. work,
          path,
          tb,
        })
        if vim.v.shell_error ~= 0 then
          failures[#failures + 1] = parsed.name .. ": analyse"
        else
          vim.fn.system({
            "ghdl",
            "-e",
            "--std=08",
            "--workdir=" .. work,
            "-o",
            work .. "/run",
            "tb_" .. parsed.name,
          })
          if vim.v.shell_error ~= 0 then
            failures[#failures + 1] = parsed.name .. ": elaborate"
          end
        end
        checked = checked + 1
      end
    end

    assert.is_true(checked > 0, "no entities were checked")
    assert.are.same({}, failures)
  end)
end)
