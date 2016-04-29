--[[
This file adds runtime type checks to tables in a Typed Lua AST using Tableshape

Types are tables:
- types.any      succeeds no matter what the type
- types.string   checks for type(val) == "string"
- types.number   checks for type(val) == "number"
- types.funcn    checks for type(val) == "function"
- types.function checks for type(val) == "function"
- types.boolean  checks for type(val) == "boolean"
- types.userdata checks for type(val) == "userdata"
- types.table    checks for type(val) == "table"
- types.nil      checks for type(val) == "nil"
- types.array    checks for table of numerically increasing indexes
- types.integer  checks for a number with no decimal component
Complex types can be built with these:
- one_of: Union
- shape: Table with the defined fields
- pattern: string that matches a pattern
- array_of: array with integer keys and values of a specified type
- map_of: dictionary of specified types for key and value
Types can be made optional with: t = t:is_optional()
]]

local tlvisitor = require "typedlua.tlvisitor"

local tlruntime_tableshape = setmetatable({}, { __index = tlvisitor })


function tlruntime_tableshape.add_runtime_checks (ast)
  assert(type(ast) == "table")
  assert(ast.tag == "Block")

  -- Add the runtime checks
  tlruntime_tableshape:visit(ast)
end


return tlruntime_tableshape
