local form = require("hdlsnip.form")

describe("form.parse", function()
  local params = {
    { name = "label", type = "identifier" },
    { name = "width", type = "integer" },
  }

  it("takes one value per line, in parameter order", function()
    local values = form.parse({ "main", "8" }, params)
    assert.are.same({ label = "main", width = "8" }, values)
  end)

  it("keeps spaces inside a value", function()
    local values = form.parse({ "idle, run, done" }, { params[1] })
    assert.are.equal("idle, run, done", values.label)
  end)

  it("trims surrounding whitespace", function()
    assert.are.equal("main", form.parse({ "  main   " }, params).label)
  end)

  -- Guarded against in `collect`, which refuses a buffer whose line count no
  -- longer matches the parameters. Pinned here so the function itself stays
  -- total rather than returning a shifted table.
  it("gives a missing line an empty value", function()
    local values = form.parse({ "main" }, params)
    assert.are.same({ label = "main", width = "" }, values)
  end)
end)

describe("form.lines", function()
  local params = {
    { name = "label", type = "identifier", default = "main", desc = "d" },
    { name = "width", type = "integer", default = 8, desc = "d" },
  }

  it("holds the values and nothing else", function()
    local lines = form.lines(params, { label = "main", width = 8 })
    assert.are.same({ "main", "8" }, lines)
  end)

  it("round trips through parse", function()
    local lines = form.lines(params, { label = "wr_ptr", width = 32 })
    assert.are.same(
      { label = "wr_ptr", width = "32" },
      form.parse(lines, params)
    )
  end)
end)

describe("form.geometry", function()
  it("leaves room for the virtual text the buffer line does not hold", function()
    -- The axi4lite_slave case, which wrapped at the old fixed 34.
    local params = {
      { name = "name", type = "identifier" },
      { name = "registers", type = "integer", min = 1, max = 256 },
      { name = "prefix", type = "string" },
    }
    local lines = form.lines(params, {
      name = "axi_regs",
      registers = 4,
      prefix = "s_axi",
    })
    local geometry = form.geometry(params, lines, "axi4lite_slave")

    local longest = 0
    for _, line in ipairs(lines) do
      longest = math.max(longest, #line)
    end

    assert.is_true(geometry.prefix > 0)
    assert.is_true(geometry.width >= geometry.prefix + longest)
  end)

  it("never goes below the minimum", function()
    local params = { { name = "n", type = "integer" } }
    assert.are.equal(34, form.geometry(params, form.lines(params, { n = 1 }), "x").width)
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

describe("form field keys", function()
  it("accepts a single mapping or a list", function()
    local config = require("hdlsnip.config")
    local function errors_for(keys)
      local cfg = config.resolve(config.merge(config.defaults, { keys = keys }))
      local _, errs = config.validate(cfg)
      return table.concat(errs, "\n")
    end

    assert.are.equal("", errors_for({ field_next = "<Tab>" }))
    assert.are.equal("", errors_for({ field_next = { "<Tab>", "<C-k>" } }))
    assert.are.equal("", errors_for({ field_next = false }))
    assert.matches("field_next", errors_for({ field_next = {} }))
    assert.matches("field_next", errors_for({ field_next = { "<Tab>", 42 } }))
  end)
end)
