--- Fixture: an unsupported language directory, skipped with a problem.
return {
  name = "fixture_sv",
  kind = "rtl",
  desc = "Fixture SystemVerilog",
  params = {
    { name = "sig", type = "identifier", default = "data", desc = "signal" },
  },
  body = "logic {{sig}};",
}
