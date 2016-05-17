--[[
This file implements a visitor for the Typed Lua AST
]]

local default_visitor = {}


---------------------------------------------------------------------------------------------------
-- Common
---------------------------------------------------------------------------------------------------

function default_visitor:visit (node, ...)
  local tag = node.tag
  if tag then
    local method = self[tag]
    if method then
      return method(self, node, ...)
    else
      error("the visitor doesn't know how to visit " .. tag)
    end
  --[[
  else
    -- Fallback: visit all subnodes
    for _, child in pairs(node) do
      if type(child) == "table" then
        self:visit(child, ...)
      end
    end
  --]]
  end
end


---------------------------------------------------------------------------------------------------
-- Nodes
---------------------------------------------------------------------------------------------------

function default_visitor:BinaryOp (exp, ...)
  self:Expression(exp[2], ...)
  self:Expression(exp[3], ...)
end

-- block: { stat* }
function default_visitor:Block (block, ...)
  for _, stm in ipairs(block) do
    self:Statement(stm, ...)
  end
end

-- Break                                    -- break
function default_visitor:Break () -- stm, ...
end

-- Call{ expr expr* }
function default_visitor:Call (call, ...)
  self:Expression(call[1], ...)
  for k = 2, #call do
    self:Expression(call[k], ...)
  end
end

function default_visitor:CallExpression (exp, ...)
  return self:Call(exp, ...)
end

function default_visitor:CallStatement (stm, ...)
  return self:Call(stm, ...)
end

-- Do{ stat* }
function default_visitor:Do (stm, ...)
  return self:Block(stm, ...)
end

-- Dots
function default_visitor:Dots () -- exp, ...
end

function default_visitor:ExpList (explist, ...)
  local l = {}
  for k, exp in ipairs(explist) do
    l[k] = self:Expression(exp, ...)
  end
  return l
end

function default_visitor:Expression (exp, ...)
  local tag = exp.tag
  if tag == "Id" or tag == "Index" then
    return self:Variable(exp, ...)
  elseif tag == "Call" then
    return self:CallExpression(exp, ...)
  elseif tag == "Invoke" then
    return self:InvokeExpression(exp, ...)
  elseif tag == "Dots"
    or tag == "False"
    or tag == "Function"
    or tag == "Nil"
    or tag == "Number"
    or tag == "Op"
    or tag == "Paren"
    or tag == "String"
    or tag == "Table"
    or tag == "True" then

    return self:visit(exp, ...)
  else
    error("tyring to visit an expression, but got " .. tag)
  end
end

-- False
function default_visitor:False () -- exp, ...
end

-- Forin{ {ident+} {expr+} block }          -- for i1, i2... in e1, e2... do b end
function default_visitor:Forin (stm, ...)
  self:Varlist(stm[1], ...)
  self:ExpList(stm[2], ...)
  self:Block(stm[3], ...)
end

-- Fornum{ ident expr expr expr? block }    -- for ident = e, e[, e] do b end
function default_visitor:Fornum (stm, ...)
  self:Variable(stm[1], ...)
  self:Expression(stm[2], ...)
  self:Expression(stm[3], ...)
  if stm[5] then
    self:Expression(stm[4], ...)
    self:Block(stm[5], ...)
  else
    self:Block(stm[4], ...)
  end
end

