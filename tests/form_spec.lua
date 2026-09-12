local form = require("hdlsnip.form")

describe("form.parse", function()
  local names = { label = true, width = true }

  it("reads a value after the name", function()
    local values = form.parse({ "label  main", "width  8" }, names)
    assert.are.same({ label = "main", width = "8" }, values)
  end)

  it("keeps spaces inside a value", function()
    local values = form.parse({ "label  idle, run, done" }, { label = true })
    assert.are.equal("idle, run, done", values.label)
  end)

  it("trims trailing whitespace", function()
    assert.are.equal("main", form.parse({ "label  main   " }, names).label)
  end)

  it("reports a name that is not a parameter", function()
    local values, unknown = form.parse({ "lable  main" }, names)
    assert.are.same({}, values)
    assert.are.same({ "lable" }, unknown)
  end)

  it("ignores a line with no value separator", function()
    assert.are.same({}, form.parse({ "label" }, names))
  end)
end)

describe("form.lines", function()
  local params = {
    { name = "label", type = "identifier", default = "main", desc = "d" },
    { name = "width", type = "integer", default = 8, desc = "d" },
  }

  it("aligns the names into a column", function()
    local lines, width = form.lines(params, { label = "main", width = 8 })
    assert.are.equal(5, width)
    assert.are.equal("label  main", lines[1])
    assert.are.equal("width  8", lines[2])
  end)

  it("round trips through parse", function()
    local lines = form.lines(params, { label = "wr_ptr", width = 32 })
    local values = form.parse(lines, { label = true, width = true })
    assert.are.same({ label = "wr_ptr", width = "32" }, values)
  end)
end)

describe("form.hint", function()
  it("lists the choices", function()
    assert.are.equal(
      "wrap | saturate",
      form.hint({ type = "choice", choices = { "wrap", "saturate" } })
    )
  end)

  it("gives the bounds of a number", function()
    assert.matches(
      "1%.%.4096",
      form.hint({ type = "integer", min = 1, max = 4096 })
    )
  end)

  it("falls back to the type", function()
    assert.are.equal("identifier", form.hint({ type = "identifier" }))
  end)
end)

describe("form.edit", function()
  it("reports when there is nothing under the cursor", function()
    local helpers = require("helpers")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "-- nothing here" })

    local notifications = helpers.captured_notify(function()
      assert.is_false(form.edit(0))
    end)
    assert.matches("no template under the cursor", notifications[1].msg)
  end)
end)
