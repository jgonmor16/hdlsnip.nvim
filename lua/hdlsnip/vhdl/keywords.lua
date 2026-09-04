--- VHDL reserved words.
---
--- Split by revision so identifier validation can be as permissive as the
--- configured standard: `entity` is reserved everywhere, but `context` and
--- `force` only became reserved in VHDL-2008, and code targeting VHDL-93 may
--- legitimately use them as identifiers.
local M = {}

--- Reserved in VHDL-87 through VHDL-2019.
M.common = {
  "abs",
  "access",
  "after",
  "alias",
  "all",
  "and",
  "architecture",
  "array",
  "assert",
  "attribute",
  "begin",
  "block",
  "body",
  "buffer",
  "bus",
  "case",
  "component",
  "configuration",
  "constant",
  "disconnect",
  "downto",
  "else",
  "elsif",
  "end",
  "entity",
  "exit",
  "file",
  "for",
  "function",
  "generate",
  "generic",
  "group",
  "guarded",
  "if",
  "impure",
  "in",
  "inertial",
  "inout",
  "is",
  "label",
  "library",
  "linkage",
  "literal",
  "loop",
  "map",
  "mod",
  "nand",
  "new",
  "next",
  "nor",
  "not",
  "null",
  "of",
  "on",
  "open",
  "or",
  "others",
  "out",
  "package",
  "port",
  "postponed",
  "procedure",
  "process",
  "pure",
  "range",
  "record",
  "register",
  "reject",
  "rem",
  "report",
  "return",
  "rol",
  "ror",
  "select",
  "severity",
  "shared",
  "signal",
  "sla",
  "sll",
  "sra",
  "srl",
  "subtype",
  "then",
  "to",
  "transport",
  "type",
  "unaffected",
  "units",
  "until",
  "use",
  "variable",
  "wait",
  "when",
  "while",
  "with",
  "xnor",
  "xor",
}

--- Added by VHDL-2002.
M["2002"] = { "protected" }

--- Added by VHDL-2008. Mostly the PSL-derived verification directives, which
--- is why `cover`, `sequence` and `property` are suddenly illegal names for a
--- signal in a design that used to analyse fine under VHDL-93.
M["2008"] = {
  "assume",
  "assume_guarantee",
  "context",
  "cover",
  "default",
  "fairness",
  "force",
  "parameter",
  "property",
  "release",
  "restrict",
  "restrict_guarantee",
  "sequence",
  "strong",
  "vmode",
  "vprop",
  "vunit",
}

--- Added by VHDL-2019.
M["2019"] = { "private", "view" }

local cache = {}

--- Set of reserved words for a given standard, keyed lowercase.
---@param std string one of "93", "2002", "2008", "2019"
---@return table<string, true>
function M.set(std)
  if cache[std] then
    return cache[std]
  end
  local set = {}
  for _, w in ipairs(M.common) do
    set[w] = true
  end
  for _, rev in ipairs({ "2002", "2008", "2019" }) do
    if (tonumber(std) or 0) >= tonumber(rev) then
      for _, w in ipairs(M[rev]) do
        set[w] = true
      end
    end
  end
  cache[std] = set
  return set
end

--- VHDL identifiers are case insensitive, so the comparison is too.
---@param word string
---@param std string
---@return boolean
function M.is_reserved(word, std)
  return M.set(std or "2008")[word:lower()] == true
end

return M
