-- Designs for the testbench demo, generated rather than typed.
--
-- Called headlessly from demo/testbench.tape: parameters are passed directly,
-- so no dialog opens and the result does not depend on timing.
local hdlsnip = require("hdlsnip")

local designs = {
  { file = "regs", template = "axi4lite_slave" },
  { file = "apb", template = "apb_slave" },
  { file = "wishbone", template = "wishbone_slave" },
  { file = "avalon", template = "avalon_mm_slave" },
  { file = "buffer", template = "fifo_sync" },
  { file = "afifo", template = "fifo_async" },
  { file = "memory", template = "ram_dp" },
  { file = "stream", template = "axis_skid" },
  { file = "sync", template = "bit_sync" },
  { file = "cross", template = "cdc_handshake" },
  {
    file = "rx_fifo",
    template = "fifo_sync",
    params = { name = "rx_fifo", width = 32, depth = 512 },
  },
  {
    file = "status_regs",
    template = "axi4lite_slave",
    params = { name = "status_regs", registers = 16, prefix = "s_axi" },
  },
}

for _, design in ipairs(designs) do
  vim.cmd.edit(("src/%s.vhd"):format(design.file))
  hdlsnip.insert(design.template, design.params or {})
  vim.cmd.write()
end

-- The file the testbench is written from, left empty.
vim.cmd.edit("src/top.vhd")
vim.cmd.write()
