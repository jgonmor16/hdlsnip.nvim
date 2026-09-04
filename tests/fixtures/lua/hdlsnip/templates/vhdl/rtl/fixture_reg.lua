--- Fixture: a minimal valid static template.
return {
  name = "fixture_reg",
  kind = "rtl",
  desc = "Fixture registered signal",
  params = {
    { name = "sig", type = "identifier", default = "data", desc = "signal" },
  },
  body = "signal {{sig}}_r : std_logic;",
}
