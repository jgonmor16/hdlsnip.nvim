--- Render every template through the public API and dump the result.
---
--- Complements demo/smoke.tape, which drives the interactive paths. This one
--- answers the other question: does every template still produce what it
--- should, under more than one configuration, through the same code path a
--- user's `:HdlSnip` takes?
---
--- Usage: make smoke   (writes .tests/smoke.txt)
local registry = require("hdlsnip.registry")
local render = require("hdlsnip.render")
local config = require("hdlsnip.config")
local template = require("hdlsnip.template")

local OUT = vim.env.HDLSNIP_SMOKE_OUT or ".tests/smoke.txt"

local VARIANTS = {
  { name = "defaults", cfg = {} },
  {
    name = "upper, sync reset, axi names",
    cfg = {
      keyword_case = "upper",
      reset = { style = "sync", polarity = "high" },
      clock = { name = "axi_aclk" },
    },
  },
  { name = "no reset", cfg = { reset = { style = "none" } } },
}

local out = {}

local function say(fmt, ...)
  out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
end

local function rule(char)
  say(string.rep(char or "-", 78))
end

local function main()
  local templates = registry.list()

  rule("=")
  say("hdlsnip smoke check")
  say("%d templates, %d configuration variants", #templates, #VARIANTS)
  rule("=")
  say("")

  local problems = registry.problems()
  if #problems > 0 then
    say("PROBLEMS AT LOAD:")
    for _, problem in ipairs(problems) do
      say("  %s", problem)
    end
    say("")
  end

  say("REGISTRY")
  for _, tpl in ipairs(templates) do
    say(
      "  %-9s %-16s %-6s %-12s %s",
      tpl.trig or "-",
      tpl.name,
      tpl.kind,
      template.scope(tpl),
      tpl.dynamic and "dynamic" or "static"
    )
  end
  say("")

  local failures = 0

  for _, tpl in ipairs(templates) do
    rule("=")
    say("%s  (%s)", tpl.name, tpl.desc)
    rule("=")

    for _, param in ipairs(tpl.params or {}) do
      say(
        "  param %-10s %-10s default %s",
        param.name,
        param.type,
        tostring(param.default)
      )
    end

    -- Static templates also render as snippets; show that body once.
    if not tpl.dynamic then
      local body = render.placeholders(tpl, config.get())
      say("")
      say("  snippet body:")
      for _, line in ipairs(vim.split(body or "<failed>", "\n")) do
        say("    %s", line)
      end
    end

    for _, variant in ipairs(VARIANTS) do
      local cfg = config.resolve(config.merge(config.defaults, variant.cfg))
      local sections, errors = render.sections(tpl, {}, cfg)

      say("")
      say("  -- %s", variant.name)
      if not sections then
        failures = failures + 1
        say("     FAILED: %s", table.concat(errors, "; "))
      else
        if sections.declarations and sections.declarations ~= "" then
          say("     [declarations]")
          for _, line in ipairs(render.lines(sections.declarations)) do
            say("     %s", line)
          end
          say("     [statements]")
        end
        for _, line in ipairs(render.lines(sections.statements or "")) do
          say("     %s", line)
        end
      end
    end
    say("")
  end

  rule("=")
  say(
    failures == 0 and "OK: every template rendered"
      or ("FAILED: %d"):format(failures)
  )
  rule("=")

  vim.fn.mkdir(vim.fn.fnamemodify(OUT, ":h"), "p")
  local fd = assert(io.open(OUT, "w"))
  fd:write(table.concat(out, "\n") .. "\n")
  fd:close()

  print(("smoke: wrote %s"):format(OUT))
  os.exit(failures == 0 and 0 or 1)
end

main()
