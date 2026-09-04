--- Fixture: declares a kind that does not match its directory, which would
--- hide it from the picker group a reader expects to find it in.
return {
  name = "fixture_misplaced",
  kind = "cdc",
  desc = "Fixture in the wrong directory",
  params = {
    { name = "sig", type = "identifier", default = "data", desc = "signal" },
  },
  body = "signal {{sig}}_r : std_logic;",
}
