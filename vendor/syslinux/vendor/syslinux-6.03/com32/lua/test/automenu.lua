--[[
Automatically generated boot menu of the installed Linux kernels

Example:

m = require "automenu"
m.run { dir = "/",
        default = 1,
        timeout = 5,
        append = "root=/dev/hda2 ro",
}

TODO:
- add hooks
- demo adding break options from user config
- kernel flavor preference (pae/rt)
]]

local lfs = require "lfs"
local sl = require "syslinux"

local single = false
local verbosity = 2

local function modifiers ()
   return (single and " single" or "") .. ({" quiet",""," debug"})[verbosity]
end

local function scan (params)
   local sep = string.sub (params.dir, -1) == "/" and "" or "/"
   if not params.items then params.items = {} end
   for name in lfs.dir (params.dir) do
      local path = params.dir .. sep .. name
      if lfs.attributes (path, "mode") == "file" then
         local from,to,version = string.find (name, "^vmlinuz%-(.*)")
         if from then
            local initrd = params.dir .. sep .. "initrd.img-" .. version
            local initrd_param = ""
            if lfs.attributes (initrd, "size") then
               initrd_param = "initrd=" .. initrd .. " "
            end
            table.insert (params.items, {
                             show = function () return name end,
                             version = version,
                             execute = function () sl.boot_linux (path, initrd_param .. params.append .. modifiers ()) end
                          })
         end
      end
   end
end

local function version_gt (v1, v2)
   local negatives = {"rc", "pre"}
   local m1, r1 = string.match (v1, "^(%D*)(.*)")
   local m2, r2 = string.match (v2, "^(%D*)(.*)")
   if m1 ~= m2 then
      for _, suffix in ipairs (negatives) do
         suffix = "-" .. suffix
         if m1 == suffix and m2 ~= suffix then
            return false
         elseif m1 ~= suffix and m2 == suffix then
            return true
         end
      end
      return m1 > m2
   end
   m1, r1 = string.match (r1, "^(%d*)(.*)")
   m2, r2 = string.match (r2, "^(%d*)(.*)")
   m1 = tonumber (m1) or 0
   m2 = tonumber (m2) or 0
   if m1 ~= m2 then
      return m1 > m2
   end
   if r1 == "" and r2 == "" then
      return false
   end
   return version_gt (r1, r2)
end

local function kernel_gt (k1, k2)
   return version_gt (k1.version, k2.version)
end

local function print_or_call (x, def)
   local t = type (x)
   if t == "nil" then
      if def then print (def) end
   elseif t == "function" then
      x ()
   else
      print (x)
   end
end

local function draw (params)
   print_or_call (params.title, "\n=== Boot menu ===")
   for i, item in ipairs (params.items) do
      print ((i == params.default and " > " or "   ") .. i .. "  " .. item.show ())
   end
   print ("\nKernel arguments:\n  " .. params.append .. modifiers ())
   print ("\nHit a number to select from the menu,\n    ENTER to accept default,\n    ESC to exit\n or any other key to print menu again")
end

local function choose (params)
   draw (params)
   print ("\nBooting in " .. params.timeout .. " s...")
   while true do
      local i = sl.get_key (params.timeout * 1000)
      if i == sl.KEY.ESC then
         break
      else
         if i == sl.KEY.NONE or i == sl.KEY.ENTER then
            i = params.default
         elseif i == sl.KEY.DOWN then
            params.default = params.default < #params.items and params.default + 1 or #params.items
         elseif i == sl.KEY.UP then
            params.default = params.default > 1 and params.default - 1 or 1
         else
            i = i - string.byte "0"
         end
         if params.items[i] then
            params.items[i].execute ()
         end
         params.timeout = 0
         draw (params)
      end
   end
end

local function run (params)
   scan (params)
   if not next (params.items) then
      print ("No kernels found in directory " .. params.dir)
      os.exit (false)
   end
   table.sort (params.items, kernel_gt)
   table.insert (params.items, {
                    show = function () return "Single user: " .. (single and "true" or "false") end,
                    execute = function () single = not single end
                 })
   table.insert (params.items, {
                    show = function () return "Verbosity: " .. ({"quiet","normal","debug"})[verbosity] end,
                    execute = function () verbosity = verbosity < 3 and verbosity + 1 or 1 end
                 })
   choose (params)
end

return {
   scan = scan,
   choose = choose,
   run = run
}
