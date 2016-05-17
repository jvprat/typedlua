--[[
This file adds runtime type checks to a Typed Lua AST
- Function arguments and return values are checked using Typecheck
- Tables are checked using Tableshape
]]

local tlruntime_argscheck  = require "typedlua.tlruntime-argscheck"
local tlruntime_tableshape = require "typedlua.tlruntime-tableshape"
local tlruntime = {}


function tlruntime.add_runtime_checks (ast)
  tlruntime_argscheck.add_runtime_checks(ast)
  tlruntime_tableshape.add_runtime_checks(ast)
end


return tlruntime
