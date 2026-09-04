--- Fixture: fails validation. The body uses a marker that is not a
--- parameter, so the registry must skip it and record the problem rather
--- than aborting the whole load.
return {
  name = "fixture_bad",
  kind = "rtl",
  desc = "Fixture invalid template",
  params = {
    { name = "sig", type = "identifier", default = "data", desc = "signal" },
  },
  body = "signal {{sig}}_r : {{undeclared}};",
}
