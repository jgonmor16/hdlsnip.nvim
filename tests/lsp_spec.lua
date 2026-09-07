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

  it("omits dynamic templates, which cannot ask a question", function()
    local items = lsp.items(cfg({}))
    assert.is_nil(by_label(items, "ent"))
    assert.is_nil(by_label(items, "prc"))
    assert.is_nil(by_label(items, "cdc"))
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
