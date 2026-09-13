local instantiate = require("hdlsnip.instantiate")
local entity = require("hdlsnip.vhdl.entity")
local config = require("hdlsnip.config")

local function cfg(over)
  return config.resolve(config.merge(config.defaults, over))
end

local FIFO = entity.parse(vim.split(
  table.concat({
    "entity fifo is",
    "  generic (G_WIDTH : positive := 8);",
    "  port (",
    "    clk       : in  std_logic;",
    "    wr_data_i : in  std_logic_vector(G_WIDTH - 1 downto 0);",
    "    full_o    : out std_logic",
    "  );",
    "end entity fifo;",
  }, "\n"),
  "\n",
  { plain = true }
))

describe("instantiate.sections", function()
  it("returns only statements without signals", function()
    local sections = instantiate.sections(FIFO, cfg())
    assert.is_nil(sections.declarations)
    assert.matches("fifo_inst : entity work%.fifo", sections.statements)
  end)

  it("returns declarations too when asked for signals", function()
    local sections = instantiate.sections(FIFO, cfg(), { signals = true })
    assert.matches("signal wr_data", sections.declarations)
    assert.matches("signal full", sections.declarations)
  end)

  it("maps the ports to the signals it declares", function()
    -- The two halves have to agree, or the instantiation names signals that
    -- were never declared.
    local sections = instantiate.sections(FIFO, cfg(), { signals = true })
    assert.matches("wr_data_i%s+=> wr_data", sections.statements)
    assert.matches("full_o%s+=> full", sections.statements)
  end)

  it("maps the ports to themselves without signals", function()
    local sections = instantiate.sections(FIFO, cfg())
    assert.matches("wr_data_i%s+=> wr_data_i", sections.statements)
  end)

  it("passes the label and library through", function()
    local sections =
      instantiate.sections(FIFO, cfg(), { label = "u_buf", library = "fifos" })
    assert.matches("u_buf : entity fifos%.fifo", sections.statements)
  end)
end)

describe("instantiate.entities", function()
  it("finds entities with ports and skips those without", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    -- A root marker, or the search walks up and finds the repository's own
    -- fixtures instead of the two files written here.
    vim.fn.writefile({}, dir .. "/.hdlsnip.lua")
    vim.fn.writefile({
      "entity worth_it is",
      "  port (clk : in std_logic);",
      "end entity worth_it;",
    }, dir .. "/design.vhd")
    vim.fn.writefile({
      "entity tb_nothing is",
      "end entity tb_nothing;",
    }, dir .. "/tb.vhd")

    local bufnr = vim.api.nvim_create_buf(false, true)
    -- vim.fs.root resolves against a real path, so the buffer's file has to
    -- exist or the search falls back to the working directory.
    vim.fn.writefile({}, dir .. "/scratch.vhd")
    vim.api.nvim_buf_set_name(bufnr, dir .. "/scratch.vhd")
    vim.api.nvim_win_set_buf(0, bufnr)

    local names = {}
    for _, choice in ipairs(instantiate.entities(bufnr)) do
      names[#names + 1] = choice.name
    end

    assert.is_true(vim.tbl_contains(names, "worth_it"))
    -- Legal, but there is nothing to instantiate.
    assert.is_false(vim.tbl_contains(names, "tb_nothing"))
  end)
end)

describe("hdlsnip instantiate", function()
  local original

  before_each(function()
    -- A picker in a headless run blocks and takes the whole file down, so
    -- choosing nothing is the safe default here.
    original = vim.ui.select
    vim.ui.select = function(_, _, on_choice)
      on_choice(nil)
    end
  end)

  after_each(function()
    vim.ui.select = original
  end)

  it("reports when the project has no entity", function()
    local helpers = require("helpers")
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({}, dir .. "/.hdlsnip.lua")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, dir .. "/empty.vhd")
    vim.api.nvim_win_set_buf(0, bufnr)

    local notifications = helpers.captured_notify(function()
      instantiate.instantiate()
    end)
    assert.matches("no entity with ports", notifications[1].msg)
  end)

  it("reports a name that is not in the project", function()
    local helpers = require("helpers")
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({}, dir .. "/.hdlsnip.lua")
    vim.fn.writefile({
      "entity real_one is",
      "  port (clk : in std_logic);",
      "end entity real_one;",
    }, dir .. "/design.vhd")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, dir .. "/scratch.vhd")
    vim.api.nvim_win_set_buf(0, bufnr)

    local notifications = helpers.captured_notify(function()
      instantiate.instantiate("no_such_entity")
    end)
    assert.matches("no entity named", notifications[1].msg)
  end)
end)
