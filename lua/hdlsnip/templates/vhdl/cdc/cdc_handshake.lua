--- Multi-bit clock domain crossing by handshake.
---
--- `bit_sync` refuses a bus on purpose: synchronising each bit independently
--- lets them settle on different cycles, so the destination can observe a
--- value that was never sent. This is the answer to that, and the reason it
--- exists is that the comment in `bit_sync` sends people looking for it.
---
--- How it works: the payload is captured in a register that only changes
--- while the request is idle, so it is stable for the whole crossing. A
--- single request bit crosses through a synchroniser, the destination
--- captures the payload and answers with an acknowledge that crosses back.
--- Only the two control bits are synchronised; the payload is never
--- synchronised at all, which is what makes it safe.
---
--- The cost is throughput: a full round trip is roughly two source cycles
--- plus two destination cycles. For a stream, use an asynchronous FIFO
--- instead.
local style = require("hdlsnip.style")

return {
  name = "cdc_handshake",
  trig = "hs",
  kind = "cdc",
  scope = "design_unit",
  desc = "Multi-bit CDC by request and acknowledge handshake",
  dynamic = true,

  params = {
    {
      name = "name",
      type = "identifier",
      default = "cdc_handshake",
      desc = "Entity name",
    },
    {
      name = "width",
      type = "integer",
      default = 16,
      min = 1,
      max = 4096,
      desc = "Default payload width",
    },
    {
      name = "stages",
      type = "integer",
      default = 2,
      min = 2,
      max = 8,
      desc = "Default synchroniser stages",
    },
  },

  render = function(params, cfg)
    local kw = style.kw(cfg)
    local ind = cfg.indent
    local has_reset = cfg.reset.style ~= "none"
    local width = style.name(cfg, "WIDTH", "generic")
    local stages = style.name(cfg, "STAGES", "generic")
    local lines = {}

    local function push(depth, text)
      lines[#lines + 1] = text == "" and "" or (ind:rep(depth) .. text)
    end
    local function name(base, kind)
      return style.name(cfg, base, kind)
    end

    -- Two domains, so the configured clock and reset names get a side.
    local src_clk = "src_" .. cfg.clock.name
    local dst_clk = "dst_" .. cfg.clock.name
    local src_rst = has_reset and ("src_" .. cfg.reset.name) or nil
    local dst_rst = has_reset and ("dst_" .. cfg.reset.name) or nil
    local slv = ("std_logic_vector(%s - 1 %s 0)"):format(width, kw("downto"))

    local function edge(clock)
      local fn = cfg.clock.edge == "falling" and "falling_edge" or "rising_edge"
      return ("%s(%s)"):format(kw(fn), clock)
    end
    local function active(reset)
      return ("%s = '%s'"):format(
        reset,
        cfg.reset.polarity == "low" and "0" or "1"
      )
    end
    local function sensitivity(clock, reset)
      if cfg.reset.style == "async" and reset then
        return ("(%s, %s)"):format(clock, reset)
      end
      return ("(%s)"):format(clock)
    end

    push(0, ("%s ieee;"):format(kw("library")))
    push(1, ("%s ieee.std_logic_1164.%s;"):format(kw("use"), kw("all")))
    push(0, "")
    push(0, "-- Multi-bit crossing by handshake.")
    push(0, "--")
    push(0, "-- Only the request and acknowledge bits cross through")
    push(0, "-- synchronisers. The payload is never synchronised: it is held")
    push(0, "-- stable for the whole crossing instead, which is what makes it")
    push(0, "-- safe to sample directly.")
    push(0, "--")
    push(0, "-- Constrain both crossings with set_max_delay -datapath_only,")
    push(0, "-- and the payload path with a bus-skew constraint.")
    push(0, ("%s %s %s"):format(kw("entity"), params.name, kw("is")))

    local generics = style.align({
      { width, (": positive := %d;"):format(params.width) },
      { stages, (": positive := %d"):format(params.stages) },
    })
    push(1, ("%s ("):format(kw("generic")))
    for _, line in ipairs(generics) do
      push(2, line)
    end
    push(1, ");")

    local ports = { { src_clk, (": %s"):format(kw("in")), "std_logic" } }
    if has_reset then
      ports[#ports + 1] = { src_rst, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { name("src_valid", "input"), (": %s"):format(kw("in")), "std_logic" },
      { name("src_data", "input"), (": %s"):format(kw("in")), slv },
      { name("src_ready", "output"), (": %s"):format(kw("out")), "std_logic" },
      { dst_clk, (": %s"):format(kw("in")), "std_logic" },
    })
    if has_reset then
      ports[#ports + 1] = { dst_rst, (": %s"):format(kw("in")), "std_logic" }
    end
    vim.list_extend(ports, {
      { name("dst_valid", "output"), (": %s"):format(kw("out")), "std_logic" },
      { name("dst_data", "output"), (": %s"):format(kw("out")), slv },
    })

    push(1, ("%s ("):format(kw("port")))
    local aligned = style.align(ports)
    for index, line in ipairs(aligned) do
      push(2, line .. (index < #aligned and ";" or ""))
    end
    push(1, ");")
    push(0, ("%s %s %s;"):format(kw("end"), kw("entity"), params.name))
    push(0, "")

    push(
      0,
      ("%s rtl %s %s %s"):format(
        kw("architecture"),
        kw("of"),
        params.name,
        kw("is")
      )
    )
    push(0, "")

    local payload = name("payload", "register")
    local req = name("req", "register")
    local ack = name("ack", "register")
    local req_sync = name("req_sync", "register")
    local ack_sync = name("ack_sync", "register")

    push(1, "-- Source domain.")
    push(
      1,
      ("%s %s : %s := (%s => '0');"):format(
        kw("signal"),
        payload,
        slv,
        kw("others")
      )
    )
    push(1, ("%s %s : std_logic := '0';"):format(kw("signal"), req))
    push(
      1,
      ("%s %s : std_logic_vector(%s - 1 %s 0) := (%s => '0');"):format(
        kw("signal"),
        ack_sync,
        stages,
        kw("downto"),
        kw("others")
      )
    )
    push(0, "")
    push(1, "-- Destination domain.")
    push(1, ("%s %s : std_logic := '0';"):format(kw("signal"), ack))
    push(
      1,
      ("%s %s : std_logic_vector(%s - 1 %s 0) := (%s => '0');"):format(
        kw("signal"),
        req_sync,
        stages,
        kw("downto"),
        kw("others")
      )
    )

    if cfg.vendor == "amd" then
      push(0, "")
      push(1, ("%s async_reg : string;"):format(kw("attribute")))
      push(
        1,
        ('%s async_reg %s %s : %s %s "TRUE";'):format(
          kw("attribute"),
          kw("of"),
          ack_sync,
          kw("signal"),
          kw("is")
        )
      )
      push(
        1,
        ('%s async_reg %s %s : %s %s "TRUE";'):format(
          kw("attribute"),
          kw("of"),
          req_sync,
          kw("signal"),
          kw("is")
        )
      )
    elseif cfg.vendor == "intel" then
      push(0, "")
      push(1, ("%s preserve : boolean;"):format(kw("attribute")))
      push(
        1,
        ("%s preserve %s %s : %s %s true;"):format(
          kw("attribute"),
          kw("of"),
          ack_sync,
          kw("signal"),
          kw("is")
        )
      )
      push(
        1,
        ("%s preserve %s %s : %s %s true;"):format(
          kw("attribute"),
          kw("of"),
          req_sync,
          kw("signal"),
          kw("is")
        )
      )
    end

    push(0, "")
    push(0, kw("begin"))
    push(0, "")

    -- -------------------------------------------------------------------
    -- Source domain
    -- -------------------------------------------------------------------
    local src_label = name("source", "process")
    push(1, "-- The payload changes only while the request is idle, so it is")
    push(1, "-- stable for the whole crossing and needs no synchroniser.")
    push(
      1,
      ("%s : %s %s %s"):format(
        src_label,
        kw("process"),
        sensitivity(src_clk, src_rst),
        kw("is")
      )
    )
    push(1, kw("begin"))

    local function src_reset(depth)
      push(depth, ("%s <= '0';"):format(req))
      push(depth, ("%s <= (%s => '0');"):format(ack_sync, kw("others")))
      push(depth, ("%s <= (%s => '0');"):format(payload, kw("others")))
    end

    local function src_body(depth)
      push(
        depth,
        ("%s <= %s(%s'high - 1 %s 0) & %s;"):format(
          ack_sync,
          ack_sync,
          ack_sync,
          kw("downto"),
          ack
        )
      )
      push(depth, "")
      push(depth, ("%s %s = '0' %s"):format(kw("if"), req, kw("then")))
      push(
        depth + 1,
        ("%s %s = '1' %s %s(%s'high) = '0' %s"):format(
          kw("if"),
          name("src_valid", "input"),
          kw("and"),
          ack_sync,
          ack_sync,
          kw("then")
        )
      )
      push(depth + 2, ("%s <= %s;"):format(payload, name("src_data", "input")))
      push(depth + 2, ("%s <= '1';"):format(req))
      push(depth + 1, kw("end if") .. ";")
      push(
        depth,
        ("%s %s(%s'high) = '1' %s"):format(
          kw("elsif"),
          ack_sync,
          ack_sync,
          kw("then")
        )
      )
      push(depth + 1, ("%s <= '0';"):format(req))
      push(depth, kw("end if") .. ";")
    end

    if cfg.reset.style == "async" then
      push(2, ("%s %s %s"):format(kw("if"), active(src_rst), kw("then")))
      src_reset(3)
      push(2, ("%s %s %s"):format(kw("elsif"), edge(src_clk), kw("then")))
      src_body(3)
      push(2, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(2, ("%s %s %s"):format(kw("if"), edge(src_clk), kw("then")))
      push(3, ("%s %s %s"):format(kw("if"), active(src_rst), kw("then")))
      src_reset(4)
      push(3, kw("else"))
      src_body(4)
      push(3, kw("end if") .. ";")
      push(2, kw("end if") .. ";")
    else
      push(2, ("%s %s %s"):format(kw("if"), edge(src_clk), kw("then")))
      src_body(3)
      push(2, kw("end if") .. ";")
    end

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), src_label))
    push(0, "")
    push(
      1,
      ("%s <= '1' %s %s = '0' %s %s(%s'high) = '0' %s '0';"):format(
        name("src_ready", "output"),
        kw("when"),
        req,
        kw("and"),
        ack_sync,
        ack_sync,
        kw("else")
      )
    )
    push(0, "")

    -- -------------------------------------------------------------------
    -- Destination domain
    -- -------------------------------------------------------------------
    local dst_label = name("dest", "process")
    push(
      1,
      ("%s : %s %s %s"):format(
        dst_label,
        kw("process"),
        sensitivity(dst_clk, dst_rst),
        kw("is")
      )
    )
    push(1, kw("begin"))

    local function dst_reset(depth)
      push(depth, ("%s <= '0';"):format(ack))
      push(depth, ("%s <= (%s => '0');"):format(req_sync, kw("others")))
      push(depth, ("%s <= '0';"):format(name("dst_valid", "output")))
      push(
        depth,
        ("%s <= (%s => '0');"):format(name("dst_data", "output"), kw("others"))
      )
    end

    local function dst_body(depth)
      push(
        depth,
        ("%s <= %s(%s'high - 1 %s 0) & %s;"):format(
          req_sync,
          req_sync,
          req_sync,
          kw("downto"),
          req
        )
      )
      push(depth, ("%s <= '0';"):format(name("dst_valid", "output")))
      push(depth, "")
      push(depth, "-- The payload has been stable for at least the crossing")
      push(depth, "-- delay by now, so it is sampled directly.")
      push(
        depth,
        ("%s %s(%s'high) = '1' %s %s = '0' %s"):format(
          kw("if"),
          req_sync,
          req_sync,
          kw("and"),
          ack,
          kw("then")
        )
      )
      push(depth + 1, ("%s <= %s;"):format(name("dst_data", "output"), payload))
      push(depth + 1, ("%s <= '1';"):format(name("dst_valid", "output")))
      push(depth + 1, ("%s <= '1';"):format(ack))
      push(
        depth,
        ("%s %s(%s'high) = '0' %s"):format(
          kw("elsif"),
          req_sync,
          req_sync,
          kw("then")
        )
      )
      push(depth + 1, ("%s <= '0';"):format(ack))
      push(depth, kw("end if") .. ";")
    end

    if cfg.reset.style == "async" then
      push(2, ("%s %s %s"):format(kw("if"), active(dst_rst), kw("then")))
      dst_reset(3)
      push(2, ("%s %s %s"):format(kw("elsif"), edge(dst_clk), kw("then")))
      dst_body(3)
      push(2, kw("end if") .. ";")
    elseif cfg.reset.style == "sync" then
      push(2, ("%s %s %s"):format(kw("if"), edge(dst_clk), kw("then")))
      push(3, ("%s %s %s"):format(kw("if"), active(dst_rst), kw("then")))
      dst_reset(4)
      push(3, kw("else"))
      dst_body(4)
      push(3, kw("end if") .. ";")
      push(2, kw("end if") .. ";")
    else
      push(2, ("%s %s %s"):format(kw("if"), edge(dst_clk), kw("then")))
      dst_body(3)
      push(2, kw("end if") .. ";")
    end

    push(1, ("%s %s %s;"):format(kw("end"), kw("process"), dst_label))
    push(0, "")
    push(0, ("%s %s rtl;"):format(kw("end"), kw("architecture")))

    return table.concat(lines, "\n")
  end,
}
