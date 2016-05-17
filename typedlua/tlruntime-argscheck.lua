--[[
This file adds runtime type checks to function arguments and return values
in a Typed Lua AST using Typecheck's argscheck

Types are denoted by a string:
- Lua's primitive types
- stdlib's object types
- special options:
  - #table    any non-empty table
  - any       any non-nil argument type
  - callable  a function or a functor
  - file      an open file object
  - func      a function
  - functor   an object with a __call metamethod
  - int       an integer valued number
  - list      a table where all keys are a contiguous 1-based integer range
  - #list     any non-empty list
  - object    any std.Object derived type
  - :foo      only the exact string ":foo", works for any :-prefixed string
Optional values: ?type
Function: (t1, t2, ...) => t3, t4, ...
Union: t1 | t2
Return options: (t1) or (t2) or ...
]]

local tlast = require "typedlua.tlast"
local tltype = require "typedlua.tltype"
local tlvisitor = require "typedlua.tlvisitor"

--[[
local function dump_node(node, tag)
  tag = tag or ""
  print(tag, node.tag)
  for k,v in pairs(node) do
    print(tag, "-", k, v)
  end
end
--]]


-------------------------------------------------------------------------------
-- Types translation
-------------------------------------------------------------------------------

local argscheck_translation = setmetatable({}, { __index = tlvisitor })

--[[
function argscheck_translation:visit(node)
--dump_node(node)
print("NAVIGATING:",node.tag)
return tlvisitor.visit(self, node)
end
--]]

function argscheck_translation.translate_function_type(f, skip_self)
  assert(f.tag == "Function")
  local type_string = argscheck_translation:visit(f[1], skip_self)
  if #f == 3 then
    -- Have return type
    type_string = type_string .. " => " .. argscheck_translation:visit(f[2])
  end

  return type_string
end


-- List of parameters

function argscheck_translation:parameters_list(params, skip_self)
  local types = {}
  for k, node in ipairs(params) do
    if k == 1 and skip_self then
      assert(node.type.tag == "TSelf")
    else
      local _, t = self:visit(node)
      table.insert(types, t)
    end
  end
  return "(" .. table.concat(types, ", ") .. ")"
end

function argscheck_translation:Parlist(parlist, skip_self)
  return self:parameters_list(parlist, skip_self)
end

function argscheck_translation:NameList(namelist, skip_self)
  return self:parameters_list(namelist, skip_self)
end


-- Individual parameters: return name and type

function argscheck_translation:Id(node)
  return node[1], self:visit(node.type)
end

function argscheck_translation:Dots(t)
  local item_type = ""
  if t[1] then
    item_type = self:visit(t[1])
  end
  return nil, item_type .. "..."
end


-- Individual types

function argscheck_translation:TAny(t)
  return "any"
end

function argscheck_translation:TBase(t)
  if tltype.isInteger(t) then
    return "int"
  else
    -- primitive: nil, boolean, number, string, function, userdata, thread, and table
    return t.name
  end
end

function argscheck_translation:TFunction(t)
  return "function"
end

function argscheck_translation:TNil(t)
  return "nil"
end

function argscheck_translation:TSelf(t)
  return "self"
end

function argscheck_translation:TTable(t)
  if t.userdata then
    if t.userdata == "thread" then
      return "thread"
    else
      return "userdata"
    end
  elseif t.interface then
    -- TODO: use the interface name?
    return "table"
  else
    return "table"
  end
end

function argscheck_translation:TTuple(tuple)
  local types = {}
  for _, node in ipairs(tuple) do
    local t = self:visit(node)
    table.insert(types, t)
  end
  if #types == 1 then
    return types[1]
  else
    return "(" .. table.concat(types, ", ") .. ")"
  end
end

function argscheck_translation:TValue(t)
  return "any"
end

function argscheck_translation:TVararg(t)
  local item_type = ""
  if t[1] then
    if t[1].tag == "TNil" then
      return
    end
    item_type = self:visit(t[1])
  end
  return item_type .. "..."
end

function argscheck_translation:TVariable(t)
  local varname = t[1]
  -- TODO: handle custom tables?
  if varname == "thread" then
    return varname
  else
    return "table"
  end
end


-- Complex types

function argscheck_translation:TUnion(t)
  local has_nil = false
  local types = {}
  for _, v in ipairs(t) do
    if v.tag == "TNil" then
      has_nil = true
    else
      table.insert(types, self:visit(v))
    end
  end
  local type_string = table.concat(types, " | ")
  if has_nil then
    type_string = "?" .. type_string
  end
  return type_string