-- Function{ { ident* { `Dots type? }? } typelist? block }
function default_visitor:Function (exp, ...)
  self:Parlist(exp[1], ...)
  if not exp[3] then
    self:Block(exp[2], ...)
  else
    self:Block(exp[3], ...)
  end
end

-- Goto{ <string> }                         -- goto str
function default_visitor:Goto () -- stm, ...
end

-- Id{ <string> type? }
function default_visitor:Id () -- var, ...
end

-- If{ (expr block)+ block? }               -- if e1 then b1 [elseif e2 then b2] ... [else bn] end
function default_visitor:If (stm, ...)
  self:Expression(stm[1], ...)
  self:Block(stm[2], ...)

  local len = #stm
  if len % 2 == 0 then
    for k=3, len, 2 do
      self:Expression(stm[k], ...)
      self:Block(stm[k+1], ...)
    end
  else
    for k=3, len-1, 2 do
      self:Expression(stm[k], ...)
      self:Block(stm[k+1], ...)
    end
    self:Block(stm[len], ...)
  end
end

-- Index{ expr expr }
function default_visitor:Index (var, ...)
  if var[1].tag == "Id" and var[1][1] == "_ENV" and var[2].tag == "String" then
    local v = { tag = "Id", [1] = var[2][1] }
    self:Expression(v, ...)
  else
    self:Expression(var[1], ...) -- obj
    self:Expression(var[2], ...) -- field
  end
end

-- Interface{ <string> type }
function default_visitor:Interface () -- stm, ...
end

-- Invoke{ expr `String{ <string> } expr* }
function default_visitor:Invoke (invoke, ...)
  self:Expression(invoke[1], ...)
  --invoke[2][1] -- method name
  for k = 3, #invoke do
    self:Expression(invoke[k], ...)
  end
end

function default_visitor:InvokeExpression (exp, ...)
  return self:Invoke(exp, ...)
end

function default_visitor:InvokeStatement (stm, ...)
  return self:Invoke(stm, ...)
end

-- Label{ <string> }                        -- ::str::
function default_visitor:Label () -- stm, ...
end

-- Local{ {ident+} {expr+}? }               -- local i1, i2... = e1, e2...
function default_visitor:Local (stm, ...)
  self:Varlist(stm[1], ...)
  if #stm[2] > 0 then
    self:ExpList(stm[2], ...)
  end
end

-- Localrec{ ident expr }                   -- only used for 'local function'
function default_visitor:Localrec (stm, ...)
  self:Variable(stm[1][1], ...)
  self:Parlist(stm[2][1][1], ...)
  if not stm[2][1][3] then
    self:Block(stm[2][1][2], ...)
  else
    self:Block(stm[2][1][3], ...)
  end
end

function default_visitor:NameList () -- list, ...
  -- TODO
end

-- Nil
function default_visitor:Nil () -- exp, ...
end

-- Number{ <number> }
function default_visitor:Number () -- exp, ...
end

-- Op{ opid expr expr? }
function default_visitor:Op (exp, ...)
  if exp[3] then
    return self:BinaryOp(exp, ...)
  else
    return self:UnaryOp(exp, ...)
  end
end

-- Paren{ expr }       -- significant to cut multiple values returns
function default_visitor:Paren (exp, ...)
  return self:Expression(exp[1], ...)
end

function default_visitor:Parlist (parlist, ...)
  local len = #parlist
  for k=1, len do
    self:Variable(parlist[k], ...)
  end
end

-- Repeat{ block expr }                     -- repeat b until e
function default_visitor:Repeat (stm, ...)
  self:Block(stm[1], ...)
  self:Expression(stm[2], ...)
end

-- Return{ <expr*> }                        -- return e1, e2...
function default_visitor:Return (stm, ...)
  return self:ExpList(stm, ...)
end

-- Set{ {lhs+} {expr+} }                    -- lhs1, lhs2... = e1, e2...
function default_visitor:Set (stm, ...)
  self:Varlist(stm[1], ...)
  self:ExpList(stm[2], ...)
end

function default_visitor:Statement (stm, ...)
  local tag = stm.tag
  if tag == "Call" then
    return self:CallStatement(stm, ...)
  elseif tag == "Invoke" then
    return self:InvokeStatement(stm, ...)
  elseif tag == "Break"
    or tag == "Do"
    or tag == "Forin"
    or tag == "Fornum"
    or tag == "Goto"
    or tag == "If"
    or tag == "Interface"
    or tag == "Label"
    or tag == "Local"
    or tag == "Localrec"
    or tag == "Repeat"
    or tag == "Return"
    or tag == "Set"
    or tag == "While" then

    return self:visit(stm, ...)
  else
    error("tyring to visit a statement, but got " .. tag)
  end
end

-- String{ <string> }
function default_visitor:String () -- exp, ...
end

-- Table{ ( `Pair{ expr expr } | expr )* }
function default_visitor:Table (fieldlist, ...)
  for _, v in ipairs(fieldlist) do
    if v.tag == "Pair" then
      self:Expression(v[1], ...) -- field
      self:Expression(v[2], ...) -- value
    else
      self:Expression(v, ...)
    end
  end
end

-- True
function default_visitor:True () -- exp, ...
end

function default_visitor:UnaryOp (exp, ...)
  return self:Expression(exp[2], ...)
end

function default_visitor:Variable (var, ...)
  local tag = var.tag
  if tag == "Dots"
    or tag == "Id"
    or tag == "Index" then
    return self:visit(var, ...)
  else
    error("tyring to visit a variable, but got " .. tag)
  end
end

function default_visitor:Varlist (varlist, ...)
  local l = {}
  for k, var in ipairs(varlist) do
    l[k] = self:Variable(var, ...)
  end
  return l
end

-- While{ expr block }                      -- while e do b end
function default_visitor:While (stm, ...)
  self:Expression(stm[1], ...)
  self:Block(stm[2], ...)
end


---------------------------------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------------------------------

-- TAny
function default_visitor:TAny () -- t, ...
end

-- TBase{ 'boolean' | 'number' | 'string' }
function default_visitor:TBase () -- t, ...
end

-- TODO
function default_visitor:TField () -- t, ...
end

-- TFunction{ type type }
function default_visitor:TFunction () -- t, ...
end

-- TLiteral{ false | true | <number> | <string> }
function default_visitor:TLiteral () -- t, ...
end

-- TNil
function default_visitor:TNil () -- t, ...
end

-- TODO
-- TRecursive{ <string> type }

-- TSelf
function default_visitor:TSelf () -- t, ...
end

-- TTable{ type type* }
function default_visitor:TTable () -- t, ...
end

-- TTuple{ type type* }
function default_visitor:TTuple () -- t, ...
end

-- TUnion{ type type type* }
function default_visitor:TUnion () -- t, ...
end

-- TUnionlist{ type type type* }
function default_visitor:TUnionlist () -- t, ...
end

-- TValue
function default_visitor:TValue () -- t, ...
end

-- TVararg{ type }
function default_visitor:TVararg () -- t, ...
end

-- TVariable{ <string> }
function default_visitor:TVariable () -- t, ...
end

-- TVoid
function default_visitor:TVoid () -- t, ...
end


return default_visitor
