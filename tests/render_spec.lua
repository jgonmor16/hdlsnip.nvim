local config = require("hdlsnip.config")
local render = require("hdlsnip.render")

local cfg = config.resolve(config.merge(config.defaults, {}))

local static = {
  name = "reg",
  desc = "Registered signal",
  kind = "rtl",
  params = {
    { name = "sig", type = "identifier", default = "data", desc = "signal" },
    {
      name = "width",
      type = "integer",
      default = 8,
      min = 1,
      desc = "width",
    },
    {
      name = "kind",
      type = "choice",
      choices = { "std_logic_vector", "unsigned" },
      default = "unsigned",
      desc = "type",
    },
  },
  body = "signal {{sig}}_r : {{kind}}({{width}} - 1 downto 0);\n"
    .. "{{sig}}_o <= {{sig}}_r;{{cursor}}",
}

local dynamic = {
  name = "cdc",
  desc = "Synchroniser",
  kind = "cdc",
  dynamic = true,
  params = {
    { name = "stages", type = "integer", default = 2, min = 2, desc = "n" },
  },
  render = function(params)
    local out = {}
    for i = 1, params.stages do
      out[i] = ("stage %d"):format(i)
    end
    return table.concat(out, "\n")
  end,
}

describe("render.values", function()
  it("substitutes defaults", function()
    local text = render.values(static, {}, cfg)
    assert.matches("signal data_r : unsigned%(8 %- 1 downto 0%);", text)
  end)

  it("substitutes overrides and drops the cursor marker", function()
    local text = render.values(static, { width = 16, sig = "addr" }, cfg)
    assert.are.equal(
      "signal addr_r : unsigned(16 - 1 downto 0);\naddr_o <= addr_r;",
      text
    )
  end)

  it("formats integers without a decimal point", function()
    local text = render.values(static, { width = 32 }, cfg)
    assert.matches("unsigned%(32 %-", text)
    assert.is_nil(text:match("32%.0"))
  end)

  it("returns errors instead of text when a parameter is invalid", function()
    local text, errs = render.values(static, { width = 0 }, cfg)
    assert.is_nil(text)
    assert.matches("must be >= 1", errs[1])
  end)

  it("runs a dynamic template's render function", function()
    assert.are.equal(
      "stage 1\nstage 2\nstage 3",
      render.values(dynamic, { stages = 3 }, cfg)
    )
  end)
end)

describe("render.placeholders", function()
  it("numbers tabstops by first appearance, not declaration order", function()
    local body = render.placeholders(static)
    assert.are.equal(
      "signal ${1:data}_r : ${2|std_logic_vector,unsigned|}(${3:8} - 1 downto 0);\n"
        .. "$1_o <= $1_r;$0",
      body
    )
  end)

  it("mirrors repeated parameters", function()
    local body = render.placeholders(static)
    assert.are.equal(2, select(2, body:gsub("%$1", "")))
  end)

  it("appends a final tabstop when the body has no cursor marker", function()
    local tpl = vim.deepcopy(static)
    tpl.body = "signal {{sig}}_r : {{kind}}({{width}} - 1 downto 0);"
    assert.matches("%$0$", (render.placeholders(tpl)))
  end)

  it("refuses dynamic templates", function()
    local body, errs = render.placeholders(dynamic)
    assert.is_nil(body)
    assert.matches("values mode only", errs[1])
  end)

  it("escapes dollars in literal text and in defaults", function()
    local tpl = {
      name = "esc",
      desc = "escaping",
      kind = "rtl",
      params = { { name = "a", type = "string", default = "x$y", desc = "a" } },
      body = "cost $5 -- {{a}}",
    }
    assert.are.equal("cost \\$5 -- ${1:x\\$y}$0", (render.placeholders(tpl)))
  end)
end)

describe("render.lines", function()
  it("strips trailing whitespace and surrounding blank lines", function()
    assert.are.same({ "  a", "", "b" }, render.lines("\n  a  \n\nb\t\n\n"))
  end)
end)