end

function argscheck_translation:TUnionlist(union)
  local types = {}
  for _, node in ipairs(union) do
    local t = self:visit(node)
    table.insert(types, t)
  end
  return table.concat(types, " or ")
end


-------------------------------------------------------------------------------
-- ID handling
-------------------------------------------------------------------------------

local function add_to_table(t, items)
  local items_type = type(items)
  if items_type == "table" then
    for _, item in ipairs(items) do
      table.insert(t, item)
    end
  elseif items_type == "string" then
    table.insert(t, items)
  else
    error("Invalid items type: " .. items_type)
  end
end

local function flatten_id_except_last(self)
  if #self.id_chain > 1 then
    local last = table.remove(self.id_chain)
    self.id_chain = { tostring(self) }
    table.insert(self.id_chain, last)
  end
end

local Id = {}
Id.__index = Id

function Id.new(base_id, child)
  local self = setmetatable({}, Id)

  self.id_chain = {}
  self.context_chain = {}
  if base_id then
    -- Copy the info from the base ID
    add_to_table(self.id_chain, base_id.id_chain)
    add_to_table(self.context_chain, base_id.context_chain)
  end

  if child then
    -- Fill the ID chain
    add_to_table(self.id_chain, child)
  end

  flatten_id_except_last(self)

  return self
end

function Id:flatten_id()
  if #self.id_chain == 0 then
    return "<anon>"
  else
    return table.concat(self.id_chain, ".")
  end
end

function Id:child(child_id)
  return Id.new(self, child_id)
end

function Id:child_context()
  local child = Id.new(self)
  if #self.id_chain > 0 then
    local last = child:flatten_id()
    child.id_chain = {}
    table.insert(child.context_chain, last)
  end
  return child
end

function Id:concat(str)
  self.id_chain = { self:flatten_id() .. str }
end

function Id:make_method()
  if #self.id_chain > 1 then
    local last = table.remove(self.id_chain)
    self:concat(":" .. last)
    return true
  else
    return false
  end
end

function Id:__tostring()
  local prefix = ""
  local suffix = ""
  for _, context in pairs(self.context_chain) do
    prefix = prefix .. context .. "."
    suffix = " in " .. context .. suffix
  end
  --f2.f2.t.f1
  --t in f2.f1 in f2
  return prefix .. self:flatten_id()
  --return self:flatten_id() .. suffix
end


-------------------------------------------------------------------------------
-- Function annotation and ID collection
-------------------------------------------------------------------------------

local tlruntime_argscheck = setmetatable({}, { __index = tlvisitor })

local function first_is_self(arg)
  assert(arg.tag == "TTuple")
  return #arg > 0 and arg[1].tag == "TSelf"
end

local function build_argscheck_call (type_string, function_def)
  -- argscheck("type_string") .. function_def
  return tlast.exprBinaryOp(
    tlast.call(nil,
      tlast.ident(nil, "argscheck"),
      tlast.exprString(nil, type_string)
    ),
    "concat", function_def
  )
end

function tlruntime_argscheck:function_declaration (f, id)
  local skip_self = false
  if first_is_self(f.type[1]) then
    skip_self = id:make_method()
  end

  local type_string = argscheck_translation.translate_function_type(f, skip_self)
  local spec_string = tostring(id) .. " " .. type_string

  --local apply_argscheck = true
  --if apply_argscheck then
    self.uses_argscheck = true
    return build_argscheck_call(spec_string, f)
  --end
end

function tlruntime_argscheck:Function (f, id)
  tlvisitor.Function(self, f, id)

  return self:function_declaration(f, id)
end

function tlruntime_argscheck:Localrec (f, parent_id)
  local context_id = parent_id:child_context()
  local _, my_id = self:Variable(f[1][1], context_id)

  tlvisitor.Localrec(self, f, my_id)

  local checked_function = self:function_declaration(f[2][1], my_id)
  if checked_function then
    -- Transform "local function fname()" into "local fname = function()"
    return tlast.statLocal(nil, f[1],
      --[[
      tlast.namelist(nil,
        tlast.ident(nil, "argscheck")
      ),
      --]]
      tlast.explist(nil, checked_function)
    )
  end
end

