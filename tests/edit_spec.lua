local edit = require("hdlsnip.edit")
local hdlsnip = require("hdlsnip")

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

local function text(bufnr)
  return table.concat(contents(bufnr), "\n")
end

describe("edit tracking", function()
  it("anchors a dynamic template inserted as one block", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)
    assert.is_not_nil(id)
    assert.are.equal("main", edit.params(bufnr, id).label)
  end)

  it("re-renders with a changed parameter", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)

    local ok, errors = edit.update(bufnr, id, { label = "wr_ptr" })
    assert.is_true(ok, table.concat(errors, "; "))
    assert.matches("p_wr_ptr : process", text(bufnr))
    assert.is_nil(text(bufnr):match("p_main"))
  end)

  it("keeps the block anchored across several changes", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)

    edit.update(bufnr, id, { label = "one" })
    edit.update(bufnr, id, { label = "two" })
    assert.matches("p_two : process", text(bufnr))
    assert.are.equal("two", edit.params(bufnr, id).label)
  end)

  it("leaves the buffer alone when a change is invalid", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)
    local before = contents(bufnr)

    local ok, errors = edit.update(bufnr, id, { label = "process" })
    assert.is_false(ok)
    assert.matches("not a legal VHDL", table.concat(errors, "\n"))
    assert.are.same(before, contents(bufnr))
  end)

  it("survives text inserted above the block", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- a comment", "" })
    assert.is_true((edit.update(bufnr, id, { label = "moved" })))
    assert.matches("^%-%- a comment", text(bufnr))
    assert.matches("p_moved : process", text(bufnr))
  end)

  it("forgets a block that was edited by hand", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)

    -- Replacing it would throw that edit away.
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "  -- hand written" })

    local ok, errors = edit.update(bufnr, id, { label = "other" })
    assert.is_false(ok)
    assert.matches("edited by hand", table.concat(errors, "\n"))
    assert.matches("hand written", text(bufnr))
    assert.is_nil(edit.at(bufnr, 1))
  end)

  it("does not anchor a mixed template", function()
    local bufnr = scratch({
      "architecture rtl of x is",
      "",
      "begin",
      "",
      "end architecture rtl;",
    }, 4)
    hdlsnip.insert("fsm", { name = "main", states = "idle, run" })
    assert.is_nil(edit.at(bufnr, 4))
  end)

  it("does not anchor a static template", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("package", { name = "my_pkg" })
    assert.is_nil(edit.at(bufnr, 1))
  end)

  it("forgets everything on write", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    assert.is_not_nil(edit.at(bufnr, 1))

    edit.detach_all(bufnr)
    assert.is_nil(edit.at(bufnr, 1))
  end)

  it("survives text inserted below the block", function()
    local bufnr = scratch({ "" })
    hdlsnip.insert("process", { label = "main" })
    local id = edit.at(bufnr, 1)

    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "-- trailing" })
    assert.is_true((edit.update(bufnr, id, { label = "moved" })))
    assert.matches("p_moved : process", text(bufnr))
    assert.matches("%-%- trailing", text(bufnr))
  end)
end)
