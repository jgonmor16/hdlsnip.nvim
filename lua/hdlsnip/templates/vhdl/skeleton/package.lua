--- Package declaration.
---
--- Static on purpose: nothing here depends on configuration beyond keyword
--- case, so it renders as an LSP snippet body too. Typing the package name
--- once fills all three occurrences through tabstop mirroring.
return {
  name = "package",
  kind = "skeleton",
  desc = "Package declaration",

  params = {
    {
      name = "name",
      type = "identifier",
      default = "my_pkg",
      desc = "Package name",
    },
  },

  body = table.concat({
    "library ieee;",
    "  use ieee.std_logic_1164.all;",
    "",
    "package {{name}} is",
    "",
    "  {{cursor}}",
    "",
    "end package {{name}};",
  }, "\n"),
}