function tlruntime_argscheck:Index (var, parent_id)
  if var[1].tag == "Id" and var[1][1] == "_ENV" and var[2].tag == "String" then
    local v = { tag = "Id", [1] = var[2][1] }
    return self:Expression(v, parent_id)
  end

  --local empty_id = Id.new()
  --[[
  local context_id = parent_id:child_context()
  local container_id = self:Expression(var[1], context_id)
  --]]
  local _, container_id = self:Expression(var[1], parent_id)
  local _, my_id = self:Expression(var[2], container_id)
  local item_id = container_id:child(my_id)
--f2.f2.t.f1
--[[
print("INDEX")
print("- parent:", parent_id)
print("- container:", container_id)
print("- my_id:", my_id)
print("- item_id:", item_id)
--]]

  tlvisitor.Index(self, var, item_id)
  return nil, item_id
end

function tlruntime_argscheck:Id (id, parent_id)
  --[[
  local context_id = parent_id:child_context()
  local item_id = context_id:child(id[1])
  --]]
  local item_id = parent_id:child(id[1])
  tlvisitor.Id(self, id, item_id)
  return nil, item_id
end

function tlruntime_argscheck:String (s)
  return nil, s[1]
end


-------------------------------------------------------------------------------
-- Containers: distribute IDs and apply node replacements
-------------------------------------------------------------------------------

function tlruntime_argscheck:Block (block, parent_id)
  for k, stm in ipairs(block) do
    local replacement = self:Statement(stm, parent_id)
    if replacement then
      block[k] = replacement
    end
  end
end

function tlruntime_argscheck:ExpList (explist, child_ids)
  for k, exp in ipairs(explist) do
    local child_id = child_ids[k]
    if child_ids.id_chain then
      child_id = child_ids:child()
      child_id:concat(".<anon>")
    end

    local replacement = self:Expression(exp, child_id)
    if replacement then
      explist[k] = replacement
    end
  end
end

function tlruntime_argscheck:Varlist (varlist, parent_id)
  local l = {}
  for k, var in ipairs(varlist) do
    local _, result = self:Variable(var, parent_id)
    l[k] = result
  end
  return nil, l
end

function tlruntime_argscheck:Local (stm, parent_id)
  local context_id = parent_id:child_context()
  local _, child_ids = self:Varlist(stm[1], context_id)
  if #stm[2] > 0 then
    self:ExpList(stm[2], child_ids)
  end
end

function tlruntime_argscheck:Set (set, parent_id)
  local context_id = parent_id:child_context()
  local _, child_ids = self:Varlist(set[1], context_id)
  self:ExpList(set[2], child_ids)
end

function tlruntime_argscheck:Table (fieldlist, table_id)
  local unkeyed_index = 1
  for k, v in ipairs(fieldlist) do
    if v.tag == "Pair" then
      local _, my_id = self:Expression(v[1])
      local item_id = table_id:child(my_id)
      local replacement = self:Expression(v[2], item_id)
      if replacement then
        v[2] = replacement
      end
    else
      local item_id = table_id:child()
      item_id:concat("["  .. tostring(unkeyed_index) .. "]")
      unkeyed_index = unkeyed_index + 1
      local replacement = self:Expression(v, item_id)
      if replacement then
        fieldlist[k] = replacement
      end
    end
  end
end

-------------------------------------------------------------------------------

local function build_argscheck_require ()
  -- require("typecheck").argscheck
  local expr = tlast.index(nil,
    tlast.call(nil,
      tlast.ident(nil, "require"),
      tlast.exprString(nil, "typecheck")
    ),
    tlast.exprString(nil, "argscheck")
  )

  -- local argscheck = expr
  return tlast.statLocal(nil,
    tlast.namelist(nil,
      tlast.ident(nil, "argscheck")
    ),
    tlast.explist(nil, expr)
  )
end

function tlruntime_argscheck.add_runtime_checks (ast)
  assert(type(ast) == "table")
  assert(ast.tag == "Block")

  -- Initialize
  tlruntime_argscheck.uses_argscheck = false

  -- Add the runtime checks
  local root_id = Id.new()
  tlruntime_argscheck:visit(ast, root_id)

  -- Require argscheck
  if tlruntime_argscheck.uses_argscheck and #ast > 0 then
    --[[
    if ast[1].l then
      -- Separate it from the new require statement
      ast[1].l = ast[1].l + 1
    end
    --]]
    table.insert(ast, 1, build_argscheck_require())
    ast[1].l = 1
  end
end


return tlruntime_argscheck
