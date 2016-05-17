--[[
This file implements the code generator for Typed Lua
]]

local tlvisitor = require "typedlua.tlvisitor"
local tlcode = setmetatable({}, { __index = tlvisitor })

local function spaces (fmt)
  return string.rep(" ", 2 * fmt.indent)
end

local function indent (s, fmt)
  return spaces(fmt) .. s
end

local function iscntrl (x)
  if (x >= 0 and x <= 31) or (x == 127) then return true end
  return false
end

local function isprint (x)
  return not iscntrl(x)
end

local function fix_str (str)
  local new_str = ""
  for i=1,string.len(str) do
    local char = string.byte(str, i)
    if char == 34 then new_str = new_str .. string.format("\\\"")
    elseif char == 92 then new_str = new_str .. string.format("\\\\")
    elseif char == 7 then new_str = new_str .. string.format("\\a")
    elseif char == 8 then new_str = new_str .. string.format("\\b")
    elseif char == 12 then new_str = new_str .. string.format("\\f")
    elseif char == 10 then new_str = new_str .. string.format("\\n")
    elseif char == 13 then new_str = new_str .. string.format("\\r")
    elseif char == 9 then new_str = new_str .. string.format("\\t")
    elseif char == 11 then new_str = new_str .. string.format("\\v")
    else
      if isprint(char) then
        new_str = new_str .. string.format("%c", char)
      else
        new_str = new_str .. string.format("\\%03d", char)
      end
    end
  end
  return new_str
end

local function is_simple_key (key)
  return key.tag == "String" and key[1]:match("^[a-zA-Z_][a-zA-Z0-9_]*$")
end

local function resync_line(node, fmt, out)
  while node.l > fmt.line do
    table.insert(out, "\n")
    fmt.line = fmt.line + 1
  end
end

local op = { add = " + ",
             sub = " - ",
             mul = " * ",
             idiv = " // ",
             div = " / ",
             mod = " % ",
             pow = " ^ ",
             concat = " .. ",
             eq = " == ",
             lt = " < ",
             le = " <= ",
             bor = "|",
             bxor = "~",
             band = "&",
             shl = "<<",
             shr = ">>",
             ["and"] = " and ",
             ["or"] = " or ",
             ["not"] = "not ",
             unm = "-",
             bnot = "~",
             len = "#" }


function tlcode:BinaryOp (exp, fmt)
  local str = ""
  if _VERSION == "Lua 5.3" then
    if exp[2].tag == "Call" and exp[2][1].tag == "Index" and
       exp[2][1][1].tag == "Id" and exp[2][1][1][1] == "_ENV" and
       exp[2][1][2].tag == "String" and exp[2][1][2][1] == "type" and
       exp[3].tag == "String" and exp[3][1] == "integer" then
      str = "math."
    end
  end
  return str .. self:Expression(exp[2], fmt) .. op[exp[1]] .. self:Expression(exp[3], fmt)
end

function tlcode:Block (block, fmt)
  local l = {}
  local firstline = fmt.line
  local saveindent = fmt.indent
  if block[1] and block[1].l and block[1].l > firstline then
    fmt.indent = fmt.indent + 1
  else
    fmt.indent = 0
  end
  for _, v in ipairs(block) do
    if v.l then
      resync_line(v, fmt, l)
    else
      table.insert(l, "\n")
    end
    table.insert(l, self:Statement(v, fmt))
  end
  if fmt.line ~= firstline then
    table.insert(l, "\n")
    fmt.line = fmt.line + 1
  else
    table.insert(l, " ")
  end
  fmt.indent = saveindent
  return table.concat(l)
end

function tlcode:Break (stm, fmt)
  return indent("break", fmt)
end

function tlcode:Call (call, fmt)
  local l = {}
  for k = 2, #call do
    l[k - 1] = self:Expression(call[k], fmt)
  end
  return self:Expression(call[1], fmt) .. "(" .. table.concat(l, ",") .. ")"
end

function tlcode:CallStatement (call, fmt)
  return indent(self:Call(call, fmt), fmt)
end

function tlcode:Do (stm, fmt)
  return indent("do ", fmt) .. self:Block(stm, fmt) .. indent("end", fmt)
end

function tlcode:Dots (exp, fmt)
  return "..."
end

function tlcode:ExpList (explist, fmt)
  local l = tlvisitor.ExpList(self, explist, fmt)
  return table.concat(l, ", ")
end

function tlcode:False (exp, fmt)
  return "false"
end

function tlcode:Forin (stm, fmt)
  local str = indent("for ", fmt)
  str = str .. self:Varlist(stm[1], fmt) .. " in "
  str = str .. self:ExpList(stm[2], fmt) .. " do "
  str = str .. self:Block(stm[3], fmt)
  str = str .. indent("end", fmt)
  return str
end

function tlcode:Fornum (stm, fmt)
  local str = indent("for ", fmt)
  str = str .. self:Variable(stm[1], fmt) .. " = " .. self:Expression(stm[2], fmt)
  str = str .. ", " .. self:Expression(stm[3], fmt)
  if stm[5] then
    str = str .. ", " .. self:Expression(stm[4], fmt) .. " do "
    str = str .. tlcode:Block(stm[5], fmt)
  else
    str = str .. " do " .. self:Block(stm[4], fmt)
  end
  str = str .. indent("end", fmt)
  return str
end

function tlcode:Function (exp, fmt)
  local str = "function ("
  str = str .. self:Parlist(exp[1], fmt) .. ") "
  if not exp[3] then
    str = str .. self:Block(exp[2], fmt) .. indent("end", fmt)
  else
    str = str .. self:Block(exp[3], fmt) .. indent("end", fmt)
  end
  return str
