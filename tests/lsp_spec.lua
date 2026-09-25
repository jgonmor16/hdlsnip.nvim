local config = require("hdlsnip.config")
local lsp = require("hdlsnip.lsp")

local function cfg(over)
  return config.resolve(config.merge(config.defaults, over))
end

local function by_label(items, label)
  for _, item in ipairs(items) do
    if item.label == label then
      return item
    end
  end
  return nil
end

describe("lsp.items", function()
  it("offers a static template by its trigger", function()
    local item = by_label(lsp.items(cfg({})), "pkg")
    assert.is_not_nil(item)
    assert.are.equal("pkg", item.filterText)
    assert.are.equal(vim.lsp.protocol.CompletionItemKind.Snippet, item.kind)
    assert.matches("Package", item.detail)
  end)

  it("marks the text as a snippet, with tabstops", function()
    local item = by_label(lsp.items(cfg({})), "pkg")
    assert.are.equal(2, item.insertTextFormat)
    assert.matches("%${1:my_pkg}", item.insertText)
    assert.matches("%$1", item.insertText)
  end)

  it("offers dynamic templates too, flagged for the dialog", function()
    local registry = require("hdlsnip.registry")
    local items = lsp.items(cfg({}))
    for _, trigger in ipairs({ "ent", "prc", "cdc", "axil" }) do
      local item = by_label(items, trigger)
      assert.is_not_nil(item, trigger .. " is missing")
      assert.is_true(item.data.dynamic)
      -- Nothing is inserted: CompleteDone opens the dialog instead, and
      -- inserted text would have to be undone first.
      assert.are.equal("", item.insertText)
      assert.are.equal(1, item.insertTextFormat)
      -- The kind alone tells them apart from snippets; the detail is the
      -- description and nothing more, so the menu stays narrow.
      assert.are.equal(vim.lsp.protocol.CompletionItemKind.Interface, item.kind)
      assert.are.equal(registry.get(item.data.template).desc, item.detail)
    end
  end)

  it("offers one item per template with a trigger", function()
    local registry = require("hdlsnip.registry")
    local expected = 0
    for _, tpl in ipairs(registry.list({ lang = "vhdl" })) do
      if tpl.trig then
        expected = expected + 1
      end
    end
    assert.are.equal(expected, #lsp.items(cfg({})))
  end)

  it("previews a dynamic template's output too", function()
    local item = by_label(lsp.items(cfg({})), "prc")
    assert.matches("p_main : process", item.documentation.value)
  end)

  it("previews the rendered template in the documentation", function()
    local item = by_label(lsp.items(cfg({})), "pkg")
    assert.are.equal("markdown", item.documentation.kind)
    assert.matches("```vhdl", item.documentation.value)
    assert.matches("package my_pkg is", item.documentation.value)
  end)

  it("follows the configuration it is given", function()
    local item = by_label(lsp.items(cfg({ keyword_case = "upper" })), "pkg")
    assert.matches("PACKAGE", item.insertText)
    assert.matches("PACKAGE my_pkg IS", item.documentation.value)
  end)

  it("names the template it came from", function()
    local item = by_label(lsp.items(cfg({})), "pkg")
    assert.are.equal("package", item.data.template)
  end)

  it("keeps every preview within the cap", function()
    -- Two fences around the code, and one line saying what was cut.
    local most = lsp.PREVIEW_LINES + 3
    for _, item in ipairs(lsp.items(cfg({}))) do
      local count = #vim.split(item.documentation.value, "\n")
      assert.is_true(count <= most, ("%s: %d lines"):format(item.label, count))
    end
  end)
end)

describe("lsp.preview", function()
  it("starts at the code, past the context clause and header", function()
    local text = table.concat({
      "library ieee;",
      "  use ieee.std_logic_1164.all;",
      "",
      "-- A header comment.",
      "entity top is",
      "end entity top;",
    }, "\n")
    assert.are.equal("entity top is\nend entity top;", lsp.preview(text))
  end)

  it("skips the context clause in upper case too", function()
    local text = "LIBRARY ieee;\n  USE ieee.std_logic_1164.ALL;\nENTITY top IS"
    assert.are.equal("ENTITY top IS", lsp.preview(text))
  end)

  it("caps a long template and says how much is left out", function()
    local lines = {}
    for index = 1, 40 do
      lines[index] = ("signal s%d : std_logic;"):format(index)
    end
    local shown = vim.split(lsp.preview(table.concat(lines, "\n")), "\n")
    assert.are.equal(lsp.PREVIEW_LINES + 1, #shown)
    assert.are.equal("signal s1 : std_logic;", shown[1])
    assert.are.equal(
      ("-- ... %d more lines"):format(40 - lsp.PREVIEW_LINES),
      shown[#shown]
    )
  end)

  it("leaves a short template whole", function()
    local text = "package p is\nend package p;"
    assert.are.equal(text, lsp.preview(text))
  end)
end)

describe("lsp.server", function()
  --- Drive the client directly: no vim.lsp.start, no buffer, no frontend.
  ---
  --- Replies are deferred, as a real server's are, so the result has to be
  --- waited for rather than read straight back.
  local function request(method, params)
    local srv = lsp.server({ on_exit = function() end })
    local result
    local replied = false
    local ok = srv.request(method, params, function(_, res)
      result = res
      replied = true
    end)
    assert.is_true(ok)
    vim.wait(1000, function()
      return replied
    end)
    assert.is_true(replied, "server never replied to " .. method)
    return result
  end

  it("advertises completion on initialize", function()
    local result = request("initialize", {})
    assert.is_not_nil(result.capabilities.completionProvider)
    assert.are.equal("hdlsnip", result.serverInfo.name)
  end)

  it("answers a completion request", function()
    local items = request("textDocument/completion", {})
    assert.is_true(#items > 0)
    assert.is_not_nil(by_label(items, "pkg"))
  end)

  --- Ask for completions at a column of a one-line VHDL buffer.
  local function complete_at(line, character)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".vhd")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
    return request("textDocument/completion", {
      textDocument = { uri = vim.uri_from_bufnr(bufnr) },
      position = { line = 0, character = character },
    })
  end

  it("offers nothing after whitespace", function()
    assert.are.same({}, complete_at("  wr_clk   : in std_logic;", 11))
  end)

  it("offers nothing on an empty line", function()
    assert.are.same({}, complete_at("", 0))
  end)

  it("offers templates once a word is typed", function()
    assert.is_not_nil(by_label(complete_at("  ax", 4), "axil"))
  end)

  it("reads the word before the cursor, not the whole line", function()
    assert.is_not_nil(by_label(complete_at("pkg  -- note", 3), "pkg"))
  end)

  it("answers shutdown", function()
    assert.is_nil(request("shutdown", {}))
  end)

  it("reports closing only after terminate", function()
    local srv = lsp.server({ on_exit = function() end })
    assert.is_false(srv.is_closing())
    srv.terminate()
    assert.is_true(srv.is_closing())
  end)

  it("exits on notify", function()
    local exited
    local srv = lsp.server({
      on_exit = function(code)
        exited = code
      end,
    })
    srv.notify("exit")
    assert.are.equal(0, exited)
  end)
end)
