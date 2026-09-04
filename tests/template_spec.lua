local config = require("hdlsnip.config")
local template = require("hdlsnip.template")

local cfg = config.resolve(config.merge(config.defaults, {}))

--- A fresh, valid template on every call. Tests mutate their own copy, so no
--- deep merge is involved and one test cannot leak state into another.
local function base()
  return {
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
        max = 4096,
        desc = "width",
      },
    },
    body = "signal {{sig}}_r : unsigned({{width}} - 1 downto 0);",
  }
end

--- Validate a template built by `mutate` and return its errors as one string.
local function errors_for(mutate)
  local tpl = base()
  if mutate then
    mutate(tpl)
  end
  local _, errs = template.validate(tpl)
  return table.concat(errs, "\n")
end

describe("template.validate", function()
  it("accepts a well formed template", function()
    local ok, errs = template.validate(base())
    assert.is_true(ok, table.concat(errs, "; "))
  end)

  it("requires a lower_snake_case name", function()
    assert.matches(
      "lower_snake_case",
      errors_for(function(t)
        t.name = "AXI4Lite"
      end)
    )
  end)

  it("rejects an unknown kind", function()
    assert.matches(
      "unknown kind",
      errors_for(function(t)
        t.kind = "nonsense"
      end)
    )
  end)

  it("requires exactly one of body or render", function()
    assert.matches(
      "exactly one",
      errors_for(function(t)
        t.render = function() end
      end)
    )
    assert.matches(
      "exactly one",
      errors_for(function(t)
        t.body = nil
      end)
    )
  end)

  it("requires dynamic alongside a render function", function()
    assert.matches(
      "requires dynamic",
      errors_for(function(t)
        t.body = nil
        t.render = function()
          return ""
        end
      end)
    )
  end)

  it("rejects a dynamic template with a string body", function()
    assert.matches(
      "cannot be dynamic",
      errors_for(function(t)
        t.dynamic = true
      end)
    )
  end)

  it("rejects a marker with no parameter", function()
    assert.matches(
      "not a param",
      errors_for(function(t)
        t.body = "{{sig}} {{width}} {{oops}}"
      end)
    )
  end)

  it("rejects a parameter never used in the body", function()
    assert.matches(
      "never used",
      errors_for(function(t)
        t.body = "{{sig}}"
      end)
    )
  end)

  it("allows the cursor marker without declaring it", function()
    local tpl = base()
    tpl.body = tpl.body .. "{{cursor}}"
    assert.is_true((template.validate(tpl)))
  end)

  it("rejects a choice default outside its choices", function()
    assert.matches(
      "not one of the choices",
      errors_for(function(t)
        t.params[2] = {
          name = "kind",
          type = "choice",
          choices = { "unsigned", "signed" },
          default = "std_logic_vector",
          desc = "type",
        }
        t.body = "{{sig}} {{kind}}"
      end)
    )
  end)

  it("rejects duplicate parameter names", function()
    assert.matches(
      "duplicate param",
      errors_for(function(t)
        t.params[2] =
          { name = "sig", type = "string", default = "x", desc = "dup" }
      end)
    )
  end)

  it("requires a description on every parameter", function()
    assert.matches(
      "needs a desc",
      errors_for(function(t)
        t.params[2].desc = nil
      end)
    )
  end)

  it("requires a default on every parameter", function()
    assert.matches(
      "needs a default",
      errors_for(function(t)
        t.params[2].default = nil
      end)
    )
  end)
end)

describe("template.resolve_params", function()
  it("fills defaults", function()
    local values = template.resolve_params(base(), {}, cfg)
    assert.are.same({ sig = "data", width = 8 }, values)
  end)

  it("coerces strings from the prompt", function()
    local values = template.resolve_params(base(), { width = "32" }, cfg)
    assert.are.equal(32, values.width)
  end)

  it("enforces bounds", function()
    local _, errs = template.resolve_params(base(), { width = 0 }, cfg)
    assert.matches("must be >= 1", errs[1])
  end)

  it("rejects a non-integer for an integer parameter", function()
    local _, errs = template.resolve_params(base(), { width = 2.5 }, cfg)
    assert.matches("expected an integer", errs[1])
  end)

  it("rejects a reserved word for an identifier parameter", function()
    local _, errs = template.resolve_params(base(), { sig = "signal" }, cfg)
    assert.matches("not a legal VHDL", errs[1])
  end)

  it("reports unknown parameters", function()
    local _, errs = template.resolve_params(base(), { widht = 8 }, cfg)
    assert.matches("unknown parameter", errs[1])
  end)
end)

describe("template.coerce", function()
  local param = { name = "b", type = "boolean", default = false, desc = "b" }

  it("accepts several spellings of boolean", function()
    assert.is_true(template.coerce(param, "yes", cfg))
    assert.is_true(template.coerce(param, "1", cfg))
    assert.is_true(template.coerce(param, true, cfg))
    assert.is_false(template.coerce(param, "no", cfg))
    assert.is_false(template.coerce(param, false, cfg))
  end)

  it("rejects anything else", function()
    local value, err = template.coerce(param, "maybe", cfg)
    assert.is_nil(value)
    assert.matches("expected a boolean", err)
  end)
end)
