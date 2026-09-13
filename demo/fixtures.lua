-- Designs for the instantiation demo, generated rather than typed.
--
-- Called headlessly from demo/instantiate.tape. Parameters are passed
-- directly, so no dialog opens and the result does not depend on timing.
local hdlsnip = require("hdlsnip")

local designs = {
  { file = "regs", template = "axi4lite_slave" },
  { file = "apb", template = "apb_slave" },
  { file = "buffer", template = "fifo_sync" },
  { file = "sync", template = "bit_sync" },
  { file = "cross", template = "cdc_handshake" },
  { file = "memory", template = "ram_dp" },
  { file = "stream", template = "axis_skid" },
}

-- The same templates again with different parameters, which is how a real
-- project accumulates designs: several FIFOs of different widths, a couple
-- of register blocks. Enough to push the list past one page, and every one
-- of them a genuine interface.
vim.list_extend(designs, {
  {
    file = "status_regs",
    template = "axi4lite_slave",
    params = { name = "status_regs", registers = 16, prefix = "s_axi" },
  },
  {
    file = "ctrl_regs",
    template = "apb_slave",
    params = { name = "ctrl_regs", registers = 8 },
  },
  {
    file = "rx_fifo",
    template = "fifo_sync",
    params = { name = "rx_fifo", width = 32, depth = 512 },
  },
  {
    file = "tx_fifo",
    template = "fifo_sync",
    params = { name = "tx_fifo", width = 8, depth = 64 },
  },
  {
    file = "line_buffer",
    template = "ram_dp",
    params = { name = "line_buffer", width = 24, depth = 2048 },
  },
  {
    file = "irq_sync",
    template = "bit_sync",
    params = { name = "irq_sync", stages = 3 },
  },
  {
    file = "cfg_cross",
    template = "cdc_handshake",
    params = { name = "cfg_cross", width = 32, stages = 2 },
  },
})

for _, design in ipairs(designs) do
  vim.cmd.edit(("src/%s.vhd"):format(design.file))
  hdlsnip.insert(design.template, design.params or {})
  vim.cmd.write()
end
