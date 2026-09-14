-- The design the testbench demo is built around.
--
-- Called headlessly from demo/testbench.tape: passing the parameters directly
-- means no dialog opens and the result does not depend on timing.
vim.cmd.edit("src/fifo.vhd")
require("hdlsnip").insert("fifo_sync", {})
vim.cmd.write()