end

function tlcode:Goto (stm, fmt)
  return indent("goto ", fmt) .. stm[1]
end

function tlcode:Id (var, fmt)
  return var[1]
end

function tlcode:If (stm, fmt)
  local str = indent("if ", fmt) .. self:Expression(stm[1], 0) .. " then "
  str = str .. self:Block(stm[2], fmt)
  local len = #stm
  if len % 2 == 0 then
    for k=3, len, 2 do
      str = str .. indent("elseif ", fmt) .. self:Expression(stm[k], 0) .. " then "
      str = str .. self:Block(stm[k+1], fmt)
    end
  else
    for k=3, len-1, 2 do
      str = str .. indent("elseif ", fmt) .. self:Expression(stm[k], 0) .. " then "
      str = str .. self:Block(stm[k+1], fmt)
    end
    str = str .. indent("else ", fmt)
    str = str .. self:Block(stm[len], fmt)
  end
  str = str .. indent("end", fmt)
  return str
end

function tlcode:Index (var, fmt)
  if var[1].tag == "Id" and var[1][1] == "_ENV" and var[2].tag == "String" then
    local v = { tag = "Id", [1] = var[2][1] }
    return self:Expression(v, fmt)
  else
    if is_simple_key(var[2]) then
      return self:Expression(var[1], fmt) .. "." .. var[2][1]
    else
      return self:Expression(var[1], fmt) .. "[" .. self:Expression(var[2], fmt) .. "]"
    end
  end
end

function tlcode:Interface (stm, fmt)
  return ""
end

function tlcode:Invoke (invoke, fmt)
  local l = {}
  for k = 3, #invoke do
    l[k - 2] = self:Expression(invoke[k], fmt)
  end
  local str = self:Expression(invoke[1], fmt)
  str = str .. ":" .. invoke[2][1]
  str = str .. "(" .. table.concat(l, ",") .. ")"
  return str
end

function tlcode:InvokeStatement (stm, fmt)
  return indent(self:Invoke(stm, fmt), fmt)
end

function tlcode:Label (stm, fmt)
  return indent("::", fmt) .. stm[1] .. "::"
end

function tlcode:Local (stm, fmt)
  local str = indent("local ", fmt) .. self:Varlist(stm[1], fmt)
  if #stm[2] > 0 then
    str = str .. " = " .. self:ExpList(stm[2], fmt)
  end
  return str
end

function tlcode:Localrec (stm, fmt)
  local str = indent("local function ", fmt) .. self:Variable(stm[1][1], fmt)
  str = str .. " (" .. self:Parlist(stm[2][1][1], fmt) .. ") "
  if not stm[2][1][3] then
    str = str .. self:Block(stm[2][1][2], fmt) .. indent("end", fmt)
  else
    str = str .. self:Block(stm[2][1][3], fmt) .. indent("end", fmt)
  end
  return str
end

function tlcode:Nil (exp, fmt)
  return "nil"
end

function tlcode:Number (exp, fmt)
  return tostring(exp[1])
end

function tlcode:Paren (exp, fmt)
  return "(" .. self:Expression(exp[1], fmt) .. ")"
end

function tlcode:Parlist (parlist, fmt)
  local l = {}
  local len = #parlist
  local is_vararg = false
  if len > 0 and parlist[len].tag == "Dots" then
    is_vararg = true
    len = len - 1
  end
  for k=1, len do
    l[k] = self:Variable(parlist[k], fmt)
  end
  if is_vararg then
    table.insert(l, "...")
  end
  return table.concat(l, ", ")
end

function tlcode:Repeat (stm, fmt)
  local str = indent("repeat ", fmt)
  str = str .. self:Block(stm[1], fmt)
  str = str .. indent("until ", fmt)
  str = str .. self:Expression(stm[2], fmt)
  return str
end

function tlcode:Return (stm, fmt)
  return indent("return ", fmt) .. self:ExpList(stm, fmt)
end

function tlcode:Set (stm, fmt)
  return spaces(fmt) .. self:Varlist(stm[1], fmt) .. " = " .. self:ExpList(stm[2], fmt)
end

function tlcode:String (exp, fmt)
  return '"' .. fix_str(exp[1]) .. '"'
end

function tlcode:Table (fieldlist, fmt)
  local l = {}
  for k, v in ipairs(fieldlist) do
    if v.tag == "Pair" then
      if is_simple_key(v[1]) then
        l[k] = v[1][1] .. " = " .. self:Expression(v[2], fmt)
      else
        l[k] = "[" .. self:Expression(v[1], fmt) .. "] = " .. self:Expression(v[2], fmt)
      end
    else
      l[k] = self:Expression(v, fmt)
    end
  end
  return "{" .. table.concat(l, ", ") .. "}"
end

function tlcode:True (exp, fmt)
  return "true"
end

function tlcode:UnaryOp (exp, fmt)
  return op[exp[1]] .. "(" .. self:Expression(exp[2], fmt) .. ")"
end

function tlcode:Varlist (varlist, fmt)
  local l = tlvisitor.Varlist(self, varlist, fmt)
  return table.concat(l, ", ")
end

function tlcode:While (stm, fmt)
  local str = indent("while ", fmt) .. self:Expression(stm[1], 0) .. " do "
  str = str .. self:Block(stm[2], fmt) .. indent("end", fmt)
  return str
end


function tlcode.generate (ast)
  assert(type(ast) == "table")
  local fmt = { line = 1, indent = -1 }
  return tlcode:visit(ast, fmt) .. "\n"
end

return tlcode
