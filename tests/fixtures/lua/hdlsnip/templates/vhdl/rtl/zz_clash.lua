--- Fixture: claims a trigger that fixture_reg already owns. The registry
--- must refuse it rather than let load order decide which one fires.
return {
  name = "zz_clash",
  trig = "fxr",
  kind = "rtl",
  desc = "Fixture with a duplicate trigger",
  params = {
    { name = "sig", type = "identifier", default = "data", desc = "signal" },
  },
  body = "signal {{sig}}_clash : std_logic;",
}
