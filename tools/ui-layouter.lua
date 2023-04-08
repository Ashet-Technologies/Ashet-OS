--
local in_file_name = nil
if #arg > 0 then
  in_file_name = arg[1]
end

local out_file_name = nil
if #arg > 1 then
  out_file_name = arg[2]
end

-- io.stderr:write("Hello, World!\n")
-- for i = 1, #arg do
-- io.stderr:write(tostring(i), ": ", arg[i], "\n")
-- end

if not in_file_name then
  error("usage: ui-layouter.lua <input file> [<output file>]")
end

-- io.stderr:write("read file:        ", tostring(in_file_name), "\n")
-- io.stderr:write("generate file to: ", tostring(out_file_name), "\n")

function isNumber(x)
  return type(x) == "number"
end

do
  local arithmetic_mt = {}

  local VALUE = {}
  local EXPRESSION = {}

  function isValue(x)
    return (getmetatable(x) == VALUE)
  end

  function isExpression(x)
    return (getmetatable(x) == EXPRESSION)
  end

  function isSemanticValue(v)
    return isValue(v) or isExpression(v) or isNumber(v)
  end

  function Value(owner, name, initial)
    local v = { owner = assert(owner), name = assert(tostring(name)), initial = initial }
    setmetatable(v, VALUE)
    return v
  end

  local function performArithmetic(op, a, b)
    assert(isSemanticValue(a), "arithmetic requires number or semantic value")
    assert(isSemanticValue(b), "arithmetic requires number or semantic value")
    local expr = { type = "binary", op = op, lhs = a, rhs = b }
    setmetatable(expr, EXPRESSION)
    return expr
  end

  local function performUnaryArithmetic(op, a)
    assert(isValue(a) or isNumber(a), "arithmetic requires number or semantic value")
    local expr = { type = "unary", op = op, value = a }
    setmetatable(expr, EXPRESSION)
    return expr
  end

  function arithmetic_mt.__add(a, b)
    return performArithmetic("+", a, b)
  end
  function arithmetic_mt.__mul(a, b)
    return performArithmetic("*", a, b)
  end
  function arithmetic_mt.__div(a, b)
    return performArithmetic("/", a, b)
  end
  function arithmetic_mt.__sub(a, b)
    return performArithmetic("-", a, b)
  end
  function arithmetic_mt.__mod(a, b)
    return performArithmetic("%", a, b)
  end
  function arithmetic_mt.__unm(v)
    return performUnaryArithmetic("-", v)
  end
  function arithmetic_mt.__tostring(v)
    if isExpression(v) then
      if v.type == "binary" then
        return tostring(v.lhs) .. " " .. v.op .. " " .. tostring(v.rhs)
      elseif v.type == "unary" then
        return tostring(v.op) .. " " .. tostring(v.value)
      end
    elseif isValue(v) then
      return v.owner.name .. "." .. v.name
    else
      assert(false)
    end

  end

  for k, v in pairs(arithmetic_mt) do
    VALUE[k] = v
    EXPRESSION[k] = v
  end
end

function ownerSet(value, set)
  local function ownerSetInner(value, set)
    assert(isSemanticValue(value))
    if isValue(value) then
      set[value.owner] = true
    elseif isNumber(value) then
      -- pass
    elseif isExpression(value) then
      if value.type == "binary" then
        ownerSetInner(value.lhs, set)
        ownerSetInner(value.rhs, set)
      elseif value.type == "unary" then
        ownerSetInner(value.value, set)
      else
        assert(value.type .. " is not a supported op type")
      end
    end
  end
  local set = {}
  ownerSetInner(value, set)
  return set
end

function valueSet(value, set)
  local function valueSetInner(value, set)
    assert(isSemanticValue(value))
    if isValue(value) then
      set[value] = true
    elseif isNumber(value) then
      -- pass
    elseif isExpression(value) then
      if value.type == "binary" then
        valueSetInner(value.lhs, set)
        valueSetInner(value.rhs, set)
      elseif value.type == "unary" then
        valueSetInner(value.value, set)
      else
        assert(value.type .. " is not a supported op type")
      end
    end
  end
  local set = {}
  if value ~= nil then
    valueSetInner(value, set)
  end
  return set
end

local named_objects = {}
local all_objects = {}

