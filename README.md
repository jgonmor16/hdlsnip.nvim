# hdlsnip.nvim

[![ci](https://github.com/jgonmor16/hdlsnip.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/jgonmor16/hdlsnip.nvim/actions/workflows/ci.yml)
![release](https://img.shields.io/github/v/release/jgonmor16/hdlsnip.nvim?display_name=tag)
![neovim](https://img.shields.io/badge/Neovim-0.10+-57A143?logo=neovim&logoColor=white)
![ghdl](https://img.shields.io/badge/templates-GHDL%20verified-D79921)
![license](https://img.shields.io/github/license/jgonmor16/hdlsnip.nvim)

<p align="center">
  <a href="https://github.com/jgonmor16/hdlsnip.nvim">
    <img src="https://readme-typing-svg.demolab.com/?font=JetBrains+Mono&size=20&duration=3500&pause=1500&color=D79921&center=true&vCenter=true&width=620&height=45&lines=Templates+that+follow+your+house+style;Async%2C+sync+or+no+reset%2C+from+config;Every+template+compiled+by+GHDL" alt="hdlsnip.nvim" />
  </a>
</p>

Parameterised VHDL templates for Neovim — entities, packages, clocked processes
and CDC synchronisers, rendered from Lua rather than pasted from a static
snippet file.

```vhdl
-- :HdlSnip process, with reset.style = "async", polarity = "low"
p_main : process (clk, rst_n) is
begin
  if rst_n = '0' then
    -- reset state
  elsif rising_edge(clk) then
    -- clocked logic
  end if;
end process p_main;
```

Change `reset.style` to `"sync"` and the same template puts the reset branch
inside the clock test instead, and drops the reset from the sensitivity list.
That is the point: the shape of the code follows your house style, and getting
it wrong is a synthesis mismatch rather than a syntax error.

<p align="center">
  <img src="https://github.com/user-attachments/assets/2767ce9a-3e42-429f-8129-341acdbc9e16" width="900"
       alt="The same process template inserted twice: an asynchronous reset outside the clock test, then a synchronous one inside it after a single configuration change" />
</p>

## Why not a snippet pack

VS Code snippet files cannot express a stage count, a register file depth, a
reset flavour, a vendor attribute or an aligned port column. Templates here are
Lua that renders VHDL, so they can:

- omit the reset port entirely when the design has no reset
- align port columns against whatever your clock is called
- emit `async_reg` on AMD, `preserve` on Intel, nothing on neither
- keep the last port free of its trailing semicolon, whatever the port count

Static templates still render as ordinary LSP snippets, so nothing is lost.

## Requirements

- Neovim >= 0.10 (`vim.snippet`)
- Neovim >= 0.12 if installing with `vim.pack`; the plugin itself still works on
  0.10 with any other manager
- No plugins. Pickers and prompts go through `vim.ui`, so telescope, fzf-lua or
  snacks are used if you have them and the built-in prompts if you do not.

## Installation

With `vim.pack`, built into Neovim 0.12 and needing nothing else:

```lua
vim.pack.add({ { src = "https://github.com/jgonmor16/hdlsnip.nvim" } })

-- Optional; the commands work on the defaults without it.
require("hdlsnip").setup({
  vhdl_std = "2008",
  reset = { style = "async", polarity = "low" },
})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jgonmor16/hdlsnip.nvim",
  ft = { "vhdl" },
  ---@type hdlsnip.Config
  opts = {
    vhdl_std = "2008",
    reset = { style = "async", polarity = "low" },
  },
}
```

`setup()` is optional. The commands work on the defaults without it.

## Usage

| Command | Does |
| --- | --- |
| `:HdlSnip [name]` | Prompt for parameters and insert. Picker when no name is given |
| `:HdlSnipExpand [name]` | Expand as a snippet, with tabstops |
| `:HdlSnipReload` | Rescan the runtimepath for templates |
| `:checkhealth hdlsnip` | Templates found, configuration in effect, anything skipped |
| `:HdlSnipLspAttach` | Attach the completion server to this buffer |

Nothing is mapped by default. To expand from insert mode and move between
tabstops:

```lua
require("hdlsnip").setup({
  keys = {
    expand = "<C-k>",       -- expand a trigger, or jump forward in a snippet
    jump_prev = "<C-j>",
  },
})
```

Each falls through when it has nothing to do, so `<C-k>` still inserts a
digraph when the word before the cursor is not a trigger and no snippet is
active. `jump_next` is only needed if you want a separate key for jumping
forward.

With a plugin manager that takes an opts table, keys goes in there alongside
the rest of the configuration.

If a completion plugin is bound to the same key, whichever mapping is defined
last wins. With blink.cmp, give hdlsnip first refusal instead:

```lua
keymap = {
  ["<C-k>"] = {
    function()
      return require("hdlsnip").expand_at_cursor()
    end,
    "fallback",
  },
}
```

Templates also appear in the completion menu. hdlsnip runs an in-process LSP
server — a Lua table, not a process — so any completion frontend picks them up.
With the built-in menu:

```lua
vim.lsp.completion.enable(true, client_id, bufnr, { autotrigger = true })
```

nvim-cmp and blink.cmp need nothing: they consume LSP sources already. Turn it
off with `lsp = false`.

Only static templates are offered. A completion item cannot ask a question, so
`ent`, `prc` and `cdc` stay on the trigger key and `:HdlSnip`.

Type `pkg`, press `<C-k>`, and the trigger is replaced by the template with the
package name as the first tabstop.

<p align="center">
  <img src="https://github.com/user-attachments/assets/73d8b769-8a93-43fa-9e89-04e5ed57928e" width="900"
       alt="Typing pkg and pressing Ctrl-K expands a package template; naming it once updates both the declaration and the end clause" />
</p>

## Templates

| Trigger | Name | Kind | Emits |
| --- | --- | --- | --- |
| `ent` | `entity` | skeleton | Entity with a matching architecture |
| `pkg` | `package` | skeleton | Package declaration |
| `prc` | `process` | rtl | Clocked process with the configured reset |
| `cdc` | `bit_sync` | cdc | Single-bit CDC synchroniser entity |

Templates are either **static**, rendering as a snippet with tabstops, or
**dynamic**, where the output depends on configuration or on a parameter. A
tabstop cannot decide whether a reset port exists, so dynamic templates prompt
and insert fully formed instead. `:HdlSnipExpand` falls back to that
automatically.

<p align="center">
  <img src="https://github.com/user-attachments/assets/63ab0a16-55ca-49c6-b411-ae905d0547ac" width="900"
       alt="Running HdlSnip bit_sync, answering two prompts, and getting a complete synchroniser entity with the stage count as a generic" />
</p>

## Configuration

Defaults, in full:

```lua
{
  vhdl_std = "2008",        -- "93" | "2002" | "2008" | "2019"
  keyword_case = "lower",   -- "lower" | "upper"
  indent = "  ",
  clock = { name = "clk", edge = "rising" },
  reset = {
    style = "async",        -- "async" | "sync" | "none"
    polarity = "low",       -- "low" | "high"
    name = nil,             -- derived: rst_n when low, rst when high
  },
  naming = {
    in_suffix = "_i",
    out_suffix = "_o",
    reg_suffix = "_r",
    sig_prefix = "",
    proc_prefix = "p_",
    const_prefix = "C_",
    generic_prefix = "G_",
  },
  vendor = "generic",       -- "generic" | "amd" | "intel" | "lattice" | "microchip"
  align_ports = true,
}
```

Invalid options are reported with the path that is wrong, and the previous
configuration is kept rather than half-applied.

### Per project

A `.hdlsnip.lua` at the project root overrides the global configuration for
buffers under it:

```lua
-- .hdlsnip.lua
return {
  keyword_case = "upper",
  clock = { name = "axi_aclk" },
  reset = { style = "sync" },
}
```

It is arbitrary Lua from a checked-out repository, so it goes through
`vim.secure.read`: Neovim asks once per file, the same as `exrc`.

## Adding your own templates

Templates are discovered from the runtimepath at
`lua/hdlsnip/templates/<lang>/<kind>/<name>.lua`. Neovim searches your config
before plugins, so a file at that path in your own config **shadows** the one
shipped here. Overriding a template needs no configuration.

```lua
-- ~/.config/nvim/lua/hdlsnip/templates/vhdl/rtl/counter.lua
return {
  name = "counter",         -- must match the file name
  trig = "cnt",             -- unique, and never a reserved word
  kind = "rtl",             -- must match the directory
  scope = "declarative",
  desc = "Counter register",
  params = {
    { name = "sig", type = "identifier", default = "count", desc = "Signal" },
    { name = "width", type = "integer", default = 8, min = 1, desc = "Width" },
  },
  body = "signal {{sig}} : unsigned({{width}} - 1 downto 0);{{cursor}}",
}
```

A `render = function(params, cfg)` returning a string replaces `body` for
anything needing logic; set `dynamic = true` alongside it.

`:checkhealth hdlsnip` lists anything that failed to load and why.

## Correctness

Every template is rendered across six configuration variants and one case per
parameter alternative, committed under `tests/golden/`, and analysed with GHDL
in CI. A change to generated VHDL shows up as a reviewable diff rather than
hiding inside a Lua change.

```bash
make test          # spec suite
make golden        # regenerate fixtures
make ghdl          # analyse every fixture
```

## Roadmap

- Configurable keymaps for expansion and tabstop jumping ([#7](https://github.com/jgonmor16/hdlsnip.nvim/issues/7))
- Completion menu integration through an in-process LSP server, no plugins
  ([#8](https://github.com/jgonmor16/hdlsnip.nvim/issues/8))
- Live parameter editing for dynamic templates, with no snippet engine
  dependency ([#12](https://github.com/jgonmor16/hdlsnip.nvim/issues/12))
- More templates: FSMs, counters, FIFOs, dual-port RAM, AXI4-Lite, AXI-Stream,
  VUnit and OSVVM testbench scaffolding
- Treesitter: entity to component, instantiation, signal declarations and
  testbench

## Contributing

Branches follow `feat/`, `fix/`, `doc/`, `ci/`, `test/`, `refactor/`,
`chore/` and `hotfix/`; pull requests target `devel`, which is merged into
`main` and tagged for each release.
Commit messages follow Conventional Commits with a 50-character subject and a
body wrapped at 70 columns.

## Licence

MIT — see [LICENSE](LICENSE). Code generated by this plugin is yours to use
without restriction or attribution; see [OUTPUT-LICENSE.md](OUTPUT-LICENSE.md).
