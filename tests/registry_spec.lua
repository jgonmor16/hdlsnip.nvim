local helpers = require("helpers")
local registry = require("hdlsnip.registry")

--- Put the fixture templates on the runtimepath, then rescan. Reloading
--- notifies about the deliberately broken fixtures, so it is captured.
local function reload()
  local fixtures = helpers.fixture_rtp()
  if not vim.o.runtimepath:find(fixtures, 1, true) then
    vim.opt.runtimepath:append(fixtures)
  end
  return helpers.captured_notify(function()
    registry.reload()
  end)
end

describe("registry discovery", function()
  before_each(reload)

  it("finds a valid template and records where it came from", function()
    local tpl = registry.get("fixture_reg")
    assert.is_not_nil(tpl)
    assert.are.equal("rtl", tpl.kind)
    assert.are.equal("vhdl", tpl.lang)
    assert.matches("fixture_reg%.lua$", tpl.source)
  end)

  it("finds templates of every kind", function()
    assert.is_not_nil(registry.get("fixture_sync"))
    assert.are.equal("cdc", registry.get("fixture_sync").kind)
  end)

  it("skips a template that fails validation", function()
    assert.is_nil(registry.get("fixture_bad"))
  end)

  it("skips a template whose kind contradicts its directory", function()
    assert.is_nil(registry.get("fixture_misplaced"))
  end)

  it("skips an unsupported language directory", function()
    assert.is_nil(registry.get("fixture_sv"))
    assert.is_nil(registry.get("fixture_sv", "sv"))
  end)

  it("keeps loading after a broken template", function()
    -- fixture_bad sits in the same directory as fixture_reg, so this fails
    -- if one bad file aborts the scan.
    assert.is_not_nil(registry.get("fixture_reg"))
  end)
end)

describe("registry problem reporting", function()
  it("warns once, listing every problem", function()
    local notifications = reload()
    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.WARN, notifications[1].level)
    assert.matches("fixture_bad", notifications[1].msg)
    assert.matches("fixture_misplaced", notifications[1].msg)
  end)

  it("explains each problem", function()
    reload()
    local problems = table.concat(registry.problems(), "\n")
    assert.matches("fixture_bad.*not a param", problems)
    assert.matches("fixture_misplaced.*kind is", problems)
    assert.matches("fixture_sv.*unknown language", problems)
  end)
end)

describe("registry listing", function()
  before_each(reload)

  it("sorts by kind then name", function()
    local list = registry.list()
    local order = {}
    for i, tpl in ipairs(list) do
      order[i] = tpl.kind .. "/" .. tpl.name
    end
    assert.are.equal("cdc/fixture_sync", order[1])
    assert.is_true(vim.tbl_contains(order, "rtl/fixture_reg"))
  end)

  it("filters by kind", function()
    local list = registry.list({ kind = "cdc" })
    for _, tpl in ipairs(list) do
      assert.are.equal("cdc", tpl.kind)
    end
    assert.is_true(#list >= 1)
  end)

  it("returns names for completion", function()
    assert.is_true(vim.tbl_contains(registry.names(), "fixture_reg"))
    assert.is_false(vim.tbl_contains(registry.names(), "fixture_bad"))
  end)
end)

describe("registry.register", function()
  before_each(reload)

  it("accepts a template built in Lua", function()
    local ok, errs = registry.register({
      name = "built_in_config",
      kind = "rtl",
      desc = "Registered from a user config",
      params = {
        { name = "sig", type = "identifier", default = "x", desc = "signal" },
      },
      body = "signal {{sig}} : std_logic;",
    })
    assert.is_true(ok, table.concat(errs, "; "))
    assert.is_not_nil(registry.get("built_in_config"))
  end)

  it("rejects an invalid template and does not index it", function()
    local ok, errs = registry.register({
      name = "rejected",
      kind = "nonsense",
      desc = "Bad kind",
      body = "constant c : integer := 0;",
    })
    assert.is_false(ok)
    assert.matches("unknown kind", table.concat(errs, "\n"))
    assert.is_nil(registry.get("rejected"))
  end)

  it("rejects an unknown language", function()
    local ok, errs = registry.register({
      name = "wrong_lang",
      lang = "verilog",
      kind = "rtl",
      desc = "Unsupported language",
      body = "constant c : integer := 0;",
    })
    assert.is_false(ok)
    assert.matches("unknown language", table.concat(errs, "\n"))
  end)
end)