do
  local legal_keys = { left = "h", right = "h", width = "h", top = "v", bottom = "v", height = "v" }

  local other_two_options = {
    h = { left = { "right", "width" }, width = { "left", "right" }, right = { "width", "left" } },
    v = { top = { "bottom", "height" }, bottom = { "top", "height" }, height = { "top", "bottom" } },
  }

  local index_counter = 0

  function LayoutObject(defaults, properties)
    for k, v in pairs(defaults) do
      assert(legal_keys[k], k .. " is not a legal key value for defaults.")
      assert(type(v) == "number", "default value for " .. k .. " must be a number!")
    end

    local o = { props = properties, number = index_counter - 1 }

    if properties.name then
      assert(#properties.name > 0, "Names must be non-empty!")
      assert(named_objects[properties.name] == nil, "An object with the name " .. properties.name .. " already exists!")
      o.name = properties.name
    else
      o.name = string.format("Object[%d]", o.number)
    end

    local mt = {
      refs = {
        left = Value(o, "left"),
        right = Value(o, "right"),
        width = Value(o, "width"),
        top = Value(o, "top"),
        bottom = Value(o, "bottom"),
        height = Value(o, "height"),
      },
      values = {},
      defaults = defaults,
    }
    o.__internal = mt

    function mt.__index(obj, key)
      assert(obj == o)
      if legal_keys[key] then
        return mt.refs[key]
      else
        error("illegal object property for object " .. obj.name .. ": " .. key)
      end
    end

    function mt.__newindex(obj, key, value)
      assert(obj == o)
      local group = legal_keys[key]
      if group then
        if value == nil then
          error("cannot pass nil value to property " .. key, 2)
        end
        if not isSemanticValue(value) then
          error("must pass semantic value (property, expression or number) to property " .. key, 2)
        end

        if ownerSet(value)[o] then
          error("a property cannot be self-referential", 2)
        end

        local others = other_two_options[group][key]

        local count = 0
        for _, other in ipairs(others) do
          if mt.values[other] then
            count = count + 1
          end
        end

        if count >= 2 then
          error(string.format("'%s' cannot be set when '%s' and '%s' are already set.", key, others[1], others[2]), 2)
        end

        mt.values[key] = value
      else
        error("illegal object property for object " .. obj.name .. ": " .. key)
      end
    end

    function mt.__tostring(obj)
      assert(obj == o)
      return string.format("%s", obj.name)
    end

    setmetatable(o, mt)
    index_counter = index_counter + 1
    table.insert(all_objects, o)
    if properties.name then
      named_objects[properties.name] = o
    end
    return o
  end

  window = LayoutObject({}, { name = "$window" })

  assert(named_objects["$window"] == window)
  named_objects["$window"] = nil

end

all_icons = {}

do
  local function appendIcon(path)
    local name = path:match("[%w-_]+")

    table.insert(all_icons, { name = name, file = path })

    return name
  end

  function Panel(props)
    props.class_init = "gui.Panel.new(5, 5, 172, 57)"
    return LayoutObject({}, props)
  end

  function ToolButton(props)
    props.class_init = string.format("gui.ToolButton.new(69, 42, icons.%s)", appendIcon(props.icon))
    return LayoutObject({ width = 12, height = 12 }, props)
  end

  function ScrollBar(props)
    props.class_init = string.format("gui.ScrollBar.new(0, 0, .%s, 100, %d)", props.dir, props.range)
    return LayoutObject({ width = 12, height = 12 }, props)
  end
end

-- lib code ↑
-- app code ↓

dofile(in_file_name)

---- 
-- postprocessing:

local resolution_order = {}

local open_set = {}

local closed_set = {}
closed_set[window] = true

for i = 1, #all_objects do
  local obj = all_objects[i]
  local int = obj.__internal

  -- print(i, obj, obj.name, int)

  local vals = {}
  local keys = { "left", "right", "width", "top", "bottom", "height" }

  for j = 1, #keys do
    local k = keys[j]
    local v = int.values[k]
    local prop = int.refs[k]

    local element = { property = prop, object = obj, internal = int }
    if v or k == "bottom" or k == "right" then
      local deps = valueSet(v)

      if k == "bottom" then
        deps[int.refs.top] = true
        deps[int.refs.height] = true
      end
      if k == "right" then
        deps[int.refs.left] = true
        deps[int.refs.width] = true
      end

      -- local d = ""
      -- for o in pairs(deps) do
      --   d = d .. ", " .. tostring(o)
      -- end

      element.value = v
      element.dependencies = deps

      table.insert(open_set, element)

      -- print("", "", k, v, d)
    else
      -- table.insert(resolution_order, element)
      closed_set[prop] = true
    end
  end
  -- print("")

end

while #open_set > 0 do

  local start_size = #open_set
  print("loop run", start_size)

  local i = 1
  while i <= #open_set do
    local prop = open_set[i]
    local obj = prop.object
    local val = prop.property
    local int = prop.internal
    local deps = prop.dependencies

    local all_deps = true
    for dep in pairs(deps) do
      -- print("testing", dep, closed_set[dep])
      if not closed_set[dep] then
        -- print(val, "is missing dependency", dep)
        all_deps = false
        break
      end
    end

    if all_deps then
      -- print(val, "has all dependencies resolved")
      closed_set[val] = true

      table.insert(resolution_order, prop)
      table.remove(open_set, i)
    else
      i = i + 1
    end

  end

  if start_size == #open_set then
    error("Dependency loop detected. Please resolve.")
  end

end

-- Remove $window from all_objects
assert(all_objects[1] == window)
table.remove(all_objects, 1)

---- 
-- rendering:

do
  local f = io.stdout
  if out_file_name then
    f = io.open(out_file_name, "wb")
  end

  f:write("//! THIS IS AUTOGENERATED CODE!\n")
  f:write("\n")
  f:write("const std = @import(\"std\");\n")
  f:write("const ashet = @import(\"ashet\");\n")
  f:write("const gui = @import(\"ashet-gui\");\n")
  f:write("const system_assets = @import(\"system-assets\");\n")
  f:write("const Window = ashet.abi.Window;\n");
  f:write("const Widget = gui.Widget;\n");
  f:write("const Interface = gui.Interface;\n");
  f:write("\n")
  f:write("const icons = struct {\n")
  for i = 1, #all_icons do
    local icon = all_icons[i]
    f:write("    const ", icon.name, " = gui.Bitmap.embed(system_assets.@\"", icon.file, "\").bitmap;\n")
  end
  f:write("};\n");
  f:write("\n")
  f:write("pub var interface = Interface{ .widgets = &widgets };\n")
  f:write("\n")
  f:write(string.format("pub var widgets: [%d]Widget = .{\n", #all_objects))

  for i = 1, #all_objects do
    local lobj = all_objects[i]
    f:write("    ", lobj.props.class_init, ", // ", tostring(i - 1), " ", lobj.name, "\n")
  end

  f:write("};\n")

  f:write("\n")
  for key, obj in pairs(named_objects) do

    f:write("pub const ", key, " = &widgets[", obj.number, "];\n")
  end

  f:write("\n")

  local delayed_property_assignments = {}

  local function flushInitializers()

    for i = 1, #delayed_property_assignments do
      local ass = delayed_property_assignments[i]

      -- print(ass.name, ass.value, ass.tag)

      local obj = ass.value.owner
      local int = obj.__internal
      local widget = ass.widget_name
      local var = ass.name

      f:write("    ");

      if ass.tag == "right" then

        if int.values.width or (int.defaults.width and not int.values.left) then
          -- compute x from width and right
          f:write(widget, ".x = ", var, " - @intCast(i16, ", widget, ".width)")
        else
          -- compute height from x and right
          f:write(widget, ".width = @intCast(u16, std.math.max(0, ", var, " - ", widget, ".x))")
        end

      elseif ass.tag == "bottom" then

        if int.values.height or (int.defaults.height and not int.values.top) then
          -- compute y from height and bottom
          f:write(widget, ".y = ", var, " - @intCast(i16, ", widget, ".height)")
        else
          -- compute height from top and bottom
          f:write(widget, ".height = @intCast(u16, std.math.max(0, ", var, " - ", widget, ".y))")
        end

      else
        assert(false)
      end

      f:write("; // ")
      f:write(tostring(ass.value))
      f:write("\n");

    end

    delayed_property_assignments = {}
  end

  local function renderInitializer(init)

    local function renderValueRef(value, assignment)

      local name_map = { left = "x", top = "y" }

      local widget = "widgets[" .. tostring(value.owner.number) .. "].bounds"

      if name_map[value.name] then
        f:write(widget, ".", name_map[value.name])
      elseif value.name == "width" or value.name == "height" then

        if assignment then
          f:write(widget, ".", value.name)
        else
          f:write("@intCast(i16, ", widget, ".", value.name, ")")
        end

      elseif value.name == "right" then
        local const_name = string.format("w%d_right", value.owner.number)
        if assignment then
          f:write("const ", const_name, ": i16")
          table.insert(
            delayed_property_assignments, { name = const_name, value = value, widget_name = widget, tag = "right" }
          )
        else
          f:write(const_name)
        end
      elseif value.name == "bottom" then
        local const_name = string.format("w%d_bottom", value.owner.number)
        if assignment then
          f:write("const ", const_name, ": i16")
          table.insert(
            delayed_property_assignments, { name = const_name, value = value, widget_name = widget, tag = "bottom" }
          )
        else
          f:write(const_name)
        end
      else
        assert(false, "not supported value: " .. value.name)
        -- print("MISSING MAPPING FOR", value.name)
      end
    end

    local function renderExpr(val)
      if isNumber(val) then
        f:write(string.format("%d", val))
      elseif isExpression(val) then

        local function renderSubExpr(expr)
          if isExpression(expr) then
            f:write("(")
            renderExpr(expr)
            f:write(")")
          else
            renderExpr(expr)
          end
        end

        if val.type == "binary" then
          if val.op == "/" then
            f:write("@divFloor(")
            renderSubExpr(val.lhs)
            f:write(", ")
            renderSubExpr(val.rhs)
            f:write(")")
          elseif val.op == "%" then
            f:write("@mod(")
            renderSubExpr(val.lhs)
            f:write(", ")
            renderSubExpr(val.rhs)
            f:write(")")
          else
            renderSubExpr(val.lhs)
            f:write(" ", val.op, " ")
            renderSubExpr(val.rhs)
          end
        elseif val.type == "unary" then
          f:write(val.op)
          renderSubExpr(val.value)
        else
          assert(false)
        end

      elseif isValue(val) then

        if val.owner == window then
          if val.name == "left" or val.name == "top" then
            f:write("0")
          elseif val.name == "right" then
            f:write("@intCast(i16,window.client_rectangle.width)")
          elseif val.name == "bottom" then
            f:write("@intCast(i16,window.client_rectangle.height)")
          else
            assert(false)
          end
        else
          renderValueRef(val, false)
        end
      else
        assert(false)
      end
    end

    if init.value == nil then

      if init.property.owner ~= window then
        if init.property.name == "right" then
          f:write("    ")
          renderValueRef(init.property, true)
          f:write(" = ")
          renderExpr(init.property.owner.__internal.refs.left + init.property.owner.__internal.refs.width)
          f:write(";\n")
        elseif init.property.name == "bottom" then
          f:write("    ")
          renderValueRef(init.property, true)
          f:write(" = ")
          renderExpr(init.property.owner.__internal.refs.top + init.property.owner.__internal.refs.height)
          f:write(";\n")
        end
      end

      return
    end
    f:write("    ")

    renderValueRef(init.property, true)

    f:write(" = ")

    renderExpr(init.value)

    f:write("; // ")
    f:write(tostring(init.value))
    f:write("\n");

  end

  -- print("constant resolvers:")

  -- f:write("pub fn init() void {\n")
  -- for i = 1, #resolution_order do
  --   local val = resolution_order[i].value
  --   if isNumber(val) or val == window.left or val == window.top then
  --     -- print(i, resolution_order[i].property, resolution_order[i].value)
  --     renderInitializer(resolution_order[i])
  --   end
  -- end
  -- flushInitializers()

  -- f:write("}\n")

  f:write("\n")

  f:write("pub fn layout(window: *const Window) void {\n")

  -- print("runtime resolvers:")
  for i = 1, #resolution_order do
    -- if not isNumber(resolution_order[i].value) and val ~= window.left and val ~= window.top then
    -- print(i, resolution_order[i].property, resolution_order[i].value)
    renderInitializer(resolution_order[i])
    -- end
  end
  flushInitializers()

  f:write("}\n")

  if out_file_name then
    f:close()
  end

end

-- io.stderr:write("done.\n")
