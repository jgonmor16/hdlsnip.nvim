--- Fixture: a minimal valid dynamic template, in a second kind.
return {
  name = "fixture_sync",
  kind = "cdc",
  desc = "Fixture synchroniser",
  dynamic = true,
  params = {
    {
      name = "stages",
      type = "integer",
      default = 2,
      min = 2,
      desc = "stages",
    },
  },
  render = function(params)
    return ("stages = %d"):format(params.stages)
  end,
}
