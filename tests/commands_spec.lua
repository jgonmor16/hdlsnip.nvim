local hdlsnip = require("hdlsnip")
local insert = require("hdlsnip.insert")

--- A scratch buffer, made current, with `lines` in it and the cursor on
--- `row`.
local function scratch(lines, row)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "" })
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_win_set_cursor(0, { row or 1, 0 })
  return bufnr
end

local function contents(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe("insert.insert_lines", function()
  it("replaces a blank current line rather than pushing it down", function()
    local bufnr = scratch({ "" })
    insert.insert_lines(bufnr, { "entity top is", "end entity top;" })
    assert.are.same({ "entity top is", "end entity top;" }, contents(bufnr))
  end)

  it("inserts below a line that has content", function()
    local bufnr = scratch({ "architecture rtl of top is" })
    insert.insert_lines(bufnr, { "begin" })
    assert.are.same({ "architecture rtl of top is", "begin" }, contents(bufnr))
  end)

  it("indents to match the cursor line", function()
    local bufnr = scratch({ "    " })
    insert.insert_lines(bufnr, { "signal a : std_logic;", "", "b <= a;" })
    assert.are.same(
      { "    signal a : std_logic;", "", "    b <= a;" },
      contents(bufnr)
    )
  end)

  it("leaves blank template lines empty, not full of spaces", function()
    local bufnr = scratch({ "  " })
    insert.insert_lines(bufnr, { "a", "", "b" })
    for _, line in ipairs(contents(bufnr)) do
      assert.is_nil(line:match("^%s+$"))
    end
  end)

  it("puts the cursor on the first inserted line", function()
    local bufnr = scratch({ "one", "two" }, 2)
    local row = insert.insert_lines(bufnr, { "three" })
    assert.are.equal(3, row)
    assert.are.equal(3, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("is a single undo step", function()
    local bufnr = scratch({ "" })
    insert.insert_lines(bufnr, { "a", "b", "c" })
    vim.cmd("silent undo")
    assert.are.same({ "" }, contents(bufnr))
  end)
end)

describe("hdlsnip.insert", function()
  it("inserts a template with parameters supplied", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("package", { name = "axi_pkg" })
    local text = table.concat(contents(bufnr), "\n")
    assert.matches("package axi_pkg is", text)
    assert.matches("end package axi_pkg;", text)
  end)

  it("renders a dynamic template too", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("entity", { name = "fifo", arch = "rtl", generics = false })
    local text = table.concat(contents(bufnr), "\n")
    assert.matches("entity fifo is", text)
    assert.matches("architecture rtl of fifo is", text)
  end)

  it("reports an unknown template without touching the buffer", function()
    local helpers = require("helpers")
    local bufnr = scratch({ "" })
    local notifications = helpers.captured_notify(function()
      hdlsnip.insert("no_such_template", {})
    end)
    assert.matches("no template named", notifications[1].msg)
    assert.are.same({ "" }, contents(bufnr))
  end)

  it("reports an invalid parameter without touching the buffer", function()
    local helpers = require("helpers")
    local bufnr = scratch({ "" })
    local notifications = helpers.captured_notify(function()
      hdlsnip.insert("package", { name = "entity" })
    end)
    assert.matches("not a legal VHDL", notifications[1].msg)
    assert.are.same({ "" }, contents(bufnr))
  end)
end)

describe("hdlsnip.expand", function()
  it("expands a static template as a snippet", function()
    scratch({ "" })
    hdlsnip.expand("package")
    assert.is_true(vim.snippet.active())
    vim.snippet.stop()
  end)

  it("falls back to inserting a dynamic template", function()
    local bufnr = scratch({ "" })
    -- No prompting happens because entity's parameters all have defaults and
    -- vim.ui.input is stubbed to accept them.
    local original = vim.ui.input
    vim.ui.input = function(opts, on_confirm)
      on_confirm(opts.default)
    end
    local original_select = vim.ui.select
    vim.ui.select = function(items, _, on_choice)
      on_choice(items[1])
    end

    hdlsnip.expand("entity")

    vim.ui.input = original
    vim.ui.select = original_select

    assert.is_false(vim.snippet.active())
    assert.matches("entity top is", table.concat(contents(bufnr), "\n"))
  end)
end)
